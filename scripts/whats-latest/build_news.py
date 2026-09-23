#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
构建「最新消息是什么？」资讯应用的数据：聚合全球主流新闻源（Google News RSS + 来源白名单，
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
import html
import os
import re
import sys
import time
from datetime import datetime, timezone
from urllib.parse import quote

import requests

SCRIPTS_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, SCRIPTS_DIR)
from supporting_source_health import (  # noqa: E402
    load_json as load_health_json,
    make_health,
    validate_health,
    write_health,
    write_json_atomic,
)

OUT_PATH = os.path.join("apps", "whats-latest", "data.json")
HEALTH_PATH = os.path.join("apps", "whats-latest", "health.json")
PER_CAT = 7
AI_CONFIG_PATH = os.path.join("apps", "ai-chat", "shared-config.json")
TRANSLATE_CHUNK = 12
CF_TRANSLATE_MODEL = "@cf/meta/m2m100-1.2b"

GN = "https://news.google.com/rss"
GN_TAIL = "hl=zh-CN&gl=US&ceid=US:zh-Hans"
UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/123.0 Safari/537.36")

# 板块：对齐 whatsthelatest.ai 的全球新闻范围，来源由主流媒体白名单控制。
CATS = [
    {"key": "politics", "name": "政策·政治",     "q": '"White House" OR Congress OR election OR policy OR regulation'},
    {"key": "world",    "name": "国际·地缘",     "q": 'geopolitics OR war OR Ukraine OR Iran OR "Middle East" OR Europe OR "United Nations"'},
    {"key": "markets",  "name": "市场·经济",     "q": 'markets OR economy OR stocks OR bonds OR Treasury OR oil OR inflation OR "Federal Reserve"'},
    {"key": "tech",     "name": "人工智能·科技", "q": '"artificial intelligence" OR AI OR Nvidia OR chips OR semiconductor OR "data center"'},
    {"key": "law",      "name": "法律·监管",     "q": 'court OR lawsuit OR sanctions OR regulator OR investigation OR antitrust'},
    {"key": "risk",     "name": "风险",          "q": '"geopolitical risk" OR "market risk" OR "credit risk" OR cyberattack OR "supply chain" OR disruption OR volatility OR default OR sanctions OR "energy security" OR "shipping disruption"'},
]

# Risk V2：风险页不再依赖一个宽泛查询，而是五路独立扫描。
RISK_STREAMS = [
    {"key": "geopolitics", "name": "地缘冲突", "q": '"military" OR missile OR drone OR ceasefire OR sanctions OR blockade OR "armed conflict" OR "Iran war" OR "Ukraine war"'},
    {"key": "market_credit", "name": "市场信用", "q": '"credit risk" OR "credit spread" OR bankruptcy OR "liquidity stress" OR "bank stress" OR "bond selloff" OR "debt default"'},
    {"key": "energy_shipping", "name": "能源运输", "q": '"oil supply" OR "energy security" OR tanker OR pipeline OR "shipping disruption" OR "freight disruption" OR "export route"'},
    {"key": "cyber", "name": "网络安全", "q": 'cyberattack OR ransomware OR hacking OR "data breach" OR malware OR "network attack" OR "security breach"'},
    {"key": "supply_chain", "name": "供应链", "q": '"supply chain" OR "port disruption" OR "logistics disruption" OR "trade route" OR "semiconductor shortage" OR bottleneck'},
]
RISK_MIN_ITEMS = 8
RISK_MIN_SOURCES = 3
RISK_MIN_STREAMS = 3
RISK_MAX_ITEMS = 15
RISK_PER_STREAM = 7

CATEGORY_COMPONENTS = {
    "politics": "politics-news",
    "world": "world-news",
    "markets": "markets-news",
    "tech": "tech-news",
    "law": "law-news",
    "risk": "risk-news",
}

# 新闻来源池：对齐 whatsthelatest.ai 当前简报中频繁出现的主流来源。
# 只过滤来源，不抓取或复制其站内内容；标题/摘要仍由 Google News RSS 提供并链接回原文。
SOURCE_POOL = [
    "Reuters",
    "Bloomberg",
    "Financial Times",
    "The Wall Street Journal",
    "BBC",
    "CNBC",
    "CNN",
    "NBC News",
    "CBS News",
    "ABC News",
    "The New York Times",
    "The Guardian",
    "South China Morning Post",
    "The Hill",
    "Fox News",
    "TechCrunch",
    "Semafor",
    "The Japan Times",
    "Axios",
    "WIRED",
    "Euronews",
    "Associated Press",
    "POLITICO",
    "Finextra",
]
SOURCE_ZH = {
    "Reuters": "路透社",
    "Bloomberg": "彭博社",
    "Financial Times": "英国《金融时报》",
    "The Wall Street Journal": "《华尔街日报》",
    "BBC": "英国广播公司",
    "CNBC": "美国消费者新闻与商业频道",
    "CNN": "美国有线电视新闻网",
    "NBC News": "美国全国广播公司新闻",
    "CBS News": "美国哥伦比亚广播公司新闻",
    "ABC News": "美国广播公司新闻",
    "The New York Times": "《纽约时报》",
    "The Guardian": "英国《卫报》",
    "South China Morning Post": "《南华早报》",
    "The Hill": "《国会山报》",
    "Fox News": "福克斯新闻",
    "TechCrunch": "科技博客",
    "Semafor": "塞马福新闻",
    "The Japan Times": "《日本时报》",
    "Axios": "阿克西奥斯新闻",
    "WIRED": "《连线》杂志",
    "Euronews": "欧洲新闻台",
    "Associated Press": "美联社",
    "POLITICO": "《政客》",
    "Finextra": "金融科技资讯网",
    "Ooglex rules": "Ooglex 规则",
}

SOURCE_ALIASES = {
    "reuters": "Reuters",
    "bloomberg": "Bloomberg",
    "financial times": "Financial Times",
    "wall street journal": "The Wall Street Journal",
    "wsj": "The Wall Street Journal",
    "bbc": "BBC",
    "cnbc": "CNBC",
    "cnn": "CNN",
    "nbc news": "NBC News",
    "cbs news": "CBS News",
    "abc news": "ABC News",
    "new york times": "The New York Times",
    "nytimes": "The New York Times",
    "guardian": "The Guardian",
    "south china morning post": "South China Morning Post",
    "scmp": "South China Morning Post",
    "the hill": "The Hill",
    "fox news": "Fox News",
    "techcrunch": "TechCrunch",
    "semafor": "Semafor",
    "japan times": "The Japan Times",
    "axios": "Axios",
    "wired": "WIRED",
    "euronews": "Euronews",
    "associated press": "Associated Press",
    "ap news": "Associated Press",
    "politico": "POLITICO",
    "finextra": "Finextra",
}


def canonical_source(src):
    s = re.sub(r"\\s+", " ", (src or "").strip())
    low = s.lower()
    for needle, canonical in SOURCE_ALIASES.items():
        if needle in low:
            return canonical
    return ""


def zh_source(src):
    return SOURCE_ZH.get(src, src or "其他新闻源")


def has_han(text):
    return bool(re.search(r"[\u3400-\u9fff]", text or ""))


def fallback_zh_title(item, category_name="新闻"):
    title = item.get("title") or ""
    if has_han(title):
        return title
    topic = item.get("topic") or category_name or "新闻"
    if not has_han(topic):
        topic = category_name if has_han(category_name) else "新闻"
    return f"{topic}：最新进展"


def fallback_zh_brief(item, category_name="新闻"):
    brief = item.get("brief") or ""
    if has_han(brief):
        return brief
    source = zh_source(item.get("source") or "")
    topic = item.get("topic") or category_name or "新闻"
    if not has_han(topic):
        topic = category_name if has_han(category_name) else "新闻"
    return f"{source}报道了{topic}相关最新进展；本站已链接原文，具体事实与细节以原报道为准。"


def google_gtx_translate_text(text):
    """Google Translate gtx 无密钥端点；仅翻译已有标题，不生成新事实。"""
    text = re.sub(r"\s+", " ", (text or "")).strip()
    if not text or has_han(text):
        return text
    try:
        resp = requests.get(
            "https://translate.googleapis.com/translate_a/single",
            params={
                "client": "gtx",
                "sl": "en",
                "tl": "zh-CN",
                "dt": "t",
                "q": text,
            },
            headers={"User-Agent": UA},
            timeout=15,
        )
        resp.raise_for_status()
        payload = resp.json()
        parts = payload[0] if isinstance(payload, list) and payload else []
        translated = "".join(
            str(part[0] or "")
            for part in parts
            if isinstance(part, list) and part
        ).strip()
        return translated if has_han(translated) else ""
    except Exception as exc:
        print(f"[translate-gtx] 单条失败：{str(exc)[:140]}")
        return ""


def cloudflare_translate_text(text):
    """Cloudflare Workers AI 备用翻译；密钥仅从 GitHub Actions Secret 读取。"""
    text = re.sub(r"\s+", " ", (text or "")).strip()
    if not text or has_han(text):
        return text

    token = (os.getenv("CLOUDFLARE_API_TOKEN") or "").strip()
    account_id = (os.getenv("CLOUDFLARE_ACCOUNT_ID") or "").strip()
    if not token or not account_id:
        return ""

    url = (
        f"https://api.cloudflare.com/client/v4/accounts/{account_id}/ai/run/"
        f"{CF_TRANSLATE_MODEL}"
    )
    try:
        resp = requests.post(
            url,
            headers={
                "Authorization": f"Bearer {token}",
                "Content-Type": "application/json",
                "User-Agent": UA,
            },
            json={
                "text": text,
                "source_lang": "en",
                "target_lang": "zh",
            },
            timeout=20,
        )
        resp.raise_for_status()
        payload = resp.json()
        result = payload.get("result") or {}
        translated = str(
            result.get("translated_text")
            or result.get("translation")
            or ""
        ).strip()
        return translated if has_han(translated) else ""
    except Exception as exc:
        print(f"[translate-cf] 单条失败：{str(exc)[:140]}")
        return ""


def apply_chinese_translation(cats_out):
    """统一生成中文标题、中文新闻源和中文简报；翻译失败时不回退显示英文。"""
    refs = []
    for category in cats_out:
        category_name = category.get("name") or "新闻"
        for item in category.get("items") or []:
            item["sourceZh"] = item.get("sourceZh") or zh_source(item.get("source") or "")
            item["titleZh"] = (
                item.get("titleZh")
                if has_han(item.get("titleZh"))
                else fallback_zh_title(item, category_name)
            )
            item["briefZh"] = (
                item.get("briefZh")
                if has_han(item.get("briefZh"))
                else fallback_zh_brief(item, category_name)
            )
            item["whyZh"] = (
                item.get("whyZh")
                or item.get("why")
                or "请结合原文与后续报道持续核验。"
            )
            refs.append((category_name, item))

    if not refs:
        return

    applied = 0
    failed = 0
    for category_name, item in refs:
        original_title = item.get("title") or ""
        if has_han(original_title):
            item["titleZh"] = original_title
            if not has_han(item.get("briefZh")):
                item["briefZh"] = original_title
            continue

        title_zh = google_gtx_translate_text(original_title)
        if not title_zh:
            title_zh = cloudflare_translate_text(original_title)
        if title_zh:
            item["titleZh"] = title_zh
            source_zh = item.get("sourceZh") or zh_source(item.get("source") or "")
            item["briefZh"] = (
                f"{title_zh}。新闻源：{source_zh}。"
                "本站保留原文链接，更多事实与细节请查看原报道。"
            )
            applied += 1
            time.sleep(0.28)
        else:
            failed += 1
            item["titleZh"] = fallback_zh_title(item, category_name)
            item["briefZh"] = fallback_zh_brief(item, category_name)

    print(f"[translate] 中文标题 {applied} 条；兜底 {failed} 条")


# 全局内容过滤：该专栏不收录中国相关报道。
# 仅检查新闻标题和 RSS 摘要，不检查媒体名称，因此不会因为来源名含 China
# （例如 South China Morning Post）而误删其非中国题材报道。
CHINA_RELATED_RE = re.compile(
    r"\\bChina\\b|\\bChinese\\b|\\bPRC\\b|People['’]s Republic of China|"
    r"\\bBeijing\\b|\\bShanghai\\b|\\bShenzhen\\b|\\bGuangzhou\\b|"
    r"\\bHong Kong\\b|\\bMacau\\b|\\bMacao\\b|\\bCCP\\b|"
    r"Chinese Communist Party|Communist Party of China|Xi Jinping|"
    r"People['’]s Liberation Army|\\bPLA\\b|People['’]s Bank of China|\\bPBOC\\b|"
    r"\\byuan\\b|\\brenminbi\\b|South China Sea|Taiwan Strait|"
    r"\\bAlibaba\\b|\\bTencent\\b|\\bHuawei\\b|\\bByteDance\\b|\\bTikTok\\b|"
    r"\\bDeepSeek\\b|\\bBYD\\b|\\bBaidu\\b|\\bXiaomi\\b|\\bJD\\.com\\b",
    re.I,
)


def is_china_related(item):
    text = f"{item.get('title') or ''} {item.get('summary') or ''}"
    return bool(CHINA_RELATED_RE.search(text))


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


def query_url(q):
    return f"{GN}/search?q={quote(q)}&{GN_TAIL}"


TOPIC_RULES = [
    (r"标普500|S&P ?500", "标普500"),
    (r"纳斯达克|Nasdaq", "纳斯达克"),
    (r"美联储|Fed", "美联储"),
    (r"国债|收益率", "债券市场"),
    (r"布伦特|WTI|原油|油价", "原油"),
    (r"黄金|金价", "黄金"),
    (r"人工智能|\\bAI\\b|OpenAI", "人工智能"),
    (r"芯片|半导体|GPU|英伟达|NVIDIA", "芯片 / 半导体"),
    (r"数据中心|云计算", "AI 基础设施"),
    (r"电影|影视", "影视"),
    (r"音乐|演唱会", "音乐"),
    (r"网球", "网球"),
    (r"足球|世界杯", "足球"),
    (r"篮球|NBA", "篮球"),
    (r"乌克兰|俄乌", "俄乌"),
    (r"中东|伊朗|以色列|霍尔木兹", "中东"),
    (r"欧洲|欧盟", "欧洲"),
]


def clean_feed_summary(e, title, source):
    """优先读取 RSS 自带摘要；若只是重复标题/来源则丢弃。"""
    raw = e.get("summary") or e.get("description") or ""
    if not raw:
        return ""
    text = html.unescape(re.sub(r"<[^>]+>", " ", str(raw)))
    text = re.sub(r"\\s+", " ", text).strip()
    if not text:
        return ""
    for part in (title, source):
        if part:
            text = text.replace(part, " ")
    text = re.sub(r"\\s+", " ", text).strip(" -·|")
    if len(text) < 20:
        return ""
    return text[:180].rstrip("，,;； ") + ("。" if text[-1:] not in "。！？!?" else "")


def topic_from_title(title, category_name=""):
    text = (title or "").strip()
    for pattern, label in TOPIC_RULES:
        if re.search(pattern, text, re.I):
            return label
    for sep in ("丨", "｜", "：", ":"):
        if sep in text:
            left = text.split(sep, 1)[0].strip()
            if 2 <= len(left) <= 16:
                return left
    if "？" in text:
        left = text.split("？", 1)[0].strip()
        if 4 <= len(left) <= 18:
            return left + "？"
    return category_name or "简报"


def make_brief(title, category_name="", summary=""):
    """生成一到两句编辑部式简报；只使用 RSS 标题/摘要里已有的信息。"""
    text = re.sub(r"\\s+", " ", (summary or title or "").strip())
    topic = topic_from_title(title, category_name)
    if not text:
        return topic, ""
    # 若没有可用 RSS 摘要，直接把标题整理成完整陈述，避免凭空补事实。
    if not summary:
        for sep in ("丨", "｜"):
            if sep in text:
                text = text.split(sep, 1)[1].strip()
                break
    text = re.sub(r"[！!]{2,}", "！", text)
    if len(text) > 150:
        text = text[:147].rstrip("，,;； ") + "…"
    if text[-1:] not in "。！？!?…":
        text += "。"
    return topic, text


def why_it_matters(title, category_key):
    t = title or ""
    if re.search(r"美联储|利率|加息|降息|国债|收益率", t):
        return "这可能影响利率预期、融资成本与风险资产估值。"
    if re.search(r"布伦特|WTI|原油|油价|能源", t):
        return "这可能影响能源成本、通胀预期与市场风险偏好。"
    if re.search(r"标普500|纳斯达克|美股|股市", t):
        return "这可能改变风险偏好、估值预期与资金流向。"
    if re.search(r"人工智能|\\bAI\\b|芯片|半导体|OpenAI|英伟达", t, re.I):
        return "这关系到算力供给、技术竞争与 AI 资本开支节奏。"
    if re.search(r"战争|冲突|中东|乌克兰|俄乌|制裁|霍尔木兹", t):
        return "这可能改变地缘风险、能源或贸易链条，并影响市场定价。"
    if category_key == "risk":
        return "这类事件可能放大波动、信用、能源、供应链或运营风险，需要关注后续传导。"
    return "这条信息可能影响该领域后续预期与市场关注重点。"


def importance_score(it, category_key):
    score = float(it.get("published") or 0)
    boosts = {"risk": 7, "world": 6, "markets": 5, "politics": 4, "tech": 4, "law": 3}
    score += boosts.get(category_key, 0) * 3600
    t = it.get("title") or ""
    if re.search(r"战争|冲突|制裁|美联储|利率|标普500|纳斯达克|原油|芯片|人工智能|\\bAI\\b", t, re.I):
        score += 4 * 3600
    return score


RISK_DIMENSIONS = [
    ("地缘政治", r"\b(?:war|conflict|attack|strike|missile|invasion|sanctions?|blockade|ceasefire|drone|military|troops?)\b|Iran|Israel|Ukraine|Russia|North Korea|Middle East|Hormuz"),
    ("市场 / 信用", r"\b(?:credit|default|bankruptcy|liquidity|selloff|debt|bond|loan|spread)\b|bank stress|credit spread"),
    ("能源 / 运输", r"\b(?:oil|gas|energy|pipeline|tanker|shipping|freight|port|vessel|LNG|OPEC)\b|export route"),
    ("网络安全", r"\b(?:cyber|cyberattack|ransomware|hack|hacker|malware)\b|data breach|network attack|security breach"),
    ("供应链", r"supply chain|\b(?:shortage|bottleneck|logistics)\b|port disruption|trade route|semiconductor shortage"),
]


def build_risk_analysis(cats_out, markets, risk_meta=None):
    risk_cat = next((c for c in cats_out if c.get("key") == "risk"), {"items": []})
    items = list(risk_cat.get("items") or [])
    risk_meta = risk_meta or {}
    text = " ".join((it.get("title") or "") + " " + (it.get("summary") or "") for it in items)

    sources = sorted({it.get("source") for it in items if it.get("source")})
    streams = sorted({it.get("riskStream") for it in items if it.get("riskStream")})
    sample_count = len(items)
    reliable = (
        sample_count >= RISK_MIN_ITEMS
        and len(sources) >= RISK_MIN_SOURCES
        and len(streams) >= RISK_MIN_STREAMS
    )

    high_re = re.compile(r"\b(?:attack|strike|missile|invasion|war|cyberattack|ransomware|default|blockade|explosion|shutdown)\b", re.I)
    elevated_re = re.compile(r"\b(?:sanctions?|disruption|crisis|volatility|liquidity|shortage|outage|threat|tension|bottleneck)\b|credit risk|supply chain|energy security", re.I)
    high_hits = len(high_re.findall(text))
    elevated_hits = len(elevated_re.findall(text))

    market_stress = 0
    for m in markets or []:
        pct = m.get("changePct")
        if pct is None:
            continue
        if m.get("name") in ("标普500", "纳斯达克") and pct <= -2:
            market_stress += 1
        if m.get("name") in ("布伦特原油", "WTI原油") and abs(pct) >= 4:
            market_stress += 1

    if not reliable:
        level, status = "数据不足", f"等待更多样本（{sample_count}/{RISK_MIN_ITEMS}）"
    elif high_hits >= 4 or (high_hits >= 2 and market_stress):
        level, status = "高", "升级"
    elif high_hits >= 2 or elevated_hits >= 6 or market_stress >= 2:
        level, status = "中高", "活跃"
    elif elevated_hits >= 2 or market_stress:
        level, status = "中", "持续监测"
    else:
        level, status = "低", "平稳"

    dims = []
    for name, pattern in RISK_DIMENSIONS:
        count = len(re.findall(pattern, text, re.I))
        raw_score = min(100, 20 + count * 12) if count else 10
        if not reliable:
            state = "样本不足"
        else:
            state = "高" if raw_score >= 80 else ("中高" if raw_score >= 60 else ("中" if raw_score >= 35 else "低"))
        dims.append({"name": name, "score": raw_score, "state": state, "matches": count})

    lead = max(items, key=risk_event_score) if items else None
    follow = []
    future_re = re.compile(r"will|could|may|plan|expected|next|meeting|decision|sanction|deadline|election", re.I)
    for it in sorted(items, key=risk_event_score, reverse=True):
        if future_re.search(it.get("title") or ""):
            follow.append({
                "text": it.get("briefZh") or it.get("brief") or it.get("title") or "",
                "source": it.get("source") or "",
            })
        if len(follow) >= 4:
            break
    if not follow:
        follow = [
            {"text": "监测现有事件是否出现升级、扩散或跨市场传导。", "source": "Ooglex rules"},
            {"text": "关注能源、信用利差、主要股指与关键基础设施是否出现同步压力。", "source": "Ooglex rules"},
        ]

    coverage = {
        "sampleCount": sample_count,
        "sourceCount": len(sources),
        "streamCount": len(streams),
        "sources": sources,
        "streams": streams,
        "minItems": RISK_MIN_ITEMS,
        "minSources": RISK_MIN_SOURCES,
        "minStreams": RISK_MIN_STREAMS,
        "reliable": reliable,
        "streamCounts": risk_meta.get("streamCounts", {}),
        "candidateCount": risk_meta.get("candidateCount", sample_count),
    }

    return {
        "version": "2.0",
        "level": level,
        "status": status,
        "reliable": reliable,
        "lead": lead,
        "why": (lead or {}).get("why") if lead else "",
        "dimensions": dims,
        "followUp": follow,
        "coverage": coverage,
        "method": "rule-based-multistream",
    }

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
    summary = clean_feed_summary(e, title, src)
    return {"title": title, "source": src, "link": e.get("link", ""), "published": pub, "summary": summary}


def fetch_feed(url, n=PER_CAT):
    import feedparser
    fp = feedparser.parse(url, agent=UA)
    out = []
    for e in fp.entries[:n * 20]:
        it = parse_entry(e)
        if not (it["title"] and it["link"]):
            continue
        canonical = canonical_source(it.get("source") or "")
        if not canonical:
            continue
        if is_china_related(it):
            continue
        it["source"] = canonical
        it["sourceZh"] = zh_source(canonical)
        out.append(it)
        if len(out) >= n:
            break
    return out


RISK_STREAM_FILTERS = {
    "market_credit": re.compile(r"\b(?:credit|bond|debt|loan|liquidity|bankruptcy|bank|spread)\b|credit risk|debt default|bank stress", re.I),
    "energy_shipping": re.compile(r"\b(?:oil|gas|energy|pipeline|tanker|shipping|freight|vessel|LNG|OPEC)\b|export route|shipping disruption", re.I),
    "cyber": re.compile(r"\b(?:cyber|cyberattack|ransomware|hack|hacker|malware)\b|data breach|network attack|security breach", re.I),
    "supply_chain": re.compile(r"supply chain|\b(?:shortage|bottleneck|logistics)\b|port disruption|trade route|semiconductor shortage", re.I),
}
GEO_EVENT_RE = re.compile(r"\b(?:war|conflict|attack|strike|missile|invasion|sanctions?|blockade|ceasefire|drone|military|troops?)\b", re.I)
GEO_CONTEXT_RE = re.compile(r"\b(?:Iran|Israel|Ukraine|Russia|NATO|North Korea|Yemen|Syria|Lebanon|Saudi|Gulf|Hormuz|military|army|navy|troops?)\b|United Nations", re.I)


def risk_stream_relevant(item, stream_key):
    text = f"{item.get('title') or ''} {item.get('summary') or ''}"
    if stream_key == "geopolitics":
        return bool(GEO_EVENT_RE.search(text) and GEO_CONTEXT_RE.search(text))
    pattern = RISK_STREAM_FILTERS.get(stream_key)
    if not pattern or not pattern.search(text):
        return False
    if stream_key == "market_credit" and re.search(r"default judgment", text, re.I):
        if not re.search(r"\b(?:debt|bond|loan|credit|bankruptcy|liquidity)\b", text, re.I):
            return False
    return True


def risk_event_score(item):
    """风险事件排序：事件强度优先，其次时效；不用于预测，只用于版面排序。"""
    text = f"{item.get('title') or ''} {item.get('summary') or ''}"
    score = float(item.get("published") or 0) / 3600
    severe = re.compile(r"\b(?:attack|strike|missile|invasion|war|cyberattack|ransomware|default|bankruptcy|blockade|explosion|shutdown)\b", re.I)
    elevated = re.compile(r"\b(?:sanctions?|disruption|crisis|volatility|liquidity|shortage|outage|threat|tension|bottleneck)\b", re.I)
    score += len(severe.findall(text)) * 30
    score += len(elevated.findall(text)) * 12
    return score


def risk_brief_zh(item):
    """风险页中文简报按已验证的风险流生成；英文原标题保留供原文核验。"""
    stream = item.get("riskStreamName") or "风险"
    templates = {
        "地缘冲突": "出现地缘或军事风险信号，需关注事件是否升级、扩散并传导至能源、运输与市场风险偏好。",
        "市场信用": "信用、债务或流动性风险受到关注，需观察是否向银行、债券或融资市场进一步传导。",
        "能源运输": "能源或运输链条出现风险信号，需关注供应、运价、出口通道与通胀预期变化。",
        "网络安全": "网络攻击、勒索软件或数据安全风险受到关注，需观察关键系统、数据与基础设施影响。",
        "供应链": "供应链或物流瓶颈受到关注，需观察成本、交付周期与跨行业传导。",
    }
    return f"{stream}：{templates.get(stream, '该报道涉及潜在风险事件，需结合原文与后续发展持续核验。')}"



def fetch_risk_v2():
    """五路独立扫描 + 严格相关性过滤 + 风险流均衡取样。"""
    candidates = []
    stream_counts = {}
    errors = []
    for stream in RISK_STREAMS:
        got = 0
        try:
            for it in fetch_feed(query_url(stream["q"]), n=RISK_PER_STREAM * 2):
                if not risk_stream_relevant(it, stream["key"]):
                    continue
                it = dict(it)
                it["riskStream"] = stream["key"]
                it["riskStreamName"] = stream["name"]
                topic, brief = make_brief(it["title"], "风险", it.get("summary") or "")
                it["topic"] = stream["name"]
                it["brief"] = brief
                it["briefZh"] = risk_brief_zh(it)
                it["why"] = why_it_matters(it["title"], "risk")
                it["categoryKey"] = "risk"
                it["titleZh"] = fallback_zh_title(it, "风险")
                it["sourceZh"] = zh_source(it.get("source") or "")
                it["whyZh"] = it["why"]
                candidates.append(it)
                got += 1
                if got >= RISK_PER_STREAM:
                    break
        except Exception as exc:
            errors.append(f"{stream['key']}:{str(exc)[:80]}")
        stream_counts[stream["key"]] = got
        time.sleep(0.25)

    candidates.sort(key=risk_event_score, reverse=True)
    deduped = []
    sigs_local = []
    for it in candidates:
        sig = title_sig(it["title"])
        if any(len(sig & old) / max(1, min(len(sig), len(old))) >= 0.5 for old in sigs_local):
            continue
        deduped.append(it)
        sigs_local.append(sig)

    chosen = []
    chosen_links = set()
    per_source = {}
    for stream in RISK_STREAMS:
        for it in [x for x in deduped if x.get("riskStream") == stream["key"]]:
            src = it.get("source") or ""
            if per_source.get(src, 0) >= 3:
                continue
            chosen.append(it)
            chosen_links.add(it.get("link"))
            per_source[src] = per_source.get(src, 0) + 1
            break

    for it in deduped:
        if len(chosen) >= RISK_MAX_ITEMS:
            break
        if it.get("link") in chosen_links:
            continue
        src = it.get("source") or ""
        if per_source.get(src, 0) >= 3:
            continue
        chosen.append(it)
        chosen_links.add(it.get("link"))
        per_source[src] = per_source.get(src, 0) + 1

    chosen.sort(key=risk_event_score, reverse=True)
    return chosen[:RISK_MAX_ITEMS], {
        "streamCounts": stream_counts,
        "errors": errors,
        "candidateCount": len(candidates),
        "dedupedCount": len(deduped),
    }



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


def utc_now():
    return datetime.now(timezone.utc)


def previous_categories(prev_file):
    if not isinstance(prev_file, dict) or not isinstance(prev_file.get("categories"), list):
        return {}
    return {
        category.get("key"): category
        for category in prev_file["categories"]
        if isinstance(category, dict) and category.get("key") in CATEGORY_COMPONENTS
        and isinstance(category.get("items"), list) and category["items"]
    }


def title_sig(title):
    """标题的 4-gram 指纹，用于识别不同来源的同一条新闻（近重复）。"""
    t = re.sub(r"[^\w]", "", title)
    return {t[i:i + 4] for i in range(max(1, len(t) - 3))}


def build():
    prev_file = load_prev()
    prev_health = load_health_json(HEALTH_PATH)
    previous = previous_categories(prev_file)
    now = utc_now()
    attempted_at = now.strftime("%Y-%m-%dT%H:%M:%SZ")
    seen, sigs, cats_out, total = set(), [], [], 0
    modes = {}
    fresh_categories = 0
    risk_meta = {}
    for c in CATS:
        items = []
        try:
            if c["key"] == "risk":
                items, risk_meta = fetch_risk_v2()
            else:
                for it in fetch_feed(cat_url(c)):
                    if it["link"] in seen:
                        continue
                    s = title_sig(it["title"])
                    if any(len(s & k) / max(1, min(len(s), len(k))) >= 0.5 for k in sigs):
                        continue   # 同一事件多家媒体报道，只保留一条
                    seen.add(it["link"]); sigs.append(s)
                    topic, brief = make_brief(it["title"], c["name"], it.get("summary") or "")
                    it["topic"] = topic
                    it["brief"] = brief
                    it["why"] = why_it_matters(it["title"], c["key"])
                    it["categoryKey"] = c["key"]
                    it["titleZh"] = fallback_zh_title(it, c["name"])
                    it["briefZh"] = fallback_zh_brief(it, c["name"])
                    it["whyZh"] = it["why"]
                    items.append(it)
        except Exception as e:
            print(f"[..] 板块 {c['name']} 抓取失败：{str(e)[:60]}")
        if items:
            cats_out.append({"key": c["key"], "name": c["name"], "items": items})
            total += len(items)
            fresh_categories += 1
            modes[CATEGORY_COMPONENTS[c["key"]]] = "fresh"
            print(f"[OK] {c['name']}：{len(items)} 条")
        elif c["key"] in previous:
            fallback = previous[c["key"]]
            fallback_items = [it for it in fallback["items"] if not is_china_related(it)]
            if fallback_items:
                cats_out.append({
                    "key": c["key"],
                    "name": fallback.get("name") or c["name"],
                    "items": fallback_items,
                })
                total += len(fallback_items)
                modes[CATEGORY_COMPONENTS[c["key"]]] = "fallback"
                print(f"[fallback] {c['name']}：沿用 {len(fallback_items)} 条旧新闻（已应用中国相关内容过滤）")
            else:
                modes[CATEGORY_COMPONENTS[c["key"]]] = "unavailable"
        else:
            modes[CATEGORY_COMPONENTS[c["key"]]] = "unavailable"
        time.sleep(0.3)

    apply_chinese_translation(cats_out)

    if fresh_categories == 0:
        modes["market-quotes"] = "fallback" if prev_file and prev_file.get("markets") else "unavailable"
        print("本轮没有新闻板块成功刷新，保留上次 data.json，不覆盖。")
        if prev_file:
            health = make_health(
                "whats-latest",
                data=prev_file,
                attempted_at=attempted_at,
                component_modes=modes,
                published=False,
                previous_health=prev_health,
                failure_reason="Google News六个板块均未刷新",
            )
            validate_health("whats-latest", prev_file, health)
            write_health(HEALTH_PATH, health)
        return False

    markets = []
    for m in MARKETS:
        price, pct = fetch_quote(m["sym"])
        if price is not None:
            markets.append({"name": m["name"], "symbol": m["sym"],
                            "price": price, "changePct": pct, "fmt": m["fmt"]})
        time.sleep(0.25)
    if markets:
        modes["market-quotes"] = "fresh"
    elif prev_file and isinstance(prev_file.get("markets"), list) and prev_file["markets"]:
        markets = list(prev_file["markets"])
        modes["market-quotes"] = "fallback"
    else:
        modes["market-quotes"] = "unavailable"

    highlight = None
    lead = None
    pool = [(it, c["name"], c["key"]) for c in cats_out for it in c["items"]]
    if pool:
        top, cat_name, cat_key = max(pool, key=lambda x: importance_score(x[0], x[2]))
        lead = {**top, "category": cat_name, "why": why_it_matters(top.get("title", ""), cat_key)}
        highlight = lead

    # 图二式「今日概述」：各取市场 / AI科技 / 国际最新一条，只使用标题已有事实。
    overview = []
    for key in ("risk", "politics", "world", "markets", "tech"):
        category = next((x for x in cats_out if x.get("key") == key and x.get("items")), None)
        if category:
            it = max(category["items"], key=lambda x: x.get("published") or 0)
            overview.append({
                "topic": category["name"],
                "text": it.get("briefZh") or it.get("titleZh") or "",
                "source": it.get("source") or "",
                "sourceZh": it.get("sourceZh") or zh_source(it.get("source") or ""),
            })

    # 主题 / 市场方向标签。新闻类标签表示当日出现的主题，市场类箭头直接来自行情涨跌。
    all_titles = " ".join(
        it.get("title", "")
        for category in cats_out
        for it in category.get("items", [])
    )
    signals = []
    signal_rules = [
        ("地缘政治", r"war|conflict|Iran|Israel|Ukraine|Russia|sanction|Middle East|Hormuz"),
        ("AI / 芯片", r"artificial intelligence|\\bAI\\b|chip|Nvidia|OpenAI|semiconductor"),
        ("利率 / 债券", r"Federal Reserve|Fed|interest rate|Treasury|yield|inflation"),
    ]
    for label, pattern in signal_rules:
        if re.search(pattern, all_titles, re.I):
            signals.append({"label": label, "trend": "关注"})

    market_map = {m.get("name"): m for m in markets}
    for names, label in [
        (("布伦特原油", "WTI原油"), "原油"),
        (("标普500", "纳斯达克"), "美股"),
        (("黄金",), "黄金"),
    ]:
        vals = [
            market_map[n].get("changePct")
            for n in names if n in market_map and market_map[n].get("changePct") is not None
        ]
        if vals:
            avg = sum(vals) / len(vals)
            signals.append({"label": label, "trend": "↑" if avg > 0 else ("↓" if avg < 0 else "→")})

    # 快讯：按时效 + 重要性选 6 条，尽量避免同一主题重复。
    ranked = sorted(
        [
            {**it, "category": c["name"], "categoryKey": c["key"]}
            for c in cats_out
            for it in c.get("items", [])
        ],
        key=lambda x: importance_score(x, x.get("categoryKey", "")),
        reverse=True,
    )
    wires, used_topics, used_links = [], set(), set()
    for it in ranked:
        if len(wires) >= 6:
            break
        topic = it.get("topic") or it.get("category") or "快讯"
        if topic in used_topics and len(used_topics) < 5:
            continue
        wires.append(it)
        used_topics.add(topic)
        used_links.add(it.get("link"))

    also_noted = [it for it in ranked if it.get("link") not in used_links][:3]
    future_re = re.compile(r"将|计划|预计|拟|即将|明日|下周|发布|公布|举行|会议|财报|决议")
    watch = [it for it in ranked if future_re.search(it.get("title") or "")][:3]

    risk_analysis = build_risk_analysis(cats_out, markets, risk_meta)

    data = {
        "updatedAt": attempted_at,
        "asOf": now.strftime("%Y-%m-%d"),
        "source": "Google News (curated global publishers) · Yahoo Finance",
        "sourcePool": SOURCE_POOL,
        "contentPolicy": "exclude-china-related-news",
        "lead": lead,
        "highlight": highlight,
        "overview": overview,
        "signals": signals,
        "wires": wires,
        "alsoNoted": also_noted,
        "watch": watch,
        "riskAnalysis": risk_analysis,
        "categories": cats_out,
        "markets": markets,
        "note": ("新闻通过 Google News RSS 聚合，并只保留本站配置的全球主流媒体来源池；"
                 "本专栏全局排除中国相关报道。页面统一以中文展示；新闻标题与摘要由 RSS 中文源优先，并通过 Ooglex 共享 AI 通道做忠实中文翻译，"
                 "翻译失败时使用中文兜底说明。每条均链接回原文核实。风险页采用五路独立扫描，并在样本、来源和风险维度达到最低覆盖前显示‘数据不足’。"
                 "市场快照来自雅虎财经。仅供参考。"),
    }
    health = make_health(
        "whats-latest",
        data=data,
        attempted_at=attempted_at,
        component_modes=modes,
        published=True,
        previous_health=prev_health,
    )
    validate_health("whats-latest", data, health)
    write_json_atomic(OUT_PATH, data)
    write_health(HEALTH_PATH, health)
    print(f"写入 {OUT_PATH}：{total} 条新闻 / {len(cats_out)} 板块 / {len(markets)} 个行情")
    return True


if __name__ == "__main__":
    build()
