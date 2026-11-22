"""V30 static contract tests for independent source collection and remote persistence.

The actual official data download and GitHub push are verified only by a
completed live GitHub Actions run, never by these offline tests.
"""
import unittest
from pathlib import Path


WORKFLOW = (Path(__file__).resolve().parents[1] /
            ".github/workflows/macro-treasury.yml")


class MacroV30WorkflowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = WORKFLOW.read_text(encoding="utf-8")

    def test_push_kickoff_is_scope_limited(self):
        self.assertIn("  push:\n    branches:\n      - main", self.source)
        self.assertIn("- '.github/workflows/macro-treasury.yml'", self.source)
        self.assertIn("  workflow_dispatch:", self.source)
        self.assertIn("    - cron: '40 23 * * 1-5'", self.source)

    def test_critical_sources_are_independent(self):
        for key, next_step in (
            ("id: bls", "run: python3 scripts/update_macro_bls.py"),
            ("id: effr", "run: python3 scripts/update_macro_nyfed.py"),
        ):
            self.assertIn(key+"\n        continue-on-error: true\n        "+next_step,
                          self.source)

    def test_all_seven_missing_source_collectors_still_run(self):
        for command in (
            "python3 -m scripts.update_macro_fed_bea",
            "python3 -m scripts.update_macro_liquidity",
            "python3 -m scripts.update_nyfed_recession",
        ):
            self.assertIn(command, self.source)

    def test_archive_happens_before_commit_and_remote_check(self):
        steps = [
            "Archive first-seen macro observations",
            "Check historical archive readiness",
            "Commit verified snapshot when changed",
            "Confirm snapshot and append-only archive persisted remotely",
        ]
        indexes = [self.source.index(s) for s in steps]
        self.assertEqual(indexes, sorted(indexes))
        self.assertIn("cmp data/asset-scores.json", self.source)
        self.assertIn("cmp data/asset-compass-observation-ledger.jsonl", self.source)

    def test_source_failures_raise_after_persistence(self):
        self.assertIn("if: always()", self.source)
        self.assertIn("BLS_OUTCOME:", self.source)
        self.assertIn("EFFR_OUTCOME:", self.source)
        self.assertIn('exit 1', self.source)
        self.assertGreater(
            self.source.index("Fail run if critical BLS or EFFR"),
            self.source.index("Commit verified snapshot when changed"))

    def test_no_approval_of_live_scoring(self):
        self.assertIn('summary["validated_for_live_scoring"] is False',
                      self.source)
        self.assertIn('summary["eligible_for_point_in_time_backtest"] is False',
                      self.source)


if __name__ == "__main__":
    unittest.main()
