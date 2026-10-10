extends Node3D
## 《铁冠之争》主场景（阶段 1.4：霜渡镇主街）。
## 默认是霜渡镇主街（world/frostford.gd）；网页 ?test=1 或 use_test_range = true 打开灰盒测试场（台阶、斜坡、窄门、矮洞、交互）；
## ?test=2 或 use_arena = true 打开训练场（2.5：三个无旗者，练格挡与近战）。
## ?test=3 打开军阵试验场（B.1，D8：白带对黑带各 10 人，你站在白带一边；&n=30 每边 30 人），开局 3 秒后开打。
## 3.1 起有多个区域（world/areas.gd）：主街、「倒钩鱼」酒馆……；走进通往别处的门 = travel()：淡出、记下去哪、重新载入本场景、
## 放到命名出生点、淡入、自动存档（GDD 第十节：进入新区域时）。网页 ?area=tavern 直接从酒馆开始（截图与冒烟测试用）。
## 网页参数：?q=low|medium|high 强制画质档；?view=0|1|2 从固定机位开始（截图用）；
## ?area=ferry&ending=deliver|release|extort 直接显示结束画面（3.7，截图与冒烟测试用；不改存档与旗标）。
## ?area=tavern&brawl=1 一进酒馆就和醉汉「大桶」打起来（3.3，截图与冒烟测试用；不设旗标）。
## ?perf=1 打开性能浮层并自动跑基准测试（依次在 3 个机位各测 3 秒，结果表显示在画面上，1.5）；?perf=1&view=N 只在该机位测一次（截图工具用）。
## 军阵试验场 ?test=3&n=30&perf=1：60 人开打后在观战台、两军之间各测一次，结果表显示在画面上（B.5，真机用；你不参战、不自动存档）。
## NPC 与敌人仍是占位胶囊，界面上明确标注（主角的第三人称人物在 A.1 换成了模型）。
##
## 鼠标：电脑上点击画面锁定指针（浏览器只允许在点击后锁定）；Esc 或浏览器释放锁定时打开暂停菜单，
## 不会自己把鼠标抢回来（TECH.md 4.1）。触屏设备不锁定鼠标，用 TouchControls。

const FOG_COLOR := Color("22344a")              # 夜空与远雾（ART.md 第四节 #1C2A3A 提亮一点，远处是「雾」而不是「黑」）
const AMBIENT_COLOR := Color("6f8faf")          # 月光 / 环境光
const HINT_DESKTOP := "点击画面开始 · WASD 移动 · 鼠标转视角 · E 交互 · 左键 / F 出剑（按住是重击）· R 收剑 · V 切换视角 · Shift 跑 · C 蹲下 · 空格 跳 · Esc 暂停"
const HINT_TOUCH := "左半屏拖动走路（推到底是跑）· 右半屏拖动转视角 · 点「攻」出剑（按住是重击）· 「视角」切换第一 / 第三人称 · 对准东西时点交互按钮"
const HINT_ARENA_DESKTOP := "训练场：左键 / F 出剑（按住重击）· 右键 / Q 按住格挡 · 在对方劈下前一瞬间举剑 = 完美格挡（对方失衡）· WASD 移动 · Esc 暂停"
const HINT_ARENA_TOUCH := "训练场：点「攻」出剑（按住重击）· 按住「挡」格挡 · 在对方劈下前一瞬间按「挡」= 完美格挡（对方失衡）"
const HINT_BRAWL_DESKTOP := "徒手打一架（不许动刀）：左键 / F 出拳，按住是重拳 · 右键 / Q 按住格挡 · 把对方打到认输就赢"
const HINT_BRAWL_TOUCH := "徒手打一架（不许动刀）：点「攻」出拳，按住是重拳 · 按住「挡」格挡 · 把对方打到认输就赢"
const HINT_BATTLE_DESKTOP := "军阵试验场：白带是你这边，黑带是对面，3 秒后开打 · 头顶有 ◆ 的 6 个人听你指挥：1 跟随我 · 2 原地坚守 · 3 冲锋 · 左键 / F 出剑 · 右键 / Q 格挡 · 你的剑砍不到白带"
const HINT_BATTLE_TOUCH := "军阵试验场：白带是你这边，黑带是对面，3 秒后开打 · 头顶有 ◆ 的 6 个人听你指挥：点「令」选跟随 / 坚守 / 冲锋 · 你的剑砍不到白带"
const BATTLE_DELAY := 3.0         # 军阵试验场开局几秒后开打（B.1）
const BATTLE_BENCH_WARM := 3.0    # 军阵基准测试：开打几秒后开始测（两军已经接上）（B.5）
const BATTLE_BENCH_SAMPLE := 4.0  # 每个机位测几秒
const BATTLE_BENCH_VIEWS := [1, 2]   # 观战台上（看全场）、两军之间（贴近混战）
const HINT_SECONDS := 8.0
const FADE_TIME := 0.25           # 换区域时淡出 / 淡入（减少动态效果时直接切）
const CH1_LATER := "想好了就去星铁小教堂找奥尔本修士——第一章 · 黑鹭堡从那里出发。"   # 序章打完还没进第一章时（4.3）

@export var use_test_range := false
@export var use_arena := false
var battle_autostart := true      # 军阵试验场开局自动开打（B.1；测试里关掉，自己调 battle.start()）

var moon: DirectionalLight3D
var quality := ""
var perf_overlay: PerfOverlay
var dialogue: DialoguePanel
var quest_panel: QuestPanel
var bench_results: Array = []
var battle_bench := false         # 军阵基准测试在跑（B.5）：军阵的提示不弹出来，免得盖住结果表

var env: Environment
var world: Node3D
var player: FpController
var camera: Camera3D
var hud: Hud
var touch: TouchControls
var pause_menu: PauseMenu
var defeat_panel: DefeatPanel
var ending_panel: EndingPanel    # 结束画面（3.7）
var packs: PackLoader            # 章节资源包（4.1）
var pack_panel: PackPanel        # 章节包的下载画面（4.1）
var pack_answer := ""            # 下载失败时玩家点的：retry / cancel
var travel_map: TravelMap        # 旅行地图（4.2）
var map_panel: MapPanel          # 地图册的「本地」「一带」两页（3.11）；第三页「北境西部」是 travel_map
var map_departure := false       # 这次打开地图册时能不能出发（从路牌打开的才能；切走再切回「北境西部」照旧）
var leaving := false             # 已经出发、正在淡出换区域（4.2）：这时不再打开地图
var playable_chapter := Chapters.PLAYABLE   # 做到第几章能玩了（4.1；网页 ?preview=1 预览下一章的入口，测试里也改它）
var touch_was_visible := false   # 结束画面打开前触屏按钮是否显示（关掉后还原）
var touch_hidden_by_dialogue := false   # 对话打开时藏起了触屏按钮（对话结束时还原）
var opening: Opening             # 开场（3.8）：只在新游戏时有
var title_card: TitleCard        # 开场的标题卡（3.8）
var tip_queue: Array = []        # 等着显示的教学提示编号（3.8；有界面开着、上一条还没消失时排队）
var tip_now := ""                # 底部正在显示的教学提示（空 = 显示的是别的提示或什么都没有）
var inventory_panel: InventoryPanel
var loot_panel: LootPanel
var char_panel: CharacterPanel
var touch_mode := false
var spawn := Vector3.ZERO
var yaw0 := 0.0
var moved_logged := false
var look_logged := false
var lock_seen := false          # 指针真的锁定过（锁定失败时不要误开暂停菜单）
var hint_left := HINT_SECONDS
var started := false
var use_screen_logged := false
var save_panel: SavePanel
var loaded_from := ""           # 这次是从哪个栏位读档进来的（空 = 新游戏）
var area := "frostford"         # 现在所在的区域（Areas.NAMES；3.1）
var arrived_by := ""            # 从门走进来的（换区域）时是出生点名字；读档 / 新游戏时为空
var fade: ColorRect
var brawl: Brawl                # 正在打的一架（3.3）；打完自己释放
var encounter: Encounter        # 正在打的对峙（3.6，渡口的「灰手」奥弗）
var dialogue_npc: Node3D        # 最近一次对话的说话人（对话里说好打一架时，和他打）
var nav := {}                   # 这个区域的导航网格（3.4）：{region, ms, polygons}；不烘焙的区域为空
var battle: Battle              # 这个区域里的军阵战斗（B.1：军阵试验场）；没有为空
var daypart := "night"          # 这个场景实际在用的时段（4.2，Daypart.effective：室内、测试场永远是夜）
var streamer: ChunkStreamer     # 连片地图的分块搭建（4.4 鹭沼）；别的区域为空

signal reload_requested         # 测试里 main 不是当前场景，读档时改发这个信号


func _ready() -> void:
	touch_mode = DisplayServer.is_touchscreen_available()
	var pending := GameState.pending_load
	GameState.pending_load = {}
	GameState.pending_brawl = {}
	GameState.pending_fight = {}
	GameState.pending_leave = ""
	GameState.pending_ending = ""
	tip_queue = GameState.pending_tips.duplicate() if pending.has("spawn") else []    # 从门走进来：没轮到的教学提示接着排
	GameState.pending_tips = []
	if OS.has_feature("web"):
		if _query("test") == "1":
			use_test_range = true
		elif _query("test") == "2":
			use_arena = true
		elif _query("test") == "3":
			area = "battle"
		elif Areas.known(_query("area")):
			area = _query("area")
		if Daypart.valid(_query("daypart")) and not Engine.has_meta("ic_daypart_param_done"):
			Engine.set_meta("ic_daypart_param_done", true)   # 截图、预览用（4.2）：?daypart=dawn|day|dusk|night，每次打开页面只用一次——
			GameState.daypart = _query("daypart")          # 之后读档、进章、走地图改的时段不再被它盖掉（审查发现）
		# 系统设置了「减少动态效果」：默认关掉镜头摆动（GDD.md 第四节）；玩家自己存过设置就听玩家的
		if str(JavaScriptBridge.eval("!!(window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches)", true)) == "true":
			Settings.reduced_motion = true
			if not Settings.loaded:
				Settings.head_bob = false
			print("IC_REDUCED_MOTION")
	if Daypart.valid(str(pending.get("daypart", ""))):
		GameState.daypart = str(pending.daypart)   # 走旅行地图到了：路上过了大半天（4.2；出发时不改，免得半路存档存成「人还在原地、时辰已经到了」）
	if not pending.is_empty():           # 读档 / 换区域：场景以它为准（2.8、3.1）
		area = str(pending.scene) if Areas.known(str(pending.scene)) else "frostford"
		use_arena = area == "arena"
		use_test_range = area == "test_range"
	elif use_arena:
		area = "arena"
		use_test_range = false
	elif use_test_range:
		area = "test_range"
	_build_environment()
	world = Node3D.new()
	world.name = "World"
	add_child(world)
	var t: Transform3D
	match area:
		"arena":
			t = CombatArena.build(world)
		"test_range":
			t = TestRange.build(world)
		"tavern":
			t = Tavern.build(world, Settings.reduced_motion)
		"churchyard":
			t = Churchyard.build(world, Settings.reduced_motion)
		"chapel":
			t = Chapel.build(world, Settings.reduced_motion)
		"birch":
			t = Birch.build(world, Settings.reduced_motion)
		"ferry":
			t = Ferry.build(world, Settings.reduced_motion)
		"marsh":
			t = Marsh.build(world, Settings.reduced_motion)
		"battle":
			t = BattleArena.build(world, int(_query("n")) if _query("n").is_valid_int() else BattleArena.PER_SIDE)
		_:
			t = Frostford.build(world, Settings.reduced_motion)
	# 导航网格（3.4）：区域搭好、玩家还没放进去之前烘焙（玩家不是静态碰撞体，本来也不会被算进去）
	var nb := Areas.nav_bounds(area)
	if nb.has_volume():
		nav = NavBuilder.bake(world, nb)
		print("IC_NAV area=%s ms=%.0f polygons=%d" % [area, nav.ms, nav.polygons])
	# 时段（4.2）：区域搭好以后套光（窗户、夜灯、雾带都在了）；画质在后面（月光阴影、泛光开关、雾带减半归画质）
	daypart = Daypart.effective(area, GameState.daypart)
	Daypart.apply(self, daypart)
	print("IC_DAYPART id=%s area=%s" % [daypart, area])
	player = FpController.new()
	player.name = "Player"
	add_child(player)
	player.global_transform = t
	camera = player.camera
	camera.make_current()
	var view := _query("view")
	if view.is_valid_int() and int(view) >= 0 and int(view) < Areas.views(area).size():
		set_view(int(view))
	var cam := _query("cam").split(",")           # 截图用（3.10）：?cam=x,y,z,朝向,俯仰（度）把镜头放到任意位置，检查出口和区域边界
	if cam.size() == 5 and Array(cam).all(func(c): return str(c).is_valid_float()):
		player.global_position = Vector3(float(cam[0]), float(cam[1]), float(cam[2]))
		player.rotation.y = deg_to_rad(float(cam[3]))
		player.pitch = float(cam[4])
		player.head.rotation.x = deg_to_rad(float(cam[4]))
		player.set_physics_process(false)        # 镜头定住：区域外面的地面没有碰撞，不定住会掉下去（只截图用，走不了）
	if not pending.is_empty():
		if pending.has("spawn"):              # 从门走进来：站到那扇门对应的出生点
			arrived_by = str(pending.spawn)
			var st: Variant = Areas.spawn(area, arrived_by)
			if st != null:
				player.global_transform = st
		_restore_player(pending.get("player", {}))
		loaded_from = str(pending.get("slot", ""))
	var want_opening := Opening.wanted(self, pending, _query)
	if want_opening:                     # 开场（3.8）：站在领主宅邸门口
		var st: Variant = Areas.spawn(area, "manor")
		if st != null:
			player.global_transform = st
	_prime_chunks()
	spawn = player.global_position
	if _query("preview") == "1":
		playable_chapter = maxi(playable_chapter, 1)
	elif _query("preview") == "0":
		playable_chapter = 0                     # 截图、冒烟用：看第一章开放以前的结束画面（只有两个按钮，4.3）
	_place_chapter_content()
	yaw0 = player.yaw_deg()
	_build_ui()
	var q := _query("q")
	apply_quality(q if q in Look.TIERS else (Settings.quality if Settings.quality in Look.TIERS else Look.default_tier()))
	print("IC_READY renderer=%s web=%s scene=%s touch=%s quality=%s size=%s" % [
		ProjectSettings.get_setting("rendering/renderer/rendering_method"), OS.has_feature("web"),
		scene_name(), touch_mode, quality, get_viewport().get_visible_rect().size])
	if arrived_by != "":
		_arrive()
	if want_opening:
		opening = Opening.new()
		opening.name = "Opening"
		opening.main = self
		add_child(opening)
		hud.set_hint("")                 # 操作说明改由开场开始后的教学提示给
		hint_left = 0.0
		opening.start(title_card, touch_mode)
	if area == "birch" and GameState.chapter == 0:     # 桦林（3.5）：拿武器战斗的教学提示（STORY 第三节「教学：拿武器战斗、格挡、体力」）；第一章哨卡的事已经过去了
		hud.set_hint(Birch.TEACH_TOUCH if touch_mode else Birch.TEACH_DESKTOP)
		hint_left = HINT_SECONDS * 1.5
	if _query("ending") in EndingPanel.RECAP and arrived_by == "" and loaded_from == "":     # 只在打开页面时：换区域、读档以后地址还带着它，不再弹（4.1 实测）
		show_ending.call_deferred("prologue", _query("ending"))
	if _query("map") == "1" and GameState.chapter >= 1 and not Engine.has_meta("ic_map_param_done"):
		Engine.set_meta("ic_map_param_done", true)     # 截图、冒烟用（4.2）：第一章起直接打开一次旅行地图（每次打开页面只开一次）
		open_travel_map.call_deferred(near_travel_point())
	battle = world.get_node_or_null("Battle") as Battle
	if battle:
		battle.ended.connect(_on_battle_ended)
		hud.battle = battle                 # 右上角：小队一行（B.2）、战况一行（B.3）
		if not battle.squad.is_empty():     # 有小队（B.2）：触屏多一个「令」
			touch.order_enabled = true
			touch.order_pressed.connect(give_order)
		battle.captain_down.connect(func(side: String):
			if not battle_bench: hud.toast("◆ %s的队长倒下了！" % battle.sides.get(side, side), 3.0))
		battle.routed_side.connect(func(side: String):
			if not battle_bench: hud.toast("◆ %s溃逃了！" % battle.sides.get(side, side), 3.0))
		battle.wave_arrived.connect(func(side: String, count: int):
			if not battle_bench: hud.toast("◆ %s来了 %d 个援军" % [battle.sides.get(side, side), count], 3.0))
		if battle_autostart and _query("perf") != "1":       # 基准测试自己开打（不存档）
			get_tree().create_timer(BATTLE_DELAY).timeout.connect(func():
				if is_instance_valid(battle) and not battle.started:
					start_battle())
	if area == "tavern" and _query("brawl") == "1":
		var dagu := _npc_by_dialogue("dagu")
		if dagu:
			start_brawl.call_deferred(dagu, {"brawl": "drunk"})
	if _query("perf") == "1":
		await get_tree().create_timer(2.0).timeout
		if streamer and not streamer.is_done():
			await streamer.all_built                  # 连片地图（4.4）：分帧搭完再测（不然测的是半张图）
		if battle:
			if view == "":
				Settings.set_value("show_perf", true)
			var secs := float(_query("probe")) if _query("probe").is_valid_float() else BATTLE_BENCH_SAMPLE
			await run_battle_benchmark(int(view) if view.is_valid_int() else -1, BATTLE_BENCH_WARM, clampf(secs, 0.5, 10.0))
		elif view != "" or area != "frostford":
			var secs := float(_query("probe")) if _query("probe").is_valid_float() else 1.0
			await perf_probe(clampf(secs, 0.5, 10.0))      # 截图 / 逐区域基准（tools/bench_areas.js）：只测一次，不显示浮层
		else:
			Settings.set_value("show_perf", true)
			await run_benchmark()
		return
	if arrived_by != "":
		pass                          # 换区域进来的：_arrive() 已经提示过区域名
	elif loaded_from != "":
		hud.toast("已读取：%s%s" % [Saves.SLOT_NAMES.get(loaded_from, loaded_from), ("（%s）" % pending.note) if str(pending.get("note", "")) != "" else ""], 3.0)
		if GameState.chapter == 0 and GameState.has_flag("prologue_done") and playable_chapter >= 1:
			hud.toast(CH1_LATER, 6.0)        # 序章打完以后的存档：告诉玩家怎么进第一章（4.3）
	elif Saves.has_any():
		hud.toast("有存档：%s里「存档 / 读档」可以继续（F9 读快速存档）" % ("点「菜单」，" if touch_mode else "按 Esc 打开菜单，"), 6.0)
	# 给网页冒烟测试用：「菜单」按钮在窗口里的位置（窗口像素，已乘界面缩放）
	await get_tree().process_frame
	var c := hud.menu_btn.get_global_rect().get_center() * get_tree().root.content_scale_factor
	print("IC_MENU_SCREEN x=%d y=%d" % [c.x, c.y])
	var qc := hud.quest_btn.get_global_rect().get_center() * get_tree().root.content_scale_factor
	print("IC_QUEST_SCREEN x=%d y=%d" % [qc.x, qc.y])
	var bc := hud.bag_btn.get_global_rect().get_center() * get_tree().root.content_scale_factor
	print("IC_BAG_SCREEN x=%d y=%d" % [bc.x, bc.y])
	var cc := hud.char_btn.get_global_rect().get_center() * get_tree().root.content_scale_factor
	print("IC_CHAR_SCREEN x=%d y=%d" % [cc.x, cc.y])
	var mc := hud.map_btn.get_global_rect().get_center() * get_tree().root.content_scale_factor
	print("IC_HUDMAP_SCREEN x=%d y=%d" % [mc.x, mc.y])
	if touch_mode:
		var ac: Vector2 = touch.button_centers().attack * get_tree().root.content_scale_factor
		print("IC_ATTACK_SCREEN x=%d y=%d" % [ac.x, ac.y])
		var gc: Vector2 = touch.button_centers().guard * get_tree().root.content_scale_factor
		print("IC_GUARD_SCREEN x=%d y=%d" % [gc.x, gc.y])
		var vc: Vector2 = touch.button_centers().camera * get_tree().root.content_scale_factor
		print("IC_CAMERA_SCREEN x=%d y=%d" % [vc.x, vc.y])
		if touch.order_enabled:          # 「令」和展开后「跟随」的位置（B.2，冒烟测试用）
			var oc: Vector2 = touch.button_centers().order
			var fc: Vector2 = (oc - Vector2(TouchControls.BTN_R * 2.0 + 12.0, 0.0)) * get_tree().root.content_scale_factor
			oc *= get_tree().root.content_scale_factor
			print("IC_ORDER_SCREEN x=%d y=%d fx=%d fy=%d" % [oc.x, oc.y, fc.x, fc.y])


func _build_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = FOG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = AMBIENT_COLOR
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.fog_enabled = true
	env.fog_light_color = FOG_COLOR
	if use_test_range or use_arena:
		env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
		env.fog_density = 0.045
	elif Areas.is_indoor(area):
		# 室内（3.1 酒馆）：没有月光与夜雾，暖色的暗环境光 + 一点炉烟似的薄雾；亮度主要来自炉火与油灯
		env.background_color = Color("0c0a08")
		env.ambient_light_color = Color("8a6a4c")
		env.ambient_light_energy = 0.5
		env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
		env.fog_light_color = Color("2a2119")
		env.fog_density = 0.035
	else:
		# 霜渡镇：深度雾从 3 米开始、50 米处完全吞没（ART.md 第三节「雾是构图工具」），再加一点贴地的高度雾
		env.fog_mode = Environment.FOG_MODE_DEPTH
		env.fog_depth_begin = 2.0
		env.fog_depth_end = 36.0
		env.fog_depth_curve = 0.85
		env.fog_density = 1.0
		env.fog_height = 0.8
		env.fog_height_density = 0.25
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 0.9
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 0.85
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	moon = DirectionalLight3D.new()
	moon.light_color = Color("8fb0d6")
	moon.light_energy = 0.32
	moon.rotation_degrees = Vector3(-38, 150, 0)     # 从背后偏左照过来，给房子勾一道冷色轮廓
	moon.directional_shadow_max_distance = 25.0
	moon.visible = not Areas.is_indoor(area)
	add_child(moon)


func scene_name() -> String:
	return area


func _query(key: String) -> String:
	if not OS.has_feature("web"):
		return ""
	return str(JavaScriptBridge.eval("(new URLSearchParams(window.location.search)).get('%s') || ''" % key, true))


## 从固定机位开始（Frostford.VIEWS；截图与冒烟测试用）
func set_view(i: int) -> void:
	var v: Array = Areas.views(area)[i]
	player.global_position = v[0]
	player.rotation.y = deg_to_rad(v[1])
	player.pitch = v[2]
	player.head.rotation.x = deg_to_rad(v[2])
	if streamer:
		streamer.prime(player.global_position)    # 连片地图：换到的地方附近马上搭好（基准测试、截图不等分帧）


## 连片地图（4.4 鹭沼）：主角放好以后，先把附近的块同步搭完（还在黑屏里），其余的进场以后分帧搭；
## 每搭好一块补上时段和画质（_dress_late）。载入、读档、走门、?view、?cam 都走到这里，脚下的块总是先有画面
func _prime_chunks() -> void:
	streamer = world.get_node_or_null("Streamer") as ChunkStreamer
	if streamer == null:
		return
	streamer.target = player
	streamer.budget = ChunkStreamer.BUDGET_TOUCH_USEC if touch_mode else ChunkStreamer.BUDGET_USEC
	streamer.view_dist = _fog_end()
	streamer.chunk_built.connect(_dress_late)
	var t0 := Time.get_ticks_usec()
	streamer.prime(player.global_position)
	print("IC_MARSH prime ms=%.0f built=%d of=%d" % [float(Time.get_ticks_usec() - t0) / 1000.0, streamer.stats.built, streamer.chunks.size()])


## 后搭好的一块：套上现在的时段（窗、夜灯、雾带）、画质（低画质雾带减半、芦苇只画一半）
func _dress_late(root: Node3D) -> void:
	Daypart.apply_nodes(root, daypart)
	if quality != "":
		for f in root.find_children("*", "MeshInstance3D", true, false):
			if f.is_in_group("fog_band"):
				f.visible = quality != "low" or int(f.get_meta("fog_index", 0)) % 2 == 0
		Marsh.refresh_in(root, quality == "low")


## 当前时段的雾在几米外吞没（室内、测试场 0）
func _fog_end() -> float:
	return float(Daypart.PRESETS[daypart].fog_end) if Daypart.affects(area) else 0.0


## 画质分档（TECH.md 第五节）：低 = 0.75 倍分辨率、无阴影、无泛光、无各向异性过滤、雾带减半；
## 中 = 原分辨率、月光阴影（1 段）、泛光；高 = 再加 2 倍抗锯齿、阴影 2 段
func apply_quality(tier: String) -> void:
	quality = tier
	if pause_menu:
		pause_menu.show_quality(tier)
	var vp := get_viewport()
	vp.scaling_3d_scale = 0.75 if tier == "low" else 1.0
	vp.msaa_3d = Viewport.MSAA_2X if tier == "high" else Viewport.MSAA_DISABLED
	moon.shadow_enabled = tier != "low" and moon.visible
	# 默认 4 段级联阴影会把场景重画 4 遍（1.4 实测：绘制调用 154 → 393）；中档 1 段、高档 2 段
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if tier == "high" else DirectionalLight3D.SHADOW_ORTHOGONAL
	env.glow_enabled = tier != "low"
	Look.set_anisotropic(tier != "low")
	for f in get_tree().get_nodes_in_group("fog_band"):
		f.visible = tier != "low" or int(f.get_meta("fog_index", 0)) % 2 == 0
	_refresh_edges()


## 区域边上的树画多少（3.10）：看画质和当前时段的雾有多远
func _refresh_edges() -> void:
	var fog_end := _fog_end()
	Edges.refresh(get_tree(), quality == "low", fog_end)
	Marsh.refresh(get_tree(), quality == "low")       # 鹭沼的芦苇（4.4）：低画质画一半
	if streamer:
		streamer.view_dist = fog_end                  # 块按雾的远近显示 / 隐藏
		streamer.update_visibility()


## 性能统计（TECH.md 第五节）：在当前机位连续采样 seconds 秒：平均帧率、最慢一帧、绘制调用、图元、可见物体
func perf_probe(seconds := 1.0) -> Dictionary:
	var dc := 0.0
	var prim := 0.0
	var obj := 0.0
	var n := 0
	var worst := 0
	# 逻辑耗时（B.5）：每帧从第一步物理（没有物理就从处理）开始，到开始画画为止；和 army_bench 的 logic60_ms 同一个量法。
	# 引擎的 TIME_PROCESS 在网页上差不多是整帧时间（含等画画），分不出逻辑和显卡，不用它。无头运行没有 frame_pre_draw，记 -1。
	var lg := {"start": 0, "sum": 0, "frames": 0}
	var mark := func() -> void:
		if lg.start == 0:
			lg.start = Time.get_ticks_usec()
	var cut := func() -> void:
		if lg.start > 0:
			lg.sum += Time.get_ticks_usec() - lg.start
			lg.frames += 1
		lg.start = 0
	get_tree().physics_frame.connect(mark)
	get_tree().process_frame.connect(mark)
	RenderingServer.frame_pre_draw.connect(cut)
	var t0 := Time.get_ticks_usec()
	var last := t0
	while Time.get_ticks_usec() - t0 < int(seconds * 1000000.0):
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		worst = maxi(worst, now - last)
		last = now
		dc += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		prim += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		obj += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		n += 1
	get_tree().physics_frame.disconnect(mark)
	get_tree().process_frame.disconnect(mark)
	RenderingServer.frame_pre_draw.disconnect(cut)
	n = maxi(n, 1)
	var elapsed := float(Time.get_ticks_usec() - t0) / 1000000.0
	var r := {"draw_calls": dc / n, "primitives": prim / n, "objects": obj / n, "fps": n / elapsed, "worst_ms": worst / 1000.0, "quality": quality,
		"logic_ms": float(lg.sum) / lg.frames / 1000.0 if lg.frames > 0 else -1.0}     # 真机上帧率低时分得清是逻辑慢还是显卡慢（B.5）
	print("IC_PERF draw_calls=%.0f primitives=%.0f objects=%.0f fps=%.1f worst_ms=%.0f quality=%s logic_ms=%.2f" % [r.draw_calls, r.primitives, r.objects, r.fps, r.worst_ms, quality, r.logic_ms])
	return r


## 基准测试（路线图 1.5）：依次站到 3 个固定机位，等 settle 秒再测 sample 秒，结果表显示在性能浮层上
func run_benchmark(settle := 1.5, sample := 3.0) -> Array:
	bench_results.clear()
	perf_overlay.bench_text = "基准测试进行中……（%s画质，不要操作）" % PerfOverlay.tier_name(quality)
	for i in Frostford.VIEW_NAMES.size():
		set_view(i)
		await get_tree().create_timer(settle).timeout
		var r := await perf_probe(sample)
		r["view"] = i
		bench_results.append(r)
	var lines := ["基准测试结果（%s画质，%s）" % [PerfOverlay.tier_name(quality), "电脑" if not touch_mode else "触屏设备"]]
	for r in bench_results:
		lines.append("机位 %d %s：平均 %.0f 帧，最慢一帧 %.0f 毫秒，绘制调用 %.0f" % [r.view, Frostford.VIEW_NAMES[r.view], r.fps, r.worst_ms, r.draw_calls])
	lines.append(bench_done_line())
	perf_overlay.bench_text = "\n".join(lines)
	set_view(0)
	print("IC_BENCH done quality=%s %s" % [quality, " | ".join(bench_results.map(func(r): return "v%d fps=%.1f worst=%.0f dc=%.0f" % [r.view, r.fps, r.worst_ms, r.draw_calls]))])
	return bench_results


## 军阵基准测试（B.5；?test=3&n=30&perf=1，真机上请所有者跑）：你站到一边不参战（兵不打你），直接开打（不自动存档），
## 开打 warm 秒后依次在观战台上、两军之间各测 sample 秒；only_view >= 0 时只在当前机位测一次、不显示结果表（截图、逐画质复测用）。
## 关掉士气（没人溃逃）：测的是打得最凶的时候——开着士气的话，手机上 60 人十来秒就溃逃完了，第二个机位测的是打完的场面（B.5 实测）。
func run_battle_benchmark(only_view := -1, warm := BATTLE_BENCH_WARM, sample := BATTLE_BENCH_SAMPLE) -> Array:
	bench_results.clear()
	battle_bench = true
	battle.player_side = ""
	battle.morale_on = false
	var n := get_tree().get_nodes_in_group("soldier").size()      # 在场上的兵（不算还没到的援军）
	if only_view < 0:
		perf_overlay.bench_text = "军阵基准测试进行中……（%d 人，%s画质，不要操作）" % [n, PerfOverlay.tier_name(quality)]
	if not battle.started:
		battle.start()
	await get_tree().create_timer(warm).timeout
	if only_view >= 0:
		bench_results.append(await perf_probe(sample))
		return bench_results
	for v in BATTLE_BENCH_VIEWS:
		set_view(v)
		await get_tree().create_timer(1.0).timeout
		var r := await perf_probe(sample)
		r["view"] = v
		bench_results.append(r)
	var lines := ["军阵基准测试结果（%d 人，%s画质，%s）" % [n, PerfOverlay.tier_name(quality), "电脑" if not touch_mode else "触屏设备"]]
	for r in bench_results:
		lines.append("%s：平均 %.0f 帧，最慢一帧 %.0f 毫秒" % [BattleArena.VIEW_NAMES[r.view], r.fps, r.worst_ms])      # 分两行：手机上一行放不下（B.5 截图）
		lines.append("　　绘制调用 %.0f，逻辑约 %s 毫秒" % [r.draw_calls, "%.1f" % r.logic_ms if r.logic_ms >= 0.0 else "—"])
	lines.append(bench_done_line())
	perf_overlay.bench_text = "\n".join(lines)
	print("IC_BENCH done battle=%d quality=%s %s" % [n, quality, " | ".join(bench_results.map(func(r): return "v%d fps=%.1f worst=%.0f dc=%.0f logic=%.1f" % [r.view, r.fps, r.worst_ms, r.draw_calls, r.logic_ms]))])
	return bench_results


## 基准测试的最后一行：手机上没有 Esc（2026-10-04 手机实测）；分两行，手机竖屏上一行放不下（B.5 截图）
func bench_done_line() -> String:
	return "测完了：请截图发给开发者。\n%s可换画质，换完刷新页面再测。" % ("点右上角「菜单」" if touch_mode else "按 Esc 打开菜单")


## 性能浮层的位置：触屏上生命 / 体力条在左上角，浮层放到它们下面，不压住（2026-10-04 手机实测）
func place_perf_overlay() -> void:
	perf_overlay.position = Vector2(12, hud.bar_rect().end.y + 14.0 if hud.bars_top else 44.0)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var vignette := ColorRect.new()
	vignette.name = "Vignette"
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vm := ShaderMaterial.new()
	vm.shader = load("res://shaders/vignette.gdshader")
	vignette.material = vm
	layer.add_child(vignette)
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 换区域时的黑屏（3.1）：压在所有界面上面，平时全透明、不挡点击
	var top := CanvasLayer.new()
	top.layer = 90
	add_child(top)
	fade = ColorRect.new()
	fade.name = "Fade"
	fade.color = Color(0, 0, 0, 0)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(fade)
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud = Hud.new()
	layer.add_child(hud)
	title_card = TitleCard.new()         # 开场的标题卡（3.8）：压在 HUD 上、在各种面板下面，平时藏着
	title_card.hide()
	layer.add_child(title_card)
	if use_arena:
		hud.set_hint(HINT_ARENA_TOUCH if touch_mode else HINT_ARENA_DESKTOP)
		hint_left = HINT_SECONDS * 1.5
	elif area == "battle":
		hud.set_hint(HINT_BATTLE_TOUCH if touch_mode else HINT_BATTLE_DESKTOP)
		hint_left = HINT_SECONDS * 1.5
	else:
		hud.set_hint(HINT_TOUCH if touch_mode else HINT_DESKTOP)
	hud.menu_pressed.connect(open_pause)
	hud.melee = player.melee
	hud.bars_top = touch_mode               # 触屏上左下角是摇杆，体力条放到左上
	player.melee.swung.connect(func(k: String): print("IC_ATTACK kind=%s stamina=%.0f" % [k, player.melee.stamina]))
	player.melee.hit.connect(_on_hit)
	player.melee.guarded.connect(_on_guarded)
	player.melee.damaged.connect(_on_damaged)
	player.melee.defeated.connect(_on_defeated)
	player.surface_changed.connect(_on_surface_changed)
	player.rescued.connect(_on_rescued)
	for e in get_tree().get_nodes_in_group("enemy"):
		e.state_changed.connect(_on_enemy_state)
	if touch_mode:
		hud.key_hint = ""
	player.interactor.target_changed.connect(_on_target_changed)
	player.interactor.interacted.connect(_on_interacted)
	touch = TouchControls.new()
	touch.player = player
	touch.camera_pressed.connect(toggle_camera)
	layer.add_child(touch)
	hud.touch_ref = touch
	perf_overlay = PerfOverlay.new()
	perf_overlay.main = self
	layer.add_child(perf_overlay)
	layer.move_child(perf_overlay, hud.get_index())    # 画在 HUD 底下：触屏上浮层挪低后，屏幕上方的短提示会叠到浮层上，字要在上面
	place_perf_overlay()
	dialogue = DialoguePanel.new()
	layer.add_child(dialogue)
	dialogue.closed.connect(_on_dialogue_closed)
	dialogue.node_shown.connect(_on_dialogue_node)
	quest_panel = QuestPanel.new()
	layer.add_child(quest_panel)
	quest_panel.closed.connect(_on_quest_closed)
	hud.quest_pressed.connect(open_quests)
	inventory_panel = InventoryPanel.new()
	layer.add_child(inventory_panel)
	inventory_panel.closed.connect(_on_quest_closed)
	inventory_panel.used.connect(_on_item_used)
	hud.bag_pressed.connect(open_inventory)
	char_panel = CharacterPanel.new()
	layer.add_child(char_panel)
	char_panel.closed.connect(_on_quest_closed)
	hud.char_pressed.connect(open_character)
	hud.map_pressed.connect(open_map)
	GameState.skill_up.connect(_on_skill_up)
	GameState.perk_unlocked.connect(func(s: String, p: Dictionary):
		hud.toast("◆ 解锁专长：%s ·「%s」%s" % [GameState.SKILL_NAMES[s], p.name, p.desc], 4.0))
	GameState.level_up.connect(func(lv: int):
		hud.toast("▲ 升到 %d 级：获得 1 个属性点（%s）" % [lv, "点「角色」分配" if touch_mode else "按 K 分配"], 4.0)
		print("IC_LEVEL %d" % lv))
	GameState.rep_changed.connect(_on_rep_changed)
	GameState.inventory_changed.connect(func(): show_tip("bag"))
	loot_panel = LootPanel.new()
	layer.add_child(loot_panel)
	loot_panel.closed.connect(_on_loot_closed)
	loot_panel.took.connect(func(names: Array): hud.toast("拿到：" + "、".join(names), 2.5))
	GameState.quest_event.connect(_on_quest_event)
	pause_menu = PauseMenu.new()
	layer.add_child(pause_menu)
	pause_menu.set_touch(touch_mode)
	pause_menu.quality_selected.connect(func(t: String):
		apply_quality(t)
		Settings.set_value("quality", t)          # 记住玩家选的画质（2.8）
		print("IC_QUALITY %s" % t))
	save_panel = SavePanel.new()
	save_panel.main = self
	layer.add_child(save_panel)
	pause_menu.saves_requested.connect(func(): save_panel.open())
	GameState.quest_event.connect(_autosave_on_quest)
	pause_menu.resume_requested.connect(close_pause)
	defeat_panel = DefeatPanel.new()
	layer.add_child(defeat_panel)
	defeat_panel.retry_requested.connect(func(): _retry.call_deferred())
	ending_panel = EndingPanel.new()
	layer.add_child(ending_panel)
	ending_panel.closed.connect(_on_ending_closed)
	ending_panel.restart_requested.connect(func(): _restart.call_deferred())
	ending_panel.continue_requested.connect(func(n: int): start_chapter(n))
	travel_map = TravelMap.new()
	layer.add_child(travel_map)
	travel_map.closed.connect(_on_map_closed)
	travel_map.depart_requested.connect(func(id: String): depart(id))
	travel_map.view_requested.connect(_switch_map)
	map_panel = MapPanel.new()
	layer.add_child(map_panel)
	map_panel.closed.connect(_on_area_map_closed)
	map_panel.view_requested.connect(_switch_map)
	packs = PackLoader.new()
	packs.name = "Packs"
	packs.process_mode = Node.PROCESS_MODE_ALWAYS       # 下载时游戏是暂停的，HTTPRequest 和进度照样要走
	add_child(packs)
	pack_panel = PackPanel.new()
	layer.add_child(pack_panel)
	packs.progress.connect(func(_id: String, done: int, total: int): pack_panel.set_progress(done, total))
	pack_panel.retry_requested.connect(func(): pack_answer = "retry")
	pack_panel.cancel_requested.connect(func(): pack_answer = "cancel")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		open_pause()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("quest_log"):
		open_quests()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("inventory"):
		open_inventory()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("camera_toggle"):
		toggle_camera()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("quick_save"):
		get_viewport().set_input_as_handled()
		quick_save()
		return
	if event.is_action_pressed("quick_load"):
		get_viewport().set_input_as_handled()      # 读档会重新载入场景，先标记已处理
		load_game.call_deferred("quick")
		return
	if event.is_action_pressed("character"):
		open_character()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("travel_map"):
		open_map()
		get_viewport().set_input_as_handled()
		return
	for o in Battle.ORDERS:              # 小队命令（B.2）：1 跟随我 · 2 原地坚守 · 3 冲锋
		if event.is_action_pressed("order_" + o):
			if give_order(o):
				get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("perf_toggle"):
		Settings.set_value("show_perf", not Settings.show_perf)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("interact"):
		player.interactor.use()
		get_viewport().set_input_as_handled()
		return
	# F 键也能出剑（只用键盘的玩家；按住同样是重击）
	if event.is_action_pressed("attack_key"):
		player.melee.press()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_released("attack_key"):
		player.melee.release()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("block_key"):
		player.melee.block_press()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_released("block_key"):
		player.melee.block_release()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("sheathe"):
		player.melee.toggle_draw()
		get_viewport().set_input_as_handled()
		return
	# 触屏产生的模拟鼠标事件（DEVICE_ID_EMULATION）不算鼠标（余烬陷落 TECH.md 4.1 的经验）
	# 第一次点击只用来锁定指针；锁定以后左键是攻击（按下 / 松开分开传，按住是重击）
	if event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION and not touch_mode:
		if event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			_start()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				player.melee.press()
			else:
				player.melee.release()
		elif event.button_index == MOUSE_BUTTON_RIGHT:     # 右键按住格挡（2.5）
			if event.pressed:
				player.melee.block_press()
			else:
				player.melee.block_release()
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			player.look(event.relative)


## 命中（2.4）：准星闪一下 ×，日志给冒烟测试
func _on_hit(target: Node, info: Dictionary) -> void:
	hud.hit_marker(info.kind == "heavy")
	print("IC_HIT target=%s dmg=%d kind=%s" % [target.get("display_name"), info.damage, info.kind])


## 格挡结果（2.5）：屏幕上方短提示（文字 + 符号）
func _on_guarded(result: String, info: Dictionary) -> void:
	match result:
		"perfect":
			hud.toast("◆ 完美格挡！对方失衡", 1.2)
		"block":
			hud.toast("挡住了（体力 −%d）" % roundi(player.melee.guard_cost(info)), 1.0)
		"guard_break":
			hud.toast("× 格挡被打破！", 1.2)
	print("IC_BLOCK result=%s dmg=%d stamina=%.0f" % [result, info.damage, player.melee.stamina])


func _on_damaged(amount: int, _info: Dictionary) -> void:
	hud.hurt_flash()
	print("IC_PLAYER_HIT dmg=%d hp=%d" % [amount, player.melee.health])


func _on_defeated() -> void:
	print("IC_DEFEAT")
	player.melee.cancel_press()
	if touch:
		touch.release_all()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	lock_seen = false
	defeat_panel.open()


## 倒下后：有存档就读最近的一份；没有存档就开一局新游戏（2.8）
func _retry() -> void:
	var slot := Saves.latest_slot()
	if slot != "" and load_game(slot):
		return
	GameState.new_game()
	_reload()


## 第一 / 第三人称切换（2.9，D6）：设置里记住，下次打开还是这个视角
func toggle_camera() -> void:
	Settings.set_value("third_person", not Settings.third_person)
	hud.toast("视角：%s" % ("第三人称（越肩）" if Settings.third_person else "第一人称"), 1.5)
	print("IC_CAMERA mode=%s" % ("third" if Settings.third_person else "first"))


# ---------------- 存档（2.8） ----------------

## 现在能不能存档：有敌人正在和你打（警觉 / 战斗 / 后退 / 失衡）就不行；倒下了也不行
func can_save() -> String:
	if player.melee.down:
		return "你已经倒下了"
	if in_combat():
		return "附近有敌人在和你打，不能存档"
	return ""


## 有敌人正在和你打（警觉 / 战斗 / 后退 / 失衡），或者正在打架（3.3）：不能存档，也不能走进别的区域
func in_combat() -> bool:
	if brawl_active() or encounter_active() or (battle != null and is_instance_valid(battle) and battle.active()):
		return true
	for e in get_tree().get_nodes_in_group("enemy"):
		if e.state in [Enemy.State.ALERT, Enemy.State.COMBAT, Enemy.State.RETREAT, Enemy.State.STAGGER]:
			return true
	return false


## 换区域（3.1）：从门走进另一个区域。先淡出，记下去哪、站哪、生命与体力，再重新载入本场景（和读档同一条路）。
## 返回是否出发了（战斗中、倒下了、区域不存在都不走）
func travel(to: String, spawn_id: String, arrive_daypart := "") -> bool:
	if not Areas.known(to):
		return false
	var why := "你已经倒下了" if player.melee.down else ("附近有敌人在和你打，走不开" if in_combat() else "")
	if why != "":
		hud.toast("× %s" % why, 2.5)
		print("IC_TRAVEL_FAIL to=%s %s" % [to, why])
		return false
	player.melee.cancel_press()
	GameState.pending_load = {"scene": to, "spawn": spawn_id,
		"player": {"health": player.melee.health, "stamina": player.melee.stamina, "crouch": player.crouch_wanted}}
	if Daypart.valid(arrive_daypart):
		GameState.pending_load["daypart"] = arrive_daypart      # 到了再改时段（旅行地图的路线，4.2）
	GameState.pending_tips = tip_queue.duplicate()
	leaving = true
	print("IC_TRAVEL from=%s to=%s spawn=%s" % [area, to, spawn_id])
	if not Settings.reduced_motion:
		var tw := create_tween()
		tw.tween_property(fade, "color:a", 1.0, FADE_TIME)
		await tw.finished
	_reload()
	return true


## 刚从门走进来：从黑屏淡入、提示区域名、不再显示开场的操作提示，进入新区域自动存档（GDD 第十节）
func _arrive() -> void:
	started = true
	hint_left = 0.0
	hud.set_hint("")
	var intro := "ch%d_intro" % GameState.chapter
	if GameState.chapter > 0 and not GameState.get_flag(intro):
		GameState.set_flag(intro, true)                  # 刚进这一章：先报章节名（只报一次）
		hud.toast("%s\n%s" % [Chapters.name_of(GameState.chapter), area_title()], 3.0)
	else:
		hud.toast(area_title(), 2.0)
	print("IC_ARRIVE area=%s spawn=%s chapter=%d zone=%s" % [area, arrived_by, GameState.chapter, AreaMap.zone_at(area, player_xz())])
	if GameState.chapter >= 1 and area == "frostford" and not GameState.has_flag("ch1_victor_done"):
		show_tip("ch1_victor", true)     # 第一章开场（4.3）：维克托就在眼前
	show_tip("save")                     # 进入新区域会自动存档：第一次走进别处时讲存档
	show_tip("map")                      # 地图（3.11）：排在存档后面
	if Settings.reduced_motion:
		fade.color.a = 0.0
	else:
		fade.color.a = 1.0
		# 暂停时也要淡完（4.2 实测：刚到就打开地图 / 暂停菜单，淡入停在半路，黑幕一直盖在面板上）
		create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).tween_property(fade, "color:a", 0.0, FADE_TIME * 1.5)
	save_game.call_deferred("auto", true)


## 区域名；连片地图上加你在的那一块：「鹭沼 · 芦栈村」（4.4）
func area_title() -> String:
	var z := AreaMap.zone_at(area, player_xz())
	return Areas.display_name(area) + (" · " + z if z != "" else "")


func player_xz() -> Vector2:
	return Vector2(player.global_position.x, player.global_position.z)


## 脚下的地面变了（4.4 泥潭）：HUD 写一行字（不只靠画面），第一次踩进泥里讲一句
func _on_surface_changed(id: String) -> void:
	hud.set_surface(Surface.label(id))
	print("IC_SURFACE id=%s run=%s" % [id if id != "" else "none", Surface.can_run(id)])
	if id == "mud":
		show_tip("mud")


## 掉出地图（深水下面没有地面，墙漏了的话）：放回最近站稳的地方
func _on_rescued(at: Vector3) -> void:
	hud.toast("水太深，你爬回了刚才站稳的地方。", 3.0)
	print("IC_FALL_RESCUE area=%s x=%.1f y=%.1f z=%.1f" % [area, at.x, at.y, at.z])


## 存档内容：版本、时间、场景、玩家（位置、朝向、生命、体力、蹲着）、游戏状态
func collect_save() -> Dictionary:
	var p := player.global_position
	return {
		"version": Saves.VERSION,
		"saved_at": Time.get_datetime_string_from_system(true) + "Z",
		"scene": scene_name(),
		"player": {"pos": [p.x, p.y, p.z], "yaw": player.rotation.y, "pitch": player.pitch, "health": player.melee.health,
			"stamina": player.melee.stamina, "crouch": player.crouch_wanted},
		"state": GameState.to_dict(),
	}


## 存到一个栏位；返回是否成功（失败时屏幕提示原因）
func save_game(slot: String, quiet := false) -> bool:
	var why := can_save()
	if why == "":
		if Saves.write_slot(slot, collect_save()):
			if not quiet:
				hud.toast("✓ 已存档：%s" % Saves.SLOT_NAMES[slot], 2.0)
			print("IC_SAVE slot=%s" % slot)
			return true
		why = Saves.last_error
	if not quiet:
		hud.toast("× 没有存档：%s" % why, 3.0)
	print("IC_SAVE_FAIL slot=%s %s" % [slot, why])
	return false


func quick_save() -> void:
	save_game("quick")


## 自动存档：接任务、任务更新、任务完成时（GDD 第十节）；战斗中跳过，不提示
func _autosave_on_quest(kind: String, _id: String) -> void:
	if kind in ["started", "advanced", "done"]:
		save_game.call_deferred("auto", true)


## 读档：把状态装回 GameState，记下场景与玩家，重新载入场景。返回是否读到了
func load_game(slot: String) -> bool:
	var r := Saves.read_slot(slot)
	if not r.has("data"):
		var why := str(r.get("error", "这个栏位是空的"))
		hud.toast("× 读不了%s：%s" % [Saves.SLOT_NAMES.get(slot, slot), why], 3.0)
		print("IC_LOAD_FAIL slot=%s %s" % [slot, why])
		return false
	var d: Dictionary = r.data
	var ch := int((d.state as Dictionary).get("chapter", 0))
	if not packs.has_pack(Chapters.pack_of(ch)):
		_load_after_pack(slot, d, str(r.note), ch)          # 第一章以后的存档：先把那一章的章节包拿到（4.1），拿不到就不读、存档不动
		return true
	_finish_load(slot, d, str(r.note))
	return true


func _finish_load(slot: String, d: Dictionary, note: String) -> void:
	GameState.from_dict(d.state)
	GameState.pending_load = {"scene": str(d.scene), "player": d.player, "slot": slot, "note": note}
	print("IC_LOAD slot=%s scene=%s%s" % [slot, d.scene, " note=" + note if note != "" else ""])
	_reload()


func _load_after_pack(slot: String, d: Dictionary, note: String, ch: int) -> void:
	if await ensure_chapter(ch):
		_finish_load(slot, d, note)
	else:
		hud.toast("× 没能载入%s，存档没读" % Chapters.name_of(ch), 3.0)
		print("IC_LOAD_FAIL slot=%s 章节包没到" % slot)


func _reload() -> void:
	get_tree().paused = false
	if get_tree().current_scene == self:
		get_tree().reload_current_scene()
	else:
		reload_requested.emit()


## 位置与朝向只有读档时才有（换区域时站到出生点）；生命、体力、蹲着两种情况都有
func _restore_player(p: Dictionary) -> void:
	if p.has("pos"):
		var pos: Array = p.pos
		player.global_position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
		player.rotation.y = float(p.get("yaw", 0.0))
		player.pitch = float(p.get("pitch", 0.0))
		player.head.rotation.x = deg_to_rad(player.pitch)
	player.crouch_wanted = bool(p.get("crouch", false))
	player.melee.health = clampi(int(p.get("health", player.melee.health_max())), 1, player.melee.health_max())
	player.melee.stamina = clampf(float(p.get("stamina", player.melee.stamina_max())), 0.0, player.melee.stamina_max())


func _on_enemy_state(e: Enemy, state: String) -> void:
	print("IC_ENEMY id=%s state=%s hp=%d" % [e.enemy_id, state, e.hp])
	if use_arena and state in ["dead", "yield"]:
		var left := get_tree().get_nodes_in_group("enemy").filter(func(x): return x.state not in [Enemy.State.DEAD, Enemy.State.YIELD])
		if left.is_empty():
			hud.toast("✓ 训练场清空了（按 Esc 打开菜单，刷新页面再来一次）" if not touch_mode else "✓ 训练场清空了（刷新页面再来一次）", 5.0)
			print("IC_ARENA_CLEAR")


func _on_target_changed(target: Interactable) -> void:
	hud.show_prompt(target.prompt() if target else "")
	if target is LootContainer:
		show_tip("loot")
	if target:
		print("IC_TARGET name=%s verb=%s" % [target.display_name, target.verb_now()])
		# 给网页冒烟测试用：触屏交互按钮在窗口里的位置
		if touch_mode and not use_screen_logged:
			use_screen_logged = true
			var c: Vector2 = touch.button_centers().get("interact", Vector2.ZERO) * get_tree().root.content_scale_factor
			print("IC_USE_SCREEN x=%d y=%d" % [c.x, c.y])


func _on_interacted(r: Dictionary) -> void:
	if r.is_empty():
		return
	if r.has("toast"):
		hud.toast(r.toast)
	if r.has("speech"):
		hud.say(r.speech)
	if r.get("kind") == "pickup":
		GameState.add_item(r.item)
	if r.get("kind") == "dialogue":
		if brawl_active() or encounter_active():
			hud.toast("先把这一架打完。", 1.5)
			print("IC_INTERACT kind=busy name=%s" % r.get("name", ""))
			return
		open_dialogue(r.area, r.id, r.get("npc"))
	if r.get("kind") == "loot":
		open_loot(r.container)
	if r.get("kind") == "travel":
		travel(str(r.area), str(r.spawn))
	if r.get("kind") == "map":
		open_travel_map(true)                  # 对着路牌：打开旅行地图，能从这里出发（4.2）
	var t := player.interactor.target
	if not dialogue.visible:
		hud.show_prompt(t.prompt() if t else "")     # 门开了以后提示从「打开」变「关上」
	print("IC_INTERACT kind=%s name=%s" % [r.get("kind", ""), r.get("name", "")])


## 打开对话（2.1）：镜头平滑转向说话人，游戏暂停，鼠标放出来点选项
func open_dialogue(area: String, id: String, npc: Node3D = null) -> void:
	if not dialogue.open(area, id):
		return
	dialogue_npc = npc
	player.set_dialogue_view(true)   # 第三人称时先把镜头收回眼睛，主角不挡说话人（再按眼睛的位置算转向）
	hud.show_prompt("")
	hud.set_hint("")              # 底部的操作提示不再压在对话上
	hint_left = 0.0
	tip_now = ""
	if npc:
		var head := npc.global_position + Vector3(0, 1.55, 0)
		var d := head - player.camera.global_position
		var yaw := atan2(-d.x, -d.z)
		var pitch := clampf(rad_to_deg(atan2(d.y, Vector2(d.x, d.z).length())), -30.0, 30.0)
		var tw := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_parallel()
		tw.tween_property(player, "rotation:y", player.rotation.y + angle_difference(player.rotation.y, yaw), 0.35).set_trans(Tween.TRANS_SINE)
		tw.tween_method(func(p: float):
			player.pitch = p
			player.head.rotation.x = deg_to_rad(p), player.pitch, pitch, 0.35).set_trans(Tween.TRANS_SINE)
	player.melee.cancel_press()      # 蓄力中打开界面：不攒着一记重击
	lock_seen = false
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if touch:
		touch.release_all()
		if touch.visible:
			touch.visible = false     # 暂停时按钮不响应，压在对话框底下只是碍眼（2026-10-04 手机实测）
			touch_hidden_by_dialogue = true


## 任务日志（2.3）：打开时暂停，和暂停菜单一样放出鼠标
func open_quests() -> void:
	if get_tree().paused:
		return
	player.melee.cancel_press()      # 蓄力中打开界面：不攒着一记重击
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	lock_seen = false
	if touch:
		touch.release_all()
	quest_panel.open()


## 背包（2.6）：和任务日志一样暂停、放出鼠标
func open_inventory() -> void:
	if get_tree().paused:
		return
	_pause_for_panel()
	inventory_panel.open()


## 角色（2.7）
func open_character() -> void:
	if get_tree().paused:
		return
	_pause_for_panel()
	char_panel.open()


func _on_skill_up(skill: String, value: int) -> void:
	hud.toast("%s ↑ %d" % [GameState.SKILL_NAMES.get(skill, skill), value], 2.0)
	print("IC_SKILL %s=%d" % [skill, value])


## 声望变化：「瓦伦家 · 声望上升 ↑（友善）」（文字 + 箭头，GDD 7.3；字体里没有 ▼，用 ↑ ↓）
func _on_rep_changed(faction: String, delta: int, value: int) -> void:
	hud.toast("%s · 声望%s %s（%s）" % [GameState.faction_name(faction), "上升" if delta > 0 else "下降", "↑" if delta > 0 else "↓", GameState.rep_tier(value)], 3.0)
	show_tip("rep")
	print("IC_REP %s %+d = %d" % [faction, delta, value])


## 搜刮（2.6）
func open_loot(c: LootContainer) -> void:
	if get_tree().paused:
		return
	_pause_for_panel()
	hud.show_prompt("")
	loot_panel.open(c)


func _pause_for_panel() -> void:
	player.melee.cancel_press()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	lock_seen = false
	if touch:
		touch.release_all()


func _on_loot_closed() -> void:
	_on_quest_closed()
	player.interactor.refresh()
	var t := player.interactor.target
	hud.show_prompt(t.prompt() if t else "")       # 搜空了提示变成「（空）」


## 用了消耗品：回生命 / 体力（不超过上限）
func _on_item_used(eff: Dictionary, id: String) -> void:
	var m := player.melee
	m.health = mini(m.health + int(eff.get("health", 0)), m.health_max())
	m.stamina = minf(m.stamina + float(eff.get("stamina", 0)), m.stamina_max())
	print("IC_USE item=%s hp=%d stamina=%.0f" % [id, m.health, m.stamina])


func _on_quest_closed() -> void:
	get_tree().paused = false
	if not touch_mode:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## 任务事件 → 屏幕上方的短提示（文字 + 符号）
func _on_quest_event(kind: String, id: String) -> void:
	var qd := GameState.quest_data()
	var text := ""
	match kind:
		"started":
			text = "◆ 新任务：%s（按 J 查看）" % qd.quests[id].title if not touch_mode else "◆ 新任务：%s（点「任务」查看）" % qd.quests[id].title
		"advanced":
			text = "◆ 任务更新：%s" % qd.quests[id].title
		"done":
			text = "✓ 任务完成：%s" % qd.quests[id].title
		"clue":
			text = "◇ 新线索已记入任务日志"
	if text != "":
		hud.toast(text, 3.5)
	if kind == "started":
		show_tip("quest")
	elif kind == "clue":
		show_tip("clue")
	print("IC_QUEST_EVENT %s %s" % [kind, id])


func _on_dialogue_closed() -> void:
	player.set_dialogue_view(false)
	if touch_hidden_by_dialogue:
		touch_hidden_by_dialogue = false
		touch.visible = true            # 先还原：结束画面（show_ending）要记下触屏按钮原来显不显示
	get_tree().paused = false
	if not touch_mode:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED    # 最后一次是点选项或按键，浏览器允许重新锁定
	var b := GameState.pending_brawl
	GameState.pending_brawl = {}
	if not b.is_empty() and dialogue_npc is Npc:
		start_brawl(dialogue_npc, b)                   # 对话里说好了打一架（3.3）
	var f := GameState.pending_fight
	GameState.pending_fight = {}
	if not f.is_empty():
		start_encounter(str(f.fight), str(f.get("win", "")))      # 对峙说崩了，动手（3.6）
	var lv := GameState.pending_leave
	GameState.pending_leave = ""
	if lv != "":
		var n := Encounter.leave(world, lv)
		print("IC_ENCOUNTER leave id=%s npcs=%d" % [lv, n])
	if area == "ferry":                                     # 渡口（3.7）：抉择之后人走了、修士来了
		match Ferry.refresh(world):
			"arrived":
				hud.toast("雾里有人提着灯走下坡来……", 3.0)
				print("IC_FERRY alban_arrived")
	if area == "frostford" and GameState.chapter >= 1 and GameState.has_flag("ch1_victor_done"):
		show_tip("travel_map")                              # 和维克托说完了：讲旅行地图（4.3；STORY 4.5 第 1 步的教学）
	var pd := GameState.pending_daypart
	GameState.pending_daypart = ""
	if pd != "":
		set_daypart(pd)                                     # 剧情推进到别的时段（4.2）
	var ending := GameState.pending_ending
	GameState.pending_ending = ""
	if ending != "":
		show_ending.call_deferred(ending)
	player.interactor.refresh()
	var t := player.interactor.target
	hud.show_prompt(t.prompt() if t else "")


# ---------------- 打架（3.3） ----------------

func brawl_active() -> bool:
	return brawl != null and is_instance_valid(brawl) and brawl.active()


## 和一个 NPC 徒手打一架：spec = {brawl: 敌人种类, win: 旗标, lose: 旗标}（对话效果，DialogueRunner）
func start_brawl(npc: Npc, spec: Dictionary) -> void:
	if brawl_active() or player.melee.down:
		return
	brawl = Brawl.new()
	brawl.name = "Brawl"
	add_child(brawl)
	brawl.ended.connect(_on_brawl_ended)
	brawl.begin(world, player, npc, str(spec.brawl), str(spec.get("win", "")), str(spec.get("lose", "")))
	brawl.enemy.state_changed.connect(_on_enemy_state)
	hud.show_prompt("")
	hud.toast("◆ 和%s徒手打一架" % npc.display_name, 2.5)
	hud.set_hint(HINT_BRAWL_TOUCH if touch_mode else HINT_BRAWL_DESKTOP)     # 底部的操作提示换成打架的（不许动刀）
	hint_left = HINT_SECONDS
	print("IC_BRAWL start kind=%s with=%s" % [spec.brawl, npc.display_name])


func _on_brawl_ended(won: bool) -> void:
	var who := brawl.npc.display_name if is_instance_valid(brawl) else ""
	if won:
		hud.toast("✓ %s认输了。" % who, 3.0)
	else:
		hud.toast("× 你被%s打倒了。（生命 %d）" % [who, player.melee.health], 3.5)
		if not Settings.reduced_motion:
			fade.color.a = 0.85                     # 眼前一黑，再慢慢缓过来
			create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).tween_property(fade, "color:a", 0.0, 1.2)     # 暂停时也淡完（同 _arrive）
	save_game.call_deferred("auto", true)


# ---------------- 结束画面（3.7） ----------------

## 序章结束：暂停，渐显「第一章 · 黑鹭堡　开发中」和这一夜的回顾
func show_ending(id: String, choice := "") -> void:
	if choice == "":
		choice = str(GameState.get_flag("prologue_edric"))
	player.melee.cancel_press()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	lock_seen = false
	if touch:
		touch.release_all()
	hud.show_prompt("")
	hud.set_hint("")
	hud.visible = false                 # 提示、按钮和触屏摇杆都压在结束画面底下会叠字（平板上「挡」「攻」叠在回顾上），先藏起来
	touch_was_visible = touch.visible
	touch.visible = false
	ending_panel.open(choice, Settings.reduced_motion, 1 if playable_chapter >= 1 else 0)
	print("IC_ENDING id=%s choice=%s next=%d" % [id, choice, ending_panel.next_chapter])
	if ending_panel.next_chapter > 0:
		await get_tree().process_frame
		var c := ending_panel.continue_btn.get_global_rect().get_center() * get_tree().root.content_scale_factor
		print("IC_CONTINUE_SCREEN x=%d y=%d" % [c.x, c.y])          # 给网页冒烟测试点（窗口像素，已乘界面缩放）


func _on_ending_closed() -> void:
	get_tree().paused = false
	hud.visible = true
	touch.visible = touch_was_visible
	if not touch_mode:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if ending_panel.next_chapter > 0:
		hud.toast(CH1_LATER, 6.0)            # 在雾里再走走：之后去小教堂找修士还能进第一章（4.3，审查发现：不然再也进不去）
	print("IC_ENDING closed")


## 从头再来：新游戏（存档不动），回到霜渡镇主街
func _restart() -> void:
	GameState.new_game()
	_reload()


# ---------------- 章节（4.1） ----------------

## 进第 n 章：章节包先到（网页上下载，失败可以重试或返回），再记章节、写旗标，到这一章的起点（到了自动存档）
func start_chapter(n: int) -> void:
	if not Chapters.known(n) or n > playable_chapter:
		return
	if not await ensure_chapter(n):
		return
	GameState.chapter = n
	GameState.set_flag("ch%d_started" % n, true)
	GameState.daypart = Chapters.daypart_of(n)           # 第一章从清晨开始（4.2）
	var c: Dictionary = Chapters.LIST[n]
	GameState.pending_load = {"scene": str(c.area), "spawn": str(c.spawn),
		"player": {"health": player.melee.health_max(), "stamina": player.melee.stamina_max()}}
	print("IC_CHAPTER start=%d area=%s" % [n, c.area])
	ending_panel.hide()
	_reload()


## 确保第 n 章的内容到了：已经在就直接返回 true；否则打开下载画面，失败时等玩家点「重试」或「返回」（返回 = false，什么都不改）
func ensure_chapter(n: int) -> bool:
	var id := Chapters.pack_of(n)
	if packs.has_pack(id):
		return true
	var was_paused := get_tree().paused
	get_tree().paused = true
	while true:
		pack_panel.open(Chapters.name_of(n), Settings.reduced_motion)
		var r: Dictionary = await packs.ensure(id)
		if r.ok:
			pack_panel.close()
			get_tree().paused = was_paused
			return true
		pack_panel.fail(str(r.detail))
		pack_answer = ""
		while pack_answer == "":
			await get_tree().process_frame
		if pack_answer == "cancel":
			pack_panel.close()
			get_tree().paused = was_paused
			return false
	return false


## 这一章在当前区域放的东西。4.1：第一章在霜渡镇宅邸门口立一块「往鹭沼 · 黑鹭堡」的路牌——场景在章节包里，看得到它就说明包挂上了
func _place_chapter_content() -> void:
	if GameState.chapter < 1 or area != "frostford":
		return
	Frostford.place_ch1(world)                      # 第一章开场的人：维克托、埃德里克（4.3；脚本和对话都在主包里，章节包没到也照样在）
	var path := Chapters.probe_of(1)
	var ps: PackedScene = load(path) if ResourceLoader.exists(path) else null
	if ps == null:
		print("IC_PACK_MISSING chapter=1")             # 不该走到这里（读档、进章都先确保了章节包）：不放路牌，游戏照常
		return
	var sign := ps.instantiate() as Node3D
	sign.name = "RoadSignCh1"
	world.add_child(sign)
	sign.position = Frostford.SIGN_POS              # 宅邸门口出生点（0, 0, -44.3，面朝 +Z）往前 4.5 米、路的左边，木板伸向路中间：
	sign.rotation.y = atan2(1.3, 4.5)               # 手机竖屏视野窄，板子在正前方 2°–20° 以内才看得全（4.1 截图）；板面转过来对着出门的人
	print("IC_CH1_SIGN")


# ---------------- 旅行地图（4.2） ----------------

## 站在出发的地方旁边（路牌，组 travel_point）：按 M 打开地图也能出发
func near_travel_point() -> bool:
	for t in get_tree().get_nodes_in_group("travel_point"):
		var d: Vector3 = (t as Node3D).global_position - player.global_position
		if Vector2(d.x, d.z).length() <= Travel.DEPART_RADIUS:
			return true
	return false


## M 键和右上角「地图」（3.11）：第一章起站在路牌旁边打开旅行地图（能出发，和以前一样）；
## 别的时候打开地图册——室外先看「本地」（你在哪、出口通往哪里），室内先看「一带」。序章也有（原来只弹一句「序章没有旅行地图」）
func open_map() -> void:
	if get_tree().paused or leaving:
		return
	if not Travel.places(GameState.chapter).is_empty() and near_travel_point():
		open_travel_map(true)
		return
	open_area_map(AreaMap.default_view(area))


## 打开地图册的「本地」或「一带」页：只能看，不能从这里出发
func open_area_map(v: String) -> void:
	if get_tree().paused or leaving:
		return
	map_departure = false
	_pause_for_map()
	_show_area_map(v, false)


## 打开旅行地图：departure = 站在出发的地方（能出发），否则只能看。序章没有旅行地图。打开时暂停，藏起提示和触屏按钮（和结束画面一样）
func open_travel_map(departure := false) -> void:
	if get_tree().paused or leaving:
		return
	if Travel.places(GameState.chapter).is_empty():
		hud.toast("序章没有旅行地图，第一章起才有。", 2.5)
		print("IC_MAP none chapter=%d" % GameState.chapter)
		return
	map_departure = departure
	_pause_for_map()
	_show_travel_map(departure)


## 暂停、放出鼠标、藏起提示和触屏按钮（地图册几页共用；切页时不再来一遍）
func _pause_for_map() -> void:
	player.melee.cancel_press()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	lock_seen = false
	if touch:
		touch.release_all()
	hud.visible = false                 # 只藏起来：交互提示和正在显示的教学提示关上地图后还在（审查发现：清掉了就回不来）
	touch_was_visible = touch.visible
	touch.visible = false


## 地图册里换一页（页签条，3.11）：先藏起现在这一页的面板（不发 closed，不还原暂停），再打开另一页；一直暂停着
func _switch_map(v: String) -> void:
	if v == "travel":
		map_panel.hide()
		_show_travel_map(map_departure)
	else:
		travel_map.hide()
		_show_area_map(v, true)


func _show_area_map(v: String, switched: bool) -> void:
	var p := player.global_position
	map_panel.open(area, v, AreaMap.views(area, GameState.chapter), Vector2(p.x, p.z), player.yaw_deg(), Settings.reduced_motion)
	var region := AreaMap.region_of(area)
	if switched:
		print("IC_AREAMAP view=%s area=%s exits=%d nodes=%d links=%d" % [map_panel.view, area, AreaMap.exits(area).size(), map_panel.node_btns.size(),
			AreaMap.links(region).size() if map_panel.view == "region" else 0])
	else:
		print("IC_AREAMAP open view=%s area=%s exits=%d nodes=%d px=%.1f zoom=%s" % [map_panel.view, area, AreaMap.exits(area).size(),
			map_panel.node_btns.size(), map_panel.canvas.px_per_m, map_panel.canvas.zoomable])
	map_panel.print_screen()                      # 给网页冒烟测试点的坐标（等布局摆好）


func _show_travel_map(departure: bool) -> void:
	travel_map.tabs.setup(AreaMap.views(area, GameState.chapter), "travel")
	var here := Travel.place_of_area(area, player_xz())
	travel_map.open(GameState.chapter, here, departure, Settings.reduced_motion)
	print("IC_MAP open here=%s departure=%s places=%d selected=%s" % [here, departure, travel_map.place_btns.size(), travel_map.selected])
	await get_tree().process_frame
	await get_tree().process_frame                 # 地点按钮摆好位置以后（_place_buttons 是延后调用的）
	var k := get_tree().root.content_scale_factor
	for id in travel_map.place_btns:            # 给网页冒烟测试点（窗口像素，已乘界面缩放）
		var pc: Vector2 = (travel_map.place_btns[id] as Button).get_global_rect().get_center() * k
		print("IC_MAP_PLACE id=%s x=%d y=%d" % [id, pc.x, pc.y])
	var gc := travel_map.go_btn.get_global_rect().get_center() * k
	var cc := travel_map.close_btn.get_global_rect().get_center() * k
	print("IC_MAP_SCREEN x=%d y=%d cx=%d cy=%d" % [gc.x, gc.y, cc.x, cc.y])


## 关上地图（任一页）：取消暂停，还原提示和触屏按钮，电脑上重新锁定鼠标，刷新交互提示
func _resume_from_map() -> void:
	get_tree().paused = false
	hud.visible = true
	touch.visible = touch_was_visible
	if not touch_mode:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	player.interactor.refresh()
	var t := player.interactor.target
	hud.show_prompt(t.prompt() if t else "")


func _on_map_closed() -> void:
	_resume_from_map()
	print("IC_MAP closed")


func _on_area_map_closed() -> void:
	_resume_from_map()
	print("IC_AREAMAP closed")


## 从地图出发去 id：先看能不能走（Travel.check：做好了没有、有没有路、是不是站在出发的地方），再看是不是倒下了、在打（和存档、走门一样），
## **出发前自动存档**（存的是出发前的样子，GDD 第十节「做出关键抉择之前」）——浏览器存不进去（无痕模式、空间满）时提示一句照样走，
## 和走门一样（审查发现：不然这样的浏览器永远出不了门）；然后和走门一样换区域，路线写的时段（例如走大半天到了是白天）到了再改。
## 返回不能走的原因（"" = 走了）；地图上的状态行写这个原因
func depart(id: String) -> String:
	var here := Travel.place_of_area(area, player_xz())
	var c := Travel.check(GameState.chapter, here, id, travel_map.at_departure)
	var why := str(c.why)
	if why == "":
		why = can_save()
		if why != "":
			why = "%s。" % why
	if why != "":
		travel_map.show_status("× " + why)
		print("IC_DEPART_FAIL to=%s %s" % [id, why])
		return why
	if not save_game("auto", true):
		hud.toast("× 自动存档没存上（%s），照样出发。" % Saves.last_error, 3.0)
	var p := Travel.place(id)
	var dp := str((c.route as Dictionary).get("daypart", ""))
	print("IC_DEPART from=%s to=%s daypart=%s" % [here, id, dp if Daypart.valid(dp) else GameState.daypart])
	travel_map.hide()
	_on_map_closed()
	if not await travel(str(p.area), str(p.spawn), dp):
		return "走不了。"                            # 不该发生：上面都查过了
	return ""


# ---------------- 时段（4.2） ----------------

## 剧情推进到另一个时段：记进游戏状态；这个区域受时段影响时短暂黑一下再换光（减少动态效果时直接换），上方提示「到黄昏了」之类。
## 不重新载入场景（门开着、敌人在哪都不变）；室内只记下来，走出去才看得到
func set_daypart(id: String, announce := true) -> void:
	if not Daypart.valid(id):
		return
	GameState.daypart = id
	var eff := Daypart.effective(area, id)
	if eff != daypart:
		var dim := not Settings.reduced_motion and fade != null
		if dim:
			var tw := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
			tw.tween_property(fade, "color:a", 1.0, FADE_TIME * 2.0)
			await tw.finished
		daypart = eff
		Daypart.apply(self, daypart)
		_refresh_edges()
		if dim:
			create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).tween_property(fade, "color:a", 0.0, FADE_TIME * 3.0)
	print("IC_DAYPART id=%s area=%s changed=true" % [daypart, area])
	if announce:
		hud.toast(str(Daypart.CHANGE_TEXT.get(id, "")), 2.5)


# ---------------- 对峙转战斗（3.6） ----------------

func encounter_active() -> bool:
	return encounter != null and is_instance_valid(encounter) and encounter.active()


## 区域里那组 NPC 换成敌人，开打（渡口的「灰手」奥弗和他的两个手下）
func start_encounter(id: String, win: String) -> void:
	if encounter_active():
		return
	encounter = Encounter.new()
	encounter.name = "Encounter"
	add_child(encounter)
	encounter.ended.connect(_on_encounter_ended)
	encounter.begin(world, id, win)
	for e in encounter.enemies:
		e.state_changed.connect(_on_enemy_state)
	hud.show_prompt("")
	hud.toast("◆ 动手了！", 2.0)
	print("IC_ENCOUNTER start id=%s enemies=%d" % [id, encounter.enemies.size()])


## 开打（B.3）：先自动存档（GDD 6.4「开战前自动存档，玩家倒下就读档」），再让两边动起来
func start_battle() -> void:
	if battle == null or not is_instance_valid(battle) or battle.started:
		return
	save_game("auto", true)
	battle.start()
	hud.toast("◆ 开打！", 2.0)


## 给小队下命令（B.2）；没有小队时什么都不做，返回 false
func give_order(o: String) -> bool:
	if battle == null or not is_instance_valid(battle) or not battle.order(o):
		return false
	hud.toast("◆ 小队：%s" % Battle.ORDERS[o], 2.0)
	hud.refresh_squad()
	return true


## 军阵试验场打完了（B.1）：只有一方还站着
func _on_battle_ended(winner: String) -> void:
	if battle_bench:
		return
	var refresh := "（刷新页面再来一次）"
	if winner == "":
		hud.toast("两边都打光了。" + refresh, 6.0)
	elif winner == battle.player_side:
		hud.toast("✓ %s赢了！%s" % [battle.sides.get(winner, winner), refresh], 6.0)
	else:
		hud.toast("× %s赢了……%s" % [battle.sides.get(winner, winner), refresh], 6.0)


func _on_encounter_ended(_won: bool) -> void:
	hud.toast("✓ 渡口的无旗者都解决了。", 3.0)
	save_game.call_deferred("auto", true)


func _npc_by_dialogue(id: String) -> Npc:
	for n in world.find_children("*", "", true, false):
		if n is Npc and (n as Npc).dialogue_id == id:
			return n
	return null


## 潜行（2.7）：蹲着走、附近 10 米内有还没察觉你的敌人，每秒涨 0.5 进度
func _train_stealth(delta: float) -> void:
	if not player.crouching or Vector2(player.velocity.x, player.velocity.z).length() < 0.3:
		return
	for e in get_tree().get_nodes_in_group("enemy"):
		if e.state in [Enemy.State.PATROL, Enemy.State.SUSPICIOUS] and e.global_position.distance_to(player.global_position) <= 10.0:
			GameState.train("stealth", 0.5 * delta)
			return


func _start() -> void:
	if not started:
		started = true
		if tip_now == "":                # 开局的操作说明在开始走动后再停 3 秒；教学提示照常显示完
			hint_left = minf(hint_left, 3.0)


func open_pause() -> void:
	if get_tree().paused:
		return
	player.melee.cancel_press()      # 蓄力中打开界面：不攒着一记重击
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	lock_seen = false
	pause_menu.open()
	print("IC_PAUSE open=true")
	if touch_mode:                    # 给网页冒烟测试用：「存档 / 读档」按钮的位置
		await get_tree().process_frame
		var c := pause_menu.saves_btn.get_global_rect().get_center() * get_tree().root.content_scale_factor
		print("IC_SAVES_SCREEN x=%d y=%d" % [c.x, c.y])


func close_pause() -> void:
	pause_menu.hide()
	get_tree().paused = false
	if not touch_mode:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED   # 「继续」按钮是一次点击，浏览器允许重新锁定
	print("IC_PAUSE open=false")


# ---------------- 开场与教学提示（3.8） ----------------

## 教学提示（data/tips.json）：每条只显示一次（看过的记进存档），暂停菜单可以关；
## now = 立刻换掉底部正在显示的提示（开场用），否则排队：有界面开着（游戏暂停）或上一条还没消失时等着
func show_tip(id: String, now := false) -> void:
	if not Settings.tips or id in GameState.tips_seen or id == tip_now or not GameState.tips_data().has(id):
		return
	if now:
		tip_queue.erase(id)
		_show_tip(id)
	elif not tip_queue.has(id):
		tip_queue.append(id)


func _show_tip(id: String) -> void:
	if id in GameState.tips_seen:
		return
	GameState.tips_seen.append(id)
	var d: Dictionary = GameState.tips_data()[id]
	hud.set_hint(str(d.touch if touch_mode else d.desktop))
	hint_left = float(d.get("sec", 7))
	tip_now = id
	print("IC_TIP %s" % id)


## 对话换了节点：第一次遇到检定选项时，在对话面板里讲一下检定（游戏暂停着，底部提示看不到）
func _on_dialogue_node(has_check: bool) -> void:
	if not has_check or not Settings.tips or "check" in GameState.tips_seen:
		return
	GameState.tips_seen.append("check")
	var d: Dictionary = GameState.tips_data().get("check", {})
	dialogue.show_tip(str(d.get("touch" if touch_mode else "desktop", "")))
	print("IC_TIP check")


## 贴地雾带在主角脚边淡出（fog_plane.gdshader 的 clear_at）：第三人称时小腿不会被雾片盖成灰白一截（2026-10-04 手机实测）
func _clear_fog_at(pos: Vector3) -> void:
	for f in get_tree().get_nodes_in_group("fog_band"):
		if not (f as Node3D).is_visible_in_tree():
			continue                                 # 藏起来的（低画质减半、鹭沼远处的块）不用更新，下次显示时下一帧就补上
		var m := (f as MeshInstance3D).material_override as ShaderMaterial
		if m:
			m.set_shader_parameter("clear_at", pos)


func _process(delta: float) -> void:
	# 浏览器用 Esc 释放指针锁定时，游戏收不到 Esc：发现锁定没了就打开暂停菜单
	var locked := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if locked:
		lock_seen = true
	elif lock_seen:
		lock_seen = false
		open_pause()
	if hint_left > 0.0:
		hint_left -= delta
		if hint_left <= 0.0:
			hud.set_hint("")
			tip_now = ""
	if hint_left <= 0.0 and not tip_queue.is_empty():
		_show_tip(tip_queue.pop_front())
	_train_stealth(delta)
	GameState.playtime += delta
	var pos := player.global_position
	_clear_fog_at(pos)
	if not moved_logged and Vector2(pos.x - spawn.x, pos.z - spawn.z).length() > 1.0:
		moved_logged = true
		_start()
		print("IC_MOVED d=%.2f" % Vector2(pos.x - spawn.x, pos.z - spawn.z).length())
	if not look_logged and absf(angle_difference(deg_to_rad(player.yaw_deg()), deg_to_rad(yaw0))) > deg_to_rad(15.0):
		look_logged = true
		print("IC_LOOK yaw=%.1f" % player.yaw_deg())
