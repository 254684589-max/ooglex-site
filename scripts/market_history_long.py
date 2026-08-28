#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""长周期月线历史的共享构建器。

日线那份（market_history.py）滚动保留约一年，用来画近端走势；这一份保留每个标的
**全部可得的月线收盘**，用来画 5 年 / 10 年 / 25 年 / 全部。两份各司其职，互不覆盖。

规则与日线那份一致，只是把「共享日期轴 + 滚动截断」换成「每标的自己的起始月 + 不截断」：
- 每个标的存 start（起始月）与 closes（按月连续排列），缺哪个月就在对应位置留 null，
  不做前向填充，也不把相邻月的价格挪过来充数；
- 本轮没取到的标的沿用上次序列，不丢历史、也不补造新点；
- 全部标的都没取到时返回 None，调用方保留上次文件而不是写入空数据。
"""

DEFAULT_ROUND = 4


def month_index(month):
    """把 YYYY-MM 折成一个可直接相减的整数月序号。"""
    text = str(month or "")
    if len(text) < 7 or text[4] != "-":
        raise ValueError(f"月份格式不合法：{month}")
    year = int(text[:4])
    mon = int(text[5:7])
    if not 1 <= mon <= 12:
        raise ValueError(f"月份取值不合法：{month}")
    return year * 12 + (mon - 1)


def month_label(index):
    year, mon = divmod(int(index), 12)
    return f"{year:04d}-{mon + 1:02d}"


def to_columns(points):
    """[(YYYY-MM, close), ...] → (start, closes)；缺月留 null，重复月取最后一个。"""
    pairs = {}
    for month, value in points or []:
        if value is None:
            continue
        try:
            number = float(value)
        except (TypeError, ValueError):
            continue
        if number != number:
            continue
        pairs[month_index(month)] = number
    if not pairs:
        return None, []
    first, last = min(pairs), max(pairs)
    closes = [pairs.get(index) for index in range(first, last + 1)]
    return month_label(first), [None if v is None else round(v, DEFAULT_ROUND) for v in closes]


def build_long_history(collected, prev_history, updated_at, source, note):
    """把本轮抓到的月线合成长周期历史。

    collected: {symbol: [(YYYY-MM, close), ...]}，仅含本轮真实取到的序列。
    返回 (history, retained)：history 为 None 表示本轮一个序列都没有。
    """
    prev_series = (prev_history or {}).get("series") or {}
    series = {}
    for symbol, points in (collected or {}).items():
        start, closes = to_columns(points)
        if start and len(closes) >= 2:
            series[symbol] = {"start": start, "closes": closes}
    retained = []
    for symbol, entry in prev_series.items():
        if symbol in series or not isinstance(entry, dict):
            continue
        closes = entry.get("closes")
        if isinstance(entry.get("start"), str) and isinstance(closes, list) and len(closes) >= 2:
            series[symbol] = {"start": entry["start"], "closes": closes}
            retained.append(symbol)
    if not series:
        return None, retained
    ends = []
    for entry in series.values():
        ends.append(month_index(entry["start"]) + len(entry["closes"]) - 1)
    return {
        "updatedAt": updated_at,
        "asOf": month_label(max(ends)),
        "source": source,
        "frequency": "monthly",
        "status": "ok",
        "interval": "1mo",
        "symbols": len(series),
        "note": note,
        "series": {symbol: series[symbol] for symbol in sorted(series)},
    }, sorted(retained)


def monthly_from_daily(points):
    """把日线 [(YYYY-MM-DD, close), ...] 折成每月最后一个有效收盘。"""
    monthly = {}
    for date, value in points or []:
        text = str(date or "")
        if len(text) < 7 or value is None:
            continue
        monthly[text[:7]] = value
    return sorted(monthly.items())
