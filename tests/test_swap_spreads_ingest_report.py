"""Tests for V9 daily ingestion audit evidence. No network required."""
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location("sofr_report",ROOT/"scripts"/"report_swap_spread_ingest.py")
report=importlib.util.module_from_spec(spec)
spec.loader.exec_module(report)

def archive():
    return {"schemaVersion":2,"demo":False,"observations":[
        {"asOf":"2026-11-20","tenors":[{"years":i} for i in (2,3,5,7,10,30)]}
    ]}
CLOCK="2026-11-23T00:00:00+00:00"

class IngestReportTests(unittest.TestCase):
    def test_same_date_is_not_mistaken_for_new_market_data(self):
        r=report.summarize(archive(),0,"UNCHANGED 2026-11-20\n",CLOCK,workflow_run="123")
        self.assertEqual(r["ingestionResult"],"no_new_observation")
        self.assertEqual(r["archiveObservations"],1)
        self.assertEqual(r["runId"],"123")
        self.assertEqual(r["ageCalendarDays"],3)
        self.assertFalse(r["rateDataPublishedByThisReport"])
    def test_append_has_distinct_classification(self):
        r=report.summarize(archive(),0,"APPENDED 2026-11-23\n",CLOCK)
        self.assertEqual(r["ingestionResult"],"new_observation")
    def test_failed_data_source_cannot_be_green(self):
        r=report.summarize(archive(),1,"NO UPDATE: No matching official Treasury observation for SOFR date 2026-11-20",CLOCK)
        self.assertEqual(r["ingestionResult"],"date_mismatch")
        self.assertEqual(r["ingestionExitCode"],1)
    def test_revision_is_explicit(self):
        r=report.summarize(archive(),1,"NO UPDATE: Historical observation changed; manual review required",CLOCK)
        self.assertEqual(r["ingestionResult"],"source_revision_conflict")
    def test_missing_tenor_is_not_an_empty_success(self):
        r=report.summarize(archive(),1,"NO UPDATE: Missing mandatory SOFR tenors; retain existing history",CLOCK)
        self.assertEqual(r["ingestionResult"],"incomplete_or_unsupported_tenors")
    def test_unverified_success_not_misclassified(self):
        r=report.summarize(archive(),0,"Something changed",CLOCK)
        self.assertEqual(r["ingestionResult"],"unverified_success")
    def test_old_snapshot_explicitly_stale(self):
        r=report.summarize(archive(),0,"UNCHANGED 2026-11-20\n","2026-12-05T00:00:00Z")
        self.assertTrue(r["stale"])
    def test_duplicate_archived_observations_block_evidence(self):
        a=archive();a["observations"].append(a["observations"][0])
        with self.assertRaisesRegex(ValueError,"Duplicate"):
            report.summarize(a,0,"UNCHANGED 2026-11-20",CLOCK)
    def test_missing_or_invalid_history_rejected(self):
        with self.assertRaisesRegex(ValueError,"Invalid"):
            report.summarize({"schemaVersion":1},0,"",CLOCK)

if __name__=="__main__": unittest.main()
