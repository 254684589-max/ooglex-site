import unittest
from scripts.prepare_asset_compass_returns import extract_rows, research_returns
from tests.test_macro_price_audit import history, crypto

class PriceReturnResearchTests(unittest.TestCase):
    def test_coin_gecko_btc_independent_calendar(self):
        report=research_returns(history(),crypto())
        btc=report["assets"]["bitcoin"]
        self.assertEqual(btc["symbol"],"BTC")
        self.assertEqual(btc["source"],"CoinGecko")
        self.assertEqual(btc["return_observations"],2)
        self.assertEqual(btc["returns"][0]["date"],"2026-11-19")
        self.assertFalse(report["proxy_total_return_comparable"])
        self.assertFalse(report["validated_for_live_scoring"])
    def test_missing_bitcoin_stays_missing(self):
        result=research_returns(history())
        self.assertEqual(result["assets"]["bitcoin"]["status"],"missing")
    def test_null_quote_not_forward_filled(self):
        d=["2026-11-17","2026-11-18","2026-11-19"]
        values=[100.0,None,110.0]
        tr={"dates":d,"series":{"GC=F":values},"source":"Yahoo Finance"}
        result=research_returns(tr)
        self.assertEqual(result["assets"]["gold"]["return_observations"],1)
        self.assertEqual(result["assets"]["gold"]["returns"][0]["previous_observation_date"],"2026-11-17")
    def test_long_gap_refused(self):
        d=["2026-10-01","2026-10-20"]
        tr={"dates":d,"series":{"GC=F":[100.0,110.0]}}
        self.assertEqual(research_returns(tr)["assets"]["gold"]["return_observations"],0)
    def test_duplicate_dates_refused(self):
        with self.assertRaisesRegex(ValueError,"unique"):
            extract_rows(["2026-11-20","2026-11-20"],[10.0,11.0],"BTC")
    def test_invalid_prices_refused(self):
        with self.assertRaisesRegex(ValueError,"Invalid"):
            extract_rows(["2026-11-19","2026-11-20"],[10.0,-11.0],"BTC")
if __name__=="__main__":unittest.main()
