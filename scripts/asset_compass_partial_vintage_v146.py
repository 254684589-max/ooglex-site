"""V146–V152: matched-sample sensitivity to date-level macro revisions.

Only CPI and UNRATE use ALFRED decision-date snapshots. The four other
features and return labels remain current/reported history, not certified PIT.
"""
import hashlib
import math
import time
import urllib.error
from datetime import date,datetime,timedelta,timezone
from decimal import Decimal
from statistics import fmean
from scripts.asset_compass_alfred_v138 import BATCH,url_for,fetch,parse
from scripts.asset_compass_monthly_diagnostic_v69 import prev
from scripts.asset_compass_multisource_v74 import align
from scripts.asset_compass_six_feature_v90 import extend,evaluate,NAMES

SERIES=("CPIAUCNS","UNRATE")

def cutoff(month):
    # End of prior calendar day, before target month begins.
    d=date.fromisoformat(month+"-01")-timedelta(days=1)
    if d>=datetime.now(timezone.utc).date():raise ValueError("Future decision date")
    return d.isoformat()

def collect(months,fetcher=fetch,wait=time.sleep):
    dates=sorted({cutoff(m) for m in months})
    snapshots={s:{} for s in SERIES};receipts=[];fail={};stop=False
    for sid in SERIES:
        if stop:break
        for i in range(0,len(dates),BATCH):
            batch=dates[i:i+BATCH]
            url=url_for(sid,batch,start="2020-01-01")
            try:
                wait(2)
                raw=fetcher(url);digest=hashlib.sha256(raw).hexdigest()
                parsed=parse(raw,sid,batch)
                if set(parsed)!=set(batch) or set(parsed)&set(snapshots[sid]):
                    raise ValueError("Wrong or duplicate decision snapshot")
                snapshots[sid].update(parsed)
                receipts.append({"series":sid,"url":url,"sha256":digest,
                    "requested_dates":batch,"nonmissing_level_cells":sum(len(v) for v in parsed.values())})
            except (OSError,ValueError,ArithmeticError) as exc:
                fail[sid+":"+batch[0]]={"type":type(exc).__name__,"detail":str(exc)[:180]}
                if isinstance(exc,urllib.error.HTTPError) and exc.code in (403,429):
                    stop=True;break
    return snapshots,receipts,fail

def pair_rows(current,snapshots):
    current_matched=[];vintage_matched=[];gaps=[];diffs=[]
    seen=set()
    for row in sorted(current,key=lambda r:r["month"]):
        month=row["month"]
        if month in seen or len(row["x"])!=6:raise ValueError("Invalid matched research row")
        seen.add(month)
        day=cutoff(month);q=prev(month,2);yr=prev(q,12)
        c=snapshots["CPIAUCNS"].get(day,{});u=snapshots["UNRATE"].get(day,{})
        if q not in c or yr not in c or q not in u:
            gaps.append(month);continue
        if c[yr]<=0 or c[q]<=0:raise ValueError("Invalid vintage CPI level")
        x=list(row["x"])
        x[3]=float((c[q]/c[yr]-1)*100)
        x[4]=float(u[q])
        if not all(math.isfinite(v) for v in x):raise ValueError("Nonfinite vintage features")
        current_matched.append(row)
        vintage_matched.append({**row,"x":x})
        diffs.append((abs(x[3]-row["x"][3]),abs(x[4]-row["x"][4])))
    return current_matched,vintage_matched,gaps,diffs

def compare(current,snapshots):
    a,b,gaps,diffs=pair_rows(current,snapshots)
    r=evaluate(a);v=evaluate(b)
    def boundaries(report):
        return [(f["train_count"],f["train_last"],f["test_first"],f["test_last"],f["test_count"]) for f in report["folds"]]
    result={"matched_months":len(a),"excluded_missing_vintage_months":gaps,
        "current_candidate_months":len(current),"current_and_vintage_same_folds":boundaries(r)==boundaries(v),
        "evaluated_months":0,"formal_oos_validated":False,"eligible_for_live_scoring":False}
    if diffs:
        result["revision_sensitivity"]={name:{"months_different_gt_0_000001_pp":sum(d[i]>1e-6 for d in diffs),
            "mean_absolute_difference_pct":round(fmean(d[i] for d in diffs),8),
            "maximum_absolute_difference_pct":round(max(d[i] for d in diffs),8)}
            for i,name in enumerate(("cpi_yoy_pct","unemployment_pct"))}
    if not result["current_and_vintage_same_folds"]:
        result["status"]="different_valid_folds_no_comparison"
        return result
    if not r.get("evaluated_months"):
        result["status"]="insufficient_matched_test_windows"
        return result
    if r["evaluated_months"]!=v["evaluated_months"] or r["mae_pct"]["training_mean"]!=v["mae_pct"]["training_mean"]:
        raise ValueError("Matched comparison invariant failed")
    result.update(status="partial_vintage_exploratory_reused_history",
        evaluated_months=r["evaluated_months"],folds=[{"train_count":t[0],"train_last":t[1],"test_first":t[2],"test_last":t[3],"test_count":t[4]} for t in boundaries(r)],
        training_mean_mae_pct=r["mae_pct"]["training_mean"],
        current_six_feature_mae_pct=r["mae_pct"]["six_source"],
        partial_vintage_six_feature_mae_pct=v["mae_pct"]["six_source"],
        vintage_minus_current_mae_pct=round(v["mae_pct"]["six_source"]-r["mae_pct"]["six_source"],6),
        current_direction_hits=r["direction_hits"]["six_source"],partial_vintage_direction_hits=v["direction_hits"]["six_source"])
    return result

def build(panel,history,usd,nfci,data):
    current={};base_gaps={}
    for ticker,fund in panel["funds"].items():
        base,gaps=align(fund,history["observations"],usd,nfci)
        current[ticker],more=extend(base,data)
        base_gaps[ticker]=sorted(set(gaps+more))
    target=sorted({r["month"] for rows in current.values() for r in rows})
    if not target:raise ValueError("No matched current history")
    snapshots,receipts,fail=collect(target)
    assets={k:{**compare(rows,snapshots),"excluded_current_source_months":base_gaps[k]} for k,rows in current.items()}
    return {"report_type":"asset_compass_v146_partial_vintage_sensitivity",
        "generated_at":datetime.now(timezone.utc).isoformat(),"features":list(NAMES),
        "date_level_vintage_features":["cpi_yoy_pct","unemployment_pct"],
        "decision_date_rule":"calendar day before target month begins; observation month t-2",
        "target_decision_dates":len(target),"retrieved_decision_dates":{s:len(v) for s,v in snapshots.items()},
        "source_receipts":receipts,"source_failures":fail,"assets":assets,
        "historical_pit_certified_series":0,"independent_factor_groups_certified":0,
        "formal_oos_validated_assets":0,"official_scores_published":0,"eligible_for_live_scoring":False,
        "limitations":["Only two of six features use date-level ALFRED snapshots.",
            "Other four features use latest historical observations; original publication clocks unverified.",
            "Previously examined history, not fresh holdout. Three-month label embargo is not exact label availability evidence.",
            "Missing vintages excluded from both models; no interpolation, no investor cost certification."]}
