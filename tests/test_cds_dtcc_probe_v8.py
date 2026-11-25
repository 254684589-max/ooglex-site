import io,zipfile,unittest,pathlib,sys
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[1]/"scripts"))
from cds_dtcc_probe_v8 import audit_zip
DAY="2026-11-24"
NAME="SEC_CUMULATIVE_CREDITS_2026_11_24.csv"
HEADER="Dissemination Identifier,Action type,Fixed rate-Leg 1,Other payment type,Other payment amount,Notional amount-Leg 1,Spread-Leg 1,Unique product identifier\n"
def sample(body,name=NAME):
    b=io.BytesIO()
    with zipfile.ZipFile(b,"w") as z:z.writestr(name,body)
    return b.getvalue()
class TestProbe(unittest.TestCase):
    def test_schema(self):
        r=audit_zip(sample(HEADER+"1,NEWT,0.01,UFRO,1000,5000000+,100,FAKE\n"),DAY)
        self.assertEqual(r["row_counts"]["upfront_numeric_rows"],1)
        self.assertEqual(r["row_counts"]["potentially_capped_or_large_notional_rows"],1)
        self.assertEqual(r["admitted_spreads"],0)
        self.assertFalse(r["publication_enabled"])
        self.assertNotIn("FAKE",str(r))
    def test_lifecycle(self):
        r=audit_zip(sample(HEADER+"1,CORR,,,,,,\n2,EROR,,,,,,\n"),DAY)
        self.assertEqual(r["action_counts"],{"CORR":1,"EROR":1})
    def test_missing_not_zero(self):
        r=audit_zip(sample(HEADER+"1,NEWT,0.01,UFRO,,1000000,,\n"),DAY)
        self.assertNotIn("upfront_numeric_rows",r["row_counts"])
    def test_wrong_name(self):
        with self.assertRaises(ValueError):audit_zip(sample(HEADER,"../data.csv"),DAY)
    def test_bad_schema(self):
        with self.assertRaises(ValueError):audit_zip(sample("price,notional\n1,2\n"),DAY)
    def test_duplicate_headers(self):
        with self.assertRaises(ValueError):audit_zip(sample("Dissemination Identifier,Action type,action-type\n1,NEWT,NEWT\n"),DAY)
    def test_row_shape(self):
        with self.assertRaises(ValueError):audit_zip(sample(HEADER+"1,NEWT\n"),DAY)
if __name__=="__main__":unittest.main()
