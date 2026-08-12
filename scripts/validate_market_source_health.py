#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""校验三条聚合行情管道的健康文件，并可输出只读汇总诊断。"""

from __future__ import annotations

import argparse
from copy import deepcopy
from datetime import datetime, timezone
import json
from pathlib import Path

from market_data_quality import make_data_meta
from market_source_health import (
    DATASET_SPECS,
    attach_upstream_health,
    make_source_health,
    validate_source_health,
)


ROOT = Path(__file__).resolve().parents[1]
DATASETS = {
    "asset-tracker": {
        "data": ROOT / "apps" / "asset-tracker" / "data.json",
        "health": ROOT / "apps" / "asset-tracker" / "health.json",
        "rowsKey": "assets",
    },
    "companies": {
        "data": ROOT / "apps" / "companies" / "data.json",
        "health": ROOT / "apps" / "companies" / "health.json",
        "rowsKey": "companies",
    },
    "asset-ranking": {
        "data": ROOT / "apps" / "asset-ranking" / "data.json",
        "health": ROOT / "apps" / "asset-ranking" / "health.json",
        "rowsKey": "assets",
    },
}


def run_contract_tests() -> None:
    snapshot_at = "2026-08-01T00:00:00Z"
    next_attempt = "2026-08-02T00:00:00Z"
    rows = [{
        "name": f"测试资产{index}",
        "dataMeta": make_data_meta(
            "market", "Yahoo Finance", as_of="2026-08-01", updated_at=snapshot_at, frequency="daily"
        ),
    } for index in range(28)]
    migrated = make_source_health(
        "asset-tracker",
        published_rows=rows,
        attempted_rows=rows,
        attempted_at=snapshot_at,
        published_snapshot_at=snapshot_at,
        published=True,
        migrated=True,
    )
    assert migrated["historyStatus"] == "migrated" and migrated["consecutiveFailures"] is None
    assert not validate_source_health(
        migrated, dataset="asset-tracker", published_rows=rows, published_snapshot_at=snapshot_at
    )

    failed_rows = [{
        "name": f"测试资产{index}",
        "dataMeta": make_data_meta(
            "unavailable", "Yahoo Finance", as_of=None, updated_at=next_attempt, frequency="daily"
        ),
    } for index in range(28)]
    failed = make_source_health(
        "asset-tracker",
        published_rows=rows,
        attempted_rows=failed_rows,
        attempted_at=next_attempt,
        published_snapshot_at=snapshot_at,
        published=False,
        previous_health=migrated,
        failure_reason="测试整源失败，保留旧快照。",
    )
    assert failed["status"] == "failed" and failed["consecutiveFailures"] == 1
    assert failed["snapshotPreserved"] is True and failed["lastSuccessfulAt"] == snapshot_at
    assert not validate_source_health(
        failed, dataset="asset-tracker", published_rows=rows, published_snapshot_at=snapshot_at
    )

    no_snapshot = make_source_health(
        "asset-tracker",
        published_rows=[],
        attempted_rows=failed_rows,
        attempted_at=next_attempt,
        published_snapshot_at=None,
        published=False,
        failure_reason="测试首次运行整源失败，无历史快照。",
    )
    assert no_snapshot["status"] == "failed" and no_snapshot["snapshotPreserved"] is False
    assert not validate_source_health(
        no_snapshot, dataset="asset-tracker", published_rows=[], published_snapshot_at=None
    )

    second_failed = make_source_health(
        "asset-tracker",
        published_rows=rows,
        attempted_rows=failed_rows,
        attempted_at="2026-08-03T00:00:00Z",
        published_snapshot_at=snapshot_at,
        published=False,
        previous_health=failed,
        failure_reason="测试连续失败。",
    )
    assert second_failed["consecutiveFailures"] == 2
    tampered = deepcopy(second_failed)
    tampered["coverage"]["freshCoveragePct"] = 0
    assert validate_source_health(
        tampered, dataset="asset-tracker", published_rows=rows, published_snapshot_at=snapshot_at
    )

    company_rows = [{
        "name": f"上市公司{index}",
        "private": False,
        "dataMeta": make_data_meta(
            "market", "Yahoo Finance", as_of="2026-08-01", updated_at=snapshot_at, frequency="daily"
        ),
    } for index in range(450)] + [{
        "name": f"未上市公司{index}",
        "private": True,
        "dataMeta": make_data_meta(
            "estimate", "multiples.vc公开融资估值汇总", as_of=None,
            updated_at=snapshot_at, frequency="irregular", status="partial" if index == 0 else "ok",
        ),
    } for index in range(50)]
    company_health = make_source_health(
        "companies", published_rows=company_rows, attempted_rows=company_rows,
        attempted_at=snapshot_at, published_snapshot_at=snapshot_at, published=True,
    )
    assert company_health["status"] == "healthy"
    assert all(source["status"] == "healthy" for source in company_health["sources"])
    assert not validate_source_health(
        company_health, dataset="companies", published_rows=company_rows,
        published_snapshot_at=snapshot_at,
    )

    ranking_rows = [{
        "name": f"公司资产{index}", "category": "company", "private": False, "static": False,
        "dataMeta": make_data_meta(
            "market", "Yahoo Finance", as_of="2026-08-01", updated_at=snapshot_at, frequency="daily"
        ),
    } for index in range(200)] + [{
        "name": f"其他行情{index}", "category": "commodity", "private": False, "static": False,
        "dataMeta": make_data_meta(
            "market", "Yahoo Finance", as_of="2026-08-01", updated_at=snapshot_at, frequency="daily"
        ),
    } for index in range(31)] + [{
        "name": f"加密资产{index}", "category": "crypto", "private": False, "static": False,
        "dataMeta": make_data_meta(
            "market", "CoinGecko", as_of="2026-08-01", updated_at=snapshot_at, frequency="daily"
        ),
    } for index in range(4)] + [{
        "name": f"公开估值{index}", "category": "real-estate", "private": False, "static": True,
        "dataMeta": make_data_meta(
            "estimate", "公开存量基准", as_of=None, updated_at=snapshot_at,
            frequency="irregular", status="partial" if index < 7 else "ok",
        ),
    } for index in range(15)]
    ranking_health = make_source_health(
        "asset-ranking", published_rows=ranking_rows, attempted_rows=ranking_rows,
        attempted_at=snapshot_at, published_snapshot_at=snapshot_at, published=True,
    )
    attach_upstream_health(
        ranking_health, source_id="companies-upstream", upstream_dataset="companies",
        upstream_health=company_health, upstream_snapshot_at=snapshot_at,
    )
    assert ranking_health["status"] == "healthy"
    assert all(source["status"] == "healthy" for source in ranking_health["sources"])
    assert not validate_source_health(
        ranking_health, dataset="asset-ranking", published_rows=ranking_rows,
        published_snapshot_at=snapshot_at,
    )

    proxy_rows = deepcopy(ranking_rows)
    proxy_rows[0]["dataMeta"].update({
        "status": "partial", "source": "Yahoo Finance · 公开存量基准（原始来源未结构化）",
    })
    proxy_health = make_source_health(
        "asset-ranking", published_rows=proxy_rows, attempted_rows=proxy_rows,
        attempted_at=snapshot_at, published_snapshot_at=snapshot_at, published=True,
    )
    attach_upstream_health(
        proxy_health, source_id="companies-upstream", upstream_dataset="companies",
        upstream_health=company_health, upstream_snapshot_at=snapshot_at,
    )
    assert proxy_health["status"] == "healthy"
    unregistered_proxy_rows = deepcopy(proxy_rows)
    unregistered_proxy_rows[0]["dataMeta"]["source"] = "Yahoo Finance · 静态流通量基准"
    unregistered_proxy_health = make_source_health(
        "asset-ranking", published_rows=unregistered_proxy_rows,
        attempted_rows=unregistered_proxy_rows, attempted_at=snapshot_at,
        published_snapshot_at=snapshot_at, published=True,
    )
    assert unregistered_proxy_health["status"] == "degraded"

    dynamic_fallback = deepcopy(company_rows)
    dynamic_fallback[0]["dataMeta"] = make_data_meta(
        "fallback", "Yahoo Finance", as_of="2026-07-31", updated_at="2026-07-31T00:00:00Z",
        frequency="daily",
    )
    degraded = make_source_health(
        "companies", published_rows=dynamic_fallback, attempted_rows=dynamic_fallback,
        attempted_at=next_attempt, published_snapshot_at=next_attempt, published=True,
        previous_health=company_health,
    )
    assert degraded["status"] == "degraded"


def read_json(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as error:
        raise SystemExit(f"缺少文件：{path.relative_to(ROOT)}") from error
    except json.JSONDecodeError as error:
        raise SystemExit(f"JSON无效：{path.relative_to(ROOT)} · {error}") from error


def validate_dataset(name: str) -> dict:
    spec = DATASETS[name]
    data = read_json(spec["data"])
    health = read_json(spec["health"])
    rows = data.get(spec["rowsKey"])
    if not isinstance(rows, list):
        raise SystemExit(f"{name} 的{spec['rowsKey']}必须为数组")
    errors = validate_source_health(
        health,
        dataset=name,
        published_rows=rows,
        published_snapshot_at=data.get("updatedAt"),
    )
    if errors:
        raise SystemExit(name + " 来源健康校验失败：\n- " + "\n- ".join(errors))
    coverage = health["coverage"]
    print(
        f"{name}: PASS · {health['status']} · fresh={coverage['freshCoveragePct']:.2f}%"
        f" · verified={coverage['verifiedCoveragePct']:.2f}% · failures={health['consecutiveFailures']}"
    )
    if health["status"] == "failed":
        print(f"::warning title={name} source health::连续失败{health['consecutiveFailures']}次；已保留最后有效快照")
    return health


def write_report(path: Path, results: list[dict]) -> None:
    counts = {status: sum(item["status"] == status for item in results)
              for status in ("healthy", "degraded", "failed")}
    overall = "failed" if counts["failed"] else "degraded" if counts["degraded"] else "healthy"
    report = {
        "contractVersion": 1,
        "generatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "status": overall,
        "summary": counts,
        "datasets": [{
            "dataset": item["dataset"],
            "status": item["status"],
            "lastAttemptAt": item["lastAttemptAt"],
            "lastSuccessfulAt": item["lastSuccessfulAt"],
            "consecutiveFailures": item["consecutiveFailures"],
            "snapshotPreserved": item["snapshotPreserved"],
            "coverage": item["coverage"],
            "sources": item["sources"],
        } for item in results],
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"诊断汇总：{path}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dataset", choices=[*DATASETS, "all"], default="all")
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    selected = list(DATASETS) if args.dataset == "all" else [args.dataset]
    missing_specs = set(selected) - set(DATASET_SPECS)
    if missing_specs:
        raise SystemExit("健康契约缺少数据集登记：" + ", ".join(sorted(missing_specs)))
    run_contract_tests()
    results = [validate_dataset(name) for name in selected]
    if args.report:
        write_report(args.report, results)


if __name__ == "__main__":
    main()
