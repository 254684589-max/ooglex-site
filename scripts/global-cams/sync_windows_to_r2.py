#!/usr/bin/env python3
"""Build an Ooglex WINDOW catalog from freely reusable Wikimedia Commons video files.

The script discovers videos by configured location, validates machine-readable
license metadata, downloads bounded-size media files, and emits an R2 upload plan
plus a browser manifest. It does not upload anything itself.
"""
from __future__ import annotations

import argparse
import hashlib
import html
import json
import mimetypes
import re
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

API = "https://commons.wikimedia.org/w/api.php"
UA = "Ooglex-Global-Windows/0.6 (https://www.ooglex.com/apps/global-cams/; contact via ooglex.com)"
ALLOWED_LICENSE_PREFIXES = (
    "CC BY",
    "CC0",
    "Public domain",
    "Public Domain",
    "PD",
)
VIDEO_MIMES = {"video/webm", "video/ogg", "video/mp4"}


def http_json(params: dict) -> dict:
    params = {"format": "json", "formatversion": "2", **params}
    url = API + "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


def strip_html(value: str) -> str:
    value = html.unescape(str(value or ""))
    value = re.sub(r"<[^>]+>", " ", value)
    value = re.sub(r"\s+", " ", value).strip()
    return value


def ext_value(ext: dict, key: str) -> str:
    row = ext.get(key) or {}
    if isinstance(row, dict):
        return strip_html(row.get("value", ""))
    return strip_html(row)


def category_titles(category: str, limit: int = 30) -> list[str]:
    out: list[str] = []
    cont = {}
    for _ in range(3):
        data = http_json({
            "action": "query",
            "list": "categorymembers",
            "cmtitle": "Category:" + category,
            "cmtype": "file",
            "cmlimit": min(50, limit),
            **cont,
        })
        out.extend(x.get("title", "") for x in data.get("query", {}).get("categorymembers", []) if x.get("title"))
        if len(out) >= limit or "continue" not in data:
            break
        cont = data["continue"]
    return out[:limit]


def search_titles(city: str, limit: int = 30) -> list[str]:
    queries = [
        f'intitle:"{city}" filemime:video/webm',
        f'"{city}" filemime:video/webm',
        f'"{city}" video',
    ]
    seen: set[str] = set()
    out: list[str] = []
    for query in queries:
        try:
            data = http_json({
                "action": "query",
                "generator": "search",
                "gsrsearch": query,
                "gsrnamespace": "6",
                "gsrlimit": min(50, limit),
                "prop": "info",
            })
        except Exception:
            continue
        for page in data.get("query", {}).get("pages", []):
            title = page.get("title", "")
            if title and title not in seen:
                seen.add(title)
                out.append(title)
                if len(out) >= limit:
                    return out
    return out


def image_info(title: str) -> dict | None:
    data = http_json({
        "action": "query",
        "titles": title,
        "prop": "imageinfo",
        "iiprop": "url|mime|size|extmetadata",
        "iiextmetadatalanguage": "en",
        "iiextmetadatafilter": "Artist|Attribution|LicenseShortName|LicenseUrl|UsageTerms|NonFree|GPSLatitude|GPSLongitude|ImageDescription",
    })
    pages = data.get("query", {}).get("pages", [])
    if not pages:
        return None
    info = (pages[0].get("imageinfo") or [None])[0]
    if not info:
        return None
    info["title"] = title
    return info


def license_ok(info: dict) -> bool:
    ext = info.get("extmetadata") or {}
    if ext_value(ext, "NonFree").lower() in {"true", "1", "yes"}:
        return False
    license_name = ext_value(ext, "LicenseShortName") or ext_value(ext, "UsageTerms")
    return any(license_name.startswith(prefix) for prefix in ALLOWED_LICENSE_PREFIXES)


def media_ext(info: dict) -> str:
    mime = str(info.get("mime") or "").lower()
    if mime == "video/webm":
        return ".webm"
    if mime == "video/ogg":
        return ".ogv"
    if mime == "video/mp4":
        return ".mp4"
    guessed = Path(urllib.parse.urlparse(info.get("url", "")).path).suffix.lower()
    return guessed if guessed in {".webm", ".ogv", ".ogg", ".mp4"} else ".webm"


def safe_float(value: str, fallback: float) -> float:
    try:
        n = float(value)
        if -180 <= n <= 180:
            return n
    except Exception:
        pass
    return fallback


def download(url: str, dest: Path, max_bytes: int) -> int:
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "video/*,*/*;q=0.8"})
    total = 0
    with urllib.request.urlopen(req, timeout=90) as r, dest.open("wb") as f:
        declared = int(r.headers.get("Content-Length") or 0)
        if declared and declared > max_bytes:
            raise ValueError(f"remote file too large: {declared}")
        while True:
            chunk = r.read(1024 * 1024)
            if not chunk:
                break
            total += len(chunk)
            if total > max_bytes:
                raise ValueError(f"download exceeded max bytes: {total}")
            f.write(chunk)
    return total


def build_item(info: dict, loc: dict, key: str, size: int) -> dict:
    ext = info.get("extmetadata") or {}
    source_url = info.get("descriptionurl") or info.get("descriptionshorturl") or ""
    author = ext_value(ext, "Attribution") or ext_value(ext, "Artist") or "Wikimedia Commons contributor"
    license_name = ext_value(ext, "LicenseShortName") or ext_value(ext, "UsageTerms") or "Free license"
    license_url = ext_value(ext, "LicenseUrl")
    title = str(info.get("title") or "").removeprefix("File:")
    title = re.sub(r"\.[A-Za-z0-9]{2,5}$", "", title).replace("_", " ").strip()

    gps_lat = ext_value(ext, "GPSLatitude")
    gps_lng = ext_value(ext, "GPSLongitude")
    lat = safe_float(gps_lat, float(loc["lat"]))
    lng = safe_float(gps_lng, float(loc["lng"]))

    return {
        "id": "r2-" + hashlib.sha256(str(info.get("url", "")).encode()).hexdigest()[:16],
        "kind": "window",
        "name": title or f'{loc["city"]} WINDOW',
        "country": loc["country"],
        "city": loc["city"],
        "lat": lat,
        "lng": lng,
        "category": loc.get("category", "实景"),
        "source": "Wikimedia Commons → Ooglex R2",
        "author": author[:240],
        "license": license_name[:120],
        "license_url": license_url,
        "source_url": source_url,
        "r2_key": key,
        "bytes": size,
        "origin_url": info.get("url", ""),
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", default="data/global-windows/locations.json")
    ap.add_argument("--output", default=".window-build")
    ap.add_argument("--target", type=int, default=0)
    args = ap.parse_args()

    cfg = json.loads(Path(args.config).read_text(encoding="utf-8"))
    target = args.target or int(cfg.get("target") or 36)
    max_per_location = int(cfg.get("max_per_location") or 2)
    max_bytes = int(float(cfg.get("max_file_mb") or 15) * 1024 * 1024)

    root = Path(args.output)
    media_dir = root / "media"
    manifest_dir = root / "manifest"
    media_dir.mkdir(parents=True, exist_ok=True)
    manifest_dir.mkdir(parents=True, exist_ok=True)

    items: list[dict] = []
    upload_plan: list[dict] = []
    seen_urls: set[str] = set()

    for loc in cfg.get("locations", []):
        if len(items) >= target:
            break
        city = str(loc["city"])
        category = str(loc.get("commons_category") or "")
        titles: list[str] = []
        if category:
            try:
                titles.extend(category_titles(category, limit=30))
            except Exception as exc:
                print(f"warn: category {category}: {exc}", file=sys.stderr)
        if len(titles) < max_per_location:
            try:
                titles.extend(search_titles(city, limit=30))
            except Exception as exc:
                print(f"warn: search {city}: {exc}", file=sys.stderr)

        used_here = 0
        seen_titles: set[str] = set()
        for title in titles:
            if len(items) >= target or used_here >= max_per_location:
                break
            if title in seen_titles:
                continue
            seen_titles.add(title)
            try:
                info = image_info(title)
                if not info:
                    continue
                mime = str(info.get("mime") or "").lower()
                url = str(info.get("url") or "")
                size = int(info.get("size") or 0)
                if mime not in VIDEO_MIMES or not url or url in seen_urls:
                    continue
                if size <= 0 or size > max_bytes or not license_ok(info):
                    continue

                ext = media_ext(info)
                digest = hashlib.sha256(url.encode()).hexdigest()[:24]
                filename = digest + ext
                dest = media_dir / filename
                if not dest.exists() or dest.stat().st_size != size:
                    tmp = dest.with_suffix(dest.suffix + ".part")
                    if tmp.exists():
                        tmp.unlink()
                    got = download(url, tmp, max_bytes)
                    tmp.replace(dest)
                    size = got

                key = "media/" + filename
                item = build_item(info, loc, key, size)
                items.append(item)
                upload_plan.append({
                    "local": str(dest),
                    "key": key,
                    "content_type": mime,
                    "bytes": size,
                })
                seen_urls.add(url)
                used_here += 1
                print(f"accepted {len(items):02d}/{target}: {city} :: {title} :: {size/1024/1024:.1f} MiB")
                time.sleep(0.08)
            except Exception as exc:
                print(f"warn: skip {title}: {exc}", file=sys.stderr)

    if len(items) < min(12, target):
        raise SystemExit(f"catalog too small: {len(items)} accepted; need at least {min(12, target)}")

    manifest = json.dumps(items, ensure_ascii=False, indent=2) + "\n"
    (manifest_dir / "windows.json").write_text(manifest, encoding="utf-8")
    (root / "upload-plan.json").write_text(json.dumps(upload_plan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    total = sum(x["bytes"] for x in upload_plan)
    print(f"built {len(items)} WINDOW clips, {total/1024/1024:.1f} MiB total")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
