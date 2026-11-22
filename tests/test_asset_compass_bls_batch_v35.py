"""V35 multi-release batch manifest with mocked download receipts only."""
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

from scripts.capture_asset_compass_bls_batch_v35 import collect, IDENTIFIERS
from scripts.capture_asset_compass_bls_release_v34 import ALLOWLIST

NOW=datetime(2026,11,22,9,30,tzinfo=timezone.utc)

def receipt(id, now, persist_dir):
    declared=ALLOWLIST[id]
    return {"artifact_id":id,"source_url":declared["url"],
            "historical_observation_period":declared["observation_period"],
            "sha256":"a"*64,"byte_size":1240,
            "eligible_for_point_in_time_backtest":False,
            "raw_artifact_saved_in_private_directory":bool(persist_dir)}

class V35BatchTests(unittest.TestCase):
    def test_three_distinct_observation_periods(self):
        self.assertEqual(len(IDENTIFIERS),3)
        self.assertEqual(len({ALLOWLIST[i]["observation_period"] for i in IDENTIFIERS}),3)

    def test_successful_receipts_only_verify_today_capture(self):
        r=collect(fetcher=receipt,now=NOW)
        self.assertEqual(r["fetched_archives"],3)
        self.assertEqual(r["failed_archives"],0)
        self.assertEqual(r["raw_custody_scope"],"ephemeral_process_only")
        self.assertFalse(r["eligible_for_point_in_time_backtest"])
        self.assertFalse(r["source_document_bytes_continuously_preserved_since_publication"])

    def test_partial_http_failure_not_reported_as_success(self):
        def broken(id,now,persist_dir):
            if id==IDENTIFIERS[1]:raise OSError("blocked")
            return receipt(id,now,persist_dir)
        r=collect(fetcher=broken,now=NOW)
        self.assertEqual(r["fetched_archives"],2)
        self.assertEqual(r["failed_archives"],1)
        self.assertEqual(r["entries"][IDENTIFIERS[1]]["status"],"capture_failed")
        self.assertEqual(r["entries"][IDENTIFIERS[1]]["error_type"],"OSError")

    def test_all_fail_closed(self):
        def blocked(*args,**kwargs):
            raise TimeoutError("rate limit")
        r=collect(fetcher=blocked,now=NOW)
        self.assertEqual(r["fetched_archives"],0)
        self.assertEqual(r["failed_archives"],3)
        self.assertEqual(r["historical_pit_series_approved"],0)

    def test_wrong_url_rejected(self):
        def wrong(id,now,persist_dir):
            d=receipt(id,now,persist_dir)
            d["source_url"]="https://attacker.test/cpi"
            return d
        r=collect(fetcher=wrong,now=NOW)
        self.assertEqual(r["fetched_archives"],0)
        self.assertEqual(r["failed_archives"],3)

    def test_mismatched_observation_period_rejected(self):
        def wrong(id,now,persist_dir):
            d=receipt(id,now,persist_dir)
            d["historical_observation_period"]="2026-11"
            return d
        r=collect(fetcher=wrong,now=NOW)
        self.assertEqual(r["failed_archives"],3)

    def test_unexpected_pit_approval_rejected(self):
        def wrong(id,now,persist_dir):
            d=receipt(id,now,persist_dir)
            d["eligible_for_point_in_time_backtest"]=True
            return d
        r=collect(fetcher=wrong,now=NOW)
        self.assertEqual(r["failed_archives"],3)

    def test_unexpected_saved_claim_rejected(self):
        def wrong(id,now,persist_dir):
            d=receipt(id,now,persist_dir)
            d["raw_artifact_saved_in_private_directory"]=True
            return d
        r=collect(fetcher=wrong,now=NOW)
        self.assertEqual(r["failed_archives"],3)

    def test_private_directory_not_public_release(self):
        with tempfile.TemporaryDirectory() as folder:
            r=collect(fetcher=receipt,private_dir=Path(folder),now=NOW)
            self.assertEqual(r["raw_custody_scope"],"local_private_dir")
            self.assertFalse(r["public_repository_contains_raw_release_files"])
            self.assertFalse(r["original_release_time_independently_verified"])

    def test_naive_clock_rejected(self):
        with self.assertRaises(ValueError):
            collect(fetcher=receipt,now=datetime(2026,11,22,9,30))

    def test_invalid_hash_rejected(self):
        def wrong(id,now,persist_dir):
            d=receipt(id,now,persist_dir)
            d["sha256"]="bad"
            return d
        r=collect(fetcher=wrong,now=NOW)
        self.assertEqual(r["failed_archives"],3)


if __name__=="__main__":
    unittest.main()
