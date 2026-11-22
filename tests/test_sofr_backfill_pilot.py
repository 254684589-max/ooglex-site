"""Offline controls for non-publishing SOFR historical backfill pilot."""
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"scripts"))
spec=importlib.util.spec_from_file_location("sofr_pilot",ROOT/"scripts"/"audit_sofr_backfill_pilot.py")
pilot=importlib.util.module_from_spec(spec)
spec.loader.exec_module(pilot)

def full():
    return {"generatedAt":"2026-11-23T00:00:00Z",
            "requestedDates":3,"latestArchivedDate":"2026-11-20",
            "results":[
                {"asOf":"2026-03-20","status":"candidate","verifiedTenorCount":6,
                 "methodCounts":{"close":5,"close-thin":1},
                 "unpublishedObservation":{"tenors":[{"swap":4.5,"treasury":4.7,"spreadBp":-20}]},
                 "provenance":{"oisSha256":"a"*64,"treasurySha256":"b"*64}},
                {"asOf":"2026-04-15","status":"no_archive","reason":"HTTP 404"},
                {"asOf":"2026-11-20","status":"archive_conflict",
                 "unpublishedObservation":{"tenors":[{"swap":9}]},
                 "provenance":{"oisSha256":"c"*64,"treasurySha256":"d"*64}}
            ]}

class PilotTests(unittest.TestCase):
    def test_summaries_never_contain_rates(self):
        result=pilot.summarize(full())
        text=json.dumps(result)
        for forbidden in ('"swap"','"treasury"','"spreadBp"','"unpublishedObservation"'):
            self.assertNotIn(forbidden,text)
        self.assertEqual(result["counts"]["candidate"],1)
        self.assertEqual(result["counts"]["archive_conflict"],1)
        self.assertFalse(result["publicationApproved"])
        self.assertEqual(result["decision"],"REVIEW_ONLY")
        self.assertEqual(result["licenseApproval"],"not_obtained")
    def test_unknown_status_is_rejected(self):
        f=full();f["results"][0]["status"]="permission_granted"
        with self.assertRaises(ValueError):
            pilot.summarize(f)
    def test_exactly_ten_sampling_dates(self):
        self.assertEqual(len(pilot.PILOT_DATES),10)
        self.assertEqual(len(set(pilot.PILOT_DATES)),10)
    def test_isolated_history_stays_byte_identical(self):
        # Only the source candidate generator is mocked, rather than making
        # ten real requests. This tests the file-write boundary.
        original=pilot.build_candidates
        try:
            pilot.build_candidates=lambda *args,**kw:full()
            with tempfile.TemporaryDirectory() as td:
                path=Path(td)/"production-history.json"
                raw=b'{ "schemaVersion": 2, "demo": false, "observations": [] }\n'
                path.write_bytes(raw)
                report=pilot.run(["2026-03-20"],path,today=pilot.date(2026,11,23))
                self.assertEqual(path.read_bytes(),raw)
                self.assertTrue(report["productionHistoryModified"] is False)
        finally:
            pilot.build_candidates=original

if __name__=="__main__":unittest.main()
