#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""金融终端辅助来源资格验收的离线契约测试。"""

from __future__ import annotations

from datetime import datetime, timezone

from finance_terminal_qualification import QualificationError
from finance_terminal_supporting_qualification import (
    FIRST_WAVE,
    SUPPORTING_WORKFLOWS,
    render_markdown,
    run_supporting_qualification,
)


NOW = datetime(2026, 8, 12, 6, 0, tzinfo=timezone.utc)
BRANCH = "agent/finance-terminal-supporting-qualification"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


class FakeExecutor:
    def __init__(
        self,
        *,
        conclusions: dict[str, str] | None = None,
        start_failures: set[str] | None = None,
        wait_failures: set[str] | None = None,
    ) -> None:
        self.conclusions = conclusions or {}
        self.start_failures = start_failures or set()
        self.wait_failures = wait_failures or set()
        self.events: list[tuple[str, str]] = []

    def start(self, workflow_id: str, branch: str) -> tuple[str, str]:
        self.events.append(("start", workflow_id))
        if workflow_id in self.start_failures:
            raise QualificationError(f"{workflow_id} dispatch failed")
        require(branch == BRANCH, "编排器传入错误目标分支")
        return workflow_id, branch

    def wait(self, pending: tuple[str, str]) -> dict:
        workflow_id, _ = pending
        self.events.append(("wait", workflow_id))
        if workflow_id in self.wait_failures:
            raise QualificationError(f"{workflow_id} timed out")
        conclusion = self.conclusions.get(workflow_id, "success")
        return {
            "status": "completed",
            "conclusion": conclusion,
            "runId": 2000 + list(SUPPORTING_WORKFLOWS).index(workflow_id),
            "runAttempt": 1,
            "createdAt": "2026-08-12T06:00:00Z",
            "updatedAt": "2026-08-12T06:05:00Z",
            "headSha": workflow_id,
            "url": f"https://github.com/example/repo/actions/runs/{workflow_id}",
        }


def test_cnn_contract() -> None:
    require(tuple(SUPPORTING_WORKFLOWS) == ("fear-greed",),
            "首项资格来源必须是CNN恐慌与贪婪")
    require(FIRST_WAVE == ("fear-greed",), "CNN必须处于独立来源第一波")
    spec = SUPPORTING_WORKFLOWS["fear-greed"]
    require(spec["file"] == "fear_greed.yml" and "CNN" in spec["sources"][0],
            "CNN资格工作流或来源登记错误")


def test_success_and_report() -> None:
    executor = FakeExecutor()
    report = run_supporting_qualification(
        executor, BRANCH, "main", generated_at=NOW
    )
    require(report["status"] == "PASS", "CNN成功后资格验收必须PASS")
    require(report["summary"] == {"total": 1, "successful": 1, "blocked": 0},
            "CNN资格汇总不可复算")
    require(executor.events == [("start", "fear-greed"), ("wait", "fear-greed")],
            "CNN资格启动与等待顺序错误")
    markdown = render_markdown(report)
    require("状态：**PASS**" in markdown and "成功：1/1" in markdown,
            "辅助资格Markdown报告缺少结论")
    require(report["safety"]["oldRunsExcludedByIdBaseline"] is True,
            "资格报告必须声明隔离旧运行")


def test_failure_is_explicit() -> None:
    report = run_supporting_qualification(
        FakeExecutor(wait_failures={"fear-greed"}),
        BRANCH,
        "main",
        generated_at=NOW,
    )
    item = report["workflows"]["fear-greed"]
    require(report["status"] == "BLOCKED" and item["conclusion"] == "failure",
            "CNN远端失败必须阻断辅助资格")
    require("timed out" in item["error"], "CNN超时必须明确进入报告")


def main() -> None:
    test_cnn_contract()
    test_success_and_report()
    test_failure_is_explicit()
    print("Finance terminal supporting qualification: PASS")
    print("- CNN workflow identity and old-run isolation: PASS")
    print("- development-branch safety inherited from core qualification: PASS")
    print("- success, timeout and machine-readable report: PASS")


if __name__ == "__main__":
    main()
