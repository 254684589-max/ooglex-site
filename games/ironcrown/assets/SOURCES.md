# 铁冠之争 · 外部素材来源台账

每个外部素材一行：名称、在工程里的位置、作者、许可、原始链接、下载日期、备注。许可不清楚的一律不用（`.claude/skills/ironcrown/SKILL.md` 原创红线）。

## 字体

| 名称 | 位置 | 作者 | 许可 | 原始链接 | 下载日期 | 备注 |
|---|---|---|---|---|---|---|
| Noto Sans SC（可变字重，本工程字符集子集） | `godot/assets/fonts/NotoSansSC-IC.ttf`（许可全文 `OFL.txt`） | Google / Adobe | SIL Open Font License 1.1 | https://github.com/google/fonts/tree/main/ofl/notosanssc | 2026-09-27 | 1.3 起由 `tools/build_font.py` 按本工程字符集生成子集（字重 500） |

## 贴图（Poly Haven，CC0）

全部来自 Poly Haven，许可 CC0 1.0（https://polyhaven.com/license），每套取颜色（diff）、OpenGL 法线（nor_gl）、ARM（遮蔽 / 粗糙度 / 金属度）三张 1K JPG。
游戏里按世界坐标三向投影（不用 UV），「平铺」一栏是游戏里每隔多少米重复一次。

| 名称 | 位置 | 作者 | 原始链接 | 下载日期 | 用途 · 导入 |
|---|---|---|---|---|---|
| Cobblestone Floor 03 | `godot/assets/textures/cobblestone_floor_03/` | Rob Tuytel | https://polyhaven.com/a/cobblestone_floor_03 | 2026-09-27 | 1.4 霜渡镇主街石板路；原始 2.4 米见方，平铺 2.4 米；1K |
| Stone Wall | `godot/assets/textures/stone_wall/` | Charlotte Baglioni（拍摄）、Dario Barresi（处理） | https://polyhaven.com/a/stone_wall | 2026-09-27 | 1.4 房屋石砌底层、烟囱、领主宅邸；2 米见方，平铺 2.2 米；1K |
| Plastered Wall 02 | `godot/assets/textures/plastered_wall_02/` | Charlotte Baglioni | https://polyhaven.com/a/plastered_wall_02 | 2026-09-27 | 1.4 房屋上层灰泥墙（木构架之间）；2.2 米见方，平铺 2.4 米；1K |
| Weathered Planks | `godot/assets/textures/weathered_planks/` | Dimitrios Savva（拍摄）、Dario Barresi（处理） | https://polyhaven.com/a/weathered_planks | 2026-09-27 | 1.4 木梁、门、百叶窗、街灯杆；2 米见方，平铺 1.6 米；导入缩到 512 |
| Roof Slates 02 | `godot/assets/textures/roof_slates_02/` | Rob Tuytel | https://polyhaven.com/a/roof_slates_02 | 2026-09-27 | 1.4 石板瓦屋顶；3 米见方，平铺 2.5 米；导入缩到 512 |
| Snow 03 | `godot/assets/textures/snow_03/` | Rob Tuytel | https://polyhaven.com/a/snow_03 | 2026-09-27 | 1.4 路边雪泥、屋脊积雪；2 米见方，平铺 3 米；导入缩到 512 |
| Bark Brown 02 | `godot/assets/textures/bark_brown_02/` | Rob Tuytel | https://polyhaven.com/a/bark_brown_02 | 2026-09-27 | 1.4 小广场上的枯树；1 米见方，平铺 1.2 米；导入缩到 512 |

## 不用的来源

- 所有者 2026-09-27 发来的参考截图（疑似其他商业游戏画面）：只用来理解氛围，不进仓库、不作生成输入（`design/ART.md` 第一节）。
