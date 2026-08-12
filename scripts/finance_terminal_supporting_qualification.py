#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""在金融终端开发分支建立辅助数据源的真实运行证据。

本脚本只通过GitHub Actions API触发已有辅助数据工作流。所有来源先启动再
分别等待，确保一个公开来源失败不会取消其他独立来源。脚本不直接写数据、
提交代码、合并分支或部署网站。
"""

from __future__ import annotations

import argparse
from datetime import datetime
import json
import os
from pathlib import Path
from typing import Any

from finance_terminal_qualification import (
    GitHubActionsClient,
    QualificationError,
    WorkflowExecutor,
    iso_utc,
    utc_now,
    validate_target_branch,
)


REPORT_VERSION = 1
SUPPORTING_WORKFLOWS: dict[str, dict[str, Any]] = {
    "fear-greed": {
        "name": "CNN恐慌与贪婪",
        "file": "fear_greed.yml",
        "sources": ["CNN Fear & Greed公开接口"],
    },
    "ofr-monitor": {
        "name": "OFR金融压力",
        "file": "ofr_monitor.yml",
        "sources": ["OFR Financial Stress Index", "OFR STFM公开接口"],
    },
    "econ-calendar": {
        "name": "Forex Factory经济日历",
        "file": "econ_calendar.yml",
        "sources": ["Forex Factory公开周历"],
    },
}
FIRST_WAVE = tuple(SUPPORTING_WORKFLOWS)


def failed_result(message: str) -> dict[str, Any]:
    return {"status": "failed", "conclusion": "failure", "error": message}


def run_supporting_qualification(
    executor: Any,
    branch: str,
    default_branch: str,
    *,
    generated_at: datetime | None = None,
) -> dict[str, Any]:
    """同时启动全部独立辅助来源，再逐项收集本轮远端结论。"""
    validate_target_branch(branch, default_branch)
    generated_at = generated_at or utc_now()
    pending: dict[str, Any] = {}
    results: dict[str, dict[str, Any]] = {}

    for workflow_id in FIRST_WAVE:
        try:
            pending[workflow_id] = executor.start(workflow_id, branch)
        except QualificationError as exc:
            results[workflow_id] = failed_result(str(exc))

    for workflow_id in FIRST_WAVE:
        if workflow_id not in pending:
            continue
        try:
            results[workflow_id] = executor.wait(pending[workflow_id])
        except QualificationError as exc:
            results[workflow_id] = failed_result(str(exc))

    successful = [
        workflow_id
        for workflow_id in SUPPORTING_WORKFLOWS
        if results.get(workflow_id, {}).get("conclusion") == "success"
    ]
    blocked = [
        workflow_id
        for workflow_id in SUPPORTING_WORKFLOWS
        if workflow_id not in successful
    ]
    return {
        "schemaVersion": REPORT_VERSION,
        "generatedAt": iso_utc(generated_at),
        "targetBranch": branch,
        "defaultBranch": default_branch,
        "status": "PASS" if not blocked else "BLOCKED",
        "summary": {
            "total": len(SUPPORTING_WORKFLOWS),
            "successful": len(successful),
            "blocked": len(blocked),
        },
        "workflows": {
            workflow_id: {
                "name": SUPPORTING_WORKFLOWS[workflow_id]["name"],
                "file": SUPPORTING_WORKFLOWS[workflow_id]["file"],
                "sources": SUPPORTING_WORKFLOWS[workflow_id]["sources"],
                **results[workflow_id],
            }
            for workflow_id in SUPPORTING_WORKFLOWS
        },
        "blocked": blocked,
        "safety": {
            "developmentBranchOnly": True,
            "doesNotMerge": True,
            "doesNotDeploy": True,
            "independentSourcesStartBeforeWaiting": True,
            "oldRunsExcludedByIdBaseline": True,
        },
    }


def render_markdown(report: dict[str, Any]) -> str:
    lines = [
        "# Ooglex金融终端辅助来源资格验收",
        "",
        f"- 状态：**{report['status']}**",
        f"- 目标分支：`{report['targetBranch']}`",
        f"- 生成时间：`{report['generatedAt']}`",
        f"- 成功：{report['summary']['successful']}/{report['summary']['total']}",
        "",
        "| 来源 | 结论 | 运行 |",
        "|---|---|---|",
    ]
    for workflow_id, item in report["workflows"].items():
        run = (
            f"[#{item['runId']}]({item['url']})"
            if item.get("runId") and item.get("url")
            else "—"
        )
        lines.append(f"| {item['name']} | {item['conclusion']} | {run} |")
        if item.get("error"):
            lines.append(f"| ↳ {workflow_id} | {item['error']} | — |")
    lines.extend([
        "",
        "> 本流程只操作金融终端开发分支，不合并main、不部署网站。",
        "",
    ])
    return "\n".join(lines)


def write_text(path: Path | None, value: str) -> None:
    if path is None:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(value, encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description="运行金融终端辅助来源资格验收")
    parser.add_argument("--repository", default=os.environ.get("GITHUB_REPOSITORY"))
    parser.add_argument("--branch", default=os.environ.get("GITHUB_REF_NAME"))
    parser.add_argument("--github-token-env", default="GITHUB_TOKEN")
    parser.add_argument("--timeout-minutes", type=int, default=35)
    parser.add_argument("--poll-seconds", type=int, default=15)
    parser.add_argument("--report-json", type=Path)
    parser.add_argument("--report-md", type=Path)
    parser.add_argument("--fail-on-blocked", action="store_true")
    args = parser.parse_args()

    try:
        client = GitHubActionsClient(
            args.repository or "", os.environ.get(args.github_token_env, "")
        )
        report = run_supporting_qualification(
            WorkflowExecutor(
                client,
                workflow_specs=SUPPORTING_WORKFLOWS,
                timeout_seconds=max(args.timeout_minutes, 1) * 60,
                poll_seconds=max(args.poll_seconds, 1),
            ),
            args.branch or "",
            client.default_branch(),
        )
    except QualificationError as exc:
        raise SystemExit(str(exc)) from exc

    write_text(
        args.report_json,
        json.dumps(report, ensure_ascii=False, indent=2) + "\n",
    )
    markdown = render_markdown(report)
    write_text(args.report_md, markdown)
    print(markdown)
    if args.fail_on_blocked and report["status"] != "PASS":
        raise SystemExit(1)


if __name__ == "__main__":
    main()
