#!/usr/bin/env python3
"""V57 immutable Ooglex first-seen evidence journal, not official PIT vintage proof.

An append-only hash chain preserves *when this website saw* each Gold CFTC /
Treasury 30-year quote, including revisions. Dates are neither source
publication UTC times nor certified market information-availability timestamps.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import re
from datetime import datetime, timezone
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
DEFAULT_REPORT=ROOT/"data/asset-compass-asset-specific-v57.json"
DEFAULT_LEDGER=ROOT/"data/asset-compass-asset-specific-first-seen-v57.jsonl"
ALLOWED=("cftc_gold","treasury_30y")


def digest(value):
    return hashlib.sha256(json.dumps(value,sort_keys=True,separators=(",",":"),
              ensure_ascii=False,allow_nan=False).encode("utf-8")).hexdigest()


def checked_time(value):
    dt=datetime.fromisoformat(value.replace("Z","+00:00"))
    if dt.utcoffset() is None:
        raise ValueError("First seen requires timezone-aware UTC timestamp")
    return dt.astimezone(timezone.utc)


def read_rows(text):
    rows=[]
    prev="GENESIS"
    last_timestamp=None
    for n,line in enumerate(text.splitlines(),start=1):
        item=json.loads(line)
        if item.get("schema_version")!=1 or item.get("report_type")!="ooglex_v57_first_seen_evidence":
            raise ValueError(f"V57 ledger schema invalid at {n}")
        if item.get("source_id") not in ALLOWED:
            raise ValueError("Unknown source in first-seen evidence")
        if item.get("prior_entry_sha256")!=prev or item.get("entry_sha256")!=digest({
              k:v for k,v in item.items() if k!="entry_sha256"}):
            raise ValueError("V57 first-seen chain or contents modified")
        stamp=checked_time(item["first_seen_at_utc"])
        if last_timestamp and stamp<last_timestamp:
            raise ValueError("First-seen timestamp moved backward")
        if (item.get("source_release_timestamp_verified") is not False or
            item.get("historical_pit_qualified") is not False or
            item.get("model_scoring_qualified") is not False):
            raise ValueError("Journal must not self-approve publication provenance")
        prev=item["entry_sha256"]
        rows.append(item)
        last_timestamp=stamp
    return rows


def append_evidence(existing,report,*,now=None):
    now=now or datetime.now(timezone.utc)
    if now.utcoffset() is None:
        raise ValueError("UTC current time required")
    now=now.astimezone(timezone.utc)
    if (report.get("report_type")!="asset_compass_v57_authentic_asset_specific_source_research"
        or report.get("validated_for_live_scoring") is not False
        or report.get("approved_asset_scores")!=0
        or report.get("first_publication_vintages_certified")!=0):
        raise ValueError("Cannot journal unqualified or fabricated score report")
    generated=checked_time(report.get("generated_at"))
    if generated>now:
        raise ValueError("Cannot journal report from the future")
    rows=read_rows(existing)
    seen={(x["source_id"],x["observation_date"],x["value"],
           x["original_response_sha256"]) for x in rows}
    previous=rows[-1]["entry_sha256"] if rows else "GENESIS"
    for source_id in ALLOWED:
        source=report["sources"][source_id]
        if source_id=="cftc_gold":
            observation_date=source["latest_observation_date"]
            value=source["latest_managed_money_net_percent_oi"]
        else:
            observation_date=source["latest_auction_date"]
            value=source["latest_bid_to_cover_ratio"]
        raw_sha=source["source_sha256"]
        if not re.fullmatch(r"[0-9a-f]{64}",raw_sha):
            raise ValueError("Original public source response digest missing")
        key=(source_id,observation_date,value,raw_sha)
        if key in seen:continue
        item={
            "schema_version":1,
            "report_type":"ooglex_v57_first_seen_evidence",
            "source_id":source_id,
            "observation_date":observation_date,
            "value":value,
            "original_response_sha256":raw_sha,
            "first_seen_at_utc":now.isoformat(),
            "source_report_generated_at_utc":generated.isoformat(),
            "source_release_timestamp_verified":False,
            "historical_pit_qualified":False,
            "model_scoring_qualified":False,
            "prior_entry_sha256":previous,
        }
        item["entry_sha256"]=digest(item)
        rows.append(item)
        previous=item["entry_sha256"]
        seen.add(key)
    # The output is fully revalidated to prevent writing a broken chain.
    content="".join(json.dumps(row,sort_keys=True,ensure_ascii=False,
            separators=(",",":"),allow_nan=False)+"\n" for row in rows)
    read_rows(content)
    return content


def main():
    p=argparse.ArgumentParser()
    p.add_argument("--report",type=Path,default=DEFAULT_REPORT)
    p.add_argument("--ledger",type=Path,default=DEFAULT_LEDGER)
    p.add_argument("--verify-only",action="store_true")
    a=p.parse_args()
    current=a.ledger.read_text(encoding="utf-8") if a.ledger.exists() else ""
    if a.verify_only:
        rows=read_rows(current)
        print("V57 first-seen chain valid:",len(rows),"records; none are original PIT-certified")
        return
    report=json.loads(a.report.read_text(encoding="utf-8"))
    result=append_evidence(current,report)
    a.ledger.parent.mkdir(parents=True,exist_ok=True)
    a.ledger.write_text(result,encoding="utf-8")
    print("V57 first-seen journal valid:",len(read_rows(result)),"records; not original release PIT")


if __name__=="__main__":
    main()
