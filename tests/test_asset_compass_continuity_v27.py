"""V27 synthetic operational checks; never synthetic market forecasts."""
import unittest
from datetime import datetime, timedelta, timezone

from scripts.monitor_asset_compass_continuity_v27 import analyze, business_days_since


class ContinuityV27Tests(unittest.TestCase):
    NOW = "2026-11-24T12:00:00Z"

    def row(self, sid, period, seen="2026-11-22T06:53:57Z", value=4.92):
        return {"schema_version": 1, "series_id": sid,
                "observation_period": period, "value": value, "unit": "percent",
                "source_url": (
                    "https://home.treasury.gov/resource-center/data-chart-center/"
                    "interest-rates/daily-treasury-rates.csv/2026/all?"
                    "type=daily_treasury_yield_curve&field_tdr_date_value=2026"
                ) if sid.startswith("treasury.") else "https://example.org/release",
                "first_seen_at": seen,
                "official_release_time_known": False,
                "eligible_for_historical_official_vintage": False,
                "provenance": "observed_snapshot_first_seen_not_original_release"}

    def test_missing_series_separate_from_operational_failure(self):
        result = analyze([self.row("treasury.us10y", "2026-11-20")], self.NOW)
        self.assertEqual(result["monitor_status"], "collecting_with_gaps")
        self.assertIn("bls.core_cpi", result["missing_required_series"])
        self.assertFalse(result["critical_operational_alerts"])
        self.assertEqual(result["series"]["treasury.us10y"]["distinct_periods"], 1)
        self.assertFalse(result["validated_for_live_scoring"])

    def test_weekend_not_a_daily_gap(self):
        from datetime import date
        self.assertEqual(business_days_since(date(2026, 11, 20), date(2026, 11, 23)), 1)

    def test_daily_overdue_triggers_critical(self):
        old = self.row("treasury.us10y", "2026-11-03",
                       seen="2026-11-04T00:00:00Z")
        result = analyze([old], self.NOW)
        self.assertIn("observation_overdue_review:treasury.us10y",
                      result["critical_operational_alerts"])
        self.assertEqual(result["monitor_status"], "attention_required")

    def test_monthly_older_period_not_prematurely_overdue(self):
        row = self.row("bls.cpi", "2026-10")
        result = analyze([row], self.NOW)
        self.assertEqual(result["series"]["bls.cpi"]["status"],
                         "warming_up_single_period")
        self.assertFalse(result["critical_operational_alerts"])

    def test_weekly_stale_alert(self):
        result = analyze([self.row("liquidity.reserves", "2026-10-30",
                                   seen="2026-11-01T00:00:00Z")], self.NOW)
        self.assertIn("observation_overdue_review:liquidity.reserves",
                      result["critical_operational_alerts"])

    def test_derived_rates_not_independent_operational_alert(self):
        result = analyze([self.row("treasury.spread10y2y", "2026-11-03",
                                   seen="2026-11-04T00:00:00Z")], self.NOW)
        self.assertNotIn("observation_overdue_review:treasury.spread10y2y",
                         result["critical_operational_alerts"])

    def test_legacy_provenance_exception_is_reported_without_deletion(self):
        row = self.row("treasury.us10y", "2026-11-20")
        row["source_url"] = row["source_url"].replace(
            "/2026/all", "/2025/all").replace(
            "field_tdr_date_value=2026", "field_tdr_date_value=2025")
        result = analyze([row], self.NOW)
        self.assertEqual(result["provenance_exception_count"], 1)
        self.assertEqual(result["archived_versions"], 1)
        self.assertTrue(any("legacy_treasury" in s
                            for s in result["investigation_warnings"]))

    def test_future_first_seen_rejected(self):
        with self.assertRaises(ValueError):
            analyze([self.row("treasury.us10y", "2026-11-20",
                              seen="2026-12-01T00:00:00Z")], self.NOW)

    def test_empty_archive_is_critical_and_fails_closed(self):
        r = analyze([], self.NOW)
        self.assertIn("archive_missing_or_empty", r["critical_operational_alerts"])
        self.assertFalse(r["eligible_for_point_in_time_backtest"])
        self.assertFalse(r["automatic_investment_alerts_enabled"])

    def test_multiple_vintages_are_not_multiple_periods(self):
        older = self.row("treasury.us10y", "2026-11-20")
        newer = self.row("treasury.us10y", "2026-11-20",
                         seen="2026-11-22T07:15:16Z", value=4.93)
        r = analyze([older,newer], self.NOW)
        self.assertEqual(r["series"]["treasury.us10y"]["versions"], 2)
        self.assertEqual(r["series"]["treasury.us10y"]["distinct_periods"], 1)


if __name__ == "__main__":
    unittest.main()
