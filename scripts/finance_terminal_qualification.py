#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""在非生产分支编排金融终端四条核心数据管道的远端资格验收。

本脚本只通过GitHub Actions API触发仓库中已有的数据工作流。三条互不依赖的
管道先全部启动；全球资产榜只在公司榜成功后启动，避免读取旧公司快照。脚本
不会直接写行情文件、提交代码、合并分支或部署网站。
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import time
from typing import Any, Callable
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


REPORT_VERSION = 1
ALLOWED_BRANCH = re.compile(r"^agent/finance-terminal-[A-Za-z0-9._-]+$")
FIRST_WAVE = ("macro-radar", "asset-tracker", "companies")
DATA_WORKFLOWS = {
    "macro-radar": {
        "name": "宏观雷达官方源",
        "file": "macro_radar.yml",
        "sources": ["FRED DGS10", "FRED DTWEXBGS", "EIA RWTC"],
        "dependsOn": None,
    },
    "asset-tracker": {
        "name": "跨资产强弱",
        "file": "asset_tracker.yml",
        "sources": ["Yahoo Finance日线"],
        "dependsOn": None,
    },
    "companies": {
        "name": "全球公司榜",
        "file": "companies.yml",
        "sources": ["Yahoo Finance公司行情", "公开未上市估值"],
        "dependsOn": None,
    },
    "asset-ranking": {
        "name": "全球资产榜",
        "file": "asset_ranking.yml",
        "sources": ["Yahoo Finance", "CoinGecko", "公司榜快照", "公开存量估值"],
        "dependsOn": "companies",
    },
}


class QualificationError(RuntimeError):
    """资格验收无法安全继续。"""


class GitHubApiError(QualificationError):
    """GitHub Actions API调用失败。"""


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def iso_utc(value: datetime) -> str:
    return value.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def validate_target_branch(branch: str, default_branch: str) -> None:
    if not branch or not ALLOWED_BRANCH.fullmatch(branch):
        raise QualificationError("资格验收只允许agent/finance-terminal-*开发分支")
    if branch == default_branch:
        raise QualificationError("资格验收禁止在默认生产分支运行")


class GitHubActionsClient:
    """最小GitHub Actions API客户端；令牌只进入请求头。"""

    def __init__(
        self,
        repository: str,
        token: str,
        *,
        api_url: str = "https://api.github.com",
        timeout_seconds: int = 20,
    ) -> None:
        if not re.fullmatch(r"[^/\s]+/[^/\s]+", repository or ""):
            raise QualificationError("缺少有效的GitHub仓库owner/name")
        if not token:
            raise QualificationError("缺少GitHub Actions令牌")
        self.repository = repository
        self.token = token
        self.api_url = api_url.rstrip("/")
        self.timeout_seconds = timeout_seconds

    def _request(
        self,
        method: str,
        path: str,
        *,
        payload: dict[str, Any] | None = None,
    ) -> dict[str, Any] | None:
        body = None if payload is None else json.dumps(payload).encode("utf-8")
        request = Request(
            f"{self.api_url}{path}",
            data=body,
            method=method,
            headers={
                "Accept": "application/vnd.github+json",
                "Authorization": f"Bearer {self.token}",
                "X-GitHub-Api-Version": "2022-11-28",
                "User-Agent": "ooglex-finance-terminal-qualification",
                **({"Content-Type": "application/json"} if body is not None else {}),
            },
        )
        try:
            with urlopen(request, timeout=self.timeout_seconds) as response:
                if response.status == 204:
                    return None
                value = json.load(response)
            if not isinstance(value, dict):
                raise GitHubApiError("GitHub API响应根节点不是对象")
            return value
        except HTTPError as exc:
            raise GitHubApiError(f"GitHub API HTTP {exc.code}") from exc
        except URLError as exc:
            raise GitHubApiError(f"GitHub API网络错误：{type(exc.reason).__name__}") from exc
        except (OSError, ValueError, json.JSONDecodeError) as exc:
            raise GitHubApiError(f"GitHub API响应读取失败：{type(exc).__name__}") from exc

    def default_branch(self) -> str:
        payload = self._request("GET", f"/repos/{self.repository}") or {}
        branch = payload.get("default_branch")
        if not isinstance(branch, str) or not branch:
            raise GitHubApiError("GitHub仓库响应缺少默认分支")
        return branch

    def list_dispatch_runs(self, workflow_file: str, branch: str) -> list[dict[str, Any]]:
        query = urlencode({
            "branch": branch,
            "event": "workflow_dispatch",
            "per_page": 50,
        })
        payload = self._request(
            "GET",
            f"/repos/{self.repository}/actions/workflows/{workflow_file}/runs?{query}",
        ) or {}
        runs = payload.get("workflow_runs")
        if not isinstance(runs, list) or any(not isinstance(run, dict) for run in runs):
            raise GitHubApiError(f"{workflow_file}运行列表结构无效")
        return runs

    def dispatch(self, workflow_file: str, branch: str) -> None:
        self._request(
            "POST",
            f"/repos/{self.repository}/actions/workflows/{workflow_file}/dispatches",
            payload={"ref": branch},
        )

    def get_run(self, run_id: int) -> dict[str, Any]:
        payload = self._request(
            "GET", f"/repos/{self.repository}/actions/runs/{run_id}"
        ) or {}
        if payload.get("id") != run_id:
            raise GitHubApiError(f"运行{run_id}响应ID错配")
        return payload


@dataclass(frozen=True)
class PendingRun:
    workflow_id: str
    workflow_file: str
    branch: str
    previous_ids: frozenset[int]
    dispatched_at: datetime


class WorkflowExecutor:
    def __init__(
        self,
        client: GitHubActionsClient,
        *,
        timeout_seconds: int = 3600,
        poll_seconds: int = 15,
        sleep: Callable[[float], None] = time.sleep,
        monotonic: Callable[[], float] = time.monotonic,
    ) -> None:
        self.client = client
        self.timeout_seconds = timeout_seconds
        self.poll_seconds = poll_seconds
        self.sleep = sleep
        self.monotonic = monotonic

    def start(self, workflow_id: str, branch: str) -> PendingRun:
        spec = DATA_WORKFLOWS[workflow_id]
        workflow_file = spec["file"]
        previous_ids = {
            run.get("id")
            for run in self.client.list_dispatch_runs(workflow_file, branch)
            if isinstance(run.get("id"), int)
        }
        dispatched_at = utc_now()
        self.client.dispatch(workflow_file, branch)
        return PendingRun(
            workflow_id=workflow_id,
            workflow_file=workflow_file,
            branch=branch,
            previous_ids=frozenset(previous_ids),
            dispatched_at=dispatched_at,
        )

    def wait(self, pending: PendingRun) -> dict[str, Any]:
        deadline = self.monotonic() + self.timeout_seconds
        run_id: int | None = None
        while self.monotonic() < deadline:
            candidates = []
            for run in self.client.list_dispatch_runs(pending.workflow_file, pending.branch):
                candidate_id = run.get("id")
                if isinstance(candidate_id, int) and candidate_id not in pending.previous_ids:
                    candidates.append(run)
            if candidates:
                candidates.sort(key=lambda run: (str(run.get("created_at") or ""), run["id"]), reverse=True)
                run_id = candidates[0]["id"]
                break
            self.sleep(self.poll_seconds)
        if run_id is None:
            raise QualificationError(f"{pending.workflow_file}触发后未出现新运行")

        while self.monotonic() < deadline:
            run = self.client.get_run(run_id)
            if run.get("status") == "completed":
                conclusion = run.get("conclusion")
                if not isinstance(conclusion, str) or not conclusion:
                    raise QualificationError(f"{pending.workflow_file}完成但缺少结论")
                return {
                    "status": "completed",
                    "conclusion": conclusion,
                    "runId": run_id,
                    "runAttempt": run.get("run_attempt"),
                    "createdAt": run.get("created_at"),
                    "updatedAt": run.get("updated_at"),
                    "headSha": run.get("head_sha"),
                    "url": run.get("html_url"),
                }
            self.sleep(self.poll_seconds)
        raise QualificationError(f"{pending.workflow_file}超过等待时限")


def failed_result(message: str) -> dict[str, Any]:
    return {"status": "failed", "conclusion": "failure", "error": message}


def skipped_result(message: str) -> dict[str, Any]:
    return {"status": "skipped", "conclusion": "skipped", "error": message}


def run_qualification(
    executor: Any,
    branch: str,
    default_branch: str,
    *,
    generated_at: datetime | None = None,
) -> dict[str, Any]:
    """启动第一波全部独立管道，再按公司榜依赖启动资产榜。"""
    validate_target_branch(branch, default_branch)
    generated_at = generated_at or utc_now()
    results: dict[str, dict[str, Any]] = {}
    pending: dict[str, Any] = {}

    # 先全部启动，确保单源失败不会阻止其他独立源执行。
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

    if results.get("companies", {}).get("conclusion") == "success":
        try:
            asset_pending = executor.start("asset-ranking", branch)
            results["asset-ranking"] = executor.wait(asset_pending)
        except QualificationError as exc:
            results["asset-ranking"] = failed_result(str(exc))
    else:
        results["asset-ranking"] = skipped_result("公司榜未成功，禁止资产榜读取旧公司快照")

    successful = [
        workflow_id for workflow_id in DATA_WORKFLOWS
        if results.get(workflow_id, {}).get("conclusion") == "success"
    ]
    blocked = [workflow_id for workflow_id in DATA_WORKFLOWS if workflow_id not in successful]
    return {
        "schemaVersion": REPORT_VERSION,
        "generatedAt": iso_utc(generated_at),
        "targetBranch": branch,
        "defaultBranch": default_branch,
        "status": "PASS" if not blocked else "BLOCKED",
        "summary": {
            "total": len(DATA_WORKFLOWS),
            "successful": len(successful),
            "blocked": len(blocked),
        },
        "workflows": {
            workflow_id: {
                "name": DATA_WORKFLOWS[workflow_id]["name"],
                "file": DATA_WORKFLOWS[workflow_id]["file"],
                "sources": DATA_WORKFLOWS[workflow_id]["sources"],
                "dependsOn": DATA_WORKFLOWS[workflow_id]["dependsOn"],
                **results[workflow_id],
            }
            for workflow_id in DATA_WORKFLOWS
        },
        "blocked": blocked,
        "safety": {
            "developmentBranchOnly": True,
            "doesNotMerge": True,
            "doesNotDeploy": True,
            "assetRankingRequiresCompaniesSuccess": True,
            "independentPipelinesStartBeforeWaiting": True,
        },
    }


def render_markdown(report: dict[str, Any]) -> str:
    lines = [
        "# Ooglex金融终端稳定V1资格验收",
        "",
        f"- 状态：**{report['status']}**",
        f"- 目标分支：`{report['targetBranch']}`",
        f"- 生成时间：`{report['generatedAt']}`",
        f"- 成功：{report['summary']['successful']}/{report['summary']['total']}",
        "",
        "| 管道 | 结论 | 运行 |",
        "|---|---|---|",
    ]
    for workflow_id, item in report["workflows"].items():
        run = f"[#{item['runId']}]({item['url']})" if item.get("runId") and item.get("url") else "—"
        lines.append(f"| {item['name']} | {item['conclusion']} | {run} |")
        if item.get("error"):
            lines.append(f"| ↳ {workflow_id} | {item['error']} | — |")
    lines.extend([
        "",
        "> 本流程只操作开发分支的数据工作流，不合并main、不部署网站。",
        "",
    ])
    return "\n".join(lines)


def write_text(path: Path | None, text: str) -> None:
    if path is None:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description="运行金融终端四管道开发分支资格验收")
    parser.add_argument("--repository", default=os.environ.get("GITHUB_REPOSITORY"))
    parser.add_argument("--branch", default=os.environ.get("GITHUB_REF_NAME"))
    parser.add_argument("--github-token-env", default="GITHUB_TOKEN")
    parser.add_argument("--timeout-minutes", type=int, default=60)
    parser.add_argument("--poll-seconds", type=int, default=15)
    parser.add_argument("--report-json", type=Path)
    parser.add_argument("--report-md", type=Path)
    parser.add_argument("--fail-on-blocked", action="store_true")
    args = parser.parse_args()

    try:
        client = GitHubActionsClient(
            args.repository or "", os.environ.get(args.github_token_env, "")
        )
        report = run_qualification(
            WorkflowExecutor(
                client,
                timeout_seconds=max(args.timeout_minutes, 1) * 60,
                poll_seconds=max(args.poll_seconds, 1),
            ),
            args.branch or "",
            client.default_branch(),
        )
    except QualificationError as exc:
        raise SystemExit(f"资格验收输入无效：{exc}") from exc

    json_text = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    markdown = render_markdown(report)
    write_text(args.report_json, json_text)
    write_text(args.report_md, markdown)
    print(json_text, end="")
    if args.fail_on_blocked and report["status"] == "BLOCKED":
        raise SystemExit(2)


if __name__ == "__main__":
    main()
