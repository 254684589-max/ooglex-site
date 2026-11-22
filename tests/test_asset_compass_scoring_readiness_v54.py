"""V54 score-contract and research-readiness gates (real committed source inputs)."""
import copy
import json
import math
import unittest
from datetime import datetime, timezone, timedelta
from pathlib import Path

from scripts.score_macro_assets import score_one, produce
from scripts.build_asset_compass_scoring_readiness_v54 import build, hash_input, SOURCES

ROOT = Path(__file__).resolve().parents[1]
NOW = datetime.now(timezone.utc)


def load():
    return {k: json.loads(v.read_text(encoding="utf-8")) for k, v in SOURCES.items()}


class V54ScoringReadinessTests(unittest.TestCase):
    def setUp(self):
        d = load()
        self.snapshot, self.observations, self.history, self.config = (
            d["snapshot"], d["observations"], d["history"], d["config"])

    def report(self, **overrides):
        sources = dict(snapshot=self.snapshot, observations=self.observations,
                       history=self.history, config=self.config)
        sources.update(overrides)
        return build(**sources, now=NOW)

    def test_real_source_readiness_has_six_assets_and_no_scores(self):
        r = self.report()
        self.assertEqual(r["report_type"], "asset_compass_v54_scoring_readiness")
        self.assertEqual(r["asset_count"], 6)
        self.assertEqual(r["factor_group_count"], 6)
        self.assertEqual(r["independently_qualified_factor_groups"], 0)
        self.assertEqual(r["source_pit_qualified_count"], 0)
        self.assertFalse(r["validated_for_live_scoring"])
        self.assertFalse(r["automatic_trading_alerts_enabled"])
        for asset, item in r["assets"].items():
            self.assertEqual(item["status"], "unavailable", asset)
            self.assertIsNone(item["score"], asset)
            self.assertEqual(item["qualified_factor_group_count"], 0)
            self.assertEqual(item["qualified_model_signal_coverage_pct"], 0)
            self.assertFalse(item["historical_calibration_passed"])
            self.assertFalse(item["out_of_sample_validation_passed"])
            self.assertEqual(sum(item["weights_pct"].values()), 100)
            self.assertIn("historical_calibration_not_passed", item["blocked_by"])

    def test_actual_four_groups_have_observations_and_two_lack_sources(self):
        r = self.report()
        # Only count what is observed in today's committed report,
        # never infer the missing risk and asset-specific groups from model weights.
        observed = {k for k, v in self.observations["groups"].items()
                    if v["observations"]}
        self.assertEqual(r["groups_with_source_observations"], len(observed))
        self.assertEqual(r["groups_without_source_observations"], 6 - len(observed))
        self.assertEqual(
            r["research_observations_present"],
            sum(len(v["observations"]) for v in self.observations["groups"].values()))
        self.assertIn("risk", r["assets"]["gold"]["missing_source_groups"])
        self.assertIn("asset_specific", r["assets"]["bitcoin"]["missing_source_groups"])
        self.assertEqual(r["assets"]["gold"]["source_observation_weight_pct_research_only"],
                         sum(dict(zip(self.config["factor_order"],
                                      self.config["weights"]["gold"]))[g]
                             for g in observed))

    def test_research_weight_is_not_model_coverage(self):
        r = self.report()
        self.assertGreater(r["assets"]["gold"]["source_observation_weight_pct_research_only"], 0)
        self.assertEqual(r["assets"]["gold"]["qualified_model_signal_coverage_pct"], 0)

    def test_reports_correct_model_input_hashes(self):
        r = self.report()
        self.assertEqual(r["source_snapshot_generated_at"], self.snapshot["generated_at"])
        self.assertEqual(r["source_observations_generated_at"],
                         self.observations["generated_at"])
        self.assertEqual(r["input_sha256"]["snapshot"], hash_input(self.snapshot))
        self.assertEqual(r["input_sha256"]["config"], hash_input(self.config))
        self.assertEqual(r["website_archived_first_seen_records"],
                         self.history["archived_observations"])

    def test_empty_risk_input_remains_unqualified(self):
        report = self.report()
        for key in ("risk", "asset_specific"):
            if not self.observations["groups"][key]["observations"]:
                self.assertEqual(report["groups"][key]["source_status"], "missing_observations")
                self.assertEqual(report["groups"][key]["qualified_signal_count"], 0)

    def test_injected_forged_pit_approval_rejected(self):
        x = copy.deepcopy(self.observations)
        x["groups"]["rates"]["observations"][0]["qualifies_as_model_factor_signal"] = True
        with self.assertRaises(ValueError):
            self.report(observations=x)

    def test_unapproved_public_scores_rejected(self):
        x = copy.deepcopy(self.snapshot)
        x["assets"]["gold"]["score"] = 92.3
        with self.assertRaises(ValueError):
            self.report(snapshot=x)

    def test_future_calibration_cannot_be_misrepresented_as_research(self):
        x = copy.deepcopy(self.snapshot)
        x["scoring"]["calibration_verified"] = True
        with self.assertRaises(ValueError):
            self.report(snapshot=x)

    def test_future_snapshot_refused(self):
        with self.assertRaises(ValueError):
            build(self.snapshot, self.observations, self.history, self.config,
                  now=datetime(2025, 1, 1, tzinfo=timezone.utc))

    def test_history_pit_not_self_approved(self):
        x = copy.deepcopy(self.history)
        x["eligible_for_point_in_time_backtest"] = True
        with self.assertRaises(ValueError):
            self.report(history=x)

    def test_invalid_factor_values_rejected(self):
        x = copy.deepcopy(self.observations)
        x["groups"]["rates"]["observations"][0]["value"] = float("nan")
        with self.assertRaises(ValueError):
            self.report(observations=x)

    def test_duplicate_source_observation_rejected(self):
        x = copy.deepcopy(self.observations)
        x["groups"]["rates"]["observations"].append(
            copy.deepcopy(x["groups"]["rates"]["observations"][0]))
        with self.assertRaises(ValueError):
            self.report(observations=x)

    def test_wrong_source_snapshot_lineage_rejected(self):
        x = copy.deepcopy(self.observations)
        x["source_snapshot_observation_date"] = "2022-01-01"
        with self.assertRaises(ValueError):
            self.report(observations=x)

    def test_wrong_source_status_rejected(self):
        x = copy.deepcopy(self.observations)
        x["groups"]["rates"]["status"] = "unavailable"
        with self.assertRaises(ValueError):
            self.report(observations=x)

    def test_invalid_model_weights_rejected(self):
        x = copy.deepcopy(self.config)
        x["weights"]["oil"][0] += 3
        with self.assertRaises(ValueError):
            self.report(config=x)

    def test_no_false_authorization_via_score_one_backend_contract(self):
        r = score_one("gold", {}, self.config)
        self.assertIsNone(r["score"])
        self.assertEqual(r["validation"], {
            "historical_calibration_passed": False,
            "out_of_sample_passed": False})
        self.assertIn("insufficient_weight_coverage", r["blocked_by"])

    def test_backend_validated_fixture_exposes_matching_frontend_contract(self):
        # Synthetic input ONLY to test serialization; never passed into public JSON.
        s = {g: {"signal": 0.3, "verified": True, "fresh": True,
                 "observation_date": "2026-11-20"}
             for g in self.config["factor_order"]}
        approved = {"historical_calibration_passed": True,
                    "out_of_sample_passed": True}
        out = score_one("gold", s, self.config, approved)
        self.assertEqual(out["status"], "calibrated")
        self.assertTrue(out["validation"]["historical_calibration_passed"])
        self.assertTrue(out["validation"]["out_of_sample_passed"])
        self.assertGreater(out["score"], 50)
        self.assertLess(out["score"], 100)

    def test_production_empty_signals_remain_unavailable_after_contract_change(self):
        d = produce({"schema_version": 1}, self.config)
        self.assertTrue(all(
            a["score"] is None and not a["validation"]["out_of_sample_passed"]
            for a in d["assets"].values()))
        self.assertFalse(d["scoring"]["calibration_verified"])


if __name__ == "__main__":
    unittest.main()
