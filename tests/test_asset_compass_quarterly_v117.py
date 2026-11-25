import unittest
from decimal import Decimal
from scripts.asset_compass_quarterly_v117 import derive_quarter,combine,aggregate_monthly,parse_doc,DOCS,quarter_months,common_diagnostics

class QuarterlyResearchTests(unittest.TestCase):
    def test_annual_division_not_subtraction(self):
        self.assertEqual(derive_quarter(Decimal(32),Decimal(20)),Decimal(10))
        with self.assertRaises(ValueError):derive_quarter(Decimal(20),Decimal(-100))
    def test_full_quarter_and_missing_month(self):
        fund={"monthly_observations":[{"month":m,"reported_fund_total_return_percent":"10"} for m in ("2024-01","2024-02","2024-03","2024-04","2024-06")]}
        self.assertAlmostEqual(aggregate_monthly(fund)["2024-03"],33.1)
        self.assertNotIn("2024-06",aggregate_monthly(fund))
    def test_duplicate_claim_must_match(self):
        a={"ticker":"GLD","direct":{"2024-03":Decimal(5)},"cumulative":{},"kind":"cumulative_partial","sha256":"a"*64}
        r=combine([a,a],"GLD")
        self.assertEqual(r["direct_quarters"],1)
        self.assertEqual(r["target_quarters"],12)
        self.assertFalse(r["monthly_returns_inferred"])
        with self.assertRaises(ValueError):combine([a,{**a,"direct":{"2024-03":Decimal(6)}}],"GLD")
    def test_partial_inception_excluded(self):
        doc=next(d for d in DOCS if d[0]=="IBIT" and None in d[2])
        raw=b"<html>iShares Bitcoin Trust ETF<table><tr><td>Total return, at net asset value</td><td>(11.21</td><td>)%</td><td>52.94</td></tr></table></html>"
        r=parse_doc(doc,raw)
        self.assertEqual(r["direct"],{"2025-03":Decimal("-11.21")})
    def test_same_quarters_only(self):
        r=common_diagnostics({"A":{"2024-03":1,"2024-06":9},"B":{"2024-03":-1}})
        self.assertEqual(r["common_quarters"],["2024-03"])
        self.assertEqual(r["descriptive"]["A"]["mean_quarterly_return_pct"],1)
        self.assertFalse(r["predictive_validation"])
