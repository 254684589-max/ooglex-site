#!/usr/bin/env python3
"""Append-only record of macro observations first seen by Ooglex.

IMPORTANT: first_seen_at is NOT the original official release time. It must
never be backdated or interpreted as a historical official macro vintage.
Snapshots are existing public official macro observations, not asset prices.
"""
import argparse
import hashlib
import json
import math
from datetime import date,datetime,timezone
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/"data"/"asset-scores.json"
LEDGER=ROOT/"data"/"asset-compass-observation-ledger.jsonl"
FIELDS={
 "treasury.us10y":("rates","us10y","percent"),
 "treasury.us2y":("rates","us2y","percent"),
 "treasury.real10y":("rates","real10y","percent"),
 "treasury.breakeven10y":("rates","breakeven10y","percent"),
 "treasury.spread10y2y":("rates","spread10y2y","percentage_points"),
 "nyfed.effr":("nyfed","effr_percent","percent"),
 "bls.cpi":("bls","cpi","index"),
 "bls.core_cpi":("bls","core_cpi","index"),
 "bls.unemployment":("bls","unemployment","percent"),
 "bls.payroll":("bls","payroll","thousands"),
}
SOURCES={
 "treasury":"U.S. Department of the Treasury",
 "nyfed":"Federal Reserve Bank of New York",
 "bls":"U.S. Bureau of Labor Statistics",
}

def utc(value):
    if not isinstance(value,str):raise ValueError("Timestamp must be explicit")
    ts=datetime.fromisoformat(value.replace("Z","+00:00"))
    if ts.tzinfo is None:raise ValueError("Timezone required")
    return ts.astimezone(timezone.utc)

def rows_from_snapshot(snapshot,first_seen_at):
    seen=utc(first_seen_at)
    if snapshot.get("schema_version")!=1:raise ValueError("Schema mismatch")
    items=[]
    for key,(section,name,unit) in FIELDS.items():
        prefix=key.split(".")[0]
        if section=="rates":
            value=(snapshot.get("rates") or {}).get(name)
            observed=snapshot.get("observation_date")
            source_type="daily_treasury_real_yield_curve" if name=="real10y" else "daily_treasury_yield_curve"
            source_url=next((u for u in snapshot.get("source_urls",[]) if isinstance(u,str) and u.startswith("https://home.treasury.gov/") and "type="+source_type+"&" in u),"")
        elif section=="nyfed":
            block=snapshot.get("nyfed") or {}
            value=block.get(name);observed=block.get("observation_date")
            source_url=block.get("source_url","")
        else:
            block=(snapshot.get("bls") or {}).get("series",{}).get(name) or {}
            value=block.get("value");observed=block.get("period")
            source_url=(snapshot.get("bls") or {}).get("source_url","")
        if type(value) not in (int,float) or not math.isfinite(value):continue
        if not isinstance(observed,str):continue
        if len(observed)==7 and prefix=="bls":
            d=date.fromisoformat(observed+"-01")
        else:
            d=date.fromisoformat(observed)
        if d>seen.date():raise ValueError("Future observation: "+key)
        if not isinstance(source_url,str) or not source_url.startswith("https://"):
            raise ValueError("Missing HTTPS source: "+key)
        # BLS monthly period is not the same as a known release timestamp.
        record={"schema_version":1,"series_id":key,"source":SOURCES[prefix],
          "observation_period":observed,"value":float(value),"unit":unit,
          "source_url":source_url,
          "first_seen_at":seen.isoformat(),
          "official_release_time_known":False,
          "eligible_for_historical_official_vintage":False,
          "provenance":"observed_snapshot_first_seen_not_original_release"}
        items.append(record)
    if not items:raise ValueError("No verified macro observations in snapshot")
    return items

def fingerprint(row):
    fields={k:row[k] for k in ("series_id","observation_period","value","unit","source_url")}
    payload=json.dumps(fields,sort_keys=True,ensure_ascii=False,separators=(",",":"))
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()

def append_ledger(old,new):
    previous={}
    for row in old:
        if row.get("schema_version")!=1 or row.get("official_release_time_known") is not False or row.get("eligible_for_historical_official_vintage") is not False:
            raise ValueError("Existing ledger has unverified data")
        utc(row["first_seen_at"])
        key=(row["series_id"],row["observation_period"],fingerprint(row))
        if key in previous:raise ValueError("Duplicate existing ledger record")
        previous[key]=row
    if old:
        last=utc(old[-1]["first_seen_at"])
        if any(utc(r["first_seen_at"])<last for r in new):
            raise ValueError("Cannot backdate observed records")
    added=[]
    for item in new:
        key=(item["series_id"],item["observation_period"],fingerprint(item))
        if key not in previous:
            previous[key]=item;added.append(item)
    return old+added,added

def load(path):
    if not path.exists():return []
    content=path.read_text(encoding="utf-8")
    return [json.loads(line) for line in content.splitlines() if line.strip()]

def update(snapshot_path=SOURCE,ledger_path=LEDGER,first_seen_at=None):
    instant=first_seen_at or datetime.now(timezone.utc).isoformat()
    snapshot=json.loads(Path(snapshot_path).read_text(encoding="utf-8"))
    old=load(Path(ledger_path))
    fresh=rows_from_snapshot(snapshot,instant)
    merged,added=append_ledger(old,fresh)
    if added:
        Path(ledger_path).parent.mkdir(parents=True,exist_ok=True)
        tmp=Path(str(ledger_path)+".tmp")
        tmp.write_text("".join(json.dumps(r,ensure_ascii=False,separators=(",",":"))+"\n" for r in merged),encoding="utf-8")
        tmp.replace(ledger_path)
    return len(merged),len(added)

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--snapshot",type=Path,default=SOURCE)
    p.add_argument("--ledger",type=Path,default=LEDGER)
    a=p.parse_args()
    total,added=update(a.snapshot,a.ledger)
    print("Macro first-seen observations:",total,"new:",added)
if __name__=="__main__":main()
