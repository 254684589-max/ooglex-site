import unittest
from scripts.asset_compass_sec_returns_v64 import REGISTRY, REFERENCE, build, month_range

def sample(accession, values=None):
    a,b,c=values or REFERENCE.get(accession,("1","0","-1"))
    return f'<edgarSubmission xmlns="http://www.sec.gov/edgar/nport"><formData><genInfo><seriesId>S000004360</seriesId><repPdDate>{REGISTRY[accession]}</repPdDate></genInfo><fundInfo><returnInfo><monthlyTotReturns><monthlyTotReturn classId="C000012090" rtn1="{a}" rtn2="{b}" rtn3="{c}"/></monthlyTotReturns></returnInfo></fundInfo></formData></edgarSubmission>'.encode()

class BackfillTests(unittest.TestCase):
    def test_complete_synthetic_window(self):
        r=build({a:sample(a) for a in REGISTRY})
        self.assertEqual(r["parsed_months"],21)
        self.assertEqual(r["missing_months"],[])
        self.assertTrue(r["complete_target_window"])
        self.assertFalse(r["investable_total_return_certified"])
        self.assertIsNone(r["official_score"])
    def test_missing_never_zero_filled(self):
        r=build({a:sample(a) for a in REFERENCE})
        self.assertEqual(r["parsed_months"],15)
        self.assertEqual(r["missing_months"],["2024-09","2024-10","2024-11","2025-09","2025-10","2025-11"])
        self.assertFalse(r["complete_target_window"])
    def test_reviewed_value_mismatch(self):
        a=next(iter(REFERENCE))
        with self.assertRaisesRegex(ValueError,"Mismatch"):
            build({a:sample(a,("0","0","0"))})
    def test_empty_and_unknown(self):
        self.assertEqual(build({})["missing_months"],month_range())
        with self.assertRaises(ValueError):
            build({"unknown":b"invalid"})
