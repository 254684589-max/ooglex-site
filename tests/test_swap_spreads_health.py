"""Offline V10 heartbeat contract: only successful verified runs can update public status."""
import importlib.util
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location("heartbeat",ROOT/"scripts"/"publish_swap_spread_health.py")
mod=importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

def evidence(**changes):
    data={"reportedAt":"2026-11-23T01:05:00Z","ingestionResult":"no_new_observation",
          "ingestionExitCode":0,"rateDataPublishedByThisReport":False,
          "lastArchivedObservationDate":"2026-11-20","archiveObservations":1,"runId":"123456"}
    data.update(changes)
    return data

class HeartbeatTests(unittest.TestCase):
    def test_no_new_day_success_preserves_actual_market_date(self):
        got=mod.build(evidence())
        self.assertEqual(got["lastDataAsOf"],"2026-11-20")
        self.assertEqual(got["lastSuccessAt"],"2026-11-23T01:05:00Z")
        self.assertEqual(got["runResult"],"no_new_observation")
        self.assertEqual(got["observations"],1)
        self.assertEqual(got["runId"],"123456")
    def test_verified_append_allowed(self):
        got=mod.build(evidence(ingestionResult="new_observation",lastArchivedObservationDate="2026-11-23",archiveObservations=2))
        self.assertEqual(got["runResult"],"new_observation")
    def test_failed_and_ambiguous_results_rejected(self):
        for status in ["source_revision_conflict","date_mismatch","ingestion_error",
                       "source_behind_archive","unverified_success"]:
            with self.subTest(status=status),self.assertRaises(ValueError):
                mod.build(evidence(ingestionResult=status))
        with self.assertRaises(ValueError):
            mod.build(evidence(ingestionExitCode=1))
    def test_invalid_evidence_rejected(self):
        with self.assertRaises(ValueError):
            mod.build(evidence(rateDataPublishedByThisReport=True))
        with self.assertRaises(ValueError):
            mod.build(evidence(archiveObservations=0))
        with self.assertRaises(ValueError):
            mod.build(evidence(lastArchivedObservationDate=None))
        with self.assertRaises(ValueError):
            mod.build(evidence(reportedAt="2026-11-23T00:00:00"))
    def test_status_is_not_a_market_price(self):
        got=mod.build(evidence())
        self.assertFalse(any(key in got for key in ("swap","treasury","spreadBp","tenors")))
        self.assertIn("not",got["note"].lower())

if __name__=="__main__":unittest.main()
