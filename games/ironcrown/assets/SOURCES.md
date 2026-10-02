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

## 候选素材（D4 = B，尚未下载、尚未入库）

2026-10-02 读取 quaternius.com 各包页面（页面标注 License CC0，并写明「个人、教育、商业项目均可使用」）。**下载只提供 itch.io 入口，本环境访问不了 itch.io，所以一个都还没下**；下载到、核对许可后再移到上面的正式表里。

| 包 | 内容 | 许可（页面标注） | 格式 | 原始链接 | 下载入口 | 状态 |
|---|---|---|---|---|---|---|
| Universal Base Characters（2025-08） | 6 个人体底模（超级英雄 / 常规 / 少年体型，男女），平均约 1.3 万三角面，20 种发型，统一人形骨架；页面写明与 Universal Animation Library 兼容、Godot 4.3 测试过 | CC0 | FBX、glTF（Source 版另有 blend） | https://quaternius.com/packs/universalbasecharacters.html | https://quaternius.itch.io/universal-base-characters | 待下载（itch.io 被拦） |
| Modular Character Outfits – Fantasy（2025-11） | 12 套奇幻服装、62 个模块部件，每套 3 种颜色贴图；与 Universal Base Characters 兼容，统一人形骨架 | CC0 | FBX、glTF | https://quaternius.com/packs/modularcharacteroutfitsfantasy.html | https://quaternius.itch.io/modular-character-outfits-fantasy | 待下载（itch.io 被拦） |
| Universal Animation Library（2025-03） | 120+ 动作：八方向移动、慢跑、冲刺、蹲伏、爬行、游泳、坐、死亡、战斗、表情等；任意版本 Godot 可用 | CC0 | FBX、GLB | https://quaternius.com/packs/universalanimationlibrary.html | https://quaternius.itch.io/universal-animation-library | 待下载（itch.io 被拦） |
| Universal Animation Library 2（2026-01） | 130+ 动作：近战与持械连击（3 段、4 段连击，拆成单击与收招，另有整套连击）、跑酷、农活、钓鱼、僵尸移动等 | CC0 | FBX、GLB | https://quaternius.com/packs/universalanimationlibrary2.html | https://quaternius.itch.io/universal-animation-library-2 | 待下载（itch.io 被拦） |

四个包用同一套「通用人形骨架」，动作不用改骨骼就能套在任何一个底模和服装上。

## 看过但不用

| 包 | 为什么不用 |
|---|---|
| Quaternius RPG Characters（6 个角色，Google Drive 能下） | 粗描边的卡通风，与 `ART.md`「写实倾向」冲突 |
| Quaternius Ultimate Modular Women（10 个，Google Drive 能下） | 现代服装、纯色平涂的低多边形，没有中世纪服装 |

## 不用的来源

- 所有者 2026-09-27 发来的参考截图（疑似其他商业游戏画面）：只用来理解氛围，不进仓库、不作生成输入（`design/ART.md` 第一节）。
