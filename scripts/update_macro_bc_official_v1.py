#!/usr/bin/env python3
"""Public FRED mirror for eight non-ICE B/C macro indicator observations.
Each observation keeps unit, frequency, origin agency, observation period,
retrieval instant and fail-closed PIT flags. No asset scoring or fake interpolation.
"""
import argparse
import csv
import io
import json
import math
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
OUTPUT=ROOT/"data"/"asset-compass-bc-official-v1.json"
SPEC={
 "美国实际GDP增长率":("A191RL1Q225SBEA","BEA","quarterly","percent_annualized_qoq",160),
 "美元广义贸易加权指数":("DTWEXBGS","Federal Reserve Board","daily","index",12),
 "美国工业生产指数":("INDPRO","Federal Reserve Board","monthly","index",95),
 "美国零售销售":("RSAFS","US Census Bureau","monthly","millions_usd_sa",95),
 "美国初请失业金人数":("ICSA","US Department of Labor","weekly","persons_sa",20),
 "美国10Y－3M国债利差":("T10Y3M","Federal Reserve Board/Treasury","daily","percentage_points",12),
 "5Y5Y远期通胀补偿":("T5YIFR","Federal Reserve Board","daily","percent",12),
 "WTI原油现货价格":("DCOILWTICO","US Energy Information Administration","daily","usd_per_barrel",16),
}
def parse(raw,series_id,now,max_age_days):
    if not isinstance(raw,bytes) or not raw or len(raw)>2000000 or b"<html" in raw[:250].lower():
        raise ValueError("FRED response is not a bounded CSV")
    text=raw.decode("utf-8-sig")
    rd=csv.DictReader(io.StringIO(text))
    if not rd.fieldnames or not any(k in rd.fieldnames for k in ("DATE","observation_date")) or series_id not in rd.fieldnames:
        raise ValueError("Wrong FRED CSV header")
    rows=[]
    seen=set()
    for rec in rd:
        period=rec.get("DATE") or rec.get("observation_date") or ""
        try: day=datetime.strptime(period,"%Y-%m-%d").date()
        except ValueError:raise ValueError("Invalid FRED period date")
        if day in seen:raise ValueError("Duplicate FRED observation period")
        seen.add(day)
        if day>now.date():raise ValueError("FRED series contains a future observation")
        cell=str(rec.get(series_id) or "").strip()
        if not cell or cell==".":
            continue
        try: value=float(cell)
        except ValueError:raise ValueError("Nonnumeric FRED observation")
        if not math.isfinite(value) or abs(value)>100000000:
            raise ValueError("Nonfinite or implausibly large FRED value")
        rows.append({"date":day.isoformat(),"value":value})
    if not rows:raise ValueError("No populated FRED observations")
    rows.sort(key=lambda x:x["date"])
    age=(now.date()-datetime.strptime(rows[-1]["date"],"%Y-%m-%d").date()).days
    if age>max_age_days:raise ValueError("Last source observation stale")
    return rows[-260:],rows[-1],len(rows)

def fetch(url):
    req=urllib.request.Request(url,headers={"User-Agent":"OoglexResearch/1.0","Accept":"text/csv"})
    with urllib.request.urlopen(req,timeout=30) as r:
        return r.read(2000001)

def collect(fetcher=fetch,now=None):
    now=now or datetime.now(timezone.utc)
    if now.tzinfo is None:raise ValueError("timezone missing")
    out={}
    failures={}
    for name,(sid,agency,frequency,unit,max_age) in SPEC.items():
        params=urllib.parse.urlencode({"id":sid,"cosd":f"{now.year-4}-01-01","coed":now.date().isoformat()})
        url="https://fred.stlouisfed.org/graph/fredgraph.csv?"+params
        try:
            raw=fetcher(url)
            recent,last,total=parse(raw,sid,now,max_age)
            out[name]={
                "fred_series_id":sid,"source_url":url,
                "original_agency":agency,"retrieval_provider":"Federal Reserve Bank of St. Louis FRED",
                "frequency":frequency,"unit":unit,
                "observation_period":last["date"],"latest_value":last["value"],
                "observations":recent,"source_observation_count":total,
                "retrieved_at":now.isoformat(),
                "historical_release_vintages_verified":False,
                "validated_for_live_scoring":False}
        except (ValueError,UnicodeDecodeError,TimeoutError,OSError) as err:
            failures[name]={"series_id":sid,"error_type":type(err).__name__,
                            "status":"source_not_verified"}
    if not out:
        raise RuntimeError("No fresh independently validated macro sources; refusing empty replacement")
    return {"schema_version":1,"report_type":"asset_compass_bc_official_observations_v1",
            "generated_at":now.isoformat(),"series":out,"failed_sources":failures,
            "requested_series_count":len(SPEC),"accepted_series_count":len(out),
            "historical_pit_certified":False,"validated_for_live_scoring":False,
            "source_context":"FRED public access mirrors primary agencies; not the original publication vintage.",
            "redistribution_rights_independently_approved":False}
def main():
    p=argparse.ArgumentParser()
    p.add_argument("--output",type=Path,default=OUTPUT)
    args=p.parse_args()
    result=collect()
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print("Official-origin B/C sources",result["accepted_series_count"],"/",result["requested_series_count"],"failed",list(result["failed_sources"]))
if __name__=="__main__":main()
