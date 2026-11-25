#!/usr/bin/env python3
"""V66-V68: SEC monthly fund research panel, revision review and backtest readiness."""
from __future__ import annotations
import argparse
import json
import time
import urllib.error
from datetime import date, datetime, timezone
from decimal import Decimal
from pathlib import Path
from scripts.asset_compass_sec_returns_v63 import ROOT, parse_filing, MAX_BYTES
from scripts.asset_compass_sec_returns_v64 import REGISTRY, check_reference, fetch

TLT = {
    "000175272423165683":"2023-05-31",
    "000175272423238735":"2023-08-31",
    "000175272424015053":"2023-11-30",
    "000175272424088779":"2024-02-29",
    "000175272424162927":"2024-05-31",
    "000175272424237596":"2024-08-31",
    **REGISTRY,
    "000207169126024225":"2026-08-31",
}
IVV = {
    "000175272424269943":"2024-09-30",
    "000175272425043800":"2024-12-31",
    "000175272425119791":"2025-03-31",
    "000175272425210389":"2025-06-30",
    "000207169125007634":"2025-09-30",
    "000207169126004238":"2025-12-31",
    "000207169126012459":"2026-03-31",
    "000207169126019760":"2026-06-30",
}
AMEND = {"000207169126015790":"2025-09-30"}
FUNDS = {
    "TLT":("us_long_bonds","S000004360","C000012090",TLT),
    "IVV":("us_equities","S000004310","C000012040",IVV),
}
# Optional earlier candidate filings; identity and actual report date must
# pass the same raw XML checks before a month is counted.
EXTENDED = {
    "TLT":{"000175272423012198":"2022-11-30","000175272423086769":"2023-02-28"},
    "IVV":{"000175272424043113":"2023-12-31","000175272424123331":"2024-03-31","000175272424194289":"2024-06-30"},
}
def fund_registry(extended=False):
    return {k:(asset,series,cls,{**(EXTENDED[k] if extended else {}),**registry})
            for k,(asset,series,cls,registry) in FUNDS.items()}

MIN_TRAIN_MONTHS = 36
MIN_TEST_MONTHS = 12

def months(first,last):
    a,b = date.fromisoformat(first+"-01"),date.fromisoformat(last+"-01")
    return [f"{i//12:04d}-{i%12+1:02d}" for i in range(a.year*12+a.month-1,b.year*12+b.month)]

def target(ticker, extended=False):
    if ticker=="TLT":
        return months("2022-09" if extended else "2023-03","2026-08")
    return months("2023-10" if extended else "2024-07","2026-06")

def parse(ticker, accession, raw, *, amendment=False, extended=False):
    asset,series,cls,registry=fund_registry(extended)[ticker]
    if amendment:
        if ticker!="IVV": raise ValueError("Unexpected amendment")
        registry=AMEND
    result=parse_filing(raw,accession,registry,series_id=series,class_id=cls)
    if ticker=="TLT":
        result["matches_reviewed_sec_display"]=check_reference(result)
    return result

def reconcile(original, amendment):
    if original["report_period_end"]!=amendment["report_period_end"]:
        raise ValueError("Amendment period mismatch")
    before={x["month"]:Decimal(x["reported_fund_total_return_percent"]) for x in original["monthly_observations"]}
    after={x["month"]:Decimal(x["reported_fund_total_return_percent"]) for x in amendment["monthly_observations"]}
    if set(before)!=set(after): raise ValueError("Amendment months mismatch")
    return {"original_accession":original["accession"],"amendment_accession":amendment["accession"],
            "amendment_sha256":amendment["local_input_sha256"],
            "changed_months":[m for m in sorted(before) if before[m]!=after[m]],
            "historical_publication_clock_verified":False,
            "original_retained_no_silent_revision":True}

def build(raw, amendments=None, *, extended=False):
    registry_by_fund=fund_registry(extended)
    allowed=set().union(*(set(v[3]) for v in registry_by_fund.values()))
    if set(raw)-allowed or set(amendments or {})-set(AMEND):
        raise ValueError("Unknown filing")
    funds={}
    revisions=[]
    for ticker,(asset,series,cls,registry) in registry_by_fund.items():
        rows,receipts,parsed={},[],{}
        for accession in registry:
            if accession not in raw: continue
            f=parse(ticker,accession,raw[accession],extended=extended)
            parsed[accession]=f
            receipts.append({k:v for k,v in f.items() if k!="monthly_observations"})
            for r in f["monthly_observations"]:
                m=r["month"]
                if m in rows or m not in target(ticker,extended):
                    raise ValueError("Duplicate or out-of-window month")
                rows[m]={**r,"accession":accession}
        if ticker=="IVV" and amendments and "000207169125007634" in parsed:
            for accession,content in amendments.items():
                revisions.append(reconcile(parsed["000207169125007634"],parse("IVV",accession,content,amendment=True)))
        missing=[m for m in target(ticker,extended) if m not in rows]
        funds[ticker]={"asset":asset,"ticker":ticker,"series_id":series,"class_id":cls,
            "target_months":len(target(ticker,extended)),"parsed_months":len(rows),"missing_months":missing,
            "source_receipts":receipts,"monthly_observations":[rows[m] for m in sorted(rows)],
            "fund_reported_return_not_investor_execution":True,"investable_total_return_certified":False}
    common=sorted(set(x["month"] for x in funds["TLT"]["monthly_observations"]) &
                  set(x["month"] for x in funds["IVV"]["monthly_observations"]))
    continuous=common==months(common[0],common[-1]) if common else False
    # Sample-size preparation only. No use of returns as predictors; no fit or OOS claim.
    for f in funds.values():
        f["minimum_research_sample_months"]=MIN_TRAIN_MONTHS+MIN_TEST_MONTHS
        f["meets_minimum_sample_count"]=not f["missing_months"] and f["parsed_months"]>=MIN_TRAIN_MONTHS+MIN_TEST_MONTHS
        f["historical_pit_certified"]=False
        f["oos_validated"]=False
        f["official_score"]=None
    return {"report_type":"asset_compass_v66_v68_monthly_fund_research_panel",
            "generated_at":datetime.now(timezone.utc).isoformat(),"funds":funds,
            "common_observed_months":len(common),"common_window_contiguous":continuous,
            "common_first":common[0] if common else None,"common_last":common[-1] if common else None,
            "amendment_reviews":revisions,
            "minimum_train_months":MIN_TRAIN_MONTHS,"minimum_test_months":MIN_TEST_MONTHS,
            "pit_certified_macro_series":0,"independent_factor_groups_certified":0,
            "investable_total_return_certified_assets":0,"oos_validated_assets":0,
            "official_scores_published":0,"eligible_for_live_scoring":False}

def metadata(report):
    # Only metadata can leave private research workspace. No actual returns.
    return {**report,"funds":{k:{a:b for a,b in v.items() if a!="monthly_observations"}
                              for k,v in report["funds"].items()}}

def main():
    p=argparse.ArgumentParser(description=__doc__)
    group=p.add_mutually_exclusive_group(required=True)
    group.add_argument("--download",action="store_true")
    group.add_argument("--xml-dir",type=Path)
    p.add_argument("--output",type=Path,required=True)
    p.add_argument("--metadata",type=Path,required=True)
    p.add_argument("--require-complete",action="store_true")
    p.add_argument("--extended",action="store_true")
    args=p.parse_args()
    if any(x.resolve().is_relative_to(ROOT) for x in (args.output,args.metadata)) or args.output.resolve()==args.metadata.resolve():
        p.error("Distinct output paths outside the website repo required")
    raw,amendments,failures={}, {}, {}
    tasks=[(ticker,a,reg,False) for ticker,(_,_,_,reg) in fund_registry(args.extended).items() for a in reg]
    tasks.extend(("IVV",a,AMEND,True) for a in AMEND)
    for ticker,accession,registry,is_amend in tasks:
        stage="download" if args.download else "local_read"
        try:
            if args.download:
                time.sleep(1)
                content=fetch(accession,registry)
            else:
                with (args.xml_dir/(accession+".xml")).open("rb") as f: content=f.read(MAX_BYTES+1)
            stage="parse_and_identity"
            parse(ticker,accession,content,amendment=is_amend,extended=args.extended)
            (amendments if is_amend else raw)[accession]=content
        except urllib.error.HTTPError as exc:
            failures[accession]={"stage":stage,"http_status":exc.code}
            if exc.code in (403,429): break
        except (OSError,ValueError) as exc:
            failures[accession]={"stage":stage,"type":type(exc).__name__,
                "reason":str(exc) if isinstance(exc,ValueError) else None}
    for _,a,_,_ in tasks:
        if a not in raw and a not in amendments and a not in failures:
            failures[a]={"stage":"not_attempted_after_access_denial"}
    result=build(raw,amendments,extended=args.extended)
    result["source_failures"]=failures
    for file,report in ((args.output,result),(args.metadata,metadata(result))):
        file.parent.mkdir(parents=True,exist_ok=True)
        file.write_text(json.dumps(report,indent=2,allow_nan=False)+"\n",encoding="utf-8")
    print(json.dumps({"funds":{k:{"parsed_months":v["parsed_months"],"target_months":v["target_months"],"missing_months":v["missing_months"]} for k,v in result["funds"].items()},"common_observed_months":result["common_observed_months"],"amendment_reviews":result["amendment_reviews"],"source_failures":failures,"eligible_for_live_scoring":False}))
    if args.require_complete and (failures or any(v["missing_months"] for v in result["funds"].values()) or len(result["amendment_reviews"])!=len(AMEND)):
        raise SystemExit(1)

if __name__=="__main__":
    main()
