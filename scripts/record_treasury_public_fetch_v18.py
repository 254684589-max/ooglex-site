#!/usr/bin/env python3
"""V18 append-only first-successful-observation receipts for Treasury CSV URLs.

An Ooglex retrieval proves that an HTTP response was obtainable by Ooglex at
the recorded UTC verification instant. It does NOT prove first publication by
the Treasury, historical PIT availability, amendment provenance or permissions.
The V18 first-seen clock starts when this recorder is installed: no backdating
using archival observation dates, HTTP Date or repository commit timestamps.
"""
import argparse
import hashlib
import json
import os
from datetime import datetime,timezone
from pathlib import Path

from scripts.collect_treasury_source_evidence_v15 import ROOT
from scripts.track_treasury_retrievals_v16 import iso_utc

V15=ROOT/"data/asset-compass-treasury-source-evidence-v15.json"
V16=ROOT/"data/asset-compass-treasury-v16-report.json"
LOG=ROOT/"data/asset-compass-treasury-v18-public-fetches.jsonl"
REPORT=ROOT/"data/asset-compass-treasury-v18-fetch-readiness.json"

def checked_time(v):
    return datetime.fromisoformat(iso_utc(v))

def verify(v15,v16,raw_dir,at):
    when=checked_time(at)
    if v15.get("report_type")!="asset_compass_v15_treasury_raw_source_evidence" or v16.get("report_type")!="asset_compass_v16_retrieval_comparison":
        raise ValueError("Missing V15/V16 completed retrieval evidence")
    if v15.get("year")!=v16.get("year"):
        raise ValueError("V15/V16 source year conflict")
    if v16.get("source_sha256")!={r["type"]:r["sha256"] for r in v15.get("source_receipts",[])}:
        raise ValueError("V15/V16 raw source hash mismatch")
    if any(v15.get(k) is not False for k in ("original_publication_time_verified","eligible_for_point_in_time_backtest","validated_for_live_scoring")) or any(v16.get(k) is not False for k in ("historical_original_publication_timestamp_verified","eligible_for_point_in_time_backtest","validated_for_live_scoring")):
        raise ValueError("Historical PIT gate must remain closed")
    if checked_time(v16["checked_at"])>when or checked_time(v15["retrieved_at"])>when:
        raise ValueError("Cannot witness successful retrieval in the past")
    receipts=v15.get("source_receipts",[])
    if len(receipts)!=2 or {r.get("type") for r in receipts}!={"nominal","real"}:
        raise ValueError("Exactly two authentic curve receipts required")
    for r in receipts:
        if not r.get("source_url","").startswith("https://home.treasury.gov/resource-center/data-chart-center/interest-rates/"):
            raise ValueError("Unexpected source URL")
        raw=(Path(raw_dir)/(str(v15["year"])+"-"+r["type"]+".csv")).read_bytes()
        if hashlib.sha256(raw).hexdigest()!=r["sha256"] or len(raw)!=r["bytes"]:
            raise ValueError("Source raw response bytes differ from official receipts")
    return receipts,when

def build(v15,v16,raw_dir,prior,*,run_id,at):
    receipts,now=verify(v15,v16,raw_dir,at)
    if not isinstance(run_id,str) or not run_id.isdigit():
        raise ValueError("GitHub Actions run ID required")
    if len(prior)!=len({(x.get("run_id"),x.get("curve_type")) for x in prior}):
        raise ValueError("Duplicate previously recorded curve/run event")
    last=None
    first={}
    prev_hash={}
    for item in prior:
        if item.get("report_type")!="asset_compass_v18_successful_fetch" or item.get("schema_version")!=1:
            raise ValueError("Invalid historical V18 evidence event")
        if item.get("validated_for_live_scoring") is not False or item.get("official_first_publication_verified") is not False:
            raise ValueError("Event metadata attempts to unlock unsupported claims")
        stamp=checked_time(item["verified_no_later_than"])
        if last is not None and stamp<last:
            raise ValueError("Nonmonotonic append-only fetch log")
        if stamp>now:
            raise ValueError("Prior event from the future")
        last=stamp
        key=item["source_url"]
        if item["curve_type"] not in ("nominal","real") or len(item["sha256"])!=64:
            raise ValueError("Invalid previous event")
        if key not in first:
            first[key]=item["verified_no_later_than"]
        prev_hash[key]=item["sha256"]
    if any(item["run_id"]==run_id for item in prior):
        raise ValueError("Current run already recorded; refuse replay")
    events=[]
    for receipt in sorted(receipts,key=lambda r:r["type"]):
        key=receipt["source_url"]
        prior_digest=prev_hash.get(key)
        events.append({
          "schema_version":1,"report_type":"asset_compass_v18_successful_fetch",
          "run_id":run_id,"year":v15["year"],"curve_type":receipt["type"],
          "source_url":key,"sha256":receipt["sha256"],
          "verified_no_later_than":now.isoformat(),
          "first_ooglex_verified_fetch_at":first.get(key,now.isoformat()),
          "newly_witnessed_url":key not in first,
          "changed_bytes_since_previous_fetch":None if prior_digest is None else prior_digest!=receipt["sha256"],
          "raw_artifact_retention_days":30,
          "http_header_date_is_publication_time":False,
          "original_observation_date_is_publication_time":False,
          "official_first_publication_verified":False,
          "eligible_for_point_in_time_backtest":False,
          "validated_for_live_scoring":False,
        })
    report={
      "schema_version":1,"report_type":"asset_compass_v18_fetch_witness_summary",
      "run_id":run_id,"verified_no_later_than":now.isoformat(),
      "tracked_curves":len(events),
      "first_fetch_events":sum(bool(x["newly_witnessed_url"]) for x in events),
      "changed_source_files":sum(x["changed_bytes_since_previous_fetch"] is True for x in events),
      "first_successful_ooglex_fetches":[{"curve_type":x["curve_type"],"source_url":x["source_url"],
         "sha256":x["sha256"],"first_ooglex_verified_fetch_at":x["first_ooglex_verified_fetch_at"],
         "changed_bytes_since_previous_fetch":x["changed_bytes_since_previous_fetch"]} for x in events],
      "raw_artifact_retention_days":30,
      "official_first_publication_verified":False,
      "historical_vintage_asof_verified":False,
      "eligible_for_point_in_time_backtest":False,
      "validated_for_live_scoring":False,
      "note":"Ooglex first successful public HTTP retrieval evidence only. It does not establish Treasury first-publication timestamps or authorize PIT investment backtests.",
    }
    return events,report

def read_events(path):
    if not Path(path).exists():return []
    return [json.loads(line) for line in Path(path).read_text(encoding="utf-8").splitlines() if line.strip()]

def persist(events,report,log_path,report_path):
    log_path=Path(log_path);report_path=Path(report_path)
    log_path.parent.mkdir(parents=True,exist_ok=True)
    report_path.parent.mkdir(parents=True,exist_ok=True)
    # Validate uniqueness and ordering before writing either file.
    before=read_events(log_path)
    if before and checked_time(before[-1]["verified_no_later_than"])>checked_time(events[0]["verified_no_later_than"]):
        raise ValueError("Attempted to backdate append-only event")
    if any((event["run_id"],event["curve_type"]) in
           {(x["run_id"],x["curve_type"]) for x in before} for event in events):
        raise ValueError("Duplicate event would violate append-only log")
    with log_path.open("a",encoding="utf-8") as f:
        for row in events:f.write(json.dumps(row,ensure_ascii=False,separators=(",",":"))+"\n")
    report_path.write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--v15",type=Path,default=V15)
    p.add_argument("--v16",type=Path,default=V16)
    p.add_argument("--raw-dir",type=Path,required=True)
    p.add_argument("--log",type=Path,default=LOG)
    p.add_argument("--report",type=Path,default=REPORT)
    p.add_argument("--run-id",default=os.environ.get("GITHUB_RUN_ID"))
    a=p.parse_args()
    if not a.run_id:raise ValueError("Run ID required")
    v15=json.loads(a.v15.read_text(encoding="utf-8"))
    v16=json.loads(a.v16.read_text(encoding="utf-8"))
    events,report=build(v15,v16,a.raw_dir,read_events(a.log),run_id=str(a.run_id),
                        at=datetime.now(timezone.utc).isoformat())
    persist(events,report,a.log,a.report)
    print(json.dumps({"curves":report["tracked_curves"],"new_fetches":report["first_fetch_events"],
                      "changed_bytes":report["changed_source_files"],"pit_eligible":False}))
if __name__=="__main__":main()
