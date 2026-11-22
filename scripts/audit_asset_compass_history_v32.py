#!/usr/bin/env python3
"""V32 audit immutable first-seen history for coverage and revision provenance.

A new source URL is not a value revision; repeated fetches of the same
observation period are not new history. This report cannot validate official
release dates, redistribution rights, asset returns, or model predictions.
"""
import argparse
import hashlib
import json
import math
from collections import defaultdict
from datetime import date, datetime, timezone
from pathlib import Path

from scripts.archive_asset_compass_observations import LEDGER, ROOT, load, utc
from scripts.check_asset_compass_archive_continuity_v25 import verify_ledger
from scripts.check_asset_compass_history_readiness import REQUIRED_SERIES, report as readiness_report
from scripts.check_asset_compass_snapshot_timing_v31 import inspect as timing_inspect
from scripts.monitor_asset_compass_continuity_v27 import DAILY, WEEKLY, DERIVED, day_of_observation

SNAPSHOT=ROOT/"data"/"asset-scores.json"
OUTPUT=ROOT/"data"/"asset-compass-history-audit-v32.json"
# This is an operational sampling target, not evidence of any predictive skill.
TARGET_DISTINCT_PERIODS=36


def value_key(row):
    """Differentiate real value/units revisions from URL-only corrections."""
    v=row.get("value")
    if type(v) not in (int,float) or not math.isfinite(v):
        raise ValueError("Non-finite or boolean archive value")
    return (row["unit"], float(v))


def analyze(rows, snapshot, now):
    instant=utc(now) if isinstance(now,str) else now
    if not isinstance(instant,datetime) or instant.tzinfo is None:
        raise ValueError("Timezone aware audit required")
    instant=instant.astimezone(timezone.utc)
    verify_ledger(rows,now=instant.isoformat())
    readiness=readiness_report(rows)
    timestamp_audit=timing_inspect(snapshot,now=instant)
    groups=defaultdict(list)
    for r in rows:
        groups[r["series_id"]].append(r)
    diagnostics={}
    missing=[]
    single_period=[]
    groups_full={}
    value_revisions=0
    provenance_only=0
    for sid in sorted(REQUIRED_SERIES | DERIVED):
        records=groups.get(sid,[])
        by_period=defaultdict(list)
        for r in records:
            d=day_of_observation(r["observation_period"])
            if d>instant.date():
                raise ValueError("Future macro observation date: "+sid)
            by_period[r["observation_period"]].append(r)
        count=len(by_period)
        if sid in REQUIRED_SERIES and not count:
            missing.append(sid)
        if sid in REQUIRED_SERIES and count==1:
            single_period.append(sid)
        revised=[]
        url_only=[]
        for period, versions in sorted(by_period.items()):
            distinct_values={value_key(r) for r in versions}
            if len(distinct_values)>1:
                revised.append(period)
            if len(distinct_values)==1 and len({r["source_url"] for r in versions})>1:
                url_only.append(period)
        value_revisions+=len(revised)
        provenance_only+=len(url_only)
        cadence=("derived" if sid in DERIVED else
                 "daily" if sid in DAILY else
                 "weekly" if sid in WEEKLY else "monthly")
        periods=sorted(by_period,key=day_of_observation)
        diagnostics[sid]={
            "cadence":cadence,
            "required":sid in REQUIRED_SERIES,
            "archived_versions":len(records),
            "distinct_observation_periods":count,
            "earliest_period":periods[0] if periods else None,
            "latest_period":periods[-1] if periods else None,
            "periods_to_36_sample_target":max(0,TARGET_DISTINCT_PERIODS-count),
            "value_revision_periods":revised,
            "url_only_correction_periods":url_only,
            "observed_version_count_not_period_count":True,
            "verified_official_release_vintages":False,
        }
        if sid in REQUIRED_SERIES:
            groups_full.setdefault(cadence,[]).append(sid)
    raw_hash=hashlib.sha256("".join(json.dumps(r,ensure_ascii=False,separators=(",",":"))+"\n"
                        for r in rows).encode("utf-8")).hexdigest()
    blockers=list(readiness["blockers"])
    if timestamp_audit["issues"]:
        blockers.append("snapshot_temporal_integrity_failed")
    if missing:
        blockers.append("required_sources_have_no_observations")
    return {
        "schema_version":1,
        "report_type":"asset_compass_v32_historical_coverage_quality",
        "as_of":instant.isoformat(),
        "snapshot_generated_at":timestamp_audit["generated_at"],
        "snapshot_temporal_integrity":timestamp_audit["status"],
        "snapshot_temporal_issues":timestamp_audit["issues"],
        "first_seen_ledger_canonical_sha256":raw_hash,
        "archive_record_count":len(rows),
        "archived_series_count":sum(bool(groups.get(s)) for s in REQUIRED_SERIES),
        "required_series_count":len(REQUIRED_SERIES),
        "required_missing_series":missing,
        "single_period_required_series":single_period,
        "number_of_series_with_36_distinct_periods":sum(
            diagnostics[s]["distinct_observation_periods"]>=TARGET_DISTINCT_PERIODS
            for s in REQUIRED_SERIES),
        "total_value_revision_periods":value_revisions,
        "total_url_only_correction_periods":provenance_only,
        "legacy_treasury_source_year_mismatches":readiness["treasury_source_year_mismatch_rows"],
        "series":diagnostics,
        "operational_quality_status":"attention_required" if missing or timestamp_audit["issues"]
            else "collecting_insufficient_history" if single_period or blockers
            else "audit_required",
        "blockers":blockers,
        "official_release_timestamps_verified":False,
        "historical_redistribution_rights_verified":False,
        "point_in_time_backtest_eligible":False,
        "validated_for_live_scoring":False,
        "investment_alerts_enabled":False,
        "interpretation":"First-seen records are not original publication vintages; URL corrections do not extend history.",
    }


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--ledger",type=Path,default=LEDGER)
    p.add_argument("--snapshot",type=Path,default=SNAPSHOT)
    p.add_argument("--output",type=Path,default=OUTPUT)
    p.add_argument("--fail-on-integrity",action="store_true")
    a=p.parse_args()
    snapshot=json.loads(a.snapshot.read_text(encoding="utf-8"))
    result=analyze(load(a.ledger),snapshot,datetime.now(timezone.utc))
    a.output.parent.mkdir(parents=True,exist_ok=True)
    a.output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(json.dumps({
       "archive_record_count":result["archive_record_count"],
       "required_coverage":f"{result['archived_series_count']}/{result['required_series_count']}",
       "number_of_series_with_36_distinct_periods":result["number_of_series_with_36_distinct_periods"],
       "value_revision_periods":result["total_value_revision_periods"],
       "url_only_correction_periods":result["total_url_only_correction_periods"],
       "snapshot_temporal_integrity":result["snapshot_temporal_integrity"],
       "validated_for_live_scoring":False,
    },ensure_ascii=False))
    if a.fail_on_integrity and (result["snapshot_temporal_issues"] or result["required_missing_series"]):
        raise SystemExit(2)


if __name__=="__main__":
    main()
