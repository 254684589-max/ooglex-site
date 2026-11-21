#!/usr/bin/env python3
"""Ooglex deterministic factor scoring engine.

Conservative publication policy: scores only after independent factor coverage,
out-of-sample validation and approved model calibration. No fabricated signals.
"""
import json
import math
from datetime import datetime, timezone
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
CONFIG=ROOT/"macro"/"model-config.json"
DATA=ROOT/"data"/"asset-scores.json"

def finite_signal(value):
    # bool is a subclass of int, but never an acceptable input.
    return type(value) in (int,float) and math.isfinite(value) and -1<=value<=1

def validate_config(config):
    keys=config["factor_order"]
    if len(keys)!=6 or len(set(keys))!=6:raise ValueError("Expected 6 distinct factor groups")
    for asset,weights in config["weights"].items():
        if len(weights)!=len(keys) or any(type(v) not in (int,float) or v<0 for v in weights):
            raise ValueError("Invalid weights: "+asset)
        if abs(sum(weights)-100)>1e-8:raise ValueError("Weights must total 100%: "+asset)
    gates=config["guardrails"]
    if not (1<=gates["minimum_factor_groups"]<=len(keys)):raise ValueError("Invalid group gate")
    if not (0<gates["minimum_weight_coverage_percent"]<=100):raise ValueError("Invalid coverage gate")
    return config

def score_one(asset,signals,config,validation=None):
    """signals is a mapping of asset-specific independent group signals [-1,1].

    No renormalization: the original weights are preserved; missing factors
    cannot silently become neutral or increase other factor weights.
    """
    validate_config(config)
    if asset not in config["weights"]:raise ValueError("Unknown asset")
    validation=validation or {}
    weights=dict(zip(config["factor_order"],config["weights"][asset]))
    accepted={}
    for name in weights:
        entry=signals.get(name)
        if not isinstance(entry,dict):continue
        # An individual signal may be stale or unverified.
        if entry.get("verified") is not True or entry.get("fresh") is not True:continue
        if not finite_signal(entry.get("signal")):continue
        if not isinstance(entry.get("observation_date"),str) or not entry["observation_date"]:continue
        accepted[name]=entry["signal"]
    coverage=sum(weights[name] for name in accepted)
    guard=config["guardrails"]
    reasons=[]
    if len(accepted)<guard["minimum_factor_groups"]:reasons.append("insufficient_factor_groups")
    if coverage<guard["minimum_weight_coverage_percent"]:reasons.append("insufficient_weight_coverage")
    if guard["require_historical_calibration"] and validation.get("historical_calibration_passed") is not True:
        reasons.append("historical_calibration_not_passed")
    if guard["require_out_of_sample_validation"] and validation.get("out_of_sample_passed") is not True:
        reasons.append("out_of_sample_validation_not_passed")
    if reasons:
        return {"score":None,"label":None,"status":"unavailable","coverage_pct":round(coverage,2),
                "covered_factors":sorted(accepted),"blocked_by":reasons}
    raw=50+0.5*sum(weights[name]*accepted[name] for name in weights)
    score=round(min(100,max(0,raw)),2)
    tiers=config["tiers"]
    label=next((t["label"] for t in tiers if t["range"][0]<=score<=t["range"][1]),None)
    # Boundary between inclusive integer tiers can be fractional: use floor for 0..100 bins.
    if label is None:
        import math
        b=math.floor(score)
        label=next((t["label"] for t in tiers if t["range"][0]<=b<=t["range"][1]),None)
    if label is None:raise ValueError("Tier configuration does not cover score")
    return {"score":score,"label":label,"status":"calibrated","coverage_pct":round(coverage,2),
            "covered_factors":sorted(accepted),"blocked_by":[],
            "contributions":{name:round(weights[name]*accepted[name]*0.5,3) for name in accepted}}

def produce(data,config,signals_by_asset=None,validation=None):
    """Stage-3 wiring intentionally supplies no inferred signals from spot levels.
    A future separately verified factor pipeline may supply explicit signals.
    """
    signals_by_asset=signals_by_asset or {}
    scored={asset:score_one(asset,signals_by_asset.get(asset,{}),config,validation)
            for asset in config["weights"]}
    data["assets"]=scored
    data["scoring"]={"model":config["model"],"generated_at":datetime.now(timezone.utc).isoformat(),
                     "calibration_verified":bool(validation and validation.get("historical_calibration_passed") is True),
                     "out_of_sample_verified":bool(validation and validation.get("out_of_sample_passed") is True)}
    data["status"]="scored" if all(x["score"] is not None for x in scored.values()) else "partial_data_no_full_score"
    return data

def main():
    config=validate_config(json.loads(CONFIG.read_text(encoding="utf-8")))
    data=json.loads(DATA.read_text(encoding="utf-8"))
    if data.get("schema_version")!=1:raise ValueError("Snapshot schema mismatch")
    # Neither a CI flag nor a synthetic test fixture may self-certify validation.
    # Real factor history & independent validation are not yet implemented.
    result=produce(data,config)
    DATA.write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print("Scoring gate evaluated:",{a:s["blocked_by"] for a,s in result["assets"].items()})
if __name__=="__main__":main()
