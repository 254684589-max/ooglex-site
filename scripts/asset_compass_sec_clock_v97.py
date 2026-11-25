#!/usr/bin/env python3
"""V97-V103: official SEC acceptance clock evidence, never assume public dissemination."""
import argparse
import hashlib
import json
import re
import time
import urllib.request
import urllib.error
from datetime import date,datetime,timezone
from pathlib import Path
from scripts.asset_compass_sec_returns_v63 import ROOT
from scripts.asset_compass_sec_returns_v64 import NoRedirect
from scripts.asset_compass_sec_returns_v66 import fund_registry,AMEND

BASE="https://data.sec.gov/submissions/"
CIK="CIK0001100663"
MAX_BYTES=12_000_000
MAX_SHARDS=30
FIELDS=("accessionNumber","filingDate","reportDate","acceptanceDateTime","form","primaryDocument")

def registry():
    out={}
    for ticker,(_,_,_,reg) in fund_registry(True).items():
        for accession,period in reg.items():
            if accession in out:raise ValueError("Duplicate expected accession")
            out[accession]={"ticker":ticker,"period":period,"amendment":False}
    for accession,period in AMEND.items():
        out[accession]={"ticker":"IVV","period":period,"amendment":True}
    return out

def fetch(name):
    if not re.fullmatch(r"CIK0001100663(?:-submissions-\d{3,5})?\.json",name):
        raise ValueError("Unapproved SEC submissions file")
    url=BASE+name
    req=urllib.request.Request(url,headers={"User-Agent":"Ooglex Research (https://www.ooglex.com/; research backfill)","Accept":"application/json"})
    with urllib.request.build_opener(NoRedirect()).open(req,timeout=35) as res:
        if res.geturl()!=url or "json" not in res.headers.get("Content-Type","").lower():
            raise ValueError("Unexpected SEC submissions response")
        raw=res.read(MAX_BYTES+1)
    if not raw or len(raw)>MAX_BYTES:raise ValueError("Empty or excessive SEC metadata")
    return raw

def parse_rows(columns,expected,source_name,digest):
    if any(not isinstance(columns.get(k),list) for k in FIELDS):
        raise ValueError("SEC submission columns missing")
    count=len(columns["accessionNumber"])
    if any(len(columns[k])!=count for k in FIELDS):raise ValueError("Unequal SEC columns")
    results={}
    for i,key in enumerate(columns["accessionNumber"]):
        if not isinstance(key,str):raise ValueError("Invalid accession")
        acc=key.replace("-","")
        if acc not in expected:continue
        if acc in results:raise ValueError("Duplicate tracked SEC accession")
        r={k:columns[k][i] for k in FIELDS};e=expected[acc]
        if r["reportDate"]!=e["period"]:raise ValueError("SEC reporting period mismatch: "+acc)
        allowed=("NPORT-P/A",) if e["amendment"] else ("NPORT-P",)
        if r["form"] not in allowed or r["primaryDocument"]!="primary_doc.xml":
            raise ValueError("SEC document or amendment mismatch: "+acc)
        accepted=datetime.fromisoformat(r["acceptanceDateTime"].replace("Z","+00:00"))
        if accepted.tzinfo is None or accepted.utcoffset() is None:
            raise ValueError("SEC acceptance clock missing timezone")
        utc=accepted.astimezone(timezone.utc)
        filing=date.fromisoformat(r["filingDate"])
        period=date.fromisoformat(e["period"])
        if utc.date()<period or filing<period or utc>datetime.now(timezone.utc) or filing>datetime.now(timezone.utc).date():
            raise ValueError("Invalid SEC filing chronology")
        results[acc]={"ticker":e["ticker"],"report_period_end":e["period"],"form":r["form"],
                      "filing_date":filing.isoformat(),"sec_acceptance_utc":utc.isoformat(),
                      "acceptance_lag_calendar_days":(utc.date()-period).days,
                      "metadata_url":BASE+source_name,"metadata_sha256":digest,
                      "public_dissemination_at_verified":False,
                      "historical_pit_certified":False}
    return results

def collect(expected,fetcher=fetch):
    all_rows={};receipts=[]
    main=CIK+".json"
    raw=fetcher(main);doc=json.loads(raw)
    if str(doc.get("cik")).lstrip("0")!="1100663":raise ValueError("Wrong SEC filer")
    def consume(columns,name,raw):
        digest=hashlib.sha256(raw).hexdigest()
        found=parse_rows(columns,expected,name,digest)
        if set(found)&set(all_rows):raise ValueError("Repeated accession across SEC shards")
        all_rows.update(found)
        receipts.append({"url":BASE+name,"sha256":digest,"tracked_accessions":len(found)})
    consume(doc["filings"]["recent"],main,raw)
    lower=min(e["period"] for e in expected.values())
    files=doc["filings"].get("files",[])
    if not isinstance(files,list):raise ValueError("Bad SEC shard registry")
    candidates=[]
    for item in files:
        name=item["name"]
        if not re.fullmatch(r"CIK0001100663-submissions-\d{3,5}\.json",name):
            raise ValueError("Unapproved shard identity")
        start=date.fromisoformat(item["filingFrom"]);end=date.fromisoformat(item["filingTo"])
        if start>end:raise ValueError("Invalid shard dates")
        if end.isoformat()>=lower:candidates.append((end,name))
    if len(candidates)>MAX_SHARDS:raise ValueError("Too many SEC shards; review bounded scope")
    if len({name for _,name in candidates})!=len(candidates):raise ValueError("Duplicate SEC shard")
    for _,name in sorted(candidates,reverse=True):
        if len(all_rows)==len(expected):break
        time.sleep(1)
        raw=fetcher(name)
        consume(json.loads(raw),name,raw)
    return all_rows,receipts

def build(coverage,rows,receipts):
    expected=registry()
    if coverage.get("report_type")!="asset_compass_v66_v68_monthly_fund_research_panel" or coverage.get("eligible_for_live_scoring") is not False:
        raise ValueError("Expected extended fund coverage evidence")
    seen={}
    for ticker,fund in coverage["funds"].items():
        for src in fund["source_receipts"]:
            acc=src["accession"]
            if acc not in expected or ticker!=expected[acc]["ticker"] or src["report_period_end"]!=expected[acc]["period"]:
                raise ValueError("Fund receipt mismatch")
            if not re.fullmatch(r"[0-9a-f]{64}",src["local_input_sha256"]):
                raise ValueError("Missing XML digest")
            seen[acc]=src["local_input_sha256"]
    for a in coverage.get("amendment_reviews",[]):
        acc=a["amendment_accession"]
        if acc not in AMEND or not re.fullmatch(r"[0-9a-f]{64}",a["amendment_sha256"]):
            raise ValueError("Unrecognized amendment receipt")
        seen[acc]=a["amendment_sha256"]
    joined={k:{**v,"raw_fund_xml_sha256":seen[k]} for k,v in rows.items() if k in seen}
    return {"report_type":"asset_compass_v97_sec_acceptance_research",
            "generated_at":datetime.now(timezone.utc).isoformat(),"target_filings":len(expected),
            "acceptance_metadata_found":len(rows),"xml_and_metadata_matched":len(joined),
            "missing_metadata":sorted(set(expected)-set(rows)),
            "missing_xml":sorted(set(expected)-set(seen)),
            "source_receipts":receipts,"filings":joined,
            "public_dissemination_certified_filings":0,"historical_pit_certified":False,
            "official_scores_published":0,"eligible_for_live_scoring":False,
            "limitations":["EDGAR acceptance is not proof of exact public dissemination time.",
                           "Current metadata and archived XML do not prove historical byte identity or complete revisions.",
                           "A return period end is not an information availability date."]}

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--coverage",type=Path,required=True)
    p.add_argument("--output",type=Path,required=True)
    a=p.parse_args()
    if a.output.resolve().is_relative_to(ROOT):p.error("Research metadata outside site only")
    try:
        rows,receipts=collect(registry())
    except (OSError,ValueError,KeyError) as exc:
        # No alternative host or access bypass after denial.
        report={"report_type":"asset_compass_v97_sec_acceptance_research","status":"source_failed",
                "reason":type(exc).__name__,"http_status":getattr(exc,"code",None),
                "eligible_for_live_scoring":False}
        a.output.write_text(json.dumps(report,indent=2)+"\n")
        print(json.dumps(report))
        raise SystemExit(1)
    r=build(json.loads(a.coverage.read_text()),rows,receipts)
    a.output.write_text(json.dumps(r,indent=2,allow_nan=False)+"\n")
    print(json.dumps({k:r[k] for k in ("target_filings","acceptance_metadata_found","xml_and_metadata_matched","missing_metadata","missing_xml","public_dissemination_certified_filings","eligible_for_live_scoring")}))
    if r["xml_and_metadata_matched"]!=r["target_filings"]:raise SystemExit(1)

if __name__=="__main__":main()
