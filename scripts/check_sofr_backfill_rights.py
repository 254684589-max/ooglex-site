#!/usr/bin/env python3
"""Fail-closed release readiness gate for SOFR historical backfills.

This NEVER grants redistribution rights or writes market data.
It reports why publication is not yet eligible. Live scheduled collection
has a different operational pipeline; do not confuse it with old-date backfill.
"""
import argparse
from datetime import date
import json
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parents[1]
REGISTRY=ROOT/"docs/data-rights/sofr-historical-publication.json"
SCOPE=("historicalStorage","publicWebRedistribution","derivedSwapSpreadPublication",
       "commercialUse","bulkAutomatedRetrieval")

def assess(registry):
    issues=[]
    if registry.get("schemaVersion")!=1:
        issues.append("invalid_registry_schema")
    src=registry.get("dataSources",{}).get("checkmyswap",{})
    if src.get("redistributionStatus")!="express_permission_documented":
        issues.append("no_documented_express_redistribution_permission")
    for field in ("agreementIdentifier","evidenceUrl","licenseEffectiveDate",
                  "rightsHolderConfirmation","reviewedBy","reviewedAt"):
        if not isinstance(src.get(field),str) or not src[field].strip():
            issues.append("missing_"+field)
    rights=src.get("scopeChecks",{})
    for field in SCOPE:
        if rights.get(field) is not True:
            issues.append("unverified_scope_"+field)
    try:
        if src.get("licenseEffectiveDate"):
            date.fromisoformat(src["licenseEffectiveDate"])
        if src.get("licenseExpiryDate") and date.fromisoformat(src["licenseExpiryDate"]) < date.today():
            issues.append("license_expired")
    except ValueError:
        issues.append("invalid_license_date")
    conflict=registry.get("legacyConflict",{})
    if conflict.get("status")!="resolved":
        issues.append("legacy_2026_11_20_conflict_unresolved")
    if not conflict.get("resolutionEvidenceUrl") or not conflict.get("resolutionApprovedBy"):
        issues.append("legacy_conflict_resolution_not_documented")
    if registry.get("historicalPublicationApproved") is not True:
        issues.append("publication_not_approved")
    if registry.get("publicationMode")!="approved_with_human_review":
        issues.append("publication_mode_blocked")
    return {
        "schemaVersion":1,
        "type":"SOFR-historical-backfill-readiness",
        "canPublishHistoricalBackfill":False if issues else True,
        "reasons":issues,
        "source":"docs/data-rights/sofr-historical-publication.json",
        "note":"This code checks a registry; it is NOT independent verification of legal authority or data accuracy. Manual evidence review remains mandatory."
    }

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--registry",type=Path,default=REGISTRY)
    p.add_argument("--output",type=Path)
    p.add_argument("--require-clearance",action="store_true",
                   help="Return failure for an actual backfill publishing step unless every documented gate clears")
    args=p.parse_args()
    report=assess(json.loads(args.registry.read_text(encoding="utf-8")))
    if args.output:
        if args.output.resolve()==args.registry.resolve():
            p.error("Cannot overwrite the permissions registry")
        args.output.parent.mkdir(parents=True,exist_ok=True)
        args.output.write_text(json.dumps(report,indent=2,ensure_ascii=False)+"\n",encoding="utf-8")
    print(json.dumps(report,ensure_ascii=False,indent=2))
    return 2 if args.require_clearance and not report["canPublishHistoricalBackfill"] else 0

if __name__=="__main__":
    try:sys.exit(main())
    except (OSError,ValueError,KeyError,json.JSONDecodeError) as err:
        print("SOFR LICENSE GATE ERROR:",err,file=sys.stderr);sys.exit(1)
