#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""补齐已发布边文件里的冶炼厂国别。纯本地文件变换，不发起网络请求。

**为什么要有这个后置脚本，而不是修抽取器了事。**

抽取器每年只在申报季跑（Form SD 五月底截止），重新解析要重新抓 SEC。
而这里要修的两件事都能在已发布的数据上离线做完：

一、**归一化漏网。** `match_country` 此前不折逗号倒装式，
    "CONGO, DEMOCRATIC REPUBLIC OF THE" 落到「认得出是国家但没有译名」
    那条分支，把英文原文发到了页面上——刚果（金）因此在国别榜上被拆成
    4 种写法，哪一行都不排名。而刚果（金）不是随便哪个国家：**Form SD
    这套披露制度就是为它立的**。已在 form_sd_parse 修好，这里把存量数据
    过一遍同一个函数。

二、**国别列没被映射上。** 有 7 家公司（丰田、本田、飞利浦、安波福、
    Ralph Lauren、Arista、Rentokil）的名单里 98% 的条目没有国别——
    那几份申报的表格列序与常见形态不同，抽取器没认出国别列。
    `parse.countryRatio` 早就记着 0.02，**数据照发、页面照印，没有一处
    说这一栏是空的**。

    这一条能补，是因为这些条目都带 **RMI CID**——那是冶炼厂设施的全球
    唯一编号，不是某份申报的内部编号。同一个 CID 在别家申报人那里写着
    国别，说的就是同一座厂。所以这不是推断关系，是**用标识符去查它自己
    的属性**，正是 CID 存在的用途。

**补什么、不补什么**（判据说「收谁」，不说「除了谁」）：

    只补 —— 该 CID 在其他申报人那里的国别**唯一**（无分歧）；
    不补 —— 有两家及以上写法不同的（61 条），以及登记表里也没有的（16 条）。

有分歧就留空。挑一个多数派看着更好看，但那是拿「多数人这么写」冒充
「事实如此」——同一座厂被写成中国和中国香港，是口径问题，不该由我裁决。

**回填的边必须留下痕迹。** 每条补过的边带 `countryBasis: "rmi-registry"`，
页面据此说明这一格来自登记表而不是本份申报。不留痕迹的话，读者会以为
丰田那份申报里真写了国别。
"""
from __future__ import annotations

import collections
import glob
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import form_sd_parse  # noqa: E402

EDGES_DIR = "apps/supply-chain/edges"
SMELTERS_PATH = "apps/supply-chain/smelters.json"
CJK = re.compile(r"[一-鿿]")
UNKNOWN = "未归类"


def is_translated(value) -> bool:
    """中文名才算译过。英文原文能显示，但不该当成终态。"""
    return bool(value) and bool(CJK.search(str(value)))


def renormalize(value):
    """把英文原文再过一次国别表。认不出就原样退回，不猜。"""
    if not value or is_translated(value):
        return value, False
    _, shown = form_sd_parse.match_country(str(value))
    if shown and is_translated(shown):
        return shown, True
    return value, False


def load_bundles() -> list[tuple[str, dict]]:
    out = []
    for path in sorted(glob.glob(os.path.join(EDGES_DIR, "*.json"))):
        with open(path, encoding="utf-8") as handle:
            out.append((path, json.load(handle)))
    return out


def cid_consensus(bundles) -> tuple[dict, dict]:
    """每个 CID 在所有申报人那里的国别。返回（唯一的, 有分歧的）。

    **分歧要按国别本身判，不能按（中文名, 英文键）这个二元组判。** 第一版
    是按二元组的，于是同一座厂被一家写成 ("中国", "china")、另一家写成
    ("中国", None)，就算成了「两家说法不同」——凭空多出 76 个假分歧，
    少补了 318 条边。**国别一致而附带字段缺失，不是分歧，是缺字段。**

    英文键只在国别唯一确定之后拿来填，取该 CID 出现过的非空值。
    """
    seen: dict[str, collections.Counter] = collections.defaultdict(collections.Counter)
    en_of: dict[str, dict[str, str]] = collections.defaultdict(dict)
    for _, bundle in bundles:
        for edge in bundle.get("edges") or []:
            cid = edge.get("cid")
            country, _ = renormalize(edge.get("country"))
            if not cid or not is_translated(country):
                continue
            seen[cid][country] += 1
            if edge.get("countryEn"):
                en_of[cid].setdefault(country, edge["countryEn"])
    unique = {}
    for cid, counter in seen.items():
        if len(counter) != 1:
            continue
        country = next(iter(counter))
        unique[cid] = (country, en_of[cid].get(country))
    split = {cid: dict(c) for cid, c in seen.items() if len(c) > 1}
    return unique, split


def rebuild_by_country(edges) -> dict:
    """重算文件级国别汇总。补了国别却不重算这一份，页面还是印旧数。"""
    counter = collections.Counter(e.get("country") or UNKNOWN for e in edges)
    return dict(counter.most_common())


def main() -> int:
    bundles = load_bundles()
    if not bundles:
        print("没有边文件，跳过")
        return 0
    unique, split = cid_consensus(bundles)
    print(f"CID 国别共识：唯一 {len(unique)} 个 · 有分歧 {len(split)} 个")

    fixed_name = filled = left_split = left_none = 0
    touched: dict[str, int] = {}
    for path, bundle in bundles:
        changed = 0
        for edge in bundle.get("edges") or []:
            country, did = renormalize(edge.get("country"))
            if did:
                key, _ = form_sd_parse.match_country(str(edge.get("country")))
                edge["country"] = country
                edge["countryEn"] = key or edge.get("countryEn")
                fixed_name += 1
                changed += 1
                continue
            if edge.get("country"):
                continue
            cid = edge.get("cid")
            if not cid:
                left_none += 1
                continue
            if cid in split:
                left_split += 1
                continue
            hit = unique.get(cid)
            if not hit:
                left_none += 1
                continue
            edge["country"], edge["countryEn"] = hit
            # 痕迹：这一格来自 RMI 登记表，不是本份申报写的。
            edge["countryBasis"] = "rmi-registry"
            filled += 1
            changed += 1
        if changed:
            bundle["byCountry"] = rebuild_by_country(bundle.get("edges") or [])
            with open(path, "w", encoding="utf-8") as handle:
                json.dump(bundle, handle, ensure_ascii=False, separators=(",", ":"))
            touched[bundle.get("symbol") or path] = changed

    print(f"改写英文原文国别 {fixed_name} 条 · 按 CID 回填 {filled} 条")
    print(f"仍留空：登记表有分歧 {left_split} 条 · 登记表也没有 {left_none} 条")
    for sym, n in sorted(touched.items(), key=lambda kv: -kv[1])[:10]:
        print(f"    {sym:8} {n} 条")

    # 登记表本身也要过同一遍，否则冶炼厂清单与边文件说的国别会不一致。
    with open(SMELTERS_PATH, encoding="utf-8") as handle:
        registry = json.load(handle)
    reg_fixed = 0
    for entry in (registry.get("smelters") or {}).values():
        country, did = renormalize(entry.get("country"))
        if did:
            key, _ = form_sd_parse.match_country(str(entry.get("country")))
            entry["country"] = country
            entry["countryEn"] = key or entry.get("countryEn")
            reg_fixed += 1
    if reg_fixed:
        with open(SMELTERS_PATH, "w", encoding="utf-8") as handle:
            json.dump(registry, handle, ensure_ascii=False, separators=(",", ":"))
    print(f"登记表改写 {reg_fixed} 条")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
