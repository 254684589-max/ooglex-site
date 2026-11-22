"""V24 tests use synthetic samples and temporary PRIVATE SQLite files only."""
import sqlite3
import tempfile
import unittest
from pathlib import Path

from scripts.asset_compass_vintages import create_schema, ingest_macro
from scripts.audit_asset_compass_real_history_v24 import audit


class RealHistoryV24Tests(unittest.TestCase):
    NOW = "2025-06-01T00:00:00Z"

    def test_no_ledger_no_db_never_enables_scoring(self):
        result = audit([], now=self.NOW)
        self.assertEqual(result["first_seen_archive"]["record_count"], 0)
        self.assertEqual(result["private_historical_release_vintages"]["status"],
                         "private_pit_db_not_provided")
        self.assertIn("no_private_historical_release_vintages", result["blockers"])
        self.assertFalse(result["validated_for_live_scoring"])
        self.assertFalse(result["eligible_for_point_in_time_backtest"])

    def test_first_seen_is_not_official_release(self):
        rows = [{
            "schema_version": 1, "series_id": "treasury.us10y",
            "observation_period": "2025-05-30",
            "first_seen_at": "2025-05-31T12:00:00Z",
            "official_release_time_known": False,
            "eligible_for_historical_official_vintage": False,
        }]
        result = audit(rows, now=self.NOW)
        self.assertEqual(result["first_seen_archive"]["record_count"], 1)
        self.assertFalse(result["first_seen_archive"]["official_release_time_known"])

    def test_private_db_counts_only_and_license_stays_uncertified(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "research.sqlite"
            with sqlite3.connect(path) as db:
                create_schema(db)
                ingest_macro(db, [{
                    "series_id": "TEST", "source": "fixture", "frequency": "monthly",
                    "units": "index", "observation_date": "2025-04-01",
                    "available_at": "2025-05-01T00:00:00Z",
                    "value": "1.5", "source_release_id": "synthetic",
                    "source_url": "https://example.org/test",
                }])
            result = audit([], path, now=self.NOW)
            data = result["private_historical_release_vintages"]
            self.assertEqual(data["release_version_rows"], 1)
            self.assertEqual(data["distinct_observation_periods"], 1)
            self.assertEqual(data["registered_series"], 1)
            self.assertEqual(data["series"]["TEST"]["license_review_status"], "pending")
            self.assertFalse(result["official_historical_release_times_certified"])
            self.assertFalse(result["historical_data_license_certified"])
            self.assertNotIn("value", str(data))

    def test_private_db_not_found_is_not_empty_success(self):
        with tempfile.TemporaryDirectory() as temp:
            result = audit([], Path(temp) / "missing.sqlite", now=self.NOW)
        self.assertEqual(result["private_historical_release_vintages"]["status"],
                         "private_pit_db_missing")

    def test_future_first_seen_fails(self):
        rows = [{
            "schema_version": 1, "series_id": "treasury.us10y",
            "observation_period": "2025-05-30",
            "first_seen_at": "2025-07-01T00:00:00Z",
            "official_release_time_known": False,
            "eligible_for_historical_official_vintage": False,
        }]
        with self.assertRaises(ValueError):
            audit(rows, now=self.NOW)

    def test_repository_database_path_rejected(self):
        from scripts.audit_asset_compass_real_history_v24 import ROOT
        with self.assertRaises(ValueError):
            audit([], ROOT / "macro" / "private.sqlite", now=self.NOW)


if __name__ == "__main__":
    unittest.main()
