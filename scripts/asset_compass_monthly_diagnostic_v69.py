#!/usr/bin/env python3
"""V69-73: lagged monthly Treasury / fund-return research, NOT certified PIT or OOS."""
import argparse
import json
import math
from pathlib import Path
from statistics import fmean
from scripts.asset_compass_sec_returns_v63 import ROOT
from scripts.asset_compass_sec_returns_v66 import months
from scripts.validate_asset_compass_treasury_trends_v42 import validate

def prev(month,n):
    y,m=map(int,month.split("-"))
    i=y*12+m-1-n
    return f"{i//12:04d}-{i%12+1:02d}"

def examples(fund,history):
    # Last observed session per month, no forward fill. Predictor change is
    # t-3 to t-2, leaving an entire month between predictor and label.
    close={}
    for x in history["observations"]:
        close[x["date"][:7]]=x
    out=[]
    seen=set()
    for r in sorted(fund["monthly_observations"],key=lambda x:x["month"]):
        m=r["month"]
        if m in seen: raise ValueError("Duplicate return month")
        seen.add(m)
        p,q=prev(m,3),prev(m,2)
        if p not in close or q not in close: continue
        y=float(r["reported_fund_total_return_percent"])
        x=100*(close[q]["us10y"]-close[p]["us10y"])
        if not math.isfinite(y) or y < -100 or not math.isfinite(x):
            raise ValueError("Invalid research observation")
        out.append({"month":m,"predictor_end":close[q]["date"],"rate_change_bp":x,"return_percent":y})
    return out

def evaluate(rows, *, min_train=24, min_test=6):
    # Fixed, chronological exploratory split; no parameter search or trading P&L.
    if len(rows)<min_train+min_test:
        return {"status":"insufficient_exploratory_samples","aligned_months":len(rows)}
    if [r["month"] for r in rows]!=months(rows[0]["month"],rows[-1]["month"]):
        return {"status":"calendar_gap","aligned_months":len(rows)}
    train,test=rows[:-min_test],rows[-min_test:]
    x=[r["rate_change_bp"] for r in train]
    y=[r["return_percent"] for r in train]
    mx,my=fmean(x),fmean(y)
    var=sum((a-mx)**2 for a in x)
    if var<=1e-12:
        return {"status":"zero_train_variance","aligned_months":len(rows)}
    beta=sum((a-mx)*(b-my) for a,b in zip(x,y))/var
    alpha=my-beta*mx
    forecasts=[alpha+beta*r["rate_change_bp"] for r in test]
    actual=[r["return_percent"] for r in test]
    return {"status":"exploratory_holdout_not_pit","aligned_months":len(rows),
            "train_count":len(train),"test_count":len(test),
            "train_last_month":train[-1]["month"],"test_first_month":test[0]["month"],
            "test_last_month":test[-1]["month"],
            "train_slope_pct_per_bp":round(beta,8),
            "holdout_mae_pct":round(fmean(abs(a-b) for a,b in zip(forecasts,actual)),6),
            "training_mean_baseline_mae_pct":round(fmean(abs(a-my) for a in actual),6),
            "holdout_direction_hits":sum((a>0)==(b>0) for a,b in zip(forecasts,actual) if a!=0 and b!=0),
            "constant_long_hits":sum(a>0 for a in actual),
            "formal_oos_validated":False}

def build(panel,history):
    if panel.get("report_type")!="asset_compass_v66_v68_monthly_fund_research_panel" or panel.get("eligible_for_live_scoring") is not False:
        raise ValueError("Unapproved fund research input")
    validate(history)
    results={k:evaluate(examples(f,history)) for k,f in panel["funds"].items()}
    return {"report_type":"asset_compass_v69_v73_exploratory_lagged_monthly_diagnostic",
            "treasury_observations":history["observation_count"],"assets":results,
            "predictor":"10Y nominal Treasury yield change t-3 to t-2, basis points",
            "label":"reported ETF fund total return in month t, percent",
            "historical_pit_certified":False,"investor_costs_reconciled":False,
            "independent_factor_groups_certified":0,"formal_oos_validated_assets":0,
            "official_scores_published":0,"eligible_for_live_scoring":False,
            "limitations":["Latest retrieved Treasury series, not original vintage.",
                           "Fixed lag does not prove historical availability.",
                           "Single factor and short holdout, not statistical certification.",
                           "No investor execution costs, no strategy returns."]}

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--panel",type=Path,required=True)
    p.add_argument("--history",type=Path,default=ROOT/"data/asset-compass-treasury-history.json")
    p.add_argument("--output",type=Path,required=True)
    a=p.parse_args()
    if a.output.resolve().is_relative_to(ROOT):p.error("Research output must remain outside website repo")
    r=build(json.loads(a.panel.read_text()),json.loads(a.history.read_text()))
    a.output.write_text(json.dumps(r,indent=2,allow_nan=False)+"\n")
    # No raw return or factor series in logs.
    print(json.dumps({"treasury_observations":r["treasury_observations"],"assets":r["assets"],"eligible_for_live_scoring":False}))

if __name__=="__main__":main()
