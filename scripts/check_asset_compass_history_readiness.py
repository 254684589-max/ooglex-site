#!/usr/bin/env python3
"""Conservative public metadata for the macro observation archive.

No market prices or proprietary model history included. A first-seen archive
cannot certify official historical release vintages or return predictive skill.
"""
import argparse
import json
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from scripts.archive_asset_compass_observations import LEDGER,load,utc

ROOT=Path(__file__).resolve().parents[1]
OUTPUT=ROOT/"data"/"asset-compass-history-readiness.json"
REQUIRED_SERIES={"treasury.us10y","treasury.real10y","treasury.us2y",
 "nyfed.effr","bls.cpi","bls.core_cpi","bls.unemployment","bls.payroll",
 "bea.core_pce","fed_h41.total_assets",
 "liquidity.reserves","liquidity.tga","liquidity.overnight_rrp",
 "nyfed_recession.probability"}

def report(rows):
    groups=defaultdict(list)
    for r in rows:
        if r.get("official_release_time_known") is not False or r.get("eligible_for_historical_official_vintage") is not False:
            raise ValueError("Archive incorrectly claims official release vintages")
        if r.get("schema_version")!=1:raise ValueError("Schema mismatch")
        utc(r["first_seen_at"])
        groups[r["series_id"]].append(r)
    summary={}
    for sid in sorted(REQUIRED_SERIES):
        items=groups.get(sid,[])
        summary[sid]={
          "archived_versions":len(items),
          "distinct_observation_periods":len({x["observation_period"] for x in items}),
          "first_recorded_at":min((x["first_seen_at"] for x in items),default=None),
          "latest_recorded_at":max((x["first_seen_at"] for x in items),default=None)
        }
    reasons=[]
    if not rows:reasons.append("no_live_archive_yet")
    if any(summary[k]["distinct_observation_periods"]<36 for k in REQUIRED_SERIES):
        reasons.append("less_than_36_monthly_or_daily_periods_for_one_or_more_series")
    # Even a 36+ period first-seen dataset is NOT necessarily multi-cycle
    # macro release history with independently validated cross-asset returns.
    reasons+=["official_historical_release_vintages_unverified",
              "asset_total_return_history_not_qualified",
              "multi_regime_oos_validation_not_passed"]
    return {
      "schema_version":1,"report_type":"asset_compass_history_readiness",
      "status":"research_data_collection_only",
      "archived_observations":len(rows),"series":summary,
      "validated_for_live_scoring":False,
      "eligible_for_point_in_time_backtest":False,
      "blockers":reasons,
      "note":"first_recorded_at is when Ooglex archived a value, not the original official release date."
    }

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--archive",type=Path,default=LEDGER)
    p.add_argument("--output",type=Path,default=OUTPUT)
    args=p.parse_args()
    result=report(load(args.archive))
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print("Macro archive readiness:",result["archived_observations"],"score enabled:",result["validated_for_live_scoring"])
if __name__=="__main__":main()
