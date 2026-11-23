#!/usr/bin/env python3
"""Official NY Fed daily SOFR observation for the A-tier indicator directory.
This endpoint is historical overnight SOFR (NOT SOFR swaps/OIS forward rates).
A separately fetched source document is published only if validation passes.
"""
import argparse
import json
import math
import urllib.request
from datetime import date,datetime,timezone
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
URL="https://markets.newyorkfed.org/api/rates/secured/sofr/last/10.json"
OUTPUT=ROOT/"data"/"asset-compass-a10-sofr.json"

def parse(payload,*,today=None):
    today=today or datetime.now(timezone.utc).date()
    if not isinstance(payload,dict) or not isinstance(payload.get("refRates"),list):
        raise ValueError("Invalid NY Fed SOFR schema")
    observations=[]
    for row in payload["refRates"]:
        if not isinstance(row,dict) or row.get("type")!="SOFR":continue
        try:
            observed=date.fromisoformat(row["effectiveDate"])
            raw=row["percentRate"]
            if type(raw) not in (int,float,str) or isinstance(raw,str) and not raw.strip():continue
            value=float(raw)
        except (TypeError,ValueError,KeyError):continue
        if observed>today or not math.isfinite(value) or not -5<value<30:continue
        observations.append((observed,value))
    if not observations:raise ValueError("No valid official SOFR observation")
    observed,rate=max(observations)
    if (today-observed).days>10:raise ValueError("NY Fed SOFR source is stale")
    return {"schema_version":1,"report_type":"asset_compass_a10_sofr_observation",
            "source":"Federal Reserve Bank of New York",
            "source_url":URL,"observation_date":observed.isoformat(),
            "sofr_overnight_percent":rate,"unit":"percent",
            "sofr_forward_curve_available":False,
            "original_official_release_time_independently_verified":False,
            "eligible_for_point_in_time_backtest":False,
            "validated_for_live_scoring":False}
def main():
    p=argparse.ArgumentParser()
    p.add_argument("--output",type=Path,default=OUTPUT)
    args=p.parse_args()
    req=urllib.request.Request(URL,headers={"User-Agent":"OoglexResearch/1.0","Accept":"application/json"})
    with urllib.request.urlopen(req,timeout=30) as response:
        data=json.load(response)
    result=parse(data)
    result["retrieved_at"]=datetime.now(timezone.utc).isoformat()
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print("A10 NY Fed SOFR",result["observation_date"],result["sofr_overnight_percent"],
          "forwards unavailable; investment score closed")
if __name__=="__main__":main()
