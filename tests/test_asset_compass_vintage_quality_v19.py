"""V19 historical vintage audit tests: provenance, gaps, as-of revisions."""
import sqlite3
import unittest

from scripts.asset_compass_vintages import create_schema, ingest_macro
from scripts.asset_compass_vintage_quality import audit_series


class TestVintageQuality(unittest.TestCase):
    def setUp(self):
        self.db = sqlite3.connect(":memory:")
        create_schema(self.db)
        rows = []
        for month in (1, 2, 4, 5):
            rows.append(dict(
                series_id="CPI_TEST", source="test-fixture", frequency="monthly",
                units="index", observation_date=f"2025-{month:02d}-01",
                available_at=f"2025-{month:02d}-15T12:00:00Z",
                value=str(100 + month),
                source_release_id=f"release-{month}",
                source_url=f"https://example.org/release/{month}"
            ))
        ingest_macro(self.db, rows)
        self.asof = "2025-06-01T00:00:00Z"

    def tearDown(self):
        self.db.close()

    def check(self, **kwargs):
        return audit_series(self.db, "CPI_TEST", self.asof, "2025-01-01",
                            end_date="2025-05-31", **kwargs)

    def test_monthly_gaps_not_imputed(self):
        r = self.check()
        self.assertEqual(r["observed_periods"], 4)
        self.assertEqual(r["missing_months"], ["2025-03"])
        self.assertEqual(r["expected_months"], 5)
        self.assertEqual(r["coverage_ratio"], 0.8)
        self.assertFalse(r["validated_for_live_scoring"])
        self.assertFalse(r["asset_specific_contributions_available"])

    def test_asof_future_revision_excluded(self):
        ingest_macro(self.db, [dict(
            series_id="CPI_TEST", source="test-fixture", frequency="monthly",
            units="index", observation_date="2025-02-01",
            available_at="2026-02-01T00:00:00Z", value="999",
            source_release_id="future-revision",
            source_url="https://example.org/revision"
        )])
        r = self.check()
        self.assertEqual(r["release_versions"], 4)
        self.assertEqual(r["revised_periods"], 0)

    def test_prior_revision_counted(self):
        ingest_macro(self.db, [dict(
            series_id="CPI_TEST", source="test-fixture", frequency="monthly",
            units="index", observation_date="2025-02-01",
            available_at="2025-02-20T00:00:00Z", value="111",
            source_release_id="revision",
            source_url="https://example.org/revision"
        )])
        r = self.check()
        self.assertEqual(r["release_versions"], 5)
        self.assertEqual(r["revised_periods"], 1)
        self.assertEqual(r["observed_periods"], 4)

    def test_no_series_and_no_history(self):
        self.assertEqual(audit_series(self.db, "NOPE", self.asof, "2025-01-01")["reason"],
                         "series_not_registered")
        r = audit_series(self.db, "CPI_TEST", "2025-01-01T00:00:00Z",
                         "2025-01-01", end_date="2025-01-01")
        self.assertEqual(r["reason"], "no_asof_observations")
        self.assertIsNone(r["coverage_ratio"])

    def test_below_coverage_threshold(self):
        self.assertEqual(self.check(min_monthly_coverage=0.9)["reason"],
                         "monthly_coverage_below_research_threshold")

    def test_daily_frequency_not_divided_by_calendar_months(self):
        row = dict(series_id="DAILY_TEST", source="fixture", frequency="daily",
                   units="percent", observation_date="2025-02-01",
                   available_at="2025-02-02T00:00:00Z", value="2",
                   source_release_id="x", source_url="https://example.org/x")
        ingest_macro(self.db, [row])
        r = audit_series(self.db, "DAILY_TEST", self.asof, "2025-01-01",
                         end_date="2025-05-31")
        self.assertIsNone(r["coverage_ratio"])
        self.assertEqual(r["reason"], "coverage_requires_frequency_calendar")

    def test_invalid_dates_and_threshold(self):
        for params in (dict(end_date="2026-01-01"),
                       dict(end_date="2024-01-01"),
                       dict(min_monthly_coverage=1.1)):
            with self.assertRaises(ValueError):
                audit_series(self.db, "CPI_TEST", self.asof,
                             "2025-01-01", **params)


if __name__ == "__main__":
    unittest.main()
