#!/usr/bin/env python3
"""V57 real gold CFTC managed-money positioning and 30Y Treasury auction demand.

Research-only current/revised observations. No proxy is a validated forward
return signal, licensed asset total return, original release-vintage or score.
The official source observations are not first-available historical vintages.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import math
import re
import statistics
import urllib.parse
import urllib.request
from datetime import date, datetime, timezone
from pathlib import Path

from scripts.score_macro_assets import score_one, validate_config

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/"data/asset-compass-asset-specific-v57.json"
MODEL=ROOT/"macro/model-config.json"
V56=ROOT/"data/asset-compass-new-sources-v56.json"
CFTC_ENDPOINT="https://publicreporting.cftc.gov/resource/72hh-3qpy.json"
FISCAL_ENDPOINT="https://api.fiscaldata.treasury.gov/services/api/fiscal_service/v1/accounting/od/treasury_securities_auctions_v2"
CFTC_CODE="088691"
ASSETS=("gold","us_equities","us_long_bonds","usd","bitcoin","oil")

# Keep a source-specific, bounded dataset, not an unconstrained scraped catalog.
CFTC_ARGS={
    "$where":"cftc_contract_market_code='088691'",
    "$order":"report_date_as_yyyy_mm_dd DESC",
    "$limit":"350",
}
FISCAL_ARGS={
    "fields":"comp_auction_close_date,security_type,security_term,bid_to_cover_ratio,cusip",
    "filter":"security_type:eq:Bond,comp_auction_close_date:gte:2018-01-01",
    "sort":"-comp_auction_close_date",
    "page[size]":"250",
}


def address(endpoint, args):
    return endpoint+"?"+urllib.parse.urlencode(args, safe=",:", quote_via=urllib.parse.quote)


def retrieve(url, host, opener=None):
    parsed=urllib.parse.urlsplit(url)
    if parsed.scheme!="https" or parsed.hostname!=host or parsed.username or parsed.password:
        raise ValueError("Unapproved official HTTPS endpoint")
    req=urllib.request.Request(url,headers={
        "User-Agent":"Ooglex-AssetCompass-Research/1.0 (public data)",
        "Accept":"application/json"})
    opener=opener or urllib.request.urlopen
    with opener(req,timeout=40) as response:
        final=urllib.parse.urlsplit(response.geturl())
        if final.scheme!="https" or final.hostname!=host:
            raise ValueError("Official data source redirected elsewhere")
        payload=response.read(3_000_001)
    if len(payload)<20 or len(payload)>3_000_000:
        raise ValueError("Empty or unusually large official JSON response")
    return payload


def _decimal(value, name, lo=None, hi=None):
    if isinstance(value, bool) or value is None:
        raise ValueError(f"Missing {name}")
    try:
        x=float(value)
    except (ValueError,TypeError) as exc:
        raise ValueError(f"Non-numeric {name}") from exc
    if not math.isfinite(x) or (lo is not None and x<lo) or (hi is not None and x>hi):
        raise ValueError(f"Out-of-range {name}")
    return x


def _day(value, field):
    if not isinstance(value,str):
        raise ValueError("Missing "+field)
    # CFTC SoQL dates are often YYYY-MM-DDT00:00:00.000
    try:
        day=date.fromisoformat(value[:10])
    except ValueError as exc:
        raise ValueError("Invalid "+field) from exc
    if not re.match(r"^\d{4}-\d{2}-\d{2}(?:$|T)",value):
        raise ValueError("Invalid "+field)
    return day


def parse_gold(raw, *, now=None):
    now=now or datetime.now(timezone.utc)
    try:
        records=json.loads(raw)
    except (TypeError,ValueError) as exc:
        raise ValueError("CFTC JSON invalid") from exc
    if not isinstance(records,list) or not 104<=len(records)<=350:
        raise ValueError("CFTC Gold official filtered historical rows insufficient")
    seen=set()
    rows=[]
    for r in records:
        if not isinstance(r,dict) or str(r.get("cftc_contract_market_code","")).strip()!=CFTC_CODE:
            raise ValueError("CFTC contract not verified as COMEX gold")
        contract=str(r.get("market_and_exchange_names") or r.get("commodity_name") or "").upper()
        if "GOLD" not in contract:
            raise ValueError("CFTC result not gold")
        day=_day(r.get("report_date_as_yyyy_mm_dd"),"CFTC report date")
        # CFTC may move the report-as-of day to MONDAY when the regular
        # Tuesday is a US holiday, e.g. 2025-11-10 before Veterans Day.
        # Preserve actual date instead of silently relabeling it Tuesday.
        if day.weekday() not in (0,1) or day>now.date() or day.isoformat() in seen:
            raise ValueError(f"CFTC report date not unique past Monday holiday exception or Tuesday: {day.isoformat()} weekday={day.weekday()} duplicate={day.isoformat() in seen}")
        seen.add(day.isoformat())
        oi=_decimal(r.get("open_interest_all"),"open interest",lo=1000,hi=100_000_000)
        longs=_decimal(r.get("m_money_positions_long_all"),"managed long",lo=0,hi=oi)
        shorts=_decimal(r.get("m_money_positions_short_all"),"managed short",lo=0,hi=oi)
        net=longs-shorts
        rows.append({"date":day.isoformat(),"managed_money_net_contracts":int(net),
                     "managed_money_net_pct_open_interest":round(100*net/oi,6),
                     "open_interest_contracts":int(oi)})
    rows.sort(key=lambda x:x["date"])
    if len(rows)<104:
        raise ValueError("CFTC Gold at least 104 unique weeks required")
    return rows


def parse_treasury(raw, *, now=None):
    now=now or datetime.now(timezone.utc)
    try:
        d=json.loads(raw)
    except (TypeError,ValueError) as exc:
        raise ValueError("Treasury Fiscal Data JSON invalid") from exc
    if not isinstance(d,dict) or not isinstance(d.get("data"),list):
        raise ValueError("FiscalData data envelope missing")
    rows=[]
    seen=set()
    for r in d["data"]:
        if r.get("security_type")!="Bond":
            continue
        term=str(r.get("security_term") or "")
        if not re.match(r"^30[- ]Year",term,re.I):
            continue
        if r.get("bid_to_cover_ratio") in (None,"","null"):
            continue # a not-yet-auctioned official announcement, not a zero
        day=_day(r.get("comp_auction_close_date") or r.get("auction_date"),"30Y auction close date")
        if day>now.date():
            raise ValueError("Treasury auction result dated in future")
        cusip=str(r.get("cusip") or "")
        if not re.fullmatch(r"[0-9A-Z]{9}",cusip):
            raise ValueError("Missing valid Treasury auction CUSIP")
        key=(day.isoformat(),cusip)
        if key in seen:
            raise ValueError("Duplicate official 30Y auction record")
        seen.add(key)
        ratio=_decimal(r["bid_to_cover_ratio"],"30Y bid-to-cover",lo=1,hi=10)
        rows.append({"auction_date":day.isoformat(),"cusip":cusip,
                     "bid_to_cover_ratio":round(ratio,5),"security_term":term})
    rows.sort(key=lambda x:(x["auction_date"],x["cusip"]))
    if len(rows)<36:
        raise ValueError("Insufficient genuine 30Y completed bond auctions")
    return rows


def _normalized(values,current):
    base=values
    mu=statistics.fmean(base)
    std=statistics.pstdev(base,mu=mu)
    z=(current-mu)/std if std>1e-10 else None
    return {
        "reference_count":len(base),
        "reference_mean":round(mu,6),
        "reference_std":round(std,6),
        "research_z_score":round(z,6) if z is not None else None,
        "research_normalized_tanh":round(math.tanh(z/2),6) if z is not None else None,
        "independently_calibrated":False,
    }


def build(gold,bond,config,v56,*,now=None,source_hashes=None):
    now=now or datetime.now(timezone.utc)
    if now.utcoffset() is None:
        raise ValueError("Timezone-aware reference time required")
    now=now.astimezone(timezone.utc)
    validate_config(config)
    if set(config["weights"])!=set(ASSETS):
        raise ValueError("Six-asset contract mismatch")
    if (not isinstance(v56,dict)
        or v56.get("report_type")!="asset_compass_v56_official_risk_and_oil_research"
        or v56.get("validated_for_live_scoring") is not False
        or v56.get("approved_asset_scores")!=0
        or v56.get("assets_with_asset_specific_source_observations")!=["oil"]):
        raise ValueError("V56 source lineage not validated")
    source_hashes=source_hashes or {}
    for key in ("cftc_gold","treasury_30y"):
        if not re.fullmatch(r"[0-9a-f]{64}",str(source_hashes.get(key) or "")):
            raise ValueError("Missing original source response SHA-256")
    if len(gold)<105 or len(bond)<37:
        raise ValueError("Actual historical reference windows are incomplete")
    g=gold[-1];b=bond[-1]
    gold_age=(now.date()-date.fromisoformat(g["date"])).days
    bond_age=(now.date()-date.fromisoformat(b["auction_date"])).days
    if min(gold_age,bond_age)<0:
        raise ValueError("Future reported source data")
    gold_stat=_normalized([r["managed_money_net_pct_open_interest"]
                           for r in gold[-105:-1]],g["managed_money_net_pct_open_interest"])
    bond_stat=_normalized([r["bid_to_cover_ratio"]
                           for r in bond[-37:-1]],b["bid_to_cover_ratio"])
    gold_stat.update({
        "series_id":"CFTC_COMEX_GOLD_MANAGED_MONEY_FUTURES_ONLY",
        "source_url":address(CFTC_ENDPOINT,CFTC_ARGS),
        "series_home":"https://www.cftc.gov/MarketReports/CommitmentsofTraders/index.htm",
        "source_owner":"Commodity Futures Trading Commission",
        "source_sha256":source_hashes["cftc_gold"],
        "latest_observation_date":g["date"],
        "latest_managed_money_net_contracts":g["managed_money_net_contracts"],
        "latest_managed_money_net_percent_oi":g["managed_money_net_pct_open_interest"],
        "latest_open_interest_contracts":g["open_interest_contracts"],
        "age_calendar_days":gold_age,
        "fresh_for_research":gold_age<=18,
        "recent_observations":gold[-110:],
        "observation_count":len(gold),
        "non_tuesday_report_dates": [r["date"] for r in gold if
            date.fromisoformat(r["date"]).weekday()!=1][-24:],
        "non_tuesday_exception_approved_as_pit":False,
        "report_date_is_publication_time":False,
        "signal_verified":False,
        "known_release_lag":"Tuesday position snapshot generally published Friday; holiday/delayed reports vary",
        "not_a_gold_spot_etf_flow":True,
    })
    bond_stat.update({
        "series_id":"TREASURY_30Y_BOND_AUCTION_BID_TO_COVER",
        "source_url":address(FISCAL_ENDPOINT,FISCAL_ARGS),
        "series_home":"https://fiscaldata.treasury.gov/datasets/treasury-securities-auctions-data/",
        "source_owner":"U.S. Department of the Treasury (FiscalData)",
        "source_sha256":source_hashes["treasury_30y"],
        "latest_auction_date":b["auction_date"],
        "latest_auction_cusip":b["cusip"],
        "latest_bid_to_cover_ratio":b["bid_to_cover_ratio"],
        "age_calendar_days":bond_age,
        "fresh_for_research":bond_age<=75,
        "recent_auctions":bond[-48:],
        "auction_count":len(bond),
        "auction_date_is_publication_time":False,
        "signal_verified":False,
        "not_a_total_return_or_whole_curve_demand":True,
    })
    gold_known=gold_stat["fresh_for_research"]
    bond_known=bond_stat["fresh_for_research"]
    oil_known=v56.get("sources",{}).get("oil_inventory",{}).get("current_observation_fresh") is True
    available=({"gold"} if gold_known else set())|({"us_long_bonds"} if bond_known else set())|({"oil"} if oil_known else set())
    assets={}
    for a in ASSETS:
        blocked=score_one(a,{},config,{})
        if blocked["score"] is not None:
            raise ValueError("Unqualified source escaped scoring gate")
        assets[a]={
            "asset_specific_research_source_available":a in available,
            "sources":(["cftc_gold"] if a=="gold" and gold_known else [])+
                      (["treasury_30y"] if a=="us_long_bonds" and bond_known else [])+
                      (["v56_oil_inventory"] if a=="oil" and oil_known else []),
            "verified_asset_specific_model_signal":False,
            "historic_as_published_vintages_certified":False,
            "historical_calibration_passed":False,
            "out_of_sample_validation_passed":False,
            "score":None,
            "blocked_by":blocked["blocked_by"],
        }
    return {
        "schema_version":1,
        "report_type":"asset_compass_v57_authentic_asset_specific_source_research",
        "status":"research_only_no_model_promotion",
        "generated_at":now.isoformat(),
        "sources":{"cftc_gold":gold_stat,"treasury_30y":bond_stat},
        "v56_observed_at":v56.get("generated_at"),
        "v56_oil_source_date":v56.get("sources",{}).get("oil_inventory",{}).get("latest_observation_date"),
        "assets":assets,
        "asset_specific_source_available_assets":sorted(available),
        "asset_specific_source_missing_assets":sorted(set(ASSETS)-available),
        "source_completeness_6_assets":len(available),
        "first_publication_vintages_certified":0,
        "independent_model_factor_qualified_count":0,
        "approved_asset_scores":0,
        "validated_for_live_scoring":False,
        "eligible_for_point_in_time_backtest":False,
        "automated_trading_alerts_enabled":False,
        "limitations":[
            "CFTC dates are Tuesday positioning snapshots, not public availability timestamps.",
            "Treasury auction date is not proof of exact first-released timestamp or revision vintage.",
            "CFTC net managed-money positioning can indicate crowdedness, not future gold return.",
            "30Y bid-to-cover is specific-auction demand, not total-return or ETF demand.",
            "No exposure is treated as an independent certified signal or input to 0–100 scoring.",
            "Only three assets have some asset-specific source data; the other three still lack inputs.",
            "No PIT-certified historical returns, licensed spread or sample-out-of-sample calibration.",
        ],
    }


def main():
    p=argparse.ArgumentParser()
    p.add_argument("--fetch",action="store_true")
    p.add_argument("--cftc-json",type=Path)
    p.add_argument("--treasury-json",type=Path)
    p.add_argument("--v56",type=Path,default=V56)
    p.add_argument("--model",type=Path,default=MODEL)
    p.add_argument("--output",type=Path,default=OUT)
    a=p.parse_args()
    if a.fetch==bool(a.cftc_json or a.treasury_json):
        p.error("Provide --fetch OR both --cftc-json and --treasury-json")
    if a.fetch:
        c=retrieve(address(CFTC_ENDPOINT,CFTC_ARGS),"publicreporting.cftc.gov")
        t=retrieve(address(FISCAL_ENDPOINT,FISCAL_ARGS),"api.fiscaldata.treasury.gov")
    else:
        if not (a.cftc_json and a.treasury_json):
            p.error("Both original JSON files required")
        c,t=a.cftc_json.read_bytes(),a.treasury_json.read_bytes()
    now=datetime.now(timezone.utc)
    gold=parse_gold(c,now=now)
    bond=parse_treasury(t,now=now)
    report=build(gold,bond,
       json.loads(a.model.read_text(encoding="utf-8")),
       json.loads(a.v56.read_text(encoding="utf-8")),
       now=now,source_hashes={
        "cftc_gold":hashlib.sha256(c).hexdigest(),
        "treasury_30y":hashlib.sha256(t).hexdigest(),
       })
    a.output.parent.mkdir(parents=True,exist_ok=True)
    a.output.write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(json.dumps({
      "status":report["status"],
      "gold_cot_weeks":report["sources"]["cftc_gold"]["observation_count"],
      "treasury_30y_auctions":report["sources"]["treasury_30y"]["auction_count"],
      "gold_latest_date":report["sources"]["cftc_gold"]["latest_observation_date"],
      "treasury_latest_date":report["sources"]["treasury_30y"]["latest_auction_date"],
      "gold_age_days":report["sources"]["cftc_gold"]["age_calendar_days"],
      "treasury_age_days":report["sources"]["treasury_30y"]["age_calendar_days"],
      "cftc_holiday_exceptions":report["sources"]["cftc_gold"]["non_tuesday_report_dates"],
      "asset_specific_source_available":report["asset_specific_source_available_assets"],
      "scores_published":0,"pit_vintages_certified":0,
    },ensure_ascii=False))
    if not (report["sources"]["cftc_gold"]["fresh_for_research"] and
            report["sources"]["treasury_30y"]["fresh_for_research"]):
        raise SystemExit("V57 source stale; report created but cannot qualify as current")


if __name__=="__main__":
    main()
