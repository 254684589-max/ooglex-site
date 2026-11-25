import csv,io,pathlib,sys,unittest,zipfile
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[1]/"scripts"))
from cds_dtcc_mapping_v11 import diagnose,valid_lei
DAY="2026-11-24"; LEI="BQ4BKCS1HXDV9HN80Z93"
ISSUERS=[{"issuer_id":"meta","name":"Meta Platforms","issuer_identity":{"legal_name":"Meta Platforms, Inc.","lei":LEI}}]
FIELDS=["Dissemination Identifier","Original Dissemination Identifier","Action type","Unique Product Identifier","UPI FISN","UPI Underlier Name","Underlier ID-Leg 1","Underlier ID source-Leg 1"]
def row(**kwargs):
    r=dict(zip(FIELDS,["1","","NEWT","QZ1234567890","NA/CDS Corp SN Sr","Meta Platforms, Inc.","",""]))
    r.update(kwargs);return r
def fixture(*rows):
    b=io.StringIO();w=csv.DictWriter(b,fieldnames=FIELDS);w.writeheader();w.writerows(rows)
    z=io.BytesIO()
    with zipfile.ZipFile(z,"w") as f:f.writestr("SEC_CUMULATIVE_CREDITS_2026_11_24.csv",b.getvalue())
    return {DAY:z.getvalue()}
class Tests(unittest.TestCase):
    def audit(self,*rows):return diagnose(fixture(*rows),ISSUERS)
    def test_name_only(self):
        d=self.audit(row());self.assertEqual(d["candidate_issuer_ids"],["meta"]);self.assertEqual(d["verified_upis"],0)
    def test_lei(self):
        self.assertTrue(valid_lei(LEI));self.assertFalse(valid_lei(LEI[:-1]+"4"))
        d=self.audit(row(**{"Underlier ID-Leg 1":LEI,"Underlier ID source-Leg 1":"LEI"}))
        self.assertEqual(d["explicit_lei_candidate_issuer_ids"],["meta"])
    def test_conflict(self):
        d=self.audit(row(**{"Underlier ID-Leg 1":"INR2EJN1ERAN0W5ZP974","Underlier ID source-Leg 1":"LEI"}))
        self.assertEqual(d["candidate_issuer_ids"],[])
    def test_index(self):
        self.assertEqual(self.audit(row(**{"UPI FISN":"NA/CDS Idx"}))["candidate_upi_count"],0)
    def test_metadata_change(self):
        d=self.audit(row(),row(**{"Dissemination Identifier":"2","UPI Underlier Name":"Other company"}))
        self.assertEqual(d["conflicting_upis"],1);self.assertEqual(d["candidate_upi_count"],0)
    def test_bad_upi_correction(self):
        d=self.audit(row(),row(**{"Dissemination Identifier":"2","Original Dissemination Identifier":"1","Action type":"CORR","Unique Product Identifier":"bad"}))
        self.assertEqual(d["candidate_upi_count"],0)
    def test_no_quotes(self):
        d=self.audit(row());self.assertFalse(d["publication_enabled"]);self.assertEqual(d["admitted_spreads"],0)
if __name__=="__main__":unittest.main()
