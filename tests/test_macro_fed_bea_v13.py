import json
import unittest
from datetime import date
from pathlib import Path
from scripts.update_macro_fed_bea import parse_csv, calculate
from scripts.archive_asset_compass_observations import rows_from_snapshot

ROOT=Path(__file__).resolve().parents[1]
class FedBEAIntegrationTests(unittest.TestCase):
    def test_fred_csv_header_variants(self):
        p=parse_csv("observation_date,PCEPILFE\n2025-10-01,130\n2026-10-01,134\n", "PCEPILFE",date(2026,11,22))
        self.assertEqual(p[date(2026,10,1)],134)
        h=parse_csv("DATE,WALCL\n2026-11-18,6600000\n", "WALCL",date(2026,11,22))
        self.assertEqual(h[date(2026,11,18)],6600000)
    def test_rejects_missing_columns_and_future(self):
        with self.assertRaisesRegex(ValueError,"headers"):
            parse_csv("x,y\na,b\n","WALCL")
        with self.assertRaisesRegex(ValueError,"No valid"):
            parse_csv("DATE,WALCL\n2028-01-01,120\n","WALCL",date(2026,11,22))
    def test_core_pce_yoy_and_h41(self):
        core,h=calculate({date(2025,10,1):130.0,date(2026,10,1):134.0},
                         {date(2026,11,18):6600000.0},date(2026,11,22))
        self.assertAlmostEqual(core["yoy_percent"],3.077)
        self.assertEqual(h["value_millions_usd"],6600000)
        self.assertFalse(core["release_timestamp_verified"])
    def test_absent_pce_baseline_is_not_fabricated(self):
        core,h=calculate({date(2026,10,1):134.0},
                         {date(2026,11,18):6600000.0},date(2026,11,22))
        self.assertNotIn("yoy_percent",core)
        self.assertEqual(core["yoy_unavailable_reason"],"official_reference_month_missing")
    def test_staleness_rejected(self):
        with self.assertRaisesRegex(ValueError,"stale"):
            calculate({date(2025,1,1):123.0},{date(2026,11,18):6600000.0},date(2026,11,22))
        with self.assertRaisesRegex(ValueError,"stale"):
            calculate({date(2026,10,1):123.0},{date(2026,9,1):6600000.0},date(2026,11,22))
    def test_new_sources_archive_distinct(self):
        snap={"schema_version":1,"rates":{},"source_urls":[],
          "bea":{"core_pce":{"value":134.0,"observation_period":"2026-10","source_url":"https://fred.stlouisfed.org/graph/fredgraph.csv?id=PCEPILFE"}},
          "fed_h41":{"total_assets":{"value_millions_usd":6600000.0,"observation_date":"2026-11-18","source_url":"https://fred.stlouisfed.org/graph/fredgraph.csv?id=WALCL"}}}
        rows=rows_from_snapshot(snap,"2026-11-22T03:00:00Z")
        self.assertEqual({r["series_id"] for r in rows},{"bea.core_pce","fed_h41.total_assets"})
        self.assertTrue(all(r["eligible_for_historical_official_vintage"] is False for r in rows))
    def test_ui_and_registry_definitions(self):
        cfg=json.loads((ROOT/"macro/model-config.json").read_text(encoding="utf-8"))
        vals={x["id"]:x for x in cfg["indicator_registry"]}
        self.assertEqual(vals["core_pce"]["status"],"implemented")
        self.assertEqual(vals["fed_balance_sheet"]["status"],"implemented")
        html=(ROOT/"macro/index.html").read_text(encoding="utf-8")
        self.assertIn('id="fed-bea"',html)
        self.assertIn("showFedBea(d)",html)
        self.assertIn("value_millions_usd",html)
        self.assertNotIn(r"/^\\d",html)
if __name__=="__main__":unittest.main()
