#!/usr/bin/env python3
"""V11: correlate public report UPI metadata and legal-entity evidence. No market quotes."""
import argparse
import collections
import datetime as dt
import json
import re
from cds_dtcc_probe_v8 import fetch
from cds_dtcc_diagnostic_v9 import read_rows, exact_name

def valid_lei(s):
    if not re.fullmatch(r"[A-Z0-9]{18}[0-9]{2}",s): return False
    n=0
    for c in s:
        for digit in (str(ord(c)-55) if c.isalpha() else c):
            n=(n*10+int(digit))%97
    return n==1

def diagnose(reports, issuers):
    names=collections.defaultdict(set)
    leis={}
    for issuer in issuers:
        identity=issuer.get("issuer_identity") or {}
        for name in (issuer["name"],identity.get("legal_name","")):
            if name:names[exact_name(name)].add(issuer["issuer_id"])
        lei=identity.get("lei","")
        if lei:
            if not valid_lei(lei) or lei in leis:raise ValueError("invalid or duplicate issuer LEI")
            leis[lei]=issuer["issuer_id"]
    profiles=collections.defaultdict(set)
    rows=[]; counts=collections.Counter(); dates={}
    for day,raw in sorted(reports.items()):
        base,fields,records=read_rows(raw,day)
        required=("unique product identifier","upi fisn","upi underlier name","dissemination identifier","original dissemination identifier","action type")
        if any(k not in fields for k in required):raise ValueError("missing product metadata")
        dates[day]={"rows":len(records),"sha256":base["sha256"]}
        for r in records:
            def v(k):return r.get(fields.get(k,""),"").strip()
            upi=v("unique product identifier"); fisn=v("upi fisn"); name=v("upi underlier name")
            if not re.fullmatch(r"[A-Z0-9]{12}",upi):
                counts["invalid_upi_shape_rows"]+=1
                continue
            profiles[upi].add((exact_name(name),fisn.upper()))
            observed_leis=set(); malformed=False
            for suffix in (" leg 1"," leg 2",""):
                source=v("underlier id source"+suffix).upper()
                underlier=v("underlier id"+suffix).upper()
                if source=="LEI":
                    if valid_lei(underlier):observed_leis.add(underlier)
                    else:malformed=True
            rows.append((upi,fisn,name,observed_leis,malformed,v("action type").upper(),
                         v("dissemination identifier"),v("original dissemination identifier")))
    ids=collections.Counter(r[6] for r in rows)
    # All messages (including invalid UPI) must participate in lifecycle exclusion.
    all_ids=collections.Counter(); linked=set()
    for day,raw in sorted(reports.items()):
        _,fields,records=read_rows(raw,day)
        for r in records:
            rid=r[fields["dissemination identifier"]].strip()
            orig=r[fields["original dissemination identifier"]].strip()
            all_ids[rid]+=1
            if orig:linked.add(orig)
    candidates=set(); lei_candidates=set(); candidate_upis=set()
    conflicting={u for u,p in profiles.items() if len(p)!=1}
    for upi,fisn,name,observed,malformed,action,rid,orig in rows:
        if action!="NEWT" or not rid or all_ids[rid]!=1 or orig or rid in linked:
            counts["lifecycle_excluded_rows"]+=1;continue
        if upi in conflicting or not name or not fisn:
            counts["metadata_conflict_or_missing_rows"]+=1;continue
        matched=names.get(exact_name(name),set())
        if len(matched)!=1:
            counts["name_not_unique_rows"]+=1;continue
        issuer=next(iter(matched))
        # FISN contains descriptive labels; this is not a certified template lookup.
        tokens=set(re.findall(r"[A-Z0-9]+",fisn.upper()))
        if not {"CDS","SN"}.issubset(tokens):
            counts["not_cds_single_name_label_rows"]+=1;continue
        if malformed or len(observed)>1 or (observed and any(leis.get(x)!=issuer for x in observed)):
            counts["lei_conflict_or_unmatched_rows"]+=1;continue
        candidates.add(issuer);candidate_upis.add(upi)
        counts["consistent_name_single_name_cds_label_rows"]+=1
        if observed:
            lei_candidates.add(issuer)
            counts["explicit_lei_corroborated_rows"]+=1
        else:counts["no_explicit_lei_rows"]+=1
    return {"report_dates":dates,"distinct_upis":len(profiles),"conflicting_upis":len(conflicting),
            "counts":dict(counts),"candidate_issuer_ids":sorted(candidates),
            "candidate_upi_count":len(candidate_upis),"explicit_lei_candidate_issuer_ids":sorted(lei_candidates),
            "verified_reference_entities":0,"verified_upis":0,"admitted_spreads":0,"publication_enabled":False}
def main():
    p=argparse.ArgumentParser();p.add_argument("--end",required=True);p.add_argument("--days",type=int,default=7)
    a=p.parse_args();end=dt.date.fromisoformat(a.end);today=dt.datetime.now(dt.timezone.utc).date()
    if not 1<=a.days<=7 or end>=today or end<today-dt.timedelta(days=359):p.error("bounded past window")
    with open("macro/nasdaq100-cds.json",encoding="utf-8") as f:d=json.load(f)
    if d["publication"]["enabled"] is not False or len(d["issuers"])!=100:raise ValueError("closed universe")
    reports={};failures={}
    for i in range(a.days-1,-1,-1):
        day=(end-dt.timedelta(days=i)).isoformat()
        try:
            raw=fetch(day);read_rows(raw,day);reports[day]=raw
        except Exception as e:failures[day]=type(e).__name__
    if not reports:raise SystemExit("no valid reports")
    result=diagnose(reports,d["issuers"]);result["failed_dates"]=failures
    print(json.dumps(result,indent=2,sort_keys=True))
if __name__=="__main__":main()
