#!/usr/bin/env python3
"""V58 authentic six-asset evidence/readiness matrix.

Strict source-provenance lineage; neither provenance presence nor
the unsigned booleans here can authorize actual live asset scores.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from datetime import datetime,timezone
from pathlib import Path
from scripts.score_macro_assets import score_one,validate_config

ROOT=Path(__file__).resolve().parents[1]
DATA=ROOT/"data"
PATHS={
 "snapshot":DATA/"asset-scores.json",
 "v54":DATA/"asset-compass-scoring-readiness-v54.json",
 "v55":DATA/"asset-compass-rate-shocks-v55.json",
 "v56":DATA/"asset-compass-new-sources-v56.json",
 "v57":DATA/"asset-compass-asset-specific-v57.json",
 "v57_overlap":DATA/"asset-compass-overlap-audit-v57.json",
 "v58_usd":DATA/"asset-compass-usd-h10-v58.json",
 "history":DATA/"asset-compass-history-readiness.json",
 "model":ROOT/"macro/model-config.json",
}
OUT=DATA/"asset-compass-model-gaps-v58.json"
ASSETS=("gold","us_equities","us_long_bonds","usd","bitcoin","oil")
LABELS={"gold":"黄金","us_equities":"美国股票","us_long_bonds":"美国长期国债",
        "usd":"美元","bitcoin":"比特币","oil":"原油"}
SOURCES={
 "gold":("cftc_gold",),
 "us_equities":(),
 "us_long_bonds":("treasury_30y",),
 "usd":("fed_h10_dollar",),
 "bitcoin":(),
 "oil":("eia_commercial_oil_inventory",),
}
ISSUES={
 "point_in_time_history":"historical_first_publication_and_revisions_not_certified",
 "total_returns":"investable_total_return_with_distributions_and_fx_or_roll_not_certified",
 "out_of_sample":"multi_regime_independent_walkforward_evidence_not_certified",
 "factor_calibration":"asset_direction_sensitivity_and_weight_calibration_not_certified",
 "source_independence":"risk_and_rate_source_overlap_not_resolved",
 "legal_rights":"series_specific_redistribution_rights_not_universally_verified",
}
RECOMMENDATIONS={
 "us_equities":"official_index_level_is_not_total_return; seek properly licensed index-valuation/earnings or SEC source",
 "bitcoin":"licensed_chain_supply_or_verifiable_ETF_holding_or_market_aggregate_required",
 "gold":"CFTC reporting_asof_not_release_datetime; historical direction to be validated",
 "us_long_bonds":"Treasury auction bid_cover_not_investable_total_return",
 "usd":"Fed H10 broad_index_is_not_fx_carry_total_return",
 "oil":"EIA weekly_inventory_is_not_futures_roll_adjusted_return",
}

def canonical_hash(obj):
    return hashlib.sha256(json.dumps(obj,sort_keys=True,ensure_ascii=False,
      separators=(",",":"),allow_nan=False).encode("utf-8")).hexdigest()


def produce(d,*,now=None):
    now=now or datetime.now(timezone.utc)
    if now.tzinfo is None or now.utcoffset() is None:
        raise ValueError("Missing UTC-aware audit clock")
    snapshot=d["snapshot"]; v54=d["v54"];v55=d["v55"];v56=d["v56"];
    v57=d["v57"];usd=d["v58_usd"];history=d["history"];
    overlap=d["v57_overlap"];config=validate_config(d["model"])
    if set(config["weights"])!=set(ASSETS):
        raise ValueError("Six-asset config mismatch")
    conditions=[
      snapshot.get("schema_version")==1,
      snapshot.get("scoring",{}).get("calibration_verified") is False,
      snapshot.get("scoring",{}).get("out_of_sample_verified") is False,
      set(snapshot.get("assets",{}))==set(ASSETS),
      all(x["score"] is None and x["status"]=="unavailable" for x in snapshot["assets"].values()),
      v54.get("report_type")=="asset_compass_v54_scoring_readiness",
      v54.get("validated_for_live_scoring") is False,
      v54.get("source_pit_qualified_count")==0,
      v54.get("source_snapshot_generated_at")==snapshot.get("generated_at"),
      v55.get("report_type")=="asset_compass_v55_real_treasury_rate_shock_research",
      v55.get("validated_for_live_scoring") is False,
      v55.get("official_0_to_100_scores_published")==0,
      v55.get("source_snapshot_generated_at")==snapshot.get("generated_at"),
      v56.get("report_type")=="asset_compass_v56_official_risk_and_oil_research",
      v56.get("validated_for_live_scoring") is False,
      v56.get("source_vintages_qualified")==0,
      v56.get("independent_scoring_factor_groups_qualified")==0,
      v56.get("approved_asset_scores")==0,
      set(v56.get("group_ids_with_any_observation",[]))==set(config["factor_order"]),
      v57.get("report_type")=="asset_compass_v57_authentic_asset_specific_source_research",
      v57.get("validated_for_live_scoring") is False,
      v57.get("approved_asset_scores")==0,
      v57.get("first_publication_vintages_certified")==0,
      v57.get("independent_model_factor_qualified_count")==0,
      v57.get("v56_observed_at")==v56.get("generated_at"),
      overlap.get("report_type")=="asset_compass_v57_descriptive_source_overlap_audit",
      overlap.get("available_for_investment_scoring") is False,
      overlap.get("historical_pit_qualified") is False,
      overlap.get("out_of_sample_return_calibration_passed") is False,
      usd.get("report_type")=="asset_compass_v58_fed_h10_usd_research",
      usd.get("source_series_id")=="DTWEXBGS",
      usd.get("asset_id")=="usd",
      usd.get("official_asset_score") is None,
      usd.get("historical_first_publication_vintages_verified") is False,
      usd.get("independent_signal_verified") is False,
      usd.get("sample_out_of_sample_calibration_passed") is False,
      usd.get("validated_for_live_scoring") is False,
      usd.get("observation_count",0)>=310,
      history.get("validated_for_live_scoring") is False,
      history.get("eligible_for_point_in_time_backtest") is False,
    ]
    if not all(conditions):
        raise ValueError("One or more upstream audit flags/snapshot source lineage invalid")
    if set(v57.get("assets",{}))!=set(ASSETS):
        raise ValueError("Incomplete V57 assets")
    if (set(v57.get("asset_specific_source_available_assets",[]))!={"gold","us_long_bonds","oil"}
          or set(v57.get("asset_specific_source_missing_assets",[]))!={"us_equities","usd","bitcoin"}):
        raise ValueError("V57 source coverage changed without provenance review")
    for x in (v55["assets"],v56["assets"],v57["assets"]):
        if any(entry.get("score",entry.get("official_score")) is not None for entry in x.values()):
            raise ValueError("Unapproved research score supplied")

    rows={}
    for aid in ASSETS:
        original=SOURCES[aid]
        candidate=("fed_h10_dollar",) if aid=="usd" else original
        # This is a source inventory only; source existence does not prove
        # a unique statistical factor, an economic sign, or model prediction.
        blocked=score_one(aid,{},config,{})
        if blocked["score"] is not None or blocked["status"]!="unavailable":
            raise ValueError("Official score must remain locked")
        research_status="observed_research_only" if candidate else "missing_specific_source"
        rows[aid]={
          "label":LABELS[aid],"source_observation_status":research_status,
          "source_ids":list(candidate),"research_source_count":len(candidate),
          "completeness_in_six_assets_pct":100 if candidate else 0,
          "research_proxy_not_price_total_return":True,
          "macro_group_raw_sources":6,
          "model_qualified_factor_group_count":0,
          "model_qualified_weight_pct":0,
          "model_calibration_verified":False,
          "point_in_time_provenance_verified":False,
          "investable_total_return_verified":False,
          "out_of_sample_backtest_verified":False,
          "official_score":None,
          "blocked_by":blocked["blocked_by"],
          "missing_evidence":list(ISSUES),
          "next_evidence":RECOMMENDATIONS[aid],
        }
    available=[k for k,v in rows.items() if v["research_source_count"]]
    return {
       "schema_version":1,"report_type":"asset_compass_v58_six_asset_model_evidence",
       "generated_at":now.astimezone(timezone.utc).isoformat(),
       "status":"research_only_no_authorized_scores",
       "input_sha256":{k:canonical_hash(v) for k,v in d.items()},
       "macro_observation_group_count":6,
       "asset_specific_observed_assets":available,
       "asset_specific_missing_assets":[k for k in ASSETS if k not in available],
       "asset_specific_observed_count":len(available),
       "asset_specific_missing_count":6-len(available),
       "historical_first_release_certified_source_count":0,
       "audited_asset_total_return_count":0,
       "approved_independent_model_factor_group_count":0,
       "oos_validated_assets":0,"official_0_to_100_scores_published":0,
       "research_assets":rows,
       "blockers":ISSUES,
       "model_scoring_qualification":"not_approved",
       "qualified_for_live_scoring":False,
       "automated_investment_actions_enabled":False,
       "limitations":[
         "Four assets have an observable research proxy but none has independently certified factor score.",
         "Gold CFTC, long-bond Treasury auction, crude EIA stocks and Fed H10 USD index are incomparable units.",
         "H10 index is a broad nominal currency value, not a tradable carry-adjusted USD total return.",
         "Raw macro source presence is not as-of publish vintage, calibration or tested trading performance.",
         "No purchase/sell/asset-allocation rating is authorized by this document.",
       ],
    }

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--output",type=Path,default=OUT)
    a=p.parse_args()
    d={k:json.loads(v.read_text(encoding="utf-8")) for k,v in PATHS.items()}
    report=produce(d)
    a.output.parent.mkdir(parents=True,exist_ok=True)
    a.output.write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(json.dumps({"observed_asset_specific_sources":report["asset_specific_observed_count"],
       "assets_missing_sources":report["asset_specific_missing_assets"],
       "oos_qualified":0,"official_scores":0},ensure_ascii=False))

if __name__=="__main__":
    main()
