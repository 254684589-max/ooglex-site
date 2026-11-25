#!/usr/bin/env python3
"""Audit public Tradeweb SBSEF daily XML locally; never publish a par spread."""
import argparse
import collections
import datetime as dt
import decimal
import json
import pathlib
import re
import xml.etree.ElementTree as ET

MAX_BYTES = 8 * 1024 * 1024
NAME = re.compile(r"^([A-Z0-9.-]+) SEN 5Y ([0-9]+(?:\.[0-9]+)?) USD$")
UPI = re.compile(r"^[A-Z0-9]{12}$")

def read_xml(raw, expected_date, tickers):
    if len(raw) > MAX_BYTES or re.search(br"<!\s*(DOCTYPE|ENTITY)", raw, re.I):
        raise ValueError("unsafe XML")
    root = ET.fromstring(raw)
    if root.tag != "dailyMarketDataReport" or root.findtext("sbsef") != "TW SEF LLC":
        raise ValueError("wrong report")
    date = dt.date.fromisoformat(root.findtext("date", ""))
    if date.isoformat() != expected_date:
        raise ValueError("report date mismatch")
    generated = dt.datetime.fromisoformat(root.findtext("generated", ""))
    if generated.tzinfo is None or generated.date() < date:
        raise ValueError("invalid generation timestamp")
    counts = collections.Counter()
    candidates = set()
    rows = root.findall("sbsTnr")
    for row in rows:
        def get(k):
            values = row.findall(k)
            return (values[0].text or "").strip() if len(values) == 1 else ""
        m = NAME.fullmatch(get("sbsNm"))
        if not m or get("tenor") != "P5Y" or get("ccy") != "USD":
            counts["contract_excluded"] += 1
            continue
        if not UPI.fullmatch(get("upi")):
            counts["missing_product_identifier"] += 1
            continue
        if m[1] not in tickers:
            counts["unmatched_label"] += 1
            continue
        candidates.add(tickers[m[1]])
        try:
            close = decimal.Decimal(get("clsgPrc"))
            trades = int(get("tradCnt"))
            if not close.is_finite() or close <= 0 or trades <= 0:
                raise ValueError("missing")
        except (decimal.InvalidOperation, ValueError):
            counts["invalid_price_or_count"] += 1
            continue
        if get("prcFrmt") != "SprdBsisPts":
            counts["incompatible_price_format"] += 1
        elif close == decimal.Decimal(m[2]):
            counts["coupon_collision"] += 1
        else:
            counts["price_semantics_unverified"] += 1
    return {"report_date":date.isoformat(),"generated":generated.isoformat(),
            "report_rows":len(rows),"classification_counts":dict(counts),
            "candidate_issuer_ids":sorted(candidates),
            "candidate_count":len(candidates),"verified_reference_entities":0,
            "admitted_par_spreads":0,"publication_enabled":False}

def load_tickers(path):
    data = json.loads(path.read_text(encoding="utf-8"))
    if data["publication"]["enabled"] is not False:
        raise ValueError("expected closed V1 gate")
    rows = data["issuers"]
    pairs = [(t,r["issuer_id"]) for r in rows for t in r["tickers"]]
    if len(rows) != 100 or len(pairs) != 101 or len(dict(pairs)) != 101:
        raise ValueError("unexpected universe")
    return dict(pairs)

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--xml", type=pathlib.Path, required=True, help="downloaded official report")
    p.add_argument("--date", required=True)
    p.add_argument("--universe", type=pathlib.Path, default=pathlib.Path("macro/nasdaq100-cds.json"))
    args = p.parse_args()
    with args.xml.open("rb") as f:
        raw = f.read(MAX_BYTES+1)
    print(json.dumps(read_xml(raw, args.date, load_tickers(args.universe)), indent=2))
if __name__ == "__main__":
    main()
