#!/usr/bin/env python3
"""Read-only live SOFR/Treasury pipeline smoke probe.

Runs the actual ingestion parsing contract without writing the production archive.
Never asserts a fresh market quote when a dated API returns an older snapshot.
"""
import argparse
from datetime import date, datetime, timezone
import hashlib
import json
from pathlib import Path
import sys
from urllib.error import HTTPError, URLError

from update_swap_spreads import (
    OUTPUT, OIS_URL, TREASURY_URL, build_observation,
    request_bytes, treasury_by_day,
)

ROOT = Path(__file__).resolve().parents[1]


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def latest_date(document):
    dates = []
    for item in document.get("observations", []):
        d = date.fromisoformat(item["asOf"])
        dates.append(d)
    if len(set(dates)) != len(dates):
        raise ValueError("Archive contains duplicate observation dates")
    return max(dates).isoformat() if dates else None


def check_sources(history, fetch=request_bytes, now=None):
    now = now or datetime.now(timezone.utc)
    checked_at = now.isoformat(timespec="seconds")
    archived = latest_date(history)
    report = {
        "schemaVersion": 1,
        "reportType": "sofr-live-read-only-smoke",
        "checkedAt": checked_at,
        "archiveLatestDate": archived,
        "published": False,
        "writesProductionHistory": False,
        "status": "unavailable",
    }
    try:
        swap_blob = fetch(OIS_URL)
    except (HTTPError, URLError, OSError) as error:
        report.update(status="source_unavailable", reason=type(error).__name__,
                      source="CheckMySwap")
        return report
    report["swapSha256"] = digest(swap_blob)
    try:
        swap = json.loads(swap_blob)
        as_of = swap.get("date")
        d = date.fromisoformat(as_of)
        if d > now.date():
            raise ValueError("OIS observation is dated in the future")
        report["swapAsOf"] = as_of
    except (KeyError, TypeError, ValueError, json.JSONDecodeError) as error:
        report.update(status="source_invalid", reason=str(error)[:160])
        return report

    treasury_url = TREASURY_URL.format(year=d.year)
    report["treasuryUrl"] = treasury_url
    try:
        treasury_blob = fetch(treasury_url)
    except (HTTPError, URLError, OSError) as error:
        report.update(status="source_unavailable", source="US Treasury",
                      reason=type(error).__name__)
        return report
    report["treasurySha256"] = digest(treasury_blob)
    try:
        treasury = treasury_by_day(treasury_blob)
    except (ValueError, KeyError, TypeError) as error:
        report.update(status="source_invalid", source="US Treasury",
                      reason=str(error)[:160])
        return report

    if as_of not in treasury:
        report.update(status="date_mismatch",
                      treasuryLatestDate=max(treasury),
                      reason="Treasury does not contain the exact SOFR as-of date")
        return report

    try:
        observation = build_observation(swap, treasury)
    except (ValueError, KeyError, TypeError) as error:
        report.update(status="source_invalid", reason=str(error)[:160])
        return report
    report["tenorCount"] = len(observation["tenors"])
    report["thinTenors"] = sum(x["method"] == "close-thin" for x in observation["tenors"])
    report["dayAge"] = (now.date() - d).days
    if archived is None or as_of > archived:
        report["status"] = "new_candidate_available"
    elif as_of == archived:
        rows = history.get("observations", [])
        recorded = next((row for row in rows if row["asOf"] == as_of), None)
        report["status"] = "no_new_day" if recorded == observation else "archived_date_revision"
    else:
        report["status"] = "source_behind_archive"
    report["note"] = ("Indicative OIS, not executable rates. A passing probe proves API parsing only; "
                      "it does not prove the production scheduler, publication rights, or historical coverage.")
    return report


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--history",type=Path,default=OUTPUT)
    parser.add_argument("--output",type=Path,required=True,
                        help="Temporary diagnostics JSON path outside the repository")
    args=parser.parse_args()
    out=args.output.resolve()
    if out==args.history.resolve() or out.is_relative_to(ROOT.resolve()):
        parser.error("Refusing a report path inside the GitHub repository or history file")
    history=json.loads(args.history.read_text(encoding="utf-8"))
    if history.get("schemaVersion")!=2 or history.get("demo") is not False:
        parser.error("Invalid existing history")
    report=check_sources(history)
    out.parent.mkdir(parents=True,exist_ok=True)
    out.write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(json.dumps({k:v for k,v in report.items() if k not in ("swapSha256","treasurySha256")},
                     ensure_ascii=False,indent=2))
    if report["status"] in ("source_unavailable","source_invalid","date_mismatch","archived_date_revision"):
        sys.exit(2)


if __name__=="__main__":
    try:
        main()
    except (ValueError,KeyError,TypeError,OSError,json.JSONDecodeError) as error:
        print("PROBE FAILED:",error,file=sys.stderr)
        sys.exit(1)
