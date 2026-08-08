#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""金融终端上线门禁的离线契约测试。"""

from __future__ import annotations

from copy import deepcopy
from datetime import date, datetime, timezone
import json
from pathlib import Path
import tempfile

from finance_terminal_release_gate import (
    AGGREGATE_DATASETS,
    EXPECTED_DEMOS,
    WORKFLOW_SPECS,
    build_report,
    business_days_since,
    collect_workflow_evidence,
    evaluate_aggregate_pipeline,
    evaluate_macro_pipeline,
    evaluate_workflow_runs,
    load_aggregate_inputs,
    render_markdown,
    workflow_cycle_date,
)
from market_data_quality import make_data_meta
from macro_source_health import SERIES_SPECS, make_macro_health as build_macro_health
from market_source_health import attach_upstream_health, make_source_health


ROOT = Path(__file__).resolve().parents[1]
NOW = datetime(2026, 8, 7, 12, 0, tzinfo=timezone.utc)
PAGE = " ".join((
    "当前为部分演示数据",
    "其余5项仍为演示数据",
    "FRED API使用条款",
    "本产品未获圣路易斯联储认可或认证",
    "EIA RWTC官方序列",
    "非投资建议",
))


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def demo_asset(asset_id: str) -> dict:
    return {
        "id": asset_id,
        "symbol": asset_id.upper(),
        "demo": True,
        "status": "demo",
        "price": 100,
        "source": {"name": "Ooglex演示数据"},
    }


def official_asset(asset_id: str, symbol: str, series: str) -> dict:
    return {
        "id": asset_id,
        "symbol": symbol,
        "demo": False,
        "status": "loading",
        "price": None,
        "source": {"name": "官方来源", "seriesId": series},
    }


def make_config() -> dict:
    return {
        "schemaVersion": 2,
        "demo": True,
        "status": "partial",
        "assets": [
            *(demo_asset(asset_id) for asset_id in sorted(EXPECTED_DEMOS)),
            official_asset("us10y", "DGS10", "DGS10"),
            official_asset("dxy", "DTWEXBGS", "DTWEXBGS"),
            official_asset("wti", "WTI", "RWTC"),
        ],
    }


def reference(series: str, source: str, price: float, previous: float) -> dict:
    return {
        "id": series,
        "demo": False,
        "status": "ok",
        "price": price,
        "previousPrice": previous,
        "changePct": (price / previous - 1) * 100,
        "asOf": "2026-08-05",
        "previousAsOf": "2026-08-04",
        "updatedAt": "2026-08-06T01:00:00Z",
        "lastAttemptAt": "2026-08-06T01:00:00Z",
        "source": {"name": source, "seriesId": series},
    }


def make_macro() -> dict:
    return {
        "updatedAt": "2026-08-06T01:00:00Z",
        "macro": [{
            "src": "FRED",
            "rows": [{"id": "DGS10", "val": "4.25%", "chg": "+2bp", "asOf": "2026-08-05"}],
        }],
        "referenceSeries": {
            "DTWEXBGS": reference("DTWEXBGS", "FRED / Federal Reserve H.10", 121.1, 120.9),
            "RWTC": reference("RWTC", "U.S. EIA / Cushing WTI Spot", 82.4, 81.7),
        },
    }


def make_macro_health_fixture(snapshot_at: str = "2026-08-06T01:00:00Z") -> tuple[dict, dict]:
    macro = make_macro()
    macro["updatedAt"] = snapshot_at
    row = macro["macro"][0]["rows"][0]
    row.update({
        "status": "ok",
        "price": 4.25,
        "previousPrice": 4.23,
        "changeBps": 2,
        "previousAsOf": "2026-08-04",
        "updatedAt": snapshot_at,
        "lastAttemptAt": snapshot_at,
        "source": {"name": SERIES_SPECS["DGS10"]["provider"],
                   "url": SERIES_SPECS["DGS10"]["url"], "seriesId": "DGS10"},
    })
    for series_id, record in macro["referenceSeries"].items():
        record["updatedAt"] = snapshot_at
        record["lastAttemptAt"] = snapshot_at
        record["source"]["url"] = SERIES_SPECS[series_id]["url"]
    return macro, build_macro_health(macro, attempted_at=snapshot_at)


def by_id(report: dict) -> dict[str, dict]:
    return {check["id"]: check for check in report["checks"]}


def market_meta(source: str, snapshot_at: str) -> dict:
    return make_data_meta(
        "market", source, as_of=snapshot_at[:10], updated_at=snapshot_at, frequency="daily"
    )


def estimate_meta(source: str, snapshot_at: str) -> dict:
    return make_data_meta(
        "estimate", source, as_of=snapshot_at[:10], updated_at=snapshot_at, frequency="irregular"
    )


def make_aggregate_inputs(snapshot_at: str = "2026-08-06T01:00:00Z") -> dict:
    tracker_rows = [
        {"name": f"资产{index}", "dataMeta": market_meta("Yahoo Finance", snapshot_at)}
        for index in range(28)
    ]
    company_rows = [
        {
            "name": f"公司{index}",
            "private": False,
            "dataMeta": market_meta("Yahoo Finance", snapshot_at),
        }
        for index in range(450)
    ] + [
        {
            "name": f"未上市公司{index}",
            "private": True,
            "dataMeta": estimate_meta("multiples.vc公开融资估值汇总", snapshot_at),
        }
        for index in range(50)
    ]
    ranking_rows = [
        {
            "name": f"上市公司资产{index}",
            "category": "company",
            "private": False,
            "static": False,
            "dataMeta": market_meta("Yahoo Finance", snapshot_at),
        }
        for index in range(200)
    ] + [
        {
            "name": f"加密资产{index}",
            "category": "crypto",
            "private": False,
            "static": False,
            "dataMeta": market_meta("CoinGecko", snapshot_at),
        }
        for index in range(4)
    ] + [
        {
            "name": f"其他行情资产{index}",
            "category": "commodity",
            "private": False,
            "static": False,
            "dataMeta": market_meta("Yahoo Finance", snapshot_at),
        }
        for index in range(30)
    ] + [
        {
            "name": f"公开估值资产{index}",
            "category": "real-estate",
            "private": False,
            "static": True,
            "dataMeta": estimate_meta("公开存量基准", snapshot_at),
        }
        for index in range(16)
    ]

    tracker_health = make_source_health(
        "asset-tracker", published_rows=tracker_rows, attempted_rows=tracker_rows,
        attempted_at=snapshot_at, published_snapshot_at=snapshot_at, published=True,
    )
    companies_health = make_source_health(
        "companies", published_rows=company_rows, attempted_rows=company_rows,
        attempted_at=snapshot_at, published_snapshot_at=snapshot_at, published=True,
    )
    ranking_health = make_source_health(
        "asset-ranking", published_rows=ranking_rows, attempted_rows=ranking_rows,
        attempted_at=snapshot_at, published_snapshot_at=snapshot_at, published=True,
    )
    attach_upstream_health(
        ranking_health,
        source_id="companies-upstream",
        upstream_dataset="companies",
        upstream_health=companies_health,
        upstream_snapshot_at=snapshot_at,
    )
    return {
        "asset-tracker": {
            "data": {"updatedAt": snapshot_at, "assets": tracker_rows},
            "health": tracker_health,
        },
        "companies": {
            "data": {"updatedAt": snapshot_at, "companies": company_rows},
            "health": companies_health,
        },
        "asset-ranking": {
            "data": {"updatedAt": snapshot_at, "assets": ranking_rows},
            "health": ranking_health,
        },
    }


def workflow_run(run_id: int, created_at: str, conclusion: str = "success", branch: str = "agent/test") -> dict:
    return {
        "id": run_id,
        "run_number": run_id,
        "run_attempt": 1,
        "event": "workflow_dispatch",
        "status": "completed",
        "conclusion": conclusion,
        "head_branch": branch,
        "head_sha": f"{run_id:040x}",
        "created_at": created_at,
        "updated_at": created_at,
        "html_url": f"https://github.com/example/repo/actions/runs/{run_id}",
    }


def make_workflow_evidence(cycles: int = 3, *, latest_conclusion: str = "success") -> dict:
    timestamps = [
        "2026-08-06T22:00:00Z",
        "2026-08-05T22:00:00Z",
        "2026-08-04T22:00:00Z",
        "2026-08-03T22:00:00Z",
        "2026-08-02T22:00:00Z",
        "2026-08-01T22:00:00Z",
        "2026-07-31T22:00:00Z",
    ][:cycles]
    workflows = {}
    for workflow_index, spec in enumerate(WORKFLOW_SPECS.values(), start=1):
        runs = []
        for index, timestamp in enumerate(timestamps):
            conclusion = latest_conclusion if index == 0 else "success"
            runs.append(workflow_run(workflow_index * 100 + index, timestamp, conclusion))
        workflows[spec["file"]] = {"workflow_runs": runs}
    return {
        "source": "fixture",
        "repository": "example/repo",
        "branch": "agent/test",
        "workflows": workflows,
    }


def test_fresh_core_with_explicit_demos() -> None:
    report = build_report(make_config(), make_macro(), PAGE, NOW)
    checks = by_id(report)
    require(report["status"] == "WARN", "5项明确演示数据应使Beta报告为WARN")
    require(checks["market-demo-policy"]["status"] == "WARN", "演示资产策略状态错误")
    require(checks["official-dgs10"]["status"] == "PASS", "新鲜DGS10应通过")
    require(checks["official-dtwexbgs"]["status"] == "PASS", "新鲜DTWEXBGS应通过")
    require(checks["official-rwtc"]["status"] == "PASS", "新鲜RWTC应通过")
    require(report["summary"] == {"PASS": 3, "WARN": 1, "BLOCKED": 0}, "门禁汇总不可复算")
    markdown = render_markdown(report)
    require("Beta状态：**WARN**" in markdown and "| FRED DGS10 | PASS |" in markdown,
            "Markdown报告缺少关键状态")


def test_stale_is_warn_not_silent_pass() -> None:
    macro = make_macro()
    macro["macro"][0]["rows"][0]["asOf"] = "2026-07-20"
    for record in macro["referenceSeries"].values():
        record["status"] = "stale"
        record["asOf"] = "2026-07-20"
        record["previousAsOf"] = "2026-07-17"
    checks = by_id(build_report(make_config(), macro, PAGE, NOW))
    for check_id in ("official-dgs10", "official-dtwexbgs", "official-rwtc"):
        require(checks[check_id]["status"] == "WARN", f"{check_id}过期后必须告警")
        require(checks[check_id]["metrics"]["businessDaysOld"] > checks[check_id]["metrics"]["maxBusinessDays"],
                f"{check_id}过期天数未准确记录")


def test_dgs10_source_attempt_status_is_independent() -> None:
    macro = make_macro()
    row = macro["macro"][0]["rows"][0]
    row.update({
        "status": "stale",
        "updatedAt": "2026-08-05T20:00:00Z",
        "lastAttemptAt": "2026-08-06T20:00:00Z",
        "source": {"name": "FRED / Federal Reserve H.15", "seriesId": "DGS10"},
    })
    check = by_id(build_report(make_config(), macro, PAGE, NOW))["official-dgs10"]
    require(check["status"] == "WARN" and check["metrics"]["pipelineStatus"] == "stale",
            "DGS10本轮失败时即使观测未过期也必须告警")
    row["source"]["seriesId"] = "DXY"
    check = by_id(build_report(make_config(), macro, PAGE, NOW))["official-dgs10"]
    require(check["status"] == "BLOCKED", "DGS10错误逐条来源必须阻断")


def test_wrong_instrument_and_change_are_blocked() -> None:
    macro = make_macro()
    macro["referenceSeries"]["RWTC"]["source"]["seriesId"] = "CL=F"
    macro["referenceSeries"]["DTWEXBGS"]["changePct"] = 99
    checks = by_id(build_report(make_config(), macro, PAGE, NOW))
    require(checks["official-rwtc"]["status"] == "BLOCKED", "期货不得冒充RWTC现货")
    require(checks["official-dtwexbgs"]["status"] == "BLOCKED", "不可复算涨跌幅必须阻断")


def test_missing_disclosure_and_demo_flag_are_blocked() -> None:
    config = make_config()
    config["assets"][0]["source"]["name"] = "未知来源"
    report = build_report(config, make_macro(), "当前为部分演示数据", NOW)
    check = by_id(report)["market-demo-policy"]
    require(check["status"] == "BLOCKED", "缺少演示来源或页面披露必须阻断")
    require(any("公开" in detail or "演示" in detail for detail in check["details"]), "阻断原因不清楚")


def test_future_observation_is_blocked() -> None:
    macro = make_macro()
    macro["macro"][0]["rows"][0]["asOf"] = "2026-08-10"
    check = by_id(build_report(make_config(), macro, PAGE, NOW))["official-dgs10"]
    require(check["status"] == "BLOCKED", "未来观测日期必须阻断")


def test_us_business_day_contract() -> None:
    # 2026-07-03 is the observed Independence Day holiday; weekend and holiday do not age data.
    age = business_days_since(date(2026, 7, 2), datetime(2026, 7, 6, 12, tzinfo=timezone.utc))
    require(age == 1, f"美国联邦假日工作日计算错误：{age}")


def test_fresh_aggregate_pipelines_pass() -> None:
    aggregate = make_aggregate_inputs()
    report = build_report(make_config(), make_macro(), PAGE, NOW, aggregate)
    checks = by_id(report)
    for dataset in AGGREGATE_DATASETS:
        check = checks[f"pipeline-{dataset}"]
        require(check["status"] == "PASS", f"{dataset}新鲜健康快照应通过：{check}")
        require(check["metrics"]["freshCoveragePct"] == 100.0, f"{dataset}行情覆盖率错误")
    require(len(report["checks"]) == 7, "核心与三条聚合门禁应合并为7项检查")
    require(report["scope"]["aggregatePipelines"] == list(AGGREGATE_DATASETS), "聚合范围未登记")


def test_macro_source_health_gate() -> None:
    macro, health = make_macro_health_fixture()
    check = evaluate_macro_pipeline(macro, health, NOW)
    require(check["status"] == "PASS" and check["metrics"]["freshCoveragePct"] == 100.0,
            "三项官方源最近成功应通过宏观健康门禁")

    migrated = build_macro_health(macro, attempted_at="2026-08-07T01:00:00Z", migrated=True)
    migrated_check = evaluate_macro_pipeline(macro, migrated, NOW)
    require(migrated_check["status"] == "WARN", "迁移未知历史应告警但不伪造失败")

    stale_macro, stale_health = make_macro_health_fixture("2026-08-01T01:00:00Z")
    stale_check = evaluate_macro_pipeline(stale_macro, stale_health, NOW)
    require(stale_check["status"] == "BLOCKED" and stale_check["metrics"]["reportAgeHours"] > 72,
            "超过72小时的宏观健康报告必须阻断")

    failed_macro, previous_health = make_macro_health_fixture("2026-08-06T01:00:00Z")
    failed_at = "2026-08-07T01:00:00Z"
    dgs = failed_macro["macro"][0]["rows"][0]
    dgs["status"] = "stale"
    dgs["lastAttemptAt"] = failed_at
    for record in failed_macro["referenceSeries"].values():
        record["status"] = "stale"
        record["lastAttemptAt"] = failed_at
    failed_health = build_macro_health(
        failed_macro, attempted_at=failed_at, previous_health=previous_health,
    )
    failed_check = evaluate_macro_pipeline(failed_macro, failed_health, NOW)
    require(failed_check["status"] == "BLOCKED" and failed_health["snapshotPreserved"] is True,
            "三项本轮失败即使旧值可用也必须阻断")

    tampered = deepcopy(health)
    tampered["coverage"]["freshCoveragePct"] = 0
    require(evaluate_macro_pipeline(macro, tampered, NOW)["status"] == "BLOCKED",
            "宏观逐源覆盖率被篡改必须阻断")


def test_stale_aggregate_health_blocks_beta() -> None:
    aggregate = make_aggregate_inputs("2026-08-01T01:00:00Z")
    check = evaluate_aggregate_pipeline(
        "asset-tracker", aggregate["asset-tracker"]["data"],
        aggregate["asset-tracker"]["health"], NOW,
    )
    require(check["status"] == "BLOCKED", "超过72小时的健康报告必须阻断Beta")
    require(check["metrics"]["reportAgeHours"] > 72, "健康报告年龄未记录")


def test_tampered_coverage_blocks_beta() -> None:
    aggregate = make_aggregate_inputs()
    aggregate["companies"]["health"]["coverage"]["freshCoveragePct"] = 0
    check = evaluate_aggregate_pipeline(
        "companies", aggregate["companies"]["data"], aggregate["companies"]["health"], NOW,
    )
    require(check["status"] == "BLOCKED", "覆盖率不可复算一致时必须阻断")
    require(any("coverage" in item for item in check["details"]), "覆盖率篡改原因未报告")


def test_failed_pipeline_with_snapshot_blocks_beta() -> None:
    aggregate = make_aggregate_inputs()
    pair = aggregate["asset-tracker"]
    attempted_at = "2026-08-07T02:00:00Z"
    failed_rows = [
        {
            "name": row["name"],
            "dataMeta": make_data_meta(
                "unavailable", "Yahoo Finance", as_of=None, updated_at=attempted_at,
                frequency="daily",
            ),
        }
        for row in pair["data"]["assets"]
    ]
    failed = make_source_health(
        "asset-tracker",
        published_rows=pair["data"]["assets"],
        attempted_rows=failed_rows,
        attempted_at=attempted_at,
        published_snapshot_at=pair["data"]["updatedAt"],
        published=False,
        previous_health=pair["health"],
        failure_reason="测试整源失败并保留旧快照。",
    )
    check = evaluate_aggregate_pipeline("asset-tracker", pair["data"], failed, NOW)
    require(check["status"] == "BLOCKED", "最近整批任务失败必须阻断Beta")
    require(check["metrics"]["snapshotPreserved"] is True, "保留快照状态未记录")
    require(check["metrics"]["consecutiveFailures"] == 1, "连续失败次数错误")


def test_recent_degraded_pipeline_warns() -> None:
    aggregate = make_aggregate_inputs()
    pair = aggregate["asset-tracker"]
    rows = deepcopy(pair["data"]["assets"])
    rows[0]["dataMeta"] = make_data_meta(
        "fallback", "Yahoo Finance", as_of="2026-08-04", updated_at="2026-08-04T01:00:00Z",
        frequency="daily",
    )
    health = make_source_health(
        "asset-tracker", published_rows=rows, attempted_rows=rows,
        attempted_at="2026-08-06T01:00:00Z", published_snapshot_at="2026-08-06T01:00:00Z",
        published=True,
    )
    data = {"updatedAt": "2026-08-06T01:00:00Z", "assets": rows}
    check = evaluate_aggregate_pipeline("asset-tracker", data, health, NOW)
    require(check["status"] == "WARN", "近期部分回退应告警但不伪装健康")
    require(check["metrics"]["freshCoveragePct"] < 100, "回退后行情覆盖率未下降")


def test_three_remote_cycles_pass_beta_evidence() -> None:
    report = build_report(
        make_config(), make_macro(), PAGE, NOW, make_aggregate_inputs(), make_workflow_evidence(3)
    )
    checks = by_id(report)
    for workflow_id in WORKFLOW_SPECS:
        check = checks[f"workflow-{workflow_id}"]
        require(check["status"] == "PASS", f"{workflow_id}三次连续成功应通过Beta证据门槛")
        require(check["metrics"]["consecutiveSuccessfulCycles"] == 3,
                f"{workflow_id}连续周期计数错误")
    require(report["status"] == "WARN" and report["targets"]["beta"]["canLaunch"] is True,
            "远端证据通过后，明确演示数据应使Beta可上线但带WARN")
    require(report["targets"]["stableV1"]["status"] == "BLOCKED",
            "仍有演示数据和不足7周期时不得宣称稳定V1")
    require(report["scope"]["workflowEvidenceSource"] == "fixture", "运行证据来源未登记")


def test_duplicate_run_same_cycle_counts_once() -> None:
    evidence = make_workflow_evidence(3)
    payload = evidence["workflows"]["macro_radar.yml"]
    payload["workflow_runs"].extend([
        workflow_run(999, "2026-08-06T21:20:00Z", "failure"),
        workflow_run(1000, "2026-08-06T23:20:00Z", "success"),
    ])
    check = evaluate_workflow_runs("macro-radar", payload, "agent/test", NOW)
    require(check["status"] == "PASS", "同周期最终重试成功后应通过")
    require(check["metrics"]["observedCycles"] == 3, "同一调度日多次运行不得重复计周期")
    require(check["metrics"]["consecutiveSuccessfulCycles"] == 3, "同周期去重后连续成功数错误")


def test_insufficient_or_failed_remote_cycles_block() -> None:
    insufficient = make_workflow_evidence(2)["workflows"]["companies.yml"]
    check = evaluate_workflow_runs("companies", insufficient, "agent/test", NOW)
    require(check["status"] == "BLOCKED", "不足3个远端周期必须阻断Beta")
    require(check["metrics"]["consecutiveSuccessfulCycles"] == 2, "不足周期计数错误")

    failed = make_workflow_evidence(3, latest_conclusion="failure")["workflows"]["asset_ranking.yml"]
    check = evaluate_workflow_runs("asset-ranking", failed, "agent/test", NOW)
    require(check["status"] == "BLOCKED" and check["metrics"]["latestConclusion"] == "failure",
            "最近周期失败必须阻断Beta")


def test_wrong_branch_and_missing_token_do_not_fake_evidence() -> None:
    payload = {"workflow_runs": [workflow_run(1, "2026-08-06T22:00:00Z", branch="main")]}
    check = evaluate_workflow_runs("macro-radar", payload, "agent/test", NOW)
    require(check["status"] == "BLOCKED" and check["metrics"]["observedCycles"] == 0,
            "其他分支运行不得算作当前分支证据")

    evidence = collect_workflow_evidence("example/repo", "agent/test", None)
    encoded = json.dumps(evidence, ensure_ascii=False)
    require(evidence["source"] == "unavailable", "缺少令牌时证据来源必须不可用")
    require(all(item.get("error") for item in evidence["workflows"].values()), "缺少令牌应逐工作流报错")
    require("Bearer" not in encoded and "token" not in encoded.lower(), "报告不得泄露认证头或令牌")


def test_scheduler_cycle_date_boundary() -> None:
    require(workflow_cycle_date(datetime(2026, 8, 6, 22, tzinfo=timezone.utc)) == "2026-08-06",
            "21:00 UTC后的运行应归入当日调度周期")
    require(workflow_cycle_date(datetime(2026, 8, 7, 2, tzinfo=timezone.utc)) == "2026-08-06",
            "次日凌晨运行应归入前一调度周期")


def test_read_only_workflow_contract() -> None:
    gate_path = ROOT / ".github/workflows/finance_terminal_beta_gate.yml"
    quality_path = ROOT / ".github/workflows/finance_terminal_quality.yml"
    gate = gate_path.read_text(encoding="utf-8")
    quality = quality_path.read_text(encoding="utf-8")
    require("workflow_dispatch:" in gate and "schedule:" in gate, "Beta门禁必须支持手动与每日观察")
    require("permissions:\n  actions: read\n  contents: read" in gate, "Beta门禁权限必须严格只读")
    require("contents: write" not in gate and "secrets." not in gate, "Beta门禁不得取得写权限或行情Secrets")
    require("GITHUB_TOKEN: ${{ github.token }}" in gate, "远端运行证据必须使用GitHub临时令牌")
    require("finance_terminal_release_gate.py" in gate and "readiness.json" in gate and "readiness.md" in gate,
            "Beta门禁未生成双格式报告")
    require("retention-days: 14" in gate and "actions/upload-artifact@v6" in gate,
            "Beta门禁Artifact保留规则错误")
    require("fail-on-blocked" not in gate, "观察工作流不得因BLOCKED状态丢失报告")
    require("validate_finance_terminal_release_gate.py" in quality,
            "金融终端只读质量CI未纳入门禁契约测试")
    require("finance_terminal_beta_gate.yml" in quality,
            "门禁工作流变化未纳入金融终端质量CI路径")


def test_repository_snapshot_and_cli_outputs() -> None:
    config = json.loads((ROOT / "apps/finance-terminal/data.json").read_text(encoding="utf-8"))
    macro = json.loads((ROOT / "apps/macro-radar/data.json").read_text(encoding="utf-8"))
    macro_health = json.loads((ROOT / "apps/macro-radar/health.json").read_text(encoding="utf-8"))
    page = (ROOT / "apps/finance-terminal/index.html").read_text(encoding="utf-8")
    report = build_report(config, macro, page, NOW)
    require(report["schemaVersion"] == 1 and len(report["checks"]) == 4, "仓库门禁报告结构错误")
    require(report["status"] in {"WARN", "BLOCKED"}, "当前旧快照不得被报告为全部通过")
    with tempfile.TemporaryDirectory() as tmp:
        json_path = Path(tmp) / "readiness.json"
        md_path = Path(tmp) / "readiness.md"
        json_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        md_path.write_text(render_markdown(report), encoding="utf-8")
        require(json.loads(json_path.read_text(encoding="utf-8"))["status"] == report["status"],
                "JSON报告无法重新读取")
        require(md_path.read_text(encoding="utf-8").startswith("# Ooglex金融终端上线准备报告"),
                "Markdown报告标题错误")

    full_report = build_report(
        config, macro, page, NOW, load_aggregate_inputs(), macro_health=macro_health,
    )
    require(len(full_report["checks"]) == 8, "仓库完整门禁缺少宏观或聚合管道检查")
    require(full_report["status"] == "BLOCKED", "当前过期聚合健康报告必须阻断Beta")


def main() -> None:
    test_fresh_core_with_explicit_demos()
    test_stale_is_warn_not_silent_pass()
    test_dgs10_source_attempt_status_is_independent()
    test_wrong_instrument_and_change_are_blocked()
    test_missing_disclosure_and_demo_flag_are_blocked()
    test_future_observation_is_blocked()
    test_us_business_day_contract()
    test_macro_source_health_gate()
    test_fresh_aggregate_pipelines_pass()
    test_stale_aggregate_health_blocks_beta()
    test_tampered_coverage_blocks_beta()
    test_failed_pipeline_with_snapshot_blocks_beta()
    test_recent_degraded_pipeline_warns()
    test_three_remote_cycles_pass_beta_evidence()
    test_duplicate_run_same_cycle_counts_once()
    test_insufficient_or_failed_remote_cycles_block()
    test_wrong_branch_and_missing_token_do_not_fake_evidence()
    test_scheduler_cycle_date_boundary()
    test_read_only_workflow_contract()
    test_repository_snapshot_and_cli_outputs()
    print("Finance terminal release gate core contract: PASS")
    print("- DGS10 / DTWEXBGS / RWTC source, unit, calculation and freshness: PASS")
    print("- five explicit demos and required public disclosures: PASS")
    print("- stale, future, wrong-instrument and malformed states: PASS")
    print("- macro source health alignment, fallback history and 72h freshness: PASS")
    print("- aggregate snapshot alignment, 72h freshness, coverage and failure states: PASS")
    print("- four GitHub workflows, cycle deduplication, branch scope and 3/7-day gates: PASS")


if __name__ == "__main__":
    main()
