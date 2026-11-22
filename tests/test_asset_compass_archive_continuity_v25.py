"""V25 archive resilience checks. Synthetic snapshots and records only."""
import unittest
from datetime import datetime, timedelta, timezone

from scripts.check_asset_compass_archive_continuity_v25 import (
    preflight, verify_growth, verify_ledger
)


class ArchiveContinuityV25Tests(unittest.TestCase):
    def setUp(self):
        self.now = datetime(2026, 11, 22, 6, 0, tzinfo=timezone.utc)
        self.snapshot = {
            "schema_version": 1,
            "generated_at": (self.now - timedelta(hours=1)).isoformat(),
            "status": "partial_data_no_full_score",
            "observation_date": "2026-11-20",
            "rates": {"us10y": 4.5},
            "source_urls": [
                "https://home.treasury.gov/resource-center/data-chart-center/interest-rates/daily-treasury-rates.csv/2026/all?type=daily_treasury_yield_curve&field_tdr_date_value=2026&page=&_format=csv"
            ],
        }
        self.row = {
            "schema_version": 1, "series_id": "treasury.us10y",
            "observation_period": "2026-11-20", "value": 4.5, "unit": "percent",
            "source_url": "https://home.treasury.gov/example",
            "first_seen_at": (self.now - timedelta(minutes=30)).isoformat(),
            "official_release_time_known": False,
            "eligible_for_historical_official_vintage": False,
            "provenance": "observed_snapshot_first_seen_not_original_release",
        }

    def test_fresh_verified_snapshot(self):
        p = preflight(self.snapshot, self.now.isoformat())
        self.assertEqual(p["candidate_rows"], 1)
        self.assertEqual(p["snapshot_age_hours"], 1)

    def test_stale_snapshot_not_archived(self):
        snap = dict(self.snapshot, generated_at=(self.now - timedelta(hours=49)).isoformat())
        with self.assertRaises(ValueError):
            preflight(snap, self.now.isoformat())

    def test_future_snapshot_not_archived(self):
        snap = dict(self.snapshot, generated_at=(self.now + timedelta(minutes=1)).isoformat())
        with self.assertRaises(ValueError):
            preflight(snap, self.now.isoformat())

    def test_missing_source_refuses_archive(self):
        snap = dict(self.snapshot, source_urls=[])
        with self.assertRaises(ValueError):
            preflight(snap, self.now.isoformat())

    def test_append_only_preserves_existing_records(self):
        first = dict(self.row, first_seen_at=(self.now-timedelta(hours=1)).isoformat())
        second = dict(self.row, value=4.6)
        result = verify_growth([first], [first, second], now=self.now.isoformat())
        self.assertEqual(result["added_rows"], 1)
        self.assertFalse(result["validated_for_live_scoring"])

    def test_rewrite_and_truncation_rejected(self):
        first = dict(self.row, first_seen_at=(self.now-timedelta(hours=1)).isoformat())
        with self.assertRaises(ValueError):
            verify_growth([first], [], now=self.now.isoformat())
        with self.assertRaises(ValueError):
            verify_growth([first], [dict(first, value=5)], now=self.now.isoformat())

    def test_future_first_seen_rejected(self):
        with self.assertRaises(ValueError):
            verify_ledger([dict(self.row, first_seen_at=(self.now+timedelta(days=1)).isoformat())],
                          now=self.now.isoformat())

    def test_fake_release_certification_rejected(self):
        with self.assertRaises(ValueError):
            verify_ledger([dict(self.row, official_release_time_known=True)], now=self.now.isoformat())

    def test_duplicate_archive_record_rejected(self):
        with self.assertRaises(ValueError):
            verify_ledger([self.row, self.row], now=self.now.isoformat())

    def test_backdated_archive_rejected(self):
        earlier = dict(self.row, first_seen_at=(self.now-timedelta(hours=2)).isoformat(),
                       value=4.4)
        with self.assertRaises(ValueError):
            verify_ledger([self.row, earlier], now=self.now.isoformat())


if __name__ == "__main__":
    unittest.main()
