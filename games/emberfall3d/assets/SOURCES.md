# 余烬陷落 EMBERFALL 大作版 · 外部素材来源台账

每个外部素材（模型、贴图、动作、音频、字体、AI 生成图）一行。许可不清楚的一律不用（见 `.claude/skills/emberfall/SKILL.md`）。
导出网页版时本文件随游戏一起打包（导出预设的 include_filter）。

| 素材 | 仓库内路径 | 作者 / 来源 | 许可 | 原始链接 | 取得日期 | 备注 |
|---|---|---|---|---|---|---|
| Noto Sans SC 中文字体子集（ASCII、常用标点、GB2312 一级汉字与符号区、本工程源码与数据里出现的全部字符，共 4546 个字形） | `godot/assets/fonts/NotoSansSC-EF.ttf` | Google / Adobe（Noto Sans SC）；子集由 `tools/build_font.py`（复用 `games/working-life/tools/build_font.py`）生成，字重 500 | SIL Open Font License 1.1（全文 `godot/assets/fonts/OFL.txt`） | https://github.com/google/fonts/tree/main/ofl/notosanssc（`NotoSansSC[wght].ttf`） | 2026-09-26（P5 按本工程字符集重新生成，补上 V0.1 物品名里的「匕、睿、鸢」） | 代码或数据里新增生僻字后重新运行 `tools/build_font.py` |

阶段 1 的场景全部是代码生成的**占位几何体**，不使用任何外部模型或贴图。
