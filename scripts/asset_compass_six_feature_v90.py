"""V90-V96: six-feature research, same-window comparisons, not PIT or live scoring."""
import csv
import hashlib
import io
import math
import time
from datetime import date,datetime,timezone
from statistics import fmean
from scripts.asset_compass_multisource_v74 import fit,correlation,align,month_end,MIN_TRAIN,TEST,EMBARGO,FEATURES,RIDGE
from scripts.asset_compass_monthly_diagnostic_v69 import prev
from scripts.asset_compass_sec_returns_v66 import months
from scripts.build_asset_compass_new_sources_v56 import fetch_official

SERIES={"CPIAUCNS":("monthly",1,1000),"UNRATE":("monthly",0,100),"WALCL":("weekly",1,100000000)}
NAMES=(*FEATURES,"cpi_yoy_pct","unemployment_pct","fed_assets_change_pct")
URL="https://fred.stlouisfed.org/graph/fredgraph.csv?id={}&cosd=2020-01-01"

def parse_series(raw,sid):
    freq,lo,hi=SERIES[sid]
    reader=csv.DictReader(io.StringIO(raw.decode("utf-8-sig")))
    if reader.fieldnames not in (["DATE",sid],["observation_date",sid]):
        raise ValueError("Wrong series header: "+sid)
    rows=[];last=""
    for row in reader:
        day=date.fromisoformat(row[reader.fieldnames[0]])
        stamp=day.isoformat()
        if stamp<=last or day>datetime.now(timezone.utc).date():
            raise ValueError("Duplicate or future observation")
        last=stamp
        if (freq=="monthly" and day.day!=1) or (freq=="weekly" and day.weekday()!=2):
            raise ValueError("Wrong observation frequency")
        raw_value=row[sid]
        if raw_value is None:raise ValueError("Truncated source record")
        if raw_value.strip() in ("","."):continue
        val=float(raw_value)
        if not math.isfinite(val) or not lo<=val<=hi:raise ValueError("Invalid source value")
        rows.append({"date":stamp,"value":val})
    if len(rows)<36:raise ValueError("Insufficient history")
    return rows

def get_sources():
    data={};receipts={}
    for sid in SERIES:
        url=URL.format(sid)
        raw=fetch_official(url,"fred.stlouisfed.org")
        data[sid]=parse_series(raw,sid)
        receipts[sid]={"url":url,"sha256":hashlib.sha256(raw).hexdigest(),"observations":len(data[sid]),"first":data[sid][0]["date"],"last":data[sid][-1]["date"]}
        time.sleep(1)
    return data,receipts

def extend(base,data):
    cpi={r["date"][:7]:r["value"] for r in data["CPIAUCNS"]}
    un={r["date"][:7]:r["value"] for r in data["UNRATE"]}
    fed=month_end(data["WALCL"],"value")
    out=[];missing=[]
    for row in base:
        m=row["month"];p,q=prev(m,3),prev(m,2);year=prev(q,12)
        if not(q in cpi and year in cpi and q in un and p in fed and q in fed):
            missing.append(m);continue
        x=[*row["x"],100*(cpi[q]/cpi[year]-1),un[q],100*(fed[q]["value"]/fed[p]["value"]-1)]
        if not all(math.isfinite(v) for v in x):raise ValueError("Nonfinite feature")
        out.append({**row,"x":x})
    return out,missing

def stability(folds):
    # Standardized coefficients: return percentage points per one training SD.
    # These are not allocated model weights or independent statistical evidence.
    out={}
    for name in NAMES:
        vals=[f["six_source_training_coefficients"][name] for f in folds]
        pos=sum(v>1e-10 for v in vals);neg=sum(v < -1e-10 for v in vals)
        out[name]={"fold_count":len(vals),"positive_folds":pos,"negative_folds":neg,
                   "near_zero_folds":len(vals)-pos-neg,"sign_changed":bool(pos and neg),
                   "minimum":round(min(vals),6),"maximum":round(max(vals),6),
                   "mean":round(fmean(vals),6),"certified_model_weight":False}
    return out

def evaluate(rows):
    if not rows:return {"status":"no_common_observations","folds":[]}
    by={r["month"]:r for r in rows}
    if len(by)!=len(rows):raise ValueError("Duplicate month")
    cal=months(min(by),max(by))
    variants={"three_source":(0,1,2),"six_source":tuple(range(6))}
    variants.update({"without_"+name:tuple(j for j in range(6) if j!=i) for i,name in enumerate(NAMES)})
    errors={k:[] for k in ("training_mean",*variants)}
    hits={k:0 for k in errors};folds=[]
    for start in range(MIN_TRAIN+EMBARGO,len(cal)-TEST+1,TEST):
        train=[by[m] for m in cal[:start-EMBARGO] if m in by]
        test=[by[m] for m in cal[start:start+TEST] if m in by]
        if len(train)<MIN_TRAIN or len(test)!=TEST:continue
        try:models={k:fit(train,ids) for k,ids in variants.items()}
        except ValueError:continue
        avg=fmean(r["y"] for r in train)
        preds={"training_mean":[avg]*len(test),**{k:[f(r) for r in test] for k,f in models.items()}}
        actual=[r["y"] for r in test]
        fold={"train_count":len(train),"train_last":train[-1]["month"],"test_first":test[0]["month"],"test_last":test[-1]["month"],"test_count":len(test),"mae_pct":{},
              "training_correlations":{NAMES[i]+"__"+NAMES[j]:correlation(train,i,j) for i in range(6) for j in range(i+1,6)}}
        fold["six_source_training_coefficients"]=dict(zip(NAMES,models["six_source"].standardized_coefficients))
        for k,vals in preds.items():
            e=[abs(a-b) for a,b in zip(vals,actual)]
            errors[k].extend(e)
            hits[k]+=sum((a>0 and b>0) or (a<0 and b<0) for a,b in zip(vals,actual))
            fold["mae_pct"][k]=round(fmean(e),6)
        folds.append(fold)
    result={"status":"exploratory_reused_history_not_pit" if folds else "insufficient_complete_folds","aligned_months":len(rows),"calendar_months":len(cal),"folds":folds,"evaluated_months":len(errors["six_source"]),"formal_oos_validated":False}
    if folds:
        mae={k:round(fmean(v),6) for k,v in errors.items()}
        result.update(mae_pct=mae,direction_hits=hits,incremental_mae_delta_pct={k:round(v-mae["six_source"],6) for k,v in mae.items() if k.startswith("without_")},training_coefficient_stability=stability(folds),six_source_improves_mean_baseline=mae["six_source"]<mae["training_mean"],six_source_improves_three_source=mae["six_source"]<mae["three_source"])
    return result

def build(panel,history,usd,nfci,data,receipts):
    assets={}
    for ticker,fund in panel["funds"].items():
        base,missing=align(fund,history["observations"],usd,nfci)
        ext,gaps=extend(base,data)
        assets[ticker]={**evaluate(ext),"missing_base_months":missing,"missing_extended_months":gaps}
    return {"report_type":"asset_compass_v90_v96_six_feature_research","generated_at":datetime.now(timezone.utc).isoformat(),"features":list(NAMES),"sources":receipts,
            "min_train":MIN_TRAIN,"test_months":TEST,"embargo_months":EMBARGO,"fixed_ridge_penalty":RIDGE,"assets":assets,
            "historical_pit_certified":False,"independent_factor_groups_certified":0,"formal_oos_validated_assets":0,"official_scores_published":0,"eligible_for_live_scoring":False,
            "limitations":["Six features are not six independent groups.","Latest revised FRED history, not PIT; reused research history.","WALCL changes are not net liquidity.","No investor execution cost or strategy return certification."]}
