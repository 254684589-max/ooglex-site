"""V61 first-release evidence contract. All examples are TEST FIXTURES."""
import copy
import json
import unittest
from datetime import datetime, timezone
from scripts.audit_asset_compass_pit_release_v61 import (
    V50, V59, V60, candidate_bundle, asof_candidate_timeline, readiness,
)

NOW = datetime(2026, 11, 24, 2, tzinfo=timezone.utc)


def release(ts, release_id, value=3.1):
    return {"official_publication_at": ts,
            "source_release_id": release_id,
            "original_bytes_sha256": ("a" if release_id == "original" else "b") * 64,
            "source_url": "https://www.bls.gov/news.release/archives/cpi_01012025.htm",
            "numeric_value": value,
            "original_source_format": "archived_html",
            "units": "percent"}


class V61Tests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.v50=json.loads(V50.read_text(encoding="utf-8"))
        cls.v59=json.loads(V59.read_text(encoding="utf-8"))
        cls.v60=json.loads(V60.read_text(encoding="utf-8"))

    def test_real_v50_registry_14_no_false_certification(self):
        r=readiness(self.v50,self.v59,self.v60,now=NOW)
        self.assertEqual(r["required_macro_series"],14)
        self.assertEqual(len(r["series"]),14)
        self.assertEqual(r["registered_release_reference_series"],14)
        self.assertEqual(r["independently_certified_original_release_series"],0)
        self.assertEqual(r["independently_verified_revision_chains"],0)
        self.assertEqual(r["investable_total_return_certified_assets"],0)
        self.assertEqual(r["oos_validated_assets"],0)
        self.assertEqual(r["official_0_to_100_scores_published"],0)
        self.assertFalse(r["eligible_for_historical_pit_backtest"])
        for v in r["series"].values():
            self.assertFalse(v["available_for_pit_backtest"])

    def test_candidate_first_release_and_later_revision_do_not_self_approve(self):
        b=candidate_bundle("bls.cpi","2025-01-01",[
            release("2025-02-12T08:30:00-05:00","original",3.1),
            release("2025-03-12T08:30:00-04:00","revised",3.2)])
        self.assertEqual(b["release_candidate_count"],2)
        self.assertFalse(b["eligible_for_pit_backtest"])
        self.assertFalse(b["original_publication_timestamp_independently_verified"])
        self.assertFalse(b["historical_data_license_approved"])
        early=asof_candidate_timeline(b,"2025-02-12T13:29:59Z")
        first=asof_candidate_timeline(b,"2025-02-12T13:30:00Z")
        late=asof_candidate_timeline(b,"2025-03-12T12:30:00Z")
        self.assertIsNone(early["selected_candidate_release_id"])
        self.assertEqual(first["selected_candidate_release_id"],"original")
        self.assertEqual(late["selected_candidate_release_id"],"revised")
        self.assertFalse(late["historically_tradeable_verified"])

    def test_first_seen_only_cannot_be_a_release(self):
        x=release("2025-02-12T08:30:00-05:00","original")
        del x["official_publication_at"]
        x["first_seen_at"]="2025-02-12T13:30:00Z"
        with self.assertRaisesRegex(ValueError,"Original release"):
            candidate_bundle("bls.cpi","2025-01-01",[x])

    def test_naive_or_future_release_time_rejected(self):
        for ts in ("2025-02-12T08:30:00","2099-01-01T08:30:00Z"):
            with self.assertRaises(ValueError):
                candidate_bundle("bls.cpi","2025-01-01",[release(ts,"original")])

    def test_revision_earlier_than_first_release_or_duplicate(self):
        orig=release("2025-02-12T13:30:00Z","original")
        with self.assertRaisesRegex(ValueError,"Out-of-order"):
            candidate_bundle("bls.cpi","2025-01-01",[
                orig,release("2025-02-11T13:30:00Z","revised")])
        with self.assertRaisesRegex(ValueError,"Out-of-order"):
            candidate_bundle("bls.cpi","2025-01-01",[orig,orig])

    def test_missing_publisher_hash_or_unsafe_url_rejected(self):
        orig=release("2025-02-12T13:30:00Z","original")
        for name,bad in (("original_bytes_sha256","x"),
                         ("source_url","http://bad.com"),
                         ("numeric_value",float("nan"))):
            rec=dict(orig);rec[name]=bad
            with self.assertRaises(ValueError):
                candidate_bundle("bls.cpi","2025-01-01",[rec])

    def test_cannot_claim_release_prior_to_observation(self):
        with self.assertRaisesRegex(ValueError,"earlier"):
            candidate_bundle("bls.cpi","2025-01-01",[
                release("2024-12-31T23:00:00Z","original")])

    def test_v50_fake_pit_qualified_rejected(self):
        v50=copy.deepcopy(self.v50)
        v50["entries"][0]["point_in_time_qualified"]=True
        with self.assertRaises(ValueError):
            readiness(v50,self.v59,self.v60,now=NOW)

    def test_v50_fake_archives_not_implicitly_authorized(self):
        v50=copy.deepcopy(self.v50)
        v50["entries"][0]["first_publication_records"]=[{"unverified":"fake"}]
        with self.assertRaisesRegex(ValueError,"independent review"):
            readiness(v50,self.v59,self.v60,now=NOW)

    def test_no_backtest_if_v60_return_report_forged(self):
        v60=copy.deepcopy(self.v60)
        v60["audited_asset_total_return_count"]=6
        with self.assertRaises(ValueError):
            readiness(self.v50,self.v59,v60,now=NOW)

    def test_missing_or_duplicate_evidence_series_refused(self):
        v50=copy.deepcopy(self.v50)
        v50["entries"].append(copy.deepcopy(v50["entries"][0]))
        with self.assertRaises(ValueError):
            readiness(v50,self.v59,self.v60,now=NOW)
        v50=copy.deepcopy(self.v50)
        v50["entries"].pop()
        with self.assertRaises(ValueError):
            readiness(v50,self.v59,self.v60,now=NOW)


if __name__=="__main__":
    unittest.main()
