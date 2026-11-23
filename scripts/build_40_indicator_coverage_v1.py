#!/usr/bin/env python3
"""40-item catalog coverage based ONLY on already saved, independently retrieved sources.
Research-priority A/B/C/D is unrelated to source completeness or asset scores.
This audit never invents a value or treats an observation timestamp as publication.
"""
import argparse
import json
import re
from datetime import datetime, timezone
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
CATALOG=ROOT/"macro/indicator-ratings.html"
SNAPSHOT=ROOT/"data/asset-scores.json"
SOFR=ROOT/"data/asset-compass-a10-sofr.json"
BC=ROOT/"data/asset-compass-bc-official-v1.json"
OUTPUT=ROOT/"data/asset-compass-indicator-coverage-v1.json"

def catalog_items(text):
    match=re.search(r'const indicators=(\[\[.*?\]\]);',text,re.S)
    if not match:raise ValueError("40-indicator catalog literal missing")
    rows=json.loads(match.group(1))
    if len(rows)!=40 or len({v[2] for v in rows})!=40 or {g:sum(v[0]==g for v in rows) for g in "ABCD"}!={g:10 for g in "ABCD"}:
        raise ValueError("Catalog must have 10 independent items in each grade")
    return rows

def age_ok(period,now,max_age,kind="day"):
    if not isinstance(period,str):return False
    try:
        if kind=="month":
            if not re.fullmatch(r"\d{4}-(0[1-9]|1[0-2])",period):return False
            year,month=map(int,period.split("-"))
            delta=(now.year-year)*12+now.month-month
            return 0<=delta<=max_age
        if not re.fullmatch(r"\d{4}-\d{2}-\d{2}",period):return False
        observed=datetime.fromisoformat(period+"T00:00:00+00:00")
        return 0<=(now-observed).total_seconds()<=max_age*86400+86400
    except ValueError:return False

def number(value):
    import math
    return type(value) in (int,float) and math.isfinite(value)

def classify(name,d,sofr,now,bc=None):
    bc=bc or {}
    available=(bc.get("series") or {}) if bc.get("report_type")=="asset_compass_bc_official_observations_v1" and bc.get("validated_for_live_scoring") is False and bc.get("historical_pit_certified") is False else {}
    observation=available.get(name)
    if observation and observation.get("validated_for_live_scoring") is False and number(observation.get("latest_value")) and isinstance(observation.get("observation_period"),str):
        period=observation["observation_period"]
        max_age={"quarterly":160,"monthly":95,"weekly":20,"daily":16}.get(observation.get("frequency"),0)
        if max_age>0:
            return ("current" if age_ok(period,now,max_age) else "stale", "FRED public mirror of "+str(observation.get("original_agency"))+"; latest verifiable observation")
    rates=d.get("rates") or {}
    date=d.get("observation_date")
    if name in {
        "美国10年期实际收益率":"real10y","美国10年期国债收益率":"us10y",
        "美国2年期国债收益率":"us2y","10Y－2Y期限利差":"spread10y2y",
        "10年盈亏平衡通胀率":"breakeven10y"}:
        key={"美国10年期实际收益率":"real10y","美国10年期国债收益率":"us10y",
             "美国2年期国债收益率":"us2y","10Y－2Y期限利差":"spread10y2y",
             "10年盈亏平衡通胀率":"breakeven10y"}[name]
        if number(rates.get(key)):
            return ("current" if age_ok(date,now,7) else "stale","US Treasury observed or derived values")
        return ("missing","US Treasury observation absent")
    if name=="SOFR及SOFR远期曲线":
        if (sofr.get("report_type")=="asset_compass_a10_sofr_observation"
            and sofr.get("sofr_forward_curve_available") is False
            and sofr.get("validated_for_live_scoring") is False
            and number(sofr.get("sofr_overnight_percent"))):
            return ("partial" if age_ok(sofr.get("observation_date"),now,7) else "stale",
                    "SOFR overnight only; forward curve not connected")
        return ("missing","SOFR official overnight/forward not verified")
    if name=="联邦基金目标利率及FOMC指引":
        n=d.get("nyfed") or {}
        if number(n.get("target_range_lower")) and number(n.get("target_range_upper")) and n["target_range_lower"]<=n["target_range_upper"]:
            return ("partial" if age_ok(n.get("observation_date"),now,7) else "stale",
                    "NY Fed reported target bounds; FOMC guidance not connected")
        return ("missing","FOMC guidance and target range not verified")
    if name=="美国非农就业与失业率":
        b=((d.get("bls") or {}).get("series") or {})
        u=b.get("unemployment") or {};p=b.get("payroll") or {}
        if (number(u.get("value")) and number(p.get("monthly_change_thousands"))
            and u.get("period")==p.get("period")):
            return ("current" if age_ok(u.get("period"),now,2,"month") else "stale",
                    "BLS unemployment and nonfarm monthly change")
        if number(u.get("value")) or number(p.get("monthly_change_thousands")):
            return ("partial","Only one BLS labor component or periods differ")
        return ("missing","BLS labor pairing unavailable")
    if name=="美国核心PCE同比":
        p=((d.get("bea") or {}).get("core_pce") or {})
        if number(p.get("yoy_percent")):
            return ("current" if age_ok(p.get("observation_period"),now,3,"month") else "stale",
                    "BEA core PCE YoY via FRED mirror")
    if name=="美联储资产负债表总资产":
        p=((d.get("fed_h41") or {}).get("total_assets") or {})
        if number(p.get("value_millions_usd")):
            return ("current" if age_ok(p.get("observation_date"),now,21) else "stale",
                    "Federal Reserve H.4.1 total assets")
    if name=="准备金、TGA与ON RRP":
        li=d.get("liquidity") or {}
        valid=[number((li.get(k) or {}).get("value")) and
               age_ok((li.get(k) or {}).get("observation_date"),now,21 if k!="overnight_rrp" else 11)
               for k in ("reserves","tga","overnight_rrp")]
        if any(valid):return ("partial","H.4.1 and ON RRP components; frequencies and units differ")
    if name=="美国CPI总体同比":
        c=((d.get("bls") or {}).get("series") or {}).get("cpi") or {}
        if number(c.get("yoy_percent")):
            return ("current" if age_ok(c.get("period"),now,2,"month") else "stale","BLS CPI annual percent change")
    return ("missing","No separately verified indicator data feed")

def build(rows,snapshot,sofr,*,now,bc=None):
    if snapshot.get("schema_version")!=1 or not isinstance(snapshot.get("assets"),dict):
        raise ValueError("Source snapshot invalid")
    if any((a or {}).get("score") is not None for a in snapshot["assets"].values()):
        raise ValueError("Never use this catalog for enabled investment scores")
    if now.tzinfo is None:raise ValueError("UTC now required")
    out=[]
    for grade,group,name,meaning,source,url in rows:
        status,reason=classify(name,snapshot,sofr,now,bc)
        out.append({"grade":grade,"name":name,"status":status,"reason":reason})
    counts={grade:{status:sum(r["grade"]==grade and r["status"]==status for r in out)
                   for status in ("current","partial","stale","missing")}
            for grade in "ABCD"}
    return {
      "schema_version":1,"report_type":"asset_compass_40_indicator_coverage_v1",
      "generated_at":now.astimezone(timezone.utc).isoformat(),
      "source_snapshot_generated_at":snapshot.get("generated_at"),
      "bc_source_coverage":len((bc or {}).get("series") or {}),
      "items":out,"counts_by_grade":counts,
      "status_meanings":{"current":"recent supported indicator observation(s)",
                         "partial":"only some required components, frequencies or tenors",
                         "stale":"observations exceed website freshness gate",
                         "missing":"independent current data feed not verified"},
      "not_an_asset_score":True,
      "historical_pit_certification":False,
      "validated_for_live_scoring":False,
    }

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--output",type=Path,default=OUTPUT)
    args=p.parse_args()
    rows=catalog_items(CATALOG.read_text(encoding="utf-8"))
    snapshot=json.loads(SNAPSHOT.read_text(encoding="utf-8"))
    sofr=json.loads(SOFR.read_text(encoding="utf-8")) if SOFR.exists() else {}
    bc=json.loads(BC.read_text(encoding="utf-8")) if BC.exists() else {}
    report=build(rows,snapshot,sofr,now=datetime.now(timezone.utc),bc=bc)
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(json.dumps(report["counts_by_grade"],ensure_ascii=False))
if __name__=="__main__":main()
