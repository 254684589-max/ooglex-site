import unittest
from scripts.asset_compass_sec_returns_v63 import parse_filing, assemble, FILINGS

FEB, MAY = tuple(FILINGS)

def fixture(accession, series="S000004360", cls="C000012090", r1="-2", r2="0", r3="3"):
    # Synthetic XML, never a live SEC document or real performance history.
    return f"""<edgarSubmission xmlns="http://www.sec.gov/edgar/nport">
    <formData><genInfo><seriesId>{series}</seriesId><repPdDate>{FILINGS[accession]}</repPdDate></genInfo>
    <fundInfo><returnInfo><monthlyTotReturns><monthlyTotReturn classId="{cls}" rtn1="{r1}" rtn2="{r2}" rtn3="{r3}"/>
    </monthlyTotReturns></returnInfo></fundInfo></formData></edgarSubmission>""".encode()

class SecReturnPilotTests(unittest.TestCase):
    def test_months_and_no_certification(self):
        a = parse_filing(fixture(FEB), FEB)
        b = parse_filing(fixture(MAY), MAY)
        report = assemble([a,b])
        self.assertEqual([x["month"] for x in report["observations"]],
            ["2025-12","2026-01","2026-02","2026-03","2026-04","2026-05"])
        self.assertEqual(report["observations"][1]["reported_fund_total_return_percent"],"0")
        self.assertEqual(len(a["local_input_sha256"]),64)
        self.assertIsNone(report["official_score"])
        self.assertFalse(report["investable_total_return_certified"])
        self.assertFalse(report["historical_pit_certified"])
    def test_wrong_fund_or_class(self):
        for raw in [fixture(FEB,series="OTHER"),fixture(FEB,cls="OTHER"),fixture(MAY)]:
            with self.assertRaises(ValueError):
                parse_filing(raw,FEB)
    def test_missing_nonfinite_or_impossible_return(self):
        for val in ["", "NaN", "Infinity", "-101"]:
            with self.assertRaises(ValueError):
                parse_filing(fixture(FEB,r1=val),FEB)
    def test_no_unreviewed_accession_or_xml_entity(self):
        with self.assertRaises(ValueError):
            parse_filing(fixture(FEB),"fake")
        with self.assertRaises(ValueError):
            parse_filing(b'<!DOCTYPE x [<!ENTITY z "bad">]>'+fixture(FEB),FEB)
    def test_no_duplicate_months(self):
        a = parse_filing(fixture(FEB),FEB)
        with self.assertRaises(ValueError):
            assemble([a,a])

if __name__ == "__main__":
    unittest.main()
