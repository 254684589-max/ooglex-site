#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""判断一个外部站点能否被正当接入：只读探测公开订阅口、robots 规则与条款位置。

用途是回答「能不能接、允不允许接」，不是把对方内容搬过来：

- 只请求固定的一小组元数据地址（首页、robots.txt、常见订阅路径、条款页）；
- 先读 robots.txt，被 Disallow 的路径一律跳过、不再请求；
- 使用如实标明来意的 User-Agent，不伪装浏览器；
- 只输出「有没有、在哪里、条款怎么写」，不保存对方正文，也不把正文写进仓库。

发现有公开订阅口时，接入方式仍限于标题、链接与时间，正文以对方页面为准。
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import time
from urllib import error, parse, request

USER_AGENT = ("OoglexFeedProbe/1.0 (+https://www.ooglex.com; "
              "read-only feed and terms discovery; contact via site)")
TIMEOUT = 15
REQUEST_GAP_SECONDS = 1.0          # 逐个请求之间留出间隔，不给对方造成压力
MAX_REQUESTS = 20                  # 硬上限：这是探测不是爬取
BODY_LIMIT = 200_000               # 只读取足够做判断的开头部分

FEED_PATHS = (
    "/rss", "/rss.xml", "/feed", "/feed.xml", "/atom.xml", "/index.xml",
    "/feeds/all.rss.xml", "/news/rss", "/rss/news", "/feed.json",
)
TERMS_PATHS = ("/terms", "/terms-of-service", "/tos", "/legal", "/about", "/privacy", "/api")
FEED_TYPES = ("application/rss+xml", "application/atom+xml", "application/feed+json", "application/json")


class Probe:
    """带请求预算的只读取数器；每次请求都记录结果，失败不抛出。"""

    def __init__(self, budget: int = MAX_REQUESTS) -> None:
        self.budget = budget
        self.log: list[dict] = []

    def get(self, url: str) -> dict:
        if self.budget <= 0:
            record = {"url": url, "status": None, "note": "已达请求上限，未发起"}
            self.log.append(record)
            return record
        self.budget -= 1
        req = request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "*/*"})
        record: dict = {"url": url}
        try:
            with request.urlopen(req, timeout=TIMEOUT) as response:
                body = response.read(BODY_LIMIT)
                record.update({
                    "status": response.status,
                    "finalUrl": response.geturl(),
                    "contentType": response.headers.get("Content-Type", ""),
                    "bytes": len(body),
                    "text": body.decode("utf-8", "replace"),
                })
        except error.HTTPError as err:
            record.update({"status": err.code, "note": f"HTTP {err.code}"})
        except Exception as err:                      # noqa: BLE001 - 探测失败只记录
            record.update({"status": None, "note": f"{type(err).__name__}: {err}"})
        self.log.append({k: v for k, v in record.items() if k != "text"})
        time.sleep(REQUEST_GAP_SECONDS)
        return record


def parse_robots(text: str) -> dict:
    """取 User-agent: * 段落的 Disallow/Allow 与全站 Sitemap 声明。"""
    disallow: list[str] = []
    allow: list[str] = []
    sitemaps: list[str] = []
    applies = False
    for raw in (text or "").splitlines():
        line = raw.split("#", 1)[0].strip()
        if not line or ":" not in line:
            continue
        field, _, value = line.partition(":")
        field, value = field.strip().lower(), value.strip()
        if field == "user-agent":
            applies = value == "*"
        elif field == "sitemap":
            sitemaps.append(value)
        elif applies and field == "disallow" and value:
            disallow.append(value)
        elif applies and field == "allow" and value:
            allow.append(value)
    return {"disallow": disallow, "allow": allow, "sitemaps": sitemaps}


def robots_blocks(path: str, rules: dict) -> bool:
    """粗判某路径是否被 robots 的通配段禁止；同长度下 Allow 优先。"""
    def match(patterns: list[str]) -> int:
        best = 0
        for pattern in patterns:
            prefix = pattern.rstrip("*")
            if prefix and path.startswith(prefix):
                best = max(best, len(prefix))
            elif pattern == "/":
                best = max(best, 1)
        return best
    return match(rules.get("disallow", [])) > match(rules.get("allow", []))


def discover_declared_feeds(html: str, base: str) -> list[dict]:
    """从 <head> 的 link rel=alternate 里读出站点自己声明的订阅口。"""
    found = []
    for tag in re.findall(r"<link\b[^>]*>", html or "", flags=re.I):
        attrs = dict(re.findall(r'(\w[\w-]*)\s*=\s*"([^"]*)"', tag))
        rel = (attrs.get("rel") or "").lower()
        kind = (attrs.get("type") or "").lower()
        href = attrs.get("href")
        if href and "alternate" in rel and any(kind.startswith(t) for t in FEED_TYPES):
            found.append({"type": kind, "title": attrs.get("title", ""),
                          "url": parse.urljoin(base, href)})
    return found


def find_api_hints(html: str) -> dict:
    """看首页外壳里有没有指向自身 API 或预渲染数据的线索。"""
    text = html or ""
    endpoints = sorted({m for m in re.findall(r'["\'](/(?:api|data|content)/[^"\'\s?]{2,80})["\']', text)})
    return {
        "endpoints": endpoints[:20],
        "nextData": "__NEXT_DATA__" in text,
        "nuxtData": "__NUXT__" in text,
        "jsonLd": 'application/ld+json' in text.lower(),
        "looksLikeShell": len(re.sub(r"<[^>]+>", "", text).split()) < 120,
    }


def probe_site(base: str, probe: Probe | None = None) -> dict:
    base = base.rstrip("/")
    probe = probe or Probe()
    report: dict = {"base": base, "userAgent": USER_AGENT, "requests": []}

    robots = probe.get(f"{base}/robots.txt")
    rules = parse_robots(robots.get("text", "")) if robots.get("status") == 200 else {}
    report["robots"] = {"status": robots.get("status"), **(rules or {})}

    home = probe.get(base + "/")
    report["home"] = {"status": home.get("status"), "contentType": home.get("contentType"),
                      "bytes": home.get("bytes")}
    html = home.get("text", "")
    report["declaredFeeds"] = discover_declared_feeds(html, base + "/")
    report["apiHints"] = find_api_hints(html)

    candidates = []
    for path in FEED_PATHS:
        if rules and robots_blocks(path, rules):
            candidates.append({"path": path, "status": "skipped", "note": "robots 禁止，未请求"})
            continue
        result = probe.get(base + path)
        body = result.get("text", "")
        is_feed = bool(re.search(r"<(rss|feed)\b", body, flags=re.I)) or (
            result.get("contentType", "").startswith("application/feed+json"))
        candidates.append({"path": path, "status": result.get("status"),
                           "contentType": result.get("contentType", ""),
                           "looksLikeFeed": is_feed})
    report["feedCandidates"] = candidates

    terms = []
    for path in TERMS_PATHS:
        if rules and robots_blocks(path, rules):
            terms.append({"path": path, "status": "skipped", "note": "robots 禁止，未请求"})
            continue
        result = probe.get(base + path)
        body = re.sub(r"<[^>]+>", " ", result.get("text", ""))
        keywords = sorted({word for word in
                           ("scrape", "scraping", "crawl", "republish", "redistribute",
                            "reproduce", "license", "commercial", "api", "rss", "feed")
                           if word in body.lower()})
        terms.append({"path": path, "status": result.get("status"), "keywords": keywords})
    report["termsPages"] = terms
    report["requests"] = probe.log
    report["verdict"] = summarize(report)
    return report


def summarize(report: dict) -> dict:
    """把探测结果压成一句可执行的结论，不替所有者做许可判断。"""
    declared = report.get("declaredFeeds") or []
    working = [c for c in report.get("feedCandidates", []) if c.get("looksLikeFeed")]
    robots_status = (report.get("robots") or {}).get("status")
    return {
        "hasDeclaredFeed": bool(declared),
        "hasReachableFeed": bool(working),
        "feedUrls": [f["url"] for f in declared] + [report["base"] + c["path"] for c in working],
        "robotsAvailable": robots_status == 200,
        "homeReachable": (report.get("home") or {}).get("status") == 200,
        "nextStep": ("有公开订阅口：可只取标题、链接与时间接入，正文仍以对方页面为准"
                     if (declared or working) else
                     "未发现公开订阅口：不要抓正文，改用自建风险页方案"),
    }


SELF_TEST_HOME = """
<html><head>
<link rel="alternate" type="application/rss+xml" title="Latest" href="/rss.xml">
<script id="__NEXT_DATA__" type="application/json">{"props":{}}</script>
</head><body><div id="root"></div><script src="/api/news/list.json"></script></body></html>
"""


def self_test() -> int:
    """离线自测：不联网，验证解析与判定逻辑。"""
    rules = parse_robots("User-agent: *\nDisallow: /api\nAllow: /api/public\nSitemap: https://x/y.xml\n")
    assert rules["disallow"] == ["/api"], rules
    assert rules["sitemaps"] == ["https://x/y.xml"], rules
    assert robots_blocks("/api/private", rules) is True
    assert robots_blocks("/api/public/list", rules) is False
    assert robots_blocks("/rss.xml", rules) is False
    assert robots_blocks("/x", parse_robots("User-agent: *\nDisallow: /\n")) is True
    assert robots_blocks("/x", parse_robots("User-agent: bot\nDisallow: /\n")) is False

    feeds = discover_declared_feeds(SELF_TEST_HOME, "https://example.com/")
    assert feeds == [{"type": "application/rss+xml", "title": "Latest",
                      "url": "https://example.com/rss.xml"}], feeds
    hints = find_api_hints(SELF_TEST_HOME)
    assert hints["nextData"] is True and hints["endpoints"] == ["/api/news/list.json"], hints
    assert hints["looksLikeShell"] is True

    verdict = summarize({"base": "https://example.com", "declaredFeeds": feeds,
                         "feedCandidates": [], "robots": {"status": 200},
                         "home": {"status": 200}})
    assert verdict["hasDeclaredFeed"] is True and "只取标题" in verdict["nextStep"]
    empty = summarize({"base": "https://example.com", "declaredFeeds": [],
                       "feedCandidates": [{"path": "/rss", "looksLikeFeed": False}],
                       "robots": {"status": 404}, "home": {"status": 200}})
    assert empty["hasReachableFeed"] is False and "自建" in empty["nextStep"]

    budget = Probe(budget=0).get("https://example.com/")
    assert budget["status"] is None and "上限" in budget["note"]
    print("probe_feed_availability self-test: PASS")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", help="站点根地址，例如 https://example.com")
    parser.add_argument("--json", action="store_true", help="输出机器可读结果")
    parser.add_argument("--self-test", action="store_true", help="离线自测，不联网")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    if not args.base:
        parser.error("需要 --base 或 --self-test")

    report = probe_site(args.base)
    if args.json:
        print(json.dumps(report, ensure_ascii=False, indent=2))
        return 0
    verdict = report["verdict"]
    print(f"探测目标：{report['base']}")
    print(f"robots.txt：{report['robots'].get('status')}"
          f" · Disallow {report['robots'].get('disallow') or '无'}"
          f" · Sitemap {report['robots'].get('sitemaps') or '无'}")
    print(f"首页：{report['home']['status']} · {report['home'].get('contentType')}"
          f" · {report['home'].get('bytes')} 字节"
          f" · 疑似空壳 {report['apiHints']['looksLikeShell']}")
    print(f"站点声明的订阅口：{report['declaredFeeds'] or '无'}")
    print(f"API 线索：{report['apiHints']['endpoints'] or '无'}"
          f" · __NEXT_DATA__ {report['apiHints']['nextData']}"
          f" · JSON-LD {report['apiHints']['jsonLd']}")
    print("常见订阅路径：")
    for item in report["feedCandidates"]:
        print(f"  {item['path']:<20} {item.get('status')} "
              f"{'FEED' if item.get('looksLikeFeed') else ''} {item.get('note', '')}")
    print("条款/说明页：")
    for item in report["termsPages"]:
        print(f"  {item['path']:<20} {item.get('status')} 关键词 {item.get('keywords') or '无'}")
    print(f"结论：{verdict['nextStep']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
