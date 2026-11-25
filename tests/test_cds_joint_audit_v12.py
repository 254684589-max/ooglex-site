import csv,io,pathlib,sys,unittest,zipfile
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[1]/"scripts"))
from cds_joint_audit_v12 import diagnose
DAY="2026-11-24";UPI="QZ1234567890"
ISSUERS=[{"issuer_id":"meta","name":"Meta Platforms","tickers":["META"]}]
FIELDS=["Dissemination Identifier","Original Dissemination Identifier","Action type","Unique Product Identifier","UPI FISN","UPI Underlier Name","Effective Date","Expiration Date","Notional currency-Leg 1","Notional amount-Leg 1","Fixed rate-Leg 1","Spread-Leg 1","Spread notation-Leg 1","Other payment type","Other payment amount","Other payment currency","Package indicator","Post priced swap indicator","Notional currency-Leg 2","Spread-Leg 2","Spread notation-Leg 2"]
def row(**kw):
    d=dict(zip(FIELDS,["1","","NEWT",UPI,"NA/CDS Corp SN Sr","Meta Platforms","2026-11-24","2031-12-20","USD","1000000","0.01","92","BAPO","UFRO","20000","USD","false","false"]))
    d.update(kw);return d
def ziprows(*rows):
    b=io.StringIO();w=csv.DictWriter(b,fieldnames=FIELDS);w.writeheader();w.writerows(rows)
    z=io.BytesIO()
    with zipfile.ZipFile(z,"w") as f:f.writestr("SEC_CUMULATIVE_CREDITS_2026_11_24.csv",b.getvalue())
    return {DAY:z.getvalue()}
def xmlrow(label="META SEN 5Y 100 USD",upi=UPI):
    return f"<sbsTnr><sbsNm>{label}</sbsNm><upi>{upi}</upi><tenor>P5Y</tenor><ccy>USD</ccy><prcFrmt>SprdBsisPts</prcFrmt><tradCnt>1</tradCnt><clsgPrc>100</clsgPrc></sbsTnr>"
def xml(*rows):
    return {DAY:(f"<dailyMarketDataReport><sbsef>TW SEF LLC</sbsef><date>{DAY}</date><generated>{DAY}T19:00:00-05:00</generated>"+"".join(rows)+"</dailyMarketDataReport>").encode()}
class Tests(unittest.TestCase):
    def run_audit(self,*rows,tw=None):return diagnose(ziprows(*rows),xml(xmlrow()) if tw is None else tw,ISSUERS)
    def test_joint(self):
        d=self.run_audit(row());self.assertEqual(d["counts"]["strict_joint_input_candidate"],1);self.assertEqual(d["cross_source_products"],1);self.assertEqual(d["admitted_spreads"],0)
    def test_cross_source_missing(self):
        d=self.run_audit(row(),tw=xml(xmlrow(upi="QZ1234567891")));self.assertEqual(d["counts"]["cross_source_upi"],0);self.assertEqual(d["counts"]["strict_joint_input_candidate"],0)
    def test_cross_source_conflict(self):
        d=self.run_audit(row(),tw=xml(xmlrow(),xmlrow("OTHER SEN 5Y 100 USD")));self.assertEqual(d["counts"]["cross_source_conflict_excluded"],1);self.assertEqual(d["candidate_products"],0)
    def test_lifecycle(self):
        d=self.run_audit(row(),row(**{"Dissemination Identifier":"2","Original Dissemination Identifier":"1","Action type":"CORR"}));self.assertEqual(d["candidate_products"],0)
    def test_no_joint_without_payment(self):
        d=self.run_audit(row(**{"Other payment amount":""}));self.assertEqual(d["counts"]["strict_joint_input_candidate"],0)
    def test_no_joint_wrong_tenor(self):
        d=self.run_audit(row(**{"Expiration Date":"2030-12-20"}));self.assertEqual(d["counts"]["strict_joint_input_candidate"],0)
    def test_package(self):
        d=self.run_audit(row(**{"Package indicator":"true"}));self.assertEqual(d["counts"]["strict_joint_input_candidate"],0)
    def test_notional_cap(self):
        d=self.run_audit(row(**{"Notional amount-Leg 1":"5,000,000+"}));self.assertEqual(d["counts"]["strict_joint_input_candidate"],0)
    def test_wrong_leg_price(self):
        d=self.run_audit(row(**{"Spread-Leg 1":"","Spread notation-Leg 1":"","Notional currency-Leg 2":"USD","Spread-Leg 2":"92","Spread notation-Leg 2":"BAPO"}));self.assertEqual(d["counts"]["strict_joint_input_candidate"],0)
    def test_no_price_publication(self):
        d=self.run_audit(row(**{"Spread-Leg 1":"987654.321"}));self.assertNotIn("987654.321",str(d));self.assertNotIn(UPI,str(d));self.assertFalse(d["readiness"]["risk_ranking"])
    def test_audit_history_counts(self):
        d=self.run_audit(row());self.assertEqual(d["issuer_audit"]["meta"]["cross_source_upi"],1);self.assertEqual(d["date_audit"][DAY]["cross_source_upi"],1)
if __name__=="__main__":unittest.main()
