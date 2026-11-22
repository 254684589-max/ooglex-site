#!/usr/bin/env python3
"""Generate *unpublished* SOFR spread backfill candidates from date-specific sources.

This tool NEVER writes the public history JSON. Rates remain in a temporary
review artifact, subject to licensing and provenance review before publication.
"""
import argparse
from datetime import date, datetime, timezone
import hashlib
import json
from pathlib import Path
import sys
from urllib.error import HTTPError

from audit_swap_spreads_coverage import ARCHIVE_START, HISTORY, parse_date
from update_swap_spreads import (
    OIS_URL, TREASURY_URL, request_bytes, treasury_by_day, build_observation,
)

ROOT = Path(__file__).resolve().parents[1]
MAX_DATES = 10


def _digest(raw):
    return hashlib.sha256(raw).hexdigest()


def build_candidates(date_strings, existing, fetch=request_bytes, today=None):
    """Returns an audit report; no file I/O or side effects other than fetch()."""
    today = today or date.today()
    if not isinstance(date_strings, list) or not 1 <= len(date_strings) <= MAX_DATES:
        raise ValueError("Expected 1-10 requested dates")
    days = [parse_date(s) for s in date_strings]
    if len(set(days)) != len(days):
        raise ValueError("Duplicate requested date")
    if any(d < ARCHIVE_START or d > today for d in days):
        raise ValueError("Date outside verified archive window")
    if existing.get("schemaVersion") != 2 or existing.get("demo") is not False:
        raise ValueError("Invalid production history schema")
    archived = {}
    for obs in existing.get("observations", []):
        asof = obs["asOf"]
        if asof in archived:
            raise ValueError("Duplicate date in production history")
        archived[asof] = obs

    treasury_cache = {}
    results = []
    for day in sorted(days):
        asof = day.isoformat()
        treasury_url = TREASURY_URL.format(year=day.year)
        if day.year not in treasury_cache:
            blob = fetch(treasury_url)
            treasury_cache[day.year] = {
                "sha256": _digest(blob),
                "rates": treasury_by_day(blob),
                "url": treasury_url
            }
        t = treasury_cache[day.year]
        ois_url = OIS_URL + "?date=" + asof
        try:
            ois_blob = fetch(ois_url)
        except HTTPError as err:
            if err.code == 404:
                results.append({"asOf": asof, "status": "no_archive",
                                "reason": "HTTP 404; no substitute date"})
                continue
            raise
        try:
            swap = json.loads(ois_blob)
            if swap.get("date") != asof:
                raise ValueError("Dated API returned a different date")
            record = build_observation(swap, t["rates"])
        except (ValueError, KeyError, TypeError, json.JSONDecodeError) as err:
            results.append({"asOf": asof, "status": "rejected",
                            "reason": str(err)[:180],
                            "oisSha256": _digest(ois_blob),
                            "treasurySha256": t["sha256"]})
            continue

        old = archived.get(asof)
        status = ("candidate" if old is None else
                  "already_archived" if old == record else "archive_conflict")
        item = {
            "asOf": asof,
            "status": status,
            "provenance": {
                "oisSource": "CheckMySwap public indicative USD SOFR OIS archive",
                "oisUrl": ois_url,
                "oisSha256": _digest(ois_blob),
                "treasurySource": "U.S. Treasury daily par yield curve",
                "treasuryUrl": t["url"],
                "treasurySha256": t["sha256"],
                "retrievalKind": "current archived version, not immutable original",
            },
            "methodCounts": {
                method: sum(row["method"] == method for row in record["tenors"])
                for method in ("close", "close-thin")
            },
            "verifiedTenorCount": len(record["tenors"]),
        }
        # Include rates only in temporary, non-public review artifact.
        # No automatic promotion into the static website.
        if status in ("candidate", "archive_conflict"):
            item["unpublishedObservation"] = record
        results.append(item)
    counts = {key: sum(r["status"] == key for r in results)
              for key in ("candidate", "already_archived", "archive_conflict",
                          "no_archive", "rejected")}
    return {
        "schemaVersion": 1, "type": "SOFR-backfill-review-only",
        "generatedAt": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "latestArchivedDate": max(archived) if archived else None,
        "requestedDates": len(days),
        "results": results, "counts": counts,
        "productionHistoryModified": False,
        "publicationApproved": False,
        "warning": "Indicative OIS; review source license, revision history and treasury conventions before manually approving any publication."
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--date", action="append", required=True,
                        help="Date to inspect, YYYY-MM-DD; repeat up to ten times")
    parser.add_argument("--history", type=Path, default=HISTORY)
    parser.add_argument("--output", type=Path, required=True,
                        help="Temporary review report path, outside the repository")
    parser.add_argument("--today", default=date.today().isoformat())
    args = parser.parse_args()
    output = args.output.resolve()
    try:
        output.relative_to(ROOT.resolve())
        parser.error("Review artifact MUST NOT be inside public repository")
    except ValueError:
        pass
    history = json.loads(args.history.read_text(encoding="utf-8"))
    report = build_candidates(args.date, history, today=parse_date(args.today))
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({
        "report": str(output), "counts": report["counts"],
        "productionHistoryModified": False, "publicationApproved": False
    }, ensure_ascii=False))
    # Reject conflicts and malformed/mismatched inputs instead of silently approving.
    if report["counts"]["archive_conflict"] or report["counts"]["rejected"]:
        sys.exit(2)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError) as err:
        print("BACKFILL REVIEW FAILED:", err, file=sys.stderr)
        sys.exit(1)
