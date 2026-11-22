"""V7 immutable provenance quarantine regression tests."""
import unittest
from datetime import datetime, timezone

from scripts.audit_asset_compass_provenance_v7 import inspect, LEGACY, LEGACY_PERIOD, LEGACY_TIME, PREFIX, SUFFIX
from scripts.archive_asset_compass_observations import rows_from_snapshot

NOMINAL=lambda y: PREFIX+f"{y}/all?type=daily_treasury_yield_curve&field_tdr_date_value={y}"+SUFFIX
REAL=lambda y: PREFIX+f"{y}/all?type=daily_treasury_real_yield_curve&field_tdr_date_value={y}"+SUFFIX

def row(series, val, unit, kind, year=2025):
    return {"schema_version":1,"series_id":series,
            "observation_period":LEGACY_PERIOD,"first_seen_at":LEGACY_TIME,
            "source_url":REAL(year) if kind=="daily_treasury_real_yield_curve" else NOMINAL(year),
            "value":val,"unit":unit,
            "official_release_time_known":False,
            "eligible_for_historical_official_vintage":False,
            "provenance":"observed_snapshot_first_seen_not_original_release"}

class V7ProvenanceTests(unittest.TestCase):
    def setUp(self):
        self.legacy=[row(k,*v) for k,v in LEGACY.items()]
        self.now=datetime(2026,11,23,tzinfo=timezone.utc).isoformat()

    def test_known_immutable_five_quarantined_not_verified(self):
        r=inspect(self.legacy,now=self.now)
        self.assertEqual(r["legacy_quarantined_rows"],5)
        self.assertEqual(r["unexpected_mismatch_rows"],0)
        self.assertTrue(r["integrity_gate_passed"])
        self.assertFalse(r["legacy_rows_are_valid_evidence"])
        self.assertFalse(r["validated_for_live_scoring"])

    def test_new_bad_url_is_hard_failure(self):
        additional=row("treasury.us10y",4.94,"percent","daily_treasury_yield_curve")
        additional["first_seen_at"]="2026-11-22T07:15:16.780714+00:00"
        r=inspect(self.legacy+[additional],now=self.now)
        self.assertEqual(r["unexpected_mismatch_rows"],1)
        self.assertFalse(r["integrity_gate_passed"])

    def test_known_record_modified_fails(self):
        modified=[dict(x) for x in self.legacy]
        modified[0]["value"]=4.93
        r=inspect(modified,now=self.now)
        self.assertFalse(r["integrity_gate_passed"])

    def test_year_correct_url_is_not_legacy(self):
        corrected=row("treasury.us10y",4.92,"percent","daily_treasury_yield_curve",2026)
        corrected["first_seen_at"]="2026-11-22T07:15:16.780714+00:00"
        r=inspect(self.legacy+[corrected],now=self.now)
        self.assertEqual(r["treasury_valid_source_rows"],1)
        self.assertEqual(r["unexpected_mismatch_rows"],0)
        self.assertTrue(r["integrity_gate_passed"])

if __name__=="__main__":
    unittest.main()
