"""V57 append-only first-seen journal tamper and non-PIT accuracy tests."""
import copy
import json
import unittest
from datetime import datetime,timezone,timedelta
from pathlib import Path

from scripts.archive_asset_compass_v57_first_seen import append_evidence,read_rows,digest
from scripts.build_asset_compass_asset_specific_v57 import build,parse_gold,parse_treasury
from tests.test_asset_compass_asset_specific_v57 import gold_raw,treasury_raw,ROOT,NOW


class V57FirstSeenTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cfg=json.loads((ROOT/"macro/model-config.json").read_text())
        v56=json.loads((ROOT/"data/asset-compass-new-sources-v56.json").read_text())
        cls.report=build(parse_gold(gold_raw(),now=NOW),
                         parse_treasury(treasury_raw(),now=NOW),
                         cfg,v56,now=NOW-timedelta(minutes=2),
                         source_hashes={"cftc_gold":"a"*64,"treasury_30y":"b"*64})

    def test_first_real_source_capture_adds_two_records_with_genesis(self):
        s=append_evidence("",self.report,now=NOW)
        records=read_rows(s)
        self.assertEqual(len(records),2)
        self.assertEqual(records[0]["prior_entry_sha256"],"GENESIS")
        self.assertEqual(records[1]["prior_entry_sha256"],records[0]["entry_sha256"])
        self.assertEqual({r["source_id"] for r in records},{"cftc_gold","treasury_30y"})
        self.assertTrue(all(r["historical_pit_qualified"] is False for r in records))
        self.assertTrue(all(r["source_release_timestamp_verified"] is False for r in records))

    def test_idempotent_capture_does_not_duplicate_or_rewrite_first_seen(self):
        first=append_evidence("",self.report,now=NOW)
        again=append_evidence(first,self.report,now=NOW+timedelta(hours=3))
        self.assertEqual(first,again)

    def test_new_observation_appends_without_modifying_old_history(self):
        original=append_evidence("",self.report,now=NOW)
        newer=copy.deepcopy(self.report)
        newer["sources"]["cftc_gold"]["latest_managed_money_net_percent_oi"]+=1
        updated=append_evidence(original,newer,now=NOW+timedelta(hours=4))
        self.assertTrue(updated.startswith(original))
        self.assertEqual(len(read_rows(updated)),3)
        self.assertEqual(read_rows(original)[0],read_rows(updated)[0])

    def test_captured_source_revision_sha_records_new_receipt(self):
        original=append_evidence("",self.report,now=NOW)
        newer=copy.deepcopy(self.report)
        newer["sources"]["treasury_30y"]["source_sha256"]="c"*64
        updated=append_evidence(original,newer,now=NOW+timedelta(hours=2))
        self.assertEqual(len(read_rows(updated)),3)
        self.assertEqual(read_rows(updated)[-1]["source_id"],"treasury_30y")

    def test_tampering_old_public_value_breaks_all_future_hash_integrity(self):
        original=append_evidence("",self.report,now=NOW)
        altered=original.replace("gold", "dust",1)
        with self.assertRaises(ValueError):
            read_rows(altered)
        altered=original.replace('"historical_pit_qualified":false','"historical_pit_qualified":true',1)
        with self.assertRaises(ValueError):
            read_rows(altered)

    def test_utc_clock_is_required(self):
        with self.assertRaises(ValueError):
            append_evidence("",self.report,now=datetime(2026,11,23,10))

    def test_cannot_archive_future_source_report(self):
        with self.assertRaises(ValueError):
            append_evidence("",self.report,now=NOW-timedelta(hours=1))

    def test_forged_model_approval_blocked_before_ledger_mutation(self):
        fake=copy.deepcopy(self.report)
        fake["approved_asset_scores"]=1
        with self.assertRaises(ValueError):
            append_evidence("",fake,now=NOW)

    def test_invalid_hex_digest_cannot_count_as_original_response(self):
        fake=copy.deepcopy(self.report)
        fake["sources"]["cftc_gold"]["source_sha256"]="no digest"
        with self.assertRaises(ValueError):
            append_evidence("",fake,now=NOW)

    def test_ledger_timestamp_must_remain_non_decreasing(self):
        a=append_evidence("",self.report,now=NOW)
        fake=copy.deepcopy(self.report)
        fake["sources"]["treasury_30y"]["latest_bid_to_cover_ratio"]+=0.1
        with self.assertRaisesRegex(ValueError,"moved backward"):
            append_evidence(a,fake,now=NOW-timedelta(minutes=1))

    def test_ledger_no_score_conflation_from_real_observation(self):
        s=append_evidence("",self.report,now=NOW)
        r=read_rows(s)
        self.assertTrue(all(x["model_scoring_qualified"] is False for x in r))
        self.assertEqual(self.report["approved_asset_scores"],0)


if __name__=="__main__":
    unittest.main()
