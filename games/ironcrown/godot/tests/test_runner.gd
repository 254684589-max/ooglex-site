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
	dog.wait_time = 420.0
	dog.one_shot = true
	dog.timeout.connect(func():
		print("WATCHDOG TIMEOUT in group: ", current_group)
		get_tree().quit(2))
	add_child(dog)
	dog.start()
	get_tree().root.size = Vector2i(1280, 720)   # 无头模式默认窗口只有 64×64，界面与触屏测试按电脑窗口算
	Settings.set_value("third_person", false)    # 上一次测试被中断时，设置文件里可能留着第三人称（Settings 在测试开始前已经读过它）
	wipe_test_saves()
	await frames(2)
	only = Array(OS.get_cmdline_user_args())
	for g in ["boot", "ui", "move", "terrain", "look", "touch", "pause", "interact", "frostford", "perf", "dialogue", "checks", "quests", "melee", "enemies", "inventory", "growth", "saves", "areas", "chapel", "brawl", "nav", "birch", "camera", "character"]:
		if not only.is_empty() and not only.has(g):
			continue
		print("\n== %s" % g)
		current_group = g
		await call("test_" + g)
	wipe_test_saves()
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


## 测试用的存档目录（Saves 在测试里自动改到 user://test_saves/），开始和结束时清空
func wipe_test_saves() -> void:
	var d := DirAccess.open(Saves.dir)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)


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


## 直接在某个区域开一局（3.1；和网页 ?area= 一样）
func make_area(area: String) -> Node3D:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.area = area
	add_child(main)
	await frames(3)
	return main


## data/dialogue/ 下所有区域的对话文件（不带扩展名）
func dialogue_areas() -> Array:
	var out := []
	for f in DirAccess.get_files_at("res://data/dialogue"):
		if f.ends_with(".json"):
			out.append(f.get_basename())
	out.sort()
	return out


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
	# 角色（2.7）：属性、技能、专长、势力与面板文字
	var pd := GameState.progression()
	for k in pd.attributes:
		texts.append(str(pd.attributes[k].name) + str(pd.attributes[k].desc))
	for k in pd.skills:
		texts.append(str(pd.skills[k].name) + str(pd.skills[k].desc))
		for pk in pd.skills[k].perks:
			texts.append(str(pk.name) + str(pk.desc))
	for k in pd.factions:
		texts.append(str(pd.factions[k].name))
	texts.append_array([main.hud.TITLE_SHORT, "角色等级再提升次技能升级可分配属性点＋给加 1 点生命上限体力上限负重上限护甲技能（用什么涨什么）◆◇「」（到解锁）声望敌视冷淡中立友善信任（+-）■□｜",
		"↑↓◆ 解锁专长：·▲ 升到级：获得 1 个属性点（点「角色」分配按 K 分配）声望上升下降"])
	# 第三人称（2.9）
	texts.append("视角：第三人称（越肩）第一人称" + main.pause_menu.tp_check.text)
	# 徒手格斗（3.3）
	texts.append_array([Birch.TEACH_DESKTOP, Birch.TEACH_TOUCH, "（求饶）"])     # 桦林（3.5）
	texts.append_array([main.HINT_BRAWL_DESKTOP, main.HINT_BRAWL_TOUCH, "先把这一架打完。✓ 认输了。× 你被打倒了。（生命 ）◆ 和徒手打一架", str(Melee.FISTS.name)])
	# 存档（2.8）
	texts.append_array(Saves.SLOT_NAMES.values() + Saves.SCENE_NAMES.values())
	texts.append("存档 / 读档覆盖存到这里读取（空）（损坏，读不了：）存在这台设备的浏览器里；清除浏览器数据会把存档一起清掉。✓ 已存档：× 没有存档：读不了已读取：有存档：点「菜单」，按 Esc 打开菜单，里「存档 / 读档」可以继续（F9 读快速存档）级游戏时间分钟读取最近的存档重新开始附近有敌人在和你打，不能存档你已经倒下了这一份存档坏了已退回上一份存档内容损坏（不是有效的 JSON）这是更新版本的游戏写的存档写不进浏览器存储（可能是无痕模式或空间满了）")
	texts.append(main.pause_menu.help_label.text + main.pause_menu.saves_btn.text)
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
	# 全部对话台词与选项（2.1；3.1 起每个区域一个对话文件，全都查）
	for darea in dialogue_areas():
		var dlg := DialogueRunner.load_file(darea)
		for did in dlg:
			if did.begins_with("_"):
				continue
			texts.append(str(dlg[did].speaker))
			for nid in dlg[did].nodes:
				texts.append(str(dlg[did].nodes[nid].text))
				for o in dlg[did].nodes[nid].options:
					texts.append(str(o.text))
	# 测试场、霜渡镇、酒馆都要查（1.5 发现：只查测试场，漏掉了霜渡镇领主宅邸大门上「宅邸」的「邸」）
	var town := await make_main(false)
	var inn := await make_area("tavern")
	var yard := await make_area("churchyard")
	var nave := await make_area("chapel")
	var woods := await make_area("birch")
	var nodes: Array = main.find_children("*", "", true, false) + town.find_children("*", "", true, false) + inn.find_children("*", "", true, false) \
		+ yard.find_children("*", "", true, false) + nave.find_children("*", "", true, false) + woods.find_children("*", "", true, false)
	for n in nodes:
		if n is Interactable:
			texts.append(n.prompt())
			if n is Door:
				texts.append(n.locked_text)
	for n in nodes:
		if n is Label or n is Label3D or n is Button:
			texts.append(n.text)
	town.queue_free()
	inn.queue_free()
	yard.queue_free()
	nave.queue_free()
	woods.queue_free()
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
	# 让屏幕中心（相机的视线）对准目标；第三人称时相机在头侧后方、跟着转，要迭代几次才对得准
	for i in (4 if p.third_person else 1):
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
	check(doors.size() == 2, "两扇锁着的门：民居、领主宅邸（%d；酒馆 3.1 起能进去）" % doors.size())
	var tavern_door := main.find_children("*", "Door", true, false).filter(func(d): return d.to_area == "tavern")
	check(tavern_door.size() == 1 and not tavern_door[0].locked and tavern_door[0].prompt() == "进入 · 「倒钩鱼」酒馆", "酒馆的门通往酒馆内部（3.1）")
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
	# 数据：每个区域的对话都通过校验（3.1 起不止霜渡镇）
	var bad := []
	var areas := dialogue_areas()
	for darea in areas:
		var all := DialogueRunner.load_file(darea)
		for did in all:
			if did.begins_with("_"):
				continue
			for e in DialogueRunner.validate(all[did]):
				bad.append("%s/%s：%s" % [darea, did, e])
	check(areas.has("frostford") and areas.has("tavern") and bad.is_empty(), "所有区域的对话（%s）全部通过校验：节点都走得到、选项都指向存在的节点、能结束（问题：%s）" % [", ".join(areas), str(bad)])
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
		GameState.skills.speech = 10          # 检定会练技能（2.7），这里只测掷骰分布，每次复原
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
	var text := ""
	for darea in dialogue_areas():
		text += FileAccess.get_file_as_string("res://data/dialogue/%s.json" % darea)
	var unused := []
	for f in reg:
		# 打架的输赢旗标（3.3）写在 brawl 效果的 win / lose 上
		if not f.begins_with("_") and not text.contains('"set": "%s"' % f) and not text.contains('"win": "%s"' % f) and not text.contains('"lose": "%s"' % f):
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
			var need := str(q.stages[st].get("advance_when", {}).get("clue", ""))
			if need != "" and not qd.clues.has(need):
				bad.append("%s/%s 等的线索 %s 不存在" % [qid, st, need])
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
		var expect := DamageCalc.compute(10.0, GameState.strength, int(GameState.skills.blade), "light", true)
		check(hp0 - a.hp == expect and expect >= 24, "失衡时挨一记轻击：伤害加倍（剑术 %d：%d，实际 %d）" % [GameState.skills.blade, expect, hp0 - a.hp])
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
	wipe_test_saves()
	m.health = 5
	m.receive_hit({"damage": 9, "kind": "light", "attacker": null})
	check(m.down and main.defeat_panel.visible and get_tree().paused, "生命归零：「你倒下了」画面，游戏暂停")
	check(main.defeat_panel.retry_btn.text == "重新开始", "没有存档时按钮是「重新开始」")
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
	check(m.unarmed() and m.view.model == "fists" and m.weapon_skill() == "brawl", "卸下武器：手里是拳头，用格斗技能（3.3）")
	m.toggle_draw()
	await seconds(0.45)
	check(m.state == Melee.State.IDLE and m.view.visible, "空手按 R：举起拳头（3.3；以前是提示去背包装备）")
	GameState.equip("short_sword")
	check(m.view.model == "sword" and m.state == Melee.State.SHEATHED, "重新装备短剑：拳头放下，换回剑（再按一次拔剑）")
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


func test_growth() -> void:
	check(GameState.validate_progression(GameState.progression()).is_empty(), "成长数据（data/progression.json）完整：%s" % [GameState.validate_progression(GameState.progression())])
	var bad := GameState.progression().duplicate(true)
	bad.skills.blade.perks.append({"at": 30, "name": "x", "desc": "x", "effect": "fly"})
	check(GameState.validate_progression(bad).size() >= 2, "校验能抓出不对的门槛和不在白名单里的专长效果")
	GameState.new_game(5)
	check(GameState.strength == 5 and GameState.agility == 5 and GameState.constitution == 5 and GameState.wits == 3, "开局属性：力量 5、敏捷 5、体魄 5、机敏 3")
	check(GameState.skills.blade == 15 and GameState.skills.stealth == 5 and GameState.skills.size() == 8, "八项技能，剑术 15")
	check(GameState.get_rep("valen") == 10 and GameState.get_rep("outlaws") == -20 and GameState.rep.size() == 8, "八个势力：瓦伦家 +10（你的雇主）、无旗者 −20")
	# 用什么涨什么
	var ups: Array = []
	GameState.skill_up.connect(func(sk, v): ups.append([sk, v]))
	GameState.train("blade", 4.9)
	check(GameState.skills.blade == 15 and is_equal_approx(GameState.skill_progress("blade"), 0.98), "剑术 15 → 16 要 5 点进度（2 + 15 × 0.2）")
	GameState.train("blade", 0.1)
	check(GameState.skills.blade == 16 and ups.back() == ["blade", 16], "攒够了：剑术升到 16")
	var lv: Array = []
	GameState.level_up.connect(func(l): lv.append(l))
	GameState.train("survival", 100.0)
	check(GameState.skill_ups >= 10 and GameState.level >= 2 and GameState.attr_points == GameState.level - 1 and lv.size() == GameState.level - 1, "技能累计提升 10 次升一级、得 1 个属性点（现在 %d 级）" % GameState.level)
	# 属性
	GameState.attr_points = 1
	check(GameState.raise_attr("constitution") and GameState.constitution == 6 and GameState.health_max() == 104 and GameState.stamina_max() == 104.0, "加 1 点体魄：生命、体力上限各 +4")
	check(not GameState.raise_attr("agility"), "没有属性点就加不了")
	GameState.agility = 7
	check(is_equal_approx(GameState.stamina_regen_mult(), 1.1), "敏捷 7：体力恢复快 10%")
	# 专长
	GameState.new_game(5)
	var perks: Array = []
	GameState.perk_unlocked.connect(func(sk, pk): perks.append(pk.name))
	GameState.skills.blade = 24
	GameState.train("blade", GameState.skill_need(24))
	check(GameState.skills.blade == 25 and perks == ["连环"] and GameState.has_perk("blade", "combo3"), "剑术到 25：解锁「连环」")
	GameState.skills.insight = 25
	check(GameState.check_value("insight") == 25 + 6 + 5, "洞察到 25「察言」：洞察检定 +5")
	GameState.skills.survival = 50
	check(GameState.carry_limit() == 50.0, "生存 25「背夫」：负重上限 +10")
	var main := await make_arena()
	var p: FpController = main.player
	var m: Melee = p.melee
	for e in main.get_tree().get_nodes_in_group("enemy"):
		e.process_mode = Node.PROCESS_MODE_DISABLED
	check(m.combo_max() == 3, "剑术 25：轻击可以连三段")
	var chest: LootContainer = null
	for c in main.get_tree().get_nodes_in_group("loot"):
		if c.loot_id == "arena_chest":
			chest = c
	var s0 := GameState.silver
	chest.take(-1)
	check(GameState.silver == s0 + 8, "生存 50「搜刮老手」：补给箱 6 枚银币多拿 2 枚")
	var sv0 := float(GameState.skill_xp.get("survival", 0.0))
	chest.take(0)
	check(float(GameState.skill_xp.get("survival", 0.0)) > sv0, "搜刮一件东西：生存涨进度")
	# 反击（剑术 50）与定心（剑术 75）
	GameState.skills.blade = 50
	var a := arena_enemy(main, "a")
	a.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE     # 冻住思考但留着碰撞：停了处理的物理体默认会从物理世界里拿掉，剑就砍不到
	await place(p, 0.0, 3.0)
	put_enemy(a, Vector3(0, 0, 1.5), PI)
	m.block_press()
	await seconds(0.5)
	check(m.perfect_window() == Melee.PERFECT_WINDOW, "剑术 50：完美格挡时机还是 0.2 秒")
	m.block_release()
	m.block_press()
	await frames(2)
	m.receive_hit({"damage": 10, "kind": "light", "attacker": a})
	check(m.counter_ready, "剑术 50「反击」：完美格挡后记下一次反击")
	m.block_release()
	await seconds(0.3)
	var kinds: Array = []
	m.swung.connect(func(k): kinds.append(k))
	m.press()
	m.release()
	check(kinds == ["heavy"] and not m.counter_ready, "反击：点一下也是重击")
	await seconds(0.8)
	GameState.skills.blade = 75
	check(m.perfect_window() == 0.3, "剑术 75「定心」：完美格挡时机放宽到 0.3 秒")
	# 命中练技能：打木桩一半、打人全额；钝器用木棍
	GameState.skills.blade = 30
	GameState.skill_xp.blade = 0.0
	a.data = a.data.duplicate()
	a.data.block_chance = 0.0
	a.hp = 50
	await aim(p, Vector3(0, 0, 3.0), a.global_position + Vector3(0, 1.2, 0))
	m.press()
	m.release()
	await seconds(0.5)
	check(is_equal_approx(float(GameState.skill_xp.blade), Melee.TRAIN_HIT), "用剑砍中敌人：剑术涨 1 点进度（%.2f）" % float(GameState.skill_xp.blade))
	GameState.add_item("club")
	GameState.equip("club")
	check(m.weapon_skill() == "blunt" and m.combo_max() == 2, "换上木棍：用钝器技能，「连环」只对剑有效")
	GameState.skills.blunt = 25
	a.hp = 50
	a._enter(Enemy.State.COMBAT)
	await seconds(0.6)
	var hp0 := a.hp
	m.press()
	await seconds(0.45)
	m.release()
	await seconds(0.3)
	check(a.state == Enemy.State.STAGGER and a.hp < hp0, "钝器 25「震骨」：木棍重击打中让对方失衡（%s，%d → %d）" % [a.state_name(), hp0, a.hp])
	check(float(GameState.skill_xp.get("blunt", 0.0)) > 0.0, "用木棍打中：钝器涨进度")
	await seconds(0.9)
	# 轻步（潜行 25）：被察觉得慢
	GameState.equip("short_sword")
	a.state = Enemy.State.PATROL
	a.suspicion = 0.0
	put_enemy(a, Vector3(0, 0, -2), PI)
	await place(p, 0.0, 3.0)
	a._perceive(0.1)
	var plain := a.suspicion
	a.suspicion = 0.0
	GameState.skills.stealth = 25
	a._perceive(0.1)
	check(plain > 0.0 and is_equal_approx(a.suspicion, plain * 0.7), "潜行 25「轻步」：敌人察觉的速度降低三成")
	# 蹲着在没察觉你的敌人旁边走：潜行涨
	GameState.skills.stealth = 5
	GameState.skill_xp.stealth = 0.0
	a.state = Enemy.State.PATROL
	p.crouch_wanted = true
	await physics(10)
	await hold("move_left", 1.0)
	check(float(GameState.skill_xp.get("stealth", 0.0)) > 0.3, "蹲着在没察觉你的敌人附近走动：潜行涨进度（%.2f）" % float(GameState.skill_xp.get("stealth", 0.0)))
	p.crouch_wanted = false
	# 声望
	var reps: Array = []
	GameState.rep_changed.connect(func(f, d, v): reps.append([f, d, v]))
	a.take_hit({"damage": 999, "kind": "heavy", "stop": 0.0})
	await frames(2)
	check(GameState.get_rep("outlaws") == -25 and reps.back() == ["outlaws", -5, -25], "杀了一个无旗者：无旗者声望 −5")
	check(main.hud.toast_label.text.contains("无旗者 · 声望下降 ↓（冷淡）"), "屏幕提示「无旗者 · 声望下降 ▼（冷淡）」（%s）" % main.hud.toast_label.text)
	GameState.change_rep("valen", 500)
	check(GameState.get_rep("valen") == 100, "声望最高 100")
	check([GameState.rep_tier(-60), GameState.rep_tier(-20), GameState.rep_tier(0), GameState.rep_tier(20), GameState.rep_tier(60)] == ["敌视", "冷淡", "中立", "友善", "信任"], "声望五档：敌视 / 冷淡 / 中立 / 友善 / 信任")
	# 角色面板
	GameState.attr_points = 1
	var cp: CharacterPanel = main.char_panel
	main._unhandled_input(key_ev(KEY_K))
	await frames(2)
	check(cp.visible and get_tree().paused and cp.header.text.contains("可分配属性点 1"), "按 K 打开角色面板，写着可分配的属性点（%s）" % cp.header.text)
	var plus := find_button(cp, "＋")
	check(plus != null, "有属性点时属性旁出现「＋」")
	var str0 := GameState.strength
	plus.pressed.emit()
	await frames(1)
	check(GameState.strength == str0 + 1 and GameState.attr_points == 0 and find_button(cp, "＋") == null, "点「＋」给力量加 1，点数用完「＋」消失")
	var all_text := "\n".join(cp.box.find_children("*", "Label", true, false).map(func(l): return l.text))
	check(all_text.contains("◆ 25「连环」") and all_text.contains("◇ 25「轻步」") or all_text.contains("◆ 25「轻步」"), "专长写明解锁了没有（◆ / ◇）")
	check(all_text.contains("瓦伦家　信任（+100）") and all_text.contains("渡工行会　中立（+0）"), "声望列出八个势力的档位与数值")
	var rect: Rect2 = cp.f.panel.get_global_rect()
	check(rect.size.x <= main.hud.size.x and rect.size.y <= main.hud.size.y + 1.0, "角色面板不超出画面（%s）" % rect.size)
	cp._unhandled_input(key_ev(KEY_K))
	await frames(2)
	check(not cp.visible and not get_tree().paused, "再按 K 关上")
	main.hud.char_pressed.emit()
	await frames(2)
	check(cp.visible, "右上角「角色」按钮打开（手机用）")
	cp.close()
	await frames(1)
	# 窄屏标题
	var hud: Hud = main.hud
	hud.size = Vector2(480, 900)
	hud._layout()
	check(hud.title_label.text == Hud.TITLE_SHORT and hud.title_label.get_minimum_size().x + 16.0 < hud.char_btn.position.x, "窄屏：标题缩短，不和右上角四个按钮重叠")
	hud.size = Vector2(1280, 720)
	hud._layout()
	check(hud.title_label.text == Hud.TITLE, "宽屏：完整标题")
	await free_main(main)
	# 检定练技能、对话改声望
	GameState.new_game(5)
	GameState.check("grow_a", "insight", 12)
	check(float(GameState.skill_xp.get("insight", 0.0)) in [1.0, 3.0], "做一次洞察检定：洞察涨进度（成功 3、失败 1）")
	check(DialogueRunner.conds_ok([{"rep": "valen", "at_least": 10}]) and not DialogueRunner.conds_ok([{"rep": "valen", "at_least": 11}]), "对话条件：声望至少多少")
	var r := DialogueRunner.new()
	r.start("frostford", "steward")
	r.choose(0)
	check(GameState.quest_active("edric_missing") and GameState.get_rep("valen") == 15, "接下管家的委托：瓦伦家声望 +5")


## 把 main 的「读档后重新载入场景」接到测试里：释放旧的 main、建新的
func reload_main(main: Node3D, test_range := false) -> Node3D:
	var scene: String = GameState.pending_load.get("scene", "frostford")
	await free_main(main)
	if scene == "arena":
		return await make_arena()
	return await make_main(scene == "test_range" or test_range)


func test_saves() -> void:
	wipe_test_saves()                      # 前面几组里接任务会触发自动存档
	check(Saves.dir == "user://test_saves/", "自动化测试用单独的存档目录，不碰真正的存档")
	check(not Saves.has_any() and Saves.latest_slot() == "", "开始时没有存档")
	# 校验
	var good := {"version": Saves.VERSION, "saved_at": "2026-10-02T10:00:00Z", "scene": "frostford", "player": {"pos": [0, 0, 6]}, "state": {"seed": 1, "inventory": []}}
	check(Saves.check_save(good) == "", "完整的存档通过校验")
	check(Saves.check_save({"scene": "frostford"}).contains("版本号"), "缺版本号：不认")
	var future := good.duplicate(true)
	future.version = Saves.VERSION + 1
	check(Saves.check_save(future).contains("更新版本"), "更新版本写的存档：说明读不了")
	var no_player := good.duplicate(true)
	no_player.erase("player")
	check(not Saves.write_slot("slot2", no_player) and Saves.read_slot("slot2").is_empty(), "内容不完整的存档不写入")
	# 存一份：霜渡镇里改一些状态
	GameState.new_game(11)
	var main := await make_main(false)
	var p: FpController = main.player
	GameState.set_flag("heard_edric_to_ferry")
	GameState.start_quest("edric_missing")
	GameState.add_clue("ferry")
	GameState.add_item("bandage", 2)
	GameState.add_silver(5)
	GameState.skills.speech = 22
	GameState.skill_xp.speech = 1.5
	GameState.change_rep("valen", 7)
	GameState.check("save_chk", "insight", 12)
	var chk: bool = GameState.checks.save_chk
	main.set_view(6)
	await physics(6)
	main.player.interactor.refresh()
	(main.player.interactor.target as LootContainer).take(-1)
	var bread_node: Node = null
	for c in main.world.get_children():
		if c is Pickup and c.pickup_id == "frostford_bread":
			bread_node = c
	bread_node.interact(p)
	await frames(2)
	await place(p, -2.0, -12.0)
	p.rotation.y = 0.7
	p.melee.health = 63
	var before: Dictionary = JSON.parse_string(JSON.stringify(GameState.to_dict()))
	check(main.save_game("slot1"), "存到栏位 1")
	check(Saves.read_slot("slot1").has("data") and Saves.has_any(), "栏位 1 读得出来")
	# 读档回来
	GameState.new_game(99)
	GameState.silver = 0
	var reloads := [0]
	main.reload_requested.connect(func(): reloads[0] += 1)
	check(main.load_game("slot1") and reloads[0] == 1, "读栏位 1：重新载入场景")
	var after: Dictionary = JSON.parse_string(JSON.stringify(GameState.to_dict()))
	check(after.hash() == before.hash() or JSON.stringify(after) == JSON.stringify(before), "游戏状态原样读回（旗标、任务、线索、背包、银币、技能、声望、检定、搜刮、拾取）")
	check(GameState.seed_value == 11 and GameState.checks.save_chk == chk and GameState.silver == 12 + 5 + 3, "检定种子和结果、银币都对（%d）" % GameState.silver)
	check(GameState.skills.speech == 22 and typeof(GameState.skills.speech) == TYPE_INT and GameState.get_rep("valen") == 17, "技能是整数、声望对")
	main = await reload_main(main)
	p = main.player
	check(p.global_position.distance_to(Vector3(-2, 0.05, -12)) < 0.3 and absf(p.rotation.y - 0.7) < 0.01, "读档后站在存档时的位置、朝向（%s）" % p.global_position)
	check(p.melee.health == 63, "生命也读回来了（63）")
	var still_bread: bool = main.world.get_children().any(func(c): return c is Pickup and c.pickup_id == "frostford_bread")
	check(not still_bread, "捡走的面包读档后不再出现")
	var crate: LootContainer = main.get_tree().get_nodes_in_group("loot").filter(func(c): return c.loot_id == "frostford_crate")[0]
	check(int(crate.contents().silver) == 0 and (crate.contents().items as Array).size() == 2, "破木箱里拿走的银币没有回来")
	check(main.hud.toast_label.text.contains("已读取：栏位 1"), "读档后提示「已读取：栏位 1」")
	# 当前 + 上一份；坏档退回上一份
	GameState.add_silver(1)
	check(main.save_game("slot1", true), "再存一次栏位 1")
	check(Saves.read_slot("slot1").data.state.silver == 21, "当前这份是新的")
	Saves._write_raw(Saves._key("slot1"), "{坏掉的数据")
	var r := Saves.read_slot("slot1")
	check(r.has("data") and int(r.data.state.silver) == 20 and r.note.contains("已退回上一份"), "当前这份坏了：退回上一份并说明（%s）" % r.get("note", ""))
	Saves._write_raw(Saves._key("slot1") + ".prev", "也坏了")
	r = Saves.read_slot("slot1")
	check(r.has("error") and not r.has("data"), "两份都坏了：报错，不给空数据")
	check(not main.load_game("slot1") and main.hud.toast_label.text.contains("读不了"), "读坏档：提示读不了，不重新载入")
	check(main.save_game("slot1", true) and Saves.read_slot("slot1").has("data"), "坏档的栏位可以重新存")
	# 版本迁移
	var old := good.duplicate(true)
	old.version = 0
	old.erase("scene")
	Saves._write_raw(Saves._key("slot3"), JSON.stringify(old))
	check(Saves.read_slot("slot3").has("error"), "没有迁移办法的旧版本：读不了")
	Saves.migrations[0] = func(d: Dictionary) -> Dictionary:
		d["scene"] = "frostford"
		return d
	r = Saves.read_slot("slot3")
	check(r.has("data") and r.data.version == Saves.VERSION and r.data.scene == "frostford", "有迁移办法：逐版本升到当前版本再读")
	Saves.migrations.clear()
	Saves._write_raw(Saves._key("slot3"), JSON.stringify(future))
	check(Saves.read_slot("slot3").get("error", "").contains("更新版本"), "栏位里是更新版本的存档：说明读不了")
	Saves.delete_slot("slot3")
	# 快速存档 / 读档、最近一份
	main._unhandled_input(key_ev(KEY_F8))
	check(Saves.read_slot("quick").has("data"), "F8 快速存档")
	check(Saves.latest_slot() in ["quick", "slot1"], "最近一份存档（%s）" % Saves.latest_slot())
	var rl := [0]
	main.reload_requested.connect(func(): rl[0] += 1)
	main._unhandled_input(key_ev(KEY_F9))
	await frames(1)
	check(rl[0] == 1 and GameState.pending_load.get("slot") == "quick", "F9 读快速存档")
	main = await reload_main(main)
	# 自动存档：接任务时
	Saves.delete_slot("auto")
	GameState.new_game(12)
	var dr := DialogueRunner.new()
	dr.start("frostford", "steward")
	dr.choose(0)
	await frames(3)
	check(Saves.read_slot("auto").has("data") and Saves.read_slot("auto").data.state.quests.has("edric_missing"), "接下主线时自动存档")
	# 存档面板
	main.open_pause()
	main.pause_menu.saves_requested.emit()
	await frames(2)
	var sp: SavePanel = main.save_panel
	check(sp.visible and find_button(sp, "覆盖") != null and find_button(sp, "存到这里") != null, "暂停菜单「存档 / 读档」：栏位 1 写「覆盖」、空栏位写「存到这里」")
	var labels: Array = sp.box.get_children().filter(func(c): return c is Label).map(func(l): return l.text)
	check(labels.any(func(t): return t.begins_with("自动存档") and t.contains("霜渡镇")), "自动存档一行写着场景（%s）" % [labels])
	find_button(sp, "存到这里").pressed.emit()
	await frames(1)
	check(Saves.read_slot("slot2").has("data"), "点「存到这里」存进栏位 2")
	var rect: Rect2 = sp.f.panel.get_global_rect()
	check(rect.size.x <= main.hud.size.x and rect.size.y <= main.hud.size.y + 1.0, "存档面板不超出画面")
	sp.close()
	main.close_pause()
	await free_main(main)
	# 训练场：战斗中不能存；倒下的敌人读档后还是倒下的
	GameState.new_game(13)
	main = await make_arena()
	var a := arena_enemy(main, "a")
	solo(main, a)
	await place(main.player, 0.0, 3.0)
	put_enemy(a, Vector3(0, 0, 1.5), PI)
	a.alert(false)
	await physics(2)
	check(main.can_save() != "" and not main.save_game("slot3"), "敌人在和你打的时候不能存档")
	var rep0 := 0
	a.take_hit({"damage": 999, "kind": "heavy", "stop": 0.0})
	await frames(2)
	rep0 = GameState.get_rep("outlaws")
	var corpse_pos := a.global_position
	(main.get_tree().get_nodes_in_group("loot").filter(func(c): return c.loot_id == "loot:a")[0] as LootContainer).take(0)
	check(main.save_game("slot3"), "敌人倒下以后可以存档")
	main.load_game("slot3")
	main = await reload_main(main)
	await frames(3)
	a = arena_enemy(main, "a")
	check(a.state == Enemy.State.DEAD and a.collision_layer == 0 and a.global_position.distance_to(corpse_pos) < 0.2, "读档后倒下的敌人还倒在原地")
	var corpses: Array = main.get_tree().get_nodes_in_group("loot").filter(func(c): return c.loot_id == "loot:a")
	check(corpses.size() == 1 and corpses[0].contents().items == ["bread", "dice"], "尸体上拿走的木棍没有回来")
	check(GameState.get_rep("outlaws") == rep0, "读档恢复倒下的敌人不会再扣一次声望")
	# 倒下：有存档时「读取最近的存档」
	main.player.melee.health = 3
	main.player.melee.receive_hit({"damage": 9, "kind": "light", "attacker": null})
	check(main.defeat_panel.visible and main.defeat_panel.retry_btn.text == "读取最近的存档", "倒下时有存档：按钮是「读取最近的存档」")
	var rr := [0]
	main.reload_requested.connect(func(): rr[0] += 1)
	main.defeat_panel.retry_btn.pressed.emit()
	await frames(1)
	check(rr[0] == 1 and GameState.pending_load.has("slot"), "点一下读最近的存档")
	GameState.pending_load = {}
	get_tree().paused = false
	await free_main(main)
	# 设置也会保存
	Settings.set_value("fov", 90)
	check(int(Saves.load_settings().get("fov", 0)) == 90, "改了视野角马上存进浏览器")
	Settings.set_value("quality", "high")
	check(Saves.load_settings().get("quality") == "high", "选过的画质也记住")
	Settings.set_value("fov", 75)
	Settings.set_value("quality", "")
	GameState.new_game(1)


func test_camera() -> void:
	Settings.set_value("third_person", false)
	GameState.new_game(21)
	var main := await make_main(true)
	var p: FpController = main.player
	var m: Melee = p.melee
	check(not p.third_person and not p.avatar.visible and p.camera.position.length() < 0.1, "默认第一人称：看不到自己的身体")
	main._unhandled_input(key_ev(KEY_V))
	await physics(90)
	check(Settings.third_person and p.third_person and p.avatar.visible, "按 V 切到第三人称：看得到人物")
	check(p.avatar.character != null and p.avatar.character.loaded, "第一次切到第三人称时才加载人物模型与动作库")
	check(not m.view.mesh_node.visible, "第三人称时藏起第一人称的武器")
	check(Saves.load_settings().get("third_person") == true, "视角设置存进浏览器，下次打开还是第三人称")
	var want := Vector3(FpController.TP_SIDE, FpController.TP_UP, FpController.TP_DIST).length()
	check(absf(p.camera.position.length() - want) < 0.1 and p.camera.position.z > 2.0 and p.camera.position.x > 0.3, "空旷处：相机在头部后方偏右（越肩，%.2f 米）" % p.camera.position.length())
	check(p.camera.global_position.distance_to(p.aim_origin()) > 2.0, "瞄准起点仍是眼睛，不是相机")
	# 身后有墙：相机往前收
	await place(p, -3.0, 11.0)
	await physics(30)
	check(p.camera.position.length() < 1.2, "背靠墙：相机收到墙前面，不穿墙（%.2f 米）" % p.camera.position.length())
	# 交互：准星对准 NPC
	await aim(p, TestRange.NPC_POS + Vector3(0, 0, 2.3), TestRange.NPC_POS + Vector3(0, 1.2, 0))
	await physics(20)
	p.interactor.refresh()
	check(p.interactor.target is Npc, "第三人称对准灰盒路人：能交谈（%s）" % p.interactor.target)
	await aim(p, TestRange.NPC_POS + Vector3(0, 0, 4.0), TestRange.NPC_POS + Vector3(0, 1.2, 0))
	await physics(20)
	p.interactor.refresh()
	check(p.interactor.target == null, "离 NPC 4 米：相机虽然离得更近，也够不着（按眼睛算 2.5 米）")
	await place(p, TestRange.NPC_POS.x, TestRange.NPC_POS.z + 2.0)
	p.rotation.y = 0.0
	p.pitch = 0.0
	p.head.rotation.x = 0.0
	await physics(10)
	p.interactor.refresh()
	check(p.interactor.target is Npc, "正对 2 米外的 NPC（越肩视差让准星偏在旁边）：照样能交谈")
	# 出剑打木桩
	var dummy: TrainingDummy = main.world.get_children().filter(func(c): return c is TrainingDummy)[0]
	await aim(p, TestRange.DUMMY_POS + Vector3(0, 0, 1.6), TestRange.DUMMY_POS + Vector3(0, 1.2, 0))
	m.press()
	m.release()
	await seconds(0.5)
	check(m.drawn() and p.avatar.weapon_mesh.visible and p.avatar.weapon_mesh.get_parent() == p.avatar.character.grip, "拔剑：人物右手里出现剑（挂在手骨骼上）")
	var h0 := dummy.hits
	m.press()
	m.release()
	await seconds(0.6)
	check(dummy.hits == h0 + 1, "第三人称出剑也能打中木桩")
	m.block_press()
	await seconds(0.4)
	check(p.avatar.character.role == "block" and p.avatar.character.anim.get_playing_speed() == 0.0, "举剑格挡：人物举剑并停住（%s）" % p.avatar.character.role)
	m.block_release()
	p.crouch_wanted = true
	await seconds(0.6)
	check(p.avatar.character.role == "crouch_idle", "蹲下：人物换蹲姿待机（%s）" % p.avatar.character.role)
	p.crouch_wanted = false
	await seconds(0.3)
	# 菜单勾选框、触屏按钮
	check(main.pause_menu.tp_check.button_pressed, "暂停菜单里的「第三人称越肩视角」已勾上")
	var t: TouchControls = main.touch
	t.visible = true
	var bc: Dictionary = t.button_centers()
	var others := bc.keys().filter(func(k): return k != "camera")
	check(bc.has("camera") and others.all(func(k): return bc[k].distance_to(bc.camera) > TouchControls.BTN_R * 2.5), "触屏有「视角」按钮，不和其他按钮挤在一起")
	t._input(touch_ev(5, bc.camera, true))
	t._input(touch_ev(5, bc.camera, false))
	await physics(5)
	check(not Settings.third_person and not p.avatar.visible and m.view.mesh_node.visible and p.camera.position.length() < 0.1, "点「视角」切回第一人称")
	await free_main(main)
	# 下次打开页面：按保存的视角开始
	Settings.set_value("third_person", true)
	main = await make_main(true)
	check(main.player.third_person and main.player.avatar.visible, "设置里是第三人称：打开就是第三人称")
	await free_main(main)
	Settings.set_value("third_person", false)


## 人物模型与动作（路线图 A.1）：数据一致性、模型与骨架、动作真的驱动骨架、动作与近战判定对齐、角色选择
func test_character() -> void:
	# —— 数据：动作映射、动画库
	var map := CharacterModel.load_map()
	check(not map.is_empty() and map.has("roles") and map.has("clips") and map.has("attacks") and map.has("locomotion"), "动作映射文件 data/character_anims.json 能读，有 roles / clips / attacks / locomotion")
	var lib := load(CharacterModel.ANIMS) as AnimationLibrary
	check(lib != null, "动画库 ual_core.res 能加载")
	var missing: Array = []
	for c in map.clips.keys():
		if not lib.has_animation(c):
			missing.append(c)
	check(missing.is_empty(), "映射里列的 %d 个动作动画库里都有（缺：%s）" % [map.clips.size(), missing])
	check(lib.get_animation_list().size() == map.clips.size(), "动画库里没有多余的动作（只打包用到的）")
	var bad_roles: Array = []
	for r in map.roles.keys():
		if not map.clips.has(map.roles[r]):
			bad_roles.append(r)
	check(bad_roles.is_empty(), "每个角色（站、走、跑……）指向的动作都在 clips 里（%s）" % [bad_roles])
	var loops_ok := true
	for c in map.clips.keys():
		if lib.has_animation(c) and (lib.get_animation(c).loop_mode != Animation.LOOP_NONE) != bool(map.clips[c].loop):
			loops_ok = false
	check(loops_ok, "循环方式与映射一致（站走跑蹲循环，出招挨打倒下只播一遍）")
	var h: Dictionary = map.attacks.heavy
	var hl := lib.get_animation(h.clip).length
	check(0.0 < float(h.wind_peak) and float(h.wind_peak) < float(h.impact) and float(h.impact) < hl, "重击标记合理：蓄力到顶 %.2f < 命中 %.2f < 动作长 %.2f 秒" % [h.wind_peak, h.impact, hl])
	var light_ok := true
	for a in map.attacks.light:
		light_ok = light_ok and float(a.impact) > 0.0 and float(a.impact) < lib.get_animation(a.clip).length
	check(light_ok and (map.attacks.light as Array).size() == 2, "轻击两段，命中时刻都在动作长度之内")
	# 动作播放速度对齐近战判定的命中帧（改了 Melee.TIMING 之后动作不会变得离谱）
	var lt: Dictionary = Melee.TIMING.light
	var light_scale := float(CharacterModel.light_attack(map, 0).impact) / (float(lt.wind) + float(lt.strike) * float(lt.hit_at))
	var ht: Dictionary = Melee.TIMING.heavy
	var heavy_scale := (float(h.impact) - float(h.wind_peak)) / (float(ht.strike) * float(ht.hit_at))
	check(light_scale > 0.8 and light_scale < 2.2, "轻击动作播放速度 ×%.2f（0.8–2.2 内）" % light_scale)
	check(heavy_scale > 0.5 and heavy_scale < 1.8, "重击劈下的播放速度 ×%.2f（0.5–1.8 内）" % heavy_scale)
	check(CharacterModel.light_attack(map, 0).clip == "Sword_Regular_A" and CharacterModel.light_attack(map, 1).clip == "Sword_Regular_B" and CharacterModel.light_attack(map, 2).clip == "Sword_Regular_A", "轻击连击：第一段 A、第二段 B、第三段（剑术专长）回到 A")
	# 站 / 走 / 跑 / 蹲走的选择
	var pk := CharacterModel.pick_locomotion(map, 0.0, false, false)
	check(pk.role == "idle", "不动：待机")
	check(CharacterModel.pick_locomotion(map, 0.1, false, true).role == "idle_armed", "拔剑后不动：持剑待机")
	check(CharacterModel.pick_locomotion(map, 0.0, true, true).role == "crouch_idle", "蹲着不动：蹲姿待机")
	pk = CharacterModel.pick_locomotion(map, 1.5, false, false)
	check(pk.role == "walk" and pk.scale > 1.0 and pk.scale <= 1.8, "1.5 米 / 秒：走路动作加速 ×%.2f（不超过 1.8）" % pk.scale)
	pk = CharacterModel.pick_locomotion(map, FpController.RUN_SPEED, false, false)
	check(pk.role == "run" and absf(pk.scale - 1.0) < 0.15, "跑速 5.5 米 / 秒：跑步动作约 ×1（×%.2f）" % pk.scale)
	pk = CharacterModel.pick_locomotion(map, FpController.WALK_SPEED, false, false)
	check(pk.role == "run" and pk.scale >= 0.5 and pk.scale < 0.7, "步行速度 3 米 / 秒：慢跑动作放慢 ×%.2f（走路动作的周期太小，3 米 / 秒要放大 3 倍才跟得上）" % pk.scale)
	pk = CharacterModel.pick_locomotion(map, FpController.CROUCH_SPEED, true, true)
	check(pk.role == "crouch_move" and pk.scale >= 0.6 and pk.scale <= 1.8, "蹲着走：蹲走动作 ×%.2f" % pk.scale)
	# —— 模型：节点、骨架、身高、动作驱动骨架
	var cm := CharacterModel.new()
	add_child(cm)
	await frames(2)
	check(cm.loaded and cm.skeleton != null and cm.anim != null, "人物模型加载成功（节点：Model / Skeleton3D / AnimationPlayer）")
	check(cm.skeleton.get_bone_count() == 65 and cm.skeleton.find_bone("hand_r") >= 0 and cm.skeleton.find_bone("pelvis") >= 0, "骨架 65 根骨头，有 pelvis 与 hand_r")
	var unknown: Array = []
	for c in lib.get_animation_list():
		var a := lib.get_animation(c)
		for i in a.get_track_count():
			var bone := str(a.track_get_path(i)).get_slice(":", 1)
			if cm.skeleton.find_bone(bone) < 0 and not unknown.has(bone):
				unknown.append(bone)
	check(unknown.is_empty(), "所有动作用到的骨头模型骨架里都有，不用重定向（缺：%s）" % [unknown])
	var meshes := cm.scene_root.find_children("*", "MeshInstance3D", true, false)
	var tris := 0
	var body: MeshInstance3D = null
	for mi: MeshInstance3D in meshes:
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			tris += (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		if mi.name == "SuperHero_Male":
			body = mi
	check(meshes.size() == 3 and tris > 12000 and tris < 16000, "三个网格（身体、眼睛、眉毛），共 %d 个三角面（约 1.4 万）" % tris)
	var top := (body.global_transform * body.get_aabb()).end.y
	check(top > 1.7 and top < 1.95, "身高约 1.8 米，和玩家碰撞体（1.8 米）匹配（%.2f）" % top)
	var mats_ok := true
	for mi: MeshInstance3D in meshes:
		var mat := mi.get_surface_override_material(0) as StandardMaterial3D
		mats_ok = mats_ok and mat != null and mat.emission_enabled
	check(mats_ok, "三个网格都有一点自发光，背光时不会变成黑影")
	check(cm.hand != null and cm.grip != null and cm.hand.bone_name == "hand_r" and cm.hand.get_parent() == cm.skeleton, "右手骨骼上有挂点（拿剑用）")
	var rest_pose := {}
	for bn in ["upperarm_r", "lowerarm_r", "spine_02", "thigh_l"]:
		rest_pose[bn] = cm.skeleton.get_bone_pose_rotation(cm.skeleton.find_bone(bn))
	cm.hold("Sword_Attack", 0.33, 0.0)
	await frames(3)
	var turned := 0.0
	for bn in rest_pose.keys():
		turned = maxf(turned, (rest_pose[bn] as Quaternion).angle_to(cm.skeleton.get_bone_pose_rotation(cm.skeleton.find_bone(bn))))
	check(turned > 0.3, "动作真的驱动了骨架：抬剑起手时骨头从 T 姿势最多转了 %.0f°" % rad_to_deg(turned))
	cm.queue_free()
	await frames(2)
	# —— 不开第三人称：不加载模型
	Settings.set_value("third_person", false)
	GameState.new_game(22)
	var main := await make_main(true)
	check(main.player.avatar.character == null, "默认第一人称：不加载人物模型（省加载与显存）")
	await free_main(main)
	# —— 玩家的人物：站 / 走 / 跑 / 倒着走 / 侧着走 / 跳 / 蹲
	Settings.set_value("third_person", true)
	GameState.new_game(23)
	main = await make_main(true)
	var p: FpController = main.player
	var m: Melee = p.melee
	var av := p.avatar
	await place(p, 0.0, 10.0)
	await seconds(0.4)
	var c: CharacterModel = av.character
	check(c != null and c.loaded, "设置里是第三人称：开局就加载人物")
	check(c.role == "idle" and c.playing() == "Idle_Loop", "站着不动：待机动作（%s）" % c.playing())
	check(absf(c.rotation.y - PI) < 0.05, "人物模型面朝 -Z（和玩家的「向前」一致）")
	p.touch_move = Vector2(0, -0.5)
	await seconds(0.5)
	check(c.role == "walk" and c.playing() == "Walk_Loop" and c.anim.get_playing_speed() > 1.0, "半推摇杆：走路动作（加速 ×%.2f）" % c.anim.get_playing_speed())
	p.touch_move = Vector2(0, -1.0)
	await seconds(0.5)
	check(c.role == "run" and c.playing() == "Jog_Fwd_Loop" and absf(c.anim.get_playing_speed() - 1.0) < 0.25, "推到底：跑步动作（×%.2f）" % c.anim.get_playing_speed())
	await place(p, 0.0, 10.0)
	p.touch_move = Vector2(0, 0.5)
	await seconds(0.6)
	check(av.reversed and c.role == "walk" and c.anim.get_playing_speed() < 0.0, "倒着走：走路动作倒放（×%.2f），身体仍朝前" % c.anim.get_playing_speed())
	check(absf(av.face_deg) < 10.0, "倒着走时身体朝向镜头方向（偏转 %.0f°）" % av.face_deg)
	await place(p, 0.0, 10.0)
	p.touch_move = Vector2(0.5, 0)
	await seconds(0.6)
	check(not av.reversed and absf(av.face_deg - 90.0) < 10.0 and c.role == "walk", "向右侧着走：腿朝右（偏转 %.0f°）" % av.face_deg)
	p.touch_move = Vector2.ZERO
	await seconds(0.6)
	check(absf(av.face_deg) < 10.0 and c.role == "idle", "停下：身体转回朝向镜头方向")
	await place(p, 0.0, 10.0)
	p.request_jump()
	await seconds(0.35)
	check(c.role == "air" and c.playing() == "Jump_Loop", "跳起来：空中动作（%s）" % c.playing())
	await seconds(1.0)
	check(c.role == "idle", "落地：回到待机（%s）" % c.role)
	p.crouch_wanted = true
	await seconds(0.5)
	check(c.role == "crouch_idle", "蹲下：蹲姿待机")
	p.touch_move = Vector2(0, -1.0)
	await seconds(0.4)
	check(c.role == "crouch_move" and c.playing() == "Crouch_Fwd_Loop", "蹲着走：蹲走动作（%s）" % c.playing())
	p.touch_move = Vector2.ZERO
	p.crouch_wanted = false
	await seconds(0.6)
	# —— 战斗：拔剑、出招对齐命中帧、蓄力、格挡、挨打、失衡、倒下
	var dummy: TrainingDummy = main.world.get_children().filter(func(n): return n is TrainingDummy)[0]
	await aim(p, TestRange.DUMMY_POS + Vector3(0, 0, 1.6), TestRange.DUMMY_POS + Vector3(0, 1.2, 0))
	m.press()
	m.release()
	await seconds(0.6)
	check(m.drawn() and c.role == "idle_armed" and c.playing() == "Sword_Idle", "拔剑后：持剑待机（%s）" % c.playing())
	var rec: Array = []
	m.hit.connect(func(_t, _info): rec.append([c.playing(), c.anim.current_animation_position]))
	m.press()
	m.release()
	await seconds(0.3)
	check(rec.size() == 1 and rec[0][0] == "Sword_Regular_A" and absf(rec[0][1] - float(map.attacks.light[0].impact)) < 0.08, "轻击第一段：命中帧时动作正好在挥到最前（%s，第 %.2f 秒，目标 %.2f）" % [rec[0][0] if rec.size() > 0 else "-", rec[0][1] if rec.size() > 0 else -1.0, float(map.attacks.light[0].impact)])
	m.press()
	m.release()
	await seconds(0.4)
	check(rec.size() == 2 and rec[1][0] == "Sword_Regular_B" and absf(rec[1][1] - float(map.attacks.light[1].impact)) < 0.08, "轻击第二段：换成 B 动作，同样对齐命中帧（%s，第 %.2f 秒）" % [rec[1][0] if rec.size() > 1 else "-", rec[1][1] if rec.size() > 1 else -1.0])
	await seconds(0.8)
	check(m.state == Melee.State.IDLE and c.role == "idle_armed", "收招后回到持剑待机（%s）" % c.role)
	rec.clear()
	m.press()
	await seconds(0.5)
	check(m.state == Melee.State.CHARGE and c.playing() == "Sword_Attack" and c.anim.get_playing_speed() == 0.0 and absf(c.anim.current_animation_position - float(h.wind_peak)) < 0.02, "按住攻击蓄力：剑举到最高处停住（第 %.2f 秒）" % c.anim.current_animation_position)
	m.release()
	await seconds(0.5)
	check(rec.size() == 1 and rec[0][0] == "Sword_Attack" and absf(rec[0][1] - float(h.impact)) < 0.08, "重击：松手后劈下，命中帧对齐（第 %.2f 秒，目标 %.2f）" % [rec[0][1] if rec.size() > 0 else -1.0, float(h.impact)])
	await seconds(0.8)
	m.block_press()
	await seconds(0.5)
	check(m.blocking() and c.role == "block" and c.anim.get_playing_speed() == 0.0 and absf(c.anim.current_animation_position - float(map.block.hold)) < 0.03, "按住格挡：举剑停住（第 %.2f 秒）" % c.anim.current_animation_position)
	m.block_release()
	await seconds(0.6)
	check(c.role == "idle_armed", "松开格挡：回到持剑待机（%s）" % c.role)
	m.receive_hit({"damage": 4, "kind": "light", "attacker": null})
	await frames(3)
	check(c.role == "hit" and c.playing() == "Hit_Chest", "挨打（没在出招）：受击动作（%s）" % c.playing())
	await seconds(0.7)
	check(c.role == "idle_armed", "受击动作播完回到待机（%s）" % c.role)
	m.stagger_left = 0.6
	await frames(3)
	check(c.role == "stagger" and c.playing() == "Hit_Knockback", "失衡：被击退的动作（%s）" % c.playing())
	m.stagger_left = 0.0
	await seconds(0.5)
	m.health = 3
	m.receive_hit({"damage": 9, "kind": "light", "attacker": null})
	await seconds(0.5)
	check(m.down and c.role == "death" and c.playing() == "Death01", "生命归零：倒下动作（%s）" % c.playing())
	await seconds(2.2)
	check(not c.anim.is_playing() and c.anim.current_animation_position > 2.2, "倒下后停在最后一帧，不会爬起来（第 %.2f 秒）" % c.anim.current_animation_position)
	# 切回第一人称：动画停掉
	GameState.new_game(23)
	await free_main(main)
	Settings.set_value("third_person", false)


## 区域切换与「倒钩鱼」酒馆（路线图 3.1）
func test_areas() -> void:
	Settings.set_value("third_person", false)
	check(Areas.known("tavern") and Areas.is_indoor("tavern") and not Areas.is_indoor("frostford") and Saves.SCENE_NAMES.has("tavern"), "区域登记：酒馆是室内区域，存档认得它")
	check(Areas.spawn("frostford", "tavern_door") is Transform3D and Areas.spawn("tavern", "front") is Transform3D and Areas.spawn("tavern", "nowhere") == null, "两个区域都有命名出生点，名字不对返回空")
	# —— 主街：走到酒馆门口，按交互进门
	GameState.new_game(31)
	GameState.start_quest("edric_missing")
	var main := await make_main(false)
	var p: FpController = main.player
	var door: Door = main.find_children("*", "Door", true, false).filter(func(d): return d.to_area == "tavern")[0]
	var door_mid := door.global_position + door.global_transform.basis.x * 0.55 + Vector3(0, 1.1, 0)
	await aim(p, Vector3(-3.1, 0.05, -7.1), door_mid)
	check(p.interactor.target == door and p.interactor.target.prompt() == "进入 · 「倒钩鱼」酒馆", "站在酒馆门外对准门：提示「进入 · 「倒钩鱼」酒馆」（%s）" % (p.interactor.target.prompt() if p.interactor.target else "没对准"))
	p.melee.health = 77
	var rr := [0]
	main.reload_requested.connect(func(): rr[0] += 1)
	p.interactor.use()
	await seconds(0.45)
	var pend: Dictionary = GameState.pending_load
	check(rr[0] == 1 and pend.get("scene") == "tavern" and pend.get("spawn") == "front", "按交互：淡出后去酒馆（%s）" % str(pend))
	check(main.fade.color.a > 0.9, "出门前画面淡成黑色")
	check(int(pend.get("player", {}).get("health", 0)) == 77, "生命值带过去（77）")
	main = await reload_main(main)
	p = main.player
	await frames(5)
	check(main.area == "tavern" and main.scene_name() == "tavern", "换到了酒馆区域")
	check(flat(p.global_position).distance_to(Vector2(Tavern.DOOR_X, 2.6)) < 0.3 and absf(p.rotation.y) < 0.05, "站在酒馆门内的出生点、面朝大堂（%s）" % str(p.global_position))
	check(p.melee.health == 77 and main.arrived_by == "front", "生命值还是 77，记得是从门走进来的")
	check(main.hud.toast_label.text == "「倒钩鱼」酒馆" and main.hud.hint_label.text == "", "进门提示区域名，不再显示开场的操作提示")
	var auto := Saves.read_slot("auto")
	check(auto.has("data") and auto.data.scene == "tavern", "进入新区域自动存档（GDD 第十节）")
	await seconds(0.5)
	check(main.fade.color.a < 0.05, "黑屏淡出，看得见酒馆")
	check(not main.moon.visible and main.env.fog_mode == Environment.FOG_MODE_EXPONENTIAL and main.env.background_color.r < 0.1, "室内：没有月光，换成暖暗的环境光和薄烟")
	var omni := main.find_children("*", "OmniLight3D", true, false)
	var fire := omni.filter(func(l): return l is Tavern.FireLight)
	check(omni.size() == 3 and fire.size() == 1, "三盏光：炉火、吧台油灯、桌上蜡烛（%d）" % omni.size())
	var e0: float = fire[0].light_energy
	await seconds(0.2)
	check(fire[0].flicker and absf(fire[0].light_energy - e0) > 0.001, "炉火在闪")
	var npcs := main.find_children("*", "Npc", true, false).map(func(n): return n.display_name)
	check(npcs.has("玛蒂尔达") and npcs.has("伐木工") and npcs.has("货郎"), "酒馆里有玛蒂尔达、伐木工、货郎（%s）" % str(npcs))
	var room: MeshInstance3D = main.world.get_node("Tavern")
	check(room.mesh.get_surface_count() <= 7, "整间酒馆按材质合并成一个网格，%d 个表面" % room.mesh.get_surface_count())
	# 碰撞：墙、壁炉、吧台、楼梯
	await place(p, 0.5, -0.8)
	await hold("move_left", 2.5)
	check(p.global_position.x < -2.0 and p.global_position.x > -2.9, "从吧台前沿过道往西走到壁炉前，被炉台挡住、走不进火里（x = %.2f）" % p.global_position.x)
	await place(p, -0.5, 2.5)
	await hold("move_back", 2.0)
	check(p.global_position.z > 2.9 and p.global_position.z < 3.5, "往南走到墙根被南墙挡住，出不去（z = %.2f）" % p.global_position.z)
	await place(p, 0.5, -0.8)
	await hold("move_forward", 1.5)
	check(p.global_position.z > -1.85, "吧台挡着，走不到玛蒂尔达身后（z = %.2f）" % p.global_position.z)
	await place(p, 2.4, 1.5)
	await hold("move_right", 2.0)
	check(p.global_position.x < 3.05, "楼梯上不去（x = %.2f）" % p.global_position.x)
	var gate: Door = main.find_children("*", "Door", true, false).filter(func(d): return d.locked)[0]
	var r0: Dictionary = gate.interact(p)
	check(r0.get("locked", false) and str(r0.get("toast", "")).contains("客房"), "梯口的栅门锁着：玛蒂尔达说楼上客房住满了")
	# 固定机位：吧台前对准玛蒂尔达
	main.set_view(1)
	await physics(4)
	p.interactor.refresh()
	check(p.interactor.target is Npc and p.interactor.target.display_name == "玛蒂尔达", "?view=1 站在吧台前，对准玛蒂尔达能交谈")
	# —— 玛蒂尔达：付钱问出线索
	var r := DialogueRunner.new()
	GameState.new_game(31)
	GameState.start_quest("edric_missing")
	check(r.start("tavern", "matilda") and r.speaker() == "玛蒂尔达", "玛蒂尔达的对话能打开")
	var labels: Array = r.options().map(func(o): return DialogueRunner.option_label(o))
	check(labels.has("打听埃德里克少爷的事。") and labels.has("来块面包。（2 银币）"), "接了少爷的任务才能打听；有钱能买面包（%s）" % str(labels))
	var s0 := GameState.silver
	r.choose(labels.find("来块面包。（2 银币）"))
	check(GameState.silver == s0 - 2 and GameState.has_item("bread") and r.node_id == "bread", "买面包：花 2 银币，背包里多一块面包")
	r.choose(0)
	labels = r.options().map(func(o): return DialogueRunner.option_label(o))
	r.choose(labels.find("打听埃德里克少爷的事。"))
	check(r.node_id == "edric", "打听少爷：她先不肯说")
	labels = r.options().map(func(o): return DialogueRunner.option_label(o))
	s0 = GameState.silver
	r.choose(0)
	check(r.node_id == "edric_told" and GameState.silver == s0 - 5 and GameState.has_flag("matilda_paid") and GameState.clues.has("boots"), "塞 5 枚银币：她说出南方人的事，记下线索「好靴子」")
	r.choose(0)
	check(r.node_id == "edric_where" and r.text().contains("渡口"), "追问：南方人的马拴在渡口")
	check(r.start("tavern", "matilda") and r.node_id == "greet_again", "说过以后再来：换成熟客的开场")
	# 口才检定：成功 / 失败（读档刷不出别的结果）
	var sd_pass := seed_for("matilda_edric_speech", "speech", 13, true)
	var sd_fail := seed_for("matilda_edric_speech", "speech", 13, false)
	GameState.new_game(sd_pass)
	GameState.start_quest("edric_missing")
	r.start("tavern", "matilda")
	r.choose(0)
	labels = r.options().map(func(o): return DialogueRunner.option_label(o))
	var speech_i := -1
	for i in labels.size():
		if labels[i].contains("口才"):
			speech_i = i
	check(speech_i >= 0 and labels[speech_i].contains("把握"), "口才选项显示把握（%s）" % (labels[speech_i] if speech_i >= 0 else "没有"))
	r.choose(speech_i)
	check(r.node_id == "edric_told" and GameState.clues.has("boots") and GameState.silver == 12, "口才检定成功：不花钱也问出来")
	GameState.new_game(sd_fail)
	GameState.start_quest("edric_missing")
	r.start("tavern", "matilda")
	r.choose(0)
	r.choose(speech_i)
	check(r.node_id == "edric_refuse" and GameState.has_flag("matilda_refused") and not GameState.clues.has("boots"), "口才检定失败：她不肯说")
	r.choose(r.options().map(func(o): return o.text).find("好吧。"))
	r.choose(0)
	labels = r.options().map(func(o): return DialogueRunner.option_label(o))
	check(r.node_id == "edric" and not labels.any(func(l): return l.contains("口才")) and labels.any(func(l): return l.contains("银币")), "失败后不能再试口才，只剩付钱（%s）" % str(labels))
	GameState.silver = 1
	r.start("tavern", "matilda")
	labels = r.options().map(func(o): return DialogueRunner.option_label(o))
	check(not labels.has("来块面包。（2 银币）"), "钱不够：不显示买面包")
	# 伐木工：桦林边的营火；两条线索凑齐，主线推进到「去渡口」
	GameState.new_game(32)
	GameState.start_quest("edric_missing")
	r.start("tavern", "woodcutter")
	r.choose(0)
	check(GameState.clues.has("birch_fires") and GameState.has_flag("woodcutter_talked"), "伐木工说了桦林边的营火（线索）")
	r.start("tavern", "matilda")
	r.choose(0)
	r.choose(0)
	check(GameState.quest_stage("edric_missing") == "to_ferry", "两条线索凑齐：主线推进到「去渡口找少爷」")
	check(r.start("tavern", "woodcutter") and r.node_id == "asleep", "再找伐木工：他睡着了")
	# —— 出门：回到主街酒馆门外
	await place(p, Tavern.DOOR_X, 2.3)
	p.rotation.y = PI
	await physics(4)
	p.interactor.refresh()
	check(p.interactor.target is Door and p.interactor.target.prompt() == "离开 · 回到主街", "门内对准门：提示「离开 · 回到主街」")
	rr = [0]
	main.reload_requested.connect(func(): rr[0] += 1)
	p.interactor.use()
	await seconds(0.45)
	check(rr[0] == 1 and GameState.pending_load.get("scene") == "frostford" and GameState.pending_load.get("spawn") == "tavern_door", "出门：回主街")
	main = await reload_main(main)
	p = main.player
	await frames(3)
	check(main.area == "frostford" and flat(p.global_position).distance_to(Vector2(-3.1, -7.1)) < 0.3 and absf(p.rotation.y + PI / 2) < 0.05, "站在酒馆门外、背对酒馆（%s）" % str(p.global_position))
	check(main.moon.visible and main.env.fog_mode == Environment.FOG_MODE_DEPTH, "回到室外：月光与夜雾回来了")
	# —— 酒馆里存档、读档：回到酒馆同一个位置
	await free_main(main)
	main = await make_area("tavern")
	p = main.player
	await place(p, -1.0, -1.0)
	check(main.save_game("slot2", true), "酒馆里能存档")
	GameState.new_game(1)
	check(main.load_game("slot2"), "读这个存档")
	main = await reload_main(main)
	check(main.area == "tavern" and flat(main.player.global_position).distance_to(Vector2(-1.0, -1.0)) < 0.2 and main.arrived_by == "", "读档回到酒馆里同一个位置（不是门口）")
	await free_main(main)
	# —— 战斗中走不开
	main = await make_arena()
	var e: Enemy = main.get_tree().get_nodes_in_group("enemy")[0]
	e.state = Enemy.State.COMBAT
	var went: bool = await main.travel("tavern", "front")
	check(not went and GameState.pending_load.is_empty() and main.hud.toast_label.text.contains("走不开"), "有敌人和你打的时候走不进别的区域")
	e.state = Enemy.State.PATROL
	await free_main(main)
	GameState.pending_load = {}
	GameState.new_game(1)


## 星铁小教堂与墓园（路线图 3.2）
func test_chapel() -> void:
	Settings.set_value("third_person", false)
	check(Areas.known("churchyard") and Areas.known("chapel") and Areas.is_indoor("chapel") and not Areas.is_indoor("churchyard"), "两个新区域：墓园（室外）、小教堂（室内）")
	GameState.new_game(41)
	GameState.start_quest("edric_missing")
	GameState.add_item("edric_letter")
	check(GameState.clues.has("letter"), "拿到那封没写完的信：自动记下线索（物品数据里的 clue）")
	check(GameState.item("crypt_key").kind == "quest" and GameState.item("edric_letter").desc.contains("棋子"), "墓园钥匙、少爷的信是任务物品，信的内容写在物品说明里")
	# —— 主街：小路门 → 墓园
	GameState.new_game(41)
	GameState.start_quest("edric_missing")
	var main := await make_main(false)
	var p: FpController = main.player
	var lane: Door = main.find_children("*", "Door", true, false).filter(func(d): return d.to_area == "churchyard")[0]
	await aim(p, Vector3(3.3, 0.05, -27.25), lane.global_position + lane.global_transform.basis.x * 0.55 + Vector3(0, 1.1, 0))
	check(p.interactor.target == lane and lane.prompt() == "前往 · 通往星铁小教堂的小路", "主街右手边的窄巷口：对准木门提示「前往 · 通往星铁小教堂的小路」（%s）" % (p.interactor.target.prompt() if p.interactor.target else "没对准"))
	var signs := main.find_children("*", "Label3D", true, false).filter(func(l): return l.text == "星铁小教堂")
	check(signs.size() == 1, "门边挂着「星铁小教堂」的木牌")
	p.interactor.use()
	await seconds(0.45)
	check(GameState.pending_load.get("scene") == "churchyard" and GameState.pending_load.get("spawn") == "lane", "进小路：去墓园")
	main = await reload_main(main)
	p = main.player
	await frames(3)
	check(main.area == "churchyard" and flat(p.global_position).distance_to(Vector2(0, 9.4)) < 0.3 and absf(p.rotation.y) < 0.05, "站在墓园院门内、面朝小教堂（%s）" % str(p.global_position))
	check(main.moon.visible and main.env.fog_mode == Environment.FOG_MODE_DEPTH, "墓园是室外：月光与夜雾")
	var omni := main.find_children("*", "OmniLight3D", true, false)
	check(omni.size() == 3, "三盏灯：小教堂门口、守墓人的灯笼、墓室门边（%d）" % omni.size())
	var npcs := main.find_children("*", "Npc", true, false).map(func(n): return n.display_name)
	check(npcs == ["守墓人"], "墓园里有守墓人（%s）" % str(npcs))
	var stones: int = (main.world.get_node("Churchyard") as MeshInstance3D).mesh.get_surface_count()
	check(stones <= 8, "墓园的墙、路、墓碑、墓室按材质合并成一个网格（%d 个表面）" % stones)
	# 墙翻不过去
	await place(p, 0.0, 9.0)
	await hold("move_right", 3.5)
	check(p.global_position.x > 8.0 and p.global_position.x < 12.8, "往东一直走：被墓碑或东墙挡住，翻不出去（x = %.2f）" % p.global_position.x)
	await place(p, 0.0, 9.6)
	await hold("move_back", 1.5)
	check(p.global_position.z < 10.9, "院门关着：往南出不去（出门靠交互，z = %.2f）" % p.global_position.z)
	# 守墓人：把人引向墓室与修士的钥匙
	var r := DialogueRunner.new()
	check(r.start("churchyard", "gravedigger") and r.speaker() == "守墓人", "守墓人的对话能打开")
	r.choose(0)
	check(r.text().contains("墓室") and r.text().contains("修士"), "守墓人：少爷昨天在瓦伦家墓室待了好一阵，钥匙在修士那儿")
	# 墓室：没钥匙打不开
	var crypt: Door = main.find_children("*", "Door", true, false).filter(func(d): return d.key_item == "crypt_key")[0]
	main.set_view(1)
	await physics(4)
	p.interactor.refresh()
	check(p.interactor.target == crypt, "?view=1 站在墓室门前，对准铁门")
	var rr: Dictionary = crypt.interact(p)
	check(rr.get("locked", false) and crypt.locked and str(rr.get("toast", "")).contains("瓦伦"), "没有钥匙：铁门锁着，门楣上刻着「瓦伦」")
	var bundle: LootContainer = main.find_children("*", "LootContainer", true, false).filter(func(c): return c.loot_id == "valen_crypt_bundle")[0]
	check(bundle.global_position.x < Churchyard.CRYPT_FRONT_X, "少爷的包袱在墓室里面（铁门后）")
	# —— 墓园 → 小教堂
	main.set_view(3)
	await physics(4)
	p.interactor.refresh()
	check(p.interactor.target is Door and p.interactor.target.prompt() == "进入 · 星铁小教堂", "小教堂门前：提示「进入 · 星铁小教堂」")
	p.interactor.use()
	await seconds(0.45)
	main = await reload_main(main)
	p = main.player
	await frames(3)
	check(main.area == "chapel" and flat(p.global_position).distance_to(Vector2(0, 4.1)) < 0.3, "进了小教堂，站在门内")
	check(not main.moon.visible and main.find_children("*", "OmniLight3D", true, false).size() == 3, "室内：没有月光；祭坛两座烛台 + 门边油灯三盏光")
	check(main.find_children("*", "Npc", true, false).map(func(n): return n.display_name) == ["奥尔本修士"], "小教堂里有奥尔本修士")
	await place(p, 0.0, 3.5)
	await hold("move_forward", 3.0)
	check(p.global_position.z < -2.0 and p.global_position.z > -3.7, "沿中间走道走到祭坛前，被祭台挡住（z = %.2f）" % p.global_position.z)
	await place(p, 1.65, 3.7)
	await hold("move_forward", 1.5)
	check(p.global_position.z > 2.9, "长椅挡着，从长椅中间穿不过去（z = %.2f）" % p.global_position.z)
	main.set_view(1)
	await physics(4)
	p.interactor.refresh()
	check(p.interactor.target is Npc and p.interactor.target.display_name == "奥尔本修士", "?view=1 对准奥尔本修士能交谈")
	# —— 奥尔本修士：线索、借钥匙（捐钱）
	check(r.start("chapel", "alban") and r.speaker() == "奥尔本修士", "修士的对话能打开")
	var labels: Array = r.options().map(func(o): return DialogueRunner.option_label(o))
	check(labels.has("打听埃德里克少爷的事。") and not labels.has("能借墓园的钥匙吗？"), "先打听少爷，才会想到借钥匙（%s）" % str(labels))
	r.choose(labels.find("打听埃德里克少爷的事。"))
	check(GameState.clues.has("chapel_key") and GameState.has_flag("alban_told") and r.text().contains("钥匙"), "修士：少爷昨天傍晚借走了墓园钥匙（线索）")
	r.choose(0)
	check(r.node_id == "key", "追问钥匙")
	labels = r.options().map(func(o): return DialogueRunner.option_label(o))
	var s0 := GameState.silver
	r.choose(labels.find("（往捐献箱里放 3 枚银币）给教堂添点灯油。"))
	check(r.node_id == "key_given" and GameState.has_item("crypt_key") and GameState.silver == s0 - 3 and GameState.has_flag("alban_lent_key"), "捐 3 枚银币：修士把墓园钥匙借给你")
	r.start("chapel", "alban")
	labels = r.options().map(func(o): return DialogueRunner.option_label(o))
	check(not labels.has("能借墓园的钥匙吗？") and not labels.has("打听埃德里克少爷的事。"), "借到以后不再借第二次、不再重复打听")
	# 口才：成功 / 失败（失败后只剩捐钱）
	var sd_pass := seed_for("alban_key_speech", "speech", 11, true)
	var sd_fail := seed_for("alban_key_speech", "speech", 11, false)
	for sd in [sd_pass, sd_fail]:
		GameState.new_game(sd)
		GameState.start_quest("edric_missing")
		r.start("chapel", "alban")
		r.choose(0)
		r.choose(0)
		labels = r.options().map(func(o): return DialogueRunner.option_label(o))
		var si := -1
		for i in labels.size():
			if labels[i].contains("口才"):
				si = i
		r.choose(si)
		if sd == sd_pass:
			check(r.node_id == "key_given" and GameState.has_item("crypt_key") and GameState.silver == 12, "口才说服修士：不花钱借到钥匙")
		else:
			check(r.node_id == "key_refused" and not GameState.has_item("crypt_key") and GameState.has_flag("alban_refused"), "口才没说动：「死人也有他们的安宁」")
			labels = r.options().map(func(o): return DialogueRunner.option_label(o))
			r.choose(labels.find("（往捐献箱里放 3 枚银币）给教堂添点灯油。"))
			check(GameState.has_item("crypt_key"), "没说动也还能捐钱借到")
			r.start("chapel", "alban")
			check(not r.options().map(func(o): return DialogueRunner.option_label(o)).any(func(l): return l.contains("口才")), "口才失败后不能再试")
	r.start("chapel", "alban")
	labels = r.options().map(func(o): return DialogueRunner.option_label(o))
	check(labels.has("坠星是什么？"), "可以问坠星（星铁教会的来历）")
	r.choose(labels.find("坠星是什么？"))
	check(r.text().contains("哈尔文") and r.text().contains("誓"), "修士讲坠星：开国的哈尔文在坠星落地处加冕，加冕时还要发一个誓")
	# —— 回墓园：用钥匙开墓室、搜包袱、读信
	main.set_view(3)
	await physics(4)
	p.interactor.refresh()
	check(p.interactor.target is Door and p.interactor.target.prompt() == "离开 · 回到墓园", "门内对准门：提示「离开 · 回到墓园」")
	p.interactor.use()
	await seconds(0.45)
	main = await reload_main(main)
	p = main.player
	await frames(3)
	check(main.area == "churchyard" and flat(p.global_position).distance_to(Vector2(0, -6.4)) < 0.3 and absf(absf(p.rotation.y) - PI) < 0.05, "回到墓园：站在小教堂门前、背对着门")
	crypt = main.find_children("*", "Door", true, false).filter(func(d): return d.key_item == "crypt_key")[0]
	main.set_view(1)
	await physics(4)
	rr = crypt.interact(p)
	check(not crypt.locked and crypt.is_open and str(rr.get("toast", "")).contains("用墓园钥匙打开了"), "有钥匙：铁门打开，提示「用墓园钥匙打开了瓦伦家墓室的铁门」")
	bundle = main.find_children("*", "LootContainer", true, false).filter(func(c): return c.loot_id == "valen_crypt_bundle")[0]
	var got: Array = bundle.take_all()
	check(got.has("没写完的信") and got.has("6 枚银币") and GameState.has_item("edric_letter") and GameState.clues.has("letter"), "搜包袱：拿到少爷没写完的信，记下线索（%s）" % str(got))
	check(GameState.quest_stage("edric_missing") == "to_ferry", "修士的线索 + 信：主线推进到「去渡口找少爷」")
	r.start("chapel", "alban")
	labels = r.options().map(func(o): return DialogueRunner.option_label(o))
	check(labels.has("（把墓室里找到的信递给他）"), "带着信回去：可以给修士看")
	r.choose(labels.find("（把墓室里找到的信递给他）"))
	check(r.text().contains("渡口") and GameState.has_flag("alban_saw_letter"), "修士读信：今夜只有渡口还点着灯")
	# —— 墓园存档、读档
	await place(p, 2.0, 0.0)
	check(main.save_game("slot2", true), "墓园里能存档")
	check(main.load_game("slot2"), "读这个存档")
	main = await reload_main(main)
	check(main.area == "churchyard" and flat(main.player.global_position).distance_to(Vector2(2.0, 0.0)) < 0.2, "读档回到墓园同一个位置")
	p = main.player
	# —— 院门回主街
	var gate: Door = main.find_children("*", "Door", true, false).filter(func(d): return d.to_area == "frostford")[0]
	await aim(p, Vector3(0, 0.05, 9.4), gate.global_position + Vector3(0.7, 1.0, 0))
	check(p.interactor.target == gate and gate.prompt() == "回到 · 霜渡镇主街", "院门：提示「回到 · 霜渡镇主街」")
	p.interactor.use()
	await seconds(0.45)
	main = await reload_main(main)
	p = main.player
	await frames(3)
	check(main.area == "frostford" and flat(p.global_position).distance_to(Vector2(3.3, -27.25)) < 0.3 and absf(p.rotation.y - PI / 2) < 0.05, "回到主街：站在小路门外、面朝街心")
	await free_main(main)
	GameState.pending_load = {}
	GameState.new_game(1)


## 3.3 徒手格斗：拳头、格斗专长、不致命的打斗；酒馆里和大桶打一架（玛蒂尔达的第三种问法）
func test_brawl() -> void:
	# —— 数据：格斗专长、醉汉
	var bp: Array = GameState.perks_of("brawl")
	check(bp.size() == 3 and bp.map(func(x): return x.effect) == ["combo3", "fist_stagger", "guard_cheap"] and GameState.validate_progression(GameState.progression()).is_empty(),
		"格斗三个专长：连拳 25、重拳 50、硬骨头 75（%s）" % str(bp.map(func(x): return x.name)))
	var dk: Dictionary = Enemy.types().drunk
	check(dk.weapon == "fists" and bool(dk.nonlethal) and float(dk.yield_chance) == 1.0 and Enemy.validate_types(Enemy.types()).is_empty(), "醉汉：徒手、打不死、打到三成生命一定认输")
	# —— 训练场里练拳头
	GameState.new_game(41)
	var main := await make_arena()
	var p: FpController = main.player
	var m: Melee = p.melee
	var a := arena_enemy(main, "a")
	solo(main, a)
	a._enter(Enemy.State.YIELD)                # 跪着不还手，但还挨得着（停用的节点会被移出物理世界，打不到）
	GameState.unequip("weapon")
	check(m.unarmed() and m.view.model == "fists" and m.weapon_skill() == "brawl" and is_equal_approx(m.reach_far(), Melee.FIST_REACH), "没装备武器：手里是拳头，用格斗，够得着 1.5 米")
	m.toggle_draw()
	await seconds(0.45)
	check(m.state == Melee.State.IDLE and m.view.off_node != null and m.view.off_node.visible, "按 R 举起拳头：两只拳头都在画面里")
	put_enemy(a, Vector3(0, 0, 1.75), PI)
	await aim(p, Vector3(0, 0, 3.0), a.global_position + Vector3(0, 1.2, 0))
	var hp0 := a.hp
	var st0 := m.stamina
	m.press()
	m.release()
	await seconds(0.4)
	var want := DamageCalc.compute(5.0, GameState.strength, int(GameState.skills.brawl), "light", false, a.armor)
	check(hp0 - a.hp == want, "轻拳打中：伤害按拳头 5 + 格斗算（%d，应为 %d）" % [hp0 - a.hp, want])
	check(is_equal_approx(st0 - m.stamina, Melee.TIMING.light.cost * Melee.FIST_COST) or m.stamina > st0 - Melee.TIMING.light.cost, "出拳比挥剑省体力（−%.1f）" % (st0 - m.stamina))
	check(float(GameState.skill_xp.get("brawl", 0.0)) >= Melee.TRAIN_HIT, "拳头打中：格斗涨进度")
	await seconds(0.4)
	put_enemy(a, Vector3(0, 0, 1.1), PI)       # 隔 1.9 米（身子外沿 1.6 米）：拳头够不着，剑够得着
	hp0 = a.hp
	await aim(p, Vector3(0, 0, 3.0), a.global_position + Vector3(0, 1.2, 0))
	m.press()
	m.release()
	await seconds(0.6)
	check(a.hp == hp0, "隔 1.9 米：拳头够不着")
	GameState.equip("short_sword")
	check(m.view.model == "sword" and m.state == Melee.State.SHEATHED and not m.unarmed(), "装上剑：拳头放下，换回剑")
	m.toggle_draw()
	await seconds(0.45)
	m.press()
	m.release()
	await seconds(0.6)
	check(a.hp < hp0, "同样的距离，剑够得着")
	# 专长
	GameState.skills.blade = 25
	GameState.skills.brawl = 5
	m.set_fists_only(true)
	check(m.state == Melee.State.SHEATHED and m.view.model == "fists" and m.combo_max() == 2, "只许用拳头：剑收起来；剑术的「连环」不管拳头")
	GameState.skills.brawl = 25
	check(m.combo_max() == 3, "格斗 25「连拳」：轻拳三连")
	var info := {"damage": 10, "kind": "light"}
	var c0 := m.guard_cost(info)
	GameState.skills.brawl = 75
	check(is_equal_approx(m.guard_cost(info), c0 * 0.5), "格斗 75「硬骨头」：空手格挡体力减半（%.1f → %.1f）" % [c0, m.guard_cost(info)])
	m.set_fists_only(false)
	check(is_equal_approx(m.guard_cost(info), c0), "拿剑格挡不减半")
	m.set_fists_only(true)
	GameState.skills.brawl = 50
	a.process_mode = Node.PROCESS_MODE_INHERIT
	a.data = a.data.duplicate()
	a.data.block_chance = 0.0
	a.hp = 50
	put_enemy(a, Vector3(0, 0, 1.75), PI)
	a._enter(Enemy.State.COMBAT)
	m.toggle_draw()
	await seconds(0.45)
	await aim(p, Vector3(0, 0, 3.0), a.global_position + Vector3(0, 1.2, 0))
	m.press()
	await seconds(0.45)
	m.release()
	await seconds(0.25)
	check(a.state == Enemy.State.STAGGER and a.hp < 50, "格斗 50「重拳」：重拳打中让对方失衡（%s）" % a.state_name())
	a.process_mode = Node.PROCESS_MODE_DISABLED
	m.set_fists_only(false)
	# 不致命：被打到 KO_FLOOR 就算被打倒，不会倒下死去
	var ko := [0]
	m.knocked_out.connect(func(_i): ko[0] += 1)
	m.health = 40
	m.receive_hit({"damage": 30, "kind": "light", "nonlethal": true})
	check(ko[0] == 1 and m.health == Melee.KO_FLOOR and not m.down, "不致命的一拳：生命停在 %d，被打倒（不是倒下）" % m.health)
	m.health = 10
	m.receive_hit({"damage": 3, "kind": "light", "nonlethal": true})
	check(ko[0] == 2 and m.health == 10 and not m.down, "已经在这条线以下：挨一下就倒，生命不再减")
	m.health = m.health_max()
	await seconds(0.9)
	# 醉汉打不死：最少留 1 点，认输
	var d := Enemy.make("drunk", "t")
	main.world.add_child(d)
	d.global_position = Vector3(4, 0, 4)
	await physics(2)
	d.take_hit({"damage": 999, "kind": "heavy", "stop": 0.0})
	check(d.alive() and d.hp == 1 and d.state == Enemy.State.YIELD, "醉汉挨了重手也不死：生命 1，认输（%s）" % d.state_name())
	check(d.arm.get_child_count() > 0 and d.display_name == "醉汉", "醉汉手里没有兵器（拳头）")
	await free_main(main)
	# —— 酒馆：玛蒂尔达请你让大桶结账
	GameState.new_game(43)
	GameState.start_quest("edric_missing")
	main = await make_area("tavern")
	p = main.player
	m = p.melee
	var npcs := main.find_children("*", "Npc", true, false).map(func(n): return n.display_name)
	check(npcs.has("大桶") and npcs.size() == 4, "酒馆里多了靠在吧台东头的大桶（%s）" % str(npcs))
	var dagu: Npc = main._npc_by_dialogue("dagu")
	var home := dagu.global_position
	var r := DialogueRunner.new()
	r.start("tavern", "dagu")
	var labels: Array = r.options().map(func(o): return o.text)
	check(not labels.any(func(l): return l.contains("酒钱")), "没受玛蒂尔达之托：不能找大桶要账")
	r.start("tavern", "matilda")
	r.choose(0)
	labels = r.options().map(func(o): return o.text)
	var off_i := labels.find(labels.filter(func(l): return l.contains("大个子"))[0] if labels.any(func(l): return l.contains("大个子")) else "")
	check(r.node_id == "edric" and off_i >= 0, "打听少爷时可以问「那个大个子」（%s）" % str(labels))
	r.choose(off_i)
	check(r.node_id == "dagu_offer" and GameState.has_flag("matilda_brawl_offer"), "玛蒂尔达：让大桶把账结了（不许动刀），她就说")
	# 和大桶说话 → 开打（走真的对话面板，对话关上后开打）
	m.toggle_draw()
	await seconds(0.45)
	await aim(p, Vector3(1.9, 0, 0.2), dagu.global_position + Vector3(0, 1.5, 0))
	check(p.interactor.target == dagu, "对准大桶")
	p.interactor.use()
	await frames(2)
	check(main.dialogue.visible and main.dialogue.runner.id == "dagu", "大桶的对话能打开")
	find_button(main.dialogue, "玛蒂尔达说你欠了三个晚上的酒钱。").pressed.emit()
	await frames(1)
	check(main.dialogue.runner.node_id == "challenge", "大桶：想要钱，先把我放倒；不许动刀子")
	find_button(main.dialogue, "那就来吧。（徒手打一架）").pressed.emit()
	await frames(3)
	var e: Enemy = null
	for x in main.get_tree().get_nodes_in_group("enemy"):
		e = x
	check(main.brawl_active() and e != null and e.display_name == "大桶" and e.state == Enemy.State.COMBAT, "对话关上就开打：大桶站起来动手（%s）" % (e.state_name() if e else "没有"))
	check(not dagu.visible and dagu.collision_layer == 0, "说话的大桶先藏起来（换成打架的那个）")
	check(main.hud.hint_label.text == main.HINT_BRAWL_DESKTOP, "底部提示换成打架的操作（出拳、格挡、不许动刀）")
	check(m.fists_only and m.state == Melee.State.SHEATHED and m.view.model == "fists", "剑收起来了，只许用拳头")
	var went: bool = await main.travel("frostford", "tavern_door")
	check(main.in_combat() and main.can_save() != "" and not went, "打架的时候不能存档、不能出门")
	var matilda: Npc = main._npc_by_dialogue("matilda")
	main._on_interacted(matilda.interact(p))
	check(not main.dialogue.visible, "打架的时候不能和别人搭话")
	# 站着不动：大桶会上来打你（不致命）
	var hp_start := m.health
	var hits := [0]
	m.damaged.connect(func(_a, inf): hits[0] += (1 if bool(inf.get("nonlethal", false)) else 0))
	await place(p, 1.9, 0.6)
	p.rotation.y = atan2(-(e.global_position.x - 1.9), -(e.global_position.z - 0.6))
	await seconds(4.0)
	check(hits[0] >= 1 and m.health < hp_start and not m.down, "大桶冲上来出拳打中你（%d 下，生命 %d → %d，不致命）" % [hits[0], hp_start, m.health])
	# 还手：真的出一拳（先把他定住，免得他的拳头打断这一下），再把他打到认输
	e.stop_left = 5.0
	e.action = ""
	e.data = e.data.duplicate()
	e.data.block_chance = 0.0
	await seconds(0.9)
	var ehp := e.hp
	m.toggle_draw()
	await seconds(0.45)
	await aim(p, e.global_position + (p.global_position - e.global_position).normalized() * 1.0, e.global_position + Vector3(0, 1.2, 0))
	m.press()
	m.release()
	await seconds(0.4)
	check(e.hp < ehp, "出拳打中大桶（%d → %d）" % [ehp, e.hp])
	e.take_hit({"damage": 999, "kind": "heavy", "stop": 0.0})
	await frames(2)
	check(not main.brawl_active() and GameState.has_flag("dagu_beaten") and not main.in_combat(), "打到认输：打赢了，不再算战斗中")
	check(not m.fists_only, "打完了：又能拔剑")
	await seconds(Brawl.END_DELAY + 0.3)
	check(not is_instance_valid(e) and dagu.visible and dagu.collision_layer != 0, "跪了一会儿：大桶变回能说话的人")
	check(Saves.read_slot("auto").has("data") and bool(Saves.read_slot("auto").data.state.flags.get("dagu_beaten", false)), "打完自动存档（记着打赢了）")
	r.start("tavern", "dagu")
	check(r.node_id == "beaten", "再找大桶：他揉着下巴把账结了")
	r.start("tavern", "matilda")
	labels = r.options().map(func(o): return o.text)
	check(labels[0] == "大桶把账结了。", "玛蒂尔达：多了「大桶把账结了」")
	r.choose(0)
	r.choose(0)
	check(r.node_id == "edric_told" and GameState.clues.has("boots") and GameState.has_flag("matilda_told_edric") and GameState.silver == 12, "说话算话：不花钱也问出了南方人的事（线索）")
	await free_main(main)
	# —— 输了：被大桶打倒，生命停在 25，他回原处接着喝，可以再来一场
	GameState.new_game(44)
	GameState.start_quest("edric_missing")
	GameState.set_flag("matilda_brawl_offer")
	main = await make_area("tavern")
	p = main.player
	m = p.melee
	dagu = main._npc_by_dialogue("dagu")
	main.start_brawl(dagu, {"brawl": "drunk", "win": "dagu_beaten", "lose": "dagu_won"})
	await frames(2)
	e = main.brawl.enemy
	m.receive_hit({"damage": 200, "kind": "heavy", "attacker": e, "nonlethal": true})
	await frames(3)
	check(not main.brawl_active() and GameState.has_flag("dagu_won") and not GameState.has_flag("dagu_beaten"), "被打倒：这一架输了")
	check(m.health == Melee.KO_FLOOR and not m.down and not get_tree().paused, "生命停在 %d，没有倒下（不出倒下界面）" % m.health)
	check(not is_instance_valid(e) or e.is_queued_for_deletion(), "打架的大桶撤掉了")
	await frames(2)
	check(dagu.visible and flat(dagu.global_position).distance_to(flat(home)) < 0.05, "大桶回到吧台东头接着喝")
	r.start("tavern", "dagu")
	labels = r.options().map(func(o): return o.text)
	check(r.node_id == "won" and labels.has("再来一场。（徒手打一架）"), "再找大桶：他笑你，可以再来一场")
	await free_main(main)
	# —— 第三人称的出拳动作（character_anims.json 的 fists）
	var map := CharacterModel.load_map()
	var fm: Dictionary = map.fists
	var lib := load(CharacterModel.ANIMS) as AnimationLibrary
	var fh: Dictionary = fm.heavy
	var marks_ok: bool = float(fh.wind_peak) < float(fh.impact) and float(fh.impact) < lib.get_animation(fh.clip).length
	for x in fm.light:
		marks_ok = marks_ok and float(x.impact) > 0.0 and float(x.impact) < lib.get_animation(x.clip).length
	var lt: Dictionary = Melee.TIMING.light
	var ht: Dictionary = Melee.TIMING.heavy
	var ls1 := float(fm.light[0].impact) / (float(lt.wind) + float(lt.strike) * float(lt.hit_at))
	var ls2 := float(fm.light[1].impact) / (float(lt.wind) + float(lt.strike) * float(lt.hit_at))
	var hs := (float(fh.impact) - float(fh.wind_peak)) / (float(ht.strike) * float(ht.hit_at))
	check(marks_ok and ls1 > 0.8 and ls2 < 2.2 and hs > 0.5 and hs < 1.8, "出拳动作的命中时刻在动作之内，播放速度合理（刺拳 ×%.2f、直拳 ×%.2f、重拳 ×%.2f）" % [ls1, ls2, hs])
	Settings.set_value("third_person", true)
	GameState.new_game(45)
	main = await make_main(true)
	p = main.player
	m = p.melee
	GameState.unequip("weapon")
	await place(p, 0.0, 10.0)
	await seconds(0.4)
	var c: CharacterModel = p.avatar.character
	await aim(p, TestRange.DUMMY_POS + Vector3(0, 0, 1.3), TestRange.DUMMY_POS + Vector3(0, 1.2, 0))
	m.toggle_draw()
	await seconds(0.6)
	check(c.role == "idle_fists" and c.playing() == "Punch_Jab" and c.anim.get_playing_speed() == 0.0 and not p.avatar.weapon_mesh.visible, "第三人称举起拳头：护脸的架势，手里没有剑（%s）" % c.role)
	var rec: Array = []
	m.hit.connect(func(_t, _info): rec.append([c.playing(), c.anim.current_animation_position]))
	m.press()
	m.release()
	await seconds(0.3)
	check(rec.size() == 1 and rec[0][0] == "Punch_Jab" and absf(rec[0][1] - float(fm.light[0].impact)) < 0.08, "第一拳刺拳：打中时拳头正好伸到最前（%s，第 %.2f 秒）" % [rec[0][0] if rec.size() > 0 else "-", rec[0][1] if rec.size() > 0 else -1.0])
	m.press()
	m.release()
	await seconds(0.4)
	check(rec.size() == 2 and rec[1][0] == "Punch_Cross" and absf(rec[1][1] - float(fm.light[1].impact)) < 0.08, "第二拳直拳：换右手（%s，第 %.2f 秒）" % [rec[1][0] if rec.size() > 1 else "-", rec[1][1] if rec.size() > 1 else -1.0])
	await seconds(0.8)
	check(c.role == "idle_fists", "收拳回到架势（%s）" % c.role)
	rec.clear()
	m.press()
	await seconds(0.5)
	check(c.playing() == "OverhandThrow" and c.anim.get_playing_speed() == 0.0 and absf(c.anim.current_animation_position - float(fh.wind_peak)) < 0.02, "按住蓄重拳：拳头抡到身后停住（第 %.2f 秒）" % c.anim.current_animation_position)
	m.release()
	await seconds(0.5)
	check(rec.size() == 1 and rec[0][0] == "OverhandThrow" and absf(rec[0][1] - float(fh.impact)) < 0.08, "重拳：松手砸下，命中帧对齐（第 %.2f 秒，目标 %.2f）" % [rec[0][1] if rec.size() > 0 else -1.0, float(fh.impact)])
	await seconds(0.8)
	m.block_press()
	await seconds(0.4)
	check(m.blocking() and c.role == "block_fists" and c.playing() == "Idle_Shield_Loop" and c.anim.get_playing_speed() == 0.0, "空手格挡：小臂横在胸前停住（%s）" % c.role)
	m.block_release()
	await seconds(0.5)
	GameState.equip("short_sword")
	await seconds(0.2)
	check(p.avatar.weapon_mesh != null and not p.avatar.weapon_mesh.visible and m.state == Melee.State.SHEATHED, "装上剑：拳头放下，剑还在鞘里")
	await free_main(main)
	Settings.set_value("third_person", false)
	GameState.new_game(1)


## 3.4 导航网格与街巷 AI：运行时烘焙、敌人绕房子追击、沿路巡逻、酒馆里绕桌子；没有导航网格的区域照旧直线走
func test_nav() -> void:
	GameState.new_game(51)
	var main := await make_main(false)
	var p: FpController = main.player
	check(not main.nav.is_empty() and int(main.nav.polygons) > 50 and (main.nav.region as Node).is_inside_tree(),
		"霜渡镇载入时烘焙了导航网格（%d 个多边形，%.0f 毫秒）" % [int(main.nav.get("polygons", 0)), float(main.nav.get("ms", 0.0))])
	check(float(main.nav.ms) < 300.0, "烘焙耗时 %.0f 毫秒（无头模式；网页实测见冒烟测试）" % float(main.nav.ms))
	var nb := Areas.nav_bounds("frostford").grow(0.3)
	var inside := true
	var low := true
	for v in (main.nav.region as NavigationRegion3D).navigation_mesh.get_vertices():
		inside = inside and nb.has_point(v)
		low = low and (v.y < 1.2)
	check(inside and low, "导航网格只铺在围墙里能走的地方（不铺到墙外、屋顶上）")
	await physics(10)
	var map: RID = main.get_world_3d().navigation_map
	var gp := NavigationServer3D.map_get_closest_point(map, Vector3(0, 0, -15))
	check(absf(gp.y) < 0.2 and flat(gp).distance_to(Vector2(0, -15)) < 0.1, "网格面贴着地面（街心的点高 %.2f 米）" % gp.y)
	# 房子背后到街心：房子之间的窄缝挤不过去，要从这一排房子的尽头绕；路径不穿墙
	var space := main.get_world_3d().direct_space_state
	var path := NavigationServer3D.map_get_path(map, Vector3(-13.5, 0, -8.5), Vector3(0, 0, -8.5), true)
	var clear := path.size() >= 3
	for i in range(1, path.size()):
		var q := PhysicsRayQueryParameters3D.create(Vector3(path[i - 1].x, 0.6, path[i - 1].z), Vector3(path[i].x, 0.6, path[i].z), 1)
		clear = clear and space.intersect_ray(q).is_empty()
	check(clear and NavBuilder.path_length(path) > 25.0, "从酒馆背后到街心：绕过整排房子（路径 %.0f 米，直线 13.5 米），不穿墙" % NavBuilder.path_length(path))
	# 追击：敌人在房子背后，你在小广场上；隔着房子看不见你，沿路绕过房角追过来
	var director := CombatDirector.new()
	main.world.add_child(director)
	var e := Enemy.make("clubber", "nav_a")
	main.world.add_child(e)
	e.global_position = Vector3(-13.5, 0, -16.75)
	await place(p, -8.0, -24.5)
	await physics(2)
	check(e.nav_ready(), "敌人用得上这个区域的导航网格")
	var straight := Vector3(-8.0, 0.6, -24.5)
	var blocked := not space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-13.5, 0.6, -16.75), straight, 1)).is_empty()
	e.engage()
	var t := 0.0
	var reached := false
	var corner_ok := true
	while t < 9.0 and not reached:
		await seconds(0.25)
		t += 0.25
		var ep := e.global_position
		corner_ok = corner_ok and not (ep.x > -11.5 and ep.x < -4.5 and ep.z < -13.5 and ep.z > -20.0)     # 没钻进房子里
		reached = flat(ep).distance_to(flat(p.global_position)) < 3.2
	check(blocked and reached and corner_ok, "敌人隔着房子：绕过房角追到你跟前（%.1f 秒）" % t)
	e.queue_free()
	await frames(2)
	# 巡逻：井的两边各一个巡逻点，沿路绕过井走，不卡在井栏上
	await place(p, 0.0, 8.0)
	p.crouch_wanted = true
	var g := Enemy.make("clubber", "nav_b", [Vector3(-4.6, 0, -25.6), Vector3(-8.3, 0, -25.6)])
	main.world.add_child(g)
	g.global_position = Vector3(-4.6, 0, -25.6)
	var max_wp := 0
	var in_well := false
	t = 0.0
	while t < 12.0 and max_wp < 1:
		await seconds(0.25)
		t += 0.25
		in_well = in_well or flat(g.global_position).distance_to(Vector2(-6.4, -25.6)) < 0.9
		if g.wp_index >= 1 and flat(g.global_position).distance_to(Vector2(-8.3, -25.6)) < 0.6:
			max_wp = 1
	check(max_wp == 1 and not in_well and g.state == Enemy.State.PATROL, "巡逻：从井的东边绕到西边的巡逻点（%.1f 秒，%s，在 %s）" % [t, g.state_name(), str(flat(g.global_position))])
	p.crouch_wanted = false
	await free_main(main)
	# 酒馆：大桶绕过长桌过来
	GameState.new_game(52)
	main = await make_area("tavern")
	p = main.player
	check(not main.nav.is_empty() and int(main.nav.polygons) > 0, "酒馆也烘焙了导航网格（%.0f 毫秒）" % float(main.nav.ms))
	await place(p, -2.0, 2.7)
	main.start_brawl(main._npc_by_dialogue("dagu"), {"brawl": "drunk"})
	await physics(2)
	var d: Enemy = main.brawl.enemy
	space = main.get_world_3d().direct_space_state
	var low_ray := PhysicsRayQueryParameters3D.create(Vector3(2.5, 0.5, -1.35), Vector3(-2.0, 0.5, 2.7), 1)
	low_ray.exclude = [d.get_rid()]
	var table_between := not space.intersect_ray(low_ray).is_empty()
	t = 0.0
	reached = false
	while t < 8.0 and not reached:
		await seconds(0.25)
		t += 0.25
		reached = flat(d.global_position).distance_to(flat(p.global_position)) < 1.6
	check(table_between and reached, "打架时大桶绕过长桌走到你跟前（%.1f 秒）" % t)
	await free_main(main)
	# 没有导航网格的区域（墓园）：照旧直线走
	main = await make_area("churchyard")
	check(main.nav.is_empty(), "墓园没有敌人，不烘焙导航网格")
	var c := Enemy.make("clubber", "nav_c")
	main.world.add_child(c)
	c.global_position = Vector3(0, 0, 5)
	await physics(3)
	var v: Vector3 = c._steer(Vector3(4, 0, 5), 2.0)
	var direct_dir := Vector3(4, 0, 5) - c.global_position
	direct_dir.y = 0.0
	check(not c.nav_ready() and v.normalized().dot(direct_dir.normalized()) > 0.999, "没有导航网格：直线朝目标走（方向 %s）" % str(v.normalized()))
	c.queue_free()
	await free_main(main)
	GameState.new_game(1)


## 3.5 镇外桦林：主街南门、白桦林、营火哨卡的三个无旗者（伏击）、头目身上的雇佣信、求饶的人能搜身、读档后原样
func test_birch() -> void:
	check(Areas.known("birch") and not Areas.is_indoor("birch") and Areas.nav_bounds("birch").has_volume(), "新区域：镇外桦林（室外，烘焙导航网格）")
	var it := GameState.item("hire_letter")
	check(it.kind == "quest" and str(it.get("clue", "")) == "hire_letter" and str(it.desc).contains("两把钥匙交叉"), "雇佣信：任务物品，拿到记下线索，压着双钥蜡印")
	check(Enemy.types().outlaw_leader.loot.has("hire_letter"), "雇佣信在哨卡头目身上")
	# 线索推进：先拿到雇佣信、后凑够线索，也能一口气推到「赶在他们前头去渡口」
	GameState.new_game(61)
	GameState.start_quest("edric_missing")
	GameState.add_item("hire_letter")
	check(GameState.quest_stage("edric_missing") == "find_clues", "只有雇佣信一条线索：还在打探")
	GameState.add_clue("ferry")
	check(GameState.quest_stage("edric_missing") == "warned", "再凑一条线索：推进到「去渡口」，有雇佣信就接着推进到「赶在他们前头去渡口」")
	# —— 主街南门 → 桦林
	GameState.new_game(62)
	GameState.start_quest("edric_missing")
	GameState.add_clue("ferry")
	GameState.add_clue("boots")
	check(GameState.quest_stage("edric_missing") == "to_ferry", "主线在「穿过桦林去渡口」")
	var main := await make_main(false)
	var p: FpController = main.player
	await place(p, 0.0, 9.6)
	p.rotation.y = PI
	await physics(4)
	p.interactor.refresh()
	check(p.interactor.target is Door and p.interactor.target.prompt() == "前往 · 南门（往桦林、渡口）", "主街南头：对准南门提示「前往 · 南门（往桦林、渡口）」（%s）" % (p.interactor.target.prompt() if p.interactor.target else "没对准"))
	p.interactor.use()
	await seconds(0.45)
	check(GameState.pending_load.get("scene") == "birch" and GameState.pending_load.get("spawn") == "north", "出南门：去桦林")
	main = await reload_main(main)
	p = main.player
	await frames(3)
	check(main.area == "birch" and flat(p.global_position).distance_to(Vector2(0, Birch.NORTH + 3.2)) < 0.3 and absf(absf(p.rotation.y) - PI) < 0.05, "站在桦林北头、面朝南边的小路")
	check(main.moon.visible and main.env.fog_mode == Environment.FOG_MODE_DEPTH, "桦林是室外：月光与夜雾")
	check(main.hud.hint_label.text == Birch.TEACH_DESKTOP, "进桦林：提示拿武器战斗的操作（教学）")
	check(not main.nav.is_empty() and int(main.nav.polygons) > 100, "桦林烘焙了导航网格（%d 个多边形，%.0f 毫秒）" % [int(main.nav.get("polygons", 0)), float(main.nav.get("ms", 0.0))])
	var trees: Array = main.world.find_children("*", "StaticBody3D", true, false).filter(func(b): return b.get_child_count() > 0 and b.get_child(0) is CollisionShape3D and (b.get_child(0) as CollisionShape3D).shape is CylinderShape3D)
	check(trees.size() >= 80 and (main.world.get_node("Birch") as MeshInstance3D).mesh.get_surface_count() <= 8, "白桦林：%d 棵树（每棵一个碰撞体），整片林子一个网格" % trees.size())
	var fires := main.get_tree().get_nodes_in_group("light_source")
	check(fires.size() == 1 and flat(fires[0].global_position).distance_to(flat(Birch.FIRE_POS)) < 0.1, "哨卡的营火：站在火光里，远处的人也看得见你")
	var enemies := main.get_tree().get_nodes_in_group("enemy")
	var names: Array = enemies.map(func(e): return e.display_name)
	names.sort()
	check(enemies.size() == 3 and names == ["无旗者 · 头目", "无旗者 · 棍手", "无旗者 · 棍手"], "哨卡有三个无旗者：头目和两个棍手（%s）" % str(names))
	check(enemies.all(func(e): return e.state == Enemy.State.PATROL), "开始时都在巡逻，还没发现你")
	# 南头去渡口的路：还走不过去
	var south: Door = main.find_children("*", "Door", true, false).filter(func(d): return d.display_name == "去渡口的路")[0]
	var sr: Dictionary = south.interact(p)
	check(sr.get("locked", false) and str(sr.toast).contains("渡口在后续版本开放"), "南头去渡口的路：还走不过去，说明渡口在后续版本开放")
	# 伏击：沿路往南走，被路上巡逻的棍手看见，喊上营火边的人
	var leader: Enemy = enemies.filter(func(e): return e.kind == "outlaw_leader")[0]
	var road: Enemy = enemies.filter(func(e): return e.enemy_id == "birch_a")[0]
	var east: Enemy = enemies.filter(func(e): return e.enemy_id == "birch_b")[0]
	await place(p, 0.4, -9.0)
	p.rotation.y = PI
	var t := 0.0
	var hostile := 0
	while t < 8.0 and hostile < 2:
		await hold("move_forward", 0.25)
		t += 0.25
		hostile = enemies.filter(func(e): return e.state in [Enemy.State.ALERT, Enemy.State.COMBAT]).size()
	check(hostile >= 2, "沿路往南走：哨卡的人发现你、喊上同伙（%d 个敌人在战斗，%.1f 秒）" % [hostile, t])
	# 解决：两个棍手倒下，头目求饶
	var rep0 := GameState.get_rep("outlaws")
	road.take_hit({"damage": 999, "kind": "heavy", "stop": 0.0})
	east.take_hit({"damage": 999, "kind": "heavy", "stop": 0.0})
	leader.data = leader.data.duplicate()
	leader.data.yield_chance = 1.0
	leader.data.block_chance = 0.0
	leader.take_hit({"damage": leader.hp - 5, "kind": "heavy", "stop": 0.0})
	await frames(3)
	check(not road.alive() and not east.alive() and GameState.get_rep("outlaws") == rep0 - 10, "两个棍手倒下（无旗者声望 −10）")
	check(leader.alive() and leader.state == Enemy.State.YIELD and GameState.yielded.has("birch_leader"), "头目求饶：跪在地上，记进存档")
	var lc: Array = main.find_children("*", "LootContainer", true, false).filter(func(c): return c.loot_id == "loot:birch_leader")
	check(lc.size() == 1 and lc[0].corpse, "求饶的头目也能搜身")
	var got: Array = lc[0].take_all()
	check(got.has("雇佣信") and GameState.has_item("hire_letter") and GameState.clues.has("hire_letter"), "搜出雇佣信，记下线索（%s）" % str(got))
	check(GameState.quest_stage("edric_missing") == "warned", "主线推进：他们收了钱要在渡口劫人，赶在他们前头去渡口")
	# 存档读档：倒下的还倒着、求饶的还跪着，搜过的不会再有
	await place(p, 0.0, -2.0)
	check(main.save_game("slot1"), "仗打完了，能存档")
	check(main.load_game("slot1"), "读这个存档")
	main = await reload_main(main)
	p = main.player
	await frames(4)
	enemies = main.get_tree().get_nodes_in_group("enemy")
	leader = enemies.filter(func(e): return e.kind == "outlaw_leader")[0]
	check(main.area == "birch" and enemies.filter(func(e): return not e.alive()).size() == 2, "读档：两个棍手还倒在地上")
	check(leader.state == Enemy.State.YIELD and leader.body.position.y < -0.3 and leader.name_label.text.contains("求饶"), "读档：头目还跪着")
	lc = main.find_children("*", "LootContainer", true, false).filter(func(c): return c.loot_id == "loot:birch_leader")
	check(lc.size() == 1 and lc[0].is_empty(), "头目身上已经搜过了")
	check(not main.in_combat() and main.can_save() == "", "求饶的人不算在和你打")
	# 回镇上
	await place(p, 0.0, Birch.NORTH + 1.6)
	p.rotation.y = 0.0
	await physics(4)
	p.interactor.refresh()
	check(p.interactor.target is Door and p.interactor.target.prompt() == "回到 · 回霜渡镇的木门", "北头：提示「回到 · 回霜渡镇的木门」")
	p.interactor.use()
	await seconds(0.45)
	main = await reload_main(main)
	p = main.player
	await frames(3)
	check(main.area == "frostford" and flat(p.global_position).distance_to(Vector2(0, 9.9)) < 0.3 and absf(p.rotation.y) < 0.05, "回到主街：站在南门里、面朝街道")
	await free_main(main)
	GameState.pending_load = {}
	GameState.new_game(1)
