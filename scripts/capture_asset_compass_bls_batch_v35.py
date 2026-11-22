#!/usr/bin/env python3
"""V35 three-month BLS CPI artifact custody manifest, independent failure tracking.

A successful capture is evidence of today's retrieval, NOT a verified PIT
release or a license. GitHub runner /tmp is transient; receipts uploaded to
Actions have finite retention and do not establish permanent private custody.
"""
import argparse
import json
from datetime import datetime, timezone
from pathlib import Path

from scripts.archive_asset_compass_observations import ROOT
from scripts.capture_asset_compass_bls_release_v34 import ALLOWLIST, acquire

OUTPUT=Path("/tmp/ooglex-v35-cpi-manifest.json")
IDENTIFIERS=(
    "bls-cpi-2024-12-release",
    "bls-cpi-2025-01-release",
    "bls-cpi-2025-02-release",
)

def collect(*, private_dir=None, fetcher=acquire, now=None):
    checked=now or datetime.now(timezone.utc)
    if checked.tzinfo is None:
        raise ValueError("Timezone-aware capture instant required")
    results={}
    for ident in IDENTIFIERS:
        declared=ALLOWLIST[ident]
        try:
            receipt=fetcher(ident,now=checked,persist_dir=private_dir)
            if receipt["artifact_id"] != ident:
                raise ValueError("Mismatched capture receipt identity")
            if receipt["source_url"] != declared["url"]:
                raise ValueError("Mismatched capture source URL")
            if receipt["historical_observation_period"] != declared["observation_period"]:
                raise ValueError("Mismatched observation month")
            if not isinstance(receipt.get("sha256"),str) or len(receipt["sha256"])!=64:
                raise ValueError("Missing sha256")
            if not isinstance(receipt.get("byte_size"),int) or receipt["byte_size"]<=0:
                raise ValueError("Missing byte count")
            if receipt["eligible_for_point_in_time_backtest"] is not False:
                raise ValueError("Forbidden PIT certification flag")
            if private_dir is None and receipt["raw_artifact_saved_in_private_directory"]:
                raise ValueError("Unexpected private retention claim on ephemeral runner")
            results[ident]={"status":"captured_today_unverified_for_pit",
                            "receipt":receipt}
        except Exception as e:
            # Never silently treat a failed official archive fetch as a zero
            # value or historical record. The caller decides whether to fail CI.
            results[ident]={"status":"capture_failed",
                            "error_type":type(e).__name__}
    success=sum(x["status"]=="captured_today_unverified_for_pit"
                for x in results.values())
    return {
        "schema_version":1,
        "report_type":"asset_compass_v35_bls_cpi_release_custody",
        "batch_checked_at":checked.astimezone(timezone.utc).isoformat(),
        "requested_archives":len(IDENTIFIERS),
        "fetched_archives":success,
        "failed_archives":len(IDENTIFIERS)-success,
        "entries":results,
        "archive_urls_independently_identified":True,
        "source_document_bytes_continuously_preserved_since_publication":False,
        "original_release_time_independently_verified":False,
        "historical_pit_series_approved":0,
        "public_repository_contains_raw_release_files":False,
        "eligible_for_point_in_time_backtest":False,
        "validated_for_live_scoring":False,
        "automatic_investment_alerts_enabled":False,
        "raw_custody_scope":"local_private_dir" if private_dir is not None
            else "ephemeral_process_only",
    }

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--private-dir",type=Path)
    p.add_argument("--output",type=Path,default=OUTPUT)
    p.add_argument("--fail-if-incomplete",action="store_true")
    a=p.parse_args()
    if a.private_dir and a.output.resolve().is_relative_to(ROOT.resolve()):
        raise ValueError("Private evidence manifest must remain outside GitHub repo")
    result=collect(private_dir=a.private_dir)
    a.output.parent.mkdir(parents=True,exist_ok=True)
    a.output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n",
                        encoding="utf-8")
    # V36 local-only custody: verify captured bytes and append sealed journal.
    if a.private_dir:
        from scripts.verify_asset_compass_private_custody_v36 import record_batch
        custody=record_batch(result,a.private_dir)
        print(json.dumps({"v36_private_custody_entries":custody["verified_total_records"],
                          "v36_new_records":custody["new_custody_records"],
                          "historic_release_time_verified":False},ensure_ascii=False))
    print(json.dumps({"requested":result["requested_archives"],
                      "fetched":result["fetched_archives"],
                      "failed":result["failed_archives"],
                      "pit_approved":0,
                      "raw_custody_scope":result["raw_custody_scope"]},
                     ensure_ascii=False))
    if a.fail_if_incomplete and result["failed_archives"]:
        raise SystemExit(2)

if __name__=="__main__":
    main()
