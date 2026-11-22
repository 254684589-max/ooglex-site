#!/usr/bin/env python3
"""V17 Treasury disclosure-time evidence inventory — strictly not PIT certification.

Separates quote observation timing (about 15:30 America/New_York), official
series documentation, file retrieval timestamps and unknown *initial*
publication instants. No guessed first-publication time or vintage backfill.
Sources are official Treasury public methodology/archives discovery links,
not independently archived, timestamped original daily release files.
"""
import argparse
import json
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
V15 = ROOT / "data/asset-compass-treasury-source-evidence-v15.json"
V16 = ROOT / "data/asset-compass-treasury-v16-report.json"
OUTPUT = ROOT / "data/asset-compass-treasury-release-evidence-v17.json"
DOCS = {
 "methodology":"https://home.treasury.gov/policy-issues/financing-the-government/interest-rate-statistics",
 "archive":"https://home.treasury.gov/resource-center/data-chart-center/interest-rates/daily-treasury-rate-archives",
 "xml":"https://home.treasury.gov/treasury-daily-interest-rate-xml-feed",
}
SERIES = {"treasury.us2y":"nominal","treasury.us10y":"nominal","treasury.real10y":"real"}

def utc(value):
    d=datetime.fromisoformat(value.replace("Z","+00:00"))
    if d.tzinfo is None:raise ValueError("timezone required")
    return d.astimezone(timezone.utc)

def audit(v15,v16,*,now=None):
    instant=now or datetime.now(timezone.utc)
    if instant.tzinfo is None:raise ValueError("audit timestamp needs timezone")
    if v15.get("report_type")!="asset_compass_v15_treasury_raw_source_evidence":
        raise ValueError("V15 evidence unavailable")
    if v16.get("report_type")!="asset_compass_v16_retrieval_comparison":
        raise ValueError("V16 retrieval comparison unavailable")
    if any(v15.get(flag) is not False for flag in
           ("original_publication_time_verified","original_release_vintages_verified",
            "eligible_for_point_in_time_backtest","validated_for_live_scoring")):
        raise ValueError("V15 historical gate unexpectedly unlocked")
    if any(v16.get(flag) is not False for flag in
           ("historical_official_revisions_verified","historical_original_publication_timestamp_verified",
            "eligible_for_point_in_time_backtest","validated_for_live_scoring")):
        raise ValueError("V16 historical gate unexpectedly unlocked")
    if v15.get("year")!=v16.get("year"):
        raise ValueError("V15/V16 source year mismatch")
    receipts=v15.get("source_receipts")
    if not isinstance(receipts,list) or len(receipts)!=2:
        raise ValueError("Missing official CSV receipts")
    by_type={r["type"]:r for r in receipts}
    if set(by_type)!={"nominal","real"}:
        raise ValueError("Wrong or duplicated Treasury curve receipts")
    if v16.get("source_sha256")!={k:r["sha256"] for k,r in by_type.items()}:
        raise ValueError("V16 source digest does not match V15 receipts")
    if utc(v15["retrieved_at"])>utc(v16["checked_at"]) or utc(v16["checked_at"])>instant:
        raise ValueError("Out-of-order retrievals")
    rows=[]
    for sid,curve in SERIES.items():
        receipt=by_type[curve]
        if not receipt["source_url"].startswith("https://home.treasury.gov/"):
            raise ValueError("Unexpected official source domain")
        if receipt.get("original_release_time_verified") is not False:
            raise ValueError("Unreviewed release evidence passed as verified")
        if len(receipt.get("sha256",""))!=64:
            raise ValueError("Source digest missing")
        rows.append({
          "series_id":sid,"curve_type":curve,
          "official_quote_sampling_approx_local_time":"15:30",
          "official_quote_timezone":"America/New_York",
          "quote_time_evidence_type":"official_methodology_description",
          "quote_time_is_publication_time":False,
          "publication_timestamp_utc":None,
          "publication_time_evidence_status":"not_independently_verified",
          "historical_first_release_vintage_hash":None,
          "historical_first_release_vintage_verified":False,
          "observed_source_content_sha256":receipt["sha256"],
          "retrieved_at":receipt["retrieved_at"],
          "source_url":receipt["source_url"],
          "official_methodology_url":DOCS["methodology"],
          "required_additional_proof":[
             "archived_original_daily_release_artifact_with_chain_of_custody",
             "independent_source_publication_timestamp_with_timezone",
             "asof_value_and_revisions_as_published_at_decision_instant",
             "independent_publication_rights_and_statistical_use_review",
          ],
          "eligible_for_point_in_time_backtest":False,
        })
    return {
      "schema_version":1,
      "report_type":"asset_compass_v17_treasury_publication_evidence",
      "generated_at":instant.astimezone(timezone.utc).isoformat(),
      "v15_retrieved_at":v15["retrieved_at"],
      "v16_checked_at":v16["checked_at"],
      "source_year":v15["year"],
      "methodology_evidence_type":"official_public_website_description_not_original_release_archive",
      "methodology_review_status":"official_documentation_identified_not_independently_timestamped",
      "official_information_sources":DOCS,
      "interpretation":"Treasury describes quotes obtained at about 3:30 PM New York time. This is not a documented Treasury website publishing instant. Published archives/XML alone do not provide certified original first-release timestamps or complete amendment history.",
      "series":rows,
      "independently_verified_original_publication_timestamps":0,
      "independently_verified_historical_vintages":0,
      "first_seen_is_official_release_timestamp":False,
      "http_date_is_official_release_timestamp":False,
      "quotation_timestamp_is_publication_timestamp":False,
      "eligible_for_point_in_time_backtest":False,
      "validated_for_live_scoring":False,
      "safe_for_public_research_only":True,
    }

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--v15",type=Path,default=V15)
    parser.add_argument("--v16",type=Path,default=V16)
    parser.add_argument("--output",type=Path,default=OUTPUT)
    opts=parser.parse_args()
    report=audit(json.loads(opts.v15.read_text(encoding="utf-8")),
                 json.loads(opts.v16.read_text(encoding="utf-8")))
    opts.output.parent.mkdir(parents=True,exist_ok=True)
    opts.output.write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print("V17 official methodology cataloged; original publication proof 0/3, PIT scoring disabled")
if __name__=="__main__":
    main()
