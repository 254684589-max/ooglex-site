"""Historical publishing rights cannot be inferred from public API access."""
import importlib.util
import copy
import json
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location("rights",ROOT/"scripts/check_sofr_backfill_rights.py")
rights=importlib.util.module_from_spec(spec)
spec.loader.exec_module(rights)
SOURCE=json.loads((ROOT/"docs/data-rights/sofr-historical-publication.json").read_text(encoding="utf-8"))

class RightsTests(unittest.TestCase):
    def test_actual_project_is_blocked(self):
        r=rights.assess(SOURCE)
        self.assertFalse(r["canPublishHistoricalBackfill"])
        self.assertIn("no_documented_express_redistribution_permission",r["reasons"])
        self.assertIn("legacy_2026_11_20_conflict_unresolved",r["reasons"])
    def test_public_api_download_does_not_grant_rights(self):
        d=copy.deepcopy(SOURCE)
        d["dataSources"]["checkmyswap"]["access"]="public_read_only"
        self.assertFalse(rights.assess(d)["canPublishHistoricalBackfill"])
    def test_license_scope_must_be_complete(self):
        d=copy.deepcopy(SOURCE)
        d["dataSources"]["checkmyswap"]["redistributionStatus"]="express_permission_documented"
        d["dataSources"]["checkmyswap"]["agreementIdentifier"]="synthetic test"
        d["dataSources"]["checkmyswap"]["evidenceUrl"]="https://example.invalid/licence"
        d["dataSources"]["checkmyswap"]["licenseEffectiveDate"]="2026-01-01"
        d["dataSources"]["checkmyswap"]["rightsHolderConfirmation"]="fixture only"
        d["dataSources"]["checkmyswap"]["reviewedBy"]="unit test"
        d["dataSources"]["checkmyswap"]["reviewedAt"]="2026-11-23"
        for key in rights.SCOPE:d["dataSources"]["checkmyswap"]["scopeChecks"][key]=True
        d["legacyConflict"]["status"]="resolved"
        d["legacyConflict"]["resolutionEvidenceUrl"]="https://example.invalid/conflict"
        d["legacyConflict"]["resolutionApprovedBy"]="unit test"
        d["historicalPublicationApproved"]=True
        d["publicationMode"]="approved_with_human_review"
        self.assertTrue(rights.assess(d)["canPublishHistoricalBackfill"])
        d["dataSources"]["checkmyswap"]["scopeChecks"]["derivedSwapSpreadPublication"]=False
        self.assertFalse(rights.assess(d)["canPublishHistoricalBackfill"])
    def test_unresolved_conflict_blocks_even_with_license(self):
        d=copy.deepcopy(SOURCE)
        d["legacyConflict"]["status"]="unresolved"
        self.assertIn("legacy_2026_11_20_conflict_unresolved",rights.assess(d)["reasons"])
    def test_research_only_mode_stays_blocked(self):
        d=copy.deepcopy(SOURCE)
        d["publicationMode"]="blocked"
        self.assertIn("publication_mode_blocked",rights.assess(d)["reasons"])

if __name__=="__main__":unittest.main()
