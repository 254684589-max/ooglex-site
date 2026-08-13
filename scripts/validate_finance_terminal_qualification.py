#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""金融终端四管道资格验收编排的离线契约测试。"""

from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path

from finance_terminal_qualification import (
    DATA_WORKFLOWS,
    FIRST_WAVE,
    QualificationError,
    render_markdown,
    run_qualification,
    validate_target_branch,
)


NOW = datetime(2026, 8, 9, 12, 0, tzinfo=timezone.utc)
BRANCH = "agent/finance-terminal-v1-qualification"
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
            "runId": 1000 + list(DATA_WORKFLOWS).index(workflow_id),
            "runAttempt": 1,
            "createdAt": "2026-08-09T12:00:00Z",
            "updatedAt": "2026-08-09T12:05:00Z",
            "headSha": workflow_id,
            "url": f"https://github.com/example/repo/actions/runs/{workflow_id}",
        }


def expect_qualification_error(branch: str, default_branch: str) -> None:
    try:
        validate_target_branch(branch, default_branch)
    except QualificationError:
        return
    raise AssertionError(f"不安全分支未被拒绝：{branch}")


def test_branch_guard() -> None:
    validate_target_branch(BRANCH, "main")
    expect_qualification_error("main", "main")
    expect_qualification_error("feature/finance-terminal", "main")
    expect_qualification_error("", "main")


def test_workflow_contract() -> None:
    require(tuple(DATA_WORKFLOWS) == (
        "macro-radar", "asset-tracker", "companies", "asset-ranking"
    ), "资格验收必须恰好覆盖四条核心数据管道")
    require(FIRST_WAVE == ("macro-radar", "asset-tracker", "companies"),
            "三条独立管道必须处于第一波")
    require(DATA_WORKFLOWS["asset-ranking"]["dependsOn"] == "companies",
            "资产榜必须依赖公司榜成功")
    require(len({item["file"] for item in DATA_WORKFLOWS.values()}) == 4,
            "四条管道不得共享工作流文件")


def test_github_workflow_safety() -> None:
    workflow_path = ROOT / ".github" / "workflows" / "finance_terminal_v1_qualification.yml"
    quality_path = ROOT / ".github" / "workflows" / "finance_terminal_quality.yml"
    workflow = workflow_path.read_text(encoding="utf-8")
    quality = quality_path.read_text(encoding="utf-8")
    require("branches:\n      - 'agent/finance-terminal-*'" in workflow,
            "资格工作流必须只由金融终端开发分支推送触发")
    require("actions: write" in workflow and "contents: write" in workflow,
            "资格工作流必须使用Actions调度与证据快照写入权限")
    require("pages: write" not in workflow and "deploy" not in workflow.lower(),
            "资格工作流不得包含Pages或部署步骤")
    require("finance_terminal_readiness_snapshot.py" in workflow
            and "--validate-only apps/finance-terminal/readiness.json" in workflow,
            "资格工作流必须生成并复验稳定V1静态证据")
    require('git add -- apps/finance-terminal/readiness.json' in workflow
            and 'test "$(git diff --cached --name-only)" = "apps/finance-terminal/readiness.json"' in workflow,
            "资格工作流只能精确提交稳定V1证据快照")
    require("apps/finance-terminal/readiness.json" not in workflow.split("permissions:", 1)[0],
            "证据快照提交不得递归触发资格工作流")
    require("--fail-on-blocked" in workflow and "if: always()" in workflow,
            "资格失败必须阻断，同时仍上传诊断证据")
    require("ref: ${{ github.ref_name }}" in workflow,
            "最终门禁必须重新读取资格运行后的最新开发分支")
    require("scripts/validate_finance_terminal_qualification.py" in quality,
            "质量CI必须运行资格编排契约测试")
    require("scripts/validate_finance_terminal_readiness_snapshot.py" in quality,
            "质量CI必须运行稳定V1证据快照契约测试")
    require("scripts/validate_finance_terminal_market_licenses.py" in workflow
            and "scripts/validate_finance_terminal_market_licenses.py" in quality,
            "资格与质量CI必须共同验证四项行情授权契约")
    require(".github/finance-terminal-v1-cycle.json" in workflow
            and "scripts/validate_finance_terminal_cycle_trigger.py" in workflow
            and "scripts/validate_finance_terminal_cycle_trigger.py" in quality,
            "跨日周期标记及其契约必须纳入资格与质量CI")
    require("apps/finance-terminal/market-source-readiness.json" in workflow,
            "行情授权结论变化必须触发开发分支资格验收")
    require("scripts/validate_finance_terminal_browser_evidence.mjs" in workflow
            and "finance-terminal-v1-proxy-runtime" in workflow
            and "finance-terminal-browser-evidence.json" in workflow
            and "finance-terminal-browser-evidence.md" in workflow
            and "validate_finance_terminal_proxy_runtime_history.py" in workflow
            and "finance_terminal_proxy_runtime_history.py" in workflow
            and "finance-terminal-proxy-runtime-history.json" in workflow
            and "finance-terminal-proxy-runtime-history.md" in workflow
            and "GITHUB_TOKEN: ${{ github.token }}" in workflow
            and "GITHUB_STEP_SUMMARY" in workflow
            and "retention-days: 14" in workflow,
            "稳定V1资格必须保留四项代理的浏览器证据、趋势与运维评估")
    require("scripts/finance_terminal_browser_evidence.mjs" in quality
            and "scripts/validate_finance_terminal_browser_evidence.mjs" in quality
            and "scripts/finance_terminal_proxy_runtime_history.py" in quality
            and "scripts/validate_finance_terminal_proxy_runtime_history.py" in quality,
            "浏览器证据或趋势生成与契约变化必须触发质量CI")
    require(".github/workflows/finance_terminal_v1_qualification.yml" in quality,
            "资格工作流变更必须触发质量CI")


def test_success_order_and_report() -> None:
    executor = FakeExecutor()
    report = run_qualification(executor, BRANCH, "main", generated_at=NOW)
    require(report["status"] == "PASS", "四源成功后资格验收必须PASS")
    require(report["summary"] == {"total": 4, "successful": 4, "blocked": 0},
            "成功汇总不可复算")
    first_wait = next(index for index, event in enumerate(executor.events) if event[0] == "wait")
    require([event[1] for event in executor.events[:first_wait]] == list(FIRST_WAVE),
            "必须先启动全部独立管道再等待结果")
    companies_wait = executor.events.index(("wait", "companies"))
    ranking_start = executor.events.index(("start", "asset-ranking"))
    require(ranking_start > companies_wait, "资产榜不得早于公司榜完成时启动")
    markdown = render_markdown(report)
    require("状态：**PASS**" in markdown and "成功：4/4" in markdown,
            "Markdown报告缺少资格结论")
    require(report["safety"]["doesNotDeploy"] is True,
            "资格报告必须声明不部署")


def test_company_failure_blocks_only_dependency() -> None:
    executor = FakeExecutor(conclusions={"companies": "failure"})
    report = run_qualification(executor, BRANCH, "main", generated_at=NOW)
    require(report["status"] == "BLOCKED", "公司榜失败必须阻断整批资格")
    require(report["workflows"]["macro-radar"]["conclusion"] == "success",
            "公司榜失败不得取消宏观独立管道")
    require(report["workflows"]["asset-tracker"]["conclusion"] == "success",
            "公司榜失败不得取消跨资产独立管道")
    require(report["workflows"]["asset-ranking"]["conclusion"] == "skipped",
            "公司榜失败后资产榜必须跳过")
    require(("start", "asset-ranking") not in executor.events,
            "依赖失败时不得触发资产榜")


def test_one_dispatch_failure_does_not_cancel_others() -> None:
    executor = FakeExecutor(start_failures={"macro-radar"})
    report = run_qualification(executor, BRANCH, "main", generated_at=NOW)
    require(report["status"] == "BLOCKED", "任一核心源触发失败必须阻断资格")
    require(("start", "asset-tracker") in executor.events
            and ("start", "companies") in executor.events,
            "单源触发失败后仍须启动其他独立管道")
    require(report["workflows"]["asset-ranking"]["conclusion"] == "success",
            "宏观失败不应阻止公司榜成功后的资产榜")


def test_timeout_is_explicit() -> None:
    executor = FakeExecutor(wait_failures={"asset-tracker"})
    report = run_qualification(executor, BRANCH, "main", generated_at=NOW)
    item = report["workflows"]["asset-tracker"]
    require(item["conclusion"] == "failure" and "timed out" in item["error"],
            "超时必须以明确失败进入报告")


def main() -> None:
    test_branch_guard()
    test_workflow_contract()
    test_github_workflow_safety()
    test_success_order_and_report()
    test_company_failure_blocks_only_dependency()
    test_one_dispatch_failure_does_not_cancel_others()
    test_timeout_is_explicit()
    print("Finance terminal V1 qualification orchestration: PASS")
    print("- development-branch guard and main protection: PASS")
    print("- three independent pipelines start before waiting: PASS")
    print("- companies-success dependency before asset ranking: PASS")
    print("- isolated failure continuation, timeout and report contract: PASS")


if __name__ == "__main__":
    main()
