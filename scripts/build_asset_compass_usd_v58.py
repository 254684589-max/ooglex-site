#!/usr/bin/env python3
"""V58 Federal Reserve H.10 broad dollar index and six-asset evidence gate.

Public H.10 latest-revised historical index (via FRED), NOT USD total return.
No original release-vintage proof, verified price direction or live model score.
"""
from __future__ import annotations
import argparse
import csv
import zipfile
import xml.etree.ElementTree as ET
import hashlib
import io
import json
import math
import statistics
import time
import urllib.parse
import urllib.request
from datetime import date, datetime, timezone
from pathlib import Path

from scripts.score_macro_assets import score_one, validate_config

ROOT=Path(__file__).resolve().parents[1]
URL="https://fred.stlouisfed.org/graph/fredgraph.csv?id=DTWEXBGS&cosd=2021-01-01"
FED_XML_URL="https://www.federalreserve.gov/releases/h10/data/FRB_h10_xml.zip"
FED_SERIES="JRXWTFB_N.B"
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



def parse_fed_xml(raw:bytes):
    """Parse only FRB H10 JRXWTFB_N.B daily values, never a different index."""
    result=[]
    with zipfile.ZipFile(io.BytesIO(raw)) as archive:
        files=[name for name in archive.namelist() if name.lower().endswith(".xml")
               and not name.startswith("__MACOSX/")]
        if not files or len(files)>20:
            raise ValueError("Unexpected Federal Reserve H10 XML archive files")
        for name in files:
            if archive.getinfo(name).file_size>400_000_000:
                raise ValueError("Unbounded official H10 XML member")
            with archive.open(name) as fp:
                active=False
                series_depth=0
                for event,element in ET.iterparse(fp,events=("start","end")):
                    tag=element.tag.split("}")[-1]
                    if event=="start" and tag=="Series":
                        series_depth+=1
                        attrs={k.split("}")[-1].upper():str(v) for k,v in element.attrib.items()}
                        active=FED_SERIES in attrs.values()
                    # Some SDMX exports encode the series identifier in
                    # nested SeriesKey/Value elements, not Series attributes.
                    if event=="start" and tag=="Value" and series_depth:
                        attrs={k.split("}")[-1].upper():str(v) for k,v in element.attrib.items()}
                        if attrs.get("ID","").upper()=="SERIES_NAME" and attrs.get("VALUE")==FED_SERIES:
                            active=True
                    if event=="end" and tag=="Obs" and active:
                        attrs={k.split("}")[-1].upper():str(v) for k,v in element.attrib.items()}
                        day=attrs.get("TIME_PERIOD")
                        val=attrs.get("OBS_VALUE")
                        if day and val and val not in (".","NaN","nan",""):
                            dt=date.fromisoformat(day)
                            value=float(val)
                            if not math.isfinite(value) or not 20<value<400:
                                raise ValueError(f"Invalid Federal Reserve XML dollar-index value: date={dt}, raw={val}, status={attrs.get('OBS_STATUS')}")
                            result.append({"date":dt.isoformat(),"index":value})
                    if event=="end" and tag=="Series":
                        active=False
                        series_depth=max(0,series_depth-1)
                    if event=="end":
                        element.clear()
    if len(result)<310:
        raise ValueError("Federal Reserve H10 nominal broad index missing in XML")
    result=sorted(result,key=lambda x:x["date"])
    if len({x["date"] for x in result})!=len(result):
        raise ValueError("Duplicate FRB H10 broad index date across XML")
    return result

def retrieve_fed_xml(*,opener=None):
    opener=opener or urllib.request.urlopen
    request=urllib.request.Request(FED_XML_URL,
                                  headers={"User-Agent":"Ooglex-AssetCompass-Research/1.0"})
    with opener(request,timeout=50) as response:
        actual=urllib.parse.urlsplit(response.geturl())
        if actual.scheme!="https" or actual.hostname!="www.federalreserve.gov":
            raise ValueError("Unapproved Federal Reserve XML redirect")
        raw=response.read(34_000_001)
    if not 500< len(raw)<=34_000_000:
        raise ValueError("Invalid official Federal Reserve H10 ZIP size")
    return raw

def retrieve(*,opener=None):
    opener=opener or urllib.request.urlopen
    request=urllib.request.Request(URL,headers={"User-Agent":"Ooglex-AssetCompass-Research/1.0"})
    # The FRED CSV graph endpoint occasionally stalls on GitHub Actions
    # before response headers; bounded retries must NEVER substitute a
    # generated series or mark stale historical values as current.
    errors=[]
    for attempt in range(3):
        try:
            with opener(request,timeout=18) as response:
                actual=urllib.parse.urlsplit(response.geturl())
                if actual.scheme!="https" or actual.hostname!="fred.stlouisfed.org":
                    raise ValueError("Unapproved source or redirect")
                result=response.read(2_000_001)
                if len(result)>2_000_000 or len(result)<100:
                    raise ValueError("Empty or unbounded source")
                return result
        except (OSError,TimeoutError) as exc:
            errors.append(type(exc).__name__)
            if attempt<2:
                print("Official FRED H10 request transient failure:",type(exc).__name__,
                      "attempt",attempt+1,"/3; retrying",flush=True)
                time.sleep(3*(attempt+1))
    raise ConnectionError("Official H10 source unavailable after 3 bounded HTTPS attempts: "+
                          ",".join(errors))


def build(rows,config,*,raw_sha,source_kind="fred_csv",now=None):
    now=now or datetime.now(timezone.utc)
    if now.tzinfo is None or now.utcoffset() is None:
        raise ValueError("UTC-aware verification clock required")
    now=now.astimezone(timezone.utc)
    validate_config(config)
    if source_kind not in ("fred_csv","fed_original_xml"):
        raise ValueError("Unrecognized authentic H10 source form")
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
      "distribution_channel":"FRED (Federal Reserve Bank of St. Louis)" if source_kind=="fred_csv" else "Federal Reserve Board original H10 SDMX ZIP",
      "source_url":URL if source_kind=="fred_csv" else FED_XML_URL,
      "citation_url":"https://fred.stlouisfed.org/series/DTWEXBGS" if source_kind=="fred_csv" else "https://www.federalreserve.gov/releases/h10/",
      "original_source_format":source_kind,
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
    source_kind="fred_csv"
    if a.fetch:
        # Official original FRB SDMX ZIP is preferred: it succeeds on
        # GitHub-hosted runners where the FRED graph CSV intermittently hangs.
        # FRED is an independent public mirror, never an imputed fallback.
        try:
            data=retrieve_fed_xml()
            rows=parse_fed_xml(data)
            source_kind="fed_original_xml"
        except (OSError,ConnectionError,TimeoutError,UnicodeError,zipfile.BadZipFile) as exc:
            print("Original FRB H10 source unavailable; attempting approved FRED mirror:",
                  type(exc).__name__,str(exc)[:250],flush=True)
            data=retrieve()
            rows=parse_csv(data)
            source_kind="fred_csv"
    else:
        data=a.csv.read_bytes()
        rows=parse_csv(data)
    config=json.loads(MODEL.read_text(encoding="utf-8"))
    result=build(rows,config,raw_sha=hashlib.sha256(data).hexdigest(),source_kind=source_kind)
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
