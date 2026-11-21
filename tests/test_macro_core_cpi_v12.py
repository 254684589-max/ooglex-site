import json
import unittest
from datetime import date
from pathlib import Path

from scripts.update_macro_bls import SERIES, calculate, parse_series
from scripts.archive_asset_compass_observations import rows_from_snapshot
from scripts.check_asset_compass_history_readiness import report

ROOT=Path(__file__).resolve().parents[1]

class CoreCPIIntegrationTests(unittest.TestCase):
    def test_bls_core_cpi_official_identifier(self):
        self.assertEqual(SERIES["core_cpi"],"CUSR0000SA0L1E")

    def test_independent_headline_and_core_calculation(self):
        observations={
          "cpi":{"2025-09":300.0,"2026-09":309.0},
          "core_cpi":{"2025-09":310.0,"2026-09":322.4},
          "unemployment":{"2026-09":4.2},
          "payroll":{"2026-08":160000.0,"2026-09":160110.0}
        }
        r=calculate(observations,date(2026,10,22))
        self.assertAlmostEqual(r["cpi"]["yoy_percent"],3.0)
        self.assertAlmostEqual(r["core_cpi"]["yoy_percent"],4.0)
        self.assertEqual(r["core_cpi"]["unit"],"index")
        self.assertEqual(r["core_cpi"]["period"],"2026-09")

    def test_core_cpi_missing_year_ago_never_inferred(self):
        obs={
          "cpi":{"2025-10":300.0,"2026-10":309.0},
          "core_cpi":{"2026-10":321.0},
          "unemployment":{"2026-10":4.2},
          "payroll":{"2026-09":160000.0,"2026-10":160090.0}
        }
        out=calculate(obs,date(2026,11,22))
        self.assertNotIn("yoy_percent",out["core_cpi"])
        self.assertIn("yoy_unavailable_reason",out["core_cpi"])
        self.assertAlmostEqual(out["cpi"]["yoy_percent"],3)

    def test_core_cpi_is_separate_from_headline(self):
        series=parse_series({"data":[{"year":"2026","period":"M10","value":"321.123"}]})
        self.assertEqual(series["2026-10"],321.123)

    def test_archive_has_distinct_core_cpi_record(self):
        snapshot={
          "schema_version":1,"observation_date":"2026-11-20","rates":{},
          "source_urls":[],"bls":{
            "source_url":"https://api.bls.gov/publicAPI/v1/timeseries/data/",
            "series":{"core_cpi":{"period":"2026-10","value":321.1},
                      "cpi":{"period":"2026-10","value":337.476}}}
        }
        rows=rows_from_snapshot(snapshot,"2026-11-22T01:00:00Z")
        self.assertEqual({r["series_id"] for r in rows},{"bls.core_cpi","bls.cpi"})
        ready=report(rows)
        self.assertEqual(ready["series"]["bls.core_cpi"]["distinct_observation_periods"],1)
        self.assertFalse(ready["validated_for_live_scoring"])

    def test_registry_and_ui_are_consistent(self):
        config=json.loads((ROOT/"macro/model-config.json").read_text(encoding="utf-8"))
        ids=[x["id"] for x in config["indicator_registry"]]
        self.assertEqual(len(ids),len(set(ids)))
        self.assertIn("core_cpi",ids)
        self.assertIn("nyfed_recession_probability_12m",ids)
        recession=next(x for x in config["indicator_registry"] if x["id"]=="nyfed_recession_probability_12m")
        self.assertEqual(recession["status"],"implemented")
        self.assertEqual(recession["source"],"Federal Reserve Bank of New York")
        page=(ROOT/"macro/index.html").read_text(encoding="utf-8")
        self.assertIn("recent(b.core_cpi)",page)
        self.assertIn("核心CPI同比",page)
        self.assertIn("10年期与3个月期",page)

if __name__=="__main__":unittest.main()
