"""A10 SOFR observations must never be confused with forward rates."""
import unittest
from datetime import date
from scripts.update_macro_a10_sofr import parse

class A10SofrTests(unittest.TestCase):
    def test_extract_latest_official_overnight_rate(self):
        source={"refRates":[
           {"type":"SOFR","effectiveDate":"2026-11-18","percentRate":3.90},
           {"type":"SOFR","effectiveDate":"2026-11-19","percentRate":3.91},
           {"type":"EFFR","effectiveDate":"2026-11-20","percentRate":3.88}]}
        d=parse(source,today=date(2026,11,23))
        self.assertEqual(d["sofr_overnight_percent"],3.91)
        self.assertEqual(d["observation_date"],"2026-11-19")
        self.assertFalse(d["sofr_forward_curve_available"])
        self.assertFalse(d["validated_for_live_scoring"])
        self.assertFalse(d["eligible_for_point_in_time_backtest"])
    def test_bad_date_future_and_nonfinite_fail_closed(self):
        with self.assertRaises(ValueError):parse({"refRates":[{"type":"SOFR","effectiveDate":"2026-11-24","percentRate":3.9}]},today=date(2026,11,23))
        with self.assertRaises(ValueError):parse({"refRates":[{"type":"SOFR","effectiveDate":"2026-11-19","percentRate":"NaN"}]},today=date(2026,11,23))
        with self.assertRaises(ValueError):parse({"refRates":[]},today=date(2026,11,23))
    def test_stale_rate_not_published_as_current(self):
        with self.assertRaises(ValueError):parse({"refRates":[{"type":"SOFR","effectiveDate":"2026-10-20","percentRate":4}]},today=date(2026,11,23))
if __name__=="__main__":unittest.main()
