import unittest
from scripts.check_asset_compass_history_readiness import report
from scripts.archive_asset_compass_observations import rows_from_snapshot
from test_macro_observation_ledger import snapshot

class ReadinessReportTests(unittest.TestCase):
    def test_no_archive_fails_closed(self):
        r=report([])
        self.assertEqual(r["archived_observations"],0)
        self.assertIn("no_live_archive_yet",r["blockers"])
        self.assertFalse(r["validated_for_live_scoring"])
    def test_one_actual_snapshot_is_insufficient_history(self):
        rows=rows_from_snapshot(snapshot(),"2026-11-22T01:00:00Z")
        r=report(rows)
        self.assertEqual(r["archived_observations"],9)
        self.assertEqual(r["series"]["bls.cpi"]["distinct_observation_periods"],1)
        self.assertIn("official_historical_release_vintages_unverified",r["blockers"])
        self.assertFalse(r["eligible_for_point_in_time_backtest"])
    def test_archive_does_not_expose_market_prices(self):
        r=report(rows_from_snapshot(snapshot(),"2026-11-22T01:00:00Z"))
        import json
        content=json.dumps(r)
        self.assertNotIn('"value"',content)
        self.assertNotIn('"source_url"',content)
    def test_rejects_fake_official_release_flags(self):
        r=rows_from_snapshot(snapshot(),"2026-11-22T01:00:00Z")
        r[0]["eligible_for_historical_official_vintage"]=True
        with self.assertRaisesRegex(ValueError,"claims"):
            report(r)
if __name__=="__main__":unittest.main()
