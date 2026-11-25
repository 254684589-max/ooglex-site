import csv
import io
import pathlib
import sys
import unittest
import zipfile
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[1]/"scripts"))
from cds_dtcc_diagnostic_v9 import diagnose
DAY="2026-11-24"
FIELDS=["Dissemination Identifier","Original Dissemination Identifier","Action type","UPI Underlier Name","Effective Date","Expiration Date","Spread-Leg 1","Spread notation-Leg 1","Notional currency-Leg 1","Fixed rate-Leg 1","Notional amount-Leg 1","Spread notation-Leg 2","Price","Price notation"]
ISSUERS=[{"issuer_id":"meta","name":"Meta Platforms","issuer_identity":{"legal_name":"Meta Platforms, Inc."}}]
def fixture(rows):
    buf=io.StringIO()
    writer=csv.DictWriter(buf,fieldnames=FIELDS)
    writer.writeheader()
    for row in rows: writer.writerow(row)
    z=io.BytesIO()
    with zipfile.ZipFile(z,"w",zipfile.ZIP_DEFLATED) as out: out.writestr("SEC_CUMULATIVE_CREDITS_2026_11_24.csv",buf.getvalue())
    return z.getvalue()
def row(**kwargs):
    d={"Dissemination Identifier":"1","Action type":"NEWT","UPI Underlier Name":"Meta Platforms, Inc.","Effective Date":"2026-11-24","Expiration Date":"2031-12-20","Spread-Leg 1":"100","Spread notation-Leg 1":"bps","Notional currency-Leg 1":"USD"}
    d.update(kwargs)
    return d
class TestDiagnostic(unittest.TestCase):
    def run_rows(self,*rows):
        return diagnose(fixture(rows),DAY,ISSUERS)
    def test_exact_candidate_not_certified(self):
        d=self.run_rows(row())
        self.assertEqual(d["exact_name_candidate_issuer_count"],1)
        self.assertEqual(d["verified_reference_entities"],0)
        self.assertEqual(d["admitted_spreads"],0)
    def test_no_substring(self):
        d=self.run_rows(row(**{"UPI Underlier Name":"Meta Platforms Subsidiary"}))
        self.assertEqual(d["exact_name_candidate_issuer_count"],0)
    def test_correction_link(self):
        d=self.run_rows(row(),row(**{"Dissemination Identifier":"2","Original Dissemination Identifier":"1","Action type":"CORR"}))
        self.assertEqual(d["diagnostic_counts"]["new_linked_duplicate_or_ambiguous"],1)
        self.assertEqual(d["diagnostic_counts"]["non_new_lifecycle"],1)
        self.assertEqual(d["exact_name_candidate_issuer_count"],0)
    def test_duplicate_id(self):
        d=self.run_rows(row(),row())
        self.assertEqual(d["diagnostic_counts"]["new_linked_duplicate_or_ambiguous"],2)
    def test_leg_mismatch(self):
        d=self.run_rows(row(**{"Spread notation-Leg 1":"","Spread notation-Leg 2":"bps"}))
        self.assertNotIn("same_leg_spread_notation_pairs",d["diagnostic_counts"])
    def test_same_leg(self):
        d=self.run_rows(row())
        self.assertEqual(d["diagnostic_counts"]["same_leg_usd_spread_notation_pairs"],1)
        self.assertEqual(d["diagnostic_counts"]["approx_5y_calendar_rows"],1)
    def test_no_values_emitted(self):
        d=self.run_rows(row(**{"Spread-Leg 1":"123456.78"}))
        self.assertNotIn("123456.78",str(d))
        self.assertFalse(d["publication_enabled"])
if __name__=="__main__":unittest.main()
