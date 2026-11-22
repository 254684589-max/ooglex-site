#!/usr/bin/env python3
"""V10 production artifact acceptance for Ooglex Macro V1–V9.

Static build validation only: successful local artifacts do NOT establish a live
deployment. No trading or PIT eligibility can be inferred from artifact presence.
"""
import json
from pathlib import Path
import argparse

PAGES = ("index.html","overview.html","attribution.html","research.html",
         "swap-spreads.html","indicator-ratings.html","indicator-lab.html","operations.html")
SCRIPTS = ("compass-pages.js","treasury-trends.js",
           "indicator-observations.js","indicator-history.js",
           "indicator-correlations.js","indicator-leadlag.js",
           "indicator-quality.js","indicator-provenance-v7.js",
           "indicator-monitor-v8.js","operations-v9.js","indicator-a10.js")
DATA = ("asset-scores.json","asset-compass-treasury-history.json",
        "asset-compass-history-readiness.json",
        "asset-compass-observation-ledger.jsonl",
        "asset-compass-provenance-v7.json",
        "asset-compass-monitor-v8.json",
        "asset-compass-monitor-events-v8.jsonl")
def accept(root):
    root=Path(root)
    errors=[]
    for filename in PAGES+SCRIPTS+("compass-pages.css","model-config.json"):
        if not (root/"macro"/filename).is_file():
            errors.append("missing macro/"+filename)
    for filename in DATA:
        if not (root/"data"/filename).is_file():
            errors.append("missing data/"+filename)
    for filename in PAGES:
        path=root/"macro"/filename
        if not path.is_file():continue
        html=path.read_text(encoding="utf-8")
        if 'href="./operations.html"' not in html:
            errors.append(filename+" missing operations navigation")
        if 'href="./indicator-ratings.html"' not in html:
            errors.append(filename+" missing indicator ratings navigation")
    for filename,script in (("operations.html","operations-v9.js"),
                            ("indicator-lab.html","indicator-history.js"),
                            ("indicator-lab.html","indicator-correlations.js"),
                            ("indicator-lab.html","indicator-leadlag.js"),
                            ("indicator-lab.html","indicator-quality.js"),
                            ("indicator-lab.html","indicator-monitor-v8.js"),
                            ("indicator-ratings.html","indicator-a10.js")):
        path=root/"macro"/filename
        if path.is_file() and 'src="./'+script+'"' not in path.read_text(encoding="utf-8"):
            errors.append(filename+" missing "+script)
    ratings_path=root/"macro"/"indicator-ratings.html"
    if ratings_path.is_file():
        ratings=ratings_path.read_text(encoding="utf-8")
        for marker in ('id="indicator-rows"','id="a10-rows"','href="./indicator-lab.html"'):
            if marker not in ratings:
                errors.append("ratings page lacks core catalog: "+marker)
        if 'id="v8-heading"' in ratings or 'id="quality-asset-rows"' in ratings:
            errors.append("operational audits or asset-scoring panels leaked into indicator catalog")
    for filename in DATA:
        path=root/"data"/filename
        if not path.is_file():continue
        if filename.endswith(".jsonl"):
            try:
                lines=[json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
                if not lines:errors.append(filename+" has no events")
            except (ValueError, OSError) as exc: errors.append(filename+" invalid JSONL: "+str(exc))
        else:
            try:json.loads(path.read_text(encoding="utf-8"))
            except (ValueError,OSError) as exc:errors.append(filename+" invalid JSON: "+str(exc))
    def obj(name):
        p=root/"data"/name
        return json.loads(p.read_text(encoding="utf-8")) if p.is_file() else {}
    try:
        snapshot=obj("asset-scores.json")
        readiness=obj("asset-compass-history-readiness.json")
        provenance=obj("asset-compass-provenance-v7.json")
        monitor=obj("asset-compass-monitor-v8.json")
        if not snapshot.get("assets") or any(x.get("score") is not None for x in snapshot["assets"].values()):
            errors.append("production asset scoring unexpectedly enabled")
        if readiness.get("validated_for_live_scoring") is not False or readiness.get("eligible_for_point_in_time_backtest") is not False:
            errors.append("historical readiness gate unexpectedly unlocked")
        if provenance.get("legacy_rows_are_valid_evidence") is not False or provenance.get("validated_for_live_scoring") is not False:
            errors.append("provenance gate unexpectedly unlocked")
        if monitor.get("validated_for_live_scoring") is not False or monitor.get("point_in_time_backtest_eligible") is not False:
            errors.append("operations monitor gate unexpectedly unlocked")
    except (ValueError,TypeError,AttributeError,KeyError) as exc:
        errors.append("could not validate model gate: "+str(exc))
    return errors

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--root",type=Path,default=Path(".site"))
    args=p.parse_args()
    errors=accept(args.root)
    if errors:raise SystemExit("V10 production artifact FAILED:\n"+"\n".join(errors))
    print("V10 artifact acceptance PASSED: macro pages, scripts, datasets and fail-closed model status")
if __name__=="__main__":main()
