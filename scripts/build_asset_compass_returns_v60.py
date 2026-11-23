#!/usr/bin/env python3
"""V60 six-asset total-return ACCOUNTING CONTRACT, not an approved return feed.

Real existing tracker closes are unaudited price proxies. V60 defines accounting
requirements and rejects partial period ledgers in pure functions; it never
invents payouts, rolls, bid/ask, FX carry or historical as-of releases.
No fixture values or unlicensed quotes are added to public artifacts.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from datetime import date, datetime, timezone
from pathlib import Path

from scripts.audit_asset_compass_prices import PROXIES
from scripts.score_macro_assets import score_one, validate_config

ROOT = Path(__file__).resolve().parents[1]
MODEL = ROOT / "macro/model-config.json"
V59 = ROOT / "data/asset-compass-model-gaps-v59.json"
PRICE_AUDIT = ROOT / "data/asset-compass-price-audit.json"
OUTPUT = ROOT / "data/asset-compass-return-readiness-v60.json"

ASSETS = ("gold", "us_equities", "us_long_bonds", "usd", "bitcoin", "oil")
# These are *proposed accounting targets*. No claim that these feeds are
# connected, commercially redistributable or valid for backtesting.
CONTRACTS = {
    "gold": {
        "proposed_vehicle": "physically_backed_gold_etf",
        "example": "GLD",
        "accounting_class": "fund_nav",
        "requires": ["unadjusted_nav_per_share", "distributions_per_share",
                     "split_factor", "management_fees_nav_treatment",
                     "trade_commissions", "bid_ask_slippage"],
        "fallback_existing": "GC=F unadjusted continuous futures price; not roll-adjusted",
        "alternative": "gold_futures_collateralized_roll_account",
    },
    "us_equities": {
        "proposed_vehicle": "sp500_tracking_etf",
        "example": "SPY",
        "accounting_class": "fund_nav",
        "requires": ["unadjusted_nav_per_share", "distributions_per_share",
                     "split_factor", "management_fees_nav_treatment",
                     "trade_commissions", "bid_ask_slippage"],
        "fallback_existing": "^GSPC price-only S&P 500 index; excludes dividends",
    },
    "us_long_bonds": {
        "proposed_vehicle": "long_treasury_etf",
        "example": "TLT",
        "accounting_class": "fund_nav",
        "requires": ["unadjusted_nav_per_share", "distributions_per_share",
                     "split_factor", "management_fees_nav_treatment",
                     "trade_commissions", "bid_ask_slippage"],
        "fallback_existing": "TLT unadjusted close; missing coupon distributions",
    },
    "usd": {
        "proposed_vehicle": "usd_cash_vs_explicit_foreign_currency_basket",
        "example": "USD foreign exchange basket with declared funding",
        "accounting_class": "fx_funded",
        "requires": ["base_currency", "quote_currency", "opening_fx_rate",
                     "closing_fx_rate", "usd_interest_income", "foreign_funding_cost",
                     "trade_commissions", "bid_ask_slippage"],
        "fallback_existing": "DX-Y.NYB index level / FRB H10 nominal index; not FX carry",
        "note": "A dollar index level is not investable total return; basket and financing must be fixed ex ante.",
    },
    "bitcoin": {
        "proposed_vehicle": "spot_btc_custody_account",
        "example": "BTC spot; declared custody",
        "accounting_class": "cash_asset",
        "requires": ["btc_spot_reference", "units_held", "custody_fees",
                     "trade_commissions", "bid_ask_slippage",
                     "funding_cost", "fork_airdrop_treatment"],
        "fallback_existing": "BTC-USD / CoinGecko spot price; excludes investor costs",
    },
    "oil": {
        "proposed_vehicle": "collateralized_wti_futures_roll_account",
        "example": "front-WTI with documented roll schedule",
        "accounting_class": "futures_collateral",
        "requires": ["dated_contract_identifiers", "contract_multiplier",
                     "settlement_prices", "signed_contract_quantities",
                     "realized_roll_pnl", "unrealized_mark_pnl",
                     "cash_collateral_interest", "trade_commissions",
                     "bid_ask_slippage", "margin_and_financing"],
        "fallback_existing": "CL=F continuous price; no contract roll return",
    },
}


def sha(payload):
    return hashlib.sha256(json.dumps(payload, ensure_ascii=False, sort_keys=True,
        separators=(",", ":"), allow_nan=False).encode()).hexdigest()


def _money(v, name, *, positive=False, nonnegative=False):
    if type(v) not in (int, float) or not math.isfinite(v):
        raise ValueError("Invalid finite value: " + name)
    if positive and v <= 0:
        raise ValueError("Expected positive: " + name)
    if nonnegative and v < 0:
        raise ValueError("Expected nonnegative: " + name)
    return float(v)


def _dates(row):
    start = date.fromisoformat(row["start_date"])
    end = date.fromisoformat(row["end_date"])
    if not start < end or end > datetime.now(timezone.utc).date():
        raise ValueError("Invalid accounting period dates")
    return start, end


def reconcile_fund_period(row):
    """One unadjusted ETF/NAV share held through the period, with split-adjusted shares.

    Payouts must be cash amounts, not silently embedded adjusted prices.
    This is arithmetic for a fixture/account statement, not a data feed.
    """
    _dates(row)
    start = _money(row["opening_nav_per_share"], "opening_nav_per_share", positive=True)
    end = _money(row["closing_nav_per_share"], "closing_nav_per_share", positive=True)
    shares_per_old_share = _money(row["split_factor"], "split_factor", positive=True)
    distribution = _money(row["distributions_per_original_share"],
                          "distributions_per_original_share", nonnegative=True)
    costs = sum(_money(row[k], k, nonnegative=True)
                for k in ("commissions_per_original_share", "slippage_per_original_share"))
    gross = (end * shares_per_old_share + distribution) / start - 1
    net = (end * shares_per_old_share + distribution - costs) / start - 1
    if net < -1:
        raise ValueError("Net fund return below -100% impossible without leverage")
    return {"gross_period_return": round(gross, 12),
            "net_period_return": round(net, 12),
            "capital_return": round(end * shares_per_old_share / start - 1, 12),
            "cash_distribution_return": round(distribution / start, 12),
            "cost_drag_return": round(costs / start, 12),
            "period_end": row["end_date"], "model_qualified": False}


def reconcile_cash_asset_period(row):
    """Unlevered BTC spot account with explicitly allocated custody and trading costs."""
    _dates(row)
    units = _money(row["opening_units"], "opening_units", positive=True)
    start = _money(row["opening_spot_price_usd"], "opening_spot_price_usd", positive=True)
    end = _money(row["closing_spot_price_usd"], "closing_spot_price_usd", positive=True)
    if _money(row["closing_units"], "closing_units", positive=True) != units:
        raise ValueError("External flows/position changes require separate return attribution")
    cost = sum(_money(row[k], k, nonnegative=True) for k in
               ("custody_fee_usd", "commission_usd", "slippage_usd", "funding_cost_usd"))
    start_wealth = units * start
    net = (units * end - cost) / start_wealth - 1
    if net < -1:
        raise ValueError("Net unlevered spot return below -100%")
    return {"gross_period_return": round(end / start - 1, 12),
            "net_period_return": round(net, 12),
            "cost_drag_return": round(cost / start_wealth, 12),
            "period_end": row["end_date"], "model_qualified": False}


def reconcile_fx_period(row):
    """One declared foreign-basket funding period in USD numeraire.

    Opening/closing FX are explicitly USD per 1 foreign unit, so a USD long
    versus foreign is (opening_rate/closing_rate - 1) before carry.
    """
    _dates(row)
    if row.get("base_currency") != "USD" or row.get("quote_currency") in (None, "", "USD"):
        raise ValueError("USD numeraire / non-USD funding currency required")
    start = _money(row["opening_usd_per_foreign"], "opening_usd_per_foreign", positive=True)
    end = _money(row["closing_usd_per_foreign"], "closing_usd_per_foreign", positive=True)
    dollar_interest = _money(row["usd_interest_rate_period"], "usd_interest_rate_period")
    foreign_rate = _money(row["foreign_borrow_rate_period"], "foreign_borrow_rate_period")
    costs = sum(_money(row[k], k, nonnegative=True)
                for k in ("commissions_fraction", "slippage_fraction"))
    # 1 USD invested at end of period, less foreign funding in the original
    # foreign unit amount. Borrow 1/start foreign units and repay with interest.
    gross = (1 + dollar_interest) - (end / start) * (1 + foreign_rate)
    net = gross - costs
    return {"gross_period_return": round(gross, 12),
            "net_period_return": round(net, 12),
            "cost_drag_return": round(costs, 12),
            "period_end": row["end_date"], "model_qualified": False}


def reconcile_futures_period(row):
    """Collateralized futures account: explicit mark and realized roll cash P&L.

    No continuous price divided by previous price or hidden contract multiplier.
    Enforces no external capital deposits/withdrawals during the period.
    """
    _dates(row)
    opening = _money(row["opening_cash_collateral_usd"], "opening_cash_collateral_usd", positive=True)
    realized = _money(row["realized_contract_pnl_usd"], "realized_contract_pnl_usd")
    roll = _money(row["realized_roll_pnl_usd"], "realized_roll_pnl_usd")
    unreal = _money(row["unrealized_mark_pnl_usd"], "unrealized_mark_pnl_usd")
    interest = _money(row["cash_collateral_interest_usd"], "cash_collateral_interest_usd")
    fees = sum(_money(row[k], k, nonnegative=True) for k in
               ("commission_usd", "slippage_usd", "financing_cost_usd"))
    gross = (realized + roll + unreal + interest) / opening
    net = (realized + roll + unreal + interest - fees) / opening
    closing = _money(row["closing_cash_equity_usd"], "closing_cash_equity_usd", positive=True)
    expected = opening * (1 + net)
    if abs(closing - expected) > max(1e-5, 1e-8 * opening):
        raise ValueError("Unreconciled futures cash equity / roll / mark-to-market")
    return {"gross_period_return": round(gross, 12),
            "net_period_return": round(net, 12),
            "cost_drag_return": round(fees / opening, 12),
            "period_end": row["end_date"], "model_qualified": False}


RECONCILERS = {
    "fund_nav": reconcile_fund_period,
    "cash_asset": reconcile_cash_asset_period,
    "fx_funded": reconcile_fx_period,
    "futures_collateral": reconcile_futures_period,
}


def audit_submission(asset, submission):
    """No external untrusted manifest can self-award verified total returns."""
    if asset not in CONTRACTS or not isinstance(submission, dict):
        raise ValueError("Unknown asset/submission")
    schema = CONTRACTS[asset]["accounting_class"]
    if submission.get("accounting_class") != schema:
        raise ValueError("Wrong asset accounting convention")
    if submission.get("claims_total_return_certified") is True:
        raise ValueError("Unsigned total-return qualification prohibited")
    periods = submission.get("periods")
    if not isinstance(periods, list) or len(periods) < 2:
        raise ValueError("Insufficient independently reconciled periods")
    results = []
    last_end = ""
    for row in periods:
        if row["start_date"] < last_end:
            raise ValueError("Overlapping accounting windows")
        check = RECONCILERS[schema](row)
        if row["end_date"] <= last_end:
            raise ValueError("Non-increasing account dates")
        last_end = row["end_date"]
        results.append(check)
    # Unlicensed or unverified cases remain private; this output contains no
    # raw quote, custody identity, position size or copyrighted input history.
    return {"asset_id": asset, "status": "arithmetic_reconciled_research_only",
            "accounting_class": schema, "period_count": len(results),
            "results": results, "independent_source_verified": False,
            "public_redistribution_licensed": False,
            "point_in_time_verified": False,
            "investable_total_return_certified": False,
            "qualified_for_scoring": False}


def build_readiness(v59, model, price=None, *, now=None):
    now = now or datetime.now(timezone.utc)
    if now.tzinfo is None or now.utcoffset() is None:
        raise ValueError("Clock must be timezone-aware")
    cfg = validate_config(model)
    if set(cfg["weights"]) != set(ASSETS):
        raise ValueError("Asset identities no longer match scoring config")
    if (v59.get("report_type") != "asset_compass_v59_two_missing_asset_research_provenance" or
        set(v59.get("research_assets", {})) != set(ASSETS) or
        v59.get("official_0_to_100_scores_published") != 0 or
        v59.get("qualified_for_live_scoring") is not False or
        v59.get("audited_asset_total_return_count") != 0 or
        v59.get("oos_validated_assets") != 0 or
        v59.get("historical_first_release_certified_source_count") != 0 or
        any(r["official_score"] is not None for r in v59["research_assets"].values())):
        raise ValueError("Upstream V59 score or historical-return lock invalid")
    if price is not None and (price.get("report_type") != "price_coverage_audit" or
                             price.get("validated_for_live_scoring") is not False or
                             set(price.get("assets", {})) != set(ASSETS)):
        raise ValueError("Price-only proxy source audit invalid")
    rows = {}
    for asset in ASSETS:
        blocked = score_one(asset, {}, cfg, {})
        if blocked["score"] is not None or blocked["status"] != "unavailable":
            raise ValueError("Model score unexpectedly unlocked")
        p = (price or {}).get("assets", {}).get(asset, {})
        if p.get("eligible_for_return_backtest") is True or p.get("total_return_series") is True:
            raise ValueError("An unlicensed price-only proxy self-promoted to total return")
        rows[asset] = {
            **CONTRACTS[asset],
            "asset_id": asset,
            "existing_price_proxy": PROXIES[asset]["symbol"],
            "existing_price_observations": p.get("observation_count", 0),
            "existing_source_is_price_only": True,
            "real_accounting_ledger_connected": False,
            "real_dividends_coupons_or_rolls_certified": False,
            "public_redistribution_licensed": False,
            "historical_point_in_time_verified": False,
            "investable_total_return_certified": False,
            "oos_calibrated": False,
            "official_score": None,
            "blocked_by": blocked["blocked_by"],
        }
    return {
        "schema_version": 1, "report_type": "asset_compass_v60_investable_return_accounting_readiness",
        "generated_at": now.astimezone(timezone.utc).isoformat(),
        "source_v59_sha256": sha(v59), "source_model_sha256": sha(model),
        "price_audit_sha256": sha(price) if price is not None else None,
        "asset_specific_research_coverage": v59["asset_specific_observed_count"],
        "accounting_contracts_defined": 6, "actual_investable_ledgers_certified": 0,
        "audited_asset_total_return_count": 0,
        "historical_first_release_certified_source_count": 0,
        "qualified_independent_factor_groups": 0,
        "oos_validated_assets": 0, "official_0_to_100_scores_published": 0,
        "validated_for_live_scoring": False,
        "status": "accounting_requirements_only_no_authorized_returns",
        "assets": rows,
        "limitations": [
            "Six independently specified accounting conventions are not six live, audited returns.",
            "Price series, ETF closes, USD spot indices and futures continuous quotes cannot be relabeled total return.",
            "No historical point-in-time macro vintage, OOS result, redistribution license or live 0–100 score is certified.",
        ],
    }


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--output", type=Path, default=OUTPUT)
    args = p.parse_args()
    v59 = json.loads(V59.read_text(encoding="utf-8"))
    model = json.loads(MODEL.read_text(encoding="utf-8"))
    price = json.loads(PRICE_AUDIT.read_text(encoding="utf-8")) if PRICE_AUDIT.is_file() else None
    report = build_readiness(v59, model, price)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2, allow_nan=False) + "\n",
                           encoding="utf-8")
    print(json.dumps({"accounting_contracts_defined": 6,
                      "actual_investable_ledgers_certified": 0,
                      "approved_scores": 0}, ensure_ascii=False))


if __name__ == "__main__":
    main()
