#!/usr/bin/env python3
"""Three distinct Fed-liquidity observations, via bounded FRED official mirrors.

WRESBAL: weekly reserve balances in millions USD
WTREGEN: weekly Treasury General Account in millions USD
RRPONTSYD: daily overnight reverse repo operations in billions USD

Never sum asynchronous observations into one claimed net liquidity figure.
FRED's current revised values are NOT independently verified release vintages.
"""
import csv
import io
import json
import math
import urllib.error
import urllib.request
from datetime import date, datetime, timezone
from pathlib import Path
from scripts.update_macro_fed_bea import download_url, FILE

SOURCES={
    "reserves":("WRESBAL","millions_usd",21,"Federal Reserve Board H.4.1"),
    "tga":("WTREGEN","millions_usd",21,"Federal Reserve Board H.4.1"),
    "overnight_rrp":("RRPONTSYD","billions_usd",11,"Federal Reserve Bank of New York"),
}

def source_url(symbol,today=None):
    if symbol not in {r[0] for r in SOURCES.values()}:
        raise ValueError("Unknown liquidity series")
    from urllib.parse import urlencode
    today=today or date.today()
    return "https://fred.stlouisfed.org/graph/fredgraph.csv?"+urlencode({
        "id":symbol,"cosd":date(today.year-1,1,1).isoformat(),"coed":today.isoformat()
    })

def parse_series(body,symbol,today=None):
    today=today or date.today()
    reader=csv.DictReader(io.StringIO(body.lstrip("\ufeff")))
    if not reader.fieldnames or symbol not in reader.fieldnames:
        raise ValueError("Missing series column "+symbol)
    datekey="observation_date" if "observation_date" in reader.fieldnames else "DATE"
    if datekey not in reader.fieldnames:raise ValueError("Missing date column")
    values={}
    for row in reader:
        try:
            day=date.fromisoformat(row[datekey])
            amount=float(row[symbol])
        except (ValueError,TypeError,KeyError):
            continue
        # A zero RRP balance is legitimate; negative balances are invalid here.
        if day>today or not math.isfinite(amount) or amount<0:continue
        values[day]=amount
    if not values:raise ValueError("No valid observations for "+symbol)
    return values

def build_observation(values,key,url,today=None):
    today=today or date.today()
    symbol,units,max_age,origin=SOURCES[key]
    day=max(values)
    if (today-day).days<0 or (today-day).days>max_age:
        raise ValueError("Liquidity source stale: "+symbol)
    return {
        "observation_date":day.isoformat(),"value":values[day],
        "unit":units,"source_series_id":symbol,
        "source":origin+" via FRED","source_url":url,
        "release_timestamp_verified":False,
        "frequency":"daily" if key=="overnight_rrp" else "weekly",
        "frequency_detail":"daily overnight operation balance" if key=="overnight_rrp" else "H.4.1 week-average estimate"
    }

def download(symbol):
    url=source_url(symbol)
    req=urllib.request.Request(url,headers={"User-Agent":"Mozilla/5.0 OoglexResearch/1.0","Accept":"text/csv"})
    with urllib.request.urlopen(req,timeout=25) as response:
        content=response.read(1200000).decode("utf-8-sig")
    if "<html" in content.lower()[:120]:raise ValueError("HTML instead of CSV")
    return parse_series(content,symbol),url

def main():
    if not FILE.is_file():raise ValueError("Macro snapshot unavailable")
    snapshot=json.loads(FILE.read_text(encoding="utf-8"))
    if snapshot.get("schema_version")!=1:raise ValueError("Snapshot schema invalid")
    verified={}
    pending={}
    for key,(symbol,*_) in SOURCES.items():
        try:
            values,url=download(symbol)
            verified[key]=build_observation(values,key,url)
            print("VERIFIED_LIQUIDITY_SOURCE:",symbol,verified[key]["observation_date"])
        except (OSError,TimeoutError,urllib.error.URLError,ValueError) as exc:
            pending[key]=type(exc).__name__
            print("PENDING_LIQUIDITY_SOURCE:",symbol,type(exc).__name__,str(exc))
    if verified:
        snapshot.setdefault("liquidity",{}).update(verified)
        snapshot["liquidity"]["retrieved_at"]=datetime.now(timezone.utc).isoformat()
        FILE.write_text(json.dumps(snapshot,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print("Liquidity verified:",sorted(verified),"pending:",pending)
    return {"verified":sorted(verified),"pending":pending}
if __name__=="__main__":main()
