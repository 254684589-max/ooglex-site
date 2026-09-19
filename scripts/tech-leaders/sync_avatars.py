#!/usr/bin/env python3
"""
Audit and synchronize Tech Leaders avatar metadata.

Policy:
- Active records with a valid X handle are resolved only through the Ooglex
  self-hosted avatar endpoint.
- Only responses whose X-Ooglex-Avatar-Source header proves an X-original
  transport are classified as x_direct.
- Any record that cannot be verified is marked pending_review.
- Binary avatar bytes remain in Cloudflare R2; the catalog stores metadata only.

The script is idempotent and can optionally rewrite leaders.json.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import datetime as dt
import json
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

HANDLE_RE = re.compile(r"^[A-Za-z0-9_]{1,15}$")
X_ORIGINAL_PREFIXES = ("x_profile_redirect", "x_syndication")


def utc_now() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc)


def iso_now() -> str:
    return utc_now().replace(microsecond=0).isoformat().replace("+00:00", "Z")


def date_today() -> str:
    return utc_now().date().isoformat()


def normalize_handle(value: Any) -> str:
    handle = str(value or "").strip().lstrip("@")
    return handle if HANDLE_RE.fullmatch(handle) else ""


def normalize_source(value: Any) -> str:
    return str(value or "").strip().lower()


def is_x_original_source(value: Any) -> bool:
    source = normalize_source(value)
    return any(source.startswith(prefix) for prefix in X_ORIGINAL_PREFIXES)


def avatar_endpoint(base_url: str, handle: str) -> str:
    return (
        base_url.rstrip("/")
        + "/v1/tech-leaders/avatar?handle="
        + urllib.parse.quote(handle, safe="")
    )


def fetch_avatar(base_url: str, leader: dict[str, Any], retries: int, timeout: int) -> dict[str, Any]:
    raw_handle = str(leader.get("handle") or "").strip()
    handle = normalize_handle(raw_handle)
    identity = {
        "id": str(leader.get("id") or ""),
        "name": str(leader.get("name_en") or leader.get("name") or leader.get("name_zh") or ""),
        "handle": handle or raw_handle.lstrip("@"),
    }

    if not raw_handle:
        return {
            **identity,
            "ok": False,
            "status": "pending_review",
            "source_type": "pending_review",
            "reason": "missing_handle",
        }
    if not handle:
        return {
            **identity,
            "ok": False,
            "status": "pending_review",
            "source_type": "pending_review",
            "reason": "invalid_handle",
        }

    url = avatar_endpoint(base_url, handle)
    last_error = "unknown_error"

    for attempt in range(1, max(1, retries) + 1):
        try:
            req = urllib.request.Request(
                url,
                headers={
                    "User-Agent": "Ooglex-Avatar-Sync/5.0",
                    "Accept": "image/avif,image/webp,image/png,image/jpeg,image/*,*/*;q=0.8",
                    "Cache-Control": "no-cache",
                },
            )
            with urllib.request.urlopen(req, timeout=max(5, timeout)) as resp:
                content_type = (resp.headers.get("Content-Type") or "").split(";")[0].strip().lower()
                source = resp.headers.get("X-Ooglex-Avatar-Source") or ""
                response_handle = resp.headers.get("X-Ooglex-Avatar-Handle") or ""
                sample = resp.read(96)

                if (
                    resp.status == 200
                    and content_type.startswith("image/")
                    and sample
                    and is_x_original_source(source)
                ):
                    return {
                        **identity,
                        "ok": True,
                        "status": "verified",
                        "source_type": "x_direct",
                        "source_transport": source,
                        "content_type": content_type,
                        "response_handle": response_handle,
                        "avatar_url": url,
                        "origin_url": f"https://x.com/{handle}",
                    }

                if resp.status == 200 and content_type.startswith("image/") and sample:
                    last_error = f"non_x_original_source:{source or 'unknown'}"
                else:
                    last_error = f"bad_response:{resp.status}:{content_type or 'unknown'}"

        except urllib.error.HTTPError as exc:
            last_error = f"http_{exc.code}:{exc.reason}"
            if exc.code == 429 and attempt < retries:
                retry_after = 0
                try:
                    retry_after = int(exc.headers.get("Retry-After") or 0)
                except (TypeError, ValueError):
                    pass
                time.sleep(max(retry_after, min(attempt * 4, 20)))
                continue
        except Exception as exc:  # noqa: BLE001 - audit should record exact runtime failure
            last_error = f"{type(exc).__name__}:{exc}"

        if attempt < retries:
            time.sleep(min(attempt * 2, 8))

    return {
        **identity,
        "ok": False,
        "status": "pending_review",
        "source_type": "pending_review",
        "reason": last_error,
        "avatar_url": url,
        "origin_url": f"https://x.com/{handle}",
    }


def should_audit(leader: dict[str, Any], include_inactive: bool) -> bool:
    if include_inactive:
        return True
    state = str(leader.get("admission_status") or "active").strip().lower()
    return state == "active"


def apply_result(leader: dict[str, Any], result: dict[str, Any], checked_at: str, checked_date: str, base_url: str) -> None:
    handle = normalize_handle(leader.get("handle"))

    leader["avatar_audited_at"] = checked_at
    leader["avatar_source_type"] = result["source_type"]
    leader["avatar_audit_status"] = result["status"]
    leader["avatar_policy"] = "x_original_only"
    leader["avatar_fallback"] = "local_initials_svg"

    if handle:
        leader["avatar_url"] = avatar_endpoint(base_url, handle)
        leader["avatar_origin_url"] = f"https://x.com/{handle}"

    if result["ok"]:
        leader["avatar_verified"] = True
        leader["avatar_verified_at"] = checked_at
        leader["avatar_updated_at"] = checked_date
        leader["avatar_status"] = "x_original_verified"
        leader["avatar_source"] = "Ooglex R2 cache · X original profile avatar"
        leader["avatar_source_transport"] = result.get("source_transport") or ""
        leader.pop("avatar_review_reason", None)
    else:
        previous_verified = leader.get("avatar_verified_at")
        if previous_verified:
            leader["avatar_last_verified_at"] = previous_verified
        leader["avatar_verified"] = False
        leader["avatar_status"] = "pending_review"
        leader["avatar_source"] = "Pending review · X original avatar not verified"
        leader["avatar_source_transport"] = ""
        leader["avatar_review_reason"] = result.get("reason") or "unverified"
        if not handle:
            leader["avatar_url"] = ""


def write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Audit and sync Tech Leaders X avatars.")
    parser.add_argument("--catalog", required=True)
    parser.add_argument("--base-url", default="https://pro-api.ooglex.com")
    parser.add_argument("--audit-out")
    parser.add_argument("--write-catalog", action="store_true")
    parser.add_argument("--workers", type=int, default=4)
    parser.add_argument("--retries", type=int, default=3)
    parser.add_argument("--timeout", type=int, default=25)
    parser.add_argument("--include-inactive", action="store_true")
    parser.add_argument("--fail-on-pending", action="store_true")
    args = parser.parse_args()

    catalog_path = Path(args.catalog)
    data = json.loads(catalog_path.read_text(encoding="utf-8"))
    leaders = data.get("leaders")
    if not isinstance(leaders, list):
        raise SystemExit("catalog_missing_leaders")

    indexed: list[tuple[int, dict[str, Any]]] = [
        (idx, leader)
        for idx, leader in enumerate(leaders)
        if isinstance(leader, dict) and should_audit(leader, args.include_inactive)
    ]

    checked_at = iso_now()
    checked_date = date_today()
    results_by_index: dict[int, dict[str, Any]] = {}

    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, args.workers)) as pool:
        pending = {
            pool.submit(
                fetch_avatar,
                args.base_url,
                leader,
                max(1, args.retries),
                max(5, args.timeout),
            ): idx
            for idx, leader in indexed
        }
        for future in concurrent.futures.as_completed(pending):
            idx = pending[future]
            result = future.result()
            results_by_index[idx] = result
            prefix = "OK  " if result["ok"] else "PEND"
            handle = result.get("handle") or "(no handle)"
            detail = result.get("source_transport") or result.get("reason") or ""
            print(f"{prefix} @{handle} {detail}")

    audit_items: list[dict[str, Any]] = []
    for idx, leader in indexed:
        result = results_by_index[idx]
        if args.write_catalog:
            apply_result(leader, result, checked_at, checked_date, args.base_url)
        audit_items.append(result)

    verified = sum(1 for item in audit_items if item["ok"])
    pending_count = len(audit_items) - verified
    missing_handles = sum(1 for item in audit_items if item.get("reason") == "missing_handle")
    invalid_handles = sum(1 for item in audit_items if item.get("reason") == "invalid_handle")

    audit = {
        "schema_version": 1,
        "policy": "x_original_only",
        "checked_at": checked_at,
        "catalog": str(catalog_path),
        "total_checked": len(audit_items),
        "x_direct": verified,
        "pending_review": pending_count,
        "missing_handle": missing_handles,
        "invalid_handle": invalid_handles,
        "items": sorted(
            audit_items,
            key=lambda item: (
                0 if item["ok"] else 1,
                str(item.get("handle") or "").lower(),
                str(item.get("id") or ""),
            ),
        ),
    }

    data["avatar_audit"] = {
        "schema_version": audit["schema_version"],
        "policy": audit["policy"],
        "checked_at": checked_at,
        "total_checked": len(audit_items),
        "x_direct": verified,
        "pending_review": pending_count,
    }

    if args.write_catalog:
        write_json(catalog_path, data)

    if args.audit_out:
        write_json(Path(args.audit_out), audit)

    print(
        f"Avatar audit summary: {verified}/{len(audit_items)} x_direct, "
        f"{pending_count} pending_review, {missing_handles} missing handle(s), "
        f"{invalid_handles} invalid handle(s)"
    )

    if args.fail_on_pending and pending_count:
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
