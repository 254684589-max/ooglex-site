# 余烬陷落 EMBERFALL 大作版 · 外部素材来源台账

每个外部素材（模型、贴图、动作、音频、字体、AI 生成图）一行。许可不清楚的一律不用（见 `.claude/skills/emberfall/SKILL.md`）。
导出网页版时本文件随游戏一起打包（导出预设的 include_filter）。

| 素材 | 仓库内路径 | 作者 / 来源 | 许可 | 原始链接 | 取得日期 | 备注 |
|---|---|---|---|---|---|---|
| Noto Sans SC 中文字体子集（ASCII、常用标点、GB2312 一级汉字 3755 个） | `godot/assets/fonts/NotoSansSC-EF.ttf` | Google / Adobe（Noto Sans SC）；子集由 `games/working-life/tools/build_font.py` 生成 | SIL Open Font License 1.1（全文 `godot/assets/fonts/OFL.txt`） | https://github.com/google/fonts/tree/main/ofl/notosanssc | 2026-09-26（复制自仓库内 `games/working-life/godot/assets/fonts/NotoSansSC-WL.ttf`） | 以后需要生僻字时，改用本工程自己的字符集重新生成子集 |

阶段 1 的场景全部是代码生成的**占位几何体**，不使用任何外部模型或贴图。
