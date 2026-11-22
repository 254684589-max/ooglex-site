#!/usr/bin/env python3
"""V24 evidence-aware readiness audit. Outputs counts only, never raw observations.

Snapshot first-seen timestamps and operator-supplied historical release vintages
are separate evidence lanes. Neither alone certifies official publication times,
data redistribution rights, or model suitability.
"""
import argparse
import json
import sqlite3
from datetime import datetime, timezone
from pathlib import Path

from scripts.archive_asset_compass_observations import load, utc
from scripts.check_asset_compass_history_readiness import report as first_seen_report

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_LEDGER = ROOT / "data" / "asset-compass-observation-ledger.jsonl"
DEFAULT_OUTPUT = ROOT / "data" / "asset-compass-v24-history-audit.json"


def _private_database_counts(path, now):
    if path is None:
        return {"status": "private_pit_db_not_provided",
                "registered_series": 0, "release_version_rows": 0,
                "distinct_observation_periods": 0, "future_release_rows": 0,
                "series": {}}
    path = Path(path).resolve()
    if path.is_relative_to(ROOT.resolve()):
        raise ValueError("Private historical database must be outside repository")
    if not path.is_file():
        return {"status": "private_pit_db_missing",
                "registered_series": 0, "release_version_rows": 0,
                "distinct_observation_periods": 0, "future_release_rows": 0,
                "series": {}}
    with sqlite3.connect(f"file:{path.as_posix()}?mode=ro", uri=True) as db:
        tables = {r[0] for r in db.execute(
            "SELECT name FROM sqlite_master WHERE type='table'")}
        if not {"macro_series", "macro_vintages"}.issubset(tables):
            return {"status": "invalid_pit_schema",
                    "registered_series": 0, "release_version_rows": 0,
                    "distinct_observation_periods": 0, "future_release_rows": 0,
                    "series": {}}
        lines = db.execute("""
          SELECT s.series_id, s.frequency, s.license_review_status,
            COUNT(v.vintage_id), COUNT(DISTINCT v.observation_date),
            SUM(CASE WHEN v.available_at > ? THEN 1 ELSE 0 END)
          FROM macro_series s LEFT JOIN macro_vintages v
             ON s.series_id = v.series_id
          GROUP BY s.series_id, s.frequency, s.license_review_status
          ORDER BY s.series_id
        """, (now.isoformat(),)).fetchall()
    series = {
        sid: {"frequency": frequency, "license_review_status": license_state,
              "release_version_rows": versions, "distinct_observation_periods": periods,
              "future_release_rows": future or 0}
        for sid, frequency, license_state, versions, periods, future in lines
    }
    return {
        "status": "research_vintages_present_not_independently_verified"
                  if any(x["release_version_rows"] for x in series.values())
                  else "empty_pit_database",
        "registered_series": len(series),
        "release_version_rows": sum(x["release_version_rows"] for x in series.values()),
        "distinct_observation_periods": sum(x["distinct_observation_periods"] for x in series.values()),
        "future_release_rows": sum(x["future_release_rows"] for x in series.values()),
        "series": series,
    }


def audit(ledger_rows, private_db=None, *, now=None):
    now = utc(now) if isinstance(now, str) else now or datetime.now(timezone.utc)
    if now.tzinfo is None:
        raise ValueError("Audit time must have timezone")
    now = now.astimezone(timezone.utc)
    for row in ledger_rows:
        seen = utc(row["first_seen_at"])
        if seen > now:
            raise ValueError("Archive contains first_seen timestamp in the future")
    initial = first_seen_report(ledger_rows)
    private = _private_database_counts(private_db, now)
    blockers = list(initial["blockers"])
    if initial["archived_observations"] == 0:
        blockers.append("first_seen_observation_ledger_missing_or_empty")
    if private["status"] != "research_vintages_present_not_independently_verified":
        blockers.append("no_private_historical_release_vintages")
    if private["future_release_rows"]:
        blockers.append("future_release_rows_present_in_private_db")
    blockers.extend([
        "official_release_provenance_not_independently_certified",
        "historical_data_redistribution_rights_not_certified",
        "factor_calibration_not_validated",
    ])
    return {
        "schema_version": 1,
        "report_type": "asset_compass_v24_historical_evidence_audit",
        "audit_at": now.isoformat(),
        "first_seen_archive": {
            "status": initial["status"],
            "record_count": initial["archived_observations"],
            "series": initial["series"],
            "official_release_time_known": False,
            "eligible_for_historical_official_vintage": False,
        },
        "private_historical_release_vintages": private,
        "blockers": list(dict.fromkeys(blockers)),
        "official_historical_release_times_certified": False,
        "historical_data_license_certified": False,
        "eligible_for_point_in_time_backtest": False,
        "validated_for_live_scoring": False,
        "asset_specific_contributions_available": False,
        "automatic_alerts_enabled": False,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ledger", type=Path, default=DEFAULT_LEDGER)
    parser.add_argument("--private-db", type=Path)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    a = parser.parse_args()
    if a.output.resolve().is_relative_to(ROOT.resolve()) and a.private_db:
        raise ValueError("Private DB audit metadata must not be published into the site")
    result = audit(load(a.ledger), a.private_db)
    a.output.parent.mkdir(parents=True, exist_ok=True)
    a.output.write_text(json.dumps(result, ensure_ascii=False, indent=2)+"\n",
                        encoding="utf-8")
    print("V24 archive rows:", result["first_seen_archive"]["record_count"],
          "PIT rows:", result["private_historical_release_vintages"]["release_version_rows"],
          "live scoring:", result["validated_for_live_scoring"])


if __name__ == "__main__":
    main()
