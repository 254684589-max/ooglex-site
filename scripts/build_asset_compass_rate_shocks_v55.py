#!/usr/bin/env python3
"""V55: genuine Treasury time-series -> rolling standardized rate-shock research.

Historical *latest-revised* levels are not the same as first-available vintages.
Rates-only hypotheses are NEVER verified asset signals or 0–100 model scores.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import statistics
from datetime import date, datetime, timezone
from pathlib import Path

from scripts.validate_asset_compass_treasury_trends_v42 import validate
from scripts.score_macro_assets import score_one, validate_config

ROOT = Path(__file__).resolve().parents[1]
HISTORY = ROOT / "data" / "asset-compass-treasury-history.json"
SNAPSHOT = ROOT / "data" / "asset-scores.json"
CONFIG = ROOT / "macro" / "model-config.json"
OUTPUT = ROOT / "data" / "asset-compass-rate-shocks-v55.json"
RAW_SERIES = ("us10y", "us2y", "real10y")
DERIVED_SERIES = ("breakeven10y", "spread10y2y")
ASSETS = ("gold", "us_equities", "us_long_bonds", "usd", "bitcoin", "oil")
# Directional hypotheses only where a direct valuation mechanism exists.
# Even these are regime-sensitive, NOT estimated sensitivities or predictions.
HYPOTHESES = {
    "gold": ("real10y", -1, "实际利率上行可能提高无息黄金的相对持有成本；未验证市场方向"),
    "us_long_bonds": ("us10y", -1, "名义长期收益率上行可能压低现存长期定息债券价格；未计久期与票息"),
}


def canonical_hash(obj):
    payload = json.dumps(obj, sort_keys=True, ensure_ascii=False,
                         separators=(",", ":"), allow_nan=False).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def calculate(history, snapshot, config, *, now=None,
              horizon=21, baseline_sessions=252, max_stale_days=11):
    now = now or datetime.now(timezone.utc)
    if now.tzinfo is None or now.utcoffset() is None:
        raise ValueError("Timezone-aware UTC clock required")
    today = now.astimezone(timezone.utc).date()
    if not all(type(x) is int and x > 0 for x in
               (horizon, baseline_sessions, max_stale_days)):
        raise ValueError("Invalid shock and baseline window")
    if horizon < 2 or baseline_sessions < 60:
        raise ValueError("Avoid trivial research baseline")
    validate(history, minimum=horizon+baseline_sessions+1, now=now)
    validate_config(config)
    if set(config["weights"]) != set(ASSETS):
        raise ValueError("Unexpected assets")
    if (snapshot.get("schema_version") != 1
            or snapshot.get("scoring", {}).get("calibration_verified") is not False
            or snapshot.get("scoring", {}).get("out_of_sample_verified") is not False
            or not isinstance(snapshot.get("rates"), dict)):
        raise ValueError("Macro snapshot was approved or malformed")
    observations = history["observations"]
    latest = observations[-1]
    stamp = date.fromisoformat(latest["date"])
    snapshot_date = date.fromisoformat(snapshot["observation_date"])
    age = (today-stamp).days
    # Out-of-date history is explicit unavailable research, never a current signal.
    fresh = 0 <= age <= max_stale_days

    # Full-rate input list may be heavily correlated. Derived series are
    # diagnostic only, NEVER independent model votes.
    values = {}
    last_idx = len(observations)-1
    for key in (*RAW_SERIES, *DERIVED_SERIES):
        def rate_change(i):
            return (observations[i][key]-observations[i-horizon][key])*100.0
        shock = rate_change(last_idx)
        baseline = [rate_change(i) for i in range(
            last_idx-baseline_sessions, last_idx)]
        mu = statistics.fmean(baseline)
        sigma = statistics.pstdev(baseline, mu=mu)
        usable = math.isfinite(sigma) and sigma > 1e-10
        z = (shock-mu)/sigma if usable else None
        normalized = math.tanh(z/2) if z is not None else None
        values[key] = {
            "source_series": key,
            "series_type": "derived_algebraic_diagnostic" if key in DERIVED_SERIES
                            else "raw_treasury_yield",
            "observation_date": latest["date"],
            "lookback_start_date": observations[last_idx-horizon]["date"],
            "period_change_basis_points": round(shock, 4),
            "prior_baseline_period_count": len(baseline),
            "baseline_start_date": observations[last_idx-baseline_sessions-horizon]["date"],
            "baseline_end_date": observations[last_idx-1]["date"],
            "baseline_mean_basis_points": round(mu, 6),
            "baseline_std_basis_points": round(sigma, 6),
            "research_z_score": round(z, 6) if z is not None else None,
            "normalized_rate_shock": round(normalized, 6) if normalized is not None else None,
            "status": "research_only_latest_revised_not_pit" if usable
                      else "unavailable_zero_variance",
            "historical_pit_verified": False,
            "qualified_independent_model_signal": False,
        }

    asset_candidates = {}
    for asset in ASSETS:
        if asset in HYPOTHESES:
            key, sign, hypothesis = HYPOTHESES[asset]
            field = values[key]
            viable = fresh and field["normalized_rate_shock"] is not None
            candidate = round(sign * field["normalized_rate_shock"], 6) if viable else None
            entry = ({
                "signal": candidate, "verified": False, "fresh": fresh,
                "observation_date": latest["date"],
                "source_series": key,
                "source_vintage": "latest_revised_not_as_published"
            } if candidate is not None else None)
            state = "uncalibrated_research_hypothesis" if viable else "stale_or_invalid_research"
        else:
            key, sign, hypothesis, candidate, entry = None, None, None, None, None
            state = "direction_unknown_requires_asset_specific_empirical_estimation"
        # Real scorer must reject even the candidate supplied directly:
        # verified=False and no OOS/calibration, never fill 5 missing groups.
        blocked = score_one(asset, {"rates":entry} if entry else {}, config, {})
        if blocked["score"] is not None or blocked["status"] != "unavailable":
            raise ValueError("Unapproved research hypothesis escaped scoring gate")
        asset_candidates[asset] = {
            "status": state, "source_series": key,
            "research_exposure_sign": sign,
            "research_hypothesis": hypothesis,
            "rate_pressure_candidate": candidate,
            "candidate_scoring_entry": entry,
            "eligible_for_live_scoring": False,
            "historical_calibration_passed": False,
            "out_of_sample_validation_passed": False,
            "official_score": None,
            "blocked_by": blocked["blocked_by"],
        }
    return {
        "schema_version": 1,
        "report_type": "asset_compass_v55_real_treasury_rate_shock_research",
        "status": "research_only_latest_revised_rate_shocks",
        "generated_at": now.astimezone(timezone.utc).isoformat(),
        "source": history["source"],
        "source_observation_count": len(observations),
        "source_start_date": history["start_date"],
        "source_end_date": history["end_date"],
        "source_retrieved_at": history["retrieved_at"],
        "source_history_sha256": canonical_hash(history),
        "source_snapshot_sha256": canonical_hash(snapshot),
        "source_snapshot_generated_at": snapshot["generated_at"],
        "snapshot_date_precedes_history": snapshot_date < stamp,
        "model_config_sha256": canonical_hash(config),
        "observed_age_calendar_days": age,
        "latest_history_usable_for_current_research": fresh,
        "shock_horizon_observations": horizon,
        "rolling_reference_shocks": baseline_sessions,
        "shock_features": values,
        "assets": asset_candidates,
        "asset_hypothesis_count": len(HYPOTHESES),
        "historical_first_publication_vintages_verified": False,
        "asset_direction_signs_empirically_calibrated": False,
        "independent_factor_groups_qualified": 0,
        "official_0_to_100_scores_published": 0,
        "validated_for_live_scoring": False,
        "eligible_for_point_in_time_backtest": False,
        "automated_trading_alerts_enabled": False,
        "limitations": [
            "Actual Treasury daily history, but latest-revised and not original PIT release vintages.",
            "21-observation overlapping changes are descriptive shocks, NOT independent backtest returns.",
            "Simple z and tanh transforms are descriptive; signs are predeclared hypotheses NOT measured relationships.",
            "Nominal yield, real yield, breakeven and curve are not independent votes.",
            "Four assets have no justified standalone rate-direction hypothesis.",
            "Missing risk/credit, asset-specific flows, licensed total returns and OOS calibration.",
            "No scores, probability estimates or performance claims are generated.",
        ],
    }


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--history", type=Path, default=HISTORY)
    p.add_argument("--snapshot", type=Path, default=SNAPSHOT)
    p.add_argument("--config", type=Path, default=CONFIG)
    p.add_argument("--output", type=Path, default=OUTPUT)
    a = p.parse_args()
    with a.history.open(encoding="utf-8") as f: history = json.load(f)
    with a.snapshot.open(encoding="utf-8") as f: snapshot = json.load(f)
    with a.config.open(encoding="utf-8") as f: config = json.load(f)
    report = calculate(history, snapshot, config)
    a.output.parent.mkdir(parents=True, exist_ok=True)
    a.output.write_text(json.dumps(report, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    print(json.dumps({
        "status": report["status"],
        "real_rate_observations": report["source_observation_count"],
        "research_z_features": sum(v["research_z_score"] is not None
                                   for v in report["shock_features"].values()),
        "asset_rate_hypotheses": sum(
            a["rate_pressure_candidate"] is not None for a in report["assets"].values()),
        "qualified_asset_scores": report["official_0_to_100_scores_published"],
        "historical_pit_verified": False,
    }, ensure_ascii=False))


if __name__ == "__main__":
    main()
