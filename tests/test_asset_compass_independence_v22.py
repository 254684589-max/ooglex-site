"""V22 research-only synthetic checks: not historical market evidence."""
import unittest
from scripts.asset_compass_independence_v22 import run_audit


class IndependenceV22Tests(unittest.TestCase):
    def setUp(self):
        self.asof = "2025-06-01T00:00:00Z"

    def series(self, sid, values, *, frequency="daily", unit="percent"):
        return [{
            "series_id": sid, "observation_date": f"2025-01-{i+1:02d}",
            "available_at": f"2025-01-{i+2:02d}T12:00:00Z",
            "value": v, "unit": unit, "frequency": frequency,
            "source_release_id": f"synthetic-{sid}-{i}",
            "source_url": "https://example.org/source/vintage",
        } for i, v in enumerate(values)]

    def test_perfect_change_correlation_flagged_not_certified(self):
        a = self.series("a", [1, 3, 4, 7, 9, 10, 13, 16, 17, 20, 22])
        b = self.series("b", [10+2*x["value"] for x in a])
        result = run_audit(a+b, self.asof)
        pair = result["pairwise_change_diagnostics"][0]
        self.assertEqual(pair["status"], "high_change_correlation_review")
        self.assertEqual(pair["correlation"], 1.0)
        self.assertFalse(result["independent_factor_groups_certified"])
        self.assertFalse(result["validated_for_live_scoring"])

    def test_future_revision_excluded_at_decision(self):
        a = self.series("a", [1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
        revision = dict(a[0], available_at="2025-08-01T00:00:00Z",
                        source_release_id="late-revision", value=999)
        result = run_audit(a+[revision], self.asof)
        self.assertEqual(result["observations_by_series"]["a"], 10)

    def test_frequency_mismatch_blocks_correlation(self):
        a = self.series("a", list(range(11)))
        b = self.series("b", list(range(11)), frequency="monthly")
        pair = run_audit(a+b, self.asof)["pairwise_change_diagnostics"][0]
        self.assertEqual(pair["status"], "frequency_mismatch")
        self.assertIsNone(pair["correlation"])

    def test_algebraic_identity_blocks_independent_vote(self):
        a = self.series("us10y", [2, 3])
        b = self.series("real10y", [1, 2])
        report = run_audit(a+b, self.asof)
        self.assertEqual(len(report["algebraic_dependencies"]), 1)
        self.assertEqual(report["algebraic_dependencies"][0]["status"],
                         "known_algebraic_dependency_no_independent_vote")

    def test_insufficient_overlap_and_constant(self):
        a = self.series("a", list(range(10)))
        b = self.series("b", [1, 2])
        pair = run_audit(a+b, self.asof)["pairwise_change_diagnostics"][0]
        self.assertEqual(pair["status"], "insufficient_aligned_changes")
        c = self.series("c", [1]*10)
        pair2 = run_audit(a+c, self.asof)["pairwise_change_diagnostics"][0]
        self.assertEqual(pair2["status"], "zero_variance")

    def test_reject_bad_provenance_and_duplicates(self):
        a = self.series("a", [1])[0]
        for change in ({"source_url": "http://example.org/a"},
                       {"available_at": "2025-01-02"},
                       {"value": float("nan")},
                       {"value": True},
                       {"frequency": "hourly"}):
            with self.subTest(change=change), self.assertRaises(ValueError):
                run_audit([dict(a, **change)], self.asof)
        with self.assertRaises(ValueError):
            run_audit([a, a], self.asof)

    def test_no_observations_keeps_gates_locked(self):
        report = run_audit([], self.asof)
        self.assertEqual(report["series_count"], 0)
        self.assertFalse(report["asset_scores_available"])
        self.assertFalse(report["automatic_alerts_enabled"])

    def test_no_mixed_units_within_series(self):
        a = self.series("a", [1, 2])
        a[1]["unit"] = "index"
        with self.assertRaises(ValueError):
            run_audit(a, self.asof)


if __name__ == "__main__":
    unittest.main()
