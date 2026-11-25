#!/usr/bin/env python3
"""Collect ONLY the public Tradeweb SBSEF regulatory daily report audit metadata.
No raw XML, trade prices, inferred spreads or restricted provider data are saved.
"""
import argparse
import datetime as dt
import hashlib
import json
import pathlib
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from audit_tradeweb_cds_v2 import MAX_BYTES, load_tickers, read_xml

BASE = "https://reports.tradeweb.com/DownloadSbSef.adl?file=/TWSBSEF-CDS-Report_"
SOURCE = "tradeweb_sbsef_dmdr"
VERSION = 1
CLASSES = {"contract_excluded", "missing_product_identifier", "unmatched_label",
           "invalid_price_or_count", "incompatible_price_format", "coupon_collision",
           "price_semantics_unverified"}

def utc_now():
    return dt.datetime.now(dt.timezone.utc).isoformat()

def report_url(day):
    return BASE + dt.date.fromisoformat(day).isoformat() + ".xml"

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None

def download(day):
    req = urllib.request.Request(report_url(day), headers={
        "User-Agent": "Ooglex-CDS-research/1.0 (public regulatory report audit)",
        "Accept": "application/xml,text/xml,application/octet-stream"})
    with urllib.request.build_opener(NoRedirect()).open(req, timeout=20) as response:
        if response.status != 200:
            raise ValueError("unexpected status")
        raw = response.read(MAX_BYTES + 1)
    return raw

def audit(raw, day, tickers):
    if not isinstance(raw, bytes) or len(raw) > MAX_BYTES:
        raise ValueError("oversize")
    # Reject alternate encodings, embedded NUL, DTD/entity declarations.
    decoded = raw.decode("utf-8-sig")
    if "\x00" in decoded or re.search(r"<!\s*(DOCTYPE|ENTITY)", decoded, re.I):
        raise ValueError("unsafe XML")
    if re.search(r'<\?xml[^?]*encoding\s*=\s*["\'](?!utf-8["\'])', decoded, re.I):
        raise ValueError("unsupported encoding")
    result = read_xml(raw, day, tickers)
    n = result["report_rows"]
    counts = result["classification_counts"]
    if n <= 0 or set(counts) - CLASSES or sum(counts.values()) != n:
        raise ValueError("empty or unsupported schema")
    return {"sha256": hashlib.sha256(raw).hexdigest(), "first_retrieved_at": utc_now(),
            "report_generated_at": result["generated"], "report_rows": n,
            "classification_counts": counts,
            "candidate_issuer_count": result["candidate_count"],
            "candidate_issuer_ids": result["candidate_issuer_ids"],
            "verified_reference_entities": 0, "admitted_par_spreads": 0}

def empty():
    return {"schema_version": VERSION, "source": SOURCE, "publication_enabled": False,
            "admitted_par_spreads": 0, "reports": {}, "last_run": None}

def validate_ledger(data, tickers):
    if (data.get("schema_version") != VERSION or data.get("source") != SOURCE
        or data.get("publication_enabled") is not False or data.get("admitted_par_spreads") != 0
        or not isinstance(data.get("reports"), dict)):
        raise ValueError("bad ledger")
    ids = set(tickers.values())
    for day, versions in data["reports"].items():
        if dt.date.fromisoformat(day).isoformat() != day or not isinstance(versions, list) or not versions:
            raise ValueError("bad date/version")
        hashes = set()
        for row in versions:
            if set(row) != {"sha256","first_retrieved_at","report_generated_at","report_rows",
                            "classification_counts","candidate_issuer_count","candidate_issuer_ids",
                            "verified_reference_entities","admitted_par_spreads"}:
                raise ValueError("unexpected fields")
            digest = row["sha256"]
            counts = row["classification_counts"]
            candidates = row["candidate_issuer_ids"]
            if (not isinstance(digest, str) or not re.fullmatch("[0-9a-f]{64}", digest)
                or digest in hashes or row["admitted_par_spreads"] != 0 or row["verified_reference_entities"] != 0
                or not isinstance(counts, dict) or set(counts) - CLASSES
                or any(type(v) is not int or v < 0 for v in counts.values())
                or type(row["report_rows"]) is not int or row["report_rows"] <= 0
                or sum(counts.values()) != row["report_rows"]
                or not isinstance(candidates, list) or len(set(candidates)) != len(candidates)
                or set(candidates) - ids or row["candidate_issuer_count"] != len(candidates)):
                raise ValueError("bad audit version")
            for k in ("first_retrieved_at", "report_generated_at"):
                if dt.datetime.fromisoformat(row[k]).tzinfo is None:
                    raise ValueError("missing timezone")
            hashes.add(digest)
    return data

def merge(data, day, row):
    versions = data["reports"].setdefault(day, [])
    if any(v["sha256"] == row["sha256"] for v in versions):
        return "unchanged"
    versions.append(row)
    return "new_version" if len(versions) > 1 else "new_report"

def dates(end, days):
    return [(end - dt.timedelta(days=i)).isoformat()
            for i in range(days - 1, -1, -1)
            if (end - dt.timedelta(days=i)).weekday() < 5]

def collect(data, days, tickers, fetch=download):
    attempts = {}
    for day in days:
        try:
            row = audit(fetch(day), day, tickers)
            attempts[day] = merge(data, day, row)
        except urllib.error.HTTPError as exc:
            attempts[day] = "not_available" if exc.code in (404,410) else "http_error_" + str(exc.code)
        except (urllib.error.URLError, TimeoutError, OSError):
            attempts[day] = "network_error"
        except (ValueError, ET.ParseError, TypeError, OverflowError):
            attempts[day] = "schema_or_validation_error"
    data["last_run"] = {"attempted_at": utc_now(), "attempts": attempts}
    return data

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--ledger", type=pathlib.Path, default=pathlib.Path("macro/nasdaq100-cds-audit.json"))
    p.add_argument("--universe", type=pathlib.Path, default=pathlib.Path("macro/nasdaq100-cds.json"))
    p.add_argument("--end", type=dt.date.fromisoformat, default=dt.datetime.now(dt.timezone.utc).date()-dt.timedelta(days=1))
    p.add_argument("--days", type=int, default=7)
    args = p.parse_args()
    today = dt.datetime.now(dt.timezone.utc).date()
    if not 1 <= args.days <= 31 or args.end >= today or args.end < today-dt.timedelta(days=366):
        p.error("bounded past dates only (1–31 days, end within last 366 days)")
    tickers = load_tickers(args.universe)
    data = validate_ledger(json.loads(args.ledger.read_text(encoding="utf-8")) if args.ledger.exists() else empty(), tickers)
    collect(data, dates(args.end, args.days), tickers)
    validate_ledger(data, tickers)
    tmp = args.ledger.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, indent=2, sort_keys=True)+"\n", encoding="utf-8")
    tmp.replace(args.ledger)
    print(json.dumps(data["last_run"], indent=2))
    print("Verified audit dates:", len(data["reports"]), "; admitted spreads: 0")
    # No network success is not proof of zero trading. Retain prior reports.
    return 0

if __name__ == "__main__":
    sys.exit(main())
