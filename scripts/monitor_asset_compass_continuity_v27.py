#!/usr/bin/env python3
"""V27 operational observation continuity monitor (not market-data validation).

Only compares already archived first-seen records; does not synthesize
publication timestamps, download data, or infer real historical vintages.
"""
import argparse
import json
from collections import defaultdict
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

from scripts.archive_asset_compass_observations import LEDGER, load, utc
from scripts.check_asset_compass_archive_continuity_v25 import verify_ledger
from scripts.check_asset_compass_history_readiness import REQUIRED_SERIES, report

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "data" / "asset-compass-continuity-v27.json"

# Operational heuristics, NOT official release schedules. Holidays can delay
# an otherwise normal observation; an alert requests investigation.
DAILY = {"treasury.us10y", "treasury.us2y", "treasury.real10y",
         "nyfed.effr", "liquidity.overnight_rrp"}
WEEKLY = {"fed_h41.total_assets", "liquidity.reserves", "liquidity.tga"}
MONTHLY = REQUIRED_SERIES - DAILY - WEEKLY
# Derived rates recorded in the ledger, but not independent source obligations.
DERIVED = {"treasury.breakeven10y", "treasury.spread10y2y"}


def day_of_observation(raw):
    if not isinstance(raw, str):
        raise ValueError("Observation period required")
    if len(raw) == 7:
        return date.fromisoformat(raw + "-01")
    if len(raw) == 10:
        return date.fromisoformat(raw)
    raise ValueError("Unrecognized observation period")


def business_days_since(d, now_day):
    if d > now_day:
        raise ValueError("Future observation period")
    return sum((d + timedelta(days=n)).weekday() < 5
               for n in range(1, (now_day - d).days + 1))


def analyze(rows, now):
    instant = utc(now) if isinstance(now, str) else now
    if not isinstance(instant, datetime) or instant.tzinfo is None:
        raise ValueError("Timezone-aware audit instant required")
    instant = instant.astimezone(timezone.utc)
    verify_ledger(rows, now=instant.isoformat())
    readiness = report(rows)
    grouped = defaultdict(list)
    for row in rows:
        grouped[row["series_id"]].append(row)
    series = {}
    critical = []
    warnings = []
    for sid in sorted(REQUIRED_SERIES | DERIVED):
        records = grouped.get(sid, [])
        cadence = ("derived" if sid in DERIVED else "daily" if sid in DAILY
                   else "weekly" if sid in WEEKLY else "monthly")
        if not records:
            series[sid] = {"cadence": cadence, "status": "not_yet_archived",
                           "versions": 0, "distinct_periods": 0,
                           "last_period": None, "last_first_seen_at": None}
            warnings.append(f"not_yet_archived:{sid}")
            continue
        periods = {r["observation_period"] for r in records}
        latest_period = max(periods, key=day_of_observation)
        observed = day_of_observation(latest_period)
        if observed > instant.date():
            raise ValueError("Future observation in archive: " + sid)
        last_seen = max(utc(r["first_seen_at"]) for r in records)
        days = (instant.date() - observed).days
        weekdays = business_days_since(observed, instant.date())
        status = "observed"
        # Derived series do not create independent availability obligations.
        # Daily: 6 weekday cushion; weekly/monthly: generous calendar windows,
        # so normal weekends/publication lags should not produce noisy alarms.
        stale = (cadence == "daily" and weekdays > 6 or
                 cadence == "weekly" and days > 21 or
                 cadence == "monthly" and days > 80)
        if stale:
            status = "observation_overdue_review"
            critical.append(f"observation_overdue_review:{sid}")
        elif len(periods) < 2:
            status = "warming_up_single_period"
        series[sid] = {"cadence": cadence, "status": status,
                       "versions": len(records), "distinct_periods": len(periods),
                       "last_period": latest_period,
                       "last_first_seen_at": last_seen.isoformat(),
                       "period_age_days": days,
                       "period_age_business_days": weekdays if cadence == "daily" else None}
    if not rows:
        critical.append("archive_missing_or_empty")
    legacy = readiness["treasury_source_year_mismatch_rows"]
    if legacy:
        warnings.append(f"legacy_treasury_source_year_mismatch:{legacy}")
    for sid in sorted(grouped):
        if sid not in series:
            warnings.append(f"unregistered_series:{sid}")
    return {
        "schema_version": 1, "report_type": "asset_compass_v27_observation_continuity",
        "checked_at": instant.isoformat(), "archived_versions": len(rows),
        "seeded_series": sum(bool(grouped.get(s)) for s in REQUIRED_SERIES),
        "required_series": len(REQUIRED_SERIES),
        "missing_required_series": [s for s in sorted(REQUIRED_SERIES)
                                    if not grouped.get(s)],
        "series": series, "critical_operational_alerts": critical,
        "investigation_warnings": warnings,
        "monitor_status": "attention_required" if critical else
                          "collecting_with_gaps" if warnings else "observing",
        "alert_policy": "6 weekdays daily, 21 calendar days weekly, 80 days monthly; heuristic, not official release calendar",
        "provenance_exception_count": legacy,
        "official_release_times_verified": False,
        "eligible_for_point_in_time_backtest": False,
        "validated_for_live_scoring": False,
        "automatic_investment_alerts_enabled": False,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ledger", type=Path, default=LEDGER)
    parser.add_argument("--output", type=Path, default=OUTPUT)
    parser.add_argument("--fail-on-critical", action="store_true")
    args = parser.parse_args()
    data = analyze(load(args.ledger), datetime.now(timezone.utc))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n",
                           encoding="utf-8")
    print(json.dumps({
        "monitor_status": data["monitor_status"],
        "archived_versions": data["archived_versions"],
        "seeded_series": data["seeded_series"],
        "missing_required_series": data["missing_required_series"],
        "critical_operational_alerts": data["critical_operational_alerts"],
        "provenance_exception_count": data["provenance_exception_count"],
        "validated_for_live_scoring": False,
    }, ensure_ascii=False))
    if args.fail_on_critical and data["critical_operational_alerts"]:
        raise SystemExit(2)


if __name__ == "__main__":
    main()
