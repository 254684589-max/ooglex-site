#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""加密长周期月线的离线契约。

这份历史与加密板的现价来自两个不同的数据源：现价是 CoinGecko，月线是
Yahoo Finance 的现货交易对——因为 CoinGecko 免费档只回溯 365 天，
5年/10年/25年/全部四档在那边根本不存在。来源不同就必须守住三件事：

1. 不冒充——文件自报的来源必须是月线的真实来源，且说明里写明与现价不同源；
2. 不越界——只给加密板里已登记的币种补历史，不引入板上没有的标的；
3. 不张冠李戴——同名代码在 Yahoo 上可能是另一个资产，尾点价位必须与本站现价
   在同一量级，差出数倍的序列一律判为取错标的。

用法：
    python scripts/validate_crypto_long_history.py            # 校验仓库里的产物
    python scripts/validate_crypto_long_history.py --self-test  # 只跑取数逻辑自测
"""
import importlib.util
import json
import os
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BOARD_PATH = os.path.join(ROOT, "apps", "asset-ranking", "crypto.json")
LONG_PATH = os.path.join(ROOT, "apps", "asset-ranking", "crypto-history-monthly.json")
# 尾点与现价的量级校验：留出足够的行情波动余量（沿用的序列可能是若干天前取的），
# 只用来抓「取到了完全不同的资产」这类错误。
MAX_TAIL_FACTOR = 4.0


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def load(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def load_builder():
    """按路径加载加密板构建脚本，直接复用它的取数判定逻辑做自测。"""
    sys.path.insert(0, os.path.join(ROOT, "scripts"))
    sys.path.insert(0, os.path.join(ROOT, "scripts", "asset-ranking"))
    spec = importlib.util.spec_from_file_location(
        "build_ranking", os.path.join(ROOT, "scripts", "asset-ranking", "build_ranking.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def self_test():
    builder = load_builder()
    require(builder.crypto_yahoo_symbol("btc") == "BTC-USD", "币种代码应转成 Yahoo 现货交易对")
    require(builder.crypto_yahoo_symbol("") is None, "空代码不得拼出交易对")
    require(builder.crypto_yahoo_symbol("BTC-USD") is None, "含分隔符的代码不得再次拼接")

    points = [("2024-01", 100.0), ("2024-02", 110.0)]
    require(builder.plausible_monthly(points, 112.0) is True, "尾点与现价接近时应当采纳")
    require(builder.plausible_monthly(points, 3.5) is False, "尾点与现价差出数量级时必须丢弃")
    require(builder.plausible_monthly([], 100.0) is False, "空序列不得采纳")
    require(builder.plausible_monthly(points, None) is False, "现价缺失时无从核对，不得采纳")

    fetched = {"BTC-USD": [("2024-01", 100.0), ("2024-02", 110.0)],
               "FAKE-USD": [("2024-01", 1.0), ("2024-02", 2.0)]}
    calls = []

    def fake_fetch(symbol):
        calls.append(symbol)
        if symbol not in fetched:
            raise ValueError("无可用月线")
        return fetched[symbol]

    original = builder.fetch_monthly
    original_interval = builder.CRYPTO_LONG_INTERVAL
    original_path = builder.CRYPTO_LONG_HISTORY_PATH
    scratch = os.path.join(tempfile.gettempdir(), "crypto-long-history-selftest.json")
    builder.fetch_monthly = fake_fetch
    builder.CRYPTO_LONG_INTERVAL = 0
    builder.CRYPTO_LONG_HISTORY_PATH = scratch
    try:
        history = builder.build_crypto_long_history(
            [{"symbol": "BTC", "price": 111.0},      # 正常
             {"symbol": "FAKE", "price": 900.0},     # 同名但价位对不上 → 丢弃
             {"symbol": "NONE", "price": 5.0}],      # 数据源没有 → 跳过
            "2024-03-01T00:00:00Z")
        require(history is not None, "至少取到一条序列时应当写入历史")
        require(list(history["series"]) == ["BTC"], "只有通过核对的币种才进入历史")
        require(history["source"] == builder.CRYPTO_LONG_SOURCE, "历史必须自报月线的真实来源")
        require(calls == ["BTC-USD", "FAKE-USD", "NONE-USD"], "应逐币按交易对代码取数")
        written = load(scratch)
        require(written["series"]["BTC"]["start"] == "2024-01", "起始月应取该币可得的最早月份")
    finally:
        builder.fetch_monthly = original
        builder.CRYPTO_LONG_INTERVAL = original_interval
        builder.CRYPTO_LONG_HISTORY_PATH = original_path
        if os.path.exists(scratch):
            os.remove(scratch)
    print("加密长周期月线取数逻辑自测通过。")


def check_file():
    if not os.path.exists(LONG_PATH):
        print("加密长周期月线尚未生成，跳过（首次运行前属于正常状态）。")
        return
    board = load(BOARD_PATH)
    history = load(LONG_PATH)

    prices = {}
    for asset in board.get("assets") or []:
        symbol = str(asset.get("symbol") or "").upper()
        if symbol:
            prices[symbol] = asset.get("price")
    require(prices, "加密板缺少币种清单，无法核对长周期月线")

    source = str(history.get("source") or "")
    require(source, "长周期月线必须写明来源")
    require(source != board.get("source"),
            "长周期月线与现价不是同一来源，来源字段不得照抄现价那份")
    require(history.get("frequency") == "monthly", "长周期月线必须自报 frequency=monthly")
    require(history.get("interval") == "1mo", "长周期月线必须自报 interval=1mo")
    require(history.get("updatedAt"), "长周期月线必须带更新时间")
    note = str(history.get("note") or "")
    require(source in note and str(board.get("source") or "") in note and "不是同一来源" in note,
            "说明里必须点名两个来源并写清它们不是同一来源")
    require("不做前向填充" in note, "说明里必须写明缺月不做前向填充")

    series = history.get("series")
    require(isinstance(series, dict) and series, "长周期月线必须给出至少一条序列")
    require(history.get("symbols") == len(series), "symbols 必须与序列条数一致")

    for symbol, entry in series.items():
        require(symbol in prices, f"{symbol} 不在加密板清单里，长周期月线不得引入板外标的")
        start = entry.get("start")
        require(isinstance(start, str) and len(start) == 7 and start[4] == "-",
                f"{symbol} 的起始月格式必须是 YYYY-MM")
        closes = entry.get("closes")
        require(isinstance(closes, list) and len(closes) >= 2, f"{symbol} 的月线点数不足")
        values = [v for v in closes if v is not None]
        require(values, f"{symbol} 的月线全是空值")
        for value in values:
            require(isinstance(value, (int, float)) and value > 0,
                    f"{symbol} 的月线收盘必须是正数")
        spot = prices.get(symbol)
        if isinstance(spot, (int, float)) and spot > 0:
            tail = values[-1]
            require(tail / spot <= MAX_TAIL_FACTOR and spot / tail <= MAX_TAIL_FACTOR,
                    f"{symbol} 的月末价 {tail} 与站内现价 {spot} 差出数倍，疑似取错标的")

    print(f"加密长周期月线契约通过：{len(series)} 币，来源 {source}，"
          f"最新 {history.get('asOf')}，现价来源 {board.get('source')}。")


def main():
    if "--self-test" in sys.argv[1:]:
        self_test()
        return
    self_test()
    check_file()


if __name__ == "__main__":
    main()
