#!/usr/bin/env python3
"""V31 verify source retrieval timestamps precede final snapshot generation.

This checks internal snapshot consistency, NOT historical official release
timestamps, PIT data rights, backtest validity, or scoring eligibility.
"""
import argparse
import json
from datetime import datetime, timezone
from pathlib import Path
from scripts.archive_asset_compass_observations import ROOT, utc

SECTIONS=("bls","bea","fed_h41","liquidity","nyfed_recession_model")

def inspect(snapshot, *, now):
    instant=utc(now) if isinstance(now,str) else now.astimezone(timezone.utc)
    if snapshot.get("schema_version") != 1:
        raise ValueError("Invalid snapshot schema")
    generated=utc(snapshot["generated_at"])
    if generated>instant:raise ValueError("Future snapshot generated_at")
    observed={}
    problems=[]
    for section in SECTIONS:
        block=snapshot.get(section)
        if block is None:
            continue
        if not isinstance(block,dict):
            problems.append(f"malformed_source_block:{section}")
            continue
        raw=block.get("retrieved_at")
        if not raw:
            problems.append(f"missing_retrieval_timestamp:{section}")
            continue
        try:
            received=utc(raw)
        except (TypeError,ValueError,AttributeError):
            problems.append(f"invalid_retrieval_timestamp:{section}")
            continue
        observed[section]=received.isoformat()
        if received>generated:
            problems.append(f"retrieval_after_snapshot_generation:{section}")
        if received>instant:
            problems.append(f"future_retrieval_timestamp:{section}")
    return {"schema_version":1,
            "report_type":"asset_compass_v31_snapshot_temporal_integrity",
            "generated_at":generated.isoformat(),
            "source_retrieval_at":observed,
            "issues":problems,
            "status":"pass" if not problems else "blocked",
            "official_release_time_certified":False,
            "eligible_for_point_in_time_backtest":False,
            "validated_for_live_scoring":False}

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--snapshot",type=Path,
                   default=ROOT/"data"/"asset-scores.json")
    p.add_argument("--output",type=Path,
                   default=Path("/tmp/asset-compass-v31-timing.json"))
    p.add_argument("--fail-on-issue",action="store_true")
    a=p.parse_args()
    data=json.loads(a.snapshot.read_text(encoding="utf-8"))
    result=inspect(data,now=datetime.now(timezone.utc))
    a.output.parent.mkdir(parents=True,exist_ok=True)
    a.output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n",
                        encoding="utf-8")
    print(json.dumps({"status":result["status"],"issues":result["issues"],
                      "validated_for_live_scoring":False},ensure_ascii=False))
    if a.fail_on_issue and result["issues"]:
        raise SystemExit(2)

if __name__=="__main__":
    main()
