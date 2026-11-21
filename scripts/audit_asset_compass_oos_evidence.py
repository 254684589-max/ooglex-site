#!/usr/bin/env python3
"""Conservative OOS statistical evidence audit for Asset Compass.

This tool audits externally supplied walk-forward diagnostics. It does not
self-certify data rights, original macro release vintages, or model quality.
Synthetic fixtures can exercise arithmetic but cannot unlock production.
"""
import argparse
import json
import math
from pathlib import Path
from statistics import NormalDist

ROOT=Path(__file__).resolve().parents[1]
MIN_FOLDS=8
MIN_ACTIVE=80
MIN_REGIMES=3
MIN_YEARS=5

def wilson(successes,n,z=1.959963984540054):
    if not isinstance(successes,int) or not isinstance(n,int) or n<=0 or successes<0 or successes>n:
        raise ValueError("Invalid success count")
    p=successes/n
    den=1+z*z/n
    middle=(p+z*z/(2*n))/den
    radius=z*math.sqrt((p*(1-p)+z*z/(4*n))/n)/den
    return [round(max(0,middle-radius),6),round(min(1,middle+radius),6)]

def binomial_pvalue(k,n,baseline=.5):
    """Exact one-sided tail Pr[X>=k] under fixed Bernoulli baseline.

    Requires pre-specified baseline; no independence claim is made for the
    historical fold output, which may have shared temporal exposure.
    """
    if not (0<=baseline<=1) or not isinstance(k,int) or not isinstance(n,int) or n<=0 or k<0 or k>n:
        raise ValueError("Invalid binomial test")
    if baseline==0:return 0.0 if k>0 else 1.0
    if baseline==1:return 1.0
    # logsumexp to avoid huge nCr and numeric overflow
    terms=[math.lgamma(n+1)-math.lgamma(i+1)-math.lgamma(n-i+1)
         +i*math.log(baseline)+(n-i)*math.log1p(-baseline) for i in range(k,n+1)]
    maximum=max(terms)
    return round(min(1.0,math.exp(maximum)*sum(math.exp(t-maximum) for t in terms)),8)

def _years_between(start,end):
    from datetime import date
    a,b=date.fromisoformat(start),date.fromisoformat(end)
    if b<a:raise ValueError("Invalid chronology")
    return (b-a).days/365.2425

def inspect_evidence(report,manifest):
    if report.get("report_type")!="expanding_window_research_diagnostic":
        raise ValueError("Unexpected research report type")
    results=report.get("results")
    if not isinstance(results,dict):raise ValueError("Missing results")
    # Manifest is an evidence index, not a self-signed approval. Its claims are
    # treated as declarative fields that MUST be externally corroborated.
    claims=manifest.get("evidence") or {}
    conditions={
      "original_release_timestamp_archive":claims.get("original_release_timestamp_archive") is True,
      "independent_macro_vintage_verification":claims.get("independent_macro_vintage_verification") is True,
      "license_for_statistical_derived_publication":claims.get("license_for_statistical_derived_publication") is True,
      "investable_total_return_conventions":claims.get("investable_total_return_conventions") is True,
      "out_of_sample_not_used_for_model_selection":claims.get("out_of_sample_not_used_for_model_selection") is True,
      "multi_regime_classification_verified":claims.get("multi_regime_classification_verified") is True,
      "costs_slippage_rolls_documented":claims.get("costs_slippage_rolls_documented") is True
    }
    auditor=manifest.get("independent_auditor")
    signed=bool(isinstance(auditor,dict) and auditor.get("evidence_reference") and auditor.get("reviewed_at")
                and auditor.get("identity"))
    summaries={}
    for asset,values in results.items():
        folds=values.get("folds",[])
        if not isinstance(folds,list):raise ValueError("Invalid folds")
        # If folds overlap, directional counts cannot be aggregated as iid.
        prior_end=None
        independent=True
        samples=0
        for f in folds:
            n=f.get("active_signal_count")
            if not isinstance(n,int) or n<0:raise ValueError("Invalid fold sample count")
            entry=f.get("test_first_entry")
            final=f.get("test_last_entry")
            if not isinstance(entry,str) or not isinstance(final,str) or final<entry:raise ValueError("Invalid fold dates")
            if prior_end is not None and entry<=prior_end:independent=False
            if f.get("training_last_label_exit","")>=entry:raise ValueError("Train/test leakage")
            prior_end=final
            samples+=n
        first=folds[0]["test_first_entry"] if folds else None
        last=folds[-1]["test_last_entry"] if folds else None
        years=_years_between(first,last) if folds else 0
        blockers=[]
        if len(folds)<MIN_FOLDS:blockers.append("insufficient_independent_folds")
        if samples<MIN_ACTIVE:blockers.append("insufficient_oos_events")
        if years<MIN_YEARS:blockers.append("insufficient_years")
        if not independent:blockers.append("overlapping_test_folds")
        if values.get("status")!="research_diagnostic_not_validated":blockers.append("research_status_not_eligible")
        for label,passed in conditions.items():
            if not passed:blockers.append("missing_"+label)
        if not signed:blockers.append("missing_independent_review_evidence")
        # A manifest + report generated within the same project are not
        # independently proven evidence and can never authorize live scores.
        blockers.append("external_evidence_and_governance_not_verified")
        summaries[asset]={
            "diagnostic_fold_count":len(folds),"active_signal_count_reported":samples,
            "test_years":round(years,2),"folds_date_nonoverlap":independent,
            "blockers":blockers,"eligible_for_public_scoring":False
        }
    return {"schema_version":1,"report_type":"statistical_evidence_audit",
            "validated_for_live_scoring":False,
            "oos_backtest_certified":False,
            "data_license_certified":False,
            "independent_review_claim_present":signed,
            "requirements":conditions,"assets":summaries,
            "note":"Fold diagnostics do not provide independent Bernoulli trials. Exact p-values or confidence intervals require independently grounded event-level evidence."}

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--diagnostics",type=Path,required=True)
    parser.add_argument("--manifest",type=Path,required=True)
    parser.add_argument("--output",type=Path,required=True)
    opts=parser.parse_args()
    if opts.output.resolve().is_relative_to(ROOT.resolve()):
        raise ValueError("Private research audit output must not be committed to public site repository")
    result=inspect_evidence(json.loads(opts.diagnostics.read_text(encoding="utf-8")),
                            json.loads(opts.manifest.read_text(encoding="utf-8")))
    opts.output.parent.mkdir(parents=True,exist_ok=True)
    opts.output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print("Validated for public scoring:",result["validated_for_live_scoring"])
if __name__=="__main__":main()
