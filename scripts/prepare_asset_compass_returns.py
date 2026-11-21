#!/usr/bin/env python3
"""Research-only daily observed-close returns for six different asset proxies.

Not investment total returns: index excludes dividends, raw ETF close excludes
distributions, futures contract rolls/carry require separate accounting.
Uses independent source calendars. Never forward-fills or back-fills missing
quotes. Output is local, never uploaded by the Pages build pipeline.
"""
import argparse
import json
import math
from datetime import date
from pathlib import Path
from scripts.audit_asset_compass_prices import PROXIES, INPUT, CRYPTO_INPUT

def extract_rows(dates, values, symbol):
    if not isinstance(dates,list) or not isinstance(values,list) or len(dates)!=len(values):
        raise ValueError("Date/price count mismatch: "+symbol)
    if dates!=sorted(set(dates)):
        raise ValueError("Dates must be ascending and unique: "+symbol)
    result=[]
    for ds,p in zip(dates,values):
        day=date.fromisoformat(ds)
        if day>date.today():raise ValueError("Future price")
        if p is None:continue
        if type(p) not in (int,float) or not math.isfinite(p) or p<=0:
            raise ValueError("Invalid price: "+symbol)
        result.append((ds,float(p)))
    return result

def research_returns(tracker,crypto=None,max_gap_days=4):
    if max_gap_days<1:raise ValueError("Invalid gap")
    sources={}
    for asset,p in PROXIES.items():
        symbol=p["symbol"]
        rows=None
        origin=tracker.get("source") or "unknown"
        if asset=="bitcoin" and crypto and crypto.get("source")=="CoinGecko":
            h=crypto.get("history") or {}
            if "BTC" in (h.get("series") or {}):
                symbol="BTC"
                origin="CoinGecko"
                rows=extract_rows(h.get("dates"),h["series"]["BTC"],symbol)
        if rows is None and symbol in (tracker.get("series") or {}):
            rows=extract_rows(tracker.get("dates"),tracker["series"][symbol],symbol)
        if rows is None:
            sources[asset]={"status":"missing","source":origin,"symbol":symbol,
                            "observation_count":0,"returns":[]}
            continue
        results=[]
        for (d0,p0),(d1,p1) in zip(rows,rows[1:]):
            gap=(date.fromisoformat(d1)-date.fromisoformat(d0)).days
            if 1<=gap<=max_gap_days:
                results.append({"date":d1,"previous_observation_date":d0,"simple_return":round(p1/p0-1,10)})
        sources[asset]={"status":"research_only","source":origin,"symbol":symbol,
            "observation_count":len(rows),"return_observations":len(results),
            "return_definition":"observed_close_to_prior_observed_close; NOT investment total return",
            "returns":results}
    return {"schema_version":1,"report_type":"research_price_returns",
      "validated_for_live_scoring":False,
      "licensed_for_public_redistribution":False,
      "proxy_total_return_comparable":False,
      "note":"Private research only. Not macro point-in-time signals, not a backtest.",
      "assets":sources}

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--tracker",type=Path,default=INPUT)
    ap.add_argument("--crypto",type=Path,default=CRYPTO_INPUT)
    ap.add_argument("--output",required=True,type=Path)
    args=ap.parse_args()
    if args.output.resolve().is_relative_to(Path(__file__).resolve().parents[1]):
        raise ValueError("Do not save unlicensed research returns inside the public site repository")
    tr=json.loads(args.tracker.read_text(encoding="utf-8"))
    cr=json.loads(args.crypto.read_text(encoding="utf-8")) if args.crypto.is_file() else None
    report=research_returns(tr,cr)
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(report,ensure_ascii=False,separators=(",",":"))+"\n",encoding="utf-8")
    print({k:v.get("return_observations",0) for k,v in report["assets"].items()})
if __name__=="__main__":main()
