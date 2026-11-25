#!/usr/bin/env python3
"""V84-V89: published SEC fund performance tables, research only."""
import argparse
import hashlib
import json
import re
import time
import urllib.request
from datetime import datetime,timezone
from decimal import Decimal
from html.parser import HTMLParser
from pathlib import Path
from scripts.asset_compass_sec_returns_v63 import ROOT
from scripts.asset_compass_sec_returns_v66 import months
from scripts.asset_compass_sec_returns_v64 import NoRedirect

MONTHS=("January","February","March","April","May","June","July","August","September","October","November","December")
SOURCES={
 "UUP":{"asset":"usd","url":"https://www.sec.gov/Archives/edgar/data/1371571/000119312526368499/d102641d424b3.htm",
        "identity":"Invesco DB US Dollar Index Bullish Fund","years":[2026,2025,2024,2023,2022,2021],
        "last":"2026-05","annual_label":"Compound Rate of Return",
        "definition":"issuer_reported_fund_compounded_monthly_returns"},
 "USO":{"asset":"oil","url":"https://www.sec.gov/Archives/edgar/data/1327068/000207187626000128/i26211_uso-424b3.htm",
        "identity":"United States Oil Fund","years":[2021,2022,2023,2024,2025,2026],
        "last":"2026-02","annual_label":"Annual Rate of Return",
        "definition":"issuer_reported_month_end_nav_change_not_individual_futures_account"},
}
REFERENCES={
 "UUP":{"2021-01":"0.70","2022-11":"-4.73","2024-10":"3.65","2025-04":"-4.17","2026-05":"1.17"},
 "USO":{"2021-01":"6.41","2022-09":"-11.37","2024-12":"6.30","2025-04":"-17.76","2026-02":"3.51"},
}
QUARTERS={
 "GLD":{"asset":"gold","url":"https://www.sec.gov/Archives/edgar/data/1222333/000143774926025680/gld20260630_10q.htm",
        "identity":"SPDR", "label":"Total Return, at Net Asset Value","periods":["2026-06","2025-06"],"references":["-12.72","5.43"]},
 "IBIT":{"asset":"bitcoin","url":"https://www.sec.gov/Archives/edgar/data/1980994/000143774926035539/ibit20260930_10q.htm",
         "identity":"iShares Bitcoin Trust ETF","label":"Total return, at net asset value","periods":["2026-09","2025-09"],"references":["41.52","6.47"]},
}
MAX=12_000_000

class Tables(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.stack=[];self.tables=[]
    def handle_starttag(self,tag,attrs):
        if tag=="table":self.stack.append({"rows":[],"row":None,"cell":None})
        elif self.stack:
            t=self.stack[-1]
            if tag=="tr":t["row"]=[]
            elif tag in ("td","th") and t["row"] is not None:t["cell"]=[]
    def handle_data(self,s):
        if self.stack and self.stack[-1]["cell"] is not None:self.stack[-1]["cell"].append(s)
    def handle_endtag(self,tag):
        if not self.stack:return
        t=self.stack[-1]
        if tag in ("td","th") and t["cell"] is not None:
            t["row"].append(" ".join("".join(t["cell"]).split()));t["cell"]=None
        elif tag=="tr" and t["row"] is not None:
            t["rows"].append(t["row"]);t["row"]=None;t["cell"]=None
        elif tag=="table":
            self.tables.append(self.stack.pop()["rows"])

def tables(raw,identity):
    if not raw or len(raw)>MAX:raise ValueError("Invalid SEC document size")
    text=raw.decode("utf-8")
    parser=Tables();parser.feed(text)
    # Identity is independently anchored to fixed official URL and rendered text.
    # Strip formatting tags for identity check, tolerate registered-mark glyphs.
    plain=re.sub(r"<[^>]*>"," ",text)
    import html
    plain=" ".join(html.unescape(plain).replace("®","").split())
    if identity.lower() not in plain.lower():raise ValueError("Wrong SEC fund document")
    return parser.tables

def row_label(row):
    return next((c for c in row if c),"")

def numbers(row):
    # Accounting parentheses and percent signs are sometimes in separate HTML cells.
    # Require exactly two decimal places; never mistake year or footnote digits for returns.
    label=row_label(row)
    rest=" ".join(row[row.index(label)+1:])
    vals=[]
    for m in re.finditer(r"\(\s*(\d+\.\d{2})\s*\)|(?<![\d.])(-?\d+\.\d{2})(?![\d.])",rest):
        val=-Decimal(m[1]) if m[1] is not None else Decimal(m[2])
        if not val.is_finite() or val < -100:raise ValueError("Invalid return")
        vals.append(val)
    return vals

def monthly(ticker,raw):
    cfg=SOURCES[ticker]
    matches=[]
    for table in tables(raw,cfg["identity"]):
        month_rows={};annual=[];years=False
        for row in table:
            label=row_label(row)
            if label in MONTHS:
                if label in month_rows:raise ValueError("Duplicate monthly row")
                month_rows[label]=numbers(row)
            elif label.startswith(cfg["annual_label"]):
                annual.append(numbers(row))
            elif label in ("Month","Monthly Rate of Return"):
                years=[int(y) for y in re.findall(r"\b20\d{2}\b"," ".join(row))]==cfg["years"]
        if set(month_rows)==set(MONTHS) and years and len(annual)==1:
            matches.append((month_rows,annual[0]))
    if len(matches)!=1:raise ValueError("Missing or ambiguous performance table")
    mr,annual=matches[0];out={}
    expected=months("2021-01",cfg["last"])
    for i,name in enumerate(MONTHS,1):
        keys=[f"{y}-{i:02d}" for y in cfg["years"] if f"{y}-{i:02d}"<=cfg["last"]]
        if len(mr[name])!=len(keys):raise ValueError("Monthly table missing/unexpected value")
        out.update(zip(keys,mr[name]))
    if sorted(out)!=expected:raise ValueError("Noncontinuous fund month coverage")
    for k,v in REFERENCES[ticker].items():
        if out[k]!=Decimal(v):raise ValueError("Independent reference mismatch")
    if len(annual)!=len(cfg["years"]):raise ValueError("Annual comparison missing")
    checks=[]
    for year,reported in zip(cfg["years"],annual):
        compound=Decimal(1)
        for k in expected:
            if k.startswith(str(year)):compound*=1+out[k]/100
        calculated=(compound-1)*100
        # Rounded monthly percentages and reported annual figures need not be identical.
        if abs(calculated-reported)>Decimal("0.15"):raise ValueError("Annual compound reconciliation failed")
        checks.append({"year":year,"absolute_rounding_gap_pct":float(abs(calculated-reported))})
    return {"asset":cfg["asset"],"ticker":ticker,"source_url":cfg["url"],
        "source_sha256":hashlib.sha256(raw).hexdigest(),"frequency":"monthly",
        "definition":cfg["definition"],"parsed_months":len(out),"annual_compounding_checks":checks,
        "monthly_observations":[{"month":k,"reported_fund_total_return_percent":str(out[k])} for k in expected],
        "historical_pit_certified":False,"investable_total_return_certified":False,"official_score":None}

def quarterly(ticker,raw):
    cfg=QUARTERS[ticker]
    rows=[]
    for t in tables(raw,cfg["identity"]):
        for row in t:
            if row_label(row).lower().startswith(cfg["label"].lower()):
                nums=numbers(row)
                if len(nums)==4:rows.append(nums)
    if len(rows)!=1:raise ValueError("Missing or ambiguous quarterly financial highlights")
    vals=rows[0][:2]
    if vals!=list(map(Decimal,cfg["references"])):raise ValueError("Quarterly reference mismatch")
    return {"ticker":ticker,"asset":cfg["asset"],"source_url":cfg["url"],"source_sha256":hashlib.sha256(raw).hexdigest(),
            "frequency":"quarterly","quarterly_observations":[{"quarter_end_month":p,"reported_nav_total_return_pct":str(v)}
                  for p,v in zip(cfg["periods"],vals)],
            "not_monthly_labels":True,"investable_total_return_certified":False,"official_score":None}

def download(url):
    req=urllib.request.Request(url,headers={"User-Agent":"Ooglex Research (https://www.ooglex.com/; research backfill)","Accept":"text/html"})
    with urllib.request.build_opener(NoRedirect()).open(req,timeout=35) as r:
        if r.geturl()!=url or "text/html" not in r.headers.get("Content-Type","").lower():
            raise ValueError("Unexpected SEC HTML source")
        raw=r.read(MAX+1)
    if len(raw)>MAX:raise ValueError("Oversized source")
    return raw

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--output",type=Path,required=True)
    p.add_argument("--metadata",type=Path,required=True)
    a=p.parse_args()
    if a.output.resolve()==a.metadata.resolve() or any(x.resolve().is_relative_to(ROOT) for x in (a.output,a.metadata)):
        p.error("Distinct research output paths outside site repository required")
    import urllib.error
    funds={};quarter={};fail={}
    for ticker,cfg in {**SOURCES,**QUARTERS}.items():
        try:
            time.sleep(1)
            raw=download(cfg["url"])
            if ticker in SOURCES:funds[ticker]=monthly(ticker,raw)
            else:quarter[ticker]=quarterly(ticker,raw)
        except (ValueError,OSError) as exc:
            fail[ticker]={"type":type(exc).__name__,"reason":str(exc)[:180]}
            if isinstance(exc,urllib.error.HTTPError) and exc.code in (403,429):break
    report={"report_type":"asset_compass_v84_v89_sec_performance_research",
        "generated_at":datetime.now(timezone.utc).isoformat(),"funds":funds,"quarterly":quarter,
        "source_failures":fail,"eligible_for_live_scoring":False,
        "formal_oos_validated_assets":0,"official_scores_published":0}
    meta={**report,"funds":{k:{a:b for a,b in v.items() if a!="monthly_observations"} for k,v in funds.items()},
          "quarterly":{k:{a:b for a,b in v.items() if a!="quarterly_observations"} for k,v in quarter.items()}}
    for path,obj in [(a.output,report),(a.metadata,meta)]:
        path.parent.mkdir(parents=True,exist_ok=True)
        path.write_text(json.dumps(obj,indent=2,allow_nan=False)+"\n")
    print(json.dumps({"monthly_counts":{k:v["parsed_months"] for k,v in funds.items()},
                      "quarterly_counts":{k:len(v["quarterly_observations"]) for k,v in quarter.items()},"source_failures":fail,
                      "eligible_for_live_scoring":False}))
    if set(funds)!=set(SOURCES) or set(quarter)!=set(QUARTERS):raise SystemExit(1)

if __name__=="__main__":main()
