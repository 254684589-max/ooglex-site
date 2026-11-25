import csv,io,pathlib,sys,unittest,zipfile
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[1]/"scripts"))
from cds_dtcc_lifecycle_v10 import diagnose
D1="2026-11-23"; D2="2026-11-24"
FIELDS=["Dissemination Identifier","Original Dissemination Identifier","Action type","UPI Underlier Name"]
ISSUERS=[{"issuer_id":"meta","name":"Meta Platforms"}]
def fixture(day,*rows):
    b=io.StringIO(); w=csv.writer(b); w.writerow(FIELDS); w.writerows(rows)
    z=io.BytesIO()
    with zipfile.ZipFile(z,"w") as f:f.writestr("SEC_CUMULATIVE_CREDITS_"+day.replace("-","_")+".csv",b.getvalue())
    return z.getvalue()
def new(id="1"):return (id,"","NEWT","Meta Platforms")
class Tests(unittest.TestCase):
    def run_reports(self,**kwargs):return diagnose(kwargs,ISSUERS)
    def test_cross_day_correction(self):
        r=diagnose({D1:fixture(D1,new()),D2:fixture(D2,("2","1","CORR",""))},ISSUERS)
        self.assertEqual(r["diagnostic_counts"]["cross_day_reference_rows"],1)
        self.assertEqual(r["diagnostic_counts"]["quarantined_new_rows"],1)
        self.assertEqual(r["candidate_issuer_count"],0)
    def test_unresolved_original(self):
        r=diagnose({D2:fixture(D2,("2","0","TERM",""))},ISSUERS)
        self.assertEqual(r["diagnostic_counts"]["unresolved_original_rows"],1)
    def test_duplicate_cross_day(self):
        r=diagnose({D1:fixture(D1,new()),D2:fixture(D2,new())},ISSUERS)
        self.assertEqual(r["diagnostic_counts"]["quarantined_new_rows"],2)
    def test_unknown_action_quarantine(self):
        r=diagnose({D1:fixture(D1,new()),D2:fixture(D2,("2","1","X",""))},ISSUERS)
        self.assertEqual(r["diagnostic_counts"]["unknown_action_rows"],1)
        self.assertEqual(r["candidate_issuer_count"],0)
    def test_unlinked_candidate(self):
        r=diagnose({D1:fixture(D1,new())},ISSUERS)
        self.assertEqual(r["candidate_issuer_count"],1)
        self.assertEqual(r["admitted_spreads"],0)
        self.assertFalse(r["publication_enabled"])
    def test_same_day_reference(self):
        r=diagnose({D1:fixture(D1,new(),("2","1","EROR",""))},ISSUERS)
        self.assertEqual(r["diagnostic_counts"]["same_day_reference_rows"],1)
        self.assertEqual(r["candidate_issuer_count"],0)
    def test_future_reference(self):
        r=diagnose({D1:fixture(D1,("2","1","CORR","")),D2:fixture(D2,new())},ISSUERS)
        self.assertEqual(r["diagnostic_counts"]["future_reference_rows"],1)
        self.assertEqual(r["candidate_issuer_count"],0)
if __name__=="__main__":unittest.main()
