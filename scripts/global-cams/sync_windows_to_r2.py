#!/usr/bin/env python3
"""Build a curated Ooglex WINDOW catalog from freely reusable Wikimedia Commons videos.

The curator is intentionally conservative:
- reuses high-quality objects already present in Ooglex R2;
- imports known-good manual seeds;
- performs scenic/theme-first Commons discovery;
- batches metadata requests and politely rate-limits the Wikimedia API;
- rejects people/events/sports/transit/wildlife-centric clips;
- validates geographic distance when GPS metadata is available;
- emits only clips above the configured scenic quality threshold.

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
import urllib.error
import urllib.parse
import urllib.request
from collections import Counter
from pathlib import Path

API = "https://commons.wikimedia.org/w/api.php"
UA = "Ooglex-Global-Windows/0.7.2 (https://www.ooglex.com/apps/global-cams/; contact via ooglex.com)"
ALLOWED_LICENSE_PREFIXES = ("CC BY", "CC0", "Public domain", "Public Domain", "PD")
VIDEO_MIMES = {"video/webm", "video/ogg", "video/mp4"}

DEFAULT_GLOBAL_SCENIC_QUERIES = [
    "snow", "snowfall", "rain", "rainy night", "sunset", "sunrise",
    "night skyline", "cityscape", "timelapse", "beach waves", "ocean waves",
    "mountain snow", "waterfall", "fjord", "lake mountain", "fog landscape",
    "harbor sunset", "aurora", "coast sunset", "river timelapse", "canal",
]

SCENIC_WEIGHTS = {
    "snow": 6, "snowfall": 7, "snowing": 7, "snowy": 6, "winter": 3,
    "rain": 6, "raining": 7, "rainy": 6, "storm": 4, "sandstorm": 6, "thunderstorm": 6,
    "fog": 5, "mist": 4, "aurora": 7,
    "night": 5, "nighttime": 5, "evening": 3, "dusk": 4, "dawn": 4,
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
    "concert", "festival", "ceremony", "wedding", "funeral", "party",
    "football", "soccer", "cricket", "baseball", "basketball", "marathon",
    "politician", "president", "mayor", "police", "military", "soldier",
    "brigade", "medical", "medevac", "army", "navy", "air force",
    "crowd", "people", "person", "man", "woman", "boy", "girl",
    "dancer", "singer", "musician", "performer", "actor", "actress",
    "animal", "wildlife", "zoo", "cicada", "insect", "turtle", "tortoise",
    "bird", "heron", "cat", "dog", "horse",
    "subway", "metro", "train", "railway", "tram", "bus", "station", "airport",
    "aircraft", "airplane", "plane spotting", "flight",
    "tutorial", "lecture", "animation", "gameplay", "screen recording",
    "trailer", "short film", "film trailer", "movie", "official video",
    "motorcycle", "commuter", "rush hour", "venice beach",
    "cira", "satellite", "weather satellite", "sora",
}

SOFT_REJECT = {
    "museum": 2, "indoor": 3, "interior": 2, "restaurant": 3, "shop": 3,
    "vehicle": 2, "car": 1, "traffic": 1, "construction": 2,
}

_REQUEST_LAST = 0.0


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


def http_json(params: dict, interval: float = 0.8, retries: int = 6) -> dict:
    """Polite Wikimedia API client with global pacing and 429/5xx backoff."""
    global _REQUEST_LAST
    params = {"format": "json", "formatversion": "2", "maxlag": "5", **params}
    url = API + "?" + urllib.parse.urlencode(params)

    for attempt in range(retries):
        wait = interval - (time.monotonic() - _REQUEST_LAST)
        if wait > 0:
            time.sleep(wait)

        req = urllib.request.Request(url, headers={
            "User-Agent": UA,
            "Accept": "application/json",
            "Accept-Encoding": "identity",
        })
        try:
            with urllib.request.urlopen(req, timeout=40) as r:
                _REQUEST_LAST = time.monotonic()
                return json.load(r)
        except urllib.error.HTTPError as exc:
            _REQUEST_LAST = time.monotonic()
            if exc.code not in {429, 500, 502, 503, 504} or attempt == retries - 1:
                raise
            retry_after = exc.headers.get("Retry-After")
            try:
                delay = float(retry_after) if retry_after else 0.0
            except Exception:
                delay = 0.0
            delay = max(delay, min(30.0, 2.5 * (2 ** attempt)))
            print(f"warn: Wikimedia HTTP {exc.code}; backing off {delay:.1f}s", file=sys.stderr)
            time.sleep(delay)
        except (urllib.error.URLError, TimeoutError):
            _REQUEST_LAST = time.monotonic()
            if attempt == retries - 1:
                raise
            time.sleep(min(20.0, 2.0 * (2 ** attempt)))

    raise RuntimeError("Wikimedia request retry loop exhausted")


def fetch_json_url(url: str) -> object:
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


def category_titles(loc: dict, limit: int, interval: float) -> list[str]:
    categories: list[str] = []
    raw = loc.get("commons_categories") or []
    if isinstance(raw, list):
        categories.extend(str(x) for x in raw if x)
    single = str(loc.get("commons_category") or "").strip()
    if single:
        categories.append(single)

    out: list[str] = []
    seen: set[str] = set()
    for category in categories[:2]:
        cont: dict = {}
        for _ in range(2):
            try:
                data = http_json({
                    "action": "query",
                    "list": "categorymembers",
                    "cmtitle": "Category:" + category,
                    "cmtype": "file",
                    "cmlimit": min(50, limit),
                    **cont,
                }, interval=interval)
            except Exception as exc:
                print(f"warn: category {category}: {exc}", file=sys.stderr)
                break
            for row in data.get("query", {}).get("categorymembers", []):
                title = str(row.get("title") or "")
                if title and title not in seen:
                    seen.add(title)
                    out.append(title)
                    if len(out) >= limit:
                        return out
            if "continue" not in data:
                break
            cont = data["continue"]
    return out


def themed_search_titles(loc: dict, per_query: int, max_candidates: int, interval: float) -> list[tuple[str, bool]]:
    """Use place categories first, then a compact set of scenic theme queries."""
    aliases = [str(loc.get("city") or "")]
    aliases.extend(str(x) for x in loc.get("search_aliases", []) if x and x != loc.get("city"))
    themes = [str(x) for x in loc.get("themes", []) if x]
    if not themes:
        themes = ["rain", "night", "sunset", "skyline", "landscape", "street"]

    trust: dict[str, bool] = {}
    order: list[str] = []

    for title in category_titles(loc, limit=min(50, max_candidates), interval=interval):
        if title not in trust:
            order.append(title)
        trust[title] = True

    query_limit = min(25, max(8, per_query))

    def run_query(alias: str, query: str) -> None:
        if len(order) >= max_candidates:
            return
        try:
            data = http_json({
                "action": "query",
                "generator": "search",
                "gsrsearch": query,
                "gsrnamespace": "6",
                "gsrlimit": query_limit,
                "prop": "info",
            }, interval=interval)
        except Exception as exc:
            print(f"warn: search {alias}: {exc}", file=sys.stderr)
            return
        for page in data.get("query", {}).get("pages", []):
            title = str(page.get("title") or "")
            if title and title not in trust:
                trust[title] = False
                order.append(title)
                if len(order) >= max_candidates:
                    break

    for alias in aliases[:2]:
        if not alias:
            continue
        for theme in themes[:3]:
            run_query(alias, f'"{alias}" {theme} filemime:video/webm')
        run_query(alias, f'intitle:"{alias}" filemime:video/webm')
        if len(order) >= max_candidates:
            break

    ranked: list[tuple[int, int, int, str, bool]] = []
    for index, title in enumerate(order):
        score, _ = quality_score({"title": title, "extmetadata": {}})
        if score < 0:
            continue
        trusted = bool(trust.get(title))
        ranked.append((score, 1 if trusted else 0, -index, title, trusted))
    ranked.sort(reverse=True)
    return [(title, trusted) for _, _, _, title, trusted in ranked[:max_candidates]]


def image_infos(titles: list[str], interval: float) -> dict[str, dict]:
    """Batch metadata + page coordinates to avoid one API request per candidate."""
    result: dict[str, dict] = {}
    for start in range(0, len(titles), 50):
        batch = titles[start:start + 50]
        if not batch:
            continue
        try:
            data = http_json({
                "action": "query",
                "titles": "|".join(batch),
                "prop": "imageinfo|coordinates",
                "iiprop": "url|mime|size|extmetadata",
                "iiextmetadatalanguage": "en",
                "iiextmetadatafilter": (
                    "Artist|Attribution|LicenseShortName|LicenseUrl|UsageTerms|NonFree|"
                    "GPSLatitude|GPSLongitude|ImageDescription"
                ),
            }, interval=interval)
        except Exception as exc:
            print(f"warn: metadata batch failed ({len(batch)} titles): {exc}", file=sys.stderr)
            continue

        for page in data.get("query", {}).get("pages", []):
            info = (page.get("imageinfo") or [None])[0]
            title = page.get("title", "")
            if info and title:
                info["title"] = title
                coord = (page.get("coordinates") or [None])[0]
                if isinstance(coord, dict):
                    try:
                        info["_page_lat"] = float(coord.get("lat"))
                        info["_page_lng"] = float(coord.get("lon"))
                    except Exception:
                        pass
                result[title] = info
    return result


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


def media_coords(info: dict) -> tuple[float | None, float | None]:
    lat = parse_float(info.get("_page_lat"))
    lng = parse_float(info.get("_page_lng"))
    if lat is not None and lng is not None and -90 <= lat <= 90 and -180 <= lng <= 180:
        return lat, lng

    ext = info.get("extmetadata") or {}
    lat = parse_float(ext_value(ext, "GPSLatitude"))
    lng = parse_float(ext_value(ext, "GPSLongitude"))
    if lat is not None and lng is not None and -90 <= lat <= 90 and -180 <= lng <= 180:
        return lat, lng
    return None, None


def geo_ok(info: dict, loc: dict, default_radius_km: float) -> tuple[bool, float | None]:
    lat, lng = media_coords(info)
    if lat is None or lng is None:
        return True, None
    distance = haversine_km(float(loc["lat"]), float(loc["lng"]), lat, lng)
    radius = float(loc.get("radius_km") or default_radius_km)
    return distance <= radius, distance


def location_relevant(info: dict, loc: dict, distance: float | None, trusted_category: bool = False) -> bool:
    """Reject search matches that are not actually about the configured place.

    GPS is authoritative when available. Without GPS, require the city/place or
    one of its aliases to appear in the file title/description. This prevents
    matches such as Washington-state rivers being assigned to Seattle.
    """
    ext = info.get("extmetadata") or {}
    text = norm(str(info.get("title") or "") + " " + ext_value(ext, "ImageDescription"))

    for bad in loc.get("reject_terms", []):
        if norm(str(bad)) in text:
            return False

    if distance is not None or trusted_category:
        return True

    aliases = [str(loc.get("city") or "")]
    aliases.extend(str(x) for x in loc.get("search_aliases", []) if x)
    aliases = [norm(x) for x in aliases if x]
    return any(alias and alias in text for alias in aliases)


def global_scenic_titles(cfg: dict, interval: float) -> list[str]:
    """Discover a broad scenic pool with a small number of global Commons searches."""
    queries = [str(x) for x in cfg.get("global_scenic_queries", DEFAULT_GLOBAL_SCENIC_QUERIES) if x]
    per_query = int(cfg.get("global_query_limit") or 45)
    max_candidates = int(cfg.get("global_max_candidates") or 700)
    seen: set[str] = set()
    out: list[str] = []

    for term in queries:
        if len(out) >= max_candidates:
            break
        search_forms = [
            f'intitle:"{term}" filemime:video/webm',
            f'"{term}" filemime:video/webm',
        ]
        for query in search_forms:
            if len(out) >= max_candidates:
                break
            try:
                data = http_json({
                    "action": "query",
                    "generator": "search",
                    "gsrsearch": query,
                    "gsrnamespace": "6",
                    "gsrlimit": min(50, per_query),
                    "prop": "info",
                }, interval=interval)
            except Exception as exc:
                print(f"warn: global scenic search {term}: {exc}", file=sys.stderr)
                continue
            for page in data.get("query", {}).get("pages", []):
                title = page.get("title", "")
                if title and title not in seen:
                    seen.add(title)
                    score, _ = quality_score({"title": title, "extmetadata": {}})
                    if score >= 0:
                        out.append(title)
                        if len(out) >= max_candidates:
                            break

    out.sort(key=lambda title: quality_score({"title": title, "extmetadata": {}})[0], reverse=True)
    print(f"global scenic discovery produced {len(out)} unique candidates")
    return out


def match_global_location(info: dict, locations: list[dict], cfg: dict) -> tuple[dict | None, float | None]:
    """Map a global scenic candidate to a configured place or its exact GPS point."""
    lat, lng = media_coords(info)
    max_distance = float(cfg.get("global_match_distance_km") or 350)

    if lat is not None and lng is not None:
        nearest = None
        nearest_distance = None
        for loc in locations:
            distance = haversine_km(float(loc["lat"]), float(loc["lng"]), lat, lng)
            if nearest_distance is None or distance < nearest_distance:
                nearest = loc
                nearest_distance = distance
        if nearest is not None and nearest_distance is not None and nearest_distance <= max_distance:
            return nearest, nearest_distance

        # Exact coordinates are better than inventing a city. Keep the map point
        # accurate and label it as a generic scenic location.
        return {
            "city": "GPS 景观点",
            "country": "",
            "lat": lat,
            "lng": lng,
            "category": "自然景观",
            "search_aliases": [],
        }, 0.0

    text = norm(str(info.get("title") or "") + " " + ext_value(info.get("extmetadata") or {}, "ImageDescription"))
    best = None
    best_len = 0
    for loc in locations:
        for raw_alias in [loc.get("city"), *(loc.get("search_aliases") or [])]:
            alias = norm(str(raw_alias or ""))
            if alias and alias in text and len(alias) > best_len:
                if any(norm(str(bad)) in text for bad in loc.get("reject_terms", [])):
                    continue
                best = loc
                best_len = len(alias)
    return best, None


def quality_score(info: dict, search_hint: str = "") -> tuple[int, list[str]]:
    ext = info.get("extmetadata") or {}
    title = norm(info.get("title", ""))
    desc = norm(ext_value(ext, "ImageDescription"))
    combined = title + " " + desc

    for term in HARD_REJECT:
        if phrase(combined, term):
            return -100, [f"reject:{term}"]

    score = 0
    reasons: list[str] = []
    for term, weight in SCENIC_WEIGHTS.items():
        if phrase(title, term):
            score += weight
            reasons.append(term)
        elif phrase(desc, term):
            score += max(1, weight // 3)

    for term, weight in SOFT_REJECT.items():
        if phrase(title, term):
            score -= weight
        elif phrase(desc, term):
            score -= max(1, weight // 2)

    return score, reasons[:8]


def semantic_title_key(value: str) -> str:
    text = norm(value)
    text = re.sub(r"\([^)]*\)", " ", text)
    text = re.sub(r"\b(?:labels?|nolabels?|no labels?|portrait|short|version|ver)\b", " ", text)
    text = re.sub(r"\b(?:19|20)\d{2}(?:[-_/]\d{1,2}){0,2}\b", " ", text)
    text = re.sub(r"\b\d{2,}\b", " ", text)
    return re.sub(r"\s+", " ", text).strip()[:180]


def download(url: str, dest: Path, max_bytes: int) -> int:
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "video/*,*/*;q=0.8"})
    total = 0
    with urllib.request.urlopen(req, timeout=150) as r, dest.open("wb") as f:
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


def build_item(info: dict, loc: dict, key: str, size: int, score: int, reasons: list[str]) -> dict:
    ext = info.get("extmetadata") or {}
    source_url = info.get("descriptionurl") or info.get("descriptionshorturl") or ""
    author = ext_value(ext, "Attribution") or ext_value(ext, "Artist") or "Wikimedia Commons contributor"
    license_name = ext_value(ext, "LicenseShortName") or ext_value(ext, "UsageTerms") or "Free license"
    license_url = ext_value(ext, "LicenseUrl")

    gps_lat, gps_lng = media_coords(info)
    lat = gps_lat if gps_lat is not None else float(loc["lat"])
    lng = gps_lng if gps_lng is not None else float(loc["lng"])

    return {
        "id": "r2-" + hashlib.sha256(str(info.get("url", "")).encode()).hexdigest()[:16],
        "kind": "window",
        "name": normalize_title(info.get("title", "")) or f'{loc["city"]} WINDOW',
        "country": loc["country"],
        "city": loc["city"],
        "lat": lat,
        "lng": lng,
        "category": loc.get("category", "沉浸实景"),
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


def ingest_existing(cfg: dict, seen_urls: set[str], seen_keys: set[str], min_quality: int) -> list[dict]:
    url = str(cfg.get("existing_manifest_url") or "").strip()
    if not url:
        return []
    try:
        rows = fetch_json_url(url)
    except Exception as exc:
        print(f"warn: existing manifest unavailable: {exc}", file=sys.stderr)
        return []

    if not isinstance(rows, list):
        return []

    out: list[dict] = []
    for row in rows:
        key = str(row.get("r2_key") or "")
        if not key.startswith("media/") or key in seen_keys:
            continue
        origin = str(row.get("origin_url") or "")
        if origin and origin in seen_urls:
            continue
        synthetic = {
            "title": "File:" + str(row.get("name") or ""),
            "extmetadata": {"ImageDescription": {"value": ""}},
        }
        score, reasons = quality_score(synthetic)
        if score < min_quality:
            continue
        item = {
            **row,
            "kind": "window",
            "quality_score": score,
            "quality_reasons": reasons + ["existing-r2"],
        }
        out.append(item)
        seen_keys.add(key)
        if origin:
            seen_urls.add(origin)

    print(f"reused {len(out)} scenic clips from existing R2 manifest")
    return out


def seed_items(cfg: dict, root: Path, seen_urls: set[str], seen_keys: set[str]) -> tuple[list[dict], list[dict]]:
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
            key = "media/" + digest + suffix
            if key in seen_keys:
                continue
            dest = media_dir / (digest + suffix)
            tmp = dest.with_suffix(dest.suffix + ".part")
            if tmp.exists():
                tmp.unlink()
            size = download(url, tmp, max_bytes)
            tmp.replace(dest)
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
            }
            item.pop("video_url", None)
            items.append(item)
            plan.append({"local": str(dest), "key": key, "content_type": mime, "bytes": size})
            seen_urls.add(url)
            seen_keys.add(key)
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
    max_candidates = int(cfg.get("max_candidates_per_location") or 40)
    per_query = int(cfg.get("theme_query_limit") or 24)
    default_radius_km = float(cfg.get("max_distance_km") or 400)
    interval = float(cfg.get("request_interval_seconds") or 0.8)

    root = Path(args.output)
    media_dir = root / "media"
    manifest_dir = root / "manifest"
    media_dir.mkdir(parents=True, exist_ok=True)
    manifest_dir.mkdir(parents=True, exist_ok=True)

    seen_urls: set[str] = set()
    seen_keys: set[str] = set()
    upload_plan: list[dict] = []

    items = ingest_existing(cfg, seen_urls, seen_keys, min_quality)
    seeds, seed_plan = seed_items(cfg, root, seen_urls, seen_keys)
    items.extend(seeds)
    upload_plan.extend(seed_plan)

    seen_semantic = {semantic_title_key(str(x.get("name") or "")) for x in items if x.get("name")}
    city_counts = Counter(str(x.get("city") or "") for x in items)
    rejected_quality = 0
    rejected_geo = 0
    rejected_location = 0
    rejected_size = 0

    for loc in cfg.get("locations", []):
        if len(items) >= target:
            break

        city = str(loc["city"])
        used_here = city_counts[city]
        if used_here >= max_per_location:
            continue

        candidates = themed_search_titles(loc, per_query=per_query, max_candidates=max_candidates, interval=interval)
        if not candidates:
            continue
        titles = [title for title, _ in candidates]
        infos = image_infos(titles, interval=interval)

        for title, trusted_category in candidates:
            if len(items) >= target or used_here >= max_per_location:
                break
            info = infos.get(title)
            if not info:
                continue

            semantic = semantic_title_key(title)
            if semantic and semantic in seen_semantic:
                continue

            try:
                mime = str(info.get("mime") or "").lower()
                url = str(info.get("url") or "")
                size = int(info.get("size") or 0)
                if mime not in VIDEO_MIMES or not url or url in seen_urls or not license_ok(info):
                    continue
                if size < min_bytes or size > max_bytes:
                    rejected_size += 1
                    continue

                score, reasons = quality_score(info)
                if score < min_quality:
                    rejected_quality += 1
                    continue

                within, distance = geo_ok(info, loc, default_radius_km)
                if not within:
                    rejected_geo += 1
                    continue
                if not location_relevant(info, loc, distance, trusted_category=trusted_category):
                    rejected_location += 1
                    continue

                ext = media_ext(info)
                digest = hashlib.sha256(url.encode()).hexdigest()[:24]
                filename = digest + ext
                key = "media/" + filename
                if key in seen_keys:
                    continue
                dest = media_dir / filename
                if not dest.exists() or dest.stat().st_size != size:
                    tmp = dest.with_suffix(dest.suffix + ".part")
                    if tmp.exists():
                        tmp.unlink()
                    got = download(url, tmp, max_bytes)
                    tmp.replace(dest)
                    size = got

                item = build_item(info, loc, key, size, score, reasons)
                items.append(item)
                upload_plan.append({"local": str(dest), "key": key, "content_type": mime, "bytes": size})
                seen_urls.add(url)
                seen_keys.add(key)
                if semantic:
                    seen_semantic.add(semantic)
                used_here += 1
                city_counts[city] += 1
                distance_note = "" if distance is None else f" · {distance:.0f} km"
                print(
                    f"accepted {len(items):03d}/{target}: {city} :: score={score} :: "
                    f"{title} :: {size/1024/1024:.1f} MiB{distance_note}"
                )
            except Exception as exc:
                print(f"warn: skip {title}: {exc}", file=sys.stderr)

    # If place-by-place discovery is still short, fill from a global scenic
    # pool. This keeps the 100+ gate strict without lowering the quality score.
    if len(items) < target:
        locations = list(cfg.get("locations", []))
        global_cap = int(cfg.get("global_max_per_location") or 6)
        titles = global_scenic_titles(cfg, interval)
        infos = image_infos(titles, interval=interval)

        for title in titles:
            if len(items) >= target:
                break
            info = infos.get(title)
            if not info:
                continue
            semantic = semantic_title_key(title)
            if semantic and semantic in seen_semantic:
                continue
            try:
                mime = str(info.get("mime") or "").lower()
                url = str(info.get("url") or "")
                size = int(info.get("size") or 0)
                if mime not in VIDEO_MIMES or not url or url in seen_urls or not license_ok(info):
                    continue
                if size < min_bytes or size > max_bytes:
                    rejected_size += 1
                    continue

                score, reasons = quality_score(info)
                if score < min_quality:
                    rejected_quality += 1
                    continue

                loc, distance = match_global_location(info, locations, cfg)
                if not loc:
                    rejected_location += 1
                    continue

                city = str(loc.get("city") or "GPS 景观点")
                if city != "GPS 景观点" and city_counts[city] >= global_cap:
                    continue

                ext = media_ext(info)
                digest = hashlib.sha256(url.encode()).hexdigest()[:24]
                filename = digest + ext
                key = "media/" + filename
                if key in seen_keys:
                    continue
                dest = media_dir / filename
                if not dest.exists() or dest.stat().st_size != size:
                    tmp = dest.with_suffix(dest.suffix + ".part")
                    if tmp.exists():
                        tmp.unlink()
                    got = download(url, tmp, max_bytes)
                    tmp.replace(dest)
                    size = got

                item = build_item(info, loc, key, size, score, reasons + ["global-scenic"])
                items.append(item)
                upload_plan.append({"local": str(dest), "key": key, "content_type": mime, "bytes": size})
                seen_urls.add(url)
                seen_keys.add(key)
                if semantic:
                    seen_semantic.add(semantic)
                city_counts[city] += 1
                distance_note = "" if distance is None else f" · {distance:.0f} km"
                print(
                    f"global accepted {len(items):03d}/{target}: {city} :: score={score} :: "
                    f"{title} :: {size/1024/1024:.1f} MiB{distance_note}"
                )
            except Exception as exc:
                print(f"warn: global skip {title}: {exc}", file=sys.stderr)

    min_catalog = int(cfg.get("min_catalog") or 100)
    required = min(target, max(12, min_catalog))
    if len(items) < required:
        raise SystemExit(f"curated catalog too small: {len(items)} accepted; require at least {required}")

    items.sort(key=lambda x: (-int(x.get("quality_score") or 0), str(x.get("city") or ""), str(x.get("name") or "")))
    chosen = items[:target]
    selected_keys = {x["r2_key"] for x in chosen}
    upload_plan = [x for x in upload_plan if x["key"] in selected_keys]

    (manifest_dir / "windows.json").write_text(json.dumps(chosen, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (root / "upload-plan.json").write_text(json.dumps(upload_plan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    total = sum(int(x.get("bytes") or 0) for x in chosen)
    scores = [int(x.get("quality_score") or 0) for x in chosen]
    cities = {str(x.get("city") or "") for x in chosen}
    print(
        f"built {len(chosen)} curated WINDOW clips across {len(cities)} locations, "
        f"{total/1024/1024:.1f} MiB catalog size, score min/avg/max="
        f"{min(scores)}/{sum(scores)/len(scores):.1f}/{max(scores)}"
    )
    print(
        f"new uploads={len(upload_plan)}; rejected quality={rejected_quality}, "
        f"geo={rejected_geo}, location={rejected_location}, size={rejected_size}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
