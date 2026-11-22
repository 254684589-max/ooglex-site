"""V38 real crypto roundtrips and simulated private R2: no user credentials."""
import hashlib
import io
import os
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

from scripts.accept_asset_compass_recovery_v38 import execute
from scripts.capture_asset_compass_bls_release_v34 import ALLOWLIST
from scripts.verify_asset_compass_private_custody_v36 import record_batch

SECRET="synthetic-test-passphrase-very-long"
ID="bls-cpi-2024-12-release"
NOW=datetime(2026,11,22,12,0,tzinfo=timezone.utc)

class MockR2:
    def __init__(self):
        self.items={}
    def put_object(self,**kw):
        self.items[(kw["Bucket"],kw["Key"])]=(kw["Body"],kw["Metadata"])
    def get_object(self,**kw):
        body,metadata=self.items[(kw["Bucket"],kw["Key"])]
        return {"Body":io.BytesIO(body),"Metadata":metadata}

class RecoveryV38Tests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name)
        self.source=self.root/"private"
        self.source.mkdir(mode=0o700)
        os.chmod(self.source,0o700)
        self.backups=self.root/"backups"
        html=b"<!doctype html><html><title>Consumer Price Index</title></html>"
        digest=hashlib.sha256(html).hexdigest()
        file=self.source/f"{ID}-{digest}.html"
        file.write_bytes(html)
        os.chmod(file,0o600)
        self.receipt={"artifact_id":ID,"source_url":ALLOWLIST[ID]["url"],
            "historical_observation_period":"2024-12","sha256":digest,
            "byte_size":len(html),"captured_at":"2026-11-22T09:00:00Z",
            "eligible_for_point_in_time_backtest":False,
            "raw_artifact_saved_in_private_directory":True}
        self.batch={"historical_pit_series_approved":0,
            "eligible_for_point_in_time_backtest":False,
            "requested_archives":1,"fetched_archives":1,"failed_archives":0,
            "entries":{ID:{"status":"captured_today_unverified_for_pit",
                           "receipt":self.receipt}}}
        record_batch(self.batch,self.source)

    def run_v38(self,**kw):
        return execute(private_dir=self.source,backup_dir=self.backups,
                       secret=SECRET,now=NOW,**kw)

    def test_local_backup_restored_and_qualified_only_for_custody(self):
        r=self.run_v38()
        self.assertEqual(r["status"],"local_recovery_verified_only")
        self.assertEqual(r["custody_entries"],1)
        self.assertTrue(r["encrypted_backup_created"])
        self.assertTrue(r["local_restore_verified"])
        self.assertFalse(r["offsite_copy_verified"])
        self.assertFalse(r["eligible_for_point_in_time_backtest"])
        self.assertEqual(len(list(self.backups.glob("*.enc"))),1)

    def test_offsite_r2_roundtrip_and_restore(self):
        fake=MockR2()
        r=self.run_v38(offsite=True,r2_client=fake,r2_bucket="private-archive")
        self.assertEqual(r["status"],"offsite_recovery_verified")
        self.assertTrue(r["offsite_copy_verified"])
        self.assertTrue(r["offsite_restore_verified"])
        self.assertEqual(len(fake.items),1)
        self.assertFalse(r["validated_for_live_scoring"])

    def test_missing_r2_bucket_fails_without_faking_success(self):
        r=self.run_v38(offsite=True,r2_client=MockR2())
        self.assertEqual(r["status"],"failed")
        self.assertEqual(r["failed_stage"],"r2_preflight")
        self.assertFalse(r["offsite_copy_verified"])
        self.assertTrue(r["local_restore_verified"])

    def test_remote_tamper_fails_restore(self):
        class CorruptR2(MockR2):
            def get_object(self,**kw):
                body,metadata=self.items[(kw["Bucket"],kw["Key"])]
                return {"Body":io.BytesIO(b"tampered"),"Metadata":metadata}
        r=self.run_v38(offsite=True,r2_client=CorruptR2(),
                       r2_bucket="private-archive")
        self.assertEqual(r["status"],"failed")
        self.assertEqual(r["failed_stage"],"r2_upload_roundtrip")
        self.assertFalse(r["offsite_copy_verified"])

    def test_empty_archive_fails_closed(self):
        empty=self.root/"empty"
        empty.mkdir(mode=0o700)
        os.chmod(empty,0o700)
        r=execute(private_dir=empty,backup_dir=self.backups,
                  secret=SECRET,now=NOW)
        self.assertEqual(r["status"],"failed")
        self.assertFalse(r["private_custody_verified"])
        self.assertFalse(r["encrypted_backup_created"])

    def test_short_passphrase_fails_preflight(self):
        r=execute(private_dir=self.source,backup_dir=self.backups,
                  secret="short",now=NOW)
        self.assertEqual(r["status"],"failed")
        self.assertEqual(r["failed_stage"],"preflight")

    def test_custody_tampering_fails_before_encryption(self):
        for file in self.source.glob("*.html"):
            file.write_bytes(b"modified")
        r=self.run_v38()
        self.assertEqual(r["failed_stage"],"custody_check")
        self.assertFalse(r["encrypted_backup_created"])

    def test_capture_failure_preserves_partial_evidence_no_backup(self):
        def collector(*,private_dir):
            return {**self.batch,"failed_archives":2,"requested_archives":3}
        r=self.run_v38(capture=True,batch_fetcher=collector)
        self.assertEqual(r["failed_stage"],"capture")
        self.assertEqual(r["capture_failed"],2)
        self.assertFalse(r["encrypted_backup_created"])

    def test_capture_success_continues_to_recovery(self):
        def collector(*,private_dir):
            return self.batch
        r=self.run_v38(capture=True,batch_fetcher=collector)
        self.assertEqual(r["status"],"local_recovery_verified_only")
        self.assertTrue(r["capture_successful"])
        self.assertTrue(r["local_restore_verified"])

    def test_custody_and_backups_must_be_separate(self):
        r=execute(private_dir=self.source,backup_dir=self.source,
                  secret=SECRET,now=NOW)
        self.assertEqual(r["status"],"failed")
        self.assertEqual(r["failed_stage"],"preflight")

    def test_no_unverified_pit_ever_approved(self):
        r=self.run_v38()
        self.assertFalse(r["historical_release_time_verified"])
        self.assertFalse(r["automatic_investment_alerts_enabled"])

if __name__=="__main__":
    unittest.main()
