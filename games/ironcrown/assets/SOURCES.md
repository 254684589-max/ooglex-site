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

2026-10-23 场景美化四（所有者同意网页包涨到约 70 MB）新增三套，同样来自 Poly Haven（CC0 1.0），只取颜色（diff）和 OpenGL 法线（nor_gl）两张 1K JPG（不取 ARM，省包体；鹭沼地面两套的法线导入时缩到 512）：

| 用途 | Poly Haven 资源 | 链接 | 作者 |
|---|---|---|---|
| 黑鹭堡的石墙（庭院四面墙、主楼和塔楼、兵营、账房、大厅等四个室内、鹭沼上看到的城堡和堤道拱门） | castle_wall_varriation | https://polyhaven.com/a/castle_wall_varriation | Rob Tuytel |
| 鹭沼的湿泥（泥滩、泥潭） | brown_mud_02 | https://polyhaven.com/a/brown_mud_02 | Rob Tuytel |
| 鹭沼的干岸（草皮泥炭地，压暗偏灰） | grass_path_2 | https://polyhaven.com/a/grass_path_2 | Rob Tuytel |

2026-10-23 第二章「余火高地」（路线图 5.1a，D12）新增四套地面贴图和一张天空照片，同样来自 Poly Haven（CC0 1.0），**放在第二章章节包里**（`godot/chapters/ch2/`，进第二章才下载，主包不变大）。
贴图只取颜色（diff）和 OpenGL 法线（nor_gl）两张 1K JPG，法线导入时缩到 512；地形着色器按世界坐标贴（`shaders/highland_ground.gdshader`）：

| 用途 | Poly Haven 资源 | 链接 | 作者 | 下载日期 |
|---|---|---|---|---|
| 高地平处的积雪 | snow_02 | https://polyhaven.com/a/snow_02 | Rob Tuytel | 2026-10-23 |
| 盘山路和村里踩出来的雪（有脚印） | snow_01 | https://polyhaven.com/a/snow_01 | Rob Tuytel | 2026-10-23 |
| 雪薄处的碎石 | gray_rocks | https://polyhaven.com/a/gray_rocks | Rob Tuytel | 2026-10-23 |
| 陡坡、岩坎露出的岩石（长地衣的灰岩） | mossy_rock | https://polyhaven.com/a/mossy_rock | Rob Tuytel | 2026-10-23 |
| 天空：阴天的云（HDRI「Kloofendal Overcast (Pure Sky)」2K，只取上半球、色调映射成普通照片 `chapters/ch2/sky/overcast_sky.jpg`，2048 × 512） | kloofendal_overcast_puresky | https://polyhaven.com/a/kloofendal_overcast_puresky | Greg Zaal | 2026-10-23 |

看过没用的：rock_face、rock_face_03（偏棕、偏暖，不像北方的灰岩）、lichen_rock（太暗）、snow_field / passendorf_snow 等带地面的 HDRI（照片里有树林、房子、远处的地平线，和我们的地形对不上，只取天空的「pure sky」那一版）。

## 人物与动作（Quaternius，CC0；D4 = B，阶段 A.1）

三个包的许可文件（包内 `License_Standard.txt` / `License.txt`）都写 **CC0 1.0 Universal**（https://creativecommons.org/publicdomain/zero/1.0/）；Quaternius 页面标注个人、教育、商业项目均可使用。
下载日期 2026-10-02：由所有者在自己电脑上从 itch.io 点下载（免费的「Standard」版），上传到本仓库（本环境的自动下载被 itch.io 的下载校验拦下，没有绕过）。三个包同一套 65 根骨头的「通用人形骨架」，动作不用重定向（测试里逐条核对了骨头名）。

| 名称 | 位置 | 作者 | 原始链接 | 用途 · 处理 |
|---|---|---|---|---|
| Universal Base Characters [Standard]（2025-08）· `Superhero_Male_FullBody` | `godot/assets/characters/`（`.gltf`、`.bin`、5 张贴图、`LICENSE_UniversalBaseCharacters_CC0.txt`） | Quaternius | https://quaternius.itch.io/universal-base-characters（介绍页 https://quaternius.com/packs/universalbasecharacters.html） | A.1 主角的第三人称人物：1.8 米、约 1.4 万三角面、65 根骨头，身体 + 眼睛 + 眉毛三个网格，没有头发。**免费版只有「Superhero」体型的男、女各一个**（包内许可文件写明「只包含部分模型」，其余在付费源文件版里），这里只用男性。<br>处理：`tools/patch_character_gltf.py` 修补两处引用（眉毛的 `T_Hair_1_*` 贴图免费版没附带 → 眉毛改纯深棕色；眼睛法线图文件名对不上 → 改引用）；法线图用包里 `Textures/Normals Unity - Godot` 那一套；贴图导入缩到 1024、Basis 压缩；皮肤用 `T_Superhero_Male_Dark`（与另一张 `Ligh` 只有内裤颜色不同，肤色相同；`Ligh` 放在 `assets/source/quaternius/`，不进网页包） |
| Universal Animation Library [Standard]（UAL1，2025-03，v3.0） | `assets/source/quaternius/Universal Animation Library[Standard].zip`（原包） → 打包成 `godot/assets/characters/anims/ual_core.res` | Quaternius | https://quaternius.itch.io/universal-animation-library（介绍页 https://quaternius.com/packs/universalanimationlibrary.html） | **免费版 43 个动作**（页面写的「120+」是付费专业版）：只有朝前的走、跑、冲刺、蹲走，没有八方向移动。用到的：Idle_Loop、Sword_Idle、Walk_Loop、Jog_Fwd_Loop、Crouch_Idle_Loop、Crouch_Fwd_Loop、Jump_Loop、Sword_Attack（重击）、Hit_Chest、Death01；3.3 加了 Punch_Jab、Punch_Cross（徒手刺拳、直拳；Punch_Jab 第 0 帧也当举拳待机）；A.1b 加了 Hit_Head、Roll、Jump_Land；A.2a+ 加了 NPC 的站姿与动作：Idle_Talking_Loop、Idle_Torch_Loop、Sitting_Idle_Loop、Sitting_Talking_Loop、Fixing_Kneeling |
| Universal Animation Library 2 [Standard]（UAL2，2026-01） | `assets/source/quaternius/Universal Animation Library 2[Standard].zip` → 同上 | Quaternius | https://quaternius.itch.io/universal-animation-library-2（介绍页 https://quaternius.com/packs/universalanimationlibrary2.html） | **免费版同样 43 个动作**。用到的：Sword_Regular_A / B（轻击两段）、Sword_Block、Hit_Knockback；3.3 加了 OverhandThrow（借作徒手重拳，A.1b 换成 Melee_Hook 后不再打包）、Idle_Shield_Loop（第 0 帧当空手格挡）；A.1b 加了 Sword_Regular_C、Sword_Regular_A_Rec / B_Rec、Sword_Dash、Idle_Shield_Break、Melee_Hook；A.2a+ 加了 Idle_FoldArms_Loop、Idle_Lantern_Loop、Idle_Rail_Loop、TreeChopping_Loop、Consume、Yes、Idle_No_Loop、LayToIdle |

2026-10-04 为军阵战斗（D8）核对了两个免费动画库的全部 86 个动作名：**没有长枪、弓箭的动作**；有盾牌（`Idle_Shield_Loop`、`Shield_OneShot`、`Shield_Dash`、`Idle_Shield_Break`）、持火把待机（`Idle_Torch_Loop`）、`Sword_Regular_C` 与两段连招（`Sword_Regular_Combo`、`Sword_Heavy_Combo`），够做剑兵、剑盾兵和持棍民兵；长枪兵、弓手要另找 CC0 动作或用代码改骨骼姿势。2026-10-05（B.4）：兵还是占位胶囊，长枪的端、刺和弓的拉、放先用代码摆手臂，**没有引入新素材**；动作来源挪到换人物模型时（B.6）再定。

动作与游戏里「角色」（站、走、跑、出招……）的对应在 `godot/data/character_anims.json`；`tools/build_character_anims.gd` 从 zip 里只把用到的 14 个动作打成动画库（原包的 glb 还带着整个人台网格与 40 多个用不上的动作，约 7.6 MB 一个）。

## 游戏中心封面

| 文件 | 来源 | 许可 | 处理 |
|---|---|---|---|
| `games/hub/img/ironcrown-poster.webp`（900×1200，约 190 KB） | 所有者 2026-10-03 在对话里提供的竖版海报（1086×1448，「铁冠之争」标题、戴冠持剑的骑士、燃烧的城堡、碎裂的铁冠），要求整张用作游戏中心卡片封面 | **所有者用 AI 生成**（所有者 2026-10-03 说明），所有者要求使用 | 整张缩到 900 宽。**原海报里有几面红底金狮旗**（左下两面、右侧一面大旗、城墙上一面小旗，远处军队的小旗上也有模糊纹样），与 `design/WORLD.md` 第九节「不复刻家族徽记动物（狮）」冲突：这些纹样用羽化遮罩柔化成素色旗面，画面其余部分不动。原图（带狮子）没有入库。第一版只裁了标题一段（`ironcrown-cover.webp`，已删除） |

## 声音

没有外部音频素材。开场的钟声（3.8）在 `godot/core/bell.gd` 里按泛音合成，原创，不涉及许可。

背景音乐（M.1，2026-10-17）：五首（`godot/assets/music/town|night|marsh|keep|battle.ogg`）都是 `tools/compose_music.py` 代码作曲、代码合成的原创曲——旋律与和声写在脚本里（调式音乐，没有引用任何现成曲子），乐器是拨弦（Karplus-Strong）、木笛、弦垫、持续音、鼓和铜管般的音色，全部在脚本里合成，不用任何采样或外部音色库；重新运行脚本得到同样的文件。原创，不涉及许可。
所有者 2026-10-17 发来的一段 YouTube 背景音乐链接：本环境打不开 YouTube，也不能转存网上的音乐；版权、许可不清楚，不用。所有者以后提供有授权的曲子（附授权说明）时，登记在这里、放进 `godot/assets/music/`，改 `godot/data/music.json` 的 `tracks` 即可。

## 候选素材（尚未下载）

| 包 | 内容 | 许可（页面标注） | 原始链接 | 状态 |
|---|---|---|---|---|
| Modular Character Outfits – Fantasy（2025-11，v2.1） | **2026-10-17 已导入免费版（见上面 A.2a 一节）**。12 套奇幻服装、62 个模块部件，每套 3 种颜色贴图；与 Universal Base Characters 兼容；免费「Standard」版 280 MB（另有付费源文件版 724 MB） | CC0 | https://quaternius.itch.io/modular-character-outfits-fantasy | A.2 用，**阶段 B 的士兵也用这一份**（D8，`design/ART.md` 7.1：挑 3–4 套兵装，阵营靠代码改颜色和画徽记，不用每个兵单独准备）；280 MB 太大，下载后只挑用得到的几套再入库 |

### 人物（二）的服装、头、头发（阶段 A.2a，2026-10-17）

所有者 2026-10-17 在自己电脑上从 itch.io 下载两个包的免费「Standard」版，推送到私有仓库 `254684589-max/ironcrown-assets`（原包 410 MB，不进本仓库）；我从那里取用。两个包的 `License_Standard.txt` 都写 **CC0 1.0 Universal**（https://creativecommons.org/publicdomain/zero/1.0/），原文副本在 `godot/assets/characters/outfits/LICENSE_Quaternius_CC0.txt`。

| 名称 | 位置 | 作者 | 原始链接 | 用途 · 处理 |
|---|---|---|---|---|
| Modular Character Outfits – Fantasy [Standard]（v2.1，2026-01） | `godot/assets/characters/outfits/Outfit_{Male,Female}_{Peasant,Ranger}.*`、`T_Peasant_*`、`T_Ranger_*`、`T_Regular_*` | Quaternius | https://quaternius.itch.io/modular-character-outfits-fantasy | **免费版只有平民（Peasant）、游侠（Ranger）两套，男女各一**（页面上的 12 套在付费源文件版里）。NPC 的衣服：平民那套给镇民、渔民、泥炭工，换颜色当贵族、修士的衣服；游侠那套（摘掉兜帽）给卫兵、兵营里的兵和伊薇特。 |
| Universal Base Characters [Standard]（2025-08） | `godot/assets/characters/outfits/Head_{Male,Female}.*`、`Hair_*.*`、`T_Superhero_Female_*`、`T_Hair_*` | Quaternius | https://quaternius.itch.io/universal-base-characters | 头（包里说明「用服装时只要底模的头」）：从 `Superhero_{Male,Female}_FullBody` 里只留脖子以上的三角形和眼睛、眉毛；六种发型（`Hairstyles/Rigged to Head Bone` 的 glTF：分头、寸头、胡子、长发、发髻、女式短发）。 |

处理：`tools/import_outfits.py`——五个包用同一副 65 根骨头的骨架、顺序一样（导入前核对过），所以游戏里把头和头发挂到服装的骨架上就能一起动、用 A.1 的动作；每个 glTF 重写：只留位置、法线、第一套贴图坐标、骨头、权重，去掉用不到的顶点；**只留底色贴图、缩到 512**（网页首次加载的预算，见 `TECH.md` 4.27），法线、ORM 不用；Godot 导入用 Basis 压缩（同 A.1）。哪个 NPC 穿什么写在 `godot/data/looks.json`。

## 看过但不用

| 包 | 为什么不用 |
|---|---|
| Quaternius RPG Characters（6 个角色，Google Drive 能下） | 粗描边的卡通风，与 `ART.md`「写实倾向」冲突 |
| Quaternius Ultimate Modular Women（10 个，Google Drive 能下） | 现代服装、纯色平涂的低多边形，没有中世纪服装 |

## 不用的来源

- 所有者 2026-09-27 发来的参考截图（疑似其他商业游戏画面）：只用来理解氛围，不进仓库、不作生成输入（`design/ART.md` 第一节）。
