"""V42 Federal Reserve H.15 FRED mirror fallback, all records synthetic."""
import tempfile
import unittest
from datetime import date
from pathlib import Path

from scripts.build_asset_compass_history_fred_v42 import build, SERIES
from scripts.validate_asset_compass_treasury_trends_v42 import validate


class FredMirrorHistoryTests(unittest.TestCase):
    def test_mock_three_series_joins_same_day_and_has_correct_provenance(self):
        with tempfile.TemporaryDirectory() as temp:
            today=date(2026,11,22)
            # 110 genuine-shaped fixture dates; no network request.
            start=date(2026,1,1)
            from datetime import timedelta
            days=[(start+timedelta(days=i)).isoformat() for i in range(110)]
            def fake(series,begin,end):
                self.assertIn(series,SERIES)
                vals={day:{"DGS10":4.55,"DGS2":4.2,"DFII10":2.1}[series] for day in days}
                url=f"https://fred.stlouisfed.org/graph/fredgraph.csv?id={series}&cosd=2026-01-01&coed=2026-11-22"
                return vals,url
            output=Path(temp)/"history.json"
            doc=build(2026,output,today,fake)
            self.assertEqual(doc["source"],"Federal Reserve Board H.15 via FRED")
            self.assertEqual(doc["observation_count"],110)
            self.assertEqual(doc["observations"][0]["breakeven10y"],2.45)
            self.assertEqual(doc["observations"][0]["spread10y2y"],0.35)
            self.assertTrue(doc["not_valid_for_point_in_time_backtest"])
            report=validate(doc,minimum=100)
            self.assertEqual(report["observations"],110)
            self.assertFalse(report["historical_pit_approved"])

    def test_disallow_missing_h15_series(self):
        with tempfile.TemporaryDirectory() as tmp:
            from datetime import timedelta
            start=date(2026,1,1)
            days=[(start+timedelta(days=i)).isoformat() for i in range(101)]
            def fake(series,begin,end):
                vals={day:{"DGS10":4.0,"DGS2":3.5,"DFII10":2.0}[series] for day in days}
                if series=="DFII10":vals={}
                return vals,f"https://fred.stlouisfed.org/graph/fredgraph.csv?id={series}&cosd=2026-01-01&coed=2026-11-22"
            with self.assertRaises(ValueError):
                build(2026,Path(tmp)/"missing.json",date(2026,11,22),fake)


if __name__=="__main__":
    unittest.main()
