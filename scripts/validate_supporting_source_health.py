#!/usr/bin/env python3
"""Validate four supporting-feed health snapshots and their shared contract."""

from __future__ import annotations

import argparse
from copy import deepcopy
from datetime import datetime, timezone
import json
from pathlib import Path

from supporting_source_health import (
    FEED_SPECS,
    HealthContractError,
    component_ids,
    load_json,
    make_health,
    make_migrated_health,
    validate_health,
)


ROOT = Path(__file__).resolve().parents[1]
DATA_PATHS = {
    dataset: ROOT / "apps" / dataset / "data.json"
    for dataset in FEED_SPECS
}
HEALTH_PATHS = {
    dataset: ROOT / "apps" / dataset / "health.json"
    for dataset in FEED_SPECS
}
FIXED_NOW = "2026-08-08T12:00:00Z"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def expect_contract_error(fn, message: str) -> None:
    try:
        fn()
    except HealthContractError:
        return
    raise AssertionError(message)


def test_dataset_contract(dataset: str, data: dict) -> None:
    ids = component_ids(dataset)
    fresh_modes = {component_id: "fresh" for component_id in ids}

    migrated = make_migrated_health(dataset, data=data, generated_at=FIXED_NOW)
    validate_health(dataset, data, migrated)
    require(migrated["status"] == "unknown" and migrated["lastAttemptAt"] is None,
            f"{dataset}迁移状态错误")
    require(migrated["coverage"]["freshCoveragePct"] == 0.0,
            f"{dataset}迁移不得伪造本轮刷新覆盖")

    healthy = make_health(
        dataset,
        data=data,
        attempted_at=FIXED_NOW,
        component_modes=fresh_modes,
        published=True,
        previous_health=migrated,
    )
    validate_health(dataset, data, healthy)
    require(healthy["status"] == "healthy" and healthy["attempt"]["status"] == "success",
            f"{dataset}全量成功未生成健康状态")
    require(healthy["consecutiveFailures"] == 0 and healthy["coverage"]["freshCoveragePct"] == 100.0,
            f"{dataset}全量成功覆盖或失败次数错误")

    partial_modes = dict(fresh_modes)
    partial_modes[ids[0]] = "fallback"
    partial = make_health(
        dataset,
        data=data,
        attempted_at="2026-08-08T13:00:00Z",
        component_modes=partial_modes,
        published=True,
        previous_health=healthy,
    )
    validate_health(dataset, data, partial)
    require(partial["status"] == "degraded" and partial["attempt"]["status"] == "partial",
            f"{dataset}单组件回退未降级")
    require(partial["coverage"]["fallbackComponents"] == 1,
            f"{dataset}回退组件数错误")

    failed = make_health(
        dataset,
        data=data,
        attempted_at="2026-08-08T14:00:00Z",
        component_modes={component_id: "unavailable" for component_id in ids},
        published=False,
        previous_health=partial,
        failure_reason="测试：全部来源不可用",
    )
    validate_health(dataset, data, failed)
    require(failed["status"] == "failed" and failed["snapshotPreserved"] is True,
            f"{dataset}失败时未保留旧快照语义")
    require(failed["consecutiveFailures"] == 1 and failed["publishedSnapshotAt"] == data["updatedAt"],
            f"{dataset}失败次数或快照时间错误")

    second_failed = make_health(
        dataset,
        data=data,
        attempted_at="2026-08-08T15:00:00Z",
        component_modes={component_id: "unavailable" for component_id in ids},
        published=False,
        previous_health=failed,
        failure_reason="测试：连续失败",
    )
    validate_health(dataset, data, second_failed)
    require(second_failed["consecutiveFailures"] == 2,
            f"{dataset}连续失败未累加")

    tampered = deepcopy(healthy)
    tampered["coverage"]["refreshedComponents"] -= 1
    expect_contract_error(
        lambda: validate_health(dataset, data, tampered),
        f"{dataset}覆盖率篡改未被阻断",
    )

    mismatch = deepcopy(healthy)
    mismatch["publishedSnapshotAt"] = "2026-08-08T00:00:00Z"
    expect_contract_error(
        lambda: validate_health(dataset, data, mismatch),
        f"{dataset}健康与数据错配未被阻断",
    )

    invalid_modes = dict(fresh_modes)
    invalid_modes.pop(ids[-1])
    expect_contract_error(
        lambda: make_health(
            dataset,
            data=data,
            attempted_at=FIXED_NOW,
            component_modes=invalid_modes,
            published=True,
        ),
        f"{dataset}缺失组件模式未被阻断",
    )


def validate_current(dataset: str) -> dict:
    data = load_json(DATA_PATHS[dataset])
    health = load_json(HEALTH_PATHS[dataset])
    require(data, f"{dataset} data.json不存在或无效")
    require(health, f"{dataset} health.json不存在或无效")
    validate_health(dataset, data, health)
    test_dataset_contract(dataset, data)
    coverage = health["coverage"]
    print(
        f"{dataset}: PASS · status={health['status']} · "
        f"published={coverage['publishedComponents']}/{coverage['expectedComponents']} · "
        f"fresh={coverage['refreshedComponents']}/{coverage['expectedComponents']}"
    )
    return health


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dataset", choices=[*FEED_SPECS, "all"], default="all")
    parser.add_argument("--report", type=Path, default=None)
    parser.add_argument("--require-published", action="store_true")
    args = parser.parse_args()
    selected = list(FEED_SPECS) if args.dataset == "all" else [args.dataset]
    reports = []
    for dataset in selected:
        health = validate_current(dataset)
        reports.append({
            "dataset": dataset,
            "status": health["status"],
            "historyStatus": health["historyStatus"],
            "lastAttemptAt": health["lastAttemptAt"],
            "lastSuccessfulAt": health["lastSuccessfulAt"],
            "consecutiveFailures": health["consecutiveFailures"],
            "publishedSnapshotAt": health["publishedSnapshotAt"],
            "snapshotPreserved": health["snapshotPreserved"],
            "coverage": health["coverage"],
            "attempt": health["attempt"],
        })
        if args.require_published and health["attempt"]["published"] is not True:
            raise SystemExit(f"{dataset}最近一次来源尝试未发布有效快照")
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps({
            "contractVersion": 1,
            "generatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "datasets": reports,
        }, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("Supporting source health validation: PASS")


if __name__ == "__main__":
    main()
