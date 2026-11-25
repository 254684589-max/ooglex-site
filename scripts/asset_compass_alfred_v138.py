#!/usr/bin/env python3
"""V138: ALFRED date-level vintage evidence against archived BLS headlines.

Graph CSV is a public download interface, not a guarantee of API stability.
A dated vintage is NOT a certified exact release clock, original bytes, or
production approval. No raw levels or returns are uploaded.
"""
import argparse
import csv
import hashlib
import io
import json
import re
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal
from pathlib import Path
from scripts.capture_asset_compass_official_v51 import _private_path,NoRedirect
from scripts.asset_compass_monthly_diagnostic_v69 import prev

HOST="alfred.stlouisfed.org"
BASE="https://"+HOST+"/graph/alfredgraph.csv"
BATCH=6
START="2021-01-01"
MAX_BYTES=2_500_000
MAPPING={
 ("bls.cpi","headline_yoy_rate"):"CPIAUCNS",
 ("bls.unemployment","monthly_unemployment_rate"):"UNRATE",
 ("bls.payroll","monthly_payroll_change"):"PAYEMS",
}
BOUNDS={"CPIAUCNS":(Decimal(0),Decimal(1000)),
        "UNRATE":(Decimal(-1),Decimal(100)),
        "PAYEMS":(Decimal(0),Decimal(300000))}
# Keep the BLS crosscheck registry separate from the model registry.
MODEL_BOUNDS={**BOUNDS,
    "DGS10":(Decimal("-5"),Decimal("30")),
    "DTWEXBGS":(Decimal(0),Decimal(1000)),
    "NFCI":(Decimal("-20"),Decimal("20")),
    "WALCL":(Decimal(0),Decimal(100000000))}
FREQUENCIES={"DGS10":"daily","DTWEXBGS":"daily","NFCI":"friday","WALCL":"wednesday"}
STATUSES=("within_reported_rounding","different_vintage_value","vintage_value_missing")

def candidates(records):
    out=[];seen=set()
    for r in records:
        if r["reissue_notice_detected"] or r["header"]["header_status"]!="publisher_header_matches_archive_date":
            continue
        src=r["source"];p=src["observation_period"]
        release=date.fromisoformat(src["scheduled_release_date_candidate_unverified"])
        stamp=datetime.fromisoformat(r["header"]["publisher_stated_embargo_utc"])
        if stamp.tzinfo is None or stamp.astimezone(timezone.utc).date()!=release:
            raise ValueError("Archive release clock mismatch")
        # Next calendar day, not intraday. Don't assume the publisher's
        # embargo time was the timestamp of actual historical dissemination.
        cutoff=release+timedelta(days=1)
        if cutoff>=datetime.now(timezone.utc).date() or release<=date.fromisoformat(p+"-01"):
            raise ValueError("Invalid archive vintage date")
        for m in r["metrics"]:
            sid=MAPPING.get((m["source_series_id"],m["statistic"]))
            if sid is None:continue
            if ((sid,p) in seen or m["observation_period"]!=p or
                m["source_document_sha256"]!=r["sha256"] or
                not re.fullmatch(r"[0-9a-f]{64}",r["sha256"])):
                raise ValueError("Duplicate or mismatched archive metric")
            v=Decimal(m["value_reported"])
            if not v.is_finite():raise ValueError("Nonfinite archive metric")
            seen.add((sid,p))
            out.append({"series":sid,"period":p,"vintage":cutoff.isoformat(),
                        "archive_value":v,"archive_sha256":r["sha256"]})
    return sorted(out,key=lambda x:(x["series"],x["vintage"],x["period"]))

def url_for(sid,vintages,*,start=START):
    if start not in (START,"2020-01-01"):raise ValueError("Unsupported research start date")
    if sid not in MODEL_BOUNDS or not 1<=len(vintages)<=BATCH or len(set(vintages))!=len(vintages):
        raise ValueError("Unsupported vintage batch")
    if any(date.fromisoformat(v).isoformat()!=v or date.fromisoformat(v)>=datetime.now(timezone.utc).date() for v in vintages):
        raise ValueError("Invalid vintage dates")
    return BASE+"?"+urllib.parse.urlencode({"id":",".join([sid]*len(vintages)),
        "vintage_date":",".join(vintages),"cosd":",".join([start]*len(vintages))})

def fetch(url):
    req=urllib.request.Request(url,headers={"User-Agent":"Ooglex-AssetCompass-Research/1.0","Accept":"text/csv"})
    with urllib.request.build_opener(NoRedirect()).open(req,timeout=45) as r:
        if r.geturl()!=url:raise ValueError("Unexpected ALFRED source URL")
        raw=r.read(MAX_BYTES+1)
    if not raw or len(raw)>MAX_BYTES:raise ValueError("Empty or excessive ALFRED response")
    return raw

def parse(raw,sid,vintages):
    if sid not in MODEL_BOUNDS:raise ValueError("Unknown ALFRED series")
    freq=FREQUENCIES.get(sid,"monthly")
    reader=csv.reader(io.StringIO(raw.decode("utf-8-sig")))
    header=next(reader,None)
    columns=[sid+"_"+v.replace("-","") for v in vintages]
    if not header or header[0] not in ("DATE","observation_date") or header[1:]!=columns:
        raise ValueError("ALFRED returned wrong series or vintage column")
    results={v:{} for v in vintages};last=""
    for row in reader:
        if len(row)!=len(header):raise ValueError("Truncated ALFRED row")
        day=date.fromisoformat(row[0])
        if (row[0]<=last or row[0]!=day.isoformat() or
            (freq=="monthly" and day.day!=1) or
            (freq=="daily" and day.weekday()>4) or
            (freq=="friday" and day.weekday()!=4) or
            (freq=="wednesday" and day.weekday()!=2)):
            raise ValueError("Invalid ALFRED order or observation frequency")
        last=row[0]
        for v,value in zip(vintages,row[1:]):
            if value.strip() in ("","."):continue
            if day>date.fromisoformat(v):raise ValueError("Nonblank future observation in vintage")
            num=Decimal(value)
            lo,hi=MODEL_BOUNDS[sid]
            if not num.is_finite() or not lo<num<=hi:raise ValueError("Invalid ALFRED value")
            results[v][row[0][:7] if freq=="monthly" else row[0]]=num
    return results

def compare_one(candidate,observations,source_sha):
    sid=candidate["series"];p=candidate["period"]
    value=observations.get(p)
    if sid in ("CPIAUCNS","PAYEMS"):
        prior=observations.get(prev(p,12 if sid=="CPIAUCNS" else 1))
        if value is None or prior is None or prior<=0:value=None
        elif sid=="CPIAUCNS":value=(value/prior-1)*100
        else:value=(value-prior)*1000 # PAYEMS thousands of persons
    delta=None if value is None else abs(value-candidate["archive_value"])
    tolerance=Decimal(0) if sid=="PAYEMS" else Decimal("0.05")
    status=STATUSES[2] if delta is None else STATUSES[0] if delta<=tolerance else STATUSES[1]
    return {"series":sid,"period":p,"requested_vintage_date":candidate["vintage"],
            "status":status,"archive_sha256":candidate["archive_sha256"],
            "vintage_csv_sha256":source_sha,"absolute_difference":None if delta is None else float(delta),
            "difference_unit":"persons" if sid=="PAYEMS" else "percentage_points",
            "exact_historical_publication_time_certified":False,"historical_pit_certified":False}

def collect(rows,fetcher=fetch):
    receipts=[];comparisons=[];failures={};stop=False
    for sid in BOUNDS:
        if stop:break
        group=[r for r in rows if r["series"]==sid]
        dates=sorted({r["vintage"] for r in group})
        for i in range(0,len(dates),BATCH):
            batch=dates[i:i+BATCH];url=url_for(sid,batch)
            try:
                time.sleep(2)
                raw=fetcher(url);digest=hashlib.sha256(raw).hexdigest()
                parsed=parse(raw,sid,batch)
                receipts.append({"series":sid,"url":url,"sha256":digest,
                                 "requested_vintage_dates":batch,
                                 "nonmissing_level_cells":sum(len(x) for x in parsed.values())})
                for r in group:
                    if r["vintage"] in parsed:
                        comparisons.append(compare_one(r,parsed[r["vintage"]],digest))
            except (OSError,ValueError,ArithmeticError) as exc:
                failures[sid+":"+batch[0]]={"type":type(exc).__name__,"detail":str(exc)[:180]}
                if isinstance(exc,urllib.error.HTTPError) and exc.code in (403,429):
                    stop=True;break
    return comparisons,receipts,failures

def summary(rows,comparisons,receipts,failures):
    stats={}
    for sid in BOUNDS:
        target=[r for r in rows if r["series"]==sid]
        got=[r for r in comparisons if r["series"]==sid]
        stats[sid]={"target_candidates":len(target),"compared_candidates":len(got),
            **{s:sum(r["status"]==s for r in got) for s in STATUSES},
            "missing_download_or_comparison":len(target)-len(got)}
    return {"report_type":"asset_compass_v138_alfred_date_level_research",
            "generated_at":datetime.now(timezone.utc).isoformat(),
            "series":stats,"source_receipts":receipts,"comparisons":comparisons,
            "source_failures":failures,"historical_pit_certified_series":0,
            "official_scores_published":0,"eligible_for_live_scoring":False,
            "limitations":["Next-calendar-day ALFRED snapshot, not exact BLS release timestamp.",
              "Graph download is a public interface with no guarantee of stable parameters.",
              "PAYEMS changes calculated from two levels in the same vintage.",
              "BLS archived versions can differ from initial publication. No full revision chain certified."]}

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--archive",type=Path,required=True)
    p.add_argument("--output",type=Path,required=True)
    a=p.parse_args()
    src=_private_path(a.archive);out=_private_path(a.output)
    if src==out:raise ValueError("Distinct private paths required")
    rows=candidates(json.loads(src.read_text()))
    if not rows:raise ValueError("No eligible archive candidates")
    compared,receipts,failed=collect(rows)
    report=summary(rows,compared,receipts,failed)
    out.write_text(json.dumps(report,indent=2,allow_nan=False)+"\n")
    print(json.dumps({k:report[k] for k in ("series","source_failures","historical_pit_certified_series","eligible_for_live_scoring")}))
    if failed or any(v["target_candidates"]==0 or v["missing_download_or_comparison"] or v["vintage_value_missing"] for v in report["series"].values()):
        raise SystemExit(1)

if __name__=="__main__":main()
