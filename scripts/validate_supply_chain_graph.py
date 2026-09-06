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
FOREIGN_PATH = "apps/supply-chain/foreign.json"
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
        # **三个池，三栏，各按各自唯一可用的维度拆。**
        #
        #   bySector    仅 sp500       按 GICS 板块（只有这一池有）
        #   byCountry   外国发行人      按经营地
        #   bySicMajor  本土 10-K 申报人 按 SIC 大类（板块与国别两样都没有）
        #
        # 把没有板块的池算进「未分类」，等于造一个几千家的黑箱，还会把
        # 「金融 0/70」这类制度上限的解释稀释掉。**三栏加起来才是全池。**
        #
        # 这里用白名单（== sp500）而不是黑名单（!= 外国发行人）：本轮加第三池时
        # 黑名单悄悄把 4,210 家吞进了「未分类」，跑完 41 分钟才被下面那条
        # 合计校验拦下。**判据要说「收谁」，不要说「除了谁」**——
        # 加一个池，黑名单就错一次，白名单只会漏报、不会误收。
        actual: dict[str, dict[str, int]] = {}
        for node in nodes:
            if node.get("pool") != "sp500":
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
        # 比对的是 **geoCountry（经营地）**，不是 country（注册地）。
        # 注册地那一栏第一名是开曼群岛 340 家，它回答不了「这条产业链在哪」；
        # 汇总改口径之后这里也得跟着改——否则这道校验会拿旧口径去卡新数据，
        # 报出一堆「多报了国别 X」，看着像数据错，其实是校验没跟上。
        truth_country: dict[str, int] = {}
        for node in nodes:
            if node.get("pool") != "sec-foreign-issuer":
                continue
            key = node.get("geoCountry") or node.get("country") or "未分类"
            truth_country[key] = truth_country.get(key, 0) + 1
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

    # ── 第三栏：本土 10-K 申报人按 SIC 大类 ──────────────────────────────
    by_sic = coverage.get("bySicMajor")
    if by_sic is not None:
        if not isinstance(by_sic, list):
            fail(errors, "coverage.bySicMajor 必须是数组")
            return
        truth_sic: dict[str, int] = {}
        for node in nodes:
            if node.get("pool") != "sec-domestic-filer":
                continue
            key = node.get("sicMajorLabel") or "未分类"
            truth_sic[key] = truth_sic.get(key, 0) + 1
        for row in by_sic:
            name = row.get("sector")          # 字段名复用，语义是行业大类
            if name not in truth_sic:
                fail(errors, f"coverage.bySicMajor 多报了行业大类「{name}」，节点表里没有")
            elif row.get("companies") != truth_sic[name]:
                fail(errors, f"coverage.bySicMajor[{name}] 报告 {row.get('companies')}，"
                             f"实际 {truth_sic[name]}")
        for name in sorted(set(truth_sic) - {r.get("sector") for r in by_sic}):
            fail(errors, f"coverage.bySicMajor 漏了行业大类「{name}」")

    # ── 规模轴：全池按申报人类别 ─────────────────────────────────────────
    # **这一栏与上面三栏不是一回事**：三栏是把全池切成互不重叠的三份
    # （标普/外国/本土），加起来等于全池；这一栏是**同一批公司换一把尺子量**，
    # 它自己就覆盖全池。合计校验里不能把它算进去，否则会重复计数。
    by_cat = coverage.get("byFilerCategory")
    if by_cat is not None:
        if not isinstance(by_cat, list):
            fail(errors, "coverage.byFilerCategory 必须是数组")
            return
        # **这条轴按拆好的档位分，不按 SEC 的原串。** SEC 的 category 是
        # "A<br>B<br>C" 拼串，直接当轴用会把 HTML 标记印到屏幕上、把同一个档
        # 拆成好几行、还把「小型申报公司」「新兴成长公司」这两种**不是规模**
        # 的身份混进规模轴。拆分在 build_chain_nodes.split_filer_category，
        # 这里守住它的产物不许再退回原串。
        truth_cat: dict[str, int] = {}
        for node in nodes:
            key = node.get("filerTier") or "未分类"
            truth_cat[key] = truth_cat.get(key, 0) + 1
        for name in truth_cat:
            if "<br>" in name or "<" in name:
                fail(errors, f"申报人档位「{name}」里带着 HTML 标记——"
                             f"SEC 原串没拆就当轴用了，这一格会原样印到屏幕上")
            if name not in TIERS_OK:
                fail(errors, f"申报人档位「{name}」不在允许集 {sorted(TIERS_OK)}——"
                             f"这条轴只能是公众持股量档位，"
                             f"「小型申报公司」「新兴成长公司」是另外两种身份，不占轴")
        # 两个旗标各自独立，且**不得与档位相互覆盖**：一家公司可以既是
        # 非加速申报人又是小型申报公司，那是两件事同时成立，不是矛盾。
        for node in nodes:
            for flag in ("smallerReporting", "emergingGrowth"):
                if node.get(flag) is not None and not isinstance(node[flag], bool):
                    fail(errors, f"{node.get('symbol')}.{flag} 必须是布尔值，"
                                 f"实际 {node[flag]!r}")
                    break
        for row in by_cat:
            name = row.get("sector")          # 字段名复用，语义是申报人类别
            if name not in truth_cat:
                fail(errors, f"coverage.byFilerCategory 多报了类别「{name}」，节点表里没有")
            elif row.get("companies") != truth_cat[name]:
                fail(errors, f"coverage.byFilerCategory[{name}] 报告 "
                             f"{row.get('companies')}，实际 {truth_cat[name]}")
        for name in sorted(set(truth_cat) - {r.get("sector") for r in by_cat}):
            fail(errors, f"coverage.byFilerCategory 漏了类别「{name}」")
        total_cat = sum(r.get("companies") or 0 for r in by_cat)
        if total_cat != len(nodes):
            fail(errors, f"按申报人类别合计 {total_cat} 家 ≠ 全池 {len(nodes)} 家——"
                         "这一栏量的是同一批公司，必须覆盖全池")

    # 三栏之和必须等于全池。差一家就说明有公司三栏都没进——页面上它就消失了。
    # **每加一个池就要在这里加一项**，否则这条校验会把新池报成「消失的公司」。
    if by_sector is not None:
        shown = sum(sum(r.get("companies") or 0 for r in (col or []))
                    for col in (by_sector, by_country, by_sic))
        if shown != len(nodes):
            fail(errors, f"按板块 + 按经营地 + 按行业大类 合计 {shown} 家，"
                         f"全池 {len(nodes)} 家——有公司哪一栏都没进，页面上会直接消失")


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


# 允许的公司池。**加新池必须同时改这里**——2026-09-06 扩到第三池时忘了，
# 数据全跑完（取数 27 分钟、抽取器 16 分钟）才被这道校验拦下，白跑一轮。
# 拦得对：契约不认识的数据本来就不该发布。教训写在这儿，下次加池先看这行。
# 规模轴只能取这五个值：三个公众持股量档位，加上两种「没有档位」的说明。
# 加新值必须同时改构建脚本的 split_filer_category 与页面的档位说明——
# 三处任一处漏改，页面上就会出现一个没人解释过的档。
TIERS_OK = frozenset({"大型加速申报人", "加速申报人", "非加速申报人",
                      "未标注档位", "未分类"})

POOLS = ("sp500", "sec-foreign-issuer", "sec-domestic-filer")

# 没有站内报价的池。站内行情管道只覆盖标普成分股，其余两池一律 marketCap=None。
POOLS_WITHOUT_QUOTE = ("sec-foreign-issuer", "sec-domestic-filer")


def check_pools(payload: dict, errors: list[str]) -> None:
    """三个公司池的契约。守的是「哪些数适用于哪一批公司」不被混起来。

    标普那 495 家有站内报价，外国私人发行人与本土 10-K 申报人都没有。
    把三批合成一个数，读者会以为它们都有市值与当日涨跌——而市值合计与
    环节涨跌的分母里根本没有后两者。所以三个池必须分开计数，且
    **无报价池的 marketCap 必须是 null，不能是 0**：0 会被市值加权当成真值。
    """
    nodes = payload.get("nodes") or []
    if not nodes:
        return
    coverage = payload.get("coverage") or {}
    pools: dict[str, int] = {}
    for node in nodes:
        pool = node.get("pool")
        if pool not in POOLS:
            fail(errors, f"{node.get('symbol')} 的 pool 是 {pool!r}，"
                         f"只能是 {'、'.join(POOLS)}")
            continue
        pools[pool] = pools.get(pool, 0) + 1
        if pool in POOLS_WITHOUT_QUOTE:
            if node.get("marketCap") is not None:
                fail(errors, f"{node.get('symbol')}（{pool}）带了市值 "
                             f"{node.get('marketCap')!r}——站内没有它的报价，"
                             "写进去就是造数")
            if not node.get("cik"):
                fail(errors, f"{node.get('symbol')}（{pool}）没有 CIK，"
                             "它是这批公司唯一的实体锚点")

    for key, pool in (("poolSp500", "sp500"),
                      ("poolForeignIssuer", "sec-foreign-issuer"),
                      ("poolDomesticFiler", "sec-domestic-filer")):
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
        # 这一项只统计外国发行人池——本土池与标普池的中文名各有来源，
        # 混进来会让「对照表覆盖了多少」这个数说不清是谁的覆盖。
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


def check_form_sd_flag(payload: dict, errors: list[str]) -> None:
    """索引扫到「报过 Form SD」的公司，抽取器不能说它「无申报」。

    两个来源各扫各的：`fetch_foreign_identity.py` 扫的是季度全量索引（近四个
    季度），`extract_form_sd.py` 逐家取 submissions（全量历史）。**全量历史是
    近四季的超集**，所以方向是单向的——

        索引说报过 ⟹ 抽取器不能说「从未申报」（说了就是漏了一份文件）
        索引说没报 ⇏ 抽取器一定说没报（四个季度之前报的，索引本来就看不到）

    只钉住有方向的那一半。反过来钉就会把「更早年份报过」误判成错误。

    这条是扩池到全量外国私人发行人的配套：一千多家被标成「未报 Form SD、
    规则不适用」并据此从覆盖率分母里排除，那个标记要是错的，排除就是在
    粉饰覆盖率。
    """
    try:
        with open(FOREIGN_PATH, encoding="utf-8") as handle:
            companies = (json.load(handle) or {}).get("companies") or {}
    except (OSError, ValueError):
        return                                     # 还没跑过取数就跳过
    flagged = {s for s, v in companies.items() if v.get("filesFormSd")}
    if not flagged:
        # 整份文件一个都没标，说明还是改造前的旧产物。不当作错误，但要说出来，
        # 免得这条校验静默地什么都没查——静默通过等于这条断言不存在。
        print("[--] foreign.json 里没有 filesFormSd 标记（旧版产物），"
              "索引↔抽取器的交叉校验本轮跳过")
        return
    status = {n.get("symbol"): n.get("formSdStatus")
              for n in (payload.get("nodes") or [])}
    bad = sorted(s for s in flagged if status.get(s) == "no-filing")
    if bad:
        fail(errors, f"{len(bad)} 家在季度索引里报过 Form SD，抽取器却判为「无申报」，"
                     f"说明漏读了申报：{'、'.join(bad[:8])}")
    print(f"索引↔抽取器交叉校验：{len(flagged)} 家标了报过 Form SD，"
          f"其中被判「无申报」的 {len(bad)} 家")


# 多德-弗兰克法案 §1502 / SEC Rule 13p-1 的受涵盖国家：刚果民主共和国
# 及与之接壤的九国。**这里独立写一份，不从构建脚本 import。** 共用一份常量
# 的话，改错了两边一起错、校验照样通过；分开写，任何一侧的改动都要在两个
# 地方同时说明理由才过得去——法定清单值得这个代价。
COVERED_STATUTORY = frozenset({
    "刚果（金）", "安哥拉", "布隆迪", "中非", "刚果（布）",
    "卢旺达", "南苏丹", "坦桑尼亚", "乌干达", "赞比亚",
})


def load_bundles(payload: dict) -> dict:
    """按 edgeIndex 读出全部边文件。读不出来的跳过——check_edges 已经报过了，
    这里再报一遍只会让同一个问题刷两屏。"""
    out: dict = {}
    for symbol in (payload.get("edgeIndex") or {}):
        path = os.path.join(EDGES_DIR, f"{symbol}.json")
        try:
            with open(path, encoding="utf-8") as handle:
                out[symbol] = json.load(handle)
        except (OSError, ValueError):
            continue
    return out


def check_covered_countries(payload: dict, bundles: dict, errors: list[str]) -> None:
    """受涵盖国家：这套数据的法定理由，清单不许悄悄变。"""
    cc = payload.get("coveredCountries")
    if not isinstance(cc, dict):
        fail(errors, "缺少 coveredCountries——Form SD 的立法依据是 §1502，"
                     "页面靠这一份说明这批数据为什么存在")
        return
    rows = cc.get("byCountry") or []
    listed = {r.get("country") for r in rows}
    extra = listed - COVERED_STATUTORY
    missing = COVERED_STATUTORY - listed
    if extra:
        fail(errors, f"coveredCountries 多了非法定国家 {sorted(extra)}——"
                     f"这是 §1502 的法定清单，不能自行增补")
    if missing:
        fail(errors, f"coveredCountries 少了法定国家 {sorted(missing)}——"
                     f"数据里没出现也要列出来，读者才知道清单有十国")
    if cc.get("countries") != len(COVERED_STATUTORY):
        fail(errors, f"coveredCountries.countries = {cc.get('countries')}，"
                     f"法定是 {len(COVERED_STATUTORY)} 国")
    # 逐国比对边数与申报人数，口径与 countryExposure 必须一致。
    truth_edges: dict[str, int] = {}
    truth_filers: dict[str, set] = {}
    for symbol, bundle in (bundles or {}).items():
        for edge in bundle.get("edges") or []:
            country = edge.get("country")
            if country in COVERED_STATUTORY:
                truth_edges[country] = truth_edges.get(country, 0) + 1
                truth_filers.setdefault(country, set()).add(symbol)
    for row in rows:
        name = row.get("country")
        if row.get("edges") != truth_edges.get(name, 0):
            fail(errors, f"coveredCountries[{name}].edges = {row.get('edges')}，"
                         f"实际 {truth_edges.get(name, 0)}")
        if row.get("filerCount") != len(truth_filers.get(name, ())):
            fail(errors, f"coveredCountries[{name}].filerCount = "
                         f"{row.get('filerCount')}，实际 "
                         f"{len(truth_filers.get(name, ()))}")
    if cc.get("edges") != sum(truth_edges.values()):
        fail(errors, f"coveredCountries.edges = {cc.get('edges')}，"
                     f"实际 {sum(truth_edges.values())}")
    if not str(cc.get("basis") or "").strip():
        fail(errors, "coveredCountries.basis 为空——法定依据必须随数据发布，"
                     "否则页面无从说明这十国凭什么单列")
    print(f"[OK] 受涵盖国家：法定 {cc.get('countries')} 国，本轮数据出现 "
          f"{cc.get('countriesSeen')} 国 · 冶炼厂 {cc.get('smelters')} 家 · "
          f"关系 {cc.get('edges')} 条 · 申报人 {cc.get('filerCount')} 家")


def check_country_names(bundles: dict, errors: list[str]) -> None:
    """**没有一个国别可以带着英文原文发布。**

    `match_country` 有一条「认得出是国家但没有译名，照原文写」的分支，
    设计上是诚实的兜底。但它一旦真的被走到，页面上就会出现
    "CONGO, DEMOCRATIC REPUBLIC OF THE" 这样的行——而且同一个国家的四种
    大小写写法各算一行，刚果（金）因此在国别榜上被拆开，哪一行都不排名。

    实测就是这么发生的：75 条边、5 种写法，全是受涵盖国家。所以兜底保留，
    但**发布侧一条都不许有**：真出现了，就该去补国别表，而不是让它上线。
    """
    seen: dict[str, int] = {}
    for bundle in (bundles or {}).values():
        for edge in bundle.get("edges") or []:
            country = edge.get("country")
            if country and not re.search(r"[一-鿿]", str(country)):
                seen[country] = seen.get(country, 0) + 1
    for name, count in sorted(seen.items(), key=lambda kv: -kv[1]):
        fail(errors, f"国别「{name}」{count} 条带着英文原文发布——"
                     f"去 form_sd_parse.COUNTRIES 补这个写法，别让它上页面")


def check_smelter_reach(payload: dict, errors: list[str]) -> None:
    """链条另一端的可达性读数——**这是这份数据的边界，不能悄悄消失**。

    冶炼厂那一端有 1,767 家，其中能对上池内公司的只有个位数。页面靠这一份
    在每个国别后面写「N 厂 · 均不在池内」，读者才看得出这张图到冶炼厂这一层
    为止、点不下去。这一份一旦不产出，页面那一格连同它承载的界线一起消失，
    **而页面不会报错**——所以在发布契约里硬性要求，不给「没有就跳过」的余地。

    校验的是它与登记表、节点表对不对得上，不是它数得大不大：
    reach 只会因为匹配放宽而变大，而放宽匹配正是**最容易把「同名」说成
    「同一家」的地方**，所以 inPool 必须逐条能在节点表里找到落点。
    """
    reach = payload.get("smelterReach")
    if not isinstance(reach, dict):
        fail(errors, "缺少 smelterReach——冶炼厂那一端的可达性读数是页面"
                     "「均不在池内」那一格的唯一来源，不产出等于悄悄抹掉这条界线")
        return
    registry = payload.get("smelters") or payload.get("smelterRegistry") or []
    if isinstance(registry, dict):
        registry = list(registry.values())
    if registry and reach.get("smeltersTotal") != len(registry):
        fail(errors, f"smelterReach.smeltersTotal = {reach.get('smeltersTotal')}，"
                     f"登记表实际 {len(registry)} 条")
    in_pool = reach.get("smeltersInPool")
    total = reach.get("smeltersTotal") or 0
    if not isinstance(in_pool, int) or in_pool < 0 or in_pool > total:
        fail(errors, f"smelterReach.smeltersInPool = {in_pool!r}，"
                     f"必须是 0~{total} 的整数")
    symbols = {n.get("symbol") for n in (payload.get("nodes") or [])}
    for sym in (reach.get("companies") or []):
        if isinstance(sym, str) and sym not in symbols:
            fail(errors, f"smelterReach.companies 里的「{sym}」不在节点表里——"
                         f"匹配放宽把不在池里的名字算成了池内公司")
    rows = reach.get("byCountry") or []
    if not isinstance(rows, list):
        fail(errors, "smelterReach.byCountry 必须是列表")
        return
    seen: set = set()
    for row in rows:
        country = row.get("country")
        if country in seen:
            fail(errors, f"smelterReach.byCountry 里「{country}」出现了两次")
        seen.add(country)
        if (row.get("inPool") or 0) > (row.get("smelters") or 0):
            fail(errors, f"smelterReach「{country}」在池内的冶炼厂 {row.get('inPool')} "
                         f"家，比该国冶炼厂总数 {row.get('smelters')} 家还多")
    if rows and sum(r.get("inPool") or 0 for r in rows) != in_pool:
        fail(errors, f"smelterReach 各国在池内合计 "
                     f"{sum(r.get('inPool') or 0 for r in rows)}，与总数 {in_pool} 不符")
    print(f"[OK] 冶炼厂可达性：{total} 家里 {in_pool} 条对上池内公司"
          f"（去重 {reach.get('distinctCompanies')} 家），按国别 {len(rows)} 行")


def check_chain_risk(payload: dict, errors: list[str]) -> None:
    """按链切的风险读数，口径必须与全局那份一致。

    页面筛到某条链时用这一份。它最容易出的错不是算错，而是**口径悄悄变宽**：
    分母混进没有名单的公司、集中度收进只被一家列入的厂——两者都会把这条链的
    风险说得比实际大，而页面上看不出来。
    """
    risk = payload.get("chainRisk")
    if risk is None:
        print("[--] 没有 chainRisk（构建脚本还没产出这一份），本轮跳过按链风险校验")
        return
    if not isinstance(risk, dict):
        fail(errors, "chainRisk 必须是对象（链 id → 读数）")
        return
    known = {c.get("id") for c in (payload.get("chains") or [])}
    nodes = payload.get("nodes") or []
    # 每条链里**有名单**的公司数——按链风险的分母只能是它
    truth: dict[str, int] = {}
    for node in nodes:
        if not node.get("edgeCount"):
            continue
        for cid in (node.get("chains") or []):
            truth[cid] = truth.get(cid, 0) + 1
    for cid, row in risk.items():
        if cid not in known:
            fail(errors, f"chainRisk 里的「{cid}」不在 chains 列表里")
            continue
        if row.get("filers") != truth.get(cid):
            fail(errors, f"chainRisk[{cid}].filers = {row.get('filers')}，"
                         f"实际这条链里有名单的公司 {truth.get(cid)} 家")
        for item in (row.get("concentration") or []):
            if (item.get("filerCount") or 0) < 2:
                fail(errors, f"chainRisk[{cid}] 收了只被 {item.get('filerCount')} "
                             f"家列入的冶炼厂——「集中」的口径是 ≥2，与全局那份必须一致")
                break
            if len(item.get("filers") or []) != item.get("filerCount"):
                fail(errors, f"chainRisk[{cid}] 某条 filerCount 与 filers 长度不符")
                break
        if len(row.get("exposure") or []) > (row.get("exposureTotal") or 0):
            fail(errors, f"chainRisk[{cid}] 列出的国别比总数还多")
        # 按链的流向：带子加起来必须等于这条链的关系数。对不上就说明桑基画的
        # 是另一批边——而图上看不出来，读者只会以为这条链就这么点流量。
        flow = row.get("flow") or {}
        if flow:
            drawn = sum(st.get("total") or 0 for st in (flow.get("stages") or []))
            if drawn != row.get("edges"):
                fail(errors, f"chainRisk[{cid}].flow 带子合计 {drawn} ≠ "
                             f"这条链的关系数 {row.get('edges')}")
    with_flow = sum(1 for r in risk.values() if r.get("flow"))
    print(f"按链风险：{len(risk)} 条链（{with_flow} 条带流向图），分母、集中度与流向合计均与全局一致")


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
    check_form_sd_flag(payload, errors)
    check_chain_risk(payload, errors)
    check_smelter_reach(payload, errors)
    bundles = load_bundles(payload)
    check_covered_countries(payload, bundles, errors)
    check_country_names(bundles, errors)
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
