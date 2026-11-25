"""V153–V160: all six predictors from decision-date ALFRED snapshots.

Same-window comparison only. Historical date-level snapshots are not exact
publication timestamps, independently certified PIT, or investable returns.
"""
from calendar import monthrange
from datetime import date,datetime,timezone
from decimal import Decimal
from statistics import fmean
import math

from scripts.asset_compass_monthly_diagnostic_v69 import prev
from scripts.asset_compass_multisource_v74 import align
from scripts.asset_compass_six_feature_v90 import extend,evaluate,NAMES
from scripts.asset_compass_partial_vintage_v146 import cutoff,collect,build as build_partial

SERIES=("CPIAUCNS","UNRATE","DGS10","DTWEXBGS","NFCI","WALCL")
UNITS=("basis_points","percentage_points","index_points","percentage_points","percentage_points","percentage_points")

def last_in_month(values,month,decision):
    matches=[]
    for k,v in values.items():
        d=date.fromisoformat(k)
        if d>date.fromisoformat(decision):raise ValueError("Future snapshot observation")
        if k[:7]!=month:continue
        if monthrange(d.year,d.month)[1]-d.day<=7:
            matches.append((k,v))
    if not matches:return None
    return max(matches,key=lambda t:t[0])

def triple_rows(current,snapshots):
    a=[];b=[];c=[];gaps=[];diffs=[];seen=set()
    for r in sorted(current,key=lambda x:x["month"]):
        m=r["month"]
        if m in seen or len(r["x"])!=6:raise ValueError("Invalid current model row")
        seen.add(m)
        day=cutoff(m);p,q=prev(m,3),prev(m,2);year=prev(q,12)
        cp=snapshots["CPIAUCNS"].get(day,{});un=snapshots["UNRATE"].get(day,{})
        missing=[]
        if q not in cp or year not in cp:missing.append("CPIAUCNS")
        if q not in un:missing.append("UNRATE")
        if missing:
            gaps.append({"month":m,"missing_series":missing});continue
        if cp[year]<=0 or cp[q]<=0:raise ValueError("Invalid CPI")
        vals={}
        for sid in ("DGS10","DTWEXBGS","NFCI","WALCL"):
            obs=snapshots[sid].get(day,{})
            need=(q,) if sid=="NFCI" else (p,q)
            found={k:last_in_month(obs,k,day) for k in need}
            if any(v is None for v in found.values()):
                missing.append(sid)
            else:
                vals[sid]={k:v[1] for k,v in found.items()}
        if missing:
            gaps.append({"month":m,"missing_series":missing});continue
        t,u,n,w=(vals[k] for k in ("DGS10","DTWEXBGS","NFCI","WALCL"))
        if min(u[p],u[q],w[p],w[q])<=0:raise ValueError("Nonpositive index or assets")
        partial=list(r["x"])
        partial[3]=float((cp[q]/cp[year]-1)*100);partial[4]=float(un[q])
        full=[float(100*(t[q]-t[p])),float(100*(u[q]/u[p]-1)),float(n[q]),
              partial[3],partial[4],float(100*(w[q]/w[p]-1))]
        if not all(math.isfinite(v) for v in full):raise ValueError("Nonfinite vintage predictor")
        a.append(r);b.append({**r,"x":partial});c.append({**r,"x":full})
        diffs.append([abs(v-x) for v,x in zip(full,r["x"])])
    return a,b,c,gaps,diffs

def compare(current,snapshots):
    a,b,c,gaps,diffs=triple_rows(current,snapshots)
    models={name:evaluate(rows) for name,rows in (("current",a),("two_vintage",b),("six_vintage",c))}
    def boundaries(r):
        return [(f["train_count"],f["train_last"],f["test_first"],f["test_last"],f["test_count"]) for f in r["folds"]]
    foldsets=[boundaries(r) for r in models.values()]
    same=all(x==foldsets[0] for x in foldsets)
    result={"status":"insufficient_matched_test_windows","current_candidate_months":len(current),
            "matched_months":len(a),"excluded_missing_vintage_months":gaps,
            "same_fold_boundaries":same,"evaluated_months":0,"formal_oos_validated":False,
            "eligible_for_live_scoring":False}
    if diffs:
        result["source_and_revision_sensitivity"]={name:{"unit":UNITS[i],
            "months_different_gt_0_000001":sum(d[i]>1e-6 for d in diffs),
            "mean_absolute_difference":round(fmean(d[i] for d in diffs),8),
            "maximum_absolute_difference":round(max(d[i] for d in diffs),8)}
            for i,name in enumerate(NAMES)}
    if not same:
        result["status"]="different_valid_folds_no_comparison";return result
    if not foldsets[0]:return result
    baselines={r["mae_pct"]["training_mean"] for r in models.values()}
    counts={r["evaluated_months"] for r in models.values()}
    if len(baselines)!=1 or len(counts)!=1:raise ValueError("Matched benchmark mismatch")
    result.update(status="six_date_level_vintage_exploratory_reused_history",
        evaluated_months=counts.pop(),training_mean_mae_pct=baselines.pop(),
        folds=[{"train_count":t[0],"train_last":t[1],"test_first":t[2],"test_last":t[3],"test_count":t[4]} for t in foldsets[0]],
        mae_pct={k:r["mae_pct"]["six_source"] for k,r in models.items()},
        direction_hits={k:r["direction_hits"]["six_source"] for k,r in models.items()},
        six_vintage_training_coefficient_stability=models["six_vintage"]["training_coefficient_stability"],
        six_vintage_incremental_mae_delta_pct=models["six_vintage"]["incremental_mae_delta_pct"])
    return result

def build_both(panel,history,usd,nfci,data):
    current={};base_gaps={}
    for k,fund in panel["funds"].items():
        base,gaps=align(fund,history["observations"],usd,nfci)
        current[k],more=extend(base,data)
        base_gaps[k]=sorted(set(gaps+more))
    target=sorted({r["month"] for rows in current.values() for r in rows})
    if not target:raise ValueError("No current research rows")
    # Download each series/date batch once. Reuse first two series for V146.
    snapshots,receipts,fail=collect(target,series=SERIES)
    subset=SERIES[:2]
    partial=build_partial(panel,history,usd,nfci,data,snapshot_bundle=(
        {k:snapshots[k] for k in subset},[r for r in receipts if r["series"] in subset],
        {k:v for k,v in fail.items() if k.split(":")[0] in subset}))
    assets={k:{**compare(rows,snapshots),"excluded_current_source_months":base_gaps[k]} for k,rows in current.items()}
    full={"report_type":"asset_compass_v153_six_date_level_vintage_research",
        "generated_at":datetime.now(timezone.utc).isoformat(),
        "features":list(NAMES),"series":list(SERIES),
        "target_decision_dates":len(target),"retrieved_decision_dates":{s:len(v) for s,v in snapshots.items()},
        "source_receipts":receipts,"source_failures":fail,"assets":assets,
        "date_level_vintage_features":6,"historical_pit_certified_series":0,
        "independent_factor_groups_certified":0,"formal_oos_validated_assets":0,
        "official_scores_published":0,"eligible_for_live_scoring":False,
        "limitations":["All six predictor concepts queried as of the calendar day before target month.",
            "DGS10 and DTWEXBGS substitute FRED-hosted H.15/H.10 series for existing Treasury and H.10 feeds; differences may reflect source definitions, rounding or timing, not only revisions.",
            "Monthly observation t-2 and t-3, no carry-forward outside month-end seven-day window.",
            "Date-level vintage does not prove exact original publication or complete historical revision chain.",
            "Return labels remain issuer-reported research; reused test history is not independent OOS. No scores."]}
    return partial,full
