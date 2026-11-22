"""V55 historical Treasury-rate computations using real public history, no invented score."""
import copy
import json
import math
import unittest
from datetime import datetime, timezone, timedelta, date
from pathlib import Path

from scripts.build_asset_compass_rate_shocks_v55 import calculate, HYPOTHESES

ROOT = Path(__file__).resolve().parents[1]
NOW = datetime(2026, 11, 23, 2, 0, tzinfo=timezone.utc)


class V55RateResearchTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.history = json.loads((ROOT / "data/asset-compass-treasury-history.json").read_text())
        cls.snapshot = json.loads((ROOT / "data/asset-scores.json").read_text())
        cls.config = json.loads((ROOT / "macro/model-config.json").read_text())
    def build(self, history=None, snapshot=None, config=None, *, now=NOW, **opts):
        return calculate(history or self.history, snapshot or self.snapshot,
                         config or self.config, now=now, **opts)

    def test_real_1472_treasury_rows_yield_numerical_rate_changes(self):
        r = self.build()
        self.assertGreaterEqual(r["source_observation_count"], 270)
        self.assertEqual(r["source_end_date"], self.history["end_date"])
        self.assertEqual(r["rolling_reference_shocks"], 252)
        self.assertEqual(r["shock_horizon_observations"], 21)
        for key in ("us10y","us2y","real10y","breakeven10y","spread10y2y"):
            feature = r["shock_features"][key]
            self.assertEqual(feature["prior_baseline_period_count"],252)
            self.assertTrue(math.isfinite(feature["research_z_score"]))
            self.assertTrue(-1<=feature["normalized_rate_shock"]<=1)
            self.assertFalse(feature["historical_pit_verified"])
            self.assertFalse(feature["qualified_independent_model_signal"])

    def test_latest_real_changes_use_exact_21_row_window(self):
        r=self.build()
        rows=self.history["observations"]
        for key in ("real10y","us10y"):
            expected=round((rows[-1][key]-rows[-22][key])*100,4)
            self.assertEqual(r["shock_features"][key]["period_change_basis_points"],expected)
        self.assertEqual(r["shock_features"]["us10y"]["lookback_start_date"],rows[-22]["date"])
        self.assertEqual(r["shock_features"]["us10y"]["baseline_end_date"],rows[-2]["date"])

    def test_only_two_explicable_rate_hypotheses_and_no_scores(self):
        r=self.build()
        self.assertEqual(r["asset_hypothesis_count"],2)
        self.assertEqual(set(HYPOTHESES),{"gold","us_long_bonds"})
        self.assertEqual(len(r["assets"]),6)
        self.assertEqual(r["official_0_to_100_scores_published"],0)
        for asset, info in r["assets"].items():
            self.assertIsNone(info["official_score"])
            self.assertFalse(info["eligible_for_live_scoring"])
            self.assertFalse(info["historical_calibration_passed"])
            self.assertFalse(info["out_of_sample_validation_passed"])
            if asset in HYPOTHESES:
                self.assertIsInstance(info["rate_pressure_candidate"],float)
                self.assertFalse(info["candidate_scoring_entry"]["verified"])
                self.assertIn("historical_calibration_not_passed",info["blocked_by"])
            else:
                self.assertIsNone(info["rate_pressure_candidate"])
                self.assertIsNone(info["candidate_scoring_entry"])

    def test_raw_vs_derived_must_remain_distinguished(self):
        r=self.build()
        self.assertEqual(r["shock_features"]["real10y"]["series_type"],
                         "raw_treasury_yield")
        self.assertEqual(r["shock_features"]["breakeven10y"]["series_type"],
                         "derived_algebraic_diagnostic")
        self.assertFalse(r["validated_for_live_scoring"])
        self.assertFalse(r["eligible_for_point_in_time_backtest"])

    def test_research_hypothesis_is_inverse_nominal_duration_and_real_gold(self):
        r=self.build()
        self.assertAlmostEqual(r["assets"]["gold"]["rate_pressure_candidate"],
                               -r["shock_features"]["real10y"]["normalized_rate_shock"], places=6)
        self.assertAlmostEqual(r["assets"]["us_long_bonds"]["rate_pressure_candidate"],
                               -r["shock_features"]["us10y"]["normalized_rate_shock"], places=6)

    def test_real_data_digest_and_clock_are_provenance_not_pit_evidence(self):
        r=self.build()
        self.assertEqual(len(r["source_history_sha256"]),64)
        self.assertEqual(len(r["source_snapshot_sha256"]),64)
        self.assertFalse(r["historical_first_publication_vintages_verified"])
        self.assertFalse(r["asset_direction_signs_empirically_calibrated"])

    def test_falsely_claimed_historical_vintages_rejected(self):
        h=copy.deepcopy(self.history)
        h["original_release_vintages_available"]=True
        with self.assertRaisesRegex(ValueError,"PIT"):
            self.build(history=h)

    def test_forged_derived_yield_rejected(self):
        h=copy.deepcopy(self.history)
        h["observations"][-1]["breakeven10y"]+=2.5
        with self.assertRaisesRegex(ValueError,"breakeven"):
            self.build(history=h)

    def test_out_of_order_or_future_rows_rejected(self):
        h=copy.deepcopy(self.history)
        h["observations"][-1]["date"]=h["observations"][-2]["date"]
        with self.assertRaisesRegex(ValueError,"duplicate"):
            self.build(history=h)
        with self.assertRaises(ValueError):
            self.build(now=datetime(2025,1,1,tzinfo=timezone.utc))

    def test_stale_history_invalidates_both_hypotheses_no_approval(self):
        r=self.build(now=NOW+timedelta(days=18))
        self.assertFalse(r["latest_history_usable_for_current_research"])
        for value in r["assets"].values():
            self.assertIsNone(value["rate_pressure_candidate"])
            self.assertIsNone(value["official_score"])

    def test_foreign_model_or_wrong_weight_rejected(self):
        config=copy.deepcopy(self.config)
        config["weights"]["gold"][0]+=1
        with self.assertRaises(ValueError):
            self.build(config=config)
        config=copy.deepcopy(self.config)
        config["weights"]["other_asset"]=config["weights"]["gold"]
        with self.assertRaises(ValueError):
            self.build(config=config)

    def test_unverified_snapshot_rejected(self):
        snap=copy.deepcopy(self.snapshot)
        snap["scoring"]["calibration_verified"]=True
        with self.assertRaises(ValueError):
            self.build(snapshot=snap)

    def test_missing_history_cannot_generate_z_scores(self):
        h=copy.deepcopy(self.history)
        h["observations"]=h["observations"][:30]
        h["observation_count"]=30
        h["end_date"]=h["observations"][-1]["date"]
        with self.assertRaisesRegex(ValueError,"observations"):
            self.build(history=h)

    def test_flat_rate_baseline_does_not_invent_z_for_gold(self):
        h=copy.deepcopy(self.history)
        for row in h["observations"]:
            row.update(us10y=4.0,us2y=3.5,real10y=2.0,
                       breakeven10y=2.0,spread10y2y=0.5)
        # Preserve source disclaimers, latest date and record count.
        r=self.build(history=h)
        self.assertIsNone(r["shock_features"]["real10y"]["research_z_score"])
        self.assertIsNone(r["assets"]["gold"]["rate_pressure_candidate"])
        self.assertIsNone(r["assets"]["us_long_bonds"]["rate_pressure_candidate"])

    def test_h15_fallback_still_needs_full_provenance(self):
        h=copy.deepcopy(self.history)
        h["source"]="Federal Reserve Board H.15 via FRED"
        h["source_urls"]=[
            "https://fred.stlouisfed.org/graph/fredgraph.csv?id="+q+"&cosd=2021-01-01&coed=2026-11-23"
            for q in ("DGS10","DGS2","DFII10")]
        h["source_series_ids"]=["DGS10","DGS2","DFII10"]
        self.assertEqual(self.build(history=h)["source"],h["source"])


if __name__=="__main__":
    unittest.main()
