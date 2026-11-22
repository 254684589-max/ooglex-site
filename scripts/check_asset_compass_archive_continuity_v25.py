#!/usr/bin/env python3
"""V25 fail-closed continuity checks for the Ooglex first-seen macro archive.

The snapshot generated_at is *not* an official economic release timestamp.
Never backdate or certify historical vintages from a downloaded latest value.
"""
import argparse
import json
from datetime import datetime, timezone
from pathlib import Path

from scripts.archive_asset_compass_observations import (
    FIELDS, append_ledger, fingerprint, load, rows_from_snapshot, utc
)

ROOT = Path(__file__).resolve().parents[1]


def preflight(snapshot, now, max_snapshot_hours=48):
    checked_at = utc(now)
    if not isinstance(snapshot, dict) or snapshot.get("schema_version") != 1:
        raise ValueError("Invalid source snapshot")
    source_at = utc(snapshot.get("generated_at"))
    age = (checked_at - source_at).total_seconds() / 3600
    if age < 0:
        raise ValueError("Snapshot generation is in the future")
    if not 0 <= age <= max_snapshot_hours:
        raise ValueError("Snapshot is stale; refusing to relabel old data as newly observed")
    if snapshot.get("status") not in ("partial_data_no_full_score", "ok_no_full_score"):
        raise ValueError("Unexpected source snapshot status")
    expected = rows_from_snapshot(snapshot, checked_at.isoformat())
    return {"snapshot_generated_at": source_at.isoformat(),
            "snapshot_age_hours": round(age, 3),
            "candidate_rows": len(expected)}


def verify_ledger(rows, *, now):
    instant = utc(now)
    # Validate immutable flags, timestamps, full record shape and duplicates
    append_ledger(rows, [])
    last = None
    for row in rows:
        if any(k not in row for k in (
            "series_id", "observation_period", "value", "unit", "source_url",
            "first_seen_at", "provenance", "official_release_time_known",
            "eligible_for_historical_official_vintage"
        )):
            raise ValueError("Incomplete archive row")
        if row["series_id"] not in FIELDS:
            raise ValueError("Unregistered indicator in ledger")
        if row["provenance"] != "observed_snapshot_first_seen_not_original_release":
            raise ValueError("Invalid historical provenance marker")
        if not isinstance(row["source_url"], str) or not row["source_url"].startswith("https://"):
            raise ValueError("Missing HTTPS source")
        time = utc(row["first_seen_at"])
        if time > instant:
            raise ValueError("Archive records observations from the future")
        if last and time < last:
            raise ValueError("Archive sequence is not chronological")
        last = time
        fingerprint(row)
    return {"archive_rows": len(rows),
            "distinct_series": len({r["series_id"] for r in rows}),
            "latest_first_seen_at": last.isoformat() if last else None,
            "official_historical_vintages_verified": False,
            "validated_for_live_scoring": False}


def verify_growth(before, after, *, now):
    verify_ledger(before, now=now)
    status = verify_ledger(after, now=now)
    # An append-only ledger must preserve all prior entries *and their order*.
    if after[:len(before)] != before:
        raise ValueError("Archive lost or modified earlier versions")
    if not after:
        raise ValueError("Archive remains empty")
    status["added_rows"] = len(after) - len(before)
    return status


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=("preflight", "postflight"), required=True)
    parser.add_argument("--snapshot", type=Path, default=ROOT / "data" / "asset-scores.json")
    parser.add_argument("--ledger", type=Path, default=ROOT / "data" / "asset-compass-observation-ledger.jsonl")
    parser.add_argument("--before", type=Path, help="A copy of ledger before attempted archival")
    parser.add_argument("--max-snapshot-hours", type=float, default=48)
    args = parser.parse_args()
    now = datetime.now(timezone.utc).isoformat()
    if args.mode == "preflight":
        result = preflight(json.loads(args.snapshot.read_text(encoding="utf-8")),
                           now, max_snapshot_hours=args.max_snapshot_hours)
        verify_ledger(load(args.ledger), now=now)
    else:
        if args.before is None:
            parser.error("postflight requires --before")
        result = verify_growth(load(args.before), load(args.ledger), now=now)
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))


if __name__ == "__main__":
    main()
