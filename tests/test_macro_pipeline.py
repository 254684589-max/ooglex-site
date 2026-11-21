import unittest
from datetime import date
from scripts.update_asset_scores import lookup, rowdate
from scripts.update_macro_bls import parse_series, calculate

class MacroPipelineTests(unittest.TestCase):
    def test_treasury_headers(self):
        row={"Date":"11/20/2026","10 Yr":"4.31","2 Yr":"3.92"}
        self.assertEqual(lookup(row,"10yr"),4.31)
        self.assertEqual(lookup(row,"2yr"),3.92)
        self.assertEqual(rowdate(row),date(2026,11,20))
    def test_bls_yoy_and_jobs(self):
        raw={
          "cpi":{"2025-10":300.0,"2026-10":309.0},
          "unemployment":{"2026-10":4.5},
          "payroll":{"2026-09":160000.0,"2026-10":160120.0}
        }
        r=calculate(raw,date(2026,11,22))
        self.assertEqual(r["cpi"]["yoy_percent"],3.0)
        self.assertEqual(r["payroll"]["monthly_change_thousands"],120.0)
        self.assertEqual(r["unemployment"]["value"],4.5)
    def test_future_period_excluded(self):
        r=calculate({"unemployment":{"2026-10":4.5,"2027-01":5.0}},date(2026,11,22))
        self.assertEqual(r["unemployment"]["period"],"2026-10")
    def test_annual_record_excluded(self):
        rows=[{"year":"2026","period":"M13","value":"99"},{"year":"2026","period":"M10","value":"4.5"}]
        self.assertEqual(parse_series({"data":rows}),{"2026-10":4.5})
    def test_stale_data_rejected(self):
        with self.assertRaisesRegex(ValueError,"stale"):
            calculate({"cpi":{"2026-01":300}},date(2026,11,22))

if __name__=="__main__":unittest.main()
