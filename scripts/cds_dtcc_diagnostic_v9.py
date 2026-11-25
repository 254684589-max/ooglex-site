#!/usr/bin/env python3
"""Read-only V9 schema and same-day lifecycle diagnostic; never emit prices or identifiers."""
import argparse
import collections
import csv
import datetime as dt
import io
import json
import re
import zipfile
from cds_dtcc_probe_v8 import audit_zip, fetch, norm, number, MAX_CSV, MAX_ROWS

FIELDS = {
    "id": ("dissemination identifier",),
    "original": ("original dissemination identifier",),
    "action": ("action type",),
    "event": ("event type",),
    "upi": ("unique product identifier", "upi"),
    "upi_fisn": ("upi fisn", "unique product identifier fisn"),
    "upi_underlier_name": ("upi underlier name", "unique product identifier underlier name"),
    "asset_name": ("underlying asset name", "underlying asset name leg 1"),
    "underlier_source": ("underlier id source leg 1", "underlier id source leg 2", "underlier id source"),
    "underlier_id": ("underlier id leg 1", "underlier id leg 2", "underlier id"),
    "price": ("price",), "price_notation": ("price notation",),
    "payment_type": ("other payment type",), "payment_amount": ("other payment amount",),
    "payment_currency": ("other payment currency",),
    "payment_direction": ("other payment payer", "other payment receiver", "other payment payer leg 1", "other payment receiver leg 1", "other payment payer receiver", "other payment direction"),
    "package": ("package indicator", "package transaction indicator"),
    "postpriced": ("post priced swap indicator",),
    "effective": ("effective date",), "expiry": ("expiration date", "maturity date"),
}
def exact_name(s):
    # Case and punctuation normalization only; no fuzzy, substring or subsidiary guessing.
    return " ".join(re.sub(r"[^A-Z0-9]+", " ", s.upper()).split())

def read_rows(raw, day):
    # V8 checks ZIP shape, size, duplicate headers and row count before V9 processing.
    baseline = audit_zip(raw, day)
    with zipfile.ZipFile(io.BytesIO(raw)) as z:
        with z.open(z.infolist()[0]) as f:
            data = f.read(MAX_CSV + 1)
    if len(data) > MAX_CSV: raise ValueError("csv size")
    reader = csv.DictReader(io.StringIO(data.decode("utf-8-sig"), newline=""))
    fields = {norm(k):k for k in reader.fieldnames}
    rows = list(reader)
    if len(rows) > MAX_ROWS or len(rows) != baseline["row_counts"].get("rows",0):
        raise ValueError("row mismatch")
    return baseline, fields, rows

def diagnose(raw, day, issuers):
    baseline, fields, rows = read_rows(raw, day)
    aliases = {k:[fields[a] for a in variants if a in fields] for k,variants in FIELDS.items()}
    def vals(row, key):
        return [row[k].strip() for k in aliases[key] if row[k].strip()]
    def one(row,key):
        v=vals(row,key)
        return v[0] if len(v)==1 else ""
    def field(row,key):
        return row.get(fields.get(key,""),"").strip()
    names=collections.defaultdict(set)
    for issuer in issuers:
        for n in [issuer["name"], (issuer.get("issuer_identity") or {}).get("legal_name","")]:
            if n: names[exact_name(n)].add(issuer["issuer_id"])
    ids=collections.Counter(one(r,"id") for r in rows)
    linked={one(r,"original") for r in rows if one(r,"action").upper()!="NEWT" and one(r,"original")}
    counts=collections.Counter()
    candidates=set()
    for row in rows:
        action=one(row,"action").upper()
        if action!="NEWT":
            counts["non_new_lifecycle"]+=1
            continue
        rid=one(row,"id")
        if not rid or ids[rid]!=1 or one(row,"original") or rid in linked:
            counts["new_linked_duplicate_or_ambiguous"]+=1
            continue
        counts["new_unlinked_same_day_only"]+=1
        # Same-day unlinked is NOT a certified active trade across report dates.
        name_matches=set()
        for name in vals(row,"upi_underlier_name")+vals(row,"asset_name"):
            name_matches.update(names.get(exact_name(name),set()))
        if len(name_matches)==1:
            candidates.update(name_matches)
            counts["exact_name_candidate_rows"]+=1
        elif len(name_matches)>1:
            counts["ambiguous_name_rows"]+=1
        else:
            counts["no_exact_name_match_rows"]+=1
        try:
            effective=dt.date.fromisoformat(one(row,"effective"))
            expiry=dt.date.fromisoformat(one(row,"expiry"))
            if 1750 <= (expiry-effective).days <= 1900:
                counts["approx_5y_calendar_rows"]+=1
        except ValueError:
            pass
        for leg in ("1","2"):
            spread=field(row,"spread leg "+leg)
            notation=field(row,"spread notation leg "+leg)
            currency=field(row,"notional currency leg "+leg)
            notional=field(row,"notional amount leg "+leg)
            fixed=field(row,"fixed rate leg "+leg)
            if number(spread) is not None and notation:
                counts["same_leg_spread_notation_pairs"]+=1
                if currency=="USD":
                    counts["same_leg_usd_spread_notation_pairs"]+=1
            if currency=="USD" and number(notional) is not None and "+" not in notional and number(fixed) is not None:
                counts["same_leg_usd_fixed_notional_pairs"]+=1
        if one(row,"price") and one(row,"price_notation"):
            counts["price_and_notation_rows"]+=1
    return {"state":"v9_diagnostic_complete","report_date":day,"sha256":baseline["sha256"],
            "row_count":len(rows),"column_count":len(fields),
            "recognized_columns":aliases,"column_names":sorted(fields.values()),
            "diagnostic_counts":dict(counts),"exact_name_candidate_issuer_count":len(candidates),
            "verified_reference_entities":0,"admitted_spreads":0,"publication_enabled":False}
def main():
    p=argparse.ArgumentParser()
    p.add_argument("--date",required=True)
    p.add_argument("--universe",default="macro/nasdaq100-cds.json")
    args=p.parse_args()
    day=dt.date.fromisoformat(args.date)
    today=dt.datetime.now(dt.timezone.utc).date()
    if not today-dt.timedelta(days=366)<=day<today: p.error("one recent past date only")
    with open(args.universe,encoding="utf-8") as f: universe=json.load(f)
    if universe["publication"]["enabled"] is not False or len(universe["issuers"])!=100: raise ValueError("closed universe required")
    print(json.dumps(diagnose(fetch(args.date),args.date,universe["issuers"]),indent=2,sort_keys=True))
if __name__=="__main__": main()
