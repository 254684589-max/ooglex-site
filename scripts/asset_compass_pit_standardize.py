#!/usr/bin/env python3
"""Research-only point-in-time rolling standardization for Asset Compass.

Only releases available at decision_at are visible. The comparison baseline
excludes the current observation; no guessed publication times or backfill.
This script NEVER creates asset-specific signals or unlocks public scores.
"""
import argparse
import json
import math
import sqlite3
import statistics
from datetime import date, timedelta
from pathlib import Path
from scripts.asset_compass_vintages import create_schema, timestamp

ROOT = Path(__file__).resolve().parents[1]


def calculate(db, series_id, decision_at, *, window_days=1827, min_history=36,
              max_age_days=120):
    if not isinstance(series_id, str) or not series_id.strip():
        raise ValueError("series_id required")
    if type(window_days) is not int or window_days < 30:
        raise ValueError("invalid lookback window")
    if type(min_history) is not int or min_history < 3:
        raise ValueError("minimum historical observations must be >=3")
    if type(max_age_days) is not int or max_age_days < 0:
        raise ValueError("invalid freshness threshold")

    cutoff = timestamp(decision_at)
    day = date.fromisoformat(cutoff[:10])
    start = (day - timedelta(days=window_days)).isoformat()
    # Rows can have multiple vintages: choose the last published revision as
    # of the decision instant, never the eventual final revision.
    rows = db.execute("""
        SELECT observation_date, available_at, value, source_release_id, source_url
        FROM macro_vintages
        WHERE series_id=? AND available_at<=?
          AND observation_date>=? AND observation_date<=?
        ORDER BY observation_date DESC, available_at DESC, vintage_id DESC
    """, (series_id, cutoff, start, day.isoformat())).fetchall()
    latest_by_day = {}
    for obs, released, value, release_id, url in rows:
        if obs not in latest_by_day:
            if not math.isfinite(value):
                raise ValueError("nonfinite stored vintage")
            latest_by_day[obs] = {
                "observation_date": obs, "available_at": released,
                "value": value, "source_release_id": release_id,
                "source_url": url
            }
    ordered = sorted(latest_by_day.values(), key=lambda x: x["observation_date"])
    result = {
        "report_type": "asset_compass_pit_rolling_standardization",
        "series_id": series_id,
        "decision_at": cutoff,
        "window_days": window_days,
        "min_history": min_history,
        "max_age_days": max_age_days,
        "historical_observations_seen": max(0, len(ordered) - 1),
        "status": "unavailable",
        "reason": None,
        "z_score": None,
        "latest_observation": ordered[-1] if ordered else None,
        "baseline_count": 0,
        "validated_for_live_scoring": False,
        "asset_specific_signal": None,
        "independent_factor_verified": False,
    }
    if not ordered:
        result["reason"] = "no_available_vintage"
        return result
    latest = ordered[-1]
    if (day - date.fromisoformat(latest["observation_date"])).days > max_age_days:
        result["reason"] = "latest_observation_stale"
        return result
    # Exactly one stored revision per observation period, and strictly earlier
    # periods used for baseline. Historical revisions must have release <= asof.
    baseline = ordered[:-1]
    result["baseline_count"] = len(baseline)
    if len(baseline) < min_history:
        result["reason"] = "insufficient_pit_history"
        return result
    values = [x["value"] for x in baseline]
    mean = statistics.fmean(values)
    std = statistics.pstdev(values, mu=mean)
    if not math.isfinite(std) or std <= 1e-12:
        result["reason"] = "zero_or_invalid_baseline_variance"
        return result
    z = (latest["value"] - mean) / std
    if not math.isfinite(z):
        result["reason"] = "nonfinite_standardized_value"
        return result
    result.update(status="research_only", reason=None, z_score=round(z, 8),
                  baseline_mean=mean, baseline_std=std,
                  baseline_start=baseline[0]["observation_date"],
                  baseline_end=baseline[-1]["observation_date"])
    return result


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--db", type=Path, required=True)
    p.add_argument("--series", required=True)
    p.add_argument("--asof", required=True, help="ISO datetime with UTC offset")
    p.add_argument("--min-history", type=int, default=36)
    p.add_argument("--window-days", type=int, default=1827)
    p.add_argument("--max-age-days", type=int, default=120)
    a = p.parse_args()
    if a.db.resolve().is_relative_to(ROOT.resolve()):
        raise ValueError("Private research DB must remain outside public repository")
    if not a.db.is_file():
        raise FileNotFoundError("No archived vintage database; refusing to create synthetic history")
    with sqlite3.connect(a.db) as db:
        create_schema(db)
        result = calculate(db, a.series, a.asof,
                           min_history=a.min_history,
                           window_days=a.window_days,
                           max_age_days=a.max_age_days)
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
