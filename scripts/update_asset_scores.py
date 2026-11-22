#!/usr/bin/env python3
"""从美国财政部官方日度收益率CSV生成经校验的静态JSON；仅发布真实观测，不构造完整资产评分。"""
import csv
import io
import json
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
def retain_recent_auxiliary(previous, now):
    """Retain previously verified auxiliary blocks only for a short retry window.

    Treasury refresh is the first step in a multi-source pipeline. It must not
    erase independently verified PCE/H.4.1/liquidity/recession observations when
    another source has not yet returned. This is NOT permission to relabel old
    readings as newly published, nor to retain old readings indefinitely.
    """
    if not isinstance(previous, dict) or previous.get("schema_version") != 1:
        return {}
    retained = {}
    limits = {"bea": 4, "fed_h41": 21, "liquidity": 21, "nyfed_recession_model": 4}
    for section, max_age in limits.items():
        block = previous.get(section)
        if not isinstance(block, dict) or not block.get("retrieved_at"):
            continue
        try:
            stamp = datetime.fromisoformat(block["retrieved_at"].replace("Z", "+00:00"))
        except (ValueError, TypeError, AttributeError):
            continue
        if stamp.tzinfo is None:
            continue
        age = (now - stamp.astimezone(timezone.utc)).total_seconds()
        if not 0 <= age <= 72 * 3600:
            continue
        if section == "bea":
            sub = block.get("core_pce") or {}
            period = sub.get("observation_period")
            try:
                y, m = (int(p) for p in period.split("-"))
                diff = (now.year-y)*12 + now.month-m
                if not 0 <= diff <= max_age or not isinstance(sub.get("value"), (int,float)):
                    continue
            except (TypeError, ValueError, AttributeError):
                continue
        elif section == "nyfed_recession_model":
            period = block.get("observation_period")
            try:
                y, m = (int(p) for p in period.split("-"))
                if not 0 <= (now.year-y)*12+now.month-m <= max_age:
                    continue
            except (TypeError, ValueError, AttributeError):
                continue
        elif section == "fed_h41":
            try:
                observed = date.fromisoformat(block["total_assets"]["observation_date"])
                if not 0 <= (now.date()-observed).days <= max_age:
                    continue
            except (KeyError, TypeError, ValueError):
                continue
        elif section == "liquidity":
            safe = {"retrieved_at":block["retrieved_at"]}
            for key in ("reserves", "tga", "overnight_rrp"):
                item = block.get(key)
                if not isinstance(item, dict):
                    continue
                try:
                    observed = date.fromisoformat(item["observation_date"])
                    horizon = 11 if key == "overnight_rrp" else max_age
                    if not 0 <= (now.date()-observed).days <= horizon:
                        continue
                    if type(item.get("value")) not in (int,float):
                        continue
                    safe[key] = item
                except (KeyError, TypeError, ValueError):
                    continue
            if len(safe) == 1:
                continue
            retained[section] = safe
            continue
        retained[section] = block
    return retained


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
        a=lookup(n[d],"10yr");b=lookup(n[d],"2yr");c=lookup(r[d],"10yr")
        if all(v is not None and -5<v<30 for v in (a,b,c)):
            latest=(d,a,b,c);break
    if latest is None:raise ValueError("No same-date verified nominal and TIPS 10-year yields")
    d,a,b,c=latest
    if (date.today()-d).days>10:raise ValueError("Treasury observation stale: "+d.isoformat())
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
    if out.exists():
        previous=json.loads(out.read_text(encoding="utf-8"))
        if isinstance(previous.get("bls"),dict): result["bls"]=previous["bls"]
        if isinstance(previous.get("factor_signals"),dict): result["factor_signals"]=previous["factor_signals"]
        result.update(retain_recent_auxiliary(previous, datetime.now(timezone.utc)))
    out.write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print("Updated",out,d)
if __name__=="__main__":build()
