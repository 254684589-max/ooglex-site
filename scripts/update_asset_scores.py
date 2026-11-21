#!/usr/bin/env python3
"""从美国财政部官方日度收益率CSV生成经校验的静态JSON；仅发布真实观测，不构造完整资产评分。"""
import csv
import io
import json
import os
import re
import urllib.parse
import urllib.request
from datetime import date, datetime, timezone
from pathlib import Path

BASE = "https://home.treasury.gov/resource-center/data-chart-center/interest-rates/daily-treasury-rates.csv/"
TYPES = {"nominal": "daily_treasury_yield_curve", "real": "daily_treasury_real_yield_curve"}
def get_rows(kind, year):
    params = urllib.parse.urlencode({"type": TYPES[kind], "field_tdr_date_value": str(year), "page": "", "_format": "csv"})
    url = BASE + str(year) + "/all?" + params
    req = urllib.request.Request(url, headers={"User-Agent": "OoglexResearch/1.0 (+https://www.ooglex.com/)"})
    with urllib.request.urlopen(req, timeout=35) as response:
        body = response.read(4000000).decode("utf-8-sig")
    if not body.strip() or "<html" in body.lower()[:200]: raise ValueError("Treasury returned non-CSV content")
    rows = list(csv.DictReader(io.StringIO(body)))
    if not rows: raise ValueError("Empty Treasury dataset: "+kind)
    return rows,url
def lookup(row, needle):
    for key,val in row.items():
        normalized = re.sub(r"[^a-z0-9]","",str(key).lower())
        if normalized == needle:
            try: return float(val.replace(",","").strip())
            except (TypeError,ValueError,AttributeError): return None
    return None
def rowdate(row):
    for k,v in row.items():
        if "date" in k.lower():
            for pattern in ("%m/%d/%Y","%Y-%m-%d","%m/%d/%y"):
                try: return datetime.strptime(str(v).strip(),pattern).date()
                except ValueError: pass
    return None
def by_date(rows):
    return {rowdate(r):r for r in rows if rowdate(r)}
def build():
    year=date.today().year
    # Include preceding year for first trading days of January.
    nominal=[];real=[];urls=[]
    for y in (year-1,year):
        for kind,target in (("nominal",nominal),("real",real)):
            rows,u=get_rows(kind,y)
            target.extend(rows);urls.append(u)
    n=by_date(nominal);r=by_date(real)
    common=sorted(set(n)&set(r),reverse=True)
    latest=None
    for d in common:
        if d>date.today():continue
        a=lookup(n[d],"10year");b=lookup(n[d],"2year");c=lookup(r[d],"10year")
        if all(v is not None and -5<v<30 for v in (a,b,c)):
            latest=(d,a,b,c);break
    if latest is None:raise ValueError("No same-date verified nominal and TIPS 10-year yields")
    d,a,b,c=latest
    result={"schema_version":1,"observation_date":d.isoformat(),"generated_at":datetime.now(timezone.utc).isoformat(),
            "status":"partial_data_no_full_score","source":"US Department of the Treasury",
            "source_urls":urls,
            "rates":{"us10y":a,"us2y":b,"real10y":c,"breakeven10y":round(a-c,3),"spread10y2y":round(a-b,3)},
            "assets":{k:{"score":None,"status":"insufficient_data"} for k in ("gold","us_equities","us_long_bonds","usd","bitcoin","oil")}}
    out=Path(__file__).resolve().parents[1]/"data"/"asset-scores.json"
    out.parent.mkdir(parents=True,exist_ok=True)
    # Refuse to replace prior valid data with an older observation.
    if out.exists():
        previous=json.loads(out.read_text(encoding="utf-8"))
        if previous.get("observation_date","")>d.isoformat():raise ValueError("Refusing to overwrite newer snapshot")
    out.write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print("Updated",out,d)
if __name__=="__main__":build()
