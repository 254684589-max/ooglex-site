#!/usr/bin/env python3
"""BLS official public API v1: CPI-U SA, unemployment SA, nonfarm payroll SA.
No market-data redistribution claims, no fabricated observation; failure is explicit.
"""
import json
import re
import urllib.request
from datetime import date, datetime, timezone
from pathlib import Path

API="https://api.bls.gov/publicAPI/v1/timeseries/data/"
SERIES={"cpi":"CUSR0000SA0","unemployment":"LNS14000000","payroll":"CES0000000001"}
FILE=Path(__file__).resolve().parents[1]/"data"/"asset-scores.json"

def parse_series(series):
    values={}
    for item in series.get("data",[]):
        year=str(item.get("year",""))
        period=str(item.get("period",""))
        if not re.fullmatch(r"\d{4}",year) or not re.fullmatch(r"M(0[1-9]|1[0-2])",period):
            continue
        try: value=float(str(item["value"]).replace(",",""))
        except (ValueError,TypeError,KeyError): continue
        values[f"{year}-{period[1:]}"]=value
    return dict(sorted(values.items()))

def fetch():
    payload=json.dumps({"seriesid":list(SERIES.values()),"startyear":str(date.today().year-2),"endyear":str(date.today().year)}).encode("utf-8")
    req=urllib.request.Request(API,data=payload,headers={"Content-Type":"application/json","User-Agent":"OoglexResearch/1.0"},method="POST")
    with urllib.request.urlopen(req,timeout=35) as resp:
        data=json.load(resp)
    if data.get("status")!="REQUEST_SUCCEEDED": raise RuntimeError("BLS API failed: "+str(data.get("message")))
    output={}
    for series in data.get("Results",{}).get("series",[]):
        sid=series.get("seriesID")
        for key,expected in SERIES.items():
            if sid==expected:output[key]=parse_series(series)
    if set(output)!=set(SERIES):raise ValueError("BLS response missing series")
    if len(output["cpi"])<13:raise ValueError("BLS CPI history shorter than 13 months")
    return output

def calculate(raw,today=None):
    today=today or date.today()
    records={}
    for key,series in raw.items():
        valid=[(day,val) for day,val in series.items() if day<=today.strftime("%Y-%m")]
        if not valid:raise ValueError("BLS empty or future-only series: "+key)
        last_period,last_val=valid[-1]
        last_y,last_m=map(int,last_period.split("-"))
        age=(today.year-last_y)*12+today.month-last_m
        if age>3:raise ValueError("BLS series stale: "+key)
        records[key]={"period":last_period,"value":last_val,"unit":{"cpi":"index","unemployment":"percent","payroll":"thousands"}[key],"source":"BLS"}
        if key=="cpi":
            prev_period=f"{last_y-1:04d}-{last_m:02d}"
            prior=series.get(prev_period)
            if prior is not None and prior>0:
                records[key]["yoy_percent"]=round((last_val/prior-1)*100,3)
        if key=="payroll":
            # One-month difference in thousands of jobs; it is not a level percentage.
            previous_month=f"{last_y-1:04d}-12" if last_m==1 else f"{last_y:04d}-{last_m-1:02d}"
            prior=series.get(previous_month)
            if prior is not None:records[key]["monthly_change_thousands"]=round(last_val-prior,1)
    return records

def main():
    records=calculate(fetch())
    if "yoy_percent" not in records["cpi"]:
        raise ValueError("BLS CPI year-over-year cannot be calculated from official data")
    if not FILE.exists():raise RuntimeError("Treasury snapshot missing; run Treasury first")
    data=json.loads(FILE.read_text(encoding="utf-8"))
    if data.get("schema_version")!=1:raise ValueError("Unsupported macro schema")
    data["bls"]={"series":records,"retrieved_at":datetime.now(timezone.utc).isoformat(),"source_url":API,
                 "note":"Preliminary data may be revised by BLS."}
    data["generated_at"]=datetime.now(timezone.utc).isoformat()
    FILE.write_text(json.dumps(data,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print("BLS observations:",{k:v["period"] for k,v in records.items()})
if __name__=="__main__":main()
