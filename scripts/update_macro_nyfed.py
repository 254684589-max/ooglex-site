#!/usr/bin/env python3
"""Retrieve effective federal funds rate from the Federal Reserve Bank of New York."""
import json
import math
import urllib.request
from datetime import date, datetime, timezone
from pathlib import Path

URL="https://markets.newyorkfed.org/api/rates/unsecured/effr/last/10.json"
FILE=Path(__file__).resolve().parents[1]/"data"/"asset-scores.json"

def parse_response(payload,today=None):
    today=today or date.today()
    observations=[]
    for item in payload.get("refRates",[]):
        if item.get("type")!="EFFR": continue
        try:
            d=date.fromisoformat(item["effectiveDate"])
            rate=float(item["percentRate"])
            floor=float(item["targetRateFrom"])
            ceiling=float(item["targetRateTo"])
        except (ValueError,KeyError,TypeError):continue
        if d>today or not all(map(math.isfinite,(rate,floor,ceiling))):continue
        if not (0<=rate<=30 and 0<=floor<=ceiling<=30):continue
        observations.append((d,rate,floor,ceiling))
    if not observations:raise ValueError("No valid NY Fed EFFR observations")
    d,rate,floor,ceiling=max(observations)
    if (today-d).days>10:raise ValueError("NY Fed EFFR observation stale")
    return {"observation_date":d.isoformat(),"effr_percent":rate,
            "target_range_lower":floor,"target_range_upper":ceiling,
            "source":"Federal Reserve Bank of New York","source_url":URL}

def main():
    req=urllib.request.Request(URL,headers={"User-Agent":"OoglexResearch/1.0"})
    with urllib.request.urlopen(req,timeout=35) as r:payload=json.load(r)
    record=parse_response(payload)
    if not FILE.exists():raise RuntimeError("Treasury snapshot missing")
    data=json.loads(FILE.read_text(encoding="utf-8"))
    if data.get("schema_version")!=1:raise ValueError("Unexpected macro schema")
    data["nyfed"]=record
    data["generated_at"]=datetime.now(timezone.utc).isoformat()
    FILE.write_text(json.dumps(data,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print("NY Fed EFFR updated:",record["observation_date"])
if __name__=="__main__":main()
