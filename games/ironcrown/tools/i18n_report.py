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
        return sorted(GODOT.glob("world/*.gd")) + sorted(GODOT.glob("quest/*.gd")) + sorted(GODOT.glob("actors/*.gd")) + sorted(GODOT.glob("combat/*.gd")) + sorted(GODOT.glob("player/*.gd")) + sorted(GODOT.glob("chapters/*.gd")) + [GODOT / "scenes/opening.gd"]
    raise SystemExit("未知范围：" + scope)


def strings_of(scope: str) -> list[str]:
    seen: dict[str, None] = {}
    for p in scope_files(scope):
        if p.name == "en.json":
            continue
        if p.suffix == ".gd":
            items = gd_strings(p)
        else:
            items = []
            json_strings(json.loads(p.read_text(encoding="utf-8")), items)
        for s in items:
            seen.setdefault(s, None)
    return list(seen)


def main() -> int:
    argv = sys.argv[1:]
    if "--json" in argv:
        i = argv.index("--json")
        argv = argv[:i] + argv[i + 2:]
    args = [a for a in argv if not a.startswith("--")]
    scopes = args or ["ui", "data", "dialogue", "world"]
    if scopes == ["all"]:
        scopes = ["ui", "data", "dialogue", "world"]
    table = json.loads((GODOT / "data/i18n/en.json").read_text(encoding="utf-8"))
    missing_all = []
    for sc in scopes:
        ss = strings_of(sc)
        miss = [s for s in ss if s not in table]
        chars = sum(len(HAN.findall(s)) for s in miss)
        print(f"{sc}: {len(ss) - len(miss)} / {len(ss)} 句有英文；还差 {len(miss)} 句（{chars} 个汉字）")
        missing_all += miss
    if "--list" in sys.argv:
        for s in missing_all:
            print(json.dumps(s, ensure_ascii=False))
    if "--json" in sys.argv:
        out = pathlib.Path(sys.argv[sys.argv.index("--json") + 1])
        out.write_text(json.dumps({s: "" for s in missing_all}, ensure_ascii=False, indent=1), encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
