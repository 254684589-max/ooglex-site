import json
import tempfile
import unittest
from datetime import date
from pathlib import Path
from unittest.mock import patch
from scripts import update_macro_liquidity as liq

class LiquidityTests(unittest.TestCase):
    def test_series_units_and_sources_distinct(self):
        self.assertEqual(liq.SOURCES["reserves"][0],"WRESBAL")
        self.assertEqual(liq.SOURCES["tga"][0],"WTREGEN")
        self.assertEqual(liq.SOURCES["overnight_rrp"][:2],("RRPONTSYD","billions_usd"))
    def test_zero_rrp_is_valid(self):
        r=liq.parse_series("DATE,RRPONTSYD\n2026-11-18,0\n2026-11-19,0.401\n","RRPONTSYD",date(2026,11,22))
        self.assertEqual(r[date(2026,11,18)],0)
        self.assertEqual(r[date(2026,11,19)],.401)
    def test_invalid_csv_fails_closed(self):
        with self.assertRaisesRegex(ValueError,"column"):
            liq.parse_series("DATE,A\n2026-11-18,100\n","WRESBAL")
        with self.assertRaisesRegex(ValueError,"No valid"):
            liq.parse_series("DATE,WRESBAL\n2026-11-18,-100\n","WRESBAL")
    def test_staleness_gate(self):
        with self.assertRaisesRegex(ValueError,"stale"):
            liq.build_observation({date(2026,10,1):40},"reserves","https://fred.stlouisfed.org/",date(2026,11,22))
    def test_unit_not_converted_by_error(self):
        obs=liq.build_observation({date(2026,11,20):.401},"overnight_rrp","https://fred.stlouisfed.org/",date(2026,11,22))
        self.assertEqual(obs["value"],.401)
        self.assertEqual(obs["unit"],"billions_usd")
        self.assertFalse(obs["release_timestamp_verified"])
    def test_bounded_download_url(self):
        url=liq.source_url("WTREGEN",date(2026,11,22))
        self.assertIn("cosd=2025-01-01",url)
        self.assertIn("coed=2026-11-22",url)
    def test_partial_timeout_keeps_verified_source(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/"asset-scores.json"
            path.write_text('{"schema_version":1,"assets":{}}')
            dates={date(2026,11,18):3000000.}
            with patch.object(liq,"FILE",path), patch.object(liq,"download",side_effect=[
                (dates,liq.source_url("WRESBAL",date(2026,11,22))),
                TimeoutError("slow"),
                ({date(2026,11,20):0.401},liq.source_url("RRPONTSYD",date(2026,11,22)))
            ]):
                result=liq.main()
            data=json.loads(path.read_text())
            self.assertEqual(set(result["verified"]),{"reserves","overnight_rrp"})
            self.assertNotIn("tga",data["liquidity"])
            self.assertEqual(data["liquidity"]["reserves"]["value"],3000000)
            self.assertEqual(data["liquidity"]["overnight_rrp"]["value"],.401)
if __name__=="__main__":unittest.main()
