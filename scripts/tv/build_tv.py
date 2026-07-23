#!/usr/bin/env python3
# 生成「环球TV」频道库：从 iptv-org 公开数据（channels.json + streams.json）抓取全球电视台的
# HTTPS 直播源（HLS / mp4），按国家 / 行政区就近落到经纬度，写入 apps/tv/channels.json
#（同源托管，规避国内直连外网 API 不稳的问题）。
# 在 GitHub Actions 上运行（GitHub 服务器可正常访问 iptv-org）。仅用标准库，无需密钥。
#
# 存活探测：iptv-org 库里大量直播源早已失效，全部收录会让用户满屏「打不开」。
# 这里在构建时并发 GET 每个候选源：HLS 必须真的返回 #EXTM3U 才算活，同时记录是否带
# CORS 头（浏览器 hls.js 直连必需）。每台保留最多 1 主源 + 2 备用源，活源在前。
# 注意：中国大陆/港澳台的源常对境外 IP 做地域封锁，GitHub 服务器探不准 → 华语区频道
# 即使探测失败也保留（排序靠后由前端自动跳台兜底），其它地区只收录探活的源。
import json, os, ssl, random, urllib.request, zlib
from concurrent.futures import ThreadPoolExecutor

API = "https://iptv-org.github.io/api"
CTX = ssl.create_default_context()
CAP = 6000       # 最多收录频道数（兼顾移动端性能）
MAX_SRC = 4      # 每台最多探测的候选源数
MAX_ALT = 2      # 每台随主源附带的备用源上限
PROBE_TIMEOUT = 12
PROBE_WORKERS = 64
UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/124.0 Safari/537.36")
# 探测阶段总体活源少于此数，视为 CI 网络异常：中止并保留旧文件，避免把频道库清空
MIN_ALIVE = 500
# 华语区：境外服务器探测结果不可信（地域封锁），探不活也保留
CN_KEEP = {"CN", "HK", "MO", "TW"}

# 优先地区（华语区 + 亚洲）：排序时靠前，确保被 CAP 截断时优先保留
PRIORITY = {cc: i for i, cc in enumerate(
    ["CN", "HK", "MO", "TW", "JP", "KR", "SG", "MY", "TH", "VN", "PH", "ID", "IN"])}

# 国家/地区 → 首都（或代表城市）经纬度（ISO 3166-1 alpha-2）
CC_CENTER = {
    "CN": (39.90, 116.40), "HK": (22.32, 114.17), "MO": (22.20, 113.55), "TW": (25.03, 121.57),
    "JP": (35.68, 139.69), "KR": (37.57, 126.98), "KP": (39.02, 125.75), "MN": (47.89, 106.91),
    "SG": (1.35, 103.82), "MY": (3.14, 101.69), "TH": (13.75, 100.52), "VN": (21.03, 105.85),
    "PH": (14.60, 120.98), "ID": (-6.21, 106.85), "KH": (11.56, 104.92), "LA": (17.97, 102.60),
    "MM": (16.87, 96.20), "BN": (4.90, 114.94), "IN": (28.61, 77.21), "PK": (33.69, 73.06),
    "BD": (23.81, 90.41), "LK": (6.93, 79.86), "NP": (27.72, 85.32), "AF": (34.53, 69.17),
    "IR": (35.69, 51.39), "IQ": (33.31, 44.36), "SA": (24.71, 46.68), "AE": (24.45, 54.38),
    "QA": (25.29, 51.53), "KW": (29.38, 47.99), "BH": (26.23, 50.59), "OM": (23.59, 58.41),
    "YE": (15.35, 44.21), "JO": (31.95, 35.93), "LB": (33.89, 35.50), "SY": (33.51, 36.29),
    "IL": (31.77, 35.22), "PS": (31.90, 35.20), "TR": (39.93, 32.86), "CY": (35.19, 33.38),
    "GE": (41.72, 44.79), "AM": (40.18, 44.51), "AZ": (40.41, 49.87), "KZ": (51.16, 71.47),
    "UZ": (41.31, 69.24), "TM": (37.95, 58.38), "KG": (42.87, 74.59), "TJ": (38.56, 68.79),
    "RU": (55.75, 37.62), "UA": (50.45, 30.52), "BY": (53.90, 27.57), "MD": (47.01, 28.86),
    "PL": (52.23, 21.01), "CZ": (50.09, 14.42), "SK": (48.15, 17.11), "HU": (47.50, 19.04),
    "RO": (44.43, 26.10), "BG": (42.70, 23.32), "RS": (44.79, 20.45), "HR": (45.81, 15.98),
    "SI": (46.06, 14.51), "BA": (43.86, 18.41), "MK": (41.99, 21.43), "AL": (41.33, 19.82),
    "ME": (42.44, 19.26), "XK": (42.66, 21.17), "GR": (37.98, 23.73), "IT": (41.90, 12.50),
    "ES": (40.42, -3.70), "PT": (38.72, -9.14), "FR": (48.85, 2.35), "DE": (52.52, 13.40),
    "AT": (48.21, 16.37), "CH": (46.95, 7.45), "BE": (50.85, 4.35), "NL": (52.37, 4.90),
    "LU": (49.61, 6.13), "GB": (51.51, -0.13), "IE": (53.35, -6.26), "DK": (55.68, 12.57),
    "SE": (59.33, 18.07), "NO": (59.91, 10.75), "FI": (60.17, 24.94), "IS": (64.15, -21.94),
    "EE": (59.44, 24.75), "LV": (56.95, 24.11), "LT": (54.69, 25.28), "MT": (35.90, 14.51),
    "US": (38.90, -77.04), "CA": (45.42, -75.70), "MX": (19.43, -99.13), "GT": (14.63, -90.51),
    "BZ": (17.25, -88.77), "SV": (13.69, -89.19), "HN": (14.10, -87.22), "NI": (12.11, -86.24),
    "CR": (9.93, -84.08), "PA": (8.98, -79.52), "CU": (23.11, -82.37), "DO": (18.49, -69.93),
    "HT": (18.59, -72.31), "JM": (18.02, -76.79), "PR": (18.47, -66.10), "TT": (10.66, -61.51),
    "CO": (4.71, -74.07), "VE": (10.48, -66.90), "EC": (-0.18, -78.47), "PE": (-12.05, -77.04),
    "BO": (-16.50, -68.15), "CL": (-33.45, -70.67), "AR": (-34.60, -58.38), "UY": (-34.90, -56.16),
    "PY": (-25.28, -57.64), "BR": (-15.79, -47.88), "GY": (6.80, -58.16), "SR": (5.87, -55.17),
    "EG": (30.04, 31.24), "LY": (32.89, 13.19), "TN": (36.81, 10.18), "DZ": (36.75, 3.06),
    "MA": (33.97, -6.85), "MR": (18.08, -15.98), "SD": (15.50, 32.56), "SS": (4.85, 31.58),
    "ET": (9.03, 38.74), "ER": (15.34, 38.93), "DJ": (11.59, 43.15), "SO": (2.05, 45.34),
    "KE": (-1.29, 36.82), "UG": (0.35, 32.58), "TZ": (-6.79, 39.21), "RW": (-1.95, 30.06),
    "BI": (-3.38, 29.36), "CD": (-4.44, 15.27), "CG": (-4.26, 15.24), "GA": (0.42, 9.47),
    "CM": (3.87, 11.52), "NG": (9.08, 7.40), "GH": (5.60, -0.19), "CI": (6.83, -5.29),
    "SN": (14.72, -17.47), "ML": (12.65, -8.00), "BF": (12.37, -1.52), "NE": (13.51, 2.11),
    "TD": (12.11, 15.04), "GN": (9.64, -13.58), "SL": (8.48, -13.23), "LR": (6.30, -10.80),
    "TG": (6.17, 1.23), "BJ": (6.50, 2.60), "ZA": (-25.75, 28.19), "ZW": (-17.83, 31.05),
    "ZM": (-15.42, 28.28), "MW": (-13.96, 33.77), "MZ": (-25.97, 32.58), "AO": (-8.84, 13.23),
    "NA": (-22.56, 17.08), "BW": (-24.63, 25.92), "MG": (-18.88, 47.51), "MU": (-20.16, 57.50),
    "AU": (-35.28, 149.13), "NZ": (-41.29, 174.78), "FJ": (-18.14, 178.44), "PG": (-9.44, 147.18),
}

# 中国各省/直辖市 → 省会经纬度（iptv-org subdivision 常用 ISO 代码 CN-XX）
CN_SUB = {
    "CN-BJ": (39.90, 116.40), "CN-SH": (31.23, 121.47), "CN-TJ": (39.13, 117.20),
    "CN-CQ": (29.56, 106.55), "CN-GD": (23.13, 113.26), "CN-ZJ": (30.27, 120.15),
    "CN-JS": (32.06, 118.80), "CN-SD": (36.65, 117.02), "CN-SC": (30.57, 104.07),
    "CN-HB": (30.59, 114.30), "CN-HN": (28.23, 112.94), "CN-FJ": (26.07, 119.30),
    "CN-YN": (25.04, 102.71), "CN-HA": (34.76, 113.65), "CN-HE": (38.04, 114.51),
    "CN-SN": (34.34, 108.94), "CN-SX": (37.87, 112.55), "CN-LN": (41.80, 123.43),
    "CN-JL": (43.90, 125.33), "CN-HL": (45.80, 126.53), "CN-AH": (31.86, 117.28),
    "CN-JX": (28.68, 115.86), "CN-GX": (22.82, 108.32), "CN-GZ": (26.65, 106.63),
    "CN-GS": (36.06, 103.83), "CN-HI": (20.02, 110.35), "CN-NM": (40.84, 111.75),
    "CN-XJ": (43.83, 87.62), "CN-XZ": (29.65, 91.14), "CN-NX": (38.47, 106.28),
    "CN-QH": (36.62, 101.78),
}
# 美国部分州 → 代表城市（iptv-org subdivision US-XX）
US_SUB = {
    "US-CA": (34.05, -118.24), "US-NY": (40.71, -74.01), "US-TX": (29.76, -95.37),
    "US-FL": (25.76, -80.19), "US-IL": (41.88, -87.63), "US-WA": (47.61, -122.33),
    "US-DC": (38.90, -77.04), "US-GA": (33.75, -84.39), "US-MA": (42.36, -71.06),
    "US-PA": (39.95, -75.16), "US-OH": (39.96, -82.99), "US-MI": (42.33, -83.05),
    "US-AZ": (33.45, -112.07), "US-CO": (39.74, -104.99), "US-NV": (36.17, -115.14),
    "US-OR": (45.52, -122.68), "US-NC": (35.23, -80.84), "US-TN": (36.16, -86.78),
    "US-LA": (29.95, -90.07), "US-MN": (44.98, -93.27), "US-HI": (21.31, -157.86),
    "US-PR": (18.47, -66.10),
}
SUBDIV = {**CN_SUB, **US_SUB}


def fetch(name):
    url = f"{API}/{name}"
    for attempt in range(4):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "OoglexTV/1.0 (+https://ooglex.com)"})
            with urllib.request.urlopen(req, timeout=60, context=CTX) as r:
                return json.load(r)
        except Exception as e:
            print(f"  fetch {name} failed ({attempt+1}/4): {e}")
    return None


def geocode(cc, subdivision):
    """返回 (lat,lng)：优先按行政区，其次国家首都，都没有则 None。带少量抖动避免重叠。"""
    if subdivision and subdivision in SUBDIV:
        la, lo = SUBDIV[subdivision]
        return la + random.uniform(-0.25, 0.25), lo + random.uniform(-0.25, 0.25)
    if cc in CC_CENTER:
        la, lo = CC_CENTER[cc]
        return la + random.uniform(-0.5, 0.5), lo + random.uniform(-0.5, 0.5)
    return None


# 浏览器（hls.js / <video>）播不了的格式，直接排除
BAD_EXT = (".mpd", ".flv", ".mp3", ".aac", ".ts", ".m3u", ".mkv", ".avi")


def usable(url):
    """接受任意 HTTPS 直播源地址（不再要求 .m3u8 后缀——无后缀的 HLS 清单
    由存活探测按内容验证），仅排除明确播不了的格式。"""
    u = (url or "").strip()
    if not u.startswith("https://"):
        return None
    path = u.split("?", 1)[0].split("#", 1)[0].lower()
    if path.endswith(BAD_EXT):
        return None
    return u


def probe(url):
    """探测单个直播源：返回 (alive, cors)。
    HLS 清单必须真的以 #EXTM3U 开头才算活（顺带覆盖无 .m3u8 后缀的源）；
    .mp4 只要能拿到 2xx/3xx 就算活。cors = 响应带 Access-Control-Allow-Origin
    （hls.js 跨域直连必需；没有的源浏览器里只能走代理）。"""
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "*/*"})
    try:
        with urllib.request.urlopen(req, timeout=PROBE_TIMEOUT, context=CTX) as r:
            if getattr(r, "status", 200) >= 400:
                return False, False
            if not (r.geturl() or url).startswith("https://"):
                return False, False   # 重定向落到 http:// 的，浏览器会拦（混合内容）
            cors = bool(r.headers.get("Access-Control-Allow-Origin"))
            if url.split("?", 1)[0].lower().endswith(".mp4"):
                return True, cors
            head = r.read(4096) or b""
            if (r.headers.get("Content-Encoding") or "").lower() == "gzip":
                try:
                    head = zlib.decompressobj(16 + zlib.MAX_WBITS).decompress(head)
                except Exception:
                    pass
            return (head.strip().startswith(b"#EXTM3U"), cors)
    except Exception:
        return False, False


def probe_all(urls):
    """并发探测一批地址 → {url: (alive, cors)}"""
    res = {}
    urls = list(urls)
    print(f"Probing {len(urls)} stream urls …")
    with ThreadPoolExecutor(max_workers=PROBE_WORKERS) as ex:
        for i, (u, ok) in enumerate(zip(urls, ex.map(probe, urls))):
            res[u] = ok
            if (i + 1) % 1000 == 0:
                alive = sum(1 for v in res.values() if v[0])
                print(f"  {i + 1}/{len(urls)} probed, alive {alive}")
    alive = sum(1 for v in res.values() if v[0])
    cors = sum(1 for v in res.values() if v[0] and v[1])
    print(f"  done: alive {alive}/{len(urls)} (with CORS {cors})")
    return res


def load_pinned():
    """读取手工精选台 channels-fallback.json，规范化为 8 字段并去重，作为置顶列表。
    容错：文件缺失/损坏则返回空列表，不影响主流程。"""
    path = "apps/tv/channels-fallback.json"
    try:
        with open(path, encoding="utf-8") as f:
            raw = json.load(f)
    except Exception as e:
        print(f"  pinned list unavailable ({e}) — skip")
        return []
    seen, pinned = set(), []
    for r in raw:
        if not isinstance(r, list) or len(r) < 7:
            continue
        url = usable(r[3])
        if not url or url in seen:
            continue
        try:
            lat, lng = round(float(r[1]), 4), round(float(r[2]), 4)
        except (TypeError, ValueError):
            continue
        name = str(r[0] or "").strip()[:60]
        if not name:
            continue
        logo = r[7] if len(r) > 7 and isinstance(r[7], str) and r[7].startswith("https://") else ""
        seen.add(url)
        # [name, lat, lng, url, country, region, cc, logo]
        pinned.append([name, lat, lng, url,
                       str(r[4] or "")[:40], str(r[5] or "")[:40], str(r[6] or "").upper(), logo])
    return pinned


def main():
    print("Fetching channels …")
    channels = fetch("channels.json") or []
    print(f"  channels: {len(channels)}")
    print("Fetching streams …")
    streams = fetch("streams.json") or []
    print(f"  streams: {len(streams)}")
    print("Fetching countries …")
    countries = fetch("countries.json") or []
    cc_name = {c["code"].upper(): c.get("name", c["code"]) for c in countries if c.get("code")}
    if not channels or not streams:
        raise SystemExit("iptv-org data unavailable — aborting, keep old file.")

    chan = {c["id"]: c for c in channels if c.get("id")}

    # 每个频道收集最多 MAX_SRC 个候选 HTTPS 源（跳过要求特殊 Referer/UA 的——浏览器带不了这类头）
    cands = {}
    for s in streams:
        cid = s.get("channel")
        if not cid or cid not in chan:
            continue
        if s.get("referrer") or s.get("user_agent"):
            continue
        u = usable(s.get("url"))
        if not u:
            continue
        lst = cands.setdefault(cid, [])
        if u not in lst and len(lst) < MAX_SRC:
            lst.append(u)

    # 并发探测所有候选源的存活性与 CORS
    uniq = []
    seen_u = set()
    for lst in cands.values():
        for u in lst:
            if u not in seen_u:
                seen_u.add(u)
                uniq.append(u)
    res = probe_all(uniq)
    alive_total = sum(1 for v in res.values() if v[0])
    if alive_total < MIN_ALIVE:
        raise SystemExit("Too few alive streams (%d) — probe env broken? aborting, keep old file."
                         % alive_total)

    out = []
    for cid, urls in cands.items():
        c = chan[cid]
        if c.get("is_nsfw"):
            continue
        if c.get("closed") or c.get("replaced_by"):
            continue
        cc = (c.get("country") or "").upper()
        pos = geocode(cc, c.get("subdivision"))
        if not pos:
            continue
        # 候选源排序：活且带 CORS（浏览器可直连）优先，其次活但无 CORS（走代理可用）；
        # 探不活的丢弃——仅华语区例外（境外探测不可信），保留原序垫底
        alive_cors = [u for u in urls if res.get(u) == (True, True)]
        alive_rest = [u for u in urls if res.get(u, (False, False))[0] and u not in alive_cors]
        ordered = alive_cors + alive_rest
        if not ordered:
            if cc in CN_KEEP:
                ordered = urls
            else:
                continue
        lat, lng = pos
        name = (c.get("name") or "").strip().replace("\n", " ")[:60]
        if not name:
            continue
        region = c.get("city") or (c.get("subdivision") or "")
        logo = c.get("logo") or ""
        if logo and not logo.startswith("https://"):
            logo = ""
        # [name, lat, lng, url, country_name, region, cc, logo, alts?]
        row = [name, round(lat, 4), round(lng, 4), ordered[0],
               cc_name.get(cc, cc), str(region)[:40], cc, logo]
        alts = ordered[1:1 + MAX_ALT]
        if alts:
            row.append(alts)
        out.append(row)

    if len(out) < 500:
        raise SystemExit("Too few channels (%d) — aborting, keep old file." % len(out))

    # iptv-org 结果：优先地区靠前，其余随后
    out.sort(key=lambda r: PRIORITY.get(r[6], 999))

    # 手工精选台（channels-fallback.json）：去重后**始终置顶合并**，保证 CGTN/凤凰/公视等一定在、一定靠前
    pinned = load_pinned()
    pinned_urls = {r[3] for r in pinned}
    out = pinned + [r for r in out if r[3] not in pinned_urls]

    # 按 CAP 截断（精选台在最前，绝不会被截掉）
    out = out[:CAP]

    os.makedirs("apps/tv", exist_ok=True)
    with open("apps/tv/channels.json", "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))

    asia = sum(1 for r in out if r[6] in PRIORITY)
    with_alt = sum(1 for r in out if len(r) > 8 and r[8])
    print(f"Wrote apps/tv/channels.json — {len(out)} channels "
          f"(pinned {len(pinned)}, Asia/华语区 {asia}, 带备用源 {with_alt}).")


if __name__ == "__main__":
    main()
