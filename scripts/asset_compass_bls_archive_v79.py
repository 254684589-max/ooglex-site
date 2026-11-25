#!/usr/bin/env python3
"""V79-V83: bounded official BLS archive expansion; research evidence, not PIT."""
import argparse
import hashlib
import json
import os
import re
import time
import urllib.error
import urllib.request
from datetime import date, datetime, timezone
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urljoin
from zoneinfo import ZoneInfo
from scripts.capture_asset_compass_official_v51 import (
    NoRedirect, MAX_BYTES, _canonical, _download, _private_path, _save_private)
from scripts.asset_compass_release_values_v53 import (
    MONTH, visible, extract, _explicit_employment_revisions)

INDEX = {
    "cpi": "https://www.bls.gov/bls/news-release/cpi.htm",
    "employment": "https://www.bls.gov/bls/news-release/empsit.htm",
}
TITLES = {"cpi":"Consumer Price Index","employment":"Employment Situation"}
YEARS = (2024,2025)
BLOCKED = "2025-10"

class Links(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.current=None
        self.links=[]
    def handle_starttag(self, tag, attrs):
        if tag=="a":
            self.current=[dict(attrs).get("href",""),[]]
    def handle_data(self, text):
        if self.current is not None:self.current[1].append(text)
    def handle_endtag(self, tag):
        if tag=="a" and self.current is not None:
            href,parts=self.current
            self.links.append((href," ".join("".join(parts).split())))
            self.current=None

def expected_periods(years=YEARS):
    return {f"{y}-{m:02d}" for y in years for m in range(1,13)}-{BLOCKED}

def discover(raw,kind,years=YEARS):
    if not raw or len(raw)>MAX_BYTES:raise ValueError("Invalid BLS index size")
    p=Links()
    p.feed(raw.decode("utf-8"))
    result={}
    prefix="cpi" if kind=="cpi" else "empsit"
    title=TITLES[kind]
    for href,label in p.links:
        m=re.fullmatch(r"("+"|".join(MONTH)+r") ("+"|".join(map(str,years))+r") "+re.escape(title)+r"(?: \(PDF\))?",label,re.I)
        if not m:continue
        period=f"{m[2]}-{MONTH.index(m[1].title())+1:02d}"
        if period==BLOCKED:raise ValueError("Unexpected October 2025 archive link; manual review")
        listed=urljoin(INDEX[kind],href)
        # Older index links point to PDFs. Candidate sibling HTML is separately
        # validated against the same BLS host, release kind, month and header.
        # This does not parse PDF bytes or bypass a denied request.
        candidate=listed[:-4]+".htm" if listed.endswith(".pdf") else listed
        url=_canonical(candidate,"BLS")
        d=re.fullmatch(r"/news.release/archives/"+prefix+r"_(\d{8})\.htm",urllib.parse.urlsplit(url).path)
        if not d:raise ValueError("Wrong BLS archive URL family")
        day=datetime.strptime(d[1],"%m%d%Y").date()
        end=date.fromisoformat(period+"-01")
        if day<=end or day>datetime.now(timezone.utc).date():
            raise ValueError("Invalid archive link date")
        if period in result and result[period]["source_url"]!=url:
            raise ValueError("Ambiguous archive link for period")
        result[period]={"artifact_id":f"bls-{kind}-{period}","publisher":"BLS",
            "release_kind":kind,"observation_period":period,"source_url":url,
            "index_listed_url":listed,"html_candidate_from_pdf_index":listed!=url,
            "scheduled_release_date_candidate_unverified":day.isoformat(),
            "covered_source_series": ["bls.cpi","bls.core_cpi"] if kind=="cpi" else ["bls.unemployment","bls.payroll"]}
    return result

def fetch_index(kind):
    url=INDEX[kind]
    req=urllib.request.Request(url,headers={"User-Agent":"OoglexResearch/1.0 (+https://www.ooglex.com/)","Accept":"text/html"})
    with urllib.request.build_opener(NoRedirect()).open(req,timeout=25) as res:
        if res.geturl()!=url or "text/html" not in res.headers.get("Content-Type","").lower():
            raise ValueError("Unexpected BLS index response")
        raw=res.read(MAX_BYTES+1)
    return raw

def header(source,raw):
    text=visible(raw)
    # The source's embargo statement is a CLAIM, not independent proof
    # of historical byte availability. The archive filename is a cross-check.
    m=re.search(r"Transmission of material in this (?:news )?release is embargoed until(.{0,240})",text,re.I)
    if not m:return {"header_status":"no_embargo_header","publication_time_verified":False}
    block=m[1]
    d=re.search(r"(\d{1,2}):(\d{2})\s*a\.m\.\s*\(ET\)\s*\w+,\s*("+"|".join(MONTH)+r")\s+(\d{1,2}),\s*(20\d{2})",block,re.I)
    ids=re.findall(r"USDL-\d{2}-\d{4}",block)
    if not d or len(set(ids))!=1:return {"header_status":"ambiguous_embargo_header","publication_time_verified":False}
    h,minute,mo,day,yr=d.groups()
    t=datetime(int(yr),MONTH.index(mo.title())+1,int(day),int(h)%12,int(minute),tzinfo=ZoneInfo("America/New_York"))
    matches=t.date().isoformat()==source["scheduled_release_date_candidate_unverified"]
    return {"header_status":"publisher_header_matches_archive_date" if matches else "archive_date_mismatch",
        "publisher_stated_embargo_utc":t.astimezone(timezone.utc).isoformat(),"release_id":ids[0],
        "publication_time_verified":False}

def inspect(source,raw):
    digest=hashlib.sha256(raw).hexdigest()
    result=extract(source,raw,digest)
    text=visible(raw)
    # Reissue/correction notices anywhere in current archive content require review.
    # Do not treat every ordinary revision of prior payroll as a reissue.
    notice=bool(re.search(r"(?:reissued this news release|this news release was reissued|this release was reissued|this news release was corrected|this release was corrected)",text,re.I))
    claims=_explicit_employment_revisions(text,source,digest)
    return {"source":source,"sha256":digest,"byte_size":len(raw),
            "retrieved_at":datetime.now(timezone.utc).isoformat(),
            "header":header(source,raw),"reissue_notice_detected":notice,
            "metric_count":result["extracted_metrics"],"expected_metrics":result["expected_metrics"],
            "metrics":result["reported_metrics"],"revision_claims":claims,
            "original_bytes_at_historical_time_verified":False,"pit_qualified":False}

def summary(records,indexes,failures,years=YEARS):
    by_family={}
    for kind in INDEX:
        rows=[r for r in records if r["source"]["release_kind"]==kind]
        seen={r["source"]["observation_period"] for r in rows}
        by_family[kind]={"target_releases":len(expected_periods(years)),"retrieved_and_parsed":len(rows),
            "missing_periods":sorted(expected_periods(years)-seen),
            "complete_metric_releases":sum(r["metric_count"]==r["expected_metrics"] for r in rows),
            "extracted_metrics":sum(r["metric_count"] for r in rows),
            "matching_embargo_headers":sum(r["header"]["header_status"]=="publisher_header_matches_archive_date" for r in rows),
            "reissue_notices":sum(r["reissue_notice_detected"] for r in rows),
            "revision_claims":sum(len(r["revision_claims"]) for r in rows)}
    return {"report_type":"asset_compass_v79_v83_bls_archive_research",
        "generated_at":datetime.now(timezone.utc).isoformat(),"indexes":indexes,
        "families":by_family,"source_failures":failures,
        "known_unpublished":[{"family":k,"period":BLOCKED} for k in INDEX],
        "historical_pit_certified_series":0,"independent_factor_groups_certified":0,
        "official_scores_published":0,"eligible_for_live_scoring":False,
        "receipts":[{k:v for k,v in r.items() if k not in ("metrics","revision_claims")} for r in records]}

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--private-dir",type=Path,required=True)
    p.add_argument("--metadata",type=Path,required=True)
    p.add_argument("--require-complete",action="store_true")
    p.add_argument("--extended-years",action="store_true")
    a=p.parse_args()
    years=(2022,2023,2024,2025) if a.extended_years else YEARS
    private=_private_path(a.private_dir);output=_private_path(a.metadata)
    if output==private or output.is_relative_to(private):
        p.error("Coverage metadata must be outside private raw archive")
    private.mkdir(parents=True,exist_ok=True,mode=0o700)
    os.chmod(private,0o700)
    records=[];indexes={};failures={};stop=False
    for kind in INDEX:
        if stop:break
        try:
            raw=fetch_index(kind)
            registry=discover(raw,kind,years)
            indexes[kind]={"url":INDEX[kind],"sha256":hashlib.sha256(raw).hexdigest(),"discovered":len(registry)}
            if set(registry)!=expected_periods(years):
                failures[kind+"-index"]={"missing":sorted(expected_periods(years)-set(registry))}
        except (OSError,ValueError) as exc:
            failures[kind+"-index"]={"type":type(exc).__name__}
            if isinstance(exc,urllib.error.HTTPError) and exc.code in (403,429):stop=True
            continue
        for period,source in sorted(registry.items()):
            try:
                time.sleep(1)
                body=_download(source)
                digest=hashlib.sha256(body).hexdigest()
                _save_private(source,body,digest,private)
                records.append(inspect(source,body))
            except (OSError,ValueError) as exc:
                failures[source["artifact_id"]]={"type":type(exc).__name__,"reason":str(exc)[:180]}
                if isinstance(exc,urllib.error.HTTPError) and exc.code in (403,429):
                    stop=True
                    break
    report=summary(records,indexes,failures,years)
    output.parent.mkdir(parents=True,exist_ok=True)
    output.write_text(json.dumps(report,indent=2,allow_nan=False)+"\n")
    # Numeric headline records are kept locally, not uploaded.
    (private/"extracted-research.json").write_text(json.dumps(records,indent=2,allow_nan=False)+"\n")
    print(json.dumps({k:report[k] for k in ("families","source_failures","known_unpublished","historical_pit_certified_series","eligible_for_live_scoring")}))
    if a.require_complete and (failures or any(v["missing_periods"] for v in report["families"].values())):
        raise SystemExit(1)

if __name__=="__main__":main()
