extends Node
## 自动化测试：无界面运行（结构沿用 games/working-life/godot/tests/test_runner.gd）。
##   godot --headless --path games/emberfall3d/godot res://tests/test_runner.tscn -- [测试组 ...] [--pack=/abs/path/ch_test.pck]
## 全部通过时退出码为 0，否则为 1。

var failures: Array = []
var checks := 0
var only: Array = []
var pack_path := ""
var current_group := ""


func _ready() -> void:
	var dog := Timer.new()
	dog.wait_time = 120.0
	dog.one_shot = true
	dog.timeout.connect(func():
		print("WATCHDOG TIMEOUT in group: ", current_group)
		get_tree().quit(2))
	add_child(dog)
	dog.start()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--pack="):
			pack_path = a.substr(7)
		else:
			only.append(a)
	for g in ["boot", "look", "camera", "move", "damage", "combat", "monsters", "perf", "pack", "port", "dungeon", "growth", "skills", "loot", "inventory", "town", "quests", "bosses", "props", "save", "parity", "fx"]:
		if not only.is_empty() and not only.has(g):
			continue
		print("\n== %s" % g)
		current_group = g
		await call("test_" + g)
	print("")
	if failures.is_empty():
		print("ALL %d CHECKS PASSED" % checks)
		get_tree().quit(0)
	else:
		print("%d / %d CHECKS FAILED:" % [failures.size(), checks])
		for f in failures:
			print("  - " + f)
		get_tree().quit(1)


func check(cond: bool, what: String) -> void:
	checks += 1
	if cond:
		print("  ok   " + what)
	else:
		print("  FAIL " + what)
		failures.append(what)


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func seconds(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func test_boot() -> void:
	check(ProjectSettings.get_setting("rendering/renderer/rendering_method") == "gl_compatibility", "工程使用兼容渲染器（网页导出唯一支持的渲染器）")
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.use_test_area = true      # 第 0 层用灰盒测试区（P7 起默认是烬原镇）
	main.auto_pack_test = false
	main.run_nav_bench = false
	main.spawn_monsters = false
	add_child(main)
	await frames(3)
	check(main.camera != null and main.camera.current, "斜俯视相机已创建并设为当前相机")
	var fwd: Vector3 = -main.camera.global_transform.basis.z
	var pitch := rad_to_deg(asin(-fwd.y))
	check(absf(pitch - main.PITCH_DEG) < 3.0, "相机俯角约 55°（实测 %.1f°）" % pitch)
	check(main.hero != null, "主角占位体已创建")
	check(main.info.text.contains("占位"), "画面明确标注「占位几何体」")
	check(FileAccess.file_exists("res://assets/fonts/NotoSansSC-EF.ttf"), "中文字体已打包")
	main.queue_free()
	await frames(1)


func test_camera() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.use_test_area = true      # 第 0 层用灰盒测试区（P7 起默认是烬原镇）
	main.auto_pack_test = false
	main.run_nav_bench = false
	main.spawn_monsters = false
	add_child(main)
	await frames(3)
	var cam: IsoCamera = main.camera
	var hero: Node3D = main.hero
	check(cam.target == hero, "相机跟随目标是主角")
	var fwd: Vector3 = -cam.global_transform.basis.z
	check(absf(rad_to_deg(asin(-fwd.y)) - 55.0) < 0.5, "俯角固定 55°")

	# 平滑跟随：瞬移主角后相机不会立刻跳过去，约 1 秒内追上
	hero.position = Vector3(4, 0, 0)
	await frames(1)
	var lag := cam.focus.distance_to(hero.global_position)
	check(lag > 1.0, "瞬移后第一帧相机仍在追赶（平滑，不硬切）：落后 %.2f 米" % lag)
	await seconds(1.2)
	lag = cam.focus.distance_to(hero.global_position)
	check(lag < 0.15, "1.2 秒后相机追上主角：落后 %.3f 米" % lag)
	var yaw_before := cam.global_rotation.y
	hero.rotation.y = 2.0
	await frames(2)
	check(is_equal_approx(cam.global_rotation.y, yaw_before), "主角转身时相机不跟着转（固定偏航）")
	cam.snap()
	check(cam.focus.distance_to(hero.global_position) < 0.001, "snap() 立即对准（切换区域用）")

	# 遮挡半透明：主角站到南墙（z = 6）后面，墙挡在相机与主角之间
	hero.position = Vector3(-3.6, 0, 5.1)
	cam.snap()
	await seconds(0.6)
	var faded := 0
	for m in cam.fade.keys():
		var mat := (m as MeshInstance3D).material_override as StandardMaterial3D
		if mat.albedo_color.a < 0.5 and mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA:
			faded += 1
	check(faded >= 1, "挡住主角的墙变成半透明（%d 个物体）" % faded)
	hero.position = Vector3(-1, 0, -2)
	cam.snap()
	await seconds(0.6)
	check(cam.fade.is_empty(), "主角离开后墙体恢复不透明")

	# 缩放范围
	for i in 20:
		cam.zoom_by(1.0)
	check(is_equal_approx(cam.distance, cam.max_distance), "缩放不超过最远 %.0f 米" % cam.max_distance)
	for i in 20:
		cam.zoom_by(-1.0)
	check(is_equal_approx(cam.distance, cam.min_distance), "缩放不低于最近 %.0f 米" % cam.min_distance)
	cam.distance = 15.0

	# 手机竖屏：视野宽度与界面缩放（修复阶段 1.1 的问题）
	var w_phone := cam.visible_width_at_focus(Vector2(360, 740))
	var w_desk := cam.visible_width_at_focus(Vector2(1280, 720))
	check(w_phone >= 11.0, "手机竖屏 360×740 在主角处能看到 %.1f 米宽（≥ 11 米）" % w_phone)
	check(w_desk >= 18.0, "电脑 1280×720 能看到 %.1f 米宽" % w_desk)
	var ui_scale = load("res://core/ui_scale.gd")
	check(is_equal_approx(ui_scale.scale_for(Vector2(1280, 720)), 1.0), "界面缩放：1280×720 = 1.0")
	check(is_equal_approx(ui_scale.scale_for(Vector2(1920, 1080)), 1.5), "界面缩放：1920×1080 = 1.5")
	check(ui_scale.scale_for(Vector2(360, 740)) >= 0.75, "界面缩放：手机竖屏不低于 0.75（1.1 版约 0.28，文字过小）")
	check(ui_scale.scale_for(Vector2(768, 1024)) > 1.3 and ui_scale.scale_for(Vector2(768, 1024)) < 1.5, "界面缩放：平板竖屏约 1.42")

	# 屏幕震动会自行衰减，也可关闭
	cam.add_trauma(0.8)
	await frames(2)
	check(absf(cam.h_offset) + absf(cam.v_offset) > 0.0, "震动生效")
	await seconds(0.8)
	check(cam.trauma == 0.0, "震动在 0.8 秒内衰减完")
	cam.shake_enabled = false
	cam.add_trauma(1.0)
	await frames(2)
	check(cam.h_offset == 0.0 and cam.v_offset == 0.0, "关闭震动后不再晃动（无障碍设置）")
	main.queue_free()
	await frames(1)


func info(text: String) -> void:
	print("  info " + text)


func physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func test_move() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.use_test_area = true      # 第 0 层用灰盒测试区（P7 起默认是烬原镇）
	main.auto_pack_test = false
	main.run_nav_bench = false
	main.spawn_monsters = false
	add_child(main)
	await physics(4)
	var hero: Player = main.hero
	var cam: IsoCamera = main.camera
	var map := hero.get_world_3d().navigation_map
	check(main.level.navigation_mesh.get_polygon_count() > 0, "房间导航网格已烘焙：%d 个多边形，用时 %.1f 毫秒" % [main.level.navigation_mesh.get_polygon_count(), main.nav_bake_ms])
	check(InputMap.has_action("move_up") and InputMap.has_action("move_right"), "键盘移动动作已注册（WASD / 方向键）")

	# 寻路绕墙：房间中心 → 南墙外，直线穿墙，路径必须从缺口绕出去
	var a := Vector3(0, 0, 0)
	var b := Vector3(-3.5, 0, 8.0)
	# 导航地图在烘焙后的下一两个物理帧才同步完成：等到能查出路径再测（最多 60 帧）
	var path := PackedVector3Array()
	for i in 60:
		path = NavigationServer3D.map_get_path(map, a, b, true)
		if path.size() > 0:
			break
		await physics(1)
	var plen := 0.0
	for i in range(1, path.size()):
		plen += path[i - 1].distance_to(path[i])
	var via_gap := false
	for pt in path:
		if pt.x > -1.3 and pt.z > 5.0 and pt.z < 7.0:
			via_gap = true
	check(path.size() >= 3 and plen > a.distance_to(b) + 0.8, "路径绕开南墙：路径 %.1f 米 > 直线 %.1f 米" % [plen, a.distance_to(b)])
	check(via_gap, "路径经过南墙的缺口（x > -1）")

	# 点击移动：走到房间外，能到达并发出 arrived
	var got := [false]
	hero.arrived.connect(func(): got[0] = true)
	hero.move_to(b)
	for i in 400:
		await physics(1)
		if got[0]:
			break
	var end := hero.global_position
	check(got[0], "点击移动到达目标并发出到达信号")
	check(Vector2(end.x - hero.last_target.x, end.z - hero.last_target.z).length() < 0.2, "到达位置与目标相差 %.2f 米" % Vector2(end.x - hero.last_target.x, end.z - hero.last_target.z).length())

	# 目标点在墙里：取导航网格上最近的可走点（可能在墙的另一侧，那就绕过去），不会卡进墙
	hero.global_position = Vector3(0, 0, 0)
	await physics(2)
	hero.move_to(Vector3(0, 0, -5.8))   # 墙体 z ∈ [-6.3, -5.7]，这个点离房间内侧更近
	for i in 300:
		await physics(1)
		if not hero.moving_to:
			break
	var z := hero.global_position.z
	check(z > -5.75 and z < -4.6, "目标在墙体内部时停在墙前 1 米内（z = %.2f，墙面 -5.7）" % z)
	check(not hero.moving_to, "到达最近可走点后停止移动")

	# 屏幕中心拾取到主角附近的地面
	cam.snap()
	await physics(1)
	var center: Vector2 = main.get_viewport().get_visible_rect().size * 0.5
	var p = hero.pick_ground(center)
	check(p != null and Vector2(p.x - cam.focus.x, p.z - cam.focus.z).length() < 2.0, "屏幕中心拾取到相机跟随点附近的地面")

	# 摇杆「上」= 远离相机的方向
	hero.global_position = Vector3(2, 0, 2)
	await physics(2)
	var start := hero.global_position
	hero.stick = Vector2(0, -1)
	await seconds(0.5)
	hero.stick = Vector2.ZERO
	var moved := hero.global_position - start
	var fwd := Vector3(-sin(deg_to_rad(cam.yaw_deg)), 0, -cos(deg_to_rad(cam.yaw_deg)))
	check(moved.length() > 1.5 and moved.normalized().dot(fwd) > 0.95, "摇杆向上：朝屏幕上方移动 %.1f 米" % moved.length())
	check(not hero.moving_to, "使用摇杆时取消点击移动")

	# 顶着墙推：不会穿墙，并沿墙滑动
	hero.global_position = Vector3(0, 0, -2)
	await physics(2)
	hero.stick = Vector2(0, -1)
	await seconds(2.5)
	hero.stick = Vector2.ZERO
	var q := hero.global_position
	check(q.z > -5.75 and q.x > -5.75, "顶墙推 2.5 秒不穿墙（x = %.2f, z = %.2f）" % [q.x, q.z])
	check(Vector2(q.x, q.z).length() > 4.0, "撞墙后沿墙滑到角落附近")

	# 键盘（可选）
	hero.global_position = Vector3(0, 0, 2)
	await physics(2)
	start = hero.global_position
	Input.action_press("move_right")
	await seconds(0.4)
	Input.action_release("move_right")
	var right := Vector3(cos(deg_to_rad(cam.yaw_deg)), 0, -sin(deg_to_rad(cam.yaw_deg)))
	moved = hero.global_position - start
	check(moved.length() > 1.0 and moved.normalized().dot(right) > 0.9, "键盘 D：朝屏幕右方移动")

	# 虚拟摇杆控件：触点在左下区域时认领并输出方向
	var tc: TouchControls = main.touch
	var vs: Vector2 = main.get_viewport().get_visible_rect().size
	check(tc.in_zone(vs * Vector2(0.1, 0.9)) and not tc.in_zone(vs * Vector2(0.9, 0.9)) and not tc.in_zone(vs * Vector2(0.1, 0.2)), "摇杆只认领屏幕左下区域的触点")
	main.queue_free()
	await frames(1)

	# 整层地下城的运行时烘焙耗时（本机原生；网页上的数字由 EF_NAV_BENCH 日志给出）
	var bench := NavBuilder.bench_dungeon(7, 0.25)
	print("  info 整层地下城（%d 个房间、%d 格地面）烘焙 %.0f 毫秒，%d 个多边形" % [bench.rooms, bench.floor_tiles, bench.ms, bench.polygons])
	check(bench.polygons > 50, "整层地下城导航网格生成成功")
	var bench2 := NavBuilder.bench_dungeon(7, 0.4)
	print("  info 同一层用 0.4 米格子烘焙 %.0f 毫秒" % bench2.ms)


func test_look() -> void:
	# 阶段 2.3：程序化贴图、环境、火把、假阴影、画质分档
	var ft := Look.floor_texture()
	var bt := Look.brick_texture()
	check(ft.get_width() == 256 and bt.get_width() == 256, "程序生成地面石板与砖墙贴图（256×256，不用外部素材）")
	check(Look.floor_texture() == ft, "贴图全局缓存，只生成一次")
	var img := ft.get_image()
	var lum := {}
	for i in 200:
		var c := img.get_pixel((i * 37) % 256, (i * 91) % 256)
		lum[snappedf(c.get_luminance(), 0.02)] = true
	check(lum.size() > 8, "石板贴图有明暗变化（灰缝、倒角、颗粒），不是纯色")
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.use_test_area = true      # 第 0 层用灰盒测试区（P7 起默认是烬原镇）
	main.auto_pack_test = false
	main.run_nav_bench = false
	add_child(main)
	await frames(3)
	check(main.torches.size() == 4, "场景里有 4 支火把（房间 1、大厅 3）")
	check(main.hero.find_child("BlobShadow", false, false) != null, "主角脚下有圆形假阴影")
	check(main.monsters.size() > 0 and main.monsters[0].find_child("BlobShadow", false, false) != null, "怪物脚下有圆形假阴影")
	check(main.environment.fog_enabled and main.environment.adjustment_enabled, "环境：雾 + 调色")
	check(main.vignette != null and main.vignette.material is ShaderMaterial, "暗角着色器")
	main.apply_quality("low")
	var vp: Viewport = main.get_viewport()
	check(is_equal_approx(vp.scaling_3d_scale, 0.75) and not main.moon.shadow_enabled and not main.environment.glow_enabled, "低画质：0.75 倍 3D 分辨率、关闭实时阴影与泛光")
	main.apply_quality("medium")
	check(is_equal_approx(vp.scaling_3d_scale, 1.0) and main.moon.shadow_enabled and main.environment.glow_enabled and vp.msaa_3d == Viewport.MSAA_DISABLED, "中画质：原分辨率、月光阴影、泛光")
	main.apply_quality("high")
	check(vp.msaa_3d == Viewport.MSAA_2X and main.torches[0].light.shadow_enabled, "高画质：2 倍抗锯齿、火把投射阴影")
	main.apply_quality("bogus")
	check(main.quality == Look.default_tier(), "未知画质名回落到默认档（电脑：中）")
	main.queue_free()
	await frames(2)


func test_damage() -> void:
	# 纯公式（GDD.md 第 4.2 节）
	check(absf(DamageCalc.armor_reduction(30, 1) - 30.0 / 88.0) < 0.0001, "护甲减伤 = 30 / (30 + 40 + 18×1) = %.3f" % DamageCalc.armor_reduction(30, 1))
	check(is_equal_approx(DamageCalc.armor_reduction(100000, 1), 0.75), "护甲减伤上限 75%")
	check(is_equal_approx(DamageCalc.resist_reduction(50, 1), 0.70), "抗性减伤上限 70%（50 / 55 超过上限）")
	check(DamageCalc.resist_reduction(0, 5) == 0.0, "没有抗性时不减伤")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var atk := {"level": 1, "main_stat": 20, "weapon_min": 10, "weapon_max": 10, "damage_bonus": 0.0, "crit_chance": 0.0}
	var r := DamageCalc.roll(atk, 1.0, "physical", {"armor": 0}, rng)
	check(r.amount == 12 and not r.crit, "武器 10 × 系数 1 × (1 + 20/100) = 12（实得 %d）" % r.amount)
	atk.crit_chance = 1.0
	r = DamageCalc.roll(atk, 1.0, "physical", {"armor": 0}, rng)
	check(r.amount == 18 and r.crit, "暴击 +50%%：18（实得 %d）" % r.amount)
	atk.crit_chance = 0.0
	r = DamageCalc.roll(atk, 1.0, "fire", {"armor": 0, "resist": {"fire": 50}}, rng)
	check(r.amount == 4, "火焰抗性 50（封顶 70%%）：12 × 0.3 ≈ 4（实得 %d）" % r.amount)
	r = DamageCalc.roll(atk, 1.0, "void", {"armor": 0, "resist": {"void": 50}}, rng)
	check(r.amount == 12, "「虚」伤害无视抗性：12（实得 %d）" % r.amount)
	atk.erase("crit_chance")
	var crits := 0
	for i in 4000:
		if DamageCalc.roll(atk, 1.0, "physical", {}, rng).crit:
			crits += 1
	check(crits > 140 and crits < 260, "基础暴击率约 5%%：4000 次中 %d 次" % crits)


func test_combat() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.use_test_area = true      # 第 0 层用灰盒测试区（P7 起默认是烬原镇）
	main.auto_pack_test = false
	main.run_nav_bench = false
	main.spawn_monsters = false
	add_child(main)
	await physics(4)
	var hero: Player = main.hero
	var cam: IsoCamera = main.camera
	var d0: TrainingDummy = main.dummies[0]
	var d1: TrainingDummy = main.dummies[1]
	hero.rng.seed = 42
	hero.stats = hero.stats.duplicate()
	hero.stats["crit_chance"] = 0.0      # 先测普通命中

	# 断誓斩：站在木桩左侧 1.4 米、面朝它；另一个木桩放到身后
	hero.global_position = Vector3(0.8, 0, -1.2)
	d1.home = Vector3(-0.7, 0, -1.2)
	d1.global_position = d1.home
	await physics(2)
	hero.face_point(d0.global_position)
	var seen := {}
	hero.hit_landed.connect(func(id, hits):
		seen["id"] = id
		seen["hits"] = hits
		seen["hero_stop"] = hero.hitstop_t
		seen["dummy_stop"] = d0.hitstop_t
		seen["flash"] = d0.flash_t
		seen["trauma"] = cam.trauma, CONNECT_ONE_SHOT)
	var labels_before := _count_numbers(main)
	hero.attack_target = d0
	var hp0 := d0.hp
	await physics(12)
	check(seen.get("id") == "oath_cleave" and seen.get("hits") == 1, "断誓斩命中正前方的木桩（只命中 1 个）")
	check(d0.hp < hp0, "木桩掉血 %d" % (hp0 - d0.hp))
	check(d1.hp == d1.max_hp, "身后的木桩不在扇形范围内，没被打到")
	check(absf(seen.get("hero_stop", 0.0) - 0.04) < 0.001 and absf(seen.get("dummy_stop", 0.0) - 0.04) < 0.001, "命中停顿：攻击方与受击方各冻结 40 毫秒")
	check(seen.get("flash", 0.0) > 0.09, "受击闪白 0.1 秒")
	check(seen.get("trauma", 0.0) > 0.0, "命中时镜头震动")
	check(_count_numbers(main) > labels_before, "弹出伤害数字")
	var peak := 0.0
	for i in 30:
		peak = maxf(peak, Vector2(d0.global_position.x - d0.home.x, d0.global_position.z - d0.home.z).length())
		await physics(1)
	check(peak > 0.25 and peak < 0.7, "木桩被击退 %.2f 米（设计 0.3–0.6 米）" % peak)
	var disp := 0.0
	await seconds(2.0)
	disp = Vector2(d0.global_position.x - d0.home.x, d0.global_position.z - d0.home.z).length()
	check(disp < 0.1, "击退后木桩回到原位")
	check(hero.attack_target == null and hero.action == "", "单击只打一下：打完清除目标")

	# 暴击：停顿 80 毫秒、数字变大
	hero.stats["crit_chance"] = 1.0
	hero.face_point(d0.global_position)
	var crit_seen := {}
	hero.hit_landed.connect(func(id, hits): crit_seen["stop"] = hero.hitstop_t, CONNECT_ONE_SHOT)
	hero.attack_target = d0
	await physics(12)
	check(absf(crit_seen.get("stop", 0.0) - 0.08) < 0.001, "暴击命中停顿 80 毫秒")
	hero.stats["crit_chance"] = 0.0

	# 关闭伤害数字（无障碍设置）
	HitFeedback.numbers_enabled = false
	var n_before := _count_numbers(main)
	hero.face_point(d0.global_position)
	hero.attack_target = d0
	await physics(12)
	check(_count_numbers(main) <= n_before, "关闭伤害数字后不再弹出")
	HitFeedback.numbers_enabled = true
	await seconds(1.0)

	# 技能（P4 起为 V0.1 流浪者的四个技能）见 skills 组
	# 把第二个木桩挪开（原先由这里的焚地践踏测试挪开；否则它正好挡在下面「点击木桩」的路上，主角会被卡住）
	d1.home = Vector3(0.8, 0, 0.6)
	d1.global_position = d1.home
	await physics(2)

	# 死亡与复活
	d0.hp = 1.0
	hero.face_point(d0.global_position)
	hero.attack_target = d0
	await physics(12)
	check(d0.dead and d0.collision_layer == 0, "生命归零后倒下，不再可被选中")
	await seconds(d0.stats.respawn_s + 0.4)
	check(not d0.dead and d0.hp == d0.max_hp, "数秒后原地复活、满血")

	# 点击木桩：先走过去再打
	hero.global_position = Vector3(-3.0, 0, -1.0)
	cam.snap()
	await physics(3)
	var sp := cam.unproject_position(d0.global_position + Vector3(0, 1.0, 0))
	hero.click_at(sp)
	check(hero.attack_target == d0, "点击屏幕上的木桩：锁定它为攻击目标")
	var hp_c := d0.hp
	await seconds(2.0)
	check(d0.hp < hp_c, "自动走到攻击距离并出手")

	# 手机「攻击」按钮：锁定最近的敌人
	hero.global_position = Vector3(1.0, 0, 0.0)
	await physics(2)
	hero.attack_nearest(true)
	check(hero.attack_target != null and hero.attack_target.global_position.distance_to(hero.global_position) < 2.5, "「攻击」按钮锁定最近的木桩")
	hero.attack_nearest(false)
	main.queue_free()
	await frames(2)


func _arena() -> Node:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.use_test_area = true      # 第 0 层用灰盒测试区（P7 起默认是烬原镇）
	main.auto_pack_test = false
	main.run_nav_bench = false
	main.spawn_monsters = false
	add_child(main)
	for i in 60:
		await physics(1)
		if NavigationServer3D.map_get_path(main.hero.get_world_3d().navigation_map, Vector3.ZERO, Vector3(0, 0, 12), true).size() > 0:
			break
	return main


func _spawn(main: Node, id: String, pos: Vector3) -> EnemyBase:
	var e := Monsters.spawn(id, main, pos, main.hero)
	main.monsters.append(e)
	return e


func test_monsters() -> void:
	var defs := Monsters.defs()
	check(defs.has("ash_brute") and defs.has("bone_archer") and defs.has("ash_priest") and defs.has("ash_corpse"), "测试区怪物数据：冲锋、远程、召唤、仆从 4 种")
	var v01_keys := ["zombie", "skel", "imp", "archer", "ghoul", "cultist", "hound", "knight"]
	check(defs.size() == 14 and v01_keys.all(func(k): return defs.has(k) and defs[k].v01 == k) and defs.has("mog") and defs.has("abbot"), "V0.1 第一幕的 8 种怪物（P5）与 2 个首领（P9）都有 3D 定义（共 14 种）")

	# ---- 发现与群体惊动 ----
	var main = await _arena()
	var hero: Player = main.hero
	var a := _spawn(main, "ash_corpse", Vector3(-4, 0, 18))
	var b := _spawn(main, "ash_corpse", Vector3(-6, 0, 20))
	await seconds(0.5)
	check(a.state == "idle" and b.state == "idle", "玩家在房间里（隔着墙、距离远）时怪物待机")
	hero.global_position = Vector3(-4, 0, 9)
	await seconds(0.4)
	check(a.state != "idle", "玩家进入视线与警戒距离：怪物开始追击")
	check(b.state != "idle", "附近 6 米内的同伴一起被惊动")
	var d0 := a.global_position.distance_to(hero.global_position)
	await seconds(1.0)
	check(a.global_position.distance_to(hero.global_position) < d0 - 1.0, "怪物朝玩家靠近")
	# 近战打人
	var hp0 := hero.hp
	await seconds(3.0)
	check(hero.hp < hp0, "腐尸追上后近战命中玩家（-%d）" % (hp0 - hero.hp))
	main.queue_free()
	await frames(2)

	# ---- 冲锋：红色长条预警 → 冲刺命中 ----
	main = await _arena()
	hero = main.hero
	hero.global_position = Vector3(4.5, 0, 11.0)
	var c := _spawn(main, "ash_brute", Vector3(4.5, 0, 17.5))
	c.set_state("chase")
	var saw_warning := false
	var saw_act := false
	hp0 = hero.hp
	for i in 150:
		await physics(1)
		saw_warning = saw_warning or (c.state == "windup" and c.has_warning())
		saw_act = saw_act or c.state == "act"
	check(saw_warning, "冲锋前地面出现红色长条预警")
	check(saw_act, "预警结束后冲锋")
	# P3 起怪物按 V0.1 数值：焦骨蛮兵对应食尸鬼（第 1 层 3–7），冲锋 ×1.6 = 5–11，扣掉少量护甲减伤
	check(hero.hp <= hp0 - 3, "站在冲锋路线上被撞（-%d）" % (hp0 - hero.hp))
	main.queue_free()
	await frames(2)

	# ---- 冲锋：躲开后撞墙把自己撞晕 ----
	main = await _arena()
	hero = main.hero
	hero.global_position = Vector3(4.5, 0, 8.6)
	c = _spawn(main, "ash_brute", Vector3(4.5, 0, 15.2))
	c.set_state("chase")
	for i in 90:
		await physics(1)
		if c.state == "windup" and c.has_warning():
			break
	hp0 = hero.hp
	hero.global_position = Vector3(10.5, 0, 9.0)    # 预警期间闪开
	var stunned := false
	for i in 90:
		await physics(1)
		stunned = stunned or c.stun_t > 0.5
	check(hero.hp >= hp0 - 0.001, "闪开后冲锋落空")   # P3 起有生命回复，只会涨不会掉
	check(stunned, "冲锋撞墙：把自己撞晕（反击窗口）")
	main.queue_free()
	await frames(2)

	# ---- 远程：放箭、保持距离、箭会被墙挡住 ----
	main = await _arena()
	hero = main.hero
	hero.global_position = Vector3(-2, 0, 13)
	var ar := _spawn(main, "bone_archer", Vector3(-2, 0, 20.5))
	ar.set_state("chase")
	var saw_arrow := false
	hp0 = hero.hp
	for i in 180:
		await physics(1)
		for ch in main.get_children():
			if ch is Projectile:
				saw_arrow = true
	check(saw_arrow, "弓手拉弓后射出箭")
	check(hero.hp < hp0, "站着不动会被箭射中（-%d）" % (hp0 - hero.hp))
	hero.global_position = ar.global_position + Vector3(1.5, 0, -1.5)
	var close := ar.global_position.distance_to(hero.global_position)
	await seconds(1.0)
	check(ar.global_position.distance_to(hero.global_position) > close + 0.8, "玩家贴近时弓手后退拉开距离")
	var arrow := Projectile.new()
	arrow.attacker = ar.attacker_stats([6, 9])
	arrow.dir = Vector3(0, 0, -1)
	main.add_child(arrow)
	arrow.global_position = Vector3(-3.5, 1.2, 8.0)   # 朝北飞向房间南墙（z = 6）
	hp0 = hero.hp
	await physics(20)
	check(not is_instance_valid(arrow), "箭撞到墙就消失")
	main.queue_free()
	await frames(2)

	# ---- 召唤：两个红圈 → 召唤两只腐尸；有上限 ----
	main = await _arena()
	hero = main.hero
	hero.global_position = Vector3(2, 0, 16)
	var pr := _spawn(main, "ash_priest", Vector3(2, 0, 23))
	pr.set_state("chase")
	var warn_n := 0
	for i in 150:
		await physics(1)
		warn_n = maxi(warn_n, pr._warnings.size())
	var minions := get_tree().get_nodes_in_group("enemy").filter(func(e): return e is EnemyMelee and not e.dead)
	check(warn_n == 2, "召唤前出现两个红圈预警")
	check(minions.size() == 2, "召唤出 2 只腐尸")
	check(minions.all(func(m): return m.state != "idle"), "召唤出来的仆从直接追击玩家")
	pr.cooldowns["summon"] = 0.0
	await seconds(1.6)
	pr.cooldowns["summon"] = 0.0
	await seconds(1.6)
	minions = get_tree().get_nodes_in_group("enemy").filter(func(e): return e is EnemyMelee and not e.dead)
	check(minions.size() <= 4, "同时存活的仆从不超过上限 4（现有 %d）" % minions.size())

	# ---- 眩晕打断蓄力；打死后倒下并消失 ----
	for m in minions:
		m.hp = 1
		m.take_hit({"amount": 5, "crit": false, "type": "physical"}, Vector3.ZERO, 0.0)
	check(minions.all(func(m): return m.dead), "生命归零的怪物进入死亡状态")
	await seconds(3.2)
	check(minions.all(func(m): return not is_instance_valid(m)), "尸体数秒后移除")
	main.queue_free()
	await frames(2)

	main = await _arena()
	hero = main.hero
	hero.global_position = Vector3(4.5, 0, 11.0)
	c = _spawn(main, "ash_brute", Vector3(4.5, 0, 17.5))
	c.set_state("chase")
	for i in 120:
		await physics(1)
		if c.state == "windup" and c.has_warning():
			break
	c.take_hit({"amount": 1, "crit": false, "type": "physical"}, Vector3.ZERO, 0.0, 1.2)
	check(c.state == "recover" and not c.has_warning(), "眩晕打断冲锋蓄力并清除预警")

	# ---- 玩家死亡：怪物回家，玩家在房间复活 ----
	hero.hp = 1
	hero.take_hit({"amount": 5, "crit": false, "type": "physical"}, Vector3.ZERO, 0.0)
	check(hero.dead, "玩家生命归零后倒下")
	check(not hero.cast_skill("fireball"), "倒下后不能放技能")
	await seconds(1.6)    # 冲锋者此时还处于 1.2 秒眩晕中，眩晕结束才会回家
	check(c.state == "return" or c.state == "idle", "玩家倒下后怪物回出生点")
	await seconds(1.8)
	check(not hero.dead and hero.hp == hero.max_hp and hero.global_position.distance_to(Vector3.ZERO) < 0.5, "3 秒后在房间里满血复活")
	main.queue_free()
	await frames(2)


func test_perf() -> void:
	## 无头模式下的逻辑开销：大厅里 60 只腐尸同时追击，统计物理帧（含 AI、寻路、碰撞）的平均耗时。
	## 绘制调用等渲染数字由 tests/perf_stats.tscn（xvfb）和网页 ?perf=1 给出，写进 TEST_REPORT.md。
	var main = await _arena()
	var hero: Player = main.hero
	hero.max_hp = 1e9
	hero.hp = hero.max_hp
	hero.global_position = Vector3(1, 0, 16)
	for i in 60:
		var ang := TAU * i / 60.0
		var r := 5.0 + (i % 3) * 2.5
		var e := _spawn(main, "ash_corpse", Vector3(1 + cos(ang) * r, 0, 16 + sin(ang) * r * 0.75))
		e.set_state("chase")
	await seconds(1.0)
	# 用 EnemyBase.prof_us 直接计时（1.5 实测：Performance 的 TIME_PHYSICS_PROCESS 在无头模式下数值陈旧，
	# 连续几十帧读到同一个值，且怪物待机和追击读数一样，不能反映 AI 开销）
	var n := 0
	var worst := 0.0
	var start := EnemyBase.prof_us
	var last := start
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 2000:
		await get_tree().physics_frame
		worst = maxf(worst, (EnemyBase.prof_us - last) / 1000.0)
		last = EnemyBase.prof_us
		n += 1
	var avg := (EnemyBase.prof_us - start) / 1000.0 / maxi(n, 1)
	var alive := get_tree().get_nodes_in_group("enemy").filter(func(e): return not e.dead).size()
	print("  info 60 只腐尸同时追击：敌人物理更新（AI + 寻路 + 移动碰撞）每帧平均 %.2f 毫秒、最慢 %.2f 毫秒（%d 帧，存活敌人 %d，本机原生）" % [avg, worst, n, alive])
	check(alive >= 60, "60 只怪物同时活动")
	check(avg < 5.0, "60 只怪物每帧更新平均耗时 < 5 毫秒（实测 %.2f）" % avg)
	main.queue_free()
	await frames(2)


func _count_numbers(root: Node) -> int:
	# 伤害数字挂在受击者的父节点下（P2 起楼层内容都在 main/Stage 下），所以递归数；按前后差值判断
	return root.find_children("*", "Label3D", true, false).size()


func test_pack() -> void:
	if pack_path == "":
		check(false, "未传入 --pack=… ，无法测试章节包加载（run_tests.sh 会先导出测试包）")
		return
	check(FileAccess.file_exists(pack_path), "测试章节包文件存在：" + pack_path)
	var result := []
	PackLoader.pack_loaded.connect(func(id, ok, ms, detail): result.append([id, ok, ms, detail]), CONNECT_ONE_SHOT)
	PackLoader.load_chapter("ch_test", pack_path)
	await frames(2)
	check(result.size() == 1 and result[0][1], "load_resource_pack 挂载成功")
	check(ResourceLoader.exists("res://packs/ch_test/marker.tscn"), "挂载后能找到章节包里的场景")
	var inst = (load("res://packs/ch_test/marker.tscn") as PackedScene).instantiate()
	add_child(inst)
	await frames(1)
	check(inst.get_child_count() >= 2, "章节包场景可以实例化，并使用主包里的脚本")
	inst.queue_free()


# ---------- 阶段 P1：V0.1 数据移植对照 ----------
# 对照答案 tests/fixtures/v01_reference.json 由 tools/port_v01.js 用 V0.1 的原函数算出。
func _near(a, b) -> bool:
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not _near(a[i], b[i]):
				return false
		return true
	if typeof(a) in [TYPE_INT, TYPE_FLOAT] and typeof(b) in [TYPE_INT, TYPE_FLOAT]:
		return absf(float(a) - float(b)) < 1e-9
	return a == b


func test_port() -> void:
	var f := FileAccess.open("res://tests/fixtures/v01_reference.json", FileAccess.READ)
	check(f != null, "V0.1 对照答案文件存在")
	if f == null:
		return
	var ref: Dictionary = JSON.parse_string(f.get_as_text())
	var items := Act1Data.items()
	var mons := Act1Data.monsters()
	var rules := Act1Data.rules()

	# 数据完整性
	check(items.bases.size() == 25 and items.affixes.size() == 16 and items.uniques.size() == 11 and items.slots.size() == 8,
		"物品数据齐全：25 种底材、16 种词缀、11 件传奇、8 个部位")
	check(mons.monsters.size() == 10 and mons.champions.size() == 5, "怪物数据齐全：10 种（含 2 个首领）、5 种精英特性")
	check(rules.skills.size() == 4 and rules.shrines.list.size() == 4, "技能 4 个、神殿 4 种")
	var slot_ids: Array = items.slots.map(func(s): return s.id)
	var bad := []
	for k in items.bases:
		if not slot_ids.has(items.bases[k].slot):
			bad.append(k)
	for u in items.uniques:
		if not items.bases.has(u.base):
			bad.append(u.name)
		for a in u.affixes:
			if not items.affixes.has(a):
				bad.append(u.name + "/" + a)
	for p in mons.pools.values():
		for m in p:
			if not mons.monsters.has(m):
				bad.append("pool/" + m)
	for b in rules.floors.bosses.values():
		if not mons.monsters.has(b) or not mons.monsters[b].get("boss", false):
			bad.append("boss/" + b)
	check(bad.is_empty(), "交叉引用都存在（部位、传奇底材与词缀、怪物池、首领）%s" % ("" if bad.is_empty() else str(bad)))
	var names := JSON.stringify(items) + JSON.stringify(mons) + JSON.stringify(rules)
	check(not names.contains("旋风斩") and not names.contains("冰霜新星") and not names.contains("屠夫"), "没有带回已从 V0.1 去掉的暗黑相似名称")

	# 公式逐项对照
	var mism := []
	for i in 50:
		if HeroStats.xp_need(i + 1) != int(ref.xp_need[i]):
			mism.append(i + 1)
	check(mism.is_empty(), "经验曲线 1–50 级与 V0.1 一致 %s" % str(mism))

	mism = []
	for key in ref.affix_range:
		var p: PackedStringArray = key.split("@")
		if not _near(ItemGen.affix_bounds(p[0], int(p[1])), ref.affix_range[key]):
			mism.append(key)
	check(mism.is_empty(), "词缀取值范围与 V0.1 一致（%d 组）%s" % [ref.affix_range.size(), str(mism)])

	mism = []
	for c in ref.rarity:
		if ItemGen.rarity_from(c.r, c.mul) != int(c.out):
			mism.append(c)
	check(mism.is_empty(), "品质掷骰阈值与 V0.1 一致（%d 组）%s" % [ref.rarity.size(), str(mism)])

	mism = []
	for key in ref.base_stats:
		var p: PackedStringArray = key.split("@")
		var it := {"aff": {}}
		ItemGen.apply_base_stats(it, Act1Data.base(p[0]), int(p[1]))
		var want: Dictionary = ref.base_stats[key]
		for fld in want:
			if fld == "aff":
				for ak in want.aff:
					if not _near(it.aff.get(ak), want.aff[ak]):
						mism.append(key + "/" + ak)
			elif not _near(it.get(fld), want[fld]):
				mism.append(key + "/" + fld)
		for fld in it:
			if not want.has(fld):
				mism.append(key + "/多出 " + fld)
	check(mism.is_empty(), "底材属性随物品等级成长与 V0.1 一致（%d 组）%s" % [ref.base_stats.size(), str(mism)])

	mism = []
	for c in ref.item_value:
		var it: Dictionary = c.it.duplicate()
		it.rarity = int(it.r)
		if ItemGen.value(it) != int(c.value) or ItemGen.sell_value(it) != int(c.sell):
			mism.append(c)
	check(mism.is_empty(), "买价与卖价与 V0.1 一致 %s" % str(mism))

	mism = []
	for c in ref.calc_stats:
		var hero: Dictionary = c.hero.duplicate(true)
		var S := HeroStats.calc(hero)
		for fld in c.stats:
			if not _near(S.get(fld), c.stats[fld]):
				mism.append("%s/%s: %s ≠ %s" % [c.name, fld, S.get(fld), c.stats[fld]])
		for l in c.dr:
			if not _near(HeroStats.damage_reduction(S, int(l)), c.dr[l]):
				mism.append("%s/减伤@%s" % [c.name, l])
	check(mism.is_empty(), "角色属性与护甲减伤与 V0.1 一致（%d 种配装，含 4 种神殿）%s" % [ref.calc_stats.size(), str(mism)])

	mism = []
	for c in ref.spawn:
		var m := FloorRules.scale_monster(c.key, int(c.floor), c.champ if c.champ != null else "")
		for fld in ["hp", "dmg", "xp", "lvl", "spd", "name"]:
			if not _near(m[fld], c[fld]):
				mism.append("%s@%d/%s/%s" % [c.key, c.floor, c.champ, fld])
	check(mism.is_empty(), "怪物随楼层与精英特性的成长与 V0.1 一致（%d 组）%s" % [ref.spawn.size(), str(mism.slice(0, 5))])

	mism = []
	for c in ref.floors:
		var fl := int(c.floor)
		if FloorRules.theme_for(fl) != c.theme or FloorRules.floor_name(fl) != c.name or FloorRules.is_boss_floor(fl) != c.boss:
			mism.append(fl)
	check(mism.is_empty(), "楼层主题、名称、首领层（0–20 层）与 V0.1 一致 %s" % str(mism))
	check(FloorRules.monster_pool(9) == FloorRules.monster_pool(7) and FloorRules.monster_pool(0) == FloorRules.monster_pool(1), "第 7 层以后用深渊怪物池，镇上按第 1 层算")

	# 随机生成的性质（给定种子，可复现）
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260926
	var counts := [0, 0, 0, 0]
	var problems := []
	for i in 4000:
		var il := 1 + i % 30
		var it := ItemGen.generate(rng, il)
		counts[it.rarity] += 1
		var b := Act1Data.base(it.base)
		if b.get("magic_only", false) and it.rarity == 0:
			problems.append("戒指护符出了普通品质")
		if it.rarity == 1 and not items.affixes.values().any(func(a): return String(it.name).begins_with(a.prefix)):
			problems.append("魔法物品名缺前缀：" + it.name)
		if it.rarity == 2 and not (items.rare_names.first.any(func(x): return String(it.name).begins_with(x)) and items.rare_names.second.any(func(x): return String(it.name).ends_with(x))):
			problems.append("稀有物品名不合规：" + it.name)
		if it.rarity == 3 and not items.uniques.any(func(u): return u.name == it.name and u.base == it.base):
			problems.append("传奇名与底材不符：" + it.name)
		if it.rarity < 3:
			for k in it.aff:
				var a := Act1Data.affix(k)
				if a.has("max") and it.aff[k] > a.max:
					problems.append("词缀超上限：%s %s" % [k, it.aff[k]])
				if typeof(a.slots) != TYPE_STRING and not (a.slots as Array).has(b.slot) and not b.get("implicit", {}).has(k):
					problems.append("词缀不该出现在该部位：%s/%s" % [k, b.slot])
			if b.lvl > il + 1:
				problems.append("底材等级超出物品等级：" + it.base)
		var want_req := int(b.lvl) if it.rarity == 0 else (maxi(1, mini(40, maxi(int(b.lvl), int(floor(il * 0.6))))) if it.rarity == 3 else maxi(int(b.lvl), int(floor(il * 0.6))))
		if it.req != want_req:
			problems.append("需求等级不对：%s" % it.name)
	check(problems.is_empty(), "4000 件随机物品都符合规则（品质、命名、词缀部位与上限、需求等级）%s" % str(problems.slice(0, 3)))
	# 不带掉率加成时的期望：传奇 1.2%、稀有 7.8%、魔法 27%（戒指护符会把普通顶成魔法，略高）
	check(counts[3] > 20 and counts[3] < 90 and counts[2] > 230 and counts[2] < 400 and counts[1] > 1000 and counts[1] < 1500,
		"品质分布符合 V0.1 的掉率（普通 %d / 魔法 %d / 稀有 %d / 传奇 %d）" % counts)

	rng.seed = 7
	var a1 := ItemGen.generate(rng, 12)
	rng.seed = 7
	var a2 := ItemGen.generate(rng, 12)
	a1.erase("id")
	a2.erase("id")
	check(a1 == a2, "同一种子生成同一件物品（可复现）")

	# 成长与杂项
	var hero := HeroStats.new_hero()
	var S0 := HeroStats.calc(hero)
	check(hero.hp == S0.maxHp and S0.maxHp == 64 and S0.maxMp == 34 and hero.gold == 60 and hero.pots.hp == 3,
		"新角色：生命 64、法力 34、60 金币、3 瓶生命药水（%d / %d）" % [S0.maxHp, S0.maxMp])
	var ups := HeroStats.gain_xp(hero, HeroStats.xp_need(1) + HeroStats.xp_need(2))
	check(ups == 2 and hero.lvl == 3 and hero.pts == 10 and hero.xp == 0, "经验够两级时连升两级、得 10 点属性点")
	var capped := HeroStats.new_hero()
	capped.lvl = 50
	check(HeroStats.gain_xp(capped, 999999) == 0 and capped.lvl == 50, "50 级封顶")
	check(HeroStats.kill_xp(100, 12, 4) == 55 and HeroStats.kill_xp(100, 30, 2) == 10 and HeroStats.kill_xp(100, 9, 4) == 100,
		"击杀经验：高 8 级得 55%、高太多保底 10%、高 5 级以内不衰减")
	check(HeroStats.potion_amount("hp", S0) == 39 and HeroStats.potion_amount("mp", S0) == 22, "药水回复量：生命 45%+10、法力 50%+5")
	check(HeroStats.death_gold_loss(275) == 27, "死亡掉落 10% 金币")
	check(HeroStats.skills_known(5).map(func(s): return s.name) == ["火球术", "烬环斩"], "5 级学会火球术与烬环斩")

	rng.seed = 42
	var boss_drop := FloorRules.roll_loot(rng, 3, {"boss": true})
	var boss_items: Array = boss_drop.filter(func(d): return d.has("item"))
	check(boss_items.size() == 4 and boss_items[0].item.rarity >= 2 and boss_items[1].item.rarity == 2 and boss_items[0].item.ilvl == 9,
		"首领掉落：4 件装备，第一件稀有或传奇、第二件稀有，物品等级 = 层数×2+3")
	var any_drop := 0
	var champ_items := 0
	for i in 500:
		any_drop += FloorRules.roll_loot(rng, 2, {}).size()
		champ_items += FloorRules.roll_loot(rng, 2, {"champ": "fast"}).filter(func(d): return d.has("item")).size()
	check(any_drop > 250 and any_drop < 420, "普通怪 500 只的掉落总数在预期范围（%d）" % any_drop)
	check(champ_items >= 800 and champ_items <= 900, "精英怪每只掉 1–2 件装备（500 只共 %d 件）" % champ_items)
	var shop := FloorRules.refresh_shop(rng, 5)
	check(shop.smith.size() == 8 and shop.smith.all(func(it): return not Act1Data.base(it.base).get("magic_only", false) and it.ilvl == 6)
		and shop.alchemist.size() == 2 and shop.alchemist.all(func(it): return it.base in ["ring", "amulet"] and it.rarity >= 1),
		"商店：格伦 8 件（无戒指护符）、玛拉 2 件戒指或护符，物品等级 = 角色等级+1")
	var chest := FloorRules.roll_chest(rng, 4)
	check(chest[0].has("gold") and chest.filter(func(d): return d.has("item")).size() in [1, 2], "宝箱：金币 + 1–2 件装备")


# ---------- 阶段 P2：随机地下城 ----------
func test_dungeon() -> void:
	# 格子布局：12 层 × 3 个种子
	var G := DungeonGen
	var problems := []
	var gen_us := 0
	var n_maps := 0
	for f in range(1, 13):
		for sd in [11, 222, 3333]:
			var t0 := Time.get_ticks_usec()
			var m := G.generate(f, sd)
			gen_us += Time.get_ticks_usec() - t0
			n_maps += 1
			var tag := "第%d层/种子%d" % [f, sd]
			var w: int = m.w
			var boss := FloorRules.is_boss_floor(f)
			if m.rooms.size() < 8:
				problems.append(tag + " 房间太少 %d" % m.rooms.size())
			if G.tile(m, m.up.x, m.up.y) != G.UP:
				problems.append(tag + " 上楼梯不在 UP 格")
			if boss:
				var br: Dictionary = m.rooms[m.boss_room] if m.boss_room >= 0 else {}
				if m.boss_room < 0 or br.w != 13 or br.h != 13:
					problems.append(tag + " 首领层没有 13×13 首领房")
				elif m.down != Vector2i(-1, -1) or m.boss_stairs != Vector2i(br.cx, br.cy):
					problems.append(tag + " 首领层的下楼梯应在击败首领后才出现")
				else:
					var sr: Dictionary = m.rooms[m.start]
					var dmax := 0
					for i in m.rooms.size():
						if i != m.boss_room:
							dmax = maxi(dmax, absi(m.rooms[i].cx - br.cx) + absi(m.rooms[i].cy - br.cy))
					if absi(sr.cx - br.cx) + absi(sr.cy - br.cy) != dmax:
						problems.append(tag + " 起点不是离首领房最远的房间")
			elif G.tile(m, m.down.x, m.down.y) != G.DOWN:
				problems.append(tag + " 下楼梯不在 DOWN 格")
			var dist: PackedInt32Array = m.dist
			var far := -1
			for i in m.rooms.size():
				var d := dist[m.rooms[i].cy * w + m.rooms[i].cx]
				if d < 0:
					problems.append(tag + " 房间 %d 走不到" % i)
				if i != m.start:
					far = maxi(far, d)
			if not boss and dist[m.down.y * w + m.down.x] != far:
				problems.append(tag + " 下楼梯不在最远的房间")
			for y in m.h:
				for x in w:
					var tt: int = m.t[y * w + x]
					if not G.walkable(tt):
						if m.deco[y * w + x] != 0:
							problems.append(tag + " 装饰放在了非地面格")
						continue
					if x == 0 or y == 0 or x == w - 1 or y == m.h - 1:
						problems.append(tag + " 地面贴着地图边缘")
					for dy in [-1, 0, 1]:
						for dx in [-1, 0, 1]:
							if G.tile(m, x + dx, y + dy) == G.VOID:
								problems.append(tag + " 地面旁边有缺口（没墙）")
			for i in m.torches.size():
				var tc: Dictionary = m.torches[i]
				if G.tile(m, tc.cell.x, tc.cell.y) != G.WALL or not G.walkable(G.tile(m, tc.cell.x + tc.face.x, tc.cell.y + tc.face.y)):
					problems.append(tag + " 火把不在朝向地面的墙上")
				for j in range(i + 1, m.torches.size()):
					if absi(tc.cell.x - m.torches[j].cell.x) + absi(tc.cell.y - m.torches[j].cell.y) < 6:
						problems.append(tag + " 火把太密")
			var lava: bool = Array(m.deco).has(G.DECO_LAVA)
			if lava and not m.theme in ["inferno", "abyss"]:
				problems.append(tag + " 非熔渊 / 深渊出现熔岩")
	check(problems.is_empty(), "36 张随机地图都合规：房间连通、楼梯位置、首领房、墙体封闭、火把与装饰 %s" % str(problems.slice(0, 4)))
	info("生成一张 58×58 格子地图平均 %.1f 毫秒" % (gen_us / 1000.0 / n_maps))
	var a := G.generate(4, 99)
	var b := G.generate(4, 99)
	var c := G.generate(4, 100)
	check(a.t == b.t and a.torches == b.torches and a.deco == b.deco, "同一层 + 同一种子 → 同一张地图")
	check(a.t != c.t, "换种子 → 换一张地图")
	check(G.generate(1, 5).theme == "crypt" and G.generate(3, 5).theme == "catacomb" and G.generate(5, 5).theme == "inferno" and G.generate(9, 5).theme == "abyss",
		"楼层主题：1–2 地窖、3–4 墓穴、5–6 熔渊、7 起深渊")

	# 3D：从测试区走楼梯下到第 1 层
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.use_test_area = true      # 第 0 层用灰盒测试区（P7 起默认是烬原镇）
	main.auto_pack_test = false
	main.run_nav_bench = false
	add_child(main)
	await frames(3)
	var hero: Player = main.hero
	check(main.floor_i == 0 and main.stairs.has("down"), "开局在测试区，房间里有下楼梯")
	main.run_seed = 4242
	hero.global_position = main.TEST_STAIRS
	await physics(4)
	await frames(2)
	check(main.floor_i == 1, "走进楼梯格 → 到修道院地窖第 1 层")
	var m1: Dictionary = main.dungeon
	var up_pos := DungeonBuilder.cell_center(m1.up)
	check(hero.global_position.distance_to(up_pos) < 4.5 and not main.stairs.up.overlaps_body(hero), "到达后站在上楼梯旁边，而不是楼梯上（%.1f 米）" % hero.global_position.distance_to(up_pos))
	check(main.dummies.is_empty() and main.stage.find_children("*", "TrainingDummy", true, false).is_empty() and main.monsters.all(func(e): return not String(e.def.v01).is_empty() and not e.def.has("summon") and e.def.floor == 1),
		"测试区的木桩和怪物随楼层一起清掉，换成本层按 V0.1 刷的怪（%d 只）" % main.monsters.size())
	check(main.level.navigation_mesh.get_polygon_count() > 50 and main.torches.size() > 3, "整层导航已烘焙（%d 个多边形，%.0f 毫秒），%d 支火把" % [main.level.navigation_mesh.get_polygon_count(), main.nav_bake_ms, main.torches.size()])
	info("第 1 层搭建总耗时 %.0f 毫秒（几何 %.0f、导航 %.0f），%d 个地块" % [main.floor_info.build_ms, main.floor_info.geo_ms, main.floor_info.nav_ms, main.floor_info.chunks])
	await physics(3)
	var down_pos := DungeonBuilder.cell_center(main.floor_info.down_cell)
	var path := NavigationServer3D.map_get_path(hero.get_world_3d().navigation_map, hero.global_position, down_pos, true)
	var plen := 0.0
	for i in range(1, path.size()):
		plen += path[i - 1].distance_to(path[i])
	check(path.size() > 1 and path[-1].distance_to(down_pos) < 1.0, "导航能从入口走到下楼梯（路径 %.0f 米，直线 %.0f 米）" % [plen, hero.global_position.distance_to(down_pos)])

	# 墙挡路、地面可点
	var space := hero.get_world_3d().direct_space_state
	var wall_hits := 0
	var wall_tries := 0
	for y in range(1, m1.h - 1):
		for x in range(1, m1.w - 1):
			if wall_tries >= 20:
				break
			if m1.t[y * m1.w + x] == DungeonGen.FLOOR and m1.t[y * m1.w + x + 1] == DungeonGen.WALL:
				wall_tries += 1
				var from := DungeonBuilder.cell_center(Vector2i(x, y)) + Vector3(0, 1, 0)
				var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(DungeonBuilder.TILE, 0, 0), Layers.WORLD)
				if not space.intersect_ray(q).is_empty():
					wall_hits += 1
	check(wall_tries > 0 and wall_hits == wall_tries, "墙体有碰撞，挡得住（%d / %d 处）" % [wall_hits, wall_tries])
	var gq := PhysicsRayQueryParameters3D.create(hero.global_position + Vector3(0, 5, 0), hero.global_position + Vector3(0, -5, 0), Layers.GROUND)
	check(not space.intersect_ray(gq).is_empty(), "脚下有地面碰撞（点地面移动要用）")
	var wall_bodies: Array = main.stage.find_children("*", "StaticBody3D", true, false).filter(func(bd): return bd.has_meta("fade_meshes"))
	var mats := {}
	for bd in wall_bodies:
		mats[bd.get_meta("fade_meshes")[0].material_override] = true
	check(wall_bodies.size() > 10 and mats.size() == wall_bodies.size(), "每块墙有自己的材质（相机只淡化挡住主角的那一块）")

	# 走下楼梯：站到楼梯旁，点过去（真实寻路 + 触发）
	var near := DungeonGen.near_free(m1, main.floor_info.down_cell)
	hero.global_position = DungeonBuilder.cell_center(near)
	main.camera.snap()
	await physics(3)
	hero.move_to(down_pos)
	for i in 180:
		await physics(1)
		if main.floor_i == 2:
			break
	await frames(2)
	check(main.floor_i == 2, "寻路走到下楼梯 → 第 2 层")
	# 刚到新楼层有 0.8 秒换层冷却；冷却期间站上楼梯，冷却一结束就换层
	hero.global_position = DungeonBuilder.cell_center(main.dungeon.up)
	await physics(4)
	check(main.floor_i == 2, "刚到新楼层的冷却期内踩楼梯不会立刻来回跳")
	for i in 120:
		await physics(1)
		if main.floor_i == 1:
			break
	await frames(2)
	check(main.floor_i == 1 and main.dungeon.t == m1.t, "冷却结束后仍站在楼梯上 → 上楼回到第 1 层，布局和刚才一样")
	check(hero.global_position.distance_to(down_pos) < 4.5, "上楼后站在第 1 层的下楼梯旁")

	# 首领层与主题
	main.go_floor(3)
	await frames(2)
	check(main.dungeon.boss_room >= 0 and main.floor_info.down_cell.x < 0 and not main.stairs.has("down"),
		"第 3 层（首领层）：击败首领之前没有下楼梯（P9）")
	main.go_floor(5)
	await frames(2)
	check(main.environment.ambient_light_color == Look.THEME_ENV.inferno.ambient and main.environment.fog_light_color == Look.THEME_ENV.inferno.fog, "熔渊换成暗红的环境光与雾")
	check(main.stage.find_child("Lava", true, false) != null, "熔渊地面有熔岩裂缝")
	main.go_floor(0, "up")
	await frames(2)
	check(main.floor_i == 0 and main.torches.size() == 4 and main.dummies.size() == 2 and main.stage.find_children("Walls_*", "", true, false).is_empty()
		and main.environment.ambient_light_color == Look.THEME_ENV.crypt.ambient, "回到测试区：房间、大厅、木桩、火把复原，地下城清掉")
	check(hero.global_position.distance_to(main.TEST_STAIRS) < 3.5, "从第 1 层上来站在测试区楼梯旁")
	main.queue_free()
	await frames(2)


# ---------- 阶段 P3：角色成长 ----------
func test_growth() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.use_test_area = true      # 第 0 层用灰盒测试区（P7 起默认是烬原镇）
	main.auto_pack_test = false
	main.run_nav_bench = false
	main.spawn_monsters = false
	add_child(main)
	await frames(3)
	var hero: Player = main.hero
	var pr: HeroProgress = hero.progress
	var sh: Dictionary = pr.sheet

	# 开局与 V0.1 newGame 一致：短剑 + 布衣
	check(sh.lvl == 1 and sh.str == 15 and sh.vit == 15 and sh.mag == 15 and sh.eq.weapon.base == "sword" and sh.eq.body.base == "cloth", "开局 1 级、三项属性各 15、短剑与亚麻布衣（同 V0.1）")
	check(hero.max_hp == 64 and hero.max_mp == 34 and hero.stats.weapon_min == 2 and hero.stats.weapon_max == 7 and hero.stats.armor == 4 and absf(hero.stats.crit_chance - 0.05) < 1e-9,
		"开局属性：生命 64、法力 34、伤害 2–7、护甲 4、暴击 5%%（%d / %d / %d–%d / %d）" % [hero.max_hp, hero.max_mp, hero.stats.weapon_min, hero.stats.weapon_max, hero.stats.armor])
	check(is_equal_approx(pr.attack_speed_scale(), 1.0) and is_equal_approx(hero.speed, 5.0), "开局攻速与移动速度保持原来的手感（1.0 倍、5 米/秒）")

	# 怪物换算到 V0.1 数值
	var bd := Monsters.scaled_def("ash_brute", 1)
	check(bd.hp == 30 and bd.attack.dmg == [3, 7] and bd.charge.dmg == [5, 11] and bd.xp == 22 and bd.level == 2 and bd.armor == 0,
		"焦骨蛮兵按 V0.1 食尸鬼换算：第 1 层 30 血、近战 3–7、冲锋 5–11、22 经验、2 级、无护甲")
	var g5 := FloorRules.scale_monster("ghoul", 5)
	var bd5 := Monsters.scaled_def("ash_brute", 5)
	check(bd5.hp == g5.hp and bd5.attack.dmg == g5.dmg and bd5.xp == g5.xp, "同一种怪到第 5 层按 V0.1 楼层成长变强（%d 血）" % bd5.hp)
	check(Monsters.scaled_def("bone_archer").shot.dmg == [2, 4] and Monsters.scaled_def("ash_priest").hp == 20 and Monsters.scaled_def("ash_corpse").xp == 12,
		"弓手 = V0.1 骸骨弓手、祭司 = 邪教术士、腐尸 = 腐尸")

	# 击杀经验与升级
	var z := Monsters.spawn("ash_corpse", main.stage, Vector3(0, 0, 3), hero)
	await physics(2)
	z.die()
	check(sh.xp == 12 and sh.kills == 1, "击杀腐尸得 12 经验（%d）" % sh.xp)
	var big := Monsters.spawn("ash_corpse", main.stage, Vector3(1, 0, 3), hero)
	await physics(2)
	big.def.xp = 500
	hero.hp = 20
	big.die()
	await frames(1)
	check(sh.lvl == 3 and sh.pts == 10 and sh.xp == 12 + 500 - 90 - 282, "经验够两级连升两级：3 级、10 点属性点、余下经验 %d" % sh.xp)
	check(hero.hp == hero.max_hp and hero.mp == hero.max_mp and hero.max_hp == 64 + 8, "升级回满生命法力，生命上限每级 +4（%d）" % hero.max_hp)
	check(main.banner.text.begins_with("升级！你现在是 3 级"), "屏幕提示升级与属性点")
	var hp_before := hero.max_hp
	check(hero.allocate("vit") and hero.allocate("vit") and hero.max_hp == hp_before + 4 and sh.pts == 8, "加 2 点体能：生命上限 +4")
	var dmg_before: int = hero.stats.weapon_max
	for i in 8:
		hero.allocate("str")
	check(sh.str == 23 and sh.pts == 0 and hero.stats.weapon_max >= dmg_before and not hero.allocate("mag") and not pr.allocate("luck"), "点数用完后不能再加，未知属性不能加")
	var sheet_kills: int = sh.kills
	var dummy := TrainingDummy.new()
	main.stage.add_child(dummy)
	dummy.global_position = Vector3(3, 0, 3)
	await physics(2)
	dummy.die()
	check(sh.kills == sheet_kills, "打倒训练木桩不给经验")

	# 药水与回复
	hero.hp = 10.0
	var v := hero.drink_potion("hp")
	check(v == HeroStats.potion_amount("hp", pr.S) and is_equal_approx(hero.hp, 10.0 + v) and sh.pots.hp == 2, "喝生命药水：回复 45%%+10 = %d，剩 2 瓶" % v)
	hero.hp = hero.max_hp
	check(hero.drink_potion("hp") == 0 and sh.pots.hp == 2, "满血时不喝")
	hero.mp = 0.0
	check(hero.drink_potion("mp") > 0 and sh.pots.mp == 1, "喝法力药水")
	sh.pots.hp = 0
	hero.hp = 5.0
	check(hero.drink_potion("hp") == 0, "没有药水时喝不了")
	hero.hp = 10.0
	var t0 := Time.get_ticks_msec()
	await seconds(1.0)
	var el := (Time.get_ticks_msec() - t0) / 1000.0
	check(hero.hp > 10.0 and absf((hero.hp - 10.0) - pr.S.regen * el) < pr.S.regen * 0.35, "每秒回复生命 %.2f（1 秒回了 %.2f）" % [pr.S.regen, hero.hp - 10.0])

	# 攻速、移动速度、生命偷取来自装备词缀
	sh.eq.ring = {"id": 9999, "base": "ring", "rarity": 1, "ilvl": 10, "name": "测试戒指", "aff": {"ias": 20, "ms": 0, "ls": 50}, "req": 1}
	sh.eq.feet = {"id": 9998, "base": "boots", "rarity": 1, "ilvl": 10, "name": "测试靴子", "aff": {"ms": 20}, "arm": 1, "req": 1}
	pr.recalc()
	hero._apply_progress()
	check(is_equal_approx(pr.attack_speed_scale(), 1.2) and is_equal_approx(hero.speed, 6.0), "攻速 +20% → 普攻快 1.2 倍；移动速度 +20% → 6 米/秒")
	var d2 := TrainingDummy.new()
	main.stage.add_child(d2)
	d2.global_position = hero.global_position + Vector3(0, 0, 1.2)
	await physics(2)
	hero.hp = 10.0
	hero.face_point(d2.global_position)
	hero.attack_target = d2
	for i in 60:
		await physics(1)
		if d2.hp < d2.max_hp:
			break
	check(d2.hp < d2.max_hp and hero.hp > 10.0, "生命偷取：打中后回血（%.1f）" % hero.hp)
	hero.attack_target = null
	sh.eq.erase("ring")
	sh.eq.erase("feet")
	pr.recalc()
	hero._apply_progress()

	# 死亡掉 10% 金币
	sh.gold = 275
	hero.hp = 1.0
	hero.take_hit({"amount": 50, "crit": false, "type": "physical"}, Vector3.ZERO, 0.0)
	await frames(1)
	check(hero.dead and sh.gold == 248 and sh.deaths == 1 and main.dead_label.text.contains("掉落 27 金币"), "倒下掉 10%% 金币（275 → %d），提示里写明" % sh.gold)
	await seconds(3.3)
	check(not hero.dead and hero.hp == hero.max_hp and hero.mp == hero.max_mp, "复活后生命法力全满")

	# 角色面板：C 打开（暂停）、+ 加点、C 关闭
	sh.pts = 2
	pr.recalc()
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_C
	ev.pressed = true
	main._unhandled_key_input(ev)
	var panel: CharPanel = main.char_panel
	check(panel.visible and get_tree().paused and panel.pts_label.text.contains("2"), "按 C 打开角色面板，游戏暂停")
	await frames(1)
	var vr := panel.get_viewport_rect()
	var pr_rect := panel.get_global_rect()
	# 无头模式的窗口很小，放不下面板；这里只查居中与尺寸合理，放不放得下由网页冒烟在三种宽度截图确认
	check(pr_rect.get_center().distance_to(vr.get_center()) < 2.0 and pr_rect.size.y < 700 and pr_rect.size.x <= 470,
		"面板居中、尺寸合理（%d × %d）" % [pr_rect.size.x, pr_rect.size.y])
	check(panel.derived.text.contains("生命 %d" % pr.S.maxHp) and panel.head.text.contains("%d 级" % sh.lvl), "面板显示等级与计算后的属性")
	var mag0: int = sh.mag
	panel.plus.mag.pressed.emit()
	await frames(1)
	check(sh.mag == mag0 + 1 and sh.pts == 1 and panel.pts_label.text.contains("1"), "点「+」给魔力加 1 点，面板立即刷新")
	panel._unhandled_key_input(ev)
	check(not panel.visible and not get_tree().paused, "再按 C 关闭，游戏继续")
	await frames(2)
	check(main.bag_label.text.contains("金币 %d" % sh.gold) and main.char_btn.text.contains("+1"), "界面显示金币、药水，属性按钮提示还有 1 点未分配")
	main.queue_free()
	await frames(2)


# ---------- 阶段 P4：四个技能 ----------
func _wait_idle(hero: Player) -> void:
	## 等主角这一下出手（前摇 + 后摇）做完
	for i in 120:
		await physics(1)
		if hero.action == "":
			return


func test_skills() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.use_test_area = true      # 第 0 层用灰盒测试区（P7 起默认是烬原镇）
	main.auto_pack_test = false
	main.run_nav_bench = false
	main.spawn_monsters = false
	add_child(main)
	await frames(3)
	var hero: Player = main.hero
	var pr: HeroProgress = hero.progress
	var sf: Dictionary = Act1Data.rules().skill_formulas
	hero.global_position = Vector3(0, 0, 13)      # 大厅中央，四周开阔
	main.camera.snap()
	await physics(3)

	check(Player.skill_rule("fireball").mp == 5 and Player.skill_rule("whirl").lvl == 3 and Player.skill_rule("nova").cd == 3 and Player.skill_rule("blink").lvl == 10,
		"技能数值来自 V0.1：火球 5 法力、烬环斩 3 级解锁、寂霜环冷却 3 秒、闪现 10 级解锁")
	check(hero.skill_block_reason("whirl") == "烬环斩 需要 3 级" and not hero.cast_skill("whirl") and not hero.cast_skill("blink"), "1 级只会火球术，其余技能按等级解锁")

	# 火球术：直线飞、打中爆炸、范围 50% 溅射
	# 靶子：避开大厅的石柱（(0, 19) 等处有柱子），用长时间眩晕冻住，免得被打后反击把 64 血的主角打倒
	var a := Monsters.spawn("ash_brute", main.stage, Vector3(3, 0, 18), hero)
	var b := Monsters.spawn("ash_brute", main.stage, Vector3(4.2, 0, 18.6), hero)
	for e in [a, b]:
		e.stun_t = 1e6
		e.max_hp = 1000.0
		e.hp = 1000.0
	await physics(2)
	var mp0 := hero.mp
	check(hero.cast_skill("fireball", a.global_position), "对准怪物放火球")
	check(is_equal_approx(hero.mp, mp0 - 5.0) and hero.skill_cd.get("fireball", 0.0) > 0.0, "消耗 5 法力，进入 0.4 秒冷却")
	check(not hero.cast_skill("fireball", a.global_position), "冷却中不能连放")
	var dmg: float = (float(sf.fireball.base) + 1 * float(sf.fireball.per_lvl)) * pr.S.spell
	for i in 90:
		await physics(1)
		if a.hp < 1000.0:
			break
	await physics(1)
	var da := 1000.0 - a.hp
	var db := 1000.0 - b.hp
	check(da >= floor(dmg * 0.85) and da <= ceil(dmg * 1.15), "直接命中：伤害 = (4 + 1.6×等级) × 法术倍率 ±15%%（%.0f，期望约 %.1f）" % [da, dmg])
	check(db > 0.0 and db <= ceil(dmg * 0.5 * 1.15), "旁边的怪受 50%% 溅射（%.0f）" % db)
	# 撞墙也会爆炸：朝南墙放
	await seconds(0.5)
	var old_fb := hero.last_fireball
	hero.cast_skill("fireball", Vector3(0, 0, 40))
	await _wait_idle(hero)
	var fb: Fireball = hero.last_fireball
	check(fb != old_fb and is_instance_valid(fb), "前摇结束后火球飞出")
	var exploded := false
	for i in 90:
		await physics(1)
		if not is_instance_valid(fb):
			exploded = true
			break
	check(exploded, "火球撞到墙爆炸消失")

	# 升到 10 级，四个技能都能用
	await _wait_idle(hero)
	pr.sheet.lvl = 10
	pr.recalc()
	hero._apply_progress()
	hero.mp = hero.max_mp
	check(hero.skill_block_reason("blink") == "", "10 级四个技能都已解锁")

	# 烬环斩：周围一圈，130% 武器伤害
	a.global_position = hero.global_position + Vector3(1.5, 0, 0)
	b.global_position = hero.global_position + Vector3(-1.2, 0, 1.2)
	var far := Monsters.spawn("ash_brute", main.stage, hero.global_position + Vector3(3, 0, 5), hero)
	far.stun_t = 1e6
	far.max_hp = 1000.0
	far.hp = 1000.0
	await physics(3)
	var ha := a.hp
	var hb := b.hp
	var hf := far.hp
	check(hero.cast_skill("whirl"), "放烬环斩")
	await _wait_idle(hero)
	check(a.hp < ha and b.hp < hb and far.hp == hf, "身边一圈的怪都受伤，6 米外的不受影响")

	# 寂霜环：伤害 + 减速 3 秒；墙后的不受影响
	await seconds(0.3)
	var hn := a.hp
	check(hero.cast_skill("nova"), "放寂霜环")
	await _wait_idle(hero)
	var nova_dmg: float = (float(sf.nova.base) + 10 * float(sf.nova.per_lvl)) * pr.S.spell
	check(a.hp < hn and hn - a.hp >= floor(nova_dmg * 0.85) and hn - a.hp <= ceil(nova_dmg * 1.15), "寂霜环伤害 = (6 + 2×等级) × 法术倍率 ±15%%（%.0f）" % (hn - a.hp))
	check(a.slow_t > 2.5 and far.slow_t > 2.5, "范围内的怪被减速 3 秒（6 米内都算）")
	check(not hero.cast_skill("nova"), "寂霜环冷却 3 秒")

	# 暗影闪现：朝指定点瞬移，最远 10.5 米；不能闪进墙里
	await seconds(0.3)
	var p0 := hero.global_position
	check(hero.cast_skill("blink", p0 + Vector3(-6, 0, 2)), "放暗影闪现")
	await _wait_idle(hero)
	check(hero.global_position.distance_to(p0 + Vector3(-6, 0, 2)) < 0.3, "瞬移到指定位置")
	hero.skill_cd.clear()
	var p1 := hero.global_position
	hero.cast_skill("blink", p1 + Vector3(-40, 0, 0))
	await _wait_idle(hero)
	var moved := Vector2(hero.global_position.x - p1.x, hero.global_position.z - p1.z).length()
	check(moved <= Balance.skill("blink").range + 0.01 and hero.global_position.x > -12.0, "闪现最远 10.5 米，不会穿到西墙外（移动 %.1f 米，x = %.1f）" % [moved, hero.global_position.x])
	hero.skill_cd.clear()
	hero.global_position = Vector3(0, 0, 0)      # 北边房间里
	await physics(2)
	# 朝北墙外闪：和 V0.1 一样沿原路往回退，最终停在墙这一侧（北墙内侧 z = -5.7）
	hero.mp = hero.max_mp
	hero.cast_skill("blink", Vector3(0, 0, -20))
	await _wait_idle(hero)
	check(hero.global_position.z > -5.7 and hero.global_position.z < -1.0, "隔着墙闪不过去：退回到墙这一侧（z = %.1f）" % hero.global_position.z)
	hero.skill_cd.clear()
	hero.global_position = Vector3(5.2, 0, -5.2)      # 房间东北角，紧贴两面墙
	await physics(2)
	hero.mp = hero.max_mp
	var mp_b := hero.mp
	check(not hero.cast_skill("blink", Vector3(12, 0, -12)) and hero.last_skill_fail == "无法闪现到那里" and hero.mp == mp_b, "完全没有落脚点时放不出来，也不扣法力")

	# 法力不足
	await _wait_idle(hero)
	hero.skill_cd.clear()
	hero.mp = 3.0
	check(not hero.cast_skill("fireball") and hero.last_skill_fail == "法力不足", "法力不足时放不出来")

	# 自动瞄准：不给瞄准点时对准最近的可见敌人
	hero.global_position = Vector3(0, 0, 13)
	hero.mp = hero.max_mp
	hero.skill_cd.clear()
	far.global_position = Vector3(3, 0, 17)
	a.global_position = Vector3(-9, 0, 13)
	b.global_position = Vector3(-9, 0, 22)
	await physics(3)
	var prev_fb := hero.last_fireball
	check(hero.cast_skill("fireball"), "不给瞄准点也能放")
	for i in 30:
		await physics(1)
		if hero.last_fireball != prev_fb:
			break
	var want := (Vector3(3, 0, 17) - hero.global_position).normalized()
	check(is_instance_valid(hero.last_fireball) and hero.last_fireball.dir.dot(want) > 0.97, "手机按钮 / 不指向地面时，火球自动飞向最近的怪")

	# 界面：电脑有技能栏，冷却与锁定显示在格子上
	await frames(2)
	var bar: SkillBar = main.skill_bar
	check(bar != null and bar.slots.size() == 4 and bar.slots.fireball.text.contains("冷却"), "电脑下方技能栏四格，冷却中显示剩余时间")
	pr.sheet.lvl = 1
	pr.recalc()
	hero._apply_progress()
	await frames(2)
	check(bar.slots.blink.text.contains("10 级解锁") and bar.slots.blink.disabled, "未解锁的技能显示解锁等级并置灰")
	main.queue_free()
	await frames(2)


# ---------- 阶段 P5：怪物全表、精英、掉落 ----------
func test_loot() -> void:
	# 房间怪物群的规则（V0.1 genDungeon）
	var problems := []
	var total := 0
	var champ_packs := 0
	var packs := 0
	for f in range(1, 9):
		for sd in [5, 66, 777]:
			var m := DungeonGen.generate(f, sd)
			var pool := FloorRules.monster_pool(f)
			var by_room := {}
			for sp in m.spawns:
				if sp.room == m.boss_room and m.boss_room >= 0:
					continue      # 首领与护卫另测（bosses 组）
				total += 1
				var r: Dictionary = m.rooms[sp.room]
				if not pool.has(sp.key):
					problems.append("第%d层刷了池外的怪 %s" % [f, sp.key])
				if m.t[sp.cell.y * m.w + sp.cell.x] != DungeonGen.FLOOR:
					problems.append("怪物站在非地面格")
				if sp.room == m.start or sp.room == m.boss_room:
					problems.append("起点房或首领房里刷了怪")
				if sp.cell.x < r.x + 1 or sp.cell.x > r.x + r.w - 2 or sp.cell.y < r.y + 1 or sp.cell.y > r.y + r.h - 2:
					problems.append("怪物不在房间内侧")
				if not by_room.has(sp.room):
					by_room[sp.room] = []
				by_room[sp.room].append(sp)
			for ri in by_room:
				var pk: Array = by_room[ri]
				packs += 1
				var champs := {}
				var cells := {}
				for sp in pk:
					champs[sp.champ] = true
					cells[sp.cell] = true
				var champ: String = pk[0].champ
				var hi := 3 if champ != "" else (4 + (1 if f > 3 else 0))
				if champs.size() != 1 or cells.size() != pk.size() or pk.size() > hi:
					problems.append("第%d层怪物群不合规（%d 只，精英 %s）" % [f, pk.size(), champ])
				if champ != "":
					champ_packs += 1
	check(problems.is_empty(), "24 张地图的怪物群都合规：本层怪物池、房间内侧、起点房和首领房不刷、每群 2–4 只（深层 +1）、精英群同一特性 2–3 只 %s" % str(problems.slice(0, 3)))
	info("平均每层 %.1f 只怪、%.1f 群；精英群占 %.0f%%（V0.1 为 12%%）" % [total / 24.0, packs / 24.0, 100.0 * champ_packs / maxi(1, packs)])
	check(total / 24.0 > 12.0 and total / 24.0 < 50.0, "每层怪物数量合理")
	check(DungeonGen.generate(4, 9).spawns == DungeonGen.generate(4, 9).spawns, "同一层同一种子，怪物位置不变")

	# 精英数值
	var d := Monsters.scaled_def("zombie", 3, "fast")
	var m3 := FloorRules.scale_monster("zombie", 3, "fast")
	check(d.hp == m3.hp and d.name == "迅捷的腐尸" and d.xp == m3.xp and absf(d.speed - Monsters.get_def("zombie").speed * 1.45) < 0.001,
		"迅捷的腐尸：生命 ×2.6、经验 ×3、移动 ×1.45（%d 血）" % d.hp)
	var fury := Monsters.scaled_def("skel", 1, "fury")
	check(absf(fury.attack.recover_s - Monsters.get_def("skel").attack.recover_s * 0.6) < 0.001, "狂怒精英：攻击间隔 ×0.6")

	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()

	main.use_test_area = true      # 第 0 层用灰盒测试区（P7 起默认是烬原镇）
	main.auto_pack_test = false
	main.run_nav_bench = false
	main.spawn_monsters = false
	add_child(main)
	await frames(3)
	var hero: Player = main.hero
	hero.global_position = Vector3(0, 0, 13)
	main.camera.snap()
	await physics(2)

	var st := Monsters.spawn("zombie", main.stage, Vector3(4, 0, 13), hero, 1, "stone")
	st.stun_t = 1e6
	await physics(2)
	st.max_hp = 100.0
	st.hp = 100.0
	st.take_hit({"amount": 10, "crit": false, "type": "physical"}, Vector3.ZERO, 0.0)
	check(is_equal_approx(st.hp, 94.0), "石肤精英：受到的伤害 ×0.6（10 → 6）")
	check(st.find_child("ChampionRing", false, false) != null and st.hp_label.modulate.b > 0.9, "精英脚下有光环、名字是蓝色")
	var vp := Monsters.spawn("zombie", main.stage, Vector3(5, 0, 14), hero, 1, "vamp")
	vp.stun_t = 1e6
	await physics(2)
	vp.hp = 5.0
	vp.on_damage_dealt(7)
	check(is_equal_approx(vp.hp, 12.0), "嗜血精英：打中玩家按伤害回血")
	var fe := Monsters.spawn("zombie", main.stage, hero.global_position + Vector3(1.5, 0, 0), hero, 1, "fire")
	fe.stun_t = 1e6
	await physics(2)
	var hp0 := hero.hp
	fe.die()
	await seconds(0.5)
	check(hero.hp < hp0, "焚烧精英死亡时爆出火环，烧到身边的主角（-%.0f）" % (hp0 - hero.hp))

	# 掉落：精英必掉 1–2 件装备
	var before_items := get_tree().get_nodes_in_group("ground_item")
	var before := before_items.size()
	var ch := Monsters.spawn("skel", main.stage, hero.global_position + Vector3(3, 0, 1), hero, 1, "fury")
	ch.stun_t = 1e6
	await physics(2)
	ch.die()
	await frames(2)
	var items: Array = get_tree().get_nodes_in_group("ground_item").filter(func(g): return g.data.has("item") and not before_items.has(g))
	check(get_tree().get_nodes_in_group("ground_item").size() > before and items.size() >= 1, "打倒精英掉出装备（地上 %d 件）" % items.size())
	var g: GroundItem = items[0]
	check(g.label.text == g.data.item.name and g.label.modulate == GroundItem.RARITY_COLORS[int(g.data.item.rarity)], "地上的装备显示名字，颜色对应品质")
	check(g.global_position.distance_to(ch.global_position) < 2.0, "掉落物散在尸体周围")

	# 点击拾取：点名字 → 走过去 → 进背包
	hero.global_position = g.global_position + Vector3(-3, 0, 0)
	main.camera.snap()
	await physics(3)
	var sp: Vector2 = main.camera.unproject_position(g.global_position + Vector3(0, 0.8, 0))
	hero.click_at(sp)
	check(hero.pickup_target == g, "点地上装备的名字：锁定它为拾取目标")
	var inv0: int = hero.progress.sheet.inv.size()
	for i in 240:
		await physics(1)
		if hero.progress.sheet.inv.size() > inv0:
			break
	await frames(2)
	check(hero.progress.sheet.inv.size() == inv0 + 1 and not is_instance_valid(g), "走过去自动拾取，装备进背包")
	check(main.log_label.text.contains("拾取"), "左侧提示「拾取 ……」")
	var gold0: int = hero.progress.sheet.gold
	var gg := GroundItem.make({"gold": 50})
	main.stage.add_child(gg)
	gg.global_position = hero.global_position
	check(hero.pick_up(gg) and hero.progress.sheet.gold == gold0 + 50, "拾取金币")
	var pp := GroundItem.make({"pot": "mp"})
	main.stage.add_child(pp)
	var mp_pots: int = hero.progress.sheet.pots.mp
	check(hero.pick_up(pp) and hero.progress.sheet.pots.mp == mp_pots + 1, "拾取法力药水")
	while hero.progress.sheet.inv.size() < 40:
		hero.progress.sheet.inv.append({"name": "占位"})
	var rng := RandomNumberGenerator.new()
	var full := GroundItem.make({"item": ItemGen.generate(rng, 3)})
	main.stage.add_child(full)
	await frames(1)
	var picked_full := hero.pick_up(full)
	await frames(2)
	check(not picked_full and is_instance_valid(full) and main.log_label.text.contains("背包已满"), "背包满 40 件时捡不起来，东西留在地上")

	# 不再被挡路的怪卡住（P4 发现的问题）
	hero.global_position = Vector3(-6, 0, 13)
	var blocker := Monsters.spawn("ghoul", main.stage, Vector3(-3, 0, 13), hero)
	blocker.def.aggro = 0.0        # 不追击，原地待着（被眩晕的怪不移动，也就不会被挤开）
	blocker.max_hp = 1000.0
	blocker.hp = 1000.0
	var b0 := blocker.global_position
	await physics(2)
	hero.move_to(Vector3(0, 0, 13))
	var arrived := false
	for i in 180:
		await physics(1)
		if hero.global_position.distance_to(Vector3(0, 0, 13)) < 0.4:
			arrived = true
			break
	check(arrived, "点地移动时路上站着怪也能走过去（怪被推开）")
	check(blocker.global_position.distance_to(b0) > 0.2, "挡路的怪被挤开 %.2f 米" % blocker.global_position.distance_to(b0))

	# 地下城里满是怪
	main.run_seed = 99
	main.go_floor(2)
	await frames(3)
	check(main.monsters.size() == main.dungeon.spawns.size() and main.monsters.size() > 5 and main.monsters.all(func(e): return e.def.level == 4),
		"第 2 层按生成结果刷怪：%d 只，全是 4 级（第 2 层）" % main.monsters.size())
	var champs: Array = main.monsters.filter(func(e): return e.def.champ != "")
	info("第 2 层：%d 只怪，其中精英 %d 只" % [main.monsters.size(), champs.size()])
	main.queue_free()
	await frames(2)


# ---------- 阶段 P6：背包与装备 ----------
func _test_item(base: String, rarity: int, ilvl: int, aff := {}, req := 1) -> Dictionary:
	var it := {"id": 90000 + randi() % 9999, "base": base, "rarity": rarity, "ilvl": ilvl, "aff": aff.duplicate(), "name": "测试" + Act1Data.base(base).name, "req": req}
	ItemGen.apply_base_stats(it, Act1Data.base(base), ilvl)
	return it


func test_inventory() -> void:
	# 规则
	var sh := HeroStats.new_hero()
	var sword := _test_item("sword", 0, 1)
	var axe := _test_item("axe", 1, 6, {"dmgp": 12}, 3)
	sh.eq.weapon = sword
	sh.inv = [_test_item("cap", 0, 1), axe]
	check(not Inventory.equip(sh, 1) and sh.eq.weapon == sword, "等级不够（需要 3 级）穿不上")
	sh.lvl = 3
	check(Inventory.equip(sh, 1) and sh.eq.weapon == axe and sh.inv[1] == sword and sh.inv.size() == 2, "穿上战斧，原来的短剑放回同一个格子（V0.1 equip）")
	check(Inventory.unequip(sh, "weapon") and not sh.eq.has("weapon") and sh.inv[-1] == axe, "卸下武器放回背包末尾")
	while sh.inv.size() < 40:
		sh.inv.append(_test_item("ring", 1, 1, {"str": 1}))
	sh.eq.helm = _test_item("helm", 0, 5)
	check(not Inventory.unequip(sh, "helm") and sh.eq.has("helm"), "背包满了卸不下")
	var took := Inventory.take(sh, 0)
	check(took.base == "cap" and sh.inv.size() == 39 and Inventory.take(sh, 99).is_empty(), "从背包取出一件（丢在地上用）")
	var lines := Inventory.item_lines(axe, 1)
	var texts := lines.map(func(l): return l[0])
	check(texts[0] == axe.name and texts.has("+12% 伤害") and lines[-1][1] == "req_bad" and texts[1].begins_with("魔法 · 战斧 · 物品等级 6"), "物品说明：名字、品质与底材、伤害、词缀、需求等级（不够时标红）")
	var a := {"dmg": [4, 9], "spd": 1.0, "aff": {"str": 5, "crit": 2}, "arm": 0}
	var c := {"dmg": [2, 7], "spd": 1.15, "aff": {"str": 2, "ls": 3}, "arm": 0}
	var diff := Inventory.compare(a, c)
	var dmap := {}
	for dd in diff:
		dmap[dd[0]] = dd[1]
	check(is_equal_approx(dmap.get("武器每秒伤害", 0.0), 1.3) and dmap.get("力量") == 3.0 and dmap.get("暴击几率（%）") == 2.0 and dmap.get("生命偷取（%）") == -3.0 and Inventory.affix_label("regen") == "每秒回复 生命", "与已装备的比较：武器每秒伤害 = (最小+最大)×攻速÷2 的差（同 V0.1），词缀逐项相减 %s" % str(dmap))
	check(Inventory.compare(a, null).is_empty() and Inventory.compare(a, a).is_empty(), "没有同部位装备或和自己比时不显示比较")

	# 界面
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.use_test_area = true      # 第 0 层用灰盒测试区（P7 起默认是烬原镇）
	main.auto_pack_test = false
	main.run_nav_bench = false
	main.spawn_monsters = false
	add_child(main)
	await frames(3)
	var hero: Player = main.hero
	var hs: Dictionary = hero.progress.sheet
	var big := _test_item("lsword", 2, 12, {"dmgp": 30, "str": 5}, 1)
	var high := _test_item("plate", 1, 20, {"life": 20}, 15)
	hs.inv = [big, high]
	var panel: InvPanel = main.inv_panel
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_I
	ev.pressed = true
	main._unhandled_key_input(ev)
	check(panel.visible and get_tree().paused and panel.title.text.contains("背包 2 / 40"), "按 I 打开背包，游戏暂停")
	await frames(1)
	var sz := panel.get_global_rect().size
	check(sz.x <= 470 and sz.y <= 700, "面板尺寸放得进手机竖屏与 1280×720（%d × %d）" % [sz.x, sz.y])
	check(panel.eq_btns.weapon.text == "剑" and panel.inv_btns[0].text == "剑" and panel.inv_btns[5].text == "", "装备格与背包格显示物品字样，空格为空")
	panel.inv_btns[0].pressed.emit()
	await frames(1)
	var dtexts := panel.detail.get_children().filter(func(n): return n is Label and not n.is_queued_for_deletion()).map(func(n): return n.text)
	check(dtexts.has(big.name) and dtexts.any(func(t): return t.begins_with("与已装备的「")) and dtexts.any(func(t): return t.begins_with("▲")), "选中背包里的长剑：显示说明和与现在短剑的比较")
	await frames(1)
	var sz2 := panel.get_global_rect().size
	check(sz2.y <= 700 and absf(sz2.y - sz.y) < 1.0, "选中物品、说明很长时面板尺寸不变（%d）" % sz2.y)
	var wmax: int = hero.stats.weapon_max
	check(not panel.act_equip.disabled and panel.act_unequip.disabled, "可以装备（「卸下」置灰）")
	panel.act_equip.pressed.emit()
	await frames(1)
	check(hs.eq.weapon == big and hs.inv[0].base == "sword" and hero.stats.weapon_max > wmax, "装备后属性立即生效（伤害上限 %d → %d）" % [wmax, hero.stats.weapon_max])
	check(not panel.act_unequip.disabled and panel.act_equip.disabled and panel.act_drop.disabled, "选中的是身上的装备：只能「卸下」")
	panel.inv_btns[1].pressed.emit()
	await frames(1)
	check(panel.act_equip.disabled and (panel.inv_btns[1].get_theme_stylebox("normal") as StyleBoxFlat).bg_color.r > 0.3, "需要 15 级的板甲：不能装备，格子标红")
	panel.eq_btns.weapon.pressed.emit()
	await frames(1)
	panel.act_unequip.pressed.emit()
	await frames(1)
	check(not hs.eq.has("weapon") and hs.inv[-1] == big, "卸下武器回到背包")
	var gi_before := get_tree().get_nodes_in_group("ground_item").size()
	panel.inv_btns[0].pressed.emit()
	await frames(1)
	var dropped_name: String = hs.inv[0].name
	panel.act_drop.pressed.emit()
	await frames(2)
	var gis := get_tree().get_nodes_in_group("ground_item")
	check(gis.size() == gi_before + 1 and gis.any(func(g): return g.title() == dropped_name) and hs.inv.size() == 2, "丢在地上：背包少一件，脚边出现同名物品（可以再捡回来）")
	ev.physical_keycode = KEY_C
	main._unhandled_key_input(ev)
	check(main.char_panel.visible and not panel.visible and get_tree().paused, "按 C 打开角色面板时背包自动关上（同时只开一个）")
	main.char_panel.close()
	check(not get_tree().paused, "关上后游戏继续")
	main.inv_btn.pressed.emit()
	check(panel.visible, "右上角「背包」按钮也能打开")
	ev.physical_keycode = KEY_I
	panel._unhandled_key_input(ev)
	check(not panel.visible and not get_tree().paused, "再按 I 关闭")
	main.queue_free()
	await frames(2)


# ---------- 阶段 P7：烬原镇 ----------
func test_town() -> void:
	var tw := TownGen.generate()
	var T: Dictionary = Act1Data.rules().floors.town
	var bad := []
	for r in T.monastery.walls:
		for y in range(int(r[1]), int(r[3]) + 1):
			for x in range(int(r[0]), int(r[2]) + 1):
				if tw.t[y * tw.w + x] != DungeonGen.WALL:
					bad.append("修道院墙 %d,%d" % [x, y])
	for hs in T.houses:
		var r: Array = hs.rect
		if tw.t[int(r[1]) * tw.w + int(r[0])] != DungeonGen.WALL:
			bad.append("房屋 " + hs.id)
	for x in [16, 17, 18, 19]:
		if not DungeonGen.walkable(tw.t[8 * tw.w + x]):
			bad.append("修道院门口 %d 被堵" % x)
	for i in tw.w:
		if tw.t[i] != TownGen.TREE or tw.t[(tw.h - 1) * tw.w + i] != TownGen.TREE:
			bad.append("外圈不是树")
			break
	for c in tw.paths:
		if tw.t[c.y * tw.w + c.x] == TownGen.TREE:
			bad.append("石板路上长了树")
			break
	check(bad.is_empty() and tw.down == Vector2i(17, 4) and tw.t[4 * tw.w + 17] == DungeonGen.DOWN and tw.npcs.size() == 3,
		"烬原镇布局同 V0.1 genTown：修道院废墟与门口、5 座房屋、外圈树林、石板路、地窖入口 (17, 4)、3 个人物 %s" % str(bad.slice(0, 3)))
	check(TownGen.generate().t == tw.t, "每次进镇布局一样")

	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.auto_pack_test = false
	main.run_nav_bench = false
	add_child(main)
	await frames(3)
	var hero: Player = main.hero
	var sh: Dictionary = hero.progress.sheet
	check(main.floor_i == 0 and not main.use_test_area and main.npcs.size() == 3 and hero.in_town and main.monsters.is_empty(), "开局在烬原镇（P7 起第 0 层默认是镇子），镇上没有怪物")
	check(hero.global_position.distance_to(TownGen.to_world(19.5, 21.5)) < 0.5, "开局站在篝火旁（V0.1 起点）")
	check(main.level.navigation_mesh.get_polygon_count() > 20 and main.stairs.has("down") and not main.stairs.has("up"), "镇子导航已烘焙；只有往下的地窖入口")
	await physics(3)
	var map := hero.get_world_3d().navigation_map
	var path := NavigationServer3D.map_get_path(map, hero.global_position, main.stairs.down.global_position, true)
	check(path.size() > 1 and path[-1].distance_to(main.stairs.down.global_position) < 1.0, "从篝火能走到修道院里的地窖入口")
	var fire := TownGen.to_world(20.5, 17.5)
	var on_fire := NavigationServer3D.map_get_closest_point(map, fire)
	check(Vector2(on_fire.x - fire.x, on_fire.z - fire.z).length() > 0.5, "篝火、水井等道具挡路（导航绕开）")
	check(not hero.cast_skill("fireball") and hero.last_skill_fail == "镇上不能施法", "镇上不能施法（V0.1）")

	# 点伊莲 → 走过去 → 对话，回满生命法力（先把任务设成进行中，这里只测日常对话；任务在 quests 组）
	sh.q = {"q1": 1, "q2": 1, "q3": 0}
	var elin: Npc = main.npc("elin")
	hero.hp = 10.0
	hero.mp = 1.0
	main.camera.snap()
	await physics(2)
	var sp: Vector2 = main.camera.unproject_position(elin.global_position + Vector3(0, 1.5, 0))
	hero.click_at(sp)
	check(hero.talk_target == elin, "点伊莲：锁定为对话目标")
	var dp: DialogPanel = main.dialog_panel
	for i in 240:
		await physics(1)
		if dp.visible:
			break
	check(dp.visible and get_tree().paused and dp.who.text == "老祭司 伊莲", "走到伊莲身边打开对话，游戏暂停")
	check(hero.hp == hero.max_hp and hero.mp == hero.max_mp, "伊莲为你恢复全部生命与法力")
	var btn_texts: Array = dp.opts.get_children().map(func(b): return b.text)
	check(btn_texts == ["关于烬原镇", "告辞"], "伊莲的选项（没有任务可接时）：关于烬原镇 / 告辞%s" % str(btn_texts))
	dp.opts.get_child(0).pressed.emit()
	await frames(1)
	var body_texts: Array = dp.body.get_children().map(func(l): return l.text)
	check(body_texts.size() == 2 and String(body_texts[0]).begins_with("烬原镇建在三十年前"), "「关于烬原镇」的话与 V0.1 一致")
	dp.opts.get_child(0).pressed.emit()     # 返回
	await frames(1)
	dp.opts.get_children().back().pressed.emit()   # 告辞
	check(not dp.visible and not get_tree().paused, "告辞关闭对话，游戏继续")

	# 格伦：交易（买、卖）
	main._talk(main.npc("gren"))
	check(dp.visible and dp.opts.get_child(0).text == "交易", "格伦：交易")
	dp.opts.get_child(0).pressed.emit()
	var shp: ShopPanel = main.shop_panel
	check(shp.visible and not dp.visible and get_tree().paused and shp.which == "smith" and shp.stock.size() == 8, "打开格伦的货架：8 件货")
	check(shp.stock.all(func(it): return not Act1Data.base(it.base).get("magic_only", false)), "格伦不卖戒指护符")
	sh.gold = 1000
	var it0: Dictionary = shp.stock[0]
	var price := ItemGen.value(it0)
	var inv0: int = sh.inv.size()
	shp.sel = {"kind": "item", "item": it0}
	shp.refresh()
	check(shp.act.text == "购买（%d 金币）" % price and not shp.act.disabled, "选中一件显示价格（V0.1 itemValue）")
	shp.act.pressed.emit()
	check(sh.gold == 1000 - price and sh.inv.size() == inv0 + 1 and shp.stock.size() == 7, "买下：扣 %d 金币、进背包、货架少一件" % price)
	shp._set_tab("sell")
	var sell_it: Dictionary = sh.inv[-1]
	shp.sel = {"kind": "inv", "item": sell_it}
	shp.refresh()
	var g0: int = sh.gold
	shp.act.pressed.emit()
	check(sh.gold == g0 + ItemGen.sell_value(sell_it) and sh.inv.size() == inv0, "卖出：得到 1/4 价格（%d 金币）" % ItemGen.sell_value(sell_it))
	shp._set_tab("buy")
	sh.gold = 1
	shp.sel = {"kind": "item", "item": shp.stock[0]}
	shp.refresh()
	check(shp.act.disabled, "金币不够时买不了")
	shp.close()
	check(not get_tree().paused, "关上货架游戏继续")

	# 玛拉：药水与卷轴
	main.open_shop("alchemist")
	check(shp.stock.size() == 2 and shp.stock.all(func(it): return it.base in ["ring", "amulet"]), "玛拉的货架：药水、回城卷轴，外加 2 件戒指 / 护符")
	sh.gold = 100
	var hp_pots: int = sh.pots.hp
	shp.sel = {"kind": "pot", "pot": "hp"}
	shp.refresh()
	shp.act.pressed.emit()
	shp.sel = {"kind": "pot", "pot": "tp"}
	shp.refresh()
	shp.act.pressed.emit()
	check(sh.pots.hp == hp_pots + 1 and sh.gold == 100 - 25 - 40, "买生命药水 25 金币、回城卷轴 40 金币（V0.1）")
	shp.close()

	# 下地窖再上来：站在地窖入口旁，商店重新进货
	var stock_before: Array = main.shop_stock.smith
	hero.global_position = main.stairs.down.global_position
	for i in 60:
		await physics(1)
		if main.floor_i == 1:
			break
	await frames(2)
	check(main.floor_i == 1 and not hero.in_town, "走进地窖入口 → 修道院地窖第 1 层")
	check(main.stairs.up.label.text == "↑ 烬原镇", "第 1 层的上楼梯通往烬原镇")
	main.go_floor(0, "up")
	await frames(2)
	check(main.floor_i == 0 and hero.in_town and hero.global_position.distance_to(DungeonBuilder.cell_center(Vector2i(17, 4))) < 4.5, "上楼回到镇上，站在地窖入口旁")
	check(main.shop_stock.smith != stock_before, "每次进镇商店重新进货（V0.1）")

	# 在地下倒下 → 在烬原镇复活
	main.go_floor(2)
	await frames(2)
	sh.gold = 200
	hero.hp = 1.0
	hero.take_hit({"amount": 99, "crit": false, "type": "physical"}, Vector3.ZERO, 0.0)
	await frames(1)
	check(main.dead_label.text.contains("在烬原镇复活"), "倒下提示「3 秒后在烬原镇复活」")
	await seconds(3.5)
	await frames(3)
	check(main.floor_i == 0 and not hero.dead and hero.global_position.distance_to(TownGen.to_world(19.5, 21.5)) < 0.5 and sh.gold == 180, "倒下后在烬原镇篝火旁复活，掉 10% 金币")
	main.queue_free()
	await frames(2)


## P8：任务、传送石、回城卷轴、小地图
func _logs(main: Node) -> String:
	return " | ".join(main.log_lines.map(func(l): return l[0]))


func test_quests() -> void:
	# ---- 规则（Quests，同 V0.1 talk / npcMark / goFloor / bossDown） ----
	var sh := HeroStats.new_hero()
	var rng := RandomNumberGenerator.new()
	rng.seed = 8
	check(Quests.mark("elin", sh) == "!" and Quests.mark("gren", sh) == "" and Quests.branch("elin", sh) == "elin_q1_offer" and Quests.log_entries(sh).is_empty(), "新角色：伊莲头顶「!」，格伦没有标记，任务日志为空")
	Quests.accept("elin_q1_offer", sh, rng)
	check(sh.q.q1 == 1 and Quests.mark("elin", sh) == "" and Quests.mark("gren", sh) == "!", "接下「地窖里的钟声」后格伦有新任务")
	check(Quests.on_floor(sh, 1) == "" and sh.q.q1 == 1 and sh.maxFloor == 1, "到第 1 层：任务不变，记下最深到过第 1 层")
	check(Quests.on_floor(sh, 2) != "" and sh.q.q1 == 2 and Quests.mark("elin", sh) == "?", "到第 2 层：任务可交付，伊莲头顶「?」")
	var pots0: int = sh.pots.hp
	var r := Quests.accept("elin_q1_turnin", sh, rng)
	check(sh.q.q1 == 3 and sh.pots.hp == pots0 + 3 and r.xp == 120 and r.retalk, "交任务：生命药水 +3、法力药水 +2、120 经验（V0.1）")
	check(Quests.branch("elin", sh) == "" and Quests.elin_idle(sh) == Act1Data.dialogs().elin.idle.default, "伊莲没有新任务时说日常的话")
	Quests.accept("gren_q2_offer", sh, rng)
	check(Quests.elin_idle(sh).begins_with("格伦的学徒"), "「铁匠的学徒」进行中，伊莲的话随之变化")
	check(Quests.on_boss_down(sh, "mog").log != "" and sh.q.q2 == 2 and Quests.mark("gren", sh) == "?", "击败莫格（P9 调用）：救出托比，格伦头顶「?」")
	r = Quests.accept("gren_q2_turnin", sh, rng)
	var w: Dictionary = r.item
	check(sh.q.q2 == 3 and w.rarity == 2 and Act1Data.base(w.base).slot == "weapon" and w.ilvl >= 8 and r.xp == 400 and r.toby, "交任务：稀有武器（物品等级至少 8）+ 400 经验，托比回镇（V0.1）")
	check(Quests.branch("elin", sh) == "elin_q3_offer" and Quests.mark("elin", sh) == "!", "托比得救后伊莲给「余烬之心」")
	var sh2 := HeroStats.new_hero()
	sh2.q = {"q1": 3, "q2": 1, "q3": 0}
	sh2.maxFloor = 4
	check(Quests.branch("elin", sh2) == "elin_q3_offer", "或者到过第 4 层，伊莲也给「余烬之心」（V0.1）")
	Quests.accept("elin_q3_offer", sh, rng)
	var ob := Quests.on_boss_down(sh, "mordan")
	check(sh.q.q3 == 2 and ob.epilogue and Quests.mark("elin", sh) == "?", "击败摩登：播放结局文字，伊莲头顶「?」")
	r = Quests.accept("elin_q3_turnin", sh, rng)
	check(sh.q.q3 == 3 and sh.won and r.item.rarity == 3 and r.xp == 1500, "交任务：传奇物品 + 1500 经验，通关（V0.1 won）")
	var le := Quests.log_entries(sh)
	check(le.size() == 3 and le.all(func(e): return e.state == 3) and le[1].title == "铁匠的学徒", "任务日志三条全部完成")

	# ---- 场景：镇上接任务、交任务 ----
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.auto_pack_test = false
	main.run_nav_bench = false
	add_child(main)
	await frames(3)
	var hero: Player = main.hero
	var ps: Dictionary = hero.progress.sheet
	var dp: DialogPanel = main.dialog_panel
	var elin: Npc = main.npc("elin")
	check(elin.mark.text == "!" and main.npc("gren").mark.text == "" and _logs(main).contains("头顶有「!」"), "开局伊莲头顶「!」，左侧提示去找她")
	# 传送石：还没下过地窖时不能用
	var wp: InteractSpot = null
	var well: InteractSpot = null
	for s in get_tree().get_nodes_in_group("interact"):
		if s.kind == "wp":
			wp = s
		elif s.kind == "well":
			well = s
	check(wp != null and well != null and wp.global_position.distance_to(TownGen.to_world(21.5, 22.5)) < 0.5, "镇上有传送石与水井，可以点")
	main._use_spot(wp)
	check(not dp.visible and _logs(main).contains("传送石沉默着"), "还没到过地下任何一层：传送石沉默（V0.1）")
	hero.hp = 5.0
	main._use_spot(well)
	check(hero.hp == hero.max_hp, "水井回满生命（V0.1）")
	main.cast_town_portal()
	check(_logs(main).contains("你已经在镇上了") and main.tp.is_empty(), "镇上用不了回城卷轴")

	main._talk(elin)
	var bt: Array = dp.opts.get_children().map(func(b): return b.text)
	check(dp.visible and String(dp.body.get_child(0).text).begins_with("又一个旅人") and bt == ["我去地窖看看。", "告辞"], "伊莲讲述钟声的来历，给出任务 %s" % str(bt))
	dp.opts.get_child(0).pressed.emit()
	await frames(1)
	check(not dp.visible and ps.q.q1 == 1 and elin.mark.text == "" and main.npc("gren").mark.text == "!", "接下任务：对话关闭，伊莲的「!」消失，格伦出现「!」")
	main._talk(main.npc("gren"))
	bt = dp.opts.get_children().map(func(b): return b.text)
	check(bt == ["我会把托比带回来。", "先看看你的货", "告辞"], "格伦托付学徒的事，也可以先看货 %s" % str(bt))
	dp.opts.get_child(1).pressed.emit()
	check(main.shop_panel.visible and main.shop_panel.which == "smith" and ps.q.q2 == 0, "「先看看你的货」打开货架，任务还没接")
	main.shop_panel.close()
	main._talk(main.npc("gren"))
	dp.opts.get_child(0).pressed.emit()
	check(ps.q.q2 == 1 and main.npc("gren").mark.text == "", "接下「铁匠的学徒」")
	# 任务日志
	main._toggle_panel(main.quest_panel)
	var qp: QuestPanel = main.quest_panel
	await frames(1)
	check(qp.visible and get_tree().paused and qp.list.get_child_count() == 2, "任务日志（J）列出两条进行中的任务，打开时暂停")
	var qs := qp.get_combined_minimum_size()
	check(qs.x <= 360 and qs.y <= 700, "任务日志放得进手机竖屏 %s" % str(qs))
	qp.close()
	check(not get_tree().paused, "关上任务日志游戏继续")

	# 下到第 2 层：任务可交付；小地图与视野
	main.go_floor(2)
	await frames(2)
	check(ps.q.q1 == 2 and ps.maxFloor == 2 and _logs(main).contains("回镇上告诉伊莲"), "到第 2 层：「地窖里的钟声」可交付")
	var mm: Minimap = main.minimap
	var n_seen := 0
	for v in main.seen:
		n_seen += v
	var up_cell: Vector2i = main.dungeon.up
	check(n_seen > 20 and n_seen < main.seen.size() / 3 and main.cell_visible(hero.global_position), "视野：只记下主角周围看得见的格子（%d / %d）" % [n_seen, main.seen.size()])
	check(mm.visible and mm.size.x >= 110 and mm.size.x <= 160 and not mm.big, "右上角小地图 %s" % str(mm.size))
	main.toggle_map()
	await frames(1)
	check(mm.big and mm.size == mm.get_viewport_rect().size, "Tab / 「地图」打开全屏自动地图")
	main.toggle_map()
	check(not mm.big, "再按一次关闭")
	var c0: Vector2 = mm.project(hero.global_position)
	var ahead: Vector3 = hero.global_position - main.camera.global_transform.basis.z.slide(Vector3.UP).normalized() * 4.0
	check(c0.distance_to(mm.size / 2.0) < 0.5 and mm.project(ahead).y < c0.y - 2.0, "小地图以主角为中心，镜头前方在上")

	# 回城卷轴：开门 → 穿过去回镇 → 从镇上那头回到原处
	ps.pots.tp = 1
	main.cast_town_portal()
	await frames(1)
	var portal: InteractSpot = null
	for s in get_tree().get_nodes_in_group("interact"):
		if s.kind == "portal":
			portal = s
	check(ps.pots.tp == 0 and portal != null and portal.to == "town" and main.tp.floor == 2, "回城卷轴：用掉一张，身边打开蓝色传送门")
	main.cast_town_portal()
	check(_logs(main).contains("没有回城卷轴"), "没有卷轴时提示去玛拉处买")
	var back_pos: Vector3 = main.tp.pos
	await seconds(0.9)
	hero.global_position = portal.global_position
	for i in 90:
		await physics(1)
		if main.floor_i == 0:
			break
	await frames(2)
	var tportal: InteractSpot = null
	for s in get_tree().get_nodes_in_group("interact"):
		if s.kind == "portal" and is_instance_valid(s) and not s.is_queued_for_deletion():
			tportal = s
	check(main.floor_i == 0 and hero.global_position.distance_to(main.town_portal_spot()) < 3.0 and tportal != null and tportal.to == "dungeon" and tportal.label.text == "传送门：" + FloorRules.floor_name(2), "走进传送门回到镇上，镇上的传送点有通回去的门")
	await seconds(1.1)
	check(main.floor_i == 0, "刚到镇上站在门边不会被送回去")
	# 交任务（顺便：伊莲说完会接着再对话一次）；换层后镇上的人是重新搭的
	elin = main.npc("elin")
	main._talk(elin)
	bt = dp.opts.get_children().map(func(b): return b.text)
	var hp0: int = ps.pots.hp
	check(elin.mark.text == "?" and bt == ["收下药水"], "伊莲头顶「?」，交任务 %s" % str(bt))
	dp.opts.get_child(0).pressed.emit()
	await frames(1)
	check(ps.q.q1 == 3 and ps.pots.hp == hp0 + 3 and dp.visible, "收下药水：生命药水 +3，伊莲接着说话")
	dp.close()
	# 从镇上那头回到原处
	hero.global_position = tportal.global_position
	for i in 90:
		await physics(1)
		if main.floor_i == 2:
			break
	await frames(2)
	var left := 0
	for s in get_tree().get_nodes_in_group("interact"):
		if s.kind == "portal" and not s.is_queued_for_deletion():
			left += 1
	check(main.floor_i == 2 and Vector2(hero.global_position.x - back_pos.x, hero.global_position.z - back_pos.z).length() < 2.5 and main.tp.is_empty() and left == 0, "从镇上的门回到第 2 层原处，传送门关闭")
	var n_seen2 := 0
	for v in main.seen:
		n_seen2 += v
	check(n_seen2 >= n_seen, "回到去过的楼层，自动地图还记得（%d → %d）" % [n_seen, n_seen2])

	# 传送石：列出到过的楼层
	main.go_floor(0, "up")
	await frames(2)
	for s in get_tree().get_nodes_in_group("interact"):
		if s.kind == "wp":
			wp = s
	hero.global_position = TownGen.to_world(19.5, 21.5)
	main.camera.snap()
	await physics(2)
	var wsp: Vector2 = main.camera.unproject_position(wp.global_position + Vector3(0, 1.2, 0))
	hero.click_at(wsp)
	check(hero.talk_target == wp, "点传送石：走过去")
	for i in 300:
		await physics(1)
		if dp.visible:
			break
	bt = dp.opts.get_children().map(func(b): return b.text)
	check(dp.visible and dp.who.text == "传送石" and bt.size() == 3 and bt[1] == FloorRules.floor_name(2), "传送石：第 1、2 层可选 %s" % str(bt))
	dp.opts.get_child(1).pressed.emit()
	await frames(2)
	check(main.floor_i == 2 and not dp.visible and hero.global_position.distance_to(DungeonBuilder.cell_center(main.dungeon.up)) < 4.5, "传送到第 2 层入口")

	# 救出托比、结局文字（首领在 P9，这里直接调用）
	main.go_floor(0, "up")
	await frames(2)
	main.on_boss_down("mog")
	main._refresh_marks()
	check(ps.q.q2 == 2 and main.npc("gren").mark.text == "?" and main.npc("toby") == null, "击败莫格后：格伦头顶「?」")
	main._talk(main.npc("gren"))
	var inv0: int = ps.inv.size()
	dp.opts.get_child(0).pressed.emit()
	await frames(1)
	var toby: Npc = main.npc("toby")
	check(ps.q.q2 == 3 and ps.inv.size() == inv0 + 1 and ps.inv[-1].rarity == 2 and toby != null and toby.global_position.distance_to(TownGen.to_world(12.4, 17.2)) < 0.5, "收下报酬：稀有武器进背包，学徒托比出现在铁匠铺旁")
	main._talk(toby)
	check(dp.visible and dp.who.text == "学徒 托比" and Act1Data.dialogs().toby.lines.has(dp.body.get_child(0).text), "托比说一句感谢的话")
	dp.close()
	main.go_floor(1)
	await frames(2)
	main.go_floor(0, "up")
	await frames(2)
	check(main.npc("toby") != null and main.npc("elin").mark.text == "!", "之后每次进镇托比都在；伊莲给「余烬之心」")
	main.on_boss_down("mordan")
	await seconds(1.8)
	check(dp.visible and dp.who.text == "封印大厅" and String(dp.body.get_child(0).text).begins_with("摩登院长倒下时"), "击败摩登 1.6 秒后播放结局文字（V0.1 epilogue）")
	dp.close()
	main.queue_free()
	await frames(2)


## P9：两个首领
func _boss_prep(main: Node, hero: Player) -> EnemyBase:
	## 清掉首领的护卫，主角血量拉到很高（只测首领的招式），站在首领房里离首领 6 米的地方
	for e in main.monsters:
		if is_instance_valid(e) and e != main.boss:
			e.queue_free()
	hero.max_hp = 1e7
	hero.hp = 1e7
	var c := DungeonBuilder.cell_center(main.dungeon.boss_stairs)
	hero.global_position = c + Vector3(6.0, 0, 0)
	hero.stop()
	main.camera.snap()
	return main.boss


func test_bosses() -> void:
	# ---- 规则：首领房的刷怪（V0.1 genDungeon） ----
	var m3 := DungeonGen.generate(3, 42)
	var b3: Array = m3.spawns.filter(func(sp): return sp.get("boss", false))
	var g3: Array = m3.spawns.filter(func(sp): return sp.room == m3.boss_room and not sp.get("boss", false))
	check(b3.size() == 1 and b3[0].key == "mog" and b3[0].cell == m3.boss_stairs and g3.size() >= 3 and g3.all(func(sp): return sp.key == "zombie"), "第 3 层：首领房正中是莫格，带 %d 只腐尸护卫" % g3.size())
	var m6 := DungeonGen.generate(6, 42)
	var b6: Array = m6.spawns.filter(func(sp): return sp.get("boss", false))
	var g6: Array = m6.spawns.filter(func(sp): return sp.room == m6.boss_room and not sp.get("boss", false))
	check(b6.size() == 1 and b6[0].key == "abbot" and g6.all(func(sp): return sp.key == "skel"), "第 6 层：首领房正中是摩登，带骸骨战士护卫")
	var m10 := DungeonGen.generate(10, 42)
	var b10: Array = m10.spawns.filter(func(sp): return sp.get("boss", false))
	check(b10.size() == 1 and String(b10[0].get("name", "")).begins_with("深渊化身 · ") and m10.down.x < 0, "深渊第 10 层：首领改名「深渊化身」，击败前没有下楼梯")
	check(DungeonGen.generate(4, 42).spawns.all(func(sp): return not sp.get("boss", false)), "非首领层没有首领")
	var dm := Monsters.scaled_def("mog", 3)
	check(dm.hp == 340 and dm.level == 9 and dm.attack.dmg == [10, 21] and dm.boss, "莫格第 3 层数值同 V0.1：生命 200 ×（1 + 0.35 × 2）= 340、9 级、伤害 [6, 13] ×（1 + 0.3 × 2）= %s" % str(dm.attack.dmg))

	# ---- 场景：第 3 层莫格 ----
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.auto_pack_test = false
	main.run_nav_bench = false
	add_child(main)
	await frames(3)
	var hero: Player = main.hero
	var sh: Dictionary = hero.progress.sheet
	sh.q = {"q1": 3, "q2": 1, "q3": 0}
	main.go_floor(3)
	await frames(2)
	var mog: EnemyBossMog = main.boss
	check(mog != null and mog.global_position.distance_to(DungeonBuilder.cell_center(main.dungeon.boss_stairs)) < 0.5 and not main.stairs.has("down"), "进入第 3 层：莫格在首领房正中，还没有下楼梯")
	check(_logs(main).contains("这一层有强大的存在") and not main.boss_box.visible, "进层提示有强大的存在；首领没被惊动时不显示血条")
	_boss_prep(main, hero)
	for i in 60:
		await physics(1)
		if mog.state != "idle":
			break
	await frames(1)
	check(mog.state != "idle" and _logs(main).contains("监工要你干活") and main.boss_box.visible and main.boss_name.text == "腐肉监工 · 莫格", "发现主角：莫格喊话，屏幕下方出现首领血条")
	# 拉开距离、冲锋冷却清零：下一次决策就该冲锋
	var ctr := DungeonBuilder.cell_center(main.dungeon.boss_stairs)
	hero.global_position = ctr + (ctr - mog.global_position).normalized() * 4.0 if mog.global_position.distance_to(ctr) > 1.0 else ctr + Vector3(-6.0, 0, 0)
	mog.set_state("chase")
	mog.cooldowns["rush"] = 0.0
	var saw_warn := false
	var hp0 := hero.hp
	for i in 400:
		await physics(1)
		if mog.state == "windup" and mog.mode == 1 and mog.has_warning():
			saw_warn = true
		if saw_warn and hero.hp < hp0:
			break
	check(saw_warn and hero.hp < hp0, "冲锋：先亮红色长条预警，再冲过来撞中主角（掉血 %d）" % int(hp0 - hero.hp))
	mog.hp = mog.max_hp * 0.45
	for i in 30:
		await physics(1)
		if mog.enraged:
			break
	check(mog.enraged and _logs(main).contains("莫格暴怒了"), "生命低于一半：莫格暴怒")
	var items0 := get_tree().get_nodes_in_group("ground_item").size()
	mog.take_hit({"amount": 99999, "crit": false, "type": "physical"}, Vector3.ZERO, 0.0)
	await frames(2)
	var drops := get_tree().get_nodes_in_group("ground_item").size() - items0
	check(main.bosses_dead.has(3) and main.stairs.has("down") and main.stairs.down.global_position.distance_to(DungeonBuilder.cell_center(main.dungeon.boss_stairs)) < 0.5 and _logs(main).contains("阶梯出现了"), "击败莫格：首领房中间出现下楼梯")
	check(sh.q.q2 == 2 and _logs(main).contains("找到了被锁住的托比"), "「铁匠的学徒」变为可交付：托比逃回了镇上")
	check(drops >= 5, "首领掉落：金币、装备 4 件、生命药水（%d 件）" % drops)
	check(not main.boss_box.visible, "首领倒下后血条消失")
	main.go_floor(2)
	await frames(2)
	main.go_floor(3)
	await frames(2)
	check(main.boss == null and main.stairs.has("down") and main.monsters.all(func(e): return e.def.get("family", "") != "首领"), "回到第 3 层：莫格不再出现，下楼梯开着")

	# ---- 第 6 层摩登 ----
	sh.q.q3 = 1
	main.go_floor(6)
	await frames(2)
	var ab: EnemyBossAbbot = main.boss
	check(ab != null and ab.arena.has_area(), "进入第 6 层：摩登在封印大厅")
	_boss_prep(main, hero)
	hero.global_position = DungeonBuilder.cell_center(main.dungeon.boss_stairs) + Vector3(7.0, 0, 0)
	for i in 60:
		await physics(1)
		if ab.state != "idle":
			break
	check(_logs(main).contains("火焰选中的"), "摩登喊话")
	var bolts := 0
	for i in 200:
		await physics(1)
		bolts = main.stage.get_children().filter(func(n): return n is Projectile).size()
		if bolts >= 3:
			break
	check(bolts >= 3, "邪术弹一次 3 发扇形（%d）" % bolts)
	ab.cooldowns["nova"] = 0.0
	await physics(3)
	var ring: NovaRing = null
	for n in main.stage.get_children():
		if n is NovaRing:
			ring = n
	hp0 = hero.hp
	for i in 120:
		await physics(1)
		if not is_instance_valid(ring) or ring.hit:
			break
	check(ring != null and hero.hp < hp0, "烈焰新星：火环扩散，扫到主角造成火焰伤害")
	var n_mon: int = main.get_tree().get_nodes_in_group("enemy").size()
	ab.cooldowns["summon"] = 0.0
	await physics(3)
	check(ab.minions.size() == 2 and main.get_tree().get_nodes_in_group("enemy").size() == n_mon + 2, "召唤 2 只骸骨战士")
	for mn in ab.minions:
		mn.queue_free()
	hero.global_position = ab.global_position + Vector3(2.0, 0, 0)
	ab.cooldowns["blink"] = 0.0
	var ab_pos := ab.global_position
	for i in 30:
		await physics(1)
		if ab.global_position.distance_to(ab_pos) > 3.0:
			break
	check(ab.global_position.distance_to(ab_pos) >= 4.0 and ab.arena.has_point(Vector2(ab.global_position.x, ab.global_position.z)), "被贴近：摩登瞬移到 4.5 米以外，仍在封印大厅里")
	ab.hp = ab.max_hp * 0.45
	for i in 30:
		await physics(1)
		if ab.phase == 2:
			break
	await frames(1)
	check(ab.phase == 2 and main.boss_name.text == "灰烬之王的容器 · 摩登" and ab.visual.scale.x > 1.2 and _logs(main).contains("正在变成别的东西"), "生命低于一半：二阶段「灰烬之王的容器 · 摩登」，体型变大")
	ab.cooldowns["shot"] = 0.0
	hero.global_position = ab.global_position + Vector3(7.0, 0, 0)
	for n in main.stage.get_children():
		if n is Projectile:
			n.queue_free()
	await physics(2)
	bolts = 0
	for i in 60:
		await physics(1)
		bolts = main.stage.get_children().filter(func(n): return n is Projectile and not n.is_queued_for_deletion()).size()
		if bolts >= 5:
			break
	check(bolts >= 5, "二阶段邪术弹一次 5 发（%d）" % bolts)
	ab.take_hit({"amount": 999999, "crit": false, "type": "physical"}, Vector3.ZERO, 0.0)
	await frames(2)
	check(sh.q.q3 == 2 and main.stairs.has("down"), "击败摩登：「余烬之心」可交付，通往第 7 层的阶梯出现")
	await seconds(1.8)
	check(main.dialog_panel.visible and main.dialog_panel.who.text == "封印大厅", "1.6 秒后播放结局文字")
	main.dialog_panel.close()
	main.queue_free()
	await frames(2)


## P10：木桶、宝箱、神殿、照明范围与战争迷雾
func _spots(main: Node, kind: String) -> Array:
	return main.stage.get_children().filter(func(n): return n is InteractSpot and n.kind == kind and not n.is_queued_for_deletion())


func test_props() -> void:
	# ---- 规则（V0.1 genDungeon「房间内容」） ----
	var problems := []
	var shrine_floors := 0
	var rooms_n := 0
	var chests := 0
	var maps := 0
	for f in range(1, 9):
		for sd in [5, 66, 777, 4242]:
			var m := DungeonGen.generate(f, sd)
			maps += 1
			var spawn_cells := {}
			for sp in m.spawns:
				spawn_cells[sp.cell] = true
			var per_room := {}
			var shrines := 0
			for pr in m.props:
				if pr.room == m.start or pr.room == m.boss_room:
					problems.append("起点房或首领房里有道具")
				if m.t[pr.cell.y * m.w + pr.cell.x] != DungeonGen.FLOOR or spawn_cells.has(pr.cell):
					problems.append("道具不在空地上")
				if not per_room.has(pr.room):
					per_room[pr.room] = {"barrel": 0, "chest": 0, "shrine": 0}
				per_room[pr.room][pr.type] += 1
				if pr.type == "shrine":
					shrines += 1
			for ri in per_room:
				if per_room[ri].barrel > 3 or per_room[ri].chest > 1:
					problems.append("一个房间木桶超过 3 个或宝箱超过 1 个")
				chests += per_room[ri].chest
			rooms_n += m.rooms.size() - (2 if m.boss_room >= 0 else 1)
			if shrines > 1:
				problems.append("一层不止一座神殿")
			shrine_floors += shrines
	check(problems.is_empty(), "32 张地图的道具都合规：不在起点房和首领房、不占楼梯和怪物的格子、每间最多 3 个木桶 1 个宝箱、每层最多 1 座神殿 %s" % str(problems.slice(0, 3)))
	check(shrine_floors >= maps * 0.5 and chests >= rooms_n * 0.1 and chests <= rooms_n * 0.32, "神殿 %d / %d 层、宝箱 %d / %d 间（V0.1：约 75%% 的层有神殿、每间 20%% 有宝箱）" % [shrine_floors, maps, chests, rooms_n])
	check(DungeonGen.generate(3, 5).spawns == DungeonGen.generate(3, 5).spawns and DungeonGen.generate(3, 5).props == DungeonGen.generate(3, 5).props, "同一种子道具位置不变")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var cnt := {"gold": 0, "pot": 0, "item": 0, "imps": 0, "none": 0}
	for i in 4000:
		var b := FloorRules.roll_barrel(rng, 2)
		cnt[b.keys()[0] if not b.is_empty() else "none"] += 1
	check(absf(cnt.gold / 4000.0 - 0.3) < 0.03 and absf(cnt.pot / 4000.0 - 0.12) < 0.02 and absf(cnt.item / 4000.0 - 0.05) < 0.015 and absf(cnt.imps / 4000.0 - 0.08) < 0.02, "木桶：30%% 金币、12%% 生命药水、5%% 装备、8%% 窜出小鬼（V0.1）%s" % str(cnt))

	# ---- 场景 ----
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.auto_pack_test = false
	main.run_nav_bench = false
	add_child(main)
	await frames(3)
	var hero: Player = main.hero
	var sh: Dictionary = hero.progress.sheet
	var hl: OmniLight3D = hero.get_node("HeroLight")
	check(is_equal_approx(hl.omni_range, 7.0), "照明范围：基础 6 格，身上的光照 7 米")
	sh.eq.helm = {"id": 999001, "base": "cap", "rarity": 1, "ilvl": 5, "name": "明亮的皮帽", "aff": {"light": 2}, "arm": 2, "req": 1}
	hero.stats_changed()
	check(is_equal_approx(hl.omni_range, 9.4) and hero.progress.S.light == 8, "「明亮的」+2 照明：光多照 2.4 米，看见的范围也大 2 格")
	sh.eq.erase("helm")
	hero.stats_changed()
	var fl := 2
	main.go_floor(fl)
	await frames(3)
	var fog: Dictionary = main.floor_info.fog
	var shown := 0
	var total := 0
	for k in fog:
		if k is Vector2i:
			total += 1
			if fog[k].shown:
				shown += 1
	var hc: Vector2i = Vector2i(floori(hero.global_position.x / DungeonBuilder.TILE), floori(hero.global_position.z / DungeonBuilder.TILE)) / DungeonBuilder.CHUNK
	check(shown > 0 and shown < total / 3 and fog[hc].shown, "战争迷雾：只显示主角身边看见过的区块（%d / %d）" % [shown, total])
	var hidden_torch: int = main.torches.filter(func(t): return not t.visible).size()
	check(hidden_torch > 0, "没去过的地方火把也没亮（%d 支还藏着）" % hidden_torch)
	var far_mon: Array = main.monsters.filter(func(e): return is_instance_valid(e) and e.global_position.distance_to(hero.global_position) > 30.0)
	check(not far_mon.is_empty() and far_mon.all(func(e): return not e.visible), "看不见的地方的怪物不显示（%d 只）" % far_mon.size())
	var props_n: int = main.dungeon.props.size()
	var spawned := _spots(main, "barrel").size() + _spots(main, "chest").size() + _spots(main, "shrine").size()
	check(props_n > 0 and spawned == props_n, "本层 %d 件道具都搭出来了" % props_n)

	# 离主角近的怪：看得见、点得中；藏起来就点不中
	for e in main.monsters:
		if is_instance_valid(e):
			e.queue_free()
	await frames(1)
	main.monsters.clear()
	var near := Monsters.spawn("zombie", main.stage, hero.global_position + Vector3(2.0, 0, 0), hero, fl)
	near.stun_t = 30.0
	main.monsters.append(near)
	await seconds(0.25)
	main.camera.snap()
	await physics(2)
	var sp: Vector2 = main.camera.unproject_position(near.global_position + Vector3(0, 1.0, 0))
	check(near.visible and hero.pick_enemy(sp) == near, "身边的怪看得见、点得中")
	near.visible = false
	check(hero.pick_enemy(sp) == null and hero.nearest_enemy() == null, "藏在迷雾里的怪点不中，也不会被自动瞄准")
	near.queue_free()
	main.monsters.clear()

	# 宝箱
	var chest: InteractSpot = null
	for f2 in range(2, 12):
		if f2 != fl:
			main.go_floor(f2)
			await frames(2)
			fl = f2
		if not _spots(main, "chest").is_empty() and not _spots(main, "shrine").is_empty():
			break
	for e in main.monsters:
		if is_instance_valid(e):
			e.queue_free()
	main.monsters.clear()
	chest = _spots(main, "chest")[0]
	hero.global_position = chest.global_position + Vector3(1.6, 0, 1.6)
	main.camera.snap()
	await physics(3)
	var items0 := get_tree().get_nodes_in_group("ground_item").size()
	var csp: Vector2 = main.camera.unproject_position(chest.global_position + Vector3(0, 0.5, 0))
	hero.click_at(csp)
	check(hero.talk_target == chest, "点宝箱：走过去")
	for i in 200:
		await physics(1)
		if chest.used:
			break
	await frames(1)
	var got := get_tree().get_nodes_in_group("ground_item").size() - items0
	check(chest.used and not chest.is_in_group("interact") and got >= 2 and got <= 4, "打开宝箱：金币 + 1–2 件装备（有时加一瓶药水），共 %d 件；开过的不能再点" % got)
	check(main.props_used[fl].has(chest.index), "记下这个宝箱开过了")
	# 神殿
	var shrine: InteractSpot = _spots(main, "shrine")[0]
	hero.hp = 5.0
	var dmg0: Array = hero.progress.S.dmg.duplicate()
	var arm0: int = hero.progress.S.arm
	main._use_spot(shrine)
	var bf := HeroStats.active_buff(sh)
	check(bf in ["might", "guard", "swift", "arcane"] and is_equal_approx(sh.buff.t, 90.0) and hero.hp == hero.max_hp and shrine.used, "神殿：随机一种祝福 90 秒，并回满生命法力（%s）" % bf)
	await frames(2)
	var ok_fx := true
	match bf:
		"might":
			ok_fx = hero.progress.S.dmg[1] > dmg0[1]
		"guard":
			ok_fx = hero.progress.S.arm > arm0
		"swift":
			ok_fx = hero.progress.S.aps > 1.0 and hero.speed > HeroProgress.BASE_MOVE_M
		"arcane":
			ok_fx = hero.progress.S.spell > 1.0
	check(ok_fx and main.lvl_label.text.contains("神殿") and _logs(main).contains("持续 90 秒"), "祝福立即生效，左上角显示剩余秒数")
	sh.buff.t = 0.05
	await seconds(0.25)
	check(sh.buff == null and _logs(main).contains("神殿祝福消失了") and hero.progress.S.dmg == dmg0 and hero.progress.S.arm == arm0, "90 秒后祝福消失，属性恢复")
	# 木桶：强制一次窜出小鬼（找一个会掷出小鬼的种子）
	var barrels := _spots(main, "barrel")
	if barrels.is_empty():
		check(false, "这一层没有木桶")
	else:
		var seed_imps := -1
		for sd in 500:
			var r := RandomNumberGenerator.new()
			r.seed = sd
			if FloorRules.roll_barrel(r, fl).has("imps"):
				seed_imps = sd
				break
		main.loot_rng.seed = seed_imps
		var b0: InteractSpot = barrels[0]
		main._use_spot(b0)
		await seconds(0.3)
		var imps: Array = main.monsters.filter(func(e): return is_instance_valid(e) and e.def.get("v01", "") == "imp")
		check(imps.size() >= 1 and imps.all(func(e): return e.state != "idle") and _logs(main).contains("窜出了火坑小鬼") and not is_instance_valid(b0), "砸木桶：窜出火坑小鬼扑过来（%d 只），木桶碎掉" % imps.size())
		for e in imps:
			e.queue_free()
		main.monsters.clear()
	# 离开再回来：开过的宝箱还开着，砸掉的木桶没了，神殿熄着
	var n_barrels := _spots(main, "barrel").size()
	var chest_i := chest.index
	main.go_floor(fl - 1 if fl > 1 else fl + 1)
	await frames(2)
	main.go_floor(fl)
	await frames(2)
	var chests2: Array = _spots(main, "chest").filter(func(c): return c.index == chest_i)
	check(chests2.size() == 1 and chests2[0].used and _spots(main, "shrine")[0].used and _spots(main, "barrel").size() == n_barrels, "回到这一层：宝箱开着、神殿熄着、砸掉的木桶没有再出现")
	var fog2: Dictionary = main.floor_info.fog
	var shown2 := 0
	for k in fog2:
		if k is Vector2i and fog2[k].shown:
			shown2 += 1
	check(shown2 >= shown, "去过的区块回来还是亮的（%d 块）" % shown2)
	main.queue_free()
	await frames(2)


## P11：存档、音效、无尽深渊
func test_save() -> void:
	# ---- 存档格式（V0.1 saveGame / loadGame） ----
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var sh := HeroStats.new_hero()
	sh.lvl = 7
	sh.gold = 1234
	sh.q = {"q1": 3, "q2": 2, "q3": 0}
	sh.maxFloor = 5
	sh.pots.tp = 4
	sh.buff = {"k": "might", "t": 42.5}
	sh.eq.weapon = ItemGen.generate(rng, 8, {"rarity": 2, "slot": "weapon"})
	for i in 3:
		sh.inv.append(ItemGen.generate(rng, 6, {}))
	var txt := SaveGame.serialize(sh, 55.5, 12.0, false)
	var d := SaveGame.parse(txt)
	check(not d.is_empty() and d.sheet.lvl == 7 and d.sheet.gold == 1234 and d.sheet.q.q2 == 2 and d.sheet.maxFloor == 5 and d.sheet.pots.tp == 4 and d.hp == 55.5 and d.snd == false, "存档往返：等级、金币、任务、最深层、药水、生命、音效开关都读回来了")
	check(d.sheet.inv.size() == 3 and d.sheet.eq.weapon.name == sh.eq.weapon.name and typeof(d.sheet.eq.weapon.req) == TYPE_INT and d.sheet.eq.weapon.dmg == sh.eq.weapon.dmg and d.sheet.inv[0].aff == sh.inv[0].aff, "背包与装备原样读回，整数字段仍是整数")
	check(d.sheet.buff.k == "might" and is_equal_approx(d.sheet.buff.t, 42.5) and HeroStats.calc(d.sheet).dmg == HeroStats.calc(sh).dmg, "神殿祝福与计算后的属性一致")
	check(SaveGame.parse("") == {} and SaveGame.parse("{坏的") == {} and SaveGame.parse(JSON.stringify({"fmt": "ef3d-save", "v": 2, "sheet": {"lvl": 3}})) == {} and SaveGame.parse(JSON.stringify({"fmt": "other", "v": 1, "sheet": {"lvl": 3}})) == {} and SaveGame.parse(JSON.stringify({"fmt": "ef3d-save", "v": 1, "sheet": {"gold": 3}})) == {}, "空的、坏的、版本号或格式不对、缺等级的存档都当作没有存档")
	var bad: Dictionary = JSON.parse_string(txt)
	bad.sheet.lvl = 999
	bad.sheet.gold = -50
	bad.sheet.q.q1 = 9
	bad.sheet.inv.append({"id": 5, "base": "不存在的底材", "name": "?", "rarity": 0})
	bad.sheet.inv.append("乱写的")
	bad.sheet.buff = {"k": "god_mode", "t": 999}
	var d2 := SaveGame.parse(JSON.stringify(bad))
	check(d2.sheet.lvl == int(Act1Data.rules().hero.level_cap) and d2.sheet.gold == 0 and d2.sheet.q.q1 == 3 and d2.sheet.inv.size() == 3 and d2.sheet.buff == null, "读档时校验：等级封顶、负数归零、任务状态截到 0–3、未知物品和未知祝福丢掉")
	var minimal := SaveGame.parse(JSON.stringify({"fmt": "ef3d-save", "v": 1, "sheet": {"lvl": 2}}))
	check(minimal.sheet.str == 15 and minimal.sheet.pots.hp == HeroStats.new_hero().pots.hp and minimal.sheet.q.q1 == 0, "缺的字段用新角色的默认值补上")
	ItemGen._next_id = 1
	SaveGame.bump_item_ids(d.sheet)
	var mx := 0
	for it in d.sheet.inv + d.sheet.eq.values():
		mx = maxi(mx, it.id)
	check(ItemGen._next_id > mx, "读档后新物品的编号接着往下编，不和存档里的撞号")
	var path := "user://test_save_p11.json"
	SaveGame.path_override = path
	SaveGame.erase()
	check(SaveGame.read_raw() == "" and SaveGame.load_saved().is_empty() and SaveGame.write_raw(txt) and SaveGame.load_saved().sheet.lvl == 7, "存取：没有存档时为空；写入后能读回")
	SaveGame.erase()
	check(SaveGame.load_saved().is_empty(), "删除存档")

	# ---- 场景：自动存档、读档、开局选择、菜单 ----
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.auto_pack_test = false
	main.run_nav_bench = false
	main.save_enabled = true
	add_child(main)
	await frames(3)
	var hero: Player = main.hero
	check(not main.dialog_panel.visible and _logs(main).contains("头顶有「!」"), "没有存档时直接开始新游戏")
	var ps: Dictionary = hero.progress.sheet
	hero.gain_xp(400)
	ps.gold = 777
	ps.q.q1 = 1
	ps.inv.append(ItemGen.generate(rng, 4, {"rarity": 1}))
	main.go_floor(2)
	await frames(2)
	var sv := SaveGame.load_saved()
	check(not sv.is_empty() and sv.sheet.maxFloor == 2 and sv.sheet.gold == 777 and sv.sheet.lvl == ps.lvl and sv.sheet.q.q1 == 2, "换层时自动存档（第 2 层、任务进度、金币、等级）")
	main._autosave_t = 0.01
	ps.gold = 800
	await frames(3)
	check(SaveGame.load_saved().sheet.gold == 800, "每 30 秒自动存档")
	var lvl_saved: int = ps.lvl
	var inv_n: int = ps.inv.size()
	Sfx.enabled = false
	main.save_game()
	Sfx.enabled = true
	main.queue_free()
	await frames(2)
	# 重开游戏：出现「继续旅程 / 新的旅程」
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.auto_pack_test = false
	main.run_nav_bench = false
	main.save_enabled = true
	add_child(main)
	await frames(3)
	hero = main.hero
	var dp: DialogPanel = main.dialog_panel
	var bt: Array = dp.opts.get_children().map(func(b): return b.text)
	check(dp.visible and get_tree().paused and bt.size() == 2 and String(bt[0]).begins_with("继续旅程（%d 级 · 最深第 2 层）" % lvl_saved), "有存档时开局先选：%s" % str(bt))
	dp.opts.get_child(0).pressed.emit()
	await frames(2)
	ps = hero.progress.sheet
	check(not dp.visible and ps.lvl == lvl_saved and ps.gold == 800 and ps.inv.size() == inv_n and ps.q.q1 == 2 and main.floor_i == 0 and hero.max_hp == hero.progress.S.maxHp and not Sfx.enabled, "继续旅程：角色、背包、任务、音效设置都恢复，站在烬原镇")
	check(main.npc("elin").mark.text == "?" and _logs(main).contains("欢迎回来"), "读档后头顶标记按任务进度刷新（伊莲「?」）")
	Sfx.enabled = true
	# 菜单：Esc 打开；音效开关；保存
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	main._unhandled_key_input(esc)
	bt = dp.opts.get_children().map(func(b): return b.text)
	check(dp.visible and dp.who.text == "菜单" and bt.has("保存游戏") and bt.has("音效：开（M）") and bt.has("删除存档，重新开始"), "Esc 打开菜单 %s" % str(bt))
	var snd_btn: Button = dp.opts.get_children().filter(func(b): return b.text.begins_with("音效"))[0]
	snd_btn.pressed.emit()
	await frames(1)
	check(not Sfx.enabled and dp.opts.get_children().any(func(b): return b.text == "音效：关（M）"), "菜单里关掉音效")
	dp.opts.get_children().filter(func(b): return b.text == "保存游戏")[0].pressed.emit()
	check(not dp.visible and _logs(main).contains("已保存") and SaveGame.load_saved().snd == false, "菜单里保存游戏（音效设置也存下来）")
	Sfx.enabled = true
	# 新的旅程：要再确认一次，确认后覆盖存档
	main.queue_free()
	await frames(2)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.auto_pack_test = false
	main.run_nav_bench = false
	main.save_enabled = true
	add_child(main)
	await frames(3)
	dp = main.dialog_panel
	dp.opts.get_child(1).pressed.emit()
	bt = dp.opts.get_children().map(func(b): return b.text)
	check(dp.visible and String(dp.body.get_child(0).text).contains("覆盖现有存档") and bt == ["确定，重新开始", "返回"], "新的旅程：先提示会覆盖存档")
	dp.opts.get_child(0).pressed.emit()
	await frames(1)
	check(not dp.visible and main.hero.progress.sheet.lvl == 1 and SaveGame.load_saved().sheet.lvl == 1, "确认后从 1 级重新开始，存档被覆盖")
	main.queue_free()
	await frames(2)
	SaveGame.erase()
	SaveGame.path_override = ""

	# ---- 音效（V0.1 Snd 的配方） ----
	var names := ["swing", "hit", "crit", "fire", "boom", "ice", "whirl", "blink", "gold", "pick", "magic", "rare", "legend", "lvl", "die", "hurt", "potion", "portal", "chest", "barrel", "shrine", "arrow", "bolt", "boss", "click"]
	var okn := 0
	var t0 := Time.get_ticks_usec()
	for n in names:
		var w := Sfx.synth(n)
		if w != null and w.data.size() > 400 and w.get_length() < 1.4:
			okn += 1
	var synth_ms := (Time.get_ticks_usec() - t0) / 1000.0
	check(okn == names.size() and Sfx.synth("不存在") == null, "25 个音效都能合成（全部合成 %.0f 毫秒，第一次播放时才合成）" % synth_ms)
	var w_hit := Sfx.synth("hit")
	var peak := 0
	for i in range(0, w_hit.data.size(), 2):
		peak = maxi(peak, absi(w_hit.data.decode_s16(i)))
	check(peak > 3000 and peak <= 32767, "采样有声音且不削波（峰值 %d）" % peak)
	check(absf(Sfx.synth("portal").get_length() - 0.73) < 0.02 and absf(Sfx.synth("legend").get_length() - 0.8) < 0.02, "时长同 V0.1 配方（传送门 0.7 秒、传奇四音 0.8 秒）")
	# 游戏里的事件会播放对应音效
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.use_test_area = true
	main.auto_pack_test = false
	main.run_nav_bench = false
	add_child(main)
	await frames(3)
	hero = main.hero
	Sfx.counts.clear()
	hero.hp = 10.0
	hero.drink_potion("hp")
	hero.take_hit({"amount": 1, "crit": false, "type": "physical"}, Vector3.ZERO, 0.0)
	hero.mp = hero.max_mp
	hero.cast_skill("fireball", hero.global_position + Vector3(4, 0, 0))
	for i in 90:
		await physics(1)
		if Sfx.counts.get("boom", 0) > 0:
			break
	check(Sfx.counts.get("potion", 0) == 1 and Sfx.counts.get("hurt", 0) == 1 and Sfx.counts.get("fire", 0) == 1 and Sfx.counts.get("boom", 0) == 1, "喝药、受伤、放火球、火球爆炸都有音效 %s" % str(Sfx.counts))
	main.queue_free()
	await frames(2)

	# ---- 无尽深渊（第 7 层起，V0.1 T_VOID / themeFor） ----
	check(FloorRules.theme_for(6) == "inferno" and FloorRules.theme_for(7) == "abyss" and FloorRules.theme_for(40) == "abyss" and FloorRules.floor_name(7) == "无尽深渊 · 第 7 层", "第 7 层起是「无尽深渊」，没有尽头")
	check(FloorRules.is_boss_floor(10) and FloorRules.is_boss_floor(15) and not FloorRules.is_boss_floor(11) and not FloorRules.is_boss_floor(7), "深渊每 5 层一个首领（第 10、15……层）")
	check(FloorRules.monster_pool(12) == FloorRules.monster_pool(7) and FloorRules.monster_pool(7).size() == 7, "深渊怪物池：7 种怪混刷")
	var m7 := FloorRules.scale_monster("knight", 7)
	var m20 := FloorRules.scale_monster("knight", 20)
	check(m20.hp > m7.hp * 3 and m20.dmg[1] > m7.dmg[1] * 2 and m20.lvl == 40, "越往下怪越强（堕落骑士第 7 层 %d 血、第 20 层 %d 血）" % [m7.hp, m20.hp])
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.auto_pack_test = false
	main.run_nav_bench = false
	add_child(main)
	await frames(3)
	main.go_floor(12)
	await frames(2)
	check(main.dungeon.theme == "abyss" and main.monsters.size() > 10 and main.stairs.has("down") and main.stairs.has("up"), "能走到第 12 层：深渊色调、%d 只怪、上下楼梯" % main.monsters.size())
	main.go_floor(15)
	await frames(2)
	check(main.boss != null and String(main.boss.def.name).begins_with("深渊化身") and not main.stairs.has("down"), "第 15 层：深渊化身把守，击败前没有下楼梯")
	main.queue_free()
	await frames(2)


## P12：对齐 V0.1（导入经典版存档、楼层状态保留、Shift 原地攻击、B 键背包、没药提示、操作说明）
const V01_SAVE := """{"v":1,"lvl":9,"xp":120,"str":30,"vit":25,"mag":18,"pts":2,"gold":845,"hp":80,"mp":20,
"pots":{"hp":5,"mp":3,"tp":2},"maxFloor":4,"q":{"q1":3,"q2":1,"q3":0},"kills":210,"deaths":3,"won":false,"buff":null,
"inv":[{"id":41,"b":"axe","r":1,"ilvl":8,"aff":{"str":5},"n":"强壮的战斧","dmg":[5,13],"spd":0.9,"req":5},
{"id":42,"b":"不存在","r":0,"n":"坏数据"}],
"eq":{"weapon":{"id":7,"b":"lsword","r":3,"ilvl":12,"aff":{"dmgp":50,"ls":5,"str":8,"ias":12},"n":"灰烬之誓","dmg":[9,19],"spd":1.05,"req":9},
"body":{"id":8,"b":"leather","r":0,"ilvl":3,"aff":{},"n":"皮甲","arm":7,"req":2}},"savedAt":"2026-09-25T10:00:00.000Z"}"""


func test_parity() -> void:
	# ---- 导入 V0.1 经典版存档 ----
	var d := SaveGame.parse_v01(V01_SAVE)
	check(not d.is_empty() and d.from_v01 and d.sheet.lvl == 9 and d.sheet.gold == 845 and d.sheet.maxFloor == 4 and d.sheet.q.q2 == 1 and d.sheet.kills == 210, "V0.1 存档能读：等级、金币、最深层、任务、击杀数")
	var w: Dictionary = d.sheet.eq.weapon
	check(w.base == "lsword" and w.rarity == 3 and w.name == "灰烬之誓" and w.aff.dmgp == 50 and d.sheet.inv.size() == 1 and d.sheet.inv[0].base == "axe" and d.sheet.inv[0].name == "强壮的战斧", "V0.1 物品字段（b / r / n）换成 3D 版字段；未知底材的丢掉")
	var S := HeroStats.calc(d.sheet)
	check(S.dmg[1] > 19 and S.ls == 5 and S.arm > 7, "导入的装备立即生效（伤害 %s、生命偷取 %d%%、护甲 %d）" % [str(S.dmg), S.ls, S.arm])
	check(Inventory.item_lines(w, 9).size() > 3, "导入的传奇物品能正常显示说明")
	check(SaveGame.parse_v01("") == {} and SaveGame.parse_v01("{x") == {} and SaveGame.parse_v01(JSON.stringify({"v": 2, "lvl": 3})) == {}, "空的、坏的、版本不对的 V0.1 存档不导入")
	# 场景：没有 3D 存档、有 V0.1 存档 → 开局询问是否带过来
	SaveGame.path_override = "user://test_parity_save.json"
	SaveGame.erase()
	SaveGame.v01_override = V01_SAVE
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.auto_pack_test = false
	main.run_nav_bench = false
	main.save_enabled = true
	add_child(main)
	await frames(3)
	var dp: DialogPanel = main.dialog_panel
	var bt: Array = dp.opts.get_children().map(func(b): return b.text)
	check(dp.visible and String(dp.body.get_child(0).text).contains("经典版") and String(bt[0]).begins_with("带上经典版的角色继续（9 级"), "开局发现经典版存档，询问是否带过来 %s" % str(bt))
	dp.opts.get_child(0).pressed.emit()
	await frames(2)
	var hero: Player = main.hero
	check(hero.progress.sheet.lvl == 9 and hero.progress.sheet.eq.weapon.name == "灰烬之誓" and SaveGame.load_saved().sheet.lvl == 9 and _logs(main).contains("已导入经典版"), "导入后角色是 9 级、拿着灰烬之誓，并存成 3D 版存档")
	main.queue_free()
	await frames(2)
	SaveGame.v01_override = ""
	SaveGame.erase()
	SaveGame.path_override = ""

	# ---- 同一局里楼层状态保留（V0.1 maps） ----
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.auto_pack_test = false
	main.run_nav_bench = false
	add_child(main)
	await frames(3)
	hero = main.hero
	main.go_floor(2)
	await frames(2)
	var n0: int = main.monsters.size()
	var victims: Array = main.monsters.slice(0, 3)
	for e in victims:
		e.take_hit({"amount": 99999, "crit": false, "type": "physical"}, Vector3.ZERO, 0.0)
	await frames(2)
	var it := ItemGen.generate(RandomNumberGenerator.new(), 4, {"rarity": 1})
	var gi := GroundItem.make({"item": it})
	main.stage.add_child(gi)
	gi.global_position = hero.global_position + Vector3(1.0, 0, 0)
	var drop_pos: Vector3 = gi.global_position
	main.go_floor(1)
	await frames(2)
	main.go_floor(2)
	await frames(2)
	var back: Array = get_tree().get_nodes_in_group("ground_item").filter(func(g): return g.data.has("item") and g.data.item.name == it.name)
	check(main.monsters.size() == n0 - 3, "回到第 2 层：打死的 3 只怪不再出现（%d → %d）" % [n0, main.monsters.size()])
	check(back.size() == 1 and back[0].global_position.distance_to(drop_pos) < 0.05, "地上的装备还在原处")
	main.reset_session()
	main.go_floor(1)
	await frames(2)
	main.go_floor(2)
	await frames(2)
	check(main.monsters.size() == n0, "读档或重新开始后楼层重新生成（同 V0.1）")
	main.queue_free()
	await frames(2)

	# ---- 操作：Shift 原地攻击、B 键、没药提示、操作说明 ----
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.use_test_area = true
	main.auto_pack_test = false
	main.run_nav_bench = false
	add_child(main)
	await frames(3)
	hero = main.hero
	hero.global_position = Vector3(-3, 0, -2)
	main.camera.snap()
	await physics(3)
	var p0 := hero.global_position
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.shift_pressed = true
	ev.position = main.camera.unproject_position(hero.global_position + Vector3(3, 0, 0))
	hero._unhandled_input(ev)
	var swung := false
	for i in 40:
		await physics(1)
		if hero.action == "oath_cleave":
			swung = true
	check(hero.stand_attack and swung and hero.global_position.distance_to(p0) < 0.2, "Shift + 左键点空地：站着不动朝鼠标方向挥击（V0.1 原地攻击）%s" % str([hero.stand_attack, swung, hero.global_position.distance_to(p0), hero.pick_enemy(ev.position)]))
	var up := ev.duplicate()
	up.pressed = false
	hero._unhandled_input(up)
	await physics(40)
	check(not hero.stand_attack and hero.action == "", "松开后停手")
	check(InputMap.action_get_events("inv_panel").any(func(e): return e is InputEventKey and e.physical_keycode == KEY_B), "B 键也能打开背包（V0.1 同）")
	hero.progress.sheet.pots.hp = 0
	hero.hp = 5.0
	check(hero.drink_potion("hp") == 0 and _logs(main).contains("没有生命药水了"), "没有药水时提示（V0.1 同）")
	main.open_menu()
	var help_btn: Array = main.dialog_panel.opts.get_children().filter(func(b): return b.text == "操作说明")
	help_btn[0].pressed.emit()
	var htxt := " ".join(main.dialog_panel.body.get_children().map(func(l): return l.text))
	check(main.dialog_panel.who.text == "操作说明" and htxt.contains("Shift") and htxt.contains("Tab") and htxt.contains("回城卷轴"), "菜单里有「操作说明」（V0.1 helpHtml）")
	main.dialog_panel.close()
	main.queue_free()
	await frames(2)


## 阶段 2.5：特效（粒子、地面痕迹、溶解）
func test_fx() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.use_test_area = true
	main.auto_pack_test = false
	main.run_nav_bench = false
	add_child(main)
	await frames(3)
	var hero: Player = main.hero
	var st: Node3D = main.stage
	main.apply_quality("medium")
	var p := Fx.burst(st, Vector3(0, 1, 0), Color.ORANGE, 40, {"life": 0.3})
	check(p != null and p.emitting and p.amount == 40 and p.one_shot, "一次性粒子：数量按参数（中画质 40）")
	await seconds(0.8)
	check(not is_instance_valid(p), "播完自己释放")
	main.apply_quality("low")
	var p2 := Fx.burst(st, Vector3.ZERO, Color.ORANGE, 40)
	Fx.reduced = true
	var p3 := Fx.burst(st, Vector3.ZERO, Color.ORANGE, 40)
	Fx.reduced = false
	check(p2.amount == 20 and p3.amount == 7, "低画质粒子减半（20）；「减少动态效果」再减到三分之一（7）")
	main.apply_quality("medium")
	var mk := Fx.mark(st, Vector3(1, 0, 1), Color(0, 0, 0, 0.7), 1.0, 0.1, 0.2)
	check(mk != null and absf(mk.global_position.y - 0.025) < 0.01, "地面痕迹贴在地上")
	await seconds(0.6)
	check(not is_instance_valid(mk), "地面痕迹停留后淡出并释放")
	# 技能特效
	for e in main.monsters:
		if is_instance_valid(e):
			e.stun_t = 60.0
	hero.progress.sheet.lvl = 12
	hero.stats_changed()
	hero.mp = hero.max_mp
	hero.global_position = Vector3(-3, 0, -2)
	var n0 := Fx.spawned
	var marks0: int = main.find_children("*", "MeshInstance3D", true, false).filter(func(n): return n.mesh is PlaneMesh and n.material_override is StandardMaterial3D and (n.material_override as StandardMaterial3D).albedo_texture == Look.radial_texture()).size()
	Sfx.counts.clear()
	hero.cast_skill("fireball", hero.global_position + Vector3(0, 0, -6))
	var trail := false
	for i in 60:
		await physics(1)
		if is_instance_valid(hero.last_fireball) and hero.last_fireball.find_children("*", "CPUParticles3D", false, false).size() > 0:
			trail = true
		if Sfx.counts.get("boom", 0) > 0 and not is_instance_valid(hero.last_fireball):
			break
	var marks := main.find_children("*", "MeshInstance3D", true, false).filter(func(n): return n.mesh is PlaneMesh and n.material_override is StandardMaterial3D and (n.material_override as StandardMaterial3D).albedo_texture == Look.radial_texture())
	var lit: int = main.find_children("*", "OmniLight3D", true, false).filter(func(n): return n.get_parent() == hero.get_parent() and n.omni_range > 3.0 and n.light_energy > 0.0).size()
	check(trail and Fx.spawned >= n0 + 6 and marks.size() == marks0 + 2 and lit >= 1, "火球：一路拖着火星，爆炸时火焰与烟雾粒子、一闪照亮周围，地上留下焦痕与发红的余烬（新特效 %d 个）" % (Fx.spawned - n0))
	for id in ["whirl", "nova", "blink"]:
		await seconds(0.8)
		hero.mp = hero.max_mp
		hero.skill_cd[id] = 0.0
		var k := Fx.spawned
		hero.cast_skill(id, hero.global_position + Vector3(2, 0, 0))
		for i in 40:
			await physics(1)
			if Fx.spawned > k:
				break
		check(Fx.spawned > k, "%s 有粒子特效" % id)
	# 命中火花与溶解
	var dummy_e := Monsters.spawn("zombie", st, hero.global_position + Vector3(1.2, 0, 0), hero, 1)
	await frames(2)
	var k2 := Fx.spawned
	HitFeedback.apply(hero, dummy_e, {"amount": 1, "crit": true, "type": "physical"}, null)
	check(Fx.spawned == k2 + 1, "命中时溅出火花 / 血雾")
	dummy_e.take_hit({"amount": 99999, "crit": false, "type": "physical"}, Vector3.ZERO, 0.0)
	await seconds(1.2)
	var sm: Array = dummy_e.visual.find_children("*", "MeshInstance3D", true, false).map(func(m): return m.material_override)
	var prog: float = sm[0].get_shader_parameter("progress") if sm[0] is ShaderMaterial else -1.0
	check(sm.all(func(m): return m is ShaderMaterial) and prog > 0.0 and prog < 1.0, "怪物倒下后换成溶解材质，正在「烧尽」（进度 %.2f）" % prog)
	check((sm[0] as ShaderMaterial).get_shader_parameter("albedo") != Color(0.5, 0.5, 0.5), "溶解材质保留原来的颜色")
	await seconds(1.4)
	check(not is_instance_valid(dummy_e), "烧尽后释放（倒下后约 2 秒）")
	main.queue_free()
	await frames(2)
