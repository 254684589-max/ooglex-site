"""V34 BLS capture security and custody tests, never mock-official evidence."""
import hashlib
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from scripts.capture_asset_compass_bls_release_v34 import (
    acquire, normalize_url, NoRedirect,
)
from scripts.archive_asset_compass_observations import ROOT

RAW=b"<!DOCTYPE html><html><head><title>Consumer Price Index</title></head><body>Consumer Price Index archived release</body></html>"

class FakeResponse:
    def __init__(self, data=RAW, media="text/html"):
        self.raw=data
        self.headers={"Content-Type":media}
    def __enter__(self):return self
    def __exit__(self,*args):return False
    def read(self,count):return self.raw[:count]

class FakeOpener:
    def __init__(self, data=RAW, media="text/html"):
        self.data=data
        self.media=media
    def open(self, request, timeout):
        return FakeResponse(self.data,self.media)

class BLSEvidenceV34Tests(unittest.TestCase):
    NOW = None

    def test_capture_metadata_and_sha_without_storing_raw(self):
        result=acquire("bls-cpi-2024-12-release",opener=FakeOpener())
        self.assertEqual(result["sha256"],hashlib.sha256(RAW).hexdigest())
        self.assertEqual(result["byte_size"],len(RAW))
        self.assertFalse(result["raw_artifact_saved_in_private_directory"])
        self.assertFalse(result["historical_byte_availability_verified"])
        self.assertFalse(result["eligible_for_point_in_time_backtest"])

    def test_private_storage_is_immutable_and_idempotent(self):
        with tempfile.TemporaryDirectory() as d:
            first=acquire("bls-cpi-2024-12-release",persist_dir=d,opener=FakeOpener())
            again=acquire("bls-cpi-2024-12-release",persist_dir=d,opener=FakeOpener())
            files=list(Path(d).glob("*.html"))
            self.assertEqual(len(files),1)
            self.assertEqual(files[0].read_bytes(),RAW)
            self.assertEqual(first["sha256"],again["sha256"])
            self.assertTrue(first["raw_artifact_saved_in_private_directory"])

    def test_conflicting_existing_file_is_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            h=hashlib.sha256(RAW).hexdigest()
            (Path(d)/f"bls-cpi-2024-12-release-{h}.html").write_bytes(b"tampered")
            with self.assertRaises(ValueError):
                acquire("bls-cpi-2024-12-release",persist_dir=d,opener=FakeOpener())

    def test_public_repo_private_storage_rejected(self):
        with self.assertRaises(ValueError):
            acquire("bls-cpi-2024-12-release",persist_dir=ROOT/"data"/"secret",
                    opener=FakeOpener())

    def test_unknown_document_rejected(self):
        with self.assertRaises(ValueError):
            acquire("unregistered",opener=FakeOpener())

    def test_wrong_html_document_rejected(self):
        with self.assertRaises(ValueError):
            acquire("bls-cpi-2024-12-release",
                    opener=FakeOpener(b"<!doctype html><html>Other</html>"))

    def test_non_html_content_type_rejected(self):
        with self.assertRaises(ValueError):
            acquire("bls-cpi-2024-12-release",
                    opener=FakeOpener(media="application/pdf"))

    def test_block_bogus_or_http_host(self):
        for url in (
            "http://www.bls.gov/news.release/archives/cpi_01152025.htm",
            "https://www.bls.gov.attacker.test/news.release/archives/cpi_01152025.htm",
            "https://evil.test/news.release/archives/cpi_01152025.htm",
            "https://www.bls.gov/news.release/archives/cpi_01152025.htm?out=x",
        ):
            with self.subTest(url=url), self.assertRaises(ValueError):
                normalize_url(url)

    def test_large_payload_rejected(self):
        body=RAW + b"A"*2_000_001
        with self.assertRaises(ValueError):
            acquire("bls-cpi-2024-12-release",opener=FakeOpener(body))

    def test_bls_source_redirect_rejected(self):
        req=object()
        with self.assertRaises(ValueError):
            NoRedirect().redirect_request(req,None,302,"Found",{},
                                          "https://untrusted.example/file")

    def test_no_asserted_release_timestamp_or_license(self):
        result=acquire("bls-cpi-2024-12-release",opener=FakeOpener())
        self.assertFalse(result["official_original_release_timestamp_verified"])
        self.assertFalse(result["redistribution_license_approved"])
        self.assertFalse(result["historical_value_extracted_or_verified"])


if __name__=="__main__":
    unittest.main()
