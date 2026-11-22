#!/usr/bin/env python3
"""V14 public PIT evidence gap inventory: derived from existing V33 audit.

The existing private historical-vintage database must never be deployed.
An official historical value, first-seen stamp, and ALFRED vintage date alone
are NOT an original publication timestamp. This report cannot certify PIT,
redistribution licenses, total returns or statistical model performance.
"""
import argparse
import json
from datetime import datetime, timezone
from pathlib import Path

from scripts.archive_asset_compass_observations import LEDGER, ROOT, load
from scripts.check_asset_compass_history_readiness import REQUIRED_SERIES
from scripts.qualify_asset_compass_pit_v33 import qualify, ARCHIVES, source_family

SNAPSHOT=ROOT/"data"/"asset-scores.json"
OUTPUT=ROOT/"data"/"asset-compass-pit-readiness-v14.json"
CRITERIA=(
    "source_original_release_timestamp_verified",
    "provider_vintage_asof_value_verified",
    "original_release_artifact_integrity_verified",
    "redistribution_rights_approved",
    "historical_investable_asset_returns_verified",
)
PRIORITY={
    "treasury.us10y":1, "treasury.real10y":1, "treasury.us2y":1,
    "nyfed.effr":1, "bls.cpi":1, "bls.core_cpi":1,
    "bea.core_pce":2, "fed_h41.total_assets":2,
    "bls.unemployment":2, "bls.payroll":2,
    "liquidity.reserves":2, "liquidity.tga":2,
    "liquidity.overnight_rrp":2, "nyfed_recession.probability":3,
}
def build(rows,snapshot,now=None):
    audited=qualify(rows,snapshot,now=now)
    if set(audited["evidence"])!=REQUIRED_SERIES or set(PRIORITY)!=REQUIRED_SERIES:
        raise ValueError("Missing required macro series evidence")
    details=[]
    for sid in sorted(REQUIRED_SERIES,key=lambda x:(PRIORITY[x],x)):
        source=audited["evidence"][sid]
        verified=[c for c in CRITERIA if source.get(c) is True]
        missing=[c for c in CRITERIA if source.get(c) is not True]
        # V33's asserted input booleans are NOT independent verification.
        # The public count must not be interpreted as independently admitted.
        details.append({
          "series_id":sid,"source_family":source_family(sid),
          "priority_tier":PRIORITY[sid],"discovery_resource":source["discovery_resource"],
          "discovery_url":source["discovery_url"],
          "first_seen_distinct_periods":source["first_seen_distinct_periods"],
          "first_seen_versions":source["first_seen_versions"],
          "evidence_fields_present_unverified":verified,
          "evidence_gaps":missing,
          "original_release_timestamp_verified":False,
          "independently_qualified_for_pit":False,
          "research_only":True,
        })
    qualified=audited["independently_qualified_pit_series"]
    if qualified!=0 or any(x["independently_qualified_for_pit"] for x in details):
        raise ValueError("Unexpected PIT qualification: independent review required")
    return {
      "schema_version":1,"report_type":"asset_compass_v14_pit_evidence_gaps",
      "generated_at":audited["audited_at"],
      "required_series":len(REQUIRED_SERIES),
      "first_seen_covered_series":audited["first_seen_covered_series"],
      "independently_qualified_pit_series":0,
      "series":details,
      "next_evidence_steps":[
        "Acquire and preserve original release artifacts and official publication timestamps with timezone",
        "Independently compare pre-revision as-of values against original official releases",
        "Document data retrieval and redistribution or derived-results license review",
        "Acquire investable total-return series with asset conventions, costs and survivorship assumptions",
        "Complete independently reviewed multi-regime walk-forward validation",
      ],
      "blocked_by":audited["blocked_by"],
      "official_publication_timestamps_not_inferred":True,
      "private_vintage_database_exported":False,
      "validated_for_live_scoring":False,
      "eligible_for_point_in_time_backtest":False,
      "investment_alerts_enabled":False,
      "note":"14 series inventory is a research evidence gap list, not a certification; source discovery URLs are not validated original release artifacts.",
    }
def main():
    p=argparse.ArgumentParser()
    p.add_argument("--ledger",type=Path,default=LEDGER)
    p.add_argument("--snapshot",type=Path,default=SNAPSHOT)
    p.add_argument("--output",type=Path,default=OUTPUT)
    args=p.parse_args()
    snapshot=json.loads(args.snapshot.read_text(encoding="utf-8"))
    report=build(load(args.ledger),snapshot)
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(json.dumps({"covered":report["first_seen_covered_series"],"pit_qualified":0,
       "blocked":len(report["blocked_by"]),"status":"research_only"},ensure_ascii=False))
if __name__=="__main__":main()
