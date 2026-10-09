#!/usr/bin/env python3
"""为《铁冠之争》重新生成内置中文字体子集（复用 games/working-life/tools/build_font.py，只换路径；做法同 emberfall3d/tools/build_font.py）。

字符集 = ASCII 与常用标点 + GB2312 一级汉字与符号区 + 本工程源码（.gd / .json 等）里实际出现的所有字符。
1.3 加了更夫的台词，「烽燧」的「燧」不在一级字库里（原先复制的《余烬陷落》子集也没有），所以按本工程字符集重做。
以后在代码或数据里加了生僻字，自动化测试「界面文字全部在字体子集里」会失败，再跑一次本脚本即可。

用法（fonttools 只是本地构建工具，不是网站依赖）：
    pip install fonttools
    python3 games/ironcrown/tools/build_font.py path/to/NotoSansSC[wght].ttf

可变字体会先取 500 字重；也可以直接给 500 字重的静态字体（2026-10-09 重做时用的是 Google Fonts 下发的
Noto Sans SC Medium：fonts.googleapis.com/css2?family=Noto+Sans+SC:wght@500 里的 .ttf，和原来按可变字体取 500 的字形逐一比对一致）。

字体来源：Google Fonts「Noto Sans SC」，SIL Open Font License 1.1（godot/assets/fonts/OFL.txt）。
https://github.com/google/fonts/tree/main/ofl/notosanssc
"""
from __future__ import annotations

import importlib.util
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("wl_build_font", HERE.parents[1] / "working-life" / "tools" / "build_font.py")
wl = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wl)

wl.HERE = HERE
wl.GODOT = HERE.parent / "godot"
wl.OUT = wl.GODOT / "assets" / "fonts" / "NotoSansSC-IC.ttf"

# 2026-10-09：设计文档（人名、地名都在 STORY.md / WORLD.md 里）用到的字也收进来。原来只收源码里出现的字，
# 「伊薇特」的「薇」这种二级字库的字要等台词写进代码以后再重做一次字体；收进设计文档以后，按剧本写台词不用再重做（只多十几个字）。
_source_chars = wl.source_chars


def source_chars() -> set[str]:
    chars = _source_chars()
    for path in (HERE.parent / "design").glob("*.md"):
        chars.update(path.read_text(encoding="utf-8", errors="ignore"))
    return chars


wl.source_chars = source_chars

if __name__ == "__main__":
    sys.exit(wl.main())
