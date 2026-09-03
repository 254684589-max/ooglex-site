#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""校验产业链图谱发布文件：节点契约、阶段口径自洽，以及「无证据不上图」。

**这个校验器存在的理由**：供应链图谱唯一不可挽回的错误，是对真实企业断言未经证实的
商业关系。生成脚本里已有 `assert_edge_contract()` 在写盘前拦一道，本校验器在发布侧
再拦一道——**任何一条没有可核验出处的边，都不允许出现在仓库里**。两道防线针对的是
同一件事：模型「知道」的行业关系不是数据来源。

同时校验阶段口径的自洽性：已判定的节点必须真有阶段，未判定的必须给出候选集且不得
伪装成结论。「微软 = 中间制造」这类板块级推断冒充公司级结论的情况，在这里会被拦下。

纯离线，只读发布文件，不发起网络请求。
"""
from __future__ import annotations

import json
import os
import sys

NODES_PATH = "apps/supply-chain/nodes.json"
HEALTH_PATH = "apps/supply-chain/health.json"
EDGES_DIR = "apps/supply-chain/edges"
SMELTERS_PATH = "apps/supply-chain/smelters.json"

ALLOWED_CONFIDENCE = {"disclosed", "inferred"}
ALLOWED_BASIS = {"sector-initial", "sector-ambiguous", "sic-refined", "edge-derived", "unknown"}
REQUIRED_EVIDENCE_FIELDS = ("sourceType", "url", "docDate")


def fail(errors: list[str], message: str) -> None:
    errors.append(message)


def check_nodes(payload: dict, errors: list[str]) -> dict:
    stage_ids = {s.get("id") for s in payload.get("stages") or []}
    if not stage_ids:
        fail(errors, "stages 定义为空，阶段无从校验")

    nodes = payload.get("nodes")
    if not isinstance(nodes, list) or not nodes:
        fail(errors, "nodes 为空——不得用空文件覆盖有效数据")
        return {}

    seen: set[str] = set()
    counts = {"resolved": 0, "ambiguous": 0, "unknown": 0, "byBasis": {}}
    for i, node in enumerate(nodes):
        where = f"nodes[{i}] {node.get('symbol')}"
        node_id = node.get("id")
        if not node_id:
            fail(errors, f"{where}：缺少 id")
        elif node_id in seen:
            fail(errors, f"{where}：id 重复")
        else:
            seen.add(node_id)

        basis = node.get("stageBasis")
        counts["byBasis"][basis] = counts["byBasis"].get(basis, 0) + 1
        if basis not in ALLOWED_BASIS:
            fail(errors, f"{where}：stageBasis {basis!r} 不在允许集 {sorted(ALLOWED_BASIS)}")
            continue

        stage = node.get("stage")
        candidates = node.get("stageCandidates")
        if not isinstance(candidates, list):
            fail(errors, f"{where}：stageCandidates 必须是数组")
            continue
        for candidate in candidates:
            if candidate not in stage_ids:
                fail(errors, f"{where}：候选阶段 {candidate!r} 不在 stages 定义中")

        if basis in ("sector-initial", "sic-refined", "edge-derived"):
            counts["resolved"] += 1
            if not stage:
                fail(errors, f"{where}：basis={basis} 声称已判定，但 stage 为空")
            elif stage not in stage_ids:
                fail(errors, f"{where}：stage {stage!r} 不在 stages 定义中")
            if node.get("stageAmbiguous"):
                fail(errors, f"{where}：已判定的节点不得同时标 stageAmbiguous")
        elif basis == "sector-ambiguous":
            counts["ambiguous"] += 1
            # 核心断言：板块级推断不得冒充公司级结论。
            if stage:
                fail(errors, f"{where}：板块横跨多个阶段却给出了单一结论 {stage!r}——"
                             f"板块级推断不得显示为公司级结论")
            if len(candidates) < 2:
                fail(errors, f"{where}：标为歧义却只给了 {len(candidates)} 个候选")
            if not node.get("stageNote"):
                fail(errors, f"{where}：歧义节点必须说明原因")
        else:
            counts["unknown"] += 1
            if stage:
                fail(errors, f"{where}：basis=unknown 却给出了 stage")

        for field in ("cik", "sic"):
            value = node.get(field)
            if value is not None and not isinstance(value, int):
                fail(errors, f"{where}：{field} 必须是整数或 null，实际 {value!r}")
    return counts


def check_edges(payload: dict, errors: list[str]) -> int:
    """校验关系边。边按公司分文件放在 edges/ 下，本函数逐文件逐条查。

    **契约跟着数据走。** 边从 nodes.json 里挪到独立文件，不等于挪出了校验范围——
    否则「无证据不上图」就成了只管一个数组的空话。这里做四件事：

    1. 索引里登记的每个文件都要能读出来，条数与索引一致；
    2. 每条边逐条过证据契约（非空 evidence、可点开的 https 出处、文件日期）；
    3. 每条边的 `to` 必须就是这个文件的公司——串文件等于把 A 的供应商挂到 B 名下；
    4. **目录里不得有索引外的孤儿文件**——孤儿文件会随站点发布出去却没人校验过。
    """
    index = payload.get("edgeIndex")
    if index is None:
        fail(errors, "缺少 edgeIndex —— 边即使为空也要有索引结构")
        return 0
    if not isinstance(index, dict):
        fail(errors, "edgeIndex 必须是对象")
        return 0

    node_ids = {n.get("id") for n in payload.get("nodes") or []}
    on_disk = ({name[:-5] for name in os.listdir(EDGES_DIR) if name.endswith(".json")}
               if os.path.isdir(EDGES_DIR) else set())
    for orphan in sorted(on_disk - set(index)):
        fail(errors, f"{EDGES_DIR}/{orphan}.json 不在 edgeIndex 里——"
                     f"孤儿边文件会随站点发布却没经过校验")
    for missing in sorted(set(index) - on_disk):
        fail(errors, f"edgeIndex 登记了 {missing}，但 {EDGES_DIR}/{missing}.json 不存在")

    total = 0
    for symbol in sorted(set(index) & on_disk):
        path = os.path.join(EDGES_DIR, f"{symbol}.json")
        try:
            with open(path, encoding="utf-8") as handle:
                bundle = json.load(handle)
        except (OSError, ValueError) as exc:
            fail(errors, f"{path} 读不出来：{exc}")
            continue

        if symbol not in node_ids:
            fail(errors, f"{path}：{symbol} 不在节点表中")
        if bundle.get("symbol") != symbol:
            fail(errors, f"{path}：symbol {bundle.get('symbol')!r} 与文件名不符")
        if (bundle.get("coverage") or {}).get("claimComplete") is not False:
            fail(errors, f"{path}：coverage.claimComplete 必须恒为 false")
        # 边的语义必须写在文件里。「出现在供应链中」与「是供应商」是两件事，
        # 页面靠这个字段决定怎么措辞，缺了就可能被写成直接供货关系。
        if not (bundle.get("relation") or {}).get("label"):
            fail(errors, f"{path}：缺少 relation.label —— 边的语义必须随数据发布")
        if bundle.get("confidence") not in ALLOWED_CONFIDENCE:
            fail(errors, f"{path}：confidence 必须是 {sorted(ALLOWED_CONFIDENCE)}，"
                         f"实际 {bundle.get('confidence')!r}")

        # 出处在文件级：本文件每条边共用这一份。契约 v2 把它从逐边提到文件级，
        # 因为同一份申报里所有边的出处本就相同，提上来之后**结构上不可能**
        # 出现某条边指向别的出处或干脆没有出处。
        evidence = bundle.get("evidence")
        if not isinstance(evidence, dict) or not evidence:
            fail(errors, f"{path}：**没有 evidence 的边文件不得发布**")
        else:
            for field in REQUIRED_EVIDENCE_FIELDS:
                if not evidence.get(field):
                    fail(errors, f"{path} evidence：缺少可核验字段 {field}")
            url = str(evidence.get("url") or "")
            if url and not url.startswith("https://"):
                fail(errors, f"{path} evidence：出处必须是可点开的 https 链接")

        edges = bundle.get("edges")
        if not isinstance(edges, list):
            fail(errors, f"{path}：edges 必须是数组")
            continue
        declared = (index.get(symbol) or {}).get("count")
        if declared != len(edges):
            fail(errors, f"edgeIndex[{symbol}].count 报告 {declared}，实际 {len(edges)}")
        total += len(edges)

        seen_from: set = set()
        for i, edge in enumerate(edges):
            where = f"{symbol}.json edges[{i}] {edge.get('from')}"
            if not edge.get("from"):
                fail(errors, f"{where}：缺少 from")
            elif edge.get("from") in seen_from:
                fail(errors, f"{where}：同一对手方在本文件里重复出现")
            else:
                seen_from.add(edge.get("from"))
            # 定位：这条边在原始申报文档里的哪一行。没有定位，出处就只到「这份文件」，
            # 核验时无从落到具体一条。
            if not isinstance(edge.get("row"), int) or edge["row"] < 1:
                fail(errors, f"{where}：缺少有效的 row 定位")
            if edge.get("idType") not in ("rmi-cid", "name-only"):
                fail(errors, f"{where}：idType {edge.get('idType')!r} 不在允许集")
            # 带编号的必须真有编号，只有名字的必须真没有——两类分开统计的前提
            if edge.get("idType") == "rmi-cid" and not edge.get("cid"):
                fail(errors, f"{where}：标为 rmi-cid 却没有 cid")
            if edge.get("idType") == "name-only" and edge.get("cid"):
                fail(errors, f"{where}：标为 name-only 却带着 cid")
            # 对手方是上市公司时必须能对上节点表；冶炼厂普遍不是，留空即可
            if edge.get("fromListed") and edge.get("from") not in node_ids:
                fail(errors, f"{where}：声称已上市但不在节点表中")
    return total


def check_coverage(payload: dict, counts: dict, edge_count: int, errors: list[str]) -> None:
    coverage = payload.get("coverage")
    if not isinstance(coverage, dict):
        fail(errors, "缺少 coverage —— 覆盖率必须与数据同级发布")
        return
    if coverage.get("claimComplete") is not False:
        fail(errors, "coverage.claimComplete 必须恒为 false —— 本图谱永不宣称完整")
    if coverage.get("nodesTotal") != len(payload.get("nodes") or []):
        fail(errors, f"coverage.nodesTotal {coverage.get('nodesTotal')} 与实际节点数不符")
    if coverage.get("edgesTotal") != edge_count:
        fail(errors, f"coverage.edgesTotal {coverage.get('edgesTotal')} 与实际边数不符")
    with_edges = sum(1 for n in payload.get("nodes") or [] if n.get("edgeCount"))
    if coverage.get("nodesWithEdges") != with_edges:
        fail(errors, f"coverage.nodesWithEdges {coverage.get('nodesWithEdges')} "
                     f"与实际有边节点数 {with_edges} 不符")
    # 有边就必须说清这些边是什么意思，不能只报数字
    if edge_count and not (coverage.get("note") or ""):
        fail(errors, "有关系边却没有 coverage.note 说明其语义")
    # 逐项核对，不能只查其中一项：曾经只校验 sector-ambiguous，结果 stageByBasis 把
    # 495 个 sic-refined 节点全报成 sector-initial 也照样通过——覆盖率报告说错了
    # 数据质量的来源却没人拦下。
    by_basis = coverage.get("stageByBasis") or {}
    actual_basis = counts.get("byBasis") or {}
    for basis, actual in actual_basis.items():
        if by_basis.get(basis) != actual:
            fail(errors, f"coverage.stageByBasis[{basis}] 报告 {by_basis.get(basis)}，"
                         f"实际 {actual}")
    for basis, reported in by_basis.items():
        if reported and basis not in actual_basis:
            fail(errors, f"coverage.stageByBasis 多报了 {basis}={reported}，实际没有这类节点")

    # 按板块的覆盖数字直接印在页面上，说错了就是对读者撒谎。逐板块重算一遍：
    # 家数要对得上、分项要加得起来、有名单的家数不能超过实际有边的家数。
    nodes = payload.get("nodes") or []
    by_sector = coverage.get("bySector")
    if by_sector is not None:
        if not isinstance(by_sector, list):
            fail(errors, "coverage.bySector 必须是数组")
            return
        actual: dict[str, dict[str, int]] = {}
        for node in nodes:
            key = node.get("sector") or "未分类"
            row = actual.setdefault(key, {"companies": 0, "withEdges": 0})
            row["companies"] += 1
            if node.get("edgeCount"):
                row["withEdges"] += 1
        seen = set()
        parts = ("withEdges", "filedNoList", "noFiling", "failed", "unscanned")
        for row in by_sector:
            name = row.get("sector")
            seen.add(name)
            truth = actual.get(name)
            if truth is None:
                fail(errors, f"coverage.bySector 多报了板块「{name}」，节点表里没有")
                continue
            if row.get("companies") != truth["companies"]:
                fail(errors, f"coverage.bySector[{name}].companies 报告 "
                             f"{row.get('companies')}，实际 {truth['companies']}")
            if row.get("withEdges") != truth["withEdges"]:
                fail(errors, f"coverage.bySector[{name}].withEdges 报告 "
                             f"{row.get('withEdges')}，实际 {truth['withEdges']}")
            # 分项之和必须等于家数。少加一项，页面上的进度条就会缺一截，
            # 读者看到的比例是错的。
            total = sum(row.get(k) or 0 for k in parts)
            if total != truth["companies"]:
                fail(errors, f"coverage.bySector[{name}] 分项之和 {total} "
                             f"≠ 家数 {truth['companies']}")
        for name in actual:
            if name not in seen:
                fail(errors, f"coverage.bySector 漏了板块「{name}」")


def check_smelters(errors: list[str], edge_count: int) -> dict:
    """校验冶炼厂登记表。它带覆盖率声明，就必须和数据对得上。

    这里守的核心是**别把条目数说成实体数**：无编号条目里有大量与带编号条目同名的
    （实测 876 条里 681 条），不分开报就会把约 1032 家说成 1713 家。
    """
    if not os.path.exists(SMELTERS_PATH):
        return {}                                   # 抽取器还没跑过，不是错误
    try:
        with open(SMELTERS_PATH, encoding="utf-8") as handle:
            payload = json.load(handle)
    except (OSError, ValueError) as exc:
        fail(errors, f"{SMELTERS_PATH} 读不出来：{exc}")
        return {}

    coverage = payload.get("coverage") or {}
    smelters = payload.get("smelters") or {}
    if coverage.get("claimComplete") is not False:
        fail(errors, "smelters.coverage.claimComplete 必须恒为 false")
    if coverage.get("edgesTotal") != edge_count:
        fail(errors, f"smelters.coverage.edgesTotal {coverage.get('edgesTotal')} "
                     f"与实际边数 {edge_count} 不符")
    if coverage.get("uniqueSmelters") != len(smelters):
        fail(errors, f"smelters.coverage.uniqueSmelters {coverage.get('uniqueSmelters')} "
                     f"与实际条目数 {len(smelters)} 不符")

    by_id = {"rmi-cid": 0, "name-only": 0}
    same_name = 0
    for key, entry in smelters.items():
        kind = entry.get("identifierType")
        if kind not in by_id:
            fail(errors, f"smelters[{key}]：identifierType {kind!r} 不在允许集")
            continue
        by_id[kind] += 1
        if kind == "rmi-cid" and not entry.get("cid"):
            fail(errors, f"smelters[{key}]：标为 rmi-cid 却没有 cid")
        if kind == "name-only" and entry.get("cid"):
            fail(errors, f"smelters[{key}]：标为 name-only 却带着 cid")
        twin = entry.get("sameNameAs")
        if not twin:
            continue
        same_name += 1
        # sameNameAs 只记录「名字完全相同」这个事实，指向的必须是带编号的那一条，
        # 否则它就不是「有编号可查」的线索，而是两条无编号条目互指。
        if kind != "name-only":
            fail(errors, f"smelters[{key}]：只有无编号条目才该带 sameNameAs")
        elif twin not in smelters:
            fail(errors, f"smelters[{key}].sameNameAs 指向不存在的 {twin}")
        elif smelters[twin].get("identifierType") != "rmi-cid":
            fail(errors, f"smelters[{key}].sameNameAs 指向的 {twin} 不是带编号条目")

    reported = coverage.get("uniqueByIdentifier") or {}
    for kind, actual in by_id.items():
        if reported.get(kind) != actual:
            fail(errors, f"smelters.coverage.uniqueByIdentifier[{kind}] "
                         f"报告 {reported.get(kind)}，实际 {actual}")
    if coverage.get("exactNameMatchWithCid") != same_name:
        fail(errors, f"smelters.coverage.exactNameMatchWithCid "
                     f"报告 {coverage.get('exactNameMatchWithCid')}，实际 {same_name}")
    # 这一条是「别把条目数说成实体数」的落地：下限估计必须真的扣掉同名那部分
    expected = len(smelters) - same_name
    if coverage.get("distinctAfterExactNameMatch") != expected:
        fail(errors, f"smelters.coverage.distinctAfterExactNameMatch "
                     f"报告 {coverage.get('distinctAfterExactNameMatch')}，"
                     f"应为条目数 {len(smelters)} − 同名 {same_name} = {expected}")
    # 「有申报无名单」与「无申报」必须分开——合并会把披露制度的上限说成抓取失败
    for field in ("companiesWithList", "companiesFiledNoList", "companiesNoFiling"):
        if not isinstance(coverage.get(field), int):
            fail(errors, f"smelters.coverage 缺少 {field}（三种申报状态必须分开计数）")
    return coverage


def check_health(errors: list[str], node_count: int) -> None:
    if not os.path.exists(HEALTH_PATH):
        fail(errors, f"缺少 {HEALTH_PATH}")
        return
    with open(HEALTH_PATH, encoding="utf-8") as handle:
        health = json.load(handle)
    if health.get("dataset") != "supply-chain-graph":
        fail(errors, "health.dataset 不符")
    published = (health.get("coverage") or {}).get("publishedNodes")
    if published != node_count:
        fail(errors, f"health 发布节点数 {published} 与 nodes.json 的 {node_count} 不符")
    if health.get("status") not in ("healthy", "degraded", "failed"):
        fail(errors, f"health.status {health.get('status')!r} 不在允许集")


def main() -> int:
    if not os.path.exists(NODES_PATH):
        print(f"[XX] 缺少 {NODES_PATH}")
        return 1
    with open(NODES_PATH, encoding="utf-8") as handle:
        payload = json.load(handle)

    errors: list[str] = []
    counts = check_nodes(payload, errors)
    edge_count = check_edges(payload, errors)
    check_coverage(payload, counts, edge_count, errors)
    smelters = check_smelters(errors, edge_count)
    check_health(errors, len(payload.get("nodes") or []))

    total_nodes = len(payload.get("nodes") or [])
    print(f"节点 {total_nodes}：已判定 {counts.get('resolved', 0)}，"
          f"仅候选集 {counts.get('ambiguous', 0)}，未登记 {counts.get('unknown', 0)}")
    index = payload.get("edgeIndex") or {}
    print(f"关系边 {edge_count} 条，分布在 {len(index)} 个公司边文件里"
          + ("（全部携带可核验出处）" if edge_count else "（尚无证据来源）"))
    if smelters:
        print(f"冶炼厂登记表 {smelters.get('uniqueSmelters')} 条目"
              f"（带编号 {(smelters.get('uniqueByIdentifier') or {}).get('rmi-cid')} · "
              f"仅名字 {(smelters.get('uniqueByIdentifier') or {}).get('name-only')}）；"
              f"其中 {smelters.get('exactNameMatchWithCid')} 条与带编号条目同名，"
              f"扣掉后不同实体下限 {smelters.get('distinctAfterExactNameMatch')}")
        print(f"申报状态：有名单 {smelters.get('companiesWithList')} 家 · "
              f"有申报无名单 {smelters.get('companiesFiledNoList')} 家 · "
              f"无申报 {smelters.get('companiesNoFiling')} 家")
    by_sector = (payload.get("coverage") or {}).get("bySector") or []
    if by_sector:
        top = "、".join(f"{r['sector']} {r['withEdges']}/{r['companies']}"
                       for r in by_sector[:4])
        unscanned = sum(r.get("unscanned") or 0 for r in by_sector)
        print(f"按板块覆盖：{top} …"
              + (f"（其中 {unscanned} 家尚无逐家申报状态）" if unscanned else ""))
    print(f"claimComplete = {(payload.get('coverage') or {}).get('claimComplete')}（必须恒为 false）")

    if errors:
        print(f"\n失败 {len(errors)} 项：")
        for item in errors[:40]:
            print(f"  · {item}")
        if len(errors) > 40:
            print(f"  …另有 {len(errors) - 40} 项")
        return 1
    print("\n全部通过")
    return 0


if __name__ == "__main__":
    sys.exit(main())
