"""Synthetic tests only; no fabricated observations enter production."""
import unittest
from scripts.audit_tradeweb_cds_v2 import read_xml

def sample(name="META SEN 5Y 100 USD", tenor="P5Y", currency="USD", fmt="SprdBsisPts", price="100", upi="QZ1234567890"):
    return f"""<dailyMarketDataReport><sbsef>TW SEF LLC</sbsef><date>2026-11-23</date><generated>2026-11-23T19:00:00-05:00</generated><sbsTnr><sbsNm>{name}</sbsNm><upi>{upi}</upi><tenor>{tenor}</tenor><ccy>{currency}</ccy><prcFrmt>{fmt}</prcFrmt><tradCnt>1</tradCnt><clsgPrc>{price}</clsgPrc></sbsTnr></dailyMarketDataReport>""".encode()

class AuditTest(unittest.TestCase):
    def audit(self, **kwargs):
        return read_xml(sample(**kwargs), "2026-11-23", {"META":"meta"})
    def test_coupon(self):
        r=self.audit()
        self.assertEqual(r["classification_counts"],{"coupon_collision":1})
        self.assertEqual(r["admitted_par_spreads"],0)
        self.assertFalse(r["publication_enabled"])
    def test_non_coupon(self):
        self.assertEqual(self.audit(price="83")["classification_counts"],{"price_semantics_unverified":1})
    def test_mismatch(self):
        for args in ({"tenor":"P4Y"},{"currency":"EUR"},{"name":"META SEN 4.5Y 100 USD"}):
            self.assertEqual(self.audit(**args)["classification_counts"],{"contract_excluded":1})
    def test_invalid_price(self):
        self.assertEqual(self.audit(price="NaN")["classification_counts"],{"invalid_price_or_count":1})
    def test_format(self):
        self.assertEqual(self.audit(fmt="PrmPctNtnl")["classification_counts"],{"incompatible_price_format":1})
    def test_invalid_upi(self):
        self.assertEqual(self.audit(upi="bad")["classification_counts"],{"missing_product_identifier":1})
    def test_no_fuzzy_match(self):
        self.assertEqual(self.audit(name="METAX SEN 5Y 100 USD")["candidate_count"],0)
    def test_date(self):
        with self.assertRaises(ValueError):
            read_xml(sample(),"2026-11-24",{})
    def test_doctype(self):
        with self.assertRaises(ValueError):
            read_xml(b"<!DOCTYPE x>"+sample(),"2026-11-23",{})
if __name__=="__main__":
    unittest.main()
