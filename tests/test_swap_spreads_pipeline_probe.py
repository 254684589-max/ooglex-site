"""Offline smoke probe tests: do not access the internet or write the archive."""
import importlib.util
from datetime import datetime, timezone
from pathlib import Path
import sys
import unittest
from urllib.error import URLError

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"scripts"))
spec=importlib.util.spec_from_file_location("sofr_pipeline",ROOT/"scripts"/"probe_swap_spread_pipeline.py")
probe=importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)
import json
from update_swap_spreads import YEARS,TREASURY_FIELDS

ASOF="2026-11-20"
NOW=datetime(2026,11,23,12,0,tzinfo=timezone.utc)
def archive(date=ASOF,matched=False):
    result={"schemaVersion":2,"demo":False,"observations":[]}
    if date:
        result["observations"]=[{
            "asOf":date,"quality":"indicative",
            "tenors":[{"years":y,"swap":4.5,"treasury":4.7,"spreadBp":-20.0,"method":"close"} for y in YEARS] if matched else []
        }]
    return result

def responses(swap_asof=ASOF,treasury_asof=ASOF,method="close"):
    swap=json.dumps({"date":swap_asof,"curve":[{"date":swap_asof,"tenor":str(y)+"Y",
                      "rate":4.5,"method":method} for y in YEARS]}).encode()
    xml=('<feed xmlns:d="urn:test"><entry><d:NEW_DATE>'+treasury_asof+
         '</d:NEW_DATE>'+''.join("<d:%s>4.7</d:%s>"%(TREASURY_FIELDS[y],TREASURY_FIELDS[y])
                                     for y in YEARS)+'</entry></feed>').encode()
    return swap,xml
def fake_get(swap,xml):
    return lambda url:swap if "checkmyswap" in url else xml

class ProbeTests(unittest.TestCase):
    def test_matching_latest_day_without_new_data(self):
        s,x=responses()
        r=probe.check_sources(archive(matched=True),fetch=fake_get(s,x),now=NOW)
        self.assertEqual(r["status"],"no_new_day")
        self.assertEqual(r["tenorCount"],6)
        self.assertEqual(r["dayAge"],3)
        self.assertFalse(r["writesProductionHistory"])
    def test_new_older_and_revision_status(self):
        s,x=responses()
        self.assertEqual(probe.check_sources(archive(None),fake_get(s,x),NOW)["status"],"new_candidate_available")
        self.assertEqual(probe.check_sources(archive("2026-11-21"),fake_get(s,x),NOW)["status"],"source_behind_archive")
        self.assertEqual(probe.check_sources(archive(),fake_get(s,x),NOW)["status"],"archived_date_revision")
    def test_source_date_mismatch(self):
        s,x=responses(treasury_asof="2026-11-19")
        r=probe.check_sources(archive(),fake_get(s,x),NOW)
        self.assertEqual(r["status"],"date_mismatch")
    def test_rejected_method(self):
        s,x=responses(method="derived")
        r=probe.check_sources(archive(),fake_get(s,x),NOW)
        self.assertEqual(r["status"],"source_invalid")
    def test_source_network_error_and_invalid_json(self):
        def down(url): raise URLError("offline")
        self.assertEqual(probe.check_sources(archive(),down,NOW)["status"],"source_unavailable")
        self.assertEqual(probe.check_sources(archive(),lambda url:b"{",NOW)["status"],"source_invalid")
    def test_future_quote_rejected(self):
        s,x=responses(swap_asof="2026-11-25")
        self.assertEqual(probe.check_sources(archive(),fake_get(s,x),NOW)["status"],"source_invalid")

if __name__=="__main__":unittest.main()
