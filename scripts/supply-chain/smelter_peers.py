#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""从冶炼厂登记表算出「两家公司的上游有多少重叠」。

## 为什么这条能画，而「谁供货给谁」不能

板块的铁律是**公司间的关系必须有可核验的原始申报**。到目前为止唯一跑通的关系是
公司 → 冶炼厂（来自 Form SD 名单），公司 ↔ 公司 一条都没有。

这个模块给出第一条，而且它是**两份原始申报的直接交集**：

    英伟达那份申报里列了 A.L.M.T. Corp.
    超微那份申报里也列了 A.L.M.T. Corp.
    ⇒ 这两家的冶炼厂名单里出现了同一家冶炼厂

这句话完全由两份可点开的文件支撑，没有一个字是推断出来的。

## 它**不**表示什么

- 不表示两家之间有业务往来、供货、合作或竞争
- 不表示两家共用同一条供应链
- 不表示谁在谁的上游

它表示的是**上游冶炼环节的共同暴露**：同一家冶炼厂一旦出事（制裁、停产、
产地争议），这两家的名单都会被牵动。这正是供应链分析真正关心的东西，
但必须按它的原义说，不能升格成「合作关系」。

## 这个口径只会少算，不会多算

冶炼厂登记表里 837 条有 RMI 全球编号、868 条只有名字。只有名字的按规范化名字
合并，而各家申报里的写法不一（`Asahi Pretec Corp.` / `Corporation` / `CORP`），
**同一家厂被写成两条时，两家公司就不会被算作重叠**。

方向是确定的：漏算，不会错算。这与登记表本身的口径一致——宁可一家重复出现，
不可两家被错并成一家。页面上要写明这一点，不能让读者以为重叠数是精确值。
"""
from __future__ import annotations

from itertools import combinations

# 每家最多列几个重叠对手方、几家共同申报最多的冶炼厂。
# 不是省略：总数照实给（peerCount / total），列表只是取前几名，页面写明还有多少。
MAX_PEERS = 12
MAX_SHARED = 6
# 集中度榜单进 nodes.json（总览页已经会下它，不必多发一次请求）；
# 全表 1705 条不发布——发了就是 400KB，而页面只看得下前几十条。
TOP_CONCENTRATION = 30

RELATION = {
    "id": "shared-smelter-upstream",
    "label": "两家申报人的冶炼厂名单里出现了同一批冶炼厂"
             "（上游共同暴露，不表示两家之间有业务往来）",
    "basis": "two-form-sd-filings",
}


def build_peers(smelters: dict) -> dict:
    """算出公司两两之间的上游重叠。

    入参是 smelters.json 里的 `smelters`（id → 条目，条目带 `filers` 申报人列表）。
    返回 {"companies": {代码: {...}}, "pairs": 对数, "concentration": [...]}。
    """
    rows = list((smelters or {}).values())

    total: dict[str, int] = {}                  # 每家自己名单里有几家冶炼厂
    shared: dict[tuple[str, str], int] = {}     # 两家之间重叠几家
    listed_in: dict[str, list] = {}             # 每家名单里各冶炼厂被多少人共同申报

    for row in rows:
        filers = sorted({f for f in (row.get("filers") or []) if f})
        if not filers:
            continue
        for symbol in filers:
            total[symbol] = total.get(symbol, 0) + 1
        # 两两组合。90 家申报人最多 4005 对，规模无需优化。
        for left, right in combinations(filers, 2):
            key = (left, right)
            shared[key] = shared.get(key, 0) + 1

    # 上游集中度：一家冶炼厂被多少家公司共同列入。这是本板块少见的、
    # 完全不需要推断的风险读数——名单里数出来的。
    concentration = []
    for row in rows:
        filers = [f for f in (row.get("filers") or []) if f]
        # 只被一家列入的不是「集中」，那只是那一家的名单条目。
        # 发布契约也按 ≥2 收，两处口径必须一致——离线夹具就是这么把它们对上的。
        if len(filers) < 2:
            continue
        concentration.append({
            "id": row.get("id"),
            "name": row.get("name"),
            "nameZh": row.get("nameZh"),
            "country": row.get("country"),
            "minerals": row.get("minerals") or [],
            "identifierType": row.get("identifierType"),
            "filerCount": len(filers),
        })
    concentration.sort(key=lambda r: (-r["filerCount"], str(r["name"] or "")))

    # 每家公司名单里，被最多同行共同申报的那几家——它自己的集中暴露点
    by_company: dict[str, list] = {}
    for row in rows:
        filers = [f for f in (row.get("filers") or []) if f]
        if len(filers) < 2:
            continue
        for symbol in filers:
            by_company.setdefault(symbol, []).append({
                "id": row.get("id"),
                "name": row.get("name"),
                "nameZh": row.get("nameZh"),
                "country": row.get("country"),
                "filerCount": len(filers),
            })

    peers_of: dict[str, list] = {}
    for (left, right), count in shared.items():
        peers_of.setdefault(left, []).append((right, count))
        peers_of.setdefault(right, []).append((left, count))

    companies: dict[str, dict] = {}
    for symbol in sorted(total):
        pairs = sorted(peers_of.get(symbol, []), key=lambda p: (-p[1], p[0]))
        mine = sorted(by_company.get(symbol, []),
                      key=lambda r: (-r["filerCount"], str(r["name"] or "")))
        companies[symbol] = {
            "total": total[symbol],
            "peerCount": len(pairs),
            # 两边的总数都带上：只给「重叠 236 家」看不出这是多是少，
            # 得知道各自名单有多大才判断得了。
            "peers": [{"symbol": other, "shared": count, "peerTotal": total.get(other, 0)}
                      for other, count in pairs[:MAX_PEERS]],
            "topShared": mine[:MAX_SHARED],
        }

    return {
        "companies": companies,
        "pairs": len(shared),
        # 榜单截断，但**总数照实给**：读者要知道自己看的是 30/1705 还是全部。
        "concentration": concentration[:TOP_CONCENTRATION],
        # 两个总数分开报：被多家共同申报的有多少（集中度的分母），
        # 以及登记表一共多少条。只给一个数会让读者算错比例。
        "concentrationTotal": len(concentration),
        "smeltersTotal": len(rows),
        "maxPeers": MAX_PEERS,
        "maxShared": MAX_SHARED,
    }
