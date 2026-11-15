#!/usr/bin/env python3
"""《铁冠之争》中英文对照表报表（2026-11-08 中英文切换）。

列出游戏里要显示给玩家的中文句子，哪些在 godot/data/i18n/en.json 里还没有英文。
  · .gd 文件：字符串字面量里带汉字的（跳过 print 调试输出、push_warning、数据自检的出错说明 errors.append、注释、测试）；
  · data/*.json、data/dialogue/*.json：所有带汉字的字符串值（跳过以 _ 开头的说明键）。
用法：
    python3 games/ironcrown/tools/i18n_report.py [范围…] [--list] [--json 输出文件]
范围：ui（ui/ 与 scenes/main.gd、core/）、dialogue、data、world、all（默认 all）。
"""
from __future__ import annotations

import argparse
import collections
import json
import pathlib
import re
import sys

GODOT = pathlib.Path(__file__).resolve().parent.parent / "godot"
HAN = re.compile(r"[㐀-鿿]")
LIT = re.compile(r'"((?:[^"\\\n]|\\.)*)"')
SKIP_LINE = re.compile(r"^\s*(print|push_warning|push_error|assert)\(|^\s*##|^\s*#|(errors|errs|bad|problems)\.append\(")


def gd_strings(path: pathlib.Path) -> list[str]:
    out = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if SKIP_LINE.search(line):
            continue
        code = line.split("  #")[0] if "  #" in line else line
        for m in LIT.finditer(code):
            s = bytes(m.group(1), "utf-8").decode("unicode_escape").encode("latin-1").decode("utf-8") if "\\" in m.group(1) else m.group(1)
            if HAN.search(s):
                out.append(s)
    return out


def json_strings(node, out: list[str], key: str = "") -> None:
    if isinstance(node, dict):
        for k, v in node.items():
            if str(k).startswith("_"):
                continue
            json_strings(v, out, str(k))
    elif isinstance(node, list):
        for v in node:
            json_strings(v, out, key)
    elif isinstance(node, str) and HAN.search(node):
        out.append(node)


def scope_files(scope: str) -> list[pathlib.Path]:
    if scope == "ui":
        return sorted(GODOT.glob("ui/*.gd")) + [GODOT / "scenes/main.gd"] + sorted(GODOT.glob("core/*.gd"))
    if scope == "dialogue":
        return sorted(GODOT.glob("data/dialogue/*.json"))
    if scope == "data":
        return sorted(p for p in GODOT.glob("data/*.json"))
    if scope == "world":
        covered = set(scope_files("ui"))
        return sorted(p for p in GODOT.rglob("*.gd") if p not in covered and not any(x in p.relative_to(GODOT).parts for x in ("tests", "assets", ".godot"))) + sorted(p for p in GODOT.rglob("*.tscn") if not any(x in p.relative_to(GODOT).parts for x in ("tests", "assets", ".godot", "chapters")))
    raise SystemExit("未知范围：" + scope)


def strings_of(scope: str) -> list[str]:
    seen: dict[str, None] = {}
    for p in scope_files(scope):
        if p.name == "en.json":
            continue
        if p.suffix in (".gd", ".tscn"):
            items = gd_strings(p)
        else:
            items = []
            json_strings(json.loads(p.read_text(encoding="utf-8")), items)
        for s in items:
            seen.setdefault(s, None)
    return list(seen)


PLACEHOLDER = re.compile(r"%(?:[-+0 #]*[0-9]*(?:\.[0-9]+)?)?[sdiouxXfFeEgGc%]")


def load_table(path: pathlib.Path) -> tuple[dict, list[str]]:
    duplicates = []
    def pairs(items):
        out = {}
        for key, value in items:
            if key in out:
                duplicates.append(key)
            out[key] = value
        return out
    return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=pairs), duplicates


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("scopes", nargs="*", choices=["ui", "data", "dialogue", "world", "all"])
    parser.add_argument("--list", action="store_true")
    parser.add_argument("--json", type=pathlib.Path)
    parser.add_argument("--check", action="store_true", help="缺译、重复、空值、占位符不符时退出 1")
    parser.add_argument("--report", type=pathlib.Path, help="写出覆盖率、逐文件统计和未翻译清单")
    args = parser.parse_args()
    scopes = args.scopes or ["all"]
    if "all" in scopes:
        scopes = ["ui", "data", "dialogue", "world"]
    table, duplicates = load_table(GODOT / "data/i18n/en.json")
    missing = {}
    inventory = {}
    summary = {}
    for scope in scopes:
        ss = strings_of(scope)
        miss = [s for s in ss if not isinstance(table.get(s), str) or not table[s].strip()]
        summary[scope] = {"total": len(ss), "translated": len(ss) - len(miss), "missing": len(miss)}
        print(f"{scope}: {len(ss) - len(miss)} / {len(ss)} 句有英文；还差 {len(miss)} 句")
        missing.update(dict.fromkeys(miss, ""))
        for path in scope_files(scope):
            texts = gd_strings(path) if path.suffix in (".gd", ".tscn") else []
            if path.suffix == ".json":
                json_strings(json.loads(path.read_text(encoding="utf-8")), texts)
            inventory[str(path.relative_to(GODOT))] = list(dict.fromkeys(texts))
    invalid = {k: {"source": PLACEHOLDER.findall(k), "translation": PLACEHOLDER.findall(v)}
               for k, v in table.items() if not k.startswith("_") and isinstance(v, str)
               and PLACEHOLDER.findall(k) != PLACEHOLDER.findall(v)}
    empty = [k for k, v in table.items() if not k.startswith("_") and (not isinstance(v, str) or not v.strip())]
    residual_han = [k for k, v in table.items() if not k.startswith("_") and isinstance(v, str) and HAN.search(v)]
    unique = set(s for texts in inventory.values() for s in texts)
    report = {"scope": "静态文本保守超集（含内部名称/说明）；不是所有剧情路径可达性证明", "summary": summary,
              "unique_total": len(unique), "unique_translated": sum(s in table and bool(table[s]) for s in unique),
              "duplicates": duplicates, "empty": empty, "placeholder_errors": invalid, "residual_han": residual_han,
              "missing": list(missing), "files": {p: {"total": len(ss), "missing": [s for s in ss if s in missing]} for p, ss in inventory.items()}}
    if args.list:
        for s in missing:
            print(json.dumps(s, ensure_ascii=False))
    if args.json:
        args.json.write_text(json.dumps(missing, ensure_ascii=False, indent=1), encoding="utf-8")
    if args.report:
        args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"去重 {len(unique)} 句；缺译 {len(missing)}；重复 {len(duplicates)}；空值 {len(empty)}；占位符错误 {len(invalid)}；英文含汉字 {len(residual_han)}")
    return int(args.check and bool(missing or duplicates or empty or invalid or residual_han))


if __name__ == "__main__":
    sys.exit(main())
