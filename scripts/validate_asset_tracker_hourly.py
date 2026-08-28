#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""4 小时线的离线契约。

这一层唯一的职责是：给站内已发布快照里已有的标的，补一条由小时线聚合出来的
4 小时序列。因此这里守四件事：

1. 不越界——只出现三份已发布快照里已有的标的，不在这一层引入任何新标的；
2. 不冒充——文件必须自报 realtime=false、聚合来源与桶长，并写明这不是交易所原生
   的 4 小时 K 线，页面才能如实标注；
3. 不造数——每个桶都必须对齐到桶长、落在保留窗口内、且不越到未来；缺观测的位置
   留 null 而不是填充；
4. 不留空壳——写进文件的每条序列都至少有两个真实观测，取不到的标的进 unavailable
   而不是留一条画不出来的空线。
"""
import json
import os
import sys
from datetime import datetime, timezone

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TRACKER_PATH = os.path.join(ROOT, "apps", "asset-tracker", "data.json")
COMPANIES_PATH = os.path.join(ROOT, "apps", "companies", "data.json")
CRYPTO_PATH = os.path.join(ROOT, "apps", "asset-ranking", "crypto.json")
HOURLY_PATH = os.path.join(ROOT, "apps", "asset-tracker", "hourly.json")
MAX_AGE_HOURS = 12.0        # 约两个刷新周期；超过页面按过期处理
FUTURE_SLACK = 4 * 3600     # 允许最后一个桶是当前这一桶（桶起点在过去、桶本身未走完）


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def load(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def published_symbols():
    """三份已发布快照里的全部标的代码：4 小时线的清单不得超出这个并集。"""
    symbols = set()
    tracker = load(TRACKER_PATH)
    symbols.update(str(a.get("symbol")) for a in tracker.get("assets") or [] if a.get("symbol"))
    companies = load(COMPANIES_PATH)
    symbols.update(str(c.get("symbol")) for c in companies.get("companies") or [] if c.get("symbol"))
    crypto = load(CRYPTO_PATH)
    symbols.update(str(k.get("symbol")) for k in crypto.get("assets") or [] if k.get("symbol"))
    return symbols


def parse_moment(value):
    try:
        return datetime.strptime(str(value), "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    except (TypeError, ValueError):
        return None


def main():
    if not os.path.exists(HOURLY_PATH):
        print("4 小时线尚未生成，跳过（首次运行前属于正常状态）。")
        return
    snapshot = load(HOURLY_PATH)
    known = published_symbols()

    # 1. 自报口径：页面上的每一句话都要能在文件里找到依据
    require(snapshot.get("realtime") is False,
            "4 小时线必须自报 realtime=false：这不是实时行情，页面要按它来标注")
    require(snapshot.get("frequency") == "4h", "4 小时线必须自报 frequency=4h")
    require(snapshot.get("aggregatedFrom") == "1h",
            "4 小时线必须自报聚合来源：它是由 1 小时线聚合而来，不是原生 4 小时 K 线")
    bucket = snapshot.get("bucketSeconds")
    require(bucket == 4 * 3600, "4 小时线必须写明桶长，且桶长就是 4 小时")
    require(isinstance(snapshot.get("cadenceHours"), int) and snapshot["cadenceHours"] > 0,
            "4 小时线必须自报刷新周期，页面据此说明延迟")
    retain_days = snapshot.get("retainDays")
    require(isinstance(retain_days, int) and retain_days > 0, "4 小时线必须自报保留窗口")
    require(snapshot.get("source"), "4 小时线必须写明来源")
    note = str(snapshot.get("note") or "")
    require("不是交易所原生" in note and "不是实时行情" in note and "不插值" in note,
            "说明必须写明：非交易所原生 4 小时 K 线、非实时、不插值")
    require(snapshot.get("status") in ("ok", "partial"), "4 小时线状态只能是 ok 或 partial")
    updated = parse_moment(snapshot.get("updatedAt"))
    require(updated is not None, "4 小时线必须带 UTC 更新时间")

    # 2. 共享时间轴：对齐、升序、去重、不越到未来、不早于保留窗口
    axis = snapshot.get("axis")
    require(isinstance(axis, list) and len(axis) >= 2, "4 小时线必须至少有两个桶")
    require(all(isinstance(stamp, int) for stamp in axis), "时间轴必须是整型 UNIX 秒")
    require(axis == sorted(set(axis)), "时间轴必须严格升序且不重复")
    require(all(stamp % bucket == 0 for stamp in axis), "每个桶都必须对齐到 4 小时边界")
    now = int(datetime.now(timezone.utc).timestamp())
    require(axis[-1] <= now + FUTURE_SLACK, "时间轴不得越到未来：那不是观测，是编造")
    floor_stamp = now - retain_days * 86400 - 86400
    require(axis[0] >= floor_stamp,
            f"时间轴越出了自报的 {retain_days} 天保留窗口，文件会越滚越大")
    require(snapshot.get("buckets") == len(axis), "buckets 必须与时间轴长度一致")

    # 3. 逐条序列：不越界、列长对齐、至少两个真实观测、数值为正
    series = snapshot.get("series")
    require(isinstance(series, dict) and series, "4 小时线必须至少带一条序列")
    require(snapshot.get("count") == len(series), "count 必须与实际序列条数一致")
    unknown = sorted(set(series) - known)
    require(not unknown, f"4 小时线出现了已发布快照以外的标的：{unknown[:5]}")

    meta = snapshot.get("meta")
    require(isinstance(meta, dict), "4 小时线必须逐条记录取数代码与聚合标记")
    require(sorted(meta) == sorted(series), "meta 必须与序列一一对应")

    for symbol, column in series.items():
        require(isinstance(column, list) and len(column) == len(axis),
                f"{symbol} 的列长与共享时间轴不一致")
        observed = [value for value in column if value is not None]
        require(len(observed) >= 2,
                f"{symbol} 不足两个真实观测，不该写进文件（应进 unavailable）")
        require(all(isinstance(value, (int, float)) and value > 0 for value in observed),
                f"{symbol} 存在非正或非数值的收盘价")
        entry = meta[symbol]
        require(entry.get("aggregated") is True,
                f"{symbol} 未标注 aggregated：4 小时桶由本站聚合，必须逐条声明")
        require(entry.get("source"), f"{symbol} 未记录实际取数代码，来源无法核对")
        require(entry.get("buckets") == len(observed),
                f"{symbol} 自报桶数与真实观测数不符")

    # 4. 缺失与沿用如实登记，且两张名单互不重叠
    retained = snapshot.get("retained") or []
    unavailable = snapshot.get("unavailable") or []
    require(isinstance(retained, list) and isinstance(unavailable, list),
            "沿用与缺失名单必须是列表")
    require(set(retained) <= set(series), "沿用名单里出现了文件中不存在的序列")
    require(not (set(unavailable) & set(series)),
            "缺失名单里的标的不得同时出现在序列里")
    require(not (set(unavailable) - known), "缺失名单也不得越出已发布快照")
    for symbol in retained:
        require(meta[symbol].get("stale") is True,
                f"{symbol} 是沿用上一份的，必须标 stale")
    expected_status = "partial" if (retained or unavailable) else "ok"
    require(snapshot.get("status") == expected_status,
            f"状态应为 {expected_status}：有沿用或缺失就不能自称 ok")

    age_hours = (datetime.now(timezone.utc) - updated).total_seconds() / 3600.0
    span_days = (axis[-1] - axis[0]) / 86400.0
    print("Asset tracker 4h series contract: PASS")
    print(f"- {len(series)} series over {len(axis)} four-hour buckets "
          f"({span_days:.1f} days), all inside the published universe ({len(known)} symbols)")
    print(f"- realtime=false, aggregated from 1h, bucket {bucket}s, cadence "
          f"{snapshot['cadenceHours']}h, retain {retain_days}d")
    print(f"- {len(retained)} retained (stale-marked), {len(unavailable)} unavailable")
    print(f"- updated {age_hours:.2f}h ago"
          + ("（超过阈值，页面会按过期处理）" if age_hours > MAX_AGE_HOURS else ""))


if __name__ == "__main__":
    try:
        main()
    except AssertionError as error:
        print(f"FAIL: {error}", file=sys.stderr)
        sys.exit(1)
