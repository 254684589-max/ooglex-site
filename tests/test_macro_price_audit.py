import unittest
from datetime import date
from scripts.audit_asset_compass_prices import audit,PROXIES

def history():
    names={p["symbol"] for p in PROXIES.values() if p["symbol"]!="BTC-USD"}
    return {"dates":["2026-11-18","2026-11-19","2026-11-20"],
        "source":"Yahoo Finance","asOf":"2026-11-20","frequency":"daily",
        "series":{symbol:[100.0,None,102.0] for symbol in names}}

class PriceCoverageTests(unittest.TestCase):
    def test_missing_bitcoin_is_not_backfilled(self):
        a=audit(history())
        self.assertEqual(a["assets"]["bitcoin"]["status"],"missing")
        self.assertEqual(a["assets"]["bitcoin"]["observation_count"],0)
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
