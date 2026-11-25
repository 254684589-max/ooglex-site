#!/usr/bin/env python3
"""V74-V78: lagged multi-source monthly research; NOT PIT, formal OOS or a live score."""
import argparse
import hashlib
import json
import math
from datetime import date, datetime, timezone
from pathlib import Path
from statistics import fmean, pstdev
from scripts.asset_compass_sec_returns_v63 import ROOT
from scripts.asset_compass_sec_returns_v66 import months
from scripts.asset_compass_monthly_diagnostic_v69 import prev
from scripts.validate_asset_compass_treasury_trends_v42 import validate
from scripts.build_asset_compass_usd_v58 import retrieve_fed_xml, parse_fed_xml, FED_XML_URL
from scripts.build_asset_compass_new_sources_v56 import fetch_official, parse_nfci, FRED_URL

FEATURES=("rate_10y_change_bp","usd_h10_change_pct","nfci_level")
MIN_TRAIN=24
TEST=6
EMBARGO=3
RIDGE=0.1  # fixed standardized mean-square penalty, not tuned on test data

def month_end(rows,field):
    out={}
    last=""
    today=datetime.now(timezone.utc).date()
    for r in rows:
        d=date.fromisoformat(r["date"])
        v=r[field]
        if r["date"]<=last or d>today or type(v) not in (int,float) or not math.isfinite(v):
            raise ValueError("Invalid, future or duplicate source observation")
        last=r["date"]
        # Do not use an incomplete month or an old observation as month-end.
        if d.month==today.month and d.year==today.year: continue
        from calendar import monthrange
        if monthrange(d.year,d.month)[1]-d.day<=7:
            out[last[:7]]=r
    return out

def align(fund,treasury,usd,nfci):
    t=month_end(treasury,"us10y");u=month_end(usd,"index");n=month_end(nfci,"value")
    rows=[];missing=[];seen=set()
    for r in sorted(fund["monthly_observations"],key=lambda x:x["month"]):
        m=r["month"]
        if m in seen:raise ValueError("Duplicate fund month")
        seen.add(m)
        p,q=prev(m,3),prev(m,2)
        if not (p in t and q in t and p in u and q in u and q in n):
            missing.append(m)
            continue
        if u[p]["index"]<=0 or u[q]["index"]<=0:raise ValueError("Invalid H10 index")
        x=[100*(t[q]["us10y"]-t[p]["us10y"]),100*(u[q]["index"]/u[p]["index"]-1),n[q]["value"]]
        y=float(r["reported_fund_total_return_percent"])
        if not math.isfinite(y) or y < -100 or not all(math.isfinite(v) for v in x):
            raise ValueError("Invalid aligned observation")
        rows.append({"month":m,"x":x,"y":y,"latest_feature_observation":max(t[q]["date"],u[q]["date"],n[q]["date"])})
    return rows,missing

def solve(a,b):
    # Gaussian elimination with pivoting, for at most three ridge coefficients.
    a=[list(r)+[v] for r,v in zip(a,b)];n=len(a)
    for j in range(n):
        k=max(range(j,n),key=lambda i:abs(a[i][j]))
        if abs(a[k][j])<1e-12:raise ValueError("Singular system")
        a[j],a[k]=a[k],a[j]
        scale=a[j][j]
        a[j]=[v/scale for v in a[j]]
        for i in range(n):
            if i==j:continue
            scale=a[i][j]
            a[i]=[v-scale*w for v,w in zip(a[i],a[j])]
    return [r[-1] for r in a]

def fit(train,indices):
    if not train:raise ValueError("Empty training set")
    y=[r["y"] for r in train];ym=fmean(y)
    mu=[fmean(r["x"][i] for r in train) for i in indices]
    sd=[pstdev([r["x"][i] for r in train]) for i in indices]
    if any(v<=1e-12 for v in sd):raise ValueError("Constant training predictor")
    z=[[(r["x"][i]-m)/d for i,m,d in zip(indices,mu,sd)] for r in train]
    n=len(train);p=len(indices)
    gram=[[sum(r[i]*r[j] for r in z)+(RIDGE*n if i==j else 0) for j in range(p)] for i in range(p)]
    rhs=[sum(r[i]*(v-ym) for r,v in zip(z,y)) for i in range(p)]
    beta=solve(gram,rhs)
    def predict(row):
        return ym+sum(b*(row["x"][i]-m)/d for b,i,m,d in zip(beta,indices,mu,sd))
    predict.standardized_coefficients=tuple(beta)
    predict.feature_indices=tuple(indices)
    return predict

def correlation(train,i,j):
    a=[r["x"][i] for r in train];b=[r["x"][j] for r in train]
    ma,mb=fmean(a),fmean(b)
    da=sum((v-ma)**2 for v in a);db=sum((v-mb)**2 for v in b)
    return None if min(da,db)<=1e-12 else sum((u-ma)*(v-mb) for u,v in zip(a,b))/math.sqrt(da*db)

def evaluate(rows,missing):
    out={"aligned_months":len(rows),"missing_feature_months":missing,"folds":[],
         "status":"insufficient_exploratory_samples","formal_oos_validated":False}
    if missing or (rows and [r["month"] for r in rows]!=months(rows[0]["month"],rows[-1]["month"])):
        out["status"]="calendar_or_source_gap"
        return out
    models={"rates_only":(0,),"three_source":(0,1,2),"without_rates":(1,2),
            "without_usd":(0,2),"without_nfci":(0,1)}
    all_errors={k:[] for k in ("training_mean",*models)}
    hits={k:0 for k in all_errors}
    last_test=""
    for b in range(MIN_TRAIN+EMBARGO,len(rows)-TEST+1,TEST):
        train=rows[:b-EMBARGO];test=rows[b:b+TEST]
        if test[0]["month"]<=last_test:raise ValueError("Overlapping evaluation window")
        last_test=test[-1]["month"]
        try:
            predictors={k:fit(train,v) for k,v in models.items()}
        except ValueError:
            out["status"]="constant_training_predictor"
            return out
        ym=fmean(r["y"] for r in train)
        predictions={"training_mean":[ym]*len(test),**{k:[f(r) for r in test] for k,f in predictors.items()}}
        actual=[r["y"] for r in test]
        fold={"train_count":len(train),"train_last":train[-1]["month"],
              "test_first":test[0]["month"],"test_last":test[-1]["month"],"test_count":len(test),
              "training_only_correlation":{f"{FEATURES[i]}__{FEATURES[j]}":correlation(train,i,j)
                                           for i in range(3) for j in range(i+1,3)},
              "mae_pct":{}}
        for k,forecast in predictions.items():
            errors=[abs(a-b) for a,b in zip(actual,forecast)]
            all_errors[k].extend(errors)
            hits[k]+=sum((a>0 and b>0) or (a<0 and b<0) for a,b in zip(actual,forecast))
            fold["mae_pct"][k]=round(fmean(errors),6)
        out["folds"].append(fold)
    if not out["folds"]:return out
    maes={k:round(fmean(v),6) for k,v in all_errors.items()}
    out.update(status="exploratory_repeated_history_not_pit",
               evaluated_months=len(all_errors["three_source"]),mae_pct=maes,direction_hits=hits,
               incremental_mae_delta_pct={k:round(maes[k]-maes["three_source"],6)
                                          for k in ("without_rates","without_usd","without_nfci")},
               independent_factor_certified=False)
    return out

def build(panel,history,usd,nfci):
    if panel.get("report_type")!="asset_compass_v66_v68_monthly_fund_research_panel" or panel.get("eligible_for_live_scoring") is not False:
        raise ValueError("Unapproved panel")
    validate(history)
    assets={}
    for k,f in panel["funds"].items():
        rows,missing=align(f,history["observations"],usd,nfci)
        assets[k]=evaluate(rows,missing)
    return {"report_type":"asset_compass_v74_v78_exploratory_multisource_diagnostic",
            "generated_at":datetime.now(timezone.utc).isoformat(),
            "observations":{"treasury":len(history["observations"]),"h10":len(usd),"nfci":len(nfci)},
            "features":list(FEATURES),"min_train":MIN_TRAIN,"test_months":TEST,
            "training_label_embargo_months":EMBARGO,"fixed_ridge_penalty":RIDGE,"assets":assets,
            "historical_pit_certified":False,"investor_costs_reconciled":False,
            "independent_factor_groups_certified":0,"formal_oos_validated_assets":0,
            "official_scores_published":0,"eligible_for_live_scoring":False,
            "limitations":["Previously examined historical samples; not fresh independent holdout.",
                           "Latest-revised data, no historical release or revision certification.",
                           "Embargo is conservative research design, not proof of release availability.",
                           "H10 is nominal FX index, not investable USD return; NFCI is overlapping composite.",
                           "Ablation is descriptive, not causal or statistical independence certification."]}

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--panel",type=Path,required=True)
    p.add_argument("--additional-fund-panel",type=Path)
    p.add_argument("--output",type=Path,required=True)
    p.add_argument("--six-feature-output",type=Path)
    p.add_argument("--partial-vintage-output",type=Path)
    p.add_argument("--full-vintage-output",type=Path)
    a=p.parse_args()
    outputs=[x.resolve() for x in (a.output,a.six_feature_output,a.partial_vintage_output,a.full_vintage_output) if x is not None]
    if len(set(outputs))!=len(outputs) or any(x.is_relative_to(ROOT) for x in outputs):p.error("Distinct research outputs outside website repository only")
    if a.partial_vintage_output and not a.six_feature_output:p.error("Partial vintage research requires six-feature research")
    if a.full_vintage_output and not a.partial_vintage_output:p.error("Full vintage research requires partial comparison")
    usd_raw=retrieve_fed_xml()
    usd=parse_fed_xml(usd_raw)
    # Reuse V56 publisher-approved CSV parser and URL. No fabricated fallback.
    nfci_raw=fetch_official(FRED_URL,"fred.stlouisfed.org")
    nfci=parse_nfci(nfci_raw)
    history=json.loads((ROOT/"data/asset-compass-treasury-history.json").read_text())
    panel=json.loads(a.panel.read_text())
    if a.additional_fund_panel:
        extra=json.loads(a.additional_fund_panel.read_text())
        if extra.get("report_type")!="asset_compass_v84_v89_sec_performance_research" or extra.get("eligible_for_live_scoring") is not False:
            raise ValueError("Invalid added fund evidence")
        for ticker,fund in extra["funds"].items():
            if ticker not in ("UUP","USO") or ticker in panel["funds"] or fund.get("frequency")!="monthly" or fund.get("investable_total_return_certified") is not False:
                raise ValueError("Unexpected added fund or mixed frequency")
            # Treasury begins in January 2021. The first three return months
            # lack the required t-3 predictor; explicitly restrict diagnostic window.
            panel["funds"][ticker]={**fund,"monthly_observations":[r for r in fund["monthly_observations"] if r["month"]>="2021-04"]}
    r=build(panel,history,usd,nfci)
    r["source_receipts"]={"h10":{"url":FED_XML_URL,"sha256":hashlib.sha256(usd_raw).hexdigest()},
                          "nfci":{"url":FRED_URL,"sha256":hashlib.sha256(nfci_raw).hexdigest()}}
    a.output.write_text(json.dumps(r,indent=2,allow_nan=False)+"\n")
    print(json.dumps({"observations":r["observations"],"assets":r["assets"],"eligible_for_live_scoring":False}))

    if a.six_feature_output:
        if a.six_feature_output.resolve().is_relative_to(ROOT) or a.six_feature_output.resolve()==a.output.resolve():
            p.error("Distinct private output required")
        from scripts.asset_compass_six_feature_v90 import get_sources, build as build_six
        extra_macro,receipts=get_sources()
        six=build_six(panel,history,usd,nfci,extra_macro,receipts)
        a.six_feature_output.write_text(json.dumps(six,indent=2,allow_nan=False)+"\n")
        print(json.dumps({"six_feature_sources":receipts,"assets":six["assets"],"eligible_for_live_scoring":False}))
        if a.partial_vintage_output:
            from scripts.asset_compass_partial_vintage_v146 import build as build_vintage
            full=None
            if a.full_vintage_output:
                from scripts.asset_compass_full_vintage_v153 import build_both
                v,full=build_both(panel,history,usd,nfci,extra_macro)
                a.full_vintage_output.write_text(json.dumps(full,indent=2,allow_nan=False)+"\n")
                print(json.dumps({k:full[k] for k in ("target_decision_dates","retrieved_decision_dates","source_failures","assets","eligible_for_live_scoring")}))
            else:
                v=build_vintage(panel,history,usd,nfci,extra_macro)
            a.partial_vintage_output.write_text(json.dumps(v,indent=2,allow_nan=False)+"\n")
            print(json.dumps({k:v[k] for k in ("target_decision_dates","retrieved_decision_dates","source_failures","assets","eligible_for_live_scoring")}))
            for evidence in (v,full):
                if evidence is not None and (evidence["source_failures"] or any(n!=evidence["target_decision_dates"] for n in evidence["retrieved_decision_dates"].values()) or any(not a["evaluated_months"] for a in evidence["assets"].values())):
                    raise SystemExit(1)

if __name__=="__main__":main()
