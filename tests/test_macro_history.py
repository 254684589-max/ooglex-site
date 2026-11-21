import unittest
from datetime import date
from scripts.build_asset_compass_history import compile_history

class HistoricalTreasuryTests(unittest.TestCase):
    def test_matching_dates_and_spreads(self):
        n=[{"Date":"11/19/2026","2 Yr":"4.10","10 Yr":"4.50"},
           {"Date":"11/20/2026","2 Yr":"4.20","10 Yr":"4.60"}]
        r=[{"Date":"11/19/2026","10 Yr":"2.10"},
           {"Date":"11/20/2026","10 Yr":"2.30"}]
        rows=compile_history(n,r,date(2026,11,20))
        self.assertEqual(len(rows),2)
        self.assertEqual(rows[-1]["breakeven10y"],2.30)
        self.assertEqual(rows[-1]["spread10y2y"],0.4)
    def test_no_forward_observations(self):
        n=[{"Date":"11/20/2026","2 Yr":"4","10 Yr":"5"}]
        r=[{"Date":"11/20/2026","10 Yr":"2"}]
        with self.assertRaisesRegex(ValueError,"No valid"):
            compile_history(n,r,date(2026,11,19))
    def test_mismatched_dates_not_paired(self):
        n=[{"Date":"11/19/2026","2 Yr":"4","10 Yr":"5"}]
        r=[{"Date":"11/20/2026","10 Yr":"2"}]
        with self.assertRaisesRegex(ValueError,"No valid"):
            compile_history(n,r,date(2026,11,20))
    def test_invalid_rates_not_published(self):
        n=[{"Date":"11/20/2026","2 Yr":"-900","10 Yr":"5"}]
        r=[{"Date":"11/20/2026","10 Yr":"2"}]
        with self.assertRaisesRegex(ValueError,"No valid"):
            compile_history(n,r,date(2026,11,20))
if __name__=="__main__":unittest.main()
