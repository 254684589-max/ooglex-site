#!/usr/bin/env python3
"""
Audit and synchronize Tech Leaders avatar metadata.

Priority:
1. Current X profile avatar.
2. X-avatar proxy of the same profile image.
3. Verified company / institution portrait.
4. Conservative Wikipedia / Wikimedia portrait fallback.
5. Local initials only when no usable portrait can be verified.

Binary image bytes remain in Cloudflare R2. The catalog stores source metadata.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import datetime as dt
import json
import re
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

HANDLE_RE = re.compile(r"^[A-Za-z0-9_]{1,15}$")
POLICY = "x_original_then_verified_fallback"
USABLE_SOURCE_TYPES = {
    "x_original",
    "x_original_proxy",
    "official_fallback",
    "public_fallback",
    "generated_fallback",
}


def utc_now() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc)


def iso_now() -> str:
    return utc_now().replace(microsecond=0).isoformat().replace("+00:00", "Z")


def date_today() -> str:
    return utc_now().date().isoformat()


def normalize_handle(value: Any) -> str:
    handle = str(value or "").strip().lstrip("@")
    return handle if HANDLE_RE.fullmatch(handle) else ""


def leader_name(leader: dict[str, Any]) -> str:
    return str(
        leader.get("name_en")
        or leader.get("name")
        or leader.get("name_zh")
        or leader.get("zh")
        or ""
    ).strip()


def leader_company(leader: dict[str, Any]) -> str:
    return str(
        leader.get("company_en")
        or leader.get("company_zh")
        or leader.get("role")
        or ""
    ).strip()


def infer_source_type(source: Any) -> str:
    value = str(source or "").strip().lower()
    value = re.sub(r"-r2(?:-cache)?$", "", value)
    if value in {"x_profile_redirect_x", "x_profile_redirect", "x_followbutton", "x_syndication"}:
        return "x_original"
    if value in {"unavatar_x", "fxtwitter_profile"}:
        return "x_original_proxy"
    if value == "official_override":
        return "official_fallback"
    if value == "generated_initials":
        return "generated_fallback"
    if value in {"wikipedia", "wikimedia_commons"}:
        return "public_fallback"
    return "unknown"


def result_status(source_type: str) -> str:
    if source_type == "x_original":
        return "x_original"
    if source_type == "x_original_proxy":
        return "x_original_proxy"
    if source_type in {"official_fallback", "public_fallback", "generated_fallback"}:
        return "fallback"
    return "pending_review"


def avatar_endpoint(base_url: str, leader: dict[str, Any], handle: str) -> str:
    query = urllib.parse.urlencode(
        {
            "handle": handle,
            "name": leader_name(leader),
            "company": leader_company(leader),
        }
    )
    return f"{base_url.rstrip('/')}/v1/tech-leaders/avatar?{query}"


def fetch_avatar(
    base_url: str,
    leader: dict[str, Any],
    retries: int,
    timeout: int,
) -> dict[str, Any]:
    raw_handle = str(leader.get("handle") or "").strip()
    handle = normalize_handle(raw_handle)
    identity = {
        "id": str(leader.get("id") or ""),
        "name": leader_name(leader),
        "company": leader_company(leader),
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

    url = avatar_endpoint(base_url, leader, handle)
    last_error = "unknown_error"

    for attempt in range(1, max(1, retries) + 1):
        try:
            req = urllib.request.Request(
                url,
                headers={
                    "User-Agent": "Ooglex-Avatar-Sync/5.1",
                    "Accept": "image/avif,image/webp,image/png,image/jpeg,image/*,*/*;q=0.8",
                    "Cache-Control": "no-cache",
                },
            )
            with urllib.request.urlopen(req, timeout=max(5, timeout)) as resp:
                content_type = (
                    resp.headers.get("Content-Type") or ""
                ).split(";")[0].strip().lower()
                source = resp.headers.get("X-Ooglex-Avatar-Source") or ""
                source_type = (
                    resp.headers.get("X-Ooglex-Avatar-Source-Type")
                    or infer_source_type(source)
                )
                response_handle = resp.headers.get("X-Ooglex-Avatar-Handle") or ""
                sample = resp.read(96)

                if (
                    resp.status == 200
                    and content_type.startswith("image/")
                    and sample
                    and source_type in USABLE_SOURCE_TYPES
                ):
                    return {
                        **identity,
                        "ok": True,
                        "status": result_status(source_type),
                        "source_type": source_type,
                        "source_transport": source,
                        "content_type": content_type,
                        "response_handle": response_handle,
                        "avatar_url": url,
                        "origin_url": f"https://x.com/{handle}",
                    }

                if resp.status == 200 and content_type.startswith("image/") and sample:
                    last_error = f"unclassified_source:{source_type or source or 'unknown'}"
                else:
                    last_error = (
                        f"bad_response:{resp.status}:{content_type or 'unknown'}"
                    )

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
        except Exception as exc:  # noqa: BLE001
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


def source_label(source_type: str) -> str:
    return {
        "x_original": "Ooglex R2 cache · X original profile avatar",
        "x_original_proxy": "Ooglex R2 cache · X profile avatar proxy",
        "official_fallback": "Ooglex R2 cache · verified official portrait fallback",
        "public_fallback": "Ooglex R2 cache · verified public portrait fallback",
        "generated_fallback": "Ooglex R2 cache · generated initials fallback",
    }.get(source_type, "Pending review · no verified portrait available")


def avatar_status(source_type: str) -> str:
    return {
        "x_original": "x_original_verified",
        "x_original_proxy": "x_original_proxy_verified",
        "official_fallback": "official_fallback_verified",
        "public_fallback": "public_fallback_verified",
        "generated_fallback": "generated_fallback",
    }.get(source_type, "pending_review")


def apply_result(
    leader: dict[str, Any],
    result: dict[str, Any],
    checked_at: str,
    checked_date: str,
    base_url: str,
) -> None:
    handle = normalize_handle(leader.get("handle"))
    source_type = str(result.get("source_type") or "pending_review")

    leader["avatar_audited_at"] = checked_at
    leader["avatar_source_type"] = source_type
    leader["avatar_audit_status"] = result.get("status") or "pending_review"
    leader["avatar_policy"] = POLICY
    leader["avatar_fallback"] = "local_initials_svg"

    if handle:
        leader["avatar_url"] = avatar_endpoint(base_url, leader, handle)
        leader["avatar_origin_url"] = f"https://x.com/{handle}"

    if result["ok"]:
        leader["avatar_verified"] = True
        leader["avatar_verified_at"] = checked_at
        leader["avatar_updated_at"] = checked_date
        leader["avatar_status"] = avatar_status(source_type)
        leader["avatar_source"] = source_label(source_type)
        leader["avatar_source_transport"] = result.get("source_transport") or ""
        leader["avatar_is_x_original"] = source_type in {
            "x_original",
            "x_original_proxy",
        }
        leader["avatar_is_substitute"] = source_type in {
            "official_fallback",
            "public_fallback",
            "generated_fallback",
        }
        leader.pop("avatar_review_reason", None)
    else:
        previous_verified = leader.get("avatar_verified_at")
        if previous_verified:
            leader["avatar_last_verified_at"] = previous_verified
        leader["avatar_verified"] = False
        leader["avatar_is_x_original"] = False
        leader["avatar_is_substitute"] = False
        leader["avatar_status"] = "pending_review"
        leader["avatar_source"] = source_label("pending_review")
        leader["avatar_source_transport"] = ""
        leader["avatar_review_reason"] = result.get("reason") or "unverified"
        if not handle:
            leader["avatar_url"] = ""


def write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Audit and sync Tech Leaders avatars with X-first fallbacks."
    )
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
        if isinstance(leader, dict)
        and should_audit(leader, args.include_inactive)
    ]

    checked_at = iso_now()
    checked_date = date_today()
    results_by_index: dict[int, dict[str, Any]] = {}

    with concurrent.futures.ThreadPoolExecutor(
        max_workers=max(1, args.workers)
    ) as pool:
        futures = {
            pool.submit(
                fetch_avatar,
                args.base_url,
                leader,
                max(1, args.retries),
                max(5, args.timeout),
            ): idx
            for idx, leader in indexed
        }
        for future in concurrent.futures.as_completed(futures):
            idx = futures[future]
            result = future.result()
            results_by_index[idx] = result
            prefix = {
                "x_original": "X   ",
                "x_original_proxy": "X~  ",
                "fallback": "ALT ",
                "pending_review": "PEND",
            }.get(result.get("status"), "PEND")
            handle = result.get("handle") or "(no handle)"
            detail = (
                result.get("source_type")
                or result.get("source_transport")
                or result.get("reason")
                or ""
            )
            print(f"{prefix} @{handle} {detail}")

    audit_items: list[dict[str, Any]] = []
    for idx, leader in indexed:
        result = results_by_index[idx]
        if args.write_catalog:
            apply_result(
                leader,
                result,
                checked_at,
                checked_date,
                args.base_url,
            )
        audit_items.append(result)

    x_original = sum(
        1 for item in audit_items
        if item.get("source_type") == "x_original"
    )
    x_proxy = sum(
        1 for item in audit_items
        if item.get("source_type") == "x_original_proxy"
    )
    official_fallback = sum(
        1 for item in audit_items
        if item.get("source_type") == "official_fallback"
    )
    public_fallback = sum(
        1 for item in audit_items
        if item.get("source_type") == "public_fallback"
    )
    generated_fallback = sum(
        1 for item in audit_items
        if item.get("source_type") == "generated_fallback"
    )
    fallback_count = official_fallback + public_fallback + generated_fallback
    usable = sum(1 for item in audit_items if item.get("ok"))
    pending_count = len(audit_items) - usable
    missing_handles = sum(
        1 for item in audit_items
        if item.get("reason") == "missing_handle"
    )
    invalid_handles = sum(
        1 for item in audit_items
        if item.get("reason") == "invalid_handle"
    )

    audit = {
        "schema_version": 2,
        "policy": POLICY,
        "checked_at": checked_at,
        "catalog": str(catalog_path),
        "total_checked": len(audit_items),
        "usable": usable,
        "x_original": x_original,
        "x_original_proxy": x_proxy,
        "official_fallback": official_fallback,
        "public_fallback": public_fallback,
        "generated_fallback": generated_fallback,
        "fallback": fallback_count,
        "pending_review": pending_count,
        "missing_handle": missing_handles,
        "invalid_handle": invalid_handles,
        "items": sorted(
            audit_items,
            key=lambda item: (
                0 if item.get("status") == "x_original" else
                1 if item.get("status") == "x_original_proxy" else
                2 if item.get("status") == "fallback" else
                3,
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
        "usable": usable,
        "x_original": x_original,
        "x_original_proxy": x_proxy,
        "fallback": fallback_count,
        "pending_review": pending_count,
    }

    if args.write_catalog:
        write_json(catalog_path, data)

    if args.audit_out:
        write_json(Path(args.audit_out), audit)

    print(
        "Avatar audit summary: "
        f"{x_original} X original, "
        f"{x_proxy} X proxy, "
        f"{fallback_count} substitute, "
        f"{pending_count} pending."
    )

    if args.fail_on_pending and pending_count:
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
