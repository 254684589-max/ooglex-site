"""V17 quote-time context is not release-time or original-PIT certification."""
import copy
import json
import unittest
from datetime import datetime,timezone
from pathlib import Path
from scripts.audit_treasury_publication_v17 import audit

ROOT=Path(__file__).resolve().parents[1]

class TreasuryPublicationV17Tests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.v15=json.loads((ROOT/"data/asset-compass-treasury-source-evidence-v15.json").read_text())
        cls.v16=json.loads((ROOT/"data/asset-compass-treasury-v16-report.json").read_text())

    def test_original_publication_times_are_unknown(self):
        r=audit(self.v15,self.v16,now=datetime(2026,11,23,tzinfo=timezone.utc))
        self.assertEqual(len(r["series"]),3)
        self.assertEqual(r["independently_verified_original_publication_timestamps"],0)
        self.assertFalse(r["quotation_timestamp_is_publication_timestamp"])
        self.assertFalse(r["eligible_for_point_in_time_backtest"])
        for item in r["series"]:
            self.assertEqual(item["official_quote_sampling_approx_local_time"],"15:30")
            self.assertIsNone(item["publication_timestamp_utc"])
            self.assertFalse(item["historical_first_release_vintage_verified"])

    def test_v15_v16_digest_mismatch_is_rejected(self):
        bad=copy.deepcopy(self.v16)
        bad["source_sha256"]["nominal"]="0"*64
        with self.assertRaises(ValueError):
            audit(self.v15,bad,now=datetime(2026,11,23,tzinfo=timezone.utc))

    def test_out_of_order_retrievals_are_rejected(self):
        bad=copy.deepcopy(self.v16)
        bad["checked_at"]="2026-11-22T00:00:00Z"
        with self.assertRaises(ValueError):
            audit(self.v15,bad,now=datetime(2026,11,23,tzinfo=timezone.utc))

    def test_falsified_release_certification_is_rejected(self):
        bad=copy.deepcopy(self.v15)
        bad["original_publication_time_verified"]=True
        with self.assertRaises(ValueError):
            audit(bad,self.v16,now=datetime(2026,11,23,tzinfo=timezone.utc))

if __name__=="__main__":
    unittest.main()
