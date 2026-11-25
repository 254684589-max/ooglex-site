#!/usr/bin/env python3
"""V117–V123: actual SEC NAV quarterly research; no invented monthly returns."""
import argparse
import hashlib
import json
import time
import urllib.error
from datetime import datetime,timezone
from decimal import Decimal
from pathlib import Path
from statistics import fmean,pstdev
from scripts.asset_compass_sec_returns_v63 import ROOT
from scripts.asset_compass_sec_returns_v66 import months
from scripts.asset_compass_sec_performance_v84 import tables,row_label,numbers,download

BASE="https://www.sec.gov/Archives/edgar/data/"
# Explicit period-column mapping independently reviewed against financial highlights.
# The two quarterly columns always precede cumulative columns. Partial inception
# periods are labeled separately and never treated as full quarters.
DOCS=(
 ("GLD","1222333/000143774925002865/gld20241231_10q.htm",["2024-12","2023-12"],["-0.83","10.15"],[]),
 ("GLD","1222333/000143774925015077/gld20250331_10q.htm",["2025-03","2024-03"],["19.20","7.26","18.22","18.15"],[]),
 ("GLD","1222333/000143774925024998/gld20250630_10q.htm",["2025-06","2024-06"],["5.43","5.16","24.63","24.25"],["2025-09","2024-09"]),
 ("GLD","1222333/000143774926002987/gld20251231_10q.htm",["2025-12","2024-12"],["12.51","-0.83"],[]),
 ("GLD","1222333/000143774926014926/gld20260331_10q.htm",["2026-03","2025-03"],["6.87","19.20","20.24","18.22"],[]),
 ("GLD","1222333/000143774926025680/gld20260630_10q.htm",["2026-06","2025-06"],["-12.72","5.43","4.94","24.63"],["2026-09","2025-09"]),
 ("GLD","1222333/000143774926038190/gld20260930_10k.htm",[],["8.74","44.89","40.06"],["2026-09","2025-09","2024-09"]),
 ("IBIT","1980994/000143774925024884/bit20250630_10q.htm",["2025-06","2024-06"],["29.17","-10.30","14.69","37.20"],[]),
 ("IBIT","1980994/000143774925033435/bit20250930_10q.htm",["2025-09","2024-09"],["6.47","0.44","22.11","37.80"],["2025-12","2024-12"]),
 ("IBIT","1980994/000143774925015168/bit20250331_10q.htm",["2025-03",None],["-11.21","52.94"],[]),
 ("IBIT","1980994/000143774926015538/bit20260331_10q.htm",["2026-03","2025-03"],["-22.15","-11.21"],[]),
 ("IBIT","1980994/000143774926026004/bit20260630c_10q.htm",["2026-06","2025-06"],["-13.31","29.17","-32.51","14.69"],[]),
 ("IBIT","1980994/000143774926035539/ibit20260930_10q.htm",["2026-09","2025-09"],["41.52","6.47","-4.50","22.11"],[]),
 ("IBIT","1980994/000143774926006058/bit20251231_10k.htm",[],["-6.55","101.93"],["2025-12","2024-12"]),
)
WINDOWS={"GLD":("2023-12","2026-09"),"IBIT":("2024-06","2026-09")}

def quarter_months(first,last):
    return [m for m in months(first,last) if int(m[-2:])%3==0]

def parse_doc(doc,raw):
    ticker,path,periods,reference,annual_periods=doc
    identity="SPDR" if ticker=="GLD" else "iShares Bitcoin Trust"
    found=[]
    for table in tables(raw,identity):
        for row in table:
            if row_label(row).lower().startswith("total return, at net asset value"):
                vals=numbers(row)
                if len(vals)==len(reference):found.append(vals)
    if len(found)!=1 or found[0]!=list(map(Decimal,reference)):
        raise ValueError("Missing/ambiguous or changed reviewed financial highlights")
    values=found[0]
    return {"ticker":ticker,"url":BASE+path,"sha256":hashlib.sha256(raw).hexdigest(),
            "direct":{p:v for p,v in zip(periods,values) if p is not None},
            "cumulative":dict(zip(annual_periods,values[len(periods):])),
            "kind":"cumulative_partial" if periods else "annual"}

def add_unique(store,key,val,sha):
    if key in store:
        if store[key]["value"]!=val:raise ValueError("Cross-filing return disagreement")
        store[key]["source_sha256"].append(sha)
    else:store[key]={"value":val,"source_sha256":[sha]}

def derive_quarter(annual,partial):
    if annual<=-100 or partial<=-100:raise ValueError("Invalid cumulative return")
    return ((1+annual/100)/(1+partial/100)-1)*100

def combine(parsed,ticker):
    direct={};partial={};annual={}
    for p in parsed:
        if p["ticker"]!=ticker:continue
        for k,v in p["direct"].items():add_unique(direct,k,v,p["sha256"])
        dst=annual if p["kind"]=="annual" else partial
        for k,v in p["cumulative"].items():add_unique(dst,k,v,p["sha256"])
    out={k:{"value":str(v["value"]),"method":"reported_three_month_nav_return","source_sha256":v["source_sha256"]} for k,v in direct.items()}
    for k in sorted(set(annual)&set(partial)):
        if k in out:raise ValueError("Derived period duplicates direct return")
        # IBIT 2024 both cumulative periods begin Jan 10, not Jan 1;
        # dividing gross returns cancels the common partial start.
        v=derive_quarter(annual[k]["value"],partial[k]["value"])
        out[k]={"value":str(v.quantize(Decimal("0.0001"))),"method":"derived_from_reported_annual_and_nine_month_gross_returns",
                "source_sha256":annual[k]["source_sha256"]+partial[k]["source_sha256"],
                "rounded_inputs":True}
    target=quarter_months(*WINDOWS[ticker])
    if set(out)-set(target):raise ValueError("Out of window quarter")
    return {"frequency":"quarterly","observations":{k:out[k] for k in sorted(out)},
            "target_quarters":len(target),"actual_quarters":len(out),
            "missing_quarters":sorted(set(target)-set(out)),
            "direct_quarters":len(direct),"derived_quarters":len(out)-len(direct),
            "monthly_returns_inferred":False,"investable_total_return_certified":False}

def aggregate_monthly(fund):
    by={}
    for row in fund["monthly_observations"]:
        k=row["month"]
        if k in by:raise ValueError("Duplicate fund month")
        v=Decimal(row["reported_fund_total_return_percent"])
        if not v.is_finite() or v < -100:raise ValueError("Invalid fund return")
        by[k]=v
    if not by:return {}
    result={}
    for end in quarter_months(min(by),max(by)):
        y,m=map(int,end.split("-"))
        keys=[f"{y:04d}-{i:02d}" for i in range(m-2,m+1)]
        if not all(k in by for k in keys):continue
        gross=Decimal(1)
        for k in keys:gross*=1+by[k]/100
        result[end]=float((gross-1)*100)
    return result

def common_diagnostics(funds):
    common=sorted(set.intersection(*(set(v) for v in funds.values()))) if funds else []
    if not common:return {"common_quarters":[],"descriptive":{}}
    stats={}
    for ticker,rows in funds.items():
        vals=[rows[k] for k in common]
        stats[ticker]={"common_quarters":len(vals),"mean_quarterly_return_pct":round(fmean(vals),6),
                       "quarterly_return_std_pct":round(pstdev(vals),6),
                       "positive_quarters":sum(v>0 for v in vals)}
    return {"common_quarters":common,"descriptive":stats,"predictive_validation":False,
            "note":"Same calendar quarters only; descriptive fund return comparison, not strategy returns."}

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--panel",type=Path,required=True)
    p.add_argument("--extra",type=Path,required=True)
    p.add_argument("--metadata",type=Path,required=True)
    a=p.parse_args()
    if a.metadata.resolve().is_relative_to(ROOT):p.error("Private research output only")
    from scripts.asset_compass_cost_v124 import parse_market,paired_summary,research
    parsed=[];fail={};market_receipts=[];market_failures={}
    for doc in DOCS:
        try:
            time.sleep(1)
            raw=download(BASE+doc[1])
            parsed.append(parse_doc(doc,raw))
            if doc[0]=="GLD":
                try:market_receipts.append(parse_market(doc,raw))
                except ValueError as exc:market_failures[doc[1]]=str(exc)[:180]
        except (ValueError,OSError) as exc:
            fail[doc[1]]={"type":type(exc).__name__,"reason":str(exc)[:200]}
            if isinstance(exc,urllib.error.HTTPError) and exc.code in (403,429):break
    quarterly={k:combine(parsed,k) for k in WINDOWS}
    market=combine(market_receipts,"GLD")
    paired=paired_summary(quarterly["GLD"],market,market_receipts)
    panel=json.loads(a.panel.read_text());extra=json.loads(a.extra.read_text())
    if (panel.get("report_type")!="asset_compass_v66_v68_monthly_fund_research_panel"
        or extra.get("report_type")!="asset_compass_v84_v89_sec_performance_research"
        or any(d.get("eligible_for_live_scoring") is not False for d in (panel,extra))):
        raise ValueError("Unexpected source research panel")
    funds={k:aggregate_monthly(v) for k,v in {**panel["funds"],**extra["funds"]}.items()}
    funds.update({k:{m:float(r["value"]) for m,r in v["observations"].items()} for k,v in quarterly.items()})
    if set(funds)!={"GLD","IBIT","TLT","IVV","UUP","USO"}:raise ValueError("Incomplete six-fund registry")
    report={"report_type":"asset_compass_v117_v123_quarterly_research",
        "generated_at":datetime.now(timezone.utc).isoformat(),
        "source_receipts":[{"ticker":r["ticker"],"url":r["url"],"sha256":r["sha256"]} for r in parsed],
        "source_failures":fail,"quarterly_coverage":{k:{a:b for a,b in v.items() if a!="observations"} for k,v in quarterly.items()},
        "all_fund_quarter_counts":{k:len(v) for k,v in funds.items()},
        "common_diagnostics":common_diagnostics(funds),
        "cost_and_correlation_research":research(funds),
        "gld_market_nav_reconciliation":paired,
        "gld_market_source_failures":market_failures,
        "formal_oos_validated_assets":0,"historical_pit_certified":False,"official_scores_published":0,"eligible_for_live_scoring":False}
    a.metadata.write_text(json.dumps(report,indent=2,allow_nan=False)+"\n")
    print(json.dumps({k:report[k] for k in ("quarterly_coverage","all_fund_quarter_counts","common_diagnostics","source_failures","eligible_for_live_scoring")}))
    print(json.dumps({"gld_market_nav_reconciliation":paired,"gld_market_source_failures":market_failures,"cost_and_correlation_research":report["cost_and_correlation_research"]}))
    if fail or market_failures or market["missing_quarters"] or any(v["missing_quarters"] for v in quarterly.values()):raise SystemExit(1)

if __name__=="__main__":main()
