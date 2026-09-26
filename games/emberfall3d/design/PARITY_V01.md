# V0.1 → 3D 版对齐清单（步骤 P12）

> 2026-09-26。逐项对照 V0.1（`games/emberfall/play/game.js`，1967 行）的每个功能，写明 3D 版在哪里实现、是否一致、用哪组自动化测试验证。
> 「✅ 一致」= 规则与数值照搬；「≈ 等效」= 玩法相同、表现方式不同（写明差异）；「✗ 未做」= 3D 版没有。
> 结论在最后一节。

## 一、数据与规则

| V0.1 | 3D 版 | 状态 | 验证 |
|---|---|---|---|
| 25 种底材、16 种词缀、11 件传奇、稀有名（BASES / AFF / UNIQ / RARE_*） | `data/act1_items.json`、`rules/item_gen.gd` | ✅ | port 组逐项对照 V0.1 公式输出 |
| 物品价格、卖价 1/4（itemValue / sellValue） | `ItemGen.value` / `sell_value` | ✅ | port、town |
| 10 种怪物、5 种精英、楼层换算（MT / CHAMP / spawnMon） | `data/act1_monsters.json`、`FloorRules.scale_monster` | ✅ | port、loot、save（深渊） |
| 成长：经验、升级、属性点、生命法力、回复（newHero / xpNeed / calcStats / gainXp） | `rules/hero_stats.gd`、`HeroProgress` | ✅ | port、growth |
| 护甲减伤（drAgainst：护甲 /（护甲 + 40 + 18 × 等级），上限 75%） | `DamageCalc.armor_reduction`（balance.json 同参数） | ✅ | damage |
| 暴击 ×2、生命偷取 | `HeroProgress.combat_stats`、`Player._resolve_action` | ✅ | growth、skills |
| 伤害掷骰 | V0.1 取整数，3D 版取连续值再四舍五入 | ≈ 平均值相同 | damage |
| 掉落（dropLoot，含首领、精英） | `FloorRules.roll_loot` | ✅ | loot、bosses |
| 宝箱、木桶、神殿（useProp、SHRINES） | `FloorRules.roll_chest` / `roll_barrel`、`main._use_prop` | ✅ | props |
| 商店进货（refreshShops）、买卖（buy / openShop） | `FloorRules.refresh_shop`、`ui/shop_panel.gd` | ✅ | town |

## 二、世界

| V0.1 | 3D 版 | 状态 | 验证 |
|---|---|---|---|
| 烬原镇手工布局（genTown） | `rules/town_gen.gd`、`world/town_builder.gd` | ✅ | town |
| 随机地下城：房间、走廊、首领房、楼梯、火把、装饰（genDungeon） | `rules/dungeon_gen.gd`、`world/dungeon_builder.gd` | ✅ | dungeon |
| 房间里的怪物群、道具（genDungeon「房间内容」） | `DungeonGen._room_packs` / `_room_props` / `_boss_pack` | ✅ | loot、props、bosses |
| 四种主题、第 7 层起无尽深渊、每 5 层深渊首领（THEMES / themeFor / isBossFloor） | `FloorRules.theme_for` / `is_boss_floor` | ✅ | dungeon、save |
| 同一局里楼层保留：打死的怪不再刷、地上的东西还在（maps） | `main.floor_state`（P12 补上） | ✅ | parity |
| 视野与战争迷雾（computeVis） | `rules/fog.gd` 逐格视线；显示按 4 × 4 格的区块展开 | ≈ 视线规则相同；V0.1 按格子画明暗，3D 版按区块显示，「看见过但不在视野里」不额外压暗 | props |
| 照明范围（S.light，「明亮的」词缀） | 主角身上的光与视野半径 | ✅ | props |
| 小地图、自动地图（drawMinimap、Tab） | `ui/minimap.gd` | ✅ | quests |

## 三、战斗与怪物

| V0.1 | 3D 版 | 状态 | 验证 |
|---|---|---|---|
| 点怪攻击、按住连打、原地攻击（Shift） | `Player.click_at`、`stand_attack`（Shift 在 P12 补上） | ✅ | combat、parity |
| 四个技能：火球术、烬环斩、寂霜环、暗影闪现（SK / castSkill / autoAim） | `Player.cast_skill` / `_resolve_action`、`combat/fireball.gd` | ✅ | skills |
| 近战、弓手（保持距离）、术士（瞬移）、猎犬、骑士（updMon / chase / shoot / blinkAway） | `actors/enemies/*` | ✅ | monsters、loot |
| 精英五种特性 | `EnemyBase` | ✅ | loot |
| 首领莫格：冲锋、暴怒；摩登：扇形弹、火环、召唤、瞬移、二阶段（bossAI / bossShout / bossDown） | `enemy_boss_mog.gd` / `enemy_boss_abbot.gd` | ✅（莫格冲锋前多了 0.35 秒红色预警，按 GDD「只看画面就能躲」） | bosses |
| 怪物被挤开、不挡主角（separate） | `EnemyBase._separation` | ✅ | loot |
| 倒下掉 10% 金币、在镇上复活（die） | `Player._die`、`main` 复活回镇 | ✅ | growth、town |
| 尸体 | V0.1 尸体留在地上；3D 版倒下后约 2 秒烧穿消散（阶段 2.5 溶解特效） | ≈ 仅表现 | fx |
| 目标信息 | V0.1 屏幕上方目标框；3D 版怪物头顶名字与血量、屏幕下方首领血条 | ≈ | bosses |
| 粒子、飘字（burst / ftext） | `combat/fx.gd` 粒子与地面痕迹（阶段 2.5）、伤害数字 | ≈ 仅表现 | combat、fx |

## 四、镇上、任务与移动

| V0.1 | 3D 版 | 状态 | 验证 |
|---|---|---|---|
| 伊莲、格伦、玛拉，对话与话题（talk / dialog） | `main._talk`、`data/act1_dialogs.json`、`ui/dialog_panel.gd` | ✅ | town、quests |
| 伊莲免费治疗、水井 | 同 | ✅ | town、quests |
| 三条任务、头顶「!」「?」、奖励、托比、结局（questLog / npcMark / spawnToby / epilogue） | `rules/quests.gd` | ✅ | quests、bosses |
| 任务日志 | V0.1 在角色面板里；3D 版单独面板（J） | ≈ | quests |
| 回城卷轴传送门（castTownPortal / usePortal） | `main.cast_town_portal` / `use_portal` | ✅ | quests |
| 传送石（openWaypoint） | `main.open_waypoint`（首领层标「（首领）」，字体里没有 V0.1 的骷髅符号） | ✅ | quests |

## 五、界面、存档与声音

| V0.1 | 3D 版 | 状态 | 验证 |
|---|---|---|---|
| 背包、装备、比较（openInv / equip / unequip / itemHtml / delta） | `rules/inventory.gd`、`ui/inv_panel.gd` | ✅ | inventory |
| 角色面板与加点（openChar） | `ui/char_panel.gd` | ✅ | growth |
| 按键：Q / E / T / I（B）/ C / Tab / M / Esc / 1–4 / 右键 / WASD | `core/input_setup.gd`（B 键在 P12 补上；另加 J 任务、F7 画质） | ✅ | parity 等 |
| 手机：摇杆、攻击、四技能、血 / 蓝 / 城、右上角按钮 | `ui/touch_controls.gd`、`main._touch_button` / `_top_button` | ✅ | 网页冒烟（360 宽） |
| 菜单：继续、保存、音效、操作说明、返回介绍页、删除存档（openMenu / helpHtml） | `main.open_menu` / `help_lines`（操作说明在 P12 补上） | ✅ | save、parity |
| 没有药水的提示 | `Player.drink_potion`（P12 补上） | ✅ | parity |
| 存档与读档、每 30 秒 / 换层自动存（saveGame / loadGame） | `rules/save_game.gd`（键名与 V0.1 分开） | ✅ | save |
| 读取 V0.1 经典版存档 | `SaveGame.parse_v01`：没有 3D 存档时开局询问是否带过来（P12 新增，经典版存档不改动） | ✅（3D 版多出的能力） | parity |
| 标题画面（继续 / 新游戏 / 说明） | 有存档时开局对话框；没有存档直接开始；说明在菜单里 | ≈ | save |
| 25 种合成音效（Snd） | `core/sfx.gd` 配方照搬 | ✅（受伤音效 V0.1 是 50% 概率播放，3D 版每次都播，同一音效 40 毫秒内不重复） | save |
| 减少动态效果（prefers-reduced-motion 时不震屏） | 网页版读取系统设置后关闭震屏（P12 补上） | ✅ | 未自动化（需要浏览器设置） |

## 六、结论

- **玩法层面已经覆盖 V0.1 的全部功能**；P12 补上了排查出来的 6 处缺口：Shift 原地攻击、B 键、没药提示、菜单里的操作说明、减少动态效果时不震屏、同一局里楼层状态保留。另外新增导入经典版存档。
- **仍然不如 V0.1 的地方是画面**：3D 版的人物、怪物、建筑都是占位几何体（阶段 3「画质切片」才替换）；V0.1 的 2.5D 手绘画面目前看起来更完整。另外 3D 版需要 WebGL 2 与约 40 MB 下载，V0.1 在几乎所有浏览器上都能直接玩。
- **是否由 3D 版接管 `/games/emberfall/`（D4）由所有者决定**，见路线图「所有者的决定」。
