#!/usr/bin/env python3
"""为《工地搬砖》生成内置中文字体子集。

网页版的 Godot 读不到系统字体，中文必须随游戏打包。完整的思源黑体（Noto Sans SC）
有 17MB，这里只保留：

  * ASCII 与常用标点、全角符号
  * GB2312 一级常用汉字（3755 个）与 GB2312 符号区
  * 游戏源码（.gd / .tscn / .godot / .cfg）里实际出现的所有字符

生成物约 2MB，放在 godot/assets/fonts/NotoSansSC-CW.ttf。以后在代码里新增了
生僻字，重新跑一次本脚本即可。

用法：
    pip install fonttools   # 仅本地构建需要，不是网站依赖
    python3 games/construction-worker/tools/build_font.py path/to/NotoSansSC[wght].ttf

字体来源：Google Fonts「Noto Sans SC」，SIL Open Font License 1.1（见 OFL.txt）。
https://github.com/google/fonts/tree/main/ofl/notosanssc
"""
from __future__ import annotations

import argparse
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
GODOT = HERE.parent / "godot"
OUT = GODOT / "assets" / "fonts" / "NotoSansSC-CW.ttf"
SOURCE_SUFFIXES = {".gd", ".tscn", ".godot", ".cfg", ".tres"}
WEIGHT = 500


def gb2312_chars() -> set[str]:
    chars: set[str] = set()
    # 第 1~9 区：符号；第 16~55 区：一级汉字
    rows = list(range(1, 10)) + list(range(16, 56))
    for row in rows:
        for col in range(1, 95):
            try:
                ch = bytes([0xA0 + row, 0xA0 + col]).decode("gb2312")
            except UnicodeDecodeError:
                continue
            chars.add(ch)
    return chars


def source_chars() -> set[str]:
    chars: set[str] = set()
    for path in GODOT.rglob("*"):
        if ".godot" in path.parts or not path.is_file():
            continue
        if path.suffix not in SOURCE_SUFFIXES:
            continue
        chars.update(path.read_text(encoding="utf-8", errors="ignore"))
    return chars


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("variable_font", help="Noto Sans SC 可变字体（NotoSansSC[wght].ttf）")
    parser.add_argument("--weight", type=int, default=WEIGHT)
    args = parser.parse_args()

    from fontTools.subset import Options, Subsetter
    from fontTools.ttLib import TTFont
    from fontTools.varLib import instancer

    chars = {chr(c) for c in range(0x20, 0x7F)}
    chars |= set("，。、；：？！“”‘’（）【】《》…—·￥¥×÷～ ")
    chars |= gb2312_chars()
    chars |= source_chars()
    chars = {c for c in chars if c.isprintable() or c == " "}

    font = TTFont(args.variable_font)
    if "fvar" in font:
        font = instancer.instantiateVariableFont(font, {"wght": args.weight})
    options = Options()
    options.hinting = False
    options.desubroutinize = True
    options.layout_features = ["*"]
    options.name_IDs = ["*"]
    options.notdef_outline = True
    subsetter = Subsetter(options=options)
    subsetter.populate(text="".join(sorted(chars)))
    subsetter.subset(font)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    font.save(OUT)
    cmap = font.getBestCmap()
    missing = sorted(c for c in source_chars() if c.isprintable() and ord(c) > 0x7F and ord(c) not in cmap)
    print(f"写入 {OUT.relative_to(HERE.parent.parent.parent)}：{OUT.stat().st_size / 1024:.0f} KB，{len(cmap)} 个字形")
    if missing:
        print("字体里没有这些源码字符（会显示为方框）：", "".join(missing))
    return 0


if __name__ == "__main__":
    sys.exit(main())
