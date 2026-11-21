import unittest
from datetime import timedelta, date
from scripts.backtest_asset_compass import build_examples, evaluate, parse_timestamp

def fake_prices(n=280):
    day=date(2025,1,1)
    rows=[]
    while len(rows)<n:
        if day.weekday()<5:
            rows.append({"asset":"gold","date":day.isoformat(),"close":str(100+len(rows))})
        day+=timedelta(days=1)
    return rows

class BacktestTests(unittest.TestCase):
    def test_timestamps_require_timezone(self):
        with self.assertRaisesRegex(ValueError,"timezone"):
            parse_timestamp("2026-11-20T13:00:00")
    def test_publication_after_decision_excluded(self):
        p=fake_prices(60)
        day=p[0]["date"]
        s=[{"asset":"gold","observation_date":day,"available_at":day+"T23:59:59-05:00","score":"80"}]
        self.assertEqual(build_examples(s,p),[])
    def test_future_price_not_current_price(self):
        p=fake_prices(60);d=p[0]["date"]
        s=[{"asset":"gold","observation_date":d,"available_at":d+"T12:00:00+00:00","score":"80"}]
        rows=build_examples(s,p)
        self.assertEqual(len(rows),1)
        self.assertAlmostEqual(rows[0]["forward_return"],21/100)
        self.assertEqual(rows[0]["exit_date"],p[21]["date"])
    def test_missing_history_refuses_validation(self):
        p=fake_prices(70)
        s=[{"asset":"gold","observation_date":r["date"],"available_at":r["date"]+"T12:00:00Z","score":"70"} for r in p[:40]]
        result=evaluate(build_examples(s,p))
        self.assertEqual(result["gold"]["status"],"insufficient_history")
    def test_even_complete_synthetic_history_is_diagnostic_only(self):
        p=fake_prices(420)
        s=[{"asset":"gold","observation_date":r["date"],"available_at":r["date"]+"T12:00:00Z","score":"70"} for r in p[:390]]
        result=evaluate(build_examples(s,p))
        self.assertNotEqual(result["gold"]["status"],"calibrated")
        self.assertIn(result["gold"]["status"],("diagnostic_only_not_calibrated","insufficient_independent_test","insufficient_purged_train"))
    def test_duplicate_prices_rejected(self):
        p=fake_prices(80)
        with self.assertRaisesRegex(ValueError,"Duplicate"):
            build_examples([],p+[p[0]])
if __name__=="__main__":unittest.main()
