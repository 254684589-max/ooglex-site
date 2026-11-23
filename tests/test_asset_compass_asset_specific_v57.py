"""V57 official CFTC gold / Treasury long bond auction, source integrity tests."""
import copy
import json
import math
import unittest
from datetime import date,datetime,timedelta,timezone
from pathlib import Path

from scripts.build_asset_compass_asset_specific_v57 import (
 CFTC_CODE,ASSETS,CFTC_ENDPOINT,FISCAL_ENDPOINT,CFTC_ARGS,FISCAL_ARGS,
 address,parse_gold,parse_treasury,combine_auction_sources,build,retrieve,
)
ROOT=Path(__file__).resolve().parents[1]
NOW=datetime(2026,11,23,10,0,tzinfo=timezone.utc)


def gold_raw():
    dates=[date(2026,11,17)-timedelta(weeks=i) for i in range(135)]
    return json.dumps([{
       "cftc_contract_market_code":CFTC_CODE,
       "market_and_exchange_names":"GOLD - COMMODITY EXCHANGE INC.",
       "report_date_as_yyyy_mm_dd":day.isoformat()+"T00:00:00.000",
       "m_money_positions_long_all":str(175000+i%17*250),
       "m_money_positions_short_all":str(81000+i%11*300),
       "open_interest_all":"470000",
    } for i,day in enumerate(dates)]).encode()


def treasury_raw():
    items=[]
    for i in range(84):
        month=11-i
        year=2026
        while month<=0:month+=12;year-=1
        day=date(year,month,12)
        items.append({
            "auction_date":day.isoformat(),
            "security_type":"Bond",
            "security_term":"30-Year",
            "bid_to_cover_ratio":str(round(2.2+0.02*(i%9),3)),
            "cusip":"912810"+f"{i:03d}",
        })
    return json.dumps({"data":items,"meta":{"count":len(items)}}).encode()


class V57AssetTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.config=json.loads((ROOT/"macro/model-config.json").read_text())
        cls.v56=json.loads((ROOT/"data/asset-compass-new-sources-v56.json").read_text())
    def make(self):
        return (parse_gold(gold_raw(),now=NOW),
                parse_treasury(treasury_raw(),now=NOW))
    def build(self, gold=None, bond=None, v56=None):
        g,b=self.make()
        return build(gold if gold is not None else g,
                     bond if bond is not None else b,
                     self.config,v56 if v56 is not None else self.v56,
                     source_hashes={"cftc_gold":"a"*64,"treasury_30y":"b"*64},
                     now=NOW)
    def test_official_gold_contract_and_tuesday_dates(self):
        g,_=self.make()
        self.assertEqual(len(g),135)
        self.assertEqual(g[-1]["date"],"2026-11-17")
        self.assertTrue(all(date.fromisoformat(r["date"]).weekday()==1 for r in g))
    def test_gold_open_interest_net_is_exact_arithmetic(self):
        g,_=self.make()
        r=g[-1]
        self.assertEqual(r["managed_money_net_contracts"],175000-81000)
        self.assertAlmostEqual(r["managed_money_net_pct_open_interest"],
                               100*(175000-81000)/470000,places=5)
    def test_forged_gold_contract_fails(self):
        j=json.loads(gold_raw());j[0]["cftc_contract_market_code"]="088692"
        with self.assertRaisesRegex(ValueError,"COMEX gold"):
            parse_gold(json.dumps(j).encode(),now=NOW)
    def test_gold_invalid_day_or_future_fails(self):
        j=json.loads(gold_raw());j[0]["report_date_as_yyyy_mm_dd"]="2026-11-18"
        with self.assertRaisesRegex(ValueError,"Tuesday"):
            parse_gold(json.dumps(j).encode(),now=NOW)
        j=json.loads(gold_raw());j[0]["report_date_as_yyyy_mm_dd"]="2026-12-01"
        with self.assertRaises(ValueError):
            parse_gold(json.dumps(j).encode(),now=NOW)
    def test_duplicate_gold_week_rejected(self):
        j=json.loads(gold_raw());j[0]["report_date_as_yyyy_mm_dd"]=j[1]["report_date_as_yyyy_mm_dd"]
        with self.assertRaisesRegex(ValueError,"unique"):
            parse_gold(json.dumps(j).encode(),now=NOW)
    def test_gold_bad_contract_positions_rejected(self):
        j=json.loads(gold_raw());j[0]["m_money_positions_long_all"]="9999999999"
        with self.assertRaisesRegex(ValueError,"Out-of-range"):
            parse_gold(json.dumps(j).encode(),now=NOW)
    def test_treasury_30year_completed_only(self):
        _,b=self.make()
        self.assertEqual(len(b),84)
        self.assertEqual(b[-1]["auction_date"],"2026-11-12")
        self.assertEqual(b[-1]["bid_to_cover_ratio"],2.2)
        self.assertTrue(all(r["security_term"]=="30-Year" for r in b))
    def test_treasury_ignored_nonbond_and_incomplete_announcement(self):
        j=json.loads(treasury_raw())
        j["data"].append({"auction_date":"2026-11-20","security_type":"Note",
                         "security_term":"10-Year","bid_to_cover_ratio":"2.42","cusip":"912810999"})
        j["data"].append({"auction_date":"2026-11-20","security_type":"Bond",
                         "security_term":"30-Year","bid_to_cover_ratio":None,"cusip":"912810999"})
        b=parse_treasury(json.dumps(j).encode(),now=NOW)
        self.assertEqual(len(b),84)
    def test_treasury_forged_duplicate_cusip_rejected(self):
        j=json.loads(treasury_raw());j["data"].append(dict(j["data"][0]))
        with self.assertRaisesRegex(ValueError,"Duplicate"):
            parse_treasury(json.dumps(j).encode(),now=NOW)
    def test_treasury_bad_bid_cover_rejected(self):
        j=json.loads(treasury_raw());j["data"][0]["bid_to_cover_ratio"]="0"
        with self.assertRaisesRegex(ValueError,"Out-of-range"):
            parse_treasury(json.dumps(j).encode(),now=NOW)
    def test_treasury_future_auction_rejected(self):
        j=json.loads(treasury_raw());j["data"][0]["auction_date"]="2026-12-15"
        with self.assertRaisesRegex(ValueError,"future"):
            parse_treasury(json.dumps(j).encode(),now=NOW)
    def test_updated_v2_reopening_is_identified_by_remaining_29year_term(self):
        source={"data":[{
            "comp_auction_close_date":"2026-11-12",
            "security_type":"Bond","security_term":"30-Year",
            "bid_to_cover_ratio":"2.36","cusip":"912810AAA",
        },{
            "comp_auction_close_date":"2026-10-08",
            "security_type":"Bond","security_term":"29-Year 10-Month",
            "bid_to_cover_ratio":"2.54","cusip":"912810AAB",
        },{
            "comp_auction_close_date":"2026-10-21",
            "security_type":"Bond","security_term":"19-Year 10-Month",
            "bid_to_cover_ratio":"2.73","cusip":"912810AAC",
        }]}
        b=parse_treasury(json.dumps(source).encode(),now=NOW,minimum=0)
        self.assertEqual(len(b),2)
        self.assertEqual(b[-1]["auction_date"],"2026-11-12")

    def test_legacy_new_data_combination_has_no_double_count(self):
        old=self.make()[1]
        duplicate=dict(old[-1])
        latest={"auction_date":"2026-11-20","cusip":"912810XYZ",
                "bid_to_cover_ratio":2.65,"security_term":"29-Year 11-Month"}
        merged=combine_auction_sources(old,[duplicate,latest])
        self.assertEqual(len(merged),len(old)+1)
        self.assertEqual(merged[-1]["auction_date"],"2026-11-20")

    def test_conflicting_updated_auction_bid_cover_is_refused(self):
        old=self.make()[1]
        duplicate=dict(old[-1])
        duplicate["bid_to_cover_ratio"]+=0.8
        with self.assertRaisesRegex(ValueError,"Inconsistent"):
            combine_auction_sources(old,[duplicate])

    def test_cftc_monday_holiday_observation_preserved_not_forced_tuesday(self):
        raw=json.loads(gold_raw())
        found=[r for r in raw if r["report_date_as_yyyy_mm_dd"].startswith("2025-11-11")]
        self.assertEqual(len(found),1)
        found[0]["report_date_as_yyyy_mm_dd"]="2025-11-10T00:00:00.000"
        accepted=parse_gold(json.dumps(raw).encode(),now=NOW)
        self.assertIn("2025-11-10",[x["date"] for x in accepted])

    def test_auction_time_not_first_publication_certificate(self):
        r=self.build()
        self.assertFalse(r["sources"]["treasury_30y"]["auction_date_is_publication_time"])
        self.assertFalse(r["sources"]["cftc_gold"]["report_date_is_publication_time"])
        self.assertEqual(r["first_publication_vintages_certified"],0)
        self.assertFalse(r["eligible_for_point_in_time_backtest"])
    def test_three_source_covered_assets_other_three_missing(self):
        r=self.build()
        self.assertEqual(set(r["asset_specific_source_available_assets"]),
                         {"gold","us_long_bonds","oil"})
        self.assertEqual(set(r["asset_specific_source_missing_assets"]),
                         {"us_equities","usd","bitcoin"})
        self.assertEqual(len(r["assets"]),6)
        self.assertEqual(r["source_completeness_6_assets"],3)
        self.assertEqual(r["approved_asset_scores"],0)
        for x in r["assets"].values():
            self.assertIsNone(x["score"])
            self.assertFalse(x["verified_asset_specific_model_signal"])
            self.assertFalse(x["historical_calibration_passed"])
            self.assertFalse(x["out_of_sample_validation_passed"])
    def test_realized_source_levels_not_recast_as_price_signals(self):
        r=self.build()
        self.assertEqual(r["sources"]["cftc_gold"]["latest_managed_money_net_contracts"],94000)
        self.assertAlmostEqual(r["sources"]["treasury_30y"]["latest_bid_to_cover_ratio"],2.2)
        self.assertFalse(r["validated_for_live_scoring"])
        for x in r["sources"].values():
            self.assertTrue(math.isfinite(x["research_z_score"]))
            self.assertFalse(x["signal_verified"])
    def test_staleness_cannot_qualify_as_available_asset_specific(self):
        gold,bond=self.make()
        for row in gold:
            row["date"]=(date.fromisoformat(row["date"])-timedelta(weeks=5)).isoformat()
        r=self.build(gold=gold)
        self.assertNotIn("gold",r["asset_specific_source_available_assets"])
        self.assertIsNone(r["assets"]["gold"]["score"])
    def test_v56_without_public_oil_source_rejected(self):
        x=copy.deepcopy(self.v56);x["assets_with_asset_specific_source_observations"]=[]
        with self.assertRaisesRegex(ValueError,"lineage"):
            self.build(v56=x)
    def test_insufficient_auction_history_rejected(self):
        g,b=self.make()
        with self.assertRaisesRegex(ValueError,"reference"):
            self.build(bond=b[:8])
    def test_reject_unapproved_http_sources(self):
        with self.assertRaisesRegex(ValueError,"Unapproved"):
            retrieve("http://api.fiscaldata.treasury.gov/service","api.fiscaldata.treasury.gov")
        self.assertTrue(address(CFTC_ENDPOINT,CFTC_ARGS).startswith("https://publicreporting.cftc.gov"))
        self.assertTrue(address(FISCAL_ENDPOINT,FISCAL_ARGS).startswith("https://api.fiscaldata.treasury.gov"))
    def test_constant_history_does_not_just_invent_research_z(self):
        g,b=self.make()
        for row in g:row["managed_money_net_pct_open_interest"]=20
        for row in b:row["bid_to_cover_ratio"]=2.6
        r=self.build(gold=g,bond=b)
        self.assertIsNone(r["sources"]["cftc_gold"]["research_z_score"])
        self.assertIsNone(r["sources"]["treasury_30y"]["research_z_score"])


if __name__=="__main__":
    unittest.main()
