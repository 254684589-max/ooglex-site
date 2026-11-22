#!/usr/bin/env python3
"""V54 public score-readiness contract derived from real Ooglex source snapshots.

Reports what is present and what is MISSING in the six asset-specific factor
groups. THIS IS NOT A SIGNAL GENERATOR OR HISTORICAL MODEL CERTIFICATION.
No synthetic points, zero-filled factors, mock scores or sample P&L.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlsplit

from scripts.score_macro_assets import validate_config, score_one

ROOT = Path(__file__).resolve().parents[1]
SOURCES = {
    "snapshot": ROOT / "data" / "asset-scores.json",
    "observations": ROOT / "data" / "asset-compass-factor-observations.json",
    "history": ROOT / "data" / "asset-compass-history-readiness.json",
    "config": ROOT / "macro" / "model-config.json",
}
OUTPUT = ROOT / "data" / "asset-compass-scoring-readiness-v54.json"
GROUP_NAMES = {
    "rates": "利率与货币政策",
    "inflation": "通胀",
    "growth": "增长与就业",
    "liquidity": "流动性",
    "risk": "风险与信用",
    "asset_specific": "资产专属估值与资金流",
}
ASSET_NAMES = {
    "gold": "黄金",
    "us_equities": "美股",
    "us_long_bonds": "美国长期国债",
    "usd": "美元",
    "bitcoin": "比特币",
    "oil": "原油",
}
SCHEMA = 1


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True,
                      separators=(",", ":"), allow_nan=False).encode("utf-8")


def hash_input(value):
    return hashlib.sha256(canonical(value)).hexdigest()


def instant(value):
    if not isinstance(value, str):
        raise ValueError("UTC-aware source timestamp required")
    try:
        date = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise ValueError("Malformed source timestamp") from exc
    if date.tzinfo is None or date.utcoffset() is None:
        raise ValueError("Naive source timestamp prohibited")
    return date.astimezone(timezone.utc)


def build(snapshot, observations, history, config, *, now=None):
    now = now or datetime.now(timezone.utc)
    if now.tzinfo is None:
        raise ValueError("As-of must be timezone-aware")
    now = now.astimezone(timezone.utc)
    config = validate_config(config)
    groups = config["factor_order"]
    if set(groups) != set(GROUP_NAMES) or set(config["weights"]) != set(ASSET_NAMES):
        raise ValueError("Unexpected factor/asset scope")
    if snapshot.get("schema_version") != 1:
        raise ValueError("Missing official macro snapshot")
    if (not isinstance(snapshot.get("assets"), dict)
            or set(snapshot["assets"]) != set(ASSET_NAMES)
            or not isinstance(snapshot.get("scoring"), dict)):
        raise ValueError("Unverified assets or scoring schema")
    score_meta = snapshot["scoring"]
    # This V54 report is for pre-calibration only. Any future approved output
    # requires explicit new provenance contract, not silent inheritance.
    if (score_meta.get("calibration_verified") is not False
            or score_meta.get("out_of_sample_verified") is not False):
        raise ValueError("Research report cannot certify published model scores")
    for asset in ASSET_NAMES:
        obj = snapshot["assets"][asset]
        if (not isinstance(obj, dict) or obj.get("score") is not None
                or obj.get("status") != "unavailable"
                or obj.get("coverage_pct") != 0):
            raise ValueError("Unexpected asset score or input coverage")

    generated = instant(snapshot.get("generated_at"))
    if generated > now:
        raise ValueError("Future source snapshot generation")
    if (observations.get("schema_version") != 1 or
            observations.get("report_type") != "asset_compass_factor_observations"
            or observations.get("validated_for_live_scoring") is not False
            or observations.get("factor_signals_calibrated") is not False
            or observations.get("asset_specific_contributions_available") is not False
            or not isinstance(observations.get("groups"), dict)
            or set(observations["groups"]) != set(GROUP_NAMES)):
        raise ValueError("Factor observations have invalid/misleading evidence flags")
    if observations.get("source_snapshot_observation_date") != snapshot.get("observation_date"):
        raise ValueError("Source observation date mismatch")
    factor_generated = instant(observations.get("generated_at"))
    if factor_generated > now:
        raise ValueError("Future factor observations")
    if factor_generated < generated:
        raise ValueError("Factor report predates source snapshot")

    if (history.get("schema_version") != 1
            or history.get("report_type") != "asset_compass_history_readiness"
            or history.get("validated_for_live_scoring") is not False
            or history.get("eligible_for_point_in_time_backtest") is not False):
        raise ValueError("Historical PIT evidence cannot be inferred")
    archived = history.get("archived_observations")
    source_mismatches = history.get("treasury_source_year_mismatch_rows")
    if (type(archived) is not int or archived < 0
            or type(source_mismatches) is not int or source_mismatches < 0):
        raise ValueError("Invalid historical provenance totals")

    group_reports = {}
    observation_total = 0
    seen = set()
    for group in groups:
        entry = observations["groups"][group]
        rows = entry.get("observations")
        if not isinstance(rows, list):
            raise ValueError("Missing real source observation list")
        if entry.get("status") not in ("unavailable", "observations_only"):
            raise ValueError("Unexpected source evidence status")
        if (bool(rows) and entry["status"] != "observations_only") or (
                not rows and entry["status"] != "unavailable"):
            raise ValueError("Factor-group observation state mismatch")
        source_ids = []
        for obs in rows:
            if not isinstance(obs, dict):
                raise ValueError("Invalid source observation")
            oid = obs.get("id")
            val = obs.get("value")
            period = obs.get("observation_period")
            url = obs.get("source_url")
            if (not isinstance(oid, str) or not oid or (group, oid) in seen
                    or type(val) not in (int, float) or not math.isfinite(val)
                    or not isinstance(period, str) or not period
                    or not isinstance(url, str)
                    or urlsplit(url).scheme != "https" or not urlsplit(url).hostname
                    or obs.get("qualifies_as_model_factor_signal") is not False
                    or obs.get("validated_historical_release_time") is not False):
                raise ValueError("Observation is not a valid, research-only source")
            seen.add((group, oid))
            source_ids.append(oid)
        observation_total += len(rows)
        group_reports[group] = {
            "label": GROUP_NAMES[group],
            "source_observation_count": len(rows),
            "source_ids": source_ids,
            "source_status": "observations_only" if rows else "missing_observations",
            "model_signal_status": "missing_independently_verified_asset_specific_signal",
            "qualified_signal_count": 0,
            "historical_calibration_passed": False,
            "out_of_sample_validation_passed": False,
        }

    assets = {}
    for asset in ASSET_NAMES:
        weights = dict(zip(groups, config["weights"][asset]))
        actual = score_one(asset, {}, config, {})
        if (actual["status"] != "unavailable" or actual["score"] is not None
                or actual["coverage_pct"] != 0):
            raise ValueError("Research readiness must not publish a score")
        research_weight = sum(weights[g] for g in groups
                              if group_reports[g]["source_observation_count"])
        assets[asset] = {
            "label": ASSET_NAMES[asset],
            "status": "unavailable",
            "score": None,
            "source_observation_weight_pct_research_only": research_weight,
            "qualified_model_signal_coverage_pct": 0,
            "qualified_factor_group_count": 0,
            "requires_factor_group_count": config["guardrails"]["minimum_factor_groups"],
            "requires_weight_coverage_pct": config["guardrails"]["minimum_weight_coverage_percent"],
            "blocked_by": actual["blocked_by"],
            "missing_source_groups": [g for g in groups if not group_reports[g]["source_observation_count"]],
            "unqualified_factor_groups": list(groups),
            "weights_pct": weights,
            "historical_calibration_passed": False,
            "out_of_sample_validation_passed": False,
            "validated_for_live_scoring": False,
        }

    return {
        "schema_version": SCHEMA,
        "report_type": "asset_compass_v54_scoring_readiness",
        "status": "research_only_no_authorized_scores",
        "generated_at": now.isoformat().replace("+00:00", "Z"),
        "source_snapshot_generated_at": snapshot["generated_at"],
        "source_observations_generated_at": observations["generated_at"],
        "input_sha256": {key: hash_input(value) for key, value in (
            ("snapshot", snapshot), ("observations", observations),
            ("history", history), ("config", config))},
        "model": config["model"],
        "asset_count": len(assets),
        "factor_group_count": len(group_reports),
        "research_observations_present": observation_total,
        "groups_with_source_observations": sum(
            bool(v["source_observation_count"]) for v in group_reports.values()),
        "groups_without_source_observations": sum(
            not v["source_observation_count"] for v in group_reports.values()),
        "independently_qualified_factor_groups": 0,
        "source_pit_qualified_count": 0,
        "website_archived_first_seen_records": archived,
        "treasury_source_year_mismatch_records": source_mismatches,
        "groups": group_reports,
        "assets": assets,
        "limitations": [
            "Public snapshot levels are not signed or calibrated factor signals.",
            "Source observations are not historical PIT release vintages.",
            "Research-only source weight coverage is NOT qualified scoring coverage.",
            "Risk/credit and asset-specific source groups lack approved observations.",
            "Scores and simulated shadow scores are never generated by this report.",
        ],
        "validated_for_live_scoring": False,
        "automatic_trading_alerts_enabled": False,
    }


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--snapshot", type=Path, default=SOURCES["snapshot"])
    p.add_argument("--observations", type=Path, default=SOURCES["observations"])
    p.add_argument("--history", type=Path, default=SOURCES["history"])
    p.add_argument("--config", type=Path, default=SOURCES["config"])
    p.add_argument("--output", type=Path, default=OUTPUT)
    args = p.parse_args()
    def read(path):
        return json.loads(path.read_text(encoding="utf-8"))
    report = build(read(args.snapshot), read(args.observations),
                   read(args.history), read(args.config))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n",
                           encoding="utf-8")
    print(json.dumps({
        "status": report["status"],
        "assets": report["asset_count"],
        "groups_with_observations": report["groups_with_source_observations"],
        "independently_qualified_groups": 0,
        "published_scores": 0,
        "historical_pit_certified": 0,
    }, ensure_ascii=False))


if __name__ == "__main__":
    main()
