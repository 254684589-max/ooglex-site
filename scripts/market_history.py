#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""滚动日线历史的共享构建器。

跨资产、公司榜与加密快照都要把「本轮取到的日线」并进一份共享日期轴的紧凑历史，
规则完全一致：本轮未取到的标的沿用上次序列（不丢历史、也不补造新点），共享日期轴
上没有该标的报价的位置写 null（不做前向填充），并滚动截断到最近 N 个交易日，
使文件大小恒定而不是逐日增长。

三条管道共用这一份实现，避免同一套历史规则出现第二份互相漂移的副本。
"""

DEFAULT_POINTS = 260   # 约一年交易日


def build_rolling_history(collected, prev_history, updated_at, source, note,
                          limit=DEFAULT_POINTS):
    """把本轮抓到的日线合成共享日期轴的紧凑历史。

    collected: {symbol: [(date, close), ...]}，仅含本轮真实取到的序列。
    prev_history: 上次的历史文件内容；缺失或损坏时传 {}。
    返回 (history, retained)：history 为 None 表示本轮没有任何有效序列，
    调用方应保留上次文件而不是写入空数据；retained 为沿用上次序列的标的。
    """
    prev_series = (prev_history or {}).get("series") or {}
    prev_dates = (prev_history or {}).get("dates") or []

    merged = {}
    for symbol, points in (collected or {}).items():
        pairs = [(str(d), float(v)) for d, v in points
                 if d and isinstance(v, (int, float)) and v == v]
        if pairs:
            merged[symbol] = dict(pairs)
    retained = []
    for symbol, values in prev_series.items():
        if symbol in merged or not isinstance(values, list):
            continue
        pairs = [(d, v) for d, v in zip(prev_dates, values) if isinstance(v, (int, float))]
        if pairs:
            merged[symbol] = dict(pairs)
            retained.append(symbol)

    dates = sorted({d for values in merged.values() for d in values})[-limit:]
    if not dates:
        return None, retained
    series = {}
    for symbol in sorted(merged):
        column = [merged[symbol].get(d) for d in dates]
        if any(value is not None for value in column):
            series[symbol] = [None if v is None else round(v, 4) for v in column]
    if not series:
        return None, retained
    return {
        "updatedAt": updated_at,
        "asOf": dates[-1],
        "source": source,
        "frequency": "daily",
        "status": "ok",
        "points": len(dates),
        "note": note,
        "dates": dates,
        "series": series,
    }, retained
