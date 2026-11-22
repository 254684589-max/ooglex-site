"""V18 successful-fetch evidence must not impersonate official publication times."""
import json
import tempfile
import unittest
from pathlib import Path
from scripts.collect_treasury_source_evidence_v15 import collect
from scripts.track_treasury_retrievals_v16 import generate
from scripts.record_treasury_public_fetch_v18 import build,persist,read_events

STAMP="2026-11-23T00:00:00Z"
NOM=b"Date,2 Yr,10 Yr\n11/20/2026,4.04,4.45\n"
REAL=b"Date,10 Yr\n11/20/2026,2.04\n"

def evidence(raw_dir):
    raw_dir=Path(raw_dir)
    (raw_dir/"2026-nominal.csv").write_bytes(NOM)
    (raw_dir/"2026-real.csv").write_bytes(REAL)
    def fetch(url):
        return (REAL if "type=daily_treasury_real_yield_curve" in url else NOM),{}
    v15=collect(2026,fetch,STAMP)
    _,v16=generate(v15,raw_dir,None,run_id="10",checked_at="2026-11-23T00:01:00Z")
    return v15,v16

class V18Tests(unittest.TestCase):
    def test_first_witness_is_now_not_observation_or_http_header(self):
        with tempfile.TemporaryDirectory() as tmp:
            v15,v16=evidence(tmp)
            events,r=build(v15,v16,tmp,[],run_id="11",at="2026-11-23T00:02:00Z")
            self.assertEqual(r["first_fetch_events"],2)
            self.assertEqual(len(events),2)
            for event in events:
                self.assertEqual(event["first_ooglex_verified_fetch_at"],"2026-11-23T00:02:00+00:00")
                self.assertIsNone(event["changed_bytes_since_previous_fetch"])
                self.assertFalse(event["official_first_publication_verified"])
                self.assertFalse(event["eligible_for_point_in_time_backtest"])

    def test_second_fetch_retains_first_witness_and_hash_state(self):
        with tempfile.TemporaryDirectory() as tmp:
            v15,v16=evidence(tmp)
            old,r=build(v15,v16,tmp,[],run_id="11",at="2026-11-23T00:02:00Z")
            newer,r2=build(v15,v16,tmp,old,run_id="12",at="2026-11-23T00:03:00Z")
            self.assertEqual(r2["first_fetch_events"],0)
            self.assertEqual(r2["changed_source_files"],0)
            self.assertEqual(newer[0]["first_ooglex_verified_fetch_at"],old[0]["verified_no_later_than"])
            self.assertFalse(newer[0]["changed_bytes_since_previous_fetch"])

    def test_tampered_bytes_and_replayed_run_fail(self):
        with tempfile.TemporaryDirectory() as tmp:
            v15,v16=evidence(tmp)
            old,_=build(v15,v16,tmp,[],run_id="11",at="2026-11-23T00:02:00Z")
            with self.assertRaises(ValueError):
                build(v15,v16,tmp,old,run_id="11",at="2026-11-23T00:03:00Z")
            (Path(tmp)/"2026-nominal.csv").write_bytes(b"tampered")
            with self.assertRaises(ValueError):
                build(v15,v16,tmp,[],run_id="13",at="2026-11-23T00:04:00Z")

    def test_append_only_log_preserved(self):
        with tempfile.TemporaryDirectory() as tmp:
            v15,v16=evidence(tmp)
            events,r=build(v15,v16,tmp,[],run_id="11",at="2026-11-23T00:02:00Z")
            path=Path(tmp)/"events.jsonl"
            summary=Path(tmp)/"summary.json"
            persist(events,r,path,summary)
            original=path.read_bytes()
            self.assertEqual(len(read_events(path)),2)
            with self.assertRaises(ValueError):
                persist(events,r,path,summary)
            self.assertEqual(path.read_bytes(),original)

    def test_clock_cannot_be_backdated(self):
        with tempfile.TemporaryDirectory() as tmp:
            v15,v16=evidence(tmp)
            old,_=build(v15,v16,tmp,[],run_id="11",at="2026-11-23T00:02:00Z")
            with self.assertRaises(ValueError):
                build(v15,v16,tmp,old,run_id="12",at="2026-11-23T00:01:30Z")

if __name__=="__main__":
    unittest.main()
