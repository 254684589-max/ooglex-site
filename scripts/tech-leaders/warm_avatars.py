#!/usr/bin/env python3
import argparse
import concurrent.futures
import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


def fetch_one(base_url, leader, retries):
    handle = str(leader.get("handle") or "").lstrip("@")
    name = str(leader.get("name_en") or leader.get("name") or "")
    company = str(leader.get("company_en") or leader.get("company_zh") or "")
    query = urllib.parse.urlencode({"handle": handle, "name": name, "company": company})
    url = f"{base_url.rstrip('/')}/v1/tech-leaders/avatar?{query}"
    last = None
    for attempt in range(1, retries + 1):
        try:
            req = urllib.request.Request(url, headers={
                "User-Agent": "Ooglex-Avatar-Warmup/4.2",
                "Accept": "image/*"
            })
            with urllib.request.urlopen(req, timeout=25) as resp:
                content_type = (resp.headers.get("Content-Type") or "").split(";")[0].strip().lower()
                source = resp.headers.get("X-Ooglex-Avatar-Source") or ""
                body = resp.read(32)
                if resp.status == 200 and content_type.startswith("image/") and body:
                    return {"handle": handle, "ok": True, "status": resp.status, "type": content_type, "source": source}
                last = f"bad_response status={resp.status} type={content_type}"
        except urllib.error.HTTPError as exc:
            last = f"HTTP Error {exc.code}: {exc.reason}"
            if exc.code == 429:
                retry_after = 0
                try:
                    retry_after = int(exc.headers.get("Retry-After") or 0)
                except (TypeError, ValueError):
                    retry_after = 0
                if attempt < retries:
                    delay = max(retry_after, min(8 * attempt, 30))
                    print(f"RATE @{handle} 429; retrying in {delay}s (attempt {attempt}/{retries})", file=sys.stderr)
                    time.sleep(delay)
                    continue
        except Exception as exc:
            last = str(exc)
        if attempt < retries:
            time.sleep(min(3 * attempt, 10))
    return {"handle": handle, "ok": False, "error": last or "unknown_error"}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--catalog", required=True)
    ap.add_argument("--base-url", required=True)
    ap.add_argument("--workers", type=int, default=2)
    ap.add_argument("--retries", type=int, default=5)
    args = ap.parse_args()

    with open(args.catalog, "r", encoding="utf-8") as f:
        data = json.load(f)

    leaders = [
        p for p in data.get("leaders", [])
        if (not p.get("admission_status") or p.get("admission_status") == "active") and p.get("handle")
    ]
    leaders = sorted(leaders, key=lambda p: str(p.get("handle") or "").lower())
    print(f"Warming {len(leaders)} Tech Leaders avatars via {args.base_url}")

    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, args.workers)) as pool:
        futs = [pool.submit(fetch_one, args.base_url, p, max(1, args.retries)) for p in leaders]
        for fut in concurrent.futures.as_completed(futs):
            result = fut.result()
            results.append(result)
            if result["ok"]:
                print(f"OK   @{result['handle']} [{result['source'] or 'image'}]")
            else:
                print(f"FAIL @{result['handle']} {result.get('error','')}", file=sys.stderr)

    failures = sorted([r for r in results if not r["ok"]], key=lambda x: x["handle"].lower())
    ok = len(results) - len(failures)
    print(f"Avatar warmup summary: {ok}/{len(results)} ready")
    if failures:
        print("Failed handles:", ", ".join("@" + r["handle"] for r in failures), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
