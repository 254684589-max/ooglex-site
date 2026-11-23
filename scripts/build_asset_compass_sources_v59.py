#!/usr/bin/env python3
"""V59: two authentic asset-specific *research* observations, never investment scores.

US equities: Federal Reserve Z.1 all-sector corporate equities market-value *stock*
via FRED, not the S&P 500, earnings, or dividend-inclusive investable return.
Bitcoin: Blockstream Esplora verified mainnet block headers plus deterministic
Bitcoin subsidy schedule. Scheduled issuance is NOT circulating/UTXO supply,
ETF holdings, realized capitalization, or a return series.

Both sources are latest available, NOT certified point-in-time release vintages.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import math
import re
import time
import urllib.parse
import urllib.request
from datetime import date, datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"
FRED_ID = "BOGZ1LM893064105Q"
FRED_URL = f"https://fred.stlouisfed.org/graph/fredgraph.csv?id={FRED_ID}&cosd=2000-01-01"
FRED_CITATION = f"https://fred.stlouisfed.org/series/{FRED_ID}"
FED_Z1_URL = "https://www.federalreserve.gov/releases/z1/current/html/F51_1_s.htm"
CHAIN_URL = "https://blockstream.info/api"
SOURCE_EQUITIES = "fed_z1_corporate_equities_all_sectors"
SOURCE_BTC = "bitcoin_mainnet_block_subsidy"
EQUITY_FILE = DATA / "asset-compass-equities-z1-v59.json"
BTC_FILE = DATA / "asset-compass-bitcoin-chain-v59.json"
EVIDENCE_FILE = DATA / "asset-compass-model-gaps-v59.json"
V58_FILE = DATA / "asset-compass-model-gaps-v58.json"
HEX64 = re.compile(r"^[0-9a-f]{64}$")


def _utc(now=None):
    now = now or datetime.now(timezone.utc)
    if now.tzinfo is None or now.utcoffset() is None:
        raise ValueError("UTC timezone required")
    return now.astimezone(timezone.utc)


def _digest(raw):
    return hashlib.sha256(raw).hexdigest()


def _get(url, *, host, limit=3_000_000, opener=None, retries=2):
    """Bound network bytes, domain, redirects, transient retries and TLS."""
    if not url.startswith("https://"):
        raise ValueError("HTTPS required")
    opener = opener or urllib.request.urlopen
    errors = []
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "Ooglex-AssetCompass-Research/1.0 (source audit)"})
            with opener(req, timeout=25) as response:
                final = urllib.parse.urlsplit(response.geturl())
                if final.scheme != "https" or final.hostname != host:
                    raise ValueError("Unexpected remote origin or redirect")
                raw = response.read(limit + 1)
                if not raw or len(raw) > limit:
                    raise ValueError("Empty or oversized remote evidence")
                return raw
        except (OSError, TimeoutError) as exc:
            errors.append(type(exc).__name__)
            if attempt + 1 < retries:
                time.sleep(2)
    raise ConnectionError("Official data source not accessible: " + ",".join(errors))


def parse_equities_csv(raw):
    """Read observed quarterly values only; no fill, interpolation or projected Q."""
    reader = csv.DictReader(io.StringIO(raw.decode("utf-8-sig")))
    if reader.fieldnames not in (["DATE", FRED_ID], ["observation_date", FRED_ID]):
        raise ValueError("Unexpected Z.1 series identifier or CSV header")
    results = []
    last = None
    seen_quarters = set()
    for row in reader:
        if not row.get(reader.fieldnames[0]):
            raise ValueError("Missing Z.1 period date")
        day = date.fromisoformat(row[reader.fieldnames[0]])
        if last is not None and day <= last:
            raise ValueError("Non-ascending or duplicated equity date")
        last = day
        if day.month not in (1, 3, 4, 6, 7, 9, 10, 12):
            raise ValueError("Non-quarterly Z.1 record")
        quarter = f"{day.year}-Q{(day.month - 1) // 3 + 1}"
        if quarter in seen_quarters:
            raise ValueError("Duplicated Z.1 quarter")
        seen_quarters.add(quarter)
        val = row[FRED_ID]
        if val in (".", ""):
            continue
        millions = float(val)
        if not math.isfinite(millions) or not 1_000_000 < millions < 1_000_000_000:
            raise ValueError("Invalid Z.1 market-value millions of USD")
        results.append({"observation_date": day.isoformat(), "quarter": quarter,
                        "market_value_millions_usd": millions})
    if len(results) < 50:
        raise ValueError("Insufficient real official Z.1 quarterly history")
    return results


def build_equities(rows, *, raw_sha, now=None):
    now = _utc(now)
    if not HEX64.fullmatch(raw_sha):
        raise ValueError("Missing official CSV SHA256")
    if len(rows) < 50 or len(set(r["quarter"] for r in rows)) != len(rows):
        raise ValueError("Invalid quarterly history")
    if any(date.fromisoformat(r["observation_date"]) > now.date() for r in rows):
        raise ValueError("Future Z.1 record")
    latest = rows[-1]
    if latest["market_value_millions_usd"] <= 0:
        raise ValueError("Invalid market stock")
    age = (now.date() - date.fromisoformat(latest["observation_date"])).days
    return {
        "schema_version": 1, "report_type": "asset_compass_v59_us_equities_z1_research",
        "generated_at": now.isoformat(), "asset_id": "us_equities",
        "source_id": SOURCE_EQUITIES, "series_id": FRED_ID,
        "source_owner": "Board of Governors of the Federal Reserve System",
        "source_url": FRED_URL, "citation_url": FRED_CITATION,
        "official_table_url": FED_Z1_URL, "raw_source_sha256": raw_sha,
        "units": "millions_usd", "frequency": "quarterly_end_of_period",
        "observation_count": len(rows), "latest_observation_period": latest["quarter"],
        "latest_observation_date": latest["observation_date"],
        "latest_market_value_millions_usd": latest["market_value_millions_usd"],
        "latest_market_value_trillions_usd": round(latest["market_value_millions_usd"] / 1_000_000, 6),
        "quarter_over_quarter_change_pct": round(
            (latest["market_value_millions_usd"] / rows[-2]["market_value_millions_usd"] - 1) * 100, 6),
        "recent_quarterly_observations": rows[-16:],
        "fresh_for_research": 0 <= age <= 245,
        "observation_calendar_days_old": age,
        "source_observation_status": "observed_research_only",
        "source_rights": "Federal Reserve public-domain data; citation requested via FRED metadata",
        "redistribution_rights_instrument_by_instrument_certified": False,
        "historical_first_publication_vintages_verified": False,
        "investable_total_return_verified": False, "independent_signal_verified": False,
        "out_of_sample_validation_passed": False,
        "validated_for_live_scoring": False, "official_asset_score": None,
        "limitations": [
            "Z.1 all-sector corporate equity market-value STOCK includes more than publicly traded US stocks; not the S&P 500.",
            "Levels change with valuation, issuance, sector and methodological revisions; changes are not investor returns.",
            "Quarter-end observation date is NOT official publication date; no original historical vintage certified.",
            "Source is latest-revised quarterly data, not a calibrated asset pricing factor."
        ]
    }


def subsidy_total_sats(height):
    """Nominal maximum subsidy per Bitcoin consensus halving epochs, integer only.

    Includes theoretical genesis block subsidy and all subsidy allowances,
    so this is NOT actual spendable/UTXO supply or exact mined reward claims.
    """
    if type(height) is not int or not 0 <= height <= 100_000_000:
        raise ValueError("Invalid block height")
    blocks = height + 1
    total = 0
    for epoch in range(64):
        n = min(blocks, 210_000)
        if n <= 0:
            break
        total += n * ((50 * 100_000_000) >> epoch)
        blocks -= n
    if blocks > 0 or total > 21_000_000 * 100_000_000:
        raise ValueError("Invalid Bitcoin subsidy schedule")
    return total


def parse_block(raw, *, expected_hash=None, expected_height=None):
    block = json.loads(raw)
    h = block.get("height")
    digest = block.get("id")
    ts = block.get("timestamp")
    if (type(h) is not int or h < 0 or not isinstance(digest, str) or
        not HEX64.fullmatch(digest) or type(ts) is not int or
        not 1_231_006_505 <= ts <= 4_102_444_800):
        raise ValueError("Invalid mainnet block proof")
    if expected_hash is not None and digest != expected_hash:
        raise ValueError("Block hash mismatch")
    if expected_height is not None and h != expected_height:
        raise ValueError("Block height mismatch")
    return {"height": h, "block_hash": digest,
            "block_timestamp": datetime.fromtimestamp(ts, timezone.utc).isoformat()}


def _block_at_height(height, *, opener):
    hashraw = _get(f"{CHAIN_URL}/block-height/{height}", host="blockstream.info",
                   limit=150, opener=opener)
    block_hash = hashraw.decode("ascii").strip()
    if not HEX64.fullmatch(block_hash):
        raise ValueError("Unexpected block height lookup")
    blockraw = _get(f"{CHAIN_URL}/block/{block_hash}", host="blockstream.info",
                    limit=25_000, opener=opener)
    return parse_block(blockraw, expected_hash=block_hash, expected_height=height), {
        "block_hash_lookup_sha256": _digest(hashraw), "block_header_sha256": _digest(blockraw)}


def fetch_bitcoin(*, opener=None, now=None):
    """Observed tip and 1,008-block historical checkpoint, no invented dates."""
    now = _utc(now)
    opener = opener or urllib.request.urlopen
    height_raw = _get(f"{CHAIN_URL}/blocks/tip/height", host="blockstream.info",
                      limit=20, opener=opener)
    text_height = height_raw.decode("ascii").strip()
    if not text_height.isascii() or not text_height.isdigit():
        raise ValueError("Invalid mainnet height response")
    height = int(text_height)
    if not 840_000 < height < 2_000_000:
        raise ValueError("Unexpected current mainnet height")
    tip, tip_hashes = _block_at_height(height, opener=opener)
    lookback, older_hashes = _block_at_height(height - 1008, opener=opener)
    tip_dt = datetime.fromisoformat(tip["block_timestamp"])
    older_dt = datetime.fromisoformat(lookback["block_timestamp"])
    age = (now - tip_dt).total_seconds()
    if age < -7200 or age > 3 * 86400:
        raise ValueError("Bitcoin tip time inconsistent with audit clock")
    if not 0 < (tip_dt - older_dt).total_seconds() < 30 * 86400:
        raise ValueError("Historical block checkpoint not plausible")
    sats = subsidy_total_sats(height)
    prev_sats = subsidy_total_sats(height - 1008)
    return {
        "schema_version": 1, "report_type": "asset_compass_v59_bitcoin_mainnet_issuance_research",
        "generated_at": now.isoformat(), "asset_id": "bitcoin", "source_id": SOURCE_BTC,
        "network": "bitcoin_mainnet",
        "source_owner": "Bitcoin consensus subsidy schedule; block headers via Blockstream Esplora",
        "source_url": f"{CHAIN_URL}/blocks/tip/height",
        "citation_url": "https://blockstream.info/",
        "api_documentation": "https://github.com/Blockstream/esplora/blob/master/API.md",
        "observed_tip": tip, "historical_checkpoint": lookback,
        "checkpoint_distance_blocks": 1008,
        "nominal_subsidy_to_tip_sats": sats,
        "nominal_subsidy_to_tip_btc": round(sats / 100_000_000, 8),
        "nominal_subsidy_new_over_1008_blocks_btc": round((sats - prev_sats) / 100_000_000, 8),
        "source_response_sha256": {
            "tip_height": _digest(height_raw), "tip": tip_hashes,
            "checkpoint": older_hashes
        },
        "fresh_for_research": 0 <= age <= 2 * 86400,
        "source_observation_status": "observed_research_only",
        "source_rights": "Bitcoin consensus data public; Blockstream free API rate-limited; independent node/license review outstanding",
        "redistribution_rights_instrument_by_instrument_certified": False,
        "independent_node_cross_checked": False,
        "historical_first_publication_vintages_verified": False,
        "investable_total_return_verified": False, "independent_signal_verified": False,
        "out_of_sample_validation_passed": False,
        "validated_for_live_scoring": False, "official_asset_score": None,
        "limitations": [
            "Nominal sum of allowed block subsidies is NOT the actual spendable circulating supply, UTXO set or ETF-held BTC.",
            "Includes unspendable genesis subsidy and potential unclaimed or burned subsidy; actual liquid supply is lower.",
            "1008 blocks is a block-count lookback, not exactly seven calendar days.",
            "Single Esplora explorer observation is not independent Bitcoin full-node validation; reorganizations are possible.",
            "Block fees, ETF flows, custody and Bitcoin total investment return are NOT measured.",
        ]
    }


def _read_json_if_present(path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def build_evidence(v58, equities=None, bitcoin=None, *, now=None):
    """Additive V59 audit; V58 snapshot and every original score lock unchanged."""
    now = _utc(now)
    if (v58.get("report_type") != "asset_compass_v58_six_asset_model_evidence" or
        v58.get("asset_specific_observed_count") != 4 or
        set(v58.get("asset_specific_missing_assets", [])) != {"us_equities", "bitcoin"} or
        v58.get("qualified_for_live_scoring") is not False or
        v58.get("official_0_to_100_scores_published") != 0 or
        any(v.get("official_score") is not None for v in v58.get("research_assets", {}).values()) or
        set(v58.get("research_assets", {})) !=
        {"gold", "us_equities", "us_long_bonds", "usd", "bitcoin", "oil"}):
        raise ValueError("V58 original research-only contract changed")
    requested = {
        "us_equities": (equities, "asset_compass_v59_us_equities_z1_research", SOURCE_EQUITIES),
        "bitcoin": (bitcoin, "asset_compass_v59_bitcoin_mainnet_issuance_research", SOURCE_BTC),
    }
    observed = list(v58["asset_specific_observed_assets"])
    rows = json.loads(json.dumps(v58["research_assets"]))
    verification = {}
    for aid, (doc, report_type, source_id) in requested.items():
        reason = None
        if not isinstance(doc, dict):
            reason = "capture_absent"
        elif (doc.get("report_type") != report_type or doc.get("source_id") != source_id or
              doc.get("asset_id") != aid or doc.get("schema_version") != 1 or
              doc.get("source_observation_status") != "observed_research_only"):
            reason = "source_identity_invalid"
        elif (doc.get("official_asset_score") is not None or
              doc.get("validated_for_live_scoring") is not False or
              doc.get("historical_first_publication_vintages_verified") is not False or
              doc.get("investable_total_return_verified") is not False or
              doc.get("independent_signal_verified") is not False or
              doc.get("out_of_sample_validation_passed") is not False):
            reason = "source_false_qualification"
        elif doc.get("fresh_for_research") is not True:
            reason = "source_stale"
        else:
            try:
                captured = datetime.fromisoformat(doc["generated_at"].replace("Z", "+00:00"))
                if captured.tzinfo is None or not 0 <= (now - captured).total_seconds() <= 8 * 86400:
                    reason = "capture_age_invalid"
                elif aid == "us_equities":
                    latest = date.fromisoformat(doc["latest_observation_date"])
                    if (doc.get("series_id") != FRED_ID or doc.get("units") != "millions_usd" or
                        doc.get("observation_count", 0) < 50 or not
                        HEX64.fullmatch(doc.get("raw_source_sha256", "")) or
                        not 0 <= (now.date() - latest).days <= 245):
                        reason = "quarterly_market_value_unverified"
                else:
                    tip = doc["observed_tip"]
                    if (doc.get("network") != "bitcoin_mainnet" or
                        doc.get("independent_node_cross_checked") is not False or
                        doc.get("checkpoint_distance_blocks") != 1008 or
                        not HEX64.fullmatch(tip["block_hash"]) or
                        not 0 <= (now - datetime.fromisoformat(tip["block_timestamp"])).total_seconds() <= 2 * 86400 or
                        subsidy_total_sats(tip["height"]) != doc["nominal_subsidy_to_tip_sats"] or
                        doc["historical_checkpoint"]["height"] != tip["height"] - 1008):
                        reason = "bitcoin_chain_proof_unverified"
            except (KeyError, TypeError, ValueError, OverflowError):
                reason = "malformed_source_provenance"
        if reason is None:
            observed.append(aid)
            rows[aid]["source_ids"] = [source_id]
            rows[aid]["source_observation_status"] = "observed_research_only"
            rows[aid]["research_source_count"] = 1
            rows[aid]["completeness_in_six_assets_pct"] = 100
            rows[aid]["next_evidence"] = (
                "Z1_all_sector_corporate_equities_not_public_stock_return_or_first_release_PIT"
                if aid == "us_equities" else
                "nominal_block_subsidy_not_actual_spendable_supply_or_total_return")
        verification[aid] = {"observed": reason is None, "reason": reason,
                             "source_id": source_id,
                             "source_report_sha256": (
                                 hashlib.sha256(json.dumps(doc, sort_keys=True,
                                     ensure_ascii=False, separators=(",", ":")).encode()).hexdigest()
                                 if reason is None else None)}
    return {
        "schema_version": 1, "report_type": "asset_compass_v59_two_missing_asset_research_provenance",
        "generated_at": now.isoformat(),
        "parent_report": "data/asset-compass-model-gaps-v58.json",
        "parent_report_sha256": hashlib.sha256(json.dumps(v58, sort_keys=True,
            ensure_ascii=False, separators=(",", ":")).encode()).hexdigest(),
        "source_verification": verification,
        "asset_specific_observed_assets": [a for a in
             ("gold", "us_equities", "us_long_bonds", "usd", "bitcoin", "oil") if a in observed],
        "asset_specific_missing_assets": [a for a in
             ("gold", "us_equities", "us_long_bonds", "usd", "bitcoin", "oil") if a not in observed],
        "asset_specific_observed_count": len(observed),
        "asset_specific_missing_count": 6 - len(observed),
        "research_assets": rows,
        "historical_first_release_certified_source_count": 0,
        "audited_asset_total_return_count": 0,
        "approved_independent_model_factor_group_count": 0,
        "oos_validated_assets": 0, "official_0_to_100_scores_published": 0,
        "qualified_for_live_scoring": False, "automated_investment_actions_enabled": False,
        "status": "research_only_no_authorized_scores",
        "limitations": [
            "An observed sector market-value stock or nominal Bitcoin issuance is not a tradable asset return.",
            "New research sources do not certify PIT historical publication, independent signal, license for all products or OOS performance.",
            "Zero 0–100 official asset scores; every research_assets row retains official_score null."
        ]
    }


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2, allow_nan=False) + "\n",
                    encoding="utf-8")


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("task", choices=("fetch-equities", "fetch-bitcoin", "build-evidence"))
    args = p.parse_args()
    if args.task == "fetch-equities":
        raw = _get(FRED_URL, host="fred.stlouisfed.org")
        data = build_equities(parse_equities_csv(raw), raw_sha=_digest(raw))
        if not data["fresh_for_research"]:
            raise SystemExit("Official Z.1 observation stale; refusing to promote as available")
        write_json(EQUITY_FILE, data)
        print(json.dumps({"source": SOURCE_EQUITIES, "quarter": data["latest_observation_period"],
                          "trillions_usd": data["latest_market_value_trillions_usd"]}))
    elif args.task == "fetch-bitcoin":
        data = fetch_bitcoin()
        if not data["fresh_for_research"]:
            raise SystemExit("Bitcoin tip stale; refusing to promote as observed")
        write_json(BTC_FILE, data)
        print(json.dumps({"source": SOURCE_BTC, "height": data["observed_tip"]["height"],
                          "nominal_subsidy_btc": data["nominal_subsidy_to_tip_btc"]}))
    else:
        baseline = _read_json_if_present(V58_FILE)
        if baseline is None:
            raise SystemExit("V58 original audit missing; refusing V59 status")
        data = build_evidence(baseline, _read_json_if_present(EQUITY_FILE),
                              _read_json_if_present(BTC_FILE))
        write_json(EVIDENCE_FILE, data)
        print(json.dumps({"real_source_coverage": data["asset_specific_observed_count"],
                          "missing": data["asset_specific_missing_assets"],
                          "scores": data["official_0_to_100_scores_published"]}))


if __name__ == "__main__":
    main()
