"""V20 restricted source-validation tests, all synthetic fixtures."""
import sqlite3
import unittest
from datetime import datetime, timezone

from scripts.asset_compass_risk_credit_v20 import (
    CATALOG, approved_permission, import_private, validated_rows
)
from scripts.asset_compass_vintages import asof_macro


class RiskCreditV20Tests(unittest.TestCase):
    def setUp(self):
        self.permission = {"series": {
            sid: {"approved_for_private_research": True,
                  "approved_for_public_redistribution": False,
                  "authority": "fixture operator", "evidence_reference": "test-only",
                  "reviewed_at": "2025-01-01T00:00:00Z"}
            for sid in CATALOG
        }}
        self.row = dict(
            series_id="VIXCLS", source="Cboe", frequency="daily", units="index",
            observation_date="2025-01-02",
            available_at="2025-01-03T12:00:00Z",
            value="19.4", source_release_id="synthetic-test-release",
            source_url="https://fred.stlouisfed.org/series/VIXCLS"
        )
        self.db = sqlite3.connect(":memory:")

    def tearDown(self):
        self.db.close()

    def test_no_implicit_permission(self):
        self.assertFalse(approved_permission({}, "VIXCLS"))
        with self.assertRaises(PermissionError):
            validated_rows([self.row], {})

    def test_no_public_redistribution_attestation(self):
        self.permission["series"]["VIXCLS"]["approved_for_public_redistribution"] = True
        with self.assertRaises(PermissionError):
            validated_rows([self.row], self.permission)

    def test_host_owner_and_units_rejected(self):
        for change in (
            {"source_url": "https://fred.stlouisfed.org.evil.test/x"},
            {"source_url": "http://fred.stlouisfed.org/x"},
            {"source": "FRED"}, {"units": "percent"}, {"series_id": "BAD"}
        ):
            bad = dict(self.row, **change)
            with self.assertRaises((ValueError, PermissionError)):
                validated_rows([bad], self.permission)

    def test_invalid_values_and_unpublished_releases(self):
        for v in ("nan", "-2", "inf"):
            with self.assertRaises(ValueError):
                validated_rows([dict(self.row, value=v)], self.permission)
        with self.assertRaises(ValueError):
            validated_rows([dict(self.row, available_at="2099-01-01T00:00:00Z")], self.permission)

    def test_vintage_visible_only_after_release(self):
        self.assertEqual(import_private(self.db, [self.row], self.permission), 1)
        self.assertIsNone(asof_macro(self.db, "VIXCLS", "2025-01-03T11:59:59Z"))
        self.assertEqual(asof_macro(self.db, "VIXCLS", "2025-01-03T12:00:00Z")["value"], 19.4)
        self.assertEqual(import_private(self.db, [self.row], self.permission), 0)

    def test_credit_catalog_owner(self):
        for sid in ("BAMLC0A0CM", "BAMLH0A0HYM2"):
            row = dict(self.row, series_id=sid,
                       source="ICE Data Indices, LLC", units="percent",
                       source_url="https://fred.stlouisfed.org/series/" + sid)
            self.assertEqual(len(validated_rows([row], self.permission)), 1)


if __name__ == "__main__":
    unittest.main()
