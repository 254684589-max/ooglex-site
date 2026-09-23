# 《工地搬砖》ConstructionWorker V0.1

第三人称 3D 工地模拟 / 打工 / 生存 / 成长游戏。玩家从只有 300 元的临时工干起：找工头老王接活、
搬砖搬水泥扛钢筋、领工资、吃饭、睡觉，一天天在工地上成长。

- 引擎：Godot 4.7（标准版）· GDScript · Compatibility 渲染器（WebGL 2）
- 网页版：`/games/construction-worker/`（介绍页）→ `/games/construction-worker/play/`（游戏本体）
- 当前版本：**ConstructionWorker V0.1**（`godot/project.godot` 里 `config/version="0.1.0"`）

---

## 启动方法

### 1. 浏览器直接玩

打开网站的 `games/construction-worker/`，点「开始游戏」。首次需要下载约 40 MB（引擎 wasm 39.5 MB +
游戏包 1.3 MB；服务器开启压缩时实际传输约 11 MB），之后浏览器会缓存。存档保存在浏览器 IndexedDB 里。

本地预览（在仓库根目录）：

```bash
python3 -m http.server 8000
# 浏览器打开 http://localhost:8000/games/construction-worker/
```

### 2. Godot 编辑器（开发）

1. 安装 [Godot 4.7.x 标准版](https://godotengine.org/download)（不需要 .NET 版）。
2. 编辑器里「导入」→ 选择 `games/construction-worker/godot/project.godot`。
3. 按 F5 运行。编辑器里运行时开发者快捷键自动开启（见下文）。

### 3. VS Code

安装 `godot-tools` 插件，在插件设置里填 Godot 可执行文件路径，打开 `games/construction-worker/godot/`
文件夹即可获得 GDScript 补全、跳转和从 VS Code 启动游戏。脚本缩进用 Tab（见 `.editorconfig`）。

### 4. 自动化验收测试

无界面跑完整个 V0.1 游戏闭环（74 项检查，全部通过时退出码为 0）：

```bash
godot --headless --path games/construction-worker/godot res://tests/test_game_loop.tscn
```

测试覆盖：进入游戏 → 找老王 → 接任务 → 去砖堆 → 拿砖 → 搬砖（含卸货区外放下不算进度、捡回地上的砖、
熟练度 1→2→4 块）→ 完成任务 → 获得 ¥280 → 奔跑耗体力 → 去食堂用饭票换盒饭、买水 → 小卖部买手套 →
开宿舍门 → 睡觉 → 第二天 06:00 → 第二天可接三种任务 → 存档 / 读档 → 熬到凌晨 2 点累倒 → 回标题。

场景规模统计（网格数、顶点数、灯光）：

```bash
godot --headless --path games/construction-worker/godot res://tests/perf_stats.tscn
```

### 5. 重新构建网页版

需要 Godot 4.7.x 编辑器 + **同版本的导出模板**（只用到 `web_nothreads_release.zip`）。

```bash
GODOT=/path/to/Godot_v4.7.2-stable_linux.x86_64 games/construction-worker/tools/build_web.sh
```

脚本依次：导入资源 → 跑自动化测试 → 导出 Web（无线程版：GitHub Pages 不能设置跨源隔离响应头，
无线程版不需要）→ 用 `tools/stamp_web_build.py` 给文件名加内容哈希（`cw-<哈希>.wasm/.pck/.js`）
并放进 `play/`。改了游戏代码之后必须重新构建，`play/` 里才是新的。

---

## 游戏按键

| 电脑 | 作用 |
|---|---|
| W A S D / 方向键 | 移动 |
| Shift | 奔跑（消耗体力；扛超过 26 公斤跑不动） |
| 鼠标 | 转动视角（先点一下画面锁定鼠标） |
| 空格 | 跳跃（扛超过 20 公斤跳不起来） |
| E | 交互 / 对话 / 开门 / 买东西 / 睡觉 |
| F | 拿起材料（再按多拿一个）/ 在卸货区放下 / 在别处放在地上 |
| 鼠标左键 | 施工：在卸货区放下、在材料堆拿起（不会把东西丢在地上） |
| 鼠标右键（按住） | 拉近镜头，精确对准 |
| 滚轮 | 镜头远近 |
| 1 ~ 5 | 切换工具：徒手 / 劳保手套 / 独轮车 / 瓦刀 / 扳手（后三个 V0.1 未开放） |
| Tab | 任务与成长面板 |
| M | 工地图 |
| Esc | 暂停菜单（保存、读档、设置、操作说明）/ 关闭窗口 |
| 对话中 1 ~ 9 | 选择对话选项 |

| 手机 / 平板 | 作用 |
|---|---|
| 左下摇杆 | 移动 |
| 右半屏拖动 | 转动视角 |
| 交互 / 拿/放 / 跑 / 跳 | 对应 E / F / Shift（切换）/ 空格 |
| 右上角 任务 / 地图 / 菜单 | 对应 Tab / M / Esc |

### 开发者快捷键

编辑器里运行，或网页地址加 `?dev=1` 时开启：

| 键 | 作用 |
|---|---|
| F5 | 回到工地大门口 |
| F6 | 依次传送：老王 → 砖堆 → 砌筑作业面 → 水泥库 → 上料点 → 钢筋堆场 → 绑扎区 → 食堂 → 小卖部 → 床铺 |
| F7 | 时间 +1 小时 |
| F8 | 直接完成当前任务 |
| F9 | 体力 / 饥饿 / 水分回满，现金 +100 |
| F10 | 隐藏 / 显示全部界面 |

网页地址再加 `&fps=1` 显示帧率与绘制调用数，加 `&quiet=1` 不显示通知条（截图用）。

---

## 已经完成的功能（V0.1）

对照立项需求逐条：

1. **第三人称人物控制**：WASD 移动、Shift 奔跑、空格跳跃、鼠标镜头、E 交互、F 拿放、左键工作、Esc 暂停；
   平滑加减速、重力、碰撞、SpringArm 防穿墙的第三人称跟随镜头；右键瞄准拉近、滚轮缩放。
2. **3D 灰盒工地地图**（全部由代码用几何体生成，合批渲染）：工地大门（门卫室、旗杆、项目效果图）、
   项目部、1# 施工楼（五层半框架、楼梯间、施工电梯、安全通道）、砖块堆放区、水泥库、搅拌站与混凝土罐车、
   钢筋堆场与加工棚、模板堆、食堂、宿舍（可进入的 1 号宿舍、上下铺）、小卖部、凉茶桶、会转动的塔吊、
   南立面与东立面的双排脚手架和绿色安全网、蓝色施工围挡与安全标语、生活区隔离栏、城市街道和远处的城市楼群。
3. **NPC**：工头老王（发布任务、对话树）、工友大刘（新手教学，在砖堆和作业面之间来回搬砖）、
   食堂老板老陈（卖饭）；另有三位不能深聊的工友 / 门卫（会随机搭话）。NPC 被搭话时停下、转身面向玩家。
4. **搬砖任务**：砖块真实拿在手上（抱在胸前 / 扛在肩上），一次能拿的数量随「搬运」熟练度 1 → 2 → 4 → 6
   成长，越重走得越慢；只有走进黄框卸货区放下才计入进度（放在别处会留在地上，可以再捡起来）；
   卸货区显示放置预览与码放好的砖、进度「7 / 20」；完成后 ¥280 到账。
5. **体力系统**：100 点；走路消耗极低、奔跑持续消耗、搬运按重量额外消耗；体力过低走得慢、镜头晃动、
   屏幕暗角，耗尽后不能奔跑、拿不动东西；站着休息恢复。劳保手套减少 25% 搬运消耗。
6. **饥饿与水分**：随游戏时间下降，干重活下降更快；低于 20 时休息恢复体力变得很慢，归零时持续掉体力、走路变慢。
   食堂（盒饭、馒头、绿豆汤、矿泉水）、小卖部（水、冰红茶、面包、火腿肠、手套）、免费凉茶桶（有冷却）。
7. **经济系统**：初始 ¥300，任务报酬、购物扣钱、饭票（接搬砖活「管一顿饭」）、流水账、每日收支结算。
8. **时间系统**：一整天约现实 18 分钟；凌晨 / 早晨 / 白天 / 傍晚 / 夜晚，太阳、天空、雾、环境光随时间变化，
   夜里工地照明灯塔和远处城市的窗户亮起（食堂、宿舍的室内灯常亮）；晚上回宿舍睡觉恢复体力并进入第二天（白天也可以小睡一小时）；
   熬到凌晨 2 点会累倒，第二天 8 点才醒。
9. **通用任务系统**：任务 = 数据（`task_catalog.gd`）+ 目标事件（`TaskSystem.notify("deliver", …)`）；
   已有搬砖 / 搬水泥（完成搬砖后解锁）/ 搬钢筋（第 2 天起）三种；每日次数、解锁条件、声望都是数据字段。
10. **游戏 UI**：左上天数、时间、现金、饭票；左下体力 / 饥饿 / 水分（数值 + 「偏低 / 危险」文字）；右侧当前任务、
    进度条、报酬、目标；中央按键提示（E、F 可同时显示不同对象）；工具栏 1~5；通知条、大字横幅；
    Tab 任务与成长面板、M 工地图、对话框、商店、暂停 / 设置 / 操作说明、每日结算；引导箭头显示目标与距离。
11. **新手剧情**：标题画面 → 黑屏字幕开场 → 工地门口下车（大巴开走）→「你刚来到这座城市，身上只剩下 300 元。」
    → 找老王 →「一天 280，管一顿饭，干不干？」→ 选「干！」拿到安全帽和饭票、接到第一个搬砖任务。
12. **存档**：JSON 存档（现金、天数与时间、玩家位置朝向、手上的东西、任务进度、人物属性、技能、装备、剧情标记、
    地上的材料、卸货区码放、宿舍门）；自动存档（完成任务、睡觉、每 90 秒、切走标签页）+ 暂停菜单手动存读档；
    标题画面「继续游戏」显示存档摘要。
13. **模块化工程**：Player / NPC / Interaction / Inventory / TaskSystem / EconomySystem / TimeSystem /
    SaveSystem / UI 各自独立（见下方目录）。
14. **完整可玩**：没有任何外部美术素材，全部占位几何体；中文字体子集随包内置；音效为代码合成。
15. **验收闭环**：见「自动化验收测试」，并已在无头 Chromium（软件 WebGL）里实际跑过网页版：
    电脑键鼠与手机横屏触屏（摇杆移动、拖动转视角）都能操作。

额外：手机触屏操作与自动画质（关阴影 / 抗锯齿、3D 75% 分辨率、界面放大）、设置（灵敏度、反转、阴影、
抗锯齿、指引箭头、全屏）、合成音效、开发者快捷键。

## 尚未完成的功能

- 正式美术：人物、建筑都是几何体；没有骨骼动画（走路是程序化摆臂摆腿），没有贴图。
- 砌墙、抹灰、绑钢筋、支模板等「施工」玩法（左键施工目前只用于放下材料；瓦刀 / 扳手工具位未开放）。
- 独轮车、叉车、塔吊指挥等设备与载具。
- 天气（下雨停工、高温缺水）、夜班工资、随机事件（拖欠工资、检查、设备故障、工友受伤、赶工等）。
- 技能学习（泥瓦工、钢筋工、机械操作员……）只有「搬运」一项。
- 班组长 / 包工头阶段：招工、派工、买设备、接工程、成本与工期。
- 施工楼的楼上楼层不能进入（楼梯间封闭）；工程进度只体现在一层那面「每天长高一截」的砖墙上。
- 背景音乐与环境音；手柄支持；多存档位；英文界面。

## 后续版本规划

- **V0.2**：独轮车、叉车、砌墙玩法、工资日结、天气与随机事件。
- **V0.3**：工人招聘与班组系统（从自己搬 1000 块砖，到安排 10 个工人各搬 1000 块）。
- **V0.5 以后**：接工程、买设备、控制成本和工期，逐步变成「工地版人生模拟器」，最终参与建成全城最高的楼。

---

## 工程目录结构

```
games/construction-worker/
├── index.html                  # 网站介绍页（Ooglex 游戏专栏）
├── img/                        # 介绍页用的网页版实机截图
├── play/                       # Godot 网页导出（build_web.sh 生成，勿手改）
│   ├── index.html              #   加载页（由 godot/web/shell.html 生成）
│   └── cw-<哈希>.wasm/.pck/.js  #   引擎、游戏包、音频 worklet
├── tools/
│   ├── build_web.sh            # 一键：导入 → 测试 → 导出 → 放进 play/
│   ├── stamp_web_build.py      # 给导出文件加内容哈希
│   ├── build_font.py           # 生成中文字体子集（GB2312 常用字 + 源码用字）
│   └── gen_sfx.py              # 合成音效
└── godot/                      # Godot 4 工程（ConstructionWorker）
    ├── project.godot           # 工程设置、自动加载列表
    ├── export_presets.cfg      # Web 导出预设（无线程版）
    ├── web/shell.html          # 网页加载页模板
    ├── assets/
    │   ├── fonts/              # 思源黑体子集 + OFL 许可
    │   └── audio/              # 合成音效
    ├── scenes/
    │   ├── main.tscn           # 主场景：World / DayNight / TitleCamera / Player / UI
    │   └── player.tscn         # 玩家
    ├── scripts/
    │   ├── main.gd             # 游戏流程：标题 → 开场 → 干活 → 睡觉 → 第二天；存读档接线
    │   ├── core/               # InputSetup（按键注册）· ItemDB（材料表）· DevTools
    │   ├── systems/            # 自动加载单例
    │   │   ├── events.gd           # Events：全局信号总线
    │   │   ├── game_state.gd       # GameState：剧情标记、登记表、模态、设置、引导目标
    │   │   ├── economy_system.gd   # EconomySystem：现金、饭票、流水
    │   │   ├── time_system.gd      # TimeSystem：天数、时钟、昼夜阶段、睡觉
    │   │   ├── player_stats.gd     # PlayerStats：体力、饥饿、水分、技能、声望、装备、工具
    │   │   ├── task_system.gd      # TaskSystem：通用任务系统
    │   │   ├── save_system.gd      # SaveSystem：JSON 存档
    │   │   └── sfx.gd              # Sfx：音效
    │   ├── tasks/              # TaskDefinition（任务定义）· TaskCatalog（任务数据）
    │   ├── player/             # Player（控制）· PlayerCamera（第三人称镜头）· CharacterModel（人物模型与动画）
    │   ├── interaction/        # Interactable（交互物基类）· InteractionDetector（按键 → 交互对象）
    │   ├── inventory/          # Inventory（手上搬着的材料）
    │   ├── npc/                # NPC · NpcTalk · DialogueDB（对话数据与动作）
    │   ├── world/              # SiteBuilder（地图）· MeshBatcher（合批）· Mats（材质）· DayNight（昼夜）
    │   │                       # MaterialPile / DeliveryZone / DroppedStack / Door / SimpleInteractable
    │   │                       # ShopDB（商店数据）· ObjectiveMarker（引导箭头）
    │   └── ui/                 # UIRoot（界面总管）· HUD · DialogueBox · ShopPanel · TaskPanel · SiteMap
    │                           # Menus（暂停/设置/床铺/结算）· TitleScreen · StoryOverlay · TouchControls · Toasts · UIKit
    └── tests/                  # 自动化验收测试、场景规模统计（不会被导出）
```

## 怎么扩展

- **新增任务**：在 `scripts/tasks/task_catalog.gd` 的 `TASKS` 里加一条字典即可。例如「推独轮车送砂」：
  `{"id": "haul_sand", "title": "推砂", "reward": 150, "objectives": [{"type": "deliver", "item": "sand", "zone": "sand_zone", "count": 5}]}`。
- **新增玩法事件**：让场景物体调用 `TaskSystem.notify("lay_brick", {"zone": "wall_1", "count": 1})`，
  任务里写 `{"type": "lay_brick", "zone": "wall_1", "count": 30}`，任务系统不用改。
- **新增材料**：`scripts/core/item_db.gd` 里加一条（重量、每级容量、外观），地图里放一个 `MaterialPile` 和 `DeliveryZone`。
- **新增 NPC 对话**：`scripts/npc/dialogue_db.gd` 里加节点；NPC 站位在 `site_builder.gd` 的 `_npc_defs()`。
- **新增商品**：`scripts/world/shop_db.gd`。
- **改地图**：`scripts/world/site_builder.gd`（所有坐标以米为单位，X 向东、Z 向南）。
- **换正式美术**：`CharacterModel` 保留 `animate()` / `set_hat()` / `set_carry_pose()` 接口即可替换成骨骼模型；
  地图物体替换 `SiteBuilder` 里对应的方块。
- 代码里新增了生僻汉字后，重新跑 `tools/build_font.py` 生成字体子集，否则会显示方框。

## 素材与许可

- 中文字体：Noto Sans SC（思源黑体）子集，SIL Open Font License 1.1，见 `godot/assets/fonts/OFL.txt`。
- 音效：`tools/gen_sfx.py` 代码合成，无第三方素材。
- 游戏中的「宏远建设」「滨江中心」等公司与项目名称均为虚构。

## 版本记录

- **V0.1**（2026-09-23）：首个可玩版本，完成「进入游戏 → 找老王 → 接任务 → 搬砖 → 领工资 → 食堂买饭 →
  回宿舍睡觉 → 第二天」完整闭环，网页版上架 Ooglex 游戏中心。
