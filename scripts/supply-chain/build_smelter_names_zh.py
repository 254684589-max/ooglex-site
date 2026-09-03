#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成冶炼厂中文译名表 apps/supply-chain/names-zh.json。

**与带出处的申报数据分开发布**：边文件里的字段值是 SEC 申报原文，译名是我们加的
标注。混在一起会让「哪些是原文、哪些是我们写的」分不清；分开之后，译名出错只是
显示层的事，动不了证据。

页面按英文原名查这张表；查不到就显示英文原文——**不半译、不硬造**。

纯离线，只读 smelters.json。
"""
from __future__ import annotations

import importlib.util
import json
import os
from datetime import datetime, timezone

SMELTERS_PATH = "apps/supply-chain/smelters.json"
OUT_PATH = "apps/supply-chain/names-zh.json"


def load_translator():
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "smelter_names_zh.py")
    spec = importlib.util.spec_from_file_location("smelter_names_zh", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main() -> int:
    if not os.path.exists(SMELTERS_PATH):
        print(f"[--] 还没有 {SMELTERS_PATH}，跳过译名表生成")
        return 0
    with open(SMELTERS_PATH, encoding="utf-8") as handle:
        smelters = (json.load(handle) or {}).get("smelters") or {}

    zh = load_translator()
    names: dict[str, str] = {}
    from_glossary = composed = 0
    for entry in smelters.values():
        name, country = entry.get("name"), entry.get("country")
        translated = zh.translate(name, country)
        if not translated:
            continue
        names[zh.key(name)] = translated
        if zh.key(name) in zh.GLOSSARY:
            from_glossary += 1
        else:
            composed += 1

    named = sum(1 for e in smelters.values() if e.get("name"))
    payload = {
        "contractVersion": 1,
        "dataset": "supply-chain-name-zh",
        "updatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "note": ("冶炼厂中文译名。**这是译名，不是注册名称**——核对以英文原文为准，"
                 "申报里写的就是英文。给不出可靠译名的条目不在表里，页面显示英文原文："
                 "半译出来的名字（「赤峰 Dajingzi 锡业」）比纯英文更糟，它看着像个中文名，"
                 "其实是拼错的。"),
        "method": ("两个来源：① 通用中文名对照表（云南锡业、三菱综合材料这类查得到的）；"
                   "② 地名 + 行业词 + 公司后缀全部认得时按词表组合，且只对中文语境的企业"
                   "生效——把美国公司直译成中文名等于凭空造名。"
                   "拼音字号（jin / yuan / hua）一律不猜：jin 可以是金、进、锦、晋。"),
        "coverage": {
            "claimComplete": False,
            "smeltersWithName": named,
            "withChinese": len(names),
            "fromGlossary": from_glossary,
            "composed": composed,
            "note": "覆盖率会随对照表逐步补充而上升；欧美企业普遍没有通用中文名，"
                    "显示英文原文是正确结果，不是缺口。",
        },
        "names": dict(sorted(names.items())),
    }
    with open(OUT_PATH, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    print(f"译名表 {len(names)}/{named} 条（对照表 {from_glossary}，规则组合 {composed}）"
          f" → {OUT_PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
