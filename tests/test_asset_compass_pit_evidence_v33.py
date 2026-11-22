"""V33 synthetic evidence qualification tests: private counts cannot unlock PIT."""
import sqlite3
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from scripts.asset_compass_vintages import create_schema, ingest_macro
from scripts.qualify_asset_compass_pit_v33 import qualify, REQUIRED_SERIES, ROOT


class VintageEvidenceV33Tests(unittest.TestCase):
    NOW="2026-11-22T12:00:00Z"

    def snapshot(self):
        return {"schema_version":1,"generated_at":"2026-11-22T10:00:00Z",
                "bls":{"retrieved_at":"2026-11-22T09:59:59Z"}}

    def row(self, sid="bls.cpi"):
        return {"schema_version":1,"series_id":sid,
                "observation_period":"2026-10",
                "value":320.5,"unit":"index",
                "source_url":"https://api.bls.gov/publicAPI/v1/timeseries/data/",
                "first_seen_at":"2026-11-22T10:00:00Z",
                "official_release_time_known":False,
                "eligible_for_historical_official_vintage":False,
                "provenance":"observed_snapshot_first_seen_not_original_release"}

    def test_empty_archive_no_qualification(self):
        r=qualify([],self.snapshot(),now=self.NOW)
        self.assertEqual(r["required_series"],14)
        self.assertEqual(r["independently_qualified_pit_series"],0)
        self.assertEqual(r["first_seen_covered_series"],0)
        self.assertFalse(r["eligible_for_point_in_time_backtest"])

    def test_first_seen_does_not_certify_release(self):
        r=qualify([self.row()],self.snapshot(),now=self.NOW)
        self.assertEqual(r["first_seen_covered_series"],1)
        self.assertEqual(r["evidence"]["bls.cpi"]["first_seen_distinct_periods"],1)
        self.assertFalse(r["evidence"]["bls.cpi"]["source_original_release_timestamp_verified"])
        self.assertFalse(r["validated_for_live_scoring"])

    def test_full_fourteen_first_seen_not_fourteen_pit(self):
        rows=[]
        for sid in sorted(REQUIRED_SERIES):
            r=self.row(sid)
            if sid.startswith("treasury."):
                r["observation_period"]="2026-11-20"
            elif sid.startswith("fed_h41.") or sid.startswith("liquidity.") or sid.startswith("nyfed."):
                r["observation_period"]="2026-11-19"
            rows.append(r)
        r=qualify(rows,self.snapshot(),now=self.NOW)
        self.assertEqual(r["first_seen_covered_series"],14)
        self.assertEqual(r["independently_qualified_pit_series"],0)
        self.assertFalse(r["eligible_for_point_in_time_backtest"])

    def test_private_vintage_rows_cannot_self_certify(self):
        with tempfile.TemporaryDirectory() as d:
            dbfile=Path(d)/"evidence.sqlite"
            with sqlite3.connect(dbfile) as db:
                create_schema(db)
                ingest_macro(db,[{"series_id":"bls.cpi","source":"synthetic",
                    "frequency":"monthly","units":"index",
                    "observation_date":"2026-10-01",
                    "available_at":"2026-11-10T13:30:00Z",
                    "value":"320.5","source_release_id":"fixture-release",
                    "source_url":"https://example.org/not-independently-reviewed"}])
            r=qualify([self.row()],self.snapshot(),private_db=dbfile,now=self.NOW)
            self.assertEqual(r["private_research_vintage_rows_unverified"],1)
            self.assertEqual(r["independently_qualified_pit_series"],0)
            self.assertEqual(r["evidence"]["bls.cpi"]["private_license_review_status_untrusted"],"pending")
            self.assertFalse(r["evidence"]["bls.cpi"]["redistribution_rights_approved"])

    def test_repository_private_database_not_allowed(self):
        with self.assertRaises(ValueError):
            qualify([],self.snapshot(),private_db=ROOT/"macro"/"leak.sqlite",now=self.NOW)

    def test_invalid_time_rejected(self):
        row=self.row()
        row["first_seen_at"]="2026-11-23T00:00:00Z"
        with self.assertRaises(ValueError):
            qualify([row],self.snapshot(),now=self.NOW)

    def test_false_original_release_claim_rejected(self):
        row=self.row()
        row["official_release_time_known"]=True
        with self.assertRaises(ValueError):
            qualify([row],self.snapshot(),now=self.NOW)

    def test_temporal_anomalies_remain_blockers(self):
        s=self.snapshot()
        s["bls"]["retrieved_at"]="2026-11-22T11:00:00Z"
        r=qualify([self.row()],s,now=self.NOW)
        self.assertIn("snapshot_temporal_integrity_failed",r["blocked_by"])
        self.assertFalse(r["validated_for_live_scoring"])

    def test_all_candidate_archive_urls_are_https(self):
        r=qualify([],self.snapshot(),now=self.NOW)
        self.assertEqual(set(r["evidence"]),REQUIRED_SERIES)
        self.assertTrue(all(v["discovery_url"].startswith("https://")
                            for v in r["evidence"].values()))

    def test_vintage_date_alone_is_not_intraday_release_proof(self):
        r=qualify([],self.snapshot(),now=self.NOW)
        self.assertIn("ALFRED vintage DATE alone",r["official_release_time_resolution"])
        self.assertFalse(r["automatic_investment_alerts_enabled"])


if __name__=="__main__":
    unittest.main()
