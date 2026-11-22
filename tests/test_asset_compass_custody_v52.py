"""V52 private source byte custody, tamper detection, authenticated recovery."""
import hashlib
import json
import os
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

from scripts.archive_asset_compass_observations import ROOT
from scripts.capture_asset_compass_official_v51 import capture, load_candidates
from scripts.asset_compass_custody_v52 import (
    FORMAT, JOURNAL, _load_journal, audit, backup_and_restore_check,
    capture_and_record, custody_lock, encrypted_backup, r2_upload_verified,
    restore_encrypted, secure_directory,
)


NOW = datetime.now(timezone.utc).replace(microsecond=0)
SECRET = "v52-unit-test-nonproduction-key-2026"


class StubResponse:
    def __init__(self, url, body):
        self.url = url
        self.body = body
        self.headers = {"Content-Type": "text/html"}
    def geturl(self):
        return self.url
    def read(self, length):
        return self.body[:length]
    def __enter__(self):
        return self
    def __exit__(self, *args):
        return False


class StubOpener:
    def __init__(self, item, suffix=""):
        self.item = item
        title = ("Consumer Price Index" if item["release_kind"] == "cpi"
                 else "Employment Situation" if item["release_kind"] == "employment"
                 else "Personal Income and Outlays")
        self.body = ("<!doctype html><html><h1>" + title + "</h1><p>"
                     + item["artifact_id"] + suffix + "</p></html>").encode()
    def open(self, request, timeout):
        if request.full_url != self.item["source_url"]:
            raise ValueError("Wrong source URL")
        return StubResponse(request.full_url, self.body)


def make_fetcher(suffix="", skip=None, authorized=False):
    def fetch(item, *, now, private_dir):
        if item["artifact_id"] == skip:
            raise TimeoutError("official endpoint unreachable")
        receipt = capture(item, now=now, private_dir=private_dir,
                          opener=StubOpener(item, suffix))
        if authorized:
            receipt["eligible_for_point_in_time_backtest"] = True
        return receipt
    return fetch


class V52CustodyTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.private = self.root / "private"
        self.backups = self.root / "backups"
        self.registry = load_candidates()

    def seed(self):
        return capture_and_record(self.private, now=NOW, fetcher=make_fetcher())

    def test_seven_real_candidates_generate_private_content_hash_chain(self):
        r = self.seed()
        self.assertEqual((r["requested"], r["retrieved_now"], r["failed"]), (7, 7, 0))
        self.assertEqual(r["new_custody_events"], 7)
        self.assertTrue(r["original_html_retained_in_private_directory"])
        self.assertFalse(r["offsite_backup_created"])
        self.assertEqual(r["historical_pit_series_approved"], 0)
        a = audit(self.private)
        self.assertEqual(a["verified_capture_events"], 7)
        self.assertEqual(a["distinct_source_documents"], 7)
        self.assertEqual(a["distinct_content_versions"], 7)
        self.assertEqual(a["documents_with_observed_byte_changes"], 0)
        self.assertEqual(len(a["custody_chain_last_sha256"]), 64)
        self.assertEqual(len(list(self.private.glob("*.html"))), 7)
        self.assertEqual(os.stat(self.private).st_mode & 0o077, 0)

    def test_repeated_same_bytes_not_reported_as_official_revision(self):
        self.seed()
        # Identical snapshots at the same instant stay deduplicated.
        result = capture_and_record(self.private, now=NOW, fetcher=make_fetcher())
        self.assertEqual(result["failed"], 0)
        self.assertEqual(result["results"][self.registry["entries"][0]["artifact_id"]]["status"],
                         "same_html_bytes_rechecked")
        self.assertEqual(audit(self.private)["distinct_content_versions"], 7)

    def test_changed_html_reports_observed_difference_not_publisher_revision(self):
        self.seed()
        modified = capture_and_record(self.private, now=NOW,
                                      fetcher=make_fetcher(suffix=" - html changed"))
        self.assertEqual(modified["retrieved_now"], 7)
        self.assertEqual(modified["results"][self.registry["entries"][0]["artifact_id"]]["status"],
                         "changed_html_bytes_observed_not_certified_revision")
        a = audit(self.private)
        self.assertEqual(a["distinct_content_versions"], 14)
        self.assertEqual(a["documents_with_observed_byte_changes"], 7)
        self.assertFalse(a["publication_time_independently_verified"])
        self.assertEqual(a["historical_pit_series_approved"], 0)

    def test_tampered_document_or_journal_rejected_before_any_captures(self):
        self.seed()
        doc = next(self.private.glob("*.html"))
        doc.write_bytes(b"changed")
        with self.assertRaises(ValueError):
            audit(self.private)
        with self.assertRaises(ValueError):
            capture_and_record(self.private, now=NOW, fetcher=make_fetcher())
        self.assertEqual(len(list(self.private.glob("*.html"))), 7)

    def test_invalid_journal_chain_rejected(self):
        self.seed()
        file = self.private / JOURNAL
        rows = file.read_text().splitlines()
        record = json.loads(rows[0])
        record["observation_period"] = "1999-01"
        rows[0] = json.dumps(record)
        file.write_text("\n".join(rows) + "\n")
        with self.assertRaises(ValueError):
            audit(self.private)

    def test_partial_fetch_failure_keeps_valid_successes(self):
        result = capture_and_record(self.private, now=NOW,
                                    fetcher=make_fetcher(skip=self.registry["entries"][0]["artifact_id"]))
        self.assertEqual(result["retrieved_now"], 6)
        self.assertEqual(result["failed"], 1)
        self.assertEqual(result["new_custody_events"], 6)
        self.assertEqual(audit(self.private)["verified_capture_events"], 6)
        self.assertEqual(result["historical_pit_series_approved"], 0)

    def test_forged_pit_receipts_rejected_and_never_logged(self):
        result = capture_and_record(self.private, now=NOW, fetcher=make_fetcher(authorized=True))
        self.assertEqual(result["retrieved_now"], 0)
        self.assertEqual(result["failed"], 7)
        self.assertEqual(audit(self.private)["verified_capture_events"], 0)

    def test_repo_private_path_disallowed(self):
        with self.assertRaises(ValueError):
            capture_and_record(ROOT / "private" / "v52", now=NOW, fetcher=make_fetcher())

    def test_encryption_decryption_and_private_restore_roundtrip(self):
        self.seed()
        archive = encrypted_backup(self.private, SECRET)
        self.assertIn(FORMAT.encode(), archive)
        restored = restore_encrypted(archive, self.root / "recovery", SECRET)
        self.assertTrue(restored["restored_and_verified"])
        self.assertTrue(restored["verified_original_bytes"])
        self.assertEqual(restored["restored_events"], 7)
        self.assertEqual(audit(self.root / "recovery")["custody_chain_last_sha256"],
                         audit(self.private)["custody_chain_last_sha256"])
        with self.assertRaises(FileExistsError):
            restore_encrypted(archive, self.root / "recovery", SECRET)

    def test_wrong_key_or_tampered_ciphertext_cannot_restore(self):
        self.seed()
        archive = encrypted_backup(self.private, SECRET)
        with self.assertRaises(Exception):
            restore_encrypted(archive, self.root / "wrong", "wrong-secret-with-16-characters")
        corrupted = json.loads(archive)
        ciphertext = corrupted["ciphertext"]
        corrupted["ciphertext"] = ("A" if ciphertext[0] != "A" else "B") + ciphertext[1:]
        with self.assertRaises(Exception):
            restore_encrypted(json.dumps(corrupted).encode(), self.root / "tampered", SECRET)

    def test_backup_creates_distinct_file_and_restores_verified(self):
        self.seed()
        report = backup_and_restore_check(self.private, self.backups, SECRET)
        self.assertTrue(report["local_restore_verified"])
        self.assertFalse(report["offsite_restore_verified"])
        self.assertTrue(Path(report["encrypted_archive"]).is_file())
        self.assertEqual(hashlib.sha256(Path(report["encrypted_archive"]).read_bytes()).hexdigest(),
                         report["encrypted_sha256"])
        self.assertEqual(report["historical_pit_series_approved"], 0)

    def test_backup_requires_nonempty_real_custody(self):
        secure_directory(self.private, create=True)
        with self.assertRaises(ValueError):
            encrypted_backup(self.private, SECRET)

    def test_offsite_r2_roundtrip_is_authenticated_not_pit_certification(self):
        self.seed()
        local = backup_and_restore_check(self.private, self.backups, SECRET)
        class Body:
            def __init__(self, b):
                self.b = b
            def read(self, *args):
                return self.b
        class API:
            stored = {}
            def put_object(self, **kw):
                if kw["IfNoneMatch"] != "*" or kw["Key"] in self.stored:
                    raise ValueError("Duplicate remote key prohibited")
                self.stored[kw["Key"]] = (kw["Body"], kw["Metadata"])
            def get_object(self, **kw):
                data, metadata = self.stored[kw["Key"]]
                return {"Body": Body(data), "Metadata": metadata}
        api = API()
        result = r2_upload_verified(local["encrypted_archive"], SECRET, api=api,
                                    bucket="research-private",
                                    remote_key="ooglex-private/v52/audit-test.enc")
        self.assertTrue(result["offsite_copy_verified"])
        self.assertTrue(result["offsite_restore_verified"])
        self.assertEqual(result["historical_pit_series_approved"], 0)
        with self.assertRaises(ValueError):
            r2_upload_verified(local["encrypted_archive"], SECRET, api=api,
                               bucket="research-private",
                               remote_key="ooglex-private/v52/audit-test.enc")

    def test_r2_does_not_accept_public_or_unencrypted_payload(self):
        self.seed()
        local = backup_and_restore_check(self.private, self.backups, SECRET)
        with self.assertRaises(ValueError):
            r2_upload_verified(local["encrypted_archive"], SECRET, api=object(),
                               bucket="private", remote_key="public/raw-page.html")


if __name__ == "__main__":
    unittest.main()
