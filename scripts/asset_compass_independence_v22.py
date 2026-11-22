#!/usr/bin/env python3
"""V22 as-of factor evidence overlap and independence diagnostic (research only).

This is NOT a measure of predictive independence, and cannot certify scores.
Use aligned same-day FIRST DIFFERENCES for correlation, not spurious levels.
All releases must be supported by actual vintages from a private research store.
"""
import argparse
import json
import math
import statistics
from collections import defaultdict
from datetime import date, datetime, timezone
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
# Hard algebraic identities: these cannot contribute independent votes.
DEPENDENCIES = (
    ("us10y", "real10y", "breakeven10y", "10Y nominal = TIPS real + breakeven compensation"),
    ("us10y", "us2y", "spread10y2y", "10Y-2Y = 10Y nominal - 2Y nominal"),
)
FIELDS = ("series_id", "observation_date", "available_at", "value",
          "unit", "frequency", "source_release_id", "source_url")


def iso_time(s):
    if not isinstance(s, str):
        raise ValueError("Timestamp required")
    try:
        d = datetime.fromisoformat(s.replace("Z", "+00:00"))
    except ValueError as e:
        raise ValueError("Invalid ISO timestamp") from e
    if d.tzinfo is None or d.utcoffset() is None:
        raise ValueError("Timezone required")
    return d.astimezone(timezone.utc)


def validate_and_select(rows, asof):
    decision = iso_time(asof)
    if decision > datetime.now(timezone.utc):
        raise ValueError("Decision time is future")
    if not isinstance(rows, list):
        raise ValueError("Expected JSON array")
    selected = {}
    seen = set()
    for row in rows:
        if not isinstance(row, dict) or any(k not in row for k in FIELDS):
            raise ValueError("Missing fields")
        sid, obs = row["series_id"], row["observation_date"]
        if not isinstance(sid, str) or not sid.strip():
            raise ValueError("Invalid series")
        try:
            d = date.fromisoformat(obs)
        except (ValueError, TypeError) as e:
            raise ValueError("Invalid observation day") from e
        released = iso_time(row["available_at"])
        if released.date() < d or released > datetime.now(timezone.utc):
            raise ValueError("Impossible release time")
        if type(row["value"]) not in (int, float) or not math.isfinite(row["value"]):
            raise ValueError("Finite numeric observation required")
        if not isinstance(row["unit"], str) or not row["unit"].strip():
            raise ValueError("Unit missing")
        if row["frequency"] not in ("daily", "weekly", "monthly"):
            raise ValueError("Unsupported frequency")
        if not isinstance(row["source_release_id"], str) or not row["source_release_id"].strip():
            raise ValueError("Authentic release identifier missing")
        url = row["source_url"]
        if not isinstance(url, str):
            raise ValueError("Invalid provenance")
        p = urlparse(url)
        if p.scheme != "https" or not p.hostname or p.username or p.password:
            raise ValueError("HTTPS provenance required")
        key = (sid, obs, released.isoformat(), row["source_release_id"])
        if key in seen:
            raise ValueError("Duplicate immutable vintage key")
        seen.add(key)
        if released > decision:
            continue
        lookup = (sid, obs)
        current = selected.get(lookup)
        if current is None or released > current[0]:
            selected[lookup] = (released, row)
    series = defaultdict(dict)
    metadata = {}
    for (sid, obs), (_, row) in selected.items():
        meta = (row["unit"], row["frequency"])
        if sid in metadata and metadata[sid] != meta:
            raise ValueError("Series unit/frequency changed without conversion")
        metadata[sid] = meta
        series[sid][obs] = row["value"]
    return dict(series), metadata, decision


def pearson(a, b):
    if len(a) < 3 or len(a) != len(b):
        return None
    ma, mb = statistics.fmean(a), statistics.fmean(b)
    aa = [v-ma for v in a]
    bb = [v-mb for v in b]
    va = sum(x*x for x in aa)
    vb = sum(x*x for x in bb)
    if va <= 1e-16 or vb <= 1e-16:
        return None
    return sum(x*y for x, y in zip(aa, bb)) / math.sqrt(va*vb)


def run_audit(rows, asof, *, min_pairs=8, correlation_flag=0.85):
    if type(min_pairs) is not int or min_pairs < 3:
        raise ValueError("min_pairs >=3 required")
    if type(correlation_flag) not in (int, float) or not 0 < correlation_flag < 1:
        raise ValueError("correlation threshold must be between 0 and 1")
    series, metadata, decision = validate_and_select(rows, asof)
    ids = sorted(series)
    pairs = []
    for i, left in enumerate(ids):
        for right in ids[i+1:]:
            shared = sorted(set(series[left]) & set(series[right]))
            if metadata[left][1] != metadata[right][1]:
                pairs.append({"series": [left, right], "shared_dates": len(shared),
                              "status": "frequency_mismatch", "correlation": None})
                continue
            # Only consecutive shared sample differences; gaps are disclosed,
            # not interpreted as daily changes.
            if len(shared) < min_pairs + 1:
                pairs.append({"series": [left, right], "shared_dates": len(shared),
                              "status": "insufficient_aligned_changes", "correlation": None})
                continue
            a = [series[left][d] for d in shared]
            b = [series[right][d] for d in shared]
            delta_a = [y-x for x, y in zip(a, a[1:])]
            delta_b = [y-x for x, y in zip(b, b[1:])]
            corr = pearson(delta_a, delta_b)
            status = ("zero_variance" if corr is None else
                      "high_change_correlation_review" if abs(corr) >= correlation_flag
                      else "correlation_computed_not_independence_certified")
            pairs.append({"series": [left, right], "shared_dates": len(shared),
                          "change_pairs": len(delta_a), "status": status,
                          "correlation": round(corr, 6) if corr is not None else None})
    identities = []
    for first, second, third, description in DEPENDENCIES:
        present = [x for x in (first, second, third) if x in series]
        if len(present) >= 2:
            identities.append({"series": list(present), "relationship": description,
                               "status": "known_algebraic_dependency_no_independent_vote"})
    return {
        "schema_version": 1, "report_type": "asset_compass_factor_independence_audit",
        "decision_at": decision.isoformat(), "series_count": len(ids),
        "observations_by_series": {sid: len(series[sid]) for sid in ids},
        "algebraic_dependencies": identities, "pairwise_change_diagnostics": pairs,
        "method": "same-observation-date consecutive matched differences; no calendar or release-time alignment claim",
        "historical_vintage_provenance_verified_by_tool": False,
        "independent_factor_groups_certified": False,
        "factor_signals_calibrated": False,
        "validated_for_live_scoring": False,
        "asset_scores_available": False,
        "automatic_alerts_enabled": False,
    }


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--input", type=Path, required=True)
    p.add_argument("--asof", required=True)
    a = p.parse_args()
    if a.input.resolve().is_relative_to(ROOT.resolve()):
        raise ValueError("Private vintage inputs must remain outside website repository")
    if not a.input.is_file():
        raise FileNotFoundError("Real source vintage evidence file required")
    report = run_audit(json.loads(a.input.read_text(encoding="utf-8")), a.asof)
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
