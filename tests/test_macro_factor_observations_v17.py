import unittest
from datetime import date
from scripts.build_asset_compass_factor_observations import collect

TODAY=date(2026,11,22)
TREASURY_URL="https://home.treasury.gov/daily?type=daily_treasury_yield_curve&format=csv"
TIPS_URL="https://home.treasury.gov/daily?type=daily_treasury_real_yield_curve&format=csv"
def sample():
    return {
      "schema_version":1,"observation_date":"2026-11-20",
      "source_urls":[TREASURY_URL,TIPS_URL],
      "rates":{"us10y":4.92,"us2y":4.63,"real10y":2.77,
               "breakeven10y":999,"spread10y2y":999},
      "nyfed":{"effr_percent":3.88,"observation_date":"2026-11-19",
               "source_url":"https://markets.newyorkfed.org/api/rates"},
      "bls":{"source_url":"https://api.bls.gov/publicAPI/v1/timeseries/data/",
             "series":{
               "cpi":{"period":"2026-10","value":337.4},
               "core_cpi":{"period":"2026-10","yoy_percent":2.7},
               "unemployment":{"period":"2026-10","value":4.1},
               "payroll":{"period":"2026-10","monthly_change_thousands":165}}},
      "bea":{"core_pce":{"observation_period":"2026-09","yoy_percent":2.8,
            "source_url":"https://fred.stlouisfed.org/graph/fredgraph.csv?id=PCEPILFE"}},
      "fed_h41":{"total_assets":{"observation_date":"2026-11-18",
            "value_millions_usd":6600000,
            "source_url":"https://fred.stlouisfed.org/graph/fredgraph.csv?id=WALCL"}},
      "liquidity":{"reserves":{"observation_date":"2026-11-18",
            "value":2979656,"unit":"millions_usd",
            "source":"Federal Reserve via FRED",
            "source_url":"https://fred.stlouisfed.org/graph/fredgraph.csv?id=WRESBAL"},
            "tga":{"observation_date":"2026-11-18","value":916613,"unit":"millions_usd",
                   "source":"Federal Reserve via FRED",
                   "source_url":"https://fred.stlouisfed.org/graph/fredgraph.csv?id=WTREGEN"},
            "overnight_rrp":{"observation_date":"2026-11-20","value":0.0,"unit":"billions_usd",
                   "source":"New York Fed via FRED",
                   "source_url":"https://fred.stlouisfed.org/graph/fredgraph.csv?id=RRPONTSYD"}},
      "nyfed_recession_model":{"observation_period":"2026-10","target_period":"2027-10",
            "probability_percent":12.415814,"official_forecast":False,
            "source_url":"https://www.newyorkfed.org/medialibrary/media/research/capital_markets/allmonth.xls"}
    }

class FactorObservationsTests(unittest.TestCase):
    def test_no_scoring_in_public_report(self):
        result=collect(sample(),TODAY)
        self.assertFalse(result["validated_for_live_scoring"])
        self.assertFalse(result["factor_signals_calibrated"])
        self.assertFalse(result["asset_specific_contributions_available"])
        self.assertFalse(result["independent_factor_group_count_certified"])
        self.assertEqual(result["groups"]["risk"]["observations"],[])
        self.assertEqual(result["groups"]["asset_specific"]["observations"],[])
    def test_treasury_derived_identites_use_same_day_observations(self):
        report=collect(sample(),TODAY)
        rates={o["id"]:o for o in report["groups"]["rates"]["observations"]}
        inf={o["id"]:o for o in report["groups"]["inflation"]["observations"]}
        self.assertAlmostEqual(rates["spread10y2y"]["value"],.29)
        self.assertAlmostEqual(inf["breakeven10y"]["value"],2.15)
        self.assertIn("formula",inf["breakeven10y"])
        self.assertNotIn("cpi_yoy",inf)
    def test_unit_and_zero_rrp_preserved(self):
        r=collect(sample(),TODAY)
        liquidity={v["id"]:v for v in r["groups"]["liquidity"]["observations"]}
        self.assertEqual(liquidity["reserves"]["unit"],"millions_usd")
        self.assertEqual(liquidity["overnight_rrp"]["unit"],"billions_usd")
        self.assertEqual(liquidity["overnight_rrp"]["value"],0.0)
    def test_missing_is_not_neutral_or_imputed(self):
        s=sample();s["rates"]["real10y"]=None;s["rates"]["us10y"]=float("nan")
        r=collect(s,TODAY)
        self.assertNotIn("us10y",[x["id"] for x in r["groups"]["rates"]["observations"]])
        self.assertNotIn("real10y",[x["id"] for x in r["groups"]["rates"]["observations"]])
        self.assertNotIn("breakeven10y",[x["id"] for x in r["groups"]["inflation"]["observations"]])
        self.assertTrue(r["no_missing_to_neutral_imputation"])
    def test_staleness_omits_observations(self):
        s=sample();s["observation_date"]="2026-10-10"
        s["fed_h41"]["total_assets"]["observation_date"]="2026-09-01"
        s["liquidity"]["overnight_rrp"]["observation_date"]="2026-10-01"
        r=collect(s,TODAY)
        self.assertFalse(any(o["id"]=="us10y" for o in r["groups"]["rates"]["observations"]))
        self.assertFalse(any(o["id"]=="fed_assets" for o in r["groups"]["liquidity"]["observations"]))
        self.assertFalse(any(o["id"]=="overnight_rrp" for o in r["groups"]["liquidity"]["observations"]))
    def test_mismatched_model_target_rejected(self):
        s=sample();s["nyfed_recession_model"]["target_period"]="2027-09"
        r=collect(s,TODAY)
        self.assertNotIn("nyfed_recession_probability",[x["id"] for x in r["groups"]["growth"]["observations"]])
    def test_missing_source_url_is_not_verified(self):
        s=sample();s["bea"]["core_pce"]["source_url"]=""
        s["bls"]["source_url"]=""
        r=collect(s,TODAY)
        self.assertFalse(any(o["id"]=="core_pce_yoy" for o in r["groups"]["inflation"]["observations"]))
        self.assertFalse(any(o["id"]=="unemployment" for o in r["groups"]["growth"]["observations"]))
    def test_unknown_or_wrong_schema_rejected(self):
        with self.assertRaisesRegex(ValueError,"Unsupported"):
            collect({"schema_version":2},TODAY)
    def test_entry_not_historical_vintage(self):
        r=collect(sample(),TODAY)
        for group in r["groups"].values():
            for item in group["observations"]:
                self.assertFalse(item["validated_historical_release_time"])
                self.assertFalse(item["qualifies_as_model_factor_signal"])

if __name__=="__main__":unittest.main()
