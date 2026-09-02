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
    counts = {"resolved": 0, "ambiguous": 0, "unknown": 0}
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
    edges = payload.get("edges")
    if not isinstance(edges, list):
        fail(errors, "edges 必须是数组")
        return 0
    node_ids = {n.get("id") for n in payload.get("nodes") or []}
    for i, edge in enumerate(edges):
        where = f"edges[{i}] {edge.get('from')}→{edge.get('to')}"
        if not edge.get("from") or not edge.get("to"):
            fail(errors, f"{where}：缺少 from / to")
        for end in ("from", "to"):
            # 供应商侧可能是非上市公司，未必在节点表里；上市侧必须能对上。
            if edge.get(end) not in node_ids and edge.get(f"{end}Listed", False):
                fail(errors, f"{where}：{end} 声称已上市但不在节点表中")
        if edge.get("confidence") not in ALLOWED_CONFIDENCE:
            fail(errors, f"{where}：confidence 必须是 {sorted(ALLOWED_CONFIDENCE)}")
        evidence = edge.get("evidence")
        if not isinstance(evidence, list) or not evidence:
            fail(errors, f"{where}：**没有 evidence 的边不得发布**")
            continue
        for j, item in enumerate(evidence):
            if not isinstance(item, dict):
                fail(errors, f"{where} evidence[{j}]：格式错误")
                continue
            for field in REQUIRED_EVIDENCE_FIELDS:
                if not item.get(field):
                    fail(errors, f"{where} evidence[{j}]：缺少可核验字段 {field}")
            url = str(item.get("url") or "")
            if url and not url.startswith("https://"):
                fail(errors, f"{where} evidence[{j}]：出处必须是可点开的 https 链接")
    return len(edges)


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
    by_basis = coverage.get("stageByBasis") or {}
    if by_basis.get("sector-ambiguous") != counts.get("ambiguous"):
        fail(errors, f"coverage 歧义节点数 {by_basis.get('sector-ambiguous')} "
                     f"与实际 {counts.get('ambiguous')} 不符")


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
    check_health(errors, len(payload.get("nodes") or []))

    total_nodes = len(payload.get("nodes") or [])
    print(f"节点 {total_nodes}：已判定 {counts.get('resolved', 0)}，"
          f"仅候选集 {counts.get('ambiguous', 0)}，未登记 {counts.get('unknown', 0)}")
    print(f"关系边 {edge_count}"
          + ("（全部携带可核验出处）" if edge_count else "（第 0 层无证据来源）"))
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
