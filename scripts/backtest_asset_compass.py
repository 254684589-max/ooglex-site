#!/usr/bin/env python3
"""Walk-forward historical evaluation of asset signals, independent of live snapshot.

Input CSV:
  signals: asset,observation_date,available_at,score
  prices: asset,date,close
A signal released at any time enters at the CLOSE of the first trading session
strictly after both its observation date and its UTC publication date; returns
start only from that future entry close. 21-session forward labels and
non-overlapping test horizons are purged.
No synthetic or demo files are accepted as production evidence.
"""
import argparse
import csv
import json
import math
from collections import defaultdict
from datetime import date, datetime, timezone
from pathlib import Path
from statistics import mean

HORIZON=21
MIN_TRAIN=126
MIN_TEST=30

def dt(v):
    return date.fromisoformat(v)

def parse_timestamp(value):
    s=value.strip()
    if not s:raise ValueError("Missing publication timestamp")
    t=datetime.fromisoformat(s.replace("Z","+00:00"))
    if t.tzinfo is None:raise ValueError("Publication timestamp must include timezone")
    return t.astimezone(timezone.utc)

def load_rows(path):
    with open(path,newline="",encoding="utf-8-sig") as f:return list(csv.DictReader(f))

def build_examples(signals,prices,horizon=HORIZON):
    by_asset=defaultdict(dict)
    for p in prices:
        d=dt(p["date"]);v=float(p["close"])
        if not math.isfinite(v) or v<=0:raise ValueError("Invalid close")
        if d in by_asset[p["asset"]]:raise ValueError("Duplicate asset price date")
        by_asset[p["asset"]][d]=v
    ordered={a:sorted(d.items()) for a,d in by_asset.items()}
    observations=[]
    seen=set()
    for s in signals:
        asset=s["asset"];d=dt(s["observation_date"])
        available=parse_timestamp(s["available_at"])
        if available.date()<d:raise ValueError("Signal publication predates observation date")
        val=float(s["score"])
        if not math.isfinite(val) or not 0<=val<=100:raise ValueError("Score out of range")
        if (asset,d) in seen:raise ValueError("Duplicate signal/date")
        seen.add((asset,d))
        history=ordered.get(asset,[])
        # Do not use same-day close for a signal of unknown intraday release time.
        earliest=max(d,available.date())
        idx=next((i for i,(pd,_) in enumerate(history) if pd>earliest),None)
        if idx is None or idx+horizon>=len(history):continue
        entry_date,entry_price=history[idx]
        if (entry_date-earliest).days>7:continue
        future_date,future_price=history[idx+horizon]
        observations.append({"asset":asset,"date":d.isoformat(),
                             "available_at":available.isoformat(),
                             "entry_date":entry_date.isoformat(),
                             "exit_date":future_date.isoformat(),
                             "signal":(val-50)/50,
                             "forward_return":future_price/entry_price-1})
    return sorted(observations,key=lambda r:(r["asset"],r["entry_date"]))

def evaluate(rows,min_train=MIN_TRAIN,min_test=MIN_TEST,horizon=HORIZON):
    result={}
    by_asset=defaultdict(list)
    for x in rows:by_asset[x["asset"]].append(x)
    for asset,data in by_asset.items():
        data=sorted(data,key=lambda x:x["entry_date"])
        # Reserve newest 25% for final test, require a substantial training history.
        split=max(min_train,int(len(data)*0.75))
        if len(data)-split<min_test:
            result[asset]={"status":"insufficient_history","observations":len(data)}
            continue
        train=data[:split];test=data[split:]
        # No training label may depend on price after the first test decision.
        test_start=test[0]["entry_date"]
        train=[x for x in train if x["exit_date"]<test_start]
        if len(train)<min_train-horizon:
            result[asset]={"status":"insufficient_purged_train","observations":len(data)}
            continue
        # Keep non-overlapping observations to avoid pretending they are independent.
        sampled=[];last_exit=""
        for x in test:
            if x["entry_date"]>last_exit:
                sampled.append(x);last_exit=x["exit_date"]
        if len(sampled)<2:
            result[asset]={"status":"insufficient_independent_test","observations":len(data)}
            continue
        # Directional score vs flat and constant-long baselines (not a trading strategy).
        predicted=[1 if x["signal"]>0 else -1 if x["signal"]<0 else 0 for x in sampled]
        actual=[1 if x["forward_return"]>0 else -1 if x["forward_return"]<0 else 0 for x in sampled]
        nonneutral=[i for i,v in enumerate(predicted) if v!=0]
        hit=sum(predicted[i]==actual[i] for i in nonneutral)/len(nonneutral) if nonneutral else None
        naive_long=sum(r>0 for r in (x["forward_return"] for x in sampled))/len(sampled)
        result[asset]={"status":"diagnostic_only_not_calibrated","training_obs":len(train),
          "test_obs":len(test),"non_overlapping_test_obs":len(sampled),
          "directional_hit_rate":round(hit,4) if hit is not None else None,
          "constant_long_hit_rate":round(naive_long,4),
          "mean_forward_return":round(mean(x["forward_return"] for x in sampled),6),
          "first_test":test[0]["entry_date"],"last_test":test[-1]["entry_date"],
          "horizon_trading_sessions":horizon,
          "limitations":"Requires real as-published signals, licensed total-return/price history, costs and multi-regime walk-forward tests."}
    return result

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--signals",required=True,type=Path)
    p.add_argument("--prices",required=True,type=Path)
    p.add_argument("--output",required=True,type=Path)
    args=p.parse_args()
    if args.signals.resolve()==args.prices.resolve():raise ValueError("Inputs must be independent")
    report={"report_type":"research_diagnostic","validated_for_live_scoring":False,
      "generated_at":datetime.now(timezone.utc).isoformat(),
      "methodology":"Next-session-close execution after both observation and UTC publication date; 21-session forward returns, chronological holdout, purged train, non-overlapping test",
      "results":evaluate(build_examples(load_rows(args.signals),load_rows(args.prices)))}
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print("Backtest diagnostic written:",args.output)
if __name__=="__main__":main()
