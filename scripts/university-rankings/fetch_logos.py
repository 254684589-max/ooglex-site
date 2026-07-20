#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把各大学 logo 下载到 apps/university-rankings/logos/，让页面同源加载（中国大陆无 VPN 也快），
不依赖境外图床实时请求。

在 GitHub Actions（境外机房）里跑：能访问 Google / DuckDuckGo favicon 服务与各校官网；
下载成功的存为 PNG 提交回仓库。已存在的文件跳过——故只有首次或新增学校时才真正下载。

域名映射取自 build_universities.py 的 UNIV_DOMAIN；文件名用 logo_slug(域名)，与 data.json 里
每所大学的 slug 字段一致，前端据此 `<img src="logos/<slug>.png">` 加载，失败回退首字牌。
"""
import os
import sys
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from build_universities import UNIV_DOMAIN, logo_slug  # noqa: E402

LOGO_DIR = os.path.join("apps", "university-rankings", "logos")
UA = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                    "(KHTML, like Gecko) Chrome/126.0 Safari/537.36"}
TIMEOUT = 10


def candidates(dom):
    # 多个独立图床/官网依次兜底（不同基础设施，避免单点限流）；均返回位图，前端统一白底显示。
    return [f"https://www.google.com/s2/favicons?sz=128&domain={dom}",
            f"https://icons.duckduckgo.com/ip3/{dom}.ico",
            f"https://icon.horse/icon/{dom}",
            f"https://{dom}/favicon.ico"]


def download(slug, urls):
    path = os.path.join(LOGO_DIR, slug + ".png")
    if os.path.exists(path) and os.path.getsize(path) > 200:
        return "skip"
    for url in urls:
        try:
            req = urllib.request.Request(url, headers=UA)
            with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
                ct = (r.headers.get("content-type") or "").lower()
                data = r.read()
            if ("image" in ct or "octet-stream" in ct) and len(data) > 200:
                with open(path, "wb") as f:
                    f.write(data)
                return "ok"
        except Exception:
            continue
    return "miss"


def main():
    os.makedirs(LOGO_DIR, exist_ok=True)
    seen, n_ok, n_skip, n_miss = set(), 0, 0, 0
    for dom in UNIV_DOMAIN.values():
        slug = logo_slug(dom)
        if slug in seen:
            continue
        seen.add(slug)
        res = download(slug, candidates(dom))
        n_ok += res == "ok"
        n_skip += res == "skip"
        n_miss += res == "miss"
        if res == "ok":
            time.sleep(0.05)
    print(f"logos：新下载 {n_ok}，已存在 {n_skip}，未取到 {n_miss}，目标 {len(seen)}")


if __name__ == "__main__":
    main()
