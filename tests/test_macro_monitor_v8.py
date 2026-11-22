"""Offline regression coverage for V8 monitor."""
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path
from scripts.monitor_asset_compass_v8 import evaluate, publish

NOW = datetime(2026,11,23,2,tzinfo=timezone.utc)
def healthy_inputs():
    snap={"schema_version":1,"generated_at":"2026-11-23T00:00:00Z",
          "status":"partial_data_no_full_score","assets":{"gold":{"score":None}}}
    ready={"report_type":"asset_compass_history_readiness","archived_observations":20,
           "validated_for_live_scoring":False,"eligible_for_point_in_time_backtest":False}
    prov={"report_type":"asset_compass_v7_treasury_provenance",
          "validated_for_live_scoring":False,"legacy_rows_are_valid_evidence":False,
          "integrity_gate_passed":True,"unexpected_mismatch_rows":0,"ledger_sha256":"abcdef"}
    return snap,ready,prov

class MonitorTests(unittest.TestCase):
    def test_healthy_inputs_are_not_model_certification(self):
        r=evaluate(*healthy_inputs(),"abcdef",NOW,run_id="11")
        self.assertEqual(r["operational_status"],"healthy")
        self.assertEqual(r["consecutive_alert_runs"],0)
        self.assertFalse(r["validated_for_live_scoring"])
    def test_stale_report_repeated_runs_escalate(self):
        s,r,p=healthy_inputs();s["generated_at"]="2026-11-19T00:00:00Z"
        first=evaluate(s,r,p,"abcdef",NOW,run_id="11")
        second=evaluate(s,r,p,"abcdef",NOW,first,run_id="12")
        third=evaluate(s,r,p,"abcdef",NOW,second,run_id="13")
        self.assertEqual(third["consecutive_alert_runs"],3)
        self.assertEqual(third["alert_severity"],"critical")
        same=evaluate(s,r,p,"abcdef",NOW,third,run_id="13")
        self.assertEqual(same["consecutive_alert_runs"],3)
    def test_hash_drift_and_unauthorized_score_alert(self):
        s,r,p=healthy_inputs();s["assets"]["gold"]["score"]=80
        result=evaluate(s,r,p,"other",NOW,run_id="1")
        codes={x["code"] for x in result["issues"]}
        self.assertIn("provenance_digest_drift",codes)
        self.assertIn("unguarded_asset_score",codes)
        self.assertEqual(result["alert_severity"],"critical")
    def test_immutable_event_append(self):
        with tempfile.TemporaryDirectory() as directory:
            folder=Path(directory)
            report=evaluate(*healthy_inputs(),"abcdef",NOW,run_id="11")
            output=folder/"latest.json";events=folder/"events.jsonl"
            publish(report,output,events)
            original=events.read_bytes()
            publish(report,output,events)
            self.assertEqual(events.read_bytes(),original)
            altered=dict(report,operational_status="alert")
            with self.assertRaises(ValueError):publish(altered,output,events)
    def test_missing_sources_fail_closed(self):
        r=evaluate(None,None,None,None,NOW,run_id="1")
        self.assertEqual(r["operational_status"],"alert")

if __name__=="__main__":unittest.main()
