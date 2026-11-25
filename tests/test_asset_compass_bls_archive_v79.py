import unittest
from scripts.asset_compass_bls_archive_v79 import discover,header,expected_periods,summary

class ArchiveTests(unittest.TestCase):
    def test_index_link_and_gap(self):
        raw=b'<a href="/news.release/archives/cpi_10242025.htm">September 2025 Consumer Price Index</a>'
        r=discover(raw,"cpi")
        self.assertEqual(r["2025-09"]["scheduled_release_date_candidate_unverified"],"2025-10-24")
        self.assertEqual(len(expected_periods()),23)
        self.assertNotIn("2025-10",expected_periods())
    def test_reject_wrong_family_and_blocked_month(self):
        for raw in [b'<a href="/news.release/archives/empsit_10242025.htm">September 2025 Consumer Price Index</a>',
                    b'<a href="/news.release/archives/cpi_11142025.htm">October 2025 Consumer Price Index</a>']:
            with self.assertRaises(ValueError):discover(raw,"cpi")
    def test_header_is_candidate_not_pit(self):
        s={"scheduled_release_date_candidate_unverified":"2025-10-24"}
        raw=b'<html>Transmission of material in this release is embargoed until 8:30 a.m. (ET) Friday, October 24, 2025 USDL-25-1502</html>'
        r=header(s,raw)
        self.assertEqual(r["publisher_stated_embargo_utc"],"2025-10-24T12:30:00+00:00")
        self.assertFalse(r["publication_time_verified"])
        s["scheduled_release_date_candidate_unverified"]="2025-10-25"
        self.assertEqual(header(s,raw)["header_status"],"archive_date_mismatch")
    def test_empty_does_not_pass(self):
        r=summary([],{}, {})
        self.assertEqual(len(r["families"]["cpi"]["missing_periods"]),23)
        self.assertFalse(r["eligible_for_live_scoring"])
