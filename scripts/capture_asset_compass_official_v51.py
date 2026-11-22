#!/usr/bin/env python3
"""V51 official-release capture, without retrospective PIT or scoring claims.

Capturing an archived webpage today proves its PRESENT bytes and retrieval
time, not that identical bytes were available at the historical embargo time.
Retain bytes in a private directory OUTSIDE this public website repository.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import tempfile
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]
CANDIDATES = ROOT / "data" / "asset-compass-v51-release-candidates.json"
DEFAULT_OUTPUT = Path("/tmp/ooglex-v51-release-capture-manifest.json")
MAX_BYTES = 3_000_000
REQUIRED_SERIES = {"bls.cpi", "bls.core_cpi", "bls.unemployment",
                   "bls.payroll", "bea.core_pce"}
ALLOWED_PREFIX = {
    "BLS": ("/news.release/archives/cpi_", "/news.release/archives/empsit_"),
    "BEA": ("/news/2025/personal-income-and-outlays-",),
}
ALLOWED_HOST = {"BLS": "www.bls.gov", "BEA": "www.bea.gov"}
BLOCKED_2025 = {("BLS", "cpi", "2025-10"), ("BLS", "employment", "2025-10")}


def _private_path(path: Path) -> Path:
    resolved = path.expanduser().resolve()
    if resolved == ROOT or ROOT in resolved.parents:
        raise ValueError("Private evidence or manifest must stay outside public repository")
    return resolved


def _canonical(url: str, publisher: str) -> str:
    if publisher not in ALLOWED_HOST or not isinstance(url, str):
        raise ValueError("Unregistered source publisher")
    parsed = urlsplit(url)
    if (parsed.scheme != "https" or parsed.hostname != ALLOWED_HOST[publisher]
            or parsed.port not in (None, 443) or parsed.username is not None
            or parsed.password is not None or parsed.query or parsed.fragment
            or not any(parsed.path.startswith(prefix) for prefix in ALLOWED_PREFIX[publisher])
            or any(x in parsed.path.lower() for x in ("%2f", "%5c", "..", "\\"))):
        raise ValueError("Unsafe or non-official historical release URL")
    if publisher == "BLS" and not parsed.path.endswith(".htm"):
        raise ValueError("BLS release must use immutable archive HTML URL")
    if publisher == "BEA" and parsed.path.endswith("/"):
        raise ValueError("BEA release must use an exact archived page")
    return parsed.geturl()


def load_candidates(path: Path = CANDIDATES) -> dict:
    data = json.loads(path.read_text(encoding="utf-8"))
    if (data.get("schema_version") != 1
            or data.get("report_type") != "asset_compass_v51_release_capture_candidates"
            or data.get("status") != "research_only"
            or data.get("publication_candidate_date_not_pit_time") is not True
            or not isinstance(data.get("entries"), list)
            or len(data["entries"]) != 7):
        raise ValueError("Invalid V51 candidate registry")
    blocked = data.get("known_not_published", [])
    if {(x.get("publisher"), x.get("release_kind"), x.get("observation_period"))
            for x in blocked} != BLOCKED_2025:
        raise ValueError("Mandatory October 2025 no-publication exceptions missing")
    ids, links, series = set(), set(), set()
    for x in data["entries"]:
        key = (x.get("publisher"), x.get("release_kind"), x.get("observation_period"))
        if key in BLOCKED_2025:
            raise ValueError("Cannot manufacture October 2025 release")
        if (not re.fullmatch(r"[a-z0-9-]{8,72}", x.get("artifact_id", ""))
                or not re.fullmatch(r"20[0-9]{2}-(0[1-9]|1[0-2])", x.get("observation_period", ""))
                or x.get("capture_status") != "not_run"
                or any(x.get(flag) is not False for flag in (
                    "release_timestamp_independently_verified",
                    "original_bytes_available_at_candidate_time_verified",
                    "revision_lineage_complete", "scoring_eligible"))):
            raise ValueError("Invalid or pre-certified historical candidate")
        if (x["publisher"], x["release_kind"]) not in {
                ("BLS", "cpi"), ("BLS", "employment"), ("BEA", "pio")}:
            raise ValueError("Unexpected official-release family")
        _canonical(x.get("source_url"), x["publisher"])
        expected_path = x["source_url"].split("/")[-1].lower()
        if x["publisher"] == "BLS":
            archive_kind = "cpi_" if x["release_kind"] == "cpi" else "empsit_"
            if not expected_path.startswith(archive_kind):
                raise ValueError("BLS release-kind mismatch")
        else:
            if not expected_path.startswith("personal-income-and-outlays-"):
                raise ValueError("BEA release-kind mismatch")
        if (not re.fullmatch(r"20[0-9]{2}-[01][0-9]-[0-3][0-9]",
                             x.get("scheduled_release_date_candidate_unverified", ""))):
            raise ValueError("Missing candidate schedule date")
        if (not isinstance(x.get("covered_source_series"), list)
                or not x["covered_source_series"]
                or not set(x["covered_source_series"]) <= REQUIRED_SERIES):
            raise ValueError("Invalid source-series mapping")
        expected = ({"bls.cpi", "bls.core_cpi"} if x["release_kind"] == "cpi"
                    else {"bls.unemployment", "bls.payroll"} if x["release_kind"] == "employment"
                    else {"bea.core_pce"})
        if set(x["covered_source_series"]) != expected:
            raise ValueError("Incomplete macro factor source mapping")
        if x["artifact_id"] in ids or x["source_url"] in links:
            raise ValueError("Duplicate source release candidate")
        ids.add(x["artifact_id"])
        links.add(x["source_url"])
        series.update(x["covered_source_series"])
    if series != REQUIRED_SERIES:
        raise ValueError("V51 source registry does not cover the targeted five series")
    return data


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise ValueError("Unexpected historical release redirect")


def _download(candidate: dict, *, opener=None) -> bytes:
    source = _canonical(candidate["source_url"], candidate["publisher"])
    request = urllib.request.Request(
        source, headers={"User-Agent": "OoglexResearch/1.0 (+https://www.ooglex.com/)",
                         "Accept": "text/html"}, method="GET")
    client = opener or urllib.request.build_opener(NoRedirect())
    with client.open(request, timeout=25) as response:
        final_url = response.geturl()
        if final_url != source:
            raise ValueError("Historical release redirected")
        content_type = response.headers.get("Content-Type", "").lower()
        if "text/html" not in content_type:
            raise ValueError("Unexpected HTML archive content-type")
        body = response.read(MAX_BYTES + 1)
    if not body or len(body) > MAX_BYTES:
        raise ValueError("Release empty or exceeds maximum size")
    lower = body.lower()
    if b"<html" not in lower[:2000] and b"<!doctype html" not in lower[:2000]:
        raise ValueError("Source response is not HTML")
    markers = (b"consumer price index" if candidate["release_kind"] == "cpi"
               else b"employment situation" if candidate["release_kind"] == "employment"
               else b"personal income and outlays")
    if markers not in lower:
        raise ValueError("Unexpected archived-release subject")
    return body


def _save_private(candidate: dict, body: bytes, digest: str, directory: Path) -> None:
    directory = _private_path(directory)
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(directory, 0o700)
    final = directory / (candidate["artifact_id"] + "-" + digest + ".html")
    if final.exists():
        if not final.is_file() or final.is_symlink():
            raise ValueError("Evidence path is not a regular file")
        if hashlib.sha256(final.read_bytes()).hexdigest() != digest:
            raise ValueError("Existing evidence hash mismatch")
        return
    fd, tmp = tempfile.mkstemp(prefix=".v51-", dir=directory)
    try:
        with os.fdopen(fd, "wb") as output:
            output.write(body)
            output.flush()
            os.fsync(output.fileno())
        os.chmod(tmp, 0o600)
        os.replace(tmp, final)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)
    if hashlib.sha256(final.read_bytes()).hexdigest() != digest:
        raise ValueError("Evidence byte verification failed")


def capture(candidate: dict, *, now: datetime | None = None,
            private_dir: Path | None = None, opener=None) -> dict:
    instant = now or datetime.now(timezone.utc)
    if instant.tzinfo is None:
        raise ValueError("Capture timestamp must be timezone-aware")
    instant = instant.astimezone(timezone.utc)
    raw = _download(candidate, opener=opener)
    digest = hashlib.sha256(raw).hexdigest()
    if private_dir is not None:
        _save_private(candidate, raw, digest, private_dir)
    return {
        "artifact_id": candidate["artifact_id"],
        "publisher": candidate["publisher"],
        "release_kind": candidate["release_kind"],
        "observation_period": candidate["observation_period"],
        "source_url": candidate["source_url"],
        "scheduled_release_date_candidate_unverified":
            candidate["scheduled_release_date_candidate_unverified"],
        "captured_at": instant.isoformat().replace("+00:00", "Z"),
        "sha256": digest, "byte_size": len(raw),
        "raw_bytes_saved_privately": private_dir is not None,
        "raw_bytes_publicly_exported": False,
        "exact_original_publication_time_verified": False,
        "historical_artifact_identity_verified": False,
        "historical_release_value_verified": False,
        "full_revision_chain_verified": False,
        "eligible_for_point_in_time_backtest": False,
        "validated_for_live_scoring": False,
    }


def collect(*, candidates: dict | None = None, private_dir: Path | None = None,
            fetcher=capture, now: datetime | None = None) -> dict:
    registry = candidates if candidates is not None else load_candidates()
    checked = now or datetime.now(timezone.utc)
    if checked.tzinfo is None:
        raise ValueError("Capture timestamp must be timezone-aware")
    if private_dir is not None:
        _private_path(private_dir)
    results = {}
    for source in registry["entries"]:
        ident = source["artifact_id"]
        try:
            receipt = fetcher(source, now=checked, private_dir=private_dir)
            if (receipt.get("artifact_id") != ident
                    or receipt.get("source_url") != source["source_url"]
                    or receipt.get("observation_period") != source["observation_period"]
                    or not re.fullmatch(r"[0-9a-f]{64}", receipt.get("sha256", ""))
                    or type(receipt.get("byte_size")) is not int or receipt["byte_size"] < 1
                    or receipt.get("raw_bytes_saved_privately") is not (private_dir is not None)
                    or any(receipt.get(flag) is not False for flag in (
                        "raw_bytes_publicly_exported",
                        "exact_original_publication_time_verified",
                        "historical_artifact_identity_verified",
                        "historical_release_value_verified",
                        "full_revision_chain_verified",
                        "eligible_for_point_in_time_backtest", "validated_for_live_scoring"))):
                raise ValueError("Receipt contradicts source or V51 safety contract")
            results[ident] = {"status": "retrieved_now_not_historically_certified",
                              "receipt": receipt}
        except (ValueError, OSError, TimeoutError, RuntimeError) as error:
            results[ident] = {"status": "capture_failed",
                              "error_type": type(error).__name__}
    successful = sum(v["status"] == "retrieved_now_not_historically_certified"
                     for v in results.values())
    return {
        "schema_version": 1,
        "report_type": "asset_compass_v51_official_release_capture",
        "checked_at": checked.astimezone(timezone.utc).isoformat(),
        "requested": len(registry["entries"]), "retrieved_now": successful,
        "failed": len(registry["entries"]) - successful,
        "target_source_series": sorted(REQUIRED_SERIES),
        "known_no_release_periods": registry["known_not_published"],
        "results": results,
        "raw_custody_scope": "local_private_only" if private_dir else "ephemeral_only",
        "historical_pit_certified_source_series": 0,
        "eligible_for_point_in_time_backtest": False,
        "validated_for_live_scoring": False,
        "automatic_investment_alerts_enabled": False,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--private-dir", type=Path)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--fail-if-incomplete", action="store_true")
    args = parser.parse_args()
    output = _private_path(args.output)
    if args.private_dir is not None:
        _private_path(args.private_dir)
    registry = load_candidates()
    if args.dry_run:
        print(json.dumps({"requested": len(registry["entries"]),
                          "source_series": sorted(REQUIRED_SERIES),
                          "known_no_release": len(BLOCKED_2025),
                          "live_fetch_performed": False,
                          "historical_pit_certified_source_series": 0}))
        return
    report = collect(candidates=registry, private_dir=args.private_dir)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n",
                      encoding="utf-8")
    print(json.dumps({"requested": report["requested"],
                      "retrieved_now": report["retrieved_now"],
                      "failed": report["failed"],
                      "historical_pit_certified_source_series": 0,
                      "raw_custody_scope": report["raw_custody_scope"]}))
    if args.fail_if_incomplete and report["failed"]:
        raise SystemExit(2)


if __name__ == "__main__":
    main()
