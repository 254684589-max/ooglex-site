#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
把各公司 logo 下载到 apps/companies/logos/ 本地目录，让页面同源加载（中国大陆无 VPN 也快），
不再依赖 Clearbit / Google / FMP 等境外图床（这些在墙内慢或被封）。

在 GitHub Actions（境外机房）里跑：能访问这些图床；下载成功的存为 PNG 并提交回仓库。
已存在的文件跳过——故只有首次或新增公司时才真正下载，日常几乎零开销。

key 规则：有官网域名的用域名（logos/<domain>.png）；其余上市公司用代码（logos/sym_<SYMBOL>.png）。
build_companies.py 据此把命中的本地路径写进 data.json 的 logo 字段。
"""
import os
import sys
import time

import requests

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from maps import ZH_OVERLAY, PRIVATE  # noqa: E402
import json  # noqa: E402

LOGO_DIR = os.path.join("apps", "companies", "logos")
UA = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/124.0 Safari/537.36"}


def candidates_for_domain(dom):
    # 多个独立图床依次兜底（不同基础设施，避免单点被限流/下线）：
    return [f"https://www.google.com/s2/favicons?sz=128&domain={dom}",
            f"https://icons.duckduckgo.com/ip3/{dom}.ico",
            f"https://icon.horse/icon/{dom}",
            f"https://logo.clearbit.com/{dom}",
            f"https://{dom}/favicon.ico"]


def fmp_image(sym):
    return [f"https://financialmodelingprep.com/image-stock/{sym}.png"]


def collect_targets():
    """返回 {key: [候选url...]}。key 即本地文件名（不含扩展名）。"""
    targets = {}
    try:
        universe = json.load(open(os.path.join(HERE, "universe.json")))
    except Exception:
        universe = []
    for u in universe:
        sym = u.get("symbol")
        dom = ZH_OVERLAY.get(sym, (None, None))[1]
        if dom:  # 有官网域名：先试各图床，最后用 FMP 个股图兜底（上市公司多有）
            targets[dom] = candidates_for_domain(dom) + (fmp_image(sym) if sym and sym != "—" else [])
        elif sym and sym != "—":
            targets["sym_" + sym] = fmp_image(sym)
    for p in PRIVATE:
        if p.get("domain"):
            targets[p["domain"]] = candidates_for_domain(p["domain"])
    return targets


def looks_like_image(r):
    ct = (r.headers.get("content-type") or "").lower()
    return r.status_code == 200 and ("image" in ct or "octet-stream" in ct) and len(r.content) > 200


def download(key, urls):
    path = os.path.join(LOGO_DIR, key.replace("/", "_") + ".png")
    if os.path.exists(path) and os.path.getsize(path) > 200:
        return "skip"
    for url in urls:
        try:
            r = requests.get(url, headers=UA, timeout=8)
            if looks_like_image(r):
                with open(path, "wb") as f:
                    f.write(r.content)
                return "ok"
        except Exception:
            continue
    return "miss"


def main():
    os.makedirs(LOGO_DIR, exist_ok=True)
    targets = collect_targets()
    n_ok = n_skip = n_miss = 0
    for key, urls in targets.items():
        res = download(key, urls)
        n_ok += res == "ok"
        n_skip += res == "skip"
        n_miss += res == "miss"
        if res == "ok":
            time.sleep(0.05)
    print(f"logos：新下载 {n_ok}，已存在 {n_skip}，未取到 {n_miss}，目标 {len(targets)}")


if __name__ == "__main__":
    main()
