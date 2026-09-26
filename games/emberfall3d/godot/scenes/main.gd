extends Node3D
## 阶段 1 灰盒场景：工程与网页导出（1.1）、斜俯视相机（1.2）、点击移动 / 摇杆 / 导航网格（1.3）、
## 战斗手感（1.4：烬卫断誓斩 + 焚地践踏，训练木桩）、灰盒大厅与 3 种怪物 AI（1.5：冲锋、远程、召唤）。
## 画面里的所有模型都是代码生成的**占位几何体**，不代表最终美术（ART.md）。

const PITCH_DEG := 55.0
const WORLD_MASK := 1 | IsoCamera.OCCLUDER_LAYER   # 墙体与柱子：世界碰撞（第 1 层）+ 遮挡视线（第 2 层）
const TEST_STAIRS := Vector3(3.5, 0, -4.5)          # 测试区房间东北角：下到地窖第 1 层

var auto_pack_test := true
var run_nav_bench := true
var level: NavigationRegion3D
var hero: Player
var touch: TouchControls
var dummies: Array[TrainingDummy] = []
var monsters: Array[EnemyBase] = []
var spawn_monsters := true
var hp_bar: ProgressBar
var hp_label: Label
var dead_label: Label
var lvl_label: Label
var xp_bar: ProgressBar
var mp_bar: ProgressBar
var mp_label: Label
var bag_label: Label
var char_btn: Button
var btn_hp: Button
var btn_mp: Button
var char_panel: CharPanel
var inv_btn: Button
var inv_panel: InvPanel
var log_label: Label          # 左侧消息（拾取、背包已满……最近 4 条，几秒后淡出）
var log_lines: Array = []     # [文字, 颜色, 剩余秒数]
var loot_rng := RandomNumberGenerator.new()
var btn_attack: Button
var skill_btns := {}          # 手机：四个技能圆按钮（P4）
var skill_bar: SkillBar       # 电脑：屏幕下方技能栏（P4）
var torches: Array[Torch] = []
var environment: Environment
var moon: DirectionalLight3D
var quality := ""
var vignette: ColorRect
var camera: IsoCamera
var info: Label
var pack_label: Label
var pack_state := "章节包：未测试"
var nav_state := ""
var nav_bake_ms := 0.0
var t := 0.0
var stage: Node3D
var use_test_area := false      # true：第 0 层用阶段 1 的灰盒测试区（自动化测试用；网页 ?test=1）；false：烬原镇（P7）
var town: Dictionary = {}
var npcs: Array = []
var shop_stock: Dictionary = {}
var dialog_panel: DialogPanel
var shop_panel: ShopPanel
var floor_i := 0
var run_seed := 0
var dungeon: Dictionary = {}
var floor_info: Dictionary = {}
var stairs: Dictionary = {}
var stair_lock := 0.0
var banner: Label
var banner_t := 0.0
# P8：任务、传送、地图
var quest_panel: QuestPanel
var quest_btn: Button
var map_btn: Button
var btn_tp: Button
var minimap: Minimap
var tp: Dictionary = {}          # 回城传送门（V0.1 tp）：{floor: 地下那一头的楼层, pos: 位置}；没有打开时为空
var _portal_arrive := Vector3.ZERO
var seen_maps: Dictionary = {}   # 楼层 → 到过的格子（Fog.seen）；同一局里回到楼层时自动地图还在
var seen := PackedByteArray()
var vis := PackedByteArray()
var _fog_cell := Vector2i(-999, -999)
var _portal_armed := false       # 刚传送过来时站在门边不算「走进门」：先离开 1.5 米再说


func _ready() -> void:
	add_to_group("loot_host")
	loot_rng.randomize()
	_build_world()
	_build_ui()
	_after_floor()
	if not use_test_area and hero.progress.sheet.lvl == 1 and hero.progress.sheet.q.q1 == 0:
		add_log(Act1Data.dialogs().quest_log.hint_start, Color(1.0, 0.82, 0.29))
	var q := Look.default_tier()
	if OS.has_feature("web"):
		var m = str(JavaScriptBridge.eval("(new URLSearchParams(window.location.search)).get('q') || ''", true))
		if m in Look.TIERS:
			q = m
	apply_quality(q)
	PackLoader.pack_loaded.connect(_on_pack_loaded)
	hero.arrived.connect(_on_hero_arrived)
	print("EF_READY renderer=%s web=%s" % [RenderingServer.get_current_rendering_method(), OS.has_feature("web")])
	print("EF_NAV_BAKE room_ms=%.1f polygons=%d" % [nav_bake_ms, level.navigation_mesh.get_polygon_count()])
	if auto_pack_test and OS.has_feature("web"):
		pack_state = "章节包：下载中……"
		_refresh_labels()
		PackLoader.load_chapter("ch_test")
	# 给网页冒烟测试用：第一个木桩在屏幕上的位置
	await get_tree().process_frame
	# unproject_position 返回的是缩放后的视口坐标；换算成窗口像素（界面缩放 ≠ 1 时两者不同）
	if not dummies.is_empty():
		var sp := camera.unproject_position(dummies[0].global_position + Vector3(0, 1.0, 0)) * get_window().content_scale_factor
		print("EF_DUMMY_SCREEN x=%d y=%d" % [sp.x, sp.y])
	for n in npcs:
		var ns := camera.unproject_position(n.global_position + Vector3(0, 1.2, 0)) * get_window().content_scale_factor
		print("EF_NPC_SCREEN id=%s x=%d y=%d" % [n.npc_id, ns.x, ns.y])
	_print_stairs_screen()
	if run_nav_bench and OS.has_feature("web"):
		# 等两帧再跑，避免和首帧渲染抢时间；结果打到控制台与左下角
		await get_tree().process_frame
		await get_tree().process_frame
		var b := NavBuilder.bench_dungeon(7, 0.25)
		nav_state = "整层地下城导航烘焙 %.0f 毫秒（%d 个多边形）" % [b.ms, b.polygons]
		print("EF_NAV_BENCH ms=%.1f polygons=%d floor_tiles=%d wall_tiles=%d cell=%.2f" % [b.ms, b.polygons, b.floor_tiles, b.wall_tiles, b.cell_size])
		_refresh_labels()
	# 网页上加 ?floor=N 直接从第 N 层开始（试玩与测试用）
	if OS.has_feature("web"):
		var fl := str(JavaScriptBridge.eval("(new URLSearchParams(window.location.search)).get('floor') || ''", true))
		if fl.is_valid_int() and int(fl) > 0:
			go_floor(int(fl))
	# 网页上加 ?perf=1 跑性能基准（tools/perf_web.js 用）
	if OS.has_feature("web") and str(JavaScriptBridge.eval("window.location.search", true)).contains("perf=1"):
		await perf_probe()


func perf_probe(wait_s: float = 3.0) -> Dictionary:
	## 性能基准（TECH.md 第 5.2 节）：把玩家放到大厅中央（无敌，只观察），等怪物围上来、
	## 召唤出仆从、弓手放箭，再连续采样 1 秒：绘制调用、图元、可见物体、帧率、物理与逻辑耗时。
	hero.max_hp = 1e9
	hero.hp = hero.max_hp
	hero.global_position = Vector3(0, 0, 13)
	camera.snap()
	await get_tree().create_timer(wait_s).timeout
	var dc := 0.0
	var prim := 0.0
	var obj := 0.0
	var phys := 0.0
	var proc := 0.0
	var n := 0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 1000:
		await get_tree().process_frame
		dc += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		prim += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		obj += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		n += 1
	var alive := get_tree().get_nodes_in_group("enemy").filter(func(e): return not e.dead).size()
	var r := {"draw_calls": dc / n, "primitives": prim / n, "objects": obj / n, "fps": n, "physics_ms": phys / n, "process_ms": proc / n, "enemies": alive}
	print("EF_PERF draw_calls=%.0f primitives=%.0f objects=%.0f fps=%d physics_ms=%.2f process_ms=%.2f enemies=%d" % [r.draw_calls, r.primitives, r.objects, r.fps, r.physics_ms, r.process_ms, r.enemies])
	return r


func _process(delta: float) -> void:
	t += delta
	stair_lock = maxf(0.0, stair_lock - delta)
	# 站在楼梯上等换层冷却结束也能触发（进入事件只在踏上的那一刻发一次）
	if stair_lock <= 0.0 and hero and not hero.dead:
		for k in stairs:
			var st: Stairs = stairs[k]
			if is_instance_valid(st) and st.overlaps_body(hero):
				_on_stairs(st.kind)
				break
	if hero and not hero.dead:
		_update_fog()
		# 走进传送门直接穿过去（点它也行：走到跟前由 _use_spot 处理）
		for s in get_tree().get_nodes_in_group("interact"):
			if s.kind != "portal":
				continue
			var pd := Vector2(s.global_position.x - hero.global_position.x, s.global_position.z - hero.global_position.z).length()
			if pd > 1.5:
				_portal_armed = true
			elif _portal_armed and pd <= InteractSpot.PORTAL_ENTER and stair_lock <= 0.0 and not get_tree().paused:
				use_portal(s)
				break
	if banner:
		banner_t = maxf(0.0, banner_t - delta)
		banner.modulate.a = clampf(banner_t, 0.0, 1.0)
	if hp_bar and hero:
		if skill_bar:
			skill_bar.refresh()
		for id in skill_btns:
			var r := Player.skill_rule(id)
			var b: Button = skill_btns[id]
			var cd: float = hero.skill_cd.get(id, 0.0)
			var locked: bool = hero.progress.sheet.lvl < int(r.lvl)
			b.text = ("%d级" % int(r.lvl)) if locked else (("%.0f" % ceilf(cd)) if cd > 0.0 else String(r.glyph))
			b.disabled = locked or cd > 0.0 or hero.mp < float(r.mp)
		hp_bar.max_value = hero.max_hp
		hp_bar.value = hero.hp
		hp_label.text = "生命 %d / %d" % [ceili(hero.hp), int(hero.max_hp)]
		var sh: Dictionary = hero.progress.sheet
		lvl_label.text = "%d 级　经验 %d%%" % [sh.lvl, roundi(hero.progress.xp_fraction() * 100.0)]
		xp_bar.value = hero.progress.xp_fraction()
		mp_bar.max_value = hero.max_mp
		mp_bar.value = hero.mp
		mp_label.text = "法力 %d / %d" % [floori(hero.mp), int(hero.max_mp)]
		var keys := not touch.visible
		bag_label.text = "金币 %d　生命药水 ×%d%s　法力药水 ×%d%s　回城卷轴 ×%d%s　背包 %d / %d" % [sh.gold, sh.pots.hp, "（Q）" if keys else "", sh.pots.mp, "（E）" if keys else "", sh.pots.tp, "（T）" if keys else "", sh.inv.size(), int(Act1Data.rules().hero.inventory_cap)]
		var lines: PackedStringArray = []
		for l in log_lines:
			l[2] -= delta
			lines.append(l[0])
		log_lines = log_lines.filter(func(l): return l[2] > 0.0)
		log_label.text = "\n".join(lines)
		log_label.add_theme_color_override("font_color", log_lines[-1][1] if not log_lines.is_empty() else Color.WHITE)
		char_btn.text = ("属性 +%d" % sh.pts) if sh.pts > 0 else ("属性（C）" if keys else "属性")
		inv_btn.text = "背包（I）" if keys else "背包"
		quest_btn.text = "任务（J）" if keys else "任务"
		map_btn.text = "地图（Tab）" if keys else "地图"
		if btn_hp:
			btn_hp.text = "血 %d" % sh.pots.hp
			btn_mp.text = "蓝 %d" % sh.pots.mp
			btn_tp.text = "城 %d" % sh.pots.tp
		dead_label.visible = hero.dead


func _on_pack_loaded(id: String, ok: bool, ms: int, detail: String) -> void:
	if ok:
		var scene := load("res://packs/%s/marker.tscn" % id) as PackedScene
		if scene:
			var inst := scene.instantiate()
			inst.position = Vector3(3.5, 0, -2.5)
			add_child(inst)
			pack_state = "章节包 %s：加载成功，用时 %d 毫秒" % [id, ms]
			print("EF_PACK_OK id=%s ms=%d" % [id, ms])
		else:
			pack_state = "章节包 %s：已挂载，但找不到场景" % id
			print("EF_PACK_FAIL id=%s reason=scene_missing" % id)
	else:
		pack_state = "章节包 %s：加载失败（%s）" % [id, detail]
		print("EF_PACK_FAIL id=%s reason=%s" % [id, detail])
	_refresh_labels()


# ---------------- 场景 ----------------

func _mat(c: Color, emissive: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	if emissive > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emissive
	return m


func _box(size: Vector3, pos: Vector3, c: Color, solid := true) -> MeshInstance3D:
	## 占位方块。solid = true 时带静态碰撞体（世界 + 遮挡层），挂在导航区域下参与烘焙；
	## 相机会在它挡住主角时把它变半透明。
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	if not solid:
		mi.material_override = _mat(c)
		mi.position = pos
		add_child(mi)
		return mi
	var body := StaticBody3D.new()
	body.collision_layer = WORLD_MASK
	body.collision_mask = 0
	body.position = pos
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	shape.shape = bs
	body.add_child(shape)
	body.add_child(mi)
	# 程序生成的砖墙贴图（world/look.gd），按原来的灰度换算成染色：墙 = 1.0，石柱略亮
	mi.material_override = Look.wall_material(Color(c.r / 0.36, c.g / 0.33, c.b / 0.30))
	body.set_meta("fade_meshes", [mi])
	level.add_child(body)
	return mi


func _build_world() -> void:
	# 环境：冷紫阴影 + 暖色火光、雾、泛光、调色（world/look.gd，阶段 2.3）；各楼层按主题换色（P2）
	environment = Look.crypt_environment()
	var we := WorldEnvironment.new()
	we.environment = environment
	add_child(we)

	# 微弱的冷色「月光」：给墙体一个统一的明暗方向；主要光源是火把
	moon = DirectionalLight3D.new()
	moon.light_color = Color(0.5, 0.55, 0.85)
	moon.light_energy = 0.28
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 40.0
	moon.rotation_degrees = Vector3(-60, 30, 0)
	add_child(moon)

	# 玩家（占位外观）与斜俯视相机：跨楼层保留；楼层内容都挂在 stage 下，换层时整个换掉
	hero = Player.new()
	add_child(hero)
	camera = IsoCamera.new()
	camera.pitch_deg = PITCH_DEG
	camera.target = hero
	add_child(camera)
	hero.camera = camera
	run_seed = randi()
	if OS.has_feature("web") and str(JavaScriptBridge.eval("window.location.search", true)).contains("test=1"):
		use_test_area = true
	if use_test_area:
		_build_test_area()
		hero.respawn_point = Vector3.ZERO
	else:
		_build_town("start")


func _new_stage() -> void:
	if stage:
		remove_child(stage)
		stage.queue_free()
	stage = Node3D.new()
	stage.name = "Stage"
	add_child(stage)
	torches.clear()
	dummies.clear()
	monsters.clear()
	stairs.clear()
	npcs.clear()
	if hero:
		hero.in_town = false
		hero.talk_target = null
	if moon:
		moon.light_energy = 0.28


func _build_test_area() -> void:
	## 第 0 层：阶段 1 的灰盒测试区（房间 + 大厅 + 训练木桩 + 4 种怪物）。
	## 烬原镇在 P7 接入之前，由它代替地面；房间东北角的楼梯通往修道院地窖第 1 层。
	_new_stage()
	Look.apply_theme(environment, "crypt")
	# 关卡几何挂在导航区域下，运行时烘焙导航网格
	level = NavBuilder.make_region()
	stage.add_child(level)
	# 地面（占位）：地面层碰撞只用于点击拾取与导航解析，主角不与它碰撞（平面移动）
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	ground.mesh = plane
	ground.material_override = Look.floor_material()
	var gbody := StaticBody3D.new()
	gbody.collision_layer = Player.LAYER_GROUND
	gbody.collision_mask = 0
	var gshape := CollisionShape3D.new()
	var gbox := BoxShape3D.new()
	gbox.size = Vector3(40, 0.2, 40)
	gshape.shape = gbox
	gshape.position.y = -0.1
	gbody.position = Vector3(1, 0, 10)
	gbody.add_child(gshape)
	gbody.add_child(ground)
	level.add_child(gbody)

	# 北边：灰盒房间（12 × 12 米）；南墙中间留 4 米宽的门（x ∈ [-1, 3]）通往南边的大厅。
	# 南边：灰盒大厅（26 × 20 米），几根石柱，1.5 的怪物都在这里。墙高 3.2 米（约主角身高 1.8 倍）。
	var wall := Color(0.36, 0.33, 0.3)
	_box(Vector3(12, 3.2, 0.6), Vector3(0, 1.6, -6), wall)        # 房间北墙
	_box(Vector3(0.6, 3.2, 12), Vector3(-6, 1.6, 0), wall)        # 房间西墙
	_box(Vector3(0.6, 3.2, 12), Vector3(6, 1.6, 0), wall)         # 房间东墙
	_box(Vector3(5, 3.2, 0.6), Vector3(-3.5, 1.6, 6), wall)       # 房间南墙（门的西侧）
	_box(Vector3(11, 3.2, 0.6), Vector3(8.5, 1.6, 6), wall)       # 门的东侧，延伸到大厅东北角
	_box(Vector3(6, 3.2, 0.6), Vector3(-9, 1.6, 6), wall)         # 大厅北墙西段
	_box(Vector3(0.6, 3.2, 20), Vector3(-12, 1.6, 16), wall)      # 大厅西墙
	_box(Vector3(0.6, 3.2, 20), Vector3(14, 1.6, 16), wall)       # 大厅东墙
	_box(Vector3(26.6, 3.2, 0.6), Vector3(1, 1.6, 26), wall)      # 大厅南墙
	for p in [Vector3(-3, 0, -3), Vector3(3, 0, 3), Vector3(-3, 0, 3)]:
		_box(Vector3(0.7, 3.0, 0.7), p + Vector3(0, 1.5, 0), Color(0.42, 0.38, 0.34))
	for p in [Vector3(-6, 0, 14), Vector3(6, 0, 14), Vector3(0, 0, 19), Vector3(-8, 0, 21), Vector3(9, 0, 20)]:
		_box(Vector3(0.9, 3.0, 0.9), p + Vector3(0, 1.5, 0), Color(0.42, 0.38, 0.34))

	nav_bake_ms = NavBuilder.bake(level)

	# 火把（world/torch.gd）：房间一支、大厅三支
	for tp in [Vector3(-5.4, 1.7, -5.4), Vector3(-11.4, 1.8, 25.4), Vector3(13.4, 1.8, 25.4), Vector3(-11.4, 1.8, 9.0)]:
		var tch := Torch.new()
		stage.add_child(tch)
		tch.position = tp
		torches.append(tch)

	# 训练木桩（占位敌人）：房间里两个挨着（测试范围技能）；真正的怪物在南边大厅
	for p in [Vector3(2.2, 0, -1.2), Vector3(3.0, 0, 0.3)]:
		var d := TrainingDummy.new()
		stage.add_child(d)
		d.global_position = p
		d.home = p
		dummies.append(d)

	# 下楼的楼梯（P2）
	var sd := Stairs.make("down", "↓ " + FloorRules.floor_name(1))
	stage.add_child(sd)
	sd.position = TEST_STAIRS
	sd.used.connect(_on_stairs)
	stairs.down = sd

	# 大厅里的怪物（1.5）：2 个冲锋、2 个弓手、1 个召唤祭司
	if spawn_monsters:
		for sp in [["ash_brute", Vector3(-5, 0, 18)], ["ash_brute", Vector3(5, 0, 17)], ["bone_archer", Vector3(-9, 0, 23)], ["bone_archer", Vector3(10, 0, 23)], ["ash_priest", Vector3(0, 0, 24)]]:
			monsters.append(Monsters.spawn(sp[0], stage, sp[1], hero))


# ---------------- 烬原镇（P7） ----------------

func _build_town(via: String) -> void:
	## 第 0 层：烬原镇（V0.1 genTown）。进镇时商店重新进货（V0.1 enterMap → refreshShops）。
	## 从地窖上来站在地窖入口旁；开局与倒下复活站在篝火边（V0.1 起点）。
	_new_stage()
	town = TownGen.generate()
	floor_info = TownBuilder.build(stage, town, {"seed": 36, "on_stairs": _on_stairs, "down_caption": "↓ " + FloorRules.floor_name(1)})
	level = floor_info.region
	torches.assign(floor_info.torches)
	stairs = floor_info.stairs
	npcs = floor_info.npcs
	nav_bake_ms = floor_info.nav_ms
	Look.apply_theme(environment, "town")
	moon.light_energy = 0.45
	hero.in_town = true
	shop_stock = FloorRules.refresh_shop(loot_rng, hero.progress.sheet.lvl)
	if via == "up":
		hero.global_position = DungeonBuilder.cell_center(DungeonGen.near_free(town, town.down))
	elif via == "portal":
		hero.global_position = town_portal_spot() + Vector3(1.4, 0, 1.4)
	else:
		var sp: Vector2 = town.start_pos
		hero.global_position = TownGen.to_world(sp.x, sp.y)
	hero.respawn_point = hero.global_position
	camera.snap()
	_refresh_labels()


func _talk(n: Node3D) -> void:
	## 走到 NPC / 传送石 / 传送门 / 水井跟前（V0.1 talk / useProp）。
	## NPC：先看有没有任务分支（Quests.branch，同 V0.1 talk 的判断顺序），没有就是日常对话。伊莲每次对话都回满生命与法力。
	if n is InteractSpot:
		_use_spot(n)
		return
	var D: Dictionary = Act1Data.dialogs()
	var sh: Dictionary = hero.progress.sheet
	var bye := {"t": "告辞", "fn": dialog_panel.close}
	if n.npc_id == "toby":
		var tl: Array = D.toby.lines
		dialog_panel.show_dialog(n.npc_name, n.glyph, [tl[randi() % tl.size()]], [bye])
		return
	var d: Dictionary = D.get(n.npc_id, {})
	if d.get("heal", false):
		hero.hp = hero.max_hp
		hero.mp = hero.max_mp
	var key := Quests.branch(n.npc_id, sh)
	if key != "":
		var qd: Dictionary = D.quest[key]
		var qopts: Array = [{"t": qd.accept, "main": true, "fn": func(): _accept_quest(key, n)}]
		if qd.has("shop"):
			var qsid: String = d.shop
			qopts.append({"t": qd.shop, "fn": func():
				dialog_panel.close()
				open_shop(qsid)})
		if key.ends_with("_offer"):
			qopts.append(bye)
		dialog_panel.show_dialog(n.npc_name, n.glyph, qd.lines, qopts)
		return
	var opts: Array = []
	if d.has("shop"):
		var sid: String = d.shop
		opts.append({"t": "交易", "main": true, "fn": func():
			dialog_panel.close()
			open_shop(sid)})
	for tpc in d.get("topics", []):
		var lines: Array = tpc.lines
		opts.append({"t": tpc.title, "fn": func(): dialog_panel.show_dialog(n.npc_name, n.glyph, lines, [{"t": "返回", "fn": func(): _talk(n)}])})
	opts.append(bye)
	var greet: Array = [Quests.elin_idle(sh), d.heal_note] if n.npc_id == "elin" else d.get("greet", ["……"])
	dialog_panel.show_dialog(n.npc_name, n.glyph, greet, opts)


## 选了任务分支的主选项：改任务状态、发奖励（Quests.accept），刷新头顶标记
func _accept_quest(key: String, n: Npc) -> void:
	var r := Quests.accept(key, hero.progress.sheet, loot_rng)
	dialog_panel.close()
	var gold_c := Color(1.0, 0.82, 0.29)
	if r.log != "":
		add_log(r.log, gold_c)
	if r.item != null:
		var it: Dictionary = r.item
		if hero.progress.sheet.inv.size() < int(Act1Data.rules().hero.inventory_cap):
			hero.progress.sheet.inv.append(it)
		else:
			_drop_item(it)
		add_log(("获得传奇物品：" if int(it.rarity) == 3 else "获得：") + String(it.name), GroundItem.RARITY_COLORS[int(it.rarity)])
	if r.xp > 0:
		hero.gain_xp(r.xp)
	if r.toby:
		_spawn_toby()
	hero.progress.changed.emit()
	_refresh_marks()
	print("EF_QUEST %s q1=%d q2=%d q3=%d" % [key, hero.progress.sheet.q.q1, hero.progress.sheet.q.q2, hero.progress.sheet.q.q3])
	if r.retalk:
		_talk(n)


func _refresh_marks() -> void:
	for n in npcs:
		if is_instance_valid(n):
			n.set_mark(Quests.mark(n.npc_id, hero.progress.sheet))


## 学徒托比回到镇上（V0.1 spawnToby：交了「铁匠的学徒」之后一直在铁匠铺旁）
func _spawn_toby() -> void:
	if floor_i != 0 or use_test_area or npc("toby") != null:
		return
	var T: Dictionary = Act1Data.dialogs().toby
	var n := Npc.make({"id": "toby", "name": T.name, "glyph": T.glyph, "look": T.spot.look})
	stage.add_child(n)
	n.position = TownGen.to_world(T.spot.x, T.spot.y)
	n.face_v01(float(T.spot.face))
	npcs.append(n)


## 首领倒下（V0.1 bossDown 的任务部分）：P9 的首领在死亡时调用，boss = "mog" / "mordan"
func on_boss_down(boss: String) -> void:
	var r := Quests.on_boss_down(hero.progress.sheet, boss)
	if r.log != "":
		add_log(r.log, Color(1.0, 0.82, 0.29))
	if r.epilogue:
		await get_tree().create_timer(1.6).timeout
		epilogue()


## 结局文字（V0.1 epilogue）
func epilogue() -> void:
	var E: Dictionary = Act1Data.dialogs().epilogue
	dialog_panel.show_dialog(E.name, E.glyph, E.lines, [{"t": E.ok, "main": true, "fn": dialog_panel.close}])


# ---------------- 传送石、回城卷轴、水井（P8） ----------------

func _use_spot(s: InteractSpot) -> void:
	match s.kind:
		"wp":
			open_waypoint()
		"well":
			hero.hp = hero.max_hp
			add_log("井水清凉，你的伤口愈合了", Color(0.6, 0.85, 1.0))
		"portal":
			use_portal(s)


## 传送石（V0.1 openWaypoint）：列出第 1 层到最深到过的一层，首领层标「（首领）」（V0.1 用骷髅符号，字体里没有）
func open_waypoint() -> void:
	var W: Dictionary = Act1Data.dialogs().waypoint
	var mf := int(hero.progress.sheet.maxFloor)
	if mf <= 0:
		add_log(W.silent, Color(0.66, 0.6, 0.5))
		return
	var opts: Array = []
	for f in range(1, mf + 1):
		var ff := f
		opts.append({"t": FloorRules.floor_name(f) + ("（首领）" if FloorRules.is_boss_floor(f) else ""), "fn": func():
			dialog_panel.close()
			go_floor(ff, "wp")})
	opts.append({"t": "离开", "fn": dialog_panel.close})
	dialog_panel.show_dialog(W.name, W.glyph, [W.prompt], opts)


## 回城卷轴（V0.1 castTownPortal）：在身边打开一道传送门，镇上的传送点同时出现另一头
func cast_town_portal() -> void:
	if hero.dead or get_tree().paused:
		return
	if floor_i == 0:
		add_log("你已经在镇上了", Color(0.66, 0.6, 0.5))
		return
	var sh: Dictionary = hero.progress.sheet
	if sh.pots.tp <= 0:
		add_log("没有回城卷轴（可以在药剂师玛拉处购买）", Color(0.88, 0.38, 0.29))
		return
	sh.pots.tp -= 1
	var want := hero.global_position + hero.facing() * 1.6
	var p := NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, want)
	tp = {"floor": floor_i, "pos": Vector3(p.x, 0, p.z)}
	_spawn_portals()
	stair_lock = maxf(stair_lock, 0.6)
	hero.progress.changed.emit()
	add_log("一道蓝色的传送门打开了", Color(0.5, 0.84, 1.0))
	print("EF_PORTAL open floor=%d" % floor_i)


## 穿过传送门（V0.1 usePortal）：地下那一头回镇上；镇上那一头回到原处，传送门随之关闭
func use_portal(s: InteractSpot) -> void:
	if stair_lock > 0.0 or hero.dead:
		return
	stair_lock = 1.0
	if s.to == "town":
		call_deferred("go_floor", 0, "portal")
	elif not tp.is_empty():
		_portal_arrive = tp.pos
		var f: int = tp.floor
		tp = {}
		call_deferred("go_floor", f, "portal")


func town_portal_spot() -> Vector3:
	if use_test_area:
		return Vector3(2.0, 0, 2.0)
	var ps: Vector2 = town.portal_spot
	return TownGen.to_world(ps.x, ps.y)


func _spawn_portals() -> void:
	for s in get_tree().get_nodes_in_group("interact"):
		if s.kind == "portal":
			s.remove_from_group("interact")
			s.queue_free()
	if tp.is_empty():
		return
	if floor_i == tp.floor:
		var a := InteractSpot.make("portal", "回城传送门", "town")
		stage.add_child(a)
		a.global_position = tp.pos
	elif floor_i == 0:
		var b := InteractSpot.make("portal", "传送门：" + FloorRules.floor_name(tp.floor), "dungeon")
		stage.add_child(b)
		b.global_position = town_portal_spot()


# ---------------- 小地图与视野（P8） ----------------

func map_grid() -> Dictionary:
	if floor_i > 0:
		return dungeon
	return {} if use_test_area else town


func floor_title() -> String:
	return FloorRules.floor_name(floor_i) if floor_i > 0 else ("测试区" if use_test_area else "烬原镇")


func _reset_fog() -> void:
	var m := map_grid()
	_fog_cell = Vector2i(-999, -999)
	if m.is_empty():
		seen = PackedByteArray()
		vis = PackedByteArray()
		return
	if not seen_maps.has(floor_i):
		var a := PackedByteArray()
		a.resize(m.w * m.h)
		a.fill(1 if floor_i == 0 else 0)
		seen_maps[floor_i] = a
	seen = seen_maps[floor_i]
	vis = PackedByteArray()
	vis.resize(m.w * m.h)
	vis.fill(1 if floor_i == 0 else 0)
	_update_fog()


func _update_fog() -> void:
	var m := map_grid()
	if m.is_empty() or floor_i == 0 or vis.is_empty():
		return
	var p := Vector2(hero.global_position.x, hero.global_position.z) / DungeonBuilder.TILE
	var c := Vector2i(floori(p.x), floori(p.y))
	if c == _fog_cell:
		return
	_fog_cell = c
	var r := Fog.compute(m, vis, seen, p, int(hero.progress.S.light) + 2)
	vis = r[0]
	seen = r[1]
	seen_maps[floor_i] = seen


func cell_visible(pos: Vector3) -> bool:
	var m := map_grid()
	if m.is_empty():
		return true
	var x := floori(pos.x / DungeonBuilder.TILE)
	var y := floori(pos.z / DungeonBuilder.TILE)
	if x < 0 or y < 0 or x >= m.w or y >= m.h or vis.is_empty():
		return false
	return vis[y * m.w + x] == 1


## 每次换层（以及开局）之后：刷新头顶标记、视野、传送门、托比
func _after_floor() -> void:
	if Quests.toby_home(hero.progress.sheet):
		_spawn_toby()
	_refresh_marks()
	_reset_fog()
	_spawn_portals()
	_portal_armed = false


func toggle_map() -> void:
	if minimap:
		minimap.set_big(not minimap.big)


func open_shop(sid: String) -> void:
	shop_panel.open_shop(hero, sid, shop_stock.get(sid, []))


func npc(id: String) -> Npc:
	for n in npcs:
		if n.npc_id == id:
			return n
	return null


# ---------------- 楼层（P2） ----------------

func seed_for(f: int) -> int:
	## 本局的楼层种子：同一局里回到去过的楼层，布局不变
	return run_seed * 1009 + f * 7919


func _on_stairs(kind: String) -> void:
	if stair_lock > 0.0 or hero.dead:
		return
	stair_lock = 1.0
	# 在物理回调里不能删节点：推迟到本帧末尾换层
	call_deferred("go_floor", floor_i + (1 if kind == "down" else -1), kind)


func go_floor(f: int, via: String = "down") -> void:
	## 换层：第 0 层是灰盒测试区，第 1 层起是随机地下城（V0.1 genDungeon 的布局）。
	## 下楼到达新楼层的上楼梯旁；上楼到达上一层的下楼梯旁（V0.1 goFloor）。
	f = maxi(0, f)
	hero.stop()
	hero.attack_target = null
	hero.attack_hold = false
	floor_i = f
	var t0 := Time.get_ticks_usec()
	if f > 0:
		var qmsg := Quests.on_floor(hero.progress.sheet, f)
		if qmsg != "":
			add_log(qmsg, Color(1.0, 0.82, 0.29))
	if f == 0 and not use_test_area:
		_build_town(via)
		dungeon = {}
	elif f == 0:
		_build_test_area()
		floor_info = {}
		dungeon = {}
		hero.global_position = TEST_STAIRS + Vector3(-2.4, 0, 1.2) if via == "up" else (town_portal_spot() + Vector3(1.4, 0, 1.4) if via == "portal" else Vector3.ZERO)
	else:
		_new_stage()
		dungeon = DungeonGen.generate(f, seed_for(f))
		floor_info = DungeonBuilder.build(stage, dungeon, {
			"seed": seed_for(f), "on_stairs": _on_stairs,
			"down_caption": "↓ " + FloorRules.floor_name(f + 1),
			"up_caption": ("↑ " + FloorRules.floor_name(f - 1)) if f > 1 else ("↑ 返回测试区" if use_test_area else "↑ 烬原镇")})
		level = floor_info.region
		torches.assign(floor_info.torches)
		stairs = floor_info.stairs
		nav_bake_ms = floor_info.nav_ms
		var at: Vector2i = dungeon.up
		if via == "up" and floor_info.down_cell.x >= 0:
			at = floor_info.down_cell
		hero.global_position = DungeonBuilder.cell_center(DungeonGen.near_free(dungeon, at))
		if via == "portal":
			# 回到传送门旁：偏一点站；偏出去那格是墙就退回传送门所在的格子
			var ap := _portal_arrive + Vector3(0.9, 0, 0.9)
			var ac := Vector2i(floori(ap.x / DungeonBuilder.TILE), floori(ap.z / DungeonBuilder.TILE))
			if not DungeonGen.walkable(dungeon.t[ac.y * dungeon.w + ac.x]):
				ap = _portal_arrive
			hero.global_position = ap
		Look.apply_theme(environment, dungeon.theme)
		# 房间里的怪物群（P5，V0.1 genDungeon）
		var jit := RandomNumberGenerator.new()
		jit.seed = seed_for(f) + 17
		for sp in dungeon.spawns:
			var pos := DungeonBuilder.cell_center(sp.cell) + Vector3(jit.randf_range(-0.5, 0.5), 0, jit.randf_range(-0.5, 0.5))
			monsters.append(Monsters.spawn(sp.key, stage, pos, hero, f, sp.champ))
	hero.respawn_point = hero.global_position
	camera.snap()
	apply_quality(quality)
	stair_lock = 0.8
	_after_floor()
	var fname := FloorRules.floor_name(f) if f > 0 else ("测试区 · 灰盒房间与大厅" if use_test_area else "烬原镇")
	_show_banner(fname)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("EF_FLOOR n=%d theme=%s total_ms=%.1f nav_ms=%.1f chunks=%d torches=%d monsters=%d" % [f, dungeon.get("theme", "test" if use_test_area else "town"), ms, nav_bake_ms, floor_info.get("chunks", 0), torches.size(), monsters.size()])


func _on_hero_arrived() -> void:
	## 给网页冒烟测试用：主角走到后（镜头跟上之后）再报一次测试区楼梯的屏幕坐标
	if floor_i != 0 or not OS.has_feature("web"):
		return
	await get_tree().create_timer(1.0).timeout
	if floor_i == 0:
		_print_stairs_screen()


func _print_stairs_screen() -> void:
	if stairs.has("down") and is_instance_valid(stairs.down):
		var ss := camera.unproject_position(stairs.down.global_position) * get_window().content_scale_factor
		print("EF_STAIRS_SCREEN x=%d y=%d" % [ss.x, ss.y])


# ---------------- 掉落（P5） ----------------

func on_enemy_died(e: Node) -> void:
	## 怪物死亡：按 V0.1 dropLoot 掷掉落，散落在尸体周围的地面上
	var S: Dictionary = hero.progress.S
	var drops := FloorRules.roll_loot(loot_rng, maxi(1, floor_i), {"boss": e.def.get("boss", false), "champ": e.def.get("champ", "")}, S.mf, S.gf)
	var map := get_world_3d().navigation_map
	for d in drops:
		var g := GroundItem.make(d)
		stage.add_child(g)
		var a := loot_rng.randf() * TAU
		var r := loot_rng.randf_range(0.45, 1.5)
		var p: Vector3 = e.global_position + Vector3(cos(a), 0, sin(a)) * r
		p = NavigationServer3D.map_get_closest_point(map, p)
		g.global_position = Vector3(p.x, 0, p.z)


func _toggle_panel(p: Control) -> void:
	## 角色面板与背包面板同时只开一个
	for other in [char_panel, inv_panel, quest_panel]:
		if other != p and other.visible:
			other.close()
	p.toggle()


func _drop_item(it: Dictionary) -> void:
	## 背包里「丢在地上」：放在主角脚边，之后还能捡回来（V0.1 drop）
	var g := GroundItem.make({"item": it})
	stage.add_child(g)
	var a := loot_rng.randf() * TAU
	var p := NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, hero.global_position + Vector3(cos(a), 0, sin(a)) * 0.8)
	g.global_position = Vector3(p.x, 0, p.z)
	add_log("丢下 " + String(it.name), GroundItem.RARITY_COLORS[int(it.rarity)])


func add_log(text: String, c: Color) -> void:
	log_lines.append([text, c, 5.0])
	if log_lines.size() > 4:
		log_lines.pop_front()


func _show_banner(text: String) -> void:
	if banner:
		banner.text = text
		banner_t = 3.5
		# 竖屏时左上角说明文字占到屏幕三分之一以下：楼层名放到主角下方、摇杆上方
		var vs := get_viewport().get_visible_rect().size
		var portrait := vs.y > vs.x
		banner.offset_top = vs.y * 0.66 if portrait else 215.0
		banner.add_theme_font_size_override("font_size", 24 if portrait else 28)


# ---------------- 界面 ----------------

func _build_ui() -> void:
	# 暗角（在界面下面一层，只压暗 3D 画面）
	var vlayer := CanvasLayer.new()
	vlayer.layer = 0
	add_child(vlayer)
	vignette = ColorRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vm := ShaderMaterial.new()
	vm.shader = load("res://shaders/vignette.gdshader")
	vignette.material = vm
	vlayer.add_child(vignette)
	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	# 左上角一列：说明文字 → 职业资源条 →（手机上）状态文字，按内容高度往下排，互不重叠
	var top := VBoxContainer.new()
	top.anchor_right = 1.0
	top.offset_left = 16
	top.offset_top = 12
	top.offset_right = -16
	top.add_theme_constant_override("separation", 8)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(top)
	info = Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_font_size_override("font_size", 18)
	info.add_theme_color_override("font_color", Color(0.91, 0.52, 0.23))
	var how := "手机：左下摇杆移动；点敌人或按「攻击」打，「火 环 霜 闪」放技能，「血」「蓝」喝药，「城」开回城传送门；走到楼梯上换层" if DisplayServer.is_touchscreen_available() else "点地面移动；点敌人攻击（按住连打）；右键或 1、2、3、4 键：朝鼠标放技能（火球术、烬环斩、寂霜环、暗影闪现，随等级解锁）；Q / E 喝药；T 回城卷轴；C 属性；I 背包；J 任务；Tab 地图；WASD 移动；滚轮缩放"
	info.text = "余烬陷落 EMBERFALL · 大作版灰盒原型（移植 V0.1：P8 任务与传送）\n模型仍是占位几何体。点镇上的人对话、接任务、交易；北边修道院废墟里的阶梯通往地窖；镇中央的传送石能去到过的楼层。" + how
	top.add_child(info)
	pack_label = Label.new()
	pack_label.anchor_top = 1.0
	pack_label.anchor_bottom = 1.0
	pack_label.anchor_right = 1.0
	pack_label.offset_left = 16
	pack_label.offset_right = -16
	pack_label.offset_top = -56
	pack_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	pack_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pack_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pack_label.add_theme_font_size_override("font_size", 14)
	pack_label.add_theme_color_override("font_color", Color(0.85, 0.8, 0.7))
	layer.add_child(pack_label)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(box)
	# 等级与经验（P3）
	lvl_label = Label.new()
	lvl_label.add_theme_font_size_override("font_size", 15)
	lvl_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	box.add_child(lvl_label)
	xp_bar = _bar(Color(0.95, 0.75, 0.3), 6)
	xp_bar.max_value = 1.0
	xp_bar.step = 0.0
	box.add_child(xp_bar)
	# 生命条（占位；正式界面按 ART.md 第五节做成左下角的「火盆」）
	hp_bar = ProgressBar.new()
	hp_bar.custom_minimum_size = Vector2(220, 14)
	hp_bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	hp_bar.max_value = hero.max_hp
	hp_bar.show_percentage = false
	var hfill := StyleBoxFlat.new()
	hfill.bg_color = Color(0.75, 0.18, 0.12)
	hp_bar.add_theme_stylebox_override("fill", hfill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.07, 0.05, 0.8)
	hp_bar.add_theme_stylebox_override("background", bg)
	box.add_child(hp_bar)
	hp_label = Label.new()
	hp_label.add_theme_font_size_override("font_size", 14)
	hp_label.add_theme_color_override("font_color", Color(0.9, 0.82, 0.7))
	box.add_child(hp_label)
	# 法力（P3；P4 的四个技能消耗法力）与金币、药水
	mp_bar = _bar(Color(0.25, 0.42, 0.9), 12)
	box.add_child(mp_bar)
	mp_label = Label.new()
	mp_label.add_theme_font_size_override("font_size", 14)
	mp_label.add_theme_color_override("font_color", Color(0.75, 0.82, 1.0))
	box.add_child(mp_label)
	bag_label = Label.new()
	# 这两行会很长（P8 加了回城卷轴、任务消息）：不换行的标签会把左上角那一列撑宽，盖到小地图底下
	bag_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bag_label.add_theme_font_size_override("font_size", 14)
	bag_label.add_theme_color_override("font_color", Color(0.9, 0.82, 0.7))
	box.add_child(bag_label)
	log_label = Label.new()
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_label.add_theme_font_size_override("font_size", 14)
	log_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(log_label)
	dead_label = Label.new()
	dead_label.set_anchors_preset(Control.PRESET_CENTER)
	dead_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	dead_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	dead_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dead_label.add_theme_font_size_override("font_size", 30)
	dead_label.add_theme_color_override("font_color", Color(0.85, 0.2, 0.15))
	dead_label.text = "你倒下了\n3 秒后在本层入口复活"
	dead_label.visible = false
	layer.add_child(dead_label)
	# 换层时屏幕上方中间的楼层名（几秒后淡出）
	banner = Label.new()
	banner.anchor_left = 0.0
	banner.anchor_right = 1.0
	banner.offset_top = 215
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	banner.add_theme_font_size_override("font_size", 28)
	banner.add_theme_color_override("font_color", Color(1.0, 0.82, 0.5))
	banner.add_theme_color_override("font_outline_color", Color(0.08, 0.04, 0.02))
	banner.add_theme_constant_override("outline_size", 8)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.modulate.a = 0.0
	layer.add_child(banner)
	touch = TouchControls.new()
	layer.add_child(touch)
	if touch.visible:
		btn_attack = _touch_button(layer, "攻击", Vector2(-130, -150), 96)
		# 四个技能围在攻击键左上方一圈；药水在更外侧（P4）
		for sp in [["fireball", Vector2(-209, -134)], ["whirl", Vector2(-181, -205)], ["nova", Vector2(-112, -236)], ["blink", Vector2(-181, -63)]]:
			var sb := _touch_button(layer, "", sp[1], 60)
			var sid: String = sp[0]
			sb.pressed.connect(func(): hero.cast_skill(sid))
			skill_btns[sid] = sb
		btn_hp = _touch_button(layer, "血", Vector2(-282, -64), 52)
		btn_mp = _touch_button(layer, "蓝", Vector2(-282, -130), 52)
		btn_tp = _touch_button(layer, "城", Vector2(-282, -196), 52)
		btn_tp.pressed.connect(cast_town_portal)
		btn_hp.pressed.connect(func(): hero.drink_potion("hp"))
		btn_mp.pressed.connect(func(): hero.drink_potion("mp"))
		btn_attack.button_down.connect(func(): hero.attack_nearest(true))
		btn_attack.button_up.connect(func(): hero.attack_nearest(false))
		hero.ui_blockers = [btn_attack, btn_hp, btn_mp, btn_tp]
		hero.ui_blockers.append_array(skill_btns.values())
	touch.changed.connect(func(v: Vector2): hero.stick = v)
	# 说明文字会折到右上角那排按钮底下：整列从按钮下方开始（P7 手机、P8 起电脑也是四个按钮）
	top.offset_top = 64
	if touch.visible:
		# 手机上底部有摇杆和按钮：状态文字挪到左上角那一列的最后
		pack_label.get_parent().remove_child(pack_label)
		pack_label.anchor_top = 0.0
		pack_label.anchor_bottom = 0.0
		pack_label.anchor_right = 0.0
		pack_label.offset_left = 0
		pack_label.offset_right = 0
		pack_label.offset_top = 0
		pack_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		top.add_child(pack_label)
	if not touch.visible:
		skill_bar = SkillBar.new()
		skill_bar.hero = hero
		skill_bar.anchor_left = 0.5
		skill_bar.anchor_right = 0.5
		skill_bar.anchor_top = 1.0
		skill_bar.anchor_bottom = 1.0
		skill_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
		skill_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
		skill_bar.offset_bottom = -80   # 底部状态文字在 1280 宽时占两行，技能栏放在它上面
		layer.add_child(skill_bar)
		hero.ui_blockers.append(skill_bar)
	# 右上角「属性」按钮（电脑也能点；有未分配属性点时显示点数）与角色面板
	char_btn = _top_button(layer, 0, func(): _toggle_panel(char_panel))
	char_panel = CharPanel.new()
	layer.add_child(char_panel)
	char_panel.bind(hero)
	# 「背包」按钮（P6）在「属性」左边；两个面板同时只开一个
	# 不用 char_btn.duplicate()：那会把「属性」按钮的点击回调一起复制过来
	inv_btn = _top_button(layer, 1, func(): _toggle_panel(inv_panel))
	inv_panel = InvPanel.new()
	layer.add_child(inv_panel)
	inv_panel.bind(hero)
	inv_panel.drop_requested.connect(_drop_item)
	# 「任务」「地图」按钮（P8）接在「背包」左边；任务日志与另外两个面板同时只开一个
	quest_btn = _top_button(layer, 2, func(): _toggle_panel(quest_panel))
	quest_panel = QuestPanel.new()
	quest_panel.hero = hero
	layer.add_child(quest_panel)
	map_btn = _top_button(layer, 3, toggle_map)
	# 小地图在按钮下方；左上角那一列让出右边的位置
	minimap = Minimap.new()
	minimap.main = self
	layer.add_child(minimap)
	minimap.layout()
	get_viewport().size_changed.connect(minimap.layout)
	top.offset_right = -16 - (110 if touch.visible else 160) - 12
	for b in [quest_btn, quest_panel, map_btn]:
		hero.ui_blockers.append(b)
	dialog_panel = DialogPanel.new()
	layer.add_child(dialog_panel)
	shop_panel = ShopPanel.new()
	layer.add_child(shop_panel)
	hero.ui_blockers.append(dialog_panel)
	hero.ui_blockers.append(shop_panel)
	hero.talk_requested.connect(_talk)
	# 倒下后在烬原镇复活（V0.1 die → 在烬原镇复活）；在物理回调里不能换层，推迟到帧末
	hero.respawned.connect(func():
		if not use_test_area and floor_i != 0:
			call_deferred("go_floor", 0, "revive"))
	hero.ui_blockers.append(inv_btn)
	hero.ui_blockers.append(inv_panel)
	hero.ui_blockers.append(char_btn)
	hero.ui_blockers.append(char_panel)
	hero.message.connect(add_log)
	hero.progress.leveled.connect(func(lvl: int): _show_banner("升级！你现在是 %d 级\n获得 5 点属性点（按 C 或点「属性」分配）" % lvl))
	hero.died.connect(func(): dead_label.text = "你倒下了\n%s3 秒后在%s复活" % [("掉落 %d 金币；" % hero.last_gold_lost) if hero.last_gold_lost > 0 else "", "本层入口" if use_test_area else "烬原镇"])
	_refresh_labels()


func _bar(c: Color, h: float) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(220, h)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.show_percentage = false
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var f := StyleBoxFlat.new()
	f.bg_color = c
	b.add_theme_stylebox_override("fill", f)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.07, 0.05, 0.8)
	b.add_theme_stylebox_override("background", bg)
	return b


## 右上角一排按钮：0 属性、1 背包、2 任务、3 地图（从右往左）；手机上窄一些，四个放得进 360 像素宽
func _top_button(layer: CanvasLayer, idx: int, cb: Callable) -> Button:
	var narrow := DisplayServer.is_touchscreen_available()
	var w := 80.0 if narrow else 118.0
	var gap := 5.0 if narrow else 8.0
	var b := Button.new()
	b.anchor_left = 1.0
	b.anchor_right = 1.0
	b.offset_right = -16 - idx * (w + gap)
	b.offset_left = b.offset_right - w
	b.offset_top = 12
	b.offset_bottom = 56
	b.add_theme_font_size_override("font_size", 14 if narrow else 16)
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(cb)
	layer.add_child(b)
	return b


func _touch_button(layer: CanvasLayer, text: String, offset: Vector2, size: float) -> Button:
	var b := Button.new()
	b.text = text
	b.anchor_left = 1.0
	b.anchor_right = 1.0
	b.anchor_top = 1.0
	b.anchor_bottom = 1.0
	b.offset_left = offset.x
	b.offset_top = offset.y
	b.offset_right = offset.x + size
	b.offset_bottom = offset.y + size
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 18 if size > 80 else 15)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.35, 0.16, 0.08, 0.75)
	sb.border_color = Color(0.79, 0.64, 0.35)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(int(size / 2))
	b.add_theme_stylebox_override("normal", sb)
	var sp := sb.duplicate()
	sp.bg_color = Color(0.6, 0.28, 0.1, 0.9)
	b.add_theme_stylebox_override("pressed", sp)
	b.add_theme_stylebox_override("hover", sb)
	var sd := sb.duplicate()
	sd.bg_color = Color(0.15, 0.12, 0.1, 0.6)
	b.add_theme_stylebox_override("disabled", sd)
	layer.add_child(b)
	return b


func apply_quality(tier: String) -> void:
	## 画质分档（TECH.md 第 5.1 节）：
	##   low（手机默认）：3D 渲染 0.75 倍分辨率、关闭实时阴影与泛光，保留光晕贴片、假阴影与暗角
	##   medium（电脑默认）：原分辨率、月光阴影、泛光
	##   high：再加 2 倍多重采样抗锯齿、火把点光源阴影
	if not tier in Look.TIERS:
		tier = Look.default_tier()
	quality = tier
	var vp := get_viewport()
	vp.scaling_3d_scale = 0.75 if tier == "low" else 1.0
	vp.msaa_3d = Viewport.MSAA_2X if tier == "high" else Viewport.MSAA_DISABLED
	moon.shadow_enabled = tier != "low"
	environment.glow_enabled = tier != "low"
	for tch in torches:
		tch.set_quality(tier)
	_refresh_labels()


func _input(event: InputEvent) -> void:
	# Tab 在界面里默认用来切换焦点，所以在这里先接住（面板打开时不管）
	if event is InputEventKey and event.is_pressed() and not event.is_echo() and event.is_action("map_toggle") and not get_tree().paused:
		toggle_map()
		get_viewport().set_input_as_handled()


func _unhandled_key_input(event: InputEvent) -> void:
	# Q / E 喝药，C 打开角色面板（面板打开时由面板自己处理 C / Esc）
	if event.is_pressed() and not event.is_echo():
		if event.is_action("potion_hp"):
			hero.drink_potion("hp")
		elif event.is_action("potion_mp"):
			hero.drink_potion("mp")
		elif event.is_action("char_panel") and not char_panel.visible:
			_toggle_panel(char_panel)
			get_viewport().set_input_as_handled()
			return
		elif event.is_action("inv_panel") and not inv_panel.visible:
			_toggle_panel(inv_panel)
			get_viewport().set_input_as_handled()
			return
		elif event.is_action("quest_panel") and not quest_panel.visible:
			_toggle_panel(quest_panel)
			get_viewport().set_input_as_handled()
			return
		elif event.is_action("town_portal"):
			cast_town_portal()
		elif event.is_action("ui_cancel") and minimap.big:
			minimap.set_big(false)
			get_viewport().set_input_as_handled()
			return
	# F7：轮换画质档（开发与试玩用；正式设置界面在后续步骤）
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F7:
		apply_quality(Look.TIERS[(Look.TIERS.find(quality) + 1) % Look.TIERS.size()])


func _refresh_labels() -> void:
	if pack_label:
		var lines := [FloorRules.floor_name(floor_i) if floor_i > 0 else ("测试区" if use_test_area else "烬原镇"), pack_state, "导航烘焙 %.0f 毫秒" % nav_bake_ms]
		if nav_state != "":
			lines.append(nav_state)
		lines.append("渲染器：%s" % RenderingServer.get_current_rendering_method())
		lines.append("画质：%s（F7 切换）" % {"low": "低", "medium": "中", "high": "高"}.get(quality, "?"))
		pack_label.text = "　·　".join(lines)
