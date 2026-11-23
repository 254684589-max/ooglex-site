#!/usr/bin/env python3
"""V60 six-asset investable-return and historical publication-vintage gap audit.

Operates on existing, actually archived Ooglex price observations. It NEVER
publishes raw third-party prices, marks unlicensed series investable, infers
dividends from changes in close, or treats historical snapshots as PIT.

Includes a pure NAV cash-distribution/split cost calculation kernel for later
licensed issuer feeds. Mathematical correctness != authorization to use it.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from datetime import date, datetime, timezone
from pathlib import Path

from scripts.audit_asset_compass_prices import PROXIES

ROOT = Path(__file__).resolve().parents[1]
TRACKER = ROOT / "apps/asset-tracker/history.json"
CRYPTO = ROOT / "apps/asset-ranking/crypto.json"
V59 = ROOT / "data/asset-compass-model-gaps-v59.json"
HISTORY = ROOT / "data/asset-compass-history-readiness.json"
OUT = ROOT / "data/asset-compass-return-pit-gaps-v60.json"
ASSETS = ("gold","us_equities","us_long_bonds","usd","bitcoin","oil")
MISSING_CASHFLOWS = {
    "gold": ["identified_futures_contract_by_session","settlement_and_roll_execution",
             "collateral_interest","transaction_and_financing_costs","licensed_total_return_benchmark"],
    "us_equities": ["dividend_reinvestment","split_corporate_actions",
                    "investable_index_or_fund_NAV","trading_costs","per_series_redistribution_rights"],
    "us_long_bonds": ["fund_distribution_ex_dates","split_corporate_actions",
                      "verified_fund_NAV","coupon_reinvestment_inside_NAV",
                      "fund_fees_and_trading_costs"],
    "usd": ["investable_currency_basket_weights","long_and_short_funding_rate",
             "FX_rebalance_and_spread_costs","verified_FX_total_return_proxy"],
    "bitcoin": ["spot_exchange_reference_price_and_clock","custody_and_exchange_costs",
                "USD_settlement_and_transaction_costs","licensed_spot_return_history"],
    "oil": ["identified_WTI_futures_contract_by_session","settlement_and_roll_execution",
            "collateral_interest","transaction_and_financing_costs","licensed_total_return_benchmark"]
}


def _clock(now=None):
    now = now or datetime.now(timezone.utc)
    if now.tzinfo is None or now.utcoffset() is None:
        raise ValueError("Timezone-aware audit clock required")
    return now.astimezone(timezone.utc)


def canonical_sha(data):
    return hashlib.sha256(json.dumps(data, sort_keys=True, ensure_ascii=False,
         separators=(",",":"),allow_nan=False).encode("utf-8")).hexdigest()


def _period(ds):
    if not isinstance(ds,str):
        raise ValueError("Observation date not a string")
    day = date.fromisoformat(ds)
    if ds != day.isoformat():
        raise ValueError("Noncanonical observation date")
    return day


def _validate_observations(days, prices, label, *, today):
    if not isinstance(days,list) or len(days)<30 or len(days)>10000:
        raise ValueError(f"Unusable {label} calendar")
    if not isinstance(prices,list) or len(prices)!=len(days):
        raise ValueError(f"Price series not aligned to calendar: {label}")
    checked = [_period(s) for s in days]
    if checked != sorted(set(checked)) or any(d>today for d in checked):
        raise ValueError(f"Unsorted, duplicate or future observation: {label}")
    valid = []
    for dt,p in zip(checked,prices):
        if p is None:
            continue
        if type(p) not in (int,float) or not math.isfinite(p) or p <= 0:
            raise ValueError(f"Invalid actual price observation: {label}")
        valid.append((dt, float(p)))
    close_to_close = 0
    skipped_calendar_gaps = 0
    for (a,_),(b,_) in zip(valid,valid[1:]):
        delta = (b-a).days
        if 1<=delta<=4:
            close_to_close += 1
        else:
            skipped_calendar_gaps += 1
    return {
        "calendar_rows":len(days),"actual_observed_prices":len(valid),
        "missing_or_null_prices":len(days)-len(valid),
        "actual_price_coverage_percent":round(100*len(valid)/len(days),2),
        "first_observed_date":valid[0][0].isoformat() if valid else None,
        "last_observed_date":valid[-1][0].isoformat() if valid else None,
        "research_only_close_to_close_windows":close_to_close,
        "skipped_long_calendar_gaps":skipped_calendar_gaps,
        "calendar_days_since_last":(today-valid[-1][0]).days if valid else None,
    }


def nav_distribution_kernel(rows, *, max_trade_cost_bps=500):
    """Pure educational daily arithmetic. Caller MUST supply an independently
    reconciled NAV, all ex-date distributions (including explicit ZERO),
    split ratios, and transaction costs. NEVER certifies investable TR.

    NAVs must be UNADJUSTED for share splits, distribution is denominated in
    the previous period's shares, cash is notionally reinvested on ex-date.
    Fund expense drag is already embedded in issuer NAV; do not subtract again.
    Trading cost is charged only on actual trades, explicitly supplied per date.
    """
    if not isinstance(rows,list) or len(rows)<2:
        raise ValueError("NAV and actions need at least two sessions")
    prev_date=None
    prev_nav=None
    index=1.0
    results=[]
    for row in rows:
        if not isinstance(row,dict) or set(row)!={
            "date","nav_unadjusted_per_share","distribution_ex_date_cash_per_old_share",
            "split_new_shares_per_old_share","trade_cost_bps","actions_source_verified"}:
            raise ValueError("NAV, splits, ex-date cash and trade-cost evidence required")
        day=_period(row["date"])
        if prev_date is not None and day<=prev_date:
            raise ValueError("NAV dates unsorted or duplicated")
        nav=row["nav_unadjusted_per_share"]
        distribution=row["distribution_ex_date_cash_per_old_share"]
        split=row["split_new_shares_per_old_share"]
        cost=row["trade_cost_bps"]
        if (any(type(x) not in (int,float) or not math.isfinite(x)
                for x in (nav,distribution,split,cost)) or
            nav<=0 or distribution<0 or split<=0 or
            not 0<=cost<=max_trade_cost_bps or
            row["actions_source_verified"] is not True):
            raise ValueError("Missing/nonfinite NAV, distribution, split, trade or event proof")
        if prev_nav is not None:
            # Previous-share value after share split and ex-date distributions.
            # Prevents share split from appearing as a -50% return.
            gross=(nav*split+distribution)/prev_nav
            if not .01<gross<100:
                raise ValueError("Impossible NAV event-adjusted return factor")
            net=gross*(1-cost/10000)
            index*=net
            results.append({"date":day.isoformat(),
                            "gross_reinvested_return":round(gross-1,12),
                            "net_after_stated_trade_cost_return":round(net-1,12),
                            "illustrative_cumulative_index":round(index,12)})
        elif cost!=0:
            # Initial holding purchased at first mark; inception fees must be
            # documented separately, not hidden as a daily return.
            raise ValueError("Initial purchase cost requires distinct initial cash ledger")
        prev_date,prev_nav=day,nav
    return {"method":"unadjusted_NAV_plus_ex_date_cash_and_split_math",
            "research_arithmetic_only":True,
            "certifies_investable_total_return":False,
            "first_date":rows[0]["date"],"last_date":rows[-1]["date"],
            "returns":results,
            "limitation":"This calculation alone does not verify issuer NAV, event completeness, taxes, execution, currency, security rights or PIT."}


def build_readiness(tracker, crypto, v59, history, *, now=None):
    now=_clock(now)
    today=now.date()
    if (v59.get("report_type")!="asset_compass_v59_two_missing_asset_research_provenance" or
        v59.get("asset_specific_observed_count")!=6 or
        set(v59.get("research_assets",{}))!=set(ASSETS) or
        v59.get("qualified_for_live_scoring") is not False or
        v59.get("official_0_to_100_scores_published")!=0 or
        v59.get("audited_asset_total_return_count")!=0 or
        v59.get("historical_first_release_certified_source_count")!=0 or
        v59.get("oos_validated_assets")!=0 or
        any(v.get("official_score") is not None
            for v in v59["research_assets"].values()) or
        not all(v59.get("source_verification",{}).get(a,{}).get("observed") is True
                for a in ("us_equities","bitcoin"))):
        raise ValueError("V59 original six-source score guard or authenticity is not satisfied")
    if (history.get("report_type")!="asset_compass_history_readiness" or
        history.get("validated_for_live_scoring") is not False or
        history.get("eligible_for_point_in_time_backtest") is not False or
        not isinstance(history.get("series"),dict) or
        not isinstance(history.get("treasury_source_year_mismatch_rows"),int)):
        raise ValueError("PIT archive status contract invalid")
    if tracker.get("source")!="Yahoo Finance" or crypto.get("source")!="CoinGecko":
        raise ValueError("Unexpected source rights and quote conventions")
    if tracker.get("frequency")!="daily" or crypto.get("frequency")!="daily":
        raise ValueError("Mismatched price source cadence")
    if set(PROXIES)!=set(ASSETS):
        raise ValueError("Changed six-asset price symbol registry")
    if _period(tracker["asOf"])>today or _period(crypto["asOf"])>today:
        raise ValueError("Future source asOf")
    rows={}
    for asset in ASSETS:
        if asset=="bitcoin":
            h=crypto.get("history") or {}
            if h.get("source")!="CoinGecko":
                raise ValueError("Bitcoin calendar cannot be substituted")
            dates=h.get("dates")
            prices=(h.get("series") or {}).get("BTC")
            kind="bitcoin_usd_spot"
            source="CoinGecko"
            symbol="BTC"
        else:
            dates=tracker.get("dates")
            proxy=PROXIES[asset]
            symbol=proxy["symbol"]
            prices=(tracker.get("series") or {}).get(symbol)
            kind=proxy["kind"]
            source="Yahoo Finance"
        checked=_validate_observations(dates,prices,symbol,today=today)
        rows[asset]={
            "source":source,"source_symbol":symbol,"proxy_type":kind,
            "price_observation_only":True,
            "investable_total_return_certified":False,
            "historical_first_release_PIT_certified":False,
            "independent_walkforward_OOS_certified":False,
            "score":None,
            "missing_return_components":MISSING_CASHFLOWS[asset],
            "source_rights_for_public_total_return_redistribution_verified":False,
            "source_currency_assumption":"USD per quoted instrument; execution/basket FX unverified",
            "calendar_type":"crypto_utc_24x7" if asset=="bitcoin" else "market_source_calendar_nullable",
            "status":"source_prices_present_total_return_unqualified" if checked["actual_observed_prices"] else
                     "no_actual_price_observation",
            **checked,
        }
    return {
        "schema_version":1,
        "report_type":"asset_compass_v60_real_price_vs_investable_total_return_gap_audit",
        "generated_at":now.isoformat(),
        "status":"research_observation_coverage_only_no_authorized_returns",
        "input_sha256":{"tracker":canonical_sha(tracker),
                        "crypto":canonical_sha(crypto),
                        "v59":canonical_sha(v59),
                        "history":canonical_sha(history)},
        "original_sources":{"tracker":tracker.get("source"),
                            "tracker_as_of":tracker.get("asOf"),
                            "crypto":crypto.get("source"),
                            "crypto_as_of":crypto.get("asOf")},
        "asset_specific_research_source_count":6,
        "market_price_observed_assets":sum(r["actual_observed_prices"]>0 for r in rows.values()),
        "investable_total_return_certified_assets":0,
        "independent_original_release_vintages_certified":0,
        "oos_validated_assets":0,
        "approved_independent_factor_groups":0,
        "official_0_to_100_asset_scores_published":0,
        "archived_macro_series":len(history["series"]),
        "archived_treasury_source_year_mismatch_rows":history["treasury_source_year_mismatch_rows"],
        "archive_initial_observation_date_is_official_release_datetime":False,
        "research_price_diagnostics_are_total_return":False,
        "licensed_to_redistribute_research_source_prices":False,
        "qualified_for_live_scoring":False,
        "automated_investment_actions_enabled":False,
        "assets":rows,
        "limitations":[
          "Existing Yahoo Finance and CoinGecko price coverage is audited without reposting the underlying daily quotes.",
          "GC=F and CL=F continuous futures are not roll-aware investable P&L or collateral total return.",
          "SP500 index excludes cash dividends, TLT raw close excludes distributions, Dollar Index excludes currency-basket carry.",
          "BTC CoinGecko spot uses a separate UTC calendar and lacks reconciled exchange/custody and rights evidence.",
          "Ooglex first-seen archive timestamps do not provide historical first-publication vintages or corporate-action histories.",
          "The NAV ex-date/split calculation helper accepts verified inputs in tests only; no licensed production NAV or distribution ledger is supplied.",
          "No assets may publish 0-100 scores, trade signals or backtest performance from this report."
        ]
    }


def main():
    p=argparse.ArgumentParser()
    p.add_argument("--tracker",type=Path,default=TRACKER)
    p.add_argument("--crypto",type=Path,default=CRYPTO)
    p.add_argument("--v59",type=Path,default=V59)
    p.add_argument("--history",type=Path,default=HISTORY)
    p.add_argument("--output",type=Path,default=OUT)
    args=p.parse_args()
    inputs=[json.loads(x.read_text(encoding="utf-8"))
            for x in (args.tracker,args.crypto,args.v59,args.history)]
    result=build_readiness(*inputs)
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(result,ensure_ascii=False,indent=2,
                            allow_nan=False)+"\n",encoding="utf-8")
    print(json.dumps({"observed_real_price_assets":result["market_price_observed_assets"],
                      "verified_investable_total_returns":0,
                      "pit":0,"official_scores":0,
                      "mismatch_archived_treasury_rows":result["archived_treasury_source_year_mismatch_rows"]},
                     ensure_ascii=False))


if __name__=="__main__":
    main()
