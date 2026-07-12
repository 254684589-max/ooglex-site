#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
构建「全球电影榜」数据：从 TMDB（The Movie Database）公开 API 取「高分电影 Top 250」与「全球最新上映」，
含中文片名、海报、评分，写入 apps/movies/data.json。

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
                 "与全球最新上映，含海报与中文片名，每日自动更新。"
                 "（IMDb 官方禁止服务器抓取，故采用 TMDB。）评分为 TMDB 用户评分，仅供参考。"),
    }
    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    with open(OUT_PATH, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print(f"写入 {OUT_PATH}：{len(lists)} 个榜单，Top 平均分 {avg}")


if __name__ == "__main__":
    build()
