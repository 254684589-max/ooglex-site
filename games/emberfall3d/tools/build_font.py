#!/usr/bin/env python3
"""为《余烬陷落》大作版重新生成内置中文字体子集（复用 games/working-life/tools/build_font.py，只换路径）。

字符集 = ASCII 与常用标点 + GB2312 一级汉字与符号区 + 本工程源码（.gd / .json 等）里实际出现的所有字符。
P5 起地上会显示装备名，V0.1 数据里有一级字库以外的字（匕、睿、鸢），所以按本工程字符集重做。
以后在代码或数据里加了生僻字，再跑一次即可。

用法（fonttools 只是本地构建工具，不是网站依赖）：
    pip install fonttools
    python3 games/emberfall3d/tools/build_font.py path/to/NotoSansSC[wght].ttf

字体来源：Google Fonts「Noto Sans SC」，SIL Open Font License 1.1（godot/assets/fonts/OFL.txt）。
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
wl.OUT = wl.GODOT / "assets" / "fonts" / "NotoSansSC-EF.ttf"

if __name__ == "__main__":
    sys.exit(wl.main())
