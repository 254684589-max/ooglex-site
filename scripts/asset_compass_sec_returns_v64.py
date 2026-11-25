#!/usr/bin/env python3
"""V64: bounded TLT SEC backfill, with explicit missing months; no scoring."""
from __future__ import annotations
import argparse
import json
import time
import urllib.request
import urllib.error
from pathlib import Path
from decimal import Decimal
from scripts.asset_compass_sec_returns_v63 import ROOT, MAX_BYTES, parse_filing, source_url

# Seven reviewed filing identities; five have B.5 values cross-read in SEC rendered pages.
REGISTRY = {
    "000175272425011820": "2024-11-30",
    "000175272425087689": "2025-02-28",
    "000175272425178050": "2025-05-31",
    "000207169125003725": "2025-08-31",
    "000207169126001287": "2025-11-30",
    "000207169126008193": "2026-02-28",
    "000207169126016714": "2026-05-31",
}
REFERENCE = {
    "000175272425087689": ("-6.165729", "0.456097", "5.598628"),
    "000175272425178050": ("-1.261172", "-1.442555", "-3.110005"),
    "000207169125003725": ("2.649504", "-1.048409", "-0.091935"),
    "000207169126008193": ("-2.528092", "-0.083174", "4.526658"),
    "000207169126016714": ("-4.147675", "-0.861366", "0.507649"),
}

def month_range():
    return [f"{i//12:04d}-{i%12+1:02d}" for i in range(2024*12+8, 2026*12+5)]

def check_reference(filing):
    expected = REFERENCE.get(filing["accession"])
    if expected is not None:
        actual = tuple(Decimal(r["reported_fund_total_return_percent"]) for r in filing["monthly_observations"])
        if actual != tuple(map(Decimal, expected)):
            raise ValueError("Mismatch with independently read SEC display values")
    return expected is not None

def build(raw_by_accession):
    if set(raw_by_accession) - set(REGISTRY):
        raise ValueError("Unknown accession")
    files, rows = [], {}
    for accession, raw in raw_by_accession.items():
        filing = parse_filing(raw, accession, REGISTRY)
        filing["matches_reviewed_sec_display"] = check_reference(filing)
        files.append(filing)
        for row in filing["monthly_observations"]:
            month = row["month"]
            if month in rows or month not in month_range():
                raise ValueError("Overlapping or unexpected month")
            rows[month] = {**row, "accession": accession}
    missing = [m for m in month_range() if m not in rows]
    return {"report_type":"asset_compass_v64_sec_tlt_backfill_research_only",
            "ticker":"TLT", "source":"SEC EDGAR N-PORT B.5",
            "target_months":len(month_range()), "parsed_months":len(rows),
            "missing_months":missing, "filings":files,
            "observations":[rows[m] for m in month_range() if m in rows],
            "complete_target_window":not missing, "historical_pit_certified":False,
            "investor_costs_reconciled":False, "investable_total_return_certified":False,
            "eligible_for_live_scoring":False, "official_score":None}

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        raise ValueError("SEC redirect not followed")

def fetch(accession):
    url = source_url(accession, REGISTRY)
    req = urllib.request.Request(url, headers={"User-Agent":"Ooglex Research (https://www.ooglex.com/; research backfill)", "Accept":"application/xml,text/xml"})
    with urllib.request.build_opener(NoRedirect()).open(req, timeout=25) as res:
        if res.geturl() != url:
            raise ValueError("Unexpected SEC response URL")
        media = res.headers.get("Content-Type", "").split(";",1)[0].strip().lower()
        # Archives can serve raw XML as generic text or bytes; the strict
        # XML parser and fund/period checks remain mandatory. Never accept HTML.
        if media not in {"application/xml","text/xml","text/plain","application/octet-stream"}:
            raise ValueError("Unexpected SEC response media type")
        raw = res.read(MAX_BYTES+1)
    return raw

def main():
    p=argparse.ArgumentParser(description=__doc__)
    group=p.add_mutually_exclusive_group(required=True)
    group.add_argument("--download",action="store_true")
    group.add_argument("--xml-dir",type=Path)
    p.add_argument("--output",type=Path,required=True)
    p.add_argument("--require-complete",action="store_true")
    args=p.parse_args()
    if args.output.resolve().is_relative_to(ROOT):
        p.error("Research output outside website repository only")
    inputs={}
    failures={}
    for accession in REGISTRY:
        stage="download" if args.download else "local_read"
        try:
            if args.download:
                time.sleep(1)
                raw=fetch(accession)
            else:
                with (args.xml_dir/(accession+".xml")).open("rb") as f:
                    raw=f.read(MAX_BYTES+1)
            # Validate each response before allowing it to enter the batch.
            stage="xml_identity_and_values"
            filing=parse_filing(raw,accession,REGISTRY)
            stage="reference_reconciliation"
            check_reference(filing)
            inputs[accession]=raw
        except urllib.error.HTTPError as exc:
            failures[accession]={"stage":stage,"type":"HTTPError","http_status":exc.code}
            if exc.code in (403,429):
                # Respect access denial/rate limit; do not retry or bypass.
                break
        except ValueError as exc:
            failures[accession]={"stage":stage,"type":"ValueError","reason":str(exc)}
        except OSError as exc:
            failures[accession]={"stage":stage,"type":type(exc).__name__}
    for accession in REGISTRY:
        if accession not in inputs and accession not in failures:
            failures[accession]={"stage":"not_attempted","type":"stopped_after_access_denial"}
    result=build(inputs)
    result["source_failures"]=failures
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+"\n",encoding="utf-8")
    print(json.dumps({k:result[k] for k in ("target_months","parsed_months","missing_months","complete_target_window","source_failures","eligible_for_live_scoring")}))
    if args.require_complete and not result["complete_target_window"]:
        raise SystemExit(1)

if __name__=="__main__":
    main()
