#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""标普500成分股的盘中快照：写 apps/companies/intraday.json。

热力图与气泡图要在美股开盘后跟着动，就需要一份比日更收盘价更新的读数。这一层与
日更快照分开存放、互不覆盖：

- `sp500.json` / `data.json` 仍是收盘口径，所有既有契约、历史与排行都读它们；
- `intraday.json` 只带最新价、相对前收的涨跌与各标的自己的报价时点，页面在它确实
  比日更快照更新时才覆盖显示，并把「这是盘中读数、不是实时」写在页面上。

**为什么是逐标的取、为什么是30分钟一轮。** 2026-08-29 在 Actions 机房实测过全部
批量接口，一个都不通：v8 spark 四组参数在两个宿主上都是 400，v7 quote 现在要 crumb
返回 401，Stooq 的批量 CSV 是 404。也就是说没有「一次问五百个」这条路，只能沿用
日更管道一直在用的 v8 图表接口逐个取。一轮就是清单条数那么多次请求，因此：

- 只在**美股交易时段**跑（工作流 cron 限定），不整天空转；
- 逐标的之间留间隔，并在两个宿主之间轮换，把单个宿主的压力减半；
- 周期定在30分钟而不是更短——与其把取数源打到限流、连带拖垮日更那条主管道，
  不如把「盘中」这两个字说得准一点。

诚实边界（页面与文件里都写明）：
- **这不是实时行情。** 刷新周期约30分钟，交易所自身还有延迟（美股常见15分钟），
  本站不保证也不声称实时；
- 本轮取不到就保留上一份，不写空数据、不外推、不用日更值冒充盘中值；
- 只覆盖 sp500.json 里已经登记的成分股，不在这里引入任何新标的。
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

SP500_PATH = os.path.join("apps", "companies", "sp500.json")
OUT_PATH = os.path.join("apps", "companies", "intraday.json")

YF_HOSTS = ["query1.finance.yahoo.com", "query2.finance.yahoo.com"]
YF_HEADERS = {"User-Agent": ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                             "AppleWebKit/537.36 (KHTML, like Gecko) "
                             "Chrome/123.0 Safari/537.36")}
PAUSE_SECONDS = 0.12    # 逐标的之间的轻微限速
CADENCE_MINUTES = 30    # 与工作流 cron 一致，写进文件供页面如实展示
NOTE = ("盘中快照：标普500成分股的最新价与相对上一交易日收盘的涨跌，与收盘口径的 "
        "sp500.json 分开存放。刷新周期约%d分钟，且只在美股交易时段更新；交易所自身"
        "还有延迟（美股常见15分钟）。本站不保证也不声称实时。本轮未取到的标的沿用"
        "上一份，不写空数据、不外推。" % CADENCE_MINUTES)


def load_json(path):
    try:
        with open(path, encoding="utf-8") as handle:
            return json.load(handle)
    except Exception:
        return None


def universe():
    """标的清单只从日更的标普500快照里取：盘中层不引入任何新标的。"""
    data = load_json(SP500_PATH) or {}
    seen = []
    for row in data.get("members") or []:
        symbol = row.get("symbol")
        if isinstance(symbol, str) and symbol and symbol not in seen:
            seen.append(symbol)
    return seen


def latest_quote(symbol, host):
    """Yahoo v8 图表接口取盘中最新点：返回 (price, previous_close, epoch_seconds)。

    meta 里的 regularMarketPrice 与 chartPreviousClose 是数据源自己给的当期读数与
    前收，这里不由 K 线自行推算，避免和日更那条管道各算各的。
    """
    encoded = requests.utils.quote(symbol)
    url = (f"https://{host}/v8/finance/chart/{encoded}"
           "?range=1d&interval=5m&includePrePost=false")
    response = requests.get(url, headers=YF_HEADERS, timeout=12)
    response.raise_for_status()
    result = response.json()["chart"]["result"][0]
    meta = result.get("meta") or {}
    previous = meta.get("chartPreviousClose")
    if not isinstance(previous, (int, float)) or previous <= 0:
        previous = meta.get("previousClose")
    price = meta.get("regularMarketPrice")
    stamp = meta.get("regularMarketTime")
    if not isinstance(price, (int, float)):
        # meta 里没有当期价就退回该轮 K 线的最后一个有效收盘，并沿用它自己的时点
        closes = ((result.get("indicators") or {}).get("quote") or [{}])[0].get("close") or []
        stamps = result.get("timestamp") or []
        for value, moment in zip(reversed(closes), reversed(stamps)):
            if isinstance(value, (int, float)):
                price, stamp = float(value), moment
                break
    if not isinstance(price, (int, float)) or price <= 0:
        raise ValueError("无当期报价")
    if not isinstance(previous, (int, float)) or previous <= 0:
        raise ValueError("无前收价，无法给出可复算的涨跌")
    return float(price), float(previous), stamp


def build():
    symbols = universe()
    if not symbols:
        print("标普500快照里没有可用成分股，保留上一份 intraday.json，不覆盖。")
        return
    previous = load_json(OUT_PATH) or {}
    previous_quotes = previous.get("quotes") if isinstance(previous.get("quotes"), dict) else {}

    quotes, failures = {}, []
    for index, symbol in enumerate(symbols):
        # 两个宿主轮换：五百次请求全压在一个域名上更容易触发限流。
        hosts = YF_HOSTS[index % len(YF_HOSTS):] + YF_HOSTS[:index % len(YF_HOSTS)]
        last_error = ValueError("无可用报价")
        for host in hosts:
            try:
                price, prev_close, stamp = latest_quote(symbol, host)
                quote = {
                    "price": round(price, 6),
                    "previousClose": round(prev_close, 6),
                    "changePct": round((price / prev_close - 1.0) * 100, 4),
                }
                if isinstance(stamp, (int, float)):
                    quote["asOf"] = datetime.fromtimestamp(stamp, timezone.utc) \
                        .strftime("%Y-%m-%dT%H:%M:%SZ")
                quotes[symbol] = quote
                last_error = None
                break
            except Exception as error:      # 单个宿主失败就换另一个
                last_error = error
        if last_error is not None:
            failures.append(f"{symbol}：{last_error}")
        time.sleep(PAUSE_SECONDS)

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
    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    with open(OUT_PATH, "w", encoding="utf-8") as handle:
        json.dump(document, handle, ensure_ascii=False, separators=(",", ":"))
    print("写入 %s：%d/%d 家本轮取到，%d 家沿用上一份，报价时点 %s → %s"
          % (OUT_PATH, document["fresh"], len(symbols), len(retained),
             document["asOfEarliest"] or "—", document["asOfLatest"] or "—"))
    if failures:
        print("部分标的失败：%s" % "; ".join(failures[:4]))


if __name__ == "__main__":
    build()
