# 余烬陷落 EMBERFALL 大作版 · 外部素材来源台账

每个外部素材（模型、贴图、动作、音频、字体、AI 生成图）一行。许可不清楚的一律不用（见 `.claude/skills/emberfall/SKILL.md`）。
导出网页版时本文件随游戏一起打包（导出预设的 include_filter）。

| 素材 | 仓库内路径 | 作者 / 来源 | 许可 | 原始链接 | 取得日期 | 备注 |
|---|---|---|---|---|---|---|
| Noto Sans SC 中文字体子集（ASCII、常用标点、GB2312 一级汉字与符号区、本工程源码与数据里出现的全部字符，共 4546 个字形） | `godot/assets/fonts/NotoSansSC-EF.ttf` | Google / Adobe（Noto Sans SC）；子集由 `tools/build_font.py`（复用 `games/working-life/tools/build_font.py`）生成，字重 500 | SIL Open Font License 1.1（全文 `godot/assets/fonts/OFL.txt`） | https://github.com/google/fonts/tree/main/ofl/notosanssc（`NotoSansSC[wght].ttf`） | 2026-09-26（P5 按本工程字符集重新生成，补上 V0.1 物品名里的「匕、睿、鸢」） | 代码或数据里新增生僻字后重新运行 `tools/build_font.py` |
| Monastery Stone Floor（地牢地面：颜色、OpenGL 法线、ARM 遮蔽 / 粗糙度 / 金属度，1K JPG） | `godot/assets/textures/monastery_stone_floor/` | Amal Kumar / Poly Haven | CC0 1.0（https://polyhaven.com/license） | https://polyhaven.com/a/monastery_stone_floor | 2026-09-26 | 2.6 之二；原始扫描 1.8 米见方，游戏里每 2.6 米平铺一次；镇上石板路共用 |
| Rock Wall 08（地牢墙、楼梯框、灰盒测试区的墙与石柱；同上三张） | `godot/assets/textures/rock_wall_08/` | Amal Kumar / Poly Haven | CC0 1.0 | https://polyhaven.com/a/rock_wall_08 | 2026-09-26 | 2.6 之二；1.8 米见方，游戏里每 2.4 米平铺 |
| Forest Ground 04（烬原镇泥土地；同上三张） | `godot/assets/textures/forest_ground_04/` | Rob Tuytel（拍摄、处理）、Rico Cilliers（微调）/ Poly Haven | CC0 1.0 | https://polyhaven.com/a/forest_ground_04 | 2026-09-26 | 2.6 之二；3.15 米见方，游戏里每 4.5 米平铺 |

场景里的模型仍全部是代码生成的**占位几何体**；外部贴图只有上面三套 Poly Haven 贴图（2.6 之二起），它们缺失时自动退回程序化贴图（`world/look.gd`）。
贴图原文件是 Poly Haven 下载的 1K JPG，未修改；导入设置为 Basis Universal + mipmap，法线贴图勾选 normal_map（`*.jpg.import`）。
