#!/usr/bin/env python3
"""Guard generated market-data changes before an automated Git commit.

The governed market-data pipelines share one Git branch but own disjoint output
paths.  This module makes that ownership machine-readable, blocks accidental
staging outside the active pipeline, and exposes an explicit no-change result
to GitHub Actions.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from datetime import datetime, timezone
import json
from pathlib import Path, PurePosixPath
import subprocess
from typing import Iterable


ROOT = Path(__file__).resolve().parents[1]
CONTRACT_VERSION = 1
ARTIFACT_RETENTION_DAYS = 14


class GovernanceError(RuntimeError):
    """Raised when a generator changes a path it does not own."""


@dataclass(frozen=True)
class DatasetRule:
    exact_paths: tuple[str, ...]
    logo_directory: str | None = None

    @property
    def stage_paths(self) -> tuple[str, ...]:
        paths = list(self.exact_paths)
        if self.logo_directory:
            paths.append(self.logo_directory)
        return tuple(paths)


DATASET_RULES = {
    "macro-radar": DatasetRule((
        "apps/macro-radar/data.json",
        "apps/macro-radar/health.json",
        "apps/macro-radar/history.json",
        "apps/macro-radar/series.json",
        "apps/macro-radar/curve.json",
        "apps/macro-radar/curve-monthly.json",
    )),
    "asset-tracker": DatasetRule((
        "apps/asset-tracker/data.json",
        "apps/asset-tracker/health.json",
        "apps/asset-tracker/history.json",
        "apps/asset-tracker/history-monthly.json",
    )),
    # 盘中快照单独一条数据集规则：它每15分钟跑一次，只允许动 intraday.json 这一个文件，
    # 收盘口径的 data.json / health.json / 两份历史一个都不在它的可写范围内。
    "asset-tracker-intraday": DatasetRule((
        "apps/asset-tracker/intraday.json",
    )),
    # 4 小时线单独一条数据集规则：它每 4 小时跑一次，只允许动 hourly.json 这一个文件。
    # 它的标的清单横跨跨资产、公司榜与加密三份已发布快照，但一个都不允许回写——
    # 收盘口径的 data.json、盘中的 intraday.json、公司与加密的任何文件都不在可写范围内。
    "asset-tracker-hourly": DatasetRule((
        "apps/asset-tracker/hourly.json",
    )),
    # 商品现货与官方指数：FRED（EIA 日频现货 + IMF 月频初级商品价）。它只允许动自己
    # 这三个文件，期货那条 Yahoo 管道的任何文件都不在可写范围内。
    "commodities": DatasetRule((
        "apps/commodities/data.json",
        "apps/commodities/health.json",
        "apps/commodities/history.json",
    )),
    # 各国主权债收益率：FRED 转发的 OECD 长期国债收益率（月频）+ ECB 数据门户。
    # 它只允许动自己这三个文件；美债收益率曲线属于宏观雷达、债券 ETF 属于跨资产管道，
    # 两者的任何文件都不在可写范围内。
    "bonds": DatasetRule((
        "apps/bonds/data.json",
        "apps/bonds/health.json",
        "apps/bonds/history.json",
    )),
    "companies": DatasetRule(
        (
            "apps/companies/data.json",
            "apps/companies/health.json",
            "apps/companies/history.json",
            "apps/companies/history-monthly.json",
            # 完整历史按市值名次每 100 家一片。片数随家数变化，这里按上限登记；
            # 缩编时管道会自己删掉多余的片，删除同样要在授权范围内才暂存得了。
            "apps/companies/history-2.json",
            "apps/companies/history-3.json",
            "apps/companies/history-4.json",
            "apps/companies/history-5.json",
            "apps/companies/history-6.json",
            "apps/companies/history-monthly-2.json",
            "apps/companies/history-monthly-3.json",
            "apps/companies/history-monthly-4.json",
            "apps/companies/history-monthly-5.json",
            "apps/companies/history-monthly-6.json",
            # 行情板迷你走势专用的窄文件（只留最近60个交易日）
            "apps/companies/spark.json",
            # 标普500快照与公司榜同一次取数、同一条管道产出，因此归它所有；
            # 热力图页面只读这一个文件，不另开一条管道重复取五百只股票。
            "apps/companies/sp500.json",
        ),
        logo_directory="apps/companies/logos",
    ),
    "asset-ranking": DatasetRule((
        "apps/asset-ranking/data.json",
        "apps/asset-ranking/health.json",
        "apps/asset-ranking/crypto.json",
    )),
    "fear-greed": DatasetRule((
        "apps/fear-greed/data.json",
        "apps/fear-greed/health.json",
    )),
    "ofr-monitor": DatasetRule((
        "apps/ofr-monitor/data.json",
        "apps/ofr-monitor/health.json",
    )),
    "econ-calendar": DatasetRule((
        "apps/econ-calendar/data.json",
        "apps/econ-calendar/health.json",
    )),
    "whats-latest": DatasetRule((
        "apps/whats-latest/data.json",
        "apps/whats-latest/health.json",
    )),
}


def _run_git(repo: Path, *args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", *args],
        cwd=repo,
        check=check,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def _nul_paths(result: subprocess.CompletedProcess[str]) -> set[str]:
    return {path for path in result.stdout.split("\0") if path}


def changed_paths(repo: Path = ROOT) -> list[str]:
    """Return tracked, staged and untracked paths without parsing status prose."""
    paths = set()
    paths.update(_nul_paths(_run_git(repo, "diff", "--no-renames", "--name-only", "-z")))
    paths.update(_nul_paths(_run_git(repo, "diff", "--cached", "--no-renames", "--name-only", "-z")))
    paths.update(_nul_paths(_run_git(repo, "ls-files", "--others", "--exclude-standard", "-z")))
    return sorted(paths)


def staged_paths(repo: Path = ROOT) -> list[str]:
    return sorted(_nul_paths(_run_git(repo, "diff", "--cached", "--no-renames", "--name-only", "-z")))


def owns_path(dataset: str, path: str) -> bool:
    rule = DATASET_RULES[dataset]
    normalized = PurePosixPath(path).as_posix()
    if normalized in rule.exact_paths:
        return True
    if not rule.logo_directory:
        return False
    candidate = PurePosixPath(normalized)
    logo_root = PurePosixPath(rule.logo_directory)
    return candidate.parent == logo_root and candidate.suffix.lower() == ".png"


def unowned_paths(dataset: str, paths: Iterable[str]) -> list[str]:
    return sorted(path for path in paths if not owns_path(dataset, path))


def verify_ownership(dataset: str, repo: Path = ROOT) -> list[str]:
    paths = changed_paths(repo)
    unexpected = unowned_paths(dataset, paths)
    if unexpected:
        joined = "\n- ".join(unexpected)
        raise GovernanceError(f"{dataset} 生成任务修改了未授权路径：\n- {joined}")
    return paths


def _stageable_paths(rule: DatasetRule, repo: Path) -> list[str]:
    """保留磁盘上已存在或 git 已跟踪的授权路径。

    已跟踪但已删除的路径仍需保留，删除动作才能被暂存；
    尚未生成的新授权产物（例如首次运行前的 history.json）则跳过，
    否则 git add 会因 pathspec 不匹配整体失败。
    """
    listed = _run_git(repo, "ls-files", "--", *rule.stage_paths).stdout
    tracked = {line for line in listed.splitlines() if line}
    return [path for path in rule.stage_paths if (repo / path).exists() or path in tracked]


def stage_owned(dataset: str, repo: Path = ROOT) -> list[str]:
    """Verify the worktree and stage only the active pipeline's owned paths."""
    verify_ownership(dataset, repo)
    rule = DATASET_RULES[dataset]
    stageable = _stageable_paths(rule, repo)
    if stageable:
        _run_git(repo, "add", "-A", "--", *stageable)
    staged = staged_paths(repo)
    unexpected = unowned_paths(dataset, staged)
    if unexpected:
        joined = "\n- ".join(unexpected)
        raise GovernanceError(f"{dataset} 暂存区包含未授权路径：\n- {joined}")
    return staged


def _write_output(path: Path | None, key: str, value: str) -> None:
    if path is None:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as output:
        output.write(f"{key}={value}\n")


def write_report(path: Path, *, dataset: str, repo: Path, staged: list[str]) -> None:
    report = {
        "contractVersion": CONTRACT_VERSION,
        "dataset": dataset,
        "generatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "baseCommit": _run_git(repo, "rev-parse", "HEAD").stdout.strip(),
        "changed": bool(staged),
        "changedPaths": staged,
        "ownedPaths": list(DATASET_RULES[dataset].stage_paths),
        "unownedPaths": [],
        "history": {
            "storage": "github-actions-artifact",
            "committedToGit": False,
            "retentionDays": ARTIFACT_RETENTION_DAYS,
        },
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("check", "stage"))
    parser.add_argument("--dataset", choices=tuple(DATASET_RULES), required=True)
    parser.add_argument("--repo", type=Path, default=ROOT)
    parser.add_argument("--github-output", type=Path, default=None)
    parser.add_argument("--report", type=Path, default=None)
    args = parser.parse_args()

    repo = args.repo.resolve()
    try:
        if args.command == "check":
            paths = verify_ownership(args.dataset, repo)
            staged = staged_paths(repo)
            print(f"{args.dataset}: PASS · 已授权改动 {len(paths)} 项 · 已暂存 {len(staged)} 项")
        else:
            staged = stage_owned(args.dataset, repo)
            changed = "true" if staged else "false"
            _write_output(args.github_output, "changed", changed)
            _write_output(args.github_output, "changed_count", str(len(staged)))
            if args.report:
                write_report(args.report, dataset=args.dataset, repo=repo, staged=staged)
            print(f"{args.dataset}: PASS · changed={changed} · staged={len(staged)}")
    except (GovernanceError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error)) from error


if __name__ == "__main__":
    main()
