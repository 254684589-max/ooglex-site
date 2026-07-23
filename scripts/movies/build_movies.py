#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
构建「全球电影榜」数据：从 TMDB（The Movie Database）公开 API 取「高分电影 Top 250」与「全球最新上映」，
含中文片名、海报、评分，写入 apps/movies/data.json。

站内播放（全部走合法渠道，不碰任何盗版片源）：
- 每部片额外取 TMDB 详情（append_to_response=videos,watch/providers），把官方预告片的 YouTube key
  与正版观看渠道（TMDB × JustWatch，取 HK/TW/US 三地）写进 data.json，前端点海报弹窗即播；
- 另建「公版经典」榜单：美国公有领域电影，正片由 Internet Archive 官方 embed 提供，
  构建时逐条校验条目可播（metadata API），失效则按片名搜索高下载量替代条目，找不到就剔除。

高分榜排序：从 TMDB top_rated 取候选池，按 IMDb 同款「贝叶斯加权评分」排序——
  WR = v/(v+m)·R + m/(v+m)·C   （R=该片均分，v=票数，m=票数基准，C=候选池平均分）
于是「经典优先」：高分且票数多的经典片排在前面，挡掉刚上映、票数极少却虚高的新片。

为什么用 TMDB：IMDb 官方禁止服务器抓取（实测对机房 IP 返回空页，连免密钥代理也取不到），
而 TMDB 提供稳定的官方 API（含海报、中文本地化、最新上映），是从 GitHub Actions 可靠取数的正路。

需要一个免费的 TMDB API Key，放在 GitHub Secret `TMDB_KEY` 里（themoviedb.org 注册即可免费申请）。
未配置 key 时本脚本不动数据（保留上次 data.json）。失败同样保留上次数据，绝不用空数据覆盖。
由 .github/workflows/movies.yml 每日定时运行。
"""
import json
import os
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone

import requests

OUT_PATH = os.path.join("apps", "movies", "data.json")
TMDB_KEY = os.environ.get("TMDB_KEY", "").strip()
API = "https://api.themoviedb.org/3"
IMG = "https://image.tmdb.org/t/p/w342"      # 海报尺寸（浏览器直接从 TMDB 图床加载）
HEADERS = {"User-Agent": "personal-site-movies/1.0"}

MIN_VOTES = 3000      # 贝叶斯加权的票数基准 m（IMDb Top 250 同款公式）
FLOOR_VOTES = 1000    # 入选最低票数：挡掉刚上映、票数极少却虚高的新片
POOL_PAGES = 40       # 高分候选池页数（每页 20 → 约 800 部，加权后取前 250）

WATCH_REGIONS = ["HK", "TW", "US"]   # JustWatch 无中国大陆数据，取就近华语区 + 美国

# 公版经典：均为美国公有领域影片，ia 为 Internet Archive 条目标识。
# 构建时逐条校验，标识失效会按片名搜索高下载量条目自动替换（见 classics_list）。
CLASSICS = [
    {"title": "月球旅行记",         "orig": "A Trip to the Moon",          "year": "1902", "ia": "Levoyagedanslalune"},
    {"title": "卡里加里博士的小屋", "orig": "The Cabinet of Dr. Caligari", "year": "1920", "ia": "TheCabinetOfDrCaligari"},
    {"title": "诺斯费拉图",         "orig": "Nosferatu",                   "year": "1922", "ia": "Nosferatu_1922"},
    {"title": "战舰波将金号",       "orig": "Battleship Potemkin",         "year": "1925", "ia": "BattleshipPotemkin"},
    {"title": "淘金记",             "orig": "The Gold Rush",               "year": "1925", "ia": "TheGoldRush_1925"},
    {"title": "将军号",             "orig": "The General",                 "year": "1926", "ia": "TheGeneral"},
    {"title": "大都会",             "orig": "Metropolis",                  "year": "1927", "ia": "Metropolis_1927"},
    {"title": "圣女贞德蒙难记",     "orig": "The Passion of Joan of Arc",  "year": "1928", "ia": "ThePassionOfJoanOfArc"},
    {"title": "女友礼拜五",         "orig": "His Girl Friday",             "year": "1940", "ia": "his_girl_friday"},
    {"title": "绕道",               "orig": "Detour",                      "year": "1945", "ia": "Detour"},
    {"title": "外太空九号计划",     "orig": "Plan 9 from Outer Space",     "year": "1959", "ia": "Plan_9_from_Outer_Space_1959"},
    {"title": "恐怖小店",           "orig": "The Little Shop of Horrors",  "year": "1960", "ia": "the_little_shop_of_horrors"},
    {"title": "惊魂夜",             "orig": "Carnival of Souls",           "year": "1962", "ia": "carnival_of_souls"},
    {"title": "谜中谜",             "orig": "Charade",                     "year": "1963", "ia": "Charade_1963"},
    {"title": "活死人之夜",         "orig": "Night of the Living Dead",    "year": "1968", "ia": "night_of_the_living_dead"},
]


def tmdb(path, **params):
    params["api_key"] = TMDB_KEY
    params.setdefault("language", "zh-CN")
    r = requests.get(API + path, params=params, headers=HEADERS, timeout=20)
    r.raise_for_status()
    return r.json()


def fetch_pages(path, pages, **extra):
    """翻页抓取一个 TMDB 列表的原始结果，最多 pages 页。"""
    out, page = [], 1
    while page <= pages:
        p = {"page": page}
        p.update(extra)
        js = tmdb(path, **p)
        res = js.get("results") or []
        out.extend(res)
        if not res or page >= (js.get("total_pages") or 1):
            break
        page += 1
        time.sleep(0.15)
    return out


def to_item(m, rank):
    """把 TMDB 影片对象转成前端用的结构。"""
    pp = m.get("poster_path")
    mid = m.get("id")
    va = m.get("vote_average")
    return {
        "rank": rank,
        "title": m.get("title") or m.get("original_title") or "",
        "orig": m.get("original_title"),
        "year": (m.get("release_date") or "")[:4] or None,
        "rating": round(float(va), 1) if va else None,
        "votes": m.get("vote_count"),
        "poster": (IMG + pp) if pp else None,
        "id": mid,
        "link": ("https://www.themoviedb.org/movie/%s" % mid) if mid else None,
    }


def top_rated_weighted(n):
    """高分电影 Top n：贝叶斯加权排序，经典（高分 + 高票）优先。"""
    pool, seen = [], set()
    for m in fetch_pages("/movie/top_rated", POOL_PAGES):
        mid = m.get("id")
        v = m.get("vote_count") or 0
        r = m.get("vote_average")
        if not mid or mid in seen or not r or v < FLOOR_VOTES:
            continue
        seen.add(mid)
        pool.append(m)
    if not pool:
        return []
    C = sum((m.get("vote_average") or 0) for m in pool) / len(pool)   # 候选池平均分

    def wr(m):
        v = m.get("vote_count") or 0
        r = m.get("vote_average") or 0
        return (v / (v + MIN_VOTES)) * r + (MIN_VOTES / (v + MIN_VOTES)) * C

    pool.sort(key=wr, reverse=True)
    return [to_item(m, i + 1) for i, m in enumerate(pool[:n])]


def pick_trailer(videos):
    """从 TMDB videos 里挑一支最合适的 YouTube 预告片：正式预告 > 先导，官方优先，中文加分。"""
    best, score = None, -1
    for v in videos or []:
        if v.get("site") != "YouTube" or not v.get("key"):
            continue
        s = {"Trailer": 4, "Teaser": 2}.get(v.get("type"), 0)
        if v.get("official"):
            s += 2
        if (v.get("iso_639_1") or "") == "zh":
            s += 1
        if s > score:
            best, score = v["key"], s
    return best


def pick_watch(results):
    """整理正版观看渠道（TMDB × JustWatch）：按地区聚合平台名，订阅 > 免费 > 租售。"""
    out = []
    for r in WATCH_REGIONS:
        d = (results or {}).get(r) or {}
        names = []
        for k in ("flatrate", "free", "ads", "rent", "buy"):
            for p in d.get(k) or []:
                n = p.get("provider_name")
                if n and n not in names:
                    names.append(n)
        if names:
            out.append({"region": r, "names": names[:6], "link": d.get("link")})
    return out


def enrich_play(items):
    """为每部片补预告片 YouTube key 与正版观看渠道；单片失败只影响自己。"""
    def one(it):
        if not it.get("id"):
            return
        try:
            js = tmdb("/movie/%s" % it["id"],
                      append_to_response="videos,watch/providers",
                      include_video_language="zh,en,null")
            t = pick_trailer((js.get("videos") or {}).get("results"))
            if t:
                it["trailer"] = t
            w = pick_watch((js.get("watch/providers") or {}).get("results"))
            if w:
                it["watch"] = w
        except Exception as e:
            print("[..] 详情失败 #%s：%s" % (it.get("id"), str(e)[:60]))
    with ThreadPoolExecutor(max_workers=8) as ex:
        list(ex.map(one, items))


def ia_get(path, **params):
    r = requests.get("https://archive.org" + path, params=params, headers=HEADERS, timeout=25)
    r.raise_for_status()
    return r.json()


def ia_playable(identifier):
    """Internet Archive 条目存在、未下架且带视频文件才算可播。"""
    try:
        js = ia_get("/metadata/%s" % identifier)
    except Exception:
        return False
    if not isinstance(js, dict) or not js.get("metadata") or js.get("is_dark"):
        return False
    return any(str(f.get("name", "")).lower().endswith((".mp4", ".m4v", ".ogv"))
               for f in js.get("files") or [])


def ia_find(orig):
    """按片名搜 Internet Archive 影片区，下载量最高且可播的条目优先。"""
    try:
        js = ia_get("/advancedsearch.php",
                    q='title:"%s" AND mediatype:movies' % orig,
                    **{"fl[]": "identifier", "sort[]": "downloads desc",
                       "rows": 5, "output": "json"})
        docs = (js.get("response") or {}).get("docs") or []
    except Exception:
        return None
    for d in docs:
        ident = d.get("identifier")
        if ident and ia_playable(ident):
            return ident
    return None


def classics_list():
    """公版经典榜单：校验 / 搜寻 Internet Archive 片源，并用 TMDB 补中文片名、海报与评分。"""
    items = []
    for c in CLASSICS:
        ident = c["ia"] if ia_playable(c["ia"]) else ia_find(c["orig"])
        if not ident:
            print("[..] 公版片源未找到，剔除：%s" % c["orig"])
            continue
        if ident != c["ia"]:
            print("[..] 公版片源改用搜索结果：%s → %s" % (c["ia"], ident))
        it = {
            "rank": len(items) + 1,
            "title": c["title"], "orig": c["orig"], "year": c["year"],
            "rating": None, "votes": None,
            "poster": "https://archive.org/services/img/%s" % ident,
            "id": None,
            "link": "https://archive.org/details/%s" % ident,
            "video": ident,
        }
        try:
            res = tmdb("/search/movie", query=c["orig"], year=c["year"]).get("results") or []
            m = res[0] if res else None
            y = (m.get("release_date") or "")[:4] if m else ""
            if m and y.isdigit() and abs(int(y) - int(c["year"])) <= 1:
                it["title"] = m.get("title") or it["title"]
                if m.get("poster_path"):
                    it["poster"] = IMG + m["poster_path"]
                va = m.get("vote_average")
                it["rating"] = round(float(va), 1) if va else None
                it["votes"] = m.get("vote_count")
                it["id"] = m.get("id")
        except Exception as e:
            print("[..] TMDB 检索失败 %s：%s" % (c["orig"], str(e)[:60]))
        items.append(it)
        time.sleep(0.1)
    return items


def collect(path, n, region=None):
    """按 TMDB 原始顺序取前 n 部（用于「最新上映」）。"""
    extra = {"region": region} if region else {}
    out = []
    for m in fetch_pages(path, n // 20 + 2, **extra):
        out.append(to_item(m, len(out) + 1))
        if len(out) >= n:
            break
    return out


def build():
    if not TMDB_KEY:
        print("未配置 TMDB_KEY —— 跳过、保留上次 data.json。"
              "请在仓库 Settings → Secrets and variables → Actions 新增名为 TMDB_KEY 的密钥后即自动生效。")
        return

    lists = []
    try:
        top = top_rated_weighted(250)
        if top:
            lists.append({"key": "top", "name": "高分电影 Top 250", "items": top})
            print(f"[OK] 高分 Top 250：{len(top)} 部，#1 {top[0]['title']} ★{top[0]['rating']}")
    except Exception as e:
        print(f"[..] top_rated 失败：{str(e)[:90]}")
    try:
        now = collect("/movie/now_playing", 60, region="US")
        if now:
            lists.append({"key": "popular", "name": "全球最新上映", "items": now})
            print(f"[OK] 最新上映：{len(now)} 部")
    except Exception as e:
        print(f"[..] now_playing 失败：{str(e)[:90]}")

    if not lists:
        print("TMDB 未取到数据（请检查 TMDB_KEY 是否有效），保留上次 data.json，不覆盖。")
        return

    for l in lists:
        enrich_play(l["items"])
        got = sum(1 for it in l["items"] if it.get("trailer"))
        print(f"[OK] {l['name']}：预告片 {got}/{len(l['items'])}")
    try:
        classics = classics_list()
        if classics:
            lists.append({"key": "classics", "name": "公版经典 · 免费正片", "items": classics})
            print(f"[OK] 公版经典：{len(classics)}/{len(CLASSICS)} 部")
    except Exception as e:
        print(f"[..] 公版经典构建失败：{str(e)[:90]}")

    top = next((l for l in lists if l["key"] == "top"), None)
    rates = [it["rating"] for it in (top["items"] if top else []) if isinstance(it.get("rating"), (int, float))]
    avg = round(sum(rates) / len(rates), 1) if rates else None

    data = {
        "updatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "asOf": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
        "source": "TMDB · The Movie Database",
        "avgRating": avg,
        "defaultKey": "top",
        "lists": lists,
        "note": ("数据来自 TMDB（The Movie Database）公开 API：高分电影 Top 250（按票数加权排序、经典优先）"
                 "与全球最新上映，含海报与中文片名，每日自动更新。点击海报可在线看官方预告片（YouTube），"
                 "「公版经典」为美国公有领域影片、正片由 Internet Archive 提供；观看渠道数据来自 TMDB × JustWatch。"
                 "评分为 TMDB 用户评分，仅供参考。"),
    }
    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    with open(OUT_PATH, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print(f"写入 {OUT_PATH}：{len(lists)} 个榜单，Top 平均分 {avg}")


if __name__ == "__main__":
    build()
