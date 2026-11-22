#!/usr/bin/env python3
"""V15 official Treasury CSV acquisition evidence (NOT original PIT vintages).

Capture actual fetched response bytes privately as workflow artifacts and publish
only SHA256, source URLs, observation periods, and three last-date readings.
HTTP Date/Last-Modified/ETag are server metadata, NOT official release times.
Downloading an old CSV today cannot prove which values were originally published.
"""
import argparse
import csv
import hashlib
import io
import json
import math
import re
import urllib.parse
import urllib.request
from datetime import date, datetime, timezone
from pathlib import Path

BASE="https://home.treasury.gov/resource-center/data-chart-center/interest-rates/daily-treasury-rates.csv/"
KINDS={"nominal":"daily_treasury_yield_curve","real":"daily_treasury_real_yield_curve"}
FIELDS={"treasury.us2y":("nominal","2yr"),"treasury.us10y":("nominal","10yr"),
        "treasury.real10y":("real","10yr")}
ROOT=Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT=ROOT/"data"/"asset-compass-treasury-source-evidence-v15.json"

def url_for(kind,year):
    if kind not in KINDS or type(year) is not int or not 2003<=year<=date.today().year:
        raise ValueError("Invalid official Treasury curve type/year")
    params=urllib.parse.urlencode({"type":KINDS[kind],"field_tdr_date_value":str(year),"page":"","_format":"csv"})
    return BASE+str(year)+"/all?"+params

def parse_csv(raw,kind,year):
    if not isinstance(raw,bytes) or not raw or len(raw)>4000000 or b"<html" in raw[:500].lower():
        raise ValueError("Missing/invalid Treasury CSV bytes")
    content=raw.decode("utf-8-sig")
    reader=csv.DictReader(io.StringIO(content))
    if not reader.fieldnames:
        raise ValueError("Treasury CSV column header missing")
    normalized={re.sub("[^a-z0-9]","",k.lower()):k for k in reader.fieldnames}
    if "date" not in normalized or "10yr" not in normalized or (kind=="nominal" and "2yr" not in normalized):
        raise ValueError("Required Treasury date/maturity columns missing")
    records={}
    for row in reader:
        value=str(row[normalized["date"]]).strip()
        observed=None
        for fmt in ("%m/%d/%Y","%Y-%m-%d","%m/%d/%y"):
            try:observed=datetime.strptime(value,fmt).date();break
            except ValueError:pass
        if observed is None or observed.year!=year:raise ValueError("Bad or out-of-year Treasury observation")
        if observed in records:raise ValueError("Duplicate Treasury observation period")
        vals={}
        for field in (("10yr","2yr") if kind=="nominal" else ("10yr",)):
            cell=str(row.get(normalized[field]) or "").strip()
            if not cell or cell.upper() in ("N/A","NA"):
                vals[field]=None
                continue
            try:v=float(cell.replace(",",""))
            except ValueError:raise ValueError("Non-numeric Treasury yield")
            if not math.isfinite(v) or not -10<v<40:raise ValueError("Out-of-range yield")
            vals[field]=v
        records[observed.isoformat()]=vals
    if not records:raise ValueError("Treasury CSV contains no observations")
    return records

def collect(year,fetcher,seen_at):
    now=datetime.fromisoformat(seen_at.replace("Z","+00:00"))
    if now.tzinfo is None:raise ValueError("Timestamp needs UTC offset")
    now=now.astimezone(timezone.utc)
    if year>now.year:raise ValueError("Cannot fetch future-year evidence")
    receipts=[]
    originals={}
    for kind in ("nominal","real"):
        url=url_for(kind,year)
        raw,headers=fetcher(url)
        values=parse_csv(raw,kind,year)
        digest=hashlib.sha256(raw).hexdigest()
        originals[kind]=values
        receipts.append({
          "type":kind,"source_url":url,
          "sha256":digest,"bytes":len(raw),
          "observation_rows":len(values),
          "earliest_observation_date":min(values),
          "latest_observation_date":max(values),
          "retrieved_at":now.isoformat(),
          "http_date_unverified_publication_time":headers.get("Date"),
          "http_last_modified_unverified_publication_time":headers.get("Last-Modified"),
          "etag_transport_metadata_only":headers.get("ETag"),
          "original_release_time_verified":False,
        })
    dates=sorted(set(originals["nominal"]) & set(originals["real"]))
    observations=[]
    for period in dates:
        n,r=originals["nominal"][period],originals["real"][period]
        if all(n.get(k) is not None for k in ("2yr","10yr")) and r.get("10yr") is not None:
            observations.append((period,n["2yr"],n["10yr"],r["10yr"]))
    if not observations:raise ValueError("No paired official Treasury three-series date")
    latest=observations[-1]
    report={
      "schema_version":1,"report_type":"asset_compass_v15_treasury_raw_source_evidence",
      "year":year,"retrieved_at":now.isoformat(),
      "source":"U.S. Department of the Treasury",
      "source_receipts":receipts,
      "matched_three_series_observation_days":len(observations),
      "latest_matched_observation":{"date":latest[0],"treasury.us2y":latest[1],
                                    "treasury.us10y":latest[2],"treasury.real10y":latest[3]},
      "historical_raw_source_content_sha256_captured":True,
      "original_publication_time_verified":False,
      "original_release_vintages_verified":False,
      "historical_value_revision_chain_verified":False,
      "historical_redistribution_rights_verified":False,
      "eligible_for_point_in_time_backtest":False,
      "validated_for_live_scoring":False,
      "private_raw_csv_kept_out_of_public_site":True,
      "note":"Downloaded official historical CSV responses are retrieval-time artifacts, not a certified reconstruction of previously available data. HTTP response headers do not establish first publication time.",
    }
    return report

def live_fetch(url):
    req=urllib.request.Request(url,headers={"User-Agent":"OoglexResearch-V15/1.0 (+https://www.ooglex.com/)","Cache-Control":"no-cache"})
    with urllib.request.urlopen(req,timeout=40) as response:
        if response.status!=200:raise ValueError("Treasury source HTTP status not 200")
        raw=response.read(4000001)
        headers={name:response.headers.get(name) for name in ("Date","Last-Modified","ETag")}
    return raw,headers

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--year",type=int,default=date.today().year)
    p.add_argument("--output",type=Path,default=DEFAULT_OUTPUT)
    p.add_argument("--artifact-dir",type=Path,default=Path("/tmp/ooglex-treasury-v15-raw"))
    a=p.parse_args()
    responses={}
    def capture(url):
        body,headers=live_fetch(url)
        kind="real" if "type=daily_treasury_real_yield_curve" in url else "nominal"
        responses[kind]=body
        return body,headers
    report=collect(a.year,capture,datetime.now(timezone.utc).isoformat())
    if a.artifact_dir.resolve().is_relative_to(ROOT.resolve()):
        raise ValueError("Raw official CSV artifact must stay outside public website repo")
    a.artifact_dir.mkdir(parents=True,exist_ok=True)
    for kind,raw in responses.items():
        (a.artifact_dir/f"{a.year}-{kind}.csv").write_bytes(raw)
    a.output.parent.mkdir(parents=True,exist_ok=True)
    a.output.write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(json.dumps({"matched_days":report["matched_three_series_observation_days"],
                      "receipts":[x["sha256"] for x in report["source_receipts"]],
                      "pit_verified":False},ensure_ascii=False))
if __name__=="__main__":main()
