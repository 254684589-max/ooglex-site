"""V59 source-verification and fail-closed score contract.

All generated source observations in these tests are deliberately TEST FIXTURES,
not production values and are never committed to data/ outputs.
"""
import copy
import csv
import hashlib
import io
import json
import unittest
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from scripts.build_asset_compass_sources_v59 import (
    FRED_ID, CHAIN_URL, V58_FILE, SOURCE_BTC, SOURCE_EQUITIES, _get,
    build_equities, build_evidence, fetch_bitcoin, parse_block,
    parse_equities_csv, subsidy_total_sats,
)

NOW = datetime(2026, 11, 24, 0, 0, tzinfo=timezone.utc)


def equity_fixture_csv():
    out = io.StringIO()
    writer = csv.writer(out)
    writer.writerow(["observation_date", FRED_ID])
    for i in range(104):
        year = 2000 + i // 4
        month = (i % 4) * 3 + 1
        writer.writerow([f"{year}-{month:02d}-01", 30_000_000 + 600_000 * i])
    return out.getvalue().encode()


def equity_fixture():
    raw = equity_fixture_csv()
    return build_equities(parse_equities_csv(raw), raw_sha=hashlib.sha256(raw).hexdigest(), now=NOW)


class FakeResponse:
    def __init__(self, url, content):
        self.url, self.content = url, content
    def __enter__(self):
        return self
    def __exit__(self, *args):
        return False
    def geturl(self):
        return self.url
    def read(self, n=-1):
        return self.content[:n]


def bitcoin_fixture():
    tip_h = 950_000
    tip_hash = "a" * 64
    older_hash = "b" * 64
    tip_ts = int((NOW - timedelta(hours=2)).timestamp())
    older_ts = int((NOW - timedelta(days=7)).timestamp())
    bodies = {
        f"{CHAIN_URL}/blocks/tip/height": str(tip_h).encode(),
        f"{CHAIN_URL}/block-height/{tip_h}": tip_hash.encode(),
        f"{CHAIN_URL}/block/{tip_hash}": json.dumps({"id": tip_hash, "height": tip_h,
                                                   "timestamp": tip_ts}).encode(),
        f"{CHAIN_URL}/block-height/{tip_h-1008}": older_hash.encode(),
        f"{CHAIN_URL}/block/{older_hash}": json.dumps({"id": older_hash, "height": tip_h-1008,
                                                       "timestamp": older_ts}).encode(),
    }
    def opener(request, timeout=25):
        return FakeResponse(request.full_url, bodies[request.full_url])
    return fetch_bitcoin(opener=opener, now=NOW)


class V59SourceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.v58 = json.loads(V58_FILE.read_text())

    def test_z1_parser_real_series_header_and_quarter(self):
        rows = parse_equities_csv(equity_fixture_csv())
        self.assertEqual(len(rows), 104)
        self.assertEqual(rows[-1]["quarter"], "2025-Q4")
        self.assertEqual(rows[-1]["market_value_millions_usd"], 91_800_000)

    def test_z1_changes_are_not_total_return(self):
        report = equity_fixture()
        self.assertEqual(report["source_id"], SOURCE_EQUITIES)
        self.assertEqual(report["units"], "millions_usd")
        self.assertEqual(report["latest_market_value_trillions_usd"], 91.8)
        self.assertIsNone(report["official_asset_score"])
        self.assertFalse(report["investable_total_return_verified"])
        self.assertFalse(report["historical_first_publication_vintages_verified"])
        self.assertFalse(report["redistribution_rights_instrument_by_instrument_certified"])

    def test_z1_rejects_foreign_series_and_duplicate(self):
        raw = equity_fixture_csv().replace(FRED_ID.encode(), b"SP500")
        with self.assertRaisesRegex(ValueError, "identifier"):
            parse_equities_csv(raw)
        bad = equity_fixture_csv() + b"2025-10-01,90000000\n"
        with self.assertRaisesRegex(ValueError, "duplicate|ascending"):
            parse_equities_csv(bad)

    def test_z1_rejects_short_history_and_nonfinite(self):
        raw = equity_fixture_csv()
        with self.assertRaisesRegex(ValueError, "Insufficient"):
            parse_equities_csv(b"\n".join(raw.splitlines()[:10]) + b"\n")
        with self.assertRaisesRegex(ValueError, "Invalid"):
            parse_equities_csv(raw.replace(b"30000000", b"nan", 1))
        with self.assertRaisesRegex(ValueError, "Invalid"):
            parse_equities_csv(raw.replace(b"30000000", b"-9999", 1))

    def test_z1_future_and_missing_digest(self):
        raw = equity_fixture_csv()
        rows = parse_equities_csv(raw)
        with self.assertRaisesRegex(ValueError, "Future"):
            build_equities(rows, raw_sha="c" * 64,
                           now=datetime(2020, 1, 1, tzinfo=timezone.utc))
        with self.assertRaisesRegex(ValueError, "SHA256"):
            build_equities(rows, raw_sha="", now=NOW)

    def test_bitcoin_halving_consensus_boundaries(self):
        self.assertEqual(subsidy_total_sats(209_999), 10_500_000 * 10**8)
        self.assertEqual(subsidy_total_sats(210_000), 10_500_025 * 10**8)
        self.assertEqual(subsidy_total_sats(839_999), 19_687_500 * 10**8)
        self.assertEqual(subsidy_total_sats(840_000), 19_687_500 * 10**8 + 312_500_000)
        self.assertLess(subsidy_total_sats(10_000_000), 21_000_000 * 10**8)

    def test_bitcoin_strict_height_numeric(self):
        for invalid in (-1, 0.0, "900000", None, True, 100_000_001):
            with self.assertRaises(ValueError):
                subsidy_total_sats(invalid)

    def test_bitcoin_tip_and_historical_checkpoint_from_real_api_schema(self):
        r = bitcoin_fixture()
        self.assertEqual(r["source_id"], SOURCE_BTC)
        self.assertEqual(r["observed_tip"]["height"], 950_000)
        self.assertEqual(r["historical_checkpoint"]["height"], 948_992)
        self.assertEqual(r["nominal_subsidy_to_tip_sats"], subsidy_total_sats(950_000))
        self.assertTrue(r["fresh_for_research"])
        self.assertIsNone(r["official_asset_score"])
        self.assertFalse(r["independent_node_cross_checked"])

    def test_bitcoin_bad_header_identity_rejected(self):
        body = json.dumps({"id": "a"*64, "height": 950_000,
                           "timestamp": int(NOW.timestamp())}).encode()
        with self.assertRaisesRegex(ValueError, "hash mismatch"):
            parse_block(body, expected_hash="b"*64)
        with self.assertRaisesRegex(ValueError, "height mismatch"):
            parse_block(body, expected_height=949_999)
        with self.assertRaisesRegex(ValueError, "Invalid"):
            parse_block(json.dumps({"id":"a"*64,"height":950_000,
                "timestamp": "2026"}).encode())

    def test_https_origin_redirect_rejected(self):
        def opener(request, timeout=25):
            return FakeResponse("https://attacker.invalid/blocks/tip/height", b"900000")
        with self.assertRaisesRegex(ValueError, "redirect"):
            _get(f"{CHAIN_URL}/blocks/tip/height", host="blockstream.info",
                 opener=opener)

    def test_6_of_6_is_only_research(self):
        v = build_evidence(self.v58, equity_fixture(), bitcoin_fixture(), now=NOW)
        self.assertEqual(v["asset_specific_observed_count"], 6)
        self.assertEqual(v["asset_specific_missing_count"], 0)
        self.assertEqual(v["asset_specific_missing_assets"], [])
        self.assertEqual(v["research_assets"]["us_equities"]["source_ids"], [SOURCE_EQUITIES])
        self.assertEqual(v["research_assets"]["bitcoin"]["source_ids"], [SOURCE_BTC])
        self.assertEqual(v["official_0_to_100_scores_published"], 0)
        self.assertEqual(v["audited_asset_total_return_count"], 0)
        self.assertEqual(v["oos_validated_assets"], 0)
        for row in v["research_assets"].values():
            self.assertIsNone(row["official_score"])
            self.assertFalse(row["point_in_time_provenance_verified"])
            self.assertFalse(row["investable_total_return_verified"])

    def test_only_one_observed_is_5_of_6(self):
        v = build_evidence(self.v58, equity_fixture(), None, now=NOW)
        self.assertEqual(v["asset_specific_observed_count"], 5)
        self.assertEqual(v["asset_specific_missing_assets"], ["bitcoin"])
        self.assertEqual(v["source_verification"]["bitcoin"]["reason"], "capture_absent")

    def test_both_absent_preserve_v58_4_of_6(self):
        v = build_evidence(self.v58, None, None, now=NOW)
        self.assertEqual(v["asset_specific_observed_count"], 4)
        self.assertEqual(set(v["asset_specific_missing_assets"]), {"us_equities","bitcoin"})

    def test_unverified_bitcoin_supply_does_not_promote(self):
        btc = bitcoin_fixture()
        btc["nominal_subsidy_to_tip_sats"] += 1
        v = build_evidence(self.v58, equity_fixture(), btc, now=NOW)
        self.assertEqual(v["asset_specific_observed_count"], 5)
        self.assertEqual(v["source_verification"]["bitcoin"]["reason"], "bitcoin_chain_proof_unverified")

    def test_forged_score_or_pit_data_not_promoted(self):
        eq = equity_fixture()
        eq["official_asset_score"] = 80
        v = build_evidence(self.v58, eq, bitcoin_fixture(), now=NOW)
        self.assertEqual(v["asset_specific_observed_count"], 5)
        self.assertEqual(v["source_verification"]["us_equities"]["reason"], "source_false_qualification")
        bt = bitcoin_fixture()
        bt["historical_first_publication_vintages_verified"] = True
        v = build_evidence(self.v58, equity_fixture(), bt, now=NOW)
        self.assertEqual(v["asset_specific_observed_count"], 5)

    def test_stale_provenance_is_not_current_observation(self):
        eq = equity_fixture()
        eq["generated_at"] = "2026-01-01T00:00:00+00:00"
        v = build_evidence(self.v58, eq, None, now=NOW)
        self.assertEqual(v["source_verification"]["us_equities"]["reason"], "capture_age_invalid")

    def test_modified_v58_parent_cannot_unlock(self):
        old = copy.deepcopy(self.v58)
        old["research_assets"]["gold"]["official_score"] = 82
        with self.assertRaisesRegex(ValueError, "V58"):
            build_evidence(old, equity_fixture(), bitcoin_fixture(), now=NOW)


if __name__ == "__main__":
    unittest.main()
