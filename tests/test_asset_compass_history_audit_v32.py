"""V32 research-only archive coverage audit: synthetic data, no market claims."""
import unittest

from scripts.audit_asset_compass_history_v32 import analyze


class HistoricalQualityV32Tests(unittest.TestCase):
    NOW="2026-11-22T12:00:00Z"

    def snapshot(self, **changes):
        return {
            "schema_version":1,
            "generated_at":"2026-11-22T08:30:00Z",
            "bls":{"retrieved_at":"2026-11-22T08:29:00Z"},
            **changes,
        }

    def row(self,sid="treasury.us10y",period="2026-11-20",value=4.92,
            seen="2026-11-22T06:53:57Z",url=None):
        return {
            "schema_version":1,"series_id":sid,
            "source":"synthetic test fixture","observation_period":period,
            "value":value,"unit":"percent",
            "source_url":url or
                "https://home.treasury.gov/resource-center/data-chart-center/interest-rates/daily-treasury-rates.csv/2026/all?type=daily_treasury_yield_curve&field_tdr_date_value=2026",
            "first_seen_at":seen,
            "official_release_time_known":False,
            "eligible_for_historical_official_vintage":False,
            "provenance":"observed_snapshot_first_seen_not_original_release",
        }

    def test_empty_ledger_never_claims_history(self):
        r=analyze([],self.snapshot(),self.NOW)
        self.assertEqual(r["archived_series_count"],0)
        self.assertEqual(len(r["required_missing_series"]),14)
        self.assertEqual(r["number_of_series_with_36_distinct_periods"],0)
        self.assertFalse(r["point_in_time_backtest_eligible"])

    def test_one_period_is_not_one_month_of_history(self):
        r=analyze([self.row()],self.snapshot(),self.NOW)
        d=r["series"]["treasury.us10y"]
        self.assertEqual(d["distinct_observation_periods"],1)
        self.assertEqual(d["periods_to_36_sample_target"],35)
        self.assertEqual(d["cadence"],"daily")
        self.assertIn("treasury.us10y",r["single_period_required_series"])

    def test_source_url_correction_is_not_value_revision(self):
        bad=self.row(url="https://home.treasury.gov/resource-center/data-chart-center/interest-rates/daily-treasury-rates.csv/2025/all?type=daily_treasury_yield_curve&field_tdr_date_value=2025")
        corrected=self.row(seen="2026-11-22T07:15:16Z")
        r=analyze([bad,corrected],self.snapshot(),self.NOW)
        self.assertEqual(r["total_url_only_correction_periods"],1)
        self.assertEqual(r["total_value_revision_periods"],0)
        self.assertEqual(r["series"]["treasury.us10y"]["archived_versions"],2)
        self.assertEqual(r["series"]["treasury.us10y"]["distinct_observation_periods"],1)
        self.assertEqual(r["legacy_treasury_source_year_mismatches"],1)

    def test_numeric_revision_is_detected_not_backdated(self):
        original=self.row()
        revision=self.row(value=4.93,seen="2026-11-22T07:15:16Z")
        r=analyze([original,revision],self.snapshot(),self.NOW)
        self.assertEqual(r["total_value_revision_periods"],1)
        self.assertEqual(r["total_url_only_correction_periods"],0)

    def test_multiple_observations_not_multiple_versions(self):
        rows=[self.row(period="2026-11-19",seen="2026-11-20T08:00:00Z"),
              self.row(period="2026-11-20",seen="2026-11-22T06:00:00Z")]
        r=analyze(rows,self.snapshot(),self.NOW)
        self.assertEqual(r["series"]["treasury.us10y"]["distinct_observation_periods"],2)
        self.assertEqual(r["series"]["treasury.us10y"]["archived_versions"],2)
        self.assertNotIn("treasury.us10y",r["single_period_required_series"])

    def test_inconsistent_timestamps_are_blocked(self):
        data=self.snapshot(bls={"retrieved_at":"2026-11-22T08:31:00Z"})
        r=analyze([self.row()],data,self.NOW)
        self.assertIn("snapshot_temporal_integrity_failed",r["blockers"])
        self.assertEqual(r["snapshot_temporal_integrity"],"blocked")
        self.assertFalse(r["validated_for_live_scoring"])

    def test_false_official_release_claim_rejected(self):
        row=self.row()
        row["official_release_time_known"]=True
        with self.assertRaises(ValueError):
            analyze([row],self.snapshot(),self.NOW)

    def test_future_first_seen_rejected(self):
        with self.assertRaises(ValueError):
            analyze([self.row(seen="2026-11-23T00:00:00Z")],self.snapshot(),self.NOW)

    def test_future_observation_date_rejected(self):
        with self.assertRaises(ValueError):
            analyze([self.row(period="2026-11-23")],self.snapshot(),self.NOW)

    def test_non_finite_value_rejected(self):
        with self.assertRaises(ValueError):
            analyze([self.row(value=float("nan"))],self.snapshot(),self.NOW)

    def test_derived_not_counted_as_required_coverage(self):
        r=analyze([self.row(sid="treasury.spread10y2y")],self.snapshot(),self.NOW)
        self.assertEqual(r["archived_series_count"],0)
        self.assertFalse(r["series"]["treasury.spread10y2y"]["required"])

    def test_output_is_research_only(self):
        r=analyze([self.row()],self.snapshot(),self.NOW)
        self.assertFalse(r["official_release_timestamps_verified"])
        self.assertFalse(r["historical_redistribution_rights_verified"])
        self.assertFalse(r["investment_alerts_enabled"])


if __name__=="__main__":
    unittest.main()
