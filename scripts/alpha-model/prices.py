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
from datetime import date, datetime, timezone

import requests

from config import CACHE_TTL_HOURS, HTTP_TIMEOUT, YF_HEADERS, YF_HOSTS

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE_DIR = os.path.join(HERE, "cache")
MAX_FORWARD_FILL = 5     # 允许前向填补的最大连续缺口（假期、临时停牌）
MAX_DAILY_GAP_DAYS = 4   # 日线相邻 bar 的中位间隔上限（跨周末为 3 天）


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


def infer_interval(dates):
    """从日期序列反推 bar 的真实粒度，返回 (名称, 中位间隔天数)。

    **这个校验是必须的，不是保险。** Yahoo 在某些 range 下会**静默地**把
    interval=1d 降级成周线或月线——响应里没有任何字段说明这件事。
    拿到月线却当日线用，模型不会报错，只会安静地算出一整套废数：
    「60 个交易日前瞻」变成 60 个月前瞻，「12 个月动量」变成 19 年动量，
    而所有指标看上去都还是正常数字。这种错最难被发现。
    """
    if len(dates) < 3:
        return "unknown", None
    days = []
    for a, b in zip(dates, dates[1:]):
        try:
            ya, ma, da = (int(x) for x in a.split("-"))
            yb, mb, db = (int(x) for x in b.split("-"))
        except (ValueError, AttributeError):
            continue
        days.append((date(yb, mb, db) - date(ya, ma, da)).days)
    if not days:
        return "unknown", None
    days.sort()
    median = days[len(days) // 2]
    if median <= MAX_DAILY_GAP_DAYS:
        name = "1d"
    elif median <= 10:
        name = "1wk"
    elif median <= 45:
        name = "1mo"
    else:
        name = "coarser"
    return name, median


class NotDailyDataError(ValueError):
    """取回的不是日线。继续算下去会得到一整套看似正常的废数。"""


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
                  ttl_hours=CACHE_TTL_HOURS, require_daily=True):
    """取单只日线历史；失败返回 None，不返回空序列冒充成功。

    ``require_daily`` 为真（默认）时，若 Yahoo 静默降级了粒度则抛
    ``NotDailyDataError``——宁可整轮失败，也不能用月线冒充日线跑完全程。
    """
    if use_cache:
        cached = _read_cache(symbol, rng, ttl_hours)
        if cached:
            interval, gap = infer_interval(cached["dates"])
            if require_daily and interval != "1d":
                raise NotDailyDataError(
                    f"{symbol} 的缓存是 {interval} 数据（中位间隔 {gap} 天），"
                    f"请删除 {_cache_path(symbol, rng)} 后改用较短区间重取")
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
                interval, median_gap = infer_interval(series["dates"])
                if require_daily and interval != "1d":
                    raise NotDailyDataError(
                        f"{symbol} 在 range={rng} 下返回的是 {interval} 数据"
                        f"（相邻 bar 中位间隔 {median_gap} 天，日线应 ≤ "
                        f"{MAX_DAILY_GAP_DAYS} 天）。Yahoo 会静默降级粒度，"
                        f"把它当日线用会算出一整套看似正常的废数。请改用较短区间"
                        f"（如 --range 10y）。")
                series["interval"] = interval
                series["medianGapDays"] = median_gap
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
