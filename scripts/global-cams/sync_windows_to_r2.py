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
from datetime import datetime, timezone
from pathlib import Path

API = "https://commons.wikimedia.org/w/api.php"
FILE_API = "https://commons.wikimedia.org/w/rest.php/v1/file/"
UA = "Ooglex-Global-Windows/1.0 (https://www.ooglex.com/apps/global-cams/; contact via ooglex.com)"
ALLOWED_LICENSE_PREFIXES = ("CC BY", "CC0", "Public domain", "Public Domain", "PD")
VIDEO_MIMES = {"video/webm", "video/ogg", "video/mp4"}

DEFAULT_GLOBAL_SCENIC_QUERIES = [
    "snow", "snowfall", "rain", "rainy night", "sunset", "sunrise",
    "night skyline", "cityscape", "timelapse", "beach waves", "ocean waves",
    "mountain snow", "waterfall", "fjord", "lake mountain", "fog landscape",
    "harbor sunset", "aurora", "coast sunset", "river timelapse", "canal",
    "storm clouds", "cloud timelapse", "mountain timelapse", "snow timelapse",
    "rain timelapse", "beach sunset", "lake sunset", "forest mist",
    "coast waves", "seascape", "canyon sunset", "desert sunset",
    "glacier", "geyser", "alpine lake", "cliff coast", "island sunset",
]

DEFAULT_SCENIC_CATEGORIES = [
    "Videos of sunsets",
    "Videos of sunrises",
    "Videos of snowfall",
    "Videos of rain",
    "Videos of waterfalls",
    "Videos of waves",
    "Videos of beaches",
    "Videos of mountains",
    "Videos of lakes",
    "Videos of rivers",
    "Videos of canals",
    "Videos of clouds",
    "Videos of fog",
    "Videos of glaciers",
    "Videos of fjords",
    "Videos of auroras",
    "Time-lapse videos of clouds",
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
    "falls": 6, "shore": 4, "seashore": 5, "seascape": 6, "coastline": 5,
    "cliff": 4, "cliffs": 4, "canyon": 5, "dune": 4, "dunes": 5,
    "volcano": 5, "volcanic": 4, "geyser": 6, "lagoon": 5, "reef": 4,
    "alpine": 4, "glacial": 5, "meadow": 4, "creek": 3, "stream": 3,
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
    "friendship", "annual", "heroine", "renovation", "press conference",
    "news report", "documentary", "commemoration", "wikimania", "surfing",
    "railroad", "industrial", "funfair", "amusement", "fireworks",
    "coast guard", "defense force", "defence force", "smuggling",
    "naval", "warship", "destroyer", "frigate", "hmas",
    "volleyball", "arena", "samba", "dance performance",
    "cow", "cows", "cattle", "pika", "pica", "seal", "seals",
    "earth hour", "cable car", "funicular", "gondola lift",
    "montage", "compilation", "highlights", "slideshow", "showreel",
    "promo", "promotional", "teaser",
}

STRICT_DESC_REJECT = {
    "protest", "parade", "rally", "crowd", "concert", "festival",
    "football", "soccer", "basketball", "volleyball",
    "coast guard", "defense force", "defence force", "military", "naval", "smuggling",
    "pika", "pica", "cow", "cows", "cattle", "wildlife",
    "samba", "dancer", "singer", "performer",
    "subway", "metro", "train", "tram", "bus", "aircraft", "airplane", "airport",
    "seal", "seals", "cable car", "funicular", "gondola lift", "earth hour",
}

SOFT_REJECT = {
    "museum": 2, "indoor": 3, "interior": 2, "restaurant": 3, "shop": 3,
    "vehicle": 2, "car": 1, "traffic": 1, "construction": 2,
}

_REQUEST_LAST = 0.0
_MEDIA_LAST = 0.0
_PROFILE_CACHE: dict[str, dict] = {}
RUN_AT = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def strip_html(value: str) -> str:
    value = html.unescape(str(value or ""))
    value = re.sub(r"<[^>]+>", " ", value)
    return re.sub(r"\s+", " ", value).strip()


def norm(value: str) -> str:
    return strip_html(value).lower().replace("_", " ")


def phrase(text: str, needle: str) -> bool:
    return re.search(r"(?<!\w)" + re.escape(needle.lower()) + r"(?!\w)", text, flags=re.IGNORECASE) is not None


def text_has_alias(text: str, raw_alias: str) -> bool:
    alias = norm(raw_alias)
    return bool(alias and phrase(text, alias))


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


def source_title_from_url(url: str, fallback: str = "") -> str:
    try:
        path = urllib.parse.unquote(urllib.parse.urlparse(str(url or "")).path)
        if "/wiki/" in path:
            title = path.split("/wiki/", 1)[1].replace("_", " ")
            if title.startswith("File:"):
                return title
    except Exception:
        pass
    raw = str(fallback or "").strip()
    if not raw:
        return ""
    return raw if raw.startswith("File:") else "File:" + raw


def rest_media_profile(title: str, interval: float = 0.8) -> dict:
    """Read duration/dimensions before downloading the original media."""
    global _REQUEST_LAST
    title = str(title or "").strip()
    if not title:
        return {}
    if not title.startswith("File:"):
        title = "File:" + title
    if title in _PROFILE_CACHE:
        return dict(_PROFILE_CACHE[title])

    wait = interval - (time.monotonic() - _REQUEST_LAST)
    if wait > 0:
        time.sleep(wait)

    url = FILE_API + urllib.parse.quote(title, safe=":")
    req = urllib.request.Request(url, headers={
        "User-Agent": UA,
        "Accept": "application/json",
        "Accept-Encoding": "identity",
    })
    try:
        with urllib.request.urlopen(req, timeout=40) as r:
            _REQUEST_LAST = time.monotonic()
            data = json.load(r)
    except Exception as exc:
        _REQUEST_LAST = time.monotonic()
        print(f"warn: media profile unavailable {title}: {exc}", file=sys.stderr)
        _PROFILE_CACHE[title] = {}
        return {}

    rep = data.get("original") or data.get("preferred") or {}
    try:
        duration = float(rep.get("duration")) if rep.get("duration") is not None else None
    except Exception:
        duration = None
    try:
        width = int(rep.get("width")) if rep.get("width") is not None else None
    except Exception:
        width = None
    try:
        height = int(rep.get("height")) if rep.get("height") is not None else None
    except Exception:
        height = None
    try:
        size = int(rep.get("size")) if rep.get("size") is not None else None
    except Exception:
        size = None

    out = {
        "duration_seconds": duration,
        "width": width,
        "height": height,
        "size": size,
        "mediatype": str(rep.get("mediatype") or ""),
    }
    _PROFILE_CACHE[title] = out
    return dict(out)


def technical_gate(profile: dict, cfg: dict) -> tuple[bool, list[str]]:
    reasons: list[str] = []
    duration = parse_float(profile.get("duration_seconds"))
    width = parse_float(profile.get("width"))
    height = parse_float(profile.get("height"))
    if duration is None:
        return False, ["missing-duration"]
    if width is None or height is None:
        return False, ["missing-dimensions"]

    min_duration = float(cfg.get("min_duration_seconds") or 30)
    max_duration = float(cfg.get("max_duration_seconds") or 300)
    min_width = int(cfg.get("min_width") or 1280)
    min_height = int(cfg.get("min_height") or 720)

    if duration < min_duration:
        reasons.append(f"duration<{int(min_duration)}s")
    if duration > max_duration:
        reasons.append(f"duration>{int(max_duration)}s")
    if width < min_width or height < min_height:
        reasons.append(f"resolution<{min_width}x{min_height}")
    if bool(cfg.get("require_landscape", True)) and width <= height:
        reasons.append("not-landscape")
    return not reasons, reasons


def v1_quality_score(info: dict, profile: dict, semantic_score: int, cfg: dict) -> tuple[int, dict]:
    width = int(profile.get("width") or 0)
    height = int(profile.get("height") or 0)
    duration = float(profile.get("duration_seconds") or 0)
    title = norm(info.get("title", ""))

    if width >= 3840 and height >= 2160:
        visual = 25
    elif width >= 2560 and height >= 1440:
        visual = 24
    elif width >= 1920 and height >= 1080:
        visual = 23
    elif width >= 1600 and height >= 900:
        visual = 21
    else:
        visual = 18

    preferred_min = float(cfg.get("preferred_duration_min_seconds") or 60)
    preferred_max = float(cfg.get("preferred_duration_max_seconds") or 180)
    if preferred_min <= duration <= preferred_max:
        duration_score = 20
    elif 45 <= duration < preferred_min:
        duration_score = 17
    elif duration < 45:
        duration_score = 14
    elif duration <= 240:
        duration_score = 18
    else:
        duration_score = 16

    scene = min(25, 12 + max(0, min(13, int(semantic_score))))
    stable_terms = ("fixed", "stationary", "long take", "real time", "realtime", "ambient")
    moving_terms = ("drone", "aerial", "hyperlapse")
    if any(phrase(title, x) for x in stable_terms):
        stability = 15
    elif any(phrase(title, x) for x in moving_terms):
        stability = 9
    elif any(phrase(title, x) for x in ("timelapse", "time lapse", "time-lapse")):
        stability = 12
    else:
        stability = 11

    immersion = min(15, 9 + max(0, int(semantic_score)) // 2)
    total = min(100, visual + duration_score + scene + stability + immersion)
    return total, {
        "visual": visual,
        "duration": duration_score,
        "scene": scene,
        "stability": stability,
        "immersion": immersion,
    }


def load_zh_labels(cfg: dict) -> dict:
    path = Path(str(cfg.get("zh_labels") or ""))
    if not path.exists():
        return {"cities": {}, "countries": {}}
    data = json.loads(path.read_text(encoding="utf-8"))
    return {
        "cities": dict(data.get("cities") or {}),
        "countries": dict(data.get("countries") or {}),
    }


def contains_cjk(value: str) -> bool:
    return bool(re.search(r"[\u3400-\u9fff]", str(value or "")))


def scene_name_zh(info: dict, loc: dict) -> str:
    # Display labels should describe the actual file title, not incidental
    # words buried in a long Commons description.
    text = norm(str(info.get("title") or ""))
    configured_themes = {norm(str(x)) for x in (loc.get("themes") or []) if x}
    tests = [
        (("aurora",), "极光"),
        (("snow", "snowfall", "snowy"), "雪景"),
        (("rain", "rainy", "raining"), "雨景"),
        (("sunset", "dusk"), "日落"),
        (("sunrise", "dawn"), "日出"),
        (("night", "nighttime"), "夜景"),
        (("fog", "mist"), "云雾"),
        (("waterfall", "falls"), "瀑布"),
        (("glacier", "glacial"), "冰川"),
        (("fjord",), "峡湾"),
        (("beach", "ocean", "coast", "coastal", "seascape", "shore"), "海岸"),
        (("mountain", "mountains", "alpine"), "山景"),
        (("lake", "lagoon"), "湖景"),
        (("river", "canal", "harbor", "harbour", "waterfront"), "水岸"),
        (("forest", "woods"), "森林"),
        (("desert", "dune", "dunes"), "沙漠"),
        (("street",), "街景"),
        (("skyline", "cityscape"), "城市天际线"),
    ]
    for terms, label in tests:
        if configured_themes and str(loc.get("city") or "") != "GPS 景观点":
            if not any(any(phrase(theme, t) or phrase(t, theme) for t in terms) for theme in configured_themes):
                continue
        if any(phrase(text, t) for t in terms):
            return label
    category = str(loc.get("category") or "沉浸实景").split("/", 1)[0].strip()
    return category or "沉浸实景"


def display_name_zh(info: dict, loc: dict, labels: dict) -> tuple[str, str, str]:
    city = str(loc.get("city") or "")
    country = str(loc.get("country") or "")
    city_zh = str((labels.get("cities") or {}).get(city) or "")
    country_zh = str((labels.get("countries") or {}).get(country) or "")
    if not city_zh and contains_cjk(city):
        city_zh = city
    if not country_zh and contains_cjk(country):
        country_zh = country
    place = city_zh or ("自然景观" if city == "GPS 景观点" else scene_name_zh(info, loc))
    return f"{place} · {scene_name_zh(info, loc)}", city_zh, country_zh


def category_titles(category: str, limit: int, interval: float) -> list[str]:
    """Collect file titles from a Commons category with continuation."""
    out: list[str] = []
    cont: dict = {}
    while len(out) < limit:
        try:
            data = http_json({
                "action": "query",
                "list": "categorymembers",
                "cmtitle": "Category:" + category,
                "cmtype": "file",
                "cmlimit": min(50, limit - len(out)),
                **cont,
            }, interval=interval)
        except Exception as exc:
            print(f"warn: scenic category {category}: {exc}", file=sys.stderr)
            break
        for row in data.get("query", {}).get("categorymembers", []):
            title = row.get("title", "")
            if title:
                out.append(title)
        nxt = data.get("continue")
        if not nxt:
            break
        cont = nxt
    return out


def themed_search_titles(loc: dict, per_query: int, max_candidates: int, interval: float) -> list[str]:
    """Discover scenic candidates with Commons-compatible per-theme queries.

    A plain city search is often dominated by events and transit. Querying each
    configured scenic theme separately yields substantially more WindowSwap-like
    footage while keeping every query simple enough for Commons CirrusSearch.
    """
    aliases = [str(loc.get("city") or "")]
    aliases.extend(str(x) for x in loc.get("search_aliases", []) if x and x != loc.get("city"))
    themes = [str(x) for x in loc.get("themes", []) if x]
    if not themes:
        themes = ["rain", "night", "sunset", "skyline", "landscape", "street"]

    out: list[str] = []
    seen: set[str] = set()
    query_limit = min(40, max(8, per_query))

    def run_query(alias: str, query: str) -> None:
        if len(out) >= max_candidates:
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
            title = page.get("title", "")
            if title and title not in seen:
                seen.add(title)
                out.append(title)
                if len(out) >= max_candidates:
                    break

    for alias in aliases[:3]:
        if not alias:
            continue

        # Theme-first discovery across modern Commons video containers.
        # The V1 technical gate still decides whether a result is 30s+, 720p+
        # and landscape before it can enter the catalog.
        for theme in themes[:6]:
            for mime in ("video/webm", "video/mp4"):
                run_query(alias, f'"{alias}" {theme} filemime:{mime}')
                if len(out) >= max_candidates:
                    break
            if len(out) >= max_candidates:
                break

        # Fallback broad title search helps places whose Commons metadata does
        # not use English theme terms. Local scoring still decides acceptance.
        if len(out) < max_candidates:
            for mime in ("video/webm", "video/mp4"):
                run_query(alias, f'intitle:"{alias}" filemime:{mime}')
                if len(out) >= max_candidates:
                    break

        if len(out) >= max_candidates:
            break

    # Scenic titles first. Neutral titles remain available because Commons
    # descriptions can provide the actual scenic signal.
    ranked: list[tuple[int, int, str]] = []
    for index, title in enumerate(out):
        score, _ = quality_score({"title": title, "extmetadata": {}})
        if score < 0:
            continue
        ranked.append((score, -index, title))
    ranked.sort(reverse=True)
    return [title for _, _, title in ranked[:max_candidates]]


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
                "iiprop": "url|mime|size|timestamp|extmetadata",
                "iiextmetadatalanguage": "en",
                "iiextmetadatafilter": (
                    "Artist|Attribution|LicenseShortName|LicenseUrl|UsageTerms|NonFree|"
                    "GPSLatitude|GPSLongitude|ImageDescription|DateTimeOriginal|DateTimeDigitized"
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


def location_relevant(info: dict, loc: dict, distance: float | None) -> bool:
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

    aliases = [str(loc.get("city") or "")]
    aliases.extend(str(x) for x in loc.get("search_aliases", []) if x)
    aliases = [norm(x) for x in aliases if x]
    alias_match = any(text_has_alias(text, alias) for alias in aliases)

    # GPS is strong evidence only when it is reasonably close to the named
    # place. At larger radii, require a textual place match as a second signal.
    if distance is not None:
        return distance <= 60 or alias_match

    return alias_match


def global_scenic_titles(cfg: dict, interval: float) -> list[str]:
    """Discover a broad scenic pool from both search and scenic categories."""
    queries = [str(x) for x in cfg.get("global_scenic_queries", DEFAULT_GLOBAL_SCENIC_QUERIES) if x]
    categories = [str(x) for x in cfg.get("global_scenic_categories", DEFAULT_SCENIC_CATEGORIES) if x]
    per_query = int(cfg.get("global_query_limit") or 45)
    category_limit = int(cfg.get("global_category_limit") or 80)
    max_candidates = int(cfg.get("global_max_candidates") or 1600)
    seen: set[str] = set()
    out: list[str] = []

    def add_title(title: str) -> None:
        if not title or title in seen or len(out) >= max_candidates:
            return
        seen.add(title)
        score, _ = quality_score({"title": title, "extmetadata": {}})
        if score >= 0:
            out.append(title)

    for category in categories:
        if len(out) >= max_candidates:
            break
        for title in category_titles(category, category_limit, interval):
            add_title(title)

    for term in queries:
        if len(out) >= max_candidates:
            break
        search_forms = [
            f'intitle:"{term}" filemime:video/webm',
            f'"{term}" filemime:video/webm',
            f'intitle:"{term}" filemime:video/mp4',
            f'"{term}" filemime:video/mp4',
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
                add_title(page.get("title", ""))

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

        text = norm(str(info.get("title") or "") + " " + ext_value(info.get("extmetadata") or {}, "ImageDescription"))
        alias_match = False
        if nearest is not None:
            aliases = [nearest.get("city"), *(nearest.get("search_aliases") or [])]
            alias_match = any(text_has_alias(text, str(a or "")) for a in aliases if a)

        # Only assign a named place when GPS is very close or the title/description
        # independently names it. Otherwise preserve the exact GPS point instead
        # of inventing a nearby city.
        if nearest is not None and nearest_distance is not None:
            if nearest_distance <= 30 or (nearest_distance <= max_distance and alias_match):
                return nearest, nearest_distance

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
            if alias and text_has_alias(text, alias) and len(alias) > best_len:
                if any(norm(str(bad)) in text for bad in loc.get("reject_terms", [])):
                    continue
                best = loc
                best_len = len(alias)
    return best, None


def quality_score(info: dict, search_hint: str = "") -> tuple[int, list[str]]:
    ext = info.get("extmetadata") or {}
    title = norm(info.get("title", ""))
    desc = norm(ext_value(ext, "ImageDescription"))

    for term in HARD_REJECT:
        if phrase(title, term):
            return -100, [f"reject:{term}"]
    for term in STRICT_DESC_REJECT:
        if phrase(desc, term):
            return -100, [f"reject-desc:{term}"]

    title_score = 0
    desc_score = 0
    reasons: list[str] = []
    for term, weight in SCENIC_WEIGHTS.items():
        if phrase(title, term):
            title_score += weight
            reasons.append(term)
        elif phrase(desc, term):
            desc_score += max(1, weight // 3)

    score = title_score + desc_score
    for term, weight in SOFT_REJECT.items():
        if phrase(title, term):
            score -= weight
        elif phrase(desc, term):
            score -= max(1, weight // 2)

    # Descriptions can contain incidental weather/place words. Require at least
    # one meaningful scenic signal in the title for automatic admission.
    if title_score < 3:
        score = min(score, 4)

    return score, reasons[:8]


def download(url: str, dest: Path, max_bytes: int, interval: float = 1.5, retries: int = 7) -> int:
    """Polite Wikimedia media download with pacing and 429/5xx retry backoff."""
    global _MEDIA_LAST

    for attempt in range(retries):
        wait = interval - (time.monotonic() - _MEDIA_LAST)
        if wait > 0:
            time.sleep(wait)

        req = urllib.request.Request(url, headers={
            "User-Agent": UA,
            "Accept": "video/*,*/*;q=0.8",
            "Accept-Encoding": "identity",
        })
        try:
            total = 0
            with urllib.request.urlopen(req, timeout=180) as r:
                _MEDIA_LAST = time.monotonic()
                declared = int(r.headers.get("Content-Length") or 0)
                if declared and declared > max_bytes:
                    raise ValueError(f"remote file too large: {declared}")
                with dest.open("wb") as f:
                    while True:
                        chunk = r.read(1024 * 1024)
                        if not chunk:
                            break
                        total += len(chunk)
                        if total > max_bytes:
                            raise ValueError(f"download exceeded max bytes: {total}")
                        f.write(chunk)
            return total
        except urllib.error.HTTPError as exc:
            _MEDIA_LAST = time.monotonic()
            if exc.code not in {429, 500, 502, 503, 504} or attempt == retries - 1:
                raise
            retry_after = exc.headers.get("Retry-After")
            try:
                delay = float(retry_after) if retry_after else 0.0
            except Exception:
                delay = 0.0
            delay = max(delay, min(60.0, 5.0 * (2 ** attempt)))
            print(
                f"warn: media HTTP {exc.code}; retry {attempt + 1}/{retries} after {delay:.1f}s :: "
                f"{Path(urllib.parse.urlparse(url).path).name}",
                file=sys.stderr,
            )
            time.sleep(delay)
        except (urllib.error.URLError, TimeoutError):
            _MEDIA_LAST = time.monotonic()
            if attempt == retries - 1:
                raise
            delay = min(45.0, 4.0 * (2 ** attempt))
            print(f"warn: media network retry after {delay:.1f}s", file=sys.stderr)
            time.sleep(delay)

    raise RuntimeError("media download retry loop exhausted")


def normalize_title(title: str) -> str:
    title = str(title or "").removeprefix("File:")
    return re.sub(r"\.[A-Za-z0-9]{2,5}$", "", title).replace("_", " ").strip()


def scene_fingerprint(title: str) -> str:
    text = norm(normalize_title(title))
    text = re.sub(r"\b(no audio|short|video|timelapse|time lapse|time-lapse)\b", " ", text)
    text = re.sub(r"\([^)]*\d{4,}[^)]*\)", " ", text)
    text = re.sub(r"\b\d{4,}\b", " ", text)
    text = re.sub(r"[^0-9a-z\u00c0-\uffff]+", " ", text)
    return re.sub(r"\s+", " ", text).strip()


def normalize_date(value: str) -> str | None:
    raw = strip_html(value)
    if not raw:
        return None
    candidates = [
        ("%Y:%m:%d %H:%M:%S", raw),
        ("%Y-%m-%d %H:%M:%S", raw),
        ("%Y-%m-%dT%H:%M:%SZ", raw),
    ]
    for fmt, text in candidates:
        try:
            dt = datetime.strptime(text, fmt).replace(tzinfo=timezone.utc)
            return dt.isoformat().replace("+00:00", "Z")
        except ValueError:
            pass
    try:
        dt = datetime.fromisoformat(raw.replace("Z", "+00:00"))
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt.astimezone(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    except ValueError:
        return None


def fetch_popularity(cfg: dict) -> dict[str, dict]:
    url = str(cfg.get("popularity_url") or "").strip()
    if not url:
        return {}
    try:
        data = fetch_json_url(url)
        rows = data.get("items", []) if isinstance(data, dict) else []
        return {
            str(row.get("id") or ""): row
            for row in rows
            if isinstance(row, dict) and row.get("id")
        }
    except Exception as exc:
        print(f"warn: popularity unavailable: {exc}", file=sys.stderr)
        return {}


def build_item(
    info: dict,
    loc: dict,
    key: str,
    size: int,
    semantic_score: int,
    reasons: list[str],
    profile: dict,
    quality_total: int,
    breakdown: dict,
    labels: dict,
) -> dict:
    ext = info.get("extmetadata") or {}
    source_url = info.get("descriptionurl") or info.get("descriptionshorturl") or ""
    author = ext_value(ext, "Attribution") or ext_value(ext, "Artist") or "Wikimedia Commons contributor"
    license_name = ext_value(ext, "LicenseShortName") or ext_value(ext, "UsageTerms") or "Free license"
    license_url = ext_value(ext, "LicenseUrl")
    source_published_at = normalize_date(
        ext_value(ext, "DateTimeOriginal") or ext_value(ext, "DateTimeDigitized")
    )
    source_updated_at = normalize_date(str(info.get("timestamp") or ""))

    gps_lat, gps_lng = media_coords(info)
    lat = gps_lat if gps_lat is not None else float(loc["lat"])
    lng = gps_lng if gps_lng is not None else float(loc["lng"])
    original_title = normalize_title(info.get("title", ""))
    name_zh, city_zh, country_zh = display_name_zh(info, loc, labels)

    return {
        "id": "r2-" + hashlib.sha256(str(info.get("url", "")).encode()).hexdigest()[:16],
        "kind": "window",
        "name": name_zh,
        "name_zh": name_zh,
        "original_title": original_title,
        "country": loc.get("country", ""),
        "country_zh": country_zh,
        "city": loc.get("city", ""),
        "city_zh": city_zh,
        "lat": lat,
        "lng": lng,
        "category": loc.get("category", "沉浸实景"),
        "quality_schema_version": 1,
        "quality_score": quality_total,
        "semantic_score": semantic_score,
        "quality_breakdown": breakdown,
        "quality_reasons": reasons,
        "duration_seconds": round(float(profile.get("duration_seconds") or 0), 2),
        "width": int(profile.get("width") or 0),
        "height": int(profile.get("height") or 0),
        "source": "Wikimedia Commons → Ooglex R2",
        "author": author[:240],
        "license": license_name[:120],
        "license_url": license_url,
        "source_url": source_url,
        "r2_key": key,
        "bytes": size,
        "origin_url": info.get("url", ""),
        "source_published_at": source_published_at,
        "source_updated_at": source_updated_at,
        "catalog_added_at": RUN_AT,
    }


def ingest_existing(
    cfg: dict,
    seen_urls: set[str],
    seen_keys: set[str],
    min_quality: int,
    labels: dict,
    interval: float,
) -> list[dict]:
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

    popularity = fetch_popularity(cfg)
    candidates: list[tuple[tuple[int, int, int, str], dict, str, str, str]] = []
    scene_fingerprints: set[str] = set()
    rejected_technical = 0
    rejected_semantic = 0

    for row in rows:
        key = str(row.get("r2_key") or "")
        if not key.startswith("media/") or key in seen_keys:
            continue
        origin = str(row.get("origin_url") or "")
        if origin and origin in seen_urls:
            continue

        original_title = str(row.get("original_title") or "").strip()
        file_title = source_title_from_url(str(row.get("source_url") or ""), original_title or str(row.get("name") or ""))
        if not original_title:
            original_title = normalize_title(file_title)

        synthetic = {
            "title": file_title or ("File:" + original_title),
            "extmetadata": {"ImageDescription": {"value": ""}},
        }
        semantic_score, gate_reasons = quality_score(synthetic)
        if semantic_score < 5:
            rejected_semantic += 1
            continue

        profile = {
            "duration_seconds": row.get("duration_seconds"),
            "width": row.get("width"),
            "height": row.get("height"),
            "size": row.get("bytes"),
        }
        if not profile.get("duration_seconds") or not profile.get("width") or not profile.get("height"):
            profile = rest_media_profile(file_title, interval=interval)
        technical_ok, technical_reasons = technical_gate(profile, cfg)
        if not technical_ok:
            rejected_technical += 1
            continue

        total_score, breakdown = v1_quality_score(synthetic, profile, semantic_score, cfg)
        if total_score < min_quality:
            continue

        fingerprint = scene_fingerprint(original_title)
        if fingerprint and fingerprint in scene_fingerprints:
            continue
        if fingerprint:
            scene_fingerprints.add(fingerprint)

        loc = {
            "city": row.get("city") or "GPS 景观点",
            "country": row.get("country") or "",
            "category": row.get("category") or "沉浸实景",
        }
        name_zh, city_zh, country_zh = display_name_zh(synthetic, loc, labels)
        city_zh = city_zh or str(row.get("city_zh") or "")
        country_zh = country_zh or str(row.get("country_zh") or "")
        pop = popularity.get(str(row.get("id") or ""), {})
        plays30 = int(pop.get("plays30d") or pop.get("plays") or 0)
        total_plays = int(pop.get("total") or 0)
        added_at = str(row.get("catalog_added_at") or "")
        item = {
            **row,
            "kind": "window",
            "name": name_zh,
            "name_zh": name_zh,
            "original_title": original_title,
            "city_zh": city_zh,
            "country_zh": country_zh,
            "quality_schema_version": 1,
            "quality_score": total_score,
            "semantic_score": semantic_score,
            "quality_breakdown": breakdown,
            "quality_reasons": list(row.get("quality_reasons") or []) + gate_reasons + technical_reasons + ["existing-r2"],
            "duration_seconds": round(float(profile.get("duration_seconds") or 0), 2),
            "width": int(profile.get("width") or 0),
            "height": int(profile.get("height") or 0),
        }
        candidates.append(((plays30, total_plays, total_score, added_at), item, key, origin, fingerprint))

    candidates.sort(key=lambda x: x[0], reverse=True)
    keep_limit = int(cfg.get("existing_keep_limit") or len(candidates))
    out: list[dict] = []
    for _, item, key, origin, _fingerprint in candidates[:keep_limit]:
        out.append(item)
        seen_keys.add(key)
        if origin:
            seen_urls.add(origin)

    print(
        f"reused {len(out)} V1-quality clips from existing R2 manifest "
        f"(eligible={len(candidates)}, rejected_technical={rejected_technical}, "
        f"rejected_semantic={rejected_semantic}, keep_limit={keep_limit}, "
        f"popularity={'on' if popularity else 'off'})"
    )
    return out


def seed_items(
    cfg: dict,
    root: Path,
    seen_urls: set[str],
    seen_keys: set[str],
    labels: dict,
    interval: float,
    manifest_only: bool = False,
) -> tuple[list[dict], list[dict]]:
    path = Path(str(cfg.get("seed_manifest") or ""))
    if not path.exists():
        return [], []

    max_bytes = int(float(cfg.get("max_seed_file_mb") or 80) * 1024 * 1024)
    media_dir = root / "media"
    rows = json.loads(path.read_text(encoding="utf-8"))
    items: list[dict] = []
    plan: list[dict] = []

    for seed in rows:
        url = str(seed.get("video_url") or "")
        if not url or url in seen_urls:
            continue
        try:
            file_title = source_title_from_url(str(seed.get("source_url") or ""), str(seed.get("name") or ""))
            synthetic = {
                "title": file_title,
                "extmetadata": {"ImageDescription": {"value": ""}},
            }
            semantic_score, reasons = quality_score(synthetic)
            if semantic_score < 0:
                print(f"seed rejected semantic: {seed.get('name','?')} :: {semantic_score}")
                continue
            # Manual seeds are explicitly reviewed. They may use place names
            # without scenic keywords, but still must satisfy every technical
            # gate and the final V1 quality score.
            semantic_score = max(int(cfg.get("min_semantic_score") or 5), semantic_score)
            profile = rest_media_profile(file_title, interval=interval)
            technical_ok, technical_reasons = technical_gate(profile, cfg)
            if not technical_ok:
                print(f"seed rejected technical: {seed.get('name','?')} :: {','.join(technical_reasons)}")
                continue
            total_score, breakdown = v1_quality_score(synthetic, profile, semantic_score, cfg)
            if total_score < int(cfg.get("min_quality_score") or 60):
                continue

            suffix = Path(urllib.parse.urlparse(url).path).suffix.lower()
            if suffix not in {".webm", ".ogv", ".ogg", ".mp4"}:
                suffix = ".webm"
            digest = hashlib.sha256(url.encode()).hexdigest()[:24]
            key = "media/" + digest + suffix
            if key in seen_keys:
                continue
            dest = media_dir / (digest + suffix)
            mime = "video/mp4" if suffix == ".mp4" else ("video/ogg" if suffix in {".ogv", ".ogg"} else "video/webm")
            if manifest_only:
                size = int(profile.get("size") or 0)
                if size <= 0 or size > max_bytes:
                    continue
            else:
                tmp = dest.with_suffix(dest.suffix + ".part")
                if tmp.exists():
                    tmp.unlink()
                size = download(url, tmp, max_bytes)
                tmp.replace(dest)

            loc = {
                "city": seed.get("city") or "GPS 景观点",
                "country": seed.get("country") or "",
                "category": seed.get("category") or "沉浸实景",
            }
            name_zh, city_zh, country_zh = display_name_zh(synthetic, loc, labels)
            if contains_cjk(str(seed.get("name") or "")):
                name_zh = str(seed.get("name"))
            item = {
                **seed,
                "id": "r2-seed-" + digest[:16],
                "kind": "window",
                "name": name_zh,
                "name_zh": name_zh,
                "original_title": normalize_title(file_title),
                "city_zh": str(seed.get("city_zh") or "") or city_zh or (str(seed.get("city")) if contains_cjk(str(seed.get("city") or "")) else ""),
                "country_zh": str(seed.get("country_zh") or "") or country_zh or (str(seed.get("country")) if contains_cjk(str(seed.get("country") or "")) else ""),
                "source": "Curated seed → Ooglex R2",
                "r2_key": key,
                "bytes": size,
                "origin_url": url,
                "quality_schema_version": 1,
                "quality_score": total_score,
                "semantic_score": semantic_score,
                "quality_breakdown": breakdown,
                "quality_reasons": reasons + technical_reasons + ["manual-seed"],
                "duration_seconds": round(float(profile.get("duration_seconds") or 0), 2),
                "width": int(profile.get("width") or 0),
                "height": int(profile.get("height") or 0),
                "source_published_at": seed.get("source_published_at"),
                "source_updated_at": seed.get("source_updated_at"),
                "catalog_added_at": seed.get("catalog_added_at") or RUN_AT,
            }
            item.pop("video_url", None)
            items.append(item)
            if not manifest_only:
                plan.append({"local": str(dest), "key": key, "content_type": mime, "bytes": size})
            seen_urls.add(url)
            seen_keys.add(key)
            print(
                f"seed accepted: {name_zh} :: score={total_score} :: "
                f"{profile.get('width')}x{profile.get('height')} :: "
                f"{float(profile.get('duration_seconds') or 0):.1f}s :: {size/1024/1024:.1f} MiB"
            )
        except Exception as exc:
            print(f"warn: seed skipped {seed.get('name','?')}: {exc}", file=sys.stderr)

    return items, plan


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", default="data/global-windows/locations.json")
    ap.add_argument("--output", default=".window-build")
    ap.add_argument("--target", type=int, default=0)
    ap.add_argument("--audit-existing", action="store_true")
    ap.add_argument("--manifest-only", action="store_true", help="Build and validate metadata without downloading new media")
    args = ap.parse_args()

    cfg = json.loads(Path(args.config).read_text(encoding="utf-8"))
    target = args.target or int(cfg.get("target") or 150)
    max_per_location = int(cfg.get("max_per_location") or 3)
    min_quality = int(cfg.get("min_quality_score") or 60)
    min_semantic = int(cfg.get("min_semantic_score") or 5)
    min_bytes = int(float(cfg.get("min_file_mb") or 0.8) * 1024 * 1024)
    max_bytes = int(float(cfg.get("max_file_mb") or 80) * 1024 * 1024)
    max_catalog_bytes = int(float(cfg.get("max_catalog_gb") or 8) * 1024 * 1024 * 1024)
    max_candidates = int(cfg.get("max_candidates_per_location") or 40)
    per_query = int(cfg.get("theme_query_limit") or 24)
    default_radius_km = float(cfg.get("max_distance_km") or 400)
    interval = float(cfg.get("request_interval_seconds") or 0.8)
    min_width = int(cfg.get("min_width") or 1280)
    min_height = int(cfg.get("min_height") or 720)
    labels = load_zh_labels(cfg)

    root = Path(args.output)
    media_dir = root / "media"
    manifest_dir = root / "manifest"
    media_dir.mkdir(parents=True, exist_ok=True)
    manifest_dir.mkdir(parents=True, exist_ok=True)

    seen_urls: set[str] = set()
    seen_keys: set[str] = set()
    upload_plan: list[dict] = []

    existing_min_quality = int(cfg.get("existing_min_quality_score") or min_quality)
    items = ingest_existing(cfg, seen_urls, seen_keys, existing_min_quality, labels, interval)

    if args.audit_existing:
        audit_path = root / "audit-existing.json"
        audit_path.write_text(json.dumps(items, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        total = sum(int(x.get("bytes") or 0) for x in items)
        print(
            f"V1 audit existing: pass={len(items)} :: {total/1024/1024:.1f} MiB :: "
            f"min_duration={cfg.get('min_duration_seconds')}s :: "
            f"min_resolution={min_width}x{min_height} :: min_score={min_quality}"
        )
        return 0

    seeds, seed_plan = seed_items(cfg, root, seen_urls, seen_keys, labels, interval, args.manifest_only)
    items.extend(seeds)
    upload_plan.extend(seed_plan)
    seen_scenes = {
        scene_fingerprint(str(x.get("original_title") or x.get("name") or ""))
        for x in items
    }
    seen_scenes.discard("")

    city_counts = Counter(str(x.get("city") or "") for x in items)
    rejected_quality = 0
    rejected_technical = 0
    rejected_geo = 0
    rejected_location = 0
    rejected_size = 0

    local_locations = list(cfg.get("locations", []))[:int(cfg.get("local_location_scan_limit") or 36)]
    for loc in local_locations:
        if len(items) >= target:
            break

        city = str(loc["city"])
        used_here = city_counts[city]
        if used_here >= max_per_location:
            continue

        titles = themed_search_titles(loc, per_query=per_query, max_candidates=max_candidates, interval=interval)
        if not titles:
            continue
        infos = image_infos(titles, interval=interval)

        for title in titles:
            if len(items) >= target or used_here >= max_per_location:
                break
            info = infos.get(title)
            if not info:
                continue

            try:
                mime = str(info.get("mime") or "").lower()
                url = str(info.get("url") or "")
                size = int(info.get("size") or 0)
                width_hint = int(info.get("width") or 0)
                height_hint = int(info.get("height") or 0)
                if mime not in VIDEO_MIMES or not url or url in seen_urls or not license_ok(info):
                    continue
                if size < min_bytes or size > max_bytes:
                    rejected_size += 1
                    continue
                if width_hint and height_hint:
                    if width_hint < min_width or height_hint < min_height or (
                        bool(cfg.get("require_landscape", True)) and width_hint <= height_hint
                    ):
                        rejected_technical += 1
                        continue

                semantic_score, reasons = quality_score(info)
                if semantic_score < min_semantic:
                    rejected_quality += 1
                    continue
                fingerprint = scene_fingerprint(title)
                if fingerprint and fingerprint in seen_scenes:
                    continue

                within, distance = geo_ok(info, loc, default_radius_km)
                if not within:
                    rejected_geo += 1
                    continue
                if not location_relevant(info, loc, distance):
                    rejected_location += 1
                    continue

                profile = rest_media_profile(title, interval=interval)
                technical_ok, technical_reasons = technical_gate(profile, cfg)
                if not technical_ok:
                    rejected_technical += 1
                    continue
                total_score, breakdown = v1_quality_score(info, profile, semantic_score, cfg)
                if total_score < min_quality:
                    rejected_quality += 1
                    continue

                ext = media_ext(info)
                digest = hashlib.sha256(url.encode()).hexdigest()[:24]
                filename = digest + ext
                key = "media/" + filename
                if key in seen_keys:
                    continue
                dest = media_dir / filename
                if not args.manifest_only and (not dest.exists() or dest.stat().st_size != size):
                    tmp = dest.with_suffix(dest.suffix + ".part")
                    if tmp.exists():
                        tmp.unlink()
                    got = download(url, tmp, max_bytes)
                    tmp.replace(dest)
                    size = got

                item = build_item(
                    info, loc, key, size, semantic_score, reasons + technical_reasons,
                    profile, total_score, breakdown, labels
                )
                items.append(item)
                if fingerprint:
                    seen_scenes.add(fingerprint)
                if not args.manifest_only:
                    upload_plan.append({"local": str(dest), "key": key, "content_type": mime, "bytes": size})
                seen_urls.add(url)
                seen_keys.add(key)
                used_here += 1
                city_counts[city] += 1
                distance_note = "" if distance is None else f" · {distance:.0f} km"
                print(
                    f"accepted {len(items):03d}/{target}: {item['name']} :: score={total_score} :: "
                    f"{item['width']}x{item['height']} :: {item['duration_seconds']:.1f}s :: "
                    f"{size/1024/1024:.1f} MiB{distance_note}"
                )
            except Exception as exc:
                print(f"warn: skip {title}: {exc}", file=sys.stderr)

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
            try:
                mime = str(info.get("mime") or "").lower()
                url = str(info.get("url") or "")
                size = int(info.get("size") or 0)
                width_hint = int(info.get("width") or 0)
                height_hint = int(info.get("height") or 0)
                if mime not in VIDEO_MIMES or not url or url in seen_urls or not license_ok(info):
                    continue
                if size < min_bytes or size > max_bytes:
                    rejected_size += 1
                    continue
                if width_hint and height_hint:
                    if width_hint < min_width or height_hint < min_height or (
                        bool(cfg.get("require_landscape", True)) and width_hint <= height_hint
                    ):
                        rejected_technical += 1
                        continue

                semantic_score, reasons = quality_score(info)
                if semantic_score < min_semantic:
                    rejected_quality += 1
                    continue
                fingerprint = scene_fingerprint(title)
                if fingerprint and fingerprint in seen_scenes:
                    continue

                loc, distance = match_global_location(info, locations, cfg)
                if not loc:
                    rejected_location += 1
                    continue

                city = str(loc.get("city") or "GPS 景观点")
                if city != "GPS 景观点" and city_counts[city] >= global_cap:
                    continue

                profile = rest_media_profile(title, interval=interval)
                technical_ok, technical_reasons = technical_gate(profile, cfg)
                if not technical_ok:
                    rejected_technical += 1
                    continue
                total_score, breakdown = v1_quality_score(info, profile, semantic_score, cfg)
                if total_score < min_quality:
                    rejected_quality += 1
                    continue

                ext = media_ext(info)
                digest = hashlib.sha256(url.encode()).hexdigest()[:24]
                filename = digest + ext
                key = "media/" + filename
                if key in seen_keys:
                    continue
                dest = media_dir / filename
                if not args.manifest_only and (not dest.exists() or dest.stat().st_size != size):
                    tmp = dest.with_suffix(dest.suffix + ".part")
                    if tmp.exists():
                        tmp.unlink()
                    got = download(url, tmp, max_bytes)
                    tmp.replace(dest)
                    size = got

                item = build_item(
                    info, loc, key, size, semantic_score,
                    reasons + technical_reasons + ["global-scenic"],
                    profile, total_score, breakdown, labels
                )
                items.append(item)
                if fingerprint:
                    seen_scenes.add(fingerprint)
                if not args.manifest_only:
                    upload_plan.append({"local": str(dest), "key": key, "content_type": mime, "bytes": size})
                seen_urls.add(url)
                seen_keys.add(key)
                city_counts[city] += 1
                distance_note = "" if distance is None else f" · {distance:.0f} km"
                print(
                    f"global accepted {len(items):03d}/{target}: {item['name']} :: score={total_score} :: "
                    f"{item['width']}x{item['height']} :: {item['duration_seconds']:.1f}s :: "
                    f"{size/1024/1024:.1f} MiB{distance_note}"
                )
            except Exception as exc:
                print(f"warn: global skip {title}: {exc}", file=sys.stderr)

    min_catalog = int(cfg.get("min_catalog") or 100)
    required = min(target, max(12, min_catalog))
    if len(items) < required:
        raise SystemExit(f"curated catalog too small: {len(items)} accepted; require at least {required}")

    items.sort(key=lambda x: (
        -int(x.get("quality_score") or 0),
        int(x.get("bytes") or 0),
        str(x.get("city_zh") or x.get("city") or ""),
        str(x.get("name") or ""),
    ))
    chosen: list[dict] = []
    chosen_bytes = 0
    budget_skipped = 0
    for item in items:
        if len(chosen) >= target:
            break
        size = int(item.get("bytes") or 0)
        if chosen_bytes + size > max_catalog_bytes:
            budget_skipped += 1
            continue
        chosen.append(item)
        chosen_bytes += size

    if len(chosen) < required:
        raise SystemExit(
            f"catalog budget too small: {len(chosen)} fit within "
            f"{max_catalog_bytes/1024/1024/1024:.1f} GiB; require {required}"
        )

    selected_keys = {x["r2_key"] for x in chosen}
    upload_plan = [x for x in upload_plan if x["key"] in selected_keys]

    (manifest_dir / "windows.json").write_text(json.dumps(chosen, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (root / "upload-plan.json").write_text(json.dumps(upload_plan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    scores = [int(x.get("quality_score") or 0) for x in chosen]
    cities = {str(x.get("city") or "") for x in chosen}
    durations = [float(x.get("duration_seconds") or 0) for x in chosen]
    widths = [int(x.get("width") or 0) for x in chosen]
    heights = [int(x.get("height") or 0) for x in chosen]
    print(
        f"built {len(chosen)} V1 WINDOW clips across {len(cities)} locations, "
        f"{chosen_bytes/1024/1024:.1f} MiB catalog size, score min/avg/max="
        f"{min(scores)}/{sum(scores)/len(scores):.1f}/{max(scores)}, "
        f"duration min/avg/max={min(durations):.1f}/{sum(durations)/len(durations):.1f}/{max(durations):.1f}s"
    )
    print(
        f"resolution floor={min(widths)}x{min(heights)}; new uploads={len(upload_plan)}; "
        f"rejected technical={rejected_technical}, quality={rejected_quality}, "
        f"geo={rejected_geo}, location={rejected_location}, size={rejected_size}, budget={budget_skipped}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
