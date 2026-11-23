"""V60 actual six-asset price metadata vs strict investor total-return/PIT gate."""
import copy
import json
import math
import unittest
from datetime import datetime,timezone
from pathlib import Path
from scripts.audit_asset_compass_returns_v60 import (
    TRACKER,CRYPTO,V59,HISTORY,build_readiness,nav_distribution_kernel,
    _validate_observations,canonical_sha,ASSETS,
)

NOW=datetime(2026,11,24,3,0,tzinfo=timezone.utc)


def issuer_nav_test_rows():
    # Test-only hypothetical NAV and ex-date distributions, never live datasets.
    return [
       {"date":"2026-05-04","nav_unadjusted_per_share":100.0,
        "distribution_ex_date_cash_per_old_share":0.0,
        "split_new_shares_per_old_share":1.0,"trade_cost_bps":0,
        "actions_source_verified":True},
       {"date":"2026-05-05","nav_unadjusted_per_share":99.0,
        "distribution_ex_date_cash_per_old_share":2.0,
        "split_new_shares_per_old_share":1.0,"trade_cost_bps":0,
        "actions_source_verified":True},
       {"date":"2026-05-06","nav_unadjusted_per_share":49.5,
        "distribution_ex_date_cash_per_old_share":0.0,
        "split_new_shares_per_old_share":2.0,"trade_cost_bps":10,
        "actions_source_verified":True},
    ]


class V60ReturnEvidenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.inputs=[json.loads(x.read_text(encoding="utf-8"))
                    for x in (TRACKER,CRYPTO,V59,HISTORY)]

    def run_audit(self,items=None,now=NOW):
        return build_readiness(*(items or self.inputs),now=now)

    def test_actual_archived_price_coverage_is_six_research_series(self):
        r=self.run_audit()
        self.assertEqual(set(r["assets"]),set(ASSETS))
        self.assertEqual(r["market_price_observed_assets"],6)
        self.assertGreaterEqual(r["assets"]["bitcoin"]["actual_observed_prices"],200)
        self.assertGreaterEqual(r["assets"]["gold"]["actual_observed_prices"],170)
        self.assertEqual(r["assets"]["us_equities"]["source_symbol"],"^GSPC")
        self.assertEqual(r["assets"]["us_long_bonds"]["source_symbol"],"TLT")
        self.assertEqual(r["assets"]["bitcoin"]["source_symbol"],"BTC")
        self.assertEqual(r["assets"]["bitcoin"]["source"],"CoinGecko")
        self.assertEqual(r["assets"]["gold"]["source"],"Yahoo Finance")

    def test_real_price_coverage_does_not_approve_investor_returns(self):
        r=self.run_audit()
        self.assertEqual(r["investable_total_return_certified_assets"],0)
        self.assertEqual(r["independent_original_release_vintages_certified"],0)
        self.assertEqual(r["oos_validated_assets"],0)
        self.assertEqual(r["official_0_to_100_asset_scores_published"],0)
        self.assertFalse(r["qualified_for_live_scoring"])
        self.assertFalse(r["archive_initial_observation_date_is_official_release_datetime"])
        self.assertFalse(r["licensed_to_redistribute_research_source_prices"])
        for asset,v in r["assets"].items():
            self.assertIsNone(v["score"])
            self.assertFalse(v["investable_total_return_certified"])
            self.assertFalse(v["historical_first_release_PIT_certified"])
            self.assertFalse(v["source_rights_for_public_total_return_redistribution_verified"])
            self.assertGreater(len(v["missing_return_components"]),2)

    def test_real_archive_mismatches_are_not_hidden(self):
        r=self.run_audit()
        self.assertEqual(r["archived_macro_series"],len(self.inputs[3]["series"]))
        self.assertEqual(r["archived_treasury_source_year_mismatch_rows"],
                         self.inputs[3]["treasury_source_year_mismatch_rows"])
        self.assertGreaterEqual(r["archived_treasury_source_year_mismatch_rows"],1)

    def test_digests_are_traceable_to_actual_source_inputs(self):
        r=self.run_audit()
        for i,key in enumerate(("tracker","crypto","v59","history")):
            self.assertEqual(r["input_sha256"][key],canonical_sha(self.inputs[i]))
            self.assertEqual(len(r["input_sha256"][key]),64)

    def test_coingecko_utc_24x7_not_joined_by_etf_array_index(self):
        r=self.run_audit()
        btc=r["assets"]["bitcoin"]
        eq=r["assets"]["us_equities"]
        self.assertEqual(btc["calendar_type"],"crypto_utc_24x7")
        self.assertEqual(eq["calendar_type"],"market_source_calendar_nullable")
        self.assertNotEqual(btc["first_observed_date"],eq["first_observed_date"])

    def test_future_and_duplicate_quote_dates_rejected(self):
        x=copy.deepcopy(self.inputs)
        x[0]["dates"][-1]="2030-01-01"
        with self.assertRaisesRegex(ValueError,"future"):
            self.run_audit(x)
        x=copy.deepcopy(self.inputs)
        x[1]["history"]["dates"][-1]=x[1]["history"]["dates"][-2]
        with self.assertRaisesRegex(ValueError,"duplicate"):
            self.run_audit(x)

    def test_nonfinite_zero_or_boolean_prices_rejected(self):
        for value in (float("nan"),float("inf"),0,-1,True):
            x=copy.deepcopy(self.inputs)
            x[0]["series"]["TLT"][10]=value
            with self.assertRaisesRegex(ValueError,"Invalid actual price"):
                self.run_audit(x)

    def test_wrong_series_length_or_source_impostor_rejected(self):
        x=copy.deepcopy(self.inputs)
        x[0]["series"]["GC=F"].pop()
        with self.assertRaisesRegex(ValueError,"aligned"):
            self.run_audit(x)
        x=copy.deepcopy(self.inputs)
        x[1]["source"]="Yahoo Finance"
        with self.assertRaisesRegex(ValueError,"Unexpected source"):
            self.run_audit(x)
        x=copy.deepcopy(self.inputs)
        x[1]["history"]["source"]="Yahoo Finance"
        with self.assertRaisesRegex(ValueError,"Bitcoin calendar"):
            self.run_audit(x)

    def test_no_fake_v59_score_or_pit_claim(self):
        x=copy.deepcopy(self.inputs)
        x[2]["research_assets"]["gold"]["official_score"]=85
        with self.assertRaisesRegex(ValueError,"V59"):
            self.run_audit(x)
        x=copy.deepcopy(self.inputs)
        x[3]["eligible_for_point_in_time_backtest"]=True
        with self.assertRaisesRegex(ValueError,"PIT"):
            self.run_audit(x)
        x=copy.deepcopy(self.inputs)
        x[2]["asset_specific_observed_count"]=5
        with self.assertRaisesRegex(ValueError,"V59"):
            self.run_audit(x)

    def test_nav_ex_date_distribution_and_split_avoid_false_losses(self):
        r=nav_distribution_kernel(issuer_nav_test_rows())
        self.assertTrue(r["research_arithmetic_only"])
        self.assertFalse(r["certifies_investable_total_return"])
        self.assertAlmostEqual(r["returns"][0]["gross_reinvested_return"],0.01,12)
        self.assertAlmostEqual(r["returns"][1]["gross_reinvested_return"],0.0,12)
        self.assertAlmostEqual(r["returns"][1]["net_after_stated_trade_cost_return"],-0.001,12)
        self.assertAlmostEqual(r["returns"][-1]["illustrative_cumulative_index"],1.00899,10)

    def test_missing_or_forged_corporate_actions_are_not_implicitly_zero(self):
        for key,value in (
            ("actions_source_verified",False),
            ("nav_unadjusted_per_share",float("nan")),
            ("split_new_shares_per_old_share",0),
            ("distribution_ex_date_cash_per_old_share",-1),
            ("trade_cost_bps",600),
        ):
            items=issuer_nav_test_rows()
            items[-1][key]=value
            with self.assertRaisesRegex(ValueError,"event proof"):
                nav_distribution_kernel(items)
        items=issuer_nav_test_rows()
        del items[-1]["distribution_ex_date_cash_per_old_share"]
        with self.assertRaisesRegex(ValueError,"required"):
            nav_distribution_kernel(items)

    def test_double_counted_or_cannot_be_backdated_event_rejected(self):
        rows=issuer_nav_test_rows()
        rows[2]["date"]=rows[1]["date"]
        with self.assertRaisesRegex(ValueError,"unsorted"):
            nav_distribution_kernel(rows)
        rows=issuer_nav_test_rows()
        rows[0]["trade_cost_bps"]=5
        with self.assertRaisesRegex(ValueError,"Initial purchase cost"):
            nav_distribution_kernel(rows)

    def test_raw_nav_math_is_not_statistical_or_license_certification(self):
        r=nav_distribution_kernel(issuer_nav_test_rows())
        self.assertEqual(r["method"],"unadjusted_NAV_plus_ex_date_cash_and_split_math")
        self.assertEqual(len(r["returns"]),2)
        self.assertIn("does not verify issuer NAV",r["limitation"])


if __name__=="__main__":
    unittest.main()
