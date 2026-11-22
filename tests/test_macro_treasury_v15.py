"""V15 Treasury official raw byte receipts and PIT fail-closed tests."""
import unittest
from datetime import datetime,timezone
from scripts.collect_treasury_source_evidence_v15 import parse_csv,collect,url_for

YEAR=2026
NOMINAL=b"Date,2 Yr,10 Yr\n11/19/2026,4.01,4.42\n11/20/2026,4.04,4.45\n"
REAL=b"Date,10 Yr\n11/19/2026,2.02\n11/20/2026,2.04\n"

class TreasuryV15Tests(unittest.TestCase):
    def fetch(self,url):
        kind="real" if "type=daily_treasury_real_yield_curve" in url else "nominal"
        return (REAL if kind=="real" else NOMINAL),{"Date":"Sun, 22 Nov 2026 17:00:00 GMT","Last-Modified":"Sun, 22 Nov 2026 00:00:00 GMT"}
    def test_official_url_has_correct_year_and_type(self):
        url=url_for("nominal",2026)
        self.assertIn("/2026/all",url)
        self.assertIn("field_tdr_date_value=2026",url)
        self.assertIn("type=daily_treasury_yield_curve",url)
    def test_raw_capture_does_not_create_release_timestamp(self):
        report=collect(YEAR,self.fetch,"2026-11-23T00:00:00Z")
        self.assertEqual(report["matched_three_series_observation_days"],2)
        self.assertEqual(report["latest_matched_observation"]["treasury.us10y"],4.45)
        self.assertEqual(len(report["source_receipts"]),2)
        self.assertFalse(report["original_publication_time_verified"])
        self.assertFalse(report["historical_value_revision_chain_verified"])
        self.assertFalse(report["eligible_for_point_in_time_backtest"])
        self.assertFalse(report["validated_for_live_scoring"])
        self.assertEqual(len(report["source_receipts"][0]["sha256"]),64)
        self.assertTrue(report["source_receipts"][0]["http_last_modified_unverified_publication_time"])
    def test_out_of_year_and_duplicates_rejected(self):
        with self.assertRaises(ValueError):
            parse_csv(b"Date,2 Yr,10 Yr\n11/20/2025,4,5\n","nominal",2026)
        with self.assertRaises(ValueError):
            parse_csv(NOMINAL+b"11/20/2026,3.94,4.3\n","nominal",2026)
    def test_bad_or_missing_source_rejected(self):
        with self.assertRaises(ValueError):
            parse_csv(b"<html>unavailable</html>","nominal",2026)
        with self.assertRaises(ValueError):
            parse_csv(b"Date,10 Yr\n11/20/2026,4.0\n","nominal",2026)
    def test_missing_pair_is_rejected(self):
        def broken(url):
            if "type=daily_treasury_real_yield_curve" in url:
                return b"Date,10 Yr\n11/18/2026,2.0\n",{}
            return NOMINAL,{}
        with self.assertRaises(ValueError):
            collect(YEAR,broken,"2026-11-23T00:00:00Z")
if __name__=="__main__":unittest.main()
