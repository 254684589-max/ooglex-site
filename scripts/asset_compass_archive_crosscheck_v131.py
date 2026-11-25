"""V131–V137: compare archive headline candidates with current FRED observations.

A match does NOT establish historical publication identity or a vintage chain.
"""
import argparse
import hashlib
import json
import time
from decimal import Decimal
from pathlib import Path
from scripts.asset_compass_six_feature_v90 import parse_series,URL
from scripts.build_asset_compass_new_sources_v56 import fetch_official
from scripts.capture_asset_compass_official_v51 import _private_path
from scripts.asset_compass_monthly_diagnostic_v69 import prev

def compare(records,series):
    by={k:{r["date"][:7]:Decimal(str(r["value"])) for r in rows} for k,rows in series.items()}
    wanted={("bls.cpi","headline_yoy_rate"):"CPIAUCNS",
            ("bls.unemployment","monthly_unemployment_rate"):"UNRATE"}
    rows=[];excluded=[];seen=set()
    for record in records:
        p=record["source"]["observation_period"]
        if record["reissue_notice_detected"] or record["header"]["header_status"]!="publisher_header_matches_archive_date":
            excluded.append(record["source"]["artifact_id"]);continue
        for m in record["metrics"]:
            sid=wanted.get((m["source_series_id"],m["statistic"]))
            if not sid:continue
            if m["observation_period"]!=p or (sid,p) in seen or m["source_document_sha256"]!=record["sha256"]:
                raise ValueError("Duplicate or mismatched archive observation")
            seen.add((sid,p))
            latest=by[sid].get(p)
            if sid=="CPIAUCNS":
                prior=by[sid].get(prev(p,12))
                latest=(latest/prior-1)*100 if latest is not None and prior is not None and prior>0 else None
            published=Decimal(m["value_reported"])
            if not published.is_finite():raise ValueError("Invalid archive statistic")
            # CPI headline is rounded to 0.1 percentage point; UNRATE is
            # normally published at the same precision. Compare within 0.05.
            gap=None if latest is None else abs(latest-published)
            status="current_source_missing" if gap is None else "within_reported_rounding" if gap<=Decimal("0.05") else "different_current_value"
            rows.append({"series":sid,"period":p,"status":status,"archive_sha256":record["sha256"],
                         "absolute_difference_pct":None if gap is None else float(gap),
                         "historical_pit_certified":False})
    counts={}
    for sid in wanted.values():
        rr=[r for r in rows if r["series"]==sid]
        counts[sid]={"compared_candidates":len(rr),
            **{s:sum(r["status"]==s for r in rr) for s in ("within_reported_rounding","different_current_value","current_source_missing")},
            "max_absolute_difference_pct":max((r["absolute_difference_pct"] for r in rr if r["absolute_difference_pct"] is not None),default=None)}
    return {"report_type":"asset_compass_v131_archive_current_crosscheck",
            "series":counts,"excluded_archive_ids":sorted(excluded),"comparisons":rows,
            "historical_pit_certified_series":0,"eligible_for_live_scoring":False,
            "note":"Current FRED observation versus archived headline; differences are not independently proven revision events."}

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--archive",type=Path,required=True)
    p.add_argument("--output",type=Path,required=True)
    a=p.parse_args()
    src=_private_path(a.archive);out=_private_path(a.output)
    if src==out:raise ValueError("Distinct private paths required")
    data={};receipts={}
    for sid in ("CPIAUCNS","UNRATE"):
        url=URL.format(sid)
        raw=fetch_official(url,"fred.stlouisfed.org")
        data[sid]=parse_series(raw,sid)
        receipts[sid]={"url":url,"sha256":hashlib.sha256(raw).hexdigest(),"observations":len(data[sid])}
        time.sleep(1)
    r=compare(json.loads(src.read_text()),data)
    r["source_receipts"]=receipts
    out.write_text(json.dumps(r,indent=2,allow_nan=False)+"\n")
    print(json.dumps({k:r[k] for k in ("series","excluded_archive_ids","historical_pit_certified_series","eligible_for_live_scoring")}))
    if any(v["compared_candidates"]<1 for v in r["series"].values()):raise SystemExit(1)

if __name__=="__main__":main()
