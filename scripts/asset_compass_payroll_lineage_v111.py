"""V111–V116: archived BLS payroll revision narrative reconciliation.

Not a full vintage chain. No public release timestamp or current score certified.
"""
from decimal import Decimal
from datetime import datetime

def audit_payroll(records):
    candidates=[]
    excluded=[]
    for r in records:
        if r["source"]["release_kind"]!="employment":continue
        period=r["source"]["observation_period"]
        if r["reissue_notice_detected"] or r["header"]["header_status"]!="publisher_header_matches_archive_date":
            excluded.append(period)
            continue
        stamp=datetime.fromisoformat(r["header"]["publisher_stated_embargo_utc"])
        if stamp.tzinfo is None:raise ValueError("Naive release candidate clock")
        candidates.append((stamp,r))
    seen_clocks=set()
    latest={}
    comparisons=[]
    for stamp,r in sorted(candidates,key=lambda x:x[0]):
        if stamp in seen_clocks:raise ValueError("Duplicate employment candidate clock")
        seen_clocks.add(stamp)
        p=r["source"]["observation_period"]
        # Revision claims precede the same document's current headline.
        for c in r["revision_claims"]:
            target=c["target_observation_period"]
            prior=Decimal(c["source_reported_prior_value"])
            revised=Decimal(c["source_reported_revised_value"])
            delta=Decimal(c["delta_persons"])
            if target>=p or revised-prior!=delta:raise ValueError("Invalid revision narrative")
            prev=latest.get(target)
            status="prior_not_observed" if prev is None else ("matches_previous_candidate" if prev[0]==prior else "prior_value_mismatch")
            comparisons.append({"reporting_period":p,"target_period":target,"status":status,
                "previous_candidate_sha256":prev[1] if prev else None,
                "reporting_release_sha256":r["sha256"],
                "point_in_time_qualified":False})
            # A mismatch is not silently converted to a certified chain.
            latest[target]=(revised,r["sha256"])
        for m in r["metrics"]:
            if m["source_series_id"]!="bls.payroll" or m["statistic"]!="monthly_payroll_change":continue
            if m["observation_period"]!=p or p in latest:raise ValueError("Duplicate/mismatched payroll headline")
            latest[p]=(Decimal(m["value_reported"]),r["sha256"])
    counts={k:sum(c["status"]==k for c in comparisons) for k in ("prior_not_observed","matches_previous_candidate","prior_value_mismatch")}
    return {"status":"archive_narrative_reconciliation_only","eligible_archive_releases":len(candidates),
            "excluded_reissue_or_unmatched_header_periods":sorted(excluded),
            "compared_revision_claims":len(comparisons),"comparison_counts":counts,
            "comparisons":comparisons,"historical_revision_chain_certified":False,
            "independent_publication_time_certified":False,"eligible_for_live_scoring":False}
