"""V14 PIT qualification is locked until real original releases are verified."""
import unittest
from datetime import datetime,timezone
from scripts.build_asset_compass_pit_gaps_v14 import build
from scripts.check_asset_compass_history_readiness import REQUIRED_SERIES

class V14QualificationTests(unittest.TestCase):
    def test_unverified_snapshot_does_not_admit_any_series(self):
        from scripts.archive_asset_compass_observations import load,LEDGER
        from pathlib import Path
        import json
        root=Path(__file__).resolve().parents[1]
        s=json.loads((root/"data/asset-scores.json").read_text())
        report=build(load(LEDGER),s,now=datetime.now(timezone.utc))
        self.assertEqual(report["required_series"],14)
        self.assertEqual({x["series_id"] for x in report["series"]},REQUIRED_SERIES)
        self.assertEqual(report["independently_qualified_pit_series"],0)
        self.assertFalse(report["eligible_for_point_in_time_backtest"])
        self.assertFalse(report["validated_for_live_scoring"])
        self.assertFalse(report["private_vintage_database_exported"])
        for item in report["series"]:
            self.assertFalse(item["independently_qualified_for_pit"])
            self.assertIn("source_original_release_timestamp_verified",item["evidence_gaps"])
            self.assertIn("redistribution_rights_approved",item["evidence_gaps"])
            self.assertTrue(item["discovery_url"].startswith("https://"))
    def test_invalid_future_ledger_fails(self):
        from scripts.archive_asset_compass_observations import load,LEDGER
        from pathlib import Path
        import json
        root=Path(__file__).resolve().parents[1]
        data=load(LEDGER)
        first=dict(data[0],first_seen_at="2099-01-01T00:00:00+00:00")
        s=json.loads((root/"data/asset-scores.json").read_text())
        with self.assertRaises(ValueError):
            build([first],s,now=datetime(2026,11,23,tzinfo=timezone.utc))
if __name__=="__main__":unittest.main()
