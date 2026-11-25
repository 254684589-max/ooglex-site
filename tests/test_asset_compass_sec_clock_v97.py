import unittest
from scripts.asset_compass_sec_clock_v97 import registry,parse_rows,FIELDS
from datetime import date,timedelta

class SecClockTests(unittest.TestCase):
    def fixture(self):
        expected=registry()
        acc=next(iter(expected));period=expected[acc]["period"]
        day=(date.fromisoformat(period)+timedelta(days=45)).isoformat()
        cols={"accessionNumber":[acc[:10]+"-"+acc[10:12]+"-"+acc[12:]],"reportDate":[period],
              "filingDate":[day],"acceptanceDateTime":[day+"T17:00:00Z"],"form":["NPORT-P"],"primaryDocument":["primary_doc.xml"]}
        return expected,acc,cols
    def test_timestamp_not_publication(self):
        e,a,c=self.fixture()
        r=parse_rows(c,e,"CIK0001100663.json","a"*64)[a]
        self.assertEqual(r["acceptance_lag_calendar_days"],45)
        self.assertFalse(r["public_dissemination_at_verified"])
        self.assertFalse(r["historical_pit_certified"])
    def test_reject_naive_and_wrong_period(self):
        e,a,c=self.fixture()
        c["acceptanceDateTime"][0]=c["acceptanceDateTime"][0][:-1]
        with self.assertRaises(ValueError):parse_rows(c,e,"CIK0001100663.json","a"*64)
        e,a,c=self.fixture();c["reportDate"][0]="2020-01-01"
        with self.assertRaises(ValueError):parse_rows(c,e,"CIK0001100663.json","a"*64)
    def test_official_xsl_path_not_arbitrary_document(self):
        e,a,c=self.fixture()
        c["primaryDocument"][0]="xslFormNPORT-P_X01/primary_doc.xml"
        self.assertIn(a,parse_rows(c,e,"CIK0001100663.json","a"*64))
        c["primaryDocument"][0]="../primary_doc.xml"
        with self.assertRaises(ValueError):parse_rows(c,e,"CIK0001100663.json","a"*64)
    def test_registry_count(self):
        self.assertEqual(len(registry()),28)
