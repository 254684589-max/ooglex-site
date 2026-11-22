"""V18 no-substitution and no-implicit-licensing source matrix checks."""
import json
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[1]
PATH=ROOT/"docs/data-rights/sofr-v18-provider-matrix.json"

class SourceContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data=json.loads(PATH.read_text(encoding="utf-8"))
        cls.sources={r["id"]:r for r in cls.data["candidates"]}
    def test_public_release_is_explicitly_denied(self):
        self.assertFalse(self.data["productionSourceSwitchApproved"])
        for item in self.sources.values():
            self.assertFalse(item["publicRedistributionLicensed"])
            self.assertFalse(item["commercialUseLicensed"])
    def test_no_overnight_benchmark_used_as_swap_curve(self):
        self.assertNotEqual(self.sources["newyorkfed_sofr"]["kind"],"sofr_forward_par_swap_curve")
        self.assertNotEqual(self.sources["fred_legacy_swaps"]["kind"],"sofr_forward_par_swap_curve")
    def test_bluegamma_not_accepted_without_all_tenors_and_contract(self):
        provider=self.sources["bluegamma"]
        self.assertEqual(provider["approval"],"needs_contract_and_sample")
        self.assertFalse(provider["allSixTenorsIndependentlyVerified"])
        self.assertFalse(provider["historicalSnapshotVersionVerified"])
    def test_explicit_tenors_and_provider_uniqueness(self):
        self.assertEqual(self.data["requiredTenorsYears"],[2,3,5,7,10,30])
        self.assertEqual(len(self.sources),len(self.data["candidates"]))
    def test_no_rates_stored_in_research_matrix(self):
        text=PATH.read_text(encoding="utf-8")
        for key in ['"spreadBp"','"swap"','"treasury"','"observations"']:
            self.assertNotIn(key,text)

if __name__=="__main__":
    unittest.main()
