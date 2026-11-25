import unittest
from scripts.asset_compass_six_feature_v90 import evaluate,extend,parse_series
from scripts.asset_compass_sec_returns_v66 import months

class SixFeatureTests(unittest.TestCase):
    def test_fixed_calendar_and_missing(self):
        rows=[{"month":m,"x":[float(i%k) for k in (3,5,7,11,13,17)],"y":i/10} for i,m in enumerate(months("2021-01","2025-12"))]
        r=evaluate(rows)
        self.assertEqual(r["evaluated_months"],30)
        self.assertFalse(r["formal_oos_validated"])
        self.assertIn("without_unemployment_pct",r["incremental_mae_delta_pct"])
        del rows[28]
        q=evaluate(rows)
        self.assertEqual(q["evaluated_months"],24)
        self.assertEqual(q["folds"][0]["test_first"],"2023-10")
    def test_coefficient_sign_stability(self):
        from scripts.asset_compass_six_feature_v90 import stability,NAMES
        folds=[{"six_source_training_coefficients":dict.fromkeys(NAMES,v)} for v in (1,-1,2)]
        r=stability(folds)
        self.assertTrue(r[NAMES[0]]["sign_changed"])
        self.assertEqual(r[NAMES[0]]["positive_folds"],2)
        self.assertFalse(r[NAMES[0]]["certified_model_weight"])
    def test_lag_and_missing(self):
        base=[{"month":"2024-04","x":[1,2,3],"y":0}]
        d={"CPIAUCNS":[{"date":"2023-02-01","value":100},{"date":"2024-02-01","value":105}],"UNRATE":[{"date":"2024-02-01","value":4}],"WALCL":[{"date":"2024-01-31","value":100},{"date":"2024-02-28","value":110}]}
        r,g=extend(base,d)
        self.assertEqual(g,[])
        self.assertAlmostEqual(r[0]["x"][3],5)
        self.assertAlmostEqual(r[0]["x"][5],10)
        d["UNRATE"]=[]
        self.assertEqual(extend(base,d)[1],["2024-04"])
    def test_blank_and_dot_are_missing_not_zero(self):
        raw="DATE,UNRATE\n"
        for month in months("2021-01","2024-12"):
            raw+=month+"-01,"+("" if month=="2022-01" else "." if month=="2022-02" else "0" if month=="2022-03" else "4.0")+"\n"
        rows=parse_series(raw.encode(),"UNRATE")
        self.assertEqual(len(rows),46)
        self.assertNotIn("2022-01-01",{r["date"] for r in rows})
        self.assertEqual(next(r["value"] for r in rows if r["date"]=="2022-03-01"),0)
        with self.assertRaisesRegex(ValueError,"Truncated"):
            parse_series((raw+"2025-01-01\n").encode(),"UNRATE")
    def test_wrong_header(self):
        with self.assertRaises(ValueError):parse_series(b"DATE,WRONG\n2020-01-01,100\n","CPIAUCNS")
