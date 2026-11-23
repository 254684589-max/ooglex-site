#!/usr/bin/env python3
"""V57 contemporaneous source overlap audit, NEVER predictive validation.

Aligns CFTC GOLD managed-money positioning and Chicago Fed NFCI with the
as-observed (latest-revised) US Treasury daily real and nominal rates.
CFTC Tuesday as-of date is PUBLICLY KNOWN ONLY LATER, so these correlations
cannot be used as historical as-of signals or backtest performance.
"""
from __future__ import annotations
import argparse
import bisect
import hashlib
import json
import math
import statistics
from datetime import date,datetime,timezone
from pathlib import Path

from scripts.validate_asset_compass_treasury_trends_v42 import validate
ROOT=Path(__file__).resolve().parents[1]
P57=ROOT/"data/asset-compass-asset-specific-v57.json"
P56=ROOT/"data/asset-compass-new-sources-v56.json"
TREASURY=ROOT/"data/asset-compass-treasury-history.json"
OUT=ROOT/"data/asset-compass-overlap-audit-v57.json"

def sha(value):
    return hashlib.sha256(json.dumps(value,sort_keys=True,ensure_ascii=False,
               separators=(",",":"),allow_nan=False).encode("utf-8")).hexdigest()


def align(source,daily,rate_key,source_key,date_key):
    days=[date.fromisoformat(r["date"]) for r in daily]
    if days!=sorted(set(days)):
        raise ValueError("Treasury daily source dates unsorted or duplicated")
    matched=[]
    for row in source:
        week=date.fromisoformat(row[date_key])
        idx=bisect.bisect_right(days,week)-1
        if idx<0 or (week-days[idx]).days>4:
            continue
        value=row[source_key]
        rate=daily[idx][rate_key]
        if (type(value) not in (float,int) or not math.isfinite(value)
          or type(rate) not in (float,int) or not math.isfinite(rate)):
            raise ValueError("Non-finite real source observation")
        matched.append((row[date_key],value,rate))
    if len({x[0] for x in matched})!=len(matched):
        raise ValueError("Duplicated weekly source observations")
    return matched


def pearson(pairs):
    if len(pairs)<50:
        return None
    xs=[x[1] for x in pairs];ys=[x[2] for x in pairs]
    xm=statistics.fmean(xs);ym=statistics.fmean(ys)
    xx=sum((v-xm)**2 for v in xs)
    yy=sum((v-ym)**2 for v in ys)
    if xx<=1e-10 or yy<=1e-10:return None
    corr=sum((x-xm)*(y-ym) for x,y in zip(xs,ys))/math.sqrt(xx*yy)
    return round(max(-1,min(1,corr)),6)


def audit(v57,v56,history,*,now=None):
    now=now or datetime.now(timezone.utc)
    if now.utcoffset() is None:raise ValueError("Timezone-aware now required")
    validate(history,minimum=270,now=now)
    if (v57.get("report_type")!="asset_compass_v57_authentic_asset_specific_source_research"
       or v57.get("approved_asset_scores")!=0
       or v57.get("validated_for_live_scoring") is not False
       or v57.get("first_publication_vintages_certified")!=0
       or v57.get("v56_observed_at")!=v56.get("generated_at")
       or v56.get("report_type")!="asset_compass_v56_official_risk_and_oil_research"
       or v56.get("approved_asset_scores")!=0
       or v56.get("validated_for_live_scoring") is not False):
        raise ValueError("Nonqualified or inconsistent source lineage")
    cot=v57["sources"]["cftc_gold"]["recent_observations"]
    nfci=v56["sources"]["nfci"]["recent_observations"]
    if not isinstance(cot,list) or not isinstance(nfci,list) or len(cot)<80 or len(nfci)<80:
        raise ValueError("Historical source overlap samples insufficient")
    tests=[
      ("gold_positioning_vs_10y_real_yield",cot,"managed_money_net_pct_open_interest","date","real10y"),
      ("nfci_vs_10y_nominal_yield",nfci,"value","date","us10y"),
      ("nfci_vs_10y_real_yield",nfci,"value","date","real10y"),
      ("nfci_vs_10y_2y_spread",nfci,"value","date","spread10y2y"),
    ]
    results={}
    for name,rows,source_key,date_key,rate_key in tests:
        matches=align(rows,history["observations"],rate_key,source_key,date_key)
        if len(matches)<52:
            raise ValueError("Insufficient actual cross-source aligned observations "+name)
        results[name]={
          "aligned_weekly_observations":len(matches),
          "aligned_first_date":matches[0][0],
          "aligned_last_date":matches[-1][0],
          "treasury_series":rate_key,
          "contemporaneous_pearson_latest_revised":pearson(matches),
          "causal_predictive_independence_qualified":False,
          "historical_available_at_verified":False,
          "oos_predictive_significance_tested":False,
        }
    return {
      "schema_version":1,
      "report_type":"asset_compass_v57_descriptive_source_overlap_audit",
      "status":"research_only_no_predictive_certification",
      "generated_at":now.astimezone(timezone.utc).isoformat(),
      "inputs_sha256":{
        "v57_gold_treasury":sha(v57),"v56_nfci":sha(v56),"treasury_daily":sha(history)},
      "results":results,
      "source_comparison_count":len(results),
      "available_for_investment_scoring":False,
      "historical_pit_qualified":False,
      "independent_risk_credit_factor_approved":False,
      "out_of_sample_return_calibration_passed":False,
      "score":None,
      "warnings":[
        "Latest-revised same-date correlations are descriptive; neither causal nor predictive.",
        "CFTC futures positions as-of Tuesday are released days later, and cannot inform same-day trades.",
        "NFCI is a composite of interest-rate, credit, bank and risk factors; mechanically overlaps existing rates.",
        "Derived Treasury spread shares rate data; high correlations must never be counted as multiple independent model votes.",
        "No autocorrelation controls, multiple-testing correction, economic regime test, or out-of-sample returns are included.",
        "This report creates no verified factor signals or six-asset 0-100 scores.",
      ],
    }


def main():
    p=argparse.ArgumentParser()
    p.add_argument("--v57",type=Path,default=P57)
    p.add_argument("--v56",type=Path,default=P56)
    p.add_argument("--treasury",type=Path,default=TREASURY)
    p.add_argument("--output",type=Path,default=OUT)
    a=p.parse_args()
    read=lambda f:json.loads(f.read_text(encoding="utf-8"))
    result=audit(read(a.v57),read(a.v56),read(a.treasury))
    a.output.parent.mkdir(parents=True,exist_ok=True)
    a.output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(json.dumps({
      "status":result["status"],
      "correlations":{k:v["contemporaneous_pearson_latest_revised"]
                      for k,v in result["results"].items()},
      "qualified_independent_signals":0,"approved_asset_scores":0,
    },ensure_ascii=False))


if __name__=="__main__":main()
