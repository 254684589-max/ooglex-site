"""V6 unpublishable review artifacts: deterministic offline tests."""
import importlib.util
import json
from pathlib import Path
import sys
import unittest
from urllib.error import HTTPError

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
spec=importlib.util.spec_from_file_location("sofr_candidate",ROOT/"scripts"/"build_swap_spread_candidates.py")
mod=importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
from update_swap_spreads import YEARS, TREASURY_FIELDS

DATE="2026-11-20"
def source_data(observation_date=DATE):
    fields="".join(f"<d:{TREASURY_FIELDS[y]}>4.70</d:{TREASURY_FIELDS[y]}>" for y in YEARS)
    xml=("<feed xmlns:d='urn:fixture'><entry><d:NEW_DATE>"+DATE+"</d:NEW_DATE>"+fields+"</entry></feed>").encode()
    curve={"date":observation_date,"curve":[
        {"date":observation_date,"tenor":f"{y}Y","rate":4.5,"method":"close"} for y in YEARS]}
    return xml,json.dumps(curve).encode()

def inputs():
    return {"schemaVersion":2,"demo":False,"observations":[]}

class CandidateTests(unittest.TestCase):
    def test_candidate_has_six_tenors_and_source_digests(self):
        xml,ois=source_data()
        calls=[]
        def fetch(url):
            calls.append(url)
            return xml if "treasury" in url else ois
        result=mod.build_candidates([DATE],inputs(),fetch=fetch,today=mod.parse_date("2026-11-22"))
        self.assertEqual(result["counts"]["candidate"],1)
        self.assertFalse(result["productionHistoryModified"])
        entry=result["results"][0]
        self.assertEqual(entry["verifiedTenorCount"],6)
        self.assertEqual(entry["unpublishedObservation"]["tenors"][4]["spreadBp"],-20)
        self.assertEqual(len(entry["provenance"]["oisSha256"]),64)
        self.assertTrue(calls[-1].endswith("?date="+DATE))

    def test_historical_conflict_is_never_overwritten(self):
        xml,ois=source_data()
        def fetch(url):return xml if "treasury" in url else ois
        existing=inputs()
        existing["observations"]=[{"asOf":DATE,"quality":"indicative","tenors":[]}]
        result=mod.build_candidates([DATE],existing,fetch=fetch,today=mod.parse_date("2026-11-22"))
        self.assertEqual(result["counts"]["archive_conflict"],1)
        self.assertEqual(existing["observations"][0]["tenors"],[])

    def test_missing_day_is_not_filled_from_latest(self):
        xml,_=source_data()
        def fetch(url):
            if "treasury" in url:return xml
            raise HTTPError(url,404,"Not found",{},None)
        r=mod.build_candidates([DATE],inputs(),fetch=fetch,today=mod.parse_date("2026-11-22"))
        self.assertEqual(r["counts"]["no_archive"],1)
        self.assertEqual(r["counts"]["candidate"],0)

    def test_wrong_returned_date_is_rejected(self):
        xml,ois=source_data("2026-11-19")
        def fetch(url):return xml if "treasury" in url else ois
        r=mod.build_candidates([DATE],inputs(),fetch=fetch,today=mod.parse_date("2026-11-22"))
        self.assertEqual(r["counts"]["rejected"],1)
        self.assertNotIn("unpublishedObservation",r["results"][0])

    def test_no_future_archive_or_date_duplicates(self):
        for dates in [["2026-11-23"],["2026-11-20","2026-11-20"],["2026-03-18"]]:
            with self.assertRaises(ValueError):
                mod.build_candidates(dates,inputs(),fetch=lambda url:b"",today=mod.parse_date("2026-11-22"))

    def test_no_many_date_scan_without_explicit_scope(self):
        dates=["2026-03-%02d"%i for i in range(19,30)]
        with self.assertRaisesRegex(ValueError,"1-10"):
            mod.build_candidates(dates,inputs(),fetch=lambda url:b"",today=mod.parse_date("2026-11-22"))

if __name__=="__main__":unittest.main()
