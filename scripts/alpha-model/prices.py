#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""日线行情抓取、缓存与交易日历对齐。

沿用本仓库既有取数风格：纯 requests + 硬超时 + 主备双域名 + 逐项 try/except，
单只失败不影响整体。用 Yahoo v8/chart 的复权收盘价（adjclose），
它已包含分红与拆股调整，是算收益率的正确口径；用未复权价会把每次拆股
读成一次暴跌，直接污染动量与波动率因子。
"""

import json
import os
import time
from datetime import datetime, timezone

import requests

from config import CACHE_TTL_HOURS, HTTP_TIMEOUT, YF_HEADERS, YF_HOSTS

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE_DIR = os.path.join(HERE, "cache")
MAX_FORWARD_FILL = 5     # 允许前向填补的最大连续缺口（假期、临时停牌）


def new_session():
    session = requests.Session()
    session.headers.update(YF_HEADERS)
    return session


def _cache_path(symbol, rng):
    safe = symbol.replace("/", "_").replace("\\", "_")
    return os.path.join(CACHE_DIR, f"{safe}__{rng}.json")


def _read_cache(symbol, rng, ttl_hours):
    path = _cache_path(symbol, rng)
    try:
        with open(path, encoding="utf-8") as f:
            payload = json.load(f)
    except Exception:
        return None
    fetched = payload.get("fetchedAt", 0)
    if ttl_hours is not None and (time.time() - fetched) > ttl_hours * 3600:
        return None
    return payload.get("series")


def _write_cache(symbol, rng, series):
    os.makedirs(CACHE_DIR, exist_ok=True)
    path = _cache_path(symbol, rng)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump({"fetchedAt": time.time(), "symbol": symbol,
                   "range": rng, "series": series}, f)
    os.replace(tmp, path)


def _parse_chart(payload):
    """把 Yahoo 的 chart 响应解析成按日期升序的三列序列。"""
    result = ((payload.get("chart") or {}).get("result") or [None])[0]
    if not result:
        return None
    stamps = result.get("timestamp") or []
    indicators = result.get("indicators") or {}
    quote = (indicators.get("quote") or [{}])[0]
    adj = (indicators.get("adjclose") or [{}])[0]
    closes = adj.get("adjclose") or quote.get("close") or []
    volumes = quote.get("volume") or []
    if not stamps or len(closes) != len(stamps):
        return None

    rows = []
    for i, ts in enumerate(stamps):
        close = closes[i] if i < len(closes) else None
        volume = volumes[i] if i < len(volumes) else None
        if not isinstance(close, (int, float)) or close <= 0:
            continue
        date = datetime.fromtimestamp(ts, timezone.utc).strftime("%Y-%m-%d")
        rows.append((date, float(close),
                     float(volume) if isinstance(volume, (int, float)) else None))
    rows.sort(key=lambda r: r[0])

    # 同一天多条只保留最后一条（Yahoo 偶发盘中重复行）
    dedup = {}
    for date, close, volume in rows:
        dedup[date] = (close, volume)
    dates = sorted(dedup)
    return {
        "dates": dates,
        "closes": [dedup[d][0] for d in dates],
        "volumes": [dedup[d][1] for d in dates],
    }


def fetch_history(session, symbol, rng="5y", use_cache=True,
                  ttl_hours=CACHE_TTL_HOURS):
    """取单只日线历史；失败返回 None，不返回空序列冒充成功。"""
    if use_cache:
        cached = _read_cache(symbol, rng, ttl_hours)
        if cached:
            return cached

    quoted = requests.utils.quote(symbol)
    for host in YF_HOSTS:
        url = (f"https://{host}/v8/finance/chart/{quoted}"
               f"?range={rng}&interval=1d&events=div%2Csplit")
        try:
            response = session.get(url, timeout=HTTP_TIMEOUT)
            if response.status_code != 200:
                continue
            series = _parse_chart(response.json())
            if series and len(series["dates"]) > 20:
                if use_cache:
                    _write_cache(symbol, rng, series)
                return series
        except Exception:
            continue
    return None


def align_to_calendar(series, master_dates, max_fill=MAX_FORWARD_FILL):
    """把单只行情对齐到主交易日历，返回 (closes, volumes, 缺口天数)。

    收盘价允许前向填补至多 ``max_fill`` 个连续交易日（假期口径差异、临时停牌）；
    成交量不填补——价格是存量、成交量是流量，把上一天的成交量抄下来等于
    凭空造出没发生过的交易。填不上的位置留 None，让下游因子自己判定不可算。
    """
    lookup = dict(zip(series["dates"], zip(series["closes"], series["volumes"])))
    closes, volumes = [], []
    last_close, run = None, 0
    gaps = 0
    for date in master_dates:
        hit = lookup.get(date)
        if hit is not None:
            close, volume = hit
            closes.append(close)
            volumes.append(volume)
            last_close, run = close, 0
        else:
            gaps += 1
            run += 1
            closes.append(last_close if (last_close is not None and run <= max_fill) else None)
            volumes.append(None)
    return closes, volumes, gaps


def recent_gap_count(closes, t, window=20):
    """最近 window 个交易日里的缺失天数，用于剔除已停牌/退市标的。"""
    start = max(0, t - window + 1)
    return sum(1 for c in closes[start:t + 1] if c is None)
