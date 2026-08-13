#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""金融终端辅助来源资格验收的离线契约测试。"""

from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path

from finance_terminal_qualification import QualificationError
from finance_terminal_supporting_qualification import (
    FIRST_WAVE,
    SUPPORTING_WORKFLOWS,
    render_markdown,
    run_supporting_qualification,
)


NOW = datetime(2026, 8, 12, 6, 0, tzinfo=timezone.utc)
BRANCH = "agent/finance-terminal-supporting-qualification"
ROOT = Path(__file__).resolve().parents[1]


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
    require(tuple(SUPPORTING_WORKFLOWS) == (
        "fear-greed", "ofr-monitor", "econ-calendar", "whats-latest"
    ), "辅助资格必须恰好覆盖四条辅助来源")
    require(FIRST_WAVE == tuple(SUPPORTING_WORKFLOWS),
            "全部辅助来源必须同时处于独立来源第一波")
    spec = SUPPORTING_WORKFLOWS["fear-greed"]
    require(spec["file"] == "fear_greed.yml" and "CNN" in spec["sources"][0],
            "CNN资格工作流或来源登记错误")


def test_ofr_contract() -> None:
    spec = SUPPORTING_WORKFLOWS["ofr-monitor"]
    require(spec["file"] == "ofr_monitor.yml", "OFR资格工作流登记错误")
    require(spec["sources"] == [
        "OFR Financial Stress Index", "OFR STFM公开接口"
    ], "OFR两类公开来源登记错误")
    require(len({item["file"] for item in SUPPORTING_WORKFLOWS.values()}) == 4,
            "四条辅助来源不得共享工作流文件")


def test_econ_calendar_contract() -> None:
    spec = SUPPORTING_WORKFLOWS["econ-calendar"]
    require(spec["file"] == "econ_calendar.yml",
            "经济日历资格工作流登记错误")
    require(spec["sources"] == ["Forex Factory公开周历"],
            "经济日历公开来源登记错误")


def test_whats_latest_contract() -> None:
    spec = SUPPORTING_WORKFLOWS["whats-latest"]
    require(spec["file"] == "whats_latest.yml",
            "财经资讯资格工作流登记错误")
    require(spec["sources"] == [
        "Google News RSS", "Yahoo Finance公开行情接口"
    ], "财经资讯公开来源登记错误")


def test_github_workflow_safety() -> None:
    workflow = (ROOT / ".github" / "workflows"
                / "finance_terminal_supporting_qualification.yml").read_text(
                    encoding="utf-8"
                )
    quality = (ROOT / ".github" / "workflows"
               / "finance_terminal_quality.yml").read_text(encoding="utf-8")
    require("branches:\n      - 'agent/finance-terminal-*'" in workflow,
            "辅助资格工作流必须只由金融终端开发分支触发")
    require("actions: write" in workflow and "contents: read" in workflow,
            "辅助资格工作流必须使用Actions写入与内容只读权限")
    require("pages: write" not in workflow and "environment:" not in workflow,
            "辅助资格工作流不得取得发布权限或环境")
    require("--fail-on-blocked" in workflow and "if: always()" in workflow,
            "辅助资格失败必须阻断且仍上传诊断")
    require("ref: ${{ github.ref_name }}" in workflow,
            "最终检查必须重新读取辅助任务写入后的最新开发分支")
    require("scripts/validate_finance_terminal_browser_evidence.mjs" in workflow
            and "finance-terminal-supporting-proxy-runtime" in workflow
            and "finance-terminal-browser-evidence.json" in workflow
            and "finance-terminal-browser-evidence.md" in workflow,
            "辅助资格完整页面检查必须保留四项代理运行时证据")
    require(all(name not in workflow for name in (
        "fear_greed.yml", "ofr_monitor.yml", "econ_calendar.yml",
        "whats_latest.yml",
    )),
            "辅助资格CI必须经编排器触发来源，不得复制取数步骤")
    require("scripts/validate_finance_terminal_supporting_qualification.py" in quality,
            "质量CI必须运行辅助资格契约测试")
    require(".github/workflows/finance_terminal_supporting_qualification.yml" in quality,
            "辅助资格工作流变更必须触发质量CI")


def test_success_and_report() -> None:
    executor = FakeExecutor()
    report = run_supporting_qualification(
        executor, BRANCH, "main", generated_at=NOW
    )
    require(report["status"] == "PASS", "四条辅助来源成功后资格验收必须PASS")
    require(report["summary"] == {"total": 4, "successful": 4, "blocked": 0},
            "辅助资格汇总不可复算")
    first_wait = next(
        index for index, event in enumerate(executor.events) if event[0] == "wait"
    )
    require(
        [event[1] for event in executor.events[:first_wait]] == list(FIRST_WAVE),
        "必须先启动全部辅助来源再等待任一结果",
    )
    markdown = render_markdown(report)
    require("状态：**PASS**" in markdown and "成功：4/4" in markdown,
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
    require(report["workflows"]["ofr-monitor"]["conclusion"] == "success",
            "CNN失败不得取消OFR独立来源")


def test_ofr_dispatch_failure_does_not_cancel_cnn() -> None:
    executor = FakeExecutor(start_failures={"ofr-monitor"})
    report = run_supporting_qualification(
        executor, BRANCH, "main", generated_at=NOW
    )
    require(report["status"] == "BLOCKED", "OFR触发失败必须阻断辅助资格")
    require(("start", "fear-greed") in executor.events
            and ("wait", "fear-greed") in executor.events,
            "OFR触发失败不得取消CNN运行")
    require(report["workflows"]["fear-greed"]["conclusion"] == "success",
            "CNN独立成功结论必须保留")


def test_econ_failure_does_not_cancel_other_sources() -> None:
    executor = FakeExecutor(wait_failures={"econ-calendar"})
    report = run_supporting_qualification(
        executor, BRANCH, "main", generated_at=NOW
    )
    require(report["status"] == "BLOCKED",
            "经济日历远端失败必须阻断辅助资格")
    require(report["workflows"]["econ-calendar"]["conclusion"] == "failure",
            "经济日历失败结论必须独立记录")
    require(report["workflows"]["fear-greed"]["conclusion"] == "success"
            and report["workflows"]["ofr-monitor"]["conclusion"] == "success",
            "经济日历失败不得取消CNN或OFR")


def test_news_failure_does_not_cancel_other_sources() -> None:
    executor = FakeExecutor(start_failures={"whats-latest"})
    report = run_supporting_qualification(
        executor, BRANCH, "main", generated_at=NOW
    )
    require(report["status"] == "BLOCKED",
            "财经资讯触发失败必须阻断辅助资格")
    require(report["workflows"]["whats-latest"]["conclusion"] == "failure",
            "财经资讯失败结论必须独立记录")
    require(all(
        report["workflows"][workflow_id]["conclusion"] == "success"
        for workflow_id in ("fear-greed", "ofr-monitor", "econ-calendar")
    ), "财经资讯失败不得取消其他辅助来源")


def main() -> None:
    test_cnn_contract()
    test_ofr_contract()
    test_econ_calendar_contract()
    test_whats_latest_contract()
    test_github_workflow_safety()
    test_success_and_report()
    test_failure_is_explicit()
    test_ofr_dispatch_failure_does_not_cancel_cnn()
    test_econ_failure_does_not_cancel_other_sources()
    test_news_failure_does_not_cancel_other_sources()
    print("Finance terminal supporting qualification: PASS")
    print("- four workflow identities and old-run isolation: PASS")
    print("- all independent sources start before waiting: PASS")
    print("- development-branch safety inherited from core qualification: PASS")
    print("- isolated failure continuation, timeout and report contract: PASS")


if __name__ == "__main__":
    main()
