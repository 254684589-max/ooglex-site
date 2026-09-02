#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成产业链图谱第 0 层：节点表与价值链阶段初步口径。

**只读站内已有数据，不联网、不新增任何数据源。** 节点骨架直接来自
`apps/companies/sp500.json`（站内每日更新的标普成分股清单），不另建第二套事实来源。

## 这一层做什么

回答「每家公司处在产业链的哪一段」，但只到**板块级粗粒度**——因为当前可用的分类
只有 GICS 一级板块（11 类）。按 `docs/SUPPLY_CHAIN_GRAPH.md` 第 5 节的方案 C：
先用初步口径上线并逐节点标注来源，等第 2 层真实上下游边落地后再校正。

## 这一层刻意不做什么

**不产出任何关系边。** 边必须携带可核验的原始申报文件（见 `evidence` 契约），
本层没有任何证据来源，因此 `edges` 恒为空数组。这不是待办事项，是契约：
`assert_edge_contract()` 会在写盘前逐条硬校验，没有 evidence 的边一律拒绝写入。

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


def assert_edge_contract(edges: list[dict]) -> None:
    """无证据不上图：写盘前硬校验，不靠自觉。

    每条边必须携带非空 evidence[]，每条 evidence 必须能点开核验（URL + 文件日期）。
    confidence 只有 disclosed / inferred 两档。任何一条不合格即中止，不写文件——
    宁可不发布，也不发布来路不明的公司间关系。
    """
    allowed_confidence = {"disclosed", "inferred"}
    for i, edge in enumerate(edges):
        where = f"edges[{i}] {edge.get('from')}→{edge.get('to')}"
        if not edge.get("from") or not edge.get("to"):
            raise ValueError(f"{where}：缺少 from / to")
        if edge.get("confidence") not in allowed_confidence:
            raise ValueError(f"{where}：confidence 必须是 {allowed_confidence}，"
                             f"实际 {edge.get('confidence')!r}")
        evidence = edge.get("evidence")
        if not isinstance(evidence, list) or not evidence:
            raise ValueError(f"{where}：没有 evidence，拒绝写入")
        for j, item in enumerate(evidence):
            if not isinstance(item, dict):
                raise ValueError(f"{where} evidence[{j}]：格式错误")
            for field in ("sourceType", "url", "docDate"):
                if not item.get(field):
                    raise ValueError(f"{where} evidence[{j}]：缺少可核验字段 {field}")


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
    edges: list[dict] = []          # 第 0 层没有任何证据来源，恒为空
    assert_edge_contract(edges)     # 契约从第 0 层就生效，不是以后再补

    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    by_stage: dict[str, int] = {}
    for node in nodes:
        key = node.get("stage") or "pending"     # 未判定单独计，不并进任何一段
        by_stage[key] = by_stage.get(key, 0) + 1
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
        "note": ("第 0 层：节点与价值链阶段初步口径。阶段由 GICS 一级板块映射得出，"
                 "属板块级推断。板块横跨多个阶段时不给结论，只给 stageCandidates 候选集——"
                 "「微软=中间制造」即使加歧义标记也是错误断言，"
                 "「微软=待细化（可能：中间制造/品牌整合/平台服务）」才是数据实际支持的说法。本层不产出任何关系边——边必须携带可核验的"
                 "原始申报文件，写盘前逐条硬校验。"),
        "stages": STAGES,
        "nodes": nodes,
        "edges": edges,
        "stagePerformance": stage_performance(members, nodes, source_payload),
        "coverage": {
            "claimComplete": False,
            "nodesTotal": len(nodes),
            "nodesWithEdges": 0,
            "edgesTotal": 0,
            "edgesBySource": {},
            "stageByBasis": {
                "sector-initial": resolved,          # 板块与阶段一一对应，已判定
                "sector-ambiguous": ambiguous,       # 板块横跨多段，只给候选集
                "unknown": unknown,                  # 板块不在映射表内
            },
            "stageResolvedNodes": resolved,
            "stageAmbiguousNodes": ambiguous,
            "note": ("本图谱只收录有公开出处的关系，不是完整供应链。"
                     "当前尚无关系边。"),
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
            "edges": 0,
        },
        "sources": [{
            "id": "sp500-members",
            "name": "站内标普500成分股清单",
            "role": "upstream",
            "status": "healthy",
            "mode": "market",
            "frequency": "daily",
            "asOf": source_payload.get("asOf"),
            "upstream": {"dataset": "companies", "path": SOURCE_PATH},
        }],
        "note": ("第 0 层只依赖站内上游文件，不发起任何外部请求。"
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
    print(f"  关系边 {len(edges)}（第 0 层无证据来源，契约已校验）")
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
