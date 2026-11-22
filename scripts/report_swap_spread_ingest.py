#!/usr/bin/env python3
"""Produce restricted run evidence for Ooglex SOFR scheduled ingestion.

Reads only the historical data file and sanitized ingestion stdout/stderr.
Never modifies a market-data file or contains full source responses.
"""
import argparse
from datetime import date, datetime, timezone
import json
from pathlib import Path
import re

APPENDED = re.compile(r"^APPENDED (\d{4}-\d{2}-\d{2})$", re.M)
UNCHANGED = re.compile(r"^UNCHANGED (\d{4}-\d{2}-\d{2})$", re.M)


def classify(exit_code, output):
    """Conservative result classification, independent of GitHub action green/red UI."""
    additions = APPENDED.findall(output)
    unchanged = UNCHANGED.findall(output)
    if exit_code == 0:
        if len(additions) == 1 and not unchanged:
            return "new_observation"
        if len(unchanged) == 1 and not additions:
            return "no_new_observation"
        return "unverified_success"
    if "Historical observation changed" in output:
        return "source_revision_conflict"
    if "No matching official Treasury observation" in output:
        return "date_mismatch"
    if "Missing mandatory SOFR tenors" in output or "Refusing derived/unclear tenor" in output:
        return "incomplete_or_unsupported_tenors"
    if "Source is older than archived latest observation" in output:
        return "source_behind_archive"
    return "ingestion_error"


def summarize(history, exit_code, output, timestamp, *, workflow_run=None):
    observations = history.get("observations")
    if history.get("schemaVersion") != 2 or history.get("demo") is not False or not isinstance(observations, list):
        raise ValueError("Invalid original history document")
    days = []
    for entry in observations:
        day = date.fromisoformat(entry["asOf"])
        if len(entry["tenors"]) != 6:
            raise ValueError("Invalid number of archived tenors")
        days.append(day)
    if len(days) != len(set(days)):
        raise ValueError("Duplicate archived observations")
    latest = max(days) if days else None
    state = classify(exit_code, output)
    now = datetime.fromisoformat(timestamp.replace("Z","+00:00"))
    if now.tzinfo is None:
        raise ValueError("Timestamp must have a timezone")
    days_old = (now.date()-latest).days if latest else None
    details = {
        "schemaVersion": 1,
        "monitor": "sofr_swap_spread_daily_ingestion",
        "reportedAt": now.astimezone(timezone.utc).isoformat(timespec="seconds").replace("+00:00","Z"),
        "runId": str(workflow_run) if workflow_run else None,
        "ingestionExitCode": exit_code,
        "ingestionResult": state,
        "archiveObservations": len(days),
        "lastArchivedObservationDate": latest.isoformat() if latest else None,
        "ageCalendarDays": days_old,
        "stale": days_old is None or days_old > 7,
        "sourceFrequency": "daily",
        "rateDataPublishedByThisReport": False,
        "note": "No trading-day continuity or production scheduler success is inferred from this single report."
    }
    return details


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--history", type=Path, required=True)
    parser.add_argument("--ingest-log", type=Path, required=True)
    parser.add_argument("--ingest-exit", type=int, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--run-id", default="")
    args = parser.parse_args()
    if args.output.resolve() == args.history.resolve():
        parser.error("Cannot overwrite the historical market-data file")
    history=json.loads(args.history.read_text(encoding="utf-8"))
    content=args.ingest_log.read_text(encoding="utf-8") if args.ingest_log.exists() else ""
    now=datetime.now(timezone.utc).isoformat()
    evidence=summarize(history,args.ingest_exit,content,now,workflow_run=args.run_id)
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(evidence,indent=2,ensure_ascii=False)+"\n",encoding="utf-8")
    print(json.dumps(evidence,ensure_ascii=False))
    return evidence


if __name__ == "__main__":
    main()
