#!/usr/bin/env python3
"""V33 fail-closed PIT evidence register for the fourteen required macro series.

This is a qualification inventory, not a vintage collector. Historical
release timestamps, provider redistribution rights and independently reviewed
raw releases MUST be proven elsewhere, never inferred from first_seen_at,
latest-revised FRED CSV, an ALFRED vintage *date*, or private DB row counts.
"""
import argparse
import json
from datetime import datetime, timezone
from pathlib import Path

from scripts.archive_asset_compass_observations import LEDGER, ROOT, load
from scripts.audit_asset_compass_real_history_v24 import audit as audit_v24
from scripts.audit_asset_compass_history_v32 import analyze as audit_v32
from scripts.check_asset_compass_history_readiness import REQUIRED_SERIES

SNAPSHOT = ROOT / "data" / "asset-scores.json"
OUTPUT = Path("/tmp/asset-compass-v33-pit-evidence.json")

# Candidate archives are discovery destinations, not claims of a certified
# historical release archive for the individual observation.
ARCHIVES = {
    "treasury": ("Treasury official historical yields",
                 "https://home.treasury.gov/resource-center/data-chart-center/interest-rates"),
    "bls": ("BLS official archived releases",
            "https://www.bls.gov/bls/news-release/cpi.htm"),
    "bea": ("BEA consumer spending release archive",
            "https://www.bea.gov/data/consumer-spending/main"),
    "fed_h41": ("Federal Reserve H.4.1 release archive",
                "https://www.federalreserve.gov/releases/h41/"),
    "liquidity": ("FRED/ALFRED candidate vintage services",
                  "https://fred.stlouisfed.org/docs/api/fred/series_vintagedates.html"),
    "nyfed": ("New York Fed reference rate publications",
               "https://www.newyorkfed.org/markets/reference-rates/effr"),
    "nyfed_recession": ("New York Fed yield-curve research",
                         "https://www.newyorkfed.org/research/capital_markets/ycfaq.html"),
}
FRED_VINTAGE_DOC = "https://fred.stlouisfed.org/docs/api/fred/series_observations.html"
STATUS = "requires_independent_release_and_license_review"


def source_family(series_id):
    if series_id.startswith("treasury."):
        return "treasury"
    if series_id.startswith("bls."):
        return "bls"
    if series_id.startswith("liquidity."):
        return "liquidity"
    return series_id.split(".")[0]


def qualify(rows, snapshot, *, private_db=None, now=None):
    checked = now or datetime.now(timezone.utc)
    v32 = audit_v32(rows, snapshot, checked)
    v24 = audit_v24(rows, private_db, now=checked)
    private = v24["private_historical_release_vintages"]
    registered = private.get("series", {})
    evidence = {}
    for sid in sorted(REQUIRED_SERIES):
        family = source_family(sid)
        archive_name, archive_url = ARCHIVES[family]
        observed = v32["series"][sid]
        raw_meta = registered.get(sid, {})
        private_versions = raw_meta.get("release_version_rows", 0)
        evidence[sid] = {
            "source_family": family,
            "discovery_resource": archive_name,
            "discovery_url": archive_url,
            "first_seen_versions": observed["archived_versions"],
            "first_seen_distinct_periods": observed["distinct_observation_periods"],
            "private_research_vintage_rows_unverified": private_versions,
            "private_license_review_status_untrusted": raw_meta.get("license_review_status"),
            "source_original_release_timestamp_verified": False,
            "provider_vintage_asof_value_verified": False,
            "original_release_artifact_integrity_verified": False,
            "redistribution_rights_approved": False,
            "historical_investable_asset_returns_verified": False,
            "status": STATUS,
        }
    if len(evidence) != 14 or set(evidence) != REQUIRED_SERIES:
        raise ValueError("Required evidence register is incomplete")
    blockers = list(dict.fromkeys(v32["blockers"] + v24["blockers"] + [
        "independent_original_release_timestamps_missing",
        "original_vintage_values_not_verified",
        "redistribution_license_review_not_approved",
        "historical_investable_asset_returns_missing",
        "multi_regime_out_of_sample_validation_missing",
    ]))
    return {
        "schema_version": 1,
        "report_type": "asset_compass_v33_pit_evidence_qualification",
        "audited_at": v32["as_of"],
        "required_series": len(REQUIRED_SERIES),
        "first_seen_covered_series": v32["archived_series_count"],
        "first_seen_ledger_records": v32["archive_record_count"],
        "private_db_status": private["status"],
        "private_research_vintage_rows_unverified": private["release_version_rows"],
        "independently_qualified_pit_series": 0,
        "evidence": evidence,
        "blocked_by": blockers,
        "official_release_time_resolution": "Must identify original release timestamp and timezone for each vintage; ALFRED vintage DATE alone does not establish intraday availability",
        "fred_alfred_vintage_api_documentation": FRED_VINTAGE_DOC,
        "first_seen_is_not_original_release_time": True,
        "eligible_for_point_in_time_backtest": False,
        "validated_for_live_scoring": False,
        "automatic_investment_alerts_enabled": False,
        "safe_for_public_research_only": True,
    }


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--ledger", type=Path, default=LEDGER)
    p.add_argument("--snapshot", type=Path, default=SNAPSHOT)
    p.add_argument("--private-db", type=Path,
                   help="Optional local SQLite outside the repository; never uploaded")
    p.add_argument("--output", type=Path, default=OUTPUT)
    p.add_argument("--require-qualified", action="store_true",
                   help="Fail unless 14 independently certified historical series (not currently available)")
    args = p.parse_args()
    snapshot = json.loads(args.snapshot.read_text(encoding="utf-8"))
    result = qualify(load(args.ledger), snapshot, private_db=args.private_db)
    # Refuse to output private research metadata within the public site repo.
    if args.private_db and args.output.resolve().is_relative_to(ROOT.resolve()):
        raise ValueError("Private DB evidence must not be exported into website repository")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2)+"\n",
                           encoding="utf-8")
    print(json.dumps({
        "covered": result["first_seen_covered_series"],
        "pit_qualified": result["independently_qualified_pit_series"],
        "private_db_status": result["private_db_status"],
        "backtest_allowed": False,
        "live_scores_allowed": False,
    }, ensure_ascii=False))
    if args.require_qualified:
        raise SystemExit("PIT eligibility not independently verified; fail closed")


if __name__ == "__main__":
    main()
