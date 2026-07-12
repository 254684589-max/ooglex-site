#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
构建「最新消息是什么？」资讯应用的数据：聚合权威公开新闻源（Google News 中文 RSS，
逐条链接回原文）按板块归类，并附一条实时市场快照（Yahoo Finance），写入
apps/whats-latest/data.json，供静态页面渲染。

设计要点（沿用仓库 market-bot 的取数风格）：
- 真实/权威：标题与来源均来自 Google News 聚合的权威媒体，每条都链接回原文，绝不编造；
- 中文原生：Google News RSS 用 hl=zh-CN 直接返回中文标题，无需翻译；
- 零密钥：Google News RSS + Yahoo 图表接口都免登录；纯 requests/feedparser + 硬超时；
- 稳健：单源失败不影响整体；整体无所得则保留上次 data.json 不覆盖。
由 .github/workflows/whats_latest.yml 定时运行（每数小时一次），并把 data.json 提交回仓库。
"""
import json
import os
import re
import time
from datetime import datetime, timezone
from urllib.parse import quote

import requests

OUT_PATH = os.path.join("apps", "whats-latest", "data.json")
PER_CAT = 7

GN = "https://news.google.com/rss"
GN_TAIL = "hl=zh-CN&gl=CN&ceid=CN:zh"
UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/123.0 Safari/537.36")

# 板块：key / 名称 / Google News 查询。聚焦 市场·科技·娱乐·体育·国际，去掉「中国」与政治头条总览。
CATS = [
    {"key": "markets", "name": "市场",        "q": "财经 OR 股市 OR 美联储 OR 美股 OR 央行 OR 国债 OR 经济"},
    {"key": "tech",    "name": "人工智能·科技", "q": "人工智能 OR AI OR 芯片 OR OpenAI OR 半导体 OR 科技"},
    {"key": "ent",     "name": "娱乐",        "q": "娱乐 OR 明星 OR 影视 OR 电影 OR 综艺 OR 音乐 OR 演唱会"},
    {"key": "sports",  "name": "体育",        "q": "体育 OR 足球 OR 篮球 OR NBA OR 网球 OR 奥运 OR 世界杯"},
    {"key": "world",   "name": "国际",        "q": "国际 OR 全球 OR 海外 OR 中东 OR 欧洲 OR 联合国 OR 太空 OR 灾害"},
]

# 政治说教/党政类过滤：标题命中即剔除（领导人、党建、官场、外事会见、两会等），让信息流远离硬政治。
POLITICS_RE = re.compile(
    "习近平|李强|赵乐际|王沪宁|蔡奇|丁薛祥|李希|韩正|何立峰|王毅|李克强|刘国中|胡锦涛|"
    "党中央|总书记|政治局|常委会|从严治党|党建|党委|党组|党支部|纪委|监委|巡视|反腐|统战|"
    "宣传部|组织部|人大|政协|学习贯彻|重要讲话|重要指示|主旨讲话|党的二十|两会|意识形态|"
    "换届|代表大会|书记|干部|主席团|亲切会见|应约|会见|会谈|国事访问|莅临|座谈会|"
    "动员大会|外长|双边会"
)

# 官方/政务来源过滤：来自政府或党务网站的通稿基本是政治内容，按来源剔除。
SOURCE_BLOCK = re.compile(r"政府|gov\.|idcpc|mfa\.|customs|外交部|中联部|发改委|人大|政协|党校")

# 市场快照（Yahoo 代码）：名称 / 代码 / 计价格式
MARKETS = [
    {"name": "标普500",    "sym": "^GSPC",    "fmt": "idx"},
    {"name": "纳斯达克",    "sym": "^IXIC",    "fmt": "idx"},
    {"name": "布伦特原油",  "sym": "BZ=F",     "fmt": "usd"},
    {"name": "WTI原油",    "sym": "CL=F",     "fmt": "usd"},
    {"name": "黄金",       "sym": "GC=F",     "fmt": "usd"},
    {"name": "美元指数",    "sym": "DX-Y.NYB", "fmt": "idx"},
]

YF_HOSTS = ["query1.finance.yahoo.com", "query2.finance.yahoo.com"]


def cat_url(c):
    if c["q"]:
        return f"{GN}/search?q={quote(c['q'])}&{GN_TAIL}"
    return f"{GN}?{GN_TAIL}"


def parse_entry(e):
    """从 RSS 条目提取 {title, source, link, published}；Google News 标题形如『标题 - 来源』。"""
    title = (e.get("title") or "").strip()
    src = ""
    s = e.get("source")
    if isinstance(s, dict):
        src = (s.get("title") or "").strip()
    # Google News 标题恒为「标题 - 来源」，去掉结尾来源段（避免与来源字段重复）
    if " - " in title:
        head, tail = title.rsplit(" - ", 1)
        head = head.strip()
        if head:
            if not src:
                src = tail.strip()
            title = head
    ts = e.get("published_parsed") or e.get("updated_parsed")
    pub = int(time.mktime(ts)) if ts else None
    return {"title": title, "source": src, "link": e.get("link", ""), "published": pub}


def fetch_feed(url, n=PER_CAT):
    import feedparser
    fp = feedparser.parse(url, agent=UA)
    out = []
    for e in fp.entries[:n * 4]:
        it = parse_entry(e)
        if not (it["title"] and it["link"]):
            continue
        if POLITICS_RE.search(it["title"]) or SOURCE_BLOCK.search(it.get("source") or ""):
            continue
        out.append(it)
        if len(out) >= n:
            break
    return out


def fetch_quote(sym):
    """Yahoo 图表接口：返回 (最新价, 日涨跌幅%)；失败返回 (None, None)。"""
    headers = {"User-Agent": UA}
    for host in YF_HOSTS:
        url = f"https://{host}/v8/finance/chart/{quote(sym)}?range=5d&interval=1d"
        try:
            r = requests.get(url, headers=headers, timeout=12)
            r.raise_for_status()
            res = r.json()["chart"]["result"][0]
            cl = [c for c in res["indicators"]["quote"][0]["close"] if c is not None]
            if len(cl) >= 2:
                price, prev = cl[-1], cl[-2]
                return round(price, 2), round((price / prev - 1) * 100, 2)
        except Exception:
            continue
    return None, None


def load_prev():
    try:
        with open(OUT_PATH, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None


def title_sig(title):
    """标题的 4-gram 指纹，用于识别不同来源的同一条新闻（近重复）。"""
    t = re.sub(r"[^\w]", "", title)
    return {t[i:i + 4] for i in range(max(1, len(t) - 3))}


def build():
    prev_file = load_prev()
    seen, sigs, cats_out, total = set(), [], [], 0
    for c in CATS:
        items = []
        try:
            for it in fetch_feed(cat_url(c)):
                if it["link"] in seen:
                    continue
                s = title_sig(it["title"])
                if any(len(s & k) / max(1, min(len(s), len(k))) >= 0.5 for k in sigs):
                    continue   # 同一事件多家媒体报道，只保留一条
                seen.add(it["link"]); sigs.append(s)
                items.append(it)
        except Exception as e:
            print(f"[..] 板块 {c['name']} 抓取失败：{str(e)[:60]}")
        if items:
            cats_out.append({"key": c["key"], "name": c["name"], "items": items})
            total += len(items)
            print(f"[OK] {c['name']}：{len(items)} 条")
        time.sleep(0.3)

    if total == 0:
        print("本轮 0 条新闻，保留上次 data.json，不覆盖。")
        return

    markets = []
    for m in MARKETS:
        price, pct = fetch_quote(m["sym"])
        if price is not None:
            markets.append({"name": m["name"], "symbol": m["sym"],
                            "price": price, "changePct": pct, "fmt": m["fmt"]})
        time.sleep(0.25)

    highlight = None
    pool = [(it, c["name"]) for c in cats_out for it in c["items"]]
    if pool:
        top, cat_name = max(pool, key=lambda x: x[0].get("published") or 0)
        highlight = {**top, "category": cat_name}

    data = {
        "updatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "asOf": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
        "source": "Google News · Yahoo Finance",
        "highlight": highlight,
        "categories": cats_out,
        "markets": markets,
        "note": ("新闻聚合自 Google News 收录的权威媒体，每条均链接回原文，仅作信息聚合，不代表本站观点；"
                 "市场快照来自 Yahoo Finance。仅供参考。"),
    }
    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    with open(OUT_PATH, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print(f"写入 {OUT_PATH}：{total} 条新闻 / {len(cats_out)} 板块 / {len(markets)} 个行情")


if __name__ == "__main__":
    build()
