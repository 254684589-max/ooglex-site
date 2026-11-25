#!/usr/bin/env python3
"""Combined V12–V15 statutory-source audit. No actual prices or product IDs emitted."""
import argparse
import collections
import datetime as dt
import hashlib
import json
import re
import xml.etree.ElementTree as ET
from cds_dtcc_probe_v8 import fetch, number
from cds_dtcc_diagnostic_v9 import read_rows, exact_name
from cds_dtcc_mapping_v11 import valid_lei
from collect_tradeweb_cds_v5 import download, audit
from audit_tradeweb_cds_v2 import NAME, UPI

STAGES=("name_product_candidate","cross_source_upi","approx_5y","usd_same_leg_inputs",
        "upfront_amount_present","price_field_with_notation","strict_joint_input_candidate")
def tradeweb_products(reports,tickers):
    profiles=collections.defaultdict(set)
    evidence={}
    for day,raw in sorted(reports.items()):
        meta=audit(raw,day,tickers)
        evidence[day]={"sha256":meta["sha256"],"rows":meta["report_rows"]}
        for row in ET.fromstring(raw).findall("sbsTnr"):
            def one(k):
                v=row.findall(k)
                return (v[0].text or "").strip() if len(v)==1 else ""
            upi=one("upi"); label=NAME.fullmatch(one("sbsNm"))
            if UPI.fullmatch(upi) and label and one("tenor")=="P5Y" and one("ccy")=="USD":
                # Include non-target labels to detect conflicting product identities.
                profiles[upi].add(tickers.get(label[1],"unmatched:"+label[1]))
    return profiles,evidence

def diagnose(dtcc,tradeweb,issuers):
    names=collections.defaultdict(set);leis={};tickers={}
    for issuer in issuers:
        i=issuer["issuer_id"];identity=issuer.get("issuer_identity") or {}
        for t in issuer["tickers"]:
            if t in tickers:raise ValueError("duplicate ticker")
            tickers[t]=i
        for n in (issuer["name"],identity.get("legal_name","")):
            if n:names[exact_name(n)].add(i)
        lei=identity.get("lei","")
        if lei:
            if not valid_lei(lei) or lei in leis:raise ValueError("invalid LEI")
            leis[lei]=i
    tw,tw_dates=tradeweb_products(tradeweb,tickers)
    dt_dates={};rows=[];profiles=collections.defaultdict(set);ids=collections.Counter();linked=set()
    for day,raw in sorted(dtcc.items()):
        base,fields,records=read_rows(raw,day)
        required=("dissemination identifier","original dissemination identifier","action type",
                  "unique product identifier","upi fisn","upi underlier name")
        if any(k not in fields for k in required):raise ValueError("missing schema")
        dt_dates[day]={"sha256":base["sha256"],"rows":len(records)}
        for row in records:
            v={k:row[h].strip() for k,h in fields.items()}
            rid=v["dissemination identifier"]; orig=v["original dissemination identifier"]
            ids[rid]+=1
            if orig:linked.add(orig)
            upi=v["unique product identifier"]
            if UPI.fullmatch(upi):profiles[upi].add((exact_name(v["upi underlier name"]),v["upi fisn"].upper()))
            rows.append((day,v))
    stats=collections.Counter();by_issuer=collections.defaultdict(collections.Counter)
    by_date=collections.defaultdict(collections.Counter);unit_codes=collections.Counter()
    candidate_products=set();cross_products=set();strict_products=set()
    def count(stage,issuer,day):
        stats[stage]+=1;by_issuer[issuer][stage]+=1;by_date[day][stage]+=1
    for day,v in rows:
        def get(k):return v.get(k,"")
        upi=get("unique product identifier");rid=get("dissemination identifier")
        if get("action type").upper()!="NEWT" or not rid or ids[rid]!=1 or get("original dissemination identifier") or rid in linked:
            continue
        if not UPI.fullmatch(upi) or len(profiles[upi])!=1:continue
        name=get("upi underlier name");fisn=get("upi fisn")
        match=names.get(exact_name(name),set())
        if len(match)!=1 or not {"CDS","SN"}.issubset(set(re.findall(r"[A-Z0-9]+",fisn.upper()))):continue
        issuer=next(iter(match));observed=set();invalid=False
        for suffix in (" leg 1"," leg 2",""):
            if get("underlier id source"+suffix).upper()=="LEI":
                lei=get("underlier id"+suffix).upper()
                if not valid_lei(lei):invalid=True
                else:observed.add(lei)
        if invalid or len(observed)>1 or any(leis.get(x)!=issuer for x in observed):continue
        if upi in tw and tw[upi]!={issuer}:
            stats["cross_source_conflict_excluded"]+=1
            continue
        count("name_product_candidate",issuer,day);candidate_products.add(upi)
        cross=tw.get(upi)=={issuer}
        if cross:count("cross_source_upi",issuer,day);cross_products.add(upi)
        try:
            effective=dt.date.fromisoformat(get("effective date"))
            expiry=dt.date.fromisoformat(get("expiration date") or get("maturity date"))
            approx=1750<=(expiry-effective).days<=1900
        except ValueError:approx=False
        if approx:count("approx_5y",issuer,day)
        usd_legs=[];spread_legs=[]
        for leg in ("1","2"):
            suffix=" leg "+leg
            n=number(get("notional amount"+suffix));c=number(get("fixed rate"+suffix))
            s=number(get("spread"+suffix));notation=get("spread notation"+suffix).upper()
            if s is not None and notation:
                # Diagnostic notation tokens only, not a unit conversion.
                unit_codes[notation if re.fullmatch(r"[A-Z]{1,16}",notation) else "OTHER"]+=1
                if get("notional currency"+suffix).upper()=="USD":spread_legs.append(leg)
            if (get("notional currency"+suffix).upper()=="USD" and n is not None and n>0
                and "+" not in get("notional amount"+suffix) and c is not None):
                usd_legs.append(leg)
        if usd_legs:count("usd_same_leg_inputs",issuer,day)
        upfront=(get("other payment type").upper() in {"UFRO","UPFRONT","UPFRONT PAYMENT"}
                 and number(get("other payment amount")) is not None and get("other payment currency").upper()=="USD")
        if upfront:count("upfront_amount_present",issuer,day)
        price=bool(spread_legs) or (number(get("price")) is not None and bool(get("price notation")))
        if price:count("price_field_with_notation",issuer,day)
        # Explicit non-package and non-postpriced flags only; still a research candidate.
        package=(get("package indicator") or get("package transaction indicator")).upper()
        postpriced=get("post priced swap indicator").upper()
        flags=package in {"FALSE","N","0"} and postpriced in {"FALSE","N","0"}
        if cross and approx and len(usd_legs)==1 and upfront and price and flags:
            count("strict_joint_input_candidate",issuer,day);strict_products.add(upi)
    # Per-date and per-issuer counts are audit coverage, not price history or risk scores.
    result={"schema_version":1,"state":"joint_source_audit","dtcc_reports":dt_dates,"tradeweb_reports":tw_dates,
            "counts":{**{k:0 for k in STAGES},**dict(stats)},
            "candidate_products":len(candidate_products),"cross_source_products":len(cross_products),
            "strict_joint_products":len(strict_products),"observed_spread_notation_codes":dict(unit_codes),
            "issuer_audit":{i:dict(c) for i,c in sorted(by_issuer.items())},
            "date_audit":{d:dict(c) for d,c in sorted(by_date.items())},
            "verified_reference_entities":0,"verified_upis":0,"admitted_spreads":0,"publication_enabled":False,
            "readiness":{"price_history":False,"risk_ranking":False,"alerts":False,"composite":False,
                "blockers":["independent authoritative UPI/reference entity confirmation",
                  "exact 5Y maturity/seniority and contractual conventions",
                  "price units and semantics, signed clean upfront, true notional",
                  "official model validation and cross-window lifecycle"]}}
    return result

def main():
    p=argparse.ArgumentParser();p.add_argument("--end",required=True);p.add_argument("--days",type=int,default=7)
    a=p.parse_args();end=dt.date.fromisoformat(a.end);today=dt.datetime.now(dt.timezone.utc).date()
    if not 1<=a.days<=7 or end>=today or end<today-dt.timedelta(days=359):p.error("bounded past window")
    with open("macro/nasdaq100-cds.json",encoding="utf-8") as f:d=json.load(f)
    if d["publication"]["enabled"] is not False or len(d["issuers"])!=100:raise ValueError("closed universe required")
    tickers={t:i["issuer_id"] for i in d["issuers"] for t in i["tickers"]}
    dc={};tw={};fail={"dtcc":{},"tradeweb":{}}
    for i in range(a.days-1,-1,-1):
        day=end-dt.timedelta(days=i);s=day.isoformat()
        try:
            raw=fetch(s);read_rows(raw,s);dc[s]=raw
        except Exception as e:fail["dtcc"][s]=type(e).__name__
        if day.weekday()<5:
            try:
                raw=download(s);audit(raw,s,tickers);tw[s]=raw
            except Exception as e:fail["tradeweb"][s]=type(e).__name__
    if not dc or not tw:raise SystemExit("one or both sources unavailable")
    r=diagnose(dc,tw,d["issuers"]);r["failures"]=fail;r["window_end"]=a.end
    print(json.dumps(r,indent=2,sort_keys=True))
if __name__=="__main__":main()
