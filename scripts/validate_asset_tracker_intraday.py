#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""盘中快照的离线契约（跨资产与标普500成分股两层共用）。

盘中层唯一的职责是：给日更快照里已登记的标的，补一份更新的最新价与相对前收涨跌。
因此这里守三件事：
1. 不越界——只出现日更清单里的标的，不引入任何新标的；
2. 不冒充——文件必须自报 realtime=false、刷新周期与报价时点，页面才能如实标注；
3. 不造数——每条报价的涨跌必须能由 price 与 previousClose 现场复算出来。

两条盘中管道守的是同一件事，因此共用同一份实现，只把「日更清单在哪、盘中文件在哪、
清单键叫什么」参数化——把同一段契约抄成两份，早晚会有一份漏改。
"""
import argparse
import json
import os
import sys
from datetime import datetime, timezone

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAX_AGE_HOURS = 6.0

DATASETS = {
    "asset-tracker": {
        "daily": os.path.join(ROOT, "apps", "asset-tracker", "data.json"),
        "intraday": os.path.join(ROOT, "apps", "asset-tracker", "intraday.json"),
        "rowsKey": "assets",
        "label": "Asset tracker",
    },
    "companies": {
        "daily": os.path.join(ROOT, "apps", "companies", "sp500.json"),
        "intraday": os.path.join(ROOT, "apps", "companies", "intraday.json"),
        "rowsKey": "members",
        "label": "S&P 500 companies",
    },
}


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def load(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def parse_moment(value):
    try:
        return datetime.strptime(str(value), "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    except (TypeError, ValueError):
        return None


def validate(name):
    spec = DATASETS[name]
    if not os.path.exists(spec["intraday"]):
        print(f"{name}: 盘中快照尚未生成，跳过（首次运行前属于正常状态）。")
        return
    daily = load(spec["daily"])
    snapshot = load(spec["intraday"])
    symbols = {row.get("symbol") for row in daily.get(spec["rowsKey"]) or []}

    require(snapshot.get("realtime") is False,
            "盘中快照必须自报 realtime=false：这不是实时行情，页面要按它来标注")
    require(snapshot.get("frequency") == "intraday", "盘中快照必须自报 frequency=intraday")
    require(isinstance(snapshot.get("cadenceMinutes"), int) and snapshot["cadenceMinutes"] > 0,
            "盘中快照必须自报刷新周期，页面据此说明延迟")
    require(snapshot.get("source"), "盘中快照必须写明来源")
    note = str(snapshot.get("note") or "")
    require("不保证" in note and "实时" in note and "延迟" in note,
            "盘中快照的说明必须写明不保证实时与存在延迟")
    require(snapshot.get("status") in ("ok", "partial"), "盘中快照状态只能是 ok 或 partial")

    updated = parse_moment(snapshot.get("updatedAt"))
    require(updated is not None, "盘中快照必须带 UTC 更新时间")

    quotes = snapshot.get("quotes")
    require(isinstance(quotes, dict) and quotes, "盘中快照必须至少带一条报价")
    require(snapshot.get("count") == len(quotes), "count 必须与实际报价条数一致")

    unknown = sorted(set(quotes) - symbols)
    require(not unknown, f"盘中快照出现了日更清单以外的标的：{unknown[:5]}")

    for symbol, quote in quotes.items():
        require(isinstance(quote.get("price"), (int, float)) and quote["price"] > 0,
                f"{symbol} 的盘中价缺失或非正")
        previous = quote.get("previousClose")
        require(isinstance(previous, (int, float)) and previous > 0,
                f"{symbol} 缺少可复算涨跌的前收价")
        expected = round((quote["price"] / previous - 1.0) * 100, 4)
        require(abs(expected - float(quote.get("changePct"))) <= 0.0002,
                f"{symbol} 的盘中涨跌无法由 price 与 previousClose 复算")
        if quote.get("asOf"):
            require(parse_moment(quote["asOf"]) is not None,
                    f"{symbol} 的报价时点格式必须是 UTC 时点")

    age_hours = (datetime.now(timezone.utc) - updated).total_seconds() / 3600.0
    stale = age_hours > MAX_AGE_HOURS
    print(f"{spec['label']} intraday snapshot contract: PASS")
    print(f"- {len(quotes)} quotes, all inside the daily universe ({len(symbols)} symbols)")
    print(f"- reproducible change from price/previousClose, realtime=false, cadence "
          f"{snapshot['cadenceMinutes']}min")
    print(f"- updated {age_hours:.2f}h ago"
          + ("（超过阈值，页面会按过期处理）" if stale else ""))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dataset", choices=[*DATASETS, "all"], default="asset-tracker")
    args = parser.parse_args()
    for name in (list(DATASETS) if args.dataset == "all" else [args.dataset]):
        validate(name)


if __name__ == "__main__":
    try:
        main()
    except AssertionError as error:
        print(f"FAIL: {error}", file=sys.stderr)
        sys.exit(1)
