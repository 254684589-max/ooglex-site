#!/usr/bin/env python3
"""Read-only SOFR spread history coverage audit and optional historical source verification.

Never modifies the production observations. No synthetic values, no inferred trading days.
"""
import argparse
from datetime import date, datetime, timedelta, timezone
import json
from pathlib import Path
import sys
from urllib.error import HTTPError

from update_swap_spreads import (
    YEARS, TREASURY_FIELDS, OIS_URL, TREASURY_URL, request_bytes, treasury_by_day, build_observation,
)

ROOT = Path(__file__).resolve().parents[1]
HISTORY = ROOT / "macro" / "swap-spreads-history.json"
ARCHIVE_START = date(2026, 3, 19)


def parse_date(text):
    if not isinstance(text, str):
        raise ValueError("Missing date")
    result = date.fromisoformat(text)
    if result.isoformat() != text:
        raise ValueError("Non-canonical date")
    return result


def check_history(document, today):
    rows = document.get("observations")
    if document.get("schemaVersion") != 2 or document.get("demo") is not False or not isinstance(rows, list):
        raise ValueError("Invalid schema or demo status")
    seen = set()
    dates = []
    thin_days = 0
    for item in rows:
        day = parse_date(item["asOf"])
        if day in seen:
            raise ValueError("Duplicate historical date")
        if day > today:
            raise ValueError("Future observation")
        seen.add(day)
        dates.append(day)
        points = item["tenors"]
        if len(points) != len(YEARS) or [p["years"] for p in points] != list(YEARS):
            raise ValueError("Incomplete or unordered six-tenor curve")
        for point in points:
            if point.get("method") not in ("close", "close-thin"):
                raise ValueError("Non-permitted interpolation method")
            a, b, c = point["swap"], point["treasury"], point["spreadBp"]
            if any(type(x) not in (float, int) for x in (a, b, c)):
                raise ValueError("Non-numeric rate")
            if abs((a - b)*100 - c) > 0.011:
                raise ValueError("Inconsistent spread")
        if any(p["method"] == "close-thin" for p in points):
            thin_days += 1
    dates.sort()
    latest = dates[-1] if dates else None
    stale = latest is None or (today - latest).days > 7
    # Weekdays from first to last actual recorded date: coverage of accessible observations,
    # NOT proof of what official market holidays/trading days should have been.
    expected_weekdays = []
    if dates:
        cursor = dates[0]
        while cursor <= dates[-1]:
            if cursor.weekday() < 5:
                expected_weekdays.append(cursor.isoformat())
            cursor += timedelta(days=1)
    missing = sorted(set(expected_weekdays) - {x.isoformat() for x in dates})
    return {
        "source": "Ooglex archived date-matched CheckMySwap indicative OIS vs U.S. Treasury CMT",
        "asOf": today.isoformat(),
        "status": "stale" if stale else "ok",
        "observations": len(dates),
        "firstObservation": dates[0].isoformat() if dates else None,
        "lastObservation": latest.isoformat() if latest else None,
        "calendarDaysSinceLast": (today - latest).days if latest else None,
        "thinCloseDays": thin_days,
        "weekdayWindowCount": len(expected_weekdays),
        "missingWeekdayCount": len(missing),
        "missingWeekdaysSample": missing[:15],
        "eligibleForPercentiles": len(dates) >= 61 and (dates[-1]-dates[max(0,len(dates)-61)]).days >= 90 if dates else False,
        "note": "Weekday gaps include U.S. holidays, API non-availability and uncollected days; not validated missing trading days. No backfill performed.",
    }


def audit_dates(day_strings, fetch=request_bytes):
    """Verify up to 10 specified archived USD snapshots against matched Treasury dates; no writes."""
    if not 1 <= len(day_strings) <= 10 or len(set(day_strings)) != len(day_strings):
        raise ValueError("Supply 1-10 distinct dates")
    parsed = [parse_date(s) for s in day_strings]
    if any(d < ARCHIVE_START for d in parsed):
        raise ValueError("CheckMySwap USD archive starts on 2026-03-19")
    treasury_cache = {}
    verified = []
    for d in parsed:
        key = str(d.year)
        if key not in treasury_cache:
            treasury_cache[key] = treasury_by_day(fetch(TREASURY_URL.format(year=key)))
        # Explicit URL parameter ensures no silent fallback to the latest available curve.
        try:
            swap = json.loads(fetch(OIS_URL + "?date=" + d.isoformat()))
        except HTTPError as exc:
            if exc.code == 404:
                verified.append({"date": d.isoformat(), "status": "missing_archive"})
                continue
            raise
        if swap.get("date") != d.isoformat():
            raise ValueError("Dated OIS API returned wrong date")
        try:
            record = build_observation(swap, treasury_cache[key])
        except ValueError as exc:
            verified.append({"date": d.isoformat(), "status": "not_matched", "reason": str(exc)[:180]})
            continue
        verified.append({
            "date": record["asOf"],
            "status": "verified_only",
            "sixTenors": len(record["tenors"]),
            "thinCount": sum(x["method"] == "close-thin" for x in record["tenors"]),
            "source": "CheckMySwap indicative OIS + U.S. Treasury daily CMT",
        })
    return verified


def main():
    parser=argparse.ArgumentParser(description="Read-only SOFR archive and coverage audit")
    parser.add_argument("--history", type=Path, default=HISTORY)
    parser.add_argument("--date", action="append", default=[], help="Historical YYYY-MM-DD; repeat 1-10 times")
    parser.add_argument("--today", default=date.today().isoformat(), help="ISO date for reproducible audit")
    parser.add_argument("--output", type=Path, help="Optional diagnostic JSON path, not history file")
    args=parser.parse_args()
    today=parse_date(args.today)
    doc=json.loads(args.history.read_text(encoding="utf-8"))
    result=check_history(doc,today)
    if args.date:
        result["datedSourceChecks"]=audit_dates(args.date)
    result["checkedAt"]=datetime.now(timezone.utc).isoformat(timespec="seconds")
    result["writesProductionHistory"]=False
    output=json.dumps(result,ensure_ascii=False,indent=2)+"\n"
    if args.output:
        if args.output.resolve()==args.history.resolve():
            parser.error("Refusing to overwrite production history")
        args.output.parent.mkdir(parents=True,exist_ok=True)
        args.output.write_text(output,encoding="utf-8")
    print(output,end="")


if __name__=="__main__":
    try: main()
    except (ValueError, KeyError, TypeError, OSError, json.JSONDecodeError) as exc:
        print("AUDIT FAILED:",exc,file=sys.stderr)
        sys.exit(1)
