#!/usr/bin/env python3
"""Contract tests for governed market-data GitHub Actions workflows."""

from __future__ import annotations

import argparse
import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[1]
GOVERNANCE = ROOT / "scripts" / "market_workflow_governance.py"
WORKFLOWS = {
    "macro-radar": ROOT / ".github" / "workflows" / "macro_radar.yml",
    "asset-tracker": ROOT / ".github" / "workflows" / "asset_tracker.yml",
    # 盘中快照是同一条管道的第二层：单独的工作流、单独的并发组、单独的可写路径，
    # 只能动 intraday.json，动不了收盘口径的任何文件。
    "asset-tracker-intraday": ROOT / ".github" / "workflows" / "asset_tracker_intraday.yml",
    # 商品现货与官方指数：独立工作流、独立并发组、独立可写路径，动不了期货那条管道。
    "commodities": ROOT / ".github" / "workflows" / "commodities.yml",
    "companies": ROOT / ".github" / "workflows" / "companies.yml",
    "asset-ranking": ROOT / ".github" / "workflows" / "asset_ranking.yml",
    "fear-greed": ROOT / ".github" / "workflows" / "fear_greed.yml",
    "ofr-monitor": ROOT / ".github" / "workflows" / "ofr_monitor.yml",
    "econ-calendar": ROOT / ".github" / "workflows" / "econ_calendar.yml",
    "whats-latest": ROOT / ".github" / "workflows" / "whats_latest.yml",
}
SCHEDULER = ROOT / ".github" / "workflows" / "scheduler.yml"
GOVERNANCE_DOC = ROOT / "docs" / "AGGREGATE_SOURCE_HEALTH.md"
SUPPORTING_DOC = ROOT / "docs" / "SUPPORTING_SOURCE_HEALTH.md"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def load_governance():
    spec = importlib.util.spec_from_file_location("market_workflow_governance", GOVERNANCE)
    require(spec is not None and spec.loader is not None, "无法加载工作流治理模块")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def git(repo: Path, *args: str) -> None:
    subprocess.run(["git", *args], cwd=repo, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def test_path_contract(module) -> None:
    require(module.owns_path("macro-radar", "apps/macro-radar/data.json"), "宏观雷达data未授权")
    require(module.owns_path("macro-radar", "apps/macro-radar/health.json"), "宏观雷达health未授权")
    require(module.owns_path("macro-radar", "apps/macro-radar/history.json"), "宏观雷达history未授权")
    require(not module.owns_path("macro-radar", "apps/macro-radar/app.js"), "宏观雷达页面不得授权")
    require(module.owns_path("asset-tracker", "apps/asset-tracker/data.json"), "跨资产data未授权")
    require(module.owns_path("asset-tracker", "apps/asset-tracker/health.json"), "跨资产health未授权")
    require(not module.owns_path("asset-tracker", "apps/asset-tracker/index.html"), "跨资产页面不得授权")
    require(module.owns_path("companies", "apps/companies/logos/example.com.png"), "公司PNG Logo未授权")
    require(not module.owns_path("companies", "apps/companies/app.js"), "公司页面不得授权")
    require(not module.owns_path("companies", "apps/companies/logos/nested/logo.png"), "嵌套Logo路径不得授权")
    require(not module.owns_path("companies", "apps/companies/logos/readme.txt"), "非PNG Logo不得授权")
    require(module.owns_path("asset-ranking", "apps/asset-ranking/data.json"), "资产榜data未授权")
    require(not module.owns_path("asset-ranking", "apps/companies/data.json"), "资产榜不得拥有公司上游")
    for dataset in ("fear-greed", "ofr-monitor", "econ-calendar", "whats-latest"):
        require(module.owns_path(dataset, f"apps/{dataset}/data.json"), f"{dataset} data未授权")
        require(module.owns_path(dataset, f"apps/{dataset}/health.json"), f"{dataset} health未授权")
        require(not module.owns_path(dataset, f"apps/{dataset}/app.js"), f"{dataset}页面不得授权")


def test_git_contract(module) -> None:
    with tempfile.TemporaryDirectory() as temp:
        repo = Path(temp)
        git(repo, "init", "-q")
        git(repo, "config", "user.name", "workflow-test")
        git(repo, "config", "user.email", "workflow-test@example.invalid")
        data = repo / "apps" / "asset-tracker" / "data.json"
        health = repo / "apps" / "asset-tracker" / "health.json"
        page = repo / "apps" / "asset-tracker" / "index.html"
        data.parent.mkdir(parents=True)
        data.write_text('{"value": 1}\n', encoding="utf-8")
        health.write_text('{"status": "healthy"}\n', encoding="utf-8")
        page.write_text("baseline\n", encoding="utf-8")
        git(repo, "add", ".")
        git(repo, "commit", "-qm", "baseline")

        data.write_text('{"value": 2}\n', encoding="utf-8")
        page.write_text("unexpected\n", encoding="utf-8")
        try:
            module.stage_owned("asset-tracker", repo)
        except module.GovernanceError:
            pass
        else:
            raise AssertionError("越权页面改动未被阻断")
        require(not module.staged_paths(repo), "越权失败后不应留下暂存文件")

        git(repo, "restore", "apps/asset-tracker/index.html")
        staged = module.stage_owned("asset-tracker", repo)
        require(staged == ["apps/asset-tracker/data.json"], "只应暂存跨资产data改动")
        git(repo, "commit", "-qm", "data")
        require(module.stage_owned("asset-tracker", repo) == [], "无变化时必须返回空暂存集")


def test_company_logo_contract(module) -> None:
    with tempfile.TemporaryDirectory() as temp:
        repo = Path(temp)
        git(repo, "init", "-q")
        git(repo, "config", "user.name", "workflow-test")
        git(repo, "config", "user.email", "workflow-test@example.invalid")
        company_dir = repo / "apps" / "companies"
        logo_dir = company_dir / "logos"
        logo_dir.mkdir(parents=True)
        data = company_dir / "data.json"
        health = company_dir / "health.json"
        app = company_dir / "app.js"
        data.write_text('{"value": 1}\n', encoding="utf-8")
        health.write_text('{"status": "healthy"}\n', encoding="utf-8")
        app.write_text("baseline\n", encoding="utf-8")
        git(repo, "add", ".")
        git(repo, "commit", "-qm", "baseline")

        data.write_text('{"value": 2}\n', encoding="utf-8")
        (logo_dir / "example.com.png").write_bytes(b"png-test")
        app.write_text("unexpected\n", encoding="utf-8")
        try:
            module.stage_owned("companies", repo)
        except module.GovernanceError:
            pass
        else:
            raise AssertionError("公司榜页面改动未被路径守卫阻断")
        require(not module.staged_paths(repo), "公司榜越权失败后不应留下暂存文件")

        git(repo, "restore", "apps/companies/app.js")
        staged = module.stage_owned("companies", repo)
        require(staged == ["apps/companies/data.json", "apps/companies/logos/example.com.png"],
                "公司榜只应暂存数据与根目录PNG Logo")


def test_macro_git_contract(module) -> None:
    with tempfile.TemporaryDirectory() as temp:
        repo = Path(temp)
        git(repo, "init", "-q")
        git(repo, "config", "user.name", "workflow-test")
        git(repo, "config", "user.email", "workflow-test@example.invalid")
        macro_dir = repo / "apps" / "macro-radar"
        macro_dir.mkdir(parents=True)
        for name in ("data.json", "health.json", "history.json"):
            (macro_dir / name).write_text('{"version": 1}\n', encoding="utf-8")
        (macro_dir / "app.js").write_text("baseline\n", encoding="utf-8")
        git(repo, "add", ".")
        git(repo, "commit", "-qm", "baseline")

        (macro_dir / "data.json").write_text('{"version": 2}\n', encoding="utf-8")
        (macro_dir / "health.json").write_text('{"version": 2}\n', encoding="utf-8")
        (macro_dir / "app.js").write_text("unexpected\n", encoding="utf-8")
        try:
            module.stage_owned("macro-radar", repo)
        except module.GovernanceError:
            pass
        else:
            raise AssertionError("宏观雷达页面改动未被路径守卫阻断")
        require(not module.staged_paths(repo), "宏观雷达越权失败后不应留下暂存文件")

        git(repo, "restore", "apps/macro-radar/app.js")
        staged = module.stage_owned("macro-radar", repo)
        require(staged == ["apps/macro-radar/data.json", "apps/macro-radar/health.json"],
                "宏观雷达只应暂存变更的授权输出")


def test_supporting_git_contract(module) -> None:
    with tempfile.TemporaryDirectory() as temp:
        repo = Path(temp)
        git(repo, "init", "-q")
        git(repo, "config", "user.name", "workflow-test")
        git(repo, "config", "user.email", "workflow-test@example.invalid")
        app_dir = repo / "apps" / "fear-greed"
        app_dir.mkdir(parents=True)
        for name in ("data.json", "health.json"):
            (app_dir / name).write_text('{"version": 1}\n', encoding="utf-8")
        (app_dir / "app.js").write_text("baseline\n", encoding="utf-8")
        git(repo, "add", ".")
        git(repo, "commit", "-qm", "baseline")

        (app_dir / "health.json").write_text('{"version": 2}\n', encoding="utf-8")
        (app_dir / "app.js").write_text("unexpected\n", encoding="utf-8")
        try:
            module.stage_owned("fear-greed", repo)
        except module.GovernanceError:
            pass
        else:
            raise AssertionError("辅助来源页面改动未被路径守卫阻断")
        require(not module.staged_paths(repo), "辅助来源越权失败后不应留下暂存文件")

        git(repo, "restore", "apps/fear-greed/app.js")
        staged = module.stage_owned("fear-greed", repo)
        require(staged == ["apps/fear-greed/health.json"], "辅助来源只能暂存数据与健康文件")


def validate_workflow(dataset: str) -> None:
    text = WORKFLOWS[dataset].read_text(encoding="utf-8")
    expected_group = f"group: market-data-{dataset}-${{{{ github.ref }}}}"
    require(expected_group in text and "cancel-in-progress: false" in text,
            f"{dataset}缺少独立并发锁")
    require('GITHUB_REF_TYPE' in text and '!= "branch"' in text,
            f"{dataset}未阻断标签引用")
    require('git fetch --no-tags origin "$GITHUB_REF_NAME"' in text
            and 'git checkout -B "$GITHUB_REF_NAME" FETCH_HEAD' in text,
            f"{dataset}未在生成前同步目标分支")
    require(f"market_workflow_governance.py stage --dataset {dataset}" in text,
            f"{dataset}未使用共享路径守卫")
    require("if: steps.stage.outputs.changed == 'true'" in text,
            f"{dataset}未按机器输出跳过空提交")
    require("retention-days: 14" in text and "actions/upload-artifact@v6" in text,
            f"{dataset}未使用14天短期诊断Artifact")
    require("git rebase -X theirs" in text and "git push origin \"HEAD:$GITHUB_REF_NAME\"" in text,
            f"{dataset}缺少安全推送重试")
    require("git add -A apps" not in text and "git add apps/" not in text,
            f"{dataset}仍绕过共享路径守卫直接暂存")
    require("deploy" not in text.lower(), f"{dataset}数据任务不得部署")
    if dataset == "macro-radar":
        require("validate_macro_source_health.py --report" in text,
                "宏观雷达未在提交前校验逐源健康")
        allowed = {"FRED_API_KEY", "EIA_API_KEY"}
        referenced = set(__import__("re").findall(r"secrets\.([A-Z0-9_]+)", text))
        require(referenced == allowed, "宏观雷达只能读取已登记的FRED/EIA行情Secrets")
    elif dataset == "commodities":
        # 商品现货管道读同一把 FRED 行情密钥，且只读这一把；缺失时退到免密钥的公开导出，
        # 因此密钥是可选加速而不是必需依赖。
        referenced = set(__import__("re").findall(r"secrets\.([A-Z0-9_]+)", text))
        require(referenced == {"FRED_API_KEY"}, "商品现货管道只能读取已登记的FRED行情Secret")
    else:
        require("secrets." not in text, f"{dataset}治理任务不得读取Secret")
    if dataset in ("fear-greed", "ofr-monitor", "econ-calendar", "whats-latest"):
        require(f"validate_supporting_source_health.py --dataset {dataset} --report" in text
                and f"validate_supporting_source_health.py --dataset {dataset} --require-published" in text,
                f"{dataset}必须先保存健康诊断，再按最近尝试结果结束任务")


def validate_cross_pipeline_contract() -> None:
    scheduler = SCHEDULER.read_text(encoding="utf-8")
    require('-f event=workflow_dispatch -f "branch=$GITHUB_REF_NAME" -f per_page=1' in scheduler,
            "调度器查询最近运行时必须按当前分支隔离，开发分支资格运行不得抑制main生产调度")
    require("latest_dispatch companies.yml" in scheduler and 'c_concl" = "success"' in scheduler
            and "workflows/asset_ranking.yml/dispatches" in scheduler,
            "调度器必须在公司榜本窗口成功后才触发资产总榜")
    workflow_texts = {name: path.read_text(encoding="utf-8") for name, path in WORKFLOWS.items()}
    groups = [f"market-data-{name}-${{{{ github.ref }}}}" for name in WORKFLOWS]
    require(len(groups) == len(set(groups)), "三条管道不得共享会替换等待任务的同一并发组")
    build_markers = {
        "macro-radar": "python scripts/macro-radar/build_radar.py",
        "asset-tracker": "python scripts/asset-tracker/build_assets.py",
        "asset-tracker-intraday": "python scripts/asset-tracker/build_intraday.py",
        "commodities": "python scripts/commodities/build_commodities.py",
        "companies": "python scripts/companies/fetch_logos.py",
        "asset-ranking": "python scripts/asset-ranking/build_ranking.py",
        "fear-greed": "python scripts/fear-greed/build_fear_greed.py",
        "ofr-monitor": "python scripts/ofr-monitor/build_ofr.py",
        "econ-calendar": "python scripts/econ-calendar/build_calendar.py",
        "whats-latest": "python scripts/whats-latest/build_news.py",
    }
    for name, text in workflow_texts.items():
        require(text.index("Sync target branch before generation") < text.index(build_markers[name]),
                f"{name}必须先同步再生成")
    document = GOVERNANCE_DOC.read_text(encoding="utf-8")
    require("更新任务与Git历史治理" in document and "14天GitHub Actions Artifact" in document
            and "health.json" in document,
            "治理文档必须说明路径所有权、短期诊断和最新健康快照的边界")
    supporting_document = SUPPORTING_DOC.read_text(encoding="utf-8")
    require(all(dataset in supporting_document for dataset in ("fear-greed", "ofr-monitor", "econ-calendar", "whats-latest"))
            and "14天" in supporting_document and "health.json" in supporting_document,
            "辅助来源治理文档必须说明四源、健康文件与短期诊断")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dataset", choices=[*WORKFLOWS, "all"], default="all")
    args = parser.parse_args()
    selected = list(WORKFLOWS) if args.dataset == "all" else [args.dataset]

    module = load_governance()
    test_path_contract(module)
    test_git_contract(module)
    test_company_logo_contract(module)
    test_macro_git_contract(module)
    test_supporting_git_contract(module)
    validate_cross_pipeline_contract()
    for dataset in selected:
        validate_workflow(dataset)
        print(f"{dataset}: PASS · concurrency/sync/ownership/no-change/artifact/push")


if __name__ == "__main__":
    main()
