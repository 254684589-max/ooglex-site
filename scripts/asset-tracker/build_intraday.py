#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""盘中快照：给跨资产清单里的标的取一份「最新价 + 相对前收涨跌」的轻量文件。

和日更快照分成两层，互不覆盖：
- data.json 仍是收盘口径的当日快照，所有既有契约、历史与排行都读它；
- intraday.json 只带最新价、相对前收的涨跌与各标的自己的报价时点，页面在它比
  日更快照更新时覆盖显示，并明确标注这是盘中读数。

诚实边界（页面与文件里都写明）：
- 这不是实时行情。刷新周期由工作流决定（默认约15分钟一轮），各交易所本身还有
  自己的延迟（股票常见15分钟，指数/外汇/加密通常更快），本站不保证也不声称实时；
- 本轮取不到就保留上一份，不写空数据、不外推、不用日更值冒充盘中值；
- 只覆盖 data.json 里已经登记的标的，不在这里引入任何新标的。
"""
import json
import os
import sys
import time
from datetime import datetime, timezone

import requests

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPTS_DIR = os.path.dirname(HERE)
sys.path.insert(0, SCRIPTS_DIR)

DATA_PATH = os.path.join("apps", "asset-tracker", "data.json")
OUT_PATH = os.path.join("apps", "asset-tracker", "intraday.json")

YF_HOSTS = ["query1.finance.yahoo.com", "query2.finance.yahoo.com"]
YF_HEADERS = {"User-Agent": ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                             "AppleWebKit/537.36 (KHTML, like Gecko) "
                             "Chrome/123.0 Safari/537.36")}
CHUNK = 25              # 一次请求带多少个代码；spark 接口支持批量，避免每标的一请求
CADENCE_MINUTES = 15    # 与工作流 cron 一致，写进文件供页面如实展示
NOTE = ("盘中快照：最新价与相对上一交易日收盘的涨跌，与收盘口径的 data.json 分开存放。"
        "刷新周期约%d分钟，各交易所自身还有延迟（股票常见15分钟，指数/外汇/加密通常更快），"
        "本站不保证也不声称实时。本轮未取到的标的沿用上一份，不写空数据、不外推。" % CADENCE_MINUTES)


def load_json(path):
    try:
        with open(path, encoding="utf-8") as handle:
            return json.load(handle)
    except Exception:
        return None


def universe():
    """标的清单只从日更快照里取：盘中层不引入任何新标的。"""
    data = load_json(DATA_PATH) or {}
    seen = []
    for asset in data.get("assets") or []:
        symbol = asset.get("symbol")
        if isinstance(symbol, str) and symbol and symbol not in seen:
            seen.append(symbol)
    return seen


def spark(symbols):
    """Yahoo spark 批量接口：返回 {symbol: (price, previous_close, epoch_seconds)}。"""
    joined = ",".join(requests.utils.quote(symbol) for symbol in symbols)
    last_error = ValueError("无可用报价")
    for host in YF_HOSTS:
        url = (f"https://{host}/v7/finance/spark?symbols={joined}"
               "&range=1d&interval=5m")
        try:
            response = requests.get(url, headers=YF_HEADERS, timeout=15)
            response.raise_for_status()
            payload = response.json()
            out = {}
            for symbol, entry in (payload or {}).items():
                if not isinstance(entry, dict):
                    continue
                closes = entry.get("close") or []
                stamps = entry.get("timestamp") or []
                previous = entry.get("chartPreviousClose")
                if previous is None:
                    previous = entry.get("previousClose")
                price = None
                stamp = None
                for value, moment in zip(reversed(closes), reversed(stamps)):
                    if isinstance(value, (int, float)):
                        price = float(value)
                        stamp = moment
                        break
                if price is None or not isinstance(previous, (int, float)) or previous <= 0:
                    continue
                out[symbol] = (price, float(previous), stamp)
            if out:
                return out
        except Exception as error:  # 单个宿主失败就换另一个，两个都失败再上报
            last_error = error
    raise last_error


def build():
    symbols = universe()
    if not symbols:
        print("日更快照里没有可用标的，保留上一份 intraday.json，不覆盖。")
        return
    previous = load_json(OUT_PATH) or {}
    previous_quotes = previous.get("quotes") if isinstance(previous.get("quotes"), dict) else {}

    quotes = {}
    failures = []
    for index in range(0, len(symbols), CHUNK):
        batch = symbols[index:index + CHUNK]
        try:
            for symbol, (price, prev_close, stamp) in spark(batch).items():
                if symbol not in symbols:
                    continue           # 只收清单内的标的，接口回什么都不额外采纳
                quote = {
                    "price": round(price, 6),
                    "previousClose": round(prev_close, 6),
                    "changePct": round((price / prev_close - 1.0) * 100, 4),
                }
                if isinstance(stamp, (int, float)):
                    quote["asOf"] = datetime.fromtimestamp(stamp, timezone.utc) \
                        .strftime("%Y-%m-%dT%H:%M:%SZ")
                quotes[symbol] = quote
        except Exception as error:
            failures.append(f"{batch[0]}…{batch[-1]}：{error}")
        time.sleep(0.4)

    if not quotes:
        print("本轮一个盘中报价都没取到，保留上一份 %s，不覆盖。" % OUT_PATH)
        if failures:
            print("失败：%s" % "; ".join(failures[:4]))
        return

    retained = []
    for symbol, quote in previous_quotes.items():
        if symbol in quotes or symbol not in symbols:
            continue
        if isinstance(quote, dict) and isinstance(quote.get("price"), (int, float)):
            quotes[symbol] = quote
            retained.append(symbol)

    stamps = sorted(quote.get("asOf") for quote in quotes.values() if quote.get("asOf"))
    document = {
        "updatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "source": "Yahoo Finance",
        "frequency": "intraday",
        "cadenceMinutes": CADENCE_MINUTES,
        "realtime": False,
        "status": "ok" if not failures and not retained else "partial",
        "count": len(quotes),
        "fresh": len(quotes) - len(retained),
        "retained": len(retained),
        "asOfEarliest": stamps[0] if stamps else "",
        "asOfLatest": stamps[-1] if stamps else "",
        "note": NOTE,
        "quotes": {symbol: quotes[symbol] for symbol in sorted(quotes)},
    }
    with open(OUT_PATH, "w", encoding="utf-8") as handle:
        json.dump(document, handle, ensure_ascii=False, separators=(",", ":"))
    print("写入 %s：%d/%d 个标的本轮取到，%d 个沿用上一份，报价时点 %s → %s"
          % (OUT_PATH, document["fresh"], len(symbols), len(retained),
             document["asOfEarliest"] or "—", document["asOfLatest"] or "—"))
    if failures:
        print("部分批次失败：%s" % "; ".join(failures[:4]))


if __name__ == "__main__":
    build()
