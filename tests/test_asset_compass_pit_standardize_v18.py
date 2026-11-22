"""V18 point-in-time standardization: no look-ahead, no invented samples."""
import sqlite3
import unittest
from datetime import date, timedelta

from scripts.asset_compass_vintages import create_schema, ingest_macro
from scripts.asset_compass_pit_standardize import calculate


class TestPITStandardization(unittest.TestCase):
    def setUp(self):
        self.db = sqlite3.connect(":memory:")
        create_schema(self.db)
        first = date(2020, 1, 1)
        self.rows = []
        for i in range(40):
            obs = first + timedelta(days=i * 30)
            release = obs + timedelta(days=1)
            self.rows.append({
                "series_id": "TEST", "source": "fixture", "frequency": "monthly",
                "units": "index", "observation_date": obs.isoformat(),
                "available_at": release.isoformat() + "T12:00:00Z",
                "value": str(10 + i), "source_release_id": "release-" + str(i),
                "source_url": "https://example.org/release/" + str(i),
            })
        ingest_macro(self.db, self.rows)
        self.asof = (first + timedelta(days=39 * 30 + 2)).isoformat() + "T12:00:00Z"

    def tearDown(self):
        self.db.close()

    def calc(self, **kwargs):
        return calculate(self.db, "TEST", self.asof, max_age_days=45, **kwargs)

    def test_research_z_is_not_asset_signal(self):
        r = self.calc(min_history=36)
        self.assertEqual(r["status"], "research_only")
        self.assertEqual(r["baseline_count"], 39)
        self.assertGreater(r["z_score"], 0)
        self.assertIs(r["validated_for_live_scoring"], False)
        self.assertIsNone(r["asset_specific_signal"])

    def test_unpublished_revision_excluded(self):
        last = self.rows[-1]
        revised = dict(last, value="9999", source_release_id="future-revision",
                       available_at="2028-01-01T00:00:00Z")
        ingest_macro(self.db, [revised])
        r = self.calc()
        self.assertEqual(r["latest_observation"]["value"], 49.0)

    def test_unreleased_future_observation_excluded(self):
        future = dict(self.rows[-1], observation_date="2028-01-01",
                      available_at="2028-01-02T00:00:00Z",
                      source_release_id="future")
        # Do not ingest future observations: the warehouse already guards them.
        with self.assertRaises(ValueError):
            ingest_macro(self.db, [future])

    def test_earlier_asof_has_fewer_observations(self):
        r = calculate(self.db, "TEST", "2020-03-01T00:00:00Z",
                      min_history=36, max_age_days=90)
        self.assertEqual(r["reason"], "insufficient_pit_history")
        self.assertIsNone(r["z_score"])

    def test_stale_and_missing_fail_closed(self):
        r = calculate(self.db, "TEST", "2026-11-22T00:00:00Z", max_age_days=15)
        self.assertEqual(r["reason"], "latest_observation_stale")
        self.assertIsNone(calculate(self.db, "UNKNOWN", self.asof)["z_score"])

    def test_zero_variance(self):
        for row in self.rows:
            row["series_id"] = "FLAT"
            row["value"] = "2"
        ingest_macro(self.db, self.rows)
        r = calculate(self.db, "FLAT", self.asof, max_age_days=45)
        self.assertEqual(r["reason"], "zero_or_invalid_baseline_variance")

    def test_bad_inputs(self):
        for args in ({"min_history": 0}, {"window_days": 0},
                     {"max_age_days": -1}):
            with self.assertRaises(ValueError):
                self.calc(**args)


if __name__ == "__main__":
    unittest.main()
