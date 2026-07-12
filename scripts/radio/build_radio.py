#!/usr/bin/env python3
# 生成「环球电波」电台库：从 Radio Browser 抓取全球 + 中国及周边的 HTTPS 直连电台，
# 写入 apps/radio/stations.json（同源托管，规避国内直连外网 API 不稳的问题）。
# 在 GitHub Actions 上运行（GitHub 服务器可正常访问该 API）。仅用标准库，无需密钥。
import json, os, ssl, random, urllib.request

MIRRORS = [
    "https://de1.api.radio-browser.info",
    "https://nl1.api.radio-browser.info",
    "https://at1.api.radio-browser.info",
    "https://fi1.api.radio-browser.info",
]
CTX = ssl.create_default_context()
CAP = 6000  # 最多收录电台数（兼顾移动端性能）

# 中国各省/直辖市/地区 → 省会大致坐标（含威妥玛旧拼法，Radio Browser 的 state 字段常见）
CN_PROV = {
    "beijing": (39.90, 116.40), "peking": (39.90, 116.40),
    "shanghai": (31.23, 121.47), "tianjin": (39.13, 117.20), "tientsin": (39.13, 117.20),
    "chongqing": (29.56, 106.55), "chungking": (29.56, 106.55),
    "guangdong": (23.13, 113.26), "kwangtung": (23.13, 113.26),
    "zhejiang": (30.27, 120.15), "chekiang": (30.27, 120.15),
    "jiangsu": (32.06, 118.80), "kiangsu": (32.06, 118.80),
    "shandong": (36.65, 117.02), "shantung": (36.65, 117.02),
    "sichuan": (30.57, 104.07), "szechwan": (30.57, 104.07),
    "hubei": (30.59, 114.30), "hupeh": (30.59, 114.30),
    "hunan": (28.23, 112.94),
    "fujian": (26.07, 119.30), "fukien": (26.07, 119.30),
    "yunnan": (25.04, 102.71),
    "henan": (34.76, 113.65), "honan": (34.76, 113.65),
    "hebei": (38.04, 114.51), "hopeh": (38.04, 114.51),
    "shaanxi": (34.34, 108.94), "shensi": (34.34, 108.94),
    "shanxi": (37.87, 112.55), "shansi": (37.87, 112.55),
    "liaoning": (41.80, 123.43),
    "jilin": (43.90, 125.33), "kirin": (43.90, 125.33),
    "heilongjiang": (45.80, 126.53), "heilungkiang": (45.80, 126.53),
    "anhui": (31.86, 117.28), "anhwei": (31.86, 117.28),
    "jiangxi": (28.68, 115.86), "kiangsi": (28.68, 115.86),
    "guangxi": (22.82, 108.32), "kwangsi": (22.82, 108.32),
    "guizhou": (26.65, 106.63), "kweichow": (26.65, 106.63),
    "gansu": (36.06, 103.83), "kansu": (36.06, 103.83),
    "hainan": (20.02, 110.35),
    "inner mongolia": (40.84, 111.75), "nei mongol": (40.84, 111.75), "mongolia": (40.84, 111.75),
    "xinjiang": (43.83, 87.62), "sinkiang": (43.83, 87.62),
    "tibet": (29.65, 91.14), "xizang": (29.65, 91.14),
    "ningxia": (38.47, 106.28), "ningsia": (38.47, 106.28),
    "qinghai": (36.62, 101.78), "tsinghai": (36.62, 101.78),
    "hong kong": (22.32, 114.17), "hongkong": (22.32, 114.17),
    "macau": (22.20, 113.55), "macao": (22.20, 113.55),
    "taiwan": (25.03, 121.57),
}
# 部分周边国家/地区首都坐标（无经纬度时兜底放置）
CC_CENTER = {
    "CN": (34.0, 108.0), "HK": (22.32, 114.17), "MO": (22.20, 113.55), "TW": (25.03, 121.57),
    "JP": (35.68, 139.69), "KR": (37.57, 126.98), "SG": (1.35, 103.82), "MY": (3.14, 101.69),
    "TH": (13.75, 100.52), "VN": (21.03, 105.85), "PH": (14.60, 120.98), "ID": (-6.21, 106.85),
    "IN": (28.61, 77.21),
}

def geocode(s):
    """返回 (lat,lng)：优先用真实经纬度；中国等无坐标电台按省份/国家兜底放置。"""
    try:
        lat = float(s.get("geo_lat")); lng = float(s.get("geo_long"))
        if -90 <= lat <= 90 and -180 <= lng <= 180 and not (lat == 0 and lng == 0):
            return lat, lng
    except (TypeError, ValueError):
        pass
    cc = (s.get("countrycode") or "").upper()
    st = (s.get("state") or "").strip().lower()
    if cc == "CN" and st:
        for name, (la, lo) in CN_PROV.items():
            if name in st:
                return la + random.uniform(-0.25, 0.25), lo + random.uniform(-0.25, 0.25)
    if cc in CC_CENTER:
        la, lo = CC_CENTER[cc]
        return la + random.uniform(-0.35, 0.35), lo + random.uniform(-0.35, 0.35)
    return None

def fetch(path):
    servers = MIRRORS[:]
    random.shuffle(servers)
    for m in servers:
        try:
            req = urllib.request.Request(m + path, headers={"User-Agent": "OoglexRadio/1.0 (+https://ooglex.com)"})
            with urllib.request.urlopen(req, timeout=40, context=CTX) as r:
                return json.load(r)
        except Exception as e:
            print("  mirror failed:", m, "-", e)
    return None

def row(s):
    u = (s.get("url_resolved") or s.get("url") or "").strip()
    if not u.startswith("https://"):
        return None
    if ".m3u8" in u.lower():
        return None
    pos = geocode(s)
    if not pos:
        return None
    lat, lng = pos
    name = (s.get("name") or "").strip().replace("\n", " ")[:60]
    if not name:
        return None
    # [name, lat, lng, url, country, state, countrycode]
    return [name, round(lat, 4), round(lng, 4), u,
            (s.get("country") or "")[:40], (s.get("state") or "")[:40], (s.get("countrycode") or "")]

seen = set()
out = []
def add(rows, label=""):
    n0 = len(out)
    for s in rows or []:
        r = row(s)
        if r and r[3] not in seen:
            seen.add(r[3]); out.append(r)
    print(f"  + {label}: +{len(out)-n0} (total {len(out)})")

print("Fetching China …")
add(fetch("/json/stations/bycountrycodeexact/CN?hidebroken=true&limit=4000"), "CN")

print("Fetching nearby Asia …")
for cc in ["HK", "TW", "MO", "JP", "KR", "SG", "MY", "TH", "VN", "PH", "ID", "IN"]:
    add(fetch(f"/json/stations/bycountrycodeexact/{cc}?hidebroken=true&limit=500"), cc)

print("Fetching global popular …")
add(fetch("/json/stations/search?hidebroken=true&has_geo_info=true&order=clickcount&reverse=true&limit=5000"), "global")

if len(out) < 50:
    raise SystemExit("Too few stations fetched (%d) — aborting, keep old file." % len(out))

out = out[:CAP]
os.makedirs("apps/radio", exist_ok=True)
with open("apps/radio/stations.json", "w", encoding="utf-8") as f:
    json.dump(out, f, ensure_ascii=False, separators=(",", ":"))

cn = sum(1 for r in out if r[6] == "CN")
print(f"Wrote apps/radio/stations.json — {len(out)} stations (China {cn}).")
