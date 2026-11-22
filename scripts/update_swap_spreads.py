#!/usr/bin/env python3
"""Append matched, explicitly dated indicative USD SOFR OIS / US Treasury observations.

No fallback to mismatched dates, no invented quotes. Uses only public, no-key APIs.
"""
import argparse
from datetime import date, datetime, timezone
import json
from pathlib import Path
import sys
from urllib.request import Request, urlopen
import xml.etree.ElementTree as ET

YEARS = (2, 3, 5, 7, 10, 30)
OUTPUT = Path(__file__).resolve().parents[1] / "macro" / "swap-spreads-history.json"
OIS_URL = "https://www.checkmyswap.com/api/curves/USD"
TREASURY_URL = (
    "https://home.treasury.gov/resource-center/data-chart-center/"
    "interest-rates/pages/xml?data=daily_treasury_yield_curve&field_tdr_date_value={year}"
)
TREASURY_FIELDS = {
    2: "BC_2YEAR", 3: "BC_3YEAR", 5: "BC_5YEAR",
    7: "BC_7YEAR", 10: "BC_10YEAR", 30: "BC_30YEAR"
}


def request_bytes(url):
    request = Request(url, headers={"User-Agent": "Ooglex-AssetCompass-Research/1.0"})
    with urlopen(request, timeout=25) as response:
        payload = response.read(3_000_001)
        if len(payload) > 3_000_000:
            raise ValueError("Remote payload unexpectedly large")
        return payload


def localname(tag):
    return tag.rsplit("}", 1)[-1]


def treasury_by_day(xml_blob):
    root = ET.fromstring(xml_blob)
    results = {}
    for entry in root.iter():
        if localname(entry.tag) != "entry":
            continue
        fields = {}
        for node in entry.iter():
            name = localname(node.tag).upper()
            if node.text and name in set(TREASURY_FIELDS.values()) | {"NEW_DATE", "DATE"}:
                fields[name] = node.text.strip()
        date_text = (fields.get("NEW_DATE") or fields.get("DATE") or "")[:10]
        try:
            date.fromisoformat(date_text)
            rates = {y: float(fields[TREASURY_FIELDS[y]]) for y in YEARS}
        except (ValueError, KeyError):
            continue
        if all(0 < n < 30 for n in rates.values()):
            results[date_text] = rates
    if not results:
        raise ValueError("Treasury XML contains no complete dated six-tenor observation")
    return results


def build_observation(swap, treasury):
    asof = swap.get("date")
    date.fromisoformat(asof)
    if asof not in treasury:
        raise ValueError("No matching official Treasury observation for SOFR date " + asof)
    tenor_rows = {}
    for row in swap.get("curve", []):
        tenor = row.get("tenor", "")
        if not isinstance(tenor, str) or not tenor.endswith("Y"):
            continue
        try:
            years = int(tenor[:-1])
        except ValueError:
            continue
        if years not in YEARS:
            continue
        if row.get("date") != asof:
            raise ValueError("Mismatched tenor observation date")
        method = row.get("method")
        if method not in ("close", "close-thin"):
            raise ValueError("Refusing derived/unclear tenor: " + str(tenor))
        rate = row.get("rate")
        if type(rate) not in (int, float) or not 0 < rate < 30:
            raise ValueError("Invalid SOFR rate for " + tenor)
        if years in tenor_rows:
            raise ValueError("Duplicate SOFR tenor " + tenor)
        fixed = float(rate)
        t = treasury[asof][years]
        tenor_rows[years] = {
            "years": years,
            "swap": fixed,
            "treasury": t,
            "spreadBp": round((fixed - t) * 100, 2),
            "method": method,
        }
    if sorted(tenor_rows) != list(YEARS):
        raise ValueError("Missing mandatory SOFR tenors; retain existing history")
    return {"asOf": asof, "quality": "indicative", "tenors": [tenor_rows[y] for y in YEARS]}


def update_document(existing, observation, timestamp):
    observations = existing.get("observations", [])
    if not isinstance(observations, list):
        raise ValueError("Invalid history container")
    by_day = {r["asOf"]: r for r in observations}
    if len(by_day) != len(observations):
        raise ValueError("Duplicate dates in existing history")
    asof = observation["asOf"]
    if by_day and asof < max(by_day):
        raise ValueError("Source is older than archived latest observation")
    if asof in by_day:
        if by_day[asof] != observation:
            raise ValueError("Historical observation changed; manual review required")
        return existing, False
    doc = dict(existing)
    by_day[asof] = observation
    doc["observations"] = [by_day[day] for day in sorted(by_day)]
    doc["updatedAt"] = timestamp
    doc["status"] = "ok"
    return doc, True


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--swap-json", type=Path, help="Local API fixture to reproduce and test without network")
    parser.add_argument("--treasury-xml", type=Path, help="Local Treasury XML fixture")
    parser.add_argument("--output", type=Path, default=OUTPUT)
    args = parser.parse_args()
    existing = json.loads(args.output.read_text(encoding="utf-8"))
    if (args.swap_json is None) != (args.treasury_xml is None):
        parser.error("Both fixture files are required together")
    swap_blob = (args.swap_json.read_bytes() if args.swap_json else request_bytes(OIS_URL))
    swap = json.loads(swap_blob)
    asof = swap.get("date", "")
    date.fromisoformat(asof)
    treasury_blob = (args.treasury_xml.read_bytes() if args.treasury_xml
                     else request_bytes(TREASURY_URL.format(year=asof[:4])))
    observation = build_observation(swap, treasury_by_day(treasury_blob))
    timestamp = datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
    updated, changed = update_document(existing, observation, timestamp)
    if changed:
        args.output.write_text(json.dumps(updated, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print("APPENDED", observation["asOf"])
    else:
        print("UNCHANGED", observation["asOf"])


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError, json.JSONDecodeError, ET.ParseError) as err:
        print("NO UPDATE:", err, file=sys.stderr)
        sys.exit(1)
