#!/usr/bin/env python3
"""Audit existing Ooglex price observations for Asset Compass research.

This tool does not output trading signals, validated asset returns or an
authorization to redistribute Yahoo Finance data. It only reports coverage.
"""
import argparse
import json
import math
from datetime import date
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
INPUT=ROOT/"apps"/"asset-tracker"/"history.json"
# Distinguish futures, price indices, spot-index proxies and ETFs.
PROXIES={
 "gold":{"symbol":"GC=F","kind":"gold_futures_continuous","total_return":False},
 "us_equities":{"symbol":"^GSPC","kind":"sp500_price_index","total_return":False},
 "us_long_bonds":{"symbol":"TLT","kind":"long_treasury_etf_unadjusted_price","total_return":False},
 "usd":{"symbol":"DX-Y.NYB","kind":"dollar_index_price","total_return":False},
 "bitcoin":{"symbol":"BTC-USD","kind":"bitcoin_usd_spot","total_return":False},
 "oil":{"symbol":"CL=F","kind":"wti_futures_continuous","total_return":False},
}
def audit(history):
    dates=history.get("dates",[])
    series=history.get("series",{})
    if not isinstance(dates,list) or len(dates)!=len(set(dates)):
        raise ValueError("Invalid or duplicate dates")
    if sorted(dates)!=dates or any(date.fromisoformat(d)>date.today() for d in dates):
        raise ValueError("Dates unsorted or in future")
    result={}
    for asset,proxy in PROXIES.items():
        symbol=proxy["symbol"]
        values=series.get(symbol)
        if values is None:
            result[asset]={"status":"missing","symbol":symbol,"observation_count":0,
              "eligible_for_return_backtest":False,"reason":"symbol_absent"}
            continue
        if not isinstance(values,list) or len(values)!=len(dates):
            raise ValueError("Series length mismatch: "+symbol)
        points=[]
        for day,value in zip(dates,values):
            if value is None:continue
            if type(value) not in (int,float) or not math.isfinite(value) or value<=0:
                raise ValueError("Non-positive or invalid quote: "+symbol)
            points.append((day,value))
        gap=len(dates)-len(points)
        result[asset]={"status":"coverage_only","symbol":symbol,"kind":proxy["kind"],
          "observation_count":len(points),"missing_dates":gap,
          "coverage_percent":round(len(points)*100/len(dates),2) if dates else 0,
          "first_observation":points[0][0] if points else None,
          "last_observation":points[-1][0] if points else None,
          "total_return_series":proxy["total_return"],
          "eligible_for_return_backtest":False,
          "reason":"licensing_and_price_conventions_not_verified"}
    return {"schema_version":1,"report_type":"price_coverage_audit",
      "source":history.get("source"),"source_as_of":history.get("asOf"),
      "source_frequency":history.get("frequency"),
      "calendar_observation_dates":len(dates),"assets":result,
      "validated_for_live_scoring":False,
      "history_is_point_in_time_macro":False,
      "licensing_review_required":True,
      "limitations":[
        "Yahoo Finance source permissions for public derived outputs remain unverified.",
        "Futures continuous prices need contract roll and return convention validation.",
        "Index level excludes dividends; ETF raw close excludes distributions unless adjusted.",
        "Historical price quotes do not establish as-published macro signal vintages.",
        "No strategy PnL, hit-rate or score will be inferred from a price-only audit."
      ]}

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--input",type=Path,default=INPUT)
    p.add_argument("--output",type=Path,default=ROOT/"data"/"asset-compass-price-audit.json")
    opts=p.parse_args()
    result=audit(json.loads(opts.input.read_text(encoding="utf-8")))
    opts.output.parent.mkdir(parents=True,exist_ok=True)
    opts.output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print("Price coverage audited:",{k:v["observation_count"] for k,v in result["assets"].items()})
if __name__=="__main__":main()
