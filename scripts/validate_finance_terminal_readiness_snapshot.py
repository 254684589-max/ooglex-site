#!/usr/bin/env python3
"""Offline contract tests for the public stable-V1 evidence snapshot."""

from __future__ import annotations

from copy import deepcopy
import json
from pathlib import Path
import tempfile

from finance_terminal_readiness_snapshot import (
    ALLOWED_BRANCH,
    PIPELINES,
    SnapshotError,
    build_snapshot,
    carry_forward_recorded_cycles,
    semantic_signature,
    validate_snapshot,
    write_snapshot,
)


ROOT = Path(__file__).resolve().parents[1]
CURRENT = ROOT / "apps" / "finance-terminal" / "readiness.json"
BRANCH = "agent/finance-terminal-supporting-qualification"
NEXT_BRANCH = "agent/finance-terminal-sci-fi-dashboard"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def report_with_cycles(cycles: int, *, latest: str = "success", branch: str = BRANCH,
                       dates: list[str] | None = None) -> dict:
    dates = dates or [f"2026-08-{11 - offset:02d}" for offset in range(cycles)]
    checks = []
    for index, (pipeline_id, (name, workflow)) in enumerate(PIPELINES.items()):
        run_id = 31000000000 + index
        checks.append({
            "id": f"workflow-{pipeline_id}",
            "name": name,
            "status": "PASS" if cycles >= 3 else "BLOCKED",
            "summary": "测试运行证据",
            "metrics": {
                "workflow": workflow,
                "branch": branch,
                "consecutiveSuccessfulCycles": cycles,
                "latestConclusion": latest,
                "latestCreatedAt": "2026-08-12T14:00:00Z",
                "cycleDates": dates,
                "runs": [{
                    "url": f"https://github.com/example/repo/actions/runs/{run_id}"
                }],
            },
        })
    return {
        "schemaVersion": 1,
        "generatedAt": "2026-08-12T15:00:00Z",
        "checks": checks,
        "targets": {
            "beta": {"status": "PASS" if cycles >= 3 else "BLOCKED", "requiredSuccessfulCycles": 3},
            "stableV1": {"status": "PASS" if cycles >= 7 else "BLOCKED", "requiredSuccessfulCycles": 7},
        },
        "scope": {"branch": branch},
    }


def expect_error(value: dict, message: str) -> None:
    try:
        validate_snapshot(value)
    except SnapshotError:
        return
    raise AssertionError(message)


def test_progress_and_qualified_states() -> None:
    progress = build_snapshot(report_with_cycles(1))
    require(progress["summary"] == {
        "pipelineCount": 4,
        "qualifiedPipelines": 0,
        "minimumConsecutiveSuccessfulCycles": 1,
        "stableRequiredSuccessfulCycles": 7,
        "remainingStableCycles": 6,
    }, "1/7稳定V1汇总错误")
    require(all(item["status"] == "progress" for item in progress["pipelines"]),
            "成功但未满7周期必须显示progress")
    require(all(item["cycleDates"] == ["2026-08-11"] for item in progress["pipelines"]),
            "同一UTC调度周期必须只保留一个日期")
    qualified = build_snapshot(report_with_cycles(7))
    require(qualified["targets"]["stableV1"] == "PASS"
            and qualified["summary"]["qualifiedPipelines"] == 4
            and qualified["summary"]["remainingStableCycles"] == 0,
            "7/7稳定V1证据未转为qualified")
    require(all(item["status"] == "qualified" for item in qualified["pipelines"]),
            "四条管道达到7周期后必须全部qualified")


def test_invalid_or_missing_evidence_is_rejected() -> None:
    report = report_with_cycles(1)
    report["checks"].pop()
    try:
        build_snapshot(report)
    except SnapshotError:
        pass
    else:
        raise AssertionError("缺少一条核心管道证据未被阻断")
    valid = build_snapshot(report_with_cycles(1))
    tampered = deepcopy(valid)
    tampered["pipelines"][0]["remainingStableCycles"] = 0
    expect_error(tampered, "不可复算的剩余周期未被阻断")
    tampered = deepcopy(valid)
    tampered["targetBranch"] = "main"
    expect_error(tampered, "生产分支证据未被拒绝")


def test_same_cycle_deduplication() -> None:
    first = build_snapshot(report_with_cycles(1))
    repeated = deepcopy(first)
    repeated["generatedAt"] = "2026-08-12T16:00:00Z"
    repeated["pipelines"][0]["latestCreatedAt"] = "2026-08-12T15:30:00Z"
    repeated["pipelines"][0]["latestRunUrl"] = "https://github.com/example/repo/actions/runs/31999999999"
    require(semantic_signature(first) == semantic_signature(repeated),
            "同周期成功重跑不应制造新的语义证据")
    with tempfile.TemporaryDirectory() as directory:
        output = Path(directory) / "readiness.json"
        require(write_snapshot(output, first) is True, "首次快照必须写入")
        before = output.read_bytes()
        require(write_snapshot(output, repeated) is False, "同周期成功重跑必须去重")
        require(output.read_bytes() == before, "去重运行不得重写文件时间或内容")
        next_cycle = build_snapshot(report_with_cycles(2))
        require(write_snapshot(output, next_cycle) is True, "新增UTC周期必须更新快照")


def test_complete_branch_migration_preserves_cycles() -> None:
    current = build_snapshot(report_with_cycles(5))
    same_cycle = build_snapshot(report_with_cycles(
        1, branch=NEXT_BRANCH, dates=["2026-08-11"]
    ))
    migrated = carry_forward_recorded_cycles(current, same_cycle)
    require(migrated["targetBranch"] == NEXT_BRANCH, "资格证据必须迁移到最新完整开发分支")
    require(migrated["summary"]["minimumConsecutiveSuccessfulCycles"] == 5,
            "同一UTC日的分支迁移不得把5/7清空、重算或重复累计")
    require(all(item["cycleDates"] == current["pipelines"][0]["cycleDates"]
                for item in migrated["pipelines"]), "分支迁移必须保留已有五个UTC日")

    next_cycle = build_snapshot(report_with_cycles(
        1, branch=NEXT_BRANCH, dates=["2026-08-12"]
    ))
    advanced = carry_forward_recorded_cycles(migrated, next_cycle)
    require(advanced["summary"]["minimumConsecutiveSuccessfulCycles"] == 6,
            "迁移后只有新的独立UTC日可以把5/7推进到6/7")


def test_repository_snapshot() -> None:
    value = json.loads(CURRENT.read_text(encoding="utf-8"))
    validate_snapshot(value)
    require(ALLOWED_BRANCH.fullmatch(value["targetBranch"]) is not None,
            "仓库快照必须属于金融终端开发分支")
    require(value["summary"]["minimumConsecutiveSuccessfulCycles"] >= 5,
            "仓库快照不得回退已发布的5/7稳定资格")


def main() -> None:
    test_progress_and_qualified_states()
    test_invalid_or_missing_evidence_is_rejected()
    test_same_cycle_deduplication()
    test_complete_branch_migration_preserves_cycles()
    test_repository_snapshot()
    print("Finance terminal readiness snapshot contract: PASS")
    print("- four workflow identities, 3/7 thresholds and progress states: PASS")
    print("- missing/tampered evidence and main-branch guard: PASS")
    print("- same-cycle successful rerun deduplication: PASS")
    print("- complete-development-branch migration preserves 5/7 and advances only on a new UTC day: PASS")


if __name__ == "__main__":
    main()
