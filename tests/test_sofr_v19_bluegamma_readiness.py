"""V19 BlueGamma vendor trial/rights boundary. No paid API invocation."""
import json
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[1]
p=ROOT/"docs/data-rights/sofr-v19-bluegamma-evaluation.json"
d=json.loads(p.read_text(encoding="utf-8"))

class BlueGammaReadiness(unittest.TestCase):
    def test_correct_sofr_history_contract(self):
        self.assertEqual(d["api"]["path"],"/v1/historical_swap_rates")
        self.assertEqual(d["api"]["index"],"SOFR")
        self.assertEqual(d["api"]["requiredTenors"],["2Y","3Y","5Y","7Y","10Y","30Y"])
        self.assertIn("start_date",d["api"]["queryParams"])
        self.assertIn("end_date",d["api"]["queryParams"])
        self.assertEqual(d["api"]["authentication"],"x-api-key")
    def test_no_unauthorized_redistribution_or_unverified_live_rates(self):
        self.assertFalse(d["productionSwitchApproved"])
        self.assertFalse(d["api"]["apiKeyConfigured"])
        self.assertFalse(d["api"]["sixTenorApiResponseValidated"])
        self.assertFalse(d["commercial"]["websiteRedistributionApproved"])
        self.assertFalse(d["commercial"]["derivedSpreadPublicationApproved"])
        self.assertFalse(d["release"]["writeProduction"])
        self.assertFalse(d["release"]["recordRawThirdPartyRatesInGit"])
    def test_do_not_confuse_vendor_listing_with_immutable_quotes(self):
        self.assertEqual(d["history"]["method"],"historical_par_rates_bootstrapped_from_provider_curve")
        self.assertFalse(d["history"]["pointInTimeImmutableVerified"])
    def test_price_is_only_starting_price(self):
        self.assertEqual(d["commercial"]["advertisedStartingUsdPerIndexPerMonth"],349)
        self.assertFalse(d["commercial"]["redistributionPriceKnown"])
        self.assertIsNone(d["commercial"]["contractEvidence"])

if __name__=="__main__":unittest.main()
