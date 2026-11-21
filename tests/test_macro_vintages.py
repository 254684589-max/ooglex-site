import sqlite3
import unittest
from datetime import date,timedelta
from scripts.asset_compass_vintages import create_schema,ingest_macro,ingest_factors,asof_macro,asof_factors
from scripts.asset_compass_walkforward import walkforward,nonoverlap

def macro(value=4.0,available="2025-01-10T15:00:00Z",release="release-1"):
    return {"series_id":"US10Y","source":"US Treasury","frequency":"daily","units":"percent",
      "observation_date":"2025-01-09","available_at":available,
      "value":str(value),"source_release_id":release,
      "source_url":"https://home.treasury.gov/"}

def factor(value=.5,available="2025-01-10T15:00:00Z"):
    return {"asset_id":"gold","factor_group":"rates","observation_date":"2025-01-09",
      "available_at":available,"factor_signal":str(value),"model_version":"v1",
      "source_refs_json":'["US10Y:release-1"]'}

class VintageStoreTests(unittest.TestCase):
    def setUp(self):
        self.db=sqlite3.connect(":memory:")
        create_schema(self.db)
    def tearDown(self):self.db.close()
    def test_release_is_invisible_before_publication(self):
        self.assertEqual(ingest_macro(self.db,[macro()]),1)
        self.assertIsNone(asof_macro(self.db,"US10Y","2025-01-10T14:59:59Z"))
        self.assertEqual(asof_macro(self.db,"US10Y","2025-01-10T15:00:00Z")["value"],4.0)
    def test_revision_does_not_rewrite_history(self):
        ingest_macro(self.db,[macro(),macro(4.1,"2025-01-15T15:00:00Z","release-2")])
        self.assertEqual(asof_macro(self.db,"US10Y","2025-01-12T00:00:00Z")["value"],4.0)
        self.assertEqual(asof_macro(self.db,"US10Y","2025-01-16T00:00:00Z")["value"],4.1)
    def test_immutable_revision_conflict_refused(self):
        ingest_macro(self.db,[macro()])
        with self.assertRaisesRegex(ValueError,"Conflicting"):
            ingest_macro(self.db,[macro(9.0)])
    def test_import_is_idempotent(self):
        self.assertEqual(ingest_macro(self.db,[macro()]),1)
        self.assertEqual(ingest_macro(self.db,[macro()]),0)
    def test_timestamp_must_have_timezone(self):
        with self.assertRaisesRegex(ValueError,"timezone"):
            ingest_macro(self.db,[macro(available="2025-01-10T15:00:00")])
    def test_release_must_not_predate_observation(self):
        with self.assertRaisesRegex(ValueError,"precedes"):
            ingest_macro(self.db,[macro(available="2025-01-08T15:00:00Z")])
    def test_missing_source_ref_fails(self):
        with self.assertRaisesRegex(ValueError,"source"):
            ingest_factors(self.db,[{**factor(),"source_refs_json":"[]"}])
    def test_factor_release_asof(self):
        self.assertEqual(ingest_factors(self.db,[factor()]),1)
        self.assertEqual(asof_factors(self.db,"gold","2025-01-10T14:00:00Z","v1"),{})
        self.assertEqual(asof_factors(self.db,"gold","2025-01-11T00:00:00Z","v1")["rates"]["signal"],.5)
    def test_factor_out_of_range_refused(self):
        with self.assertRaisesRegex(ValueError,"outside"):
            ingest_factors(self.db,[factor(1.5)])
    def test_validation_table_cannot_mark_approved(self):
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute("INSERT INTO model_validation_runs(run_id,model_version,diagnostics_json,approved_for_public_scoring) VALUES('x','v1','{}',1)")

def examples(n=270):
    day=date(2025,1,1)
    rows=[]
    for i in range(n):
        entry=(day+timedelta(days=i)).isoformat()
        exit_at=(day+timedelta(days=i+21)).isoformat()
        rows.append({"asset":"gold","entry_date":entry,"exit_date":exit_at,
                     "signal":1 if i%2 else -1,"forward_return":.01 if i%2 else -.01})
    return rows

class WalkForwardTests(unittest.TestCase):
    def test_insufficient_history(self):
        r=walkforward(examples(30))
        self.assertEqual(r["results"]["gold"]["status"],"insufficient_history")
        self.assertFalse(r["validated_for_live_scoring"])
    def test_purge_and_research_gating(self):
        report=walkforward(examples(),min_train=126,test_window=63,step=63)
        self.assertFalse(report["validated_for_live_scoring"])
        self.assertGreater(report["results"]["gold"]["fold_count"],0)
        for fold in report["results"]["gold"]["folds"]:
            self.assertLess(fold["training_last_label_exit"],fold["test_first_entry"])
            self.assertGreaterEqual(fold["independent_test_count"],3)
    def test_nonoverlap(self):
        rows=examples(60)
        selected=nonoverlap(rows)
        self.assertTrue(all(a["exit_date"]<b["entry_date"] for a,b in zip(selected,selected[1:])))
    def test_invalid_settings(self):
        with self.assertRaises(ValueError):walkforward(examples(),step=0)

if __name__=="__main__":unittest.main()
