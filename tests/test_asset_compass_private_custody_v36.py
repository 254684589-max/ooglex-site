"""V36 private custody test fixtures; none are real archived economic releases."""
import hashlib
import json
import os
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

from scripts.capture_asset_compass_bls_release_v34 import ALLOWLIST
from scripts.verify_asset_compass_private_custody_v36 import (
    JOURNAL, private_directory, record_batch, verify_journal,
)

class V36CustodyTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name)/"evidence"
        self.root.mkdir(mode=0o700)
        os.chmod(self.root,0o700)
        self.identifier="bls-cpi-2024-12-release"
        self.html=b"<!doctype html><html><title>Consumer Price Index</title></html>"
        self.digest=hashlib.sha256(self.html).hexdigest()
        self.file=self.root/f"{self.identifier}-{self.digest}.html"
        self.file.write_bytes(self.html)
        os.chmod(self.file,0o600)

    def receipt(self,**changes):
        return {"artifact_id":self.identifier,"source_url":ALLOWLIST[self.identifier]["url"],
            "historical_observation_period":"2024-12",
            "sha256":self.digest,"byte_size":len(self.html),
            "captured_at":"2026-11-22T09:00:00Z",
            "raw_artifact_saved_in_private_directory":True,
            "eligible_for_point_in_time_backtest":False,**changes}

    def batch(self, receipt=None):
        return {"historical_pit_series_approved":0,
            "eligible_for_point_in_time_backtest":False,
            "entries":{self.identifier:{"status":"captured_today_unverified_for_pit",
                                      "receipt":receipt or self.receipt()}}}

    def test_append_and_verify_chain(self):
        result=record_batch(self.batch(),self.root)
        self.assertEqual(result["new_custody_records"],1)
        self.assertEqual(verify_journal(self.root)["entries"],1)
        self.assertFalse(result["historic_release_time_verified"])
        self.assertFalse(result["permanent_backup_verified"])

    def test_repeat_same_receipt_is_idempotent(self):
        record_batch(self.batch(),self.root)
        r=record_batch(self.batch(),self.root)
        self.assertEqual(r["new_custody_records"],0)
        self.assertEqual(r["verified_total_records"],1)

    def test_html_tampering_is_detected(self):
        record_batch(self.batch(),self.root)
        self.file.write_bytes(b"tampered")
        with self.assertRaises(ValueError):
            verify_journal(self.root)

    def test_journal_tampering_is_detected(self):
        record_batch(self.batch(),self.root)
        path=self.root/JOURNAL
        contents=path.read_text()
        path.write_text(contents.replace("2024-12","2024-11"))
        with self.assertRaises(ValueError):
            verify_journal(self.root)

    def test_missing_html_is_detected(self):
        record_batch(self.batch(),self.root)
        self.file.unlink()
        with self.assertRaises(ValueError):
            verify_journal(self.root)

    def test_extra_group_permissions_rejected(self):
        os.chmod(self.root,0o755)
        with self.assertRaises(ValueError):
            private_directory(self.root)

    def test_source_url_mismatch_rejected(self):
        r=self.receipt()
        r["source_url"]="https://example.invalid/archive"
        with self.assertRaises(ValueError):
            record_batch(self.batch(r),self.root)

    def test_fake_pit_certification_rejected(self):
        r=self.receipt()
        r["eligible_for_point_in_time_backtest"]=True
        with self.assertRaises(ValueError):
            record_batch(self.batch(r),self.root)

    def test_unstored_receipt_rejected(self):
        r=self.receipt()
        r["raw_artifact_saved_in_private_directory"]=False
        with self.assertRaises(ValueError):
            record_batch(self.batch(r),self.root)

    def test_future_capture_time_rejected(self):
        r=self.receipt()
        r["captured_at"]="2099-01-01T00:00:00Z"
        with self.assertRaises(ValueError):
            record_batch(self.batch(r),self.root)

    def test_partial_batch_with_error_only_adds_actual_captures(self):
        batch=self.batch()
        batch["entries"]["bls-cpi-2025-01-release"]={"status":"capture_failed","error_type":"HTTPError"}
        state=record_batch(batch,self.root)
        self.assertEqual(state["verified_total_records"],1)

    def test_restricted_journal_permissions(self):
        record_batch(self.batch(),self.root)
        os.chmod(self.root/JOURNAL,0o644)
        with self.assertRaises(ValueError):
            verify_journal(self.root)

    def test_invalid_hash_rejected(self):
        r=self.receipt()
        r["sha256"]="unverified"
        with self.assertRaises(ValueError):
            record_batch(self.batch(r),self.root)

if __name__=="__main__":
    unittest.main()
