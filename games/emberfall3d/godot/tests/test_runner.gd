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
	for g in ["boot", "look", "camera", "move", "damage", "combat", "monsters", "perf", "pack", "port", "dungeon"]:
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
	check(hero.kit.resource == 12.0, "命中获得 12 点誓火（实得 %.0f）" % hero.kit.resource)
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

	# 焚地践踏：誓火不足时放不出来
	hero.kit.resource = 10.0
	check(not hero.cast_skill("scorch_stomp"), "誓火不足 30 时不能放焚地践踏")
	# 把两个木桩都放到身边
	d1.home = Vector3(0.8, 0, 0.6)
	d1.global_position = d1.home
	await physics(2)
	hero.kit.resource = 50.0
	var hp_a := d0.hp
	var hp_b := d1.hp
	check(hero.cast_skill("scorch_stomp"), "誓火足够时放出焚地践踏")
	check(is_equal_approx(hero.kit.resource, 20.0), "消耗 30 点誓火")
	check(not hero.cast_skill("scorch_stomp"), "冷却中不能连放")
	await physics(20)
	check(d0.hp < hp_a and d1.hp < hp_b, "范围内两个木桩都受到伤害")
	check(d0.stun_t > 0.5 and d1.stun_t > 0.5, "被眩晕")
	check(is_equal_approx(hero.kit.resource, 20.0), "践踏只消耗誓火、不产生（GDD 第 5.1 节：基础攻击生成，技能消耗）")
	var zones := main.get_children().filter(func(c): return c is BurnZone)
	check(zones.size() == 1, "留下燃烧地面")
	var hp_after := d0.hp
	await seconds(1.2)
	check(d0.hp < hp_after, "燃烧地面持续造成火焰伤害（%d）" % (hp_after - d0.hp))
	check(hero.kit.cooldowns.get("scorch_stomp", 0.0) > 0.0 and hero.kit.cooldowns.get("scorch_stomp", 0.0) < 4.0, "冷却计时中")
	await seconds(2.5)
	check(main.get_children().filter(func(c): return c is BurnZone).is_empty(), "燃烧地面 3 秒后消失")

	# 誓火脱战衰减
	var before := hero.kit.resource
	await seconds(3.6)
	check(hero.kit.resource < before, "脱战 3 秒后誓火开始衰减（%.0f → %.0f）" % [before, hero.kit.resource])

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
	check(defs.size() == 4 and defs.has("ash_brute") and defs.has("bone_archer") and defs.has("ash_priest") and defs.has("ash_corpse"), "怪物数据：冲锋、远程、召唤、仆从 4 种")

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
	check(hero.hp <= hp0 - 10, "站在冲锋路线上被撞（-%d）" % (hp0 - hero.hp))
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
	check(hero.hp == hp0, "闪开后冲锋落空")
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
	check(not hero.cast_skill("scorch_stomp"), "倒下后不能放技能")
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
	check(main.dummies.is_empty() and main.monsters.is_empty() and main.stage.find_children("*", "TrainingDummy", true, false).is_empty(), "测试区的木桩和怪物随楼层一起清掉")
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
	check(main.dungeon.boss_room >= 0 and main.floor_info.down_cell == main.dungeon.boss_stairs and main.stairs.has("down"),
		"第 3 层（首领层）：首领房中间有下楼梯（首领在 P9 接入之前先开着）")
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
