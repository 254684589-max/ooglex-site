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
var res_bar: ProgressBar
var res_label: Label
var lvl_label: Label
var xp_bar: ProgressBar
var mp_bar: ProgressBar
var mp_label: Label
var bag_label: Label
var char_btn: Button
var btn_hp: Button
var btn_mp: Button
var char_panel: CharPanel
var btn_attack: Button
var btn_stomp: Button
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
var floor_i := 0
var run_seed := 0
var dungeon: Dictionary = {}
var floor_info: Dictionary = {}
var stairs: Dictionary = {}
var stair_lock := 0.0
var banner: Label
var banner_t := 0.0


func _ready() -> void:
	_build_world()
	_build_ui()
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
	var sp := camera.unproject_position(dummies[0].global_position + Vector3(0, 1.0, 0)) * get_window().content_scale_factor
	print("EF_DUMMY_SCREEN x=%d y=%d" % [sp.x, sp.y])
	var ss := camera.unproject_position(TEST_STAIRS) * get_window().content_scale_factor
	print("EF_STAIRS_SCREEN x=%d y=%d" % [ss.x, ss.y])
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
	if banner:
		banner_t = maxf(0.0, banner_t - delta)
		banner.modulate.a = clampf(banner_t, 0.0, 1.0)
	if res_bar and hero:
		var k: EmberguardKit = hero.kit
		res_bar.value = k.resource
		var cd: float = k.cooldowns.get("scorch_stomp", 0.0)
		var cost: int = Balance.skill("scorch_stomp").cost
		res_label.text = "誓火 %d / %d　焚地践踏：%s" % [k.resource, k.resource_max, ("冷却 %.1f 秒" % cd) if cd > 0.0 else ("可用" if k.resource >= cost else "誓火不足（需要 %d）" % cost)]
		if btn_stomp:
			btn_stomp.disabled = not k.can_cast("scorch_stomp")
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
		bag_label.text = "金币 %d　生命药水 ×%d%s　法力药水 ×%d%s" % [sh.gold, sh.pots.hp, "（Q）" if keys else "", sh.pots.mp, "（E）" if keys else ""]
		char_btn.text = ("属性 +%d" % sh.pts) if sh.pts > 0 else ("属性（C）" if keys else "属性")
		if btn_hp:
			btn_hp.text = "血 %d" % sh.pots.hp
			btn_mp.text = "蓝 %d" % sh.pots.mp
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
	_build_test_area()
	hero.respawn_point = Vector3.ZERO


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
	if f == 0:
		_build_test_area()
		floor_info = {}
		dungeon = {}
		hero.global_position = TEST_STAIRS + Vector3(-2.4, 0, 1.2) if via == "up" else Vector3.ZERO
	else:
		_new_stage()
		dungeon = DungeonGen.generate(f, seed_for(f))
		floor_info = DungeonBuilder.build(stage, dungeon, {
			"seed": seed_for(f), "on_stairs": _on_stairs,
			"down_caption": "↓ " + FloorRules.floor_name(f + 1),
			"up_caption": ("↑ " + FloorRules.floor_name(f - 1)) if f > 1 else "↑ 返回测试区"})
		level = floor_info.region
		torches.assign(floor_info.torches)
		stairs = floor_info.stairs
		nav_bake_ms = floor_info.nav_ms
		var at: Vector2i = dungeon.up
		if via == "up" and floor_info.down_cell.x >= 0:
			at = floor_info.down_cell
		hero.global_position = DungeonBuilder.cell_center(DungeonGen.near_free(dungeon, at))
		Look.apply_theme(environment, dungeon.theme)
	hero.respawn_point = hero.global_position
	camera.snap()
	apply_quality(quality)
	stair_lock = 0.8
	var fname := FloorRules.floor_name(f) if f > 0 else "测试区 · 灰盒房间与大厅"
	_show_banner(fname + ("\n本层还没有怪物（后续步骤接入）" if f > 0 else ""))
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("EF_FLOOR n=%d theme=%s total_ms=%.1f nav_ms=%.1f chunks=%d torches=%d" % [f, dungeon.get("theme", "test"), ms, nav_bake_ms, floor_info.get("chunks", 0), torches.size()])


func _on_hero_arrived() -> void:
	## 给网页冒烟测试用：主角走到后（镜头跟上之后）再报一次测试区楼梯的屏幕坐标
	if floor_i != 0 or not OS.has_feature("web"):
		return
	await get_tree().create_timer(1.0).timeout
	if floor_i == 0:
		var ss := camera.unproject_position(TEST_STAIRS) * get_window().content_scale_factor
		print("EF_STAIRS_SCREEN x=%d y=%d" % [ss.x, ss.y])


func _show_banner(text: String) -> void:
	if banner:
		banner.text = text
		banner_t = 3.5
		# 竖屏时左上角说明文字占到屏幕三分之一以下：楼层名放到主角下方、摇杆上方
		var vs := get_viewport().get_visible_rect().size
		var portrait := vs.y > vs.x
		banner.offset_top = vs.y * 0.66 if portrait else 150.0
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
	var how := "手机：左下摇杆移动；点敌人或按「攻击」打，「践踏」放技能，「血」「蓝」喝药；走到楼梯上换层" if DisplayServer.is_touchscreen_available() else "点地面移动；点敌人攻击（按住连打）；右键或 1 键：焚地践踏；Q / E 喝药；C 属性；WASD 移动；滚轮缩放；走到楼梯上换层"
	info.text = "余烬陷落 EMBERFALL · 大作版灰盒原型（移植 V0.1：P3 角色成长）\n模型仍是占位几何体。南边大厅的怪物给经验，升级得属性点；房间东北角的楼梯通往随机地下城（暂无怪物）。" + how
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
	# 职业资源条（占位；正式界面按 ART.md 第五节做成环绕技能栏的火焰）
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
	res_bar = ProgressBar.new()
	res_bar.custom_minimum_size = Vector2(220, 14)
	res_bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	res_bar.max_value = hero.kit.resource_max
	res_bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.91, 0.52, 0.23)
	res_bar.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.07, 0.05, 0.8)
	res_bar.add_theme_stylebox_override("background", bg)
	box.add_child(res_bar)
	res_label = Label.new()
	res_label.add_theme_font_size_override("font_size", 14)
	res_label.add_theme_color_override("font_color", Color(0.9, 0.82, 0.7))
	box.add_child(res_label)
	# 生命条（占位；正式界面按 ART.md 第五节做成左下角的「火盆」）
	hp_bar = ProgressBar.new()
	hp_bar.custom_minimum_size = Vector2(220, 14)
	hp_bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	hp_bar.max_value = hero.max_hp
	hp_bar.show_percentage = false
	var hfill := StyleBoxFlat.new()
	hfill.bg_color = Color(0.75, 0.18, 0.12)
	hp_bar.add_theme_stylebox_override("fill", hfill)
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
	bag_label.add_theme_font_size_override("font_size", 14)
	bag_label.add_theme_color_override("font_color", Color(0.9, 0.82, 0.7))
	box.add_child(bag_label)
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
	banner.offset_top = 150
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
		btn_stomp = _touch_button(layer, "践踏", Vector2(-230, -110), 72)
		btn_hp = _touch_button(layer, "血", Vector2(-300, -66), 56)
		btn_mp = _touch_button(layer, "蓝", Vector2(-214, -192), 56)
		btn_hp.pressed.connect(func(): hero.drink_potion("hp"))
		btn_mp.pressed.connect(func(): hero.drink_potion("mp"))
		btn_attack.button_down.connect(func(): hero.attack_nearest(true))
		btn_attack.button_up.connect(func(): hero.attack_nearest(false))
		btn_stomp.pressed.connect(func(): hero.cast_skill("scorch_stomp"))
		hero.ui_blockers = [btn_attack, btn_stomp, btn_hp, btn_mp]
	touch.changed.connect(func(v: Vector2): hero.stick = v)
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
	# 右上角「属性」按钮（电脑也能点；有未分配属性点时显示点数）与角色面板
	char_btn = Button.new()
	char_btn.anchor_left = 1.0
	char_btn.anchor_right = 1.0
	char_btn.offset_left = -150
	char_btn.offset_right = -16
	char_btn.offset_top = 12
	char_btn.offset_bottom = 56
	char_btn.add_theme_font_size_override("font_size", 16)
	char_btn.focus_mode = Control.FOCUS_ALL
	char_btn.pressed.connect(func(): char_panel.toggle())
	layer.add_child(char_btn)
	char_panel = CharPanel.new()
	layer.add_child(char_panel)
	char_panel.bind(hero)
	hero.ui_blockers.append(char_btn)
	hero.ui_blockers.append(char_panel)
	hero.progress.leveled.connect(func(lvl: int): _show_banner("升级！你现在是 %d 级\n获得 5 点属性点（按 C 或点「属性」分配）" % lvl))
	hero.died.connect(func(): dead_label.text = "你倒下了\n%s3 秒后在本层入口复活" % (("掉落 %d 金币；" % hero.last_gold_lost) if hero.last_gold_lost > 0 else ""))
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


func _unhandled_key_input(event: InputEvent) -> void:
	# Q / E 喝药，C 打开角色面板（面板打开时由面板自己处理 C / Esc）
	if event.is_pressed() and not event.is_echo():
		if event.is_action("potion_hp"):
			hero.drink_potion("hp")
		elif event.is_action("potion_mp"):
			hero.drink_potion("mp")
		elif event.is_action("char_panel") and not char_panel.visible:
			char_panel.open()
			get_viewport().set_input_as_handled()
			return
	# F7：轮换画质档（开发与试玩用；正式设置界面在后续步骤）
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F7:
		apply_quality(Look.TIERS[(Look.TIERS.find(quality) + 1) % Look.TIERS.size()])


func _refresh_labels() -> void:
	if pack_label:
		var lines := [FloorRules.floor_name(floor_i) if floor_i > 0 else "测试区", pack_state, "导航烘焙 %.0f 毫秒" % nav_bake_ms]
		if nav_state != "":
			lines.append(nav_state)
		lines.append("渲染器：%s" % RenderingServer.get_current_rendering_method())
		lines.append("画质：%s（F7 切换）" % {"low": "低", "medium": "中", "high": "高"}.get(quality, "?"))
		pack_label.text = "　·　".join(lines)
