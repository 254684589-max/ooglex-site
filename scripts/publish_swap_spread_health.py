#!/usr/bin/env python3
"""Publish a minimal last-SUCCESSFUL-ingestion heartbeat. Never publishes prices.

Only the scheduled, validated production ingestion may advance this status.
A failed ingestion must not overwrite an older successful heartbeat.
"""
import argparse
from datetime import date, datetime, timezone
import json
from pathlib import Path


def build(evidence):
    status = evidence.get("ingestionResult")
    if status not in ("new_observation", "no_new_observation"):
        raise ValueError("Only verified, successful ingestions may write a heartbeat")
    if evidence.get("ingestionExitCode") != 0:
        raise ValueError("Cannot publish status for failed ingestion")
    if evidence.get("rateDataPublishedByThisReport") is not False:
        raise ValueError("Unexpected evidence schema")
    checked_at = evidence["reportedAt"]
    d = datetime.fromisoformat(checked_at.replace("Z","+00:00"))
    if d.tzinfo is None:
        raise ValueError("Timestamp lacks timezone")
    latest = evidence.get("lastArchivedObservationDate")
    if not latest:
        raise ValueError("No archived observation")
    date.fromisoformat(latest)
    observations = evidence["archiveObservations"]
    if not isinstance(observations, int) or isinstance(observations, bool) or observations < 1:
        raise ValueError("Invalid archived observation count")
    return {
        "schemaVersion": 1,
        "type": "sofr-last-successful-ingestion",
        "status": "successful",
        "runResult": status,
        "lastSuccessAt": d.astimezone(timezone.utc).isoformat(timespec="seconds").replace("+00:00","Z"),
        "lastDataAsOf": latest,
        "observations": observations,
        "runId": str(evidence.get("runId") or ""),
        "source": "CheckMySwap indicative USD SOFR OIS plus U.S. Treasury CMT",
        "frequency": "scheduled_US_weekday_reference",
        "note": "Last successful ingest only. Later failed runs are not reflected here. Not real-time or executable prices."
    }


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--evidence",type=Path,required=True)
    parser.add_argument("--output",type=Path,required=True)
    args=parser.parse_args()
    if args.output.resolve()==args.evidence.resolve():
        parser.error("Evidence and output paths must differ")
    evidence=json.loads(args.evidence.read_text(encoding="utf-8"))
    status=build(evidence)
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(status,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print("SUCCESS_MARKER",status["lastSuccessAt"],status["runResult"],status["lastDataAsOf"])


if __name__=="__main__":
    main()
