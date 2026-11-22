#!/usr/bin/env python3
"""Build actual Federal Reserve H.15 Treasury market yields via FRED public mirror.

DGS10, DGS2 and DFII10 are independently published H.15 yield series.
This is a current historical observation export, NOT original release vintages.
"""
import argparse
import csv
import io
import json
import math
import urllib.parse
import urllib.request
from datetime import date,datetime,timezone
from pathlib import Path

SERIES={"DGS10":"us10y","DGS2":"us2y","DFII10":"real10y"}
SOURCE="Federal Reserve Board H.15 via FRED"

def download(identifier,start,end):
    if identifier not in SERIES:
        raise ValueError("Unsupported H.15 series")
    base="https://fred.stlouisfed.org/graph/fredgraph.csv"
    url=base+"?"+urllib.parse.urlencode({"id":identifier,"cosd":start.isoformat(),"coed":end.isoformat()})
    request=urllib.request.Request(url,headers={"User-Agent":"OoglexResearch/1.0 (+https://www.ooglex.com/)"})
    with urllib.request.urlopen(request,timeout=35) as response:
        # Each 3-year daily series fits comfortably within 1MB.
        if response.geturl().split("?")[0]!=base:
            raise ValueError("Unexpected FRED redirect")
        raw=response.read(2_000_001)
    if len(raw)>2_000_000 or not raw:
        raise ValueError("H.15 response oversized or empty")
    body=raw.decode("utf-8-sig")
    if "<html" in body.lower()[:300]:
        raise ValueError("Expected FRED CSV, not HTML")
    reader=csv.DictReader(io.StringIO(body))
    if not reader.fieldnames or identifier not in reader.fieldnames:
        raise ValueError("Missing FRED H.15 field")
    date_col="observation_date" if "observation_date" in reader.fieldnames else "DATE"
    if date_col not in reader.fieldnames:
        raise ValueError("Missing FRED observation_date")
    values={}
    for r in reader:
        day=date.fromisoformat(r[date_col])
        if not start<=day<=end:
            continue
        cell=r[identifier].strip()
        if not cell or cell==".":
            continue
        value=float(cell)
        if not math.isfinite(value) or not (-5<value<30):
            raise ValueError("Invalid H.15 yield")
        values[day.isoformat()]=value
    if len(values)<100:
        raise ValueError("Insufficient H.15 observations for "+identifier)
    return values,url

def build(start_year=None,output=Path("data/asset-compass-treasury-history.json"),
          today=None,fetcher=download):
    today=today or date.today()
    if start_year is None:start_year=today.year-2
    if not (1997<=start_year<=today.year):
        raise ValueError("Invalid H.15 historical start year")
    begin=date(start_year,1,1)
    source_urls=[];by_series={}
    for id in SERIES:
        records,url=fetcher(id,begin,today)
        by_series[id]=records
        source_urls.append(url)
    dates=sorted(set.intersection(*(set(v) for v in by_series.values())))
    observations=[]
    for day in dates:
        a,b,c=(by_series["DGS10"][day],by_series["DGS2"][day],by_series["DFII10"][day])
        observations.append({"date":day,"us10y":a,"us2y":b,"real10y":c,
          "breakeven10y":round(a-c,3),"spread10y2y":round(a-b,3)})
    if len(observations)<100:
        raise ValueError("Insufficient exact matched H.15 observations")
    document={"schema_version":1,"dataset":"treasury_historical_daily_observations",
        "source":SOURCE,"source_series_ids":list(SERIES),
        "retrieved_at":datetime.now(timezone.utc).isoformat(),
        "start_date":observations[0]["date"],"end_date":observations[-1]["date"],
        "observation_count":len(observations),
        "original_release_vintages_available":False,
        "not_valid_for_point_in_time_backtest":True,
        "source_urls":source_urls,"observations":observations}
    output.parent.mkdir(parents=True,exist_ok=True)
    output.write_text(json.dumps(document,ensure_ascii=False,separators=(",",":"))+"\n",
                      encoding="utf-8")
    return document

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--start-year",type=int)
    p.add_argument("--output",type=Path,default=Path("data/asset-compass-treasury-history.json"))
    args=p.parse_args()
    result=build(args.start_year,args.output)
    print("H.15 via FRED actual matched yield records:",result["observation_count"],
          result["start_date"],result["end_date"])

if __name__=="__main__":
    main()
