#!/usr/bin/env python3
"""V28 diagnose which required macro indicators reach the stored snapshot.

Read-only evidence audit. Never interprets absence as zero, never fetches,
synthesizes or certifies original economic release timestamps.
"""
import argparse
import json
from datetime import datetime, timezone
from pathlib import Path

from scripts.archive_asset_compass_observations import (
    LEDGER, ROOT, FIELDS, fingerprint, load, rows_from_snapshot, utc,
)
from scripts.check_asset_compass_history_readiness import REQUIRED_SERIES

SNAPSHOT = ROOT / "data" / "asset-scores.json"
OUTPUT = ROOT / "data" / "asset-compass-source-gaps-v28.json"

SOURCE_OWNER = {
    "bls.core_cpi": "BLS CUSR0000SA0L1E",
    "bea.core_pce": "BEA PCEPILFE via FRED",
    "fed_h41.total_assets": "Federal Reserve WALCL via FRED",
    "liquidity.reserves": "Federal Reserve WRESBAL via FRED",
    "liquidity.tga": "Federal Reserve WTREGEN via FRED",
    "liquidity.overnight_rrp": "NY Fed RRPONTSYD via FRED",
    "nyfed_recession.probability": "NY Fed capital markets allmonth.xls",
}
# This map identifies possible collectors, not proof of a successful download.
COLLECTOR = {
    "bls.core_cpi": "scripts/update_macro_bls.py",
    "bea.core_pce": "scripts/update_macro_fed_bea.py",
    "fed_h41.total_assets": "scripts/update_macro_fed_bea.py",
    "liquidity.reserves": "scripts/update_macro_liquidity.py",
    "liquidity.tga": "scripts/update_macro_liquidity.py",
    "liquidity.overnight_rrp": "scripts/update_macro_liquidity.py",
    "nyfed_recession.probability": "scripts/update_nyfed_recession.py",
}


def diagnose(snapshot, ledger, now):
    at = utc(now) if isinstance(now, str) else now
    if not isinstance(at, datetime) or at.tzinfo is None:
        raise ValueError("Timezone-aware audit time required")
    at = at.astimezone(timezone.utc)
    if snapshot.get("schema_version") != 1:
        raise ValueError("Snapshot schema mismatch")
    generated_at = utc(snapshot["generated_at"])
    if generated_at > at:
        raise ValueError("Snapshot generated in future")
    age_hours = round((at - generated_at).total_seconds() / 3600, 2)
    # Actual first-seen ledger cannot be edited and is not PIT release evidence.
    from scripts.check_asset_compass_archive_continuity_v25 import verify_ledger
    verify_ledger(ledger, now=at.isoformat())
    candidates = {r["series_id"]: r for r in rows_from_snapshot(snapshot, at.isoformat())}
    archived = {}
    for r in ledger:
        archived.setdefault(r["series_id"], set()).add(fingerprint(r))
    details = {}
    for sid in sorted(REQUIRED_SERIES):
        candidate = candidates.get(sid)
        versions = len(archived.get(sid, ()))
        if candidate is None:
            state = "missing_from_latest_snapshot"
        elif fingerprint(candidate) not in archived.get(sid, set()):
            state = "snapshot_present_not_yet_archived"
        else:
            state = "snapshot_observation_archived"
        details[sid] = {
            "status": state,
            "collector": COLLECTOR.get(sid, "scripts/update_asset_scores.py or scripts/update_macro_nyfed.py"),
            "expected_source": SOURCE_OWNER.get(sid, "US Treasury / BLS / NY Fed"),
            "archived_distinct_versions": versions,
            "latest_snapshot_observation_period": candidate["observation_period"] if candidate else None,
            "source_fetch_success_verified_by_audit": False,
        }
    missing = [s for s in sorted(REQUIRED_SERIES)
               if details[s]["status"] == "missing_from_latest_snapshot"]
    pending = [s for s in sorted(REQUIRED_SERIES)
               if details[s]["status"] == "snapshot_present_not_yet_archived"]
    return {
        "schema_version": 1,
        "report_type": "asset_compass_v28_source_gap_diagnostics",
        "checked_at": at.isoformat(),
        "snapshot_generated_at": generated_at.isoformat(),
        "snapshot_age_hours": age_hours,
        "snapshot_age_exceeds_48_hours": age_hours > 48,
        "required_series_count": len(REQUIRED_SERIES),
        "required_present_in_snapshot": len(REQUIRED_SERIES) - len(missing),
        "missing_from_snapshot": missing,
        "present_but_not_archived": pending,
        "series": details,
        "archive_total_rows": len(ledger),
        "collector_failure_reason_known_from_snapshot": False,
        "note": "Absence from committed snapshot does not prove the feed itself failed; inspect pipeline logs and persistence.",
        "official_historical_release_versions_verified": False,
        "eligible_for_point_in_time_backtest": False,
        "validated_for_live_scoring": False,
        "automatic_investment_alerts_enabled": False,
    }


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--snapshot", type=Path, default=SNAPSHOT)
    p.add_argument("--ledger", type=Path, default=LEDGER)
    p.add_argument("--output", type=Path, default=OUTPUT)
    p.add_argument("--fail-if-stale", action="store_true")
    a = p.parse_args()
    result = diagnose(json.loads(a.snapshot.read_text(encoding="utf-8")),
                      load(a.ledger), datetime.now(timezone.utc))
    a.output.parent.mkdir(parents=True, exist_ok=True)
    a.output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n",
                        encoding="utf-8")
    print(json.dumps({
        "required_present_in_snapshot": result["required_present_in_snapshot"],
        "required_series_count": result["required_series_count"],
        "missing_from_snapshot": result["missing_from_snapshot"],
        "present_but_not_archived": result["present_but_not_archived"],
        "snapshot_age_hours": result["snapshot_age_hours"],
        "validated_for_live_scoring": False,
    }, ensure_ascii=False))
    if a.fail_if_stale and result["snapshot_age_exceeds_48_hours"]:
        raise SystemExit(2)


if __name__ == "__main__":
    main()
