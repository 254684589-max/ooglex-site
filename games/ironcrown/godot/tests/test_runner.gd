extends Node
## 自动化测试：无界面运行（结构沿用 games/emberfall3d/godot/tests/test_runner.gd）。
##   godot --headless --path games/ironcrown/godot res://tests/test_runner.tscn -- [测试组 ...]
## 全部通过时退出码为 0，否则为 1。

var failures: Array = []
var checks := 0
var only: Array = []
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
	get_tree().root.size = Vector2i(1280, 720)   # 无头模式默认窗口只有 64×64，界面与触屏测试按电脑窗口算
	await frames(2)
	only = Array(OS.get_cmdline_user_args())
	for g in ["boot", "ui", "move", "terrain", "look", "touch", "pause"]:
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


func physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func make_main(test_range := true) -> Node3D:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.use_test_range = test_range
	add_child(main)
	await frames(3)
	return main


func free_main(main: Node3D) -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right", "sprint", "jump", "crouch"]:
		Input.action_release(a)
	get_tree().paused = false
	main.queue_free()
	await frames(2)


## 把玩家放到 (x, z)，面朝 -Z，站稳
func place(p: FpController, x: float, z: float) -> void:
	p.global_position = Vector3(x, 0.05, z)
	p.rotation = Vector3.ZERO
	p.velocity = Vector3.ZERO
	p.touch_move = Vector2.ZERO
	await physics(10)


## 按住一个动作 sec 秒（物理帧 60 次每秒）
func hold(action: String, sec: float) -> void:
	Input.action_press(action)
	await physics(roundi(sec * 60.0))
	Input.action_release(action)


func flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


func test_boot() -> void:
	check(ProjectSettings.get_setting("rendering/renderer/rendering_method") == "gl_compatibility", "工程使用兼容渲染器（网页导出唯一支持的渲染器）")
	check(ProjectSettings.get_setting("rendering/renderer/rendering_method.mobile") == "gl_compatibility", "移动端同样使用兼容渲染器")
	var main := await make_main(false)
	await physics(20)
	var p: FpController = main.player
	check(main.camera != null and main.camera.current and main.camera == p.camera, "第一人称相机挂在玩家头部并设为当前相机")
	check(p.is_on_floor() and absf(p.global_position.y) < 0.05, "街道场景：玩家站在地面上（地面有碰撞，y = %.3f）" % p.global_position.y)
	check(absf(main.camera.global_position.y - p.EYE_STAND) < 0.06, "相机在视高 1.65 米（GDD.md 第四节，实测 %.2f）" % main.camera.global_position.y)
	check(is_equal_approx(main.camera.fov, 75.0), "视野角默认 75°")
	check(main.env.fog_enabled and main.env.background_color == main.FOG_COLOR, "开启深度雾，背景与雾同为夜雾蓝（ART.md 第四节）")
	check(main.env.tonemap_mode == Environment.TONE_MAPPER_ACES, "色调映射为 ACES")
	var lamps := main.find_children("*", "OmniLight3D", true, false)
	check(lamps.size() >= 1 and lamps.size() <= 4, "实时点光源 1–4 盏（TECH.md 4.6 预算，实际 %d）" % lamps.size())
	# 街道的房子挡路：站在第一排房子旁边往左（-X）一直走，会被左侧房子挡住（房子外墙在 x = -6.5）
	await place(p, 0.0, -6.0)
	await hold("move_left", 3.0)
	check(p.global_position.x > -6.3, "街道两侧的灰盒房子有碰撞，走不进墙里（x = %.2f）" % p.global_position.x)
	await free_main(main)


func test_ui() -> void:
	var main := await make_main(true)
	check(main.hud.title_label.text.contains("占位"), "画面明确标注「占位几何体」（AGENTS.md：占位必须写明）")
	# 内置字体是子集：界面与场景标签上出现的每个字都必须在字体里，否则网页上会显示方块
	var font := load("res://assets/fonts/NotoSansSC-IC.ttf") as FontFile
	var texts: Array = [main.HINT_DESKTOP, main.HINT_TOUCH, "跳蹲站"]
	for n in main.find_children("*", "", true, false):
		if n is Label or n is Label3D or n is Button:
			texts.append(n.text)
	var missing := ""
	for text: String in texts:
		for i in text.length():
			var c: int = text.unicode_at(i)
			if c > 32 and not font.has_char(c) and not missing.contains(text[i]):
				missing += text[i]
	check(font != null and missing == "", "界面与场景标签的文字全部在内置字体子集里（%d 段，缺：%s）" % [texts.size(), missing])
	check(ProjectSettings.get_setting("gui/theme/custom_font") == "res://assets/fonts/NotoSansSC-IC.ttf", "工程默认字体是内置中文字体")
	check(is_equal_approx(UiScale.scale_for(Vector2(1280, 720)), 1.0), "界面缩放：1280×720 → 1.0")
	check(is_equal_approx(UiScale.scale_for(Vector2(360, 740)), 0.75), "界面缩放：手机竖屏 360×740 → 0.75（下限）")
	check(is_equal_approx(UiScale.scale_for(Vector2(1920, 1080)), 1.5), "界面缩放：1920×1080 → 1.5")
	check(main.hud.hint_label.text == main.HINT_DESKTOP, "电脑上显示键鼠操作提示")
	await free_main(main)


func test_move() -> void:
	var main := await make_main(true)
	var p: FpController = main.player
	await place(p, 0.0, 10.0)
	var a := flat(p.global_position)
	await hold("move_forward", 1.0)
	var d := flat(p.global_position).distance_to(a)
	check(d > 2.6 and d < 3.2 and p.global_position.z < 10.0, "步行 1 秒约 3 米，朝面对的方向（实测 %.2f 米）" % d)
	await place(p, 0.0, 10.0)
	Input.action_press("sprint")
	await hold("move_forward", 1.0)
	Input.action_release("sprint")
	d = flat(p.global_position).distance_to(Vector2(0, 10))
	check(d > 5.0 and d < 5.8, "按住 Shift 跑 1 秒约 5.5 米（实测 %.2f 米）" % d)
	await place(p, 0.0, 10.0)
	await hold("move_right", 0.5)
	check(p.global_position.x > 1.0 and absf(p.global_position.z - 10.0) < 0.1, "D 键向右平移（x = %.2f）" % p.global_position.x)
	# 转身 90° 后按 W：朝新的方向走
	await place(p, 0.0, 10.0)
	p.look(Vector2(90.0 / (Settings.MOUSE_DEG_PER_PX * Settings.sensitivity), 0))
	await hold("move_forward", 0.5)
	check(p.global_position.x > 1.0, "向右转 90° 后按 W 朝 +X 走（x = %.2f）" % p.global_position.x)
	# 蹲下
	await place(p, 0.0, 10.0)
	p.toggle_crouch()
	await hold("move_forward", 1.0)
	d = flat(p.global_position).distance_to(Vector2(0, 10))
	check(p.crouching and d > 1.3 and d < 1.7, "蹲下走 1 秒约 1.6 米（实测 %.2f 米）" % d)
	check(absf(p.head.position.y - p.EYE_CROUCH) < 0.05 and is_equal_approx(p.capsule.height, p.HEIGHT_CROUCH), "蹲下后视高 1.0 米、碰撞体变矮")
	p.toggle_crouch()
	await physics(30)
	check(not p.crouching and absf(p.head.position.y - p.EYE_STAND) < 0.05, "再按一次站起来")
	# 跳
	await place(p, 0.0, 10.0)
	p.request_jump()
	var top := 0.0
	for i in 72:
		await physics(1)
		top = maxf(top, p.global_position.y)
	check(top > 0.7 and top < 1.1, "跳起约 0.9 米（实测 %.2f 米）" % top)
	check(p.is_on_floor() and p.global_position.y < 0.05, "落回地面")
	p.toggle_crouch()
	await physics(5)
	p.request_jump()
	await physics(10)
	check(p.global_position.y < 0.05, "蹲着不能跳")
	p.toggle_crouch()
	await physics(5)
	# 墙挡路：窄门左侧的墙
	await place(p, TestRange.DOOR_X - 2.0, TestRange.DOOR_Z + 2.0)
	await hold("move_forward", 2.0)
	check(p.global_position.z > TestRange.DOOR_Z + 0.4, "墙挡住玩家，不会穿墙（z = %.2f）" % p.global_position.z)
	await free_main(main)


func test_terrain() -> void:
	var main := await make_main(true)
	var p: FpController = main.player
	await place(p, TestRange.STAIRS_X, TestRange.START_Z + 2.0)
	await hold("move_forward", 1.5)      # 平台只有 3 米深，走太久会从后边掉下去
	var top := TestRange.STEP_RISE * TestRange.STEPS
	check(absf(p.global_position.y - top) < 0.06 and p.global_position.z < TestRange.START_Z - 2.0, "走上 4 级 0.2 米台阶（y = %.2f，平台 %.2f）" % [p.global_position.y, top])
	await hold("move_back", 3.0)
	check(p.global_position.y < 0.05 and p.is_on_floor(), "倒退走下台阶回到地面（y = %.2f）" % p.global_position.y)
	await place(p, TestRange.RAMP_X, TestRange.START_Z + 2.0)
	await hold("move_forward", 3.5)
	check(p.global_position.y > 1.5, "走上 20° 斜坡（y = %.2f）" % p.global_position.y)
	await place(p, TestRange.STEEP_X, TestRange.START_Z + 2.0)
	await hold("move_forward", 3.0)
	check(p.global_position.y < 0.6, "55° 陡坡走不上去（y = %.2f）" % p.global_position.y)
	await place(p, TestRange.DOOR_X, TestRange.DOOR_Z + 1.5)
	await hold("move_forward", 2.0)
	check(p.global_position.z < TestRange.DOOR_Z - 1.0, "穿过 0.9 米宽的窄门（z = %.2f）" % p.global_position.z)
	await place(p, TestRange.TUNNEL_X, TestRange.START_Z + 2.0)
	await hold("move_forward", 2.0)
	check(p.global_position.z > TestRange.START_Z + 0.1, "站着进不了 1.4 米高的矮洞（z = %.2f）" % p.global_position.z)
	p.toggle_crouch()
	await hold("move_forward", 2.0)
	check(p.global_position.z < TestRange.START_Z - 1.0, "蹲下能进矮洞（z = %.2f）" % p.global_position.z)
	p.toggle_crouch()      # 想站起来，但头顶是天花板
	await physics(10)
	check(p.crouching and not p.can_stand(), "矮洞里按「站起」不会顶进天花板，保持蹲着")
	await hold("move_forward", 3.0)
	check(p.global_position.z < TestRange.START_Z - TestRange.TUNNEL_LEN and not p.crouching, "走出矮洞后自动站起（z = %.2f）" % p.global_position.z)
	await free_main(main)


func test_look() -> void:
	var main := await make_main(true)
	var p: FpController = main.player
	await place(p, 0.0, 10.0)
	p.look(Vector2(100, 0))
	check(absf(p.yaw_deg() + 12.0) < 0.01, "鼠标右移 100 像素向右转 12°（灵敏度 1.0，实测 %.2f°）" % p.yaw_deg())
	p.look(Vector2(0, 5000))
	check(is_equal_approx(p.pitch, -p.PITCH_LIMIT), "低头限制在 -85°")
	p.look(Vector2(0, -10000))
	check(is_equal_approx(p.pitch, p.PITCH_LIMIT), "抬头限制在 85°")
	p.look(Vector2(0, 100000))
	Settings.set_value("invert_y", true)
	p.look(Vector2(0, 10))
	check(p.pitch > -p.PITCH_LIMIT, "反转 Y 轴后鼠标下移变成抬头")
	Settings.set_value("invert_y", false)
	Settings.set_value("sensitivity", 2.0)
	var y0 := p.yaw_deg()
	p.look(Vector2(10, 0))
	check(absf(p.yaw_deg() - y0 + 2.4) < 0.01, "灵敏度 2 倍时转得快一倍")
	Settings.set_value("sensitivity", 1.0)
	Settings.set_value("fov", 90)
	check(is_equal_approx(p.camera.fov, 90.0), "改视野角设置后相机立即生效")
	Settings.set_value("fov", 200)
	check(is_equal_approx(Settings.fov, Settings.FOV_MAX), "视野角限制在 60–100°")
	Settings.set_value("fov", 75)
	# 镜头摆动：开着时走路相机会动，关掉后完全不动
	await place(p, 0.0, 10.0)
	Settings.set_value("head_bob", true)
	Input.action_press("move_forward")
	var moved := 0.0
	for i in 40:
		await physics(1)
		moved = maxf(moved, p.camera.position.length())
	Settings.set_value("head_bob", false)
	var still := 0.0
	for i in 40:
		await physics(1)
		still = maxf(still, p.camera.position.length())
	Input.action_release("move_forward")
	check(moved > 0.01, "镜头摆动开着：走路时相机轻微起伏（最大 %.3f 米）" % moved)
	check(still == 0.0, "镜头摆动关掉：走路时相机完全不动（GDD.md 第十二节）")
	Settings.set_value("head_bob", true)
	await free_main(main)


func touch_ev(idx: int, pos: Vector2, pressed: bool) -> InputEventScreenTouch:
	var e := InputEventScreenTouch.new()
	e.index = idx
	e.position = pos
	e.pressed = pressed
	return e


func drag_ev(idx: int, pos: Vector2, rel: Vector2) -> InputEventScreenDrag:
	var e := InputEventScreenDrag.new()
	e.index = idx
	e.position = pos
	e.relative = rel
	return e


func test_touch() -> void:
	var main := await make_main(true)
	var p: FpController = main.player
	var t: TouchControls = main.touch
	t.visible = true
	var sz := t.size
	check(sz == Vector2(1280, 720) and main.hud.size == sz, "触屏层与平视显示铺满整个画面（%s）" % sz)
	await place(p, 0.0, 10.0)
	var lp := Vector2(sz.x * 0.2, sz.y * 0.7)
	t._input(touch_ev(0, lp, true))
	t._input(drag_ev(0, lp + Vector2(0, -30), Vector2(0, -30)))
	check(p.touch_move.distance_to(Vector2(0, -0.5)) < 0.01, "左半屏按下出现摇杆，向上拖一半 = 向前慢走")
	await physics(60)
	var d := flat(p.global_position).distance_to(Vector2(0, 10))
	check(d > 1.2 and d < 1.8 and p.global_position.z < 10.0, "摇杆推一半：按比例慢走（1 秒 %.2f 米）" % d)
	t._input(drag_ev(0, lp + Vector2(0, -200), Vector2(0, -170)))
	check(p.touch_move.length() >= p.TOUCH_RUN_THRESHOLD, "摇杆推到边缘（超出半径也按边缘算）")
	await place(p, 0.0, 10.0)
	p.touch_move = Vector2(0, -1)
	await physics(60)
	d = flat(p.global_position).distance_to(Vector2(0, 10))
	check(d > 5.0, "摇杆推到底 = 跑（1 秒 %.2f 米）" % d)
	t._input(touch_ev(0, lp, false))
	check(p.touch_move == Vector2.ZERO, "松手后停下")
	var y0 := p.yaw_deg()
	var rp := Vector2(sz.x * 0.6, sz.y * 0.4)
	t._input(touch_ev(1, rp, true))
	t._input(drag_ev(1, rp + Vector2(40, 0), Vector2(40, 0)))
	t._input(touch_ev(1, rp + Vector2(40, 0), false))
	check(absf(p.yaw_deg() - y0 + 10.0) < 0.01, "右半屏拖动 40 像素向右转 10°（实测 %.2f°）" % (p.yaw_deg() - y0))
	check(p.touch_move == Vector2.ZERO, "右半屏的触点不会让人走动")
	# 两根手指同时：左手走、右手转
	await place(p, 0.0, 10.0)
	t._input(touch_ev(0, lp, true))
	t._input(touch_ev(1, rp, true))
	t._input(drag_ev(0, lp + Vector2(0, -60), Vector2(0, -60)))
	t._input(drag_ev(1, rp + Vector2(-20, 0), Vector2(-20, 0)))
	check(p.touch_move.y < -0.9 and p.yaw_deg() > 4.0, "两根手指同时：一边走一边转视角")
	t._input(touch_ev(0, lp, false))
	t._input(touch_ev(1, rp, false))
	var bc: Dictionary = t.button_centers()
	await place(p, 0.0, 10.0)
	t._input(touch_ev(2, bc.jump, true))
	t._input(touch_ev(2, bc.jump, false))
	await physics(15)
	check(p.global_position.y > 0.3 and p.touch_move == Vector2.ZERO, "点「跳」按钮起跳，不会误触摇杆")
	await physics(60)
	t._input(touch_ev(3, bc.crouch, true))
	t._input(touch_ev(3, bc.crouch, false))
	await physics(5)
	check(p.crouching, "点「蹲」按钮蹲下")
	t._input(touch_ev(3, bc.crouch, true))
	t._input(touch_ev(3, bc.crouch, false))
	await physics(5)
	check(not p.crouching, "再点一次站起来")
	t._input(touch_ev(4, Vector2(sz.x * 0.2, 20), true))
	check(t.move_index == -1, "顶部一条留给菜单按钮，按下不会出现摇杆")
	t.release_all()
	await free_main(main)


func test_pause() -> void:
	var main := await make_main(true)
	var ev := InputEventAction.new()
	ev.action = "pause"
	ev.pressed = true
	Input.parse_input_event(ev)
	await frames(3)
	check(get_tree().paused and main.pause_menu.visible, "按 Esc 打开暂停菜单，游戏暂停")
	var pz: Vector3 = main.player.global_position
	Input.action_press("move_forward")
	await frames(20)
	Input.action_release("move_forward")
	check(main.player.global_position.is_equal_approx(pz), "暂停时玩家不会移动")
	main.pause_menu.fov_slider.value = 90
	check(is_equal_approx(main.camera.fov, 90.0), "暂停菜单里拖动「视野角」立即生效")
	main.pause_menu.fov_slider.value = 75
	main.pause_menu.bob_check.button_pressed = false
	check(not Settings.head_bob, "暂停菜单里可以关掉镜头摆动")
	main.pause_menu.bob_check.button_pressed = true
	main.pause_menu.resume_btn.pressed.emit()
	await frames(2)
	check(not get_tree().paused and not main.pause_menu.visible, "点「继续游戏」回到游戏")
	# 浏览器用 Esc 释放了指针锁定（游戏收不到 Esc）：锁定过、现在没锁定 → 打开暂停菜单
	main.lock_seen = true
	await frames(2)
	check(get_tree().paused and main.pause_menu.visible, "指针锁定被浏览器释放时自动打开暂停菜单")
	main.close_pause()
	await frames(2)
	check(not main.lock_seen and not get_tree().paused, "从未锁定成功时不会误开暂停菜单")
	main.hud.menu_pressed.emit()
	await frames(2)
	check(get_tree().paused, "右上角「菜单」按钮打开暂停菜单（手机用）")
	main.close_pause()
	await frames(2)
	main.open_pause()
	Input.parse_input_event(ev)
	await frames(3)
	check(not get_tree().paused and not main.pause_menu.visible, "暂停菜单里再按 Esc 继续游戏")
	await free_main(main)
