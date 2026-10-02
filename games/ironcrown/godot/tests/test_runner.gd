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
	for g in ["boot", "ui", "move", "terrain", "look", "touch", "pause", "interact", "frostford", "perf", "dialogue", "checks", "quests", "melee", "enemies", "inventory"]:
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
	# 近战（2.4）：触屏按钮、体力条、木桩假人上的字
	texts.append("攻体力 / 0123456789 · 喘息中命中次 · 最高左键（手机点「攻」）出剑重击 −木桩假人")
	# 敌人与格挡（2.5）
	texts.append_array([main.HINT_ARENA_DESKTOP, main.HINT_ARENA_TOUCH, "挡生命 · 失衡你倒下了重来举剑格挡能把伤害换成体力；对方劈下前一瞬间格挡，能让他失衡。",
		"◆ 完美格挡！对方失衡挡住了（体力 −）× 格挡被打破！✓ 训练场清空了（按 Esc 打开菜单，刷新页面再来一次）（刷新页面再来一次）",
		"训练场 · 三个无旗者在那儿！失衡格挡别打了，我认输！快跑！（倒下）"])
	for t in Enemy.STATE_LABELS:
		texts.append(t)
	# 背包与搜刮（2.6）：物品名字与说明、面板文字
	for id in GameState.items():
		if not str(id).begins_with("_"):
			texts.append(str(GameState.items()[id].name) + str(GameState.items()[id].desc))
	texts.append_array(GameState.SLOT_NAMES.values() + GameState.KIND_NAMES.values())
	texts.append("背包搜刮：护甲负重斤银币超重：不能跑装备（空）（已装备）×卸下使用选一件东西看看。伤害部走动更吵不能丢弃值什么都没有了。全部拿走拿到：、没有装备武器（点「背包」按 I 打开背包装备）打开破木箱补给箱")
	for k in Enemy.types():
		if not str(k).begins_with("_"):
			texts.append(str(Enemy.types()[k].name))
	# 任务日志（2.3）：任务名、简介、目标、线索、提示语
	var qd := GameState.quest_data()
	texts.append("任务日志主线支线关闭（已完成）当前目标：线索：这件事已经办完了。还没有任务◆新任务：（按J查看）（点「任务」查看）任务更新：✓任务完成：◇新线索已记入任务日志▶")
	for qid in qd.quests:
		texts.append(str(qd.quests[qid].title) + str(qd.quests[qid].summary))
		for st in qd.quests[qid].stages:
			texts.append(str(qd.quests[qid].stages[st].objective))
	for cid in qd.clues:
		texts.append(str(qd.clues[cid].text))
	# 全部对话台词与选项（2.1）
	var dlg := DialogueRunner.load_file("frostford")
	for did in dlg:
		if did.begins_with("_"):
			continue
		texts.append(str(dlg[did].speaker))
		for nid in dlg[did].nodes:
			texts.append(str(dlg[did].nodes[nid].text))
			for o in dlg[did].nodes[nid].options:
				texts.append(str(o.text))
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
	check(r.get("kind") == "pickup" and GameState.has_item("bread"), "拾取面包：放进背包（%s）" % str(GameState.inventory))
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
	check(p.global_position.z > Frostford.NORTH_END and p.global_position.z < Frostford.NORTH_END + 3.0, "沿街往北跑到尽头，停在领主宅邸门前（门口站着管家，z = %.2f）" % p.global_position.z)
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


func key_ev(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = true
	return e


func test_dialogue() -> void:
	GameState.new_game(1)        # 旗标会影响对话：每次从一局新游戏开始
	# 数据：霜渡镇所有对话都通过校验
	var all := DialogueRunner.load_file("frostford")
	var bad := []
	for did in all:
		if did.begins_with("_"):
			continue
		for e in DialogueRunner.validate(all[did]):
			bad.append("%s：%s" % [did, e])
	check(all.has("watchman") and bad.is_empty(), "霜渡镇的对话全部通过校验：节点都走得到、选项都指向存在的节点、能结束（问题：%s）" % str(bad))
	var broken := {"start": "a", "nodes": {"a": {"text": "嗨", "options": [{"text": "去 b", "next": "b"}, {"text": "去 x", "next": "x"}]},
		"b": {"text": "b", "options": [{"text": "回 a", "next": "a"}]}, "c": {"text": "孤岛", "options": [{"text": "走", "end": true}]}}}
	var errs := DialogueRunner.validate(broken)
	check(errs.any(func(e): return e.contains("不存在的节点 x")) and errs.any(func(e): return e.contains("c：从开始节点走不到")) and errs.any(func(e): return e.contains("没有任何选项能结束")), "校验能抓出：指向不存在的节点、走不到的节点、从开始走不到结束（%s）" % str(errs))
	# 规则：按选项推进
	var r := DialogueRunner.new()
	check(r.start("frostford", "watchman") and r.speaker() == "更夫" and r.options().size() == 4, "更夫的对话从「greet」开始，4 个选项")
	check(r.choose(1) and r.node_id == "edric" and r.choose(0) and r.node_id == "stranger", "选「你今晚见过埃德里克少爷吗」→ 再问南方人，台词跟着走")
	check(r.choose(r.options().size() - 1) and r.node_id == "menu" and not r.choose(r.options().size() - 1) and r.node_id == "", "回到「还有什么要问的」，选「没有了」对话结束")
	check(not r.start("frostford", "nobody"), "找不到的对话不会打开")
	# 游戏里：对准更夫按 E
	GameState.new_game(1)
	var main := await make_main(false)
	var p: FpController = main.player
	await aim(p, Frostford.WATCH_POS + Vector3(1.2, 0, 1.8), Frostford.WATCH_POS + Vector3(0, 1.4, 0))
	var ev := InputEventAction.new()
	ev.action = "interact"
	ev.pressed = true
	Input.parse_input_event(ev)
	await frames(3)
	var dp: DialoguePanel = main.dialogue
	check(dp.visible and get_tree().paused and dp.name_label.text == "更夫" and dp.buttons.size() == 4, "对准更夫按 E：弹出对话面板（说话人、台词、4 个选项），游戏暂停")
	check(main.hud.prompt_label.text == "" and main.hud.hint_label.text == "", "对话时准星下的交互提示、底部的操作提示都隐藏")
	# 镜头转向：先关掉对话、把人转开，再直接打开对话，看镜头会不会转回来
	dp.close()
	await frames(2)
	p.rotation.y += 1.2
	var turned_away := p.rotation.y
	var npc: Npc = main.find_children("*", "Npc", true, false)[0]
	main.open_dialogue("frostford", "watchman", npc)
	await seconds(0.5)
	var to := npc.global_position - p.global_position
	var want := atan2(-to.x, -to.z)
	check(absf(angle_difference(p.rotation.y, want)) < 0.08 and absf(angle_difference(turned_away, want)) > 0.3, "镜头转向说话人（打开对话前转开了 %.2f 弧度，暂停时照样转回来）" % absf(angle_difference(turned_away, want)))
	var pz := p.global_position
	Input.action_press("move_forward")
	await physics(20)
	Input.action_release("move_forward")
	check(p.global_position.is_equal_approx(pz), "对话时玩家不会走动")
	Input.parse_input_event(key_ev(KEY_2))
	await frames(2)
	check(dp.runner.node_id == "edric" and dp.text_label.text.contains("渡口"), "按数字键 2 选第二个选项")
	dp.buttons[0].pressed.emit()
	await frames(2)
	check(dp.runner.node_id == "stranger" and dp.buttons.size() == 2, "点选项按钮（鼠标 / 触屏）推进对话")
	await frames(2)
	var pr := dp.panel.get_global_rect()
	check(pr.position.x >= 0 and pr.end.x <= main.hud.size.x and pr.end.y <= main.hud.size.y + 1 and pr.position.y > main.hud.size.y * 0.3, "对话面板在屏幕下方、不超出画面（%s）" % pr)
	var esc := InputEventAction.new()
	esc.action = "pause"
	esc.pressed = true
	Input.parse_input_event(esc)
	await frames(3)
	check(not dp.visible and not get_tree().paused and not main.pause_menu.visible, "按 Esc 结束对话（不会打开暂停菜单），游戏继续")
	check(main.hud.prompt_label.text.contains("交谈 · 更夫"), "对话结束后交互提示回来")
	main.player.interactor.use()
	await frames(2)
	dp.choose(dp.buttons.size() - 1)     # 最后一个选项是「没事，你接着巡夜吧」（问过少爷以后会多出一个选项）
	await frames(2)
	check(not dp.visible and not get_tree().paused, "选「没事，你接着巡夜吧」也会结束对话")
	await free_main(main)


## 找一个能让某个检定成功（want = true）或失败的存档种子
func seed_for(check_id: String, skill: String, dc: int, want: bool) -> int:
	for sd in 500:
		GameState.new_game(sd)
		if (GameState.roll_for(check_id) < GameState.check_chance(skill, dc)) == want:
			return sd
	return -1


func test_checks() -> void:
	GameState.new_game(1)
	# 把握：检定值 = 技能 + 机敏 × 2，每比难度高 1 点 +5%，限制在 5%–95%
	check(GameState.check_value("speech") == 16 and is_equal_approx(GameState.check_chance("speech", 12), 0.7), "口才检定值 10 + 3×2 = 16，难度 12 → 把握 70%")
	check(is_equal_approx(GameState.check_chance("speech", 40), 0.05) and is_equal_approx(GameState.check_chance("speech", 0), 0.95), "把握限制在 5%–95%（不会必成或必败）")
	check(GameState.chance_label(0.85) == "把握很大" and GameState.chance_label(0.6) == "把握较大" and GameState.chance_label(0.5) == "一半一半" and GameState.chance_label(0.25) == "把握较小" and GameState.chance_label(0.1) == "几乎没把握", "把握分五档文字")
	# 不能刷：同一种子同一检定结果相同；掷过的检定，技能变了也不变
	GameState.new_game(42)
	var first := GameState.check("t_a", "insight", 12)
	GameState.new_game(42)
	check(GameState.check("t_a", "insight", 12) == first, "同一个存档种子、同一个检定，结果永远一样（读档刷不出别的结果）")
	GameState.skills.insight = 100
	check(GameState.check("t_a", "insight", 12) == first, "掷过的检定记下来了：之后技能变高也不会改变结果")
	GameState.new_game(7)
	var wins := 0
	for i in 600:
		if GameState.check("dist_%d" % i, "speech", 12):
			wins += 1
	check(wins > 360 and wins < 480, "600 次把握 70%% 的检定成功 %d 次（约 70%%）" % wins)
	var differ := false
	for i in 20:
		GameState.new_game(1)
		var a := GameState.check("cmp_%d" % i, "speech", 16)
		GameState.new_game(2)
		differ = differ or a != GameState.check("cmp_%d" % i, "speech", 16)
	check(differ, "不同存档种子的结果不一样（不是写死的）")
	# 旗标登记：对话里用到的都登记了，登记的都有地方设置
	var reg := GameState.flag_registry()
	var text := FileAccess.get_file_as_string("res://data/dialogue/frostford.json")
	var unused := []
	for f in reg:
		if not f.begins_with("_") and not text.contains('"set": "%s"' % f):
			unused.append(f)
	check(reg.size() >= 5 and unused.is_empty(), "data/flags.json 登记的旗标都在对话里有地方设置（没设置的：%s）" % str(unused))
	var bad := {"start": "a", "nodes": {"a": {"text": "嗨", "options": [
		{"text": "去", "next": "a", "if": [{"flag": "no_such_flag"}]},
		{"text": "怪", "next": "a", "jump": "b"},
		{"text": "检", "check": {"id": "x", "skill": "dance", "dc": 10, "pass": "a", "fail": "nowhere"}},
		{"text": "走", "end": true}]}}}
	var errs := DialogueRunner.validate(bad)
	check(errs.any(func(e): return e.contains("no_such_flag 没有登记")) and errs.any(func(e): return e.contains("不认识的键 jump")) and errs.any(func(e): return e.contains("技能不认识：dance")) and errs.any(func(e): return e.contains("fail 指向不存在的节点 nowhere")), "校验能抓出：没登记的旗标、不认识的键、不认识的技能、检定分支指向不存在的节点")
	# 条件与效果
	GameState.new_game(1)
	var r := DialogueRunner.new()
	r.start("frostford", "watchman")
	var before := r.options().size()
	check(not r.options().any(func(o): return str(o.text).contains("再想想")), "没听说少爷的去向时，「关于埃德里克少爷，你再想想」不出现")
	r.choose(1)
	check(GameState.has_flag("heard_edric_to_ferry"), "进入「少爷的去向」那段，记下旗标 heard_edric_to_ferry")
	r.start("frostford", "watchman")
	check(r.options().size() == before + 1, "听说以后再找更夫，多出「关于埃德里克少爷，你再想想」")
	var lbl := DialogueRunner.option_label({"text": "你还看见了别的，对吧？", "check": {"id": "x", "skill": "insight", "dc": 12}})
	check(lbl == "[洞察 · 把握较大] 你还看见了别的，对吧？", "检定选项前面直接显示技能和把握（%s）" % lbl)
	# 洞察检定：成功 / 失败各走一条路
	var sd_pass := seed_for("watchman_edric_insight", "insight", 12, true)
	var sd_fail := seed_for("watchman_edric_insight", "insight", 12, false)
	GameState.new_game(sd_pass)
	r.start("frostford", "watchman")
	r.choose(1)
	r.choose(1)
	check(r.node_id == "edric_more" and r.last_check.ok and GameState.has_flag("heard_cloaked_men"), "洞察检定成功：更夫说出斗篷人，记下旗标 heard_cloaked_men")
	GameState.new_game(sd_fail)
	r.start("frostford", "watchman")
	r.choose(1)
	r.choose(1)
	check(r.node_id == "edric_shut" and not r.last_check.ok and not GameState.has_flag("heard_cloaked_men"), "洞察检定失败：更夫不肯再说")
	r.choose(0)
	var idx := -1
	for i in r.options().size():
		if str(r.options()[i].text).contains("再想想"):
			idx = i
	r.choose(idx)
	r.choose(0)
	check(r.node_id == "edric_shut", "失败后换个说法再问同一个检定，结果还是失败（不能刷）")
	# 换条路：塞银币（只能塞一次）
	r.start("frostford", "watchman")
	r.choose(2)
	r.choose(1)
	check(r.node_id == "edric_paid" and GameState.has_flag("watchman_paid") and GameState.has_flag("heard_cloaked_men"), "检定失败还可以塞银币换消息")
	r.choose(0)
	r.choose(2)
	check(not r.options().any(func(o): return str(o.text).contains("银币")), "银币只能塞一次")
	# 威吓失败：更夫翻脸，之后换成冷淡开场
	var sd_off := seed_for("watchman_stranger_intimidate", "intimidate", 14, false)
	GameState.new_game(sd_off)
	r.start("frostford", "watchman")
	r.choose(1)
	r.choose(0)
	r.choose(0)
	check(r.node_id == "watch_offended" and GameState.has_flag("watchman_offended") and GameState.has_flag("knows_double_key_ring"), "威吓更夫失败：他翻脸，记下旗标 watchman_offended")
	r.start("frostford", "watchman")
	check(r.node_id == "cold" and r.options().size() == 1, "惹恼更夫以后，再找他只有一句冷淡的话")
	# 游戏里：面板显示检定结果
	GameState.new_game(sd_pass)
	var main := await make_main(false)
	main.open_dialogue("frostford", "watchman")
	await frames(2)
	var dp: DialoguePanel = main.dialogue
	dp.choose(1)
	await frames(2)
	check(dp.buttons[1].text.contains("[洞察 · 把握较大]"), "对话面板里的检定选项显示把握（%s）" % dp.buttons[1].text)
	dp.choose(1)
	await frames(2)
	check(dp.name_label.text.contains("√ 洞察检定成功") and dp.runner.node_id == "edric_more", "检定后说话人旁边显示「√ 洞察检定成功」（文字 + 符号）")
	dp.close()
	await free_main(main)
	GameState.new_game(1)


func test_quests() -> void:
	# 数据：每个任务的开始阶段、自动推进的目标阶段、线索所属的任务都存在
	var qd := GameState.quest_data()
	var bad := []
	for qid in qd.quests:
		var q: Dictionary = qd.quests[qid]
		if not q.stages.has(str(q.first)):
			bad.append("%s 的开始阶段不存在" % qid)
		if not str(q.kind) in ["main", "side"]:
			bad.append("%s 的种类不对" % qid)
		for st in q.stages:
			var to := str(q.stages[st].get("advance_when", {}).get("to", ""))
			if to != "" and not q.stages.has(to):
				bad.append("%s/%s 自动推进到不存在的阶段 %s" % [qid, st, to])
	for cid in qd.clues:
		if not qd.quests.has(str(qd.clues[cid].quest)):
			bad.append("线索 %s 属于不存在的任务" % cid)
	check(qd.quests.has("edric_missing") and qd.quests.has("hob_debt") and bad.is_empty(), "data/quests.json：主线「雾里的少爷」、支线「醉汉的赌债」，阶段与线索都对得上（问题：%s）" % str(bad))
	# 管家交代主线
	GameState.new_game(1)
	var events := []
	var rec := func(k: String, id: String): events.append(k + ":" + id)
	GameState.quest_event.connect(rec)
	var r := DialogueRunner.new()
	r.start("frostford", "steward")
	check(r.node_id == "greet" and not GameState.quests.has("edric_missing"), "第一次找管家：他说少爷失踪了，任务还没接")
	r.choose(0)
	check(GameState.quest_active("edric_missing") and GameState.quest_stage("edric_missing") == "find_clues" and events.has("started:edric_missing"), "答应下来：接到主线「雾里的少爷」，目标是打探少爷的下落")
	r.start("frostford", "steward")
	check(r.node_id == "waiting" and r.options().size() == 1, "接了任务再找管家：他问有没有消息；还没线索时没有「去渡口」的选项")
	# 更夫给两条线索 → 主线自动推进
	r.start("frostford", "watchman")
	r.choose(1)
	check(GameState.clues == ["ferry"] and events.has("clue:ferry") and GameState.quest_stage("edric_missing") == "find_clues", "问更夫少爷的去向：记下线索「往渡口去了」")
	r.choose(0)
	check(GameState.clues_for("edric_missing").size() == 2 and GameState.quest_stage("edric_missing") == "to_ferry" and events.has("advanced:edric_missing"), "再问南方人：第二条线索（双钥印戒），任务自动更新为「去渡口找少爷」")
	r.start("frostford", "watchman")
	r.choose(1)
	check(GameState.clues.size() == 2, "同一条线索不会记两次")
	r.start("frostford", "steward")
	check(r.options().size() == 2 and r.choose(1) and r.node_id == "ferry", "线索够了再找管家：多出「线索都指向渡口」的选项")
	# 醉汉的赌债：要有面包
	r.start("frostford", "hob")
	check(GameState.quest_active("hob_debt") and r.options().size() == 1, "找老霍布：接到支线；身上没吃的，只能「回头再说」")
	GameState.add_item("bread")
	r.start("frostford", "hob")
	check(r.options().size() == 2, "捡到面包后，多出「把面包递给他」")
	r.choose(0)
	check(not GameState.has_item("bread") and GameState.quest_done("hob_debt") and GameState.clues.has("dice") and events.has("done:hob_debt"), "给了面包：面包没了，支线完成，得到线索「斗篷人是无旗者，银币上压着双钥」")
	r.start("frostford", "hob")
	check(r.node_id == "after", "办完以后再找他，他只说面包很好吃")
	GameState.quest_event.disconnect(rec)
	# 先拿到线索、后接任务：一接就直接推进
	GameState.new_game(1)
	r.start("frostford", "watchman")
	r.choose(1)
	r.choose(0)
	r.start("frostford", "steward")
	r.choose(0)
	check(GameState.quest_stage("edric_missing") == "to_ferry", "先从更夫那里问到两条线索、再去找管家接任务：任务一接就更新到「去渡口」")
	# 游戏里：任务日志
	GameState.new_game(1)
	var main := await make_main(false)
	GameState.start_quest("edric_missing")
	GameState.add_clue("ferry")
	GameState.add_item("bread")
	GameState.start_quest("hob_debt")
	await frames(2)
	check(main.hud.toast_label.text.contains("新任务：雾里的少爷") and main.hud.toast_label.text.contains("新线索"), "接任务、得线索时屏幕上方提示（%s）" % main.hud.toast_label.text.replace("\n", " / "))
	var ev := InputEventAction.new()
	ev.action = "quest_log"
	ev.pressed = true
	Input.parse_input_event(ev)
	await frames(3)
	var qp: QuestPanel = main.quest_panel
	check(qp.visible and get_tree().paused, "按 J 打开任务日志，游戏暂停")
	check(qp.detail.text.contains("当前目标：打探埃德里克少爷的下落") and qp.detail.text.contains("往渡口去了"), "主线页显示当前目标和已得到的线索")
	qp.tab_side.pressed.emit()
	await frames(2)
	check(qp.detail.text.contains("醉汉的赌债") and qp.detail.text.contains("面包"), "切到支线页：显示「醉汉的赌债」")
	Input.parse_input_event(ev)
	await frames(3)
	check(not qp.visible and not get_tree().paused, "再按 J（或 Esc）关闭任务日志")
	main.hud.quest_pressed.emit()
	await frames(2)
	check(qp.visible, "右上角「任务」按钮打开任务日志（手机用）")
	qp.close()
	await frames(2)
	var rect: Rect2 = qp.panel.get_global_rect()
	check(rect.size.x <= main.hud.size.x, "任务日志面板不超出画面")
	# 对准管家按 E
	await aim(main.player, Frostford.STEWARD_POS + Vector3(0, 0, 1.8), Frostford.STEWARD_POS + Vector3(0, 1.4, 0))
	check(main.player.interactor.target is Npc and main.player.interactor.target.display_name == "管家", "领主宅邸门口站着管家，可以交谈")
	await free_main(main)
	GameState.new_game(1)


func melee_tick(sec: float) -> void:
	await seconds(sec)


func test_melee() -> void:
	# 伤害公式（GDD.md 6.3）
	check(DamageCalc.compute(10.0, 5, 15, "light") == 12, "伤害公式：短剑 10 × (1 + 力量 5 × 0.03 + 剑术 15 × 0.005) = 12（轻击）")
	check(DamageCalc.compute(10.0, 5, 15, "heavy") == 22, "重击 × 1.8 = 22")
	check(DamageCalc.compute(10.0, 0, 0, "light", true) == 20, "对方失衡时伤害加倍（10 → 20）")
	check(DamageCalc.compute(10.0, 0, 0, "light", false, 4.0) == 8, "护甲 4 减 2 点")
	check(DamageCalc.compute(10.0, 0, 0, "light", false, 30.0) == 2, "护甲再高也至少造成 20%")
	GameState.new_game(1)
	var main := await make_main(true)
	var p: FpController = main.player
	var m: Melee = p.melee
	var dummy: TrainingDummy = null
	for c in main.world.get_children():
		if c is TrainingDummy:
			dummy = c
	check(dummy != null and dummy.is_in_group("damageable") and dummy.collision_layer & 8 != 0, "测试场有木桩假人（物理层 4「可受击」）")
	await aim(p, TestRange.DUMMY_POS + Vector3(0, 0, 1.6), TestRange.DUMMY_POS + Vector3(0, 1.2, 0))
	check(m.state == Melee.State.SHEATHED and not m.view.visible, "开局剑在鞘里，手里看不到武器")
	check(not main.hud.stamina_visible(), "收着剑、体力满：不显示体力条")
	m.press()
	m.release()
	check(m.state == Melee.State.DRAWING, "收着剑时按攻击：先拔剑，不直接出招")
	await melee_tick(0.5)
	check(m.state == Melee.State.IDLE and m.view.visible and m.drawn(), "拔剑完成，手里出现短剑")
	check(main.hud.stamina_visible() and main.hud.stamina_label.text.begins_with("体力 100"), "拔剑后左下角显示体力条和数值")
	var tip: Vector3 = m.view.to_global(Vector3(0, 0.7, 0))
	check(p.camera.is_position_in_frustum(m.view.global_position) and p.camera.is_position_in_frustum(tip), "持剑姿势：剑柄和剑尖都在画面里")
	var kinds: Array = []
	m.swung.connect(func(k: String): kinds.append(k))
	var hits: Array = []
	m.hit.connect(func(t: Node, info: Dictionary): hits.append([t, info]))
	# 轻击：点一下
	m.press()
	await frames(2)
	m.release()
	check(m.state == Melee.State.WINDUP and kinds == ["light"], "点一下 = 轻击（起手）")
	var scale_seen := []
	for i in 30:
		await get_tree().process_frame
		scale_seen.append(Engine.time_scale)
		if not hits.is_empty():
			break
	check(hits.size() == 1 and hits[0][0] == dummy, "轻击在命中帧打中前方 1.6 米的木桩")
	check(dummy.hits == 1 and dummy.best == 12 and hits[0][1].damage == 12, "木桩记下这一击：12 点（与公式一致）")
	check(m.stop_left > 0.0 and dummy.stop_left > 0.0 and scale_seen.all(func(x): return x == 1.0), "命中停顿只冻结挥剑与木桩，不改全局时间流速")
	var floats := dummy.get_children().filter(func(c): return c is FloatText)
	check(floats.size() == 1 and (floats[0] as FloatText).text == "−12", "木桩头上冒出伤害数字「−12」")
	check(main.hud.marker_left > 0.0, "准星闪成 ×（命中提示不只靠颜色）")
	check(is_equal_approx(m.stamina, 88.0), "轻击消耗 12 点体力（剩 %.1f）" % m.stamina)
	await melee_tick(0.7)
	check(m.state == Melee.State.IDLE, "收招后回到持剑姿势")
	# 两段连击：出招中再点一下
	var h0 := dummy.hits
	m.press()
	m.release()
	await melee_tick(0.15)
	m.press()
	m.release()
	await melee_tick(0.9)
	check(kinds.size() == 3 and dummy.hits == h0 + 2, "出招中再点一下：接第二段，两段都命中（共 %d 次）" % dummy.hits)
	check(m.combo == 0 and m.state == Melee.State.IDLE, "两段打完连击归零")
	# 连点第三下：最多两段（剑术 25 后三段在 2.7）
	m.press(); m.release()
	await melee_tick(0.15)
	m.press(); m.release()
	await melee_tick(0.3)
	m.press(); m.release()
	await melee_tick(1.2)
	var n_after := kinds.size()
	check(n_after == 5 or n_after == 6, "一套最多两段；第三下要等收招后才算新的一套（出招 %d 次）" % (n_after - 3))
	await melee_tick(0.8)
	# 重击：按住 0.35 秒以上松开
	m.stamina = Melee.STAMINA_MAX
	var best0 := dummy.best
	m.press()
	await melee_tick(0.45)
	check(m.state == Melee.State.CHARGE and m.held >= Melee.HEAVY_HOLD, "按住攻击：举剑蓄力")
	m.release()
	check(kinds.back() == "heavy", "按住 0.35 秒以上松开 = 重击")
	await melee_tick(0.3)
	check(hits.back()[1].kind == "heavy" and hits.back()[1].damage == 22 and dummy.best == maxi(best0, 22), "重击打中木桩：22 点")
	check(is_equal_approx(m.stamina, 75.0), "重击消耗 25 点体力（剩 %.1f）" % m.stamina)
	await melee_tick(0.8)
	# 背对木桩、离得太远：打空
	var hn := dummy.hits
	p.rotation.y += PI
	await physics(2)
	m.press(); m.release()
	await melee_tick(0.7)
	check(dummy.hits == hn and m.last_hit.is_empty(), "背对木桩挥剑：打空")
	await aim(p, TestRange.DUMMY_POS + Vector3(0, 0, 3.0), TestRange.DUMMY_POS + Vector3(0, 1.2, 0))
	m.press(); m.release()
	await melee_tick(0.7)
	check(dummy.hits == hn, "离木桩 3 米（超出 2 米剑程）：打空")
	# 中间隔着墙：放一堵墙在玩家与木桩之间
	await aim(p, TestRange.DUMMY_POS + Vector3(0, 0, 1.6), TestRange.DUMMY_POS + Vector3(0, 1.2, 0))
	var wall := Blocks.box(main.world, Vector3(2.0, 2.5, 0.1), TestRange.DUMMY_POS + Vector3(0, 1.25, 0.55), Blocks.mat(Color.GRAY))
	await physics(2)
	m.press(); m.release()
	await melee_tick(0.7)
	check(dummy.hits == hn, "中间隔着墙：打不到墙后的木桩")
	wall.queue_free()
	await physics(2)
	# 体力：耗尽后出招变慢、不能跑，缓过气才恢复
	m.stamina = 5.0
	m.press(); m.release()
	check(m.speed == Melee.TIRED_SPEED and m.exhausted and m.stamina == 0.0, "体力不够一击：照样出招但变慢，体力见底")
	await frames(2)                   # 刚从物理帧回来：同一帧的 process_frame 先于界面的 _process，等两帧
	check(main.hud.stamina_label.text.contains("喘息中"), "体力条写明「喘息中」")
	Input.action_press("sprint")
	Input.action_press("move_back")
	await physics(10)
	check(not p.running and not p.wants_run(), "体力耗尽时按住 Shift 也跑不起来")
	Input.action_release("sprint")
	Input.action_release("move_back")
	await melee_tick(2.0)
	check(not m.exhausted and m.stamina >= Melee.RECOVER_AT, "停手一会儿体力恢复、缓过气（%.0f）" % m.stamina)
	# 跑步消耗体力
	m.stamina = Melee.STAMINA_MAX
	await place(p, -3.0, 8.0)
	Input.action_press("sprint")
	await hold("move_forward", 1.0)
	Input.action_release("sprint")
	check(m.stamina < Melee.STAMINA_MAX - 8.0, "跑 1 秒消耗体力（剩 %.0f）" % m.stamina)
	# 蓄力中打开暂停菜单：不攒着重击
	m.press()
	await melee_tick(0.2)
	main.open_pause()
	check(m.state != Melee.State.CHARGE and not m.pressed, "蓄力时打开菜单：放弃蓄力")
	main.close_pause()
	await melee_tick(0.4)
	# 收剑
	m.toggle_draw()
	await melee_tick(0.5)
	check(m.state == Melee.State.SHEATHED and not m.view.visible, "R 收剑：武器放下并隐藏")
	# 触屏「攻」按钮：点按轻击、按住重击
	var t: TouchControls = main.touch
	t.visible = true
	var bc: Dictionary = t.button_centers()
	check(bc.has("attack") and t.button_at(bc.attack) == "attack", "触屏有「攻」按钮")
	var others := ["jump", "crouch"]
	check(others.all(func(k): return bc[k].distance_to(bc.attack) > TouchControls.BTN_R * 2.5), "「攻」不和「跳」「蹲」挤在一起")
	await aim(p, TestRange.DUMMY_POS + Vector3(0, 0, 1.6), TestRange.DUMMY_POS + Vector3(0, 1.2, 0))
	t._input(touch_ev(3, bc.attack, true))
	t._input(touch_ev(3, bc.attack, false))
	await melee_tick(0.5)
	check(m.drawn(), "收着剑时点「攻」：拔剑")
	var k0 := kinds.size()
	t._input(touch_ev(3, bc.attack, true))
	await melee_tick(0.45)
	t._input(touch_ev(3, bc.attack, false))
	check(kinds.size() == k0 + 1 and kinds.back() == "heavy", "按住「攻」0.35 秒以上松开 = 重击")
	await melee_tick(0.8)
	t._input(touch_ev(3, bc.attack, true))
	await frames(2)
	t._input(touch_ev(3, bc.attack, false))
	check(kinds.back() == "light", "点一下「攻」= 轻击")
	await melee_tick(0.6)
	await free_main(main)
	# 霜渡镇：更夫岗哨对面有木桩，机位 5 正对着它
	main = await make_main(false)
	main.set_view(5)
	await physics(4)
	var fd: Node3D = main.player.melee.find_target()
	check(fd is TrainingDummy and fd.global_position.distance_to(Frostford.DUMMY_POS) < 0.01, "霜渡镇机位 5：剑程内正对木桩假人")
	await free_main(main)


func make_arena() -> Node3D:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.use_arena = true
	add_child(main)
	await frames(3)
	return main


func arena_enemy(main: Node3D, id: String) -> Enemy:
	for e in main.get_tree().get_nodes_in_group("enemy"):
		if e.enemy_id == id:
			return e
	return null


## 只留一个敌人在动，其余冻住（单项测试不受干扰）
func solo(main: Node3D, keep: Enemy) -> void:
	for e in main.get_tree().get_nodes_in_group("enemy"):
		if e != keep:
			e.process_mode = Node.PROCESS_MODE_DISABLED
			e.global_position = Vector3(-14, 0, -15) + Vector3(e.get_index() * 0.9, 0, 0)


func put_enemy(e: Enemy, pos: Vector3, yaw: float) -> void:
	e.global_position = pos
	e.rotation.y = yaw
	e.velocity = Vector3.ZERO


func test_enemies() -> void:
	# 数据校验
	check(Enemy.validate_types(Enemy.types()).is_empty(), "敌人数据（data/enemies.json）字段齐全、数值合理：%s" % [Enemy.validate_types(Enemy.types())])
	check(Enemy.validate_types({"x": {"name": "x", "bogus": 1}}).size() > 5, "校验能抓出缺字段和不认识的字段")
	GameState.new_game(7)
	var main := await make_arena()
	var p: FpController = main.player
	var m: Melee = p.melee
	check(main.scene_name() == "arena" and main.get_tree().get_nodes_in_group("enemy").size() == 3, "训练场：三个无旗者")
	check(main.get_tree().get_first_node_in_group("combat_director") is CombatDirector, "训练场有攻击令牌调度（CombatDirector）")
	check(main.get_tree().get_nodes_in_group("light_source").size() == 4, "四支火把（敌人据此判断你在不在亮处）")
	var a := arena_enemy(main, "a")
	check(a.state == Enemy.State.PATROL and a.display_name == "无旗者 · 棍手" and a.hp == 50, "开局在巡逻：棍手 50 点生命")
	solo(main, a)
	a.process_mode = Node.PROCESS_MODE_DISABLED         # 感知单项：直接调用
	# 视野
	await place(p, 0.0, 3.0)
	put_enemy(a, Vector3(0, 0, -2), PI)
	await physics(2)
	check(not a.player_lit() and a.can_see_player(), "暗处 5 米、在视野锥里：看得见")
	put_enemy(a, Vector3(0, 0, -2), 0.0)
	await physics(2)
	check(not a.can_see_player(), "背对玩家：看不见（视野锥 110°）")
	put_enemy(a, Vector3(0, 0, -9), PI)
	await physics(2)
	check(not a.can_see_player(), "暗处 12 米：看不见（暗处只有 8 米）")
	await place(p, 0.0, 10.0)
	put_enemy(a, Vector3(0, 0, -2), PI)
	await physics(2)
	check(a.player_lit() and a.can_see_player(), "站在火把旁 12 米：看得见（亮处 20 米）")
	await place(p, 0.0, 3.0)
	put_enemy(a, Vector3(0, 0, -4), PI)
	p.crouch_wanted = true
	await physics(10)
	check(not a.can_see_player(), "暗处 7 米蹲着：看不见（蹲下视距打六折）")
	p.crouch_wanted = false
	await physics(10)
	check(a.can_see_player(), "站起来就被看见")
	var wall := Blocks.box(main.world, Vector3(3, 3, 0.2), Vector3(0, 1.5, 1.5), Blocks.mat(Color.GRAY))
	await physics(2)
	check(not a.can_see_player(), "中间隔着墙：看不见")
	wall.queue_free()
	await physics(2)
	# 起疑 → 警觉 → 战斗
	var seen_states: Array = []
	a.state_changed.connect(func(_e, st): seen_states.append(st))
	a.process_mode = Node.PROCESS_MODE_INHERIT
	await place(p, 0.0, 4.0)
	put_enemy(a, Vector3(0, 0, -2), PI)
	a.waypoints = [a.global_position]               # 站岗：不转身去巡逻点
	await seconds(2.5)
	check(seen_states.slice(0, 3) == ["suspicious", "alert", "combat"], "暗处被看见：起疑 → 警觉 → 战斗（%s）" % [seen_states])
	check(a.status_label.text.begins_with("！"), "战斗中头顶写「！」和生命（%s）" % a.status_label.text)
	await free_main(main)
	# 听觉 + 喊同伙
	GameState.new_game(7)
	main = await make_arena()
	p = main.player
	a = arena_enemy(main, "a")
	var b := arena_enemy(main, "b")
	var sw := arena_enemy(main, "s")
	solo(main, a)
	b.process_mode = Node.PROCESS_MODE_INHERIT
	put_enemy(a, Vector3(0, 0, -4), 0.0)                # 背对玩家
	put_enemy(b, Vector3(6, 0, -12), 0.0)               # 8 米外、也背对
	b.waypoints = [b.global_position]
	a.waypoints = [a.global_position]
	await place(p, 0.0, -1.5)
	Input.action_press("move_left")
	await physics(20)
	Input.action_release("move_left")
	check(a.state in [Enemy.State.SUSPICIOUS, Enemy.State.ALERT, Enemy.State.COMBAT], "身后 3 米走动：被听见，起疑（%s）" % a.state_name())
	check(b.state == Enemy.State.PATROL, "8 米外背对的同伙还没察觉")
	a.alert()
	await physics(2)
	check(b.state in [Enemy.State.ALERT, Enemy.State.COMBAT], "警觉时喊上 12 米内的同伙（%s）" % b.state_name())
	await free_main(main)
	# 攻击令牌：三个都来打，同时出招的不超过 2 个
	GameState.new_game(7)
	main = await make_arena()
	p = main.player
	m = p.melee
	m.health = 100000                                    # 测令牌时别被打倒
	var dir: CombatDirector = main.get_tree().get_first_node_in_group("combat_director")
	await place(p, 0.0, 2.0)
	for e in main.get_tree().get_nodes_in_group("enemy"):
		e.alert(false)
	var max_tokens := 0
	var circled := false
	var attacked := 0
	for i in 240:
		await get_tree().physics_frame
		max_tokens = maxi(max_tokens, dir.count())
		var n := 0
		for e in main.get_tree().get_nodes_in_group("enemy"):
			if e.action == "circle":
				circled = true
			if e.action in ["windup", "strike"]:
				n += 1
		attacked = maxi(attacked, n)
	check(max_tokens <= 2 and max_tokens >= 1, "攻击令牌最多 2 个（最多同时 %d 个）" % max_tokens)
	check(circled, "没拿到令牌的敌人在外圈绕圈")
	check(m.health < 100000, "敌人上来出招打中了玩家（剩 %d）" % m.health)
	await free_main(main)
	# 格挡 / 完美格挡 / 破防（直接调用 receive_hit）
	GameState.new_game(7)
	main = await make_arena()
	p = main.player
	m = p.melee
	a = arena_enemy(main, "a")
	solo(main, a)
	a.process_mode = Node.PROCESS_MODE_DISABLED
	await place(p, 0.0, 3.0)
	put_enemy(a, Vector3(0, 0, 1.5), PI)
	m.block_press()
	check(m.state == Melee.State.DRAWING, "收着剑时按格挡：先拔剑")
	await seconds(0.5)
	check(m.blocking(), "拔出来还按着：举剑格挡")
	var r := m.receive_hit({"damage": 10, "kind": "light", "attacker": a})
	check(r == "perfect" and m.health == 100 and is_equal_approx(m.stamina, Melee.STAMINA_MAX), "刚举剑 0.2 秒内被打：完美格挡，不掉血不耗体力")
	await seconds(0.3)
	r = m.receive_hit({"damage": 10, "kind": "light", "attacker": a})
	check(r == "block" and m.health == 100 and is_equal_approx(m.stamina, 90.0), "一直举着：普通格挡，伤害变成体力消耗（10）")
	r = m.receive_hit({"damage": 10, "kind": "heavy", "attacker": a})
	check(r == "block" and is_equal_approx(m.stamina, 75.0), "挡重击耗 1.5 倍体力（15）")
	put_enemy(a, Vector3(0, 0, 4.5), 0.0)              # 绕到身后
	r = m.receive_hit({"damage": 10, "kind": "light", "attacker": a})
	check(r == "hit" and m.health == 90, "背后来的攻击挡不住")
	put_enemy(a, Vector3(0, 0, 1.5), PI)
	m.stamina = 4.0
	r = m.receive_hit({"damage": 10, "kind": "light", "attacker": a})
	check(r == "guard_break" and m.staggered() and m.health == 85 and not m.blocking(), "体力不够挡：格挡被打破、失衡、吃一半伤害")
	r = m.receive_hit({"damage": 10, "kind": "light", "attacker": a})
	check(r == "hit" and m.health == 65, "失衡时受到的伤害加倍")
	m.press()
	m.release()
	check(m.staggered() and m.state != Melee.State.WINDUP, "失衡时不能出招")
	await frames(3)
	check(main.hud.health_label.visible and main.hud.health_label.text.begins_with("生命 65"), "生命条显示数值（%s）" % main.hud.health_label.text)
	check(main.hud.hurt_left > 0.0, "受伤时画面四周闪一下")
	await seconds(1.0)
	m.block_release()
	check(not m.staggered() and not m.blocking(), "失衡 0.8 秒后恢复")
	# 举剑格挡时走得慢、不能跑
	m.block_press()
	await seconds(0.3)
	check(p.current_speed(Vector2(0, -1)) == FpController.GUARD_SPEED and not p.wants_run(), "举剑格挡时只能慢慢挪")
	m.block_release()
	await seconds(0.3)
	# 完美格挡（真实时机）：棍手起手快劈下时才举剑
	a.process_mode = Node.PROCESS_MODE_INHERIT
	m.health = 100
	m.stamina = Melee.STAMINA_MAX
	var results: Array = []
	m.guarded.connect(func(res, _i): results.append(res))
	a.alert(false)
	var parried := false
	for i in 600:
		await get_tree().physics_frame
		if a.action == "windup" and not m.blocking():
			var wt := float(a.data.heavy_windup if a.attack_kind == "heavy" else a.data.windup)
			if a.action_t >= wt - 0.08:
				m.block_press()
		if a.action == "recover" and m.blocking():
			m.block_release()
		if a.state == Enemy.State.STAGGER:
			parried = true
			break
	check(parried and results.has("perfect"), "对方劈下前一瞬间举剑：完美格挡，对方失衡（%s）" % [results])
	m.block_release()
	# 失衡的敌人挨打伤害加倍
	if parried:
		await aim(p, p.global_position, a.global_position + Vector3(0, 1.2, 0))
		a.stop_left = 0.0
		m.block_release()
		await seconds(0.3)
		var hp0 := a.hp
		m.press()
		m.release()
		await seconds(0.3)
		check(hp0 - a.hp == 24, "失衡时挨一记轻击：伤害加倍 12 → 24（实际 %d）" % (hp0 - a.hp))
	await free_main(main)
	# 剑手格挡轻击、重击破防；受重伤求饶 / 逃跑；倒下
	GameState.new_game(7)
	main = await make_arena()
	p = main.player
	m = p.melee
	sw = arena_enemy(main, "s")
	solo(main, sw)
	sw.process_mode = Node.PROCESS_MODE_DISABLED
	await place(p, 0.0, 3.0)
	put_enemy(sw, Vector3(0, 0, 1.4), PI)
	sw.data = sw.data.duplicate()
	sw.data.block_chance = 1.0
	sw._enter(Enemy.State.COMBAT)
	sw.player = p
	var hp1 := sw.hp
	sw.take_hit({"damage": 12, "kind": "light", "stop": 0.0})
	check(sw.hp == hp1 and sw.action == "block" and m.stop_left > 0.0, "剑手挡住轻击：不掉血，玩家的剑被弹回来")
	sw.action = ""
	sw.take_hit({"damage": 22, "kind": "heavy", "stop": 0.0})
	check(sw.state == Enemy.State.STAGGER and sw.hp == hp1 - 22, "重击破防：剑手失衡并挨了这一下")
	sw.data.yield_chance = 1.0
	sw.data.block_chance = 0.0
	sw._enter(Enemy.State.COMBAT)
	sw.hp = 14
	sw.take_hit({"damage": 3, "kind": "light", "stop": 0.0})
	check(sw.state == Enemy.State.YIELD and sw.status_label.text == "求饶", "受重伤（生命 ≤ 20%%）：求饶（%s）" % sw.state_name())
	sw.take_hit({"damage": 30, "kind": "light", "stop": 0.0})
	check(sw.state == Enemy.State.DEAD and sw.collision_layer == 0 and sw.name_label.text.ends_with("（倒下）"), "生命归零：倒下，不再挡路")
	check(m.find_target() != sw, "倒下的敌人不再是攻击目标")
	var cl := arena_enemy(main, "a")
	cl.process_mode = Node.PROCESS_MODE_DISABLED
	put_enemy(cl, Vector3(2, 0, 1.4), PI)
	cl.data = cl.data.duplicate()
	cl.data.yield_chance = 0.0
	cl.player = p
	cl._enter(Enemy.State.COMBAT)
	cl.hp = 12
	cl.take_hit({"damage": 2, "kind": "light", "stop": 0.0})
	check(cl.state == Enemy.State.FLEE, "棍手受重伤：逃跑")
	cl._enter(Enemy.State.COMBAT)
	cl.hp = 50
	cl.stamina = 10.0
	cl._combat(0.016)
	check(cl.state == Enemy.State.RETREAT, "棍手体力见底：先退开")
	await free_main(main)
	# 真实出剑打敌人：没察觉的敌人挨一下立刻进入战斗
	GameState.new_game(7)
	main = await make_arena()
	p = main.player
	m = p.melee
	a = arena_enemy(main, "a")
	solo(main, a)
	put_enemy(a, Vector3(0, 0, 1.4), 0.0)
	a.waypoints = [a.global_position]
	await aim(p, Vector3(0, 0, 3.0), a.global_position + Vector3(0, 1.2, 0))
	m.press(); m.release()
	await seconds(0.5)
	m.press(); m.release()
	await seconds(0.4)
	check(a.hp == 38 and a.state in [Enemy.State.ALERT, Enemy.State.COMBAT], "从背后打没察觉的棍手：12 点，他立刻转入战斗（%s）" % a.state_name())
	# 触屏「挡」按钮、Q 键
	var t: TouchControls = main.touch
	t.visible = true
	var bc: Dictionary = t.button_centers()
	check(bc.has("guard") and t.button_at(bc.guard) == "guard" and bc.guard.distance_to(bc.attack) > TouchControls.BTN_R * 2.5, "触屏有「挡」按钮，在「攻」上方")
	a.process_mode = Node.PROCESS_MODE_DISABLED
	await seconds(0.8)
	t._input(touch_ev(4, bc.guard, true))
	await seconds(0.3)
	check(m.blocking(), "按住「挡」：举剑格挡")
	t._input(touch_ev(4, bc.guard, false))
	await seconds(0.3)
	check(not m.blocking(), "松开「挡」：放下")
	main._unhandled_input(key_ev(KEY_Q))
	await seconds(0.3)
	check(m.blocking(), "按住 Q：格挡")
	main.open_pause()
	check(not m.blocking() and not m.block_held, "打开菜单时放下格挡")
	main.close_pause()
	await seconds(0.2)
	# 倒下
	m.health = 5
	m.receive_hit({"damage": 9, "kind": "light", "attacker": null})
	check(m.down and main.defeat_panel.visible and get_tree().paused, "生命归零：「你倒下了」画面，游戏暂停")
	check(main.defeat_panel.retry_btn.text == "重来", "有「重来」按钮")
	get_tree().paused = false
	await free_main(main)


func find_button(root: Node, text: String) -> Button:
	for c in root.find_children("*", "Button", true, false):
		if (c as Button).text.strip_edges().ends_with(text) or (c as Button).text == text:
			return c
	return null


func test_inventory() -> void:
	check(GameState.validate_items(GameState.items()).is_empty(), "物品数据（data/items.json）完整：%s" % [GameState.validate_items(GameState.items())])
	check(GameState.validate_items({"x": {"name": "x", "kind": "armor", "weight": 1, "value": 1, "desc": "", "slot": "tail", "armor": 1, "noise": 0}}).size() == 1, "校验能抓出不对的部位")
	check(Enemy.validate_types(Enemy.types()).is_empty(), "敌人的掉落都在物品表里")
	GameState.new_game(3)
	check(GameState.equipped.get("weapon") == "short_sword" and GameState.equipped.get("body") == "padded_jacket" and GameState.silver == 12, "开局：短剑、棉甲外衣、12 银币")
	check(GameState.armor_total() == 3.0 and is_equal_approx(GameState.carry_weight(), 6.5) and GameState.carry_limit() == 40.0, "护甲 3、负重 6.5 / 40 斤（30 + 力量 5 × 2）")
	var main := await make_arena()
	var p: FpController = main.player
	var m: Melee = p.melee
	for e in main.get_tree().get_nodes_in_group("enemy"):
		e.process_mode = Node.PROCESS_MODE_DISABLED
	# 换武器：外观与伤害跟着变
	GameState.add_item("club")
	check(GameState.equip("club") and m.view.model == "club" and m.weapon().base == 8, "装备木棍：手里换成木棍，基础伤害 8")
	check(GameState.has_item("short_sword") and not GameState.is_equipped("short_sword"), "换下来的短剑还在背包里")
	GameState.unequip("weapon")
	var no_w := [false]
	m.no_weapon.connect(func(): no_w[0] = true)
	m.toggle_draw()
	check(no_w[0] and m.state == Melee.State.SHEATHED, "卸下武器后拔不出剑，提示去背包装备")
	GameState.equip("short_sword")
	check(m.view.model == "sword", "重新装备短剑")
	m.toggle_draw()
	await seconds(0.5)
	GameState.take_item("short_sword")
	check(m.state == Melee.State.SHEATHED and GameState.weapon_id() == "", "拿着的武器没了：自动收起，装备栏空")
	GameState.add_item("short_sword")
	GameState.equip("short_sword")
	# 护甲减伤
	var a := arena_enemy(main, "a")
	put_enemy(a, Vector3(0, 0, 1.3), PI)
	await place(p, 0.0, 2.5)
	a.player = p
	a.attack_kind = "light"
	a._strike_player()
	check(m.health == 100 - DamageCalc.compute(8, 4, 5, "light", false, 3.0) and m.health == 92, "穿棉甲（护甲 3）挨棍手一下：9 → 8（剩 %d）" % m.health)
	GameState.add_item("mail_shirt")
	GameState.equip("mail_shirt")
	check(GameState.armor_total() == 8.0 and GameState.has_item("padded_jacket") and not GameState.is_equipped("padded_jacket"), "换上锁甲衫：护甲 8，棉甲换下来")
	a._strike_player()
	check(m.health == 92 - 5, "穿锁甲挨同样一下：只掉 5（剩 %d）" % m.health)
	p.velocity = Vector3(2, 0, 0)
	check(is_equal_approx(a.player_noise(), Enemy.NOISE.walk + 2.0), "穿锁甲走路更吵：声音传 6 米")
	# 负重
	GameState.add_item("mail_shirt", 2)
	check(GameState.over_encumbered(), "背三件锁甲：超重（%.1f / 40 斤）" % GameState.carry_weight())
	Input.action_press("sprint")
	check(not p.wants_run(), "超重时按 Shift 也跑不起来")
	Input.action_release("sprint")
	GameState.take_item("mail_shirt")
	GameState.take_item("mail_shirt")
	check(not GameState.over_encumbered() and GameState.is_equipped("mail_shirt"), "扔掉两件就不超重；身上那件还穿着")
	# 背包面板
	var ip: InventoryPanel = main.inventory_panel
	main._unhandled_input(key_ev(KEY_I))
	await frames(2)
	check(ip.visible and get_tree().paused, "按 I 打开背包，游戏暂停")
	check(ip.summary.text.begins_with("护甲 8 · 负重") and ip.summary.text.contains("银币 12"), "背包顶部写护甲、负重、银币（%s）" % ip.summary.text)
	check(find_button(ip, "武器：短剑") != null and find_button(ip, "身：锁甲衫") != null and find_button(ip, "头：（空）") != null, "五个装备部位（空的写「（空）」）")
	check(find_button(ip, "棉甲外衣") != null and find_button(ip, "木棍") != null, "随身物品按种类列出")
	find_button(ip, "棉甲外衣").pressed.emit()
	await frames(1)
	check(ip.detail.text.contains("身部 · 护甲 3") and find_button(ip, "装备") != null, "选中一件看说明，有「装备」按钮")
	find_button(ip, "装备").pressed.emit()
	await frames(1)
	check(GameState.equipped.body == "padded_jacket" and ip.summary.text.begins_with("护甲 3"), "在背包里换回棉甲外衣")
	m.health = 50
	GameState.add_item("bread")
	ip.selected = "bread"
	ip.refresh()
	find_button(ip, "使用").pressed.emit()
	await frames(1)
	check(m.health == 60 and not GameState.has_item("bread"), "吃面包：生命 50 → 60，面包没了")
	var rect: Rect2 = ip.f.panel.get_global_rect()
	check(rect.size.x <= main.hud.size.x and rect.size.y <= main.hud.size.y + 1.0, "背包面板不超出画面（%s）" % rect.size)
	main._unhandled_input(key_ev(KEY_I))
	ip._unhandled_input(key_ev(KEY_I))
	await frames(2)
	check(not ip.visible and not get_tree().paused, "再按 I 关上背包")
	main.hud.bag_pressed.emit()
	await frames(2)
	check(ip.visible, "右上角「背包」按钮打开背包（手机用）")
	ip.close()
	await frames(2)
	# 补给箱
	var chest: LootContainer = null
	for c in main.get_tree().get_nodes_in_group("loot"):
		if c.loot_id == "arena_chest":
			chest = c
	check(chest != null and not chest.is_empty() and chest.prompt() == "打开 · 补给箱", "训练场出生点旁有补给箱")
	main.open_loot(chest)
	await frames(2)
	var lp: LootPanel = main.loot_panel
	check(lp.visible and get_tree().paused and find_button(lp, "银币 ×6") != null, "打开补给箱：搜刮面板列出银币和东西")
	var got: Array = []
	lp.took.connect(func(n): got.append_array(n))
	find_button(lp, "银币 ×6").pressed.emit()
	await frames(1)
	check(GameState.silver == 18 and got == ["6 枚银币"], "点银币：拿到 6 枚")
	var n0 := GameState.count_item("bandage")
	lp.take_everything()
	await frames(1)
	check(chest.is_empty() and GameState.count_item("bandage") == n0 + 2 and GameState.has_item("wool_trousers"), "全部拿走")
	check(chest.prompt().ends_with("（空）") and GameState.looted.has("arena_chest"), "搜空后提示「（空）」，记进存档数据")
	check(lp.take_all_btn.disabled, "空了「全部拿走」按钮变灰")
	lp.close()
	await frames(2)
	check(not get_tree().paused, "关上搜刮面板继续游戏")
	# 搜刮倒下的敌人
	a.take_hit({"damage": 999, "kind": "heavy", "stop": 0.0})
	await frames(2)
	var corpse: LootContainer = null
	for c in main.get_tree().get_nodes_in_group("loot"):
		if c.loot_id == "loot:a":
			corpse = c
	check(corpse != null and corpse.corpse and corpse.verb_now() == "搜刮", "敌人倒下的地方可以搜刮")
	check(corpse != null and corpse.contents().items == ["club", "bread", "dice"] and corpse.contents().silver == 4, "棍手身上：木棍、面包、骨骰子、4 枚银币")
	var sw := arena_enemy(main, "s")
	sw.take_hit({"damage": 999, "kind": "heavy", "stop": 0.0})
	await frames(2)
	await free_main(main)
	# 霜渡镇：小广场的破木箱，机位 6 对准它按 E
	GameState.new_game(3)
	main = await make_main(false)
	main.set_view(6)
	await physics(6)
	main.player.interactor.refresh()
	var tgt = main.player.interactor.target
	check(tgt is LootContainer and tgt.display_name == "破木箱", "霜渡镇机位 6：对准小广场的破木箱")
	main.player.interactor.use()
	await frames(2)
	check(main.loot_panel.visible and find_button(main.loot_panel, "绷带（消耗品 · 0.1 斤）") != null, "按 E 打开破木箱：里面有绷带")
	main.loot_panel.close()
	await free_main(main)
	# 银币条件与付钱（更夫的消息要 5 银币）
	GameState.new_game(3)
	check(DialogueRunner.conds_ok([{"silver": 5}]), "身上有 12 银币：满足「至少 5 银币」")
	DialogueRunner.apply([{"pay": 5}])
	check(GameState.silver == 7, "付 5 银币后剩 7")
	GameState.silver = 3
	check(not DialogueRunner.conds_ok([{"silver": 5}]), "只有 3 银币：塞钱的选项不出现")
