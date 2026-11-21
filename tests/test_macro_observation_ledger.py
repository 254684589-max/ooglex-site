import json
import tempfile
import unittest
from pathlib import Path
from scripts.archive_asset_compass_observations import rows_from_snapshot,append_ledger,update

def snapshot():
    return {
        "schema_version":1,
        "observation_date":"2026-11-20",
        "rates":{"us10y":4.92,"us2y":4.63,"real10y":2.77,
                 "breakeven10y":2.15,"spread10y2y":.29},
        "source_urls":[
            "https://home.treasury.gov/api?type=daily_treasury_yield_curve&year=2026",
            "https://home.treasury.gov/api?type=daily_treasury_real_yield_curve&year=2026"],
        "bls":{"series":{
            "cpi":{"period":"2026-10","value":337.476},
            "unemployment":{"period":"2026-10","value":4.1},
            "payroll":{"period":"2026-10","value":158000.0}},
            "source_url":"https://api.bls.gov/publicAPI/v1/timeseries/data/"},
        "nyfed":{"observation_date":"2026-11-19","effr_percent":3.88,
                 "source_url":"https://markets.newyorkfed.org/api/rates/unsecured/effr/last/10.json"}
    }

class SnapshotArchivalTests(unittest.TestCase):
    instant="2026-11-22T01:00:00Z"
    def test_all_observations_are_first_seen_not_official_release(self):
        rows=rows_from_snapshot(snapshot(),self.instant)
        self.assertEqual(len(rows),9)
        self.assertTrue(all(not row["official_release_time_known"] for row in rows))
        self.assertTrue(all(not row["eligible_for_historical_official_vintage"] for row in rows))
        real=next(x for x in rows if x["series_id"]=="treasury.real10y")
        self.assertIn("type=daily_treasury_real_yield_curve",real["source_url"])
    def test_idempotent_reruns(self):
        rows=rows_from_snapshot(snapshot(),self.instant)
        merged,new=append_ledger([],rows)
        self.assertEqual(len(new),9)
        updated,added=append_ledger(merged,rows_from_snapshot(snapshot(),"2026-11-22T03:00:00Z"))
        self.assertEqual(len(updated),9)
        self.assertEqual(added,[])
    def test_revised_value_appends_without_rewriting(self):
        rows=rows_from_snapshot(snapshot(),self.instant)
        changed=snapshot()
        changed["rates"]["us10y"]=4.94
        updated,new=append_ledger(rows,rows_from_snapshot(changed,"2026-11-23T02:00:00Z"))
        self.assertEqual(len(updated),10)
        self.assertEqual(len(new),1)
        self.assertEqual(updated[0]["value"],4.92)
    def test_backdated_run_fails(self):
        rows=rows_from_snapshot(snapshot(),self.instant)
        with self.assertRaisesRegex(ValueError,"backdate"):
            append_ledger(rows,rows_from_snapshot(snapshot(),"2026-11-21T02:00:00Z"))
    def test_ledger_does_not_infer_original_publication_timestamp(self):
        row=rows_from_snapshot(snapshot(),self.instant)[0]
        row["official_release_time_known"]=True
        with self.assertRaisesRegex(ValueError,"unverified"):
            append_ledger([row],[])
    def test_missing_and_future_values_rejected_or_skipped(self):
        snap=snapshot()
        snap["bls"]["series"]["cpi"]["value"]=None
        self.assertEqual(len(rows_from_snapshot(snap,self.instant)),8)
        snap["observation_date"]="2027-11-20"
        with self.assertRaisesRegex(ValueError,"Future"):
            rows_from_snapshot(snap,self.instant)
    def test_atomic_file_updates(self):
        with tempfile.TemporaryDirectory() as d:
            f=Path(d)/"snapshot.json";out=Path(d)/"archive.jsonl"
            f.write_text(json.dumps(snapshot()),encoding="utf-8")
            self.assertEqual(update(f,out,self.instant),(9,9))
            prior=out.read_bytes()
            self.assertEqual(update(f,out,"2026-11-22T02:00:00Z"),(9,0))
            self.assertEqual(out.read_bytes(),prior)
    def test_missing_source_rejected(self):
        item=snapshot()
        item["nyfed"]["source_url"]=""
        with self.assertRaisesRegex(ValueError,"HTTPS"):
            rows_from_snapshot(item,self.instant)

if __name__=="__main__":unittest.main()
