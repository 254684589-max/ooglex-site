"""Read-only validation and source-audit tests; no network connection required."""
import importlib.util
import io
import json
from pathlib import Path
import sys
import unittest
from urllib.error import HTTPError

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"scripts"))
spec=importlib.util.spec_from_file_location("coverage",ROOT/"scripts"/"audit_swap_spreads_coverage.py")
audit=importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)

def record(day):
    return {"asOf":day,"tenors":[
        {"years":years,"swap":4.5,"treasury":4.7,"spreadBp":-20,"method":"close-thin" if years==2 else "close"}
        for years in audit.YEARS
    ]}

class CoverageTests(unittest.TestCase):
    def test_single_day_is_not_long_history(self):
        result=audit.check_history({"schemaVersion":2,"demo":False,"observations":[record("2026-11-20")]},
                                   audit.parse_date("2026-11-22"))
        self.assertEqual(result["status"],"ok")
        self.assertEqual(result["observations"],1)
        self.assertFalse(result["eligibleForPercentiles"])
        self.assertEqual(result["thinCloseDays"],1)
    def test_stale_and_weekday_gap_labels(self):
        doc={"schemaVersion":2,"demo":False,"observations":[record("2026-11-20"),record("2026-11-24")]}
        r=audit.check_history(doc,audit.parse_date("2026-12-05"))
        self.assertEqual(r["status"],"stale")
        self.assertIn("2026-11-23",r["missingWeekdaysSample"])
    def test_duplicate_and_tampered_spread_rejected(self):
        doc={"schemaVersion":2,"demo":False,"observations":[record("2026-11-20"),record("2026-11-20")]}
        with self.assertRaisesRegex(ValueError,"Duplicate"):
            audit.check_history(doc,audit.parse_date("2026-11-22"))
        doc["observations"]=[record("2026-11-20")]
        doc["observations"][0]["tenors"][0]["spreadBp"]=5
        with self.assertRaisesRegex(ValueError,"Inconsistent"):
            audit.check_history(doc,audit.parse_date("2026-11-22"))
    def test_future_and_noncanonical_dates_rejected(self):
        with self.assertRaises(ValueError):audit.parse_date("2026-02-30")
        with self.assertRaisesRegex(ValueError,"Future"):
            audit.check_history({"schemaVersion":2,"demo":False,"observations":[record("2026-11-23")]},
                                audit.parse_date("2026-11-22"))
    def test_source_audit_rejects_dates_before_archive(self):
        with self.assertRaisesRegex(ValueError,"2026-03-19"):
            audit.audit_dates(["2026-03-18"],fetch=lambda u: b"")
        with self.assertRaisesRegex(ValueError,"1-10"):
            audit.audit_dates(["2026-11-20"]*2,fetch=lambda u: b"")
    def test_dated_source_audit_never_uses_latest_snapshot(self):
        called=[]
        date="2026-11-20"
        fields="".join("<d:%s>4.7</d:%s>"%(v,v) for v in audit.TREASURY_FIELDS.values())
        xml=('<feed xmlns:d="urn:fixture"><entry><d:NEW_DATE>'+date+'</d:NEW_DATE>'+fields+'</entry></feed>').encode()
        payload={"date":date,"curve":[{"tenor":str(y)+"Y","date":date,"method":"close","rate":4.5}
                                     for y in audit.YEARS]}
        def fetch(url):
            called.append(url)
            return xml if "treasury" in url else json.dumps(payload).encode()
        output=audit.audit_dates([date],fetch=fetch)
        self.assertTrue(called[-1].endswith("?date="+date))
        self.assertEqual(output[0]["status"],"verified_only")
    def test_mismatched_dated_source_rejected(self):
        date="2026-11-20"
        fields="".join("<d:%s>4.7</d:%s>"%(v,v) for v in audit.TREASURY_FIELDS.values())
        xml=('<feed xmlns:d="urn:fixture"><entry><d:NEW_DATE>'+date+'</d:NEW_DATE>'+fields+'</entry></feed>').encode()
        def fetch(url):
            return xml if "treasury" in url else json.dumps({"date":"2026-11-19","curve":[]}).encode()
        with self.assertRaisesRegex(ValueError,"wrong date"):
            audit.audit_dates([date],fetch=fetch)
    def test_404_recorded_as_gap_not_fabricated(self):
        date="2026-11-20"
        xml=('<feed xmlns:d="urn:fixture"><entry><d:NEW_DATE>'+date+'</d:NEW_DATE>'+
              "".join("<d:%s>4.7</d:%s>"%(v,v) for v in audit.TREASURY_FIELDS.values())+'</entry></feed>').encode()
        def fetch(url):
            if "treasury" in url:return xml
            raise HTTPError(url,404,"Not Found",{},None)
        output=audit.audit_dates([date],fetch=fetch)
        self.assertEqual(output[0]["status"],"missing_archive")

if __name__=="__main__":
    unittest.main()
