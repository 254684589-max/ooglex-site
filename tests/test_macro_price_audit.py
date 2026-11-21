import unittest
from datetime import date
from scripts.audit_asset_compass_prices import audit,PROXIES

def history():
    names={p["symbol"] for p in PROXIES.values() if p["symbol"]!="BTC-USD"}
    return {"dates":["2026-11-18","2026-11-19","2026-11-20"],
        "source":"Yahoo Finance","asOf":"2026-11-20","frequency":"daily",
        "series":{symbol:[100.0,None,102.0] for symbol in names}}

def crypto():
    return {"source":"CoinGecko","asOf":"2026-11-20",
       "history":{"dates":["2026-11-17","2026-11-18","2026-11-19","2026-11-20"],
                  "series":{"BTC":[75000.0,None,76000.0,77000.0]}}}

class PriceCoverageTests(unittest.TestCase):
    def test_missing_bitcoin_is_not_backfilled(self):
        a=audit(history())
        self.assertEqual(a["assets"]["bitcoin"]["status"],"missing")
        self.assertEqual(a["assets"]["bitcoin"]["observation_count"],0)
    def test_coin_gecko_history_reuses_independent_calendar(self):
        result=audit(history(),crypto())
        btc=result["assets"]["bitcoin"]
        self.assertEqual(btc["observation_count"],3)
        self.assertEqual(btc["calendar_observation_dates"],4)
        self.assertEqual(btc["coverage_percent"],75.0)
        self.assertEqual(btc["source"],"CoinGecko")
        self.assertFalse(btc["eligible_for_return_backtest"])
        self.assertIn("CoinGecko",result["source"])
    def test_crypto_missing_series_stays_missing(self):
        item=crypto()
        item["history"]["series"]={}
        self.assertEqual(audit(history(),item)["assets"]["bitcoin"]["status"],"missing")
    def test_crypto_misaligned_dates_fail(self):
        item=crypto()
        item["history"]["series"]["BTC"]=[12.0]
        with self.assertRaisesRegex(ValueError,"length mismatch"):
            audit(history(),item)
    def test_crypto_invalid_quotes_fail(self):
        item=crypto()
        item["history"]["series"]["BTC"][0]=float("nan")
        with self.assertRaisesRegex(ValueError,"Invalid BTC quote"):
            audit(history(),item)
    def test_crypto_source_must_be_verified(self):
        item=crypto()
        item["source"]="Unknown"
        with self.assertRaisesRegex(ValueError,"source"):
            audit(history(),item)
    def test_proxies_are_not_mislabeled_total_return(self):
        a=audit(history())
        for item in a["assets"].values():
            self.assertFalse(item["eligible_for_return_backtest"])
        self.assertFalse(a["validated_for_live_scoring"])
    def test_dates_and_nulls_are_preserved(self):
        a=audit(history())
        self.assertEqual(a["assets"]["gold"]["observation_count"],2)
        self.assertEqual(a["assets"]["gold"]["missing_dates"],1)
        self.assertEqual(a["assets"]["gold"]["coverage_percent"],66.67)
    def test_invalid_price_fails(self):
        h=history()
        h["series"]["GC=F"][1]=-1
        with self.assertRaisesRegex(ValueError,"invalid quote"):
            audit(h)
    def test_misaligned_history_fails(self):
        h=history()
        h["series"]["TLT"]=[80]
        with self.assertRaisesRegex(ValueError,"length mismatch"):
            audit(h)
    def test_duplicate_dates_fail(self):
        h=history()
        h["dates"]=["2026-11-18","2026-11-18","2026-11-20"]
        with self.assertRaisesRegex(ValueError,"duplicate"):
            audit(h)
if __name__=="__main__":unittest.main()
