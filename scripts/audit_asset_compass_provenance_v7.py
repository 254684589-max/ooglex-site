#!/usr/bin/env python3
"""V7 Treasury provenance quarantine. Historical ledger stays append-only.

Exactly five known legacy URL-year errors are tolerated for provenance history,
but NEVER treated as verified data, and any NEW mismatches fail CI.
"""
import argparse
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlparse, parse_qs
from scripts.archive_asset_compass_observations import LEDGER, load, fingerprint
from scripts.check_asset_compass_archive_continuity_v25 import verify_ledger

ROOT = Path(__file__).resolve().parents[1]
REPORT = ROOT / "data" / "asset-compass-provenance-v7.json"
LEGACY_TIME = "2026-11-22T06:53:57.974839+00:00"
LEGACY_PERIOD = "2026-11-20"
LEGACY = {
    "treasury.us10y": (4.92, "percent", "daily_treasury_yield_curve"),
    "treasury.us2y": (4.63, "percent", "daily_treasury_yield_curve"),
    "treasury.real10y": (2.77, "percent", "daily_treasury_real_yield_curve"),
    "treasury.breakeven10y": (2.15, "percent", "daily_treasury_yield_curve"),
    "treasury.spread10y2y": (0.29, "percentage_points", "daily_treasury_yield_curve"),
}
PREFIX = ("https://home.treasury.gov/resource-center/data-chart-center/"
          "interest-rates/daily-treasury-rates.csv/")
SUFFIX = "&page=&_format=csv"

def legacy_exact(row):
    item = LEGACY.get(row.get("series_id"))
    if item is None:
        return False
    value, unit, kind = item
    incorrect_url = (PREFIX + "2025/all?type=" + kind +
                     "&field_tdr_date_value=2025" + SUFFIX)
    return (row.get("observation_period") == LEGACY_PERIOD
            and row.get("first_seen_at") == LEGACY_TIME
            and type(row.get("value")) in (int, float)
            and row["value"] == value and row.get("unit") == unit
            and row.get("source_url") == incorrect_url
            and row.get("official_release_time_known") is False
            and row.get("eligible_for_historical_official_vintage") is False)

def is_valid_treasury_source(row):
    period = str(row["observation_period"])
    year = period[:4]
    url = urlparse(row["source_url"])
    q = parse_qs(url.query)
    expected_kind = ("daily_treasury_real_yield_curve"
                     if row["series_id"] == "treasury.real10y"
                     else "daily_treasury_yield_curve")
    return (url.scheme == "https" and url.hostname == "home.treasury.gov"
            and not url.username and not url.password
            and url.path == ("/resource-center/data-chart-center/interest-rates/"
                             "daily-treasury-rates.csv/" + year + "/all")
            and q.get("field_tdr_date_value") == [year]
            and q.get("type") == [expected_kind])

def inspect(rows, now=None):
    instant = now or datetime.now(timezone.utc).isoformat()
    verify_ledger(rows, now=instant)
    legacy = []
    unexpected = []
    valid = []
    for row in rows:
        if not row["series_id"].startswith("treasury."):
            continue
        if is_valid_treasury_source(row):
            valid.append(row)
        elif legacy_exact(row):
            legacy.append(row)
        else:
            unexpected.append(row)
    anomaly_list = [
        {"series_id": r["series_id"], "observation_period": r["observation_period"],
         "first_seen_at": r["first_seen_at"], "source_url": r["source_url"],
         "fingerprint_sha256": fingerprint(r)}
        for r in legacy
    ]
    raw = "".join(json.dumps(r, ensure_ascii=False, separators=(",", ":")) + "\n"
                  for r in rows).encode("utf-8")
    return {
        "schema_version": 1,
        "report_type": "asset_compass_v7_treasury_provenance",
        "generated_at": instant,
        "ledger_sha256": hashlib.sha256(raw).hexdigest(),
        "treasury_valid_source_rows": len(valid),
        "legacy_quarantined_rows": len(legacy),
        "unexpected_mismatch_rows": len(unexpected),
        "legacy_anomalies": anomaly_list,
        "unexpected_mismatches": [
            {"series_id": r["series_id"], "observation_period": r["observation_period"],
             "fingerprint_sha256": fingerprint(r)} for r in unexpected
        ],
        "integrity_gate_passed": not unexpected and len(legacy) == len(LEGACY),
        "legacy_rows_are_valid_evidence": False,
        "official_vintages_verified": False,
        "validated_for_live_scoring": False,
        "note": "Existing 2025 URLs attached to 2026 observations remain quarantined as immutable evidence of a prior extraction bug. Never count as trusted source provenance.",
    }

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--ledger", type=Path, default=LEDGER)
    parser.add_argument("--output", type=Path, default=REPORT)
    parser.add_argument("--fail-on-new-mismatch", action="store_true")
    args = parser.parse_args()
    result = inspect(load(args.ledger))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n",
                           encoding="utf-8")
    print(json.dumps({k: result[k] for k in
          ("treasury_valid_source_rows", "legacy_quarantined_rows",
           "unexpected_mismatch_rows", "integrity_gate_passed")}, ensure_ascii=False))
    if args.fail_on_new_mismatch and not result["integrity_gate_passed"]:
        raise SystemExit("Unexpected or changed Treasury provenance mismatch; archive blocked")

if __name__ == "__main__":
    main()
