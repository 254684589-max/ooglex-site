#!/usr/bin/env python3
"""Point-in-time macro vintage warehouse (private research only).

A vintage is an official observation as actually available at a timestamp;
downloading historical final values today does NOT make them past vintages.
Use recorded release timestamps and archived source identifiers. As-of lookups
use the latest revision available at the decision instant. No inferred times.
"""
import argparse
import csv
import json
import math
import sqlite3
from datetime import date, datetime, timezone
from pathlib import Path
from scripts.backtest_asset_compass import parse_timestamp

ROOT=Path(__file__).resolve().parents[1]
MIGRATION=ROOT/"macro"/"migrations"/"0001_point_in_time.sql"
GROUPS={"rates","inflation","growth","liquidity","risk","asset_specific"}

def timestamp(s):
    return parse_timestamp(s).isoformat()

def valid_date(s):
    d=date.fromisoformat(str(s))
    if d>datetime.now(timezone.utc).date():
        raise ValueError("Future observation date")
    return d.isoformat()

def finite(v):
    n=float(v)
    if not math.isfinite(n):
        raise ValueError("Non-finite macro data")
    return n

def create_schema(db):
    db.executescript(MIGRATION.read_text(encoding="utf-8"))
    db.execute("PRAGMA foreign_keys=ON")

def register_series(db,series_id,source,frequency,units):
    if not all(str(x).strip() for x in (series_id,source,frequency,units)):
        raise ValueError("Series metadata missing")
    db.execute("INSERT OR IGNORE INTO macro_series(series_id,source,frequency,units) VALUES(?,?,?,?)",
               (series_id,source,frequency,units))
    existing=db.execute("SELECT source,frequency,units FROM macro_series WHERE series_id=?",(series_id,)).fetchone()
    if existing!=(source,frequency,units):
        raise ValueError("Conflicting metadata for "+series_id)

def ingest_macro(db,rows):
    count=0
    with db:
        for row in rows:
            sid=row["series_id"].strip()
            register_series(db,sid,row["source"].strip(),row["frequency"].strip(),row["units"].strip())
            obs=valid_date(row["observation_date"])
            available=timestamp(row["available_at"])
            if available[:10]<obs:
                raise ValueError("Release precedes observation")
            release=row["source_release_id"].strip()
            url=row["source_url"].strip()
            if not release or not url.startswith("https://"):
                raise ValueError("Release ID and HTTPS original source are required")
            value=finite(row["value"])
            before=db.total_changes
            db.execute("INSERT OR IGNORE INTO macro_vintages(series_id,observation_date,available_at,value,source_release_id,source_url) VALUES(?,?,?,?,?,?)",
                       (sid,obs,available,value,release,url))
            if db.total_changes==before:
                old=db.execute("SELECT value,source_url FROM macro_vintages WHERE series_id=? AND observation_date=? AND available_at=? AND source_release_id=?",
                               (sid,obs,available,release)).fetchone()
                if old!=(value,url):
                    raise ValueError("Conflicting immutable release: "+sid)
            count+=db.total_changes-before
    return count

def ingest_factors(db,rows):
    count=0
    with db:
        for row in rows:
            group=row["factor_group"]
            if group not in GROUPS:raise ValueError("Unknown factor group")
            obs=valid_date(row["observation_date"])
            available=timestamp(row["available_at"])
            if available[:10]<obs:raise ValueError("Factor released before observation")
            sig=finite(row["factor_signal"])
            if not -1<=sig<=1:raise ValueError("Factor outside [-1,1]")
            refs=json.loads(row["source_refs_json"])
            if not isinstance(refs,list) or not refs or not all(isinstance(x,str) and x.strip() for x in refs):
                raise ValueError("At least one source reference required")
            asset=row["asset_id"].strip()
            version=row["model_version"].strip()
            if not asset or not version:raise ValueError("Asset/model ID missing")
            normalized=json.dumps(refs,ensure_ascii=False,separators=(",",":"))
            before=db.total_changes
            db.execute("INSERT OR IGNORE INTO asset_factor_vintages(asset_id,factor_group,observation_date,available_at,factor_signal,model_version,source_refs_json) VALUES(?,?,?,?,?,?,?)",
                       (asset,group,obs,available,sig,version,normalized))
            if db.total_changes==before:
                old=db.execute("SELECT factor_signal,source_refs_json FROM asset_factor_vintages WHERE asset_id=? AND factor_group=? AND observation_date=? AND available_at=? AND model_version=?",
                               (asset,group,obs,available,version)).fetchone()
                if old!=(sig,normalized):raise ValueError("Conflicting immutable factor")
            count+=db.total_changes-before
    return count

def asof_macro(db,series_id,decision_at):
    decision=timestamp(decision_at)
    rows=db.execute("""SELECT observation_date,available_at,value,source_release_id,source_url
        FROM macro_vintages WHERE series_id=? AND available_at<=?
        ORDER BY observation_date DESC, available_at DESC, vintage_id DESC LIMIT 1""",
        (series_id,decision)).fetchone()
    if rows is None:return None
    keys=("observation_date","available_at","value","source_release_id","source_url")
    return dict(zip(keys,rows))

def asof_factors(db,asset,decision_at,version):
    decision=timestamp(decision_at)
    rows=db.execute("""SELECT factor_group,observation_date,available_at,factor_signal,source_refs_json
        FROM asset_factor_vintages WHERE asset_id=? AND model_version=? AND available_at<=?
        ORDER BY observation_date DESC,available_at DESC,factor_id DESC""",
        (asset,version,decision)).fetchall()
    output={}
    for group,obs,available,signal,refs in rows:
        if group not in output:
            output[group]={"observation_date":obs,"available_at":available,
                           "signal":signal,"source_refs":json.loads(refs)}
    return output

def read_csv(path):
    with path.open(encoding="utf-8-sig",newline="") as f:return list(csv.DictReader(f))

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--db",type=Path,required=True)
    p.add_argument("--macro-csv",type=Path)
    p.add_argument("--factors-csv",type=Path)
    p.add_argument("--asof",help="UTC timestamp with timezone")
    p.add_argument("--series")
    args=p.parse_args()
    if args.db.resolve().is_relative_to(ROOT.resolve()):
        raise ValueError("Research database must stay outside the public site repository")
    if not any((args.macro_csv,args.factors_csv,args.asof)):p.error("Choose an operation")
    with sqlite3.connect(args.db) as db:
        create_schema(db)
        if args.macro_csv:print("Macro vintages added:",ingest_macro(db,read_csv(args.macro_csv)))
        if args.factors_csv:print("Factor vintages added:",ingest_factors(db,read_csv(args.factors_csv)))
        if args.asof:
            if not args.series:p.error("--asof requires --series")
            print(json.dumps(asof_macro(db,args.series,args.asof),ensure_ascii=False))
if __name__=="__main__":main()
