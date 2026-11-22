#!/usr/bin/env python3
"""V19 private point-in-time vintage quality audit. Never exports market signals.

Coverage is reported for explicitly requested *monthly* series only. For daily
and weekly data, business-day/holiday calendars are required before publishing
a comparable percentage. All reports are research-only, with missing != zero.
"""
import argparse
import json
import math
import sqlite3
from datetime import date
from pathlib import Path

from scripts.asset_compass_vintages import create_schema, timestamp

ROOT = Path(__file__).resolve().parents[1]


def month_index(day):
    d = date.fromisoformat(day[:10])
    return d.year * 12 + d.month - 1


def audit_series(db, series_id, decision_at, start_date, *, end_date=None,
                 min_monthly_coverage=0.8):
    asof = timestamp(decision_at)
    start = date.fromisoformat(start_date)
    end = date.fromisoformat(end_date) if end_date else date.fromisoformat(asof[:10])
    if start > end or end > date.fromisoformat(asof[:10]):
        raise ValueError("Invalid audit interval or end after decision time")
    if not 0 <= min_monthly_coverage <= 1 or not math.isfinite(min_monthly_coverage):
        raise ValueError("Invalid coverage threshold")
    metadata = db.execute(
        "SELECT source,frequency,units FROM macro_series WHERE series_id=?",
        (series_id,)).fetchone()
    result = {
        "schema_version": 1, "report_type": "asset_compass_vintage_quality",
        "series_id": series_id, "decision_at": asof,
        "window_start": start.isoformat(), "window_end": end.isoformat(),
        "source": metadata[0] if metadata else None,
        "frequency": metadata[1] if metadata else None,
        "units": metadata[2] if metadata else None,
        "observed_periods": 0, "release_versions": 0, "revised_periods": 0,
        "invalid_source_rows": 0, "duplicate_month_periods": 0,
        "coverage_ratio": None, "expected_months": None,
        "missing_months": None, "status": "unavailable", "reason": None,
        "validated_for_live_scoring": False,
        "asset_specific_contributions_available": False,
        "historical_model_validated": False,
    }
    if metadata is None:
        result["reason"] = "series_not_registered"
        return result
    rows = db.execute("""
       SELECT observation_date, available_at, value, source_release_id, source_url
       FROM macro_vintages
       WHERE series_id=? AND observation_date BETWEEN ? AND ?
         AND available_at<=?
       ORDER BY observation_date, available_at, vintage_id
    """, (series_id, start.isoformat(), end.isoformat(), asof)).fetchall()
    revisions = {}
    latest = {}
    invalid = 0
    for obs, released, value, release_id, url in rows:
        if (not isinstance(release_id, str) or not release_id.strip()
            or not isinstance(url, str) or not url.startswith("https://")
            or not isinstance(value, (int, float)) or not math.isfinite(value)):
            invalid += 1
            continue
        revisions[obs] = revisions.get(obs, 0) + 1
        latest[obs] = (released, value, release_id, url)
    result.update(observed_periods=len(latest), release_versions=sum(revisions.values()),
                  revised_periods=sum(v > 1 for v in revisions.values()),
                  invalid_source_rows=invalid)
    if invalid:
        result["reason"] = "invalid_provenance_rows"
        return result
    if not latest:
        result["reason"] = "no_asof_observations"
        return result
    if metadata[1].lower() not in ("monthly", "month", "m"):
        result["status"] = "research_only"
        result["reason"] = "coverage_requires_frequency_calendar"
        return result
    start_m, end_m = month_index(start.isoformat()), month_index(end.isoformat())
    expected = end_m - start_m + 1
    months = {month_index(obs) for obs in latest}
    result["expected_months"] = expected
    result["duplicate_month_periods"] = len(latest) - len(months)
    result["missing_months"] = [
        f"{m // 12:04d}-{m % 12 + 1:02d}"
        for m in range(start_m, end_m + 1) if m not in months
    ]
    result["coverage_ratio"] = round(len(months) / expected, 6)
    result["status"] = "research_only"
    if result["duplicate_month_periods"]:
        result["reason"] = "multiple_observation_dates_per_month"
    elif result["coverage_ratio"] < min_monthly_coverage:
        result["reason"] = "monthly_coverage_below_research_threshold"
    return result


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--db", type=Path, required=True)
    p.add_argument("--series", required=True)
    p.add_argument("--asof", required=True)
    p.add_argument("--start", required=True, help="YYYY-MM-DD")
    p.add_argument("--end", help="YYYY-MM-DD, defaults to as-of date")
    a = p.parse_args()
    if a.db.resolve().is_relative_to(ROOT.resolve()):
        raise ValueError("Research DB must remain outside website repository")
    if not a.db.is_file():
        raise FileNotFoundError("Historical vintage archive not found")
    with sqlite3.connect(a.db) as db:
        create_schema(db)
        out = audit_series(db, a.series, a.asof, a.start, end_date=a.end)
    print(json.dumps(out, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
