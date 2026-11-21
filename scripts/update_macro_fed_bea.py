#!/usr/bin/env python3
"""BEA core PCE and Federal Reserve H.4.1 observations mirrored by FRED.

Uses FRED public graph CSV for BEA PCEPILFE and Federal Reserve WALCL.
The CSV is the latest revised series, NOT a point-in-time release vintage.
Failure does not inject placeholder values or approve live asset scores.
"""
import csv
import io
import json
import math
import urllib.request
from datetime import date, datetime, timezone
from pathlib import Path

FILE=Path(__file__).resolve().parents[1]/"data"/"asset-scores.json"
SERIES={
 "core_pce":("PCEPILFE","Bureau of Economic Analysis","index","monthly"),
 "fed_balance_sheet":("WALCL","Federal Reserve Board (H.4.1)","millions_usd","weekly"),
}
BASE="https://fred.stlouisfed.org/graph/fredgraph.csv?id="

def parse_csv(body,series_id,today=None):
    today=today or date.today()
    rows=csv.DictReader(io.StringIO(body.lstrip("\ufeff")))
    if rows.fieldnames is None or series_id not in rows.fieldnames or "observation_date" not in rows.fieldnames and "DATE" not in rows.fieldnames:
        raise ValueError("Unexpected FRED CSV headers for "+series_id)
    date_key="observation_date" if "observation_date" in rows.fieldnames else "DATE"
    records={}
    for row in rows:
        try:
            d=date.fromisoformat(row[date_key])
            v=float(row[series_id])
        except (TypeError,ValueError,KeyError):
            continue
        if d>today or not math.isfinite(v) or v<=0:continue
        records[d]=v
    if not records:raise ValueError("No valid "+series_id+" observations")
    return records

def calculate(pce,walcl,today=None):
    today=today or date.today()
    latest_pce=max(pce)
    latest_walcl=max(walcl)
    if (today.year-latest_pce.year)*12+today.month-latest_pce.month>4:
        raise ValueError("Core PCE source stale")
    if (today-latest_walcl).days>21:
        raise ValueError("Fed H.4.1 source stale")
    pce_level=pce[latest_pce]
    year_prior=pce.get(date(latest_pce.year-1,latest_pce.month,1))
    core={"observation_period":latest_pce.strftime("%Y-%m"),"value":pce_level,
          "unit":"index","source":"Bureau of Economic Analysis via FRED","source_url":BASE+"PCEPILFE",
          "original_source_url":"https://www.bea.gov/data/personal-consumption-expenditures-price-index",
          "source_series_id":"PCEPILFE","release_timestamp_verified":False}
    if year_prior is not None and year_prior>0:
        core["yoy_percent"]=round((pce_level/year_prior-1)*100,3)
    else:core["yoy_unavailable_reason"]="official_reference_month_missing"
    h41={"observation_date":latest_walcl.isoformat(),"value_millions_usd":walcl[latest_walcl],
         "unit":"millions_usd","source":"Federal Reserve Board H.4.1 via FRED",
         "source_url":BASE+"WALCL",
         "original_source_url":"https://www.federalreserve.gov/releases/h41/",
         "source_series_id":"WALCL","release_timestamp_verified":False}
    return core,h41

def fetch(series_id):
    url=BASE+series_id
    req=urllib.request.Request(url,headers={"User-Agent":"Mozilla/5.0 OoglexResearch/1.0"})
    with urllib.request.urlopen(req,timeout=40) as r:
        body=r.read(9000000).decode("utf-8-sig")
    if "<html" in body.lower()[:100]:raise ValueError("Unexpected HTML response")
    return parse_csv(body,series_id),url

def main():
    core,_=fetch("PCEPILFE")
    assets,_=fetch("WALCL")
    pce,h41=calculate(core,assets)
    if not FILE.is_file():raise ValueError("Treasury snapshot missing")
    data=json.loads(FILE.read_text(encoding="utf-8"))
    if data.get("schema_version")!=1:raise ValueError("Invalid macro snapshot schema")
    data["bea"]={"core_pce":pce,"retrieved_at":datetime.now(timezone.utc).isoformat()}
    data["fed_h41"]={"total_assets":h41,"retrieved_at":datetime.now(timezone.utc).isoformat()}
    data["generated_at"]=datetime.now(timezone.utc).isoformat()
    FILE.write_text(json.dumps(data,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print("BEA core PCE:",pce["observation_period"],"Fed H41:",h41["observation_date"])
if __name__=="__main__":main()
