"""V16 real-retrieval comparison regressions: no fabricated revision/PIT claims."""
import json
import tempfile
import unittest
from pathlib import Path
from scripts.track_treasury_retrievals_v16 import generate,persist
from scripts.collect_treasury_source_evidence_v15 import collect
NOM=b"Date,2 Yr,10 Yr\n11/19/2026,4.01,4.42\n11/20/2026,4.04,4.45\n"
REAL=b"Date,10 Yr\n11/19/2026,2.02\n11/20/2026,2.04\n"
STAMP="2026-11-23T00:00:00Z"

def fixture(folder,nom=NOM,real=REAL):
    import hashlib
    folder=Path(folder)
    (folder/"2026-nominal.csv").write_bytes(nom)
    (folder/"2026-real.csv").write_bytes(real)
    def fetch(url):
        return (real if "type=daily_treasury_real_yield_curve" in url else nom),{}
    return collect(2026,fetch,STAMP)

class V16Tests(unittest.TestCase):
    def test_initial_baseline_is_not_fake_revision(self):
        with tempfile.TemporaryDirectory() as tmp:
            report=fixture(tmp)
            state,result=generate(report,tmp,None,run_id="1",checked_at=STAMP)
            self.assertEqual(result["baseline_state"],"first_capture")
            self.assertEqual(result["total_observed_value_changes"],0)
            self.assertFalse(result["historical_official_revisions_verified"])
            self.assertFalse(result["eligible_for_point_in_time_backtest"])
            self.assertEqual(len(state["fingerprints"]["treasury.us10y"]),2)
    def test_detect_real_value_changes_new_date_and_removed_date(self):
        with tempfile.TemporaryDirectory() as tmp:
            source=fixture(tmp)
            state,_=generate(source,tmp,None,run_id="1",checked_at=STAMP)
            new_nom=b"Date,2 Yr,10 Yr\n11/20/2026,4.04,4.55\n11/23/2026,4.05,4.53\n"
            new_real=b"Date,10 Yr\n11/20/2026,2.04\n11/23/2026,2.06\n"
            changed=fixture(tmp,new_nom,new_real)
            next_state,r=generate(changed,tmp,state,run_id="2",checked_at="2026-11-23T01:00:00Z")
            self.assertEqual(r["by_series"]["treasury.us10y"]["changed_value_periods"],1)
            self.assertEqual(r["by_series"]["treasury.us10y"]["new_observation_periods"],1)
            self.assertEqual(r["by_series"]["treasury.us10y"]["no_longer_in_response_periods"],1)
            self.assertEqual(r["total_observed_value_changes"],1)
            self.assertFalse(r["historical_official_revisions_verified"])
    def test_preserve_append_only_event_and_reject_duplicate_run(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); source=fixture(tmp)
            state,report=generate(source,tmp,None,run_id="11",checked_at=STAMP)
            persist(state,report,state_path=root/"state.json",events_path=root/"events.jsonl",report_path=root/"report.json")
            original=(root/"events.jsonl").read_bytes()
            with self.assertRaises(ValueError):
                persist(state,report,state_path=root/"state.json",events_path=root/"events.jsonl",report_path=root/"report.json")
            self.assertEqual((root/"events.jsonl").read_bytes(),original)
    def test_raw_hash_mismatch_blocks(self):
        with tempfile.TemporaryDirectory() as tmp:
            source=fixture(tmp)
            (Path(tmp)/"2026-nominal.csv").write_bytes(b"tampered")
            with self.assertRaises(ValueError):
                generate(source,tmp,None,run_id="1",checked_at=STAMP)
    def test_duplicate_run_and_backdating_blocked(self):
        with tempfile.TemporaryDirectory() as tmp:
            source=fixture(tmp)
            state,_=generate(source,tmp,None,run_id="1",checked_at=STAMP)
            with self.assertRaises(ValueError):
                generate(source,tmp,state,run_id="1",checked_at=STAMP)
            with self.assertRaises(ValueError):
                generate(source,tmp,state,run_id="2",checked_at="2026-11-22T23:59:59Z")
if __name__=="__main__":unittest.main()
