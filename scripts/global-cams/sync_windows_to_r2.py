#!/usr/bin/env python3
"""Build a curated Ooglex WINDOW catalog from freely reusable Wikimedia Commons videos.

V0.7 adds a WindowSwap-style quality gate:
- scenic/theme-first discovery instead of broad city-video harvesting;
- hard rejection of people/events/sports/transit-centric clips;
- location-distance checks when Commons GPS metadata is available;
- minimum quality score and bounded media size;
- curated seed ingestion for known-good WINDOW clips.

The script only builds a manifest + upload plan. R2 upload is handled by GitHub Actions.
"""
from __future__ import annotations

import argparse
import hashlib
import html
import json
import math
import re
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

API = "https://commons.wikimedia.org/w/api.php"
UA = "Ooglex-Global-Windows/0.7 (https://www.ooglex.com/apps/global-cams/; contact via ooglex.com)"
ALLOWED_LICENSE_PREFIXES = ("CC BY", "CC0", "Public domain", "Public Domain", "PD")
VIDEO_MIMES = {"video/webm", "video/ogg", "video/mp4"}

SCENIC_WEIGHTS = {
    "snow": 6, "snowfall": 7, "snowing": 7, "winter": 3,
    "rain": 6, "raining": 7, "storm": 4, "thunderstorm": 5,
    "fog": 5, "mist": 4, "aurora": 7,
    "night": 5, "nighttime": 5, "dusk": 4, "dawn": 4,
    "sunset": 7, "sunrise": 7,
    "skyline": 6, "cityscape": 6, "timelapse": 6, "time lapse": 6, "time-lapse": 6,
    "harbor": 5, "harbour": 5, "waterfront": 5, "bay": 4,
    "beach": 6, "ocean": 6, "sea": 4, "coast": 5, "coastal": 5, "wave": 4, "waves": 6,
    "river": 4, "canal": 5, "lake": 5, "waterfall": 7,
    "mountain": 6, "mountains": 6, "glacier": 7, "fjord": 7, "valley": 4,
    "landscape": 5, "panorama": 4, "panoramic": 4, "aerial": 4,
    "street": 3, "square": 2, "bridge": 3, "cloud": 2, "clouds": 3,
    "forest": 5, "woods": 4, "island": 4, "desert": 5, "village": 3,
    "park": 2, "architecture": 2, "temple": 2,
}

HARD_REJECT = {
    "protest", "protests", "demonstration", "demonstrations", "parade", "rally",
    "election", "campaign", "speech", "interview", "conference", "meeting",
    "concert", "festival", "ceremony", "wedding", "funeral",
    "football", "soccer", "cricket", "baseball", "basketball", "marathon",
    "politician", "president", "mayor", "police", "military", "soldier",
    "crowd", "people", "person", "man", "woman", "boy", "girl",
    "dancer", "singer", "musician", "performer", "actor", "actress",
    "animal", "zoo", "cicada", "insect", "turtle", "tortoise", "bird", "cat", "dog", "horse",
    "subway", "metro", "train", "railway", "tram", "bus", "station", "airport", "aircraft", "airplane",
    "tutorial", "lecture", "animation", "gameplay", "screen recording",
}

SOFT_REJECT = {
    "museum": 2, "indoor": 3, "interior": 2, "restaurant": 3, "shop": 3,
    "vehicle": 2, "car": 1, "traffic": 1, "construction": 2,
}


def http_json(params: dict) -> dict:
    params = {"format": "json", "formatversion": "2", **params}
    url = API + "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=35) as r:
        return json.load(r)


def strip_html(value: str) -> str:
    value = html.unescape(str(value or ""))
    value = re.sub(r"<[^>]+>", " ", value)
    return re.sub(r"\s+", " ", value).strip()


def norm(value: str) -> str:
    return strip_html(value).lower().replace("_", " ")


def phrase(text: str, needle: str) -> bool:
    return re.search(r"(?<!\w)" + re.escape(needle.lower()) + r"(?!\w)", text, flags=re.IGNORECASE) is not None


def ext_value(ext: dict, key: str) -> str:
    row = ext.get(key) or {}
    return strip_html(row.get("value", "")) if isinstance(row, dict) else strip_html(row)


def category_titles(category: str, limit: int = 40) -> list[tuple[str, str]]:
    out: list[tuple[str, str]] = []
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
        for x in data.get("query", {}).get("categorymembers", []):
            title = x.get("title", "")
            if title:
                out.append((title, "category"))
        if len(out) >= limit or "continue" not in data:
            break
        cont = data["continue"]
    return out[:limit]


def themed_search_titles(loc: dict, per_query: int, max_candidates: int) -> list[tuple[str, str]]:
    aliases = [str(loc.get("city") or "")]
    aliases.extend(str(x) for x in loc.get("search_aliases", []) if x)
    themes = [str(x) for x in loc.get("themes", []) if x]
    if not themes:
        themes = ["rain", "night", "sunset", "skyline", "landscape", "street"]

    out: list[tuple[str, str]] = []
    seen: set[str] = set()

    for alias in aliases[:2]:
        if not alias:
            continue
        for theme in themes:
            if len(out) >= max_candidates:
                return out
            query = f'"{alias}" "{theme}" filemime:video/webm'
            try:
                data = http_json({
                    "action": "query",
                    "generator": "search",
                    "gsrsearch": query,
                    "gsrnamespace": "6",
                    "gsrlimit": min(20, per_query),
                    "prop": "info",
                })
            except Exception:
                continue
            for page in data.get("query", {}).get("pages", []):
                title = page.get("title", "")
                if title and title not in seen:
                    seen.add(title)
                    out.append((title, theme))
                    if len(out) >= max_candidates:
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


def parse_float(value: str) -> float | None:
    try:
        return float(str(value).strip())
    except Exception:
        return None


def haversine_km(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    r = 6371.0088
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lng2 - lng1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(min(1.0, math.sqrt(a)))


def geo_ok(info: dict, loc: dict, default_radius_km: float) -> tuple[bool, float | None]:
    ext = info.get("extmetadata") or {}
    lat = parse_float(ext_value(ext, "GPSLatitude"))
    lng = parse_float(ext_value(ext, "GPSLongitude"))
    if lat is None or lng is None or not (-90 <= lat <= 90 and -180 <= lng <= 180):
        return True, None
    distance = haversine_km(float(loc["lat"]), float(loc["lng"]), lat, lng)
    radius = float(loc.get("radius_km") or default_radius_km)
    return distance <= radius, distance


def quality_score(info: dict, search_hint: str) -> tuple[int, list[str]]:
    ext = info.get("extmetadata") or {}
    title = norm(info.get("title", ""))
    desc = norm(ext_value(ext, "ImageDescription"))
    hint = norm(search_hint)

    for term in HARD_REJECT:
        if phrase(title, term):
            return -100, [f"reject:{term}"]

    score = 0
    reasons: list[str] = []

    for term, weight in SCENIC_WEIGHTS.items():
        if phrase(title, term):
            score += weight
            reasons.append(term)
        elif phrase(desc, term):
            score += max(1, weight // 3)

    if hint and hint != "category":
        score += 3
        reasons.append("query:" + hint)

    for term, weight in SOFT_REJECT.items():
        if phrase(title, term):
            score -= weight
        elif phrase(desc, term):
            score -= max(1, weight // 2)

    return score, reasons[:8]


def download(url: str, dest: Path, max_bytes: int) -> int:
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "video/*,*/*;q=0.8"})
    total = 0
    with urllib.request.urlopen(req, timeout=120) as r, dest.open("wb") as f:
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


def normalize_title(title: str) -> str:
    title = str(title or "").removeprefix("File:")
    return re.sub(r"\.[A-Za-z0-9]{2,5}$", "", title).replace("_", " ").strip()


def build_item(info: dict, loc: dict, key: str, size: int, score: int, reasons: list[str], hint: str) -> dict:
    ext = info.get("extmetadata") or {}
    source_url = info.get("descriptionurl") or info.get("descriptionshorturl") or ""
    author = ext_value(ext, "Attribution") or ext_value(ext, "Artist") or "Wikimedia Commons contributor"
    license_name = ext_value(ext, "LicenseShortName") or ext_value(ext, "UsageTerms") or "Free license"
    license_url = ext_value(ext, "LicenseUrl")

    gps_lat = parse_float(ext_value(ext, "GPSLatitude"))
    gps_lng = parse_float(ext_value(ext, "GPSLongitude"))
    lat = gps_lat if gps_lat is not None and -90 <= gps_lat <= 90 else float(loc["lat"])
    lng = gps_lng if gps_lng is not None and -180 <= gps_lng <= 180 else float(loc["lng"])

    return {
        "id": "r2-" + hashlib.sha256(str(info.get("url", "")).encode()).hexdigest()[:16],
        "kind": "window",
        "name": normalize_title(info.get("title", "")) or f'{loc["city"]} WINDOW',
        "country": loc["country"],
        "city": loc["city"],
        "lat": lat,
        "lng": lng,
        "category": loc.get("category", "沉浸实景"),
        "theme": hint if hint != "category" else "",
        "quality_score": score,
        "quality_reasons": reasons,
        "source": "Wikimedia Commons → Ooglex R2",
        "author": author[:240],
        "license": license_name[:120],
        "license_url": license_url,
        "source_url": source_url,
        "r2_key": key,
        "bytes": size,
        "origin_url": info.get("url", ""),
    }


def seed_items(cfg: dict, root: Path, seen_urls: set[str]) -> tuple[list[dict], list[dict]]:
    path = Path(str(cfg.get("seed_manifest") or ""))
    if not path.exists():
        return [], []

    max_bytes = int(float(cfg.get("max_seed_file_mb") or 30) * 1024 * 1024)
    media_dir = root / "media"
    rows = json.loads(path.read_text(encoding="utf-8"))
    items: list[dict] = []
    plan: list[dict] = []

    for seed in rows:
        url = str(seed.get("video_url") or "")
        if not url or url in seen_urls:
            continue
        try:
            suffix = Path(urllib.parse.urlparse(url).path).suffix.lower()
            if suffix not in {".webm", ".ogv", ".ogg", ".mp4"}:
                suffix = ".webm"
            digest = hashlib.sha256(url.encode()).hexdigest()[:24]
            dest = media_dir / (digest + suffix)
            tmp = dest.with_suffix(dest.suffix + ".part")
            if tmp.exists():
                tmp.unlink()
            size = download(url, tmp, max_bytes)
            tmp.replace(dest)
            key = "media/" + dest.name
            mime = "video/mp4" if suffix == ".mp4" else ("video/ogg" if suffix in {".ogv", ".ogg"} else "video/webm")
            item = {
                **seed,
                "id": "r2-seed-" + digest[:16],
                "kind": "window",
                "source": "Curated seed → Ooglex R2",
                "r2_key": key,
                "bytes": size,
                "origin_url": url,
                "quality_score": 100,
                "quality_reasons": ["manual-seed"],
                "theme": seed.get("category", "curated"),
            }
            item.pop("video_url", None)
            items.append(item)
            plan.append({"local": str(dest), "key": key, "content_type": mime, "bytes": size})
            seen_urls.add(url)
            print(f"seed accepted: {seed.get('name','WINDOW')} :: {size/1024/1024:.1f} MiB")
        except Exception as exc:
            print(f"warn: seed skipped {seed.get('name','?')}: {exc}", file=sys.stderr)

    return items, plan


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", default="data/global-windows/locations.json")
    ap.add_argument("--output", default=".window-build")
    ap.add_argument("--target", type=int, default=0)
    args = ap.parse_args()

    cfg = json.loads(Path(args.config).read_text(encoding="utf-8"))
    target = args.target or int(cfg.get("target") or 120)
    max_per_location = int(cfg.get("max_per_location") or 3)
    min_quality = int(cfg.get("min_quality_score") or 5)
    min_bytes = int(float(cfg.get("min_file_mb") or 0.8) * 1024 * 1024)
    max_bytes = int(float(cfg.get("max_file_mb") or 12) * 1024 * 1024)
    max_candidates = int(cfg.get("max_candidates_per_location") or 70)
    per_query = int(cfg.get("theme_query_limit") or 10)
    default_radius_km = float(cfg.get("max_distance_km") or 400)

    root = Path(args.output)
    media_dir = root / "media"
    manifest_dir = root / "manifest"
    media_dir.mkdir(parents=True, exist_ok=True)
    manifest_dir.mkdir(parents=True, exist_ok=True)

    seen_urls: set[str] = set()
    items, upload_plan = seed_items(cfg, root, seen_urls)

    rejected_quality = 0
    rejected_geo = 0
    rejected_size = 0

    for loc in cfg.get("locations", []):
        if len(items) >= target:
            break

        candidates = themed_search_titles(loc, per_query=per_query, max_candidates=max_candidates)
        category = str(loc.get("commons_category") or "")
        if category and len(candidates) < max_candidates:
            try:
                candidates.extend(category_titles(category, limit=min(30, max_candidates - len(candidates))))
            except Exception as exc:
                print(f"warn: category {category}: {exc}", file=sys.stderr)

        used_here = 0
        seen_titles: set[str] = set()
        candidates = list(dict.fromkeys(candidates))

        for title, hint in candidates:
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
                if mime not in VIDEO_MIMES or not url or url in seen_urls or not license_ok(info):
                    continue
                if size < min_bytes or size > max_bytes:
                    rejected_size += 1
                    continue

                score, reasons = quality_score(info, hint)
                if score < min_quality:
                    rejected_quality += 1
                    continue

                within, distance = geo_ok(info, loc, default_radius_km)
                if not within:
                    rejected_geo += 1
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
                item = build_item(info, loc, key, size, score, reasons, hint)
                items.append(item)
                upload_plan.append({"local": str(dest), "key": key, "content_type": mime, "bytes": size})
                seen_urls.add(url)
                used_here += 1
                distance_note = "" if distance is None else f" · {distance:.0f} km"
                print(
                    f"accepted {len(items):03d}/{target}: {loc['city']} :: score={score} :: "
                    f"{title} :: {size/1024/1024:.1f} MiB{distance_note}"
                )
                time.sleep(0.05)
            except Exception as exc:
                print(f"warn: skip {title}: {exc}", file=sys.stderr)

    min_catalog = int(cfg.get("min_catalog") or 100)
    required = min(target, max(12, min_catalog))
    if len(items) < required:
        raise SystemExit(f"curated catalog too small: {len(items)} accepted; require at least {required}")

    items.sort(key=lambda x: (-int(x.get("quality_score") or 0), str(x.get("city") or ""), str(x.get("name") or "")))
    manifest = json.dumps(items[:target], ensure_ascii=False, indent=2) + "\n"
    selected_keys = {x["r2_key"] for x in items[:target]}
    upload_plan = [x for x in upload_plan if x["key"] in selected_keys]

    (manifest_dir / "windows.json").write_text(manifest, encoding="utf-8")
    (root / "upload-plan.json").write_text(json.dumps(upload_plan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    total = sum(x["bytes"] for x in upload_plan)
    scores = [int(x.get("quality_score") or 0) for x in items[:target]]
    print(
        f"built {len(items[:target])} curated WINDOW clips, {total/1024/1024:.1f} MiB total, "
        f"score min/avg/max={min(scores)}/{sum(scores)/len(scores):.1f}/{max(scores)}"
    )
    print(
        f"rejected: quality={rejected_quality}, geo={rejected_geo}, size={rejected_size}; "
        f"seed={sum(1 for x in items[:target] if int(x.get('quality_score') or 0) == 100)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
