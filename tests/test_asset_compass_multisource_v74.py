import unittest
from scripts.asset_compass_multisource_v74 import align,evaluate,fit,MIN_TRAIN,EMBARGO,TEST
from scripts.asset_compass_sec_returns_v66 import months

def sample():
    return [{"month":m,"x":[float(i),float(i%5),float(i%7)],"y":i/3-2}
            for i,m in enumerate(months("2021-01","2024-12"))]

class MultiSourceTests(unittest.TestCase):
    def test_exact_lag_and_missing(self):
        fund={"monthly_observations":[{"month":"2024-04","reported_fund_total_return_percent":"1"}]}
        t=[{"date":"2024-01-31","us10y":4},{"date":"2024-02-29","us10y":4.5},{"date":"2024-03-29","us10y":99}]
        u=[{"date":"2024-01-31","index":100},{"date":"2024-02-29","index":101},{"date":"2024-03-29","index":300}]
        n=[{"date":"2024-02-23","value":0.5},{"date":"2024-03-29","value":99}]
        rows,missing=align(fund,t,u,n)
        self.assertEqual(missing,[])
        self.assertEqual(rows[0]["latest_feature_observation"],"2024-02-29")
        self.assertAlmostEqual(rows[0]["x"][0],50)
        self.assertAlmostEqual(rows[0]["x"][1],1)
        self.assertEqual(rows[0]["x"][2],0.5)
        self.assertEqual(align(fund,t,[],n)[1],["2024-04"])
    def test_fixed_folds_and_embargo(self):
        r=evaluate(sample(),[])
        self.assertEqual(len(r["folds"]),3)
        self.assertEqual(r["evaluated_months"],18)
        self.assertEqual(r["folds"][0]["train_count"],MIN_TRAIN)
        self.assertEqual(r["folds"][0]["train_last"],"2022-12")
        self.assertEqual(r["folds"][0]["test_first"],"2023-04")
        self.assertFalse(r["formal_oos_validated"])
        self.assertIn("without_nfci",r["incremental_mae_delta_pct"])
    def test_training_unchanged_by_future_label(self):
        rows=sample()
        train=rows[:MIN_TRAIN]
        p=fit(train,(0,1,2))(rows[MIN_TRAIN+EMBARGO])
        rows[-1]["y"]=999
        self.assertEqual(p,fit(train,(0,1,2))(rows[MIN_TRAIN+EMBARGO]))
    def test_gap_and_short_block(self):
        self.assertEqual(evaluate(sample(),["2021-01"])["status"],"calendar_or_source_gap")
        self.assertEqual(evaluate(sample()[:10],[])["status"],"insufficient_exploratory_samples")
        rows=sample()
        del rows[1]
        self.assertEqual(evaluate(rows,[])["status"],"calendar_or_source_gap")
