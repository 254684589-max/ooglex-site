#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Point-in-time 成分股：从「当前名单 + 带日期的增删记录」回溯重建历史成分。

**这是 V1 研究结论指出的唯一真正修复。**

V1 用「今日市值榜」当股票池回测过去，等于事先知道了哪些公司活下来并变大。
实测幸存者偏差暴露 t = 2.98——那是整个研究里唯一达到统计显著的发现，
而它证明的是回测不可信。详见 docs/ALPHA60_V1_FINDINGS.md。

回溯算法：
    某日 D 发生「X 被加入、Y 被移除」
    ⇒ D 当天及之后的成分含 X 不含 Y
    ⇒ D 之前的成分 = D 及之后的成分 − {X} + {Y}
从今天的名单出发，按日期倒序逐条撤销，就得到任意历史时点的成分。

**可靠性随回溯深度衰减，这一点必须如实报出。** 变更记录越早越不全，
缺失的变更会让重建的历史成分越来越偏。因此本模块输出 ``reliableFrom``
与逐年变更条数，让读者自己判断某个回测窗口能不能信——
而不是给出一个看起来精确的名单就完事。
"""

import bisect
import json
import os
from datetime import date, datetime

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_PATH = os.path.join(HERE, "pit_membership.json")

# 变更记录密度低于此值的年份，视为重建不可靠。S&P 500 每年约 20–25 次调整，
# 少于一半说明该年的记录明显不全。
MIN_CHANGES_PER_YEAR = 10


def _parse_date(value):
    if isinstance(value, date):
        return value
    for fmt in ("%Y-%m-%d", "%Y/%m/%d", "%B %d, %Y", "%b %d, %Y"):
        try:
            return datetime.strptime(str(value).strip(), fmt).date()
        except (ValueError, TypeError):
            continue
    return None


def normalize_ticker(symbol):
    """统一成 Yahoo 口径：BRK.B → BRK-B。空值与占位符返回 None。"""
    symbol = (symbol or "").strip().upper()
    if not symbol or symbol in ("—", "–", "-", "N/A", "NA"):
        return None
    symbol = symbol.replace(".", "-")
    if len(symbol) > 8 or not any(c.isalpha() for c in symbol):
        return None
    if not all(c.isascii() and (c.isalnum() or c == "-") for c in symbol):
        return None
    return symbol


def build_snapshots(current_tickers, current_date, changes):
    """回溯重建。返回按日期升序的 [(生效日, frozenset), ...]。

    ``changes``：[{"date": …, "added": …, "removed": …}, …]，顺序不限。
    同一天的多条变更会被合并成一次撤销。

    返回的每个快照表示「从该日起（含）到下一个快照日之前」的成分。
    """
    current = {t for t in (normalize_ticker(x) for x in current_tickers) if t}
    as_of = _parse_date(current_date) or date.today()

    by_date = {}
    for item in changes:
        when = _parse_date(item.get("date"))
        if when is None or when > as_of:
            continue                      # 未来日期或脏日期，丢弃
        added = normalize_ticker(item.get("added"))
        removed = normalize_ticker(item.get("removed"))
        if not added and not removed:
            continue
        bucket = by_date.setdefault(when, {"added": set(), "removed": set()})
        if added:
            bucket["added"].add(added)
        if removed:
            bucket["removed"].add(removed)

    # 从今天倒着走，逐日撤销。
    # 关键：撤销 D 日的变更后得到的成分，生效区间是**D 之前**，
    # 因此该快照的键必须是「再往前一个变更日」，不是 D 本身。
    # 用 D 当键会让整串快照错位一格。
    dates_desc = sorted(by_date, reverse=True)
    members = set(current)
    # 当前名单从最近一次变更日起生效；无任何变更时从最早时点起生效
    snapshots = [(dates_desc[0] if dates_desc else date.min, frozenset(current))]

    for i, when in enumerate(dates_desc):
        change = by_date[when]
        members -= change["added"]        # 当天加入的，之前不在
        members |= change["removed"]      # 当天移除的，之前还在
        starts_at = dates_desc[i + 1] if i + 1 < len(dates_desc) else date.min
        snapshots.append((starts_at, frozenset(members)))

    snapshots.sort(key=lambda pair: pair[0])
    return snapshots


def constituents_at(snapshots, when):
    """取某日的成分。``when`` 早于最早快照时返回最早那份，并应视为不可靠。"""
    target = _parse_date(when)
    if target is None or not snapshots:
        return frozenset()
    keys = [pair[0] for pair in snapshots]
    index = bisect.bisect_right(keys, target) - 1
    if index < 0:
        return snapshots[0][1]           # 早于记录范围，退回最早一份
    return snapshots[index][1]


def coverage_report(snapshots, changes):
    """重建可靠性报告。**这一节比名单本身更重要。**

    变更记录越早越不全，缺失的变更会让重建的历史成分越来越偏。
    这里按年统计记录条数，低于 ``MIN_CHANGES_PER_YEAR`` 的年份判为不可靠，
    并给出 ``reliableFrom``——早于该日期的回测结论不应采信。
    """
    per_year = {}
    for item in changes:
        when = _parse_date(item.get("date"))
        if when:
            per_year[when.year] = per_year.get(when.year, 0) + 1

    years = sorted(per_year)
    reliable_from = None
    # 从最近往回找，第一个记录不足的年份就是可靠边界
    for year in reversed(years):
        if per_year[year] < MIN_CHANGES_PER_YEAR:
            reliable_from = f"{year + 1}-01-01"
            break
    if reliable_from is None and years:
        reliable_from = f"{years[0]}-01-01"

    sizes = [len(members) for _, members in snapshots]
    change_dates = [d for d in (_parse_date(c.get("date")) for c in changes) if d]
    return {
        "snapshots": len(snapshots),
        "changes": len(changes),
        # 最早快照的键是 date.min（表示「记录之前」），报出来没意义；
        # 有意义的边界是最早的一条变更记录
        "earliestChange": min(change_dates).isoformat() if change_dates else None,
        "latestChange": max(change_dates).isoformat() if change_dates else None,
        "reliableFrom": reliable_from,
        "changesPerYear": {str(y): per_year[y] for y in years},
        "minChangesPerYear": MIN_CHANGES_PER_YEAR,
        "membershipSizeRange": [min(sizes), max(sizes)] if sizes else None,
        "note": ("变更记录越早越不全，重建的历史成分越往前越偏。"
                 f"每年少于 {MIN_CHANGES_PER_YEAR} 条记录的年份判为不可靠；"
                 "早于 reliableFrom 的回测结论不应采信。"),
    }


# ---------------------------------------------------------------------------
def save(path, current_tickers, current_date, changes, source, sectors=None):
    payload = {
        "source": source,
        "fetchedAt": datetime.now().strftime("%Y-%m-%dT%H:%M:%SZ"),
        "current": {"date": str(current_date), "tickers": sorted(
            {t for t in (normalize_ticker(x) for x in current_tickers) if t})},
        "changes": changes,
        "sectors": sectors or {},
    }
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)
    os.replace(tmp, path)
    return path


def load(path=DEFAULT_PATH):
    """读取并重建。返回 (snapshots, 行业映射, 元数据)；文件不存在返回 (None, {}, None)。"""
    try:
        with open(path, encoding="utf-8") as f:
            payload = json.load(f)
    except Exception:
        return None, {}, None

    current = payload.get("current") or {}
    changes = payload.get("changes") or []
    snapshots = build_snapshots(current.get("tickers") or [],
                                current.get("date"), changes)
    meta = {
        "source": payload.get("source"),
        "fetchedAt": payload.get("fetchedAt"),
        "pointInTime": True,
        **coverage_report(snapshots, changes),
    }
    return snapshots, payload.get("sectors") or {}, meta
