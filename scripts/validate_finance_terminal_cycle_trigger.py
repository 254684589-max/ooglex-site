#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""稳定V1跨日观察标记与工作流触发路径的离线契约测试。"""

from __future__ import annotations

from copy import deepcopy
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path

from finance_terminal_cycle_trigger import (
    should_advance_cycle,
    validate_cycle_marker,
    workflow_cycle_date,
)


ROOT = Path(__file__).resolve().parents[1]
MARKER_PATH = ROOT / ".github" / "finance-terminal-v1-cycle.json"
BRANCH = "agent/finance-terminal-supporting-qualification"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def utc(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone(timezone.utc)


def main() -> None:
    marker = json.loads(MARKER_PATH.read_text(encoding="utf-8"))
    marker_requested_at = utc(marker["requestedAt"])
    require(not validate_cycle_marker(marker, expected_branch=BRANCH,
                                      now=marker_requested_at + timedelta(minutes=1)),
            "仓库跨日周期标记无效")

    require(workflow_cycle_date(utc("2026-08-12T20:59:59Z")) == "2026-08-11",
            "21:00 UTC前必须仍属于上一日更周期")
    require(workflow_cycle_date(utc("2026-08-12T21:00:00Z")) == "2026-08-12",
            "21:00 UTC必须开启新日更周期")
    require(not should_advance_cycle(marker, marker_requested_at),
            "同一周期不得再次更新标记")
    require(should_advance_cycle(marker, marker_requested_at + timedelta(days=1)),
            "进入新周期后必须允许更新标记")

    production = deepcopy(marker)
    production["targetBranch"] = "main"
    require(validate_cycle_marker(production), "生产分支周期触发未被拒绝")
    mismatch = deepcopy(marker)
    mismatch["requestedCycleDate"] = workflow_cycle_date(
        marker_requested_at - timedelta(days=1)
    )
    require(any("周期边界" in error for error in validate_cycle_marker(mismatch)),
            "伪造周期日期未被拒绝")
    unsafe = deepcopy(marker)
    unsafe["safety"]["doesNotDeploy"] = False
    require(any("不合并" in error for error in validate_cycle_marker(unsafe)),
            "允许部署的周期标记未被拒绝")

    workflow = (ROOT / ".github/workflows/finance_terminal_v1_qualification.yml").read_text(
        encoding="utf-8"
    )
    require(".github/finance-terminal-v1-cycle.json" in workflow,
            "周期标记变化必须触发资格工作流")
    require("scripts/validate_finance_terminal_cycle_trigger.py" in workflow,
            "资格工作流必须验证周期标记契约")
    require("git add -- apps/finance-terminal/readiness.json" in workflow
            and "git add -- .github/finance-terminal-v1-cycle.json" not in workflow,
            "资格工作流不得自行改写周期标记")
    require("pages: write" not in workflow and "deploy" not in workflow.lower(),
            "周期资格工作流不得具有部署能力")

    print("Finance terminal distinct-cycle trigger: PASS")
    print("- 21:00 UTC boundary and same-cycle deduplication: PASS")
    print("- development-branch-only marker contract: PASS")
    print("- no merge / deploy / release and readiness-only write: PASS")


if __name__ == "__main__":
    main()
