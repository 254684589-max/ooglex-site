"""V21 private candidate evidence test fixtures (not real financial observations)."""
import unittest
from scripts.asset_compass_asset_specific_v21 import (
    ASSETS, CATALOG, LIMITATIONS, aware_time, evaluate, source_host,
)


class AssetSpecificEvidenceV21Tests(unittest.TestCase):
    def setUp(self):
        self.asof = "2025-06-01T00:00:00Z"
        self.base = {
            "indicator_id": "oil_eia_crude_stocks",
            "asset_id": "oil",
            "observation_date": "2025-01-01",
            "available_at": "2025-01-02T12:00:00Z",
            "value": 0,
            "unit": "thousand_barrels",
            "source_url": "https://www.eia.gov/petroleum/supply/weekly/",
            "source_release_id": "synthetic-test-release",
            "rights_evidence": "synthetic-test-only",
            "research_use_approved": True,
        }

    def test_all_six_assets_and_score_locked(self):
        self.assertEqual(set(ASSETS), {v[0] for v in CATALOG.values()})
        r = evaluate([self.base], self.asof)
        self.assertEqual(r["candidate_indicator_count"], 12)
        self.assertEqual(r["assets"]["oil"]["asof_eligible_rows"], 1)
        self.assertEqual(r["assets"]["gold"]["status"], "missing_verified_evidence")
        self.assertIsNone(r["assets"]["oil"]["contribution"])
        self.assertIsNone(r["assets"]["oil"]["asset_specific_factor_signal"])
        self.assertFalse(r["validated_for_live_scoring"])
        self.assertFalse(r["public_redistribution_authorized"])

    def test_future_releases_not_visible_asof(self):
        r = evaluate([dict(self.base, available_at="2025-07-01T00:00:00Z")], self.asof)
        self.assertEqual(r["asof_eligible_vintage_rows"], 0)

    def test_zero_and_negative_flow_are_not_missing(self):
        a = dict(self.base)
        b = dict(self.base, indicator_id="oil_cftc_wti_position",
                 value=-12.3, unit="contracts", source_release_id="other",
                 source_url="https://www.cftc.gov/MarketReports/CommitmentsofTraders/")
        r = evaluate([a, b], self.asof)
        self.assertEqual(r["asof_eligible_vintage_rows"], 2)

    def test_permissions_required(self):
        with self.assertRaises(PermissionError):
            evaluate([dict(self.base, research_use_approved=False)], self.asof)
        with self.assertRaises(PermissionError):
            evaluate([dict(self.base, rights_evidence="")], self.asof)

    def test_host_and_asset_and_unit_gates(self):
        cases = (
            {"source_url": "https://www.eia.gov.evil.example/data"},
            {"source_url": "http://www.eia.gov/data"},
            {"source_url": "https://www.eia.gov/"},
            {"asset_id": "bitcoin"}, {"unit": "barrels"},
            {"indicator_id": "not_registered"},
        )
        for changes in cases:
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                evaluate([dict(self.base, **changes)], self.asof)

    def test_release_time_and_duplicate_gates(self):
        with self.assertRaises(ValueError):
            evaluate([dict(self.base, available_at="2024-12-31T00:00:00Z")], self.asof)
        with self.assertRaises(ValueError):
            evaluate([dict(self.base, available_at="2025-01-02T12:00:00")], self.asof)
        with self.assertRaises(ValueError):
            evaluate([self.base, self.base], self.asof)

    def test_numeric_and_shape_checks(self):
        for bad in (True, float("nan"), "1.2", float("inf")):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                evaluate([dict(self.base, value=bad)], self.asof)
        with self.assertRaises(ValueError):
            evaluate([{"indicator_id": "oil_eia_crude_stocks"}], self.asof)
        self.assertTrue(LIMITATIONS["btc_etf_flow"])

    def test_source_url_matching(self):
        self.assertTrue(source_host("https://www.eia.gov/data", "eia.gov"))
        self.assertFalse(source_host("https://eia.gov.evil.example/data", "eia.gov"))
        with self.assertRaises(ValueError):
            aware_time("2025-01-01T12:00:00")


if __name__ == "__main__":
    unittest.main()
