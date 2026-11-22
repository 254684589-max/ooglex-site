#!/usr/bin/env python3
"""V34 capture original BLS CPI archive bytes as private, research-only evidence.

A file downloaded today is a HISTORICAL ARTIFACT CAPTURED TODAY. Its URL and
embedded scheduled embargo statement do NOT independently verify that exact
file's byte representation was publicly available at that historical instant.
No source publication timestamps, values, or PIT rights are self-certified.
"""
import argparse
import hashlib
import json
import os
import tempfile
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlsplit

from scripts.archive_asset_compass_observations import ROOT

# Direct archived release, not a moving latest-results URL.
ALLOWLIST = {
    "bls-cpi-2024-12-release": {
        "url": "https://www.bls.gov/news.release/archives/cpi_01152025.htm",
        "observation_period": "2024-12",
        "release_date_candidate": "2025-01-15",
        "publisher": "US Bureau of Labor Statistics",
        "media_type": "text/html",
    },
    "bls-cpi-2025-01-release": {
        "url": "https://www.bls.gov/news.release/archives/cpi_02122025.htm",
        "observation_period": "2025-01",
        "release_date_candidate": "2025-02-12",
        "publisher": "US Bureau of Labor Statistics",
        "media_type": "text/html",
    },
    "bls-cpi-2025-02-release": {
        "url": "https://www.bls.gov/news.release/archives/cpi_03122025.htm",
        "observation_period": "2025-02",
        "release_date_candidate": "2025-03-12",
        "publisher": "US Bureau of Labor Statistics",
        "media_type": "text/html",
    },
}
MAX_BYTES = 2_000_000
DEFAULT_DIR = Path.home() / ".local" / "share" / "ooglex" / "private-historical-evidence"
DEFAULT_METADATA = Path("/tmp/ooglex-v34-official-evidence.json")


def normalize_url(url):
    parsed = urlsplit(url)
    if (parsed.scheme != "https" or parsed.hostname != "www.bls.gov"
            or parsed.username is not None or parsed.password is not None
            or parsed.port not in (None, 443) or parsed.query or parsed.fragment
            or not parsed.path.startswith("/news.release/archives/cpi_")
            or not parsed.path.endswith(".htm")):
        raise ValueError("Unapproved official BLS archive URL")
    return parsed.geturl()


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        # A redirect can bypass the BLS host allowlist.
        raise ValueError("Unexpected redirect: official archive must be direct")


def acquire(identifier, *, now=None, persist_dir=None, opener=None):
    if identifier not in ALLOWLIST:
        raise ValueError("Unregistered original release document")
    declared = ALLOWLIST[identifier]
    source = normalize_url(declared["url"])
    checked = now or datetime.now(timezone.utc)
    if checked.tzinfo is None:
        raise ValueError("Capture time must carry timezone")
    checked = checked.astimezone(timezone.utc)
    if persist_dir is not None:
        directory = Path(persist_dir).resolve()
        if directory.is_relative_to(ROOT.resolve()):
            raise ValueError("Private release content must remain outside repository")
    request = urllib.request.Request(
        source, headers={"User-Agent": "OoglexResearch/1.0 (+https://www.ooglex.com/)",
                         "Accept": "text/html"}, method="GET")
    client = opener or urllib.request.build_opener(NoRedirect())
    with client.open(request, timeout=25) as response:
        content_type = response.headers.get("Content-Type", "").lower()
        if "text/html" not in content_type:
            raise ValueError("Unexpected content type for archived HTML release")
        raw = response.read(MAX_BYTES + 1)
    if not raw or len(raw) > MAX_BYTES:
        raise ValueError("BLS archived document empty or exceeds safety limit")
    body = raw[:1024].lower()
    if b"<html" not in body and b"<!doctype html" not in body:
        raise ValueError("Source did not return a plausible HTML document")
    if b"consumer price index" not in raw.lower():
        raise ValueError("Archive document does not identify CPI release")
    digest = hashlib.sha256(raw).hexdigest()
    stored = False
    if persist_dir is not None:
        directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        os.chmod(directory, 0o700)
        final = directory / f"{identifier}-{digest}.html"
        if final.exists():
            if hashlib.sha256(final.read_bytes()).hexdigest() != digest:
                raise ValueError("Immutable evidence file mismatch")
        else:
            fd, temporary = tempfile.mkstemp(prefix=".release-", dir=directory)
            try:
                with os.fdopen(fd,"wb") as stream:
                    stream.write(raw)
                os.chmod(temporary, 0o600)
                os.replace(temporary, final)
            finally:
                if os.path.exists(temporary):
                    os.unlink(temporary)
        stored = True
    return {
        "schema_version": 1, "report_type": "asset_compass_v34_release_artifact_receipt",
        "artifact_id": identifier, "source_url": source,
        "publisher": declared["publisher"],
        "historical_observation_period": declared["observation_period"],
        "original_release_date_candidate_unverified": declared["release_date_candidate"],
        "captured_at": checked.isoformat(),
        "sha256": digest, "byte_size": len(raw),
        "raw_artifact_saved_in_private_directory": stored,
        "raw_artifact_exported_to_public_repo": False,
        "official_original_release_timestamp_verified": False,
        "historical_byte_availability_verified": False,
        "historical_value_extracted_or_verified": False,
        "redistribution_license_approved": False,
        "eligible_for_point_in_time_backtest": False,
        "validated_for_live_scoring": False,
    }


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--artifact-id",default="bls-cpi-2024-12-release",
                   choices=sorted(ALLOWLIST))
    p.add_argument("--private-dir",type=Path,help="Required for saving raw file; MUST be outside website repo")
    p.add_argument("--output",type=Path,default=DEFAULT_METADATA)
    args=p.parse_args()
    if args.private_dir and args.output.resolve().is_relative_to(ROOT.resolve()):
        raise ValueError("Capture receipt with private evidence cannot be saved in site repository")
    receipt=acquire(args.artifact_id,persist_dir=args.private_dir)
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(json.dumps({"artifact_id":receipt["artifact_id"],
        "byte_size":receipt["byte_size"],"sha256":receipt["sha256"],
        "raw_artifact_saved_privately":receipt["raw_artifact_saved_in_private_directory"],
        "pit_eligible":False},ensure_ascii=False))


if __name__=="__main__":
    main()
