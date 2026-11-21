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
CRYPTO_INPUT=ROOT/"apps"/"asset-ranking"/"crypto.json"
# Distinguish futures, price indices, spot-index proxies and ETFs.
PROXIES={
 "gold":{"symbol":"GC=F","kind":"gold_futures_continuous","total_return":False},
 "us_equities":{"symbol":"^GSPC","kind":"sp500_price_index","total_return":False},
 "us_long_bonds":{"symbol":"TLT","kind":"long_treasury_etf_unadjusted_price","total_return":False},
 "usd":{"symbol":"DX-Y.NYB","kind":"dollar_index_price","total_return":False},
 "bitcoin":{"symbol":"BTC-USD","kind":"bitcoin_usd_spot","total_return":False},
 "oil":{"symbol":"CL=F","kind":"wti_futures_continuous","total_return":False},
}
def audit(history, crypto=None):
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
    # BTC uses its own CoinGecko daily UTC calendar, never array-index join
    # against trading days in the Yahoo Finance asset tracker.
    if crypto is not None:
        if crypto.get("source")!="CoinGecko":
            raise ValueError("Crypto history source must be CoinGecko")
        h=crypto.get("history") or {}
        cd=h.get("dates")
        cs=(h.get("series") or {}).get("BTC")
        if not isinstance(cd,list) or not cd or sorted(cd)!=cd or len(set(cd))!=len(cd):
            raise ValueError("Invalid crypto dates")
        if any(date.fromisoformat(day)>date.today() for day in cd):
            raise ValueError("Crypto history contains future dates")
        if cs is not None:
            if not isinstance(cs,list) or len(cs)!=len(cd):
                raise ValueError("Crypto series length mismatch: BTC")
            valid=[]
            for day,price in zip(cd,cs):
                if price is None:continue
                if type(price) not in (float,int) or not math.isfinite(price) or price<=0:
                    raise ValueError("Invalid BTC quote")
                valid.append(day)
            result["bitcoin"]={
              "status":"coverage_only" if valid else "missing",
              "symbol":"BTC","kind":"bitcoin_usd_spot","source":"CoinGecko",
              "source_as_of":crypto.get("asOf"),
              "calendar_observation_dates":len(cd),
              "observation_count":len(valid),"missing_dates":len(cd)-len(valid),
              "coverage_percent":round(100*len(valid)/len(cd),2),
              "first_observation":valid[0] if valid else None,
              "last_observation":valid[-1] if valid else None,
              "total_return_series":False,"eligible_for_return_backtest":False,
              "reason":"licensing_and_price_conventions_not_verified"
            }
    return {"schema_version":1,"report_type":"price_coverage_audit",
      "source":(history.get("source") or "unknown") + (" · CoinGecko" if crypto and crypto.get("source")=="CoinGecko" else ""),
      "source_as_of":history.get("asOf"),
      "source_frequency":history.get("frequency"),
      "calendar_observation_dates":len(dates),"assets":result,
      "validated_for_live_scoring":False,
      "history_is_point_in_time_macro":False,
      "licensing_review_required":True,
      "limitations":[
        "Yahoo Finance and CoinGecko data permissions for public derived outputs remain unverified.",
        "BTC uses an independent daily UTC date axis; calendar coverage percentages are per-source.",
        "Futures continuous prices need contract roll and return convention validation.",
        "Index level excludes dividends; ETF raw close excludes distributions unless adjusted.",
        "Historical price quotes do not establish as-published macro signal vintages.",
        "No strategy PnL, hit-rate or score will be inferred from a price-only audit."
      ]}

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--input",type=Path,default=INPUT)
    p.add_argument("--output",type=Path,default=ROOT/"data"/"asset-compass-price-audit.json")
    p.add_argument("--crypto-input",type=Path,default=CRYPTO_INPUT)
    opts=p.parse_args()
    crypto=json.loads(opts.crypto_input.read_text(encoding="utf-8")) if opts.crypto_input.is_file() else None
    result=audit(json.loads(opts.input.read_text(encoding="utf-8")),crypto)
    opts.output.parent.mkdir(parents=True,exist_ok=True)
    opts.output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print("Price coverage audited:",{k:v["observation_count"] for k,v in result["assets"].items()})
if __name__=="__main__":main()
