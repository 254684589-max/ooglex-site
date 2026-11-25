import unittest
from scripts.asset_compass_sec_returns_v66 import TLT,IVV,AMEND,FUNDS,build,metadata,parse,target
from scripts.asset_compass_sec_returns_v64 import REFERENCE

def fixture(ticker,a,amend=False,values=None):
    _,series,cls,reg=FUNDS[ticker]
    if amend: reg=AMEND
    x,y,z=values or REFERENCE.get(a,("1","0","-1"))
    return f'<edgarSubmission xmlns="http://www.sec.gov/edgar/nport"><headerData><seriesId>{series}</seriesId></headerData><formData><genInfo><seriesId>{series}</seriesId><repPdDate>{reg[a]}</repPdDate></genInfo><fundInfo><returnInfo><monthlyTotReturns><monthlyTotReturn classId="{cls}" rtn1="{x}" rtn2="{y}" rtn3="{z}"/></monthlyTotReturns></returnInfo></fundInfo></formData></edgarSubmission>'.encode()

class PanelTests(unittest.TestCase):
    def test_full_synthetic_panel_and_lock(self):
        rows={a:fixture(k,a) for k,(_,_,_,reg) in FUNDS.items() for a in reg}
        amendments={a:fixture("IVV",a,True,("2","0","-1")) for a in AMEND}
        r=build(rows,amendments)
        self.assertEqual(r["funds"]["TLT"]["parsed_months"],42)
        self.assertEqual(r["funds"]["IVV"]["parsed_months"],24)
        self.assertEqual(r["common_observed_months"],24)
        self.assertTrue(r["common_window_contiguous"])
        self.assertEqual(r["amendment_reviews"][0]["changed_months"],["2025-07"])
        self.assertFalse(r["eligible_for_live_scoring"])
        for f in r["funds"].values():
            self.assertFalse(f["meets_minimum_sample_count"])
            self.assertIsNone(f["official_score"])
        self.assertNotIn("monthly_observations",metadata(r)["funds"]["TLT"])
        self.assertEqual(r["funds"]["IVV"]["monthly_observations"][12]["reported_fund_total_return_percent"],"1")
    def test_gap_and_empty_panel(self):
        a=next(iter(IVV))
        r=build({a:fixture("IVV",a)})
        self.assertEqual(r["funds"]["IVV"]["parsed_months"],3)
        self.assertEqual(len(r["funds"]["IVV"]["missing_months"]),21)
        self.assertEqual(r["common_observed_months"],0)
        self.assertFalse(r["common_window_contiguous"])
        self.assertEqual(len(build({})["funds"]["TLT"]["missing_months"]),42)
    def test_cross_fund_identity_rejected(self):
        a=next(iter(IVV))
        bad=fixture("IVV",a).replace(b"S000004310",b"S000004360")
        with self.assertRaisesRegex(ValueError,"Wrong fund"):
            parse("IVV",a,bad)
    def test_unknown_accession_rejected(self):
        with self.assertRaises(ValueError): build({"not_registered":b"bad"})
