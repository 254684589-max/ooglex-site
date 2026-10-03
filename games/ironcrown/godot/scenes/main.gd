extends Node3D
## 《铁冠之争》主场景（阶段 1.4：霜渡镇主街）。
## 默认是霜渡镇主街（world/frostford.gd）；网页 ?test=1 或 use_test_range = true 打开灰盒测试场（台阶、斜坡、窄门、矮洞、交互）；
## ?test=2 或 use_arena = true 打开训练场（2.5：三个无旗者，练格挡与近战）。
## 3.1 起有多个区域（world/areas.gd）：主街、「倒钩鱼」酒馆……；走进通往别处的门 = travel()：淡出、记下去哪、重新载入本场景、
## 放到命名出生点、淡入、自动存档（GDD 第十节：进入新区域时）。网页 ?area=tavern 直接从酒馆开始（截图与冒烟测试用）。
## 网页参数：?q=low|medium|high 强制画质档；?view=0|1|2 从固定机位开始（截图用）；
## ?area=tavern&brawl=1 一进酒馆就和醉汉「大桶」打起来（3.3，截图与冒烟测试用；不设旗标）。
## ?perf=1 打开性能浮层并自动跑基准测试（依次在 3 个机位各测 3 秒，结果表显示在画面上，1.5）；?perf=1&view=N 只在该机位测一次（截图工具用）。
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
const HINT_SECONDS := 8.0
const FADE_TIME := 0.25           # 换区域时淡出 / 淡入（减少动态效果时直接切）

@export var use_test_range := false
@export var use_arena := false

var moon: DirectionalLight3D
var quality := ""
var perf_overlay: PerfOverlay
var dialogue: DialoguePanel
var quest_panel: QuestPanel
var bench_results: Array = []

var env: Environment
var world: Node3D
var player: FpController
var camera: Camera3D
var hud: Hud
var touch: TouchControls
var pause_menu: PauseMenu
var defeat_panel: DefeatPanel
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
var dialogue_npc: Node3D        # 最近一次对话的说话人（对话里说好打一架时，和他打）

signal reload_requested         # 测试里 main 不是当前场景，读档时改发这个信号


func _ready() -> void:
	touch_mode = DisplayServer.is_touchscreen_available()
	var pending := GameState.pending_load
	GameState.pending_load = {}
	GameState.pending_brawl = {}
	if OS.has_feature("web"):
		if _query("test") == "1":
			use_test_range = true
		elif _query("test") == "2":
			use_arena = true
		elif Areas.known(_query("area")):
			area = _query("area")
		# 系统设置了「减少动态效果」：默认关掉镜头摆动（GDD.md 第四节）；玩家自己存过设置就听玩家的
		if str(JavaScriptBridge.eval("!!(window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches)", true)) == "true":
			Settings.reduced_motion = true
			if not Settings.loaded:
				Settings.head_bob = false
			print("IC_REDUCED_MOTION")
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
		_:
			t = Frostford.build(world, Settings.reduced_motion)
	player = FpController.new()
	player.name = "Player"
	add_child(player)
	player.global_transform = t
	camera = player.camera
	camera.make_current()
	var view := _query("view")
	if view.is_valid_int() and int(view) >= 0 and int(view) < Areas.views(area).size():
		set_view(int(view))
	if not pending.is_empty():
		if pending.has("spawn"):              # 从门走进来：站到那扇门对应的出生点
			arrived_by = str(pending.spawn)
			var st: Variant = Areas.spawn(area, arrived_by)
			if st != null:
				player.global_transform = st
		_restore_player(pending.get("player", {}))
		loaded_from = str(pending.get("slot", ""))
	spawn = player.global_position
	yaw0 = player.yaw_deg()
	_build_ui()
	var q := _query("q")
	apply_quality(q if q in Look.TIERS else (Settings.quality if Settings.quality in Look.TIERS else Look.default_tier()))
	print("IC_READY renderer=%s web=%s scene=%s touch=%s quality=%s size=%s" % [
		ProjectSettings.get_setting("rendering/renderer/rendering_method"), OS.has_feature("web"),
		scene_name(), touch_mode, quality, get_viewport().get_visible_rect().size])
	if arrived_by != "":
		_arrive()
	if area == "tavern" and _query("brawl") == "1":
		var dagu := _npc_by_dialogue("dagu")
		if dagu:
			start_brawl.call_deferred(dagu, {"brawl": "drunk"})
	if _query("perf") == "1":
		await get_tree().create_timer(2.0).timeout
		if view != "" or area != "frostford":
			await perf_probe()          # 截图工具：只测一次，不显示浮层（截图要干净）
		else:
			Settings.set_value("show_perf", true)
			await run_benchmark()
		return
	if arrived_by != "":
		pass                          # 换区域进来的：_arrive() 已经提示过区域名
	elif loaded_from != "":
		hud.toast("已读取：%s%s" % [Saves.SLOT_NAMES.get(loaded_from, loaded_from), ("（%s）" % pending.note) if str(pending.get("note", "")) != "" else ""], 3.0)
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
	if touch_mode:
		var ac: Vector2 = touch.button_centers().attack * get_tree().root.content_scale_factor
		print("IC_ATTACK_SCREEN x=%d y=%d" % [ac.x, ac.y])
		var gc: Vector2 = touch.button_centers().guard * get_tree().root.content_scale_factor
		print("IC_GUARD_SCREEN x=%d y=%d" % [gc.x, gc.y])
		var vc: Vector2 = touch.button_centers().camera * get_tree().root.content_scale_factor
		print("IC_CAMERA_SCREEN x=%d y=%d" % [vc.x, vc.y])


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


## 性能统计（TECH.md 第五节）：在当前机位连续采样 seconds 秒：平均帧率、最慢一帧、绘制调用、图元、可见物体
func perf_probe(seconds := 1.0) -> Dictionary:
	var dc := 0.0
	var prim := 0.0
	var obj := 0.0
	var n := 0
	var worst := 0
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
	n = maxi(n, 1)
	var elapsed := float(Time.get_ticks_usec() - t0) / 1000000.0
	var r := {"draw_calls": dc / n, "primitives": prim / n, "objects": obj / n, "fps": n / elapsed, "worst_ms": worst / 1000.0, "quality": quality}
	print("IC_PERF draw_calls=%.0f primitives=%.0f objects=%.0f fps=%.1f worst_ms=%.0f quality=%s" % [r.draw_calls, r.primitives, r.objects, r.fps, r.worst_ms, quality])
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
	lines.append("测完了：请截图发给开发者。按 Esc 可换画质（菜单里）后刷新页面再测。")
	perf_overlay.bench_text = "\n".join(lines)
	set_view(0)
	print("IC_BENCH done quality=%s %s" % [quality, " | ".join(bench_results.map(func(r): return "v%d fps=%.1f worst=%.0f dc=%.0f" % [r.view, r.fps, r.worst_ms, r.draw_calls]))])
	return bench_results


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
	if use_arena:
		hud.set_hint(HINT_ARENA_TOUCH if touch_mode else HINT_ARENA_DESKTOP)
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
	perf_overlay = PerfOverlay.new()
	perf_overlay.main = self
	layer.add_child(perf_overlay)
	dialogue = DialoguePanel.new()
	layer.add_child(dialogue)
	dialogue.closed.connect(_on_dialogue_closed)
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
	GameState.skill_up.connect(_on_skill_up)
	GameState.perk_unlocked.connect(func(s: String, p: Dictionary):
		hud.toast("◆ 解锁专长：%s ·「%s」%s" % [GameState.SKILL_NAMES[s], p.name, p.desc], 4.0))
	GameState.level_up.connect(func(lv: int):
		hud.toast("▲ 升到 %d 级：获得 1 个属性点（%s）" % [lv, "点「角色」分配" if touch_mode else "按 K 分配"], 4.0)
		print("IC_LEVEL %d" % lv))
	GameState.rep_changed.connect(_on_rep_changed)
	loot_panel = LootPanel.new()
	layer.add_child(loot_panel)
	loot_panel.closed.connect(_on_loot_closed)
	loot_panel.took.connect(func(names: Array): hud.toast("拿到：" + "、".join(names), 2.5))
	GameState.quest_event.connect(_on_quest_event)
	pause_menu = PauseMenu.new()
	layer.add_child(pause_menu)
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
	if brawl_active():
		return true
	for e in get_tree().get_nodes_in_group("enemy"):
		if e.state in [Enemy.State.ALERT, Enemy.State.COMBAT, Enemy.State.RETREAT, Enemy.State.STAGGER]:
			return true
	return false


## 换区域（3.1）：从门走进另一个区域。先淡出，记下去哪、站哪、生命与体力，再重新载入本场景（和读档同一条路）。
## 返回是否出发了（战斗中、倒下了、区域不存在都不走）
func travel(to: String, spawn_id: String) -> bool:
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
	hud.toast(Areas.display_name(area), 2.0)
	print("IC_ARRIVE area=%s spawn=%s" % [area, arrived_by])
	if Settings.reduced_motion:
		fade.color.a = 0.0
	else:
		fade.color.a = 1.0
		create_tween().tween_property(fade, "color:a", 0.0, FADE_TIME * 1.5)
	save_game.call_deferred("auto", true)


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
	GameState.from_dict(d.state)
	GameState.pending_load = {"scene": str(d.scene), "player": d.player, "slot": slot, "note": str(r.note)}
	print("IC_LOAD slot=%s scene=%s%s" % [slot, d.scene, " note=" + r.note if r.note != "" else ""])
	_reload()
	return true


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
		if brawl_active():
			hud.toast("先把这一架打完。", 1.5)
			print("IC_INTERACT kind=busy name=%s" % r.get("name", ""))
			return
		open_dialogue(r.area, r.id, r.get("npc"))
	if r.get("kind") == "loot":
		open_loot(r.container)
	if r.get("kind") == "travel":
		travel(str(r.area), str(r.spawn))
	var t := player.interactor.target
	if not dialogue.visible:
		hud.show_prompt(t.prompt() if t else "")     # 门开了以后提示从「打开」变「关上」
	print("IC_INTERACT kind=%s name=%s" % [r.get("kind", ""), r.get("name", "")])


## 打开对话（2.1）：镜头平滑转向说话人，游戏暂停，鼠标放出来点选项
func open_dialogue(area: String, id: String, npc: Node3D = null) -> void:
	if not dialogue.open(area, id):
		return
	dialogue_npc = npc
	hud.show_prompt("")
	hud.set_hint("")              # 底部的操作提示不再压在对话上
	hint_left = 0.0
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
	print("IC_QUEST_EVENT %s %s" % [kind, id])


func _on_dialogue_closed() -> void:
	get_tree().paused = false
	if not touch_mode:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED    # 最后一次是点选项或按键，浏览器允许重新锁定
	var b := GameState.pending_brawl
	GameState.pending_brawl = {}
	if not b.is_empty() and dialogue_npc is Npc:
		start_brawl(dialogue_npc, b)                   # 对话里说好了打一架（3.3）
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
			create_tween().tween_property(fade, "color:a", 0.0, 1.2)
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
	_train_stealth(delta)
	GameState.playtime += delta
	var pos := player.global_position
	if not moved_logged and Vector2(pos.x - spawn.x, pos.z - spawn.z).length() > 1.0:
		moved_logged = true
		_start()
		print("IC_MOVED d=%.2f" % Vector2(pos.x - spawn.x, pos.z - spawn.z).length())
	if not look_logged and absf(angle_difference(deg_to_rad(player.yaw_deg()), deg_to_rad(yaw0))) > deg_to_rad(15.0):
		look_logged = true
		print("IC_LOOK yaw=%.1f" % player.yaw_deg())
