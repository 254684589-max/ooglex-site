"""V51 validates real source registry and mocked byte-level capture; no network."""
import copy
import hashlib
import json
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

from scripts.capture_asset_compass_official_v51 import (
    ROOT, BLOCKED_2025, _canonical, _private_path, capture,
    collect, load_candidates,
)

NOW = datetime(2026, 11, 23, 3, 0, tzinfo=timezone.utc)


def sample_bytes(item):
    marker = ("Consumer Price Index" if item["release_kind"] == "cpi"
              else "Employment Situation" if item["release_kind"] == "employment"
              else "Personal Income and Outlays")
    return ('<!doctype html><html><body><h1>' + marker
            + '</h1><p>Archived statistical news release</p></body></html>').encode()


class Response:
    def __init__(self, url, body, content_type="text/html"):
        self.url, self.body = url, body
        self.headers = {"Content-Type": content_type}

    def geturl(self):
        return self.url

    def read(self, limit):
        return self.body[:limit]

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False


class Opener:
    def __init__(self, item, *, redirect=None, content_type="text/html", body=None):
        self.item = item
        self.url = redirect if redirect else item["source_url"]
        self.content_type = content_type
        self.body = sample_bytes(item) if body is None else body

    def open(self, request, timeout):
        if request.full_url != self.item["source_url"]:
            raise AssertionError("Unexpected URL")
        if timeout < 1:
            raise AssertionError("Missing HTTP timeout")
        return Response(self.url, self.body, self.content_type)


class V51Tests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.registry = load_candidates()

    def test_exact_source_coverage_and_no_missing_october_report(self):
        entries = self.registry["entries"]
        self.assertEqual(len(entries), 7)
        self.assertEqual(len({x["artifact_id"] for x in entries}), 7)
        self.assertEqual({(x["publisher"], x["release_kind"], x["observation_period"])
                          for x in self.registry["known_not_published"]}, BLOCKED_2025)
        self.assertEqual({x["publisher"] for x in entries}, {"BLS", "BEA"})

    def test_immutable_bls_url_and_bea_archive_urls(self):
        for x in self.registry["entries"]:
            self.assertEqual(_canonical(x["source_url"], x["publisher"]), x["source_url"])
        for host in ("https://evil.example", "http://www.bls.gov",
                     "https://www.bls.gov.evil.example"):
            with self.assertRaises(ValueError):
                _canonical(host + "/news.release/archives/cpi_01152025.htm", "BLS")
        with self.assertRaises(ValueError):
            _canonical("https://www.bls.gov/news.release/archives/cpi_01152025.htm?x=1", "BLS")
        with self.assertRaises(ValueError):
            _canonical("https://www.bls.gov/news.release/archives/../cpi_01152025.htm", "BLS")
        with self.assertRaises(ValueError):
            _canonical("https://www.bea.gov/news/archive?field_related_product_target_id=716", "BEA")

    def test_capture_exact_bytes_digest_and_utc_fetch_time_not_pit(self):
        for item in self.registry["entries"]:
            raw = sample_bytes(item)
            got = capture(item, opener=Opener(item), now=NOW)
            self.assertEqual(got["sha256"], hashlib.sha256(raw).hexdigest())
            self.assertEqual(got["byte_size"], len(raw))
            self.assertEqual(got["captured_at"], "2026-11-23T03:00:00Z")
            self.assertFalse(got["exact_original_publication_time_verified"])
            self.assertFalse(got["historical_artifact_identity_verified"])
            self.assertFalse(got["historical_release_value_verified"])
            self.assertFalse(got["eligible_for_point_in_time_backtest"])

    def test_archived_html_saved_outside_public_site_in_private_mode(self):
        item = self.registry["entries"][0]
        with tempfile.TemporaryDirectory() as d:
            folder = Path(d) / "private"
            for _ in range(2):
                got = capture(item, opener=Opener(item), now=NOW, private_dir=folder)
                self.assertTrue(got["raw_bytes_saved_privately"])
            paths = list(folder.iterdir())
            self.assertEqual(len(paths), 1)
            self.assertEqual(paths[0].read_bytes(), sample_bytes(item))
            self.assertEqual(hashlib.sha256(paths[0].read_bytes()).hexdigest(), got["sha256"])
            paths[0].write_bytes(b"tampered")
            with self.assertRaises(ValueError):
                capture(item, opener=Opener(item), now=NOW, private_dir=folder)

    def test_public_repo_private_path_rejected(self):
        with self.assertRaises(ValueError):
            _private_path(ROOT / "data" / "sensitive_release.html")
        with self.assertRaises(ValueError):
            capture(self.registry["entries"][0], now=NOW, opener=Opener(self.registry["entries"][0]),
                    private_dir=ROOT / "private")

    def test_redirect_content_type_subject_and_size_fail_closed(self):
        item = self.registry["entries"][0]
        for client in (
            Opener(item, redirect="https://evil.example/cpi"),
            Opener(item, content_type="text/plain"),
            Opener(item, body=b"<html>not an actual CPI release</html>"),
            Opener(item, body=b"<html>Consumer Price Index</html>" + b"x" * 3_000_000),
            Opener(item, body=b""),
        ):
            with self.assertRaises(ValueError):
                capture(item, opener=client, now=NOW)

    def test_unverified_capture_manifest_and_all_series_not_scoring(self):
        def downloader(source, now, private_dir):
            return capture(source, now=now, private_dir=private_dir,
                           opener=Opener(source))
        result = collect(candidates=self.registry, fetcher=downloader, now=NOW)
        self.assertEqual(result["requested"], 7)
        self.assertEqual(result["retrieved_now"], 7)
        self.assertEqual(result["failed"], 0)
        self.assertEqual(result["historical_pit_certified_source_series"], 0)
        self.assertFalse(result["eligible_for_point_in_time_backtest"])
        self.assertFalse(result["validated_for_live_scoring"])
        self.assertEqual(len(result["target_source_series"]), 5)
        self.assertEqual(len(result["known_no_release_periods"]), 2)
        self.assertEqual(result["raw_custody_scope"], "ephemeral_only")

    def test_failed_source_keeps_individual_error_and_no_false_success(self):
        def downloader(source, now, private_dir):
            if source["release_kind"] == "employment":
                raise TimeoutError("source refused")
            return capture(source, now=now, private_dir=private_dir,
                           opener=Opener(source))
        result = collect(candidates=self.registry, fetcher=downloader, now=NOW)
        self.assertEqual(result["requested"], 7)
        self.assertEqual(result["retrieved_now"], 5)
        self.assertEqual(result["failed"], 2)
        self.assertEqual(result["results"]["bls-empsit-2025-01-release"]["error_type"],
                         "TimeoutError")
        self.assertFalse(result["eligible_for_point_in_time_backtest"])

    def test_forged_timestamp_or_pit_authorization_receipt_rejected(self):
        def tampered(source, now, private_dir):
            receipt = capture(source, now=now, opener=Opener(source))
            receipt["exact_original_publication_time_verified"] = True
            return receipt
        report = collect(candidates=self.registry, fetcher=tampered, now=NOW)
        self.assertEqual(report["retrieved_now"], 0)
        self.assertEqual(report["failed"], 7)

    def test_mutated_candidate_registry_cannot_claim_october_data(self):
        with tempfile.TemporaryDirectory() as d:
            for modifier in (
                lambda x: x["known_not_published"].pop(),
                lambda x: x["entries"][0].update(observation_period="2025-10"),
                lambda x: x["entries"][0].update(scoring_eligible=True),
                lambda x: x["entries"][0].update(source_url="https://attack.example/2025"),
                lambda x: x["entries"][1].update(artifact_id=x["entries"][0]["artifact_id"]),
                lambda x: x["entries"][0].update(covered_source_series=["bls.cpi"]),
            ):
                corrupted = copy.deepcopy(self.registry)
                modifier(corrupted)
                tmp = Path(d) / "bad.json"
                tmp.write_text(json.dumps(corrupted), encoding="utf-8")
                with self.assertRaises(ValueError):
                    load_candidates(tmp)

    def test_naive_clock_rejected(self):
        with self.assertRaises(ValueError):
            collect(candidates=self.registry, now=datetime(2026, 11, 23))

    def test_bls_and_bea_artifacts_do_not_verify_full_revision_lineage(self):
        for x in self.registry["entries"]:
            self.assertFalse(x["revision_lineage_complete"])
            self.assertFalse(x["original_bytes_available_at_candidate_time_verified"])


if __name__ == "__main__":
    unittest.main()
