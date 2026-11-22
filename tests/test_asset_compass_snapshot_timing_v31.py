"""V31 snapshot timestamp consistency regression tests."""
import unittest

from scripts.check_asset_compass_snapshot_timing_v31 import inspect

class SnapshotTimingV31Tests(unittest.TestCase):
    NOW="2026-11-22T09:00:00Z"

    def snapshot(self):
        return {
            "schema_version":1,
            "generated_at":"2026-11-22T08:20:00Z",
            "bls":{"retrieved_at":"2026-11-22T08:19:50Z"},
            "bea":{"retrieved_at":"2026-11-22T08:19:51Z"},
            "fed_h41":{"retrieved_at":"2026-11-22T08:19:51Z"},
            "liquidity":{"retrieved_at":"2026-11-22T08:19:52Z"},
            "nyfed_recession_model":{"retrieved_at":"2026-11-22T08:19:53Z"},
        }

    def test_completed_snapshot_passes(self):
        r=inspect(self.snapshot(),now=self.NOW)
        self.assertEqual(r["status"],"pass")
        self.assertEqual(len(r["source_retrieval_at"]),5)
        self.assertFalse(r["validated_for_live_scoring"])

    def test_actual_v30_timestamp_order_would_be_blocked(self):
        d=self.snapshot()
        d["generated_at"]="2026-11-22T08:19:50Z"
        r=inspect(d,now=self.NOW)
        self.assertIn("retrieval_after_snapshot_generation:liquidity",r["issues"])
        self.assertIn("retrieval_after_snapshot_generation:nyfed_recession_model",r["issues"])

    def test_missing_source_is_not_inferred(self):
        d=self.snapshot()
        del d["bea"]
        self.assertEqual(inspect(d,now=self.NOW)["status"],"pass")

    def test_source_without_retrieval_evidence_blocked(self):
        d=self.snapshot()
        d["bea"]={"core_pce":{"value":123}}
        self.assertIn("missing_retrieval_timestamp:bea",
                      inspect(d,now=self.NOW)["issues"])

    def test_naive_retrieval_time_blocked(self):
        d=self.snapshot()
        d["liquidity"]["retrieved_at"]="2026-11-22T08:19:52"
        self.assertIn("invalid_retrieval_timestamp:liquidity",
                      inspect(d,now=self.NOW)["issues"])

    def test_future_generation_rejected(self):
        d=self.snapshot()
        d["generated_at"]="2026-11-23T00:00:00Z"
        with self.assertRaises(ValueError):
            inspect(d,now=self.NOW)

    def test_future_retrieval_issues_reported(self):
        d=self.snapshot()
        d["bea"]["retrieved_at"]="2026-11-23T00:00:00Z"
        r=inspect(d,now=self.NOW)
        self.assertIn("future_retrieval_timestamp:bea",r["issues"])

    def test_malformed_source_block(self):
        d=self.snapshot()
        d["bls"]=[]
        self.assertIn("malformed_source_block:bls",
                      inspect(d,now=self.NOW)["issues"])

    def test_no_new_vintage_or_scoring_certification(self):
        r=inspect(self.snapshot(),now=self.NOW)
        self.assertFalse(r["official_release_time_certified"])
        self.assertFalse(r["eligible_for_point_in_time_backtest"])
        self.assertFalse(r["validated_for_live_scoring"])

if __name__=="__main__":
    unittest.main()
