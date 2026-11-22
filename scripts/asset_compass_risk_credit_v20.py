#!/usr/bin/env python3
"""V20 restricted risk/credit vintage importer for PRIVATE research only.

No network fetching, no public output, no simulated dates, and no scoring.
Source permission declarations are operator attestations, not legal clearance.
"""
import argparse
import csv
import json
import math
import sqlite3
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlparse

from scripts.asset_compass_vintages import create_schema, ingest_macro, timestamp

ROOT = Path(__file__).resolve().parents[1]
CATALOG = {
    "VIXCLS": {
        "owner": "Cboe", "frequency": "daily", "units": "index",
        "series_page": "https://fred.stlouisfed.org/series/VIXCLS",
        "hosts": ("fred.stlouisfed.org", "www.cboe.com", "cdn.cboe.com"),
    },
    "BAMLC0A0CM": {
        "owner": "ICE Data Indices, LLC", "frequency": "daily", "units": "percent",
        "series_page": "https://fred.stlouisfed.org/series/BAMLC0A0CM",
        "hosts": ("fred.stlouisfed.org", "alfred.stlouisfed.org"),
    },
    "BAMLH0A0HYM2": {
        "owner": "ICE Data Indices, LLC", "frequency": "daily", "units": "percent",
        "series_page": "https://fred.stlouisfed.org/series/BAMLH0A0HYM2",
        "hosts": ("fred.stlouisfed.org", "alfred.stlouisfed.org"),
    },
}
FIELDS = (
    "series_id", "source", "frequency", "units", "observation_date",
    "available_at", "value", "source_release_id", "source_url"
)


def approved_permission(permission, series):
    """An explicit per-series private-use attestation, not assumed redistribution rights."""
    if not isinstance(permission, dict):
        return False
    entry = permission.get("series", {}).get(series)
    if not isinstance(entry, dict):
        return False
    if entry.get("approved_for_private_research") is not True:
        return False
    if not all(isinstance(entry.get(k), str) and entry[k].strip()
               for k in ("authority", "evidence_reference", "reviewed_at")):
        return False
    try:
        when = datetime.fromisoformat(entry["reviewed_at"].replace("Z", "+00:00"))
    except ValueError:
        return False
    return (when.tzinfo is not None and when <= datetime.now(timezone.utc)
            and entry.get("approved_for_public_redistribution") is not True)


def validated_rows(rows, permission):
    checked = []
    for row in rows:
        if not isinstance(row, dict) or any(k not in row for k in FIELDS):
            raise ValueError("Missing required vintage columns")
        sid = row["series_id"].strip()
        if sid not in CATALOG:
            raise ValueError("Series not in V20 restricted catalog: " + sid)
        spec = CATALOG[sid]
        if not approved_permission(permission, sid):
            raise PermissionError("Private research rights not attested: " + sid)
        if row["source"].strip() != spec["owner"]:
            raise ValueError("Incorrect source owner for " + sid)
        if row["frequency"].strip() != spec["frequency"] or row["units"].strip() != spec["units"]:
            raise ValueError("Unexpected frequency or units for " + sid)
        try:
            val = float(row["value"])
        except (ValueError, TypeError):
            raise ValueError("Invalid metric value") from None
        if not math.isfinite(val) or val < 0:
            raise ValueError("Risk/credit index must be finite and nonnegative")
        if not row["source_release_id"].strip():
            raise ValueError("Authentic release/revision identifier required")
        try:
            url = urlparse(row["source_url"].strip())
        except ValueError:
            raise ValueError("Invalid provenance URL") from None
        if (url.scheme != "https" or url.hostname not in spec["hosts"]
                or url.username is not None or url.password is not None):
            raise ValueError("Source must be approved official HTTPS host")
        released = datetime.fromisoformat(timestamp(row["available_at"]))
        if released > datetime.now(timezone.utc):
            raise ValueError("Future release is not a historical observation")
        # The warehouse validates observation period and release chronology.
        checked.append(dict(row))
    return checked


def import_private(db, rows, permission):
    verified = validated_rows(rows, permission)
    with db:
        create_schema(db)
        return ingest_macro(db, verified)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--db", type=Path, required=True)
    p.add_argument("--csv", type=Path, required=True)
    p.add_argument("--permission", type=Path, required=True,
                   help="Private per-series permission attestation JSON")
    a = p.parse_args()
    for path in (a.db, a.csv, a.permission):
        if path.resolve().is_relative_to(ROOT.resolve()):
            raise ValueError("Restricted dataset, permission file and DB must stay outside public repo")
    if not a.csv.is_file() or not a.permission.is_file():
        raise FileNotFoundError("Real vintage CSV and private rights attestation required")
    with a.csv.open(encoding="utf-8-sig", newline="") as fp:
        rows = list(csv.DictReader(fp))
    permission = json.loads(a.permission.read_text(encoding="utf-8"))
    # Validate whole batch before touching database.
    verified = validated_rows(rows, permission)
    a.db.parent.mkdir(parents=True, exist_ok=True)
    with sqlite3.connect(a.db) as db:
        create_schema(db)
        added = ingest_macro(db, verified)
    print(json.dumps({
        "report_type": "asset_compass_v20_restricted_ingest",
        "records_added": added, "input_records": len(verified),
        "research_only": True, "redistribution_authorized_by_tool": False,
        "validated_for_live_scoring": False, "public_data_exported": False
    }, ensure_ascii=False))


if __name__ == "__main__":
    main()
