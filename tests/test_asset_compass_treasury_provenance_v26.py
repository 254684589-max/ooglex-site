"""V26 synthetic regression tests for historical Treasury source year matching."""
import unittest

from scripts.archive_asset_compass_observations import (
    rows_from_snapshot, treasury_source_for_period, append_ledger,
)
from scripts.check_asset_compass_history_readiness import report


class TreasuryProvenanceV26Tests(unittest.TestCase):
    NOMINAL_2025 = ("https://home.treasury.gov/resource-center/data-chart-center/"
                    "interest-rates/daily-treasury-rates.csv/2025/all"
                    "?type=daily_treasury_yield_curve&field_tdr_date_value=2025&page=&_format=csv")
    NOMINAL_2026 = ("https://home.treasury.gov/resource-center/data-chart-center/"
                    "interest-rates/daily-treasury-rates.csv/2026/all"
                    "?type=daily_treasury_yield_curve&field_tdr_date_value=2026&page=&_format=csv")
    REAL_2025 = NOMINAL_2025.replace("type=daily_treasury_yield_curve",
                                     "type=daily_treasury_real_yield_curve")
    REAL_2026 = NOMINAL_2026.replace("type=daily_treasury_yield_curve",
                                     "type=daily_treasury_real_yield_curve")

    def test_first_2025_url_does_not_override_2026(self):
        self.assertEqual(treasury_source_for_period(
            [self.NOMINAL_2025, self.NOMINAL_2026],
            "2026-11-20", "daily_treasury_yield_curve"), self.NOMINAL_2026)

    def test_real_yield_uses_real_curve_of_same_year(self):
        self.assertEqual(treasury_source_for_period(
            [self.NOMINAL_2025, self.REAL_2025, self.NOMINAL_2026, self.REAL_2026],
            "2026-11-20", "daily_treasury_real_yield_curve"), self.REAL_2026)

    def test_no_matching_year_fails_closed(self):
        with self.assertRaises(ValueError):
            treasury_source_for_period([self.NOMINAL_2025], "2026-11-20",
                                       "daily_treasury_yield_curve")

    def test_spoofed_host_fails_closed(self):
        url=self.NOMINAL_2026.replace("home.treasury.gov","home.treasury.gov.attacker.test")
        with self.assertRaises(ValueError):
            treasury_source_for_period([url], "2026-11-20",
                                       "daily_treasury_yield_curve")

    def test_snapshot_archive_corrected_without_overwriting_legacy(self):
        snapshot={
            "schema_version":1,"observation_date":"2026-11-20",
            "rates":{"us10y":4.92,"us2y":4.63,"real10y":2.77,
                     "breakeven10y":2.15,"spread10y2y":0.29},
            "source_urls":[self.NOMINAL_2025,self.REAL_2025,
                           self.NOMINAL_2026,self.REAL_2026],
        }
        corrected=rows_from_snapshot(snapshot,"2026-11-22T07:00:00Z")
        self.assertEqual(len(corrected),5)
        self.assertTrue(all("/2026/all" in r["source_url"] for r in corrected))
        previous=[dict(corrected[0],source_url=self.NOMINAL_2025,
                       first_seen_at="2026-11-22T06:53:57Z")]
        combined,added=append_ledger(previous,[corrected[0]])
        self.assertEqual(len(combined),2)
        self.assertEqual(len(added),1)
        self.assertEqual(combined[0],previous[0])

    def test_readiness_reports_old_bad_provenance(self):
        legacy={"schema_version":1,"series_id":"treasury.us10y",
                "observation_period":"2026-11-20",
                "first_seen_at":"2026-11-22T06:53:57Z",
                "official_release_time_known":False,
                "eligible_for_historical_official_vintage":False,
                "source_url":self.NOMINAL_2025}
        bad=report([legacy])
        self.assertEqual(bad["treasury_source_year_mismatch_rows"],1)
        self.assertIn("treasury_source_year_mismatch_in_immutable_archive",bad["blockers"])
        corrected=dict(legacy,source_url=self.NOMINAL_2026)
        good=report([corrected])
        self.assertEqual(good["treasury_source_year_mismatch_rows"],0)
        self.assertFalse(good["validated_for_live_scoring"])


if __name__=="__main__":
    unittest.main()
