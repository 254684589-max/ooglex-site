"""V60 arithmetic and provenance tests; numbers are isolated synthetic fixtures only."""
import copy
import json
import math
import unittest
from datetime import datetime, timezone
from pathlib import Path

from scripts.build_asset_compass_returns_v60 import (
    ASSETS, CONTRACTS, MODEL, V59, PRICE_AUDIT,
    audit_submission, build_readiness, reconcile_fund_period,
    reconcile_cash_asset_period, reconcile_fx_period,
    reconcile_futures_period,
)

NOW = datetime(2026, 11, 24, 1, tzinfo=timezone.utc)


def dates():
    return {"start_date": "2026-10-01", "end_date": "2026-10-02"}


def fund():
    return {**dates(), "opening_nav_per_share": 100, "closing_nav_per_share": 101,
            "split_factor": 1, "distributions_per_original_share": 2,
            "commissions_per_original_share": .3, "slippage_per_original_share": .1}


def spot():
    return {**dates(), "opening_units": 2, "closing_units": 2,
            "opening_spot_price_usd": 100, "closing_spot_price_usd": 105,
            "custody_fee_usd": .2, "commission_usd": .1,
            "slippage_usd": .1, "funding_cost_usd": 0}


def fx():
    return {**dates(), "base_currency": "USD", "quote_currency": "EUR",
            "opening_usd_per_foreign": 1.2, "closing_usd_per_foreign": 1.1,
            "usd_interest_rate_period": .002, "foreign_borrow_rate_period": .001,
            "commissions_fraction": .0003, "slippage_fraction": .0002}


def future():
    return {**dates(), "opening_cash_collateral_usd": 1000,
            "realized_contract_pnl_usd": 40, "realized_roll_pnl_usd": -5,
            "unrealized_mark_pnl_usd": 2, "cash_collateral_interest_usd": 1,
            "commission_usd": 3, "slippage_usd": 2,
            "financing_cost_usd": 1, "closing_cash_equity_usd": 1032}


def two_periods(factory):
    first = factory()
    second = copy.deepcopy(first)
    second["start_date"] = "2026-10-02"
    second["end_date"] = "2026-10-03"
    return [first, second]


class V60Tests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.v59 = json.loads(V59.read_text(encoding="utf-8"))
        cls.model = json.loads(MODEL.read_text(encoding="utf-8"))
        cls.price = (json.loads(PRICE_AUDIT.read_text(encoding="utf-8"))
                     if PRICE_AUDIT.exists() else None)

    def test_all_six_conventions_without_any_score_or_approval(self):
        out = build_readiness(self.v59, self.model, self.price, now=NOW)
        self.assertEqual(out["accounting_contracts_defined"], 6)
        self.assertEqual(set(out["assets"]), set(ASSETS))
        self.assertEqual(out["actual_investable_ledgers_certified"], 0)
        self.assertEqual(out["audited_asset_total_return_count"], 0)
        self.assertEqual(out["qualified_independent_factor_groups"], 0)
        self.assertEqual(out["historical_first_release_certified_source_count"], 0)
        self.assertEqual(out["oos_validated_assets"], 0)
        self.assertEqual(out["official_0_to_100_scores_published"], 0)
        self.assertFalse(out["validated_for_live_scoring"])
        for entry in out["assets"].values():
            self.assertIsNone(entry["official_score"])
            self.assertFalse(entry["investable_total_return_certified"])
            self.assertFalse(entry["real_accounting_ledger_connected"])
            self.assertFalse(entry["historical_point_in_time_verified"])

    def test_equity_spy_and_tlt_use_payout_accounting_not_index_close(self):
        r = reconcile_fund_period(fund())
        self.assertAlmostEqual(r["gross_period_return"], .03)
        self.assertAlmostEqual(r["net_period_return"], .026)
        self.assertAlmostEqual(r["capital_return"], .01)
        self.assertAlmostEqual(r["cash_distribution_return"], .02)
        self.assertAlmostEqual(r["cost_drag_return"], .004)
        self.assertFalse(r["model_qualified"])
        for asset in ("gold", "us_equities", "us_long_bonds"):
            self.assertEqual(CONTRACTS[asset]["accounting_class"], "fund_nav")

    def test_split_adjustment_not_double_counted(self):
        row = fund()
        row.update(opening_nav_per_share=100, closing_nav_per_share=50,
                   split_factor=2, distributions_per_original_share=0,
                   commissions_per_original_share=0, slippage_per_original_share=0)
        self.assertEqual(reconcile_fund_period(row)["net_period_return"], 0)

    def test_invalid_nav_payout_or_missing_fee_cannot_be_imputed(self):
        for key, value in (("opening_nav_per_share", 0),
                           ("closing_nav_per_share", float("nan")),
                           ("distributions_per_original_share", -1),
                           ("slippage_per_original_share", None)):
            row = fund(); row[key] = value
            with self.assertRaises((ValueError, TypeError, KeyError)):
                reconcile_fund_period(row)
        row = fund(); del row["split_factor"]
        with self.assertRaises(KeyError):
            reconcile_fund_period(row)

    def test_spot_btc_custody_and_slippage_required(self):
        r = reconcile_cash_asset_period(spot())
        self.assertAlmostEqual(r["gross_period_return"], .05)
        self.assertAlmostEqual(r["net_period_return"], .048)
        self.assertAlmostEqual(r["cost_drag_return"], .002)
        self.assertFalse(r["model_qualified"])

    def test_unexplained_btc_position_change_or_negative_fee_refused(self):
        row = spot();row["closing_units"] = 3
        with self.assertRaisesRegex(ValueError, "position"):
            reconcile_cash_asset_period(row)
        row = spot();row["custody_fee_usd"] = -1
        with self.assertRaises(ValueError):
            reconcile_cash_asset_period(row)

    def test_fx_explicit_rate_orientation_and_carry(self):
        r = reconcile_fx_period(fx())
        expected = (1 + .002) - (1.1/1.2) * (1 + .001) - .0005
        self.assertAlmostEqual(r["net_period_return"], expected, places=10)
        self.assertFalse(r["model_qualified"])

    def test_fx_undocumented_currency_and_spot_only_not_accepted(self):
        row = fx();row["base_currency"] = "EUR"
        with self.assertRaises(ValueError):
            reconcile_fx_period(row)
        row = fx();del row["foreign_borrow_rate_period"]
        with self.assertRaises(KeyError):
            reconcile_fx_period(row)

    def test_futures_realized_roll_collateral_and_mark_must_reconcile(self):
        r = reconcile_futures_period(future())
        self.assertAlmostEqual(r["gross_period_return"], .038)
        self.assertAlmostEqual(r["net_period_return"], .032)
        self.assertFalse(r["model_qualified"])

    def test_continuous_futures_price_cannot_fake_roll_account(self):
        f = future()
        f["closing_cash_equity_usd"] = 1037
        with self.assertRaisesRegex(ValueError, "Unreconciled"):
            reconcile_futures_period(f)
        f = future();del f["realized_roll_pnl_usd"]
        with self.assertRaises(KeyError):
            reconcile_futures_period(f)

    def test_arithmetic_reports_are_never_independent_verified(self):
        for asset, factory in (("gold", fund), ("us_equities", fund),
                               ("us_long_bonds", fund), ("usd", fx),
                               ("bitcoin", spot), ("oil", future)):
            proposal = {"accounting_class": CONTRACTS[asset]["accounting_class"],
                        "periods": two_periods(factory)}
            result = audit_submission(asset, proposal)
            self.assertEqual(result["period_count"], 2)
            self.assertFalse(result["investable_total_return_certified"])
            self.assertFalse(result["qualified_for_scoring"])
            self.assertFalse(result["point_in_time_verified"])
            self.assertFalse(result["public_redistribution_licensed"])

    def test_fake_approval_forged_convention_and_overlap_rejected(self):
        proposal = {"accounting_class": "fund_nav", "periods": two_periods(fund)}
        for tamper in ({"claims_total_return_certified": True},
                       {"accounting_class": "futures_collateral"}):
            x = {**proposal, **tamper}
            with self.assertRaises(ValueError):
                audit_submission("us_equities", x)
        overlap = two_periods(fund)
        overlap[1]["start_date"] = "2026-10-01"
        with self.assertRaisesRegex(ValueError, "Overlapping"):
            audit_submission("us_equities", {"accounting_class": "fund_nav", "periods": overlap})

    def test_insufficient_periods_or_future_not_promoted(self):
        with self.assertRaises(ValueError):
            audit_submission("bitcoin", {"accounting_class": "cash_asset", "periods": [spot()]})
        x = spot();x["end_date"] = "2099-01-01"
        with self.assertRaises(ValueError):
            reconcile_cash_asset_period(x)

    def test_no_score_if_v59_forged_or_price_audit_self_promotes(self):
        v = copy.deepcopy(self.v59)
        v["research_assets"]["bitcoin"]["official_score"] = 70
        with self.assertRaises(ValueError):
            build_readiness(v, self.model, self.price, now=NOW)
        if self.price is not None:
            p = copy.deepcopy(self.price)
            p["assets"]["gold"]["total_return_series"] = True
            with self.assertRaises(ValueError):
                build_readiness(self.v59, self.model, p, now=NOW)

    def test_asset_proxy_names_cannot_masquerade_as_total_returns(self):
        v = build_readiness(self.v59, self.model, self.price, now=NOW)
        self.assertIn("^GSPC", v["assets"]["us_equities"]["fallback_existing"])
        self.assertIn("CL=F", v["assets"]["oil"]["fallback_existing"])
        self.assertIn("carry", v["assets"]["usd"]["fallback_existing"])
        self.assertEqual(v["assets"]["us_long_bonds"]["example"], "TLT")


if __name__ == "__main__":
    unittest.main()
