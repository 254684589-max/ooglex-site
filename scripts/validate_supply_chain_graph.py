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
import re
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
    # nodesWithEdges（实际发布了几家的边）与 formSd.companiesWithList（本轮扫描
    # 抽到几家名单）本就可能差几家：抽取器不删有效历史数据，上一轮抓到、这一轮
    # 没复现的公司边文件仍在。差额必须与 edgesFromEarlierScan 逐家对得上，
    # 对不上就是别处出了问题，不能糊弄过去。
    listed_now = ((coverage.get("formSd") or {}).get("companiesWithList"))
    stale = coverage.get("edgesFromEarlierScan")
    if listed_now is not None and stale is not None:
        published = coverage.get("nodesWithEdges") or 0
        if published - listed_now != len(stale):
            fail(errors, f"发布了 {published} 家的边、本轮扫描只抽到 {listed_now} 家，"
                         f"差 {published - listed_now} 家，但 edgesFromEarlierScan "
                         f"只列了 {len(stale)} 家——差额没有交代清楚")
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
        # bySector 只统计标普那一池。外国发行人没有站内板块分类，按国别单列在
        # byCountry 里——把它们算进「未分类」等于一个 147 家的黑箱，而且会把
        # 「金融 0/70」这类制度上限的解释稀释掉。两栏加起来才是全池。
        actual: dict[str, dict[str, int]] = {}
        for node in nodes:
            if node.get("pool") == "sec-foreign-issuer":
                continue
            key = node.get("sector") or "未分类"
            row = actual.setdefault(key, {"companies": 0, "withEdges": 0})
            row["companies"] += 1
            if node.get("edgeCount"):
                row["withEdges"] += 1
        seen = set()
        parts = ("withEdges", "filedNoList", "noFiling", "resourceExtraction",
                 "failed", "unscanned")
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

    by_country = coverage.get("byCountry")
    if by_country is not None:
        if not isinstance(by_country, list):
            fail(errors, "coverage.byCountry 必须是数组")
            return
        truth_country: dict[str, int] = {}
        for node in nodes:
            if node.get("pool") != "sec-foreign-issuer":
                continue
            truth_country[node.get("country") or "未分类"] = truth_country.get(
                node.get("country") or "未分类", 0) + 1
        for row in by_country:
            name = row.get("sector")          # 字段名复用，语义是国别
            if name not in truth_country:
                fail(errors, f"coverage.byCountry 多报了国别「{name}」，节点表里没有")
            elif row.get("companies") != truth_country[name]:
                fail(errors, f"coverage.byCountry[{name}] 报告 {row.get('companies')}，"
                             f"实际 {truth_country[name]}")
        missing = set(truth_country) - {r.get("sector") for r in by_country}
        for name in sorted(missing):
            fail(errors, f"coverage.byCountry 漏了国别「{name}」")

        # 两栏之和必须等于全池。差一家就说明有公司两栏都没进——页面上它就消失了。
        both = (sum(r.get("companies") or 0 for r in (by_sector or []))
                + sum(r.get("companies") or 0 for r in by_country))
        if by_sector is not None and both != len(nodes):
            fail(errors, f"按板块 + 按国别 合计 {both} 家，全池 {len(nodes)} 家——"
                         "有公司两栏都没进，页面上会直接消失")


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


# 合并冲突留下的标记。这不是假想风险：2026-09-04 合并到 main 时
# identity.json 里带着 <<<<<<< 被 `git add -A` 当成「已解决」暂存，
# 构建脚本解析失败后**静默退回板块级口径**，495 家的 SIC 判定全丢，
# 苹果的 CIK 和 SIC 变成 None。四道校验里只有浏览器契约抓到了它，
# 而且是靠一条间接的断言（公司页没有 SEC 链接）。
# 数据文件是发布物，带着冲突标记上线就是把损坏的文件发给用户。
CONFLICT_MARKERS = ("<<<<<<< ", "=======\n", ">>>>>>> ")


def check_no_conflict_markers(errors: list[str]) -> None:
    """发布目录里的所有文件都不得含合并冲突标记。"""
    root = "apps/supply-chain"
    for base, _dirs, names in os.walk(root):
        for name in sorted(names):
            path = os.path.join(base, name)
            try:
                with open(path, encoding="utf-8") as handle:
                    text = handle.read()
            except (OSError, UnicodeDecodeError):
                continue
            hits = [m.strip() for m in CONFLICT_MARKERS if m in text]
            if hits:
                fail(errors, f"{path} 含合并冲突标记 {hits} —— 未解决的冲突不得发布")
            # JSON 必须真的解析得开。解析不开时构建脚本会静默退回默认口径，
            # 数据看着还在，判定依据已经全没了。
            if name.endswith(".json"):
                try:
                    with open(path, encoding="utf-8") as handle:
                        json.load(handle)
                except ValueError as exc:
                    fail(errors, f"{path} 不是合法 JSON：{exc}")


def check_chains(payload: dict, errors: list[str]) -> None:
    """横轴契约：链表与节点上的归属必须对得上。

    这里守的不是「有没有链」，是**页面读到的数与节点表算出来的数是同一个**。
    链的家数是构建时预算进 chains[].count 的，页面直接印；预算错了页面就跟着
    印错，而且看不出来——所以在这里按节点重新数一遍。
    """
    rows = payload.get("chains")
    if rows is None:
        return                      # 横轴模块缺失时构建不写这个字段，属已知降级
    if not isinstance(rows, list) or not rows:
        fail(errors, "chains 字段存在但为空——要么写全，要么别写")
        return

    ids = [r.get("id") for r in rows]
    if len(ids) != len(set(ids)):
        fail(errors, "chains 里有重复的 id")

    tally: dict[str, int] = {}
    tally_edges: dict[str, int] = {}
    unclassified = 0
    for node in payload.get("nodes") or []:
        got = node.get("chains")
        if got is None:
            fail(errors, f"{node.get('symbol')} 没有 chains 字段——横轴要么全有要么全无")
            return
        if not got:
            unclassified += 1
        for cid in got:
            if cid not in ids:
                fail(errors, f"{node.get('symbol')} 挂在未登记的链 {cid!r} 上")
            tally[cid] = tally.get(cid, 0) + 1
            tally_edges[cid] = tally_edges.get(cid, 0) + (node.get("edgeCount") or 0)

    for row in rows:
        cid = row.get("id")
        if row.get("count") != tally.get(cid, 0):
            fail(errors, f"链 {cid} 家数 {row.get('count')} 与节点实际 "
                         f"{tally.get(cid, 0)} 不符")
        if row.get("edgeCount") != tally_edges.get(cid, 0):
            fail(errors, f"链 {cid} 关系数 {row.get('edgeCount')} 与节点实际 "
                         f"{tally_edges.get(cid, 0)} 不符")
        if not row.get("label") or not row.get("labelEn"):
            fail(errors, f"链 {cid} 缺中文或英文名")

    coverage = payload.get("coverage") or {}
    if coverage.get("chainUnclassified") != unclassified:
        fail(errors, f"coverage.chainUnclassified {coverage.get('chainUnclassified')} "
                     f"与实际 {unclassified} 不符")
    # 未归类不是错误，但必须如实报出来；这里只在数对不上时失败。
    if unclassified:
        print(f"[!!] 有 {unclassified} 家没有产业链归属——SIC 表没覆盖到它们的码")


def check_chain_links(payload: dict, errors: list[str]) -> None:
    """链间上下游的契约。**这一道守的是「框架不许冒充证据」**。

    链间上下游是产业结构常识（「半导体的上游包含化工」），与 edges/ 里那两万条
    指名申报人与冶炼厂、必须能点开原始申报的关系是两回事。两者一旦混在一起，
    整块板块最重要的那条界线就没了——读者会以为「半导体→汽车」也是从某份文件里
    抽出来的。所以这里逐条钉死：只能连已登记的链、两端都不许是公司、
    必须自报 basis=framework、必须写清流动的是什么。
    """
    links = payload.get("chainLinks")
    if links is None:
        return                      # 横轴模块缺失时不写这个字段，属已知降级
    if not isinstance(links, list):
        fail(errors, "chainLinks 不是列表")
        return

    chain_ids = {row.get("id") for row in (payload.get("chains") or [])}
    symbols = {n.get("symbol") for n in (payload.get("nodes") or [])}
    seen: set[tuple[str, str]] = set()
    for link in links:
        src, dst = link.get("from"), link.get("to")
        where = f"{src}→{dst}"
        if src not in chain_ids or dst not in chain_ids:
            fail(errors, f"链间上下游 {where} 连到了未登记的链")
            continue
        if src == dst:
            fail(errors, f"链间上下游 {where} 自己连自己")
        # 两端必须是链，不能是公司。写错了就是把框架伪装成公司级关系。
        if src in symbols or dst in symbols:
            fail(errors, f"链间上下游 {where} 的一端是公司代码——框架不得指名公司")
        if link.get("basis") != "framework":
            fail(errors, f"链间上下游 {where} 的 basis 不是 framework"
                         f"（实际 {link.get('basis')!r}）——它不能被当成有出处的边")
        # 只画箭头不说流动的是什么，等于没说话
        if not (link.get("flow") or "").strip():
            fail(errors, f"链间上下游 {where} 没写流动的是什么")
        # 出处字段一个都不许有：有了就说明有人在往框架里塞证据字段
        for key in ("sourceType", "url", "docDate", "evidence"):
            if key in link:
                fail(errors, f"链间上下游 {where} 带了 {key} 字段——"
                             "框架不得携带出处，出处只属于 edges/")
        if (src, dst) in seen:
            fail(errors, f"链间上下游 {where} 重复")
        seen.add((src, dst))

    # 没有连线的链只允许是标了「横跨全链」的那几条。一条链既没有上下游、
    # 又没被说明为什么没有，页面上就是个断头——读者只会当成数据缺失。
    cross = payload.get("chainCrossCutting") or {}
    linked = {l.get("from") for l in links} | {l.get("to") for l in links}
    for row in payload.get("chains") or []:
        cid = row.get("id")
        if cid in linked or cid in cross:
            continue
        if row.get("count"):
            fail(errors, f"链 {cid} 有 {row['count']} 家公司却既无上下游、"
                         "也没标为横跨全链——页面上会是个没有解释的断头")

    count = (payload.get("coverage") or {}).get("chainLinksTotal")
    if count != len(links):
        fail(errors, f"coverage.chainLinksTotal {count} 与实际 {len(links)} 条不符")

    # 层次：页面按它排上下游，排错了整页的方向感就是错的，而且不会报错。
    coverage = payload.get("coverage") or {}
    depth = coverage.get("chainDepth") or 0
    layered = [r for r in (payload.get("chains") or []) if isinstance(r.get("layer"), int)]
    if depth:
        if depth > len(payload.get("chains") or []):
            fail(errors, f"层数 {depth} 超过链数——第一版对有环的图硬算就是这个形态")
        for row in layered:
            if not 0 <= row["layer"] < depth:
                fail(errors, f"链 {row['id']} 的层次 {row['layer']} 越界（共 {depth} 层）")
        for row in payload.get("chains") or []:
            in_cross = row.get("id") in cross
            if in_cross and isinstance(row.get("layer"), int):
                fail(errors, f"使能链 {row['id']} 不该有层次——它横跨全链，"
                             "塞进某一层是假的")
            if not in_cross and row.get("layer") is None:
                fail(errors, f"链 {row['id']} 没有层次，页面排不出它的上下游位置")

    # 逆向边：数目要与 coverage 对得上，且每条都得说清为什么是逆向的
    back = [l for l in links if l.get("direction") == "counterflow"]
    want_back = coverage.get("chainCounterflow")
    if want_back is not None and want_back != len(back):
        fail(errors, f"coverage.chainCounterflow {want_back} 与实际 {len(back)} 条不符")
    for link in links:
        direction = link.get("direction")
        if direction not in ("forward", "counterflow"):
            fail(errors, f"链间上下游 {link.get('from')}→{link.get('to')} 的 direction "
                         f"是 {direction!r}，只能是 forward 或 counterflow")
        if direction == "counterflow" and not (link.get("counterflowWhy") or "").strip():
            fail(errors, f"逆向边 {link.get('from')}→{link.get('to')} 没写为什么是逆向的")


PEERS_PATH = "apps/supply-chain/peers.json"
# 升格词。上游重叠是「两家名单里有同一批冶炼厂」，说成供应商／合作／伙伴
# 都是替申报人下结论，而且是错的——这正是本板块最想守住的那条线。
_OVERSTATED = ("供应商", "合作", "伙伴", "客户", "供货")


def check_pools(payload: dict, errors: list[str]) -> None:
    """两个公司池的契约。守的是「哪些数适用于哪一批公司」不被混起来。

    标普那 495 家有站内报价，外国私人发行人那批没有。把两批合成一个数说
    「642 家」，读者会以为它们都有市值与当日涨跌——而市值合计与环节涨跌
    的分母里根本没有后者。所以两个池必须分开计数，且**外国发行人的
    marketCap 必须是 null，不能是 0**：0 会被市值加权当成真值算进去。
    """
    nodes = payload.get("nodes") or []
    if not nodes:
        return
    coverage = payload.get("coverage") or {}
    pools: dict[str, int] = {}
    for node in nodes:
        pool = node.get("pool")
        if pool not in ("sp500", "sec-foreign-issuer"):
            fail(errors, f"{node.get('symbol')} 的 pool 是 {pool!r}，"
                         "只能是 sp500 或 sec-foreign-issuer")
            continue
        pools[pool] = pools.get(pool, 0) + 1
        if pool == "sec-foreign-issuer":
            if node.get("marketCap") is not None:
                fail(errors, f"{node.get('symbol')} 是外国发行人却带了市值 "
                             f"{node.get('marketCap')!r}——站内没有它的报价，"
                             "写进去就是造数")
            if not node.get("cik"):
                fail(errors, f"外国发行人 {node.get('symbol')} 没有 CIK，"
                             "它是这批公司唯一的实体锚点")

    for key, pool in (("poolSp500", "sp500"),
                      ("poolForeignIssuer", "sec-foreign-issuer")):
        want = coverage.get(key)
        if want is not None and want != pools.get(pool, 0):
            fail(errors, f"coverage.{key} {want} 与实际 {pools.get(pool, 0)} 家不符")

    without_quote = sum(1 for n in nodes if n.get("marketCap") is None)
    if coverage.get("nodesWithoutQuote") not in (None, without_quote):
        fail(errors, f"coverage.nodesWithoutQuote {coverage.get('nodesWithoutQuote')} "
                     f"与实际 {without_quote} 家不符")

    # 中文名对照表。**没有中文名不是错误**（多数加拿大初级矿商本就没有通用
    # 译名，显示英文原文是对的），要拦的是两件事：
    # 一、表里有条目在数据里找不到对应公司——那条键抄错了，白写；
    # 二、报的家数与节点里实际有译名的家数对不上——覆盖率在说假话。
    name_zh = coverage.get("foreignNameZh")
    if isinstance(name_zh, dict):
        orphans = name_zh.get("orphans") or []
        if orphans:
            fail(errors, f"中文名对照表里 {len(orphans)} 条在数据里找不到对应公司，"
                         f"键抄错了：{'、'.join(map(str, orphans[:5]))}")
        named = sum(1 for n in nodes
                    if n.get("pool") == "sec-foreign-issuer"
                    and n.get("name") and n.get("name") != n.get("nameEn"))
        if name_zh.get("named") not in (None, named):
            fail(errors, f"coverage.foreignNameZh.named {name_zh.get('named')} "
                         f"与实际有中文名的 {named} 家不符")

    # 环节涨跌的分母只能是有报价的那批。混进无报价的公司会伪造当日表现。
    perf = payload.get("stagePerformance") or {}
    counted = sum(row.get("companies") or 0 for row in perf.get("stages") or [])
    quoted = sum(1 for n in nodes if n.get("marketCap") is not None)
    if counted > quoted:
        fail(errors, f"环节涨跌统计了 {counted} 家，超过有报价的 {quoted} 家——"
                     "无报价的公司被算进均值了")


def check_peers(payload: dict, errors: list[str]) -> None:
    """上游重叠的契约。守三件事：不多算、说得准、两边对得上。

    这是本板块第一条公司 ↔ 公司的关系，也因此是最容易说过头的一条。
    它只是两份申报名单的交集，**不表示两家之间有任何业务往来**。
    """
    if not os.path.exists(PEERS_PATH):
        return                              # 还没算过不是错误
    try:
        with open(PEERS_PATH, encoding="utf-8") as handle:
            peers = json.load(handle)
    except (OSError, ValueError) as exc:
        fail(errors, f"{PEERS_PATH} 读不出来：{exc}")
        return

    relation = peers.get("relation") or {}
    if relation.get("id") != "shared-smelter-upstream":
        fail(errors, f"peers.relation.id 是 {relation.get('id')!r}，口径变了要同步契约")
    text = (relation.get("label") or "") + (peers.get("note") or "")
    for word in _OVERSTATED:
        if word in text and "不表示" not in text.split(word)[0][-24:]:
            # 出现升格词而附近没有否定，多半是把重叠说成了业务关系
            if f"不表示两家之间有业务往来" not in text:
                fail(errors, f"peers 的说明里出现「{word}」却没有澄清——"
                             "上游重叠不是供应关系")
                break
    if "只会少算" not in (peers.get("note") or ""):
        fail(errors, "peers.note 没写明这个口径只会少算——"
                     "读者会把重叠数当成精确值")

    coverage = peers.get("coverage") or {}
    if coverage.get("understatesOverlap") is not True:
        fail(errors, "peers.coverage.understatesOverlap 必须为 true")

    companies = peers.get("companies") or {}
    with_edges = set((payload.get("edgeIndex") or {}))
    counts: dict[tuple[str, str], int] = {}
    for symbol, row in companies.items():
        if symbol not in with_edges:
            fail(errors, f"peers 里的 {symbol} 没有边文件——没有名单就不可能有重叠")
        total = row.get("total") or 0
        for peer in row.get("peers") or []:
            other = peer.get("symbol")
            shared = peer.get("shared") or 0
            peer_total = peer.get("peerTotal") or 0
            if other == symbol:
                fail(errors, f"peers 里 {symbol} 与自己重叠")
            # 重叠不可能超过任何一方的名单长度。超了就是算法把同一条数了两遍。
            if shared > total or (peer_total and shared > peer_total):
                fail(errors, f"peers {symbol}↔{other} 重叠 {shared} 超过名单长度"
                             f"（{total} / {peer_total}）——多算了")
            if shared <= 0:
                fail(errors, f"peers {symbol}↔{other} 重叠 {shared}，不该列出来")
            counts[(symbol, other)] = shared

    # 对称性：两边都列出对方时，数必须一样。列表有上限，所以只查两边都在的那些。
    for (left, right), count in counts.items():
        mirror = counts.get((right, left))
        if mirror is not None and mirror != count:
            fail(errors, f"peers {left}↔{right} 两边对不上：{count} vs {mirror}")

    # 集中度榜：一家冶炼厂被多少家共同申报，不可能超过有名单的公司数
    listed = len(with_edges)
    rows = payload.get("upstreamConcentration") or []
    total_rows = (payload.get("coverage") or {}).get("upstreamConcentrationTotal") or 0
    if len(rows) > total_rows:
        fail(errors, f"集中度榜 {len(rows)} 条多于总数 {total_rows}")
    for row in rows:
        n = row.get("filerCount") or 0
        if n > listed:
            fail(errors, f"冶炼厂 {row.get('name')!r} 被 {n} 家申报，"
                         f"超过有名单的 {listed} 家——数错了")
        if n < 2:
            fail(errors, f"冶炼厂 {row.get('name')!r} 只有 {n} 家申报，"
                         "不构成集中度，不该上榜")
    if rows != sorted(rows, key=lambda r: -(r.get("filerCount") or 0)):
        fail(errors, "集中度榜没有按家数降序——页面按顺序显示，排错就是排行榜错")


def check_page_meta(payload: dict, errors: list[str]) -> None:
    """页面的 title / og:title / description 不得停在旧口径。

    这一条是**补上一次没修干净的漏**：两轮前把首屏那句「标普500成分股按价值链
    环节分层」改成照数据渲染，却漏了 `<title>`、`og:title` 与公司页的
    description——而那三处正是浏览器标签页、搜索结果与社交分享看到的文案。
    只修看得见的那一处、漏掉 meta，等于没修。

    静态 HTML 里的文案不会自己更新，所以只能由契约来盯：
    **凡是断言板块只收标普500的措辞，一律拦下**；写了链数环节数的，
    必须与数据对得上。
    """
    coverage = payload.get("coverage") or {}
    files = {
        "apps/supply-chain/index.html": ("title", "og:title", "description"),
        "apps/supply-chain/company.html": ("title", "description"),
    }
    # 「只收标普500」的说法。板块早已是标普 495 + 外国私人发行人 147。
    stale = re.compile(r"标普\s*500\s*公司|单家标普\s*500|只收录标普\s*500|"
                       r"标普500成分股按价值链环节分层")
    for path in files:
        try:
            with open(path, encoding="utf-8") as handle:
                html = handle.read()
        except OSError:
            continue
        head = html.split("</head>", 1)[0]
        # 报行号：title 与 og:title 往往写着同一句话，只报措辞会打出两行
        # 一模一样的错，读的人不知道该改哪一处。
        for lineno, line in enumerate(head.splitlines(), 1):
            for match in stale.findall(line):
                fail(errors, f"{path}:{lineno} 的 head 里还写着「{match}」——"
                             f"板块已是 {coverage.get('nodesTotal')} 家"
                             f"（标普 {coverage.get('poolSp500')} + 外国发行人 "
                             f"{coverage.get('poolForeignIssuer')}），这句话是假的")
        # 写了链数或环节数的，必须与数据一致——写死的数字迟早对不上。
        for label, want in (("条一级产业链", coverage.get("chainsTotal")),
                            ("条产业链", coverage.get("chainsTotal")),
                            ("个价值链环节", len(payload.get("stages") or [])),
                            ("个环节", len(payload.get("stages") or []))):
            if want is None:
                continue
            for got in re.findall(r"(\d+)\s*" + label, head):
                if int(got) != want:
                    fail(errors, f"{path} 的 head 里写着「{got} {label}」，"
                                 f"数据是 {want}")


def check_home_card(payload: dict, errors: list[str]) -> None:
    """站点首页那张卡片上印的数，必须等于 nodes.json 里的数。

    首页是静态 HTML，写死的数字不会自己更新，数据一变它就开始说假话且无人报错。
    这个板块栽过同一类跟头（手机上苹果页显示「本页已收录 20245 条」而真值是 0）。

    ## 只钉**结构性**的数

    第一版把公司数和关系条数也钉了进去，结果外国发行人一入池（495 → 500）
    整条数据管道就被这道校验挡住——而那是一次完全正常的数据变化。
    换成分次元件（成分股增减、抽到新名单）都会漂的数，不该由静态文案承担。

    因此改为：卡片上用 `data-sc="<键>"` 显式标出要校验的数，只校验被标出来的；
    公司数与关系条数这类会漂的干脆不印在首页。要加新的数就加标记，
    不标就不查——把「查什么」写在页面上，而不是让校验去猜。
    """
    path = "index.html"
    try:
        with open(path, encoding="utf-8") as handle:
            html = handle.read()
    except OSError:
        return                              # 首页不在就不查，不是本契约的职责
    match = re.search(r'href="apps/supply-chain/"(.*?)</a>', html, re.S)
    if not match:
        fail(errors, f"{path} 里找不到全球产业链的入口卡片")
        return
    card = match.group(1)

    coverage = payload.get("coverage") or {}
    truth = {
        "stages": len(payload.get("stages") or []),
        "chains": coverage.get("chainsTotal"),
        "chainLinks": coverage.get("chainLinksTotal"),
        "chainDepth": coverage.get("chainDepth"),
    }
    marked = re.findall(r'data-sc="([^"]+)"[^>]*>([^<]*)<', card)
    if not marked:
        fail(errors, f"{path} 的产业链卡片一个 data-sc 标记都没有——"
                     "没有标记就没人保证卡片上的数还是真的")
        return
    for key, shown in marked:
        if key not in truth:
            fail(errors, f"{path} 卡片标了未知的键 data-sc={key!r}")
            continue
        want = truth[key]
        if want is None:
            continue
        if shown.strip() != str(want):
            fail(errors, f"{path} 卡片上的{key} 写着 {shown.strip()}，"
                         f"实际是 {want}——静态文案与数据脱节了")


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
    check_chains(payload, errors)
    check_chain_links(payload, errors)
    check_pools(payload, errors)
    check_peers(payload, errors)
    check_home_card(payload, errors)
    check_page_meta(payload, errors)
    check_no_conflict_markers(errors)
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
    stale_list = (payload.get("coverage") or {}).get("edgesFromEarlierScan") or []
    if stale_list:
        print(f"边来自更早扫描（本轮未复现，文件按规矩保留）：{', '.join(stale_list)}")
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
