#!/usr/bin/env python3
"""Research-only expanding-window out-of-sample diagnostics.

Input examples from backtest_asset_compass.build_examples. Each sample already
uses the first market close strictly AFTER the signal's availability. Training
labels are purged when their exit date reaches the test window. This reports
diagnostics, not model validation, return forecasts, or investable P&L.
"""
import argparse
import json
from collections import defaultdict
from datetime import datetime,timezone
from pathlib import Path
from scripts.backtest_asset_compass import load_rows,build_examples

def nonoverlap(rows):
    selected=[]
    exit_at=""
    for r in sorted(rows,key=lambda r:r["entry_date"]):
        if r["entry_date"]>exit_at:
            selected.append(r)
            exit_at=r["exit_date"]
    return selected

def walkforward(rows,min_train=126,test_window=63,step=63,min_independent=3):
    if min_train<1 or test_window<1 or step<1 or min_independent<1:
        raise ValueError("Invalid window settings")
    groups=defaultdict(list)
    for row in rows:groups[row["asset"]].append(row)
    results={}
    for asset,items in groups.items():
        data=sorted(items,key=lambda r:r["entry_date"])
        if len(data)<min_train+test_window:
            results[asset]={"status":"insufficient_history","observations":len(data),"folds":[]}
            continue
        folds=[]
        for boundary in range(min_train,len(data)-test_window+1,step):
            test=data[boundary:boundary+test_window]
            start=test[0]["entry_date"]
            train=[r for r in data[:boundary] if r["exit_date"]<start]
            # Enough clean training labels must exist.
            if len(train)<min_train-21:continue
            sampled=nonoverlap(test)
            if len(sampled)<min_independent:continue
            decisions=[1 if x["signal"]>0 else -1 if x["signal"]<0 else 0 for x in sampled]
            actual=[1 if x["forward_return"]>0 else -1 if x["forward_return"]<0 else 0 for x in sampled]
            active=[i for i,v in enumerate(decisions) if v!=0]
            if not active:continue
            hit=sum(decisions[i]==actual[i] for i in active)/len(active)
            base=sum(actual[i]>0 for i in active)/len(active)
            folds.append({
                "train_count":len(train),
                "test_count":len(test),
                "independent_test_count":len(sampled),
                "active_signal_count":len(active),
                "training_last_label_exit":max(x["exit_date"] for x in train),
                "test_first_entry":start,
                "test_last_entry":test[-1]["entry_date"],
                "directional_accuracy":round(hit,5),
                "constant_long_accuracy":round(base,5)
            })
        results[asset]={
            "status":"research_diagnostic_not_validated" if folds else "insufficient_independent_folds",
            "observations":len(data),
            "fold_count":len(folds),
            "folds":folds
        }
    return {
        "report_type":"expanding_window_research_diagnostic",
        "validated_for_live_scoring":False,
        "trained_model":False,
        "warnings":[
            "The scoring function and weights are not optimized or validated by this report.",
            "Historical macro signals must be actual as-published model outputs; backfilled final data is not a valid substitute.",
            "Simple observed prices do not constitute total returns; costs, slippage, roll and distributions remain excluded.",
            "Overlapping test windows across folds may remain; statistical significance cannot be inferred from fold counts."
        ],
        "results":results,
    }

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--signals",type=Path,required=True)
    p.add_argument("--prices",type=Path,required=True)
    p.add_argument("--output",type=Path,required=True)
    p.add_argument("--min-train",type=int,default=126)
    p.add_argument("--test-window",type=int,default=63)
    p.add_argument("--step",type=int,default=63)
    args=p.parse_args()
    root=Path(__file__).resolve().parents[1]
    if args.output.resolve().is_relative_to(root):
        raise ValueError("Research diagnostic must stay outside the public site repository")
    report=walkforward(build_examples(load_rows(args.signals),load_rows(args.prices)),
                       min_train=args.min_train,test_window=args.test_window,step=args.step)
    report["generated_at"]=datetime.now(timezone.utc).isoformat()
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print("Research folds:",{k:v["fold_count"] for k,v in report["results"].items()})
if __name__=="__main__":main()
