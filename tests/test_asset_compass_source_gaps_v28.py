"""V28 snapshot-vs-ledger triage, using synthetic samples only."""
import unittest

from scripts.archive_asset_compass_observations import rows_from_snapshot
from scripts.diagnose_asset_compass_sources_v28 import diagnose


class SourceGapsV28Tests(unittest.TestCase):
    NOW = "2026-11-22T12:00:00Z"

    def snapshot(self):
        return {
            "schema_version": 1, "generated_at": "2026-11-22T08:00:00Z",
            "observation_date": "2026-11-20",
            "rates": {"us10y": 4.92},
            "source_urls": [
                "https://home.treasury.gov/resource-center/data-chart-center/"
                "interest-rates/daily-treasury-rates.csv/2026/all"
                "?type=daily_treasury_yield_curve&field_tdr_date_value=2026"
            ]
        }

    def test_absent_source_is_not_fake_zero(self):
        report = diagnose(self.snapshot(), [], self.NOW)
        self.assertIn("bls.core_cpi", report["missing_from_snapshot"])
        self.assertEqual(report["series"]["bls.core_cpi"]["status"],
                         "missing_from_latest_snapshot")
        self.assertIsNone(report["series"]["bls.core_cpi"]["latest_snapshot_observation_period"])
        self.assertFalse(report["collector_failure_reason_known_from_snapshot"])

    def test_valid_snapshot_without_ledger_is_pending_archive(self):
        report = diagnose(self.snapshot(), [], self.NOW)
        self.assertEqual(report["series"]["treasury.us10y"]["status"],
                         "snapshot_present_not_yet_archived")
        self.assertIn("treasury.us10y", report["present_but_not_archived"])

    def test_matching_immutable_record_is_archived(self):
        snapshot = self.snapshot()
        ledger = rows_from_snapshot(snapshot, "2026-11-22T09:00:00Z")
        report = diagnose(snapshot, ledger, self.NOW)
        self.assertEqual(report["series"]["treasury.us10y"]["status"],
                         "snapshot_observation_archived")
        self.assertEqual(report["required_present_in_snapshot"], 1)
        self.assertEqual(report["archive_total_rows"], 1)

    def test_same_observation_but_different_value_stays_pending(self):
        snapshot = self.snapshot()
        ledger = rows_from_snapshot(snapshot, "2026-11-22T09:00:00Z")
        snapshot["rates"]["us10y"] = 4.94
        report = diagnose(snapshot, ledger, self.NOW)
        self.assertIn("treasury.us10y", report["present_but_not_archived"])

    def test_source_link_correction_is_new_version(self):
        snapshot = self.snapshot()
        ledger = rows_from_snapshot(snapshot, "2026-11-22T09:00:00Z")
        ledger[0]["source_url"] = ledger[0]["source_url"].replace(
            "/2026/all", "/2025/all").replace("field_tdr_date_value=2026",
                                            "field_tdr_date_value=2025")
        report = diagnose(snapshot, ledger, self.NOW)
        self.assertIn("treasury.us10y", report["present_but_not_archived"])

    def test_stale_snapshot_is_reported_not_rewritten(self):
        snapshot = self.snapshot()
        snapshot["generated_at"] = "2026-11-17T08:00:00Z"
        report = diagnose(snapshot, [], self.NOW)
        self.assertTrue(report["snapshot_age_exceeds_48_hours"])
        self.assertFalse(report["validated_for_live_scoring"])

    def test_future_snapshot_is_rejected(self):
        snapshot = self.snapshot()
        snapshot["generated_at"] = "2026-12-01T00:00:00Z"
        with self.assertRaises(ValueError):
            diagnose(snapshot, [], self.NOW)

    def test_fake_official_vintage_flag_is_rejected(self):
        snapshot = self.snapshot()
        ledger = rows_from_snapshot(snapshot, "2026-11-22T09:00:00Z")
        ledger[0]["official_release_time_known"] = True
        with self.assertRaises(ValueError):
            diagnose(snapshot, ledger, self.NOW)

    def test_present_core_cpi_is_distinguished_from_archive_gap(self):
        snapshot = self.snapshot()
        snapshot["bls"] = {
            "series": {"core_cpi": {"period": "2026-10", "value": 341.7}},
            "source_url": "https://api.bls.gov/publicAPI/v1/timeseries/data/"
        }
        report = diagnose(snapshot, [], self.NOW)
        self.assertNotIn("bls.core_cpi", report["missing_from_snapshot"])
        self.assertIn("bls.core_cpi", report["present_but_not_archived"])

    def test_missing_snapshot_schema_is_rejected(self):
        snapshot = self.snapshot()
        snapshot["schema_version"] = 2
        with self.assertRaises(ValueError):
            diagnose(snapshot, [], self.NOW)


if __name__ == "__main__":
    unittest.main()
