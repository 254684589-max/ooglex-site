#!/usr/bin/env python3
"""Strictly read-only historical SOFR eligibility pilot.

No source rates, reconstructed prices or raw source payloads are written to
the repository. Output contains only dates, quality outcomes and SHA256 hashes.
CheckMySwap re-publication rights must be reviewed separately.
"""
import argparse
from datetime import date, datetime, timezone
import json
from pathlib import Path
import sys
from urllib.error import HTTPError, URLError

from build_swap_spread_candidates import build_candidates
from audit_swap_spreads_coverage import HISTORY, parse_date
from update_swap_spreads import request_bytes

ROOT=Path(__file__).resolve().parents[1]

# Sample one or two published U.S. weekdays per month, not a complete archive.
PILOT_DATES=(
    "2026-03-20",
    "2026-04-15",
    "2026-05-15",
    "2026-06-15",
    "2026-07-15",
    "2026-08-14",
    "2026-09-15",
    "2026-10-15",
    "2026-11-13",
    "2026-11-20",
)


def summarize(full):
    """Deliberately discards unpublished tenors and all source values."""
    allowed=("candidate","already_archived","archive_conflict","no_archive","rejected")
    rows=[]
    for row in full["results"]:
        status=row["status"]
        if status not in allowed:
            raise ValueError("Unknown pilot status")
        prov=row.get("provenance",{})
        data={
            "asOf":row["asOf"],
            "status":status,
            "eligibleTenors":row.get("verifiedTenorCount",0),
            "thinTenors":row.get("methodCounts",{}).get("close-thin"),
            "oisResponseSha256":prov.get("oisSha256") or row.get("oisSha256"),
            "treasuryResponseSha256":prov.get("treasurySha256") or row.get("treasurySha256"),
            "reason":row.get("reason"),
        }
        rows.append(data)
    return {
        "schemaVersion":1,
        "type":"SOFR-historical-backfill-license-gated-pilot",
        "checkedAt":full["generatedAt"],
        "datesRequested":full["requestedDates"],
        "archiveLastDate":full["latestArchivedDate"],
        "counts":{s:sum(x["status"]==s for x in rows) for s in allowed},
        "results":rows,
        "rawSwapRatesIncluded":False,
        "productionHistoryModified":False,
        "licenseApproval":"not_obtained",
        "publicationApproved":False,
        "methodologyWarning":"Indicative par SOFR OIS, not a dealer quote; dated archives can be revised.",
        "decision":"REVIEW_ONLY",
    }


def run(dates,history,fetch=request_bytes,today=None):
    original=history.read_bytes()
    document=json.loads(original)
    # build_candidates reads date-specific real sources, never writes production.
    report=build_candidates(list(dates),document,fetch=fetch,today=today or date.today())
    if history.read_bytes()!=original:
        raise RuntimeError("Original production history changed during pilot")
    output=summarize(report)
    archived={obs["asOf"]:obs for obs in document["observations"]}
    originals={obs["asOf"]:obs for obs in report["results"]}
    for row in output["results"]:
        if row["status"]!="archive_conflict":
            continue
        before=archived.get(row["asOf"],{}).get("tenors",[])
        after=originals[row["asOf"]].get("unpublishedObservation",{}).get("tenors",[])
        before_by={x["years"]:x for x in before}
        after_by={x["years"]:x for x in after}
        changed={}
        for year in sorted(set(before_by)|set(after_by)):
            a,b=before_by.get(year,{}),after_by.get(year,{})
            fields=[k for k in ("swap","treasury","spreadBp","method") if a.get(k)!=b.get(k)]
            if fields:
                changed[str(year)+"Y"]=fields
        # Only names of changed fields, never market values.
        row["conflictFieldNamesByTenor"]=changed
    return output


def main():
    p=argparse.ArgumentParser()
    p.add_argument("--date",action="append",default=[],
                   help="Explicit historical YYYY-MM-DD; at most ten")
    p.add_argument("--history",type=Path,default=HISTORY)
    p.add_argument("--output",type=Path,required=True)
    p.add_argument("--today",default=date.today().isoformat())
    a=p.parse_args()
    output=a.output.resolve()
    if output.is_relative_to(ROOT.resolve()):
        p.error("Cannot place pilot audit inside website repository")
    if output==a.history.resolve():
        p.error("Cannot overwrite market history")
    dates=a.date or list(PILOT_DATES)
    report=run(dates,a.history,today=parse_date(a.today))
    output.parent.mkdir(parents=True,exist_ok=True)
    output.write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(json.dumps(report,ensure_ascii=False,indent=2))
    # Fail if zero usable dates OR any conflict; 404/derived dates are
    # not silently replaced by synthetic observations.
    if report["counts"]["archive_conflict"]:
        return 3
    if report["counts"]["candidate"]+report["counts"]["already_archived"]<1:
        return 2
    return 0


if __name__=="__main__":
    try:sys.exit(main())
    except (OSError,ValueError,KeyError,TypeError,RuntimeError,HTTPError,URLError) as error:
        print("SOFR BACKFILL PILOT FAILED:",str(error)[:250],file=sys.stderr)
        sys.exit(1)
