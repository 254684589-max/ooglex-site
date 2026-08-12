#!/usr/bin/env python3
"""Publish a compact, static stable-V1 evidence snapshot for the terminal page.

The input is the read-only release-gate report. This script does not call GitHub or
market APIs and does not commit, push, merge, or deploy. Repeated successful runs
inside the same scheduler cycle are deduplicated so they do not grow Git history.
"""

from __future__ import annotations

import argparse
from datetime import datetime
import json
from pathlib import Path
import re
from typing import Any


SNAPSHOT_VERSION = 1
BETA_CYCLES = 3
STABLE_CYCLES = 7
PIPELINES = {
    "macro-radar": ("宏观官方序列", "macro_radar.yml"),
    "asset-tracker": ("跨资产强弱", "asset_tracker.yml"),
    "companies": ("全球公司榜", "companies.yml"),
    "asset-ranking": ("全球资产榜", "asset_ranking.yml"),
}
ALLOWED_BRANCH = re.compile(r"^agent/finance-terminal-[A-Za-z0-9._-]+$")
ALLOWED_TARGET_STATUSES = {"PASS", "WARN", "BLOCKED"}
ALLOWED_EVIDENCE_STATUSES = {"progress", "qualified", "blocked"}


class SnapshotError(RuntimeError):
    """Readiness report or static snapshot violates the public contract."""


def parse_time(value: Any, label: str) -> datetime:
    if not isinstance(value, str) or not value:
        raise SnapshotError(f"{label}缺少时间")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise SnapshotError(f"{label}时间无效") from exc
    if parsed.tzinfo is None:
        raise SnapshotError(f"{label}时间必须包含时区")
    return parsed


def as_int(value: Any, label: str, *, minimum: int = 0) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value < minimum:
        raise SnapshotError(f"{label}必须是不小于{minimum}的整数")
    return value


def build_snapshot(report: dict[str, Any]) -> dict[str, Any]:
    if report.get("schemaVersion") != 1:
        raise SnapshotError("上线门禁报告版本无效")
    generated_at = report.get("generatedAt")
    parse_time(generated_at, "上线门禁报告")
    scope = report.get("scope")
    branch = scope.get("branch") if isinstance(scope, dict) else None
    if not isinstance(branch, str) or not ALLOWED_BRANCH.fullmatch(branch):
        raise SnapshotError("稳定V1证据只允许金融终端开发分支")
    targets = report.get("targets")
    if not isinstance(targets, dict):
        raise SnapshotError("上线门禁报告缺少目标结论")
    beta = targets.get("beta")
    stable = targets.get("stableV1")
    if not isinstance(beta, dict) or not isinstance(stable, dict):
        raise SnapshotError("上线门禁报告缺少Beta或稳定V1结论")
    beta_status = beta.get("status")
    stable_status = stable.get("status")
    if beta_status not in ALLOWED_TARGET_STATUSES or stable_status not in ALLOWED_TARGET_STATUSES:
        raise SnapshotError("上线目标状态无效")
    if beta.get("requiredSuccessfulCycles") != BETA_CYCLES:
        raise SnapshotError("Beta周期门槛不得改变")
    if stable.get("requiredSuccessfulCycles") != STABLE_CYCLES:
        raise SnapshotError("稳定V1周期门槛不得改变")

    checks = report.get("checks")
    if not isinstance(checks, list):
        raise SnapshotError("上线门禁报告缺少检查项")
    checks_by_id = {
        check.get("id"): check
        for check in checks
        if isinstance(check, dict) and isinstance(check.get("id"), str)
    }
    pipelines = []
    for pipeline_id, (name, workflow) in PIPELINES.items():
        check = checks_by_id.get(f"workflow-{pipeline_id}")
        if not isinstance(check, dict):
            raise SnapshotError(f"缺少{pipeline_id}远端运行证据")
        metrics = check.get("metrics")
        if not isinstance(metrics, dict) or metrics.get("workflow") != workflow:
            raise SnapshotError(f"{pipeline_id}工作流身份无效")
        if metrics.get("branch") != branch:
            raise SnapshotError(f"{pipeline_id}证据分支错配")
        consecutive = as_int(
            metrics.get("consecutiveSuccessfulCycles"),
            f"{pipeline_id}连续成功周期",
        )
        cycle_dates = metrics.get("cycleDates")
        if not isinstance(cycle_dates, list) or any(
            not isinstance(item, str) or not re.fullmatch(r"\d{4}-\d{2}-\d{2}", item)
            for item in cycle_dates
        ):
            raise SnapshotError(f"{pipeline_id}周期日期无效")
        if len(cycle_dates) != len(set(cycle_dates)) or cycle_dates != sorted(cycle_dates, reverse=True):
            raise SnapshotError(f"{pipeline_id}周期日期必须唯一且由新到旧")
        latest_conclusion = metrics.get("latestConclusion")
        latest_created_at = metrics.get("latestCreatedAt")
        if latest_created_at is not None:
            parse_time(latest_created_at, f"{pipeline_id}最近运行")
        runs = metrics.get("runs")
        latest_url = None
        if isinstance(runs, list) and runs and isinstance(runs[0], dict):
            candidate = runs[0].get("url")
            if isinstance(candidate, str) and re.fullmatch(
                r"https://github\.com/[^/\s]+/[^/\s]+/actions/runs/\d+", candidate
            ):
                latest_url = candidate
        if consecutive >= STABLE_CYCLES and check.get("status") == "PASS":
            evidence_status = "qualified"
        elif consecutive > 0 and latest_conclusion == "success":
            evidence_status = "progress"
        else:
            evidence_status = "blocked"
        pipelines.append({
            "id": pipeline_id,
            "name": name,
            "workflow": workflow,
            "status": evidence_status,
            "checkStatus": check.get("status"),
            "consecutiveSuccessfulCycles": consecutive,
            "betaRequiredSuccessfulCycles": BETA_CYCLES,
            "stableRequiredSuccessfulCycles": STABLE_CYCLES,
            "remainingStableCycles": max(0, STABLE_CYCLES - consecutive),
            "latestConclusion": latest_conclusion,
            "latestCreatedAt": latest_created_at,
            "cycleDates": cycle_dates[:STABLE_CYCLES],
            "latestRunUrl": latest_url,
        })

    minimum_cycles = min(item["consecutiveSuccessfulCycles"] for item in pipelines)
    snapshot = {
        "schemaVersion": SNAPSHOT_VERSION,
        "generatedAt": generated_at,
        "targetBranch": branch,
        "targets": {
            "beta": beta_status,
            "stableV1": stable_status,
        },
        "summary": {
            "pipelineCount": len(pipelines),
            "qualifiedPipelines": sum(item["status"] == "qualified" for item in pipelines),
            "minimumConsecutiveSuccessfulCycles": minimum_cycles,
            "stableRequiredSuccessfulCycles": STABLE_CYCLES,
            "remainingStableCycles": max(0, STABLE_CYCLES - minimum_cycles),
        },
        "pipelines": pipelines,
        "source": "GitHub Actions workflow_dispatch / Finance Terminal release gate",
        "doesNotCallMarketApis": True,
        "doesNotDeploy": True,
    }
    validate_snapshot(snapshot)
    return snapshot


def validate_snapshot(snapshot: dict[str, Any]) -> None:
    if snapshot.get("schemaVersion") != SNAPSHOT_VERSION:
        raise SnapshotError("稳定V1证据快照版本无效")
    parse_time(snapshot.get("generatedAt"), "稳定V1证据快照")
    branch = snapshot.get("targetBranch")
    if not isinstance(branch, str) or not ALLOWED_BRANCH.fullmatch(branch):
        raise SnapshotError("稳定V1证据快照分支无效")
    targets = snapshot.get("targets")
    if not isinstance(targets, dict) or targets.get("beta") not in ALLOWED_TARGET_STATUSES \
            or targets.get("stableV1") not in ALLOWED_TARGET_STATUSES:
        raise SnapshotError("稳定V1证据快照目标状态无效")
    pipelines = snapshot.get("pipelines")
    if not isinstance(pipelines, list) or len(pipelines) != len(PIPELINES):
        raise SnapshotError("稳定V1证据快照必须恰好包含四条核心管道")
    if [item.get("id") for item in pipelines if isinstance(item, dict)] != list(PIPELINES):
        raise SnapshotError("稳定V1证据快照管道顺序或身份无效")
    for item in pipelines:
        pipeline_id = item["id"]
        name, workflow = PIPELINES[pipeline_id]
        if item.get("name") != name or item.get("workflow") != workflow:
            raise SnapshotError(f"{pipeline_id}快照来源身份无效")
        if item.get("status") not in ALLOWED_EVIDENCE_STATUSES:
            raise SnapshotError(f"{pipeline_id}证据状态无效")
        if item.get("checkStatus") not in ALLOWED_TARGET_STATUSES:
            raise SnapshotError(f"{pipeline_id}门禁检查状态无效")
        cycles = as_int(item.get("consecutiveSuccessfulCycles"), f"{pipeline_id}连续成功周期")
        if item.get("betaRequiredSuccessfulCycles") != BETA_CYCLES \
                or item.get("stableRequiredSuccessfulCycles") != STABLE_CYCLES \
                or item.get("remainingStableCycles") != max(0, STABLE_CYCLES - cycles):
            raise SnapshotError(f"{pipeline_id}门槛或剩余周期不可复算")
        dates = item.get("cycleDates")
        if not isinstance(dates, list) or len(dates) != len(set(dates)) \
                or dates != sorted(dates, reverse=True) or len(dates) > STABLE_CYCLES:
            raise SnapshotError(f"{pipeline_id}周期日期无效")
        if item.get("latestCreatedAt") is not None:
            parse_time(item["latestCreatedAt"], f"{pipeline_id}最近运行")
        latest_conclusion = item.get("latestConclusion")
        expected_status = "qualified" if cycles >= STABLE_CYCLES \
            and item.get("checkStatus") == "PASS" else \
            "progress" if cycles > 0 and latest_conclusion == "success" else "blocked"
        if item.get("status") != expected_status:
            raise SnapshotError(f"{pipeline_id}证据状态不可由运行事实复算")
        latest_url = item.get("latestRunUrl")
        if latest_url is not None and not isinstance(latest_url, str):
            raise SnapshotError(f"{pipeline_id}最近运行链接无效")
        if isinstance(latest_url, str) and not re.fullmatch(
            r"https://github\.com/[^/\s]+/[^/\s]+/actions/runs/\d+", latest_url
        ):
            raise SnapshotError(f"{pipeline_id}最近运行链接无效")
    summary = snapshot.get("summary")
    if not isinstance(summary, dict):
        raise SnapshotError("稳定V1证据快照缺少汇总")
    minimum = min(item["consecutiveSuccessfulCycles"] for item in pipelines)
    expected = {
        "pipelineCount": len(PIPELINES),
        "qualifiedPipelines": sum(item["status"] == "qualified" for item in pipelines),
        "minimumConsecutiveSuccessfulCycles": minimum,
        "stableRequiredSuccessfulCycles": STABLE_CYCLES,
        "remainingStableCycles": max(0, STABLE_CYCLES - minimum),
    }
    if summary != expected:
        raise SnapshotError("稳定V1证据汇总不可由四条管道复算")
    if snapshot.get("doesNotCallMarketApis") is not True or snapshot.get("doesNotDeploy") is not True:
        raise SnapshotError("稳定V1证据快照必须声明只读且不部署")
    if snapshot.get("source") != "GitHub Actions workflow_dispatch / Finance Terminal release gate":
        raise SnapshotError("稳定V1证据快照来源无效")


def semantic_signature(snapshot: dict[str, Any]) -> dict[str, Any]:
    """Ignore same-cycle retrieval time and run URL churn when deciding to commit."""
    return {
        "targetBranch": snapshot.get("targetBranch"),
        "targets": snapshot.get("targets"),
        "summary": snapshot.get("summary"),
        "pipelines": [
            {
                key: item.get(key)
                for key in (
                    "id", "status", "checkStatus", "consecutiveSuccessfulCycles",
                    "remainingStableCycles", "latestConclusion", "cycleDates",
                )
            }
            for item in snapshot.get("pipelines", [])
            if isinstance(item, dict)
        ],
    }


def write_snapshot(output: Path, snapshot: dict[str, Any]) -> bool:
    validate_snapshot(snapshot)
    if output.exists():
        try:
            current = json.loads(output.read_text(encoding="utf-8"))
            validate_snapshot(current)
            if semantic_signature(current) == semantic_signature(snapshot):
                return False
        except (OSError, json.JSONDecodeError, SnapshotError):
            pass
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(snapshot, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return True


def main() -> None:
    parser = argparse.ArgumentParser(description="生成金融终端稳定V1静态证据快照")
    parser.add_argument("--source-report", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--validate-only", type=Path)
    parser.add_argument("--github-output", type=Path)
    args = parser.parse_args()
    if args.validate_only:
        value = json.loads(args.validate_only.read_text(encoding="utf-8"))
        validate_snapshot(value)
        print("Finance terminal readiness snapshot: PASS")
        return
    if not args.source_report or not args.output:
        parser.error("生成快照必须同时提供--source-report与--output")
    report = json.loads(args.source_report.read_text(encoding="utf-8"))
    changed = write_snapshot(args.output, build_snapshot(report))
    if args.github_output:
        args.github_output.parent.mkdir(parents=True, exist_ok=True)
        with args.github_output.open("a", encoding="utf-8") as handle:
            handle.write(f"changed={'true' if changed else 'false'}\n")
    print(f"Finance terminal readiness snapshot: {'UPDATED' if changed else 'UNCHANGED'}")


if __name__ == "__main__":
    main()
