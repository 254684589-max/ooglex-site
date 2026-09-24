# 架构说明 · 打工 WORKING LIFE 1.0

## 分层
```
data/*.json  ──►  DataDB（读取全部内容数据）
                     │
自动加载管理器（规则）  GameManager · TimeManager · WeatherManager · EconomyManager · SkillManager · PlayerManager
                     HousingManager · JobManager · NPCManager · QuestManager · EventManager · InvestmentManager
                     BusinessManager · TransportManager · AudioManager · SaveManager · SettingsManager · Events（信号总线）
                     │  只通过 Events 信号与公共函数互相调用，不持有场景节点
场景（表现）          core/main.gd（流程编排）· CityBuilder / BuildingKit（城市）· Player · NPC / Crowd · DayNight · WeatherFX · Traffic · Train
                     │
界面                 UIRoot（窗口栈、快捷键、鼠标锁定、事件弹窗）· HUD · PhoneWindow + phone/*App · 各种 UIWindow · 小游戏
```

## 自动加载（project.godot 中的顺序）
| 名称 | 文件 | 职责 |
|---|---|---|
| Events | autoload/events.gd | 全局信号总线；`Events.notify(kind, data)` 推进任务 |
| DataDB | autoload/data_db.gd | 读取 data/*.json；按 id 查询 |
| SettingsManager | autoload/settings_manager.gd | 设置读写与应用（user://settings.cfg） |
| GameManager | autoload/game_manager.gd | 游玩状态、模态计数、剧情标记、章节、登记表、结局记录、调试开关 |
| TimeManager | autoload/time_manager.gd | 游戏时钟（一天≈22 分钟）、日历、倍速、`advance()` 逐小时快进 |
| WeatherManager | world/weather_manager.gd | 晴 / 阴 / 雨 |
| EconomyManager | economy/economy_manager.gd | **唯一**修改现金与存款的地方：earn / spend / deposit / withdraw / charge；流水、月统计、净资产、被动收入、利息 |
| SkillManager | skills/skill_manager.gd | 六项技能经验与等级 |
| PlayerManager | player/player_manager.gd | 属性、背包、储物柜、服装、耐用品、昏倒检测 |
| HousingManager | housing/housing_manager.gd | 旅馆按晚、月租、押金、欠租、储物 / 睡眠 / 体面度 |
| JobManager | jobs/job_manager.gd | 统一职业系统：招聘、面试、录用、班次、迟到、请假、旷工、绩效、工资、奖金、升降职、辞退 |
| NPCManager | npc/npc_manager.gd | 关系、闲聊 / 送礼次数、帮助（perks）、日程（整点刷新，不逐帧） |
| QuestManager | quests/quest_manager.gd | 通用任务：事件型与条件型目标、顺序 / 并行、奖励、下一任务、任务物品 |
| EventManager | events/event_manager.gd | 随机事件：按时段概率触发、权重、冷却、条件、选项、延迟效果 |
| InvestmentManager | investment/investment_manager.gd | 五种虚构资产、经济周期、日波动、持仓 / 成本 / 盈亏、分红 |
| BusinessManager | business/business_manager.gd | 公司：员工、产能、项目、预算、设备、分红、阶段、破产 |
| TransportManager | transport/transport_manager.gd | 公交 / 地铁 / 出租车 |
| AudioManager | audio/audio_manager.gd | Music / SFX / Ambience 总线，音乐、两层环境声、音效池 |
| SaveManager | save/save_manager.gd | 3 个存档槽 JSON，汇总各管理器的 to_dict / from_dict |

## 通用规则类（core/）
- `Conditions.check(dict)`：任务接取条件、事件条件、结局条件、交通解锁共用一套写法（支持 any / all）。
- `Effects.apply(dict)`：任务奖励、事件结果、对话选项共用；金钱一律经 EconomyManager。
- `EndingSystem`：按 data/endings.json 判定已达成结局与推荐结局。
- `ServiceRouter`：交互点（ServicePoint.kind）的提示文字与行为表。
- `InputSetup`：代码注册全部输入动作。

## 任务目标类型
事件型（`Events.notify`）：visit talk buy eat_at apply_job interview_pass work_shift earn sleep course read workout
treatment invest deposit practice project_done pickup deliver interact。
条件型（状态变化后节流重算）：skill relation rent job_level reputation bank cash networth have_item employees
invest_or_business ending_ready invest_profit get_job promote。

## 世界生成
`CityBuilder.build()`：地面与道路 → 按 locations.json 的 type 调用模板（shop / tower / home / station / park / site /
warehouse / oldtown）→ 填充高楼 → 公交地铁站、售货机、街道设施、高架轨道、远景天际线、边界墙 → MeshBatcher 合批 →
4 米网格导航网格。几何体按「材质 × 96 米格子」合批（约 375 个网格节点）；夜间专用几何单独一组，昼夜切换时整组显隐。
另有：人行道棕榈树与路边停车（`_palms_and_parking`）、两圈远景高楼 + 城郊 + 远山（`_skyline` / `_mountains`）。

## 画面
- 材质（`world/mats.gd`）：城市几何体用顶点色 + 十几种批次材质；立面 `fac_glass / fac_office / fac_res / fac_cyber`
  用 `world/proc_tex.gd` 生成的贴图，UV 是世界坐标（竖直面 `(x+z, y)`、水平面 `(x, z)`，单位米），
  夜间灯光走自发光贴图，亮度由 `Mats.set_window_energy()` 随昼夜调整。
- 天空（`world/sky.gdshader` + `world/day_night.gd`）：渐变、日轮、云、星星；AgX 色调映射、雾（太阳散射 + 大气透视 + 高度雾）、泛光。
- 人物（`player/character_model.gd`）：每个关节的零件合并成一个顶点色网格 + 一个发光网格。
- 地面交通（`world/street_traffic.gd`）：每种车漆一个多材质网格，所有车共享。
- 路灯（`BuildingKit.streetlight` + `world/lamp_pool.gd`）：灯罩用 `lamp_warm / lamp_cool` 材质，亮度 `Mats.lamp_energy` 随昼夜变化；
  真实点光源只放在离相机最近的几盏路灯下，每 0.4 秒重选。
- 环境光遮蔽：`MeshBatcher._tri` 把竖直面贴地部分的顶点色压暗（发光、透明类材质除外）。

## 性能手段
信号驱动（HUD 0.2 秒刷新、任务条件 0.4 秒节流、NPC 整点换日程）；Resources/JSON 数据；自动加载单例；对象池（路人、音效播放器）；
LOD（小物件、树叶、标签、人物、空中与地面车辆按距离隐藏）；遥远 NPC 直接瞬移不寻路；遮挡剔除（桌面版大楼遮挡体）；
NPC 与路人不投射阴影；触屏 / 低画质降低 3D 分辨率、关泛光、减少路人与车辆。

## 存档格式
`{version, game, saved_at, unix, summary, game_state, time, weather, economy, skills, player_stats, housing, jobs, npcs,
quests, events, investment, business, player{pos, yaw, cam_yaw}}`，JSON 文本，版本号 1。

## 测试
`tests/parse_all.gd`（加载全部脚本）、`tests/test_runner.gd`（21 组、303 项）、`tests/shots.gd` / `site_shots.gd` / `vis_shots.gd`（截图）、
`tests/perf_stats.gd`（绘制调用统计）。见 TEST_REPORT.md。
