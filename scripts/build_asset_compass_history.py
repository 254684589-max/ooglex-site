#!/usr/bin/env python3
"""Download a validated historical Treasury *observations* dataset.

Historical observations are not historical point-in-time macro publication vintages.
This file is suitable for charting and checking arithmetic, not for certifying
predictive asset scores or a cross-asset trading backtest.
"""
import argparse
import json
from datetime import date,datetime,timezone
from pathlib import Path
from scripts.update_asset_scores import get_rows, by_date, lookup

def compile_history(nominal,real,end_date):
    n,r=by_date(nominal),by_date(real)
    observations=[]
    for d in sorted(set(n)&set(r)):
        if d>end_date:continue
        a,b,c=(lookup(n[d],"10yr"),lookup(n[d],"2yr"),lookup(r[d],"10yr"))
        if any(v is None or not (-5<v<30) for v in (a,b,c)):continue
        observations.append({"date":d.isoformat(),"us10y":a,"us2y":b,"real10y":c,
          "breakeven10y":round(a-c,3),"spread10y2y":round(a-b,3)})
    if not observations:raise ValueError("No valid matched dates")
    dates=[x["date"] for x in observations]
    if dates!=sorted(set(dates)):raise ValueError("Duplicate or unsorted observations")
    return observations

def build(years,output):
    nominal=[];real=[];urls=[]
    for year in years:
        for kind,target in (("nominal",nominal),("real",real)):
            rows,url=get_rows(kind,year)
            target.extend(rows);urls.append(url)
    records=compile_history(nominal,real,date.today())
    if len(records)<100:raise ValueError("Too few historical matched observations")
    document={
        "schema_version":1,"dataset":"treasury_historical_daily_observations",
        "source":"U.S. Department of the Treasury",
        "retrieved_at":datetime.now(timezone.utc).isoformat(),
        "start_date":records[0]["date"],"end_date":records[-1]["date"],
        "observation_count":len(records),
        "original_release_vintages_available":False,
        "not_valid_for_point_in_time_backtest":True,
        "source_urls":urls,"observations":records,
    }
    output.parent.mkdir(parents=True,exist_ok=True)
    output.write_text(json.dumps(document,ensure_ascii=False,separators=(",",":"))+"\n",encoding="utf-8")
    return document

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--start-year",type=int,default=date.today().year-5)
    parser.add_argument("--end-year",type=int,default=date.today().year)
    parser.add_argument("--output",type=Path,default=Path("data/asset-compass-treasury-history.json"))
    opts=parser.parse_args()
    if opts.start_year<1997 or opts.end_year>date.today().year or opts.start_year>opts.end_year or opts.end_year-opts.start_year>15:
        parser.error("Invalid Treasury historical date range (1997-current, maximum 16 years)")
    d=build(range(opts.start_year,opts.end_year+1),opts.output)
    print("Official Treasury matched observations:",d["observation_count"],d["start_date"],d["end_date"])
if __name__=="__main__":main()
