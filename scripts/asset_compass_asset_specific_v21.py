#!/usr/bin/env python3
"""V21 six-asset-specific evidence gate (private, research only).

This is an instrument candidate registry and strict as-of validator, NOT a data
collector, factor score, prediction, redistribution approval, or position advice.
"""
import argparse
import json
import math
from collections import Counter
from datetime import date, datetime, timezone
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ("gold", "us_equities", "us_long_bonds", "usd", "bitcoin", "oil")

# Candidate concepts and institutional source hosts, not certified data feeds.
# URLs must point to source-specific evidence supplied by a licensed operator.
CATALOG = {
    "gold_cftc_position": ("gold", "positioning", "contracts", "cftc.gov"),
    "gold_etf_holdings": ("gold", "flow_proxy", "tonnes", "gold.org"),
    "equity_13f_holdings": ("us_equities", "holdings", "usd", "sec.gov"),
    "equity_issuer_earnings": ("us_equities", "valuation_input", "usd", "sec.gov"),
    "treasury_auction_bid_cover": ("us_long_bonds", "demand", "ratio", "treasurydirect.gov"),
    "treasury_auction_indirect": ("us_long_bonds", "demand", "percent", "treasurydirect.gov"),
    "usd_cftc_position": ("usd", "positioning", "contracts", "cftc.gov"),
    "usd_bis_effective_index": ("usd", "valuation_proxy", "index", "bis.org"),
    "btc_chain_supply": ("bitcoin", "onchain", "btc", "blockchain.com"),
    "btc_etf_flow": ("bitcoin", "flow", "usd", "sec.gov"),
    "oil_eia_crude_stocks": ("oil", "inventory", "thousand_barrels", "eia.gov"),
    "oil_cftc_wti_position": ("oil", "positioning", "contracts", "cftc.gov"),
}
# Several entries are deliberately marked proxies. A SEC filing cannot alone
# supply a verified aggregate ETF net-flow series; an on-chain website does not
# itself establish a verified exchange balance series.
LIMITATIONS = {
    "gold_etf_holdings": "licensed_or_derived_series_required",
    "equity_13f_holdings": "quarterly_delayed_disclosures_not_live_flows",
    "equity_issuer_earnings": "issuer_filing_not_market_index_valuation",
    "treasury_auction_bid_cover": "auction_specific_not_total_bond_flow",
    "treasury_auction_indirect": "auction_specific_not_total_bond_flow",
    "usd_bis_effective_index": "exchange_rate_index_not_position_or_intrinsic_value",
    "btc_chain_supply": "blockchain_estimate_not_exchange_balance",
    "btc_etf_flow": "sec_filings_do_not_directly_prove_daily_etf_flow",
}
REQUIRED = ("indicator_id", "asset_id", "observation_date", "available_at",
            "value", "unit", "source_url", "source_release_id",
            "rights_evidence", "research_use_approved")


def aware_time(s):
    if not isinstance(s, str):
        raise ValueError("missing timestamp")
    try:
        value = datetime.fromisoformat(s.replace("Z", "+00:00"))
    except ValueError as exc:
        raise ValueError("timestamp must be ISO8601") from exc
    if value.tzinfo is None or value.utcoffset() is None:
        raise ValueError("timestamp must specify offset")
    return value.astimezone(timezone.utc)


def source_host(url, expected):
    if not isinstance(url, str):
        return False
    try:
        parsed = urlparse(url)
        host = (parsed.hostname or "").lower()
        return (parsed.scheme == "https" and
                (host == expected or host.endswith("." + expected)) and
                parsed.username is None and parsed.password is None and
                bool(parsed.path.strip("/")))
    except ValueError:
        return False


def evaluate(rows, asof):
    """Reject an entire dataset with malformed provenance; never silently omit it."""
    decision = aware_time(asof)
    if decision > datetime.now(timezone.utc):
        raise ValueError("decision timestamp cannot be in future")
    if not isinstance(rows, list):
        raise ValueError("expected JSON list of observations")
    out = []
    seen = set()
    for row in rows:
        if not isinstance(row, dict) or any(k not in row for k in REQUIRED):
            raise ValueError("missing evidence fields")
        key = row["indicator_id"]
        if key not in CATALOG:
            raise ValueError("unknown indicator")
        asset, category, unit, host = CATALOG[key]
        if row["asset_id"] != asset or row["unit"] != unit:
            raise ValueError("asset or units inconsistent with indicator")
        if row["research_use_approved"] is not True:
            raise PermissionError("private research approval not documented")
        if not isinstance(row["rights_evidence"], str) or not row["rights_evidence"].strip():
            raise PermissionError("rights evidence required")
        if not isinstance(row["source_release_id"], str) or not row["source_release_id"].strip():
            raise ValueError("authentic release identifier required")
        if not source_host(row["source_url"], host):
            raise ValueError("untrusted or malformed source link")
        try:
            obs = date.fromisoformat(row["observation_date"])
        except (TypeError, ValueError) as exc:
            raise ValueError("invalid observation date") from exc
        published = aware_time(row["available_at"])
        if published.date() < obs:
            raise ValueError("release earlier than observation")
        if published > datetime.now(timezone.utc):
            raise ValueError("future release timestamp")
        value = row["value"]
        if type(value) not in (int, float) or not math.isfinite(value):
            raise ValueError("finite numerical value required")
        # Zero and negative values may be legitimate for net flows/positions.
        vintage_key = (key, obs.isoformat(), published.isoformat(), row["source_release_id"])
        if vintage_key in seen:
            raise ValueError("duplicate vintage key")
        seen.add(vintage_key)
        if published <= decision:
            out.append((asset, key, obs, published))
    counts = Counter(x[0] for x in out)
    return {
        "schema_version": 1,
        "report_type": "asset_compass_asset_specific_evidence_audit",
        "decision_at": decision.isoformat(),
        "candidate_indicator_count": len(CATALOG),
        "asof_eligible_vintage_rows": len(out),
        "assets": {
            asset: {
                "asof_eligible_rows": counts[asset],
                "status": "research_evidence_present_not_calibrated" if counts[asset]
                          else "missing_verified_evidence",
                "asset_specific_factor_signal": None,
                "contribution": None,
            } for asset in ASSETS
        },
        "rights_verification_is_operator_attestation_only": True,
        "validated_for_live_scoring": False,
        "factor_signals_calibrated": False,
        "out_of_sample_passed": False,
        "public_redistribution_authorized": False,
        "forecast_available": False,
    }


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--input", type=Path, required=True,
                   help="private JSON list with authentic source evidence")
    p.add_argument("--asof", required=True)
    args = p.parse_args()
    if args.input.resolve().is_relative_to(ROOT.resolve()):
        raise ValueError("restricted evidence must be stored outside repository")
    if not args.input.is_file():
        raise FileNotFoundError("real private evidence file is required")
    rows = json.loads(args.input.read_text(encoding="utf-8"))
    print(json.dumps(evaluate(rows, args.asof), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
