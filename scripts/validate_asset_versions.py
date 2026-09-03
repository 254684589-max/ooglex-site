#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""校验站内页面的静态资源引用带版本号，且哈希版本号与文件内容一致。

## 这个校验器存在的理由：一次真实的线上事故

2026-09-03，用户在手机上打开苹果的公司页，看到的是

    「本页已收录 20245 条有出处的关系」

而苹果的真实条数是 **0**。

根因不是数据错了，是**浏览器缓存了旧版 company.js**：`nodes.json` 用
`cache: "no-cache"` 拉取，每次都是新的；而 `<script src="company.js">` 没有版本号，
浏览器照旧用缓存。于是**新数据 + 旧代码**——旧代码读的是全局 `coverage.edgesTotal`
（全站 20245 条），不是这家公司的边数。数据全对、代码全对，合在一起却对一家真实
公司说了假话。

排查时发现这不是一处的问题：`apps/` 下当时有 **43 处**本地 js/css 引用没有版本号，
散在三十多个 app 里。每个 app 都是「data.json 每次拉新 + JS 可能是旧的」这个结构，
同一类事故随时可能在别处重演。

## 两条规则

1. **必须有版本号**（全站硬性）。没有就等于把「新数据配旧代码」这个组合一直敞着。
2. **哈希版本号必须与文件内容一致**（只管 8 位十六进制那种）。
   `company.js?v=<sha256 前 8 位>`——改了文件哈希就变，忘不了；没改就不变，
   不会制造无谓的缓存失效。

仓库原有的 `?v=3`、`?v=13` 是手工递增的：规则 1 管得住，规则 2 不动它们——
替换别人的约定不是这次该做的事。新补的一律用哈希，因为手工递增本身就是会忘的，
今天忘的就是它。

`--stamp` 给缺版本号的引用补上哈希，并校正已有的哈希版本号。纯离线。
"""
from __future__ import annotations

import hashlib
import os
import re
import sys

ROOT_DIRS = ("apps",)
# 只管与 HTML 同目录的资源；跨目录引用（/assets/...）匹配不到就是不管，
# 不假装管住了。
LOCAL_REF = re.compile(
    r'(?P<attr>src|href)="(?P<file>[A-Za-z0-9._-]+\.(?:js|css))(?:\?v=(?P<ver>[^"]*))?"')
VERSION_LEN = 8
HASH_VERSION = re.compile(r"^[0-9a-f]{8}$")


def content_version(path: str) -> str:
    with open(path, "rb") as handle:
        return hashlib.sha256(handle.read()).hexdigest()[:VERSION_LEN]


def html_files() -> list[str]:
    found = []
    for root_dir in ROOT_DIRS:
        for root, _, files in os.walk(root_dir):
            found += [os.path.join(root, f) for f in files if f.endswith(".html")]
    return sorted(found)


def scan(stamp: bool) -> int:
    problems: list[str] = []
    checked = fixed = 0
    for path in html_files():
        name, app_dir = path, os.path.dirname(path)
        with open(path, encoding="utf-8") as handle:
            html = handle.read()
        updated = html

        for match in LOCAL_REF.finditer(html):
            asset = match.group("file")
            asset_path = os.path.join(app_dir, asset)
            if not os.path.exists(asset_path):
                problems.append(f"{name} 引用了不存在的 {asset}")
                continue
            checked += 1
            want = content_version(asset_path)
            have = match.group("ver")
            # 手工递增的 ?v=3 / ?v=13 是仓库原有约定，规则 2 不动它们。
            if have is not None and not HASH_VERSION.match(have):
                continue
            if have == want:
                continue
            if stamp:
                updated = updated.replace(match.group(0),
                                          f'{match.group("attr")}="{asset}?v={want}"')
                fixed += 1
            elif have is None:
                problems.append(
                    f"{name} 引用 {asset} 没有版本号——回访用户会拿缓存里的旧代码"
                    f"配上每次都拉新的数据，页面可能显示与事实不符的内容"
                    f"（应为 ?v={want}）")
            else:
                problems.append(
                    f"{name} 引用 {asset}?v={have}，但文件内容的哈希是 {want}"
                    f"——改了文件没更新版本号")

        if stamp and updated != html:
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(updated)
            print(f"[--] 已改写 {name}")

    if stamp:
        print(f"已校正 {fixed} 处引用（共检查 {checked} 处）")
        return 0

    print(f"检查 {'、'.join(ROOT_DIRS)} 下 {checked} 处本地资源引用")
    if problems:
        print(f"\n失败 {len(problems)} 项：")
        for item in problems:
            print(f"  · {item}")
        print("\n跑 `python3 scripts/validate_asset_versions.py --stamp` 自动校正。")
        return 1
    print("全部带版本号；哈希版本号与文件内容一致")
    return 0


if __name__ == "__main__":
    sys.exit(scan(stamp="--stamp" in sys.argv))
