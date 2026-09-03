#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成产业链图谱：节点表、价值链阶段口径，以及关系边的索引。

**本脚本不联网、不自己造边。** 节点骨架来自 `apps/companies/sp500.json`
（站内每日更新的标普成分股清单）；关系边由 `extract_form_sd.py` 从 SEC 申报里抽取后
写在 `apps/supply-chain/edges/` 下，本脚本只负责读取、索引与逐条校验。

## 这一层做什么

1. 回答「每家公司处在产业链的哪一段」。SIC 行业码能判的用 SIC，判不了的退回板块级；
   板块横跨多个阶段时不给结论，只给候选集。
2. 把 `edges/` 下各公司的边汇成 `edgeIndex`，并对**每一条**边跑一遍证据契约。

## 边不内联在 nodes.json 里

一家公司的冶炼厂名单动辄几百条。全塞进 nodes.json，总览页为了看六个环节就得下载
几 MB，而它一条边都不需要。改为每家一个文件、公司页按需拉自己那一个；nodes.json
只留索引，索引里带出处链接，不必先下文件就知道有没有边、边从哪来。

## 契约对每一条边生效，不管它存在哪个文件里

边必须携带可核验的原始申报文件（见 `evidence` 契约）。`assert_edge_contract()` 在写盘前
逐条硬校验所有边文件里的所有边，任何一条不合格即中止，不写文件。

模型「知道」台积电给英伟达代工——但没有出处的行业知识不是数据来源。本脚本不含
任何硬编码的公司间关系。

## 板块级口径的诚实处理

GICS 一级板块粒度明显不够：同属「科技」的英伟达（芯片设计，中间制造）与微软
（软件平台，平台服务）产业链位置完全不同；「医疗健康」同样横跨制药生产、器械
制造与医疗服务。这类板块的节点会被标 `stageAmbiguous: true` 并说明原因，
**页面必须显示这个歧义，不得把板块级推断显示成公司级结论。**

歧义节点数由 `health.json` 跟踪，随 SIC 行业码细化与真实边反推逐步下降。
"""
from __future__ import annotations

import importlib.util
import json
import os
from datetime import datetime, timezone

CONTRACT_VERSION = 1
DATASET = "supply-chain-graph"

SOURCE_PATH = "apps/companies/sp500.json"
# SIC 缓存由 fetch_company_identity.py 联网生成。缺失时自动退回板块级口径——
# 一次取数失败不该让整条管道产出空数据或直接失败。
IDENTITY_PATH = "apps/supply-chain/identity.json"
OUT_DIR = "apps/supply-chain"
NODES_PATH = os.path.join(OUT_DIR, "nodes.json")
HEALTH_PATH = os.path.join(OUT_DIR, "health.json")
# 关系边不内联在 nodes.json 里：一家公司的冶炼厂名单动辄几百条，全塞进来会让
# 总览页为了看六个环节而下载几 MB。改为每家一个文件，公司页按需拉自己那一个。
EDGES_DIR = os.path.join(OUT_DIR, "edges")
SMELTERS_PATH = os.path.join(OUT_DIR, "smelters.json")

# ── 价值链阶段定义 ──────────────────────────────────────────────────────────
STAGES = [
    {"id": "upstream-resource", "label": "上游资源", "labelEn": "Upstream Resources",
     "order": 1, "description": "能源与原材料的开采、初加工"},
    {"id": "intermediate-manufacturing", "label": "中间制造", "labelEn": "Intermediate Manufacturing",
     "order": 2, "description": "零部件、设备与资本品制造"},
    {"id": "brand-integration", "label": "品牌整合", "labelEn": "Brand & Integration",
     "order": 3, "description": "面向终端市场的品牌与系统集成"},
    {"id": "distribution-service", "label": "分销服务", "labelEn": "Distribution & Services",
     "order": 4, "description": "零售、物流与终端服务"},
    {"id": "platform-service", "label": "平台服务", "labelEn": "Platform Services",
     "order": 5, "description": "软件、互联网与通信平台"},
    {"id": "supporting", "label": "支持性行业", "labelEn": "Supporting Industries",
     "order": 6, "description": "金融、地产、公用事业等不直接位于实物链上的行业"},
]
STAGE_IDS = {s["id"] for s in STAGES}

# ── GICS 一级板块 → 价值链阶段的初步映射 ────────────────────────────────────
# 只有板块与阶段一一对应时才给出结论。板块横跨多个阶段时**不给结论**，改为给候选集：
# 「微软 = 中间制造」即使加了歧义标记，也是对一家真实公司的错误断言；
# 「微软 = 待细化（可能：中间制造/品牌整合/平台服务）」才是这份数据实际支持的说法。
# 候选集会随 SIC 行业码或真实上下游边收敛为单一阶段。
SECTOR_STAGE_MAP: dict[str, dict] = {
    "Energy": {"stage": "upstream-resource"},
    "Materials": {"stage": "upstream-resource"},
    "Financials": {"stage": "supporting"},
    "Real Estate": {"stage": "supporting"},
    "Utilities": {"stage": "supporting"},
    "Industrials": {
        "candidates": ["intermediate-manufacturing", "distribution-service"],
        "reason": "工业板块横跨资本品制造与运输物流服务，板块级无法判定单家公司"},
    "Information Technology": {
        "candidates": ["intermediate-manufacturing", "brand-integration", "platform-service"],
        "reason": "科技板块同时含半导体（中间制造）、硬件（品牌整合）与软件（平台服务），"
                  "同板块的英伟达、苹果与微软位置完全不同"},
    "Communication Services": {
        "candidates": ["platform-service", "distribution-service"],
        "reason": "通信服务横跨互联网平台与电信运营"},
    "Consumer Discretionary": {
        "candidates": ["intermediate-manufacturing", "brand-integration", "distribution-service"],
        "reason": "可选消费横跨整车与耐用品制造、品牌与零售分销"},
    "Consumer Staples": {
        "candidates": ["brand-integration", "distribution-service"],
        "reason": "必需消费横跨食品饮料生产与商超分销"},
    "Health Care": {
        "candidates": ["intermediate-manufacturing", "distribution-service"],
        "reason": "医疗健康横跨制药与器械制造和医疗服务"},
}


def load_sic_resolver():
    """载入 SIC → 阶段映射。模块缺失时返回 None，构建退回板块级口径。"""
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "sic_stages.py")
    if not os.path.exists(path):
        return None
    spec = importlib.util.spec_from_file_location("sic_stages", path)
    if spec is None or spec.loader is None:
        return None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_identity() -> dict:
    """读 SIC 缓存。没有就返回空——阶段判定退回板块级，不中断构建。"""
    try:
        with open(IDENTITY_PATH, encoding="utf-8") as handle:
            return (json.load(handle) or {}).get("companies") or {}
    except (OSError, ValueError):
        return {}


def load_edge_files() -> dict[str, dict]:
    """读 edges/ 下每家公司的关系边文件。目录不存在就是「还没有边」，不是错误。"""
    if not os.path.isdir(EDGES_DIR):
        return {}
    loaded: dict[str, dict] = {}
    for name in sorted(os.listdir(EDGES_DIR)):
        if not name.endswith(".json"):
            continue
        path = os.path.join(EDGES_DIR, name)
        try:
            with open(path, encoding="utf-8") as handle:
                payload = json.load(handle)
        except (OSError, ValueError) as exc:
            # 坏文件不能当成「这家没有边」悄悄跳过——那会把故障显示成事实。
            raise SystemExit(f"{path} 读不出来（{exc}），中止构建")
        symbol = payload.get("symbol") or name[:-5]
        if symbol != name[:-5]:
            raise SystemExit(f"{path} 里的 symbol={symbol!r} 与文件名不符，中止")
        loaded[symbol] = payload
    return loaded


def load_form_sd_coverage() -> dict | None:
    """冶炼厂登记表里的覆盖率。没有这个文件就说明抽取器还没跑过。"""
    try:
        with open(SMELTERS_PATH, encoding="utf-8") as handle:
            return (json.load(handle) or {}).get("coverage")
    except (OSError, ValueError):
        return None


def sector_coverage(nodes: list[dict], filing_status: dict[str, str]) -> list[dict]:
    """按板块统计覆盖情况，并区分「没抓到」和「本来就不适用」。

    页面上金融 0/70 与科技 34/84 是两种完全不同的 0。前者是 Form SD 的适用范围
    决定的——规则只管产品中含 3TG 的发行人，银行没有产品；后者是这一轮没抓到，
    以后可能补上。混在一起报，读者会把制度上限误读成抓取缺陷。

    这里只统计事实（这家申报了没有、正文列名单没有），不给「该不该申报」下结论：
    某家公司为什么不申报是它自己的判断，本函数无从得知，也不替它回答。
    """
    buckets: dict[str, dict] = {}
    for node in nodes:
        sector = node.get("sector") or "未分类"
        row = buckets.setdefault(sector, {
            "sector": sector,
            "sectorEn": node.get("sectorEn"),
            "companies": 0,
            "withEdges": 0,
            "filedNoList": 0,
            "noFiling": 0,
            "failed": 0,
            "unscanned": 0,
        })
        row["companies"] += 1
        if node.get("edgeCount"):
            row["withEdges"] += 1
            continue
        state = filing_status.get(node["symbol"])
        if state == "filed-no-list":
            row["filedNoList"] += 1
        elif state == "no-filing":
            row["noFiling"] += 1
        elif state == "failed":
            row["failed"] += 1
        elif state == "listed":
            # 扫描说有名单、但边文件没写成：抽取器与发布路径不一致，属于缺陷，
            # 不能算进「无申报」蒙混过去。
            row["failed"] += 1
        else:
            # 没有逐家状态（抽取器还没跑过带 filingStatus 的版本）。
            # 不猜原因，单列一档。
            row["unscanned"] += 1
    return sorted(buckets.values(), key=lambda r: -r["companies"])


def assert_edge_contract(bundles: dict[str, dict]) -> None:
    """无证据不上图：写盘前硬校验，不靠自觉。

    契约 v2：出处在**文件级**——同一份申报里所有边的出处本就相同，提到文件级之后
    结构上不可能出现某条边指向别的出处或没有出处。每条边则必须有 `row`，
    把核验落到原始文档的具体一行。

    任何一条不合格即中止，不写文件——宁可不发布，也不发布来路不明的公司间关系。
    """
    allowed_confidence = {"disclosed", "inferred"}
    for symbol, bundle in sorted(bundles.items()):
        where = f"edges/{symbol}.json"
        if bundle.get("confidence") not in allowed_confidence:
            raise ValueError(f"{where}：confidence 必须是 {allowed_confidence}，"
                             f"实际 {bundle.get('confidence')!r}")
        if not (bundle.get("relation") or {}).get("label"):
            raise ValueError(f"{where}：缺少 relation.label，边的语义必须随数据发布")
        evidence = bundle.get("evidence")
        if not isinstance(evidence, dict) or not evidence:
            raise ValueError(f"{where}：没有 evidence，拒绝写入")
        for field in ("sourceType", "url", "docDate"):
            if not evidence.get(field):
                raise ValueError(f"{where} evidence：缺少可核验字段 {field}")
        if not str(evidence.get("url")).startswith("https://"):
            raise ValueError(f"{where} evidence：出处必须是可点开的 https 链接")
        for i, edge in enumerate(bundle.get("edges") or []):
            if not edge.get("from"):
                raise ValueError(f"{where} edges[{i}]：缺少 from")
            if not isinstance(edge.get("row"), int) or edge["row"] < 1:
                raise ValueError(f"{where} edges[{i}] {edge.get('from')}：缺少 row 定位")


def load_members() -> tuple[list[dict], dict]:
    with open(SOURCE_PATH, encoding="utf-8") as handle:
        payload = json.load(handle)
    members = payload.get("members") or []
    if not members:
        raise SystemExit(f"{SOURCE_PATH} 里没有成分股，中止（不产出空文件覆盖有效数据）")
    return members, payload


def build_node(member: dict, identity: dict, sic_module) -> dict:
    sector_en = member.get("sector") if member.get("sector") in SECTOR_STAGE_MAP else member.get("sectorEn")
    mapping = SECTOR_STAGE_MAP.get(sector_en or "")
    node = {
        "id": member.get("symbol"),
        "symbol": member.get("symbol"),
        "name": member.get("name"),
        "nameEn": member.get("nameEn"),
        "sector": member.get("sector"),
        "sectorEn": member.get("sectorEn"),
        "marketCap": member.get("marketCap"),
        "logo": member.get("logo"),
        "listed": True,
        # 边要靠 CIK 锚定实体，第 0 层还没有——如实留空，不猜。
        "cik": None,
        "sic": None,
        "sicDescription": None,
    }
    if not mapping:
        # 板块对不上映射表时如实标未知，不塞默认值。
        node["stage"] = None
        node["stageCandidates"] = []
        node["stageBasis"] = "unknown"
        node["stageAmbiguous"] = True
        node["stageNote"] = f"板块 {member.get('sectorEn')!r} 不在映射表中，未判定阶段"
    elif mapping.get("stage"):
        node["stage"] = mapping["stage"]
        node["stageCandidates"] = [mapping["stage"]]
        node["stageBasis"] = "sector-initial"
        node["stageAmbiguous"] = False
    else:
        # 歧义板块不给结论，只给这份数据实际支持的候选集。
        node["stage"] = None
        node["stageCandidates"] = list(mapping["candidates"])
        node["stageBasis"] = "sector-ambiguous"
        node["stageAmbiguous"] = True
        node["stageNote"] = mapping["reason"]

    # ── SIC 升级：板块级判不出来的，用 SEC 行业码再判一次 ──────────────────
    # 只在 SIC 能给出结论时覆盖，且如实记录依据；SIC 判不了就保留板块级结果。
    record = identity.get(node["symbol"]) or {}
    if record.get("cik"):
        node["cik"] = int(record["cik"])
    if record.get("sic"):
        node["sic"] = int(record["sic"])
        node["sicDescription"] = record.get("sicDescription")
    resolved = sic_module.resolve(record.get("sic")) if sic_module else None
    if resolved:
        node["stage"] = resolved["stage"]
        node["stageCandidates"] = [resolved["stage"]]
        node["stageBasis"] = "sic-refined"
        node["stageAmbiguous"] = False
        node["stageNote"] = f"SIC {resolved['sic']}：{resolved['reason']}"
        node["stageEvidence"] = {
            "sourceType": "sec-submissions-sic",
            "url": f"https://data.sec.gov/submissions/CIK{int(record['cik']):010d}.json"
                   if record.get("cik") else None,
            "sic": resolved["sic"],
            "match": resolved["basis"],
        }
    return node


def stage_performance(members: list[dict], nodes: list[dict], source_payload: dict) -> dict:
    """各产业链环节今日表现：把已判定阶段的公司按环节汇总当日涨跌。

    只做汇总，不重算行情——价格与涨跌全部沿用站内 `sp500.json` 已有的值，
    口径、来源与数据日跟着它走，不另建第二套事实来源。

    诚实要求：
    - 阶段未判定（`pending`）的公司不进任何环节，单独计数，**不摊到别处**；
    - 报价过期（`stale`）的不计入均值，单独计数——过期值混进均值会伪造当日表现；
    - 同时给等权与市值加权两个口径并标明，不用其中一个冒充「该环节表现」。
    """
    stage_of = {n["symbol"]: n.get("stage") for n in nodes}
    buckets: dict[str, list[dict]] = {}
    pending = stale = no_quote = 0
    for member in members:
        symbol = member.get("symbol")
        stage = stage_of.get(symbol)
        if not stage:
            pending += 1
            continue
        change = member.get("changePct")
        if change is None:
            no_quote += 1
            continue
        if member.get("stale"):
            stale += 1
            continue
        buckets.setdefault(stage, []).append(
            {"changePct": float(change), "marketCap": float(member.get("marketCap") or 0.0)})

    rows = []
    for stage in STAGES:
        items = buckets.get(stage["id"]) or []
        if not items:
            rows.append({"stage": stage["id"], "label": stage["label"], "companies": 0,
                         "equalWeightPct": None, "capWeightPct": None, "medianPct": None})
            continue
        changes = sorted(item["changePct"] for item in items)
        cap_total = sum(item["marketCap"] for item in items)
        middle = len(changes) // 2
        median = (changes[middle] if len(changes) % 2
                  else (changes[middle - 1] + changes[middle]) / 2)
        rows.append({
            "stage": stage["id"],
            "label": stage["label"],
            "companies": len(items),
            "equalWeightPct": round(sum(changes) / len(changes), 2),
            "capWeightPct": (round(sum(i["changePct"] * i["marketCap"] for i in items) / cap_total, 2)
                             if cap_total > 0 else None),
            "medianPct": round(median, 2),
        })
    return {
        "asOf": source_payload.get("asOf"),
        "source": "站内 apps/companies/sp500.json",
        "method": ("按价值链环节汇总当日涨跌；等权与市值加权并列给出，不互相冒充。"
                   "行情值沿用站内成分股文件，未重算。"),
        "stages": rows,
        "excluded": {
            "stageNotResolved": pending,   # 阶段未判定，不摊入任何环节
            "staleQuote": stale,           # 报价过期，不计入均值
            "noQuote": no_quote,
        },
    }


def build() -> None:
    members, source_payload = load_members()
    identity = load_identity()
    sic_module = load_sic_resolver()
    nodes = [build_node(m, identity, sic_module) for m in members if m.get("symbol")]

    # 关系边：抽取器写在 edges/ 下，本脚本只读、只索引、只校验，不自己造边。
    edge_files = load_edge_files()
    all_edges = [e for payload in edge_files.values() for e in (payload.get("edges") or [])]
    assert_edge_contract(edge_files)  # 契约对每个边文件与其每一条边生效

    edge_index: dict[str, dict] = {}
    edges_by_source: dict[str, int] = {}
    for symbol, payload in sorted(edge_files.items()):
        rows = payload.get("edges") or []
        evidence = payload.get("evidence") or {}
        edge_index[symbol] = {
            "file": f"edges/{symbol}.json",
            "count": len(rows),
            "relation": (payload.get("relation") or {}).get("id"),
            "filingDate": evidence.get("filingDate"),
            "url": evidence.get("url"),
        }
        key = evidence.get("sourceType") or "unknown"
        edges_by_source[key] = edges_by_source.get(key, 0) + len(rows)
    node_ids = {n["id"] for n in nodes}
    for node in nodes:
        node["edgeCount"] = edge_index.get(node["id"], {}).get("count", 0)
    orphans = sorted(set(edge_index) - node_ids)
    if orphans:
        # 边文件指向节点表里没有的公司：多半是成分股调整后遗留的旧文件。
        # 留着会让公司页显示一份不再属于任何节点的名单。
        raise SystemExit(f"边文件 {orphans} 不在节点表中，中止（请删除或重跑抽取器）")

    form_sd_coverage = load_form_sd_coverage()

    # 逐家申报状态盖到节点上，再按板块汇总。这是为了回答一个具体问题：
    # 「为什么有的公司有数据、有的没有」。金融 0/70、房地产 0/29 不是抓取失败——
    # Form SD 只适用于产品中含 3TG 的发行人，银行和 REIT 没有产品，本来就不申报。
    # 把这件事算出来写进数据，而不是在页面上凭印象断言。
    filing_status = (form_sd_coverage or {}).get("filingStatus") or {}
    for node in nodes:
        state = filing_status.get(node["symbol"])
        if state:
            node["formSdStatus"] = state
    by_sector = sector_coverage(nodes, filing_status)

    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    by_stage: dict[str, int] = {}
    for node in nodes:
        key = node.get("stage") or "pending"     # 未判定单独计，不并进任何一段
        by_stage[key] = by_stage.get(key, 0) + 1
    by_basis: dict[str, int] = {}
    for node in nodes:
        key = node.get("stageBasis") or "unknown"
        by_basis[key] = by_basis.get(key, 0) + 1
    resolved = sum(1 for n in nodes if n.get("stage"))
    ambiguous = sum(1 for n in nodes if n.get("stageBasis") == "sector-ambiguous")
    unknown = sum(1 for n in nodes if n.get("stageBasis") == "unknown")

    payload = {
        "contractVersion": CONTRACT_VERSION,
        "dataset": DATASET,
        "updatedAt": now,
        "asOf": source_payload.get("asOf"),
        "frequency": "daily",
        "status": "ok",
        "source": "站内 apps/companies/sp500.json",
        "sourceUpstream": source_payload.get("listSource"),
        "note": ("节点与价值链阶段口径。阶段由 GICS 一级板块映射得出，"
                 "属板块级推断。板块横跨多个阶段时不给结论，只给 stageCandidates 候选集——"
                 "「微软=中间制造」即使加歧义标记也是错误断言，"
                 "「微软=待细化（可能：中间制造/品牌整合/平台服务）」才是数据实际支持的说法。"
                 "关系边不内联在本文件里，按公司分文件放在 edges/ 下、由 edgeIndex 索引——"
                 "一家公司的冶炼厂名单动辄几百条，内联会让总览页为看六个环节下载几 MB。"
                 "每条边都必须携带可核验的原始申报文件，写盘前逐条硬校验。"),
        "stages": STAGES,
        "nodes": nodes,
        # 每家一个文件，公司页按需拉。索引里带出处链接，不必先下文件才知道有没有边。
        "edgeIndex": edge_index,
        "stagePerformance": stage_performance(members, nodes, source_payload),
        "coverage": {
            "claimComplete": False,
            "nodesTotal": len(nodes),
            "nodesWithEdges": sum(1 for n in nodes if n["edgeCount"]),
            "edgesTotal": len(all_edges),
            "edgesBySource": edges_by_source,
            # 抽取器实测到的申报形态。「有申报无名单」必须与「无申报」分开——
            # Form SD 强制申报、不强制列名单，两者混在一起会把披露制度的上限
            # 说成抓取失败。
            "formSd": form_sd_coverage,
            # 按板块拆开的覆盖情况。缺口的成因写在数据里，页面照实读。
            "bySector": by_sector,
            # 按实际 stageBasis 分组。曾经把所有已判定的都记成 sector-initial，
            # 等于把 SIC 升级的功劳记在板块级口径头上、低报了数据质量的真实来源。
            "stageByBasis": by_basis,
            "stageResolvedNodes": resolved,
            "stageAmbiguousNodes": ambiguous,
            "note": ("本图谱只收录有公开出处的关系，不是完整供应链。"
                     + ("当前尚无关系边。" if not all_edges else
                        f"当前 {len(all_edges)} 条边全部来自 Form SD 冲突矿产申报，"
                        f"语义是「该冶炼厂出现在申报人的供应链中」——间接、不含份额、"
                        f"不含层级，不等于直接供货关系。")),
        },
        "dataQuality": {
            "contractVersion": CONTRACT_VERSION,
            "status": "ok",
            "total": len(nodes),
            "byStage": by_stage,
            "resolvedStage": resolved,
            "ambiguousStage": ambiguous,
            "unknownStage": unknown,
        },
    }

    health = {
        "contractVersion": CONTRACT_VERSION,
        "dataset": DATASET,
        "generatedAt": now,
        # 歧义不是故障：这是板块级数据的真实上限，如实报告即可。
        # 只有板块对不上映射表（unknown）才是需要修的问题。
        "status": "healthy" if unknown == 0 else "degraded",
        "historyStatus": "migrated",     # 首次建立，无历史可追溯
        "lastAttemptAt": now,
        "lastSuccessfulAt": now,
        "consecutiveFailures": 0,
        "failureReason": None,
        "coverage": {
            "expectedNodes": len(members),
            "publishedNodes": len(nodes),
            "stageResolvedPct": round(100.0 * resolved / len(nodes), 1) if nodes else 0.0,
            "stageAmbiguousPct": round(100.0 * ambiguous / len(nodes), 1) if nodes else 0.0,
            "edges": len(all_edges),
            "companiesWithEdges": len(edge_index),
        },
        "sources": ([{
            "id": "form-sd-smelters",
            "name": "SEC EDGAR Form SD 冲突矿产申报",
            "role": "edges",
            "status": "healthy",
            "mode": "filing",
            "frequency": "annual",
            "asOf": None,
            "upstream": {"dataset": "supply-chain-edges", "path": EDGES_DIR},
        }] if edge_index else []) + [{
            "id": "sp500-members",
            "name": "站内标普500成分股清单",
            "role": "upstream",
            "status": "healthy",
            "mode": "market",
            "frequency": "daily",
            "asOf": source_payload.get("asOf"),
            "upstream": {"dataset": "companies", "path": SOURCE_PATH},
        }],
        "note": ("构建脚本本身不发起外部请求，只读站内上游文件与抽取器产出的边文件。"
                 "stageAmbiguousPct 随 SIC 行业码细化与真实边反推逐步下降。"),
    }

    os.makedirs(OUT_DIR, exist_ok=True)
    for path, data in ((NODES_PATH, payload), (HEALTH_PATH, health)):
        with open(path, "w", encoding="utf-8") as handle:
            json.dump(data, handle, ensure_ascii=False, indent=2)
            handle.write("\n")

    print(f"节点 {len(nodes)} 个 → {NODES_PATH}")
    print(f"  阶段分布：{by_stage}")
    print(f"  已判定阶段 {resolved}（{health['coverage']['stageResolvedPct']}%）；"
          f"仅给候选集 {ambiguous}；板块未登记 {unknown}")
    print(f"  口径来源：{by_basis}")
    print(f"  关系边 {len(all_edges)} 条，来自 {len(edge_index)} 家公司的边文件"
          f"（契约已逐条校验）")
    if edges_by_source:
        print(f"  边的出处：{edges_by_source}")
    if form_sd_coverage:
        print(f"  Form SD：有名单 {form_sd_coverage.get('companiesWithList')} 家 · "
              f"有申报无名单 {form_sd_coverage.get('companiesFiledNoList')} 家 · "
              f"无申报 {form_sd_coverage.get('companiesNoFiling')} 家")
    perf = payload["stagePerformance"]
    active = [r for r in perf["stages"] if r["companies"]]
    print(f"  环节表现：{len(active)} 个环节有报价；"
          f"未判定阶段 {perf['excluded']['stageNotResolved']} 家不摊入、"
          f"过期报价 {perf['excluded']['staleQuote']} 家不计入均值")
    for row in active:
        print(f"    {row['label']:<6} {row['companies']:>3} 家  "
              f"等权 {row['equalWeightPct']:>6}%  市值加权 {row['capWeightPct']:>6}%  "
              f"中位 {row['medianPct']:>6}%")
    print(f"健康 → {HEALTH_PATH}  status={health['status']}")


if __name__ == "__main__":
    build()
