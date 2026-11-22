"""V12 watchdog: only real scheduled main-branch GitHub runs qualify."""
import importlib.util
from datetime import datetime, timezone
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location("sofr_watchdog",ROOT/"scripts"/"watch_sofr_schedule.py")
watch=importlib.util.module_from_spec(spec)
spec.loader.exec_module(watch)

NOW=datetime(2026,11,24,7,35,tzinfo=timezone.utc)
def history():
    return {"schemaVersion":2,"demo":False,"observations":[{"asOf":"2026-11-20","tenors":[]}]}
def run(**kw):
    r={"id":1234,"name":watch.WORKFLOW_NAME,"head_branch":"main",
       "event":"schedule","created_at":"2026-11-24T03:40:00Z","status":"completed",
       "conclusion":"success","html_url":"https://github.com/example/actions/runs/1234"}
    r.update(kw);return r
def marker(**kw):
    m={"schemaVersion":1,"type":"sofr-last-successful-ingestion","status":"successful",
       "runId":"1234","lastSuccessAt":"2026-11-24T03:42:00Z",
       "lastDataAsOf":"2026-11-20","observations":1}
    m.update(kw);return m

class WatchdogTests(unittest.TestCase):
    def test_scheduled_run_with_matching_heartbeat(self):
        got=watch.check([run()],history(),marker(),NOW)
        self.assertEqual(got["status"],"verified_scheduled_success")
        self.assertEqual(got["dataDateAgeDays"],4)
        self.assertFalse(got["writesMarketData"])
    def test_pr_or_probe_success_cannot_count(self):
        for r in [run(event="pull_request"),run(name="SOFR V8 live pipeline verification"),
                  run(head_branch="feature"),run(created_at="2026-11-23T03:40:00Z")]:
            self.assertEqual(watch.check([r],history(),marker(),NOW)["status"],"missing_scheduled_run")
    def test_no_run_is_not_success(self):
        self.assertEqual(watch.check([],history(),None,NOW)["status"],"missing_scheduled_run")
    def test_failed_or_incomplete_runs(self):
        self.assertEqual(watch.check([run(conclusion="failure")],history(),marker(),NOW)["status"],"run_failed")
        self.assertEqual(watch.check([run(status="in_progress",conclusion=None)],history(),marker(),NOW)["status"],"run_not_complete")
    def test_missing_old_or_wrong_heartbeat(self):
        self.assertEqual(watch.check([run()],history(),None,NOW)["status"],"success_missing_heartbeat")
        self.assertEqual(watch.check([run()],history(),marker(runId="999"),NOW)["status"],"heartbeat_mismatch")
        self.assertEqual(watch.check([run()],history(),marker(lastSuccessAt="2026-11-23T03:42:00Z"),NOW)["status"],"heartbeat_mismatch")
        self.assertEqual(watch.check([run()],history(),marker(lastDataAsOf="2026-11-19"),NOW)["status"],"archive_heartbeat_mismatch")
    def test_before_window_and_weekend_do_not_raise_false_alarm(self):
        monday=datetime(2026,11,23,7,35,tzinfo=timezone.utc)
        self.assertEqual(watch.check([],history(),None,monday)["status"],"not_scheduled_today")
        early=datetime(2026,11,24,3,0,tzinfo=timezone.utc)
        self.assertEqual(watch.check([],history(),None,early)["status"],"before_schedule_window")
    def test_manual_run_is_not_accepted_as_schedule(self):
        r=run(event="workflow_dispatch")
        self.assertEqual(watch.check([r],history(),marker(),NOW)["status"],"missing_scheduled_run")
        self.assertEqual(watch.check([r],history(),marker(),NOW,expect_dispatch=True)["status"],"verified_manual_success")
    def test_multiple_runs_latest_required(self):
        r=run(id=2345,created_at="2026-11-24T04:20:00Z",conclusion="failure")
        self.assertEqual(watch.check([run(),r],history(),marker(),NOW)["status"],"run_failed")
    def test_duplicates_block_approval(self):
        h=history();h["observations"].append(h["observations"][0])
        with self.assertRaisesRegex(ValueError,"Duplicate"):
            watch.check([run()],h,marker(),NOW)

if __name__=="__main__":unittest.main()
