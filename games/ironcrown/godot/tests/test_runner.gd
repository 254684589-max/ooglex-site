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
	for g in ["boot", "ui", "move", "terrain", "look", "touch", "pause", "interact", "frostford", "perf"]:
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
	check(p.is_on_floor() and absf(p.global_position.y) < 0.05, "霜渡镇：玩家站在地面上（地面有碰撞，y = %.3f）" % p.global_position.y)
	check(absf(main.camera.global_position.y - p.EYE_STAND) < 0.06, "相机在视高 1.65 米（GDD.md 第四节，实测 %.2f）" % main.camera.global_position.y)
	check(is_equal_approx(main.camera.fov, 75.0), "视野角默认 75°")
	check(main.env.fog_enabled and main.env.fog_mode == Environment.FOG_MODE_DEPTH and main.env.background_color == main.FOG_COLOR, "开启深度雾，背景与雾同为夜雾蓝（ART.md 第四节）")
	check(main.env.tonemap_mode == Environment.TONE_MAPPER_ACES, "色调映射为 ACES")
	var lamps := main.find_children("*", "OmniLight3D", true, false)
	check(lamps.size() >= 1 and lamps.size() <= 4, "实时点光源 1–4 盏（TECH.md 4.6 预算，实际 %d）" % lamps.size())
	# 房子挡路：站在酒馆前往左（-X）一直走，会被房子挡住（正面石基在 x = -4.42）
	await place(p, 0.0, -6.0)
	await hold("move_left", 3.0)
	check(p.global_position.x > -4.3, "街道两侧的房子有碰撞，走不进墙里（x = %.2f）" % p.global_position.x)
	await free_main(main)


func test_ui() -> void:
	var main := await make_main(true)
	check(main.hud.title_label.text.contains("占位"), "画面明确标注「占位几何体」（AGENTS.md：占位必须写明）")
	# 内置字体是子集：界面与场景标签上出现的每个字都必须在字体里，否则网页上会显示方块
	var font := load("res://assets/fonts/NotoSansSC-IC.ttf") as FontFile
	var texts: Array = [main.HINT_DESKTOP, main.HINT_TOUCH, "跳蹲站交谈打开关上拾取[E]",
		"性能低中高画质分辨率帧率最慢一帧毫秒绘制调用图元万物体显卡基准测试进行中不要操作结果电脑触屏设备机位平均测完了请截图发给开发者按可换菜单里后刷新页面再"]
	texts.append_array(Frostford.VIEW_NAMES)
	texts.append_array(TestRange.NPC_LINES)
	texts.append_array(Frostford.WATCH_LINES)
	# 测试场和霜渡镇两个场景都要查（1.5 发现：只查测试场，漏掉了霜渡镇领主宅邸大门上「宅邸」的「邸」）
	var town := await make_main(false)
	var nodes: Array = main.find_children("*", "", true, false) + town.find_children("*", "", true, false)
	for n in nodes:
		if n is Interactable:
			texts.append(n.prompt())
			if n is Door:
				texts.append(n.locked_text)
	for n in nodes:
		if n is Label or n is Label3D or n is Button:
			texts.append(n.text)
	town.queue_free()
	await frames(2)
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


## 让玩家站在 pos、看向 look_at 点（水平转身 + 俯仰），然后刷新交互目标
func aim(p: FpController, pos: Vector3, look_at: Vector3) -> void:
	p.global_position = pos
	p.velocity = Vector3.ZERO
	await physics(4)
	var eye := p.camera.global_position
	var d := look_at - eye
	p.rotation.y = atan2(-d.x, -d.z)
	p.pitch = rad_to_deg(atan2(d.y, Vector2(d.x, d.z).length()))
	p.head.rotation.x = deg_to_rad(p.pitch)
	await physics(2)
	p.interactor.refresh()


func test_interact() -> void:
	var main := await make_main(true)
	var p: FpController = main.player
	var it: Interactor = p.interactor
	await physics(5)
	# 出生点正前方的灰盒 NPC
	check(it.target is Npc and main.hud.prompt_label.text == "[E] 交谈 · 灰盒路人", "出生点对准灰盒 NPC，准星下方提示「[E] 交谈 · 灰盒路人」（实际：%s）" % main.hud.prompt_label.text)
	var ev := InputEventAction.new()
	ev.action = "interact"
	ev.pressed = true
	Input.parse_input_event(ev)
	await frames(3)
	check(main.hud.subtitle_panel.visible and main.hud.subtitle_label.text == "灰盒路人：" + TestRange.NPC_LINES[0], "按 E 和 NPC 说话，底部字幕显示第一句")
	await frames(2)
	var sp: PanelContainer = main.hud.subtitle_panel
	check(main.hud.subtitle_label.size.x > 300.0 and sp.size.y < 140.0 and sp.position.y + sp.size.y <= main.hud.size.y, "字幕框按宽度排版、不超出屏幕（%s @ %s）" % [sp.size, sp.position])
	it.use()
	check(main.hud.subtitle_label.text.ends_with(TestRange.NPC_LINES[1]), "再按一次说下一句")
	# 离远了就没有目标
	await aim(p, Vector3(0, 0, 4.8), TestRange.NPC_POS + Vector3(0, 1.2, 0))
	check(it.target == null and main.hud.prompt_label.text == "", "超过 2.5 米对不上，提示消失")
	# 桌上的面包
	var bread_pos: Vector3 = TestRange.TABLE_POS + Vector3(-0.35, TestRange.TABLE_H + 0.06, 0)
	await aim(p, TestRange.TABLE_POS + Vector3(-0.35, 0, 1.3), bread_pos)
	check(it.target is Pickup and it.target.display_name == "面包", "低头看桌上的面包，目标是面包（提示：%s）" % main.hud.prompt_label.text)
	# 中间放一块板挡住视线：隔着东西不能交互
	var shield := Blocks.box(main.world, Vector3(1.2, 1.2, 0.05), TestRange.TABLE_POS + Vector3(-0.35, 1.2, 0.8), Blocks.mat(Color.GRAY))
	await physics(2)
	it.refresh()
	check(it.target == null, "隔着挡板看不到面包，不能交互")
	shield.queue_free()
	await physics(2)
	it.refresh()
	var r := it.use()
	await frames(2)
	check(r.get("kind") == "pickup" and main.inventory.has("bread"), "拾取面包：放进背包（%s）" % str(main.inventory))
	check(main.hud.toast_label.text == "拾取：面包", "屏幕上方提示「拾取：面包」")
	await physics(2)
	it.refresh()
	check(not (it.target is Pickup and it.target.display_name == "面包"), "面包从场景里消失")
	# 能开的木门：门在 z = 12，玩家在 -Z 一侧（z = 10.5）看向 +Z
	var door_mid := Vector3(TestRange.DOOR_GAP_X, 1.2, TestRange.DOOR_WALL_Z)
	await aim(p, Vector3(TestRange.DOOR_GAP_X, 0, TestRange.DOOR_WALL_Z - 1.5), door_mid)
	check(it.target is Door and main.hud.prompt_label.text == "[E] 打开 · 木门", "对准木门，提示「打开 · 木门」")
	var door: Door = it.target
	p.rotation.y = PI      # 面朝 +Z 走过去之前先确认门挡路
	Input.action_press("move_forward")
	await physics(60)
	Input.action_release("move_forward")
	check(p.global_position.z < TestRange.DOOR_WALL_Z - 0.3, "门关着时走不过去（z = %.2f）" % p.global_position.z)
	await aim(p, Vector3(TestRange.DOOR_GAP_X, 0, TestRange.DOOR_WALL_Z - 1.5), door_mid)
	it.use()
	await seconds(0.6)
	# 门板沿本地 +X；绕 Y 轴 -90° 后门板指向 +Z，也就是远离站在 -Z 一侧的玩家
	check(door.is_open and absf(rad_to_deg(door.rotation.y) + 90.0) < 1.0, "按 E 开门：门朝远离玩家的一侧（+Z）转开（%.1f°）" % rad_to_deg(door.rotation.y))
	check(main.hud.prompt_label.text.contains("关上") or it.target != door, "门开着时提示变成「关上」")
	p.rotation.y = PI
	p.head.rotation.x = 0.0
	p.pitch = 0.0
	Input.action_press("move_forward")
	await physics(90)
	Input.action_release("move_forward")
	check(p.global_position.z > TestRange.DOOR_WALL_Z + 0.5, "门开着能走过去（z = %.2f）" % p.global_position.z)
	# 走过去以后，对着转开的门板（x = -0.5、z 12–13）按 E 关上
	await aim(p, Vector3(TestRange.DOOR_GAP_X + 0.6, 0, TestRange.DOOR_WALL_Z + 1.8), Vector3(TestRange.DOOR_GAP_X - 0.5, 1.2, TestRange.DOOR_WALL_Z + 0.6))
	check(it.target == door and main.hud.prompt_label.text == "[E] 关上 · 木门", "对着开着的门，提示「关上 · 木门」（%s）" % main.hud.prompt_label.text)
	it.use()
	await seconds(0.6)
	check(not door.is_open and absf(door.rotation.y) < 0.02, "按 E 把门关上")
	await aim(p, Vector3(TestRange.DOOR_GAP_X, 0, TestRange.DOOR_WALL_Z + 1.5), door_mid)
	it.use()
	await seconds(0.6)
	check(door.is_open and absf(rad_to_deg(door.rotation.y) - 90.0) < 1.0, "从另一侧（+Z）开门：朝 -Z 转开（%.1f°），不会拍到人" % rad_to_deg(door.rotation.y))
	# 锁着的门
	var lock_mid := Vector3(TestRange.LOCKED_GAP_X, 1.2, TestRange.DOOR_WALL_Z)
	await aim(p, Vector3(TestRange.LOCKED_GAP_X, 0, TestRange.DOOR_WALL_Z - 1.5), lock_mid)
	check(it.target is Door and it.target.locked, "对准锁着的门")
	var locked: Door = it.target
	it.use()
	await seconds(0.5)
	check(not locked.is_open and main.hud.toast_label.text == "门锁着。", "锁着的门打不开，提示「门锁着。」")
	# 触屏交互按钮：只在有目标时出现，点它等于按 E
	var t: TouchControls = main.touch
	t.visible = true
	await aim(p, Vector3(0, 0, 4.2), TestRange.NPC_POS + Vector3(0, 1.3, 0))
	check(t.button_centers().has("interact"), "对准东西时，触屏右下角出现交互按钮")
	var before: int = (it.target as Npc).line_index if it.target is Npc else -1
	var bc: Vector2 = t.button_centers().interact
	t._input(touch_ev(5, bc, true))
	t._input(touch_ev(5, bc, false))
	check(it.target is Npc and (it.target as Npc).line_index == before + 1, "点交互按钮和 NPC 说话")
	check(p.touch_move == Vector2.ZERO, "点交互按钮不会误触摇杆")
	await aim(p, Vector3(10, 0, 8), Vector3(10, 1.5, 0))
	check(not t.button_centers().has("interact"), "没对准东西时交互按钮隐藏")
	await free_main(main)
	# 街道：更夫与锁着的民居门
	main = await make_main(false)
	p = main.player
	await aim(p, Frostford.WATCH_POS + Vector3(0, 0, 1.8), Frostford.WATCH_POS + Vector3(0, 1.4, 0))
	check(p.interactor.target is Npc and p.interactor.target.display_name == "更夫", "街道上能和更夫说话")
	await free_main(main)


func test_frostford() -> void:
	var main := await make_main(false)
	var p: FpController = main.player
	await physics(5)
	var houses := get_tree().get_nodes_in_group("house")
	check(houses.size() == 12, "霜渡镇主街有 12 栋房子（两侧 11 栋 + 领主宅邸，实际 %d）" % houses.size())
	var photo_ok := true
	for k in Look.PHOTO:
		photo_ok = photo_ok and bool(Look.mat(k).get_meta("photo", false)) and Look.mat(k).albedo_texture != null
	check(photo_ok, "7 套 Poly Haven 写实贴图全部加载（石板路、石墙、灰泥、木板、石板瓦、雪、树皮）")
	var hm: ArrayMesh = (houses[0].get_node("Mesh") as MeshInstance3D).mesh
	var arr := hm.surface_get_arrays(0)
	check(not Look.mat("stone").uv1_triplanar and Look.mat("stone").normal_texture != null and arr[Mesh.ARRAY_TEX_UV] != null and arr[Mesh.ARRAY_TANGENT] != null, "贴图用网格自带的按米 UV 与切线（不用三向投影，省采样），带法线贴图")
	var max_surf := 0
	var lit := 0
	var dark := 0
	for h in houses:
		var mi: MeshInstance3D = h.get_node("Mesh")
		max_surf = maxi(max_surf, mi.mesh.get_surface_count())
		lit += int(h.get_meta("windows").lit)
		dark += int(h.get_meta("windows").dark)
	check(max_surf <= 8, "每栋房子按材质合并成一个网格，最多 %d 个表面（每个表面一次绘制调用，预算 ≤ 8）" % max_surf)
	check(lit >= 15 and dark >= 10, "窗户有亮有暗（亮 %d 扇、暗 %d 扇）" % [lit, dark])
	var lamps := get_tree().get_nodes_in_group("street_lamp")
	var omni := main.find_children("*", "OmniLight3D", true, false)
	check(lamps.size() == 4 and omni.size() <= 4, "4 盏街灯，整条街实时点光源不超过 4 盏（%d）" % omni.size())
	var signs := main.find_children("*", "Label3D", true, false).filter(func(l): return l.text == "倒钩鱼")
	check(signs.size() == 2, "「倒钩鱼」酒馆招牌两面都有字")
	var doors := main.find_children("*", "Door", true, false).filter(func(d): return d.locked)
	check(doors.size() == 3, "三扇锁着的门：民居、酒馆、领主宅邸（%d）" % doors.size())
	var fog := get_tree().get_nodes_in_group("fog_band")
	check(fog.size() >= 10, "贴地雾带 %d 片" % fog.size())
	# 画质分档
	main.apply_quality("low")
	var shown := fog.filter(func(f): return f.visible).size()
	check(is_equal_approx(main.get_viewport().scaling_3d_scale, 0.75) and not main.moon.shadow_enabled and not main.env.glow_enabled and shown < fog.size(), "低画质：0.75 倍分辨率、无阴影、无泛光、雾带减半（%d / %d）" % [shown, fog.size()])
	main.apply_quality("high")
	check(main.get_viewport().msaa_3d == Viewport.MSAA_2X and main.moon.shadow_enabled and main.env.glow_enabled, "高画质：2 倍抗锯齿、月光阴影、泛光")
	main.apply_quality("medium")
	check(is_equal_approx(main.get_viewport().scaling_3d_scale, 1.0) and main.get_viewport().msaa_3d == Viewport.MSAA_DISABLED and main.moon.shadow_enabled, "中画质：原分辨率、月光阴影")
	# 固定机位
	main.set_view(2)
	check(p.global_position.is_equal_approx(Frostford.VIEWS[2][0]) and absf(p.yaw_deg() - 180.0) < 0.1, "?view=2：从领主宅邸前回望街道")
	# 往北一直跑：被领主宅邸挡住，不会穿过去
	await place(p, 0.0, 0.0)
	Input.action_press("sprint")
	await hold("move_forward", 10.0)
	Input.action_release("sprint")
	check(p.global_position.z > Frostford.NORTH_END and p.global_position.z < Frostford.NORTH_END + 2.0, "沿街往北跑到尽头，停在领主宅邸门前（z = %.2f）" % p.global_position.z)
	# 从小广场钻到房子背后，往西一直走：被看不见的围墙挡住
	await place(p, -6.0, -23.0)
	p.rotation.y = PI / 2
	await hold("move_forward", 6.0)
	check(p.global_position.x > -15.5 and p.global_position.x < -13.0, "走到房子背后，被区域边界挡住（x = %.2f）" % p.global_position.x)
	# 更夫在灯下，可以交谈
	await aim(p, Frostford.WATCH_POS + Vector3(0, 0, 1.8), Frostford.WATCH_POS + Vector3(0, 1.4, 0))
	check(p.interactor.target is Npc and p.interactor.target.display_name == "更夫", "更夫站在第一盏街灯下，可以交谈")
	await free_main(main)
	# 贴图缺文件：退回纯色，不崩
	var saved := Look.photo_dir
	Look.photo_dir = "res://assets/textures/%s/missing_%s_%s.jpg"
	Look.clear_cache()
	var m := Look.mat("stone")
	check(not bool(m.get_meta("photo", true)) and m.albedo_texture == null and m.albedo_color == Look.PHOTO.stone.fallback, "贴图缺文件时退回纯色材质")
	Look.photo_dir = saved
	Look.clear_cache()
	# 系统「减少动态效果」：街灯不闪、雾带不飘
	Settings.reduced_motion = true
	main = await make_main(false)
	var lamp: StreetLamp = get_tree().get_nodes_in_group("street_lamp")[0]
	await frames(5)
	var band: MeshInstance3D = get_tree().get_nodes_in_group("fog_band")[0]
	check(not lamp.flicker and is_equal_approx(lamp.light.light_energy, lamp.ENERGY) and band.material_override.get_shader_parameter("drift") == Vector2.ZERO, "减少动态效果：街灯不闪烁、雾带不飘动")
	Settings.reduced_motion = false
	await free_main(main)


func test_perf() -> void:
	var main := await make_main(false)
	var ov: PerfOverlay = main.perf_overlay
	check(not ov.visible, "性能浮层默认不显示")
	var ev := InputEventAction.new()
	ev.action = "perf_toggle"
	ev.pressed = true
	Input.parse_input_event(ev)
	await frames(3)
	check(ov.visible and Settings.show_perf, "按 F3 打开性能浮层")
	await seconds(0.7)
	var t: String = ov.label.text
	check(t.contains("帧率") and t.contains("绘制调用") and t.contains("中画质") and t.contains("显卡"), "浮层显示帧率、最慢一帧、绘制调用、画质档、显卡（%s）" % t.replace("\n", " / "))
	check(main.pause_menu.perf_check.button_pressed, "暂停菜单里「显示性能数据」同步打勾")
	main.pause_menu.perf_check.button_pressed = false
	await frames(2)
	check(not ov.visible, "在暂停菜单里关掉性能浮层")
	# 暂停菜单的画质按钮
	check(main.pause_menu.quality_btns.medium.button_pressed, "暂停菜单的画质按钮显示当前档（中）")
	main.pause_menu.quality_btns.low.pressed.emit()
	await frames(2)
	check(main.quality == "low" and is_equal_approx(main.get_viewport().scaling_3d_scale, 0.75), "在暂停菜单里切到低画质，立即生效")
	main.apply_quality("medium")
	check(main.pause_menu.quality_btns.medium.button_pressed, "代码切换画质时按钮跟着变")
	# 基准测试：3 个机位（测试里缩短等待与采样时间）
	var res: Array = await main.run_benchmark(0.2, 0.4)
	check(res.size() == 3 and res.all(func(r): return r.fps > 0.0 and r.draw_calls >= 0.0 and r.has("worst_ms")), "基准测试依次测 3 个机位，每个都有平均帧率、最慢一帧、绘制调用")
	check(ov.bench_text.contains("基准测试结果") and ov.bench_text.contains(Frostford.VIEW_NAMES[2]) and ov.bench_text.contains("请截图"), "结果表显示在性能浮层上，提示截图")
	check(main.player.global_position.is_equal_approx(Frostford.VIEWS[0][0]), "测完回到出生点")
	Settings.set_value("show_perf", false)
	await free_main(main)
