"""Synthetic fixtures only; no synthetic observation enters the public ledger."""
import datetime as dt
import pathlib
import sys
import unittest
import urllib.error
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "scripts"))
from collect_tradeweb_cds_v5 import audit, collect, dates, empty, merge, validate_ledger
DAY = "2026-11-23"
TICKERS = {"META":"meta", "MSFT":"msft"}
def xml(price="100"):
    return f"""<dailyMarketDataReport><sbsef>TW SEF LLC</sbsef><date>{DAY}</date><generated>{DAY}T19:00:00-05:00</generated><sbsTnr><sbsNm>META SEN 5Y 100 USD</sbsNm><upi>QZ1234567890</upi><tenor>P5Y</tenor><ccy>USD</ccy><prcFrmt>SprdBsisPts</prcFrmt><tradCnt>1</tradCnt><clsgPrc>{price}</clsgPrc></sbsTnr></dailyMarketDataReport>""".encode()
class Tests(unittest.TestCase):
    def test_audit(self):
        row=audit(xml(),DAY,TICKERS)
        self.assertEqual(row["candidate_issuer_ids"],["meta"])
        self.assertEqual(row["classification_counts"],{"coupon_collision":1})
        self.assertEqual(row["admitted_par_spreads"],0)
        self.assertNotIn("price",row)
    def test_idempotent(self):
        d=empty()
        self.assertEqual(merge(d,DAY,audit(xml(),DAY,TICKERS)),"new_report")
        self.assertEqual(merge(d,DAY,audit(xml(),DAY,TICKERS)),"unchanged")
        self.assertEqual(len(d["reports"][DAY]),1)
    def test_revision(self):
        d=empty()
        merge(d,DAY,audit(xml(),DAY,TICKERS))
        self.assertEqual(merge(d,DAY,audit(xml("80"),DAY,TICKERS)),"new_version")
        self.assertEqual(len(d["reports"][DAY]),2)
        validate_ledger(d,TICKERS)
    def test_failed_attempt_preserves(self):
        d=empty()
        merge(d,DAY,audit(xml(),DAY,TICKERS))
        def fail(day): raise urllib.error.URLError("offline")
        collect(d,[DAY],TICKERS,fail)
        self.assertEqual(d["last_run"]["attempts"][DAY],"network_error")
        self.assertEqual(len(d["reports"][DAY]),1)
    def test_missing_not_zero(self):
        def fail(day): raise urllib.error.HTTPError("url",404,"missing",None,None)
        d=collect(empty(),[DAY],TICKERS,fail)
        self.assertEqual(d["reports"],{})
        self.assertEqual(d["last_run"]["attempts"][DAY],"not_available")
    def test_invalid_xml(self):
        for raw in (b"<html/>", b"<!DOCTYPE x>"+xml(), xml().decode().encode("utf-16"), xml().replace(b"2026-11-23",b"2026-11-22")):
            with self.assertRaises(ValueError):
                audit(raw,DAY,TICKERS)
    def test_no_rows(self):
        raw=xml().split(b"<sbsTnr>")[0]+b"</dailyMarketDataReport>"
        with self.assertRaises(ValueError): audit(raw,DAY,TICKERS)
    def test_weekend(self):
        self.assertEqual(dates(dt.date(2026,11,23),3),[DAY])
    def test_reject_quote(self):
        d=empty()
        row=audit(xml(),DAY,TICKERS)
        row["spread_bps"]=100
        merge(d,DAY,row)
        with self.assertRaises(ValueError): validate_ledger(d,TICKERS)
    def test_reject_duplicate(self):
        d=empty()
        row=audit(xml(),DAY,TICKERS)
        d["reports"][DAY]=[row,row]
        with self.assertRaises(ValueError): validate_ledger(d,TICKERS)
if __name__=="__main__": unittest.main()
