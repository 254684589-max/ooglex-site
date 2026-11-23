#!/usr/bin/env python3
"""V58 Federal Reserve H.10 broad dollar index and six-asset evidence gate.

Public H.10 latest-revised historical index (via FRED), NOT USD total return.
No original release-vintage proof, verified price direction or live model score.
"""
from __future__ import annotations
import argparse
import csv
import hashlib
import io
import json
import math
import statistics
import urllib.parse
import urllib.request
from datetime import date, datetime, timezone
from pathlib import Path

from scripts.score_macro_assets import score_one, validate_config

ROOT=Path(__file__).resolve().parents[1]
URL="https://fred.stlouisfed.org/graph/fredgraph.csv?id=DTWEXBGS&cosd=2021-01-01"
OUTPUT=ROOT/"data/asset-compass-usd-h10-v58.json"
MODEL=ROOT/"macro/model-config.json"


def parse_csv(data):
    reader=csv.DictReader(io.StringIO(data.decode("utf-8-sig")))
    if reader.fieldnames not in (["DATE","DTWEXBGS"],["observation_date","DTWEXBGS"]):
        raise ValueError("Required Federal Reserve H10 series header missing")
    observed=[];last=None
    for raw in reader:
        if not raw.get(reader.fieldnames[0]):
            raise ValueError("Missing H10 observation date")
        day=date.fromisoformat(raw[reader.fieldnames[0]])
        if last is not None and day<=last:
            raise ValueError("Unsorted or duplicate official dates")
        last=day
        val=raw["DTWEXBGS"]
        if val==".":
            continue
        if val is None or not val:
            raise ValueError("Missing dollar-index value")
        value=float(val)
        if not math.isfinite(value) or not 20<value<400:
            raise ValueError("Invalid dollar index value")
        observed.append({"date":day.isoformat(),"index":value})
    if len(observed)<310:
        raise ValueError("Insufficient actual H10 historical observations")
    return observed


def retrieve(*,opener=None):
    opener=opener or urllib.request.urlopen
    request=urllib.request.Request(URL,headers={"User-Agent":"Ooglex-AssetCompass-Research/1.0"})
    with opener(request,timeout=35) as response:
        actual=urllib.parse.urlsplit(response.geturl())
        if actual.scheme!="https" or actual.hostname!="fred.stlouisfed.org":
            raise ValueError("Unapproved source or redirect")
        result=response.read(2_000_001)
        if len(result)>2_000_000 or len(result)<100:
            raise ValueError("Empty or unbounded source")
        return result


def build(rows,config,*,raw_sha,now=None):
    now=now or datetime.now(timezone.utc)
    if now.tzinfo is None or now.utcoffset() is None:
        raise ValueError("UTC-aware verification clock required")
    now=now.astimezone(timezone.utc)
    validate_config(config)
    if not isinstance(raw_sha,str) or len(raw_sha)!=64 or any(c not in "0123456789abcdef" for c in raw_sha):
        raise ValueError("Source digest absent")
    if len(rows)<310 or len(rows)!=len({r["date"] for r in rows}):
        raise ValueError("History incomplete or duplicate")
    if any(date.fromisoformat(r["date"])>now.date() for r in rows):
        raise ValueError("Future H10 observation prohibited")
    latest=rows[-1];last_day=date.fromisoformat(latest["date"]);age=(now.date()-last_day).days
    # Model asset USD is a trade-weighted INDEX proxy, not a verified investable position.
    current=latest["index"]
    delta_21=current-rows[-22]["index"]
    change_pct=(current/rows[-22]["index"]-1)*100
    # The final current 21-session change is excluded from the earlier 252 baselines.
    baselines=[(rows[i]["index"]/rows[i-21]["index"]-1)*100
               for i in range(len(rows)-253,len(rows)-1)]
    mean=statistics.fmean(baselines);std=statistics.pstdev(baselines,mu=mean)
    z=(change_pct-mean)/std if std>1e-10 else None
    blocked=score_one("usd",{"asset_specific":{
        "signal":math.tanh(z/2) if z is not None else None,
        "verified":False,"fresh":age<=16,
        "observation_date":latest["date"]}},config,{})
    if blocked["score"] is not None or blocked["status"]!="unavailable":
        raise ValueError("Unapproved H10 research escaped score gate")
    return {
      "schema_version":1,"report_type":"asset_compass_v58_fed_h10_usd_research",
      "generated_at":now.isoformat(),"source_series_id":"DTWEXBGS",
      "source_owner":"Board of Governors of the Federal Reserve System",
      "distribution_channel":"FRED (Federal Reserve Bank of St. Louis)",
      "source_url":URL,"citation_url":"https://fred.stlouisfed.org/series/DTWEXBGS",
      "raw_source_sha256":raw_sha,"observation_count":len(rows),
      "first_observation_date":rows[0]["date"],"latest_observation_date":latest["date"],
      "latest_index":current,"index_base":"January 2006 = 100",
      "daily_observed_last_21_session_change_points":round(delta_21,6),
      "daily_observed_last_21_session_change_percent":round(change_pct,6),
      "prior_baseline_count":len(baselines),"prior_baseline_mean_pct":round(mean,6),
      "prior_baseline_std_pct":round(std,6),
      "research_z_score":round(z,6) if z is not None else None,
      "research_normalized_candidate":round(math.tanh(z/2),6) if z is not None else None,
      "observed_calendar_days_old":age,"fresh_for_research":0<=age<=16,
      "recent_observations":rows[-260:],
      "asset_id":"usd","asset_specific_source_observed":True,
      "historical_first_publication_vintages_verified":False,
      "independent_signal_verified":False,"sample_out_of_sample_calibration_passed":False,
      "validated_for_live_scoring":False,"eligible_for_point_in_time_backtest":False,
      "official_asset_score":None,"blocked_by":blocked["blocked_by"],
      "license_classification":"Federal Reserve public domain, citation requested; FRED attribution",
      "limitations":[
         "Daily nominal trade-weighted exchange value is NOT a USD asset total return or FX carry-adjusted investment.",
         "Series is latest-revised and FRED updates can lag original Federal Reserve H10 publication.",
         "Broad index may overlap rates and liquidity; not independent directional factor certification.",
         "Historical z and tanh are descriptive, not return forecasts or trade advice.",
      ]
    }


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--fetch",action="store_true")
    p.add_argument("--csv",type=Path)
    p.add_argument("--output",type=Path,default=OUTPUT)
    a=p.parse_args()
    if a.fetch==bool(a.csv):
        p.error("Choose exactly --fetch OR --csv real downloaded source")
    data=retrieve() if a.fetch else a.csv.read_bytes()
    config=json.loads(MODEL.read_text(encoding="utf-8"))
    result=build(parse_csv(data),config,raw_sha=hashlib.sha256(data).hexdigest())
    a.output.parent.mkdir(parents=True,exist_ok=True)
    a.output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(json.dumps({"status":"research_only","observations":result["observation_count"],
      "latest_day":result["latest_observation_date"],"latest_index":result["latest_index"],
      "usd_approved_score":result["official_asset_score"],"z":result["research_z_score"]},
      ensure_ascii=False))
    if not result["fresh_for_research"]:
        raise SystemExit("H10 source stale; research file retained but cannot be current")


if __name__=="__main__":
    main()
