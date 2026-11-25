#!/usr/bin/env python3
"""V53 extract SOURCE-REPORTED headline statistics from V52 verified private bytes.

These are dated-news-release summary figures, NOT underlying index levels,
independently certified original vintages, or investable backtest data.
A changed HTML snapshot is NOT proof of a historical provider revision.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from datetime import datetime, timezone
from decimal import Decimal
from html.parser import HTMLParser
from pathlib import Path

from scripts.capture_asset_compass_official_v51 import _private_path, load_candidates
from scripts.asset_compass_custody_v52 import (
    _load_journal, custody_lock, secure_directory, secure_regular,
)

OUT = Path("/tmp/ooglex-v53-release-values.json")
MONTH = ("January", "February", "March", "April", "May", "June",
         "July", "August", "September", "October", "November", "December")
NUMBER = r"([0-9]+(?:\.[0-9]+)?)"
NONFARM = r"([+-]?[0-9]{1,3}(?:,[0-9]{3})*)"
VERBS = r"(increased|rose|decreased|fell|declined)"
EXPECTED = {"cpi": ("bls.cpi", "bls.core_cpi"),
            "employment": ("bls.payroll", "bls.unemployment"),
            "pio": ("bea.core_pce",)}


class VisibleText(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.parts = []
        self.skipping = []
    def handle_starttag(self, tag, attrs):
        if tag in ("script", "style", "noscript", "svg"):
            self.skipping.append(tag)
        if tag in ("p", "pre", "div", "td", "th", "h1", "h2", "h3", "br", "li", "tr"):
            self.parts.append(" ")
    def handle_endtag(self, tag):
        if self.skipping and self.skipping[-1] == tag:
            self.skipping.pop()
        if tag in ("p", "pre", "div", "td", "th", "h1", "h2", "h3", "br", "li", "tr"):
            self.parts.append(" ")
    def handle_data(self, data):
        if not self.skipping:
            self.parts.append(data)


def visible(raw: bytes) -> str:
    # All seven archived candidates are expected to be English HTML.
    if len(raw) > 3_000_000 or not raw:
        raise ValueError("Unexpected source byte count")
    document = VisibleText()
    document.feed(raw.decode("utf-8", errors="replace"))
    return re.sub(r"\s+", " ", " ".join(document.parts)).strip()


def decimal_text(value):
    return format(Decimal(str(value)), "f")


def _record(source, metric, kind, adjustment, sign, match, text, document_sha):
    val = Decimal(match.group("value").replace(",", "")) * (Decimal(-1) if sign else Decimal(1))
    if not val.is_finite():
        raise ValueError("Non-finite extracted number")
    if metric == "bls.payroll":
        if abs(val) > 2_000_000 or val != val.to_integral_value():
            raise ValueError("Implausible payroll count")
        unit = "persons_change_month"
    else:
        if abs(val) > 100:
            raise ValueError("Implausible percentage")
        unit = "percent"
    passage = match.group(0)
    return {
        "source_series_id": metric,
        "observation_period": source["observation_period"],
        "statistic": kind,
        "seasonal_adjustment": adjustment,
        "value_reported": decimal_text(val),
        "unit": unit,
        "source_document_sha256": document_sha,
        "source_artifact_id": source["artifact_id"],
        "source_url": source["source_url"],
        "passage_sha256": hashlib.sha256(passage.encode("utf-8")).hexdigest(),
        "passage_start_in_normalized_html": match.start(),
        "source_scope": "archived_press_release_headline_not_full_index_table",
        "human_reviewed": False,
        "historical_original_release_verified": False,
        "point_in_time_qualified": False,
    }


def _match(pattern, section, source, *, metric, kind, adjustment,
           sign_group="verb", flags=re.I):
    m = re.search(pattern, section, flags)
    if not m:
        return None
    down = m.group(sign_group).lower() in ("decreased", "fell", "declined")
    return _record(source, metric, kind, adjustment, down, m, section,
                   source["_sha256"])


def _heading_section(text, source):
    yyyy, mm = map(int, source["observation_period"].split("-"))
    month = MONTH[mm - 1]
    if source["release_kind"] == "cpi":
        heading = r"CONSUMER PRICE INDEX\s*[-–—]\s*" + month + rf"\s+{yyyy}\b"
    elif source["release_kind"] == "employment":
        heading = r"THE EMPLOYMENT SITUATION\s*[-–—]{1,2}\s*" + month + rf"\s+{yyyy}\b"
    else:
        heading = r"Personal Income and Outlays,?\s+" + month + rf"\s+{yyyy}\b"
    found = re.search(heading, text, re.I)
    if not found:
        raise ValueError("Document does not contain matching observation-month release title")
    return month, text[found.end():found.end()+7000]


def extract(source, raw: bytes, digest: str):
    if hashlib.sha256(raw).hexdigest() != digest:
        raise ValueError("Official HTML bytes disagree with custody digest")
    text = visible(raw)
    source = dict(source, _sha256=digest)
    month, section = _heading_section(text, source)
    records = []
    if source["release_kind"] == "cpi":
        patterns = [
            (rf"The Consumer Price Index for All Urban Consumers\s*\(CPI-U\)\s*"
             rf"(?P<verb>{VERBS})\s+(?P<value>{NUMBER})\s+percent on a seasonally adjusted basis\s+in\s+{month}\b",
             "bls.cpi", "headline_mom_rate", "seasonally_adjusted"),
            (rf"Over the last 12 months,?\s+the all items index\s+(?P<verb>{VERBS})\s+"
             rf"(?P<value>{NUMBER})\s+percent before seasonal adjustment",
             "bls.cpi", "headline_yoy_rate", "not_seasonally_adjusted"),
            (rf"The index for all items less food and energy\s+(?P<verb>{VERBS})\s+"
             rf"(?P<value>{NUMBER})\s+percent\s+in\s+{month}\b",
             "bls.core_cpi", "headline_mom_rate", "seasonally_adjusted"),
            (rf"The all items less food and energy index\s+(?P<verb>{VERBS})\s+"
             rf"(?P<value>{NUMBER})\s+percent\s+over the (?:last|past) 12 months",
             "bls.core_cpi", "headline_yoy_rate", "not_seasonally_adjusted"),
        ]
        section = section[:4200]
        for pattern, metric, kind, adj in patterns:
            result = _match(pattern, section, source, metric=metric, kind=kind,
                            adjustment=adj)
            if result:
                records.append(result)
    elif source["release_kind"] == "employment":
        # Never use the revised November/December/January table rows as current
        # monthly headline; limit to the first sentence after the dated heading.
        header = section[:650]
        payroll = re.search(
            rf"Total nonfarm payroll employment\s+(?P<verb>{VERBS})\s+by\s+"
            rf"(?P<value>{NONFARM})\s+in\s+{month}\b", header, re.I)
        if payroll:
            records.append(_record(source, "bls.payroll", "monthly_payroll_change",
                                   "seasonally_adjusted",
                                   payroll.group("verb").lower() in ("fell", "declined", "decreased"),
                                   payroll, header, digest))
        rate = re.search(
            r"(?:the\s+)?unemployment rate\s+(?:edged|changed|was|held|rose|fell|increased|decreased|remained)"
            r"\s+[^.;]{0,55}?\b(?:to|at|of)\s+(?P<value>[0-9]+(?:\.[0-9]+)?)\s+percent",
            header, re.I)
        if rate:
            records.append(_record(source, "bls.unemployment", "monthly_unemployment_rate",
                                   "seasonally_adjusted", False, rate, header, digest))
    else:
        for lead, kind in (
            ("From the preceding month", "headline_mom_rate"),
            ("From the same month one year ago", "headline_yoy_rate"),
        ):
            pattern = (re.escape(lead) +
                       rf",?\s+the PCE price index for\s+{month}\s+(?:increased|rose|decreased|fell)"
                       rf"\s+[0-9]+(?:\.[0-9]+)?\s+percent\.\s+"
                       rf"Excluding food and energy,?\s+the PCE price index\s+"
                       rf"(?P<verb>{VERBS})\s+(?P<value>{NUMBER})\s+percent")
            result = _match(pattern, section[:4500], source, metric="bea.core_pce",
                            kind=kind, adjustment="reported_rate_index_level_unavailable")
            if result:
                records.append(result)
    expected = 4 if source["release_kind"] == "cpi" else 2
    keys = {(r["source_series_id"], r["statistic"]) for r in records}
    if len(keys) != len(records):
        raise ValueError("Duplicate headline metric cannot be disambiguated")
    return {
        "artifact_id": source["artifact_id"], "sha256": digest,
        "observation_period": source["observation_period"],
        "source_url": source["source_url"],
        "source_family": source["release_kind"],
        "expected_metrics": expected, "extracted_metrics": len(records),
        "status": ("candidate_complete_unverified" if len(records) == expected
                   else "review_required_incomplete_headline"),
        "reported_metrics": records,
        "underlying_index_levels_verified": False,
        "human_reviewed": False, "historical_pit_certified": False,
    }


def _explicit_employment_revisions(text, source, digest):
    if source["release_kind"] != "employment":
        return []
    month, section = _heading_section(text, source)
    anchor = re.search(r"The change in total nonfarm payroll employment for\s+"
                       r"(?:December|January|February|March|April|May|June|July|August|September)",
                       section, re.I)
    if not anchor:
        return []
    block = section[anchor.start():anchor.start()+1050]
    regex = (r"(?:the change in total nonfarm payroll employment for|the change for)\s+"
             r"(?P<month>January|February|March|April|May|June|July|August|September|October|November|December)"
             r"\s+was revised\s+(?P<direction>up|down)\s+by\s+"
             r"(?P<revision>[0-9]{1,3}(?:,[0-9]{3})*),\s+from\s+"
             r"(?P<prior>[+-]?[0-9]{1,3}(?:,[0-9]{3})*)\s+to\s+"
             r"(?P<new>[+-]?[0-9]{1,3}(?:,[0-9]{3})*)")
    output = []
    yyyy = int(source["observation_period"][:4])
    current_month = int(source["observation_period"][5:])
    for m in re.finditer(regex, block, re.I):
        prior_month = MONTH.index(m.group("month").title()) + 1
        target_year = yyyy if prior_month < current_month else yyyy - 1
        prior = Decimal(m.group("prior").replace(",", ""))
        new = Decimal(m.group("new").replace(",", ""))
        delta = new - prior
        magnitude = Decimal(m.group("revision").replace(",", ""))
        expected_delta = magnitude if m.group("direction").lower() == "up" else -magnitude
        if delta != expected_delta:
            continue
        output.append({
            "target_source_series_id": "bls.payroll",
            "target_observation_period": f"{target_year:04d}-{prior_month:02d}",
            "reporting_release_artifact_id": source["artifact_id"],
            "reporting_release_sha256": digest,
            "source_reported_prior_value": decimal_text(prior),
            "source_reported_revised_value": decimal_text(new),
            "delta_persons": decimal_text(delta),
            "unit": "persons_change_month",
            "revision_claim_status": "official_release_narrative_unverified_for_pit",
            "historical_revision_chain_complete": False,
        })
    return output


def review(directory, *, registry=None):
    registry = registry or load_candidates()
    directory = secure_directory(directory)
    sources = {x["artifact_id"]: x for x in registry["entries"]}
    with custody_lock(directory):
        entries, custody_hash = _load_journal(directory, registry)
        if not entries:
            return {
                "schema_version": 1,
                "report_type": "asset_compass_v53_source_reported_figures",
                "status": "no_verified_private_custody",
                "requested_sources": len(sources), "extracted_versions": 0,
                "source_results": [], "observed_byte_change_diffs": [],
                "cross_release_revision_claims": [],
                "historical_pit_series_approved": 0,
                "validated_for_live_scoring": False,
            }
        extracted = []
        for entry in entries:
            src = sources[entry["artifact_id"]]
            raw = secure_regular(directory / f"{entry['artifact_id']}-{entry['sha256']}.html")
            item = extract(src, raw, entry["sha256"])
            item["captured_at"] = entry["captured_at"]
            extracted.append(item)
        # Compare only the SAME source document and SAME metric definition.
        versions = {}
        for item in extracted:
            versions.setdefault(item["artifact_id"], []).append(item)
        diffs = []
        for source_id, group in versions.items():
            for old, new in zip(group, group[1:]):
                if old["sha256"] == new["sha256"]:
                    continue
                old_map = {(r["source_series_id"], r["statistic"], r["seasonal_adjustment"]): r
                           for r in old["reported_metrics"]}
                new_map = {(r["source_series_id"], r["statistic"], r["seasonal_adjustment"]): r
                           for r in new["reported_metrics"]}
                for key in sorted(set(old_map) & set(new_map)):
                    a, b = old_map[key], new_map[key]
                    if a["value_reported"] != b["value_reported"]:
                        diffs.append({
                            "artifact_id": source_id, "source_series_id": key[0],
                            "statistic": key[1], "seasonal_adjustment": key[2],
                            "observed_prior_sha256": old["sha256"],
                            "observed_later_sha256": new["sha256"],
                            "prior_value": a["value_reported"],
                            "later_value": b["value_reported"],
                            "delta": decimal_text(Decimal(b["value_reported"])
                                                  - Decimal(a["value_reported"])),
                            "classification": "observed_page_value_change_not_certified_historical_revision",
                            "historical_revision_chain_complete": False,
                        })
        latest = {key: items[-1] for key, items in versions.items()}
        claims = []
        for source_id, item in latest.items():
            source = sources[source_id]
            if source["release_kind"] != "employment":
                continue
            raw = secure_regular(directory / f"{source_id}-{item['sha256']}.html")
            for claim in _explicit_employment_revisions(visible(raw), source, item["sha256"]):
                original = next((x for x in latest.values()
                                 if x["source_family"] == "employment"
                                 and x["observation_period"] == claim["target_observation_period"]), None)
                original_values = [] if original is None else [
                    r for r in original["reported_metrics"]
                    if r["source_series_id"] == "bls.payroll"]
                claim["original_candidate_sha256"] = original["sha256"] if original else None
                claim["original_headline_value"] = (
                    original_values[0]["value_reported"] if original_values else None)
                claim["prior_value_matches_observed_original"] = (
                    bool(original_values) and
                    original_values[0]["value_reported"] == claim["source_reported_prior_value"])
                claims.append(claim)
    complete = sum(x["status"] == "candidate_complete_unverified" for x in latest.values())
    return {
        "schema_version": 1,
        "report_type": "asset_compass_v53_source_reported_figures",
        "status": "research_candidates_only",
        "custody_last_sha256": custody_hash,
        "requested_sources": len(sources),
        "extracted_versions": len(extracted),
        "distinct_candidate_sources": len(latest),
        "complete_candidate_sources": complete,
        "incomplete_candidate_sources": len(latest) - complete,
        "candidate_metrics_from_latest_snapshots": sum(len(x["reported_metrics"]) for x in latest.values()),
        "source_results": sorted(latest.values(), key=lambda x: x["artifact_id"]),
        "observed_byte_change_diffs": diffs,
        "cross_release_revision_claims": claims,
        "underlying_index_levels_verified": False,
        "source_publisher_publication_instant_verified": False,
        "first_original_release_bytes_verified": False,
        "full_historical_revision_lineage_verified": False,
        "independent_human_review_verified": False,
        "historical_pit_series_approved": 0,
        "validated_for_live_scoring": False,
        "automatic_investment_alerts_enabled": False,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--private-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=OUT)
    parser.add_argument("--require-complete", action="store_true")
    args = parser.parse_args()
    target = _private_path(args.output)
    result = review(args.private_dir)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n",
                      encoding="utf-8")
    print(json.dumps({
        "status": result["status"],
        "candidate_source_documents": result.get("distinct_candidate_sources", 0),
        "complete_candidate_sources": result.get("complete_candidate_sources", 0),
        "candidate_metrics": result.get("candidate_metrics_from_latest_snapshots", 0),
        "cross_release_revision_claims": len(result["cross_release_revision_claims"]),
        "observed_byte_change_diffs": len(result["observed_byte_change_diffs"]),
        "historical_pit_series_approved": 0,
        "validated_for_live_scoring": False,
    }))
    if args.require_complete and (
        result["status"] != "research_candidates_only"
        or result["complete_candidate_sources"] != result["requested_sources"]):
        raise SystemExit(2)


if __name__ == "__main__":
    main()
