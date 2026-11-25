import unittest
from scripts.asset_compass_sec_returns_v66 import fund_registry,target,parse
from scripts.asset_compass_monthly_diagnostic_v69 import examples,evaluate,prev
from scripts.asset_compass_sec_returns_v66 import months

class MonthlyDiagnosticTests(unittest.TestCase):
    def test_extended_registry_counts(self):
        self.assertEqual(len(target("TLT",True)),48)
        self.assertEqual(len(target("IVV",True)),33)
        self.assertEqual(len(fund_registry(True)["TLT"][3]),16)
        self.assertEqual(len(fund_registry(True)["IVV"][3]),11)
    def test_lag_no_same_month_information(self):
        hist={"observations":[{"date":"2024-01-31","us10y":4},{"date":"2024-02-29","us10y":4.5},{"date":"2024-03-29","us10y":99}]}
        fund={"monthly_observations":[{"month":"2024-04","reported_fund_total_return_percent":"2"}]}
        r=examples(fund,hist)
        self.assertEqual(r[0]["predictor_end"],"2024-02-29")
        self.assertEqual(r[0]["rate_change_bp"],50)
        self.assertEqual(prev("2024-01",2),"2023-11")
    def test_training_slope_unchanged_by_holdout(self):
        rows=[{"month":m,"rate_change_bp":i,"return_percent":2*i+1} for i,m in enumerate(months("2022-01","2024-06"))]
        r=evaluate(rows)
        self.assertEqual(r["train_slope_pct_per_bp"],2)
        self.assertEqual(r["holdout_mae_pct"],0)
        self.assertFalse(r["formal_oos_validated"])
        for row in rows[-6:]:row["return_percent"]=0
        q=evaluate(rows)
        self.assertEqual(q["train_slope_pct_per_bp"],2)
        self.assertGreater(q["holdout_mae_pct"],0)
    def test_gap_and_short_sample(self):
        self.assertEqual(evaluate([])["status"],"insufficient_exploratory_samples")
        rows=[{"month":m,"rate_change_bp":i,"return_percent":i} for i,m in enumerate(months("2021-01","2024-01"))]
        del rows[3]
        self.assertEqual(evaluate(rows)["status"],"calendar_gap")
