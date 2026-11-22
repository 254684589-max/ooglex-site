#!/usr/bin/env python3
"""V42 public Treasury history chart quality gate; not original PIT vintage."""
import argparse
import json
import math
from datetime import date, datetime, timezone
from pathlib import Path
from urllib.parse import parse_qs, urlparse

SERIES=("us10y","us2y","real10y","breakeven10y","spread10y2y")

def validate(document,minimum=100,now=None):
    if not isinstance(document,dict) or document.get("schema_version")!=1:
        raise ValueError("Treasury chart: schema must be 1")
    if document.get("dataset")!="treasury_historical_daily_observations":
        raise ValueError("Treasury chart: wrong dataset")
    if document.get("source")!="U.S. Department of the Treasury":
        raise ValueError("Treasury chart: source not official")
    if document.get("original_release_vintages_available") is not False or document.get("not_valid_for_point_in_time_backtest") is not True:
        raise ValueError("Treasury chart: PIT disclaimer must remain locked")
    now=now or datetime.now(timezone.utc)
    retrieved=datetime.fromisoformat(document["retrieved_at"].replace("Z","+00:00"))
    if retrieved.tzinfo is None or retrieved.astimezone(timezone.utc)>now:
        raise ValueError("Treasury chart: invalid retrieval time")
    urls=document.get("source_urls")
    if not isinstance(urls,list) or not urls or len(urls)>40:
        raise ValueError("Treasury chart: official source URLs required")
    kinds=set()
    for source in urls:
        parsed=urlparse(source)
        query=parse_qs(parsed.query)
        year=query.get("field_tdr_date_value",[""])[0]
        kind=query.get("type",[""])[0]
        if (parsed.scheme!="https" or parsed.hostname!="home.treasury.gov"
            or parsed.username is not None or parsed.password is not None
            or kind not in ("daily_treasury_yield_curve","daily_treasury_real_yield_curve")
            or not year.isdigit() or f"/{year}/all" not in parsed.path):
            raise ValueError("Treasury chart: forged source link")
        kinds.add(kind)
    if len(kinds)!=2:
        raise ValueError("Treasury chart: nominal and TIPS sources both required")
    observations=document.get("observations")
    if not isinstance(observations,list) or len(observations)<minimum or len(observations)>10000:
        raise ValueError("Treasury chart: insufficient or excessive observations")
    if document.get("observation_count")!=len(observations):
        raise ValueError("Treasury chart: incorrect observation count")
    last=None
    for item in observations:
        if not isinstance(item,dict) or any(k not in item for k in ("date",*SERIES)):
            raise ValueError("Treasury chart: missing record field")
        day=date.fromisoformat(item["date"])
        if last is not None and day<=last:
            raise ValueError("Treasury chart: unsorted or duplicate dates")
        if day>now.date():
            raise ValueError("Treasury chart: future observation date")
        last=day
        for k in SERIES:
            v=item[k]
            if type(v) not in (int,float) or not math.isfinite(v) or not -15<v<30:
                raise ValueError("Treasury chart: invalid yield")
        if abs((item["us10y"]-item["real10y"])-item["breakeven10y"])>0.0011:
            raise ValueError("Treasury chart: invalid breakeven arithmetic")
        if abs((item["us10y"]-item["us2y"])-item["spread10y2y"])>0.0011:
            raise ValueError("Treasury chart: invalid 10Y−2Y arithmetic")
    if document.get("start_date")!=observations[0]["date"] or document.get("end_date")!=observations[-1]["date"]:
        raise ValueError("Treasury chart: date range mismatch")
    return {"source":"US Treasury","observations":len(observations),"start":document["start_date"],
            "end":document["end_date"],"historical_pit_approved":False,
            "safe_for_observational_chart":True}

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--input",type=Path,default=Path("data/asset-compass-treasury-history.json"))
    parser.add_argument("--minimum",type=int,default=100)
    args=parser.parse_args()
    print(json.dumps(validate(json.loads(args.input.read_text(encoding="utf-8")),args.minimum),ensure_ascii=False))

if __name__=="__main__":
    main()
