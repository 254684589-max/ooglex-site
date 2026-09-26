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
	for g in ["boot", "camera", "move", "damage", "combat", "pack"]:
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


func physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func test_move() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.auto_pack_test = false
	main.run_nav_bench = false
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


func _count_numbers(root: Node) -> int:
	var n := 0
	for c in root.get_children():
		if c is Label3D:
			n += 1
	return n


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
