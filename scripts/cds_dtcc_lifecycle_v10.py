#!/usr/bin/env python3
"""Bounded multi-report lifecycle quarantine. No trade IDs or prices are emitted."""
import argparse
import collections
import datetime as dt
import json
from cds_dtcc_probe_v8 import fetch
from cds_dtcc_diagnostic_v9 import read_rows, exact_name
ACTIONS={"NEWT","MODI","CORR","TERM","EROR","REVI","POSC"}
def diagnose(reports, issuers):
    records=collections.defaultdict(list)
    stats=collections.Counter()
    dates={}
    names=collections.defaultdict(set)
    for issuer in issuers:
        for name in (issuer["name"],(issuer.get("issuer_identity") or {}).get("legal_name","")):
            if name: names[exact_name(name)].add(issuer["issuer_id"])
    for day, raw in sorted(reports.items()):
        base, fields, rows=read_rows(raw,day)
        for key in ("dissemination identifier","original dissemination identifier","action type"):
            if key not in fields: raise ValueError("missing lifecycle column")
        dates[day]={"rows":len(rows),"sha256":base["sha256"]}
        for row in rows:
            def field(k): return row.get(fields.get(k,""),"").strip()
            rid,orig,act=field("dissemination identifier"),field("original dissemination identifier"),field("action type").upper()
            stats["report_rows"]+=1
            if not rid: stats["missing_id_rows"]+=1
            if act not in ACTIONS: stats["unknown_action_rows"]+=1
            matches=set()
            for key in ("upi underlier name","underlying asset name","underlying asset name leg 1"):
                matches.update(names.get(exact_name(field(key)),set()))
            records[rid].append((day,orig,act,matches))
    # Quarantine all records touched by any reference, even unknown action or malformed IDs.
    referenced=set()
    for rid,entries in records.items():
        for day,orig,act,_ in entries:
            if not orig:
                if act!="NEWT": stats["non_new_missing_original_rows"]+=1
                continue
            referenced.add(orig)
            if orig not in records: stats["unresolved_original_rows"]+=1
            elif any(d<day for d,_,_,_ in records[orig]):
                stats["cross_day_reference_rows"]+=1
            elif any(d==day for d,_,_,_ in records[orig]):
                stats["same_day_reference_rows"]+=1
            else: stats["future_reference_rows"]+=1
    candidates=set()
    for rid,entries in records.items():
        for day,orig,act,matches in entries:
            if act!="NEWT": stats["non_new_rows"]+=1; continue
            if not rid or len(entries)!=1 or orig or rid in referenced:
                stats["quarantined_new_rows"]+=1
                continue
            stats["unlinked_new_rows_in_window"]+=1
            if len(matches)==1:
                stats["exact_name_unlinked_new_rows"]+=1
                candidates.update(matches)
    return {"report_dates":dates,"diagnostic_counts":dict(stats),
            "candidate_issuer_count":len(candidates),"verified_reference_entities":0,
            "admitted_spreads":0,"publication_enabled":False,
            "scope":"bounded_window_quarantine_not_active_trade_reconstruction"}
def main():
    p=argparse.ArgumentParser()
    p.add_argument("--end",required=True)
    p.add_argument("--days",type=int,default=7)
    args=p.parse_args()
    end=dt.date.fromisoformat(args.end)
    today=dt.datetime.now(dt.timezone.utc).date()
    if not 1<=args.days<=7 or end>=today or end<today-dt.timedelta(days=359): p.error("bounded past window")
    with open("macro/nasdaq100-cds.json",encoding="utf-8") as f: d=json.load(f)
    if d["publication"]["enabled"] is not False or len(d["issuers"])!=100: raise ValueError("closed universe required")
    reports={}; failures={}
    for i in range(args.days-1,-1,-1):
        day=(end-dt.timedelta(days=i)).isoformat()
        try:
            raw=fetch(day)
            read_rows(raw,day)
            reports[day]=raw
        except Exception as exc:
            failures[day]=type(exc).__name__
    result=diagnose(reports,d["issuers"])
    result.update({"attempted_calendar_days":args.days,"failed_dates":failures,"window_end":args.end})
    print(json.dumps(result,indent=2,sort_keys=True))
    if not reports: raise SystemExit(1)
if __name__=="__main__":main()
