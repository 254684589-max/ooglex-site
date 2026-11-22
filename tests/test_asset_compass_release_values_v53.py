"""V53 unit tests: no invented raw index values or original PIT certification."""
import hashlib
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

from scripts.capture_asset_compass_official_v51 import load_candidates, capture
from scripts.asset_compass_custody_v52 import capture_and_record, secure_directory
from scripts.asset_compass_release_values_v53 import (
    extract, review, visible, _explicit_employment_revisions,
)

NOW = datetime.now(timezone.utc).replace(microsecond=0)
MONTHS = ("January", "February", "March", "April", "May", "June", "July",
          "August", "September", "October", "November", "December")


def sample(item, *, core_override=None, wrong_month=False, missing=False,
           wrong_revision=False):
    month = MONTHS[int(item["observation_period"][5:]) - 1]
    if wrong_month:
        month = "October"
    year = item["observation_period"][:4]
    if item["release_kind"] == "cpi":
        text = (
            f"CONSUMER PRICE INDEX - {month.upper()} {year}. "
            f"The Consumer Price Index for All Urban Consumers (CPI-U) increased 0.4 percent "
            f"on a seasonally adjusted basis in {month}, after rising 0.3 percent. "
            f"Over the last 12 months, the all items index increased 2.9 percent "
            f"before seasonal adjustment. "
            f"The index for all items less food and energy rose 0.2 percent in {month}, "
            "after increasing 0.3 percent. "
            f"The all items less food and energy index rose {core_override or '3.2'} percent "
            "over the last 12 months.")
        if missing:
            text = text.replace("The all items less food and energy index rose", "The core index rose")
    elif item["release_kind"] == "employment":
        jan = item["observation_period"] == "2025-01"
        amt, rate = ("143,000", "4.0") if jan else ("151,000", "4.1")
        text = (
            f"THE EMPLOYMENT SITUATION -- {month.upper()} {year}. "
            f"Total nonfarm payroll employment rose by {amt} in {month}, "
            f"and the unemployment rate edged down to {rate} percent, "
            "the U.S. Bureau of Labor Statistics reported today. "
            "This news release presents statistics from two monthly surveys.")
        if not jan:
            revision = "-17,000" if wrong_revision else "+125,000"
            text += (
                " The change in total nonfarm payroll employment for December was revised up "
                "by 16,000, from +307,000 to +323,000, and the change for January was "
                f"revised down by 18,000, from +143,000 to {revision}.")
        if missing:
            text = text.replace("the unemployment rate edged down to", "the unemployment rate did something")
    else:
        rate = "2.9" if item["observation_period"] == "2025-08" else "2.8"
        text = (
            f"Personal Income and Outlays, {month} {year}. "
            "These data have been superseded. "
            f"From the preceding month, the PCE price index for {month} increased "
            "0.3 percent. Excluding food and energy, the PCE price index "
            "increased 0.2 percent. "
            f"From the same month one year ago, the PCE price index for {month} "
            "increased 2.8 percent. Excluding food and energy, "
            f"the PCE price index increased {rate} percent from one year ago.")
        if missing:
            text = text.replace("Excluding food and energy", "Including food and energy", 1)
    return ("<!DOCTYPE html><html><head><script>Ignore this " + 
            "secret rate 999.0</script></head><body><p>" + text +
            "</p></body></html>").encode("utf-8")


class FakeResponse:
    def __init__(self, url, body):
        self.url = url
        self.body = body
        self.headers = {"Content-Type": "text/html"}
    def geturl(self):
        return self.url
    def read(self, n):
        return self.body[:n]
    def __enter__(self):
        return self
    def __exit__(self, *args):
        return False


class FakeOpener:
    def __init__(self, item, overrides):
        self.item, self.overrides = item, overrides
    def open(self, request, timeout):
        return FakeResponse(self.item["source_url"], sample(self.item, **self.overrides))


def fetcher(overrides=None):
    overrides = overrides or {}
    def run(item, *, now, private_dir):
        props = overrides.get(item["artifact_id"], {})
        return capture(item, now=now, private_dir=private_dir,
                       opener=FakeOpener(item, props))
    return run


class V53Tests(unittest.TestCase):
    def setUp(self):
        self.t = tempfile.TemporaryDirectory()
        self.addCleanup(self.t.cleanup)
        self.dir = Path(self.t.name) / "private"
        self.items = load_candidates()["entries"]
    def seed(self, overrides=None):
        report = capture_and_record(self.dir, now=NOW, fetcher=fetcher(overrides))
        self.assertEqual(report["failed"], 0)
        return report

    def test_all_seven_files_yield_only_source_reported_candidate_rates(self):
        self.seed()
        r = review(self.dir)
        self.assertEqual(r["status"], "research_candidates_only")
        self.assertEqual(r["distinct_candidate_sources"], 7)
        self.assertEqual(r["complete_candidate_sources"], 7)
        self.assertEqual(r["candidate_metrics_from_latest_snapshots"], 20)
        self.assertEqual(r["historical_pit_series_approved"], 0)
        self.assertFalse(r["first_original_release_bytes_verified"])
        self.assertFalse(r["underlying_index_levels_verified"])
        for release in r["source_results"]:
            self.assertEqual(release["status"], "candidate_complete_unverified")
            for metric in release["reported_metrics"]:
                self.assertFalse(metric["human_reviewed"])
                self.assertFalse(metric["point_in_time_qualified"])
                self.assertEqual(len(metric["passage_sha256"]), 64)
                self.assertNotEqual(metric["statistic"], "index_level")

    def test_actual_meaning_monthly_yoy_and_adjustment_not_blended(self):
        self.seed()
        r = review(self.dir)
        release = next(x for x in r["source_results"] if x["artifact_id"].startswith("bls-cpi-2024"))
        m = {(x["source_series_id"], x["statistic"]): x for x in release["reported_metrics"]}
        self.assertEqual(m[("bls.cpi", "headline_mom_rate")]["value_reported"], "0.4")
        self.assertEqual(m[("bls.cpi", "headline_yoy_rate")]["value_reported"], "2.9")
        self.assertEqual(m[("bls.core_cpi", "headline_mom_rate")]["value_reported"], "0.2")
        self.assertEqual(m[("bls.core_cpi", "headline_yoy_rate")]["value_reported"], "3.2")
        self.assertEqual(m[("bls.cpi", "headline_yoy_rate")]["seasonal_adjustment"], "not_seasonally_adjusted")

    def test_separate_nonfarm_persons_delta_from_unemployment_percent(self):
        self.seed()
        r = review(self.dir)
        release = next(x for x in r["source_results"] if x["artifact_id"] == "bls-empsit-2025-01-release")
        m = {x["source_series_id"]: x for x in release["reported_metrics"]}
        self.assertEqual(m["bls.payroll"]["value_reported"], "143000")
        self.assertEqual(m["bls.payroll"]["unit"], "persons_change_month")
        self.assertEqual(m["bls.unemployment"]["value_reported"], "4.0")
        self.assertEqual(m["bls.unemployment"]["unit"], "percent")

    def test_core_pce_yoy_not_confused_with_mom_or_index_level(self):
        self.seed()
        r = review(self.dir)
        for release in (x for x in r["source_results"] if x["source_family"] == "pio"):
            m = {x["statistic"]: x for x in release["reported_metrics"]}
            self.assertEqual(m["headline_mom_rate"]["value_reported"], "0.2")
            self.assertEqual(m["headline_yoy_rate"]["value_reported"],
                             "2.9" if release["observation_period"] == "2025-08" else "2.8")
            self.assertIn("index_level_unavailable", m["headline_yoy_rate"]["seasonal_adjustment"])

    def test_bls_explicit_revision_is_independent_claim_not_pit_approval(self):
        self.seed()
        r = review(self.dir)
        matches = [x for x in r["cross_release_revision_claims"]
                   if x["target_observation_period"] == "2025-01"]
        self.assertEqual(len(matches), 1)
        claim = matches[0]
        self.assertEqual(claim["source_reported_prior_value"], "143000")
        self.assertEqual(claim["source_reported_revised_value"], "125000")
        self.assertEqual(claim["delta_persons"], "-18000")
        self.assertTrue(claim["prior_value_matches_observed_original"])
        self.assertFalse(claim["historical_revision_chain_complete"])
        self.assertEqual(r["historical_pit_series_approved"], 0)

    def test_second_html_snapshot_changed_value_only_observed_not_certified(self):
        self.seed()
        changed = {"bls-cpi-2024-12-release": {"core_override": "3.3"}}
        self.seed(changed)
        r = review(self.dir)
        diffs = r["observed_byte_change_diffs"]
        self.assertEqual(len(diffs), 1)
        self.assertEqual(diffs[0]["source_series_id"], "bls.core_cpi")
        self.assertEqual(diffs[0]["statistic"], "headline_yoy_rate")
        self.assertEqual(diffs[0]["delta"], "0.1")
        self.assertFalse(diffs[0]["historical_revision_chain_complete"])
        self.assertIn("not_certified_historical_revision", diffs[0]["classification"])

    def test_incomplete_cpi_is_review_required_never_filled_with_future_series(self):
        self.seed({"bls-cpi-2024-12-release": {"missing": True}})
        r = review(self.dir)
        self.assertEqual(r["complete_candidate_sources"], 6)
        self.assertEqual(r["incomplete_candidate_sources"], 1)
        self.assertEqual(r["candidate_metrics_from_latest_snapshots"], 19)
        self.assertEqual(r["historical_pit_series_approved"], 0)

    def test_incomplete_employment_is_review_required(self):
        self.seed({"bls-empsit-2025-02-release": {"missing": True}})
        r = review(self.dir)
        self.assertEqual(r["complete_candidate_sources"], 6)
        self.assertEqual(r["historical_pit_series_approved"], 0)

    def test_incomplete_bea_is_review_required(self):
        self.seed({"bea-pio-2025-09-release": {"missing": True}})
        r = review(self.dir)
        self.assertEqual(r["complete_candidate_sources"], 6)
        self.assertEqual(r["historical_pit_series_approved"], 0)

    def test_would_be_original_report_wrong_month_must_fail(self):
        cpi = self.items[0]
        raw = sample(cpi, wrong_month=True)
        with self.assertRaises(ValueError):
            extract(cpi, raw, hashlib.sha256(raw).hexdigest())

    def test_checksum_mismatch_refuses_any_metrics(self):
        cpi = self.items[0]
        raw = sample(cpi)
        with self.assertRaises(ValueError):
            extract(cpi, raw, "a" * 64)

    def test_tampered_v52_document_fails_before_extraction(self):
        self.seed()
        next(self.dir.glob("*.html")).write_bytes(b"altered")
        with self.assertRaises(ValueError):
            review(self.dir)

    def test_journal_missing_or_zero_records_does_not_generate_historical_values(self):
        secure_directory(self.dir, create=True)
        r = review(self.dir)
        self.assertEqual(r["status"], "no_verified_private_custody")
        self.assertEqual(r["extracted_versions"], 0)
        self.assertEqual(r["historical_pit_series_approved"], 0)

    def test_script_tag_spoof_cannot_override_official_narrative(self):
        item = self.items[0]
        raw = sample(item).replace(b"<script>Ignore", b"<script>Fake rate 99.8. Ignore")
        results = extract(item, raw, hashlib.sha256(raw).hexdigest())
        self.assertEqual(results["extracted_metrics"], 4)
        self.assertEqual(results["reported_metrics"][0]["value_reported"], "0.4")

    def test_invalid_reported_revision_delta_is_rejected(self):
        self.seed({"bls-empsit-2025-02-release": {"wrong_revision": True}})
        r = review(self.dir)
        self.assertFalse(any(x["target_observation_period"] == "2025-01"
                             for x in r["cross_release_revision_claims"]))

    def test_source_metadata_and_revision_linkage_does_not_unlock_asset_scores(self):
        self.seed()
        r = review(self.dir)
        self.assertFalse(r["validated_for_live_scoring"])
        self.assertFalse(r["automatic_investment_alerts_enabled"])
        self.assertFalse(r["source_publisher_publication_instant_verified"])
        self.assertFalse(r["independent_human_review_verified"])
        self.assertFalse(r["full_historical_revision_lineage_verified"])

    def test_no_output_in_public_repo_is_enforced_by_collector(self):
        from scripts.capture_asset_compass_official_v51 import _private_path
        from scripts.archive_asset_compass_observations import ROOT
        with self.assertRaises(ValueError):
            _private_path(ROOT / "data" / "v53-private.json")


if __name__ == "__main__":
    unittest.main()
