#!/usr/bin/env python3
"""V16 Treasury as-retrieved CSV comparisons, not official historical PIT releases.

Run after V15 has captured authentic Treasury raw CSVs in the *same* workflow.
The previous V16 state records observation value fingerprints for comparisons.
Comparing two retrievals proves an observed change between retrieval instants,
NOT its official revision time nor its historical availability.

Never invent records when a prior baseline is missing, never overwrite prior
events, and never certify live investment scores.
"""
import argparse
import hashlib
import json
import math
import os
from datetime import datetime, timezone
from pathlib import Path

from scripts.collect_treasury_source_evidence_v15 import parse_csv, ROOT

STATE = ROOT / "data" / "asset-compass-treasury-v16-state.json"
EVENTS = ROOT / "data" / "asset-compass-treasury-v16-events.jsonl"
SUMMARY = ROOT / "data" / "asset-compass-treasury-v16-report.json"
V15 = ROOT / "data" / "asset-compass-treasury-source-evidence-v15.json"
SERIES = {"treasury.us2y": ("nominal","2yr"),
          "treasury.us10y": ("nominal","10yr"),
          "treasury.real10y": ("real","10yr")}

def encode_value(value):
    if value is None:return "null"
    if type(value) not in (int,float) or not math.isfinite(value):
        raise ValueError("Nonfinite observation")
    return format(float(value), ".12g")

def value_digest(value):
    return hashlib.sha256(encode_value(value).encode("ascii")).hexdigest()

def iso_utc(stamp):
    dt=datetime.fromisoformat(stamp.replace("Z","+00:00"))
    if dt.tzinfo is None:raise ValueError("Timestamp must be offset-aware")
    return dt.astimezone(timezone.utc).isoformat()

def parse_raw(raw_dir,year,receipts):
    if {r["type"] for r in receipts}!={"nominal","real"} or len(receipts)!=2:
        raise ValueError("Missing or duplicated official Treasury curve receipt")
    curves={}
    for receipt in receipts:
        kind=receipt["type"]
        path=Path(raw_dir)/(str(year)+"-"+kind+".csv")
        body=path.read_bytes()
        if hashlib.sha256(body).hexdigest()!=receipt["sha256"]:
            raise ValueError("Official raw CSV differs from V15 SHA256 receipt: "+kind)
        curves[kind]=parse_csv(body,kind,year)
    fingerprints={}
    for sid,(kind,field) in SERIES.items():
        fingerprints[sid]={d:value_digest(row[field]) for d,row in curves[kind].items()
                           if row.get(field) is not None}
    return fingerprints

def compare(before,after):
    original=before or {}
    added=sorted(set(after)-set(original))
    removed=sorted(set(original)-set(after))
    changed=sorted(d for d in set(after)&set(original) if original[d]!=after[d])
    return {"new_observation_periods":len(added),
            "no_longer_in_response_periods":len(removed),
            "changed_value_periods":len(changed),
            "new_dates":added[:30],"no_longer_in_response_dates":removed[:30],
            "changed_dates":changed[:30],
            "dates_truncated":any(len(items)>30 for items in (added,removed,changed))}

def generate(v15,raw_dir,previous,*,run_id,checked_at):
    if v15.get("report_type")!="asset_compass_v15_treasury_raw_source_evidence" or v15.get("schema_version")!=1:
        raise ValueError("Unverified V15 capture report")
    if any(v15.get(k) is not False for k in
           ("original_publication_time_verified","original_release_vintages_verified",
            "eligible_for_point_in_time_backtest","validated_for_live_scoring")):
        raise ValueError("V15 safety gate is not closed")
    checked=iso_utc(checked_at)
    year=v15["year"]
    if type(year) is not int or not 2003<=year<=datetime.fromisoformat(checked).year:
        raise ValueError("Invalid Treasury evidence year")
    if iso_utc(v15["retrieved_at"])>checked:
        raise ValueError("V15 source retrieval is in future")
    receipts=v15.get("source_receipts")
    if not isinstance(receipts,list):raise ValueError("Missing receipt list")
    current=parse_raw(raw_dir,year,receipts)
    old=previous if isinstance(previous,dict) else None
    if old:
        if old.get("schema_version")!=1 or old.get("report_type")!="asset_compass_v16_treasury_value_fingerprints":
            raise ValueError("Prior state has unknown schema; refuse destructive reset")
        prior_time=iso_utc(old["checked_at"])
        if prior_time>checked:raise ValueError("Backdated retrieval attempt")
        if old.get("run_id")==str(run_id):
            raise ValueError("This GitHub run already recorded")
    comparable=bool(old and old["year"]==year)
    by_series={}
    for sid in SERIES:
        before=(old["fingerprints"].get(sid,{}) if comparable else None)
        by_series[sid]=compare(before,current[sid]) if comparable else {
            "new_observation_periods":0,"no_longer_in_response_periods":0,
            "changed_value_periods":0,"new_dates":[],"no_longer_in_response_dates":[],
            "changed_dates":[],"dates_truncated":False}
        by_series[sid]["current_observation_periods"]=len(current[sid])
    current_sha={r["type"]:r["sha256"] for r in receipts}
    prior_sha=(old.get("source_sha256",{}) if comparable else {})
    raw_changed={kind:(None if not comparable else prior_sha.get(kind)!=sha)
                 for kind,sha in current_sha.items()}
    changes=sum(x["changed_value_periods"] for x in by_series.values())
    result={
      "schema_version":1,"report_type":"asset_compass_v16_retrieval_comparison",
      "checked_at":checked,"run_id":str(run_id),"year":year,
      "baseline_state":"same_year" if comparable else ("new_year" if old else "first_capture"),
      "previous_run_id":old.get("run_id") if old else None,
      "source_sha256":current_sha,
      "raw_file_changed_since_last_comparable_capture":raw_changed,
      "by_series":by_series,
      "total_observed_value_changes":changes,
      "historical_official_revisions_verified":False,
      "historical_original_publication_timestamp_verified":False,
      "previously_available_vintages_verified":False,
      "eligible_for_point_in_time_backtest":False,
      "validated_for_live_scoring":False,
      "interpretation":"Value hash changes show differences across Ooglex retrieval instants; not the official revision release time, original vintage, or cause.",
    }
    state={
      "schema_version":1,"report_type":"asset_compass_v16_treasury_value_fingerprints",
      "year":year,"checked_at":checked,"run_id":str(run_id),
      "source_sha256":current_sha,"fingerprints":current,
      "eligible_for_point_in_time_backtest":False,
      "validated_for_live_scoring":False,
    }
    return state,result

def persist(state,report,*,state_path=STATE,events_path=EVENTS,report_path=SUMMARY):
    state_path=Path(state_path);events_path=Path(events_path);report_path=Path(report_path)
    for item in (state_path,events_path,report_path):item.parent.mkdir(parents=True,exist_ok=True)
    event={k:report[k] for k in
        ("checked_at","run_id","year","baseline_state","previous_run_id",
         "source_sha256","raw_file_changed_since_last_comparable_capture",
         "by_series","total_observed_value_changes",
         "eligible_for_point_in_time_backtest","validated_for_live_scoring")}
    if events_path.exists():
        lines=[s for s in events_path.read_text(encoding="utf-8").splitlines() if s.strip()]
        if lines:
            last=json.loads(lines[-1])
            if iso_utc(last["checked_at"])>iso_utc(event["checked_at"]):
                raise ValueError("Event history cannot be backdated")
            if last.get("run_id")==event["run_id"]:
                raise ValueError("Duplicate run event")
    with events_path.open("a",encoding="utf-8") as f:
        f.write(json.dumps(event,ensure_ascii=False,separators=(",",":"))+"\n")
    state_path.write_text(json.dumps(state,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    report_path.write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--v15",type=Path,default=V15)
    p.add_argument("--raw-dir",type=Path,required=True)
    p.add_argument("--state",type=Path,default=STATE)
    p.add_argument("--events",type=Path,default=EVENTS)
    p.add_argument("--report",type=Path,default=SUMMARY)
    p.add_argument("--run-id",default=os.environ.get("GITHUB_RUN_ID"))
    args=p.parse_args()
    if not args.run_id:raise ValueError("GitHub run id required")
    v15=json.loads(args.v15.read_text(encoding="utf-8"))
    previous=json.loads(args.state.read_text(encoding="utf-8")) if args.state.is_file() else None
    state,report=generate(v15,args.raw_dir,previous,run_id=args.run_id,
                          checked_at=datetime.now(timezone.utc).isoformat())
    persist(state,report,state_path=args.state,events_path=args.events,report_path=args.report)
    print(json.dumps({"state":report["baseline_state"],"changes":report["total_observed_value_changes"],
                      "pit_qualified":False,"series":len(report["by_series"])},ensure_ascii=False))
if __name__=="__main__":main()
