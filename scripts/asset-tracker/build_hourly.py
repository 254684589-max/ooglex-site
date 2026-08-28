#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""构建 4 小时线：取 Yahoo 小时线，本地聚合成 4 小时桶，写 apps/asset-tracker/hourly.json。

诚实边界（文件里写明、页面上也逐条显示）：

- **这不是交易所原生的 4 小时 K 线**。Yahoo 对外只提供 1 小时粒度，4 小时桶由本站按
  UTC 对齐聚合而来（每桶取桶内最后一个收盘）。聚合是确定性运算，任何人拿同一份
  小时线都能复算出同一条曲线；但它与交易所自己划分的 4 小时周期不一定对齐，
  因此逐条标注 aggregated=true，页面也照实写出来。
- **只覆盖源头确实有小时级观测的标的**。FRED 的商品现货与官方指数（日频/月频）、
  美债收益率曲线在源头就没有小时数据，它们不在这份文件里，页面也不会给它们显示
  4 小时切换——给这些标的画 4 小时线只能靠插值，那是伪造。
- 各市场有自己的交易时段，桶按 UTC 对齐、缺口如实留空，不做连续化与前向填充。
- 加密的报价在站内来自 CoinGecko，而这份 4 小时线来自 Yahoo：**同一标的、两个来源**。
  逐条记下取数用的代码，页面在来源不同的时候会明确写出来。
- 本轮取不到的标的沿用上一份并标 stale，不写空数据、不外推；整轮全失败则保留上次文件。

标的清单只从站内已发布的快照里取，这一层不引入任何新标的。
由 .github/workflows/asset_tracker_hourly.yml 每 4 小时运行并提交回仓库。
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

TRACKER_PATH = os.path.join("apps", "asset-tracker", "data.json")
COMPANIES_PATH = os.path.join("apps", "companies", "data.json")
CRYPTO_PATH = os.path.join("apps", "asset-ranking", "crypto.json")
OUT_PATH = os.path.join("apps", "asset-tracker", "hourly.json")

BUCKET_SECONDS = 4 * 3600      # 4 小时桶，按 UTC 对齐
# 只保留最近 35 天：页面最长一档区间是「1个月」，多留几天是给休市与取数抖动的余量。
# 保留窗口按时间而不是按桶数——各市场每天成桶数不同（加密 6 个、美股约 2 个），
# 按桶数裁会让「1个月」在不同市场对应完全不同的真实跨度。
RETAIN_DAYS = 35
RETAIN_SECONDS = RETAIN_DAYS * 86400
COMPANY_LIMIT = 40             # 与公司榜在行情板上的常驻行数量级一致
CADENCE_HOURS = 4

YF_HOSTS = ["query1.finance.yahoo.com", "query2.finance.yahoo.com"]
YF_HEADERS = {"User-Agent": ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                             "AppleWebKit/537.36 (KHTML, like Gecko) "
                             "Chrome/123.0 Safari/537.36")}
PAUSE_SECONDS = 0.2
SOURCE_NAME = "Yahoo Finance"

NOTE = ("4 小时线：取自 Yahoo Finance 的 1 小时行情，按 UTC 对齐聚合成 4 小时桶"
        "（每桶取桶内最后一个收盘）。这不是交易所原生的 4 小时 K 线，聚合由本站完成，"
        "与交易所自己划分的 4 小时周期不一定对齐。各市场休市时段的缺口如实留空，"
        "不插值、不前向填充。刷新周期约 %d 小时，不是实时行情。" % CADENCE_HOURS)


def load_json(path):
    try:
        with open(path, encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return None


def universe():
    """标的清单只从站内已发布的快照里取：这一层不引入任何新标的。

    返回 [(站内序列键, Yahoo 取数代码, 来源类别)]。加密在站内以 BTC 这样的短代码
    登记、报价来自 CoinGecko，而小时线要向 Yahoo 要 BTC-USD，因此这里显式映射，
    两个代码都写进文件，供人核对也供页面披露来源差异。
    """
    picked = []
    tracker = load_json(TRACKER_PATH) or {}
    for asset in tracker.get("assets") or []:
        symbol = asset.get("symbol")
        if isinstance(symbol, str) and symbol:
            picked.append((symbol, symbol, "tracker"))

    companies = load_json(COMPANIES_PATH) or {}
    listed = [row for row in (companies.get("companies") or [])
              if isinstance(row, dict) and (row.get("dataMeta") or {}).get("mode") == "market"
              and isinstance(row.get("price"), (int, float))]
    for row in listed[:COMPANY_LIMIT]:
        symbol = row.get("symbol")
        if isinstance(symbol, str) and symbol:
            picked.append((symbol, symbol, "company"))

    crypto = load_json(CRYPTO_PATH) or {}
    for row in crypto.get("assets") or []:
        symbol = row.get("symbol")
        if isinstance(symbol, str) and symbol:
            picked.append((symbol, f"{symbol}-USD", "crypto"))

    seen, unique = set(), []
    for key, source, kind in picked:
        if key in seen:
            continue
        seen.add(key)
        unique.append((key, source, kind))
    return unique


def fetch_hourly(symbol):
    """Yahoo 小时线：返回按时间升序的 [(unix秒, 收盘价), ...]。取不到就抛异常。

    只取 60 天——保留窗口是 35 天，多取一倍足够覆盖长假与取数抖动，
    再长只是徒增响应体积和被限流的概率。
    """
    quoted = requests.utils.quote(symbol)
    last_error = ValueError("无可用小时线")
    for host in YF_HOSTS:
        url = f"https://{host}/v8/finance/chart/{quoted}?range=60d&interval=1h"
        try:
            response = requests.get(url, headers=YF_HEADERS, timeout=15)
            response.raise_for_status()
            result = response.json()["chart"]["result"][0]
            stamps = result.get("timestamp") or []
            closes = result["indicators"]["quote"][0]["close"]
            bars = [(int(t), float(c)) for t, c in zip(stamps, closes)
                    if isinstance(c, (int, float))]
            if len(bars) < 8:
                raise ValueError(f"小时线数据点不足（{len(bars)}）")
            return sorted(bars)
        except Exception as error:          # noqa: BLE001 - 单个标的失败不影响其余
            last_error = error
    raise last_error


def to_four_hour(bars, floor_stamp):
    """把小时线聚合成 4 小时桶：桶按 UTC 对齐，每桶取桶内最后一个收盘。

    只做聚合，不做填充——某个桶内没有任何小时观测（休市）就没有这个桶，
    页面按真实时间轴作图，缺口如实呈现。早于保留窗口的桶直接丢弃。
    """
    buckets = {}
    for stamp, close in sorted(bars):
        bucket = stamp - (stamp % BUCKET_SECONDS)
        if bucket < floor_stamp:
            continue
        buckets[bucket] = close
    return sorted(buckets.items())


def quantize(value):
    """按量级取有效位：加密上十万、外汇小数点后四位，统一给 6 位小数只是白占字节。"""
    magnitude = abs(value)
    if magnitude >= 1000:
        return round(value, 2)
    if magnitude >= 1:
        return round(value, 4)
    return round(value, 6)


def previous_pairs(previous, key):
    """把上一份文件的「共享时间轴 + 逐标的列」还原成 (桶, 收盘) 对，供沿用。"""
    axis = previous.get("axis")
    values = (previous.get("series") or {}).get(key)
    if not isinstance(axis, list) or not isinstance(values, list):
        return []
    return [(int(stamp), float(value)) for stamp, value in zip(axis, values)
            if isinstance(stamp, int) and isinstance(value, (int, float))]


def build():
    previous = load_json(OUT_PATH) or {}
    now = datetime.now(timezone.utc)
    run_at = now.strftime("%Y-%m-%dT%H:%M:%SZ")
    floor_stamp = int(now.timestamp()) - RETAIN_SECONDS

    collected, meta, retained, failed = {}, {}, [], []
    for key, source, kind in universe():
        try:
            bars = to_four_hour(fetch_hourly(source), floor_stamp)
            if len(bars) < 2:
                raise ValueError("保留窗口内的桶数不足")
            collected[key] = bars
            meta[key] = {"source": source, "kind": kind, "aggregated": True,
                         "buckets": len(bars)}
            print(f"[OK] {key:<12} ← {source:<12} {len(bars):>4} 桶")
        except Exception as error:          # noqa: BLE001
            kept = [pair for pair in previous_pairs(previous, key) if pair[0] >= floor_stamp]
            if len(kept) >= 2:
                collected[key] = kept
                meta[key] = {"source": source, "kind": kind, "aggregated": True,
                             "buckets": len(kept), "stale": True}
                retained.append(key)
                print(f"[==] {key:<12} 本轮失败，沿用上一份：{str(error)[:40]}")
            else:
                failed.append(key)
                print(f"[XX] {key:<12} 取数失败，且没有可沿用的：{str(error)[:40]}")
        time.sleep(PAUSE_SECONDS)

    if not collected:
        print("\n本轮 0 个标的成功，保留上次的 hourly.json，不覆盖。")
        return

    # 共享时间轴：所有标的成桶时点的并集。逐标的各存一份自己的时间戳会让文件涨到兆级，
    # 而页面每次只读其中一条序列；共享轴是站内日线历史一直在用的同一套压缩。
    axis = sorted({stamp for bars in collected.values() for stamp, _ in bars})
    index = {stamp: position for position, stamp in enumerate(axis)}
    series = {}
    for key, bars in collected.items():
        column = [None] * len(axis)
        for stamp, close in bars:
            column[index[stamp]] = quantize(close)
        series[key] = column

    payload = {
        "updatedAt": run_at,
        "realtime": False,
        "frequency": "4h",
        "aggregatedFrom": "1h",
        "bucketSeconds": BUCKET_SECONDS,
        "cadenceHours": CADENCE_HOURS,
        "retainDays": RETAIN_DAYS,
        "source": SOURCE_NAME,
        "status": "partial" if (retained or failed) else "ok",
        "note": NOTE,
        "count": len(series),
        "buckets": len(axis),
        "retained": retained,
        "unavailable": failed,
        "meta": meta,
        "axis": axis,
        "series": series,
    }
    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    with open(OUT_PATH, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=False, separators=(",", ":"))
    size = os.path.getsize(OUT_PATH)
    print(f"\n写入 {OUT_PATH}：{len(series)} 个标的、{len(axis)} 个 4 小时桶，"
          f"沿用 {len(retained)}，缺 {len(failed)}，{size // 1024} KB")


if __name__ == "__main__":
    build()
