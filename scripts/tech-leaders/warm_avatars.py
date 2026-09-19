#!/usr/bin/env python3
import argparse
import concurrent.futures
import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

USABLE_SOURCE_TYPES = {
    "x_original",
    "x_original_proxy",
    "official_fallback",
    "public_fallback",
}


def infer_source_type(source):
    value = str(source or "").lower()
    for suffix in ("-r2-cache", "-r2"):
        if value.endswith(suffix):
            value = value[: -len(suffix)]
            break
    if value in {"x_profile_redirect", "x_syndication"}:
        return "x_original"
    if value == "unavatar_x":
        return "x_original_proxy"
    if value == "official_override":
        return "official_fallback"
    if value in {"wikipedia", "wikimedia_commons"}:
        return "public_fallback"
    return "unknown"


def fetch_one(base_url, leader, retries):
    handle = str(leader.get("handle") or "").lstrip("@")
    name = str(leader.get("name_en") or leader.get("name") or "")
    company = str(
        leader.get("company_en")
        or leader.get("company_zh")
        or leader.get("role")
        or ""
    )
    query = urllib.parse.urlencode(
        {"handle": handle, "name": name, "company": company}
    )
    url = f"{base_url.rstrip('/')}/v1/tech-leaders/avatar?{query}"
    last = None

    for attempt in range(1, retries + 1):
        try:
            req = urllib.request.Request(
                url,
                headers={
                    "User-Agent": "Ooglex-Avatar-Warmup/5.1",
                    "Accept": "image/*",
                },
            )
            with urllib.request.urlopen(req, timeout=30) as resp:
                content_type = (
                    resp.headers.get("Content-Type") or ""
                ).split(";")[0].strip().lower()
                source = resp.headers.get("X-Ooglex-Avatar-Source") or ""
                source_type = (
                    resp.headers.get("X-Ooglex-Avatar-Source-Type")
                    or infer_source_type(source)
                )
                body = resp.read(32)

                if (
                    resp.status == 200
                    and content_type.startswith("image/")
                    and body
                    and source_type in USABLE_SOURCE_TYPES
                ):
                    return {
                        "handle": handle,
                        "ok": True,
                        "status": resp.status,
                        "type": content_type,
                        "source": source,
                        "source_type": source_type,
                    }

                last = (
                    f"bad_response status={resp.status} "
                    f"type={content_type} source={source_type or source}"
                )

        except urllib.error.HTTPError as exc:
            last = f"HTTP Error {exc.code}: {exc.reason}"
            if exc.code == 429 and attempt < retries:
                retry_after = 0
                try:
                    retry_after = int(exc.headers.get("Retry-After") or 0)
                except (TypeError, ValueError):
                    pass
                delay = max(retry_after, min(8 * attempt, 30))
                print(
                    f"RATE @{handle} 429; retrying in {delay}s "
                    f"(attempt {attempt}/{retries})",
                    file=sys.stderr,
                )
                time.sleep(delay)
                continue
        except Exception as exc:
            last = str(exc)

        if attempt < retries:
            time.sleep(min(3 * attempt, 10))

    return {
        "handle": handle,
        "ok": False,
        "source_type": "missing",
        "error": last or "unknown_error",
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--catalog", required=True)
    ap.add_argument("--base-url", required=True)
    ap.add_argument("--workers", type=int, default=2)
    ap.add_argument("--retries", type=int, default=5)
    # Kept for backward compatibility with earlier workflows.
    ap.add_argument("--min-x-original", type=int, default=1)
    args = ap.parse_args()

    with open(args.catalog, "r", encoding="utf-8") as f:
        data = json.load(f)

    leaders = [
        p
        for p in data.get("leaders", [])
        if (
            not p.get("admission_status")
            or p.get("admission_status") == "active"
        )
        and p.get("handle")
    ]
    leaders = sorted(
        leaders,
        key=lambda p: str(p.get("handle") or "").lower(),
    )
    print(
        f"Warming {len(leaders)} Tech Leaders avatars via {args.base_url}"
    )

    results = []
    with concurrent.futures.ThreadPoolExecutor(
        max_workers=max(1, args.workers)
    ) as pool:
        futs = [
            pool.submit(
                fetch_one,
                args.base_url,
                p,
                max(1, args.retries),
            )
            for p in leaders
        ]
        for fut in concurrent.futures.as_completed(futs):
            result = fut.result()
            results.append(result)
            if result["ok"]:
                print(
                    f"OK   @{result['handle']} "
                    f"[{result['source_type']} · {result['source'] or 'image'}]"
                )
            else:
                print(
                    f"FAIL @{result['handle']} {result.get('error', '')}",
                    file=sys.stderr,
                )

    failures = sorted(
        [r for r in results if not r["ok"]],
        key=lambda x: x["handle"].lower(),
    )
    x_original = sum(
        1 for r in results if r.get("source_type") == "x_original"
    )
    x_proxy = sum(
        1 for r in results if r.get("source_type") == "x_original_proxy"
    )
    substitutes = sum(
        1
        for r in results
        if r.get("source_type")
        in {"official_fallback", "public_fallback"}
    )
    usable = len(results) - len(failures)

    print(
        "Avatar warmup summary: "
        f"{usable}/{len(results)} usable · "
        f"X original {x_original} · X proxy {x_proxy} · "
        f"substitute {substitutes} · missing {len(failures)}"
    )
    if failures:
        print(
            "Still missing:",
            ", ".join("@" + r["handle"] for r in failures),
            file=sys.stderr,
        )

    # Deployment should only fail if the avatar service is effectively broken.
    if usable < max(1, args.min_x_original):
        print(
            f"Too few usable avatars: {usable} < "
            f"{max(1, args.min_x_original)}",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
