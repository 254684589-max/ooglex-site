#!/usr/bin/env python3
"""Traceable Asset Compass factor OBSERVATIONS, not scored factor signals.

Snapshot levels are not historical changes, calibrated z-scores, asset-specific
directions or independently sampled market observations. Missing and stale
entries are omitted rather than set to zero. Public output is an explicit
provenance table with research-only safeguards.
"""
import argparse
import json
import math
from datetime import date, datetime, timezone
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/"data"/"asset-scores.json"
OUTPUT=ROOT/"data"/"asset-compass-factor-observations.json"
GROUPS=("rates","inflation","growth","liquidity","risk","asset_specific")
GROUP_LABELS={
 "rates":"利率与货币政策","inflation":"通胀环境",
 "growth":"经济增长与就业","liquidity":"流动性组件",
 "risk":"风险与信用环境","asset_specific":"资产专属估值与资金流"
}

def finite(value):
    return type(value) in (int,float) and math.isfinite(value)

def fresh(period,today,max_age_days=None,max_age_months=None):
    if not isinstance(period,str):return False
    try:
        if max_age_days is not None:
            day=date.fromisoformat(period)
            age=(today-day).days
            return 0<=age<=max_age_days
        if max_age_months is not None:
            if len(period)!=7:return False
            day=date.fromisoformat(period+"-01")
            months=(today.year-day.year)*12+today.month-day.month
            return 0<=months<=max_age_months
    except ValueError:
        return False
    return False

def collect(snapshot,today=None):
    today=today or datetime.now(timezone.utc).date()
    if snapshot.get("schema_version")!=1:raise ValueError("Unsupported macro snapshot")
    results={k:{"label":GROUP_LABELS[k],"observations":[],
                "status":"unavailable","unavailable_reason":"no_current_verified_observation"} for k in GROUPS}
    def add(group,key,label,value,unit,period,source,url,days=None,months=None,formula=None):
        if not finite(value) or not fresh(period,today,days,months):return
        if not isinstance(url,str) or not url.startswith("https://"):return
        item={"id":key,"label":label,"value":round(float(value),6),
              "unit":unit,"observation_period":period,"source":source,
              "source_url":url,"validated_historical_release_time":False,
              "qualifies_as_model_factor_signal":False}
        if formula:item["formula"]=formula
        results[group]["observations"].append(item)
        results[group]["status"]="observations_only"
        results[group]["unavailable_reason"]=None
    treasury=(snapshot.get("rates") or {})
    tdate=snapshot.get("observation_date")
    sources=snapshot.get("source_urls") or []
    def treasury_url(real=False):
        match="type=daily_treasury_real_yield_curve" if real else "type=daily_treasury_yield_curve"
        return next((x for x in sources if isinstance(x,str) and match in x and x.startswith("https://home.treasury.gov/")),"")
    nominal=treasury_url()
    tips=treasury_url(True)
    add("rates","us10y","美国10年期名义国债收益率",treasury.get("us10y"),"percent",tdate,"US Treasury",nominal,days=11)
    add("rates","us2y","美国2年期名义国债收益率",treasury.get("us2y"),"percent",tdate,"US Treasury",nominal,days=11)
    add("rates","real10y","美国10年期TIPS实际收益率",treasury.get("real10y"),"percent",tdate,"US Treasury",tips,days=11)
    # Recalculate BOTH spread and inflation compensation from nominal and real
    # on the same observation date. Treat these as dependent identities.
    if all(finite(treasury.get(k)) for k in ("us10y","us2y")):
        add("rates","spread10y2y","10Y−2Y期限利差",
            treasury["us10y"]-treasury["us2y"],"percentage_points",tdate,
            "US Treasury (derived same-day rates)",nominal,days=11,
            formula="10Y nominal yield minus 2Y nominal yield")
    if all(finite(treasury.get(k)) for k in ("us10y","real10y")):
        add("inflation","breakeven10y","10年期盈亏平衡通胀补偿",
            treasury["us10y"]-treasury["real10y"],"percentage_points",tdate,
            "US Treasury (derived same-day nominal/TIPS)",tips,days=11,
            formula="10Y nominal yield minus 10Y TIPS real yield; not pure expected inflation")
    nyfed=snapshot.get("nyfed") or {}
    add("rates","effr","有效联邦基金利率 EFFR",nyfed.get("effr_percent"),"percent",
        nyfed.get("observation_date"),"New York Fed",
        nyfed.get("source_url"),days=10)
    bls=snapshot.get("bls") or {}
    series=bls.get("series") or {}
    for key,label in (("cpi","美国CPI同比"),("core_cpi","美国核心CPI同比")):
        obj=series.get(key) or {}
        add("inflation",key+"_yoy",label,obj.get("yoy_percent"),"percent",
            obj.get("period"),"US Bureau of Labor Statistics",bls.get("source_url"),months=4)
    core=(snapshot.get("bea") or {}).get("core_pce") or {}
    add("inflation","core_pce_yoy","美国核心PCE同比",core.get("yoy_percent"),"percent",
        core.get("observation_period"),"BEA via FRED",core.get("source_url"),months=4)
    unemployment=series.get("unemployment") or {}
    add("growth","unemployment","美国失业率",unemployment.get("value"),"percent",
        unemployment.get("period"),"US Bureau of Labor Statistics",bls.get("source_url"),months=4)
    payroll=series.get("payroll") or {}
    add("growth","payroll_delta","美国非农就业月度变化",payroll.get("monthly_change_thousands"),"thousands",
        payroll.get("period"),"US Bureau of Labor Statistics",bls.get("source_url"),months=4)
    recession=snapshot.get("nyfed_recession_model") or {}
    observe,target=recession.get("observation_period"),recession.get("target_period")
    try:
        oy,om=map(int,observe.split("-"));ty,tm=map(int,target.split("-"))
        aligned=(ty*12+tm)-(oy*12+om)==12
    except (TypeError,ValueError,AttributeError):
        aligned=False
    if aligned and recession.get("official_forecast") is False:
        add("growth","nyfed_recession_probability","纽约联储收益率曲线模型12个月后衰退概率",
            recession.get("probability_percent"),"percent",observe,
            "New York Fed (research model, not official forecast)",
            recession.get("source_url"),months=4)
    assets=(snapshot.get("fed_h41") or {}).get("total_assets") or {}
    add("liquidity","fed_assets","联储H.4.1总资产",assets.get("value_millions_usd"),"millions_usd",
        assets.get("observation_date"),"Federal Reserve via FRED",assets.get("source_url"),days=21)
    liquidity=snapshot.get("liquidity") or {}
    for key,label,unit,days in (("reserves","银行准备金","millions_usd",21),
                              ("tga","财政部一般账户TGA","millions_usd",21),
                              ("overnight_rrp","隔夜逆回购","billions_usd",11)):
        item=liquidity.get(key) or {}
        if item.get("unit")!=unit:continue
        add("liquidity",key,label,item.get("value"),unit,item.get("observation_date"),
            item.get("source"),item.get("source_url"),days=days)
    # Never create "neutral" proxy observations for risk or asset-specific.
    return {
      "schema_version":1,"report_type":"asset_compass_factor_observations",
      "generated_at":datetime.now(timezone.utc).isoformat(),
      "source_snapshot_observation_date":tdate,
      "groups":results,
      "validated_for_live_scoring":False,
      "factor_signals_calibrated":False,
      "asset_specific_contributions_available":False,
      "independent_factor_group_count_certified":False,
      "no_missing_to_neutral_imputation":True,
      "limitations":[
        "Current official observations are not calibrated factor signals or asset return forecasts.",
        "10Y nominal, TIPS real and break-even inflation are mathematically linked and not independent votes.",
        "No released historical vintage timestamps; newest revisions cannot backfill past trading decisions.",
        "Liquidity components have different units, dates and accounting bases; they cannot be summed into a net-liquidity trade signal.",
        "Market risk/credit and asset-specific valuation/flows lack qualifying source observations.",
        "Missing, stale or unverified observations are never set to neutral or zero."
      ]
    }

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--input",type=Path,default=SOURCE)
    p.add_argument("--output",type=Path,default=OUTPUT)
    args=p.parse_args()
    report=collect(json.loads(args.input.read_text(encoding="utf-8")))
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print("Factor observations only:",{k:len(v["observations"]) for k,v in report["groups"].items()},
          "scoring unlocked:",report["validated_for_live_scoring"])
if __name__=="__main__":main()
