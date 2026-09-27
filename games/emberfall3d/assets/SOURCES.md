# 余烬陷落 EMBERFALL 大作版 · 外部素材来源台账

每个外部素材（模型、贴图、动作、音频、字体、AI 生成图）一行。许可不清楚的一律不用（见 `.claude/skills/emberfall/SKILL.md`）。
导出网页版时本文件随游戏一起打包（导出预设的 include_filter）。

| 素材 | 仓库内路径 | 作者 / 来源 | 许可 | 原始链接 | 取得日期 | 备注 |
|---|---|---|---|---|---|---|
| Noto Sans SC 中文字体子集（ASCII、常用标点、GB2312 一级汉字与符号区、本工程源码与数据里出现的全部字符，共 4546 个字形） | `godot/assets/fonts/NotoSansSC-EF.ttf` | Google / Adobe（Noto Sans SC）；子集由 `tools/build_font.py`（复用 `games/working-life/tools/build_font.py`）生成，字重 500 | SIL Open Font License 1.1（全文 `godot/assets/fonts/OFL.txt`） | https://github.com/google/fonts/tree/main/ofl/notosanssc（`NotoSansSC[wght].ttf`） | 2026-09-26（P5 按本工程字符集重新生成，补上 V0.1 物品名里的「匕、睿、鸢」） | 代码或数据里新增生僻字后重新运行 `tools/build_font.py` |
| Monastery Stone Floor（地牢地面：颜色、OpenGL 法线、ARM 遮蔽 / 粗糙度 / 金属度，1K JPG） | `godot/assets/textures/monastery_stone_floor/` | Amal Kumar / Poly Haven | CC0 1.0（https://polyhaven.com/license） | https://polyhaven.com/a/monastery_stone_floor | 2026-09-26 | 2.6 之二；原始扫描 1.8 米见方，游戏里每 2.6 米平铺一次；镇上石板路共用 |
| Rock Wall 08（地牢墙、楼梯框、灰盒测试区的墙与石柱；同上三张） | `godot/assets/textures/rock_wall_08/` | Amal Kumar / Poly Haven | CC0 1.0 | https://polyhaven.com/a/rock_wall_08 | 2026-09-26 | 2.6 之二；1.8 米见方，游戏里每 2.4 米平铺 |
| Forest Ground 04（烬原镇泥土地；同上三张） | `godot/assets/textures/forest_ground_04/` | Rob Tuytel（拍摄、处理）、Rico Cilliers（微调）/ Poly Haven | CC0 1.0 | https://polyhaven.com/a/forest_ground_04 | 2026-09-26 | 2.6 之二；3.15 米见方，游戏里每 4.5 米平铺 |
| Mixed Rock Tiles（白骨墓穴地面）；颜色、OpenGL 法线、ARM，1K JPG | `godot/assets/textures/mixed_rock_tiles/` | Dimitrios Savva / Poly Haven | CC0 1.0 | https://polyhaven.com/a/mixed_rock_tiles | 2026-09-27 | 2.6 之四；1.9 米见方，游戏里每 2.4 米平铺；导入时缩到 512 像素 |
| Mossy Stone Wall（白骨墓穴墙）；颜色、OpenGL 法线、ARM，1K JPG | `godot/assets/textures/mossy_stone_wall/` | Amal Kumar / Poly Haven | CC0 1.0 | https://polyhaven.com/a/mossy_stone_wall | 2026-09-27 | 2.6 之四；2 米见方，每 2.4 米平铺；导入时缩到 512 像素 |
| Dark Rock 02（熔渊地面）；颜色、OpenGL 法线、ARM，1K JPG | `godot/assets/textures/dark_rock_02/` | Amal Kumar / Poly Haven | CC0 1.0 | https://polyhaven.com/a/dark_rock_02 | 2026-09-27 | 2.6 之四；2 米见方，每 2.6 米平铺；导入时缩到 512 像素 |
| Dark Rock（熔渊墙）；颜色、OpenGL 法线、ARM，1K JPG | `godot/assets/textures/dark_rock/` | Amal Kumar / Poly Haven | CC0 1.0 | https://polyhaven.com/a/dark_rock | 2026-09-27 | 2.6 之四；2.42 米见方，每 2.6 米平铺；导入时缩到 512 像素 |
| Patterned Slate Tiles（深渊地面）；颜色、OpenGL 法线、ARM，1K JPG | `godot/assets/textures/patterned_slate_tiles/` | Dimitrios Savva / Poly Haven | CC0 1.0 | https://polyhaven.com/a/patterned_slate_tiles | 2026-09-27 | 2.6 之四；2.2 米见方，每 2.4 米平铺；导入时缩到 512 像素 |
| Castle Wall Slates（深渊墙）；颜色、OpenGL 法线、ARM，1K JPG | `godot/assets/textures/castle_wall_slates/` | Rob Tuytel / Poly Haven | CC0 1.0 | https://polyhaven.com/a/castle_wall_slates | 2026-09-27 | 2.6 之四；2.5 米见方，每 2.6 米平铺；导入时缩到 512 像素 |
| Broken Wall（烬原镇修道院废墟的墙）；颜色、OpenGL 法线、ARM，1K JPG | `godot/assets/textures/broken_wall/` | Rob Tuytel / Poly Haven | CC0 1.0 | https://polyhaven.com/a/broken_wall | 2026-09-27 | 2.6 之四；3 米见方，每 3 米平铺；导入时缩到 512 像素 |
| Plaster Stone Wall 01（烬原镇房屋的墙）；颜色、OpenGL 法线、ARM，1K JPG | `godot/assets/textures/plaster_stone_wall_01/` | Charlotte Baglioni / Poly Haven | CC0 1.0 | https://polyhaven.com/a/plaster_stone_wall_01 | 2026-09-27 | 2.6 之四；2.3 米见方，每 2.4 米平铺；导入时缩到 512 像素 |
| Grey Roof Tiles 02（烬原镇房顶）；颜色、OpenGL 法线、ARM，1K JPG | `godot/assets/textures/grey_roof_tiles_02/` | Rob Tuytel / Poly Haven | CC0 1.0 | https://polyhaven.com/a/grey_roof_tiles_02 | 2026-09-27 | 2.6 之四；1.5 米见方，每 1.8 米平铺；导入时缩到 512 像素 |

场景里的模型全部由代码生成（所有角色是 `actors/rig/` 代码搭的骨骼角色，2.6 之三；道具与房屋细节是 `world/prop_models.gd` 代码搭的模型，2.6 之五；树林、地面装饰与训练木桩也是，2.6 之六），不用外部模型与动作；外部贴图只有上面这些 Poly Haven 贴图（2.6 之二起三套、2.6 之四再加九套），缺失时自动退回程序化贴图（`world/look.gd`）。
贴图原文件是 Poly Haven 下载的 1K JPG，未修改；导入设置为 Basis Universal + mipmap，法线贴图勾选 normal_map；2.6 之四的九套另设 size_limit = 512（`*.jpg.import`）。
