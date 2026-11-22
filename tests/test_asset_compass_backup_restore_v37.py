"""V37 offline encryption, restore and mock-R2 transport regression tests."""
import io
import json
import os
import tempfile
import unittest
from pathlib import Path

from scripts.backup_asset_compass_private_v37 import (
    _decrypt, backup_bytes, restore_bytes, write_backup,
)
from scripts.capture_asset_compass_bls_release_v34 import ALLOWLIST
from scripts.verify_asset_compass_private_custody_v36 import (
    record_batch, verify_journal,
)
from scripts.sync_asset_compass_r2_v37 import (
    download_verified, endpoint_for, remote_key, upload_verified,
)

SECRET="v37-fixture-only-strong-passphrase"
ID="bls-cpi-2024-12-release"


class MemoryR2:
    def __init__(self):
        self.objects={}
    def put_object(self,**kw):
        self.objects[(kw["Bucket"],kw["Key"])]=(kw["Body"],kw["Metadata"])
    def get_object(self,**kw):
        body,metadata=self.objects[(kw["Bucket"],kw["Key"])]
        return {"Body":io.BytesIO(body),"Metadata":metadata}


class BackupV37Tests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base=Path(self.tmp.name)
        self.source=self.base/"private"
        self.source.mkdir(mode=0o700)
        os.chmod(self.source,0o700)
        html=b"<!doctype html><html><title>Consumer Price Index</title></html>"
        import hashlib
        digest=hashlib.sha256(html).hexdigest()
        file=self.source/f"{ID}-{digest}.html"
        file.write_bytes(html)
        os.chmod(file,0o600)
        receipt={"artifact_id":ID,"source_url":ALLOWLIST[ID]["url"],
            "historical_observation_period":"2024-12","sha256":digest,
            "byte_size":len(html),"captured_at":"2026-11-22T09:00:00Z",
            "eligible_for_point_in_time_backtest":False,
            "raw_artifact_saved_in_private_directory":True}
        batch={"historical_pit_series_approved":0,
               "eligible_for_point_in_time_backtest":False,
               "entries":{ID:{"status":"captured_today_unverified_for_pit","receipt":receipt}}}
        record_batch(batch,self.source)

    def test_roundtrip_encrypted_and_reverified(self):
        encrypted=backup_bytes(self.source,SECRET)
        self.assertNotIn(b"Consumer Price Index",encrypted)
        self.assertNotIn(b"custody-v36.jsonl",encrypted)
        target=self.base/"restored"
        report=restore_bytes(encrypted,target,SECRET)
        self.assertEqual(report["restored_entries"],1)
        self.assertTrue(report["hash_chain_verified"])
        self.assertEqual(verify_journal(target)["entries"],1)
        self.assertFalse(report["eligible_for_point_in_time_backtest"])

    def test_wrong_password_rejected_before_restore(self):
        encrypted=backup_bytes(self.source,SECRET)
        target=self.base/"not-created"
        with self.assertRaises(Exception):
            restore_bytes(encrypted,target,"different-password-over-sixteen")
        self.assertFalse(target.exists())

    def test_ciphertext_tampering_rejected(self):
        encrypted=json.loads(backup_bytes(self.source,SECRET))
        raw=bytearray(__import__("base64").b64decode(encrypted["ciphertext"]))
        raw[0]^=1
        encrypted["ciphertext"]=__import__("base64").b64encode(raw).decode()
        with self.assertRaises(Exception):
            restore_bytes(json.dumps(encrypted).encode(),self.base/"bad",SECRET)
        self.assertFalse((self.base/"bad").exists())

    def test_restore_refuses_overwrite(self):
        encrypted=backup_bytes(self.source,SECRET)
        target=self.base/"already-exists"
        target.mkdir()
        with self.assertRaises(FileExistsError):
            restore_bytes(encrypted,target,SECRET)

    def test_empty_journal_cannot_be_backed_up(self):
        empty=self.base/"empty"
        empty.mkdir(mode=0o700)
        os.chmod(empty,0o700)
        with self.assertRaises(ValueError):
            backup_bytes(empty,SECRET)

    def test_weak_passphrase_rejected(self):
        with self.assertRaises(ValueError):
            backup_bytes(self.source,"password")

    def test_backup_file_no_overwrite(self):
        dst=self.base/"evidence.enc"
        first=write_backup(self.source,dst,SECRET)
        self.assertTrue(first["encrypted"])
        self.assertEqual(dst.stat().st_mode&0o077,0)
        with self.assertRaises(FileExistsError):
            write_backup(self.source,dst,SECRET)

    def test_r2_roundtrip_requires_encrypted_package(self):
        dst=self.base/"secure.enc"
        write_backup(self.source,dst,SECRET)
        service=MemoryR2()
        key="ooglex-private/v37/evidence-20261122.enc"
        uploaded=upload_verified(service,"private-evidence",key,dst)
        self.assertTrue(uploaded["offsite_copy_verified"])
        self.assertFalse(uploaded["restore_test_verified"])
        downloaded=self.base/"r2-retrieved.enc"
        report=download_verified(service,"private-evidence",key,downloaded)
        self.assertTrue(report["encrypted_file_downloaded"])
        self.assertEqual(dst.read_bytes(),downloaded.read_bytes())
        recovered=self.base/"r2-restored"
        self.assertTrue(restore_bytes(downloaded.read_bytes(),recovered,SECRET)["hash_chain_verified"])

    def test_remote_metadata_tamper_rejected(self):
        archive=self.base/"secure.enc"
        write_backup(self.source,archive,SECRET)
        service=MemoryR2()
        key="ooglex-private/v37/test.enc"
        upload_verified(service,"private-evidence",key,archive)
        body,metadata=service.objects[("private-evidence",key)]
        service.objects[("private-evidence",key)]=(body,{"sha256":"0"*64})
        with self.assertRaises(ValueError):
            download_verified(service,"private-evidence",key,self.base/"corrupt.enc")

    def test_key_traversal_and_account_validation(self):
        for name in ("../x.enc","ooglex-private/v37/../bad.enc",
                     "ooglex-private/v37/plain.txt"):
            with self.subTest(name=name),self.assertRaises(ValueError):
                remote_key(name)
        with self.assertRaises(ValueError):
            endpoint_for("not-an-account")
        self.assertEqual(endpoint_for("a"*32),
            "https://"+("a"*32)+".r2.cloudflarestorage.com")

    def test_private_backup_cannot_land_inside_site_repo(self):
        from scripts.archive_asset_compass_observations import ROOT
        with self.assertRaises(ValueError):
            write_backup(self.source,ROOT/"data"/"private.enc",SECRET)


if __name__=="__main__":
    unittest.main()
