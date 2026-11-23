#!/usr/bin/env python3
"""V61 official first-publication vs archive-first-seen and revision contract.

This is a conservative eligibility auditor. Plausible URLs, signed timestamps,
and hashes supplied by a reporter are NOT independent verification of a source
artifact or its historically available time. No release can self-certify PIT.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import re
from datetime import date, datetime, timezone
from pathlib import Path
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]
V50 = ROOT / "data/asset-compass-pit-evidence-v50.json"
V59 = ROOT / "data/asset-compass-model-gaps-v59.json"
V60 = ROOT / "data/asset-compass-return-readiness-v60.json"
OUT = ROOT / "data/asset-compass-pit-admission-v61.json"
HEX = re.compile(r"^[0-9a-f]{64}$")
SERIES_EXPECTED = 14


def iso_utc(value):
    if not isinstance(value, str):
        raise ValueError("Explicit release time with UTC offset required")
    d = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if d.tzinfo is None or d.utcoffset() is None:
        raise ValueError("Naive timestamp cannot establish public availability")
    return d.astimezone(timezone.utc)


def sha(doc):
    return hashlib.sha256(json.dumps(doc, sort_keys=True, ensure_ascii=False,
        separators=(",", ":"), allow_nan=False).encode()).hexdigest()


def candidate_bundle(series, observation_date, releases):
    """Validate structural timeline but NEVER grant independent PIT certification.

    No guess is permitted for ambiguous official first-published timestamps,
    revisions, or source rights. A first_seen-only repository archive is refused.
    """
    if not isinstance(series, str) or not series.strip():
        raise ValueError("Series identity required")
    observation = date.fromisoformat(observation_date)
    if not isinstance(releases, list) or not releases:
        raise ValueError("A release artifact must exist; first_seen not evidence")
    outputs = []
    seen = set()
    previous = None
    for idx, record in enumerate(releases):
        if not isinstance(record, dict):
            raise ValueError("Invalid original release record")
        if any(key not in record for key in
               ("official_publication_at", "source_release_id", "original_bytes_sha256",
                "source_url", "numeric_value", "original_source_format", "units")):
            raise ValueError("Original release timestamp and artifact evidence required")
        if "first_seen_at" in record and "official_publication_at" not in record:
            raise ValueError("GitHub first_seen is not official publication")
        published = iso_utc(record["official_publication_at"])
        if published.date() < observation:
            raise ValueError("Release earlier than observed period")
        if published > datetime.now(timezone.utc):
            raise ValueError("Future release is not historical proof")
        if previous and published <= previous:
            raise ValueError("Out-of-order or same-clock published revisions")
        previous = published
        digest = record["original_bytes_sha256"]
        release_id = record["source_release_id"]
        if not isinstance(digest, str) or not HEX.fullmatch(digest):
            raise ValueError("Original raw publication SHA256 required")
        if not isinstance(release_id, str) or not release_id.strip():
            raise ValueError("Original publisher release ID missing")
        if (release_id, digest) in seen:
            raise ValueError("Duplicate original release cannot be revision")
        seen.add((release_id, digest))
        url = urlsplit(record["source_url"])
        if url.scheme != "https" or not url.hostname or url.username or url.password:
            raise ValueError("Official artifact HTTPS URL required")
        val = record["numeric_value"]
        import math
        if type(val) not in (int, float) or not math.isfinite(val):
            raise ValueError("Finite numeric release value required")
        if not all(isinstance(record[k], str) and record[k].strip()
                   for k in ("original_source_format", "units")):
            raise ValueError("Source unit and artifact format required")
        outputs.append({
            "sequence": idx,
            "official_publication_at_unverified": published.isoformat(),
            "source_release_id": release_id,
            "source_url": record["source_url"],
            "original_bytes_sha256_unverified": digest,
            "revision_of_prior_release": idx > 0
        })
    return {
        "series_id": series, "observation_date": observation_date,
        "release_candidate_count": len(outputs), "first_publication_candidate": outputs[0],
        "revision_candidates": outputs[1:],
        "original_publication_timestamp_independently_verified": False,
        "original_publisher_artifact_bytes_independently_verified": False,
        "complete_revision_chain_independently_verified": False,
        "historical_data_license_approved": False,
        "eligible_for_pit_backtest": False,
        "status": "structured_candidate_only_requires_external_reviewer"
    }


def asof_candidate_timeline(bundle, decision_at):
    """Candidate as-of visibility is diagnostic only; not certified market availability."""
    decision = iso_utc(decision_at)
    events = [bundle["first_publication_candidate"], *bundle["revision_candidates"]]
    eligible = [r for r in events
                if iso_utc(r["official_publication_at_unverified"]) <= decision]
    return {
        "decision_at": decision.isoformat(),
        "selected_candidate_release_id": eligible[-1]["source_release_id"] if eligible else None,
        "candidate_visible": bool(eligible),
        "historically_tradeable_verified": False,
        "eligible_for_pit_backtest": False,
    }


def readiness(v50, v59, v60, *, now=None):
    now = now or datetime.now(timezone.utc)
    if now.tzinfo is None or now.utcoffset() is None:
        raise ValueError("Timezone-aware audit clock required")
    entries = v50.get("entries")
    if (v50.get("report_type") != "asset_compass_pit_evidence_ledger_v50" or
        not isinstance(entries, list) or len(entries) != SERIES_EXPECTED or
        len({x.get("id") for x in entries}) != SERIES_EXPECTED or
        v50.get("evidence_policy", {}).get("no_model_admission_from_registry") is not True or
        any(e.get("point_in_time_qualified") is not False or
            e.get("first_publication_verified") is not False or
            e.get("revision_chain_verified") is not False for e in entries)):
        raise ValueError("V50 original-releases evidence is incomplete/forged")
    if (v59.get("report_type") != "asset_compass_v59_two_missing_asset_research_provenance" or
        v59.get("asset_specific_observed_count") != 6 or
        v59.get("official_0_to_100_scores_published") != 0 or
        v59.get("historical_first_release_certified_source_count") != 0 or
        v59.get("qualified_for_live_scoring") is not False):
        raise ValueError("V59 research source or scoring contract changed")
    if (v60.get("report_type") != "asset_compass_v60_investable_return_accounting_readiness" or
        v60.get("accounting_contracts_defined") != 6 or
        v60.get("audited_asset_total_return_count") != 0 or
        v60.get("official_0_to_100_scores_published") != 0 or
        v60.get("validated_for_live_scoring") is not False):
        raise ValueError("V60 total-return status unexpectedly approved")
    result = {}
    for e in entries:
        if not isinstance(e.get("first_publication_records"), list) or not isinstance(e.get("revision_records"), list):
            raise ValueError("V50 release history malformed")
        if e["first_publication_records"] or e["revision_records"]:
            raise ValueError("Existing V50 records now nonempty; require new independent review before reclassification")
        result[e["id"]] = {
            "public_reference_only": e.get("release_reference", {}).get("status") == "reference_only",
            "official_first_publication_record_count": 0,
            "independent_publisher_artifact_hash_verified": False,
            "real_release_datetime_timezone_verified": False,
            "historical_revision_chain_verified": False,
            "redistribution_rights_verified": False,
            "available_for_pit_backtest": False,
            "next_required": "authentic_original_release_artifact_and_independently_correlated_UTC_publication_clock",
        }
    return {
        "schema_version": 1,
        "report_type": "asset_compass_v61_original_release_pit_admission_contract",
        "generated_at": now.astimezone(timezone.utc).isoformat(),
        "parent_sha256": {"v50": sha(v50), "v59": sha(v59), "v60": sha(v60)},
        "required_macro_series": SERIES_EXPECTED,
        "registered_release_reference_series": len(result),
        "independently_certified_original_release_series": 0,
        "independently_verified_revision_chains": 0,
        "investable_total_return_certified_assets": 0,
        "oos_validated_assets": 0,
        "approved_independent_factor_groups": 0,
        "official_0_to_100_scores_published": 0,
        "first_seen_or_observation_date_is_official_release_proof": False,
        "model_scoring_enabled": False, "eligible_for_historical_pit_backtest": False,
        "status": "research_registry_only_no_original_release_certification",
        "series": result,
        "limitations": [
            "Release-reference URLs are not archived original release artifacts or verified timestamps.",
            "First-seen, observation period, and latest-revised series are not contemporaneously available PIT evidence.",
            "Any independently attested release audit must separately corroborate original publisher bytes, timezone, availability and revisions.",
            "No asset score or predictive validation is unlocked by this registry."
        ],
    }


def main():
    args = argparse.ArgumentParser()
    args.add_argument("--output", type=Path, default=OUT)
    options = args.parse_args()
    v50 = json.loads(V50.read_text(encoding="utf-8"))
    v59 = json.loads(V59.read_text(encoding="utf-8"))
    v60 = json.loads(V60.read_text(encoding="utf-8"))
    out = readiness(v50, v59, v60)
    options.output.parent.mkdir(parents=True, exist_ok=True)
    options.output.write_text(json.dumps(out, ensure_ascii=False, indent=2,
        allow_nan=False) + "\n", encoding="utf-8")
    print(json.dumps({"required": 14,
                      "certified_original_releases": 0,
                      "oos": 0, "scores": 0}))


if __name__ == "__main__":
    main()
