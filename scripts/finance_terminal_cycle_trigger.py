#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""稳定V1开发分支的跨日观察标记契约。"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
import re
from typing import Any


CYCLE_BOUNDARY_UTC_HOUR = 21
STABLE_TARGET_CYCLES = 7
TARGET_BRANCH_PATTERN = re.compile(r"agent/finance-terminal-[a-z0-9][a-z0-9._-]*")
TRIGGER_KIND = "distinct-cycle-observation"
ALLOWED_REQUESTERS = {"repository-bootstrap", "chatgpt-automation", "manual-maintainer"}


def workflow_cycle_date(created_at: datetime) -> str:
    """将21:00 UTC至次日窗口内的运行归入同一个调度日。"""
    if created_at.tzinfo is None:
        created_at = created_at.replace(tzinfo=timezone.utc)
    return (
        created_at.astimezone(timezone.utc) - timedelta(hours=CYCLE_BOUNDARY_UTC_HOUR)
    ).date().isoformat()


def parse_marker_datetime(value: Any) -> datetime | None:
    if not isinstance(value, str) or not value.strip():
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def validate_cycle_marker(
    marker: dict[str, Any],
    *,
    expected_branch: str | None = None,
    now: datetime | None = None,
) -> list[str]:
    errors: list[str] = []
    if marker.get("schemaVersion") != 1:
        errors.append("周期标记schemaVersion必须为1")
    branch = marker.get("targetBranch")
    if not isinstance(branch, str) or not TARGET_BRANCH_PATTERN.fullmatch(branch):
        errors.append("周期标记只能指向agent/finance-terminal-*开发分支")
    if expected_branch is not None and branch != expected_branch:
        errors.append("周期标记目标分支与当前资格分支不一致")
    if branch in {"main", "master"}:
        errors.append("周期标记不得指向生产分支")
    if marker.get("triggerKind") != TRIGGER_KIND:
        errors.append("周期标记类型必须为distinct-cycle-observation")
    if marker.get("requestedBy") not in ALLOWED_REQUESTERS:
        errors.append("周期标记请求方未登记")
    if marker.get("stableTargetCycles") != STABLE_TARGET_CYCLES:
        errors.append("稳定V1目标必须保持7个不同日更周期")

    requested_at = parse_marker_datetime(marker.get("requestedAt"))
    requested_cycle = marker.get("requestedCycleDate")
    if requested_at is None:
        errors.append("周期标记requestedAt必须是UTC ISO 8601时间")
    elif requested_cycle != workflow_cycle_date(requested_at):
        errors.append("requestedCycleDate与21:00 UTC周期边界不一致")
    if now is not None and requested_at is not None:
        current = now.astimezone(timezone.utc)
        if requested_at > current + timedelta(minutes=5):
            errors.append("周期标记时间来自未来")

    safety = marker.get("safety")
    expected_safety = {
        "doesNotMergeMain": True,
        "doesNotDeploy": True,
        "doesNotRelease": True,
        "markerOnly": True,
    }
    if safety != expected_safety:
        errors.append("周期标记必须完整声明不合并、不部署、不发布且只改标记")
    return errors


def should_advance_cycle(marker: dict[str, Any], now: datetime) -> bool:
    """只有进入新周期才允许更新标记；同周期重跑返回False。"""
    if validate_cycle_marker(marker):
        return False
    return marker.get("requestedCycleDate") != workflow_cycle_date(now)
