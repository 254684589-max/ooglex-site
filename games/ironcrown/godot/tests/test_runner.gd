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
	dog.wait_time = 1200.0                      # 整个测试跑多久算卡死（2026-10-26：加了火把、第一夜潮水以后全量超过 600 秒）
	dog.one_shot = true
	dog.timeout.connect(func():
		print("WATCHDOG TIMEOUT in group: ", current_group)
		get_tree().quit(2))
	add_child(dog)
	dog.start()
	get_tree().root.size = Vector2i(1280, 720)   # 无头模式默认窗口只有 64×64，界面与触屏测试按电脑窗口算
	Settings.set_value("third_person", false)    # 上一次测试被中断时，设置文件里可能留着第三人称（Settings 在测试开始前已经读过它）
	Engine.set_meta("ic_skip_opening", true)     # 开场（3.8）只在 opening 组里测，其余测试照旧从主街南头开始
	wipe_test_saves()
	await frames(2)
	only = Array(OS.get_cmdline_user_args())
	for g in ["boot", "ui", "move", "terrain", "look", "touch", "pause", "interact", "frostford", "perf", "dialogue", "checks", "quests", "melee", "enemies", "inventory", "growth", "saves", "areas", "chapel", "brawl", "nav", "birch", "ferry", "ending", "opening", "fullflow", "camera", "character", "battle", "squad", "morale", "troops", "armyperf", "chapters", "daypart", "travelmap", "ch1open", "edges", "areamap", "marsh", "reedwharf", "deepmarsh", "castle", "hall", "keep", "schedule", "ledger", "errands", "music", "outlaws", "heir", "prepare", "causeway", "dawn", "sleeper", "uniforms", "uniforms2", "looks", "highland", "flora", "yangji", "villagers", "cold", "mountainroad", "beacon19", "beaconpeople", "sleepercrowd", "torch", "firsttide", "day2", "sidequests2", "convoy", "ambush", "escort", "dawn2", "well", "ch2flow", "origin", "origin2", "origin3", "plain", "plainflora", "maidu"]:
		if not only.is_empty() and not only.has(g):
			continue
		print("\n== %s" % g)
		current_group = g
		await call("test_" + g)
	wipe_test_saves()
	Music.stop_now()                 # 背景音乐（M.1）：先停下、等一会儿让音频服务器放掉播放对象，不然退出时算泄漏
	await seconds(0.5)
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
	# 2026-10-04 手机实测后的说明文字
	main.touch_mode = true
	texts.append_array([main.bench_done_line(), "已满0123456789./%检定 · 约 [] 方框是升到下一级的进度，10 格满了技能 +1；后面的数字是已攒的进度 / 升级需要的进度",
		"竖线「｜」是 0：右边是好感、左边是敌意，每格约 20 点（−100 到 +100）"])
	main.touch_mode = false
	texts.append(main.bench_done_line())
	# 徒手格斗（3.3）
	texts.append_array([Birch.TEACH_DESKTOP, Birch.TEACH_TOUCH, "（求饶）"])     # 桦林（3.5）
	texts.append_array(Ferry.FERRYMAN_LINES + Ferry.THUG_LINES + ["◆ 动手了！✓ 渡口的无旗者都解决了。踢！包抄他！"])     # 渡口（3.6）
	for id in GameState.tips_data():                                       # 教学提示与开场（3.8）
		if not str(id).begins_with("_"):
			texts.append(str(GameState.tips_data()[id].desktop) + str(GameState.tips_data()[id].touch))
	texts.append_array([Opening.CALL_LINE, Opening.BELL_LINE, PauseMenu.HELP_DESKTOP, PauseMenu.HELP_TOUCH, "序章霜渡镇之夜灰鲸河畔 · 入夜轻触画面开始点击画面或按任意键开始声音教学提示◇ "])
	texts.append_array(EndingPanel.RECAP.values() + [EndingPanel.SEAL, "序章「霜渡镇之夜」完第一章 · 黑鹭堡开发中在雾里再走走从头再来", "雾里有人提着灯走下坡来……"])     # 尾声（3.7）
	texts.append("· （需要：枚银币（身上 枚））、")     # 3.9 灰色选项
	texts.append_array(Battle.ORDERS.values() + TouchControls.ORDER_LABELS.values() + ["◆ 小队 人：· 1 跟随 2 坚守 3 冲锋点「令」下命令◆ 小队："])     # 小队命令（B.2）
	texts.append("挡箭")     # 兵种（B.4）
	texts.append_array(["正在载入 第一章 · 黑鹭堡", "正在下载这一章的内容……", "已下载 1.2 / 3.4 MB", "× 没能载入：", "重试返回", "继续：第一章 · 黑鹭堡", "往鹭沼 · 黑鹭堡",
		"× 没能载入第一章 · 黑鹭堡，存档没读", "这一章的内容不在这个版本里", "正在下载别的章节，请稍等", "下载好了，但浏览器不让存（存储空间不够或隐私模式）",
		"下载的章节包打不开，请重试", "下载没能开始（错误 ）", "网络太慢，下载超时了", "网络出错了（），请检查网络后重试", "服务器没给这一章（HTTP ）"])     # 章节包（4.1）
	texts.append_array(Daypart.NAMES.values() + Daypart.CHANGE_TEXT.values())     # 时段（4.2）
	texts.append_array([Frostford.MANOR_DOOR_CH1, "维克托", "埃德里克", "栅门上挂着锁。玛蒂尔达头也不抬：「楼上的客人还没起。」"] + Tavern.PEDDLER_LINES_CH1 + Ferry.FERRYMAN_LINES_CH1 + [main.CH1_LATER])     # 第一章开场（4.3）
	texts.append_array(["旅行地图 · 北境西部", "关上地图", "出发去", "（你在这里）", " · 你在这里", "路：，到了是", "× ", "鹭 沼", "灰鲸河", "堤道", "北", "查看地图",
		"序章没有旅行地图，第一章起才有。", "这一章去不了那里。", "你就在这里。", "要先回到地图上的地方才能出发。", "从这里去不了，先到。", "从这里没有路过去。",
		"走到那里才能出发。", "出发的地方", "还没做好。", "自动存档没存上，先别走。", "走不了。"])     # 旅行地图（4.2）
	texts.append_array(AreaMap.texts())     # 地图册（3.11）：规格的标签和出口名、一带、页签、面板上的固定文字
	texts.append(str(GameState.tips_data().get("map", {})))
	for tid in Travel.data().get("places", {}):
		var tp: Dictionary = Travel.place(tid)
		texts.append(str(tp.name) + str(tp.blurb) + str(tp.get("depart_at", "")) + str(tp.get("pending", "")))
	for tr in Travel.data().get("routes", []):
		texts.append(str(tr.text))
	texts.append_array(["军阵基准测试进行中……（ 人，画质，不要操作）", "军阵基准测试结果（ 人，画质，电脑触屏设备）", "：平均 帧，最慢一帧 毫秒，绘制调用 ，逻辑约 — 毫秒"])     # 军阵基准（B.5）
	texts.append_array(["战况：人 +援军（士气 ）· 胜（溃逃）两边都打光了", "稳动摇快崩了", "◆ 的队长倒下了！溃逃了！来了 个援军", "撤！别打了！", "（援军）"])     # 士气与胜负（B.3）
	texts.append_array([main.HINT_BATTLE_DESKTOP, main.HINT_BATTLE_TOUCH, "◆ 开打！✓ 赢了！× 赢了……两边都打光了。（刷新页面再来一次）"] + BattleArena.VIEW_NAMES)     # 军阵试验场（B.1）
	for sd in BattleArena.SIDES.values():
		texts.append(str(sd.name))
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
				for t in dlg[did].nodes[nid].get("text_if", []):              # 按时段换的开场白（4.6）
					texts.append(str(t.text))
				for o in dlg[did].nodes[nid].options:
					texts.append(str(o.text))
	# 测试场、霜渡镇、酒馆都要查（1.5 发现：只查测试场，漏掉了霜渡镇领主宅邸大门上「宅邸」的「邸」）
	var town := await make_main(false)
	var inn := await make_area("tavern")
	var yard := await make_area("churchyard")
	var nave := await make_area("chapel")
	var woods := await make_area("birch")
	var dock := await make_area("ferry")
	var field := await make_area("battle")
	var marsh := await make_area("marsh")
	marsh.streamer.build_all()                     # 鹭沼（4.4）：分帧搭的块（客栈招牌、堤道头的指路牌）也搭出来再查
	var inn_room := await make_area("inn")         # 「歪桩」客栈（4.4b）
	var keep_yard := await make_area("castle")     # 黑鹭堡庭院（4.5a）
	var hall := await make_area("hall")            # 黑鹭堡大厅（4.5b）
	var sick := await make_area("sickroom")        # 病房、兵营（4.5c）
	var bunks := await make_area("barracks")
	var ledger_room := await make_area("counting")  # 账房（4.7a）
	var nodes: Array = main.find_children("*", "", true, false) + town.find_children("*", "", true, false) + inn.find_children("*", "", true, false) \
		+ yard.find_children("*", "", true, false) + nave.find_children("*", "", true, false) + woods.find_children("*", "", true, false) + dock.find_children("*", "", true, false) \
		+ field.find_children("*", "", true, false) + marsh.find_children("*", "", true, false) + inn_room.find_children("*", "", true, false) \
		+ keep_yard.find_children("*", "", true, false) + hall.find_children("*", "", true, false) \
		+ sick.find_children("*", "", true, false) + bunks.find_children("*", "", true, false) + ledger_room.find_children("*", "", true, false)
	texts.append_array(Marsh.VIEW_NAMES + [Surface.label("mud"), "水太深，你爬回了刚才站稳的地方。", " · "])     # 鹭沼（4.4a）
	texts.append_array(Inn.VIEW_NAMES + Inn.DRINKER_LINES + Inn.OLD_BOATMAN_LINES + [Inn.GATE_TEXT])            # 芦栈村的人说的话（4.4b，写在代码里）
	for k in MarshLayout.PEOPLE_LINES:
		texts.append_array(MarshLayout.PEOPLE_LINES[k])
	for k in MarshLayout.CAMP_LINES:                                                                            # 营地的人（4.4c）
		texts.append_array(MarshLayout.CAMP_LINES[k])
	texts.append_array(Castle.VIEW_NAMES + Hall.VIEW_NAMES + Hall.ENVOY_LINES + Hall.GUARD_LINES)               # 黑鹭堡（4.5a / 4.5b）
	texts.append_array(Sickroom.VIEW_NAMES + Sickroom.OSRIC_LINES + Barracks.VIEW_NAMES + Counting.VIEW_NAMES)                         # 病房、兵营（4.5c）
	for k in Barracks.SOLDIER_LINES:
		texts.append_array(Barracks.SOLDIER_LINES[k])
	for k in Castle.GUARD_LINES:
		texts.append_array(Castle.GUARD_LINES[k])
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
	dock.queue_free()
	field.queue_free()
	marsh.queue_free()
	inn_room.queue_free()
	keep_yard.queue_free()
	hall.queue_free()
	sick.queue_free()
	bunks.queue_free()
	ledger_room.queue_free()
	await frames(2)
	var missing := ""
	for text: String in texts:
		for i in text.length():
			var c: int = text.unicode_at(i)
			if c > 32 and not font.has_char(c) and not missing.contains(text[i]):
				missing += text[i]
	check(font != null and missing == "", "界面与场景标签的文字全部在内置字体子集里（%d 段，缺：%s）" % [texts.size(), missing])
	# 2026-10-09 重做字体子集：剧本（design/*.md）里的字也收进来了，后面章节的人名不用再等重做字体
	var cast := "伊薇特蜷鼾噜弑曦樵橘瞟辎鳟"
	var lack := ""
	for i in cast.length():
		if not font.has_char(cast.unicode_at(i)):
			lack += cast[i]
	check(font != null and lack == "", "字体子集里有剧本里的人名和二级字库的字（伊薇特……；缺：%s）" % lack)
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
	# —— 2026-10-23 场景美化二：烟囱冒烟、落雪
	var smokes := get_tree().get_nodes_in_group(Atmos.SMOKE_GROUP)
	var smoke_ok := smokes.size() == 6
	for sm: CPUParticles3D in smokes:
		smoke_ok = smoke_ok and sm.emitting and sm.global_position.y > 8.0
	print("IC_DBG smoke n=%d y=%s" % [smokes.size(), str(smokes.map(func(x): return snappedf((x as Node3D).global_position.y, 0.1)))])
	check(smoke_ok, "6 个烟囱都在冒烟（烟在烟囱顶上，%d 个）" % smokes.size())
	var snow := get_tree().get_nodes_in_group(Atmos.SNOW_GROUP)
	check(snow.size() == 1 and (snow[0] as Node).get_parent() == p and (snow[0] as CPUParticles3D).emitting, "户外在落雪（跟着玩家）")
	var photo_ok := true
	for k in Look.PHOTO:
		photo_ok = photo_ok and bool(Look.mat(k).get_meta("photo", false)) and Look.mat(k).albedo_texture != null
	check(photo_ok, "%d 种写实贴图材质全部加载（Poly Haven：石板路、石墙、灰泥、木板、石板瓦、雪、树皮、泥炭，2026-10-23 加黑鹭堡石墙、鹭沼湿泥和干岸）" % Look.PHOTO.size())
	check(Look.mat("castle").roughness_texture == null and Look.mat("castle").normal_texture != null and Look.mat("stone").roughness_texture != null,
		"新加的三套只带颜色和法线（不带 ARM，省包体）")
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
	# 贴地雾带在主角脚边淡出（2026-10-04 手机实测：第三人称时雾片以下的小腿被盖成灰白一截）
	await frames(2)
	var bands := get_tree().get_nodes_in_group("fog_band")
	check(bands.all(func(f): return (f.material_override.get_shader_parameter("clear_at") as Vector3).distance_to(p.global_position) < 0.05), "每片贴地雾带都跟着主角的位置在脚边淡出（clear_at，%d 片）" % bands.size())
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
	check(ov.bench_text.contains("按 Esc 打开菜单"), "电脑：结束语写「按 Esc 打开菜单」换画质")
	main.touch_mode = true
	check(main.bench_done_line().contains("点右上角「菜单」") and not main.bench_done_line().contains("Esc"), "手机：结束语写「点右上角『菜单』」，不提 Esc（2026-10-04 手机实测）")
	main.touch_mode = false
	# 触屏上生命 / 体力条在左上角：性能浮层放到它们下面（2026-10-04 手机实测：浮层压住了生命条）
	main.hud.bars_top = true
	main.place_perf_overlay()
	var bars := Rect2(main.hud.health_rect().position - Vector2(0, 22), Vector2(main.hud.BAR_W, main.hud.bar_rect().end.y - main.hud.health_rect().position.y + 22))
	check(ov.position.y > bars.end.y, "触屏：性能浮层在生命 / 体力条和它们的文字下面（浮层顶 %.0f，条底 %.0f）" % [ov.position.y, bars.end.y])
	main.hud.bars_top = false
	main.place_perf_overlay()
	check(is_equal_approx(ov.position.y, 44.0), "电脑：性能浮层仍在标题下面（体力条在左下角）")
	check(ov.get_index() < main.hud.get_index(), "性能浮层画在 HUD 底下：短提示叠上来时字在上面")
	Settings.set_value("show_perf", false)
	Settings.set_value("quality", "")                  # 上面在暂停菜单里点过低画质，记进了设置：放回自动，别带进后面的测试组
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
	# —— 3.9：剧情条件满足、只差银币或物品的选项灰色显示「需要……」；会剧透的（locked: hide）照旧隐藏
	GameState.new_game(5)
	var o30 := {"text": "给钱", "if": [{"silver": 30}]}
	check(DialogueRunner.option_state(o30) == "locked" and DialogueRunner.option_needs(o30) == "30 枚银币（身上 12 枚）", "只差银币：灰色，写明要 30 枚、身上 12 枚（%s）" % DialogueRunner.option_needs(o30))
	check(DialogueRunner.option_state({"text": "x", "if": [{"silver": 30}, {"flag": "offer_parley"}]}) == "hide", "剧情条件不满足：照旧隐藏（不剧透）")
	check(DialogueRunner.option_state({"text": "x", "if": [{"has_item": "hire_letter"}], "locked": "hide"}) == "hide", "写了 locked: hide 的：差物品时也隐藏")
	check(DialogueRunner.option_needs({"text": "x", "if": [{"has_item": "hire_letter"}, {"silver": 30}]}) == "雇佣信、30 枚银币（身上 12 枚）", "差好几样：用顿号连起来")
	GameState.add_silver(30)
	check(DialogueRunner.option_state(o30) == "show", "银币够了：能选")
	var bad_locked := {"start": "a", "nodes": {"a": {"text": "t", "options": [{"text": "x", "end": true, "locked": "maybe"}]}}}
	check(DialogueRunner.validate(bad_locked).any(func(e): return str(e).contains("locked")), "校验：locked 只能写 hide，而且要有银币或物品条件")
	GameState.new_game(5)
	var lr := DialogueRunner.new()
	lr.start("ferry", "offer")
	lr.node_id = "why"
	var locked_texts: Array = lr.entries().filter(func(e): return e.locked).map(func(e): return [str(e.option.text).left(6), e.need])
	check(locked_texts.size() == 2 and locked_texts[0] == ["（亮出雇佣信", "雇佣信"] and str(locked_texts[1][1]).begins_with("30 枚银币"), "渡口奥弗：没有雇佣信、钱不够时，两个选项灰色显示（%s）" % [locked_texts])
	check(lr.options().size() == lr.entries().size() - 2 and not lr.options().any(func(o): return str(o.text).contains("雇佣信")), "灰色的选项不算在能选的里面（数字键、下标不变）")
	GameState.add_item("hire_letter")
	check(lr.entries().filter(func(e): return e.locked).size() == 1 and lr.options().any(func(o): return str(o.text).contains("雇佣信")), "拿到雇佣信：那个选项变成能选")
	lr.start("chapel", "alban")
	check(not lr.entries().any(func(e): return str(e.option.text).contains("墓室里找到的信")), "修士：没找到墓室里的信时，「把信递给他」照旧隐藏（不剧透）")
	# 面板：灰色的选项不编号、点不了、方向键跳过；能选的照旧 1、2、3……
	GameState.new_game(5)
	GameState.silver = 0
	main = await make_main(false)
	dp = main.dialogue
	dp.open("tavern", "matilda")
	await frames(2)
	var lb: Button = dp.locked_buttons[0] if not dp.locked_buttons.is_empty() else null
	check(lb != null and lb.text == "· 来块面包。（2 银币）（需要：2 枚银币（身上 0 枚））" and lb.disabled and lb.focus_mode == Control.FOCUS_NONE, "玛蒂尔达：没钱买面包，选项灰色、写明还差什么（%s）" % (lb.text if lb else "-"))
	var nums: Array = dp.buttons.map(func(b): return str(b.text).left(2))
	check(nums == ["1.", "2."] and dp.options_box.get_child_count() == 3, "能选的选项照旧编号 1、2，灰色的不编号（%s）" % [nums])
	check(dp.options_box.get_child(0) == lb and str(dp.buttons[0].text).contains("镇上最近怎么样"), "灰色的选项留在原来的位置（「镇上最近怎么样？」前面；新游戏时前两个剧情选项隐藏）")
	dp.close()
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
		# 代码里设置的（set_in 写着 .gd，例如开场的 opening_done）不在对话里找
		if not f.begins_with("_") and not str(reg[f].get("set_in", "")).contains(".gd") and not text.contains('"set": "%s"' % f) and not text.contains('"win": "%s"' % f) and not text.contains('"lose": "%s"' % f):
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
	check(lbl == "[洞察检定 · 约 60%] 你还看见了别的，对吧？", "检定选项前面直接显示技能和成功的百分比（%s）" % lbl)
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
	check(dp.buttons[1].text.contains("[洞察检定 · 约 60%]"), "对话面板里的检定选项显示成功的百分比（%s）" % dp.buttons[1].text)
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
			var want := str(q.stages[st].get("advance_when", {}).get("has_item", ""))
			if want != "" and GameState.item(want).is_empty():
				bad.append("%s/%s 等的物品 %s 不存在" % [qid, st, want])
			var fl := str(q.stages[st].get("advance_when", {}).get("flag", ""))
			if fl != "" and not GameState.flag_registry().has(fl):
				bad.append("%s/%s 等的旗标 %s 没有登记" % [qid, st, fl])
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
	var off: Array = []
	for key in ["l3_wind", "l3_end", "d_wind", "d_end", "broken"]:
		m.view.set_pose(m.view.pose(key))
		if not p.camera.is_position_in_frustum(m.view.global_position):
			off.append(key)
	m.view.set_pose(m.view.pose("rest"))
	check(off.is_empty(), "A.1b 新姿势（第三段劈砍、冲刺突刺、被破防）：剑柄都在画面里（出画的：%s）" % [off])
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
	# —— A.1b：闪避与冲刺突刺（第一人称）
	check(DamageCalc.compute(10.0, 5, 15, "dash") == 17, "冲刺突刺 × 1.4 = 17（介于轻击 12 和重击 22 之间）")
	check(Melee.wants_dodge(true, Vector2(1, 0)) and Melee.wants_dodge(true, Vector2(0, 1)) and Melee.wants_dodge(true, Vector2(-0.7, 0.7)),
		"拿着武器往右、往后、往左后跳 = 闪避")
	check(not Melee.wants_dodge(true, Vector2(0, -1)) and not Melee.wants_dodge(true, Vector2.ZERO) and not Melee.wants_dodge(false, Vector2(1, 0)),
		"往前跳、原地跳、收着剑往侧面跳：照旧是跳")
	GameState.new_game(1)
	main = await make_main(true)
	p = main.player
	m = p.melee
	await place(p, 0.0, 10.0)
	p.touch_move = Vector2(1.0, 0.0)
	p.request_jump()
	await physics(3)
	check(not m.dodging() and p.velocity.y > 0.0, "收着剑往侧面跳：真的跳起来")
	p.touch_move = Vector2.ZERO
	await seconds(1.0)
	m.toggle_draw()
	await melee_tick(0.5)
	var st0 := m.stamina
	var hp0 := m.health
	p.touch_move = Vector2(-1.0, 0.0)
	p.request_jump()
	await physics(3)
	check(m.dodging() and p.velocity.y <= 0.01 and p.velocity.x < -3.0, "拔着剑往左跳：闪避，身体往左冲（%.1f 米 / 秒）" % p.velocity.x)
	check(absf(m.stamina - (st0 - Melee.DODGE_COST)) < 0.5, "闪避花 %d 点体力（%.1f → %.1f）" % [int(Melee.DODGE_COST), st0, m.stamina])
	check(m.receive_hit({"damage": 10, "kind": "light", "attacker": null}) == "dodge" and m.health == hp0, "闪避前段：刀砍不着你")
	check(m.receive_hit({"damage": 3, "kind": "arrow", "attacker": null}) == "hit", "箭照样射得中")
	check(p.camera.position.y < -0.02, "第一人称闪避：镜头往下沉（%.2f 米）" % p.camera.position.y)
	p.touch_move = Vector2.ZERO
	await seconds(0.6)
	check(m.state == Melee.State.IDLE and m.view.visible, "闪避结束：回到持剑")
	m.stamina = 5.0
	p.touch_move = Vector2(1.0, 0.0)
	p.request_jump()
	await physics(3)
	check(not m.dodging() and p.is_on_floor(), "体力不够：闪不了（也不会变成跳）")
	p.touch_move = Vector2.ZERO
	m.stamina = m.stamina_max()
	await seconds(0.5)
	var z0 := p.global_position.z
	var kd: Array = []
	m.swung.connect(func(k: String): kd.append(k))
	p.touch_move = Vector2(0, -1.0)
	await seconds(0.4)
	check(p.running, "推到底在跑")
	m.press()
	await frames(2)
	m.release()
	check(kd == ["dash"] and m.state == Melee.State.WINDUP, "跑着按攻击：冲刺突刺，不蓄力")
	p.touch_move = Vector2.ZERO
	await seconds(0.15)
	check(p.velocity.length() > 4.0, "突刺时身体往前冲（%.1f 米 / 秒）" % p.velocity.length())
	await seconds(0.8)
	check(m.state == Melee.State.IDLE and z0 - p.global_position.z > 2.0, "突刺收招，回到持剑")
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
	a._strike_target()
	check(m.health == 100 - DamageCalc.compute(8, 4, 5, "light", false, 3.0) and m.health == 92, "穿棉甲（护甲 3）挨棍手一下：9 → 8（剩 %d）" % m.health)
	GameState.add_item("mail_shirt")
	GameState.equip("mail_shirt")
	check(GameState.armor_total() == 8.0 and GameState.has_item("padded_jacket") and not GameState.is_equipped("padded_jacket"), "换上锁甲衫：护甲 8，棉甲换下来")
	a._strike_target()
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
	# 2026-10-04 所有者问「方框是什么意思」：技能进度条后面写数字，两段都有一行说明
	var sw_line: String = cp.box.find_children("*", "Label", true, false).map(func(l): return l.text).filter(func(t): return t.begins_with("剑术 "))[0]
	var sw_need := CharacterPanel._num(GameState.skill_need(int(GameState.skills.blade)))
	check(sw_line.ends_with("/" + sw_need) and not sw_line.contains(".0/") and all_text.contains("方框是升到下一级的进度") and all_text.contains("    用剑命中、格挡时提升"), "技能进度条后面写「已攒/需要」的数字（剑术 %d 升级要 %s 点：%s），说明另起一行" % [GameState.skills.blade, sw_need, sw_line])
	check(CharacterPanel._num(0.5) == "0.5" and CharacterPanel._num(3.2) == "3.2" and CharacterPanel._num(5.0) == "5", "进度数字：整数不带小数点，打木桩的半次保留一位")
	check(all_text.contains("竖线「｜」是 0"), "声望上面一行说明：竖线是 0、每格约 20 点")
	check(CharacterPanel.progress_text("blade", GameState.SKILL_MAX) == "已满", "技能练满了写「已满」")
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
	check(hud.title_label.text == Hud.TITLE_SHORT and hud.title_label.get_minimum_size().x + 16.0 < hud.char_btn.position.x, "窄屏：标题缩短，不和右上角五个按钮重叠")
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
	# 对话：临时换成第一人称镜头、藏起人物和触屏按钮；对话结束后还原（2026-10-04 手机实测：竖屏时主角挡住说话人）
	var npc: Npc = main.world.get_children().filter(func(c): return c is Npc)[0]
	main.touch.visible = true
	main.open_dialogue("frostford", "watchman", npc)
	await frames(2)
	check(p.camera.position.length() < 0.01 and not p.avatar.visible and Settings.third_person, "第三人称里对话：镜头收回眼睛、看不到主角，设置仍是第三人称")
	check(not main.touch.visible, "对话时藏起触屏按钮（暂停时它们本来就不响应）")
	main.dialogue.close()
	await physics(30)
	check(p.avatar.visible and main.touch.visible and p.camera.position.length() > 1.0, "对话结束：主角重新出现、触屏按钮回来、相机退回肩后（%.2f 米）" % p.camera.position.length())
	main.touch.visible = false
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
	for a in map.attacks.light:
		light_ok = light_ok and float(a.get("from", 0.0)) < float(a.impact)
	check(light_ok and (map.attacks.light as Array).size() == 3, "轻击三个动作（第三段给剑术「连环」），起点 < 命中时刻 < 动作长度")
	# A.1b：冲刺突刺、收招、闪避、落地
	var dm: Dictionary = map.attacks.dash
	var dt: Dictionary = Melee.TIMING.dash
	var dash_scale := float(dm.impact) / (float(dt.wind) + float(dt.strike) * float(dt.hit_at))
	check(float(dm.impact) < lib.get_animation(dm.clip).length and dash_scale > 0.8 and dash_scale < 2.2, "冲刺突刺：命中时刻在动作之内，播放速度 ×%.2f" % dash_scale)
	var c3: Dictionary = map.attacks.light[2]
	var l3t: Dictionary = Melee.TIMING.light
	var c3_scale := (float(c3.impact) - float(c3.from)) / (float(l3t.wind) + float(l3t.strike) * float(l3t.hit_at))
	check(c3.clip == "Sword_Regular_C" and c3_scale > 0.8 and c3_scale < 2.2, "第三段从头顶劈下：跳过举剑的准备，播放速度 ×%.2f" % c3_scale)
	var rc: Dictionary = map.attacks.recover
	check(lib.has_animation(str(rc.Sword_Regular_A)) and lib.has_animation(str(rc.Sword_Regular_B)), "轻击两段各有收招动作")
	var dg: Dictionary = map.dodge
	var dodge_scale := (float(dg.to) - float(dg.from)) / Melee.DODGE_TIME
	check(float(dg.from) < float(dg.to) and float(dg.to) < lib.get_animation(map.roles.dodge).length and dodge_scale > 1.0 and dodge_scale < 2.2,
		"闪避：只播翻滚的中段，播放速度 ×%.2f" % dodge_scale)
	check(float(map.land.speed) * float(map.land.time) < lib.get_animation(map.roles.land).length, "落地屈膝的那段在动作之内")
	# 动作播放速度对齐近战判定的命中帧（改了 Melee.TIMING 之后动作不会变得离谱）
	var lt: Dictionary = Melee.TIMING.light
	var light_scale := float(CharacterModel.light_attack(map, 0).impact) / (float(lt.wind) + float(lt.strike) * float(lt.hit_at))
	var ht: Dictionary = Melee.TIMING.heavy
	var heavy_scale := (float(h.impact) - float(h.wind_peak)) / (float(ht.strike) * float(ht.hit_at))
	check(light_scale > 0.8 and light_scale < 2.2, "轻击动作播放速度 ×%.2f（0.8–2.2 内）" % light_scale)
	check(heavy_scale > 0.5 and heavy_scale < 1.8, "重击劈下的播放速度 ×%.2f（0.5–1.8 内）" % heavy_scale)
	check(CharacterModel.light_attack(map, 0).clip == "Sword_Regular_A" and CharacterModel.light_attack(map, 1).clip == "Sword_Regular_B" and CharacterModel.light_attack(map, 2).clip == "Sword_Regular_C", "轻击连击：第一段 A、第二段 B、第三段（剑术专长）C 从头顶劈下")
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
	# —— A.2b：主角的衣服与披风
	var parts_names: Array = c.parts.map(func(x): return str(x).get_file().get_basename())
	check(parts_names.has("Outfit_Male_Ranger") and parts_names.has("Head_Male") and parts_names.has("Hair_Beard"), "主角穿上游侠那套衣服，有头、发型和胡子（%s）" % [parts_names])
	var hood := c.scene_root.find_child("Male_Ranger_Head_Hood", true, false) as Node3D
	check(hood != null and not hood.visible, "兜帽摘下来了（藏起来，不删）")
	check(av.cape == null and av.gear != null and av.gear.is_inside_tree(), "主角背上是剑鞘和皮带，没有披风（所有者说去掉）")
	check(av.gear.hilt.visible and (av.gear.get_parent() as BoneAttachment3D).bone_name == "spine_03", "剑在鞘里：肩后露出剑柄；剑鞘挂在上身的骨头上")
	var hilt_y := (av.gear.hilt.global_transform * (av.gear.hilt as MeshInstance3D).get_aabb().get_center()).y - p.global_position.y
	check(hilt_y > 1.4 and hilt_y < 1.9, "剑柄在肩膀高度（离地 %.2f 米）" % hilt_y)
	# 披风（Cape）现在没人背，代码留着：测试时临时挂一件
	var cp := Cape.make(c, Color("5e2420"))
	av.add_child(cp)
	await seconds(0.6)
	check(cp.is_inside_tree() and cp.top_level and cp.mesh.get_surface_count() == 1, "披风（代码搭的布）挂得上")
	var cf := cp._frame()
	var mid_bottom: Vector3 = cp.pos[(Cape.ROWS - 1) * Cape.COLS + Cape.COLS / 2]
	var behind := (mid_bottom - (cf.spine as Vector3)).dot(cf.back)
	var drop: float = (cf.neck as Vector3).y - mid_bottom.y
	check(behind > 0.05 and drop > 0.8 and drop < 1.5, "站着：披风垂在背后（下摆在脊椎后 %.2f 米、脖子下 %.2f 米）" % [behind, drop])
	var nan_free := true
	for q in cp.pos:
		nan_free = nan_free and is_finite(q.x) and is_finite(q.y) and is_finite(q.z)
	check(nan_free, "披风的点都是正常的数")
	p.touch_move = Vector2(0, -0.5)
	await seconds(0.5)
	check(c.role == "walk" and c.playing() == "Walk_Loop" and c.anim.get_playing_speed() > 1.0, "半推摇杆：走路动作（加速 ×%.2f）" % c.anim.get_playing_speed())
	p.touch_move = Vector2(0, -1.0)
	await seconds(0.5)
	check(c.role == "run" and c.playing() == "Jog_Fwd_Loop" and absf(c.anim.get_playing_speed() - 1.0) < 0.25, "推到底：跑步动作（×%.2f）" % c.anim.get_playing_speed())
	var rf := cp._frame()
	var run_bottom: Vector3 = cp.pos[(Cape.ROWS - 1) * Cape.COLS + Cape.COLS / 2]
	var run_behind := (run_bottom - (rf.spine as Vector3)).dot(rf.back)
	check(run_behind > behind + 0.1 and run_behind < 0.6, "跑起来：披风往后飘一些，不飘成水平（下摆离脊椎 %.2f 米，站着时 %.2f）" % [run_behind, behind])
	p.touch_move = Vector2.ZERO
	await seconds(0.3)
	var sf := cp._frame()
	var swing := 0.0
	for k in Cape.COLS:
		swing = maxf(swing, absf((cp.pos[(Cape.ROWS - 1) * Cape.COLS + k] - (sf.spine as Vector3)).dot(sf.right)))
	check(swing < Cape.WIDTH_BOTTOM * 0.5 + Cape.SIDE_SLACK + 0.05, "猛地停下：披风不甩到身体侧面去（下摆离中线最远 %.2f 米）" % swing)
	await place(p, 40.0, -30.0)
	await seconds(0.2)
	var tf := cp._frame()
	var far := 0.0
	for q in cp.pos:
		far = maxf(far, q.distance_to(tf.neck))
	check(far < Cape.LENGTH + 0.5, "传送以后披风重新垂下来，不会拉成长条（最远的点离脖子 %.2f 米）" % far)
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
	check(not av.gear.hilt.visible and av.weapon_mesh.visible, "拔剑后：剑在手里，背上只剩空鞘")
	var rec: Array = []
	m.hit.connect(func(_t, _info): rec.append([c.playing(), c.anim.current_animation_position]))
	m.press()
	m.release()
	await seconds(0.3)
	check(rec.size() == 1 and rec[0][0] == "Sword_Regular_A" and absf(rec[0][1] - float(map.attacks.light[0].impact)) < 0.08, "轻击第一段：命中帧时动作正好在挥到最前（%s，第 %.2f 秒，目标 %.2f）" % [rec[0][0] if rec.size() > 0 else "-", rec[0][1] if rec.size() > 0 else -1.0, float(map.attacks.light[0].impact)])
	check(m.state == Melee.State.RECOVER and c.playing() == "Sword_Regular_A_Rec", "收招：接上第一段的收势动作（%s）" % c.playing())
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
	m.receive_hit({"damage": 4, "kind": "light", "attacker": null})
	await frames(3)
	check(c.role == "hit_head" and c.playing() == "Hit_Head", "再挨一下：换成头部受击，不是每次一样（%s）" % c.playing())
	await seconds(0.7)
	check(c.role == "idle_armed", "受击动作播完回到待机（%s）" % c.role)
	m.stagger_left = 0.6
	await frames(3)
	check(c.role == "stagger" and c.playing() == "Hit_Knockback", "失衡：被击退的动作（%s）" % c.playing())
	m.stagger_left = 0.0
	await seconds(0.5)
	# —— A.1b：破防踉跄、第三段劈砍、冲刺突刺、闪避、落地
	m.block_press()
	await seconds(0.3)
	m.stamina = 2.0
	m.receive_hit({"damage": 10, "kind": "light", "attacker": null})
	await frames(3)
	check(m.stagger_kind == "guard_break" and c.role == "guard_break" and c.playing() == "Idle_Shield_Break", "体力不够挡、格挡被打破：踉跄动作（%s）" % c.playing())
	m.block_release()
	m.health = m.health_max()
	await seconds(1.2)
	m.stamina = m.stamina_max()
	GameState.skills.blade = 25
	rec.clear()
	for i in 3:
		m.press()
		m.release()
		await seconds(0.3)
	await seconds(0.4)
	check(rec.size() == 3 and rec[2][0] == "Sword_Regular_C" and absf(rec[2][1] - float(map.attacks.light[2].impact)) < 0.08,
		"剑术 25「连环」：第三段从头顶劈下，命中帧对齐（%s，第 %.2f 秒；%s）" % [rec[2][0] if rec.size() > 2 else "-", rec[2][1] if rec.size() > 2 else -1.0, rec])
	GameState.skills.blade = 0
	await seconds(1.0)
	await place(p, 0.0, 10.0)
	m.stamina = m.stamina_max()
	var kinds: Array = []
	m.swung.connect(func(k: String): kinds.append(k))
	p.touch_move = Vector2(0, -1.0)
	await seconds(0.5)
	m.press()
	await frames(3)
	m.release()
	await frames(2)
	check(kinds.back() == "dash" and c.playing() == "Sword_Dash", "跑着出剑：冲刺突刺（%s）" % c.playing())
	p.touch_move = Vector2.ZERO
	await seconds(1.0)
	check(m.state == Melee.State.IDLE, "突刺收招，回到持剑")
	await place(p, 0.0, 10.0)
	m.stamina = m.stamina_max()
	var start := p.global_position
	p.touch_move = Vector2(1.0, 0.0)
	p.request_jump()
	await frames(3)
	check(m.dodging() and c.role == "dodge" and c.playing() == "Roll" and c.anim.get_playing_speed() > 0.0, "拿着剑往右跳：闪避，翻滚动作（%s）" % c.playing())
	await seconds(0.25)
	check(absf(av.face_deg - 90.0) < 20.0, "往右闪：身体转向右边滚（偏转 %.0f°）" % av.face_deg)
	p.touch_move = Vector2.ZERO
	await seconds(0.5)
	var moved := p.global_position - start
	check(not m.dodging() and moved.x > 1.2 and absf(moved.z) < 0.5 and p.is_on_floor(), "闪避结束：往右闪开 %.1f 米，没有跳起来" % moved.x)
	m.stamina = m.stamina_max()
	p.touch_move = Vector2(0.0, 1.0)
	p.request_jump()
	await frames(3)
	check(m.dodging() and c.anim.get_playing_speed() < 0.0, "往后跳：往后闪，翻滚倒着播（×%.2f）" % c.anim.get_playing_speed())
	p.touch_move = Vector2.ZERO
	await seconds(0.8)
	# 从高处落下：屈膝
	await place(p, 0.0, 10.0)
	p.global_position.y += 2.0
	await seconds(0.85)
	check(c.role == "land" and c.playing() == "Jump_Land", "从 2 米高处落下：落地屈膝（%s）" % c.playing())
	await seconds(0.8)
	check(c.role == "idle_armed", "屈膝之后回到持剑待机（%s）" % c.role)
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
	check(main.hud.toast_label.text == "「倒钩鱼」酒馆" and main.hud.hint_label.text != main.HINT_DESKTOP, "进门提示区域名，不再显示开场的操作提示")
	check(main.tip_now == "save" and main.hud.hint_label.text == str(GameState.tips_data().save.desktop), "第一次走进别处：教学提示讲自动存档（3.8）")
	var auto := Saves.read_slot("auto")
	check(auto.has("data") and auto.data.scene == "tavern", "进入新区域自动存档（GDD 第十节）")
	await seconds(0.5)
	check(main.fade.color.a < 0.05, "黑屏淡出，看得见酒馆")
	check(not main.moon.visible and main.env.fog_mode == Environment.FOG_MODE_EXPONENTIAL and main.env.background_color.r < 0.1, "室内：没有月光，换成暖暗的环境光和薄烟")
	var omni := main.find_children("*", "OmniLight3D", true, false)
	var fire := omni.filter(func(l): return l is Tavern.FireLight)
	check(omni.size() == 4 and fire.size() == 2, "四盏光：炉火、吧台油灯、桌上蜡烛，加门边墙上的火把（2026-10-23 美化）（%d）" % omni.size())
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
	check(speech_i >= 0 and labels[speech_i].contains("口才检定 · 约 "), "口才选项显示成功的百分比（%s）" % (labels[speech_i] if speech_i >= 0 else "没有"))
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
	check(c.playing() == "Melee_Hook" and c.anim.get_playing_speed() == 0.0 and absf(c.anim.current_animation_position - float(fh.wind_peak)) < 0.02, "按住蓄重拳：勾拳拉到最开停住（第 %.2f 秒）" % c.anim.current_animation_position)
	m.release()
	await seconds(0.5)
	check(rec.size() == 1 and rec[0][0] == "Melee_Hook" and absf(rec[0][1] - float(fh.impact)) < 0.08, "重拳：松手勾出去，命中帧对齐（第 %.2f 秒，目标 %.2f）" % [rec[0][1] if rec.size() > 0 else -1.0, float(fh.impact)])
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
	# 南头去渡口的路：3.6 起能走
	var south: Door = main.find_children("*", "Door", true, false).filter(func(d): return d.display_name == "去渡口的路")[0]
	check(not south.locked and south.to_area == "ferry" and south.prompt() == "前往 · 去渡口的路", "南头去渡口的路：能走（3.6，前往渡口）")
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


## 3.6 渡口：码头、渡船、雾中的河面；「灰手」奥弗（付钱 / 口才 / 威吓，说崩了就动手：会踢、半血喊包抄）；塞拉斯与埃德里克说出借据的事
func test_ferry() -> void:
	check(Areas.known("ferry") and not Areas.is_indoor("ferry") and Areas.nav_bounds("ferry").has_volume(), "新区域：渡口（室外，烘焙导航网格）")
	# —— 桦林南头 → 渡口
	GameState.new_game(71)
	GameState.start_quest("edric_missing")
	GameState.pending_load = {"scene": "birch", "spawn": "south", "player": {}}
	var main := await make_main(false)
	var p: FpController = main.player
	await frames(3)
	check(main.area == "birch" and flat(p.global_position).distance_to(Vector2(0, Birch.SOUTH - 3.2)) < 0.3, "桦林南头有出生点（从渡口回来站这里）")
	await place(p, 0.0, Birch.SOUTH - 1.7)
	p.rotation.y = PI
	await physics(4)
	p.interactor.refresh()
	check(p.interactor.target is Door and p.interactor.target.prompt() == "前往 · 去渡口的路", "桦林南头：提示「前往 · 去渡口的路」")
	p.interactor.use()
	await seconds(0.45)
	main = await reload_main(main)
	p = main.player
	await frames(3)
	check(main.area == "ferry" and flat(p.global_position).distance_to(Vector2(0, Ferry.NORTH + 3.5)) < 0.3 and absf(absf(p.rotation.y) - PI) < 0.05, "到了渡口北头、面朝河")
	check(main.moon.visible and not main.nav.is_empty(), "渡口是室外，有导航网格（%d 个多边形）" % int(main.nav.get("polygons", 0)))
	var group := main.get_tree().get_nodes_in_group(Encounter.group_name(Ferry.ENCOUNTER))
	var gnames: Array = group.map(func(n): return n.display_name)
	gnames.sort()
	check(group.size() == 3 and gnames == ["「灰手」奥弗", "无旗者", "无旗者"] and group.all(func(n): return n is Npc and n.has_meta("enemy_kind")), "码头根上站着「灰手」奥弗和两个手下（还没动手，是 NPC）")
	var names: Array = main.find_children("*", "Npc", true, false).map(func(n): return n.display_name)
	check(names.has("埃德里克") and names.has("塞拉斯") and names.has("渡工"), "码头上是埃德里克和塞拉斯，渡工在小屋门口")
	var edric: Npc = main._npc_by_dialogue("edric")
	check(edric.global_position.z > Ferry.PIER_END - 4.0 and edric.global_position.y > 0.2, "埃德里克在码头尽头（站在码头面上）")
	var r := DialogueRunner.new()
	r.start("ferry", "silas")
	check(r.node_id == "tense", "奥弗还在：塞拉斯叫你先把他打发了")
	r.start("ferry", "edric")
	check(r.node_id == "tense", "奥弗还在：埃德里克吓得发白")
	# 码头：走得上去，掉不下水
	await place(p, 2.1, -3.0)
	await hold("move_forward", 0.1)
	await place(p, 2.1, 4.5)
	await physics(10)
	check(p.global_position.y > 0.2 and p.is_on_floor(), "能站上码头（码头面高 %.2f 米）" % p.global_position.y)
	p.rotation.y = PI / 2
	await hold("move_forward", 1.5)
	check(p.global_position.x > Ferry.PIER_X0 - 0.1 and p.global_position.y > 0.2, "码头边有栏杆：掉不下水（x = %.2f）" % p.global_position.x)
	await place(p, 6.0, -3.0)
	p.rotation.y = PI
	await hold("move_forward", 2.0)
	check(p.global_position.z < Ferry.SHORE_Z + 0.2, "岸边走不进河里（z = %.2f）" % p.global_position.z)
	# —— 付钱：奥弗带人走
	GameState.silver = 40
	var rep0 := GameState.get_rep("outlaws")
	r.start("ferry", "offer")
	check(r.node_id == "greet" and GameState.has_flag("offer_parley"), "和奥弗搭话")
	r.choose(0)
	var labels: Array = r.options().map(func(o): return DialogueRunner.option_label(o))
	check(r.node_id == "why" and labels.any(func(l): return l.contains("30 枚银币")) and labels.any(func(l): return l.contains("威吓")) and not labels.any(func(l): return l.contains("雇佣信") or l.contains("蜡印")), "奥弗：想把两个人一起劫走；能付钱、能说、能吓（没有雇佣信时没有亮信的选项）")
	r.choose(labels.find(labels.filter(func(l): return l.contains("30 枚银币"))[0]))
	check(r.node_id == "paid" and GameState.silver == 10 and GameState.has_flag("offer_left") and GameState.get_rep("outlaws") == rep0 + 10, "付 30 枚银币：奥弗收钱走人（无旗者声望 +10）")
	r.choose(0)
	check(GameState.pending_leave == "ferry_offer", "对话结束时：这一伙人要走")
	main._on_dialogue_closed()
	await frames(2)
	check(main.get_tree().get_nodes_in_group(Encounter.group_name(Ferry.ENCOUNTER)).is_empty() and not main.in_combat(), "奥弗一伙走了，没打起来")
	r.start("ferry", "silas")
	check(r.node_id == "greet", "奥弗走了：塞拉斯肯好好说话了")
	await free_main(main)
	# 读档：说服走了的，不再出现
	GameState.pending_load = {"scene": "ferry", "player": {}}
	main = await make_main(false)
	await frames(3)
	check(main.area == "ferry" and main.get_tree().get_nodes_in_group(Encounter.group_name(Ferry.ENCOUNTER)).is_empty() and main.get_tree().get_nodes_in_group("enemy").is_empty(), "再来渡口：奥弗一伙不在了")
	await free_main(main)
	# —— 有雇佣信：亮信的口才检定更容易
	var sd := seed_for("offer_letter_speech", "speech", 11, true)
	GameState.new_game(sd)
	GameState.add_item("hire_letter")
	r.start("ferry", "offer")
	r.choose(0)
	labels = r.options().map(func(o): return DialogueRunner.option_label(o))
	var li: int = labels.find(labels.filter(func(l): return l.contains("蜡印"))[0])
	var ei: int = labels.find(labels.filter(func(l): return l.contains("灰鲸河两岸"))[0])
	check(GameState.check_chance("speech", 11) > GameState.check_chance("speech", 16) and labels[li].contains("口才"), "有雇佣信：亮信的说法把握更大（%s / %s）" % [labels[li].left(12), labels[ei].left(12)])
	r.choose(li)
	check(r.node_id == "convinced" and GameState.has_flag("offer_left"), "亮出雇佣信说动了奥弗：双钥港的人不会给他们留活路")
	# —— 威吓没吓住：动手
	sd = seed_for("offer_intimidate", "intimidate", 15, false)
	GameState.new_game(sd)
	GameState.start_quest("edric_missing")
	GameState.set_stage("edric_missing", "warned")
	GameState.add_item("hire_letter")
	GameState.add_item("edric_letter")
	GameState.pending_load = {"scene": "ferry", "player": {}}
	main = await make_main(false)
	p = main.player
	await frames(3)
	var offer_npc: Npc = main._npc_by_dialogue("offer")
	await aim(p, Vector3(2.1, 0.3, 0.7), offer_npc.global_position + Vector3(0, 1.5, 0))
	check(p.interactor.target == offer_npc, "对准奥弗")
	p.interactor.use()
	await frames(2)
	check(main.dialogue.visible and main.dialogue.runner.id == "offer", "奥弗的对话能打开")
	find_button(main.dialogue, "我来接瓦伦家的少爷。").pressed.emit()
	await frames(1)
	find_button(main.dialogue, "滚。不然今晚渡口多几具尸体。").pressed.emit()
	await frames(1)
	check(main.dialogue.runner.node_id == "laugh", "威吓没吓住：奥弗笑着抽出剑")
	find_button(main.dialogue, "（拔剑）").pressed.emit()
	await frames(3)
	var enemies: Array = main.get_tree().get_nodes_in_group("enemy")
	var boss: Enemy = null
	for e in enemies:
		if e.kind == "outlaw_boss":
			boss = e
	check(main.encounter_active() and enemies.size() == 3 and boss != null and boss.display_name == "「灰手」奥弗" and enemies.all(func(e): return e.state == Enemy.State.COMBAT), "动手了：奥弗和两个手下换成敌人，直接进入战斗")
	check(main.get_tree().get_nodes_in_group(Encounter.group_name(Ferry.ENCOUNTER)).is_empty(), "原来站着的 NPC 撤掉了")
	var went: bool = await main.travel("birch", "south")
	check(main.in_combat() and main.can_save() != "" and not went, "打的时候不能存档、不能走")
	# 头目的踢：举着格挡也会被踢破防
	for e in enemies:
		if e != boss:
			e.process_mode = Node.PROCESS_MODE_DISABLED
	boss.stop_left = 10.0
	await place(p, 2.1, 0.8)
	p.rotation.y = PI
	put_enemy(boss, Vector3(2.1, Ferry.DECK_Y, 2.2), 0.0)
	await physics(2)
	var m: Melee = p.melee
	m.toggle_draw()
	await seconds(0.45)
	m.block_press()
	await seconds(0.4)
	boss.attack_kind = "kick"
	boss._strike_target()
	check(m.staggered() and not m.blocking(), "奥弗的踢：举着格挡也被踢破防（%s）" % ("失衡" if m.staggered() else "没失衡"))
	m.block_release()
	m.health = m.health_max()
	# 半血喊包抄
	for e in enemies:
		e.process_mode = Node.PROCESS_MODE_INHERIT
	boss.stop_left = 0.0
	boss.data = boss.data.duplicate()
	boss.data.block_chance = 0.0
	boss.data.yield_chance = 1.0
	boss.take_hit({"damage": boss.hp - boss.hp_max / 2 + 1, "kind": "light", "stop": 0.0})
	var thugs := enemies.filter(func(e): return e != boss)
	check(boss.flank_called and thugs.all(func(e): return float(e.data.circle_side) > 1.2) and thugs[0].circle_dir != thugs[1].circle_dir, "奥弗半血：喊「包抄他！」，两个手下一左一右绕过来")
	# 打完：两个手下倒下，奥弗认输
	for e in thugs:
		e.take_hit({"damage": 999, "kind": "heavy", "stop": 0.0})
	boss.take_hit({"damage": boss.hp - 3, "kind": "heavy", "stop": 0.0})
	await frames(3)
	check(boss.state == Enemy.State.YIELD and GameState.has_flag("offer_defeated") and not main.encounter_active() and not main.in_combat(), "两个手下倒下、奥弗认输：这一仗打赢了")
	var lc: Array = main.find_children("*", "LootContainer", true, false).filter(func(c): return c.loot_id == "loot:ferry_offer")
	var got: Array = lc[0].take_all() if lc.size() == 1 else []
	check(got.has("灰皮手套") and GameState.has_item("grey_glove"), "搜奥弗的身：那只灰皮手套（%s）" % str(got))
	await frames(2)
	check(Saves.read_slot("auto").has("data"), "打完自动存档")
	# 塞拉斯与埃德里克
	r.start("ferry", "silas")
	check(r.node_id == "greet", "塞拉斯：多谢，替卡斯韦尔家办事")
	r.choose(0)
	check(r.node_id == "deal" and GameState.has_flag("heard_debt") and r.text().contains("借据") and r.text().contains("税权"), "塞拉斯说出那笔买卖：瓦伦家的借据，担保是渡口的税权")
	r.choose(0)
	labels = r.options().map(func(o): return o.text)
	r.choose(labels.find("桦林里那些无旗者，是你雇的。"))
	check(r.node_id == "hired" and GameState.has_flag("silas_admitted"), "拿着雇佣信问他：塞拉斯承认无旗者是他雇的")
	r.start("ferry", "edric")
	check(r.node_id == "greet", "埃德里克：你是我父亲派来的？我不回去")
	r.choose(0)
	check(r.node_id == "letter" and r.text().contains("联姻"), "提起那封信：父亲要送他去联姻，他不想当棋子")
	r.choose(0)
	check(r.node_id == "debt" and GameState.has_flag("edric_showed_debt") and GameState.quest_stage("edric_missing") == "choice", "埃德里克拿出借据：主线推进到抉择（3.7）")
	r.start("ferry", "edric")
	check(r.node_id == "after", "再找埃德里克：你打算怎么办？")
	# 读档：倒下的还倒着、奥弗还跪着，不会再站成 NPC
	await place(p, 0.0, -6.0)
	check(main.save_game("slot2"), "仗打完了能存档")
	check(main.load_game("slot2"), "读这个存档")
	main = await reload_main(main)
	p = main.player
	await frames(4)
	enemies = main.get_tree().get_nodes_in_group("enemy")
	check(main.area == "ferry" and enemies.size() == 3 and enemies.filter(func(e): return not e.alive()).size() == 2 and main.get_tree().get_nodes_in_group(Encounter.group_name(Ferry.ENCOUNTER)).is_empty(), "读档：两个手下还倒着，奥弗一伙不会再站成 NPC")
	boss = enemies.filter(func(e): return e.kind == "outlaw_boss")[0]
	check(boss.state == Enemy.State.YIELD and boss.display_name == "「灰手」奥弗", "读档：奥弗还跪着")
	# 回桦林
	await place(p, 0.0, Ferry.NORTH + 1.6)
	p.rotation.y = 0.0
	await physics(4)
	p.interactor.refresh()
	check(p.interactor.target is Door and p.interactor.target.prompt() == "回到 · 回桦林的路", "北头：提示「回到 · 回桦林的路」")
	p.interactor.use()
	await seconds(0.45)
	main = await reload_main(main)
	await frames(3)
	check(main.area == "birch" and flat(main.player.global_position).distance_to(Vector2(0, Birch.SOUTH - 3.2)) < 0.3, "回到桦林南头")
	await free_main(main)
	GameState.pending_load = {}
	GameState.new_game(1)


## 3.7 抉择与尾声：埃德里克三选一（交出 / 放走 / 勒索）、声望与旗标结算、借据背面的王室印鉴、修士来渡口交书、「第一章 · 黑鹭堡　开发中」结束画面
func test_ending() -> void:
	check(GameState.item("debt_note").kind == "quest" and str(GameState.item("debt_note").desc).contains("星铁冠") and GameState.item("old_book").kind == "quest", "借据（背面压着星铁冠印）与烧焦的旧书都是任务物品")
	var branches := [
		["deliver", "跟我回去。借据交给你父亲。", "（看着他走进雾里）", "他跟我回去了。借据在我这儿，交给他父亲。", "交回了瓦伦家"],
		["release", "走吧，船在等你。借据你带走。", "（看着船消失在雾里）", "他上船走了，借据他带走了。", "坐船南下"],
		["extort", "借据给我。", "（转向塞拉斯）", "他自己回镇上了。借据在我手里。", "一百二十枚"],
	]
	for b in branches:
		var choice: String = b[0]
		GameState.new_game(81)
		GameState.start_quest("edric_missing")
		GameState.set_flag("offer_left")
		GameState.set_flag("edric_showed_debt")
		GameState.set_stage("edric_missing", "choice")
		GameState.silver = 20
		var valen0 := GameState.get_rep("valen")
		var cas0 := GameState.get_rep("caswell")
		GameState.pending_load = {"scene": "ferry", "player": {}}
		var main := await make_main(false)
		var p: FpController = main.player
		await frames(3)
		var edric: Npc = main._npc_by_dialogue("edric")
		check(edric != null and main._npc_by_dialogue("silas") != null and main._npc_by_dialogue("alban_ferry") == null, "[%s] 抉择以前：埃德里克和塞拉斯在码头上，修士还没来" % choice)
		main.open_dialogue("ferry", "edric", edric)
		await frames(1)
		check(main.dialogue.runner.node_id == "after" and GameState.has_flag("saw_royal_seal") and main.dialogue.runner.text().contains("星铁冠"), "[%s] 埃德里克把借据翻过来：背面压着一顶星铁冠；问你打算怎么办" % choice)
		find_button(main.dialogue, str(b[1])).pressed.emit()
		await frames(1)
		find_button(main.dialogue, str(b[2])).pressed.emit()
		await frames(1)
		if choice == "extort":
			check(main.dialogue.runner.node_id == "extort_silas", "[extort] 拿了借据，转向塞拉斯")
			find_button(main.dialogue, "（掂了掂钱袋）").pressed.emit()
			await frames(1)
		await frames(3)
		check(not main.dialogue.visible and GameState.get_flag("prologue_edric") == choice and GameState.quest_stage("edric_missing") == "after_choice", "[%s] 做了抉择（prologue_edric = %s），主线：雾里有人提着灯走过来" % [choice, choice])
		match choice:
			"deliver":
				check(GameState.has_item("debt_note") and GameState.has_flag("edric_hates_you") and GameState.get_rep("valen") == valen0 + 10 and GameState.get_rep("caswell") == cas0 - 10, "[deliver] 借据在你手里；埃德里克恨你；瓦伦家 +10、卡斯韦尔家 −10")
			"release":
				check(not GameState.has_item("debt_note") and GameState.has_flag("edric_owes_you") and GameState.get_rep("valen") == valen0 and GameState.get_rep("caswell") == cas0, "[release] 借据跟他走了；他欠你一个人情；声望不变（瓦伦家要等谎言被识破）")
			"extort":
				check(GameState.has_item("debt_note") and GameState.silver == 140 and GameState.get_rep("caswell") == cas0 - 30 and GameState.has_flag("valen_may_learn"), "[extort] 扣下借据、收了 120 枚银币；卡斯韦尔家 −30；瓦伦家可能会知道")
		await frames(2)
		var alban: Npc = main._npc_by_dialogue("alban_ferry")
		check(main._npc_by_dialogue("edric") == null and main._npc_by_dialogue("silas") == null and alban != null, "[%s] 埃德里克和塞拉斯离开了渡口，奥尔本修士提着灯来了" % choice)
		main.open_dialogue("ferry", "alban_ferry", alban)
		await frames(1)
		var opts: Array = main.dialogue.runner.options().map(func(o): return o.text)
		check(opts == [str(b[3])], "[%s] 修士问少爷怎么样了：只有和你的抉择对得上的回答（%s）" % [choice, str(opts)])
		find_button(main.dialogue, str(b[3])).pressed.emit()
		await frames(1)
		check(main.dialogue.runner.node_id == "seal" and main.dialogue.runner.text().contains("王室的印鉴"), "[%s] 修士听说那枚印：王室的印鉴，老王亲手担保过这笔债" % choice)
		find_button(main.dialogue, "这意味着什么？").pressed.emit()
		await frames(1)
		main.touch.visible = true                       # 当成有触屏：结束画面要把触屏按钮藏起来、关掉后还原
		find_button(main.dialogue, "（收下旧书）").pressed.emit()
		await frames(4)
		check(GameState.has_item("old_book") and GameState.has_flag("prologue_done") and GameState.quest_done("edric_missing"), "[%s] 收下旧书：主线「雾里的少爷」完成" % choice)
		check(main.ending_panel.visible and get_tree().paused and main.ending_panel.title.text == "第一章 · 黑鹭堡" and main.ending_panel.sub.text == "开发中", "[%s] 结束画面：「第一章 · 黑鹭堡　开发中」，游戏暂停" % choice)
		check(main.ending_panel.recap.text.contains(str(b[4])) and main.ending_panel.seal.text.contains("黑鹭堡"), "[%s] 回顾按抉择写（%s）" % [choice, main.ending_panel.recap.text.left(16)])
		var rect: Rect2 = main.ending_panel.box.get_global_rect()
		check(rect.size.x <= main.hud.size.x, "[%s] 结束画面不超出画面宽度" % choice)
		check(not main.hud.visible and not main.touch.visible, "[%s] 结束画面打开时提示和触屏按钮藏起来（不叠在回顾上）" % choice)
		find_button(main.ending_panel, "在雾里再走走").pressed.emit()
		await frames(2)
		check(not main.ending_panel.visible and not get_tree().paused and main.hud.visible and main.touch.visible, "[%s] 「在雾里再走走」：关掉画面接着玩（提示与触屏按钮回来）" % choice)
		if choice == "deliver":
			# 读档 / 再来渡口：人走了、修士回小教堂
			await place(p, 0.0, -8.0)
			check(main.save_game("slot3"), "[deliver] 结局之后能存档")
			check(Saves.read_slot("auto").has("data"), "[deliver] 主线完成时自动存档")
			check(main.load_game("slot3"), "[deliver] 读这个存档")
			main = await reload_main(main)
			await frames(3)
			check(main.area == "ferry" and main._npc_by_dialogue("edric") == null and main._npc_by_dialogue("alban_ferry") == null, "[deliver] 读档：少爷和塞拉斯不在了，修士已经回去")
			await free_main(main)
			main = await make_area("chapel")
			var ab: Npc = main._npc_by_dialogue("alban")
			var r := DialogueRunner.new()
			r.start("chapel", "alban")
			check(ab != null and r.node_id == "after_book", "[deliver] 修士回到小教堂：「那本书，收好了吗？」")
		elif choice == "release":
			# 抉择之后、交书之前：小教堂里没有修士（他去渡口了）
			await free_main(main)
			GameState.flags.erase("prologue_done")
			main = await make_area("chapel")
			check(main._npc_by_dialogue("alban") == null, "[release] 修士去了渡口时，小教堂里没有他")
			GameState.set_flag("prologue_done")
		else:
			# 从头再来
			var rr := [0]
			main.reload_requested.connect(func(): rr[0] += 1)
			main.show_ending("prologue", "extort")
			await frames(2)
			find_button(main.ending_panel, "从头再来").pressed.emit()
			await frames(3)
			check(rr[0] == 1 and not GameState.has_flag("prologue_done") and GameState.silver == GameState.START_SILVER and not get_tree().paused, "[extort] 「从头再来」：新游戏，重新载入")
		await free_main(main)
	GameState.pending_load = {}
	GameState.new_game(1)

# ---------------- 开场与教学提示（3.8） ----------------

func test_opening() -> void:
	Engine.set_meta("ic_skip_opening", false)
	Settings.tips = true
	Settings.sound = true
	GameState.new_game(83)
	GameState.set_flag("origin", "knight")            # 出身选过了（O.1 的选择画面在 origin 组测）：这里测的是标题卡上第一下操作
	var main := await make_main(false)
	var p: FpController = main.player
	var op: Opening = main.opening
	check(op != null and op.stage == "card" and main.title_card.visible and main.title_card.title.text == "霜渡镇之夜" and main.title_card.prompt.text == "点击画面或按任意键开始",
		"新游戏：标题卡「序章 · 霜渡镇之夜」，等玩家开始")
	var manor: Transform3D = Areas.spawn("frostford", "manor")
	check(p.global_position.distance_to(manor.origin) < 0.3 and absf(angle_difference(deg_to_rad(p.yaw_deg()), PI)) < 0.05, "站在领主宅邸门口，背对大门望着街道（%s）" % p.global_position)
	var steward: Npc = main._npc_by_dialogue("steward")
	var to_steward := steward.global_position - p.global_position
	check(to_steward.length() < 4.5 and to_steward.dot(-p.global_transform.basis.z) < 0.0, "管家在身后的宅邸门口（%.1f 米）" % to_steward.length())
	check(main.hud.hint_label.text == "", "开场前不显示旧的操作说明")
	await frames(4)
	check(op.bell.stream is AudioStreamWAV and (op.bell.stream as AudioStreamWAV).data.size() == int(Bell.RATE * Bell.SECONDS) * 2, "标题卡显示时先合成好钟声（%.1f 秒，16 位单声道）" % Bell.SECONDS)
	var pcm: PackedByteArray = (op.bell.stream as AudioStreamWAV).data
	var peak := 0
	var tail_peak := 0
	for i in range(0, pcm.size(), 2):
		var v: int = absi(pcm.decode_s16(i))
		peak = maxi(peak, v)
		if i > pcm.size() - 400:
			tail_peak = maxi(tail_peak, v)
	check(peak > 20000 and peak <= 32767 and tail_peak < 300, "钟声有响度、不削顶，结尾淡出到静音（峰值 %d，结尾 %d）" % [peak, tail_peak])
	check(op.stage == "card" and op.tolls == 0, "玩家没动之前不敲钟（网页要有一次操作才能出声）")
	# 触屏：第一下触摸既开始开场，也照样按下摇杆（不被吞掉）
	main.touch.visible = true
	var tev := InputEventScreenTouch.new()
	tev.index = 0
	tev.position = Vector2(200, 500)
	tev.pressed = true
	get_viewport().push_input(tev)
	await frames(1)
	check(op.stage == "bell" and op.tolls == 1 and main.touch.move_index == 0, "第一下触摸：开场开始（第一下钟声），左半屏的摇杆也照样按下")
	var rel := tev.duplicate()
	rel.pressed = false
	get_viewport().push_input(rel)
	main.touch.visible = false
	var tips: Dictionary = GameState.tips_data()
	check(main.hud.subtitle_label.text == Opening.BELL_LINE and main.hud.hint_label.text == str(tips.move.desktop) and main.tip_now == "move", "字幕「%s」，底部是走动与转视角的教学提示" % Opening.BELL_LINE)
	await frames(2)
	check(main.title_card.prompt.text == "" and main.title_card.modulate.a <= 1.0, "标题卡收起「点击开始」并开始淡出")
	op.t = Opening.CALL_AT + 0.01            # 无头模式帧很快，直接把时间拨过喊人的时刻
	await frames(6)
	check(op.tolls == Opening.TOLLS and op.stage == "called" and GameState.has_flag("opening_done"), "钟敲了 %d 下，管家喊人；记下旗标 opening_done" % Opening.TOLLS)
	check(main.hud.subtitle_label.text == Opening.CALL_LINE and main.hud.hint_label.text == str(tips.talk.desktop) and main.tip_now == "talk", "「%s」，提示转身对准管家说话" % Opening.CALL_LINE)
	await aim(p, p.global_position, steward.global_position + Vector3(0, 1.4, 0))
	await frames(2)
	check(p.interactor.target != null and p.interactor.target.display_name == "管家", "转过身：对准了管家")
	main._unhandled_input(key_ev(KEY_E))
	await frames(2)
	check(main.dialogue.visible and main.dialogue.runner.id == "steward" and main.hud.hint_label.text == "", "按 E 和管家说话，底部提示让开对话面板")
	find_button(main.dialogue, "我这就去找。").pressed.emit()
	await frames(1)
	find_button(main.dialogue, "放心。").pressed.emit()
	await frames(3)
	check(GameState.quest_active("edric_missing") and main.tip_now == "quest" and main.hud.hint_label.text == str(tips.quest.desktop) and main.tip_queue == ["rep"], "接下主线：对话关上后提示任务日志（声望的提示排在后面）")
	main.hint_left = 0.01
	await frames(3)
	check(main.tip_now == "rep" and main.hud.hint_label.text == str(tips.rep.desktop), "上一条消失后接着讲声望（管家那里瓦伦家声望 +5）")
	check(GameState.tips_seen == ["move", "talk", "quest", "rep"], "看过的提示按顺序记下（%s）" % str(GameState.tips_seen))
	main.hint_left = 0.01
	await frames(3)
	main.show_tip("quest")
	main.show_tip("rep")
	await frames(2)
	check(main.tip_now == "" and main.tip_queue.is_empty(), "看过的提示不再显示")
	# 检定的提示在对话面板里显示一次
	main.open_dialogue("frostford", "watchman", main._npc_by_dialogue("watchman"))
	await frames(1)
	check(not main.dialogue.tip_label.visible, "没有检定选项的节点不讲检定")
	find_button(main.dialogue, "你今晚见过埃德里克少爷吗？").pressed.emit()
	await frames(1)
	var found_check: bool = main.dialogue.runner.options().any(func(o): return o.has("check"))
	check(found_check and main.dialogue.tip_label.visible and main.dialogue.tip_label.text.contains("检定") and "check" in GameState.tips_seen, "第一次遇到检定选项：对话面板里讲检定（%s）" % main.dialogue.runner.node_id)
	main.dialogue.close()
	await frames(2)
	main.open_dialogue("frostford", "watchman", main._npc_by_dialogue("watchman"))
	await frames(1)
	find_button(main.dialogue, "关于埃德里克少爷，你再想想。").pressed.emit()
	await frames(1)
	check(main.dialogue.runner.options().any(func(o): return o.has("check")) and not main.dialogue.tip_label.visible, "检定提示只讲一次（再遇到检定选项不讲了）")
	main.dialogue.close()
	await frames(2)
	# 存档带着看过的提示和开场旗标；读档不再播开场
	main.hint_left = 0.0
	check(main.save_game("slot2", true), "开场以后存档")
	var saved: Dictionary = Saves.read_slot("slot2")
	check(Array(saved.data.state.get("tips", [])).has("talk") and bool(saved.data.state.flags.get("opening_done", false)), "存档里记着看过的提示和 opening_done")
	check(main.load_game("slot2"), "读这个存档")
	main = await reload_main(main)
	check(main.opening == null and not main.title_card.visible and GameState.tips_seen.has("check"), "读档：不再播开场，看过的提示还记着")
	await free_main(main)
	# 开过一次开场的新游戏（旗标在）也不再播；新开一局（旗标清空）再播
	GameState.set_flag("opening_done")
	main = await make_main(false)
	check(main.opening == null, "这一局播过开场：重新载入主街不再播")
	await free_main(main)
	# 关掉声音：不合成、不敲钟（字幕照样有）；关掉教学提示：一条都不显示
	Settings.sound = false
	Settings.tips = false
	GameState.new_game(84)
	main = await make_main(false)
	op = main.opening
	await frames(4)
	main._unhandled_input(key_ev(KEY_W))
	op.begin()
	await frames(2)
	check(op.bell.stream == null and op.tolls == 1 and main.hud.subtitle_label.text == Opening.BELL_LINE, "关掉声音：不合成、不出声，字幕照样有")
	check(main.tip_now == "" and main.hud.hint_label.text == "" and GameState.tips_seen.is_empty(), "关掉教学提示：一条都不显示")
	main.open_pause()
	await frames(1)
	check(main.pause_menu.sound_check.text == "声音" and not main.pause_menu.sound_check.button_pressed and main.pause_menu.tips_check.text == "教学提示" and not main.pause_menu.tips_check.button_pressed,
		"暂停菜单里有「声音」「教学提示」两个开关")
	check(main.pause_menu.help_label.text == PauseMenu.HELP_DESKTOP, "暂停菜单只写这台设备的操作说明（电脑）")
	main.close_pause()
	# 触屏：底部提示和字幕不压在右下角的按钮列上（竖屏挪到上半屏，横屏收窄到摇杆和按钮之间）
	main.touch.visible = true
	main.hud.say(Opening.CALL_LINE, 5.0)
	main.hud.set_hint(str(GameState.tips_data().talk.touch))
	for sz in [Vector2(360, 740), Vector2(540, 720), Vector2(740, 360), Vector2(1280, 720)]:
		main.hud.size = sz
		main.touch.size = sz
		main.hud._layout()
		await frames(1)
		var br: Rect2 = main.touch.buttons_rect()
		var hr: Rect2 = main.hud.hint_label.get_rect()
		var sr: Rect2 = main.hud.subtitle_panel.get_rect()
		check(not hr.intersects(br) and not sr.intersects(br) and not hr.intersects(sr) and hr.end.x <= sz.x and sr.end.x <= sz.x,
			"触屏 %dx%d：提示和字幕都不压在按钮上、互不重叠（提示 %s，字幕 %s，按钮 %s）" % [sz.x, sz.y, hr, sr, br])
	main.touch.visible = false
	main.hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main.touch.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main.open_pause()
	await frames(1)
	main.pause_menu.tips_check.button_pressed = true
	main.pause_menu.sound_check.button_pressed = true
	check(Settings.tips and Settings.sound and bool(Saves.load_settings().get("tips", false)) and bool(Saves.load_settings().get("sound", false)), "打开两个开关：马上存进设置")
	main.close_pause()
	await free_main(main)
	Engine.set_meta("ic_skip_opening", true)

# ---------------- 三个分支的全流程（3.8） ----------------

## 和某人按选项文字说一串话；对话还开着就关上。找不到选项时打印当前节点和选项，返回 false
func fl_say(main: Node3D, area: String, id: String, picks: Array, keep_open := false) -> bool:
	if not main.dialogue.visible:
		main.open_dialogue(area, id, main._npc_by_dialogue(id))
		await frames(1)
	if not main.dialogue.visible:
		print("  （%s 的对话没打开）" % id)
		return false
	for t in picks:
		var b := find_button(main.dialogue, str(t))
		if b == null:
			print("  （%s 的节点 %s 没有选项「%s」：%s）" % [id, main.dialogue.runner.node_id, t, str(main.dialogue.runner.options().map(func(o): return o.text))])
			main.dialogue.close()
			await frames(2)
			return false
		b.pressed.emit()
		await frames(1)
	if main.dialogue.visible and not keep_open:
		main.dialogue.close()
	await frames(3)
	return true


## 走区域里通往 to_area 的那扇门（检查路是通的），载入新区域
func fl_go(main: Node3D, to_area: String) -> Node3D:
	var doors: Array = main.find_children("*", "Door", true, false).filter(func(d): return d.to_area == to_area and not d.locked)
	if doors.is_empty():
		print("  （%s 没有去 %s 的门）" % [main.area, to_area])
		return main
	var went: bool = await main.travel(doors[0].to_area, doors[0].to_spawn)
	if not went:
		return main
	main = await reload_main(main)
	await frames(3)
	return main


## 打赢眼前这一仗：在场的敌人都吃一记重击（倒下或认输）
func fl_win_fight(main: Node3D) -> void:
	for e in main.get_tree().get_nodes_in_group("enemy"):
		if e.alive() and e.state != Enemy.State.YIELD:
			e.take_hit({"damage": 999, "kind": "heavy", "stop": 0.0})
	await frames(4)


## 搜身：编号以 loot: 开头的尸体 / 跪着的人都搜一遍，返回搜到的东西
func fl_loot_all(main: Node3D) -> Array:
	var got: Array = []
	for c in main.find_children("*", "LootContainer", true, false):
		if str(c.loot_id).begins_with("loot:"):
			got.append_array(c.take_all())
	return got


func test_fullflow() -> void:
	# ===== 一、交出：开场 → 管家 → 更夫（两条免费线索）→ 桦林（打完搜身，拿雇佣信和银币）→ 渡口（付 30 银币）→ 交出 =====
	Engine.set_meta("ic_skip_opening", false)
	Settings.tips = true
	GameState.new_game(91)
	var main := await make_main(false)
	check(main.opening != null and main.area == "frostford", "[交出] 新游戏：开场（标题卡、宅邸门口）")
	main.opening.begin()
	main.opening.t = Opening.CALL_AT + 0.01
	await frames(4)
	check(GameState.has_flag("opening_done") and main.tip_now == "talk", "[交出] 钟声过后管家喊住你")
	check(await fl_say(main, "frostford", "steward", ["我这就去找。", "放心。"]), "[交出] 管家：接下主线")
	check(GameState.quest_stage("edric_missing") == "find_clues" and GameState.get_rep("valen") > 0, "[交出] 主线「雾里的少爷」：打探少爷的下落；瓦伦家记着你答应了")
	check(await fl_say(main, "frostford", "watchman", ["你今晚见过埃德里克少爷吗？", "那个南方人长什么样？", "我再问点别的。", "没有了，你忙吧。"]), "[交出] 更夫：少爷往渡口去了，南方人戴双钥印戒")
	check(GameState.clues.has("ferry") and GameState.clues.has("ring") and GameState.quest_stage("edric_missing") == "to_ferry", "[交出] 两条线索：主线推进到「去渡口」（%s）" % str(GameState.clues))
	main = await fl_go(main, "birch")
	check(main.area == "birch" and main.get_tree().get_nodes_in_group("enemy").size() == 3, "[交出] 出南门到桦林：哨卡三个无旗者")
	await fl_win_fight(main)
	var got := fl_loot_all(main)
	check(got.has("雇佣信") and GameState.quest_stage("edric_missing") == "warned" and GameState.silver >= 30, "[交出] 打完搜身：雇佣信（主线：赶在他们前头去渡口），银币 %d 枚" % GameState.silver)
	main = await fl_go(main, "ferry")
	check(main.area == "ferry" and main._npc_by_dialogue("offer") != null, "[交出] 到了渡口：「灰手」奥弗堵着码头")
	var s0 := GameState.silver
	check(await fl_say(main, "ferry", "offer", ["我来接瓦伦家的少爷。", "（掂了掂钱袋）30 枚银币，够你们的人过冬。", "（看着他们走进雾里）"]), "[交出] 付 30 枚银币")
	check(GameState.has_flag("offer_left") and GameState.silver == s0 - 30 and main._npc_by_dialogue("offer") == null, "[交出] 奥弗收钱带人走了")
	check(await fl_say(main, "ferry", "silas", ["什么买卖？", "明白了。", "桦林里那些无旗者，是你雇的。", "……", "告辞。"]), "[交出] 塞拉斯：借据的买卖；拿着雇佣信问，他承认雇了无旗者")
	check(await fl_say(main, "ferry", "edric", ["你父亲很担心你。", "那张借据在你手里？", "……", "跟我回去。借据交给你父亲。", "（看着他走进雾里）"]), "[交出] 埃德里克：看到借据背面的星铁冠印；带他回去")
	check(GameState.get_flag("prologue_edric") == "deliver" and GameState.has_item("debt_note") and main._npc_by_dialogue("alban_ferry") != null, "[交出] 抉择记下，借据到手，修士提着灯来了")
	check(await fl_say(main, "ferry", "alban_ferry", ["他跟我回去了。借据在我这儿，交给他父亲。", "这意味着什么？", "（收下旧书）"], true), "[交出] 修士认出王室的印鉴，交出旧书")
	await frames(3)
	check(main.ending_panel.visible and GameState.quest_done("edric_missing") and main.ending_panel.recap.text.contains("交回了瓦伦家"), "[交出] 结束画面：「第一章 · 黑鹭堡　开发中」，回顾写着交回了瓦伦家")
	find_button(main.ending_panel, "在雾里再走走").pressed.emit()
	await frames(2)
	main = await fl_go(main, "birch")
	main = await fl_go(main, "frostford")
	check(main.area == "frostford" and await fl_say(main, "frostford", "steward", [], true) and main.dialogue.runner.node_id == "thanks", "[交出] 回到镇上：管家说少爷回来了，不会再派一次任务")
	main.dialogue.close()
	await frames(2)
	var seen: Array = GameState.tips_seen + main.tip_queue
	check(["move", "talk", "quest", "rep", "check", "clue", "save", "bag"].all(func(t): return seen.has(t)), "[交出] 一路上的教学提示都出现过或排着队（看过 %s，排队 %s；换区域时排队的带过去）" % [str(GameState.tips_seen), str(main.tip_queue)])
	await free_main(main)
	Engine.set_meta("ic_skip_opening", true)

	# ===== 二、放走：管家 → 酒馆（帮玛蒂尔达和大桶打一架；伐木工）→ 桦林（打完不搜）→ 渡口（直接动手）→ 放走 =====
	GameState.new_game(92)
	main = await make_main(false)
	check(main.opening == null, "[放走] （测试从主街南头开始，不播开场）")
	check(await fl_say(main, "frostford", "steward", ["少爷最近有什么不对劲吗？", "明白了，我这就去找。", "放心。"]), "[放走] 管家：少爷最近和一个南方客人喝酒，不想联姻")
	main = await fl_go(main, "tavern")
	check(main.area == "tavern", "[放走] 走进「倒钩鱼」酒馆")
	check(await fl_say(main, "tavern", "matilda", ["打听埃德里克少爷的事。", "（朝吧台那头的大个子扬了扬下巴）那个人，是不是给你添了麻烦？", "交给我。"]), "[放走] 玛蒂尔达：让大桶把酒钱结了就告诉你")
	check(await fl_say(main, "tavern", "dagu", ["玛蒂尔达说你欠了三个晚上的酒钱。", "那就来吧。（徒手打一架）"]), "[放走] 找大桶要账")
	check(main.brawl_active(), "[放走] 徒手打起来了")
	await fl_win_fight(main)
	await seconds(Brawl.END_DELAY + 0.3)
	check(GameState.has_flag("dagu_beaten") and not main.brawl_active(), "[放走] 大桶认输，结了账")
	check(await fl_say(main, "tavern", "matilda", ["大桶把账结了。", "说吧。", "多谢。", "告辞。"]), "[放走] 玛蒂尔达说出南方人的事")
	check(await fl_say(main, "tavern", "woodcutter", ["雾里出过什么事吗？", "多谢提醒。"]), "[放走] 伐木工：桦林边有营火")
	check(GameState.clues.has("boots") and GameState.clues.has("birch_fires") and GameState.quest_stage("edric_missing") == "to_ferry", "[放走] 两条线索：去渡口（%s）" % str(GameState.clues))
	main = await fl_go(main, "frostford")
	main = await fl_go(main, "birch")
	await fl_win_fight(main)
	check(not main.in_combat() and GameState.quest_stage("edric_missing") == "to_ferry", "[放走] 桦林：打完不搜身，主线还在「去渡口」")
	main = await fl_go(main, "ferry")
	check(main.area == "ferry", "[放走] 到了渡口")
	check(await fl_say(main, "ferry", "offer", ["我来接瓦伦家的少爷。", "那就动手吧。"]), "[放走] 和奥弗：「那就动手吧。」")
	check(main.encounter_active(), "[放走] 奥弗和两个手下动手了")
	await fl_win_fight(main)
	check(GameState.has_flag("offer_defeated") and not main.in_combat(), "[放走] 打赢了渡口这一仗")
	check(fl_loot_all(main).has("灰皮手套"), "[放走] 从奥弗身上搜出灰皮手套")
	check(await fl_say(main, "ferry", "silas", ["什么买卖？", "明白了。", "告辞。"]), "[放走] 塞拉斯说出借据的买卖")
	check(await fl_say(main, "ferry", "edric", ["你父亲很担心你。", "那张借据在你手里？", "……", "走吧，船在等你。借据你带走。", "（看着船消失在雾里）"]), "[放走] 放埃德里克坐船南下")
	check(GameState.get_flag("prologue_edric") == "release" and not GameState.has_item("debt_note") and GameState.has_flag("edric_owes_you"), "[放走] 借据跟他走了，他欠你一个人情")
	check(await fl_say(main, "ferry", "alban_ferry", ["他上船走了，借据他带走了。", "这意味着什么？", "（收下旧书）"], true), "[放走] 修士交出旧书")
	await frames(3)
	check(main.ending_panel.visible and main.ending_panel.recap.text.contains("坐船南下") and GameState.quest_done("edric_missing"), "[放走] 结束画面，回顾写着坐船南下")
	find_button(main.ending_panel, "在雾里再走走").pressed.emit()
	await frames(2)
	await free_main(main)

	# ===== 三、勒索：管家 → 小教堂（捐钱借钥匙）→ 墓室（少爷的信）→ 桦林（搜出雇佣信）→ 渡口（亮信说服）→ 勒索 → 从头再来 =====
	GameState.new_game(93)
	main = await make_main(false)
	check(await fl_say(main, "frostford", "steward", ["我这就去找。", "放心。"]), "[勒索] 管家：接下主线")
	main = await fl_go(main, "churchyard")
	main = await fl_go(main, "chapel")
	check(main.area == "chapel", "[勒索] 窄巷 → 墓园 → 星铁小教堂")
	check(await fl_say(main, "chapel", "alban", ["打听埃德里克少爷的事。", "墓园钥匙还在您这儿吗？", "（往捐献箱里放 3 枚银币）给教堂添点灯油。", "我会的。"]), "[勒索] 修士：少爷借过墓园钥匙；捐 3 银币借到钥匙")
	check(GameState.has_item("crypt_key") and GameState.clues.has("chapel_key"), "[勒索] 拿到墓园钥匙，记下线索")
	main = await fl_go(main, "churchyard")
	var crypt: Door = main.find_children("*", "Door", true, false).filter(func(d): return d.key_item == "crypt_key")[0]
	crypt.interact(main.player)
	var bundle: LootContainer = main.find_children("*", "LootContainer", true, false).filter(func(c): return c.loot_id == "valen_crypt_bundle")[0]
	check(not crypt.locked and bundle.take_all().has("没写完的信") and GameState.quest_stage("edric_missing") == "to_ferry", "[勒索] 打开墓室，包袱里是少爷没写完的信：去渡口")
	main = await fl_go(main, "frostford")
	main = await fl_go(main, "birch")
	await fl_win_fight(main)
	check(fl_loot_all(main).has("雇佣信") and GameState.quest_stage("edric_missing") == "warned", "[勒索] 桦林：打完搜出雇佣信")
	main = await fl_go(main, "ferry")
	check(await fl_say(main, "ferry", "offer", ["我来接瓦伦家的少爷。", "（亮出雇佣信）信上的蜡印你认得。双钥港的人，会让你们拿着钱活着回去吗？"], true), "[勒索] 亮出雇佣信（口才检定）")
	var node: String = main.dialogue.runner.node_id
	if node == "convinced":
		check(await fl_say(main, "ferry", "offer", ["（看着他们走进雾里）"]) and GameState.has_flag("offer_left"), "[勒索] 说动了：奥弗带人走了")
	else:
		check(node == "laugh" and await fl_say(main, "ferry", "offer", ["（拔剑）"]), "[勒索] 没说动：奥弗拔剑（%s）" % node)
		await fl_win_fight(main)
		check(GameState.has_flag("offer_defeated"), "[勒索] 打赢了")
	print("  （亮信的检定：%s）" % ("说动了" if node == "convinced" else "没说动"))
	var cas0 := GameState.get_rep("caswell")
	s0 = GameState.silver
	check(await fl_say(main, "ferry", "edric", ["那张借据在你手里？", "……", "借据给我。", "（转向塞拉斯）", "（掂了掂钱袋）"]), "[勒索] 扣下借据，转向塞拉斯要钱")
	check(GameState.get_flag("prologue_edric") == "extort" and GameState.has_item("debt_note") and GameState.silver == s0 + 120 and GameState.get_rep("caswell") == cas0 - 30, "[勒索] 借据在手、收了 120 银币、卡斯韦尔家 −30")
	check(await fl_say(main, "ferry", "alban_ferry", ["他自己回镇上了。借据在我手里。", "这意味着什么？", "（收下旧书）"], true), "[勒索] 修士交出旧书")
	await frames(3)
	check(main.ending_panel.visible and main.ending_panel.recap.text.contains("一百二十"), "[勒索] 结束画面，回顾写着一百二十枚银币")
	Engine.set_meta("ic_skip_opening", false)
	var reloads := [0]
	main.reload_requested.connect(func(): reloads[0] += 1)
	find_button(main.ending_panel, "从头再来").pressed.emit()
	await frames(3)
	check(reloads[0] == 1 and GameState.quest_stage("edric_missing") == "" and not GameState.has_flag("opening_done"), "[勒索] 从头再来：新游戏")
	main = await reload_main(main)
	check(main.opening != null and main.title_card.visible, "[勒索] 新游戏又从开场（宅邸门口、标题卡）开始")
	await free_main(main)
	Engine.set_meta("ic_skip_opening", true)


## 军阵战斗（路线图 B.1，D8；GDD 6.4）：试验场、按目标分配的攻击令牌、友军砍不到、兵打兵、声望只算玩家打倒的、普通兵不进存档、名额排队
func make_battle() -> Node3D:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.area = "battle"
	main.battle_autostart = false
	add_child(main)
	await frames(3)
	return main


func soldiers_of(main: Node3D, side: String) -> Array:
	return main.get_tree().get_nodes_in_group("soldier").filter(func(s): return s.side == side)


func test_battle() -> void:
	# —— 攻击令牌按目标分配（不进场景的单元检查）
	var dir := CombatDirector.new()
	var t1 := Node3D.new()
	var t2 := Node3D.new()
	var who: Array = [Node.new(), Node.new(), Node.new(), Node.new()]
	check(dir.request(who[0], t1) and dir.request(who[1], t1) and not dir.request(who[2], t1), "每个目标最多 2 个攻击者：第三个要不到")
	check(dir.count_for(t1) == 2 and dir.request(who[2], t2) and dir.count_for(t2) == 1, "换一个目标就要得到（目标一 2 个、目标二 1 个）")
	check(dir.request(who[0], t2) and dir.count_for(t1) == 1 and dir.count_for(t2) == 2, "攻击者换目标：原来那一份自动交回")
	dir.release(who[1])
	check(dir.count_for(t1) == 0 and dir.by_target.is_empty() == false and dir.count() == 0, "交回令牌；兵的令牌不占玩家那一份")
	check(dir.request(who[3]) and dir.count() == 1, "不写目标（序章的敌人）仍是打玩家的那一份")
	for n in who + [t1, t2, dir]:
		n.free()
	check(Areas.known("battle") and Areas.nav_bounds("battle").has_volume() and Areas.views("battle").size() == BattleArena.VIEWS.size(), "新区域：军阵试验场（有导航范围、固定机位）")
	check(Enemy.types().has("soldier") and Enemy.types().has("levy") and Enemy.types().soldier.loot.is_empty(), "敌人数据：剑兵、民兵（普通兵不留东西）")
	# —— 试验场
	GameState.new_game(7)
	var main := await make_battle()
	var p: FpController = main.player
	var m: Melee = p.melee
	var b: Battle = main.battle
	var white := soldiers_of(main, "white")
	var black := soldiers_of(main, "black")
	check(main.scene_name() == "battle" and b != null and b.player_side == "white" and white.size() == 10 and black.size() == 10, "试验场：白带 10 人（你这边）对黑带 10 人")
	check(white.all(func(s): return s.is_in_group("ally") and not s.is_in_group("enemy") and s.collision_layer & 8 == 0), "白带是友军：不在敌人组、不在可受击层")
	check(black.all(func(s): return s.is_in_group("enemy") and s.collision_layer & 8 != 0), "黑带是敌人：在敌人组、可受击")
	check(range(10).all(func(i): return white[i].kind == BattleArena.kind_for(i, 10)) and white.all(func(s): return s.transient and not s.drops_loot), "兵种按搭配排（B.4 起）；普通兵不进存档、不留东西")
	check(white[1].display_name == "白带 · 剑兵" and not white[1].name_label.visible and "Band" in white[1].look_parts and look_has(white[1], Color(BattleArena.SIDES.white.band)), "名字「白带 · 剑兵」、头顶不挂名字、胸前白布带")
	check(not main.nav.is_empty() and int(main.nav.polygons) > 0, "试验场烘焙了导航网格（%s 个多边形）" % main.nav.get("polygons", 0))
	check(main.hud.hint_label.text == main.HINT_BATTLE_DESKTOP, "进试验场：提示两边是谁、怎么打")
	check(not b.started and not main.in_combat() and main.can_save() == "", "开打前：不算战斗，可以存档")
	# 观战台走得上去
	await place(p, 0.0, 13.5)
	p.rotation.y = PI                                    # 转身朝南（观战台在白带身后）
	Input.action_press("move_forward")
	await physics(90)
	Input.action_release("move_forward")
	check(p.global_position.y > BattleArena.STAND_TOP - 0.1 and p.global_position.z > 16.5, "转身走上观战台（高 %.2f 米）" % p.global_position.y)
	# 玩家的剑：砍不到白带，砍得到黑带
	await place(p, 0.0, 12.0)
	var ally: Soldier = white[0]
	var foe_s: Soldier = black[0]
	ally.global_position = Vector3(0, 0, 10.7)
	foe_s.global_position = Vector3(6, 0, 10.7)
	await physics(3)
	check(m.find_target() == null, "白带的人站在剑前：剑扫不到自己人")
	ally.global_position = Vector3(-6, 0, 10.7)
	foe_s.global_position = Vector3(0, 0, 10.7)
	await physics(3)
	check(m.find_target() == foe_s, "换成黑带的人：剑扫得到")
	foe_s.global_position = BattleArena.slot("black", 0, 10)
	ally.global_position = BattleArena.slot("white", 0, 10)
	await physics(3)
	# —— 开打：玩家站到黑带跟前，有人来打玩家，但同时最多 2 个
	m.health = 100000
	await place(p, 0.0, -6.5)
	b.start()
	await physics(2)
	check(b.active() and main.in_combat() and main.can_save() == "附近有敌人在和你打，不能存档", "开打后：在战斗中，不能存档")
	check(black.all(func(s): return s.state == Enemy.State.COMBAT) and white.all(func(s): return s.state == Enemy.State.COMBAT), "两边都进入战斗")
	var game_dir: CombatDirector = main.get_tree().get_first_node_in_group("combat_director")
	var most := 0
	var most_player := 0
	var on_player := false
	var white_on_player := false
	for i in 420:                                        # 最多 7 秒：黑带要先挑中你、走过来、起手（3 秒有时不够）
		if i >= 180 and m.health < 100000:
			break
		await get_tree().physics_frame
		most_player = maxi(most_player, game_dir.count())
		for list in game_dir.by_target.values():
			most = maxi(most, list.filter(func(h): return is_instance_valid(h)).size())
		for s in black:
			if s.target == p:
				on_player = true
		for s in white:
			if s.target == p:
				white_on_player = true
	check(on_player and not white_on_player, "黑带有人冲你来，白带的人从不把你当对手")
	check(most_player >= 1 and most_player <= 2, "同时打你的最多 2 个（最多 %d 个）" % most_player)
	check(most >= 1 and most <= 2, "每个兵同时最多被 2 个人打（最多 %d 个）" % most)
	check(m.health < 100000, "黑带的人打中了你（剩 %d）" % m.health)
	# 声望：玩家打倒的才扣，兵打倒兵不扣
	var r0: int = GameState.get_rep("valen")
	var h1: Soldier = black[1]
	var h2: Soldier = black[2]
	h1.faction_id = "valen"
	h2.faction_id = "valen"
	h1.take_hit({"damage": 999, "kind": "heavy", "stop": 0.0})
	check(not h1.alive() and GameState.get_rep("valen") == r0 - 5, "你打倒的：按设定的势力扣声望（−5）")
	h2.take_hit({"damage": 999, "kind": "heavy", "stop": 0.0, "attacker": white[3]})
	check(not h2.alive() and GameState.get_rep("valen") == r0 - 5 and h2.last_attacker == white[3], "白带的兵打倒的：不扣声望")
	check(not GameState.dead.has(h1.enemy_id) and not GameState.dead.has(h2.enemy_id), "普通兵倒下不写进存档")
	check(main.world.find_children("*", "LootContainer", true, false).filter(func(c): return str(c.container_id).begins_with("loot:")).is_empty(), "普通兵倒下不留搜刮点")
	await free_main(main)
	# —— 两队自己打到底（玩家不参战）：同阵营不互伤、目标分散、打到只剩一方
	GameState.new_game(11)
	main = await make_battle()
	p = main.player
	b = main.battle
	white = soldiers_of(main, "white")
	black = soldiers_of(main, "black")
	b.player_side = ""                                   # 兵不打玩家
	await place(p, 0.0, 18.0)
	var all_s: Array = white + black
	for s in all_s:
		s.hp = 14                                        # 打快一点：一两下就倒、求饶或逃
		s.hp_max = 14
	var rep0: Dictionary = GameState.rep.duplicate()
	var winner := ["?"]
	b.ended.connect(func(w): winner[0] = w)
	var last_hp := {}
	for s in all_s:
		last_hp[s] = s.hp
	b.start()
	var friendly_hits := 0
	var hits := 0
	var spread := 0
	most = 0
	var frames_n := 0
	while winner[0] == "?" and frames_n < 60 * 90:
		await get_tree().physics_frame
		frames_n += 1
		for s in all_s:
			if s.hp < last_hp[s]:
				hits += 1
				if s.last_attacker == null or s.last_attacker.side == s.side:
					friendly_hits += 1
				last_hp[s] = s.hp
		for list in game_dir.by_target.values() if is_instance_valid(game_dir) else []:
			most = maxi(most, list.filter(func(h): return is_instance_valid(h)).size())
		spread = maxi(spread, b.aimed.size())
		game_dir = main.get_tree().get_first_node_in_group("combat_director")
	check(winner[0] in ["white", "black"], "两队打到只剩一方：%s 赢（%.0f 秒，%d 次打中）" % [winner[0], frames_n / 60.0, hits])
	check(hits >= 5 and friendly_hits == 0, "兵只打别一边的人：%d 次打中，自己人打自己人 %d 次（B.3 起有溃逃，仗打得更短）" % [hits, friendly_hits])
	check(most <= 2, "整场每个兵同时最多被 2 个人打（最多 %d 个）" % most)
	check(spread >= 6, "目标是分散的：同一时刻最多有 %d 个不同的人被盯着（不是全挤向一个）" % spread)
	var loser := "black" if winner[0] == "white" else "white"
	check(b.side_count(loser) == 0 and b.side_count(winner[0]) > 0 and not b.active(), "输的一方没有还在打的人；战斗结束")
	check(GameState.rep == rep0 and GameState.dead.is_empty() and GameState.yielded.is_empty(), "兵打兵：声望不变、存档里没有倒下 / 求饶的记录")
	check(not main.in_combat() and all_s.all(func(s): return not s.fighting() or (s.state == Enemy.State.PATROL and s.target == null)), "打完了：赢的一方收手站着，不再算战斗中")
	await free_main(main)
	# —— 名额：同时在打的人超过上限就排队，有人倒下再补上；排队的没进场景，战斗释放时一起释放（不泄漏）
	GameState.new_game(7)
	main = await make_battle()
	var b2 := Battle.new()
	b2.max_active = 4
	b2.add_side("a", "甲")
	b2.add_side("c", "乙")
	main.world.add_child(b2)
	var mine: Array = []
	for i in 6:
		var sd := "a" if i % 2 == 0 else "c"
		var s := Soldier.create("soldier", "q%d" % i, sd, Color.GRAY, Color.WHITE)
		s.position = Vector3(-18 + i * 1.5, 0, 16 if sd == "a" else 13)
		b2.enlist(s, main.world)
		mine.append(s)
	check(b2.roster.size() == 4 and b2.reserve.size() == 2 and not mine[5].is_inside_tree(), "上限 4 人：4 个进场，2 个排队（没进场景）")
	b2.start()
	await physics(2)
	mine[0].take_hit({"damage": 999, "kind": "heavy", "stop": 0.0, "attacker": mine[1]})
	await seconds(0.4)
	check(b2.roster.size() == 5 and b2.reserve.size() == 1 and mine[4].is_inside_tree() and mine[4].state == Enemy.State.COMBAT, "倒下一个：排队的补上来，直接进入战斗")
	await free_main(main)
	check(not is_instance_valid(mine[5]), "战斗释放时，还在排队的兵一起释放")


## 小队与指令（路线图 B.2，GDD 6.4）：试验场里白带前排 6 个人听玩家指挥——跟随我 / 原地坚守 / 冲锋；键盘 1 / 2 / 3、触屏「令」；右上角写小队与命令
func test_squad() -> void:
	GameState.new_game(7)
	var main := await make_battle()
	var p: FpController = main.player
	var b: Battle = main.battle
	b.morale_on = false                                   # 这一组只测命令：士气与溃逃在 morale 组
	var squad: Array = b.squad
	var white := soldiers_of(main, "white")
	check(squad.size() == 6 and squad.all(func(s): return s.side == "white" and s.in_squad and s.marker != null and s.marker.visible), "白带有 6 个人编进小队，头顶有 ◆")
	check(white.filter(func(s): return not s.in_squad).all(func(s): return s.marker == null), "小队以外的白带头顶没有 ◆")
	check(BattleArena.squad_size(10) == 6 and BattleArena.squad_size(30) == 12 and BattleArena.squad_size(1) == 1, "小队人数：每边人数的六成，1–12 人")
	check(b.squad_order == "charge" and squad.all(func(s): return s.order == "charge") and b.leash(squad[0]).is_empty() and b.post_of(squad[0]) == null, "默认冲锋：不拴绳、没有固定位置（和 B.1 一样）")
	check(main.hud.squad_label.visible and main.hud.squad_label.text == "◆ 小队 6 人：冲锋 · 1 跟随 2 坚守 3 冲锋", "右上角写小队人数与命令（%s）" % main.hud.squad_label.text)
	var hr: Rect2 = main.hud.squad_label.get_global_rect()
	check(hr.end.x <= main.hud.size.x and hr.position.y >= main.hud.menu_btn.get_global_rect().end.y, "小队一行在右上角按钮下面、不出屏幕")
	# —— 跟随（开打前）：站到玩家身后的队形里，玩家走开就跟上
	await place(p, -8.0, 10.0)
	Input.parse_input_event(key_ev(KEY_1))
	await frames(2)
	check(b.squad_order == "follow" and main.hud.toast_label.text.contains("◆ 小队：跟随我") and main.hud.squad_label.text.contains("：跟随我"), "按 1：小队跟随我（%s / %s / %s）" % [b.squad_order, main.hud.toast_label.text, main.hud.squad_label.text])
	await seconds(6.0)
	var near := squad.filter(func(s): return flat(s.global_position).distance_to(flat(b._follow_slot(s.slot, p))) < 1.0)
	check(near.size() >= 5, "跟到玩家身后的队形里（%d / 6 个到位）" % near.size())
	var behind := squad.filter(func(s): return (s.global_position - p.global_position).dot(-p.global_transform.basis.z) < 0.0)
	check(behind.size() == 6, "队形在玩家身后（%d / 6）" % behind.size())
	p.global_position = Vector3(6.0, 0.05, 10.0)
	await seconds(5.0)
	var caught := squad.filter(func(s): return flat(s.global_position).distance_to(flat(p.global_position)) < 6.0)
	check(caught.size() == 6, "玩家走开 14 米：小队跟上来（%d / 6）" % caught.size())
	# —— 原地坚守（开打前）：在玩家面前 2 米排成一线；玩家走开也不跟
	await place(p, -8.0, 10.0)
	await seconds(3.0)
	Input.parse_input_event(key_ev(KEY_2))
	await frames(2)
	check(b.squad_order == "hold" and squad.all(func(s): return s.anchor != Vector3.INF and absf(s.anchor.z - 8.0) < 0.01), "按 2：原地坚守，坚守点在玩家面前 2 米、排成一线")
	var anchors := {}
	for s in squad:
		anchors[s] = s.anchor
	await seconds(4.0)
	p.global_position = Vector3(-8.0, 0.05, 15.0)
	await seconds(3.0)
	var at_post := squad.filter(func(s): return flat(s.global_position).distance_to(flat(anchors[s])) < 1.0)
	check(at_post.size() >= 5, "玩家走开 5 米：小队站在坚守点不动（%d / 6 在位）" % at_post.size())
	# —— 开打以后跟随：只打离玩家 7 米以内的敌人；玩家站在后面角落里，小队不冲上去
	await place(p, -16.0, 16.0)
	Input.parse_input_event(key_ev(KEY_1))
	await seconds(4.0)
	b.start()
	var far_fight := 0
	var others_fight := false
	for i in 240:
		await get_tree().physics_frame
		for s in squad:
			if s.target != null and is_instance_valid(s.target) and flat(s.target.global_position).distance_to(flat(p.global_position)) > Battle.FOLLOW_LEASH + 0.5:
				far_fight += 1
		for s in white:
			if not s.in_squad and s.target != null:
				others_fight = true
	check(far_fight == 0, "跟随时小队不去打离你 7 米以外的敌人")
	check(others_fight, "小队以外的白带照样冲上去打")
	check(squad.all(func(s): return not s.fighting() or flat(s.global_position).distance_to(flat(p.global_position)) < 8.0), "小队一直待在你身边")
	# —— 坚守（打着仗）：只打坚守点 5 米以内的敌人
	Input.parse_input_event(key_ev(KEY_2))
	await frames(2)
	var hold_far := 0
	for i in 180:
		await get_tree().physics_frame
		for s in squad:
			if s.fighting() and s.target != null and is_instance_valid(s.target) and flat(s.target.global_position).distance_to(flat(s.anchor)) > Battle.HOLD_LEASH + 0.5:
				hold_far += 1
	check(hold_far == 0, "坚守时只打坚守点 5 米以内的敌人")
	# —— 冲锋：放开打
	Input.parse_input_event(key_ev(KEY_3))
	await frames(2)
	check(b.squad_order == "charge" and b.leash(squad[0]).is_empty(), "按 3：冲锋，不再拴绳")
	var charged := false
	for i in 300:
		await get_tree().physics_frame
		if squad.any(func(s): return s.target != null and is_instance_valid(s.target) and flat(s.target.global_position).distance_to(flat(p.global_position)) > Battle.FOLLOW_LEASH + 1.0):
			charged = true
			break
	check(charged, "冲锋：小队去打远处的敌人")
	await free_main(main)
	# —— 触屏：「令」只在有小队时出现，点开三个命令
	GameState.new_game(7)
	main = await make_battle()
	b = main.battle
	var t: TouchControls = main.touch
	t.force_visible = true
	t.visible = true
	t.player = main.player
	await frames(2)
	check(t.order_enabled and t.button_centers().has("order") and not t.button_centers().has("order_hold"), "触屏：有小队时多一个「令」，命令按钮先收着")
	var tap := func(pos: Vector2):
		var ev := touch_ev(5, pos, true)
		t._input(ev)
		t._input(touch_ev(5, pos, false))
	tap.call(t.button_centers().order)
	check(t.order_open and t.button_centers().has("order_follow") and t.button_centers().has("order_charge"), "点「令」：往左展开「跟随」「坚守」「冲锋」")
	var cs: Dictionary = t.button_centers()
	check(cs.order_charge.x < cs.order_hold.x and cs.order_hold.x < cs.order_follow.x and cs.order_follow.x < cs.order.x and cs.order_charge.x > 0.0, "三个命令按钮在「令」左边一字排开、不出屏幕")
	check(not t.buttons_rect().has_point(cs.order_charge), "展开的命令按钮不算进右下角按钮列（底部提示不跟着挪）")
	tap.call(cs.order_hold)
	await frames(2)
	check(b.squad_order == "hold" and not t.order_open and main.hud.squad_label.text == "◆ 小队 6 人：原地坚守 · 1 跟随 2 坚守 3 冲锋", "点「坚守」：下了命令，按钮收起")
	await free_main(main)
	# —— 别的区域没有小队：数字键不下命令、没有「令」
	main = await make_main(false)
	Input.parse_input_event(key_ev(KEY_1))
	await frames(2)
	check(main.battle == null and not main.touch.order_enabled and not main.hud.squad_label.visible and main.hud.toast_label.text != "◆ 小队：跟随我", "霜渡镇没有小队：数字键不下命令，不显示小队、没有「令」")
	await free_main(main)


## 合并后的占位外观（B.5）里有没有这个颜色；顶点色按 8 位存，差半格以内算一样
func look_has(s: Soldier, c: Color) -> bool:
	var cols: PackedColorArray = s.look.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	for x in cols:
		if absf(x.r - c.r) < 0.004 and absf(x.g - c.g) < 0.004 and absf(x.b - c.b) < 0.004:
			return true
	return false


func captain_of(list: Array) -> Soldier:
	for s in list:
		if s.is_captain:
			return s
	return null


## 士气、溃逃与胜负（路线图 B.3，GDD 6.4）：队长、援军、同伴倒下与队长倒下的士气、撑不住就跑、过半全体溃逃、胜负写旗标、开打前自动存档、战况一行
func test_morale() -> void:
	check(Enemy.types().has("captain") and int(Enemy.types().captain.hp) > int(Enemy.types().soldier.hp), "敌人数据：队长（血更多）")
	GameState.new_game(7)
	var main := await make_battle()
	var b: Battle = main.battle
	var white := soldiers_of(main, "white")
	var black := soldiers_of(main, "black")
	var wc := captain_of(white)
	var bc := captain_of(black)
	check(wc != null and bc != null and wc.is_captain and "Flag" in wc.look_parts and look_has(wc, wc.band_color) and not "Flag" in white[0].look_parts and wc.display_name == "白带 · 队长", "每边一个队长，背上插小旗（%s）" % (wc.display_name if wc else "-"))
	check(white[1].morale == 70.0 and white[2].morale == 55.0 and wc.morale == 100.0, "士气：剑兵 70、民兵 55、队长 100")
	check(b.waves.size() == 1 and b.side_total("black") == 14 and b.side_count("black", false) == 10 and b.side_count("black") == 14, "黑带还有 4 个援军没到（一共 14 人）")
	check(not main.hud.battle_label.visible, "开打前不显示战况")
	var all_s: Array = white + black
	for s in all_s:
		s.morale_t = 1000.0                               # 不让每秒的身边判断干扰下面的数
	wipe_test_saves()
	main.start_battle()
	await frames(3)
	var auto := Saves.read_slot("auto")
	check(b.started and str(auto.get("data", {}).get("scene", "")) == "battle", "开打前先自动存档（读档回到试验场）")
	check(main.hud.battle_label.visible and main.hud.battle_label.text == "战况：白带 10 人（士气 稳）· 黑带 10 人 +4 援军（士气 稳）", "右上角写战况（%s）" % main.hud.battle_label.text)
	# 同伴倒下：附近 8 米的慌（剑兵 −10、民兵 −15），远的不受影响
	white[0].take_hit({"damage": 999, "kind": "heavy", "stop": 0.0, "attacker": black[0]})
	check(white[1].morale == 60.0 and white[2].morale == 40.0 and wc.morale == 90.0 and white[7].morale == 70.0, "身边的同伴倒下：附近的剑兵 70 → 60、民兵 55 → 40、队长 100 → 90，11 米外的不变（%.0f / %.0f / %.0f / %.0f）" % [white[1].morale, white[2].morale, wc.morale, white[7].morale])
	# 队长倒下：己方全队 −30，对面全队 +15
	var b1: float = black[1].morale
	wc.take_hit({"damage": 999, "kind": "heavy", "stop": 0.0, "attacker": black[0]})
	await frames(2)
	check(white[1].morale == 40.0 and white[7].morale == 50.0 and white.filter(func(s): return s.fighting()).size() == 8 and black[1].morale == minf(b1 + 15.0, black[1].morale_max), "白带的队长倒下：白带全队 −20（没有连锁崩掉），黑带全队 +15（%.0f / %.0f / %.0f → %.0f）" % [white[1].morale, white[7].morale, b1, black[1].morale])
	check(main.hud.toast_label.text.contains("◆ 白带的队长倒下了！"), "提示「白带的队长倒下了！」")
	# 撑不住：士气掉到 20 以下就逃或求饶
	white[1].shake(-30.0)
	check(not white[1].fighting() and white[1].state in [Enemy.State.FLEE, Enemy.State.YIELD] and white[1].broke, "士气掉到 15 以下：逃跑或跪地求饶（%s）" % white[1].state_name())
	# 过半全体溃逃：一个个打倒白带，超过一半的那一下，剩下的全跑
	b.result_flag = "test_battle_result"
	var killed := 0
	while b.routed == "" and killed < 10:
		var left := white.filter(func(s): return s.fighting())
		if left.is_empty():
			break
		left[0].take_hit({"damage": 999, "kind": "heavy", "stop": 0.0, "attacker": black[0]})
		killed += 1
	check(b.routed == "white" and killed <= 3 and int(b.fallen.white) * 2 > b.side_total("white"), "白带倒下 / 逃跑过半就全体溃逃（队长倒了、民兵只剩 20 士气，吓跑一个就连锁崩掉；之后又打倒 %d 个）" % killed)
	check(white.all(func(s): return not s.fighting()), "溃逃以后白带没有还在打的人")
	await seconds(0.4)
	check(b.finished and b.winner == "black" and main.hud.toast_label.text.contains("◆ 白带溃逃了！"), "你这边溃逃：仗打输了（你还站着也算输）")
	check(GameState.get_flag("test_battle_result") == "lost", "结果写进旗标：lost")
	check(main.hud.battle_label.text == "战况：黑带胜（白带溃逃）", "战况一行写谁赢了（%s）" % main.hud.battle_label.text)
	await free_main(main)
	# 援军：开打 20 秒后从北头进场，直接进入战斗；对面过半溃逃时，还没到的援军不来了
	GameState.new_game(7)
	main = await make_battle()
	b = main.battle
	var wave: Array = b.waves[0].soldiers.duplicate()
	b.start()
	b.elapsed = BattleArena.WAVE_DELAY - 0.1
	await seconds(0.5)
	check(b.waves.is_empty() and wave.all(func(s): return s.is_inside_tree() and s.state == Enemy.State.COMBAT and s.global_position.z < -18.0), "开打 12 秒：4 个援军从北头进场，直接开打")
	check(main.hud.toast_label.text.contains("◆ 黑带来了 4 个援军"), "提示「黑带来了 4 个援军」")
	await free_main(main)
	GameState.new_game(7)
	main = await make_battle()
	b = main.battle
	black = soldiers_of(main, "black")
	wave = b.waves[0].soldiers.duplicate()
	b.start()
	for s in black:
		if b.routed != "":
			break
		if s.fighting():
			s.take_hit({"damage": 999, "kind": "heavy", "stop": 0.0, "attacker": soldiers_of(main, "white")[0]})
	check(b.routed == "black" and b.waves.is_empty() and wave.all(func(s): return not is_instance_valid(s)), "黑带过半溃逃（算上援军一共 14 人）：还没到的援军不来了")
	await seconds(0.4)
	check(b.finished and b.winner == "white", "你这边赢")
	await free_main(main)
	# 每秒看一次身边：敌多我少 −3；你在身边 +2；同时被两个人打 −3
	GameState.new_game(7)
	main = await make_battle()
	b = main.battle
	white = soldiers_of(main, "white")
	black = soldiers_of(main, "black")
	b.start()
	await frames(1)
	var x: Soldier = white[1]
	x.global_position = Vector3(-18, 0, -2)
	for i in 3:
		black[i + 3].global_position = Vector3(-18 + (i - 1) * 1.2, 0, -0.8)
	main.player.global_position = Vector3(10, 0.05, 14)
	var m0: float = x.morale
	b.morale_tick(x, 1.0)
	check(is_equal_approx(x.morale, m0 - 3.0), "身边 8 米：1 个自己人对 3 个敌人，士气 −3（%.0f → %.0f）" % [m0, x.morale])
	main.player.global_position = Vector3(-18, 0.05, -4)
	m0 = x.morale
	b.morale_tick(x, 1.0)
	check(is_equal_approx(x.morale, m0 - 3.0 + 2.0), "你站到他身边：多一个自己人，还 +2（%.0f → %.0f）" % [m0, x.morale])
	await free_main(main)


## 兵种（路线图 B.4，GDD 6.4）：剑盾兵、长枪兵、弓手（箭）；试验场的搭配
func test_troops() -> void:
	var t := Enemy.types()
	check(Enemy.validate_types(t).is_empty() and bool(t.shield.get("shield", false)) and t.spear.weapon == "spear" and float(t.spear.reach) > float(t.soldier.reach) + 0.5 and t.archer.weapon == "bow", "敌人数据：剑盾兵（带盾）、长枪兵（够得更远）、弓手（弓）")
	var counts := {}
	for i in 10:
		var k := BattleArena.kind_for(i, 10)
		counts[k] = int(counts.get(k, 0)) + 1
	check(counts == {"shield": 2, "soldier": 2, "levy": 2, "spear": 2, "archer": 1, "captain": 1}, "每边 10 人：剑盾 2、剑兵 2、长枪 2、民兵 2、弓手 1、队长 1（%s）" % [counts])
	GameState.new_game(7)
	var main := await make_battle()
	var b: Battle = main.battle
	var white := soldiers_of(main, "white")
	var black := soldiers_of(main, "black")
	var sh: Soldier = white[0]
	var sp: Soldier = white[3]
	var ar: Soldier = white[8]
	check(sh.has_shield and "Shield" in sh.look_parts and look_has(sh, sh.band_color.lerp(Color("6a5a48"), 0.25)) and not sp.has_shield and not "Shield" in sp.look_parts, "剑盾兵左手有盾（涂成布带颜色），别的兵没有")
	check(sp.arm.rotation_degrees.x < -70.0 and ar.is_archer and not sh.is_archer and ar.display_name == "白带 · 弓手", "长枪端平往前，弓手拿弓")
	check(b.waves[0].soldiers.map(func(s): return s.kind) == BattleArena.WAVE_KINDS, "黑带援军：剑盾、剑兵、弓手、民兵")
	# —— 剑盾兵：正面的轻击多半挡住，重击破防，正面的箭全挡，背后的箭挡不住
	var foe_s: Soldier = black[1]
	sh.engage()
	sh.global_position = Vector3(-10, 0, 0)
	sh.rotation.y = 0.0                                   # 面朝 -Z
	foe_s.global_position = Vector3(-10, 0, -1.5)
	await physics(2)
	var blocks := 0
	for i in 20:
		sh.action = ""
		sh.state = Enemy.State.COMBAT
		sh.hp = sh.hp_max
		if sh.take_hit({"damage": 5, "kind": "light", "stop": 0.0, "attacker": foe_s}) == "block":
			blocks += 1
	check(blocks >= 10, "剑盾兵挡住正面的轻击 %d / 20 次（七成上下）" % blocks)
	sh.action = ""
	sh.state = Enemy.State.COMBAT
	var hp0: int = sh.hp
	var r := ""
	for i in 5:
		sh.action = ""
		sh.state = Enemy.State.COMBAT
		r = sh.take_hit({"damage": 5, "kind": "heavy", "stop": 0.0, "attacker": foe_s})
		if r != "block":
			break
	check(r == "hit" and sh.hp < hp0, "重击：盾挡不住（想挡就被破防），掉血")
	sh.state = Enemy.State.COMBAT
	sh.action = ""
	sh.hp = sh.hp_max
	check(sh.take_hit({"damage": 9, "kind": "arrow", "stop": 0.0, "attacker": foe_s}) == "block" and sh.hp == sh.hp_max, "正面射来的箭：盾全挡住")
	foe_s.global_position = Vector3(-10, 0, 1.5)
	await physics(1)
	check(sh.take_hit({"damage": 9, "kind": "arrow", "stop": 0.0, "attacker": foe_s}) == "hit" and sh.hp < sh.hp_max, "背后射来的箭：挡不住")
	var sw: Soldier = white[1]
	sw.state = Enemy.State.COMBAT
	sw.action = ""
	foe_s.global_position = sw.global_position + sw.forward() * 1.5
	await physics(1)
	check(sw.take_hit({"damage": 9, "kind": "arrow", "stop": 0.0, "attacker": foe_s}) == "hit", "没盾的兵：正面的箭也挡不住")
	await free_main(main)
	# —— 长枪兵：2.4 米外捅得到，剑兵够不着
	GameState.new_game(7)
	main = await make_battle()
	b = main.battle
	white = soldiers_of(main, "white")
	black = soldiers_of(main, "black")
	b.start()
	await physics(1)
	sp = white[3]
	sw = white[1]
	var dummy: Soldier = black[1]
	for x in [sp, sw, dummy]:
		x.process_mode = Node.PROCESS_MODE_PAUSABLE
	dummy.global_position = Vector3(12, 0, -2)
	for pair in [[sp, Vector3(12, 0, 0.4)], [sw, Vector3(12, 0, 0.4)]]:
		var a: Soldier = pair[0]
		a.global_position = pair[1]
		a.rotation.y = 0.0
		a.target = dummy
	await physics(2)
	var before: int = dummy.hp
	dummy.state = Enemy.State.PATROL                        # 不让它挡
	sp.target = dummy
	sp.attack_kind = "light"
	sp.global_position = Vector3(12, 0, 0.4)
	sp.rotation.y = 0.0
	sp._strike_target()
	check(dummy.hp < before, "长枪兵：2.4 米外捅得到（%d → %d）" % [before, dummy.hp])
	before = dummy.hp
	sw.target = dummy
	sw.attack_kind = "light"
	sw.global_position = Vector3(12, 0, 0.4)
	sw.rotation.y = 0.0
	sp.global_position = Vector3(16, 0, 6)
	sw._strike_target()
	check(dummy.hp == before, "剑兵在同样的距离够不着")
	await free_main(main)
	# —— 弓手：站在合适的距离射你；太近就往后退；箭穿过自己人；正面举剑能挡箭
	GameState.new_game(7)
	main = await make_battle()
	var p: FpController = main.player
	var m: Melee = p.melee
	m.health = 100000
	var b2 := Battle.new()
	b2.add_side("a", "甲")
	b2.add_side("c", "乙")
	b2.player_side = "a"
	main.world.add_child(b2)
	var archer := Soldier.create("archer", "qa", "c", Color.GRAY, Color.BLACK)
	archer.position = Vector3(-16, 0, -14)
	archer.rotation.y = PI
	b2.enlist(archer, main.world)
	var mate := Soldier.create("soldier", "qm", "c", Color.GRAY, Color.BLACK)     # 射手的自己人，站在箭道上（不在这场战斗里，原地不动）
	mate.position = Vector3(-16, 0, -10)
	main.world.add_child(mate)
	await place(p, -16.0, -4.0)
	p.rotation.y = 0.0
	b2.start()
	var shots := 0
	var t0 := m.health
	for i in 60 * 8:
		await get_tree().physics_frame
		shots = maxi(shots, main.get_tree().get_nodes_in_group("arrow").size())
		if m.health < t0:
			break
	check(shots >= 1 and m.health < t0, "弓手在 10 米外拉弓射你，射中了（生命 %d → %d）" % [t0, m.health])
	check(mate.hp == mate.hp_max, "箭穿过射手的自己人，不伤他")
	check(archer.target == p and flat(archer.global_position).distance_to(flat(p.global_position)) > Soldier.BOW_MIN, "弓手站在 5 米以外")
	# 正面举剑挡箭（耗体力、不掉血）
	m.health = 100000
	await seconds(0.3)
	m.block_press()
	await seconds(0.6)
	var st0: float = m.stamina
	var h0: int = m.health
	var blocked := false
	for i in 60 * 8:
		await get_tree().physics_frame
		if m.stamina < st0 - 0.5:
			blocked = true
			break
	m.block_release()
	check(blocked and m.health == h0, "正面举剑：挡住了箭（体力 %.0f → %.0f，生命不掉）" % [st0, m.stamina])
	# 太近：往后退
	await place(p, -16.0, -12.0)
	var d0 := flat(archer.global_position).distance_to(flat(p.global_position))
	await seconds(1.5)
	var d1 := flat(archer.global_position).distance_to(flat(p.global_position))
	check(d0 < Soldier.BOW_MIN and d1 > d0 + 1.0, "你贴近到 %.1f 米：弓手往后退（%.1f 米）" % [d0, d1])
	await free_main(main)


## 60 人性能（路线图 B.5，TECH.md 4.10）：占位外观合并成两份网格、站着不动不做碰撞移动、跪定了停算、远处动作降频、军阵基准测试
func test_armyperf() -> void:
	Soldier.models_on = false              # 这一组量的是 B.5 合并好的占位胶囊（B.6 的真人外观另在 uniforms 组）
	GameState.new_game(7)
	var main := await make_battle()
	var b: Battle = main.battle
	var white := soldiers_of(main, "white")
	var kinds := {}
	var two := true
	for s: Soldier in white:
		kinds[s.kind] = true
		var meshes: Array = s.body.find_children("*", "MeshInstance3D", true, false).filter(func(m): return m.visible)
		var surfaces := 0
		for m in meshes:
			surfaces += m.mesh.get_surface_count()
		two = two and meshes.size() == 2 and surfaces == 2 and s.look in meshes
	check(two and kinds.size() == 6, "每个兵合并成两份网格（身子、兵器），各一个表面：剑兵、剑盾、长枪、民兵、弓手、队长都是（%d 种）" % kinds.size())
	var s0: Soldier = white[1]
	check(look_has(s0, s0.coat_color) and look_has(s0, Color("c8a88a")) and Array(s0.look_parts) == ["Coat", "Head", "Nose", "Band"], "合并后颜色不变：罩袍、脸、布带（%s）" % ", ".join(s0.look_parts))
	check(s0.look.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON and s0.arm.get_child(0).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "身子投影，兵器不投影（和原来一样）")
	# 打中时整个人闪红
	var foe_s: Soldier = soldiers_of(main, "black")[1]
	s0.take_hit({"damage": 3, "kind": "heavy", "stop": 0.0, "attacker": foe_s})
	await physics(2)                      # physics_frame 在各节点的 _physics_process 之前发出：等两帧
	check(s0.coat_mat == s0.look.material_override and s0.coat_mat.emission_energy_multiplier > 0.0, "打中时整个人闪一下红（自发光 %.2f）" % s0.coat_mat.emission_energy_multiplier)
	# 站着不动不做碰撞移动；悬空的照样落地
	var still: Soldier = white[2]
	var p0 := still.global_position
	await physics(30)
	check(still.is_on_floor() and still.global_position.distance_to(p0) < 0.01, "开打前站着的兵不漂（%.3f 米）" % still.global_position.distance_to(p0))
	still.global_position = p0 + Vector3(0, 0.6, 0)
	await physics(40)
	check(still.is_on_floor() and absf(still.global_position.y - p0.y) < 0.05, "悬空的兵照样落到地上（%.2f → %.2f）" % [p0.y + 0.6, still.global_position.y])
	# 开打后照样走得动
	b.morale_on = false
	b.start()
	var white_far: Soldier = white[4]
	var q0 := white_far.global_position
	await seconds(1.0)
	check(white_far.global_position.distance_to(q0) > 1.0, "开打以后照样走过去打（走了 %.1f 米）" % white_far.global_position.distance_to(q0))
	# 跪定了停算
	var y: Soldier = white[5]
	y._enter(Enemy.State.YIELD)
	await seconds(0.8)
	check(not y.is_physics_processing() and y.body.position.y < -0.4 and y.collision_layer == 0, "跪地求饶的兵跪定了就停掉每帧计算（身子 %.2f）" % y.body.position.y)
	# 人物模型的动作降频（B.6 起兵才挂人物模型；这里挂一个试）
	var cm := CharacterModel.new()
	white[6].add_child(cm)
	await frames(2)
	if cm.loaded:
		cm.play_loop("run", 1.0)
		cm.set_anim_every(2)
		var a0: float = cm.anim.current_animation_position
		await frames(6)
		var a1: float = cm.anim.current_animation_position
		check(cm.anim.callback_mode_process == AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL and cm.is_processing() and not is_equal_approx(a0, a1), "动作降频：每 2 帧手动推进一次，动作照样往前走（%.2f → %.2f 秒）" % [a0, a1])
		cm.set_anim_every(1)
		check(cm.anim.callback_mode_process == AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE and not cm.is_processing(), "离近了：改回引擎每帧推进")
		var sm: Soldier = white[6]
		sm.model = cm
		main.player.global_position = sm.global_position + Vector3(0, 0, 30)
		await seconds(0.4)
		var far_every := cm.anim_every
		main.player.global_position = sm.global_position + Vector3(0, 0, 4)
		await seconds(0.4)
		check(far_every == 2 and cm.anim_every == 1, "兵离镜头 15 米以外动作每 2 帧推进，走近了恢复每帧（远 %d、近 %d）" % [far_every, cm.anim_every])
	else:
		check(false, "人物模型没加载成功，测不了动作降频")
	await free_main(main)
	Soldier.models_on = true
	# 军阵基准测试（真机用）：你不参战，直接开打（不存档），两个机位各测一次，结果表显示在画面上
	GameState.new_game(7)
	var main2 := await make_battle()
	var saved_before := Saves.read_slot("auto")
	var rs: Array = await main2.run_battle_benchmark(-1, 0.3, 0.3)
	var text: String = main2.perf_overlay.bench_text
	check(rs.size() == 2 and rs.all(func(r): return r.has("logic_ms") and r.has("draw_calls")) and main2.battle.started and main2.battle.player_side == "" and not main2.battle.morale_on and main2.battle_bench, "军阵基准：直接开打、你不参战、关掉士气（没人溃逃）、军阵提示不弹，观战台上和两军之间各测一次（%d 项）" % rs.size())
	check(text.contains("军阵基准测试结果（20 人") and text.contains("观战台上：平均") and text.contains("两军之间：平均") and text.contains("逻辑约") and Array(text.split("\n")).all(func(l): return l.length() <= 30), "结果表写在画面上，每行不超过 30 个字（手机竖屏放得下）（%s）" % text.get_slice("\n", 0))
	check(Saves.read_slot("auto") == saved_before, "基准测试不自动存档（不覆盖你的自动存档）")
	await free_main(main2)


## 测试用的章节包下载器（4.1）：内容永远「不在」，前 fails 次下载失败，之后成功（不真下载）
class FakePacks extends PackLoader:
	var fails := 0
	var calls := 0

	func has_pack(_id: String) -> bool:
		return false

	func ensure(_id: String) -> Dictionary:
		calls += 1
		await get_tree().process_frame
		if calls <= fails:
			return {"ok": false, "detail": "网络出错了（4），请检查网络后重试", "ms": 0, "from": ""}
		return {"ok": true, "detail": "测试", "ms": 0, "from": "download"}


## 目录底下的文件（不含 .import / .uid），res:// 路径
func files_under(dir: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if not (f.ends_with(".import") or f.ends_with(".uid")):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		out.append_array(files_under(dir.path_join(sub)))
	return out


## 换上测试用的下载器（下载画面的进度信号不接，测不到也无妨）
func fake_packs(main: Node3D, fails: int) -> FakePacks:
	var fp := FakePacks.new()
	fp.fails = fails
	fp.process_mode = Node.PROCESS_MODE_ALWAYS
	main.add_child(fp)
	main.packs = fp
	return fp


## 章节衔接与章节包（路线图 4.1；TECH.md 第六节）：章节登记、导出预设、存档里的章节、下载器、下载画面、结束画面的「继续」、读第一章的存档
func test_chapters() -> void:
	check(Chapters.PLAYABLE >= 1 and Chapters.name_of(1) == "第一章 · 黑鹭堡" and Chapters.pack_of(0) == "" and Chapters.pack_of(1) == "ch1" and Chapters.wip_of(1) == "", "章节登记：序章在主包里，第一章在章节包 ch1；第一章开场（4.3）做好了，能继续（PLAYABLE = %d）" % Chapters.PLAYABLE)
	check(Chapters.probe_for_pack("ch1") == Chapters.probe_of(1) and Chapters.content_ready(0) and Chapters.content_ready(1), "编辑器 / 无头测试里第一章的内容本来就在 res://（网页上挂了章节包才在）")
	# 章节包只放场景与资源，脚本留在主包；主包排除 chapters/*；第一章的预设正好列出 chapters/ch1 底下的全部文件
	var files := files_under("res://chapters/ch1")
	files.sort()
	var cfg := ConfigFile.new()
	cfg.load("res://export_presets.cfg")
	var listed: Array = []
	var web_excl := ""
	for sec in cfg.get_sections():
		if sec.ends_with(".options"):
			continue
		if cfg.get_value(sec, "name", "") == "Chapter1":
			listed = Array(cfg.get_value(sec, "export_files", PackedStringArray()))
		elif cfg.get_value(sec, "name", "") == "Web":
			web_excl = str(cfg.get_value(sec, "exclude_filter", ""))
	listed.sort()
	check(not files.is_empty() and files.all(func(f): return not str(f).ends_with(".gd")), "章节包里只放场景与资源，脚本一律留在主包（%d 个文件）" % files.size())
	check(listed == files and web_excl.contains("chapters/*"), "导出预设：主包排除 chapters/*；第一章的预设正好列出 chapters/ch1 底下的全部文件（%s）" % ", ".join(listed))
	# 存档：章节跟着走；4.1 以前的存档没有这一项 = 序章
	GameState.new_game(5)
	check(GameState.chapter == 0 and int(GameState.to_dict().chapter) == 0, "新游戏是序章（chapter = 0）")
	GameState.chapter = 1
	var d := JSON.parse_string(JSON.stringify(GameState.to_dict())) as Dictionary
	GameState.new_game(5)
	GameState.from_dict(d)
	var back := GameState.chapter
	d.erase("chapter")
	GameState.from_dict(d)
	check(back == 1 and GameState.chapter == 0, "章节写进存档、读得回来；以前的存档没有这一项，读出来是序章")
	# 下载器：内容已经在就不下载；不是网页、内容又不在时说明原因、不卡住
	var pl := PackLoader.new()
	add_child(pl)
	var r1: Dictionary = await pl.ensure("ch1")
	var r2: Dictionary = await pl.ensure("ch9")
	check(r1.ok and r1.from == "present" and not r2.ok and str(r2.detail) == "这一章的内容不在这个版本里" and pl.busy == "", "下载器：内容已经在就不下载；没有的章节说明原因")
	pl.free()
	# 下载画面
	wipe_test_saves()
	GameState.new_game(81)
	var main := await make_main(false)
	var pp: PackPanel = main.pack_panel
	pp.open("第一章 · 黑鹭堡", true)
	pp.set_progress(1258291, 3565158)
	check(pp.visible and pp.title.text == "正在载入 第一章 · 黑鹭堡" and pp.detail.text == "已下载 1.2 / 3.4 MB" and absf(pp.bar.value - 0.353) < 0.01 and not pp.retry_btn.visible, "下载画面：章节名、进度条、「已下载 1.2 / 3.4 MB」")
	pp.set_progress(2097152, 0)
	check(pp.detail.text == "已下载 2.0 MB", "不知道总大小时只写下了多少")
	pp.fail("网络出错了（4），请检查网络后重试")
	await frames(2)
	check(pp.retry_btn.visible and pp.cancel_btn.visible and pp.retry_btn.has_focus() and not pp.bar.visible and pp.detail.text == "× 没能载入：网络出错了（4），请检查网络后重试", "失败：写明原因，「重试」「返回」，焦点在「重试」上（键盘能直接按）")
	pp.close()
	check(await main.ensure_chapter(1) and not pp.visible, "第一章的内容已经在：不开下载画面")
	# 结束画面：能玩的章节是 0 时（第一章开场做好以前）没有「继续」；能玩以后有，默认焦点在它上面
	main.playable_chapter = 0
	main.show_ending("prologue", "deliver")
	await frames(3)
	check(main.ending_panel.visible and not main.ending_panel.continue_btn.visible and main.ending_panel.back_btn.has_focus(), "第一章开场做好以前：结束画面没有「继续」（和原来一样）")
	main.ending_panel.close()
	await frames(2)
	main.playable_chapter = 1
	main.show_ending("prologue", "deliver")
	await frames(3)
	var eb: EndingPanel = main.ending_panel
	check(eb.continue_btn.visible and eb.continue_btn.text == "继续：第一章 · 黑鹭堡" and eb.continue_btn.has_focus() and eb.box.get_global_rect().size.x <= main.hud.size.x, "能玩以后：结束画面多一行「继续：第一章 · 黑鹭堡」，焦点在它上面，不超出画面宽度")
	# 继续：第一章——去霜渡镇宅邸门口，路牌在，章节记进存档
	var rl := [0]
	main.reload_requested.connect(func(): rl[0] += 1)
	eb.continue_btn.pressed.emit()
	await frames(3)
	check(rl[0] == 1 and GameState.chapter == 1 and GameState.has_flag("ch1_started") and GameState.pending_load.get("scene") == "frostford" and GameState.pending_load.get("spawn") == "ch1_dawn", "「继续」：记下第一章，去霜渡镇宅邸门口（面朝门口等着的维克托，4.3）")
	main = await reload_main(main)
	await frames(4)
	var sign := main.world.get_node_or_null("RoadSignCh1") as Node3D
	check(main.area == "frostford" and sign != null and (sign.get_node("Text") as Label3D).text == "往鹭沼 · 黑鹭堡", "第一章：宅邸门口立着「往鹭沼 · 黑鹭堡」的路牌（场景在章节包里）")
	var to: Vector3 = sign.global_position - main.player.global_position if sign else Vector3.ZERO
	check(to.length() < 5.0 and (-main.player.global_basis.z).dot(to.normalized()) < -0.3, "路牌就在身后几步（%.1f 米；4.3 起开场面朝宅邸门口的维克托）" % to.length())
	check(main.hud.toast_label.text.contains("第一章 · 黑鹭堡") and GameState.has_flag("ch1_intro"), "刚进第一章先报章节名")
	await frames(3)
	var au: Dictionary = Saves.read_slot("auto")
	check(au.has("data") and int(au.data.state.chapter) == 1 and au.data.scene == "frostford", "进第一章自动存档：存档里写着第一章")
	# 读第一章的存档：章节包拿不到时下载画面说原因；点「返回」，存档没读、现在的游戏不动
	var fp := fake_packs(main, 99)
	GameState.silver = 7
	var rl2 := [0]
	main.reload_requested.connect(func(): rl2[0] += 1)
	check(main.load_game("auto"), "读第一章的存档：先去拿章节包")
	await frames(4)
	check(main.pack_panel.visible and main.pack_panel.failed and main.pack_panel.retry_btn.visible and get_tree().paused, "章节包拿不到：下载画面写明原因、给「重试」「返回」，游戏暂停")
	main.pack_panel.retry_btn.pressed.emit()
	await frames(4)
	check(fp.calls == 2 and main.pack_panel.failed, "点「重试」：再下载一次（又失败了）")
	main.pack_panel.cancel_btn.pressed.emit()
	await frames(3)
	check(not main.pack_panel.visible and rl2[0] == 0 and GameState.silver == 7 and not get_tree().paused and main.hud.toast_label.text.contains("存档没读"), "点「返回」：存档没读，现在的游戏不动，接着玩")
	# 重试一次就成了：读进来
	fp.fails = fp.calls + 1
	check(main.load_game("auto"), "再读一次")
	await frames(4)
	main.pack_panel.retry_btn.pressed.emit()
	await frames(6)
	check(rl2[0] == 1 and GameState.chapter == 1 and GameState.silver != 7 and not main.pack_panel.visible, "重试成功：读进第一章的存档")
	main = await reload_main(main)
	await frames(3)
	check(main.world.get_node_or_null("RoadSignCh1") != null, "读档回来：路牌还在")
	await free_main(main)
	GameState.new_game()


## 第一章的霜渡镇（4.2 起的测试用）：章节、时段、站在宅邸门口（路牌前）
func make_ch1(daypart := "dawn") -> Node3D:
	GameState.chapter = 1
	GameState.daypart = daypart
	GameState.pending_load = {"scene": "frostford", "spawn": "manor", "player": {}}
	return await make_main(false)


## 有多少栋房子此刻亮着灯（Daypart.set_windows 记的 lit_now；没套过时段的按建的时候算亮）
func houses_lit(main: Node3D) -> Array:
	var on := 0
	var all := 0
	for h in main.get_tree().get_nodes_in_group("house"):
		all += 1
		if bool(h.get_meta("lit_now", true)):
			on += 1
	return [on, all]


## 时段（路线图 4.2；STORY.md 4.9；world/daypart.gd）：预设、存档、霜渡镇的清晨、白天 / 黄昏现场换光、室内不受影响、敌人视距、对话效果、进第一章是清晨
func test_daypart() -> void:
	check(Daypart.IDS.size() == 4 and Daypart.IDS.all(func(i): return Daypart.PRESETS.has(i) and Daypart.NAMES.has(i) and Daypart.CHANGE_TEXT.has(i)), "四个时段：清晨 / 白天 / 黄昏 / 夜，各有预设、名字和换时段的提示")
	var keys: Array = Daypart.PRESETS.night.keys()
	check(Daypart.IDS.all(func(i): return Daypart.PRESETS[i].keys().size() == keys.size() and keys.all(func(k): return Daypart.PRESETS[i].has(k))), "每个预设的项一样多（%d 项），不会漏改哪一项" % keys.size())
	var nt: Dictionary = Daypart.PRESETS.night
	check(nt.sky == Color("22344a") and nt.ambient == Color("6f8faf") and nt.sun == Color("8fb0d6") and is_equal_approx(nt.sun_energy, 0.32) and nt.sun_rot == Vector3(-38, 150, 0) and is_equal_approx(nt.fog_end, 36.0), "夜的预设和序章原来的数值一字不差（天色、月光、雾）")
	check(is_equal_approx(Daypart.PRESETS.night.sight_dark, Enemy.SIGHT_DARK) and is_equal_approx(Daypart.PRESETS.day.sight_dark, Enemy.SIGHT_LIT) and Daypart.PRESETS.dusk.sight_dark < Daypart.PRESETS.dawn.sight_dark, "敌人在暗处的视距：夜 8 米、黄昏 12、清晨 14、白天 20（= 灯下）")
	check(Chapters.daypart_of(0) == "night" and Chapters.daypart_of(1) == "dawn" and Chapters.daypart_of(9) == "night", "序章是夜；第一章从清晨开始")
	check(not Daypart.affects("tavern") and not Daypart.affects("chapel") and not Daypart.affects("arena") and not Daypart.affects("test_range") and Daypart.affects("frostford") and Daypart.affects("birch"), "受时段影响的是室外区域；室内、训练场、灰盒测试场不受")
	check(Daypart.effective("tavern", "day") == "night" and Daypart.effective("frostford", "day") == "day" and Daypart.effective("frostford", "noon") == "night", "室内永远按夜的样子；不认识的时段当夜")
	# 存档
	GameState.new_game(5)
	check(GameState.daypart == "night" and str(GameState.to_dict().daypart) == "night", "新游戏是夜")
	GameState.chapter = 1
	GameState.daypart = "dusk"
	var d := JSON.parse_string(JSON.stringify(GameState.to_dict())) as Dictionary
	GameState.new_game(5)
	GameState.from_dict(d)
	var back := GameState.daypart
	d.erase("daypart")
	GameState.from_dict(d)
	var old1 := GameState.daypart
	d.chapter = 0
	GameState.from_dict(d)
	var old0 := GameState.daypart
	d.daypart = "noon"
	d.chapter = 1
	GameState.from_dict(d)
	check(back == "dusk" and old1 == "dawn" and old0 == "night" and GameState.daypart == "dawn", "时段写进存档、读得回来；4.2 以前的存档没有这一项：按这一章开头的时段（序章夜、第一章清晨）；坏值也按这个")
	# 序章的霜渡镇：夜，和原来一样
	GameState.new_game(41)
	var main := await make_main(false)
	var hl := houses_lit(main)
	var lamps := main.get_tree().get_nodes_in_group("street_lamp")
	check(main.daypart == "night" and Daypart.current == "night" and main.env.background_color == main.FOG_COLOR and hl[0] == hl[1] and hl[1] == 12, "序章：夜，12 栋房子都按原来的样子亮着灯")
	check(lamps.size() == 4 and lamps.all(func(l): return l.lit and l.light.visible and l.is_in_group("light_source")), "夜里 4 盏街灯亮着，算敌人感知的光源")
	await free_main(main)
	# 第一章的清晨
	main = await make_ch1("dawn")
	var dp: Dictionary = Daypart.PRESETS.dawn
	hl = houses_lit(main)
	lamps = main.get_tree().get_nodes_in_group("street_lamp")
	check(main.daypart == "dawn" and Daypart.current == "dawn" and main.env.background_color == dp.sky and main.env.fog_light_color == dp.sky and is_equal_approx(main.env.fog_depth_end, dp.fog_end), "第一章的霜渡镇是清晨：天色、远雾换成清晨（雾散了一半：%.0f 米才吞没）" % main.env.fog_depth_end)
	check(main.moon.light_color == dp.sun and is_equal_approx(main.moon.light_energy, dp.sun_energy) and main.moon.visible and main.moon.rotation_degrees.is_equal_approx(dp.sun_rot), "清晨的太阳偏暖")
	var sun_dir: Vector3 = -main.moon.global_basis.z
	check(sun_dir.x < -0.6 and sun_dir.z < -0.3 and sun_dir.y < 0.0 and sun_dir.y > -0.35, "清晨的太阳从东南低低地照过来，往西北照进街里（方向 %s）" % str(sun_dir))
	check(hl[0] >= 2 and hl[0] <= hl[1] - 4, "清晨只有几栋房子还亮着灯（%d / %d 栋）" % [hl[0], hl[1]])
	check(lamps.all(func(l): return not l.lit and not l.light.visible and not l.halo_node.visible and not l.is_in_group("light_source")) and main.get_tree().get_nodes_in_group("light_source").is_empty(), "清晨街灯灭了：灯、光晕都藏起来，也不再算敌人感知的光源")
	var dark_house: Node3D = null
	for h in main.get_tree().get_nodes_in_group("house"):
		if not bool(h.get_meta("lit_now", true)) and int(h.get_meta("windows").lit) > 0:
			dark_house = h
			break
	var swapped := false
	if dark_house:
		var mi := dark_house.get_node("Mesh") as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			if mi.mesh.surface_get_material(i) == Look.glass_lit():
				swapped = mi.get_surface_override_material(i) == Look.glass_dark()
	check(swapped and Look.glass_lit().albedo_color == Color("d99a48"), "灭了灯的房子：亮窗换成暗玻璃（表面覆盖，共用的材质不改）")
	var band: MeshInstance3D = main.get_tree().get_nodes_in_group("fog_band")[0]
	var bm := band.material_override as ShaderMaterial
	check(bm.get_shader_parameter("color") == dp.band and is_equal_approx(float(bm.get_shader_parameter("density")), float(band.get_meta("base_density")) * dp.band_density), "贴地雾带换成清晨的颜色、淡一点")
	main.apply_quality("low")
	check(main.env.background_color == dp.sky and not main.moon.shadow_enabled and not main.env.glow_enabled, "换画质不会把时段冲掉（阴影、泛光归画质）")
	main.apply_quality("medium")
	# 现场换到白天：不重新载入，再套一次
	var rl := [0]
	main.reload_requested.connect(func(): rl[0] += 1)
	await main.set_daypart("day")
	await frames(2)
	hl = houses_lit(main)
	check(rl[0] == 0 and main.daypart == "day" and GameState.daypart == "day" and main.env.background_color == Daypart.PRESETS.day.sky and hl[0] == 0, "剧情推进到白天：不重新载入，直接换光；白天家家都不点灯")
	check(main.hud.toast_label.text.contains(Daypart.CHANGE_TEXT.day) and main.moon.shadow_enabled, "上方提示「%s」；画质的阴影还在" % Daypart.CHANGE_TEXT.day)
	await main.set_daypart("dusk")
	hl = houses_lit(main)
	check(hl[0] == hl[1] and lamps.all(func(l): return l.lit and l.light.visible and l.is_in_group("light_source")) and main.env.background_color == Daypart.PRESETS.dusk.sky, "黄昏：街灯点上、家家亮灯")
	var b2 := float(bm.get_shader_parameter("density"))
	Daypart.apply(main, "dusk")
	Daypart.apply(main, "dusk")
	hl = houses_lit(main)
	check(is_equal_approx(float(bm.get_shader_parameter("density")), b2) and is_equal_approx(b2, float(band.get_meta("base_density")) * Daypart.PRESETS.dusk.band_density) and hl[0] == hl[1], "同一个时段再套两次没有变化（雾带浓度不会越乘越淡）")
	# 对话效果与条件
	var errs := []
	DialogueRunner._validate_effects([{"daypart": "noon"}], "测试", {}, errs)
	DialogueRunner._validate_conds([{"daypart": ["dawn", "teatime"]}], "测试", {}, errs)
	var ok_errs := []
	DialogueRunner._validate_effects([{"daypart": "dusk"}], "测试", {}, ok_errs)
	DialogueRunner._validate_conds([{"daypart": "day"}, {"daypart": ["dawn", "dusk"]}], "测试", {}, ok_errs)
	check(errs.size() == 2 and ok_errs.is_empty(), "对话里的时段效果与条件：认识的时段才过检查（%s）" % "; ".join(errs))
	GameState.daypart = "dusk"
	check(DialogueRunner.conds_ok([{"daypart": "dusk"}]) and DialogueRunner.conds_ok([{"daypart": ["day", "dusk"]}]) and not DialogueRunner.conds_ok([{"daypart": ["dawn", "day"]}]), "条件：现在是这个时段（或这几个之一）")
	DialogueRunner.apply([{"daypart": "night"}])
	check(GameState.daypart == "night" and GameState.pending_daypart == "night" and main.daypart == "dusk", "效果：存档里马上是夜，画面等对话关上再换")
	main._on_dialogue_closed()
	await seconds(1.6)
	check(main.daypart == "night" and GameState.pending_daypart == "" and main.env.background_color == main.FOG_COLOR and main.fade.color.a < 0.05, "对话关上：黑一下换成夜，再亮回来")
	await free_main(main)
	# 室内不受影响：白天进酒馆，还是炉火和暖暗的环境光
	GameState.daypart = "day"
	main = await make_area("tavern")
	check(main.daypart == "night" and Daypart.current == "night" and not main.moon.visible and main.env.background_color.r < 0.1 and main.env.fog_mode == Environment.FOG_MODE_EXPONENTIAL, "白天进酒馆：室内照旧（时段只记着，不换光）")
	await free_main(main)
	# 敌人视距：桦林的白天，暗处也看得见 20 米；营火不是夜灯，门口的风灯是
	GameState.new_game(43)
	GameState.daypart = "day"
	main = await make_area("birch")
	await frames(3)
	var e: Enemy = main.get_tree().get_nodes_in_group("enemy")[0]
	var nl := main.get_tree().get_nodes_in_group("night_light")
	check(nl.size() == 2 and nl.all(func(l): return not l.visible) and main.get_tree().get_nodes_in_group("light_source").size() == 1, "桦林的白天：门口两盏风灯灭了，营火照烧（仍是光源）")
	main.player.global_position = Birch.SPAWNS.north[0]
	check(not e.player_lit() and is_equal_approx(e.sight_range(), 20.0), "白天站在暗处，敌人也能看 20 米")
	await free_main(main)
	GameState.daypart = "night"
	main = await make_area("birch")
	await frames(3)
	e = main.get_tree().get_nodes_in_group("enemy")[0]
	main.player.global_position = Birch.SPAWNS.north[0]
	check(not e.player_lit() and is_equal_approx(e.sight_range(), Enemy.SIGHT_DARK) and main.get_tree().get_nodes_in_group("night_light").all(func(l): return l.visible), "夜里照旧 8 米；风灯亮着")
	await free_main(main)
	# 墓园、渡口的夜灯：白天灭、光源组跟着进出
	GameState.daypart = "day"
	main = await make_area("ferry")
	nl = main.get_tree().get_nodes_in_group("night_light")
	check(nl.size() == 5 and nl.filter(func(l): return l is OmniLight3D).size() == 4 and nl.all(func(l): return not l.visible and not l.is_in_group("light_source")), "渡口的白天：4 盏风灯和北头路口的灯笼（3.10）都灭了，不算光源")
	await main.set_daypart("dusk", false)
	check(main.get_tree().get_nodes_in_group("light_source").size() >= 2 and nl.all(func(l): return l.visible), "黄昏点上：码头的两盏又算光源了")
	await free_main(main)
	# 进第一章：从清晨开始
	wipe_test_saves()
	GameState.new_game(44)
	main = await make_main(false)
	main.playable_chapter = 1
	var rl2 := [0]
	main.reload_requested.connect(func(): rl2[0] += 1)
	await main.start_chapter(1)
	check(rl2[0] == 1 and GameState.daypart == "dawn", "「继续：第一章」：时段记成清晨")
	main = await reload_main(main)
	await frames(3)
	check(main.daypart == "dawn" and main.env.background_color == Daypart.PRESETS.dawn.sky, "到了霜渡镇宅邸门口：清晨")
	var au: Dictionary = Saves.read_slot("auto")
	check(au.has("data") and str(au.data.state.daypart) == "dawn", "进第一章自动存档：存档里写着清晨")
	await free_main(main)
	GameState.new_game()


## 测试用的旅行数据：芦栈村「做好了」（借酒馆当目的地），黑鹭堡借小教堂，用来走完出发的整条路
func travel_fixture() -> Dictionary:
	var d: Dictionary = Travel.data().duplicate(true)
	d.places.reedwharf.area = "tavern"
	d.places.reedwharf.spawn = "front"
	d.places.blackheron.area = "chapel"
	d.places.blackheron.spawn = Chapel.SPAWNS.keys()[0]
	return d


## 旅行地图（路线图 4.2；STORY.md 4.2；core/travel.gd、ui/travel_map.gd）：数据、能不能走、序章没有、路牌打开、只能看、出发前自动存档、到了是白天、窄屏
func test_travelmap() -> void:
	Travel.override(null)
	check(Travel.validate().is_empty(), "旅行数据通过检查（%s）" % "; ".join(Travel.validate()))
	check(Travel.places(0).is_empty() and Travel.places(1) == ["frostford", "reedwharf", "blackheron"], "序章没有旅行地图；第一章：霜渡镇、芦栈村、黑鹭堡")
	check(Travel.place_of_area("frostford") == "frostford" and Travel.place_of_area("tavern") == "" and Travel.built("frostford") and Travel.built("reedwharf") and Travel.built("blackheron")
		and str(Travel.place("reedwharf").area) == "marsh" and str(Travel.place("blackheron").area) == "marsh", "霜渡镇是地图上的地点；芦栈村、黑鹭堡做好了（4.4a：都在鹭沼这张连片地图上）")
	var c1 := Travel.check(1, "frostford", "reedwharf", true)
	var c2 := Travel.check(1, "frostford", "frostford", true)
	var c3 := Travel.check(1, "frostford", "blackheron", true)
	var c4 := Travel.check(1, "reedwharf", "blackheron", true)
	check(c1.ok and c2.why == "你就在这里。" and c3.why == "从这里去不了，先到芦栈村。" and c4.ok and str(c1.route.daypart) == "day", "从霜渡镇能去芦栈村（到了是白天）；黑鹭堡要先到芦栈村再走堤道")
	Travel.override(travel_fixture())
	check(Travel.validate().is_empty(), "测试数据（借酒馆、小教堂当目的地）也通过检查")
	var f1 := Travel.check(1, "frostford", "reedwharf", false)
	var f2 := Travel.check(1, "frostford", "reedwharf", true)
	var f3 := Travel.check(1, "frostford", "blackheron", true)
	var f4 := Travel.check(1, "", "reedwharf", true)
	check(f1.why == "走到宅邸门口的路牌那里才能出发。" and f2.ok and f3.why == "从这里去不了，先到芦栈村。" and f4.why == "要先回到地图上的地方才能出发。", "做好了以后：要站在路牌那里；黑鹭堡要先到芦栈村再走堤道")
	Travel.override(null)
	# 序章：没有旅行地图；3.11 起按 M 打开地图册的「本地」页（原来只弹一句「序章没有旅行地图，第一章起才有」）
	wipe_test_saves()
	GameState.new_game(51)
	var main := await make_main(false)
	main._unhandled_input(key_ev(KEY_M))
	await frames(2)
	check(not main.travel_map.visible and main.map_panel.visible and main.map_panel.view == "local" and get_tree().paused and not main.map_panel.tabs.btns.travel.visible, "序章按 M：打开地图册的「本地」页，没有「北境西部」（旅行地图第一章起才有）")
	main.map_panel._unhandled_input(key_ev(KEY_ESCAPE))
	await frames(2)
	await free_main(main)
	# 第一章：对着路牌按交互打开
	GameState.new_game(52)
	main = await make_ch1("dawn")
	var sign := main.world.get_node("RoadSignCh1") as Node3D
	var mp := sign.get_node("MapPoint") as TravelPoint
	await aim(main.player, sign.global_position + Vector3(0, 0, -2.0), mp.global_position + Vector3(0, 1.6, 0))
	var t: Interactable = main.player.interactor.target
	check(t == mp and t.prompt() == "查看地图 · 往鹭沼 · 黑鹭堡", "对着路牌：「查看地图 · 往鹭沼 · 黑鹭堡」")
	main.player.interactor.use()
	await frames(4)
	var tm: TravelMap = main.travel_map
	check(tm.visible and get_tree().paused and tm.at_departure and tm.here == "frostford" and tm.place_btns.size() == 3 and not main.hud.visible, "打开旅行地图：游戏暂停，提示和触屏按钮藏起来；站在路牌旁能出发")
	check(tm.selected == "reedwharf" and not tm.go_btn.disabled and not tm.status.visible and tm.route_label.text == "路：出镇往西，沿着沼地边上的路走大半天，到了是白天" and (tm.place_btns.reedwharf as Button).has_focus(), "默认选芦栈村：路线、到了是白天；能出发（4.4a）；焦点在地点上（键盘能用）")
	check((tm.place_btns.frostford as Button).text == "霜渡镇（你在这里）" and tm.go_btn.text == "出发去芦栈村", "霜渡镇标着「你在这里」")
	tm.select("frostford")
	check(tm.status.text == "你就在这里。" and tm.go_btn.disabled, "选霜渡镇：你就在这里")
	var cr := tm.canvas.get_global_rect()
	var inside := true
	for b in tm.place_btns.values():
		inside = inside and cr.encloses((b as Button).get_global_rect())
	check(inside and Rect2(Vector2.ZERO, main.hud.size).encloses(tm.box.get_global_rect()), "地点按钮都在地图里，地图和按钮都在画面里（1280 × 720）")
	tm._unhandled_input(key_ev(KEY_ESCAPE))
	await frames(2)
	check(not tm.visible and not get_tree().paused and main.hud.visible, "Esc 关上地图，接着玩")
	# 换成测试数据：芦栈村做好了
	Travel.override(travel_fixture())
	main.player.global_position = Frostford.SPAWNS.start[0]
	await physics(2)
	check(not main.near_travel_point(), "主街南头离路牌很远")
	main._unhandled_input(key_ev(KEY_M))
	await frames(4)
	check(main.map_panel.visible and main.map_panel.view == "local" and not tm.visible, "离路牌远时按 M：先打开地图册的「本地」页（3.11；看得到路牌在哪）")
	main.map_panel.tabs.btns.travel.pressed.emit()
	await frames(4)
	check(tm.visible and not main.map_panel.visible and not tm.at_departure and tm.status.text == "走到宅邸门口的路牌那里才能出发。" and tm.go_btn.disabled and get_tree().paused, "切到「北境西部」：只能看，写明要走到路牌那里")
	tm._unhandled_input(key_ev(KEY_M))
	await frames(2)
	check(not tm.visible and not main.map_panel.visible and not get_tree().paused and main.hud.visible, "再按 M 关上")
	main.player.global_position = mp.global_position + Vector3(0, 0, -2.0)
	await physics(2)
	main._unhandled_input(key_ev(KEY_M))
	await frames(4)
	check(tm.visible and tm.at_departure and tm.selected == "reedwharf" and not tm.go_btn.disabled, "站在路牌旁按 M 也能出发：芦栈村（测试数据）可以去了")
	# 倒下了不能走
	var before := JSON.stringify(Saves.read_slot("auto"))
	main.player.melee.down = true
	tm.go_btn.pressed.emit()
	await frames(2)
	check(tm.visible and tm.status.text == "× 你已经倒下了。" and JSON.stringify(Saves.read_slot("auto")) == before and GameState.daypart == "dawn", "倒下了：不能走，自动存档没动、时段不变")
	main.player.melee.down = false
	# 出发：先自动存档（出发前的样子），再改时段、换区域
	var rl := [0]
	main.reload_requested.connect(func(): rl[0] += 1)
	GameState.silver = 23
	tm.go_btn.pressed.emit()
	await seconds(0.6)
	var au: Dictionary = Saves.read_slot("auto")
	check(au.has("data") and au.data.scene == "frostford" and str(au.data.state.daypart) == "dawn" and int(au.data.state.silver) == 23, "出发前自动存档：存的是出发前的样子（霜渡镇、清晨）")
	check(rl[0] == 1 and GameState.daypart == "dawn" and GameState.pending_load.get("daypart") == "day" and GameState.pending_load.get("scene") == "tavern" and GameState.pending_load.get("spawn") == "front" and not tm.visible, "出发：换区域；路上的大半天记在换区域的信息里，人还没到时段不变")
	main.open_travel_map(true)
	await frames(2)
	check(main.leaving and not tm.visible and not get_tree().paused, "已经出发、正在淡出：不能再打开地图")
	main = await reload_main(main)
	await frames(4)
	check(main.area == "tavern" and main.arrived_by == "front" and GameState.daypart == "day", "到了（测试数据借酒馆当芦栈村）：白天了")
	var prev := Saves._parse(Saves._read_raw(Saves._key("auto") + ".prev"))
	var au2: Dictionary = Saves.read_slot("auto")
	check(au2.has("data") and au2.data.scene == "tavern" and prev.get("scene", "") == "frostford", "到了又自动存一次；出发前那份留作上一份")
	await free_main(main)
	Travel.override(null)
	# 窄屏：手机竖屏、横屏都放得下
	for sz in [Vector2i(360, 740), Vector2i(740, 360), Vector2i(768, 1024)]:
		get_tree().root.size = sz
		await frames(3)
		main = await make_ch1("dawn")
		main.open_travel_map(true)
		await frames(5)
		tm = main.travel_map
		var view := Rect2(Vector2.ZERO, UiKit.logical_size(tm))
		cr = tm.canvas.get_global_rect()
		inside = view.encloses(tm.box.get_global_rect())
		for b in tm.place_btns.values():
			inside = inside and cr.encloses((b as Button).get_global_rect())
		check(inside and tm.go_btn.get_global_rect().size.y >= 44.0 and tm.wide == (sz.x > sz.y), "%d × %d：地图、介绍、按钮都在画面里，地点按钮在地图里（%s）" % [sz.x, sz.y, "介绍在地图右边" if tm.wide else "竖排"])
		tm.close()
		await free_main(main)
	get_tree().root.size = Vector2i(1280, 720)
	await frames(3)
	GameState.new_game()


## 序章打完、进了第一章的样子（4.3 测试用）：按 ferry.json 三种结局给的东西摆好游戏状态，再进第一章的霜渡镇（宅邸门口，面朝维克托）
func ch1_after(choice: String, sd := 1) -> Node3D:
	ch1_state(choice, sd)
	GameState.pending_load = {"scene": "frostford", "spawn": "ch1_dawn", "player": {}}
	var main := await make_main(false)
	await physics(4)
	main.player.interactor.refresh()
	return main


## 序章做完、刚进第一章时的状态（choice = 序章抉择 deliver / release / extort），还没载入场景
func ch1_state(choice: String, sd := 1) -> void:
	GameState.new_game(sd)                        # 先清空（检定的种子也在这里定）
	GameState.set_flag("opening_done")
	GameState.start_quest("edric_missing")
	GameState.set_flag("offer_left")
	GameState.set_flag("edric_showed_debt")
	GameState.set_flag("saw_royal_seal")
	GameState.set_stage("edric_missing", "after_choice")
	GameState.set_flag("prologue_edric", choice)
	match choice:
		"deliver":
			GameState.add_item("debt_note")
			GameState.set_flag("edric_hates_you")
			GameState.change_rep("valen", 10)
			GameState.change_rep("caswell", -10)
		"release":
			GameState.set_flag("edric_owes_you")
		"extort":
			GameState.add_item("debt_note")
			GameState.add_silver(120)
			GameState.change_rep("caswell", -30)
			GameState.set_flag("valen_may_learn")
	GameState.add_item("old_book")
	GameState.set_flag("prologue_done")
	GameState.complete_quest("edric_missing")
	GameState.chapter = 1
	GameState.daypart = "dawn"
	GameState.set_flag("ch1_started")


## 第一章开场（路线图 4.3；STORY.md 4.4、4.5 第 1 步）：谁在场、面朝维克托、三种结局各自的对话与结果（引荐信、撒谎检定、让埃德里克闭嘴）、
## 中途关掉对话不会重复扣声望、主线「黑鹭之争」、教学提示、序章 NPC 清晨换了说法、代码里写死的夜里台词
func test_ch1open() -> void:
	wipe_test_saves()
	check(Chapters.LIST[1].spawn == "ch1_dawn" and Areas.spawn("frostford", "ch1_dawn") != null and GameState.quest_data().quests.has("ch1_main") and not GameState.item("intro_letter").is_empty(), "第一章从宅邸门口开始（出生点 ch1_dawn），有主线「黑鹭之争」和引荐信")
	# —— 交出 ——
	var main := await ch1_after("deliver", 61)
	var victor: Npc = main._npc_by_dialogue("victor")
	var edric: Npc = main._npc_by_dialogue("edric_ch1")
	var steward: Npc = main._npc_by_dialogue("steward")
	check(victor != null and edric != null and steward != null and steward.position.distance_to(Frostford.STEWARD_CH1) < 0.01, "交出：维克托在门口正中，埃德里克在门边，管家让到一旁")
	check(main.player.interactor.target == victor and main.player.interactor.target.prompt().contains("维克托"), "一进第一章，准星就对着维克托（不用转身）")
	check(main.tip_now == "ch1_victor" and main.hud.hint_label.text == str(GameState.tips_data().ch1_victor.desktop), "教学提示：维克托在门口等你")
	var sign := main.world.get_node_or_null("RoadSignCh1") as Node3D
	check(sign != null and flat(sign.global_position).distance_to(flat(main.player.global_position)) < Travel.DEPART_RADIUS, "路牌就在身后，站在开场的地方按 M 也能出发")
	check(await fl_say(main, "frostford", "edric_ch1", ["过不了几天，你就要在黑鹭堡和塞弗林家定亲了。", "……"]), "交出：埃德里克别过脸去，问一句只回「你满意了？」（定亲的是塞弗林家，序章他自己说的）")
	check(await fl_say(main, "frostford", "steward", [], true) and main.dialogue.runner.node_id == "ch1", "管家：老爷在门口等你（不再说序章的夜里那几句）")
	main.dialogue.close()
	await frames(2)
	var valen0 := GameState.get_rep("valen")
	check(await fl_say(main, "frostford", "victor", ["少爷还好吗？"], true) and main.dialogue.runner.node_id == "deliver_edric" and main.dialogue.runner.text().contains("门边"), "交出：问少爷——维克托朝门边的埃德里克扬了扬下巴（人就在门口，不说「在里头」）")
	main.dialogue.close()
	await frames(2)
	check(not GameState.has_flag("ch1_victor_done") and not GameState.has_item("intro_letter"), "中途关掉：什么都还没定")
	check(await fl_say(main, "frostford", "victor", ["这是我该做的。", "要我做什么？", "借据呢？", "明白。", "（告辞）"]), "交出：和维克托说完（这是我该做的 → 要我做什么 → 借据呢 → 告辞）")
	check(GameState.has_flag("ch1_letter") and GameState.has_flag("ch1_victor_done") and GameState.has_item("intro_letter") and GameState.has_item("debt_note") and GameState.get_rep("valen") == valen0, "交出：拿到引荐信，借据还在身上（维克托要你亲手交给家主）")
	check(GameState.quest_active("ch1_main") and GameState.quest_stage("ch1_main") == "to_reedwharf" and not GameState.has_flag("ch1_debt"), "主线「黑鹭之争」：去芦栈村；借据的下落先不定")
	check(main.tip_now == "travel_map" or main.tip_queue.has("travel_map"), "说完了：教学提示讲身后的路牌和旅行地图")
	check(await fl_say(main, "frostford", "victor", [], true) and main.dialogue.runner.node_id == "after_letter", "再找维克托：只催你上路")
	main.dialogue.close()
	await frames(2)
	check(await fl_say(main, "frostford", "steward", [], true) and main.dialogue.runner.node_id == "ch1_after", "管家：路上小心")
	main.dialogue.close()
	await frames(2)
	var door: Door = null
	for d in main.world.find_children("*", "Door", true, false):
		if (d as Door).display_name == "领主宅邸的大门":
			door = d
	check(door != null and door.locked_text == Frostford.MANOR_DOOR_CH1, "宅邸的大门：第一章换了说法（不再是「门缝里透出一点灯光」）")
	await free_main(main)
	# —— 放走：撒谎成功 ——
	var sd := seed_for("victor_lie_speech", "speech", 14, true)
	main = await ch1_after("release", sd)
	check(main._npc_by_dialogue("victor") != null and main._npc_by_dialogue("edric_ch1") == null, "放走：埃德里克坐船南下了，门口没有他")
	check(await fl_say(main, "frostford", "victor", ["我追到渡口的时候，船已经开了。他是自己走的。", "老爷节哀。", "要我做什么？", "我这就动身。", "（告辞）"]), "放走：向维克托撒谎（口才检定）")
	check(GameState.get_flag("victor_lie") == "lied_ok" and GameState.get_flag("ch1_debt") == "with_edric" and GameState.has_item("intro_letter") and GameState.get_rep("valen") == 10, "撒谎成功：他以为儿子是自己跑的，照样写引荐信；借据跟埃德里克走了")
	await free_main(main)
	main = await ch1_after("release", sd)
	check(await fl_say(main, "frostford", "victor", ["我追到渡口的时候，船已经开了。他是自己走的。"]) and GameState.get_flag("victor_lie") == "lied_ok" and not GameState.has_flag("ch1_victor_done"), "撒谎成功后马上关掉对话")
	check(await fl_say(main, "frostford", "victor", [], true) and main.dialogue.runner.node_id == "news", "再找维克托：接着说黑鹭堡的事，不会再问一遍少爷去哪了（也不会再给说实话的机会）")
	main.dialogue.close()
	await frames(2)
	await free_main(main)
	# —— 放走：被识破（中途关掉对话再打开，声望只扣一次）——
	sd = seed_for("victor_lie_speech", "speech", 14, false)
	main = await ch1_after("release", sd)
	check(await fl_say(main, "frostford", "victor", ["我追到渡口的时候，船已经开了。他是自己走的。"]), "放走：撒谎，没说圆，中途关掉对话")
	var v1 := GameState.get_rep("valen")
	check(GameState.get_flag("victor_lie") == "lied_caught" and v1 == -5 and not GameState.has_flag("ch1_letter") and GameState.has_flag("ch1_victor_done") and GameState.quest_active("ch1_main"), "被识破：瓦伦家声望 -15（10 → -5），没有引荐信；主线照样开始")
	check(await fl_say(main, "frostford", "victor", [], true) and main.dialogue.runner.node_id == "after_cold" and GameState.get_rep("valen") == v1, "再找维克托：他转过身去不理你，声望没有再扣")
	main.dialogue.close()
	await frames(2)
	await free_main(main)
	# —— 放走：说实话 ——
	main = await ch1_after("release", 7)
	check(await fl_say(main, "frostford", "victor", ["我放他走了。他不想被拿去换粮食和名分。", "他是你儿子，不是一张借据。", "（转身离开）"]), "放走：说实话")
	check(GameState.get_flag("victor_lie") == "told_truth" and GameState.get_rep("valen") == 0 and not GameState.has_item("intro_letter") and GameState.has_flag("ch1_victor_done"), "说实话：瓦伦家声望 -10，没有引荐信，被赶出门")
	await free_main(main)
	# —— 勒索：先找了维克托——可以先去跟埃德里克说句话 ——
	main = await ch1_after("extort", 8)
	check(await fl_say(main, "frostford", "victor", ["（瞥了一眼门边的埃德里克）老爷稍等，我先跟少爷说句话。"]) and not GameState.has_flag("edric_quiet") and not GameState.has_flag("ch1_victor_done") and GameState.get_rep("valen") == 10, "勒索：先找维克托时可以先走开（什么都没定、声望不变），去找埃德里克")
	await free_main(main)
	# —— 勒索：随他去，埃德里克当着维克托说出来 ——
	main = await ch1_after("extort", 8)
	edric = main._npc_by_dialogue("edric_ch1")
	check(edric != null and await fl_say(main, "frostford", "edric_ch1", ["随你。"]), "勒索：埃德里克在门边盯着你；随他去")
	check(await fl_say(main, "frostford", "victor", ["少爷平安就好。", "……", "（转身离开）"]), "和维克托说话：埃德里克插嘴")
	check(GameState.get_flag("edric_quiet") == "told" and GameState.get_rep("valen") == -20 and GameState.get_rep("caswell") == -30 and not GameState.has_flag("ch1_letter") and GameState.has_item("debt_note"), "他说出去了：瓦伦家声望大降（10 → -20），没有引荐信；借据还在你手里")
	check(await fl_say(main, "frostford", "edric_ch1", [], true) and main.dialogue.runner.node_id == "told_after", "埃德里克：现在大家都知道了")
	main.dialogue.close()
	await frames(2)
	await free_main(main)
	# —— 勒索：口才说服他闭嘴 ——
	sd = seed_for("edric_quiet_speech", "speech", 13, true)
	main = await ch1_after("extort", sd)
	check(await fl_say(main, "frostford", "edric_ch1", ["偷借据的是你。要说，我们一起说。", "一言为定。"]) and GameState.get_flag("edric_quiet") == "kept", "勒索：口才说服埃德里克闭嘴（偷借据的是他自己）")
	check(await fl_say(main, "frostford", "victor", ["少爷平安就好。", "要我做什么？", "我这就动身。", "（告辞）"]) and GameState.has_item("intro_letter") and GameState.get_rep("valen") == 10, "他没说出去：维克托什么也不知道，照样写引荐信")
	await free_main(main)
	# —— 勒索：口才没说动，只剩给钱；钱不够时灰着 ——
	sd = seed_for("edric_quiet_speech", "speech", 13, false)
	main = await ch1_after("extort", sd)
	check(await fl_say(main, "frostford", "edric_ch1", ["偷借据的是你。要说，我们一起说。", "……"]) and GameState.has_flag("edric_quiet_refused") and not GameState.has_flag("edric_quiet"), "口才没说动：他不答应（不能再试）")
	GameState.silver = 30
	check(await fl_say(main, "frostford", "edric_ch1", [], true) and main.dialogue.runner.node_id == "refused_again" and main.dialogue.locked_buttons.size() == 1 and (main.dialogue.locked_buttons[0] as Button).text.contains("40"), "再找他：只剩给钱，身上不够 40 枚时灰着写「需要」")
	main.dialogue.close()
	await frames(2)
	GameState.silver = 132
	check(await fl_say(main, "frostford", "edric_ch1", ["（塞给他 40 枚银币）拿着，就当什么都没发生。", "很好。"]) and GameState.get_flag("edric_quiet") == "kept" and GameState.silver == 92, "给他 40 枚银币：他什么都没看见")
	await free_main(main)
	# —— 序章没喂老霍布（支线还开着）：清晨也能把面包给他，支线能做完 ——
	main = await ch1_after("deliver", 62)
	GameState.start_quest("hob_debt")
	check(await fl_say(main, "frostford", "hob", [], true) and main.dialogue.runner.node_id == "dawn_hungry" and main.dialogue.locked_buttons.size() == 1, "老霍布的支线还开着：清晨他醒过来要吃的；身上没面包时「给他面包」灰着")
	main.dialogue.close()
	await frames(2)
	GameState.add_item("bread")
	check(await fl_say(main, "frostford", "hob", ["（把面包递给他）给你。", "保重。"]) and GameState.quest_done("hob_debt") and not GameState.has_item("bread") and not GameState.clues.has("dice"), "给他面包：支线做完（不再给序章那条已经用不上的线索）")
	await free_main(main)
	# —— 玛蒂尔达的清晨：买面包以后就结束，不回序章的菜单 ——
	GameState.new_game(63)
	GameState.set_flag("ch1_started")
	GameState.set_flag("matilda_told_edric")
	var rm := DialogueRunner.new()
	rm.start("tavern", "matilda")
	var bi := -1
	for i in rm.options().size():
		if str(rm.options()[i].text).begins_with("来块面包"):
			bi = i
	rm.choose(bi)
	var silver_left := GameState.silver
	check(rm.node_id == "bread_dawn" and GameState.has_item("bread") and not rm.choose(0), "玛蒂尔达的清晨：买了面包「多谢」就结束（不会掉进序章的「还要什么？」菜单、再说一遍少爷的事；还剩 %d 枚）" % silver_left)
	# —— 序章结束画面点了「在雾里再走走」：去小教堂找修士还能进第一章 ——
	GameState.new_game(64)
	GameState.set_flag("prologue_edric", "deliver")
	GameState.set_flag("prologue_done")
	main = await make_main(false)
	main.show_ending("prologue", "deliver")
	await frames(3)
	check(main.ending_panel.continue_btn.visible, "第一章开放了：序章结束画面有「继续：第一章」")
	main.ending_panel.back_btn.pressed.emit()
	await frames(2)
	check(main.hud.toast_label.text.contains("星铁小教堂找奥尔本修士"), "点「在雾里再走走」：提示之后去小教堂找修士还能进第一章")
	await free_main(main)
	main = await make_area("chapel")
	check(await fl_say(main, "chapel", "alban", ["我准备好了，这就去黑鹭堡。"]), "小教堂：对修士说「我准备好了，这就去黑鹭堡」")
	await frames(3)
	check(main.ending_panel.visible and main.ending_panel.continue_btn.visible, "又打开结束画面，「继续：第一章」就在上面")
	main.ending_panel.close()
	await frames(2)
	GameState.set_flag("ch1_started")
	check(await fl_say(main, "chapel", "alban", [], true) and main.dialogue.buttons.size() == 1, "进了第一章以后：修士那里不再有这个选项")
	main.dialogue.close()
	await frames(2)
	await free_main(main)
	# —— 序章的人到了清晨：换了说法，不再重开序章的事 ——
	GameState.new_game(9)
	var r := DialogueRunner.new()
	var night := {}
	for pair in [["frostford", "watchman"], ["frostford", "hob"], ["tavern", "matilda"], ["tavern", "dagu"], ["tavern", "woodcutter"], ["churchyard", "gravedigger"]]:
		r.start(pair[0], pair[1])
		night[pair[1]] = r.node_id
	GameState.new_game(9)                          # 上面进了序章的开场节点（老霍布的开场会接支线）：清掉再进第一章
	GameState.set_flag("prologue_done")
	GameState.set_flag("prologue_edric", "deliver")
	GameState.set_flag("ch1_started")
	var dawn := {}
	for pair in [["frostford", "watchman"], ["frostford", "hob"], ["frostford", "steward"], ["tavern", "matilda"], ["tavern", "dagu"], ["tavern", "woodcutter"], ["churchyard", "gravedigger"], ["chapel", "alban"]]:
		r.start(pair[0], pair[1])
		dawn[pair[1]] = r.node_id
	check(night.watchman == "greet" and night.hob == "greet" and night.matilda == "greet" and night.gravedigger == "greet", "序章里照旧（更夫、老霍布、玛蒂尔达、守墓人都从原来的开场白说起）")
	check(dawn.watchman == "dawn" and dawn.hob == "dawn" and dawn.steward == "ch1" and dawn.matilda == "dawn" and dawn.dagu == "dawn" and dawn.woodcutter == "asleep" and dawn.gravedigger == "dawn" and dawn.alban == "after_book", "第一章的清晨：更夫换班、老霍布睡着、管家指路、玛蒂尔达生炉子、大桶和伐木工睡着、守墓人扫雪、修士照旧（%s）" % str(dawn))
	r.start("frostford", "watchman")
	var opts: Array = r.options().map(func(o): return str(o.text))
	check(opts.size() == 1 and r.options()[0].get("end", false), "更夫的清晨只有一句告别，不会再从头打听少爷（%s）" % ", ".join(opts))
	r.start("frostford", "hob")
	check(r.node_id == "dawn" and r.options().size() == 1 and not GameState.quests.has("hob_debt"), "老霍布睡着了：不会在第一章重开序章的支线")
	# —— 代码里写死的夜里台词 ——
	GameState.new_game(10)
	GameState.chapter = 1
	GameState.daypart = "dawn"
	GameState.set_flag("ch1_started")
	main = await make_area("tavern")
	var peddler: Npc = null
	for n in main.world.find_children("*", "Npc", true, false):
		if (n as Npc).display_name == "货郎":
			peddler = n
	var gate_ok := false
	for d in main.world.find_children("*", "Door", true, false):
		gate_ok = gate_ok or (d as Door).locked_text.contains("楼上的客人还没起")
	check(peddler != null and peddler.lines == Tavern.PEDDLER_LINES_CH1 and gate_ok, "酒馆：货郎和楼梯栅门换成清晨的说法")
	await free_main(main)
	main = await make_area("ferry")
	var fm: Npc = null
	for n in main.world.find_children("*", "Npc", true, false):
		if (n as Npc).display_name == "渡工":
			fm = n
	check(fm != null and fm.lines == Ferry.FERRYMAN_LINES_CH1, "渡口：渡工换成清晨的说法（雾散了、船照常开）")
	await free_main(main)
	main = await make_area("birch")
	check(main.hud.hint_label.text != Birch.TEACH_DESKTOP, "桦林：第一章不再弹「前面有火光，是无旗者的哨卡」")
	await free_main(main)
	GameState.new_game()


## 区域边缘（路线图 3.10；所有者 2026-10-09 定「A + B」的 A）：四个户外区域走得到的范围外面有地、有林子，出口的路伸出去、不种树，
## 边界外的树没有碰撞（多出来的只是画面），新做的路口有门柱、地名、栅栏、灯笼，灯笼白天灭；搭场景不变慢
func test_edges() -> void:
	var spec := {                                       # 区域矩形（走得到的范围）、几个出口
		"frostford": [Rect2(-15.5, -59.0, 31.0, 70.5), 1],
		"churchyard": [Rect2(-13.0, -19.0, 26.0, 30.0), 1],
		"birch": [Rect2(-18.0, -36.0, 36.0, 72.0), 2],
		"ferry": [Rect2(-16.0, -30.0, 32.0, 30.0), 1],
	}
	for a in spec:
		GameState.new_game(70)
		var t0 := Time.get_ticks_msec()
		var main := await make_area(a)
		var ms := Time.get_ticks_msec() - t0
		var edge := main.world.get_node_or_null("Edges") as MeshInstance3D
		var trees := int(edge.get_meta("trees", 0)) if edge else 0
		var aabb := edge.get_aabb() if edge else AABB()
		var rect: Rect2 = spec[a][0]
		var tris := 0
		var mms: Array = main.world.find_children("EdgeTrees*", "MultiMeshInstance3D", true, false)
		var models := {}
		var widest := 0.0                                  # 一块里的树最远隔多远（米）：块够小，引擎才能按视野、影子范围整块裁掉
		for n in mms:
			var mm := (n as MultiMeshInstance3D).multimesh
			models[mm.mesh] = true
			for si in mm.mesh.get_surface_count():
				tris += mm.mesh.surface_get_array_len(si) / 3 * mm.instance_count
			var lo := Vector2(INF, INF)
			var hi := Vector2(-INF, -INF)
			for o: Vector3 in n.get_meta("spots", PackedVector3Array()):    # 无界面时读不回多实例的变换，用 Edges 另记的位置
				lo = lo.min(Vector2(o.x, o.z))
				hi = hi.max(Vector2(o.x, o.z))
			widest = maxf(widest, maxf(hi.x - lo.x, hi.y - lo.y) / (2.0 if bool(n.get_meta("far", false)) else 1.0))
		var holder := Node3D.new()
		add_child(holder)
		var t1 := Time.get_ticks_usec()
		Edges.dress(holder, rect, [], [], 1)
		var dress_ms := (Time.get_ticks_usec() - t1) / 1000.0
		holder.free()
		check(edge != null and trees >= 150 and models.size() == 3 and aabb.position.x < rect.position.x - 40.0 and aabb.end.x > rect.end.x + 40.0 and tris < 120000 and dress_ms < 60.0, "%s：边界外两圈白桦（%d 棵、%d 个三角面，三种树的模型多实例），地面一直铺到 40 米外（收边 %.1f 毫秒，搭整个区域 %d 毫秒）" % [Areas.display_name(a), trees, tris, dress_ms, ms])
		check(mms.size() >= 4 and widest <= Edges.CHUNK, "%s：树按块分成 %d 个多实例节点（一块最宽 %.1f 米，不超过 %d 米；远圈的块大一倍），看不见的块整块不画" % [Areas.display_name(a), mms.size(), widest, int(Edges.CHUNK)])
		# 每个出口都是真的门（通往别的区域的门就在出口那里），不是在墙上凭空开一条路（审查：霜渡镇第一版在房子后面伸出一条走不到的路）
		var exits: Array = edge.get_meta("exits", []) if edge else []
		var doors: Array = main.world.find_children("*", "Door", true, false).filter(func(d): return (d as Door).to_area != "")
		var real_exits: bool = exits.size() == int(spec[a][1]) and exits.all(func(e): return doors.any(func(d): return Vector2(d.global_position.x - e.at.x, d.global_position.z - e.at.z).length() < 1.5))
		check(real_exits, "%s：%d 个出口，每个都站着一扇通往别处的门" % [Areas.display_name(a), exits.size()])
		# 出口外的路上没有树：查每棵树的位置——从出口那条线（往里 1 米）到路的尽头，离路中线「路宽一半 + 1 米」以内不能有
		var clear := true
		var placed := 0
		for n in mms:
			var spots: PackedVector3Array = n.get_meta("spots", PackedVector3Array())
			placed += spots.size()
			for o in spots:
				for e in exits:
					var out: Vector3 = e.out
					var d: Vector3 = o - e.at
					var along := d.dot(out)
					if along > -1.0 and along < Edges.ROAD_LEN and (d - out * along).length() < float(e.half) + 1.0:
						clear = false
		check(clear and placed == trees, "%s：出口外的路中间、路边一米都没有树（路伸进林子里；查了 %d 棵树的位置）" % [Areas.display_name(a), placed])
		# 栅栏、门柱有碰撞（审查：渡口北头的栅栏在看不见的墙里面 0.6 米，没碰撞时人能穿过去站到栅栏外）
		var fenced := exits.filter(func(e): return bool(e.get("fence", false)))
		var solids := main.world.get_node_or_null("EdgeSolids") as StaticBody3D
		var boxes := solids.get_child_count() if solids else 0
		var want := fenced.size() * 2 + exits.filter(func(e): return str(e.get("frame", "")) != "").size() * 2
		check(boxes == want, "%s：出口两边的栅栏、新做的门柱有碰撞（%d 个碰撞盒）" % [Areas.display_name(a), boxes])
		if a == "ferry":
			# 审查里人站得到的地方：北头栅栏和看不见的墙之间（x 4、z -29.65）——现在一个人的身子放在那里会撞上栅栏
			for i in 2:
				await get_tree().physics_frame
			var q := PhysicsShapeQueryParameters3D.new()
			var cap := CapsuleShape3D.new()
			cap.radius = 0.35
			cap.height = 1.8
			q.shape = cap
			q.transform = Transform3D(Basis.IDENTITY, Vector3(4.0, 0.95, Ferry.NORTH + 0.35))
			var hits: Array = main.get_world_3d().direct_space_state.intersect_shape(q)
			check(hits.any(func(h): return h.collider == solids), "渡口：北头栅栏挡人（栅栏和墙之间站不进去）")
		# 边界外的树没有碰撞：从区域里看，走不出去的围墙照旧，没多出一堆树的碰撞体
		var bodies: Array = main.world.find_children("*", "StaticBody3D", true, false).filter(func(b): return b.name != "EdgeSolids" and not rect.grow(0.6).has_point(Vector2(b.global_position.x, b.global_position.z)) and (a != "ferry" or b.global_position.z < Ferry.SHORE_Z - 0.6))     # 渡口的码头本来就伸进河里
		check(bodies.size() <= 2, "%s：边界外的树不加碰撞（边界外的碰撞体 %d 个）" % [Areas.display_name(a), bodies.size()])
		await free_main(main)
	# 画多少树：夜里、黄昏雾近，远圈不画；清晨、白天画；低画质近圈只画六成、远圈不画
	GameState.new_game(73)
	var m3 := await make_area("birch")
	m3.apply_quality("medium")                          # 前面的测试组可能把画质设置留在低档（单独跑 perf edges 时出过）
	await m3.set_daypart("night", false)
	var fars: Array = m3.world.find_children("EdgeTreesFar_*", "MultiMeshInstance3D", true, false)
	var nears: Array = m3.world.find_children("EdgeTrees_*", "MultiMeshInstance3D", true, false)
	var shown := func(list: Array) -> int: return list.filter(func(n): return (n as Node3D).visible).size()
	var drawn := func() -> Array:                      # 近圈实际画几棵 / 一共几棵
		var d := 0
		var all := 0
		for n in nears:
			var mm := (n as MultiMeshInstance3D).multimesh
			all += mm.instance_count
			d += mm.instance_count if mm.visible_instance_count < 0 else mm.visible_instance_count
		return [d, all]
	var night_far: int = shown.call(fars)
	await m3.set_daypart("day", false)
	var day_far: int = shown.call(fars)
	m3.apply_quality("low")
	var low_far: int = shown.call(fars)
	var low_near: Array = drawn.call()
	m3.apply_quality("medium")
	var med_near: Array = drawn.call()
	Edges.refresh(get_tree(), false, Edges.FAR_SEEN - 1.0)
	var thick_far: int = shown.call(fars)
	m3.apply_quality("medium")
	check(fars.size() > 0 and night_far == fars.size() and day_far == fars.size() and thick_far == 0 and low_far == 0 and absf(float(low_near[0]) / low_near[1] - Edges.LOW_SHARE) < 0.05 and med_near[0] == med_near[1] and shown.call(fars) == fars.size(), "画多少树：夜里、白天远圈都画（站在边界上，远圈头几排夜里也透得出来），雾浓到 %d 米以内才不画；低画质近圈只画六成（%d / %d）、远圈不画" % [int(Edges.FAR_SEEN), low_near[0], low_near[1]])
	await free_main(m3)
	# 渡口北头：原来只有一块门板，现在有门柱、地名牌「桦林」、栅栏、灯笼；白天灯笼灭
	GameState.new_game(71)
	var m2 := await make_area("ferry")
	var label_ok: bool = m2.world.find_children("*", "Label3D", true, false).any(func(l): return (l as Label3D).text == "桦林" and absf(l.global_position.z - (Ferry.NORTH + 0.6)) < 0.3)
	var lanterns: Array = m2.world.find_children("GateLantern", "Node3D", true, false)
	check(label_ok and lanterns.size() == 1 and (lanterns[0] as Node3D).visible, "渡口北头的路口：门柱上写着「桦林」，挂着一盏夜里亮的灯笼")
	await m2.set_daypart("day", false)
	check(not (lanterns[0] as Node3D).visible, "白天：路口的灯笼灭了")
	await free_main(m2)
	GameState.new_game(72)
	m2 = await make_main(false)
	check(m2.world.find_children("GateLantern", "Node3D", true, false).size() == 1 and m2.find_children("*", "OmniLight3D", true, false).size() <= 4, "霜渡镇南门也挂了灯笼（假光，不多占实时光源：仍不超过 4 盏）")
	await free_main(m2)
	GameState.new_game()


## 地图册（路线图 3.11；core/area_map.gd、ui/map_panel.gd、ui/map_tabs.gd）：数据检查、和场景对照、剧透、按 M、切页、关上、各种窗口尺寸、大地图缩放、右上角按钮
func test_areamap() -> void:
	AreaMap.override_regions(null)
	var errs := AreaMap.validate()
	check(errs.is_empty(), "地图数据通过检查（%s）" % "; ".join(errs))
	var story := ["frostford", "tavern", "churchyard", "chapel", "birch", "ferry"]
	check(story.all(func(a): return AreaMap.region_of(a) == "frostford") and AreaMap.region_of("test_range") == "" and not AreaMap.has_map("test_range") and not AreaMap.has_map("battle"), "六个剧情区域都在「霜渡镇一带」；测试场、军阵试验场没有地图")
	var links: Array = AreaMap.links("frostford").map(func(p): return "%s-%s" % p)
	links.sort()
	check(links == ["birch-ferry", "birch-frostford", "chapel-churchyard", "churchyard-frostford", "frostford-tavern"], "一带的连线从各处的出口推出来，正好 5 条（%s）" % ", ".join(links))
	check(AreaMap.views("frostford", 0) == ["local", "region"] and AreaMap.views("frostford", 1) == ["local", "region", "travel"] and AreaMap.views("test_range", 0) == ["local"], "地图册的页：序章本地、一带；第一章多「北境西部」；测试场只有本地")
	check(AreaMap.default_view("frostford") == "local" and AreaMap.default_view("tavern") == "region" and AreaMap.default_view("chapel") == "region", "按 M 先看哪页：室外本地，室内一带")
	check(AreaMap.heading_text(0) == "北" and AreaMap.heading_text(45) == "西北" and AreaMap.heading_text(90) == "西" and AreaMap.heading_text(135) == "西南" and AreaMap.heading_text(180) == "南" and AreaMap.heading_text(-180) == "南" and AreaMap.heading_text(-90) == "东" and AreaMap.heading_text(-45) == "东北" and AreaMap.heading_text(359) == "北", "朝向的名字（0 = 北，向左转 90 = 西）")
	check(AreaMap.bearing_text(Vector2.ZERO, Vector2(0, 34)) == "南边约 34 米" and AreaMap.bearing_text(Vector2.ZERO, Vector2(-20, 0)) == "西边约 20 米" and AreaMap.bearing_text(Vector2.ZERO, Vector2(1, 1)) == "就在你旁边", "方位：「南边约 34 米」，太近说「就在你旁边」")
	# 规格和场景对照：通往别处的门 = 地图上的出口（锁着的门不算）；室外的范围 = Edges 记的范围；每栋房子都画在地图上
	for a in story:
		GameState.new_game(80)
		var main := await make_area(a)
		var ex := AreaMap.exits(a)
		var doors: Array = main.world.find_children("*", "Door", true, false).filter(func(d): return (d as Door).to_area != "")
		var bad := []
		for d: Door in doors:
			var c := d.global_transform * Vector3(d.width * 0.5, 0, 0)
			var hit := ex.filter(func(e): return str(e.to) == d.to_area and str(e.spawn) == d.to_spawn and str(e.name) == d.display_name and Vector2(c.x, c.z).distance_to(e.at) < 1.5)
			if hit.size() != 1:
				bad.append(d.display_name)
		check(doors.size() == ex.size() and bad.is_empty(), "%s：通往别处的门和地图上的出口一一对上（%d 个；对不上：%s）" % [Areas.display_name(a), ex.size(), ", ".join(bad)])
		var edge: Node = main.world.get_node_or_null("Edges")
		if edge:
			var near_all: bool = (edge.get_meta("exits", []) as Array).all(func(ee): return ex.any(func(e): return Vector2(ee.at.x, ee.at.z).distance_to(e.at) < 2.0))
			check(edge.get_meta("area") == AreaMap.bounds(a) and near_all, "%s：地图的范围就是区域边缘（Edges）的范围；边缘的路口都是地图上的出口" % Areas.display_name(a))
		var houses_ok := true
		var polys := AreaMap.shapes(a).filter(func(sh): return str(sh.k) == "house")
		for h in main.get_tree().get_nodes_in_group("house"):
			var sz: Vector2 = h.get_meta("size", Vector2.ZERO)
			var hc := House.local_xz(h.position, h.rotation_degrees.y, Vector2(0, -sz.y * 0.5))
			if not polys.any(func(sh): return Geometry2D.is_point_in_polygon(hc, sh.pts) if sh.has("pts") else (sh.rect as Rect2).has_point(hc)):
				houses_ok = false
		check(houses_ok, "%s：每栋房子都画在地图上" % Areas.display_name(a))
		var nb := Areas.nav_bounds(a)
		if nb.size != Vector3.ZERO:
			var nr := Rect2(nb.position.x, nb.position.z, nb.size.x, nb.size.z)
			check(AreaMap.bounds(a) == nr if a != "ferry" else AreaMap.view_rect(a).grow(0.01).encloses(nr), "%s：地图的范围和导航网格的范围一致（渡口：地图框住了码头）" % Areas.display_name(a))
		await free_main(main)
	check(is_equal_approx(Chapel.DAIS.position.y, -Chapel.D * 0.5) and is_equal_approx(Chapel.DAIS.end.y, Chapel.ALTAR_Z + 0.6) and AreaMap.shapes("chapel").any(func(sh): return sh.get("rect") == Chapel.DAIS), "小教堂的祭坛台：从北墙到祭坛前 0.6 米，搭场景和地图用同一个矩形（原来往北偏了 0.6 米，烛台底座悬空）")
	# 剧透：桦林的哨卡、墓园的钥匙和包袱、渡口的人都不在地图上
	var spoil := ""
	for a in ["birch", "churchyard", "ferry", "marsh"]:
		var words := JSON.stringify(AreaMap.spec(a))
		for w in ["营地", "哨卡", "拒马", "包袱", "钥匙", "埃德里克", "塞拉斯", "奥弗", "无旗者", "营火"]:
			if words.contains(w):
				spoil += "%s:%s " % [a, w]
	var near_fire := AreaMap.shapes("birch").any(func(sh): return sh.has("at") and (sh.at as Vector2).distance_to(Vector2(Birch.FIRE_POS.x, Birch.FIRE_POS.z)) < 6.0)
	check(spoil == "" and not near_fire, "地图不剧透：桦林的哨卡、墓园的钥匙和包袱、渡口的人都不画（%s）" % spoil)
	# 条件：第一章才画路牌
	GameState.new_game(81)
	check(not AreaMap.shapes("frostford").any(func(sh): return str(sh.get("icon", "")) == "sign"), "序章：地图上没有路牌")
	# 序章按 M：打开「本地」页
	var before := ""
	var main := await make_main(false)
	var before_d := GameState.to_dict()
	before_d.erase("playtime")
	before = JSON.stringify(before_d)
	var mp: MapPanel = main.map_panel
	main.touch_mode = true
	main.touch.visible = true
	main._unhandled_input(key_ev(KEY_M))
	await frames(3)
	check(mp.visible and get_tree().paused and not main.hud.visible and not main.touch.visible and not main.travel_map.visible and mp.view == "local", "序章按 M：打开地图册的「本地」页；游戏暂停，提示和触屏按钮藏起来")
	check(mp.tabs.visible and mp.tabs.btns.local.visible and mp.tabs.btns.region.visible and not mp.tabs.btns.travel.visible and mp.tabs.btns.local.text == "◆ 本地" and mp.tabs.btns.local.has_focus(), "页签只有「本地」「一带」，当前页写「◆ 本地」，焦点在它上面（键盘能用）")
	check(mp.where_text().begins_with("你在：霜渡镇，面朝") and mp.where_label.text == mp.where_text(), "写着你在哪、面朝哪（%s）" % mp.where_text())
	check(mp.process_mode == Node.PROCESS_MODE_ALWAYS and mp.can_process() and mp.tabs.can_process(), "游戏暂停时地图照样收按键、渐显照样走（不然暂停了就关不掉）")
	var names: Array = mp.exit_btns.map(func(b): return (b as Button).text)
	check(names == ["1 → 镇外桦林", "2 → 星铁小教堂墓园", "3 → 「倒钩鱼」酒馆"], "三个出口按编号列出来（%s）" % ", ".join(names))
	var pc := mp.canvas.world_to_canvas(Vector2(main.player.global_position.x, main.player.global_position.z))
	check(Rect2(Vector2.ZERO, mp.canvas.size).has_point(pc) and not mp.canvas.zoomable and not mp.zoom_row.visible and mp.canvas.px_per_m >= MapPanel.MIN_PX_PER_M, "「你」在图上；霜渡镇整张放得下（每米 %.1f 像素），不出缩放按钮" % mp.canvas.px_per_m)
	(mp.exit_btns[0] as Button).pressed.emit()
	await frames(1)
	check(mp.selected_exit == 0 and mp.detail_label.text.begins_with("南门（往桦林、渡口）：通往镇外桦林。在你南边约"), "选出口 1：写它通往哪里、在你哪边多远（%s）" % mp.detail_label.text)
	check(mp.legend.text.contains("▲ 出口") and mp.legend.text.contains("■ 房屋") and not mp.legend.text.contains("≈ 水"), "图例只列这张图里有的（%s）" % mp.legend.text)
	# 一带页
	mp.tabs.btns.region.pressed.emit()
	await frames(3)
	var nodes: Array = mp.node_btns.values()
	var overlap := false
	var cr := mp.canvas.get_global_rect()
	var inside := true
	for i in nodes.size():
		inside = inside and cr.grow(0.5).encloses((nodes[i] as Button).get_global_rect())
		for j in range(i + 1, nodes.size()):
			if (nodes[i] as Button).get_global_rect().intersects((nodes[j] as Button).get_global_rect()):
				overlap = true
	check(mp.view == "region" and nodes.size() == 6 and (mp.node_btns.frostford as Button).text == "霜渡镇\n（你在这里）" and (mp.node_btns.tavern as Button).text == "「倒钩鱼」酒馆\n（室内）" and inside and not overlap and get_tree().paused, "切到「一带」：6 处都在图里、不重叠，你在的地方写「你在这里」，室内写「室内」")
	check(mp.detail_label.text.begins_with("霜渡镇：") and mp.detail_label.text.contains("南门（往桦林、渡口） → 镇外桦林") and mp.tabs.btns.region.text == "◆ 一带", "默认选中你在的地方：它的出口都通往哪里")
	mp.select_node("birch")
	check(mp.detail_label.text == "镇外桦林：回霜渡镇的木门 → 霜渡镇；去渡口的路 → 渡口", "选桦林：两头的门通往哪里")
	main.hud.set_hint("测试用的教学提示")
	mp._unhandled_input(key_ev(KEY_ESCAPE))
	await frames(2)
	check(not mp.visible and not get_tree().paused and main.hud.visible and main.touch.visible and main.hud.hint_label.text == "测试用的教学提示", "Esc 关上：接着玩，触屏按钮回来了，底部的教学提示还在")
	main.hud.set_hint("")
	main.player.rotation.y = deg_to_rad(90.0)              # 向左转 90 度 = 面朝西
	main.open_map()
	await frames(2)
	check(mp.where_text().ends_with("面朝西"), "转向西边再打开：写「面朝西」（%s）" % mp.where_text())
	mp.close()
	main.player.rotation.y = 0.0
	await frames(1)
	main.touch_mode = false
	main.touch.visible = false
	main.hud.map_pressed.emit()
	await frames(2)
	check(mp.visible and mp.view == "local", "右上角「地图」按钮也能打开")
	mp._unhandled_input(key_ev(KEY_M))
	await frames(2)
	check(not mp.visible and not get_tree().paused, "再按 M 关上")
	var after_d := GameState.to_dict()
	after_d.erase("playtime")                    # 游戏时间在两步之间照常走
	check(JSON.stringify(after_d) == before, "看地图不改存档里的任何东西（游戏时间除外）")
	# 不该打开的时候：暂停菜单开着、正在出发
	main.open_pause()
	await frames(1)
	main.open_map()
	await frames(1)
	check(not mp.visible, "暂停菜单开着：不打开地图")
	main.close_pause()
	await frames(1)
	main.leaving = true
	main.open_map()
	await frames(1)
	check(not mp.visible and not get_tree().paused, "已经出发、正在淡出：不打开地图")
	main.leaving = false
	# 减少动态效果：不渐显
	var rm := Settings.reduced_motion
	Settings.reduced_motion = true
	main.open_map()
	await frames(1)
	check(mp.visible and is_equal_approx(mp.box.modulate.a, 1.0), "减少动态效果：地图直接显示，不渐显")
	mp.close()
	Settings.reduced_motion = rm
	await frames(1)
	# 右上角五个按钮：从右往左 菜单、地图、任务、背包、角色；都不小于 44 × 44，在触屏层放行的顶部 56 像素以内
	var hud: Hud = main.hud
	hud.size = Vector2(480, 900)
	hud._layout()
	var row: Array = [hud.menu_btn, hud.map_btn, hud.quest_btn, hud.bag_btn, hud.char_btn]
	var ordered := true
	for i in row.size() - 1:
		ordered = ordered and (row[i] as Button).position.x > (row[i + 1] as Button).position.x
	var big: bool = row.all(func(b): return (b as Button).size.x >= 44.0 and (b as Button).size.y >= 44.0 and (b as Button).position.y + (b as Button).size.y <= TouchControls.TOP_BAND)
	check(ordered and big and hud.title_label.get_minimum_size().x + 16.0 < hud.char_btn.position.x, "手机竖屏（480 宽）：右上角五个按钮不小于 44 × 44、不出顶部 56 像素，标题不和它们重叠")
	hud.size = Vector2(1280, 720)
	hud._layout()
	check(hud.title_label.text == Hud.TITLE and hud.title_label.get_theme_font_size("font_size") == Hud.TITLE_FS, "宽屏：完整标题、18 号字")
	await free_main(main)
	# 室内：先看「一带」
	GameState.new_game(82)
	main = await make_area("tavern")
	main.open_map()
	await frames(3)
	check(main.map_panel.visible and main.map_panel.view == "region" and (main.map_panel.node_btns.tavern as Button).text == "「倒钩鱼」酒馆\n（你在这里）", "酒馆里按 M：先看「一带」，酒馆写「你在这里」")
	main.map_panel.tabs.btns.local.pressed.emit()
	await frames(2)
	main.map_panel.player_xz = Vector2(0.0, -1.0)
	main.map_panel.select_exit(0)
	check(main.map_panel.where_text() == "你在：「倒钩鱼」酒馆" and main.map_panel.detail_label.text == "回到主街：通往霜渡镇。离你约 5 米。" and not AreaMap.has_compass("tavern"), "酒馆的「本地」页不说东南西北（屋里的图和镇上的方向对不上）：只说离你多远（%s）" % main.map_panel.detail_label.text)
	main.map_panel.close()
	await free_main(main)
	# 测试场：没有地图
	GameState.new_game(83)
	main = await make_main(true)
	main.open_map()
	await frames(3)
	check(main.map_panel.visible and main.map_panel.where_label.text == MapPanel.NO_MAP and not main.map_panel.tabs.visible, "测试场：写「这里没有地图。」，没有别的页")
	main.map_panel.close()
	await free_main(main)
	# 第一章：路牌旁打开旅行地图；切到本地再切回来照样能出发；关上只还原一次
	GameState.new_game(84)
	main = await make_ch1("dawn")
	main.touch_mode = true
	main.touch.visible = true
	check(AreaMap.shapes("frostford").any(func(sh): return str(sh.get("icon", "")) == "sign" and (sh.at as Vector2).distance_to(Vector2(main.world.get_node("RoadSignCh1").global_position.x, main.world.get_node("RoadSignCh1").global_position.z)) < 0.5), "第一章：地图上画了路牌，就在路牌那里")
	main.open_map()
	await frames(4)
	var tm: TravelMap = main.travel_map
	check(tm.visible and tm.at_departure and tm.tabs.visible and tm.tabs.btns.travel.text == "◆ 北境西部" and tm.tabs.btns.local.visible and tm.tabs.btns.region.visible, "第一章站在路牌旁按 M：旅行地图（能出发），顶上三个页签")
	tm.tabs.btns.local.pressed.emit()
	await frames(3)
	check(main.map_panel.visible and not tm.visible and get_tree().paused and not main.hud.visible and main.map_panel.view == "local" and main.map_panel.tabs.btns.travel.visible, "切到「本地」：换成地图册，仍然暂停，提示仍藏着")
	main.map_panel.tabs.btns.travel.pressed.emit()
	await frames(3)
	check(tm.visible and not main.map_panel.visible and tm.at_departure, "再切回「北境西部」：照样能出发")
	tm._unhandled_input(key_ev(KEY_ESCAPE))
	await frames(2)
	check(not tm.visible and not main.map_panel.visible and not get_tree().paused and main.hud.visible and main.touch.visible, "Esc 关上：接着玩，切过页也只还原一次，触屏按钮回来了")
	await free_main(main)
	# 各种窗口尺寸：六个区域整张放得下、按钮够大、都在画面里；一带的节点不重叠
	for sz in [Vector2i(360, 740), Vector2i(740, 360), Vector2i(768, 1024), Vector2i(1280, 720)]:
		get_tree().root.size = sz
		await frames(3)
		GameState.new_game(85)
		main = await make_main(false)
		mp = main.map_panel
		var view_r := Rect2(Vector2.ZERO, UiKit.logical_size(mp))
		var lines := []
		var ok := true
		for a in story:
			var sp: Transform3D = Areas.spawn(a, Areas.spawns(a).keys()[0])
			mp.open(a, "local", AreaMap.views(a, 0), Vector2(sp.origin.x, sp.origin.z), 0.0, true)
			await frames(3)
			var cs := mp.canvas.get_global_rect().size
			var a_ok: bool = view_r.grow(0.5).encloses(mp.box.get_global_rect()) and mp.canvas.px_per_m >= MapPanel.MIN_PX_PER_M and not mp.zoom_row.visible \
				and cs.x >= 200.0 and cs.y >= 200.0 and mp.close_btn.get_global_rect().size.y >= 44.0 and mp.tabs.btns.local.get_global_rect().size.y >= 44.0 \
				and mp.exit_btns.all(func(b): return (b as Button).get_global_rect().size.y >= 44.0) and mp.wide == (sz.x > sz.y)
			var skipped: Array = mp.canvas.place_labels().skipped
			if a == "frostford" and not skipped.is_empty():
				a_ok = false
			if not a_ok:
				ok = false
				lines.append("%s %.1f 像素/米 跳过%s" % [a, mp.canvas.px_per_m, skipped])
			mp.show_view("region", false)
			await frames(3)
			var nb: Array = mp.node_btns.values()
			var crr := mp.canvas.get_global_rect().grow(0.5)
			for i in nb.size():
				if not crr.encloses((nb[i] as Button).get_global_rect()):
					ok = false
					lines.append("%s 一带：%s 出了画布" % [a, (nb[i] as Button).text])
				for j in range(i + 1, nb.size()):
					if (nb[i] as Button).get_global_rect().intersects((nb[j] as Button).get_global_rect()):
						ok = false
						lines.append("%s 一带：%s 和 %s 重叠" % [a, (nb[i] as Button).text, (nb[j] as Button).text])
			if not view_r.grow(0.5).encloses(mp.box.get_global_rect()):
				ok = false
				lines.append("%s 一带：面板出了画面" % a)
			mp.close()
			await frames(1)
		check(ok, "%d × %d：六个区域的地图整张放得下、按钮够大、都在画面里，一带的节点不重叠（%s）" % [sz.x, sz.y, "；".join(lines) if not lines.is_empty() else ("横排" if mp.wide else "竖排")])
		await free_main(main)
	get_tree().root.size = Vector2i(1280, 720)
	await frames(3)
	# 4.4 那种大地图（假数据 600 × 400 米，带一个分块）：放不下就从你这里放大看，能缩放、拖动、回到你这里
	GameState.new_game(86)
	AreaMap.override("frostford", {"bounds": Rect2(-300, -200, 600, 400), "shapes": [{"k": "road", "rect": Rect2(-2, -200, 4, 400)}], "exits": [],
		"zones": [{"id": "t", "name": "测试区", "pts": PackedVector2Array([Vector2(-50, -50), Vector2(50, -50), Vector2(50, 50), Vector2(-50, 50)])}]})
	main = await make_main(false)
	mp = main.map_panel
	main.open_map()
	await frames(3)
	var cv := mp.canvas
	var you := cv.world_to_canvas(Vector2(main.player.global_position.x, main.player.global_position.z))
	check(cv.zoomable and mp.zoom_row.visible and cv.focus_mode == Control.FOCUS_ALL and you.distance_to(cv.size * 0.5) < 2.0, "大地图：放不下就从你这里放大看（「你」在画布中间），出缩放按钮，画布能拿到焦点")
	var px0 := cv.px_per_m
	mp.zoom_in_btn.pressed.emit()
	check(cv.px_per_m > px0, "「放大」：每米像素变多（%.1f → %.1f）" % [px0, cv.px_per_m])
	cv.grab_focus()
	for i in 30:
		cv._gui_input(key_ev(KEY_RIGHT))
	var vr := AreaMap.view_rect("frostford")
	check(vr.has_point(cv.center) and cv.center.x > 0.0, "方向键拖动地图，拖到头也不出地图范围")
	# 真的触屏拖动（走 Input.parse_input_event，工程开着「触屏模拟鼠标」）：地图跟着手指走，不多走一倍
	mp.recenter_btn.pressed.emit()
	await frames(1)
	var c0 := cv.center
	var k := get_tree().root.content_scale_factor
	var p0 := cv.get_global_rect().get_center() * k
	Input.parse_input_event(touch_ev(0, p0, true))
	await frames(1)
	for i in 6:
		Input.parse_input_event(drag_ev(0, p0 + Vector2(-10.0 * (i + 1), 0) * k, Vector2(-10.0, 0) * k))
		await frames(1)
	Input.parse_input_event(touch_ev(0, p0 + Vector2(-60.0, 0) * k, false))
	await frames(2)
	var moved_m := cv.center.x - c0.x
	check(absf(moved_m - 60.0 / cv.px_per_m) < 0.6, "触屏拖动：手指往左拖 60 像素，地图正好跟着走 %.1f 米（不是两倍）" % moved_m)
	mp.recenter_btn.pressed.emit()
	you = cv.world_to_canvas(Vector2(main.player.global_position.x, main.player.global_position.z))
	check(you.distance_to(cv.size * 0.5) < 2.0 and mp.where_text().contains(" · 测试区"), "「回到你这里」；你在哪写上分块的名字（%s）" % mp.where_text())
	mp.close()
	AreaMap.override("frostford", null)
	await free_main(main)
	GameState.new_game()


## 鹭沼连片地图（路线图 4.4a；world/marsh.gd、world/marsh_layout.gd、world/chunk_streamer.gd、core/surface.gd）：
## 布局（都在图里、栈道台阶、堤道尺寸）、出生点脚下一载入就有地、深水边都有墙（从村口出发把走得到的地方都走一遍）、碰撞一次建完、
## 分帧搭建（附近的块先搭、全搭完、每件活多快）、按距离显示 / 隐藏、后搭的块补时段和画质、泥潭、掉进水里放回来、地图分块和旅行地图的地点、读档
func test_marsh() -> void:
	var fl := MarshLayout.floors()
	var inside: bool = fl.all(func(f): return MarshLayout.BOUNDS.grow(0.01).encloses(MarshLayout.aabb(f)))
	check(inside and fl.size() >= 20, "布局：%d 块地面都在图里（%s）" % [fl.size(), MarshLayout.BOUNDS])
	var cw_len := MarshLayout.cw(0).distance_to(MarshLayout.cw(MarshLayout.APRON_T.x))
	check(cw_len > 78.0 and cw_len < 84.0 and is_equal_approx(MarshLayout.CW_W, 4.0) and MarshLayout.GAP.y - MarshLayout.GAP.x >= 4.0 and MarshLayout.BRIDGE_W >= 1.5 and MarshLayout.ARCH_GAP >= 2.5,
		"堤道 %.0f 米长、4 米宽；中段断口 %.0f 米、搭的木板 %.1f 米宽；石拱下 %.1f 米宽（STORY：宽约 4 米、长约 80 米）" % [cw_len, MarshLayout.GAP.y - MarshLayout.GAP.x, MarshLayout.BRIDGE_W, MarshLayout.ARCH_GAP])
	var steps_ok: bool = MarshLayout.DECK_Y - MarshLayout.MUD_Y <= 0.25 and MarshLayout.DECK_Y - MarshLayout.BANK_Y <= 0.25 and MarshLayout.WALKS.all(func(w): return float(w[3]) >= 1.5)
	check(steps_ok, "栈道比泥滩高 %.2f 米、比干地高 %.2f 米（掉下去一步就上得来，台阶 0.3 米以内）；每段栈道至少 1.5 米宽" % [MarshLayout.DECK_Y - MarshLayout.MUD_Y, MarshLayout.DECK_Y - MarshLayout.BANK_Y])
	var reach := House.stair_reach(MarshLayout.STILTS)
	var stairs_ok := true
	for h in MarshLayout.HOUSES:
		var foot: Vector2 = House.local_xz(MarshLayout.house_pos(h), float(h[2]), Vector2(float(h[3].get("door_x", 0.0)), reach + 0.15))
		if not fl.any(func(f): return f.k == "deck" and MarshLayout.contains(f, foot)):
			stairs_ok = false
	check(stairs_ok, "%d 栋高脚屋的台阶都落在栈道上" % MarshLayout.HOUSES.size())
	# 村里的零碎（场景美化五）：都站在地上，不压栈道、不压房子和台阶，离村里的人 1 米以上
	var pd := Marsh.props_decor()
	var walk_rects := MarshLayout.WALKS.map(func(w): return Rect2(w[1], Vector2.ZERO).expand(w[2]).grow(float(w[3]) * 0.5))
	var house_rects := []
	for h in MarshLayout.HOUSES:
		for hs in House.solids(MarshLayout.house_pos(h), float(h[2]), MarshLayout.house_spec(h)):
			var ab: AABB = hs[0] * AABB(-(hs[1] as Vector3) * 0.5, hs[1])
			house_rects.append(Rect2(ab.position.x, ab.position.z, ab.size.x, ab.size.z))
	var pgrid := Marsh.make_index(fl, 0.0)
	var bad_props := []
	for so in pd.solids:
		var c3: Vector3 = so[0]
		var sz: Vector3 = so[1]
		var r := Rect2(c3.x - sz.x * 0.5, c3.z - sz.z * 0.5, sz.x, sz.z)
		var on_ground := Marsh.on_floor(fl, pgrid, Vector2(c3.x, c3.z))
		if not on_ground or walk_rects.any(func(w): return w.intersects(r)) or house_rects.any(func(hr): return hr.intersects(r)) \
				or MarshLayout.PEOPLE.any(func(pp): return Vector2(pp[2].x, pp[2].z).distance_to(r.get_center()) < 1.0 + sz.length() * 0.5):
			bad_props.append(Vector2(c3.x, c3.z))
	check(MarshLayout.PROPS.size() >= 20 and pd.solids.size() >= 15 and bad_props.is_empty(),
		"村里 %d 件零碎（%d 个碰撞盒）都在地上，不压栈道、房子和台阶，离村里的人 1 米以上（不合适的：%s）" % [MarshLayout.PROPS.size(), pd.solids.size(), str(bad_props)])
	# 载入：碰撞一次建完，出生点脚下马上有地（还没分帧搭画面的时候）
	GameState.new_game(440)
	var main := await make_area("marsh")
	var st: ChunkStreamer = main.streamer
	var space := main.get_world_3d().direct_space_state
	var ground_at := func(x: float, z: float, top := 3.0) -> Dictionary:
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, top, z), Vector3(x, -3.0, z), 1)
		return space.intersect_ray(q)
	var spawn_ok := true
	for k in MarshLayout.SPAWNS:
		var sp: Vector3 = MarshLayout.SPAWNS[k][0]
		var hit: Dictionary = ground_at.call(sp.x, sp.z, sp.y + 0.6)
		if hit.is_empty() or absf(hit.position.y - sp.y) > 0.05:
			spawn_ok = false
	check(st != null and spawn_ok, "两个出生点（村口、堡门前）脚下一载入就有地（碰撞同步建完）")
	await physics(10)
	var p: FpController = main.player
	check(p.is_on_floor() and p.global_position.distance_to(MarshLayout.SPAWNS.reedwharf[0]) < 0.3, "新开一局：站在芦栈村村口（%s）" % p.global_position)
	var near_id := MarshLayout.cell_id(MarshLayout.cell_of(Vector2(p.global_position.x, p.global_position.z)))
	check(st.chunks[near_id].done and (st.root_of(near_id) as Node3D).visible, "脚下这块（%s）载入时就搭好、显示着" % near_id)
	var waited := 0
	while not st.is_done() and waited < 600:
		await frames(1)
		waited += 1
	check(st.is_done() and st.primed < st.chunks.size() and st.primed >= 1, "载入时同步搭了附近 %d 块，其余的进场以后分帧搭完（%d 件活，最慢一件 %.1f 毫秒、合计 %.0f 毫秒）" % [st.primed, st.stats.jobs, st.stats.max_job_ms, st.stats.total_ms])
	var prop_nodes: Array = main.world.find_children("Props", "MeshInstance3D", true, false)
	var barrel_hit: Dictionary = ground_at.call(106.2, 35.9, 2.0)
	check(prop_nodes.size() >= 4 and not barrel_hit.is_empty() and absf(float(barrel_hit.position.y) - 0.85) < 0.05,
		"零碎分 %d 块搭出来；村口的木桶挡人（从上往下打到桶盖 y = %.2f）" % [prop_nodes.size(), float(barrel_hit.get("position", Vector3.ZERO).y)])
	check(float(st.stats.max_job_ms) < 40.0, "每件活都不长（最慢 %.1f 毫秒；网页上每帧最多做 %d 毫秒）" % [st.stats.max_job_ms, ChunkStreamer.BUDGET_USEC / 1000])
	# 深水边都有墙：从村口出发，按 1 米的格子把走得到的地方都走一遍；每一步走到没有地的格子，中间都要撞上墙（层 5）或别的东西
	var grid := Marsh.make_index(fl, MarshLayout.SHORE + 1.0)
	var start := Vector2i(roundi(MarshLayout.SPAWNS.reedwharf[0].x), roundi(MarshLayout.SPAWNS.reedwharf[0].z))
	var seen := {start: true}
	var todo := [start]
	var leaks := []
	var edges := 0
	while not todo.is_empty() and seen.size() < 40000:
		var c: Vector2i = todo.pop_back()
		var cp := Vector2(c)
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if seen.has(n):
				continue
			var np := Vector2(n)
			if Marsh.on_floor(fl, grid, np):
				seen[n] = true
				todo.append(n)
				continue
			edges += 1
			var hit: Dictionary = ground_at.call(cp.x, cp.y, 1.2)       # 从 1.2 米往下找地面（地面最高是堤道 0.5 米；别打到路口的门柱顶上）
			var y: float = (hit.position.y if not hit.is_empty() else 0.0) + 0.9
			var from := cp - Vector2(d) * 0.45                     # 格子正好在地面边上时，从里面一点打（射线从墙面上起头打不中墙）
			var q := PhysicsRayQueryParameters3D.create(Vector3(from.x, y, from.y), Vector3(np.x, y, np.y), 1 | FpController.LAYER_BOUNDARY)
			if space.intersect_ray(q).is_empty():
				leaks.append(np)
	check(leaks.is_empty() and seen.size() > 3000, "走得到的地方（%d 个 1 米格子）的 %d 条边上都有墙，掉不进深水（漏的：%s）" % [seen.size(), edges, str(leaks.slice(0, 6))])
	var gate := Vector2i(roundi(MarshLayout.SPAWNS.castle_gate[0].x), roundi(MarshLayout.SPAWNS.castle_gate[0].z))
	check(seen.has(gate) or seen.has(gate + Vector2i(1, 0)), "从村口沿栈道、堤道走得到堡门前")
	var campc := Vector2i(roundi(MarshLayout.CAMP_FIRE.x) + 3, roundi(MarshLayout.CAMP_FIRE.z) + 4)
	check(seen.has(campc), "从村口沿沼地的小路、泥滩、土墩走得到西边土墩上的营地（4.4c）")
	# 墙在物理层 5：挡人走，不挡视线和镜头（层 1 的射线穿过去）
	var walls := main.world.get_node_or_null("MarshWalls") as StaticBody3D
	check(walls != null and walls.collision_layer == FpController.LAYER_BOUNDARY and p.collision_mask & FpController.LAYER_BOUNDARY != 0 and walls.get_child_count() > 20,
		"看不见的墙 %d 段，在物理层 5「边界」（主角撞得上；视线、镜头、箭的射线只看层 1，穿得过去）" % (walls.get_child_count() if walls else 0))
	# 按距离显示 / 隐藏
	main.apply_quality("medium")
	await main.set_daypart("day", false)
	var village := MarshLayout.cell_id(MarshLayout.cell_of(Vector2(80, 30)))
	var gate_id := MarshLayout.cell_id(MarshLayout.cell_of(MarshLayout.cw(MarshLayout.CASTLE_T)))
	var day_ids: Array = st.visible_ids()
	check(village in day_ids and not gate_id in day_ids, "白天在村口：村子的块显示，黑鹭堡那块在雾外藏着（显示 %s）" % str(day_ids))
	p.global_position = MarshLayout.SPAWNS.castle_gate[0]
	st.update_visibility(true)                       # 一下子传过去（读档、走地图）：按显示的门槛重新定
	var at_gate: Array = st.visible_ids()
	p.global_position += Vector3(2, 0, 2)
	st.update_visibility()
	var nudged: Array = st.visible_ids()
	check(gate_id in at_gate and not village in at_gate and nudged == at_gate, "到了堡门前：黑鹭堡那块显示、村子藏起来；来回走两步不闪（%s）" % str(at_gate))
	await main.set_daypart("night", false)
	var night_ids: Array = st.visible_ids()
	check(night_ids.size() < at_gate.size(), "夜里雾近（%d 米），显示的块更少（%s）" % [int(Daypart.PRESETS.night.fog_end), str(night_ids)])
	var in_chunks := 0                                   # 块里除了门、路牌这类可交互物，不该有碰撞体（碰撞都在 world 下的 Marsh* 里，块隐藏不影响）
	for id in st.chunks:
		var r: Node = st.root_of(id)
		if r:
			in_chunks += r.find_children("*", "CollisionObject3D", true, false).filter(func(b): return not b is Interactable).size()
	var bodies_ok := ["MarshFloor", "MarshMud", "MarshWalls", "MarshSolids"].all(func(n): return main.world.get_node_or_null(n) is StaticBody3D)
	check(in_chunks == 0 and bodies_ok, "碰撞体都不在块里（块只管画面，隐藏时碰撞照旧；块里多出来的碰撞体 %d 个）" % in_chunks)
	# 断口的木板桥、码头两头：看不见的墙不伸到木板上（审查：第一版墙多伸了 0.3 米，2.4 米宽的桥只剩 1.4 米）
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.6
	var pinched := []
	var probes := []
	for t in [MarshLayout.GAP.x - 0.2, MarshLayout.GAP.x + 0.2, MarshLayout.GAP.y - 0.2, MarshLayout.GAP.y + 0.2]:
		for off in [-0.75, 0.75]:
			probes.append(MarshLayout.cw3(t, off, MarshLayout.CAUSE_Y + 0.95))
	for z in [52.2, 57.8]:
		for x in [49.1, 50.9]:
			probes.append(Vector3(x, MarshLayout.DECK_Y + 0.95, z))
	for pr in probes:
		var sq := PhysicsShapeQueryParameters3D.new()
		sq.shape = cap
		sq.transform = Transform3D(Basis.IDENTITY, pr)
		sq.collision_mask = 1 | FpController.LAYER_BOUNDARY
		if not space.intersect_shape(sq).is_empty():
			pinched.append(pr)
	check(pinched.is_empty(), "断口的木板桥两头、码头两头站得下一个人靠边走（%d 处，被墙挤着的：%s）" % [probes.size(), str(pinched)])
	# 石拱是窄口：两边的泥滩被矮石墙截断，绕不过去
	var around := 0
	for side in [-1.0, 1.0]:
		for off in [5.0, 7.0, 9.0]:
			var a3 := MarshLayout.cw3(MarshLayout.ARCH_T - 3.0, side * off, MarshLayout.MUD_Y + 0.9)
			var b3 := MarshLayout.cw3(MarshLayout.ARCH_T + 3.0, side * off, MarshLayout.MUD_Y + 0.9)
			if space.intersect_ray(PhysicsRayQueryParameters3D.create(a3, b3, 1 | FpController.LAYER_BOUNDARY)).is_empty():
				around += 1
	check(around == 0, "石拱两边的泥滩有矮石墙截断：从泥里绕不过石拱（绕得过去的 %d 处）" % around)
	# 泥潭：慢、不能跑，HUD 写着；踩上栈道就好了
	await main.set_daypart("day", false)
	var mud_spot: Vector3 = MarshLayout.VIEWS[5][0]
	p.global_position = mud_spot + Vector3(0, 0.05, 0)
	p.velocity = Vector3.ZERO
	await physics(20)
	Input.action_press("sprint")
	await physics(3)
	var mud_speed := p.current_speed(Vector2(0, -1))
	var mud_run := p.wants_run()
	Input.action_release("sprint")
	check(p.surface == "mud" and is_equal_approx(mud_speed, FpController.WALK_SPEED * Surface.mult("mud")) and not mud_run and main.hud.surface_label.visible and main.hud.surface_label.text == Surface.label("mud"),
		"泥滩里：速度 %.2f（走路的 %.0f%%）、按着冲刺也跑不起来，左下角写着「%s」" % [mud_speed, Surface.mult("mud") * 100.0, Surface.label("mud")])
	check(main.tip_now == "mud" or GameState.tips_seen.has("mud") or main.tip_queue.has("mud"), "第一次踩进泥里：教学提示讲泥潭")
	p.global_position = Vector3(70, MarshLayout.DECK_Y + 0.05, 30)
	await physics(20)
	Input.action_press("sprint")
	await physics(3)
	var deck_run := p.wants_run()
	Input.action_release("sprint")
	check(p.surface == "" and deck_run and not main.hud.surface_label.visible, "踩上栈道（栈道铺在泥滩上面）：又能跑了，那行字没了")
	# 掉进水里（墙漏了的话）：放回最近站稳的地方
	await physics(40)
	var safe := p.last_safe
	p.global_position = Vector3(20, -8, 40)
	await physics(3)
	check(safe != Vector3.INF and p.global_position.distance_to(safe) < 0.5, "掉出地图：放回最近站稳的地方（%s）" % p.global_position)
	# 地图：分块、旅行地图上的地点
	var errs := AreaMap.validate()
	check(errs.is_empty(), "地图数据通过检查（鹭沼的规格由布局表生成；%s）" % "; ".join(errs))
	var vz := Vector2(MarshLayout.SPAWNS.reedwharf[0].x, MarshLayout.SPAWNS.reedwharf[0].z)
	var gz := Vector2(MarshLayout.SPAWNS.castle_gate[0].x, MarshLayout.SPAWNS.castle_gate[0].z)
	var mid := MarshLayout.cw(30.0)
	check(AreaMap.zone_at("marsh", vz) == "芦栈村" and AreaMap.zone_at("marsh", gz) == "黑鹭堡外" and AreaMap.zone_at("marsh", mid) == "堤道", "地图分块：村口在「芦栈村」、堡门前在「黑鹭堡外」、堤道中间在「堤道」")
	check(Travel.place_of_area("marsh", vz) == "reedwharf" and Travel.place_of_area("marsh", gz) == "blackheron" and Travel.place_of_area("marsh", mid) == "" and Travel.place_of_area("frostford") == "frostford",
		"旅行地图上的地点按站的地方分：村口是芦栈村、堡门前是黑鹭堡、堤道中间哪个都不是")
	check(Travel.built("reedwharf") and Travel.built("blackheron") and Travel.validate().is_empty(), "芦栈村、黑鹭堡都能去了（都在鹭沼这张图上，出生点不同）")
	var tps: Array = main.find_children("*", "TravelPoint", true, false)
	check(tps.size() == 3 and tps.any(func(t): return (t as TravelPoint).display_name == Marsh.EXIT_NAME), "三处能出发：村口的路牌、东头路口「%s」、堡门前的路牌" % Marsh.EXIT_NAME)
	var gate_door: Array = main.world.find_children("*", "Door", true, false).filter(func(d): return (d as Door).display_name == Marsh.GATE_NAME)
	check(gate_door.size() == 1 and gate_door[0].locked and gate_door[0].locked_text.contains("赫尔曼"), "黑鹭堡的堡门锁着：没有堡守点头谁也进不去（4.5a）")
	# 高脚屋：每栋不超过 8 次绘制；地图上的房子和场景对得上
	var houses: Array = main.world.find_children("House_*", "Node3D", true, false)
	var surf_ok: bool = houses.all(func(h): return (h.get_node("Mesh") as MeshInstance3D).mesh.get_surface_count() <= 8)
	check(houses.size() == MarshLayout.HOUSES.size() + 1 and surf_ok, "%d 栋房子（高脚屋 + 托宾的小屋）都搭好了，每栋不超过 8 个表面" % houses.size())
	await free_main(main)
	# 后搭的块补上时段：白天进场，远处的块晚搭，窗也按白天熄着、夜灯灭着（不补的话是搭的时候那样：窗亮、灯亮）
	GameState.new_game(441)
	GameState.daypart = "day"
	main = await make_area("marsh")
	st = main.streamer
	var late: Array = st.chunks.keys().filter(func(id): return not st.chunks[id].done)
	st.build_all()
	var late_houses: Array = []
	for id in late:
		late_houses.append_array((st.root_of(id) as Node).find_children("House_*", "Node3D", false, false))
	var lit_ok: bool = late_houses.all(func(h): return h.has_meta("lit_now") and not bool(h.get_meta("lit_now")))
	var late_lamps: Array = []
	for id in late:
		late_lamps.append_array((st.root_of(id) as Node).find_children("*", "Node3D", true, false).filter(func(n): return n.is_in_group("night_light")))
	var lamps_off: bool = late_lamps.all(func(l): return not (l as Node3D).visible)
	check(not late.is_empty() and not late_houses.is_empty() and lit_ok and not late_lamps.is_empty() and lamps_off, "白天进场：后搭的 %d 块里的 %d 栋房子窗熄着、%d 盏夜灯灭着" % [late.size(), late_houses.size(), late_lamps.size()])
	main.apply_quality("low")
	var reeds: Array = main.get_tree().get_nodes_in_group("reeds")
	var half: bool = reeds.all(func(r): return (r as MultiMeshInstance3D).multimesh.visible_instance_count == int((r as MultiMeshInstance3D).multimesh.instance_count * Marsh.REED_LOW_SHARE))
	var bands := main.get_tree().get_nodes_in_group("fog_band")
	var shown := bands.filter(func(f): return (f as Node3D).visible).size()
	check(reeds.size() > 10 and half and shown < bands.size(), "低画质：%d 片芦苇都只画一半，雾带减半（%d / %d）" % [reeds.size(), shown, bands.size()])
	main.apply_quality("medium")
	# 读档：在堤道上存，读回来脚下有地、站得住
	main.player.global_position = MarshLayout.cw3(60.0, 0.0, MarshLayout.CAUSE_Y + 0.05)
	await physics(10)
	var d := main.collect_save() as Dictionary
	check(Saves.describe(d).begins_with("鹭沼 · 堤道"), "存档栏位写上在哪一块（%s）" % Saves.describe(d))
	await free_main(main)
	GameState.from_dict(d.state)
	GameState.pending_load = {"scene": "marsh", "player": d.player, "slot": "test"}
	main = await make_main(false)
	await physics(10)
	var pp: Vector3 = main.player.global_position
	var cid := MarshLayout.cell_id(MarshLayout.cell_of(Vector2(pp.x, pp.z)))
	check(main.area == "marsh" and main.player.is_on_floor() and absf(pp.y - MarshLayout.CAUSE_Y) < 0.1 and main.streamer.chunks[cid].done, "在堤道上存档、读回来：站在堤道上（y = %.2f），脚下这块先搭好了" % pp.y)
	await free_main(main)
	GameState.new_game()


## 第一章到了鹭沼（4.4b）：序章 choice 的状态，和维克托说完了（交出 / 勒索时埃德里克没说出去就有引荐信），主线在「去芦栈村」，
## 从霜渡镇的路牌出发到了 spawn（村口；走 _arrive：提示、自动存档）。letter = 有没有引荐信
func marsh_after(choice: String, sd := 1, letter := false, spawn := "reedwharf") -> Node3D:
	ch1_state(choice, sd)
	GameState.set_flag("ch1_victor_done")
	if letter:
		GameState.set_flag("ch1_letter")
		GameState.add_item("intro_letter")
	GameState.start_quest("ch1_main")
	GameState.daypart = "day"
	GameState.pending_load = {"scene": "marsh", "spawn": spawn, "player": {}}
	var main := await make_main(false)
	await physics(4)
	main.player.interactor.refresh()
	return main


## 直接在客栈里（不走门，像读档）：先把状态摆好再调
func inn_now() -> Node3D:
	GameState.pending_load = {"scene": "inn", "player": {}, "slot": "quick"}
	var main := await make_main(false)
	await physics(4)
	return main


## 不开场景、只跑对话（DialogueRunner）：按顺序选文字是 picks 的选项（检定选项的文字前面有「[口才检定 · 约 70%]」，按结尾比）；返回最后停在哪个节点（"" = 对话结束了）
func say_runner(id: String, picks: Array, file := "reedwharf") -> String:
	var r := DialogueRunner.new()
	if not r.start(file, id):
		return "（没打开）"
	for t in picks:
		var idx := -1
		var opts := r.options()
		for i in opts.size():
			if str(opts[i].text) == str(t) or DialogueRunner.option_label(opts[i]).ends_with(str(t)):
				idx = i
				break
		if idx < 0:
			return "（%s 没有选项「%s」）" % [r.node_id, t]
		if not r.choose(idx):
			return ""
	return r.node_id


## 人站在地上、没有卡在别的东西里：脚下 0.5 米内有地面（顶面就在脚底），身子那么大的胶囊不碰任何别的碰撞体（地面、墙、房子、垛子、木架、家具）
func stands_clear(n: Npc) -> bool:
	var space := n.get_world_3d().direct_space_state
	var from := n.global_position + Vector3(0, 0.5, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -1.0, 0), 1)
	q.exclude = [n.get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty() or absf(float(hit.position.y) - n.global_position.y) > 0.05:
		return false
	var sq := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.6
	sq.shape = cap
	sq.transform = Transform3D(Basis.IDENTITY, n.global_position + Vector3(0, 0.95, 0))
	sq.collision_mask = 1
	sq.exclude = [n.get_rid()]
	return space.intersect_shape(sq, 4).is_empty()


## 芦栈村的人与三条消息（路线图 4.4b；STORY.md 4.2「芦栈村：客栈老板、托宾、渡工、吉尔伯特（只在勒索时）」、4.4 勒索那一行、4.5 第 2 步）：
## 到了村子主线推进、村里的人一进场就在（不等分帧）、站得稳；托宾和渡工的消息、两条就推进到「去黑鹭堡」、顺序任意；
## 走进「歪桩客栈」（室内、三盏光、自动存档）、客栈里的人；吉尔伯特只在勒索时、卖借据（150 / 口才 200）、不卖、问来意；从客栈出来站在门前平台上；
## 4.4a 时在鹭沼存的档读进来也推进；地图出口和「鹭沼一带」
func test_reedwharf() -> void:
	Settings.set_value("third_person", false)
	wipe_test_saves()
	check(Areas.known("inn") and Areas.is_indoor("inn") and Saves.SCENE_NAMES.has("inn") and Areas.display_name("inn") == "「歪桩」客栈", "区域登记：「歪桩」客栈是室内区域，存档认得它")
	check(Areas.spawn("inn", "front") is Transform3D and Areas.spawn("marsh", "inn_door") is Transform3D, "客栈门内、门外都有命名出生点")
	var qd: Dictionary = GameState.quest_data()
	var stages: Dictionary = qd.quests.ch1_main.stages
	var msgs := ["msg_recruiters", "msg_causeway", "msg_envoy"]
	check(stages.has("ask_reedwharf") and stages.has("to_blackheron") and int(stages.ask_reedwharf.advance_when.get("clues_at_least", 0)) == 2 and str(stages.ask_reedwharf.advance_when.get("to", "")) == "to_blackheron"
		and msgs.all(func(c): return qd.clues.has(c) and qd.clues[c].quest == "ch1_main"), "主线「黑鹭之争」：在芦栈村打听（三条消息是三条线索，拿到两条推进）→ 去黑鹭堡")
	# —— 勒索：到了村口。渡工的口才检定这次要过
	var sd := seed_for("boatman_envoy_speech", "speech", 12, true)
	var main := await marsh_after("extort", sd)
	var p: FpController = main.player
	check(main.area == "marsh" and main.arrived_by == "reedwharf" and GameState.quest_stage("ch1_main") == "ask_reedwharf", "到了芦栈村：主线从「去芦栈村」推进到「在芦栈村打听」（%s）" % GameState.quest_stage("ch1_main"))
	check(main.hud.toast_label.text.contains("任务更新"), "提示任务更新（%s）" % main.hud.toast_label.text.replace("\n", " / "))
	await frames(3)
	var auto := Saves.read_slot("auto")
	check(auto.has("data") and auto.data.scene == "marsh" and str(auto.data.state.quests.ch1_main.stage) == "ask_reedwharf", "自动存档里已经是新的任务阶段")
	var people_ok := true
	var clear_ok := true
	var bad := []
	for pp: Array in MarshLayout.PEOPLE:
		var n := main.world.get_node_or_null("Npc_" + str(pp[0])) as Npc
		if n == null or n.get_parent() != main.world:
			people_ok = false
			continue
		var talks := n.dialogue_id != ""
		if talks != (str(pp[0]) in ["tobin", "boatman"]) or (not talks and n.lines.is_empty()):
			people_ok = false
		if not stands_clear(n):
			clear_ok = false
			bad.append(str(pp[0]))
	check(people_ok, "村里的 %d 个人一进场就在（不等分帧搭的块）：托宾、渡工说话用对话树，泥炭工、补网的女人轮流说一句" % MarshLayout.PEOPLE.size())
	check(clear_ok, "村里的人都站在地上，没卡在房子、泥炭垛、木架里（%s）" % str(bad))
	var door := main.world.get_node_or_null("InnDoor") as Door
	var ex: Array = AreaMap.exits("marsh")
	var dmid := Vector3.ZERO if door == null else door.global_transform * Vector3(door.width * 0.5, 0, 0)
	check(door != null and door.to_area == "inn" and door.to_spawn == "front" and not door.locked and ex.size() == 1 and ex[0].to == "inn"
		and Vector2(dmid.x, dmid.z).distance_to(ex[0].at) < 0.2 and ex[0].name == door.display_name, "客栈的门一进场就在、推得开（不等分帧），和鹭沼地图上的出口对得上")
	check(AreaMap.region_of("marsh") == "marsh" and AreaMap.region_of("inn") == "marsh" and AreaMap.links("marsh").has(["inn", "marsh"])
		and AreaMap.default_view("inn") == "region", "地图「鹭沼一带」：鹭沼和客栈连着；在客栈里按 M 先看一带")
	# —— 托宾：堤道和水门（第一条消息）
	check(await fl_say(main, "reedwharf", "tobin", ["去黑鹭堡怎么走？", "水门有人守吗？"]), "和托宾说话：去黑鹭堡怎么走")
	check(GameState.has_flag("heard_causeway") and "msg_causeway" in GameState.clues and GameState.quest_stage("ch1_main") == "ask_reedwharf", "托宾的消息记进任务日志；一条还不够，主线还在打听")
	main.open_dialogue("reedwharf", "tobin", main._npc_by_dialogue("tobin"))
	await frames(1)
	var labels: Array = main.dialogue.buttons.map(func(b): return (b as Button).text)
	check(main.dialogue.runner.node_id == "greet_again" and labels.any(func(t): return str(t).ends_with("要是堡门不让我进呢？"))
		and not labels.any(func(t): return str(t).ends_with("去黑鹭堡怎么走？")), "再找托宾：换了开场白，没有引荐信时多问一句「堡门不让我进」（%s）" % str(labels))
	main.dialogue.close()
	await frames(2)
	# —— 渡工：口才检定过了（第二条消息 → 推进）
	var silver0 := GameState.silver
	check(await fl_say(main, "reedwharf", "boatman", ["南边最近有人过来吗？", "我不是来找麻烦的，只想知道堡里在谈什么。"]), "和渡工说话：口才检定问塞弗林家的信使")
	check(GameState.has_flag("heard_envoy") and "msg_envoy" in GameState.clues and GameState.silver == silver0, "检定过了：渡工说了信使的事，没花钱")
	check(GameState.quest_stage("ch1_main") == "to_blackheron", "两条消息：主线推进到「去黑鹭堡」（%s）" % GameState.quest_stage("ch1_main"))
	await frames(3)
	check(str(Saves.read_slot("auto").data.state.quests.ch1_main.stage) == "to_blackheron", "任务更新时自动存档")
	# —— 冒烟测试用的机位：6 号对着客栈门，7 号对着托宾
	await seconds(0.4)
	main.set_view(6)
	await physics(3)
	p.interactor.refresh()
	var t6 := p.interactor.target
	main.set_view(7)
	await physics(3)
	p.interactor.refresh()
	check(t6 == door and p.interactor.target == main.world.get_node("Npc_tobin"), "鹭沼 6 号机位对着客栈门、7 号对着托宾（冒烟测试用）")
	# —— 走进客栈：在门前的平台上对准门，按交互
	var v6: Array = MarshLayout.VIEWS[6]
	await aim(p, v6[0], dmid + Vector3(0, 1.1, 0))
	check(p.interactor.target == door and door.prompt() == "进入 · 歪桩客栈", "站在客栈门前对准门：提示「进入 · 歪桩客栈」（%s）" % (p.interactor.target.prompt() if p.interactor.target else "没对准"))
	var rr := [0]
	main.reload_requested.connect(func(): rr[0] += 1)
	p.interactor.use()
	await seconds(0.45)
	check(rr[0] == 1 and GameState.pending_load.get("scene") == "inn" and GameState.pending_load.get("spawn") == "front", "按交互：去客栈里面（%s）" % str(GameState.pending_load))
	main = await reload_main(main)
	p = main.player
	await frames(5)
	check(main.area == "inn" and main.arrived_by == "front" and flat(p.global_position).distance_to(Vector2(Inn.DOOR_X, 3.1)) < 0.3 and absf(p.rotation.y) < 0.05,
		"站在客栈门内、面朝大堂（%s）" % str(p.global_position))
	check(main.hud.toast_label.text.begins_with("「歪桩」客栈") and Saves.read_slot("auto").data.scene == "inn", "进门提示「「歪桩」客栈」，自动存档")
	check(not main.moon.visible and main.env.fog_mode == Environment.FOG_MODE_EXPONENTIAL and GameState.quest_stage("ch1_main") == "to_blackheron", "室内：没有月光、暖暗的环境光；主线不倒退")
	var omni := main.find_children("*", "OmniLight3D", true, false)
	check(omni.size() == 4 and omni.filter(func(l): return l is Tavern.FireLight).size() == 2, "四盏光：泥炭火塘、吧台油灯、过道上方的吊灯，加西墙的火把（2026-10-23 美化）（%d）" % omni.size())
	var inn_people := main.find_children("Npc_*", "Npc", true, false)
	var names := inn_people.map(func(n): return n.display_name)
	var inn_bad: Array = inn_people.filter(func(n): return not stands_clear(n)).map(func(n): return n.display_name)
	check(names.has("客栈老板") and names.has("阿尔里克的军士") and names.has("伊薇特的老兵") and names.has("吉尔伯特") and names.has("喝酒的泥炭工") and names.has("烤火的老船夫"),
		"客栈里：老板、两拨招兵的人、勒索时窗边的吉尔伯特、两个只说一句的客人（%s）" % str(names))
	check(inn_bad.is_empty(), "客栈里的人都站在地上，没卡在吧台、桌子、火塘里（%s）" % str(inn_bad))
	var gate: Array = main.find_children("*", "Door", true, false).filter(func(d): return d.display_name == "上楼的栅门")
	check(gate.size() == 1 and gate[0].locked and gate[0].locked_text == Inn.GATE_TEXT, "上楼的栅门锁着")
	var views_ok := true
	for i in Inn.VIEWS.size():
		main.set_view(i)
		await physics(6)
		if absf(p.global_position.y) > 0.05 or flat(p.global_position).distance_to(Vector2(Inn.VIEWS[i][0].x, Inn.VIEWS[i][0].z)) > 0.1:
			views_ok = false
	check(views_ok, "%d 个固定机位都站在地板上、没被家具推开" % Inn.VIEWS.size())
	main.set_view(1)
	await physics(3)
	p.interactor.refresh()
	check(p.interactor.target != null and p.interactor.target.display_name == "客栈老板", "吧台前的机位正对着客栈老板（冒烟测试用）")
	check(await fl_say(main, "reedwharf", "innkeeper", ["打听一下黑鹭堡的事。", "家主怎么样了？"]), "和客栈老板说话：打听黑鹭堡")
	check(GameState.has_flag("heard_recruiters") and "msg_recruiters" in GameState.clues and GameState.clues_for("ch1_main").size() == 3, "第三条消息也记下了（三条都在任务日志里）")
	var s0 := GameState.silver
	var b0 := GameState.count_item("bread")
	check(await fl_say(main, "reedwharf", "innkeeper", ["来块面包。（2 银币）", "多谢。"]) and GameState.silver == s0 - 2 and GameState.count_item("bread") == b0 + 1, "在客栈买面包：2 枚银币")
	# —— 吉尔伯特：按原价卖
	var cas := GameState.get_rep("caswell")
	s0 = GameState.silver
	check(await fl_say(main, "reedwharf", "gilbert", ["你在这儿等我做什么？", "成交。（交出借据，拿 150 枚银币）"]), "和吉尔伯特说话：卖借据")
	check(GameState.silver == s0 + 150 and not GameState.has_item("debt_note") and str(GameState.get_flag("ch1_debt")) == "sold" and GameState.get_rep("caswell") == cas + 20,
		"卖了：拿 150 枚银币，借据没了，ch1_debt = sold，卡斯韦尔家声望 +20（%d → %d）" % [cas, GameState.get_rep("caswell")])
	main.open_dialogue("reedwharf", "gilbert", main._npc_by_dialogue("gilbert"))
	await frames(1)
	check(main.dialogue.runner.node_id == "done", "卖完再找他：「买卖做完了」")
	main.dialogue.close()
	await frames(2)
	# —— 出门：站在客栈门前的平台上，背对门
	main = await fl_go(main, "marsh")
	p = main.player
	await physics(4)
	var down := PhysicsRayQueryParameters3D.create(p.global_position + Vector3(0, 0.5, 0), p.global_position + Vector3(0, -1.0, 0), 1)
	down.exclude = [p.get_rid()]
	var hit := p.get_world_3d().direct_space_state.intersect_ray(down)
	check(main.area == "marsh" and main.arrived_by == "inn_door" and not hit.is_empty() and absf(float(hit.position.y) - (MarshLayout.DECK_Y + MarshLayout.STILTS)) < 0.05
		and absf(wrapf(p.rotation.y - PI, -PI, PI)) < 0.05, "从客栈出来：站在门前的平台上、背对门（%s）" % str(p.global_position))
	check(main.hud.toast_label.text.begins_with("鹭沼 · 芦栈村") and GameState.quest_stage("ch1_main") == "to_blackheron", "提示「鹭沼 · 芦栈村」，主线还是「去黑鹭堡」")
	await free_main(main)
	# —— 口才说动吉尔伯特抬价：200 枚、声望 +15；问来意（洞察）只问一次
	ch1_state("extort", seed_for("gilbert_price_speech", "speech", 14, true))
	GameState.start_quest("ch1_main", "ask_reedwharf")
	main = await inn_now()
	cas = GameState.get_rep("caswell")
	s0 = GameState.silver
	check(await fl_say(main, "reedwharf", "gilbert", ["你在这儿等我做什么？", "卡斯韦尔家要它做什么？", "……", "一百五？背面压着王室的印，它可不止这个价。"], true)
		and main.dialogue.runner.node_id == "price_up" and GameState.has_flag("gilbert_asked"), "问来意、讨价还价（口才过了）：两百枚")
	var lab2: Array = main.dialogue.buttons.map(func(b): return (b as Button).text)
	check(lab2.any(func(t): return str(t).ends_with("成交。（交出借据，拿 200 枚银币）")) and not lab2.any(func(t): return str(t).ends_with("拿 150 枚银币）")), "抬价以后只剩 200 枚的成交（%s）" % str(lab2))
	main.dialogue.close()
	await frames(2)
	main.open_dialogue("reedwharf", "gilbert", main._npc_by_dialogue("gilbert"))
	await frames(1)
	var lab3: Array = []
	if main.dialogue.runner.node_id == "again":
		find_button(main.dialogue, "说说你的价钱。").pressed.emit()
		await frames(1)
		lab3 = main.dialogue.buttons.map(func(b): return (b as Button).text)
	check(main.dialogue.runner.node_id == "offer_up" and not lab3.any(func(t): return str(t).ends_with("卡斯韦尔家要它做什么？")), "回头再谈：价钱还是两百，来意不能再问（%s）" % str(lab3))
	check(await fl_say(main, "reedwharf", "gilbert", ["成交。（交出借据，拿 200 枚银币）"]) and GameState.silver == s0 + 200 and GameState.get_rep("caswell") == cas + 15
		and str(GameState.get_flag("ch1_debt")) == "sold", "卖了 200 枚，卡斯韦尔家声望 +15")
	await free_main(main)
	# —— 抬价没说动、不卖：借据留着（4.8 交给继承人当筹码）；交出 / 放走时客栈里没有吉尔伯特
	ch1_state("extort", seed_for("gilbert_price_speech", "speech", 14, false))
	GameState.start_quest("ch1_main", "ask_reedwharf")
	check(say_runner("gilbert", ["你在这儿等我做什么？", "一百五？背面压着王室的印，它可不止这个价。"]) == "price_firm" and GameState.has_flag("gilbert_firm"), "讨价还价没说动：价钱不变")
	var r := DialogueRunner.new()
	r.start("reedwharf", "gilbert")
	var ot := r.options().map(func(o): return o.text)
	check(r.node_id == "again" and say_runner("gilbert", ["说说你的价钱。"]) == "offer", "回头再谈：回到 150 枚的价钱")
	r.start("reedwharf", "gilbert")
	r.choose(0)
	ot = r.options().map(func(o): return o.text)
	check(not ot.has("一百五？背面压着王室的印，它可不止这个价。") and ot.has("成交。（交出借据，拿 150 枚银币）"), "不能再讨价还价，原价还能卖（%s）" % str(ot))
	check(say_runner("gilbert", ["说说你的价钱。", "不卖。", "（告辞）"]) == "" and GameState.has_item("debt_note") and not GameState.has_flag("ch1_debt"), "不卖：借据还在身上，ch1_debt 不设")
	ch1_state("deliver")
	GameState.start_quest("ch1_main", "ask_reedwharf")
	main = await inn_now()
	names = main.find_children("Npc_*", "Npc", true, false).map(func(n): return n.display_name)
	check(not names.has("吉尔伯特") and main.area == "inn", "交出：客栈里没有吉尔伯特")
	r.start("reedwharf", "innkeeper")
	ot = r.options().map(func(o): return o.text)
	check(not ot.has("窗边那位客人是谁？") and ot.has("打听一下黑鹭堡的事。"), "交出：客栈老板不提窗边的客人")
	await free_main(main)
	# —— 顺序任意：客栈（阿尔里克的军士）+ 渡工（给 3 枚银币）也推进；口才没问出来就只剩给钱，没钱时选项灰着
	ch1_state("release", seed_for("boatman_envoy_speech", "speech", 12, false))
	GameState.start_quest("ch1_main", "ask_reedwharf")
	check(say_runner("alric_sergeant", ["阿尔里克大人凭什么继承？"]) == "why" and GameState.has_flag("heard_recruiters") and GameState.quest_stage("ch1_main") == "ask_reedwharf", "阿尔里克的军士也说得出客栈那条消息")
	check(say_runner("boatman", ["南边最近有人过来吗？", "我不是来找麻烦的，只想知道堡里在谈什么。"]) == "refuse" and GameState.has_flag("boatman_refused"), "口才没问出渡工的话")
	r.start("reedwharf", "boatman")
	r.choose(0)
	ot = r.options().map(func(o): return o.text)
	check(r.node_id == "envoy_ask" and not ot.has("我不是来找麻烦的，只想知道堡里在谈什么。"), "不能再试口才（%s）" % str(ot))
	var keep := GameState.silver
	GameState.add_silver(-keep)
	var ent: Array = r.entries()
	var pay_e: Array = ent.filter(func(e): return str(e.option.text).begins_with("（把 3 枚银币"))
	check(pay_e.size() == 1 and pay_e[0].locked and str(pay_e[0].need).begins_with("3 枚银币"), "没钱：给 3 枚银币那一项灰着、写着需要什么")
	GameState.add_silver(keep)
	check(say_runner("boatman", ["南边最近有人过来吗？", "（把 3 枚银币放在船帮上）这够不够买一句规矩以外的话？"]) == "envoy" and GameState.silver == keep - 3
		and GameState.quest_stage("ch1_main") == "to_blackheron", "给 3 枚银币问出来了：客栈 + 渡工两条，也推进到「去黑鹭堡」")
	r.start("reedwharf", "innkeeper")
	check(r.node_id == "greet" and say_runner("innkeeper", ["打听一下黑鹭堡的事。"]) == "news" and say_runner("innkeeper", ["再说说招兵的那两拨人。"]) == "news_recap",
		"先听了军士的再找客栈老板：他是头一回见你（不说「又来了」），照样讲、再问也接得上")
	check(say_runner("ivette_veteran", ["那就说说实话。"]) == "truth" and say_runner("alric_sergeant", ["我是誓剑，不替谁签名。"]) == "hired_free",
		"伊薇特的老兵接得上；没有引荐信（被维克托赶出来）时不说「已经有雇主了」")
	# —— 4.4a 时在鹭沼存的档（主线还在「去芦栈村」）：读进来就推进；第一章以前（网页 ?area=marsh）不碰任务
	ch1_state("release")
	GameState.start_quest("ch1_main")
	GameState.pending_load = {"scene": "marsh", "player": {"pos": [80.5, 0.12, 31.0], "yaw": 0.7}, "slot": "quick"}
	main = await make_main(false)
	await physics(2)
	check(main.arrived_by == "" and GameState.quest_stage("ch1_main") == "ask_reedwharf", "读 4.4a 在鹭沼存的档：主线也推进到「在芦栈村打听」")
	await free_main(main)
	ch1_state("release")
	GameState.pending_load = {"scene": "marsh", "spawn": "reedwharf", "player": {}}
	main = await make_main(false)
	check(GameState.quest_stage("ch1_main") == "ask_reedwharf", "没和维克托说话就出发了：到了村子主线也从「在芦栈村打听」接上")
	await free_main(main)
	GameState.new_game()
	main = await make_area("marsh")
	check(GameState.quest_stage("ch1_main") == "" and main.world.get_node_or_null("Npc_tobin") != null, "第一章以前直接开鹭沼（截图用）：人在，任务不动")
	await free_main(main)
	GameState.new_game()


## 鹭沼深处与营地（路线图 4.4c；STORY.md 4.2「鹭沼深处」、4.4「序章其他旗标」）：小路、泥滩、土墩、枯树都在，分块；营地对你的态度看序章怎么了结的奥弗
## （友善 / 记恨 / 奥弗死了是头目 / 没打过交道），营地的人一进场就在、站得稳；奥弗的对话（说动、吓住、给钱、没说动就让你滚、只剩给钱）、头目的对话；
## 托宾指路；固定机位；营火白天也烧着；泥滩走得慢
func test_deepmarsh() -> void:
	Settings.set_value("third_person", false)
	var fire2 := Vector2(MarshLayout.CAMP_FIRE.x, MarshLayout.CAMP_FIRE.z)
	check(AreaMap.zone_at("marsh", fire2) == "鹭沼深处" and AreaMap.zone_at("marsh", Vector2(25, 30)) == "芦栈村" and Travel.place_of_area("marsh", fire2) == "",
		"营地在「鹭沼深处」（不是能出发的地方），小路靠村子那头还算芦栈村")
	var ids := MarshLayout.floors().map(func(f): return str(f.id))
	check(MarshLayout.DEEP.all(func(d): return str(d[0]) in ids), "鹭沼深处的 %d 块地面都在地面表里（碰撞、画面、地图、墙一起生成）" % MarshLayout.DEEP.size())
	var touch := true
	for i in MarshLayout.DEEP.size() - 1:
		var a: Rect2 = MarshLayout.DEEP[i][2]
		var b: Rect2 = MarshLayout.DEEP[i + 1][2]
		if not a.grow(0.01).intersects(b):
			touch = false
	check(touch, "小路、泥滩、土墩、泥滩、营地一块接一块，中间没有缝")
	# 序章的四种了结 → 营地的态度
	GameState.new_game(1)
	check(Marsh.camp_mood() == "neutral", "没和奥弗打过交道：营地是 neutral")
	GameState.set_flag("offer_left")
	check(Marsh.camp_mood() == "friendly", "谈妥 / 吓走 / 花钱打发了（offer_left）：friendly")
	GameState.new_game(1)
	GameState.set_flag("offer_defeated")
	GameState.yielded["ferry_offer"] = [0.0, 0.0, 0.0]
	check(Marsh.camp_mood() == "grudge", "打过一仗、奥弗跪地认输还活着：grudge")
	GameState.dead["ferry_offer"] = [0.0, 0.0, 0.0]
	check(Marsh.camp_mood() == "boss", "奥弗死在渡口：boss（火边站的是手下的头目）")
	# —— 友善：第一章到了村子，营地的人一进场就在
	wipe_test_saves()
	var main := await marsh_after("deliver", 3)                     # ch1_state 里序章和奥弗谈妥了（offer_left）
	var p: FpController = main.player
	var camp_people: Array = [MarshLayout.CAMP_OFFER] + MarshLayout.CAMP_MEN
	var here := camp_people.all(func(cp): return main.world.get_node_or_null("Npc_" + str(cp[0])) != null)
	check(here and main.world.get_node_or_null("Npc_camp_boss") == null, "营地的 %d 个人一进场就在（不等分帧）：奥弗和三个手下" % camp_people.size())
	var bad := camp_people.filter(func(cp): return not stands_clear(main.world.get_node("Npc_" + str(cp[0])))).map(func(cp): return str(cp[0]))
	check(bad.is_empty(), "营地的人都站在地上，没卡在窝棚、火堆、圆木、箱子里（%s）" % str(bad))
	var thug := main.world.get_node("Npc_camp_thug_a") as Npc
	check(thug.lines == MarshLayout.CAMP_LINES.friendly and (main.world.get_node("Npc_offer_camp") as Npc).dialogue_id == "offer_camp", "友善：手下说的是友善的话，奥弗用对话树")
	main.streamer.build_all()
	await frames(2)
	var camp_root: Node = main.streamer.root_of(MarshLayout.cell_id(MarshLayout.cell_of(fire2)))
	var campfire := camp_root.find_child("Campfire", true, false) as OmniLight3D
	check(camp_root.find_child("Camp", true, false) != null and campfire != null and campfire.visible and campfire.light_energy > 1.0,
		"营地搭出来了：窝棚、营火（白天也烧着，不归夜灯管）")
	var trees := 0
	for t in MarshLayout.DEEP_TREES:
		var r: Node = main.streamer.root_of(MarshLayout.cell_id(MarshLayout.cell_of(t[0])))
		for c in r.get_children():
			if c is Node3D and not (c is MeshInstance3D) and (c as Node3D).position.distance_to(Vector3(t[0].x, MarshLayout.BANK_Y, t[0].y)) < 0.01:
				trees += 1
	var trunk := 0
	var space := p.get_world_3d().direct_space_state
	for t in MarshLayout.DEEP_TREES:
		var q := PhysicsRayQueryParameters3D.create(Vector3(t[0].x + 1.5, 1.0, t[0].y), Vector3(t[0].x, 1.0, t[0].y), 1)
		if not space.intersect_ray(q).is_empty():
			trunk += 1
	check(trees == MarshLayout.DEEP_TREES.size() and trunk == trees, "%d 棵枯树搭出来了、树干撞得上（碰撞同步建、不在块里）" % trees)
	# 机位：9 号在小路上，10 号对着火边的人
	main.set_view(10)
	await physics(3)
	p.interactor.refresh()
	check(p.interactor.target == main.world.get_node("Npc_offer_camp"), "10 号机位正对着火边的奥弗（冒烟测试用）")
	main.set_view(9)
	await physics(4)
	check(absf(p.global_position.y - MarshLayout.DECK_Y) < 0.05, "9 号机位站在沼地的小路上")
	# 泥滩：走得慢
	place(p, 6.0, 30.0)
	await physics(8)
	check(p.surface == "mud", "小路西头下去是泥滩（走得慢、不能跑）")
	# 托宾指路
	check(await fl_say(main, "reedwharf", "tobin", ["沼地深处有什么？"]) and GameState.has_flag("heard_camp"), "托宾说沼地的小路和西边扎营的外乡人")
	# 奥弗（友善）：说上话，说出「谁出价高就跟谁」
	check(await fl_say(main, "deepmarsh", "offer_camp", ["黑鹭堡要出事了，你们听说了吗？"]) and GameState.has_flag("offer_camp_met") and GameState.has_flag("offer_camp_terms"),
		"友善的奥弗直接说话：两边都来问过价，谁出价高就跟谁")
	await free_main(main)
	# —— 记恨：口才说动 / 威吓吓住 / 没说动就滚、只剩给钱
	ch1_state("deliver", seed_for("offer_camp_speech", "speech", 17, true))
	GameState.flags.erase("offer_left")
	GameState.set_flag("offer_defeated")
	GameState.yielded["ferry_offer"] = [0.0, 0.0, 0.0]
	check(say_runner("offer_camp", ["那晚各为其主。今天我不是来打架的。"], "deepmarsh") == "calm" and GameState.has_flag("offer_camp_met"), "记恨：口才说动了，肯说话")
	ch1_state("deliver", seed_for("offer_camp_intimidate", "intimidate", 16, true))
	GameState.flags.erase("offer_left")
	GameState.set_flag("offer_defeated")
	check(say_runner("offer_camp", ["上回你们几个一起上，也没赢。要再试试？"], "deepmarsh") == "calm_scared", "记恨：威吓吓住了")
	ch1_state("deliver", seed_for("offer_camp_speech", "speech", 17, false))
	GameState.flags.erase("offer_left")
	GameState.set_flag("offer_defeated")
	GameState.yielded["ferry_offer"] = [0.0, 0.0, 0.0]
	check(say_runner("offer_camp", ["那晚各为其主。今天我不是来打架的。"], "deepmarsh") == "refused" and GameState.has_flag("offer_camp_refused") and not GameState.has_flag("offer_camp_met"), "记恨：没说动，让你滚")
	var r := DialogueRunner.new()
	r.start("deepmarsh", "offer_camp")
	var ot := r.options().map(func(o): return o.text)
	check(r.node_id == "refused_again" and not ot.any(func(t): return str(t).begins_with("那晚各为其主")), "再去：只剩给钱或者走（%s）" % str(ot))
	GameState.silver = 50
	check(say_runner("offer_camp", ["（扔过去一袋银币）40 枚，给你的人买药。"], "deepmarsh") == "calm_paid" and GameState.silver == 10 and GameState.has_flag("offer_camp_met"), "给 40 枚银币：肯说话了")
	main = await make_main_marsh()
	var ld := main.world.get_node("Npc_offer_camp") as Npc
	check(ld != null and stands_clear(ld) and (main.world.get_node("Npc_camp_thug_b") as Npc).lines == MarshLayout.CAMP_LINES.grudge, "记恨：奥弗还在火边，手下说的是记恨的话")
	await free_main(main)
	# —— 奥弗死在渡口：头目
	ch1_state("deliver")
	GameState.flags.erase("offer_left")
	GameState.set_flag("offer_defeated")
	GameState.dead["ferry_offer"] = [0.0, 0.0, 0.0]
	main = await make_main_marsh()
	var boss := main.world.get_node_or_null("Npc_camp_boss") as Npc
	check(boss != null and main.world.get_node_or_null("Npc_offer_camp") == null and boss.dialogue_id == "camp_boss" and stands_clear(boss), "奥弗死在渡口：火边站的是手下的头目")
	await free_main(main)
	GameState.silver = 45
	check(say_runner("camp_boss", ["（放下 40 枚银币）给他的人买口吃的。", "黑鹭堡要出事了，你们听说了吗？"], "deepmarsh") == "war" and GameState.silver == 5 and GameState.has_flag("offer_camp_terms"),
		"头目：放下 40 枚银币才肯说话，也说「谁出价高就跟谁」")
	GameState.silver = 0
	r.start("deepmarsh", "camp_boss")
	check(r.node_id == "again", "给过钱的再去：直接说话")
	GameState.new_game(1)
	GameState.silver = 10
	r.start("deepmarsh", "camp_boss")
	var bo: Array = r.entries().map(func(e): return [str(e.option.text), e.locked])
	check(r.node_id == "greet" and bo.has(["（放下 40 枚银币）给他的人买口吃的。", true]) and bo.has(["我只是路过。", false]), "头目：钱不够时给钱那一项灰着，只能走（%s）" % str(bo))
	check(say_runner("offer_camp", ["你们怎么到鹭沼来了？"], "deepmarsh") == "why_here" and GameState.has_flag("offer_camp_met"), "没和奥弗打过交道（网页直接开鹭沼）：他也肯说话")
	# 第一章起渡口不再跪着认输的奥弗（他带人去了鹭沼深处）；死在渡口的照旧
	ch1_state("deliver")
	GameState.flags.erase("offer_left")
	GameState.set_flag("offer_defeated")
	GameState.yielded["ferry_offer"] = [2.1, 0.0, 2.4]
	GameState.dead["ferry_thug_a"] = [0.0, 0.0, 0.0]
	GameState.pending_load = {"scene": "ferry", "player": {}}
	main = await make_main(false)
	var fe: Array = main.find_children("*", "Enemy", true, false).map(func(e): return str(e.enemy_id))
	check(not fe.has("ferry_offer") and fe.has("ferry_thug_a"), "第一章的渡口：认输的奥弗不在了（在鹭沼的营地），死在那儿的还在（%s）" % str(fe))
	await free_main(main)
	GameState.new_game()


## 第一章的状态已经摆好，直接在鹭沼村口载入（不走路牌）
func make_main_marsh() -> Node3D:
	GameState.pending_load = {"scene": "marsh", "spawn": "reedwharf", "player": {}}
	var main := await make_main(false)
	await physics(3)
	return main


## 0.5 米的格子上，身子那么大的胶囊放得下的地方（不碰墙、房子、井、车、垛子、别的人）；从 from 走得到 to 附近（radius 米内）吗
func walk_reach(main: Node3D, from: Vector3, to: Vector3, radius: float, area: Rect2) -> bool:
	var space: PhysicsDirectSpaceState3D = main.player.get_world_3d().direct_space_state
	var sq := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.4
	sq.shape = cap
	sq.collision_mask = 1
	sq.exclude = [main.player.get_rid()]
	var free := func(c: Vector2i) -> bool:
		sq.transform = Transform3D(Basis.IDENTITY, Vector3(c.x * 0.5, 0.95, c.y * 0.5))
		return space.intersect_shape(sq, 1).is_empty()
	var start := Vector2i(roundi(from.x * 2.0), roundi(from.z * 2.0))
	var seen := {start: true}
	var todo := [start]
	while not todo.is_empty():
		var c: Vector2i = todo.pop_back()
		if Vector2(c.x * 0.5, c.y * 0.5).distance_to(Vector2(to.x, to.z)) <= radius:
			return true
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if seen.has(n) or not area.has_point(Vector2(n.x * 0.5, n.y * 0.5)):
				continue
			seen[n] = true
			if free.call(n):
				todo.append(n)
	return false


## 黑鹭堡（路线图 4.5a；STORY.md 4.5 第 3 步）：庭院区域、堡门前的卫兵看引荐信放人（对话里的 goto 把人送进去）、进了庭院主线推进、赫尔曼按进来的路说话、
## 见过以后堡门推得开；没有引荐信的三种办法（托宾的泥炭船、伊薇特的老兵带路走侧门、奥弗的船）；庭院里从三个进来的地方都走得到赫尔曼；地图出口
func test_castle() -> void:
	Settings.set_value("third_person", false)
	wipe_test_saves()
	check(Areas.known("castle") and not Areas.is_indoor("castle") and Saves.SCENE_NAMES.has("castle") and Castle.SPAWNS.keys().all(func(k): return Areas.spawn("castle", k) is Transform3D),
		"区域登记：黑鹭堡庭院是室外区域，三个进来的地方都是出生点")
	# —— 有引荐信：堡门前的卫兵看了信就放人
	var main := await marsh_after("deliver", 5, true, "castle_gate")
	var guard := main.world.get_node_or_null("Npc_gate_guard") as Npc
	check(guard != null and stands_clear(guard) and Travel.place_of_area("marsh", flat(guard.global_position)) == "blackheron", "堡门前站着守门的卫兵（站在石台上，没卡在门洞里）")
	var gd: Door = main.world.find_children("*", "Door", true, false).filter(func(d): return d.display_name == Marsh.GATE_NAME)[0]
	check(gd.locked and AreaMap.exits("marsh").size() == 1, "没放进过：堡门锁着，地图上不算出口")
	var rr := [0]
	main.reload_requested.connect(func(): rr[0] += 1)
	check(await fl_say(main, "blackheron", "gate_guard", ["我有维克托大人写给堡守赫尔曼的引荐信。", "（进堡）"]), "和卫兵说话：拿出引荐信")
	await seconds(0.6)
	check(rr[0] == 1 and GameState.pending_load.get("scene") == "castle" and GameState.pending_load.get("spawn") == "gate" and GameState.has_flag("castle_admitted"),
		"卫兵放人：对话一关就走进堡门（%s）" % str(GameState.pending_load))
	main = await reload_main(main)
	await physics(3)
	check(main.area == "castle" and main.arrived_by == "gate" and GameState.quest_stage("ch1_main") == "meet_herman" and main.hud.toast_label.text.begins_with("黑鹭堡"),
		"进了黑鹭堡的庭院：提示「黑鹭堡」，主线推进到「见赫尔曼」（%s）" % GameState.quest_stage("ch1_main"))
	check(Saves.read_slot("auto").data.scene == "castle", "进了庭院自动存档")
	var people := main.find_children("Npc_*", "Npc", true, false)
	var bad: Array = people.filter(func(n): return not stands_clear(n)).map(func(n): return n.display_name)
	check(people.size() == 1 + Castle.GUARDS.size() and bad.is_empty(), "庭院里：赫尔曼和 %d 个兵，都站得稳（%s）" % [Castle.GUARDS.size(), str(bad)])
	var herman: Npc = main._npc_by_dialogue("herman")
	var area := Rect2(-Castle.HW, -Castle.HD, Castle.HW * 2.0, Castle.HD * 2.0)
	var reach_ok := true
	for k in Castle.SPAWNS:
		if not walk_reach(main, Castle.SPAWNS[k][0], herman.position, 1.4, area):
			reach_ok = false
	check(reach_ok, "从堡门、水门、兵营侧门进来，都走得到井边的赫尔曼")
	var doors: Array = main.find_children("*", "Door", true, false)
	var open: Array = doors.filter(func(d): return d.to_area != "" and not d.locked)
	var ex: Array = AreaMap.exits("castle")
	var doors_match := open.size() == 2 and ex.size() == 2
	for d in open:
		var mid: Vector3 = d.global_transform * Vector3(d.width * 0.5, 0, 0)
		var hit: Array = ex.filter(func(e): return e.name == d.display_name and Vector2(mid.x, mid.z).distance_to(e.at) < 0.3)
		doors_match = doors_match and hit.size() == 1
	var targets: Array = open.map(func(d): return "%s/%s" % [d.to_area, d.to_spawn])
	targets.sort()
	check(doors_match and targets == ["hall/front", "marsh/castle_gate"],
		"堡门通往鹭沼、大厅门通往大厅，都和地图出口对得上（%s）" % str(targets))
	var locked_names: Array = doors.filter(func(d): return d.locked).map(func(d): return d.display_name)
	check(["兵营", "病房", "账房", "水门", "兵营侧门"].all(func(n): return n in locked_names) and not "大厅" in locked_names, "兵营、病房、账房、水门、侧门都还关着，大厅开着（%s）" % str(locked_names))
	check(AreaMap.region_of("castle") == "marsh" and AreaMap.links("marsh").has(["castle", "marsh"]), "地图「鹭沼一带」里有黑鹭堡")
	# 赫尔曼（堡门进来）：主线推进到「去大厅」，借据只能等家主醒
	main.set_view(1)
	await physics(3)
	main.player.interactor.refresh()
	check(main.player.interactor.target == herman, "1 号机位正对着赫尔曼（冒烟测试用）")
	check(await fl_say(main, "blackheron", "herman", ["维克托大人让我把借据亲手交给家主。"]) and GameState.has_flag("herman_met") and GameState.quest_stage("ch1_main") == "to_hall",
		"赫尔曼：堡门进来的规规矩矩；交出时说借据的事（等家主醒）；主线推进到「去大厅」")
	# 出堡门：回到堡门前，堡门这回推得开，地图上也算出口
	main = await fl_go(main, "marsh")
	await physics(3)
	gd = main.world.find_children("*", "Door", true, false).filter(func(d): return d.display_name == Marsh.GATE_NAME)[0]
	check(main.area == "marsh" and main.arrived_by == "castle_gate" and not gd.locked and gd.to_area == "castle" and AreaMap.exits("marsh").size() == 2,
		"出了堡门站在石台上；堡门推得开了，地图上算出口")
	await free_main(main)
	# —— 没有引荐信：卫兵不放；托宾的泥炭船走水门
	ch1_state("release", 6)
	GameState.set_flag("ch1_victor_done")
	GameState.start_quest("ch1_main", "to_blackheron")
	GameState.set_flag("heard_causeway")
	check(say_runner("gate_guard", ["我是霜渡镇的誓剑，有事要见家主。"], "blackheron") == "no" and not GameState.has_flag("castle_admitted"), "没有引荐信：卫兵不放")
	GameState.add_item("intro_letter")
	check(say_runner("gate_guard", ["我有维克托大人写给堡守赫尔曼的引荐信。"], "blackheron") == "letter" and not GameState.has_flag("castle_admitted"),
		"卫兵看了信、还没进门就关掉对话：不算放进过（堡门和地图不会对不上，审查）")
	GameState.take_item("intro_letter")
	var r := DialogueRunner.new()
	r.start("blackheron", "gate_guard")
	check(not r.options().any(func(o): return str(o.text).begins_with("我有维克托")), "没有引荐信就没有那一项（不灰着提示）")
	GameState.pending_load = {"scene": "marsh", "spawn": "reedwharf", "player": {}}
	main = await make_main(false)
	await physics(2)
	rr = [0]
	main.reload_requested.connect(func(): rr[0] += 1)
	check(await fl_say(main, "reedwharf", "tobin", ["你说的泥炭船——能捎我进堡吗？", "上船。"]), "托宾：蹲在泥炭船里走水门")
	await seconds(0.6)
	check(rr[0] == 1 and GameState.pending_load.get("spawn") == "water_gate" and str(GameState.get_flag("castle_entry")) == "tobin", "托宾的船：送到水门里面")
	main = await reload_main(main)
	await physics(3)
	check(main.area == "castle" and main.arrived_by == "water_gate" and GameState.quest_stage("ch1_main") == "meet_herman", "从水门进了庭院")
	main.open_dialogue("blackheron", "herman", main._npc_by_dialogue("herman"))
	await frames(1)
	check(main.dialogue.runner.node_id == "greet_water", "赫尔曼：「水门进来的？」")
	main.dialogue.close()
	await free_main(main)
	# —— 伊薇特的老兵：兵营侧门；奥弗的船：水门（20 枚银币）；有引荐信的人没有这些选项
	ch1_state("extort", 7)
	GameState.start_quest("ch1_main", "to_blackheron")
	check(say_runner("ivette_veteran", ["堡门不让我进。"]) == "side_gate", "伊薇特的老兵：兵营的侧门归他们的人管")
	r.start("reedwharf", "ivette_veteran")
	r.choose(r.options().map(func(o): return o.text).find("堡门不让我进。"))
	r.choose(0)
	check(GameState.pending_goto == {"area": "castle", "spawn": "barracks_gate"} and str(GameState.get_flag("castle_entry")) == "barracks", "说是来投伊薇特小姐的：走兵营侧门")
	GameState.pending_goto = {}
	r.start("blackheron", "herman")
	check(r.node_id == "greet_barracks", "赫尔曼：「伊薇特小姐的人从侧门放进来一个誓剑」")
	ch1_state("deliver", 8)
	GameState.set_flag("offer_camp_met")
	GameState.silver = 25
	r.start("deepmarsh", "offer_camp")
	r.choose(r.options().map(func(o): return o.text).find("你们的船进得了水门吗？"))
	r.choose(0)
	check(GameState.pending_goto.get("spawn") == "water_gate" and GameState.silver == 5 and str(GameState.get_flag("castle_entry")) == "offer", "奥弗的船：20 枚银币送到水门")
	GameState.pending_goto = {}
	ch1_state("deliver", 9)
	GameState.set_flag("ch1_letter")
	GameState.set_flag("heard_causeway")
	r.start("reedwharf", "tobin")
	var ot := r.options().map(func(o): return o.text)
	r.start("reedwharf", "ivette_veteran")
	ot += r.options().map(func(o): return o.text)
	check(not ot.has("你说的泥炭船——能捎我进堡吗？") and not ot.has("堡门不让我进。"), "有引荐信的人：托宾和老兵不提偷偷进堡的事")
	GameState.new_game()


## 黑鹭堡大厅（路线图 4.5b；STORY.md 4.5 第 4 步「两位继承人各找你谈」）：从庭院的大厅门进来、主线推进到「听两位继承人」；人都站得稳、走得到；
## 阿尔里克托你偷账、伊薇特托你收编无旗者（两条支线开始）；两边都听完，不管先后，主线推进到「去看家主」；埃德里克只在序章「交出」时在；出门回庭院
func test_hall() -> void:
	Settings.set_value("third_person", false)
	wipe_test_saves()
	check(Areas.known("hall") and Areas.is_indoor("hall") and Saves.SCENE_NAMES.has("hall") and Areas.spawn("hall", "front") is Transform3D and Areas.spawn("castle", "hall_door") is Transform3D,
		"区域登记：大厅是室内区域，门口和庭院的大厅门口都是出生点")
	check(AreaMap.region_of("hall") == "marsh" and AreaMap.exits("hall").size() == 1, "地图：大厅在「鹭沼一带」，一个出口")
	ch1_state("extort", 10)
	GameState.pending_load = {"scene": "hall", "spawn": "front", "player": {}}
	var main := await make_main(false)
	await physics(2)
	check(main._npc_by_dialogue("edric_hall") == null, "序章「勒索」：埃德里克不在大厅（只有「交出」时在）")
	await free_main(main)
	# —— 序章「交出」、堡门进来：先阿尔里克后伊薇特
	ch1_state("deliver", 11)
	for f in ["ch1_victor_done", "castle_admitted", "herman_met"]:
		GameState.set_flag(f)
	GameState.set_flag("castle_entry", "gate")
	GameState.start_quest("ch1_main", "to_hall")
	GameState.daypart = "day"
	GameState.pending_load = {"scene": "castle", "spawn": "gate", "player": {}}
	main = await make_main(false)
	await physics(3)
	main = await fl_go(main, "hall")
	await physics(3)
	check(main.area == "hall" and main.arrived_by == "front" and GameState.quest_stage("ch1_main") == "hear_heirs", "从庭院进了大厅：主线推进到「听两位继承人」（%s）" % GameState.quest_stage("ch1_main"))
	var exit: Door = main.find_children("*", "Door", true, false).filter(func(d): return d.to_area == "castle")[0]
	var emid: Vector3 = exit.global_transform * Vector3(exit.width * 0.5, 0, 0)
	check(exit.to_spawn == "hall_door" and Vector2(emid.x, emid.z).distance_to(AreaMap.exits("hall")[0].at) < 0.3 and AreaMap.exits("hall")[0].name == exit.display_name, "出口的门和地图出口对得上")
	var people := main.find_children("Npc_*", "Npc", true, false)
	var bad: Array = people.filter(func(n): return not stands_clear(n)).map(func(n): return n.display_name)
	check(people.size() == 4 + Hall.GUARDS.size() and bad.is_empty(), "大厅里：阿尔里克、信使、伊薇特、埃德里克和卫兵，都站得稳（%s）" % str(bad))
	var alric: Npc = main._npc_by_dialogue("alric")
	var ivette: Npc = main._npc_by_dialogue("ivette")
	var room := Rect2(-Hall.W * 0.5, -Hall.D * 0.5, Hall.W, Hall.D)
	check(walk_reach(main, Hall.SPAWNS.front[0], alric.position, 1.4, room) and walk_reach(main, Hall.SPAWNS.front[0], ivette.position, 1.4, room)
		and walk_reach(main, Hall.SPAWNS.front[0], main._npc_by_dialogue("edric_hall").position, 1.4, room), "从门口走得到阿尔里克、伊薇特和埃德里克")
	for v in [[1, alric], [2, ivette]]:
		main.set_view(v[0])
		await physics(3)
		main.player.interactor.refresh()
		check(main.player.interactor.target == v[1], "%d 号机位正对着%s（冒烟测试用）" % [v[0], v[1].display_name])
	check(await fl_say(main, "hall", "alric", ["您打算怎么守北境？", "一半的兵权，等于把烽燧交出去。", "那您要我做什么？", "我会考虑。"])
		and GameState.has_flag("ledger_asked") and GameState.quest_stage("ch1_ledger") == "get_ledger" and GameState.quest_stage("ch1_main") == "hear_heirs",
		"阿尔里克：托你去账房偷账（支线开始）；伊薇特还没听，主线不动")
	check(await fl_say(main, "hall", "ivette", ["您打算怎么守北境？", "您这是在拿全家冒险。", "那您要我做什么？", "我会考虑。"])
		and GameState.has_flag("outlaws_asked") and GameState.quest_stage("ch1_outlaws") == "talk_offer" and GameState.quest_stage("ch1_main") == "see_osric",
		"伊薇特：托你收编无旗者（支线开始）；两边都听完，主线推进到「去看家主」（%s）" % GameState.quest_stage("ch1_main"))
	check(GameState.has_flag("heirs_heard") and Castle.sickroom_open(), "两边都听完：病房的门推得开了（4.5c）")
	main.open_dialogue("hall", "alric", alric)
	await frames(1)
	check(main.dialogue.runner.node_id == "again" and main.dialogue.runner.options().any(func(o): return o.text == "账房那本账……"), "再找阿尔里克：问账的事")
	main.dialogue.close()
	check(await fl_say(main, "hall", "edric_hall", ["这不是我定的。", "……"]), "埃德里克（交出）：坐在窗边，不想多说")
	main.set_view(3)
	await physics(3)
	main = await fl_go(main, "castle")
	await physics(3)
	check(main.area == "castle" and main.arrived_by == "hall_door" and GameState.quest_stage("ch1_main") == "see_osric", "出门回到庭院的大厅门口，主线不倒退")
	await free_main(main)
	# —— 序章「放走」、兵营侧门进来：伊薇特认得你；先伊薇特后阿尔里克也一样推进；埃德里克不在
	ch1_state("release", 12)
	for f in ["ch1_victor_done", "castle_admitted", "herman_met"]:
		GameState.set_flag(f)
	GameState.set_flag("castle_entry", "barracks")
	GameState.start_quest("ch1_main", "to_hall")
	GameState.pending_load = {"scene": "hall", "spawn": "front", "player": {}}
	main = await make_main(false)
	await physics(3)
	check(main._npc_by_dialogue("edric_hall") == null and main.find_children("Npc_*", "Npc", true, false).size() == 3 + Hall.GUARDS.size(), "序章没交出埃德里克：大厅里没有他")
	main.open_dialogue("hall", "ivette", main._npc_by_dialogue("ivette"))
	await frames(1)
	check(main.dialogue.runner.node_id == "greet_barracks", "伊薇特：认出你是从她兵营侧门进来的")
	main.dialogue.close()
	await frames(2)
	check(await fl_say(main, "hall", "ivette", ["您打算怎么守北境？", "那您要我做什么？", "我会考虑。"]) and GameState.quest_stage("ch1_outlaws") == "talk_offer"
		and GameState.quest_stage("ch1_main") == "hear_heirs", "先听伊薇特：支线开始，阿尔里克还没听，主线不动")
	check(await fl_say(main, "hall", "alric", ["您打算怎么守北境？", "那您要我做什么？", "那是揭您妹妹的短。"]) and GameState.quest_stage("ch1_ledger") == "get_ledger"
		and GameState.quest_stage("ch1_main") == "see_osric", "再听阿尔里克（问他揭妹妹的短，没选「我会考虑」就关掉）：主线一样推进到「去看家主」")
	GameState.quests.ch1_main.stage = "meet_herman"                 # 借一个不是「听两位继承人」的阶段，代替以后（4.5c 起）的阶段
	check(await fl_say(main, "hall", "alric", ["账房那本账……", "我会考虑。"]) and GameState.quest_stage("ch1_main") == "meet_herman", "主线不在「听两位继承人」时再找他们说话，主线不会被改（以后不倒退）")
	await free_main(main)
	GameState.new_game()


## 黑鹭堡的病房、兵营、水门、账房（路线图 4.5c；STORY.md 4.5 第 3 步「见医师玛尔塔；家主昏睡」）：两位继承人都托过你以后病房推得开、伊薇特见过你（或从侧门进来）以后兵营推得开，
## 地图出口跟着门走；玛尔塔让你看一眼昏睡的家主（主线推进到「等黄昏」）、托你采白芦根；家主躺在床上；兵营的军士；守水门的老头（夜里只有他、泥炭船回芦栈村）；账房还锁着、赫尔曼不给钥匙
func test_keep() -> void:
	Settings.set_value("third_person", false)
	wipe_test_saves()
	check(["sickroom", "barracks"].all(func(a): return Areas.known(a) and Areas.is_indoor(a) and Saves.SCENE_NAMES.has(a) and Areas.spawn(a, "front") is Transform3D)
		and Areas.spawn("castle", "sickroom_door") is Transform3D and Areas.spawn("castle", "barracks_door") is Transform3D and AreaMap.region_of("sickroom") == "marsh" and AreaMap.region_of("barracks") == "marsh",
		"区域登记：病房、兵营是室内区域，在「鹭沼一带」；庭院里两个门口是出生点")
	# —— 还没听完两位继承人、伊薇特没见过：病房、兵营都关着
	ch1_state("deliver", 13)
	for f in ["ch1_victor_done", "castle_admitted", "herman_met", "alric_met", "ledger_asked"]:
		GameState.set_flag(f)
	GameState.set_flag("castle_entry", "gate")
	GameState.start_quest("ch1_main", "hear_heirs")
	GameState.start_quest("ch1_ledger")
	GameState.daypart = "day"
	GameState.pending_load = {"scene": "castle", "spawn": "gate", "player": {}}
	var main := await make_main(false)
	await physics(3)
	var doors: Array = main.find_children("*", "Door", true, false)
	var locked_names: Array = doors.filter(func(d): return d.locked).map(func(d): return d.display_name)
	check(["病房", "兵营", "账房"].all(func(n): return n in locked_names) and AreaMap.exits("castle").size() == 2, "听完两位继承人之前：病房、兵营、账房都关着，地图上只有堡门和大厅（%s）" % str(locked_names))
	var ct: Door = doors.filter(func(d): return d.display_name == "账房")[0]
	check(ct.locked_text.contains("赫尔曼"), "账房的门：两道锁，钥匙在赫尔曼那儿")
	check(await fl_say(main, "blackheron", "herman", ["账房的钥匙……"], true) and main.dialogue.runner.node_id == "ledger_key", "阿尔里克托过你以后问赫尔曼要账房的钥匙：他不给（怎么拿到在 4.7）")
	main.dialogue.close()
	await frames(2)
	# 守水门的老头：夜里只有他一个人守；能坐泥炭船回芦栈村
	var keeper: Npc = main._npc_by_dialogue("water_keeper")
	check(keeper != null and stands_clear(keeper), "守水门的老头有对话了，站得稳")
	check(await fl_say(main, "blackheron", "water_keeper", ["这道水门夜里谁守？", "……"]) and GameState.has_flag("water_keeper_met"),
		"守水门的老头：夜里水门只有他一个人守")
	var rr := [0]
	main.reload_requested.connect(func(): rr[0] += 1)
	check(await fl_say(main, "blackheron", "water_keeper", ["能坐泥炭船出去吗？", "（上船回芦栈村）"]), "坐泥炭船回芦栈村")
	await seconds(0.6)
	check(rr[0] == 1 and GameState.pending_load.get("scene") == "marsh" and GameState.pending_load.get("spawn") == "reedwharf", "泥炭船：对话一关就回到芦栈村（%s）" % str(GameState.pending_load))
	await free_main(main)
	# —— 两位继承人都托过你：病房、兵营都推得开，地图出口对得上，出生点在门前
	GameState.set_flag("ivette_met")
	GameState.set_flag("outlaws_asked")
	GameState.start_quest("ch1_outlaws")
	GameState.set_stage("ch1_main", "see_osric")
	GameState.set_flag("heirs_heard")
	GameState.pending_load = {"scene": "castle", "spawn": "gate", "player": {}}
	main = await make_main(false)
	await physics(3)
	doors = main.find_children("*", "Door", true, false)
	var open: Array = doors.filter(func(d): return d.to_area != "" and not d.locked)
	var ex: Array = AreaMap.exits("castle")
	var ok := open.size() == 4 and ex.size() == 4
	for d in open:
		var mid: Vector3 = d.global_transform * Vector3(d.width * 0.5, 0, 0)
		ok = ok and ex.filter(func(e): return e.name == d.display_name and e.to == d.to_area and Vector2(mid.x, mid.z).distance_to(e.at) < 0.3).size() == 1
		if d.to_area in ["sickroom", "barracks"]:
			var sp: Transform3D = Areas.spawn("castle", d.to_area + "_door")
			var away := Vector2(sp.origin.x - mid.x, sp.origin.z - mid.z)
			var look := -sp.basis.z
			ok = ok and away.length() > 1.0 and away.length() < 1.8 and away.normalized().dot(Vector2(look.x, look.z)) > 0.9
	check(ok, "病房、兵营的门推得开了，和地图出口对得上；出来时站在门前、背对门（%s）" % str(open.map(func(d): return d.display_name)))
	# 病房：玛尔塔、床上昏睡的家主
	main = await fl_go(main, "sickroom")
	await physics(3)
	var marta: Npc = main._npc_by_dialogue("marta")
	var osric := main.world.get_node_or_null("Npc_osric") as Npc
	check(main.area == "sickroom" and main.arrived_by == "front" and marta != null and stands_clear(marta), "进了病房：玛尔塔站在床边（站得稳）")
	check(osric != null and osric.lying and absf(osric.global_position.y - Sickroom.BED_TOP) < 0.01 and Sickroom.BED.has_point(flat(osric.global_position)) and osric.verb == "看看",
		"家主奥斯瑞克躺在床上（只能看看）")
	var room := Rect2(-Sickroom.W * 0.5, -Sickroom.D * 0.5, Sickroom.W, Sickroom.D)
	check(walk_reach(main, Sickroom.SPAWNS.front[0], marta.position, 1.4, room) and walk_reach(main, Sickroom.SPAWNS.front[0], osric.position, 1.6, room), "从门口走得到玛尔塔和床边")
	for v in [[1, marta], [2, osric]]:
		main.set_view(v[0])
		await physics(3)
		main.player.interactor.refresh()
		check(main.player.interactor.target == v[1], "%d 号机位正对着%s（冒烟测试用）" % [v[0], v[1].display_name])
	var yaw := osric.rotation.y
	var said: Dictionary = osric.interact(main.player)
	check(said.get("kind") == "npc" and str(said.get("speech", "")).contains("睡着") and is_equal_approx(osric.rotation.y, yaw), "看看家主：他睡着（不转身）")
	check(await fl_say(main, "sickroom", "marta", ["（走到床边看看家主）", "好，黄昏再来。"]) and GameState.has_flag("osric_seen") and GameState.quest_stage("ch1_main") == "wait_dusk",
		"玛尔塔让你看一眼家主：主线推进到「等黄昏」（%s）" % GameState.quest_stage("ch1_main"))
	check(await fl_say(main, "sickroom", "marta", ["家主怎么样了？", "有什么能帮上他？", "……"]) and not GameState.quest_active("ch1_whitereed"), "玛尔塔说起白芦根，没答应就不接支线")
	check(await fl_say(main, "sickroom", "marta", ["家主怎么样了？", "有什么能帮上他？", "我去试试。"]) and GameState.quest_stage("ch1_whitereed") == "gather", "答应了：支线「白芦根」开始")
	var r := DialogueRunner.new()
	r.start("sickroom", "marta")
	var ot: Array = r.options().map(func(o): return o.text)
	check(not ot.has("（走到床边看看家主）") and ot.has("（再看看家主）") and ot.has("白芦根……"), "看过以后：不会再推一次主线；能再看看、问白芦根（%s）" % str(ot))
	main = await fl_go(main, "castle")
	await physics(3)
	check(main.area == "castle" and main.arrived_by == "sickroom_door" and GameState.quest_stage("ch1_main") == "wait_dusk", "出病房回到塔楼门前，主线不倒退")
	# 兵营：军士和三个兵
	main = await fl_go(main, "barracks")
	await physics(3)
	var people := main.find_children("Npc_*", "Npc", true, false)
	var bad: Array = people.filter(func(n): return not stands_clear(n)).map(func(n): return n.display_name)
	check(main.area == "barracks" and people.size() == 1 + Barracks.SOLDIERS.size() and bad.is_empty(), "进了兵营：军士和 %d 个兵，都站得稳（%s）" % [Barracks.SOLDIERS.size(), str(bad)])
	var sgt: Npc = main._npc_by_dialogue("sergeant")
	var hall_rect := Rect2(-Barracks.W * 0.5, -Barracks.D * 0.5, Barracks.W, Barracks.D)
	check(people.all(func(n): return walk_reach(main, Barracks.SPAWNS.front[0], n.position, 1.4, hall_rect)), "从门口走得到兵营里每个人")
	main.set_view(1)
	await physics(3)
	main.player.interactor.refresh()
	check(main.player.interactor.target == sgt, "1 号机位正对着军士（冒烟测试用）")
	check(await fl_say(main, "barracks", "sergeant", ["小姐让我去收编沼地里那伙人。", "记住了。"]) and GameState.has_flag("sergeant_met"), "军士：伊薇特托过你收编无旗者，他说灰手要的不只是钱")
	main = await fl_go(main, "castle")
	await physics(3)
	check(main.area == "castle" and main.arrived_by == "barracks_door", "出兵营回到兵营门前")
	await free_main(main)
	# —— 从兵营侧门进来的：还没见伊薇特，兵营也推得开；玛尔塔在主线没到「去看家主」时不让看
	ch1_state("release", 14)
	GameState.set_flag("castle_entry", "barracks")
	check(Castle.barracks_open() and not Castle.sickroom_open(), "从兵营侧门进来的：兵营推得开，病房还关着")
	GameState.set_flag("side_gate_used")
	GameState.set_flag("castle_entry", "offer")
	check(Castle.barracks_open(), "后来又坐奥弗的船进来（castle_entry 改了）：兵营照样推得开（审查）")
	GameState.set_flag("ledger_asked")
	GameState.set_flag("outlaws_asked")
	check(Castle.sickroom_open(), "4.5b 时的旧存档（两位继承人都托过、没有 heirs_heard 旗标）：病房也推得开（审查）")
	GameState.start_quest("ch1_main", "hear_heirs")
	r.start("sickroom", "marta")
	check(not r.options().any(func(o): return o.text == "（走到床边看看家主）"), "主线没到「去看家主」：玛尔塔不让走到床边")
	GameState.new_game()


## NPC 作息（路线图 4.6；core/schedule.gd、data/schedules.json、对话节点的 text_if）：同一个人按时段换地方、换开场白。
## 伊薇特黄昏、夜里在兵营（没见过她的人兵营也推得开）；赫尔曼黄昏在大厅门口、夜里守堡门；托宾黄昏、夜里在客栈的火塘边；剧情推到别的时段时人当场换地方
func test_schedule() -> void:
	Settings.set_value("third_person", false)
	wipe_test_saves()
	check(Schedule.validate().is_empty(), "作息表：区域、站位、时段、名字都对（%s）" % str(Schedule.validate()))
	check(DialogueRunner.validate({"start": "a", "nodes": {"a": {"text": "x", "text_if": [{"text": "y"}], "options": [{"text": "走", "end": true}]}}}).size() > 0,
		"text_if 没写条件：校验报错")
	var r := DialogueRunner.new()
	GameState.new_game()
	GameState.chapter = 1
	GameState.daypart = "day"
	r.start("hall", "ivette")
	var day_text := r.text()
	GameState.new_game()                           # 开场白节点会设 ivette_met：重来一遍才又从 greet 开始
	GameState.chapter = 1
	GameState.daypart = "dusk"
	r.start("hall", "ivette")
	check(day_text.contains("壁炉") and r.text().contains("长凳不分高低") and r.node_id == "greet", "同一个节点按时段换开场白：白天在壁炉前，黄昏在兵营的长桌边（选项不变；%s / %s / %s）" % [r.node_id, day_text.left(12), r.text().left(30)])
	check(Schedule.area_of("ivette", "day") == "hall" and Schedule.area_of("ivette", "dusk") == "barracks" and Schedule.area_of("tobin", "night") == "inn" and Schedule.area_of("herman", "dawn") == "castle",
		"作息：没写的时段在老地方")
	GameState.chapter = 0
	check(Schedule.area_of("tobin", "night") == "marsh", "序章（夜里）：还没到第一章，托宾在老地方")
	GameState.chapter = 1
	# —— 黄昏的黑鹭堡：赫尔曼站到大厅门口；没见过伊薇特、从堡门进来的也推得开兵营
	ch1_state("deliver", 15)
	for f in ["ch1_victor_done", "castle_admitted", "herman_met", "alric_met", "ledger_asked"]:
		GameState.set_flag(f)
	GameState.set_flag("castle_entry", "gate")
	GameState.start_quest("ch1_main", "hear_heirs")
	GameState.daypart = "dusk"
	GameState.pending_load = {"scene": "castle", "spawn": "gate", "player": {}}
	var main := await make_main(false)
	await physics(3)
	var herman: Npc = main._npc_by_dialogue("herman")
	var at: Array = Schedule.slot("herman").pos
	check(herman != null and herman.position.distance_to(Vector3(at[0], at[1], at[2])) < 0.01 and stands_clear(herman), "黄昏：赫尔曼站在大厅门口的火盆边（站得稳）")
	check(Castle.barracks_open() and AreaMap.exits("castle").any(func(e): return e.to == "barracks") and main.find_children("*", "Door", true, false).any(func(d): return d.to_area == "barracks" and not d.locked),
		"黄昏：伊薇特在兵营，没见过她的人兵营也推得开（不然找不到她，主线卡住）")
	main.open_dialogue("blackheron", "herman", herman)
	await frames(1)
	check(main.dialogue.runner.node_id == "again" and main.dialogue.runner.text().contains("火盆"), "赫尔曼黄昏的开场白：「站在大厅门口的火盆边」")
	main.dialogue.close()
	await frames(2)
	# 大厅：伊薇特不在；兵营：伊薇特在长桌边
	main = await fl_go(main, "hall")
	await physics(3)
	check(main._npc_by_dialogue("ivette") == null and main._npc_by_dialogue("alric") != null and main.world.get_node_or_null("Npc_ivette") == null, "黄昏的大厅：伊薇特不在（去兵营了），阿尔里克还在")
	main = await fl_go(main, "castle")
	await physics(3)
	main = await fl_go(main, "barracks")
	await physics(3)
	var ivette: Npc = main._npc_by_dialogue("ivette")
	var room := Rect2(-Barracks.W * 0.5, -Barracks.D * 0.5, Barracks.W, Barracks.D)
	check(main.area == "barracks" and ivette != null and ivette.dialogue_area == "hall" and stands_clear(ivette) and walk_reach(main, Barracks.SPAWNS.front[0], ivette.position, 1.4, room),
		"黄昏的兵营：伊薇特在长桌边（站得稳、走得到，对话还是她那套）")
	check(await fl_say(main, "hall", "ivette", ["您打算怎么守北境？", "那您要我做什么？", "我会考虑。"]) and GameState.quest_stage("ch1_main") == "see_osric" and GameState.has_flag("heirs_heard"),
		"在兵营听完伊薇特：主线照样推进到「去看家主」")
	await free_main(main)
	# —— 夜里：赫尔曼守堡门；托宾在客栈火塘边、村里泥炭场没有他
	GameState.daypart = "night"
	GameState.pending_load = {"scene": "castle", "spawn": "gate", "player": {}}
	main = await make_main(false)
	await physics(3)
	herman = main._npc_by_dialogue("herman")
	at = Schedule.slot("herman").pos
	check(herman.position.distance_to(Vector3(at[0], at[1], at[2])) < 0.01 and stands_clear(herman), "夜里：赫尔曼守在堡门里（站得稳）")
	await main.set_daypart("day", false)
	await frames(3)
	check(herman.position.distance_to(Castle.HERMAN[2]) < 0.01 and absf(herman.rotation.y - float(Castle.HERMAN[3])) < 0.01, "天亮了（同一次进场里时段回到白天）：赫尔曼回到井边（审查）")
	await main.set_daypart("night", false)
	await frames(3)
	check(main.world.find_children("Npc_herman", "Npc", true, false).size() == 1, "时段换来换去：赫尔曼只有一个")
	var wk := _runner_text("blackheron", "water_keeper")
	check(wk.contains("提着灯"), "守水门的老头夜里的开场白（%s / %s）" % [GameState.daypart, wk.left(16)])
	await free_main(main)
	GameState.daypart = "dusk"
	GameState.pending_load = {"scene": "inn", "spawn": "front", "player": {}}
	main = await make_main(false)
	await physics(3)
	var tobin: Npc = main._npc_by_dialogue("tobin")
	var inn_room := Rect2(-Inn.W * 0.5, -Inn.D * 0.5, Inn.W, Inn.D)
	check(tobin != null and tobin.dialogue_area == "reedwharf" and stands_clear(tobin) and walk_reach(main, Inn.SPAWNS.front[0], tobin.position, 1.4, inn_room),
		"黄昏的客栈：托宾收工了，坐在火塘边（站得稳、走得到）")
	main.open_dialogue("reedwharf", "tobin", tobin)
	await frames(1)
	check(main.dialogue.runner.text().contains("收工了"), "托宾黄昏的开场白：「收工了」")
	main.dialogue.close()
	await free_main(main)
	GameState.pending_load = {"scene": "marsh", "spawn": "reedwharf", "player": {}}
	main = await make_main(false)
	await physics(3)
	check(main._npc_by_dialogue("tobin") == null and main._npc_by_dialogue("boatman") != null, "黄昏的村里：泥炭场没有托宾（在客栈），渡工还在码头")
	await free_main(main)
	# —— 剧情把时段推到黄昏：人当场换地方
	ch1_state("deliver", 17)
	GameState.set_flag("castle_admitted")
	GameState.daypart = "day"
	GameState.pending_load = {"scene": "hall", "spawn": "front", "player": {}}
	main = await make_main(false)
	await physics(3)
	check(main._npc_by_dialogue("ivette") != null, "白天的大厅：伊薇特在壁炉前")
	await main.set_daypart("dusk", false)
	await frames(3)
	check(GameState.daypart == "dusk" and main._npc_by_dialogue("ivette") == null and main._npc_by_dialogue("alric") != null, "剧情推到黄昏：伊薇特当场离开大厅")
	await free_main(main)
	GameState.daypart = "day"
	GameState.pending_load = {"scene": "barracks", "spawn": "front", "player": {}}
	main = await make_main(false)
	await physics(3)
	check(main._npc_by_dialogue("ivette") == null, "白天的兵营：伊薇特不在")
	await main.set_daypart("dusk", false)
	await frames(3)
	var iv: Array = main.world.find_children("Npc_ivette", "Npc", true, false)
	check(iv.size() == 1 and stands_clear(iv[0]), "在兵营里等到黄昏：伊薇特走进来，只有一个、站得稳")
	await free_main(main)
	GameState.new_game()


func _runner_text(file: String, id: String) -> String:
	var r := DialogueRunner.new()
	r.start(file, id)
	return r.text()


## 皮毛税账册（路线图 4.7a；STORY.md 4.7「账房上锁：找赫尔曼要钥匙（声望或口才）、或趁夜里撬窗（被看见就闹大）；交给阿尔里克 / 交给伊薇特 / 自己留着」）：
## 窄巷里的小窗走得到、对得准；赫尔曼没说动就不能再问；撬窗进去（白天难度 15、夜里 10）、拿到账册主线支线推进；交给伊薇特（她扔进火里）；
## 瓦伦家信得过你时赫尔曼直接给钥匙、账房的门推得开、交给阿尔里克（他交给信使）；撬窗被抓：窗钉死、支线失败、声望下降、钥匙也要不到了
func test_ledger() -> void:
	Settings.set_value("third_person", false)
	wipe_test_saves()
	check(Areas.known("counting") and Areas.is_indoor("counting") and Areas.spawn("counting", "window") is Transform3D and Areas.spawn("castle", "counting_door") is Transform3D
		and not GameState.item("fur_ledger").is_empty() and not GameState.item("counting_key").is_empty() and AreaMap.region_of("counting") == "marsh",
		"区域、物品登记：账房（室内，门口和窗下两个出生点）、皮毛税账册、账房钥匙")
	check(say_runner("counting_window", [], "blackheron") == "plain", "阿尔里克没托过你：那只是一扇闩着的小窗")
	# —— 撬窗进去，交给伊薇特
	ch1_state("deliver", 21)
	for f in ["ch1_victor_done", "castle_admitted", "herman_met", "alric_met", "ivette_met", "ledger_asked"]:
		GameState.set_flag(f)
	GameState.set_flag("castle_entry", "gate")
	GameState.start_quest("ch1_main", "hear_heirs")
	GameState.start_quest("ch1_ledger")
	GameState.daypart = "day"
	GameState.pending_load = {"scene": "castle", "spawn": "gate", "player": {}}
	var main := await make_main(false)
	await physics(3)
	var win := main.world.get_node_or_null("LedgerWindow") as Fixture
	var yard := Rect2(-Castle.HW, -Castle.HD, Castle.HW * 2.0, Castle.HD * 2.0)
	check(win != null and walk_reach(main, Castle.SPAWNS.gate[0], Vector3(Castle.LEDGER_WINDOW.x, 0, Castle.LEDGER_WINDOW.z), 1.0, yard), "从堡门走得到塔楼和账房之间窄巷里那扇小窗")
	main.player.global_position = Vector3(Castle.LEDGER_WINDOW.x, 0.05, Castle.LEDGER_WINDOW.z - 0.8)
	main.player.rotation.y = PI
	await physics(3)
	main.player.interactor.refresh()
	check(main.player.interactor.target == win, "站在窄巷里面朝小窗：对得准（「看看 · 账房的小窗」）")
	GameState.checks["herman_key"] = false
	check(await fl_say(main, "blackheron", "herman", ["账房的钥匙……", "家主醒的时候不多。他要问账，总不能等人去翻你的钥匙串——让我先替他把账拿出来。"], true) and main.dialogue.runner.node_id == "key_no"
		and GameState.has_flag("herman_key_refused") and not GameState.has_item("counting_key"), "口才没说动赫尔曼：不给钥匙")
	main.dialogue.close()
	await frames(2)
	var r := DialogueRunner.new()
	r.start("blackheron", "herman")
	r.choose(r.options().map(func(o): return o.text).find("账房的钥匙……"))
	check(r.options().size() == 1, "没说动就不能再问（只剩「……」）")
	GameState.checks["ledger_window_day"] = true
	var rr := [0]
	main.reload_requested.connect(func(): rr[0] += 1)
	check(await fl_say(main, "blackheron", "counting_window", ["（趁院子里没人注意，撬开百叶）", "（爬进账房）"]) and GameState.has_flag("ledger_window"), "撬开百叶（潜行检定）")
	await seconds(0.6)
	check(rr[0] == 1 and GameState.pending_load.get("scene") == "counting" and GameState.pending_load.get("spawn") == "window", "爬进账房：落在窗下")
	main = await reload_main(main)
	await physics(3)
	var ledger: Array = main.find_children("*", "Pickup", true, false).filter(func(p): return p.item_id == "fur_ledger")
	var room := Rect2(-Counting.W * 0.5, -Counting.D * 0.5, Counting.W, Counting.D)
	check(main.area == "counting" and main.arrived_by == "window" and ledger.size() == 1 and walk_reach(main, Counting.SPAWNS.window[0], ledger[0].global_position, 1.6, room), "进了账房：写字台上摊着账册，从窗下走得到")
	main.set_view(1)
	await physics(3)
	main.player.interactor.refresh()
	check(main.player.interactor.target == ledger[0], "1 号机位正对着写字台上的账册（冒烟测试用）")
	main.player.interactor.use()
	await frames(2)
	check(GameState.has_item("fur_ledger") and GameState.quest_stage("ch1_ledger") == "deliver", "拿到账册：支线推进到「交给谁」（%s）" % GameState.quest_stage("ch1_ledger"))
	main = await fl_go(main, "castle")
	await physics(3)
	var cdoor: Door = main.find_children("*", "Door", true, false).filter(func(d): return d.display_name == "账房")[0]
	check(main.arrived_by == "counting_door" and cdoor.locked and not AreaMap.exits("castle").any(func(e): return e.to == "counting"), "从里面推门出来，站在账房门前；没有钥匙，外面的门还锁着")
	check(say_runner("counting_window", [], "blackheron") == "done", "账册到手以后：窗户用不着了")
	main = await fl_go(main, "hall")
	await physics(3)
	check(await fl_say(main, "hall", "ivette", ["阿尔里克让我去账房拿皮毛税的账。", "……"]) and GameState.has_flag("ivette_knows_ledger"), "告诉伊薇特：她要你先给她")
	var eld := GameState.get_rep("eld")
	check(await fl_say(main, "hall", "ivette", ["账册在我手里。", "……"]) and str(GameState.get_flag("ch1_ledger")) == "ivette" and not GameState.has_item("fur_ledger")
		and GameState.quest_done("ch1_ledger") and GameState.get_rep("eld") == eld + 10, "交给伊薇特：她扔进壁炉，支线做完，厄尔德家 +10")
	await free_main(main)
	# —— 瓦伦家信得过你：赫尔曼直接给钥匙，门推得开，交给阿尔里克
	ch1_state("deliver", 22)
	for f in ["ch1_victor_done", "castle_admitted", "herman_met", "alric_met", "ledger_asked"]:
		GameState.set_flag(f)
	GameState.change_rep("valen", 25 - GameState.get_rep("valen"))
	GameState.start_quest("ch1_main", "hear_heirs")
	GameState.start_quest("ch1_ledger")
	check(say_runner("herman", ["账房的钥匙……", "维克托大人让我替他照看家主。瓦伦家的人信得过我。"], "blackheron") == "key_trust" and GameState.has_item("counting_key"), "瓦伦家声望 25：赫尔曼直接给钥匙")
	GameState.pending_load = {"scene": "castle", "spawn": "gate", "player": {}}
	main = await make_main(false)
	await physics(3)
	var ex: Array = AreaMap.exits("castle").filter(func(e): return e.to == "counting")
	cdoor = main.find_children("*", "Door", true, false).filter(func(d): return d.display_name == "账房")[0]
	var mid: Vector3 = cdoor.global_transform * Vector3(cdoor.width * 0.5, 0, 0)
	check(not cdoor.locked and ex.size() == 1 and Vector2(mid.x, mid.z).distance_to(ex[0].at) < 0.3, "有钥匙：账房的门推得开，和地图出口对得上")
	main = await fl_go(main, "counting")
	await physics(3)
	ledger = main.find_children("*", "Pickup", true, false).filter(func(p): return p.item_id == "fur_ledger")
	check(main.area == "counting" and main.arrived_by == "front" and ledger.size() == 1, "从门进了账房")
	check(say_runner("counting_window", [], "blackheron") == "keyed", "有钥匙的人：用不着撬窗（审查：不然撬窗被抓会把支线弄坏）")
	main.set_view(1)
	await physics(3)
	main.player.interactor.refresh()
	main.player.interactor.use()
	await frames(2)
	check(GameState.has_item("fur_ledger") and GameState.quest_stage("ch1_ledger") == "deliver", "从门进来也拿得到账册")
	var sev := GameState.get_rep("severin")
	check(say_runner("alric", ["账册拿来了。"], "hall") == "ledger_alric" and str(GameState.get_flag("ch1_ledger")) == "alric" and GameState.get_rep("severin") == sev + 10 and GameState.quest_done("ch1_ledger"),
		"交给阿尔里克：他交给塞弗林家的信使，支线做完，塞弗林家 +10")
	r.start("hall", "alric")
	check(not r.options().any(func(o): return o.text == "账房那本账……"), "账册交出去以后：阿尔里克不再说「钥匙在赫尔曼那儿」")
	await free_main(main)
	GameState.pending_load = {"scene": "counting", "spawn": "front", "player": {}}
	main = await make_main(false)
	await physics(2)
	check(main.find_children("*", "Pickup", true, false).filter(func(p): return p.item_id == "fur_ledger").is_empty(), "账册交出去以后，账房里不会再有一本")
	await free_main(main)
	# —— 撬窗被抓
	ch1_state("release", 23)
	GameState.set_flag("ledger_asked")
	GameState.start_quest("ch1_ledger")
	var valen := GameState.get_rep("valen")
	GameState.checks["ledger_window_day"] = false
	check(say_runner("counting_window", ["（趁院子里没人注意，撬开百叶）"], "blackheron") == "caught" and GameState.has_flag("ledger_caught") and not GameState.quest_done("ch1_ledger")
		and GameState.quest_stage("ch1_ledger") == "caught"
		and GameState.get_rep("valen") == valen - 10 and str(GameState.get_flag("ch1_ledger")) == "caught", "撬窗被赫尔曼抓了个正着：支线停在「进不去了」（不算完成，审查）、瓦伦家 -10")
	check(say_runner("counting_window", [], "blackheron") == "nailed", "窗户钉死了")
	GameState.set_flag("herman_met")
	r.start("blackheron", "herman")
	r.choose(r.options().map(func(o): return o.text).find("账房的钥匙……"))
	check(r.text().contains("撬窗") and r.options().size() == 1, "再找赫尔曼要钥匙：「撬窗的人，还有脸来要钥匙？」")
	# 夜里：难度低一档的选项
	ch1_state("deliver", 24)
	GameState.set_flag("ledger_asked")
	GameState.daypart = "night"
	r.start("blackheron", "counting_window")
	var ot: Array = r.options().map(func(o): return o.text)
	check(ot.has("（摸黑撬开百叶）") and not ot.has("（趁院子里没人注意，撬开百叶）") and r.text().contains("黑着"), "夜里：摸黑撬窗（难度低一档）")
	GameState.new_game()


## 白芦根与埃德里克的婚事（路线图 4.7b；STORY.md 4.7）：白芦根只在玛尔塔托过你、还在「采」的时候长在鹭沼深处的泥滩上，采三株推进、交给玛尔塔做完；
## 埃德里克（只在序章「交出」时）想逃婚：找伊薇特（她答应退亲）→ 他提醒你水门；口才劝他留下（没劝动不能再试）；或者告诉阿尔里克
func test_errands() -> void:
	Settings.set_value("third_person", false)
	wipe_test_saves()
	check(not GameState.item("white_reed").is_empty() and GameState.quest_data().quests.has("ch1_wedding"), "登记：白芦根、支线「埃德里克的婚事」")
	# —— 白芦根
	ch1_state("deliver", 31)
	GameState.set_flag("ch1_victor_done")
	GameState.start_quest("ch1_main", "wait_dusk")
	GameState.daypart = "day"
	GameState.pending_load = {"scene": "marsh", "spawn": "reedwharf", "player": {}}
	var main := await make_main(false)
	await physics(2)
	check(main.find_children("WhiteReed_*", "Pickup", true, false).is_empty(), "玛尔塔还没托你：泥滩上没有白芦根")
	await free_main(main)
	GameState.start_quest("ch1_whitereed")
	GameState.pending_load = {"scene": "marsh", "spawn": "reedwharf", "player": {}}
	main = await make_main(false)
	await physics(2)
	var reeds: Array = main.find_children("WhiteReed_*", "Pickup", true, false)
	var on_mud := reeds.size() == MarshLayout.WHITE_REEDS.size()
	for rd in reeds:
		var xz := Vector2(rd.position.x, rd.position.z)
		on_mud = on_mud and MarshLayout.DEEP.any(func(f): return f[1] == "mud" and (f[2] as Rect2).grow(-1.0).has_point(xz))
		on_mud = on_mud and MarshLayout.DEEP_TREES.all(func(t): return xz.distance_to(t[0]) > 2.0) and absf(rd.position.y - MarshLayout.MUD_Y) < 0.01
	check(on_mud, "托过你以后：%d 株白芦根长在鹭沼深处的泥滩上（离枯树远）" % reeds.size())
	var first: Pickup = reeds[0]
	main.player.global_position = first.global_position + Vector3(0, 0.1, 1.2)
	main.player.rotation.y = 0.0
	main.player.pitch = -50.0
	main.player.head.rotation.x = deg_to_rad(-50.0)
	await physics(3)
	main.player.interactor.refresh()
	check(main.player.interactor.target == first, "站在泥里低头：对得准白芦根（「拾取 · 白芦根」）")
	main.player.interactor.use()
	await frames(2)
	check(GameState.inventory.count("white_reed") == 1 and GameState.quest_stage("ch1_whitereed") == "gather", "采了一株：还差两株")
	await free_main(main)
	GameState.pending_load = {"scene": "marsh", "spawn": "reedwharf", "player": {}}
	main = await make_main(false)
	await physics(2)
	reeds = main.find_children("WhiteReed_*", "Pickup", true, false)
	check(reeds.size() == MarshLayout.WHITE_REEDS.size() - 1, "再进鹭沼：采过的那株不再长，还剩 %d 株" % reeds.size())
	for k in [0, 1, 2]:
		var rd: Pickup = reeds[k]
		main.player.global_position = rd.global_position + Vector3(0, 0.1, 1.2)
		main.player.rotation.y = 0.0
		main.player.pitch = -50.0
		main.player.head.rotation.x = deg_to_rad(-50.0)
		await physics(3)
		main.player.interactor.refresh()
		main.player.interactor.use()
		await frames(2)
	check(GameState.quest_stage("ch1_whitereed") == "return" and GameState.inventory.count("white_reed") == 4, "又采了三株（多采了一株）：支线推进到「交给玛尔塔」")
	await free_main(main)
	GameState.pending_load = {"scene": "marsh", "spawn": "reedwharf", "player": {}}
	main = await make_main(false)
	await physics(2)
	check(main.find_children("WhiteReed_*", "Pickup", true, false).is_empty(), "采齐以后再来：泥滩上不再长（不会多采）")
	await free_main(main)
	GameState.set_flag("marta_met")
	var valen := GameState.get_rep("valen")
	check(say_runner("marta", ["白芦根采来了，三株。"], "sickroom") == "reed_done" and GameState.has_flag("ch1_herb") and GameState.quest_done("ch1_whitereed")
		and not GameState.has_item("white_reed") and GameState.get_rep("valen") == valen + 5, "交给玛尔塔：多采的也一起收下，支线做完（ch1_herb），瓦伦家 +5")
	# —— 埃德里克的婚事：找伊薇特
	ch1_state("deliver", 32)
	for f in ["ch1_victor_done", "castle_admitted", "herman_met", "alric_met", "ivette_met"]:
		GameState.set_flag(f)
	GameState.start_quest("ch1_main", "hear_heirs")
	GameState.pending_load = {"scene": "hall", "spawn": "front", "player": {}}
	main = await make_main(false)
	await physics(2)
	check(await fl_say(main, "hall", "edric_hall", ["你不想娶她。", "我去找伊薇特说说。她不会让王都的人拴住瓦伦家。", "等我消息。"]) and GameState.quest_stage("ch1_wedding") == "ask_ivette",
		"埃德里克：他不想娶，今晚之后自己走；你说去找伊薇特")
	check(await fl_say(main, "hall", "ivette", ["埃德里克不想娶塞弗林家的人。", "……"]) and GameState.has_flag("edric_ivette_promise") and GameState.quest_stage("ch1_wedding") == "tell_edric",
		"伊薇特：她当了家就退了这门亲事")
	var ar := DialogueRunner.new()
	ar.start("hall", "alric")
	check(not ar.options().any(func(o): return str(o.text).begins_with("埃德里克不想娶")), "伊薇特答应了以后：不能再去跟阿尔里克告状")
	check(await fl_say(main, "hall", "edric_hall", ["伊薇特答应了：她当了家，就退了这门亲事。", "记住了。"]) and str(GameState.get_flag("ch1_edric")) == "helped"
		and GameState.has_flag("edric_warned_water") and GameState.quest_done("ch1_wedding"), "告诉埃德里克：他提醒你水门（支线做完）")
	main.open_dialogue("hall", "edric_hall", main._npc_by_dialogue("edric_hall"))
	await frames(1)
	check(main.dialogue.runner.node_id == "after" and main.dialogue.runner.text().contains("点了点头"), "以后再找他：冲你点点头")
	main.dialogue.close()
	await free_main(main)
	# —— 劝他留下：没劝动不能再试；劝动了
	ch1_state("deliver", 33)
	GameState.checks["edric_persuade"] = false
	var persuade := "你走了，你父亲怎么跟塞弗林家交代？这门亲事能让霜渡镇过冬。"
	check(say_runner("edric_hall", ["你不想娶她。", persuade], "hall") == "stubborn" and GameState.has_flag("edric_stubborn"), "口才没劝动：他不听")
	var r := DialogueRunner.new()
	r.start("hall", "edric_hall")
	check(r.node_id == "again" and not r.options().any(func(o): return o.text == persuade), "没劝动就不能再劝（找伊薇特、告诉阿尔里克还行）")
	ch1_state("deliver", 34)
	GameState.checks["edric_persuade"] = true
	check(say_runner("edric_hall", ["你不想娶她。", persuade], "hall") == "persuaded" and str(GameState.get_flag("ch1_edric")) == "persuaded" and GameState.quest_done("ch1_wedding"),
		"劝动了：他留下（为了霜渡镇）")
	# —— 告诉阿尔里克
	ch1_state("deliver", 35)
	GameState.set_flag("alric_met")
	say_runner("edric_hall", ["你不想娶她。", "（不说话）"], "hall")
	var sev := GameState.get_rep("severin")
	check(say_runner("alric", ["埃德里克不想娶塞弗林家的人，打算今晚之后自己走。"], "hall") == "edric_report" and str(GameState.get_flag("ch1_edric")) == "reported"
		and GameState.get_rep("severin") == sev + 5 and GameState.quest_done("ch1_wedding"), "告诉阿尔里克：他让人看着埃德里克（塞弗林家 +5）")
	r.start("hall", "edric_hall")
	check(r.node_id == "after_reported", "埃德里克：「你去告诉了阿尔里克……你满意了？」")
	# 黄昏伊薇特在兵营：照样能找她说埃德里克的事
	ch1_state("deliver", 36)
	GameState.set_flag("ivette_met")
	say_runner("edric_hall", ["你不想娶她。", "我去找伊薇特说说。她不会让王都的人拴住瓦伦家。"], "hall")
	GameState.daypart = "dusk"
	GameState.pending_load = {"scene": "barracks", "spawn": "front", "player": {}}
	main = await make_main(false)
	await physics(2)
	check(await fl_say(main, "hall", "ivette", ["埃德里克不想娶塞弗林家的人。", "……"]) and GameState.has_flag("edric_ivette_promise"), "黄昏在兵营：照样能找伊薇特说埃德里克的事")
	await free_main(main)
	GameState.new_game()


## 背景音乐（路线图 M.1；core/music.gd、data/music.json、tools/compose_music.py）：曲目表对得上、每首能读、能循环、长度合理；区域和时段选曲；
## 换曲子交叉淡入淡出、同一首不重放；暂停菜单里的开关和音量管「Music」总线（「声音」关了也静音）；进区域、时段变了自动换曲；开场先听钟声
func test_music() -> void:
	Settings.set_value("third_person", false)
	wipe_test_saves()
	var tracks: Dictionary = Music.data.get("tracks", {})
	var bad := []
	for id in tracks:
		var s := load(str(tracks[id])) as AudioStreamOggVorbis
		if s == null or s.get_length() < 30.0 or s.get_length() > 120.0:
			bad.append(id)
	check(tracks.size() == 5 and bad.is_empty(), "五首曲子都能读、长度 30–120 秒（%s）" % str(bad))
	var unknown := []
	for a in Music.data.get("areas", {}):
		var v: Variant = Music.data.areas[a]
		var ids: Array = (v as Dictionary).values() if v is Dictionary else [v]
		if not Areas.known(str(a)) or ids.any(func(i): return not tracks.has(str(i))):
			unknown.append(a)
	check(unknown.is_empty() and Music.data.areas.size() >= 14, "区域表：区域都认识，曲目都存在（%s）" % str(unknown))
	check(Music.track_for("frostford", "night") == "night" and Music.track_for("frostford", "dawn") == "town" and Music.track_for("castle", "night") == "keep"
		and Music.track_for("marsh", "day") == "marsh" and Music.track_for("test_range", "day") == "", "选曲：霜渡镇夜里和白天不一样、黑鹭堡、鹭沼；测试场不放")
	Music.play("keep")
	var p: AudioStreamPlayer = Music.players[Music.active]
	check(Music.track == "keep" and p.playing and p.stream is AudioStreamOggVorbis and (p.stream as AudioStreamOggVorbis).loop and p.bus == "Master", "放「黑鹭堡」：走主总线、循环")
	check(AudioServer.get_bus_index("Music") < 0 and AudioServer.bus_count == 1, "不在运行时加总线（网页上加总线会让整个游戏没声音，上线后查出）")
	Music.play("keep")
	check(Music.players[Music.active] == p, "同一首不重放（换区域时接着放）")
	Music.play("marsh")
	await seconds(Music.FADE + 0.4)
	check(Music.track == "marsh" and Music.players[Music.active].playing and not p.playing, "换曲子：旧的淡出后停下，新的接上（%s / %s / %.1f dB）" % [Music.players[Music.active].playing, p.playing, p.volume_db])
	Music.play("keep")
	Music.play("marsh")
	Music.play("keep")
	await seconds(Music.FADE + 0.4)
	check(Music.track == "keep" and Music.players[Music.active].playing and Music.fades[Music.active] > 0.99, "很快地换来换去：最后那首照样在放（没被没跑完的淡出停掉）")
	var cur: AudioStreamPlayer = Music.players[Music.active]
	Settings.set_value("music_volume", 0.5)
	check(absf(cur.volume_db - linear_to_db(0.5)) < 0.05, "音乐音量 50%%：播放器 -6 dB（%.1f）" % cur.volume_db)
	Settings.set_value("music", false)
	check(cur.volume_db <= Music.SILENT_DB, "关掉背景音乐：静音")
	Settings.set_value("music", true)
	Settings.set_value("sound", false)
	check(cur.volume_db <= Music.SILENT_DB, "关掉「声音」：背景音乐也静音")
	Settings.set_value("sound", true)
	check(cur.volume_db > -7.0, "都打开：有声音")
	cur.stop()
	cur.finished.emit()
	check(cur.playing, "放完了（网页上的样本不循环时）：从头再放")
	Settings.set_value("music_volume", 0.6)
	# 战斗配乐（核对配乐与剧本）：开打换「battle」，打完 4 秒换回来；病房用安静的「night」
	check(Music.track_for("sickroom", "day") == "night", "病房（家主昏睡）：安静的「night」，不用带鼓点的「keep」")
	Music.stop_now()
	Music.play_area("tavern")
	Music.set_fighting(true, 0.25)
	check(Music.track == "battle" and Music.fighting, "开打：换「battle」")
	Music.set_fighting(false, 1.0)
	check(Music.track == "battle", "刚打完：先别换回去（敌人一会儿警觉一会儿不警觉时不来回切）")
	Music.play_area("tavern")
	check(Music.track == "battle", "打着的时候换区域 / 时段：不换曲子")
	Music.set_fighting(false, Music.CALM_DELAY)
	check(Music.track == "town" and not Music.fighting, "安静 4 秒以后：换回区域的曲子（酒馆：「town」）")
	# 进区域自动选曲；剧情改时段换曲
	ch1_state("deliver", 41)
	GameState.daypart = "day"
	GameState.pending_load = {"scene": "frostford", "spawn": "", "player": {}}
	var main := await make_main(false)
	await physics(2)
	check(Music.track == "town", "白天的霜渡镇：「town」（%s）" % Music.track)
	await main.set_daypart("night", false)
	await frames(2)
	check(Music.track == "night", "剧情推到夜里：换成「night」")
	main = await fl_go(main, "tavern")
	check(Music.track == "town", "进酒馆：「town」")
	await free_main(main)
	# 新游戏的开场：先听钟声（上一首淡出），管家喊人以后起「night」
	Music.play("keep")
	var skip: bool = Engine.get_meta("ic_skip_opening", false)
	Engine.set_meta("ic_skip_opening", false)
	GameState.new_game()
	main = await make_main(false)
	await physics(2)
	check(main.opening != null and Music.track == "", "新游戏的开场：上一首淡出，先听钟声（%s）" % Music.track)
	if main.opening != null:
		main.opening.called.emit()
		await frames(1)
	check(Music.track == "night", "管家喊人以后：「night」")
	await free_main(main)
	Engine.set_meta("ic_skip_opening", skip)
	GameState.new_game()


## 4.7c 沼地里的无旗者：伊薇特托你收编或赶走奥弗那伙人（ch1_outlaws），拉托宾的泥炭工（ch1_peat）
func outlaws_state(sd := 1) -> void:
	ch1_state("deliver", sd)                       # 序章和奥弗谈妥了（offer_left）：营地友善
	GameState.set_flag("outlaws_asked")
	GameState.start_quest("ch1_outlaws")


func test_outlaws() -> void:
	Settings.set_value("third_person", false)
	wipe_test_saves()
	# —— 伊薇特：营地的人说过「谁给的粮实在就跟谁」才给粮单，只给一次
	outlaws_state()
	GameState.set_flag("ivette_met")
	var r := DialogueRunner.new()
	r.start("hall", "ivette")
	r.choose(r.options().map(func(o): return str(o.text)).find("沼地那伙人……"))
	check(r.node_id == "ask_again" and not r.options().any(func(o): return str(o.text).begins_with("他们说")), "伊薇特：营地的人还没开价，不给粮单")
	GameState.set_flag("offer_camp_terms")
	check(say_runner("ivette", ["沼地那伙人……", "他们说，谁给的粮实在就跟谁。"], "hall") == "writ" and GameState.has_item("grain_writ"), "营地的人说了谁给粮就跟谁：伊薇特写了粮单")
	r.start("hall", "ivette")
	r.choose(r.options().map(func(o): return str(o.text)).find("沼地那伙人……"))
	check(not r.options().any(func(o): return str(o.text).begins_with("他们说")), "粮单只给一次")
	# —— 营地：粮单收编
	r.start("deepmarsh", "offer_camp")
	var ot: Array = r.options().map(func(o): return str(o.text))
	check(r.node_id == "friendly_greet" and ot.has("伊薇特小姐托我来找你。"), "接了支线：奥弗那里多一项「伊薇特小姐托我来找你」")
	var rep0 := GameState.get_rep("outlaws")
	check(say_runner("offer_camp", ["伊薇特小姐托我来找你。", "（把粮单递过去）黑鹭堡的粮仓，三车燕麦——够你们过冬。"], "deepmarsh") == "ally_grain"
		and GameState.get_flag("ch1_outlaws") == "ally" and not GameState.has_item("grain_writ") and GameState.get_rep("outlaws") == rep0 + 10,
		"把粮单给奥弗：收编了（ch1_outlaws = ally，无旗者 +10，粮单交出去了）")
	check(GameState.quest_stage("ch1_outlaws") == "report", "营地的事了结了：任务推进到「回去告诉伊薇特」")
	r.start("deepmarsh", "offer_camp")
	check(r.node_id == "ally_again" and not r.options().any(func(o): return str(o.text).begins_with("伊薇特小姐")), "收编以后再去：等她的号角，不再问价")
	# 回去报告：支线做完、瓦伦家 +5；泥炭工没说定
	var v0 := GameState.get_rep("valen")
	check(say_runner("ivette", ["沼地那伙人的事办完了。"], "hall") == "outlaws_report" and GameState.quest_done("ch1_outlaws") and GameState.get_rep("valen") == v0 + 5, "回去告诉伊薇特：支线做完，瓦伦家 +5")
	r.start("hall", "ivette")
	check(not r.options().any(func(o): return str(o.text).begins_with("沼地那伙人")), "做完以后不再问沼地那伙人")
	# —— 没有粮单：粮单那一项不显示（会剧透），钱不够灰着；给 50 枚银币收编
	outlaws_state()
	GameState.silver = 20
	r.start("deepmarsh", "offer_camp")
	r.choose(r.options().map(func(o): return str(o.text)).find("伊薇特小姐托我来找你。"))
	var pe: Array = r.entries().map(func(e): return [str(e.option.text), e.locked])
	check(r.node_id == "pitch" and not pe.any(func(e): return str(e[0]).begins_with("（把粮单")) and pe.has(["（放下 50 枚银币）这是定钱。", true]), "没有粮单：不显示粮单；钱不够，给钱那一项灰着（%s）" % str(pe))
	GameState.silver = 60
	check(say_runner("offer_camp", ["伊薇特小姐托我来找你。", "（放下 50 枚银币）这是定钱。"], "deepmarsh") == "ally_paid" and GameState.silver == 10 and GameState.get_flag("ch1_outlaws") == "ally", "给 50 枚银币：收编了")
	# —— 口才：说动了收编；没说动只剩给东西、打或走
	outlaws_state(seed_for("offer_recruit_speech", "speech", 15, true))
	check(say_runner("offer_camp", ["伊薇特小姐托我来找你。", "她守住了黑鹭堡，就许你们在鹭沼过冬，不追旧账。"], "deepmarsh") == "ally_word" and GameState.get_flag("ch1_outlaws") == "ally", "口才说动：「不追旧账」，收编了")
	var sd := seed_for("offer_recruit_speech", "speech", 15, false)
	outlaws_state(sd)
	check(say_runner("offer_camp", ["伊薇特小姐托我来找你。", "她守住了黑鹭堡，就许你们在鹭沼过冬，不追旧账。"], "deepmarsh") == "pitch_fail" and not GameState.has_flag("ch1_outlaws"), "口才没说动：空话不顶饿")
	# —— 威吓：吓走了（人当场走掉）；没吓住只剩打或走
	outlaws_state(seed_for("offer_drive_intimidate", "intimidate", 15, true))
	rep0 = GameState.get_rep("outlaws")
	check(say_runner("offer_camp", ["伊薇特小姐托我来找你。", "她什么也不出。你们收拾东西离开鹭沼，别替任何人卖命。"], "deepmarsh") == "driven"
		and GameState.get_flag("ch1_outlaws") == "driven" and GameState.get_rep("outlaws") == rep0 - 5 and GameState.quest_stage("ch1_outlaws") == "report", "威吓吓住了：赶走（driven，无旗者 -5），任务推进")
	outlaws_state(seed_for("offer_drive_intimidate", "intimidate", 15, false))
	check(say_runner("offer_camp", ["伊薇特小姐托我来找你。", "她什么也不出。你们收拾东西离开鹭沼，别替任何人卖命。"], "deepmarsh") == "drive_fail", "没吓住：他们笑你，只剩拔剑或者走")
	# —— 记恨你、让你滚的奥弗：有支线时也能拔剑
	outlaws_state(seed_for("offer_camp_speech", "speech", 17, false))
	GameState.flags.erase("offer_left")
	GameState.set_flag("offer_defeated")
	GameState.yielded["ferry_offer"] = [0.0, 0.0, 0.0]
	say_runner("offer_camp", ["那晚各为其主。今天我不是来打架的。"], "deepmarsh")
	r.start("deepmarsh", "offer_camp")
	check(r.node_id == "refused_again" and r.options().any(func(o): return str(o.text).begins_with("（拔剑）")), "让你滚的奥弗：有支线时能拔剑")
	say_runner("offer_camp", ["（拔剑）你说过，下回就不是说话了。"], "deepmarsh")
	check(str(GameState.pending_fight.get("fight", "")) == "camp" and GameState.pending_fight.get("value") == "beaten" and str(GameState.pending_fight.get("win", "")) == "ch1_outlaws", "拔剑：营地那一仗，打赢记 ch1_outlaws = beaten")
	GameState.pending_fight = {}
	check(Marsh.camp_loot("offer_camp").has("grey_glove") == false and Marsh.camp_loot("camp_thug_a") == Enemy.types().clubber.loot, "奥弗在渡口被搜过身：营地里没有第二只灰皮手套")
	# —— 奥弗死在渡口：伊薇特、军士说的是「灰手剩下的那伙人」，头目一样能收编
	outlaws_state()
	GameState.dead["ferry_offer"] = [0.0, 0.0, 0.0]
	GameState.set_flag("ivette_met")
	r.start("hall", "ivette")
	r.choose(r.options().map(func(o): return str(o.text)).find("沼地那伙人……"))
	check(r.text().begins_with("灰手剩下的那伙人"), "奥弗死在渡口：伊薇特不再说「奥弗那伙人」（%s）" % r.text().left(12))
	r.start("hall", "ivette")
	r.node_id = "ask"
	check(r.text().contains("死在渡口"), "伊薇特托你的时候也说灰手死在渡口了")
	r.start("barracks", "sergeant")
	r.node_id = "offer"
	check(r.text().begins_with("灰手死在渡口了"), "军士也不把灰手当活人说")
	GameState.dead.erase("ferry_offer")
	r.node_id = "offer"
	check(r.text().begins_with("灰手？"), "奥弗活着：军士照旧")
	GameState.dead["ferry_offer"] = [0.0, 0.0, 0.0]
	GameState.silver = 100
	check(say_runner("camp_boss", ["（放下 40 枚银币）给他的人买口吃的。", "伊薇特小姐托我来找你。", "（放下 50 枚银币）这是定钱。"], "deepmarsh") == "ally_paid" and GameState.get_flag("ch1_outlaws") == "ally", "头目：一样能收编")
	outlaws_state(seed_for("boss_recruit_speech", "speech", 15, true))
	GameState.dead["ferry_offer"] = [0.0, 0.0, 0.0]
	GameState.silver = 0
	check(say_runner("camp_boss", ["伊薇特小姐托我来找你。", "她守住了黑鹭堡，就许你们在鹭沼过冬，不追旧账。"], "deepmarsh") == "ally_word", "头目：有支线时不用先给 40 枚银币，也能直接谈（审查）")
	outlaws_state()
	say_runner("offer_camp", ["伊薇特小姐托我来找你。"], "deepmarsh")
	check(GameState.has_flag("offer_camp_terms"), "一开口问价就记下「谁给粮就跟谁」：回去伊薇特就给粮单（审查：不用先问「黑鹭堡要出事了」）")
	# —— 托宾的泥炭工
	outlaws_state()
	GameState.silver = 40
	check(say_runner("tobin", ["伊薇特小姐想让泥炭工站到她那边。", "（数出 30 枚银币）这笔账我先替她结了。"]) == "peat_yes" and GameState.get_flag("ch1_peat") == "ivette" and GameState.silver == 10, "托宾：替堡里结清 30 枚泥炭钱，泥炭工站到伊薇特这边（ch1_peat）")
	r.start("reedwharf", "tobin")
	ot = r.options().map(func(o): return str(o.text))
	check(not ot.has("伊薇特小姐想让泥炭工站到她那边。") and ot.has("到那天，泥炭工……"), "说定以后：不再问，改成「到那天」")
	outlaws_state(seed_for("tobin_peat_speech", "speech", 14, true))
	check(say_runner("tobin", ["伊薇特小姐想让泥炭工站到她那边。", "小姐守住了堡，欠的钱她加倍还——我替她担保。"]) == "peat_yes", "口才担保：也行")
	outlaws_state(seed_for("tobin_peat_speech", "speech", 14, false))
	GameState.silver = 0
	check(say_runner("tobin", ["伊薇特小姐想让泥炭工站到她那边。", "小姐守住了堡，欠的钱她加倍还——我替她担保。"]) == "peat_no" and not GameState.has_flag("ch1_peat"), "担保没说动：拿钱来再说")
	GameState.new_game(1)
	r.start("reedwharf", "tobin")
	check(not r.options().any(func(o): return str(o.text).begins_with("伊薇特小姐")), "没接支线：托宾那里没有这一项")
	# —— 营地的人按结果摆：没了结是一组对峙；赶走了空；收编了说自己人的话
	outlaws_state()
	var main := await make_main_marsh()
	var grp := main.get_tree().get_nodes_in_group(Encounter.group_name(MarshLayout.CAMP_ENCOUNTER))
	check(grp.size() == 4 and grp.all(func(n): return n.has_meta("enemy_kind") and n.has_meta("enemy_id")), "还没了结：营地的 4 个人是一组对峙（能开打）")
	await free_main(main)
	outlaws_state()
	GameState.set_flag("ch1_outlaws", "driven")
	main = await make_main_marsh()
	check(main.world.get_node_or_null("Npc_offer_camp") == null and main.world.get_node_or_null("Npc_camp_thug_a") == null, "赶走了：营地空了")
	await free_main(main)
	outlaws_state()
	GameState.set_flag("ch1_outlaws", "ally")
	main = await make_main_marsh()
	var th := main.world.get_node_or_null("Npc_camp_thug_a") as Npc
	check(th != null and th.lines == MarshLayout.CAMP_LINES.ally and main.get_tree().get_nodes_in_group(Encounter.group_name(MarshLayout.CAMP_ENCOUNTER)).is_empty(), "收编了：手下说自己人的话，不再是对峙")
	await free_main(main)
	# —— 真打：拔剑，营地的人换成敌人；只烘焙营地那块的导航；打完 ch1_outlaws = beaten，任务推进
	outlaws_state()
	main = await make_main_marsh()
	check(main.nav.is_empty(), "鹭沼平时不烘焙导航网格")
	place(main.player, -50.0, 30.0)
	await physics(4)
	var music_before := Music.track
	check(await fl_say(main, "deepmarsh", "offer_camp", ["伊薇特小姐托我来找你。", "（拔剑）那就没什么好谈的了。"]), "拔剑")
	await frames(2)
	check(main.encounter_active() and main.encounter.enemies.size() == 4 and main.in_combat(), "营地的 4 个人换成敌人开打（%d）" % (main.encounter.enemies.size() if main.encounter else 0))
	check(not main.nav.is_empty() and int(main.nav.polygons) > 0 and float(main.nav.ms) < 1500.0, "开打时只烘焙营地那块的导航（%s 个多边形，%.0f 毫秒）" % [main.nav.get("polygons", 0), main.nav.get("ms", 0.0)])
	await physics(30)
	var en: Array = main.encounter.enemies
	var reached := en.filter(func(e): return e.nav_ready())
	check(reached.size() == en.size(), "敌人用得上导航网格（%d / %d）" % [reached.size(), en.size()])
	var nmap: RID = main.player.get_world_3d().navigation_map
	var holes := []
	for cp: Array in [MarshLayout.CAMP_OFFER] + MarshLayout.CAMP_MEN:
		var at: Vector3 = cp[2]
		var q := NavigationServer3D.map_get_closest_point(nmap, at)
		if Vector2(q.x - at.x, q.z - at.z).length() > 0.3:
			holes.append(str(cp[0]))
	check(holes.is_empty(), "营地的人原来站的地方都在导航网格上（NPC 开打前就拿掉了，不在脚下挖洞；%s）" % str(holes))
	var boss: Enemy = en.filter(func(e): return e.enemy_id == "offer_camp")[0]
	check(boss.display_name == "「灰手」奥弗" and boss.kind == "outlaw_boss", "奥弗是 outlaw_boss，名字照旧")
	for e in en:
		e.take_hit({"damage": 999, "kind": "heavy", "stop": 0.0})
	await frames(3)
	check(str(GameState.get_flag("ch1_outlaws")) == "beaten" and GameState.quest_stage("ch1_outlaws") == "report" and not main.in_combat(), "打完：ch1_outlaws = beaten，任务推进到「回去告诉伊薇特」")
	check(GameState.dead.has("offer_camp") and GameState.dead.has("camp_lookout"), "死的人记进存档")
	await free_main(main)
	main = await make_main_marsh()
	var ens: Array = main.find_children("*", "Enemy", true, false).map(func(e): return str(e.enemy_id))
	check(ens.size() == 4 and main.world.get_node_or_null("Npc_offer_camp") == null, "再来：营地里躺着倒下的人，没人站着（%s）" % str(ens))
	await free_main(main)
	GameState.set_flag("ivette_met")
	GameState.add_item("grain_writ")
	check(say_runner("ivette", ["沼地那伙人的事办完了。"], "hall") == "outlaws_report" and GameState.quest_done("ch1_outlaws") and not GameState.has_item("grain_writ"), "打散了也能回去报告；没用上的粮单她收回去")
	# 网址 ?fight=camp 在营地已经了结时：没有人可打，不留一个打不完的对峙
	GameState.set_flag("ch1_outlaws", "driven")
	main = await make_main_marsh()
	main.start_encounter(MarshLayout.CAMP_ENCOUNTER, "")
	check(not main.encounter_active() and not main.in_combat(), "营地空了还开打：马上结束，能走能存档")
	await free_main(main)
	Music.stop_now()
	GameState.new_game()


## 4.8a：在病房等黄昏，家主醒来交出印戒，交给继承人；另一位离堡
func heir_state(choice := "deliver", sd := 1) -> void:
	ch1_state(choice, sd)
	for f in ["ch1_victor_done", "castle_admitted", "herman_met", "alric_met", "ivette_met", "ledger_asked", "outlaws_asked", "heirs_heard", "marta_met", "osric_seen"]:
		GameState.set_flag(f)
	GameState.start_quest("ch1_main")
	GameState.set_stage("ch1_main", "wait_dusk")
	GameState.start_quest("ch1_ledger")
	GameState.start_quest("ch1_outlaws")
	GameState.daypart = "day"


func test_heir() -> void:
	Settings.set_value("third_person", false)
	wipe_test_saves()
	# —— 水门的表（STORY 4.7b）
	var table := [["helped", "ivette", "deliver", "warned"], ["persuaded", "ivette", "deliver", "unknown"], ["reported", "ivette", "deliver", "opened"], ["", "ivette", "deliver", "unknown"],
		["helped", "alric", "deliver", "opened"], ["persuaded", "alric", "deliver", "unknown"], ["reported", "alric", "deliver", "unknown"], ["", "alric", "deliver", "opened"], ["", "alric", "release", "unknown"]]
	var wrong := []
	for row: Array in table:
		GameState.new_game(1)
		GameState.set_flag("prologue_edric", row[2])
		if str(row[0]) != "":
			GameState.set_flag("ch1_edric", row[0])
		if Chapter1.water_gate(str(row[1])) != str(row[3]):
			wrong.append(row)
	check(wrong.is_empty(), "水门按 STORY 4.7b 的表算（%s）" % str(wrong))
	# —— 玛尔塔：等黄昏；白芦根还没交的来不及了
	heir_state()
	GameState.start_quest("ch1_whitereed")
	var r := DialogueRunner.new()
	r.start("sickroom", "marta")
	r.choose(r.options().map(func(o): return str(o.text)).find("家主什么时候醒？"))
	check(r.node_id == "wait_ask" and r.text().contains("白芦根还没熬上"), "问玛尔塔家主什么时候醒：她提醒白芦根还没熬上")
	r.choose(r.options().map(func(o): return str(o.text)).find("我就在这儿等他醒。"))
	check(r.node_id == "dusk" and GameState.has_flag("osric_awake") and GameState.quest_stage("ch1_main") == "osric_awake" and GameState.quest_stage("ch1_whitereed") == "late",
		"在床边等：家主醒了，主线推进；白芦根来不及了（late）")
	heir_state()
	check(say_runner("marta", ["家主什么时候醒？", "我先去办点事。"], "sickroom") == "again" and not GameState.has_flag("osric_awake"), "先去办事：还是白天，家主没醒")
	# —— 在病房里真的等：时段推到黄昏，家主能说话了
	GameState.pending_load = {"scene": "sickroom", "spawn": "front", "player": {}}
	var main := await make_main(false)
	await physics(3)
	var osric := main.world.get_node("Npc_osric") as Npc
	check(osric.dialogue_id == "" and osric.verb == "看看", "白天：家主睡着，只能看看")
	check(await fl_say(main, "sickroom", "marta", ["家主什么时候醒？", "我就在这儿等他醒。", "（走到床前）"]), "陪玛尔塔等")
	await frames(3)
	check(GameState.daypart == "dusk" and main.daypart == Daypart.effective("sickroom", "dusk") and osric.dialogue_id == "osric" and osric.verb == "交谈", "对话一关：黄昏了，家主醒着、能说话（%s / %s）" % [GameState.daypart, osric.verb])
	check(await fl_say(main, "sickroom", "osric", ["（把奥尔本修士的旧书给他看）", "……", "（拿出借据）霜渡镇那张借据，在我这儿。", "……", "两位继承人都在等您一句话。", "为什么是我？", "（收下印戒）"]),
		"给他看旧书、交出借据、问继承人")
	check(GameState.has_flag("osric_book") and GameState.get_flag("ch1_debt") == "given_osric" and not GameState.has_item("debt_note") and GameState.has_item("valen_signet") and GameState.quest_stage("ch1_main") == "choose_heir",
		"家主认出了旧书、收下借据（given_osric），把印戒交给你；主线：交给该拿的人")
	r.start("sickroom", "osric")
	check(r.node_id == "after", "再找家主：他又睡过去了")
	GameState.add_item("debt_note")
	GameState.flags.erase("ch1_debt")
	check(say_runner("osric", ["（拿出借据）霜渡镇那张借据……"], "sickroom") == "debt_late" and GameState.get_flag("ch1_debt") == "given_osric", "先拿了印戒、后想起借据：睡着的家主照样收下（审查）")
	await free_main(main)
	# —— 旧书没看之前不说继承人；没有借据不显示借据（会剧透）
	heir_state("release")
	GameState.set_flag("osric_awake")
	r.start("sickroom", "osric")
	var ot: Array = r.options().map(func(o): return str(o.text))
	check(not ot.has("两位继承人都在等您一句话。") and not ot.any(func(t): return str(t).begins_with("（拿出借据")) and ot.has("（把奥尔本修士的旧书给他看）"), "先看旧书才说到继承人；借据跟埃德里克走了的不显示（%s）" % str(ot))
	GameState.set_flag("ch1_herb")
	check(r.start("sickroom", "osric") and r.text().contains("目光比你想的清楚"), "喝过白芦根汤：他清醒得多")
	# —— 交给阿尔里克（黄昏在大厅）：伊薇特带着兵营的人离堡；她托你的支线收尾；借据一起交出
	heir_state("extort")
	GameState.start_quest("ch1_wedding")
	GameState.set_flag("ch1_edric", "helped")
	GameState.set_flag("osric_awake")
	GameState.set_flag("osric_ring_given")
	GameState.set_stage("ch1_main", "choose_heir")
	GameState.add_item("valen_signet")
	GameState.daypart = "dusk"
	var sev := GameState.get_rep("severin")
	GameState.pending_load = {"scene": "hall", "spawn": "front", "player": {}}
	main = await make_main(false)
	await physics(3)
	check(main.world.get_node_or_null("Npc_ivette") == null and main.world.get_node_or_null("Npc_alric") != null, "黄昏：伊薇特回兵营了，阿尔里克在大厅")
	check(await fl_say(main, "hall", "alric", ["（拿出家主印戒）", "（把印戒交给他）", "还有这个——霜渡镇那张借据。", "……"]), "把印戒交给阿尔里克，借据也给他")
	await frames(2)
	check(GameState.get_flag("valen_heir") == "alric" and not GameState.has_item("valen_signet") and GameState.get_flag("ch1_debt") == "given_heir" and GameState.get_rep("severin") == sev + 10
		and GameState.quest_stage("ch1_main") == "prepare", "valen_heir = alric，借据 given_heir，塞弗林家 +10，主线推进到备战")
	check(GameState.get_flag("ch1_water_gate") == "opened" and GameState.quest_stage("ch1_outlaws") == "left" and GameState.quest_stage("ch1_ledger") == "get_ledger" and GameState.quest_stage("ch1_wedding") == "left",
		"水门：伊薇特答应过退亲、却选了阿尔里克——埃德里克会开门（opened）；伊薇特的支线、婚事收尾，阿尔里克的账册还在")
	check(Chapter1.gone("ivette") and Chapter1.gone("sergeant") and not Chapter1.gone("alric") and Schedule.area_of("ivette") == "", "伊薇特和兵营里她的人走了")
	check(GameState.quest_done("ch1_wedding") and GameState.quest_done("ch1_outlaws") and not GameState.quest_done("ch1_ledger"), "收尾的支线算做完（日志里不再挂着；埃德里克、阿尔里克那里不能再了结婚事）")
	r.start("hall", "edric_hall")
	check(r.node_id == "after_heir", "埃德里克：戒指给出去了，他的事由不得他了")
	r.start("hall", "alric")
	r.choose(r.options().map(func(o): return str(o.text)).find("还有别的事。"))
	check(not r.options().any(func(o): return str(o.text).begins_with("埃德里克不想娶")), "阿尔里克那里不再能告发婚事")
	r.start("blackheron", "herman")
	r.node_id = "heirs"
	check(r.text().begins_with("阿尔里克大人在大厅，戒指在他手上了"), "赫尔曼说继承人在哪：按交给了谁")
	main = await fl_go(main, "castle")
	main = await fl_go(main, "barracks")
	await physics(2)
	var left := main.find_children("Npc_*", "Npc", true, false).map(func(n): return str(n.name))
	check(main.area == "barracks" and left.is_empty(), "兵营空了（%s）" % str(left))
	main = await fl_go(main, "castle")
	check(main.world.get_node_or_null("Npc_barracks_soldier") == null and (main.world.get_node("Npc_gate_guard_in") as Npc).lines == Castle.GUARD_LINES_HEIR.gate_guard_in, "庭院：兵营门口的兵也走了，守门的说的是今晚的事")
	await free_main(main)
	r.start("hall", "alric")
	check(r.node_id == "heir", "再找阿尔里克：他让你去找赫尔曼")
	# —— 交给伊薇特（黄昏在兵营）：阿尔里克带着信使离堡，当场从大厅拿掉
	heir_state()
	GameState.set_flag("osric_ring_given")
	GameState.set_stage("ch1_main", "choose_heir")
	GameState.add_item("valen_signet")
	GameState.daypart = "dusk"
	var eld := GameState.get_rep("eld")
	GameState.pending_load = {"scene": "barracks", "spawn": "front", "player": {}}
	main = await make_main(false)
	await physics(3)
	check(main.world.get_node_or_null("Npc_ivette") != null, "黄昏：伊薇特在兵营")
	check(await fl_say(main, "hall", "ivette", ["（拿出家主印戒）", "（把印戒交给她）", "……"]), "把印戒交给伊薇特")
	await frames(2)
	check(GameState.get_flag("valen_heir") == "ivette" and GameState.get_rep("eld") == eld + 10 and GameState.has_item("debt_note") and GameState.get_flag("ch1_water_gate") == "unknown"
		and GameState.quest_stage("ch1_ledger") == "left" and GameState.quest_stage("ch1_outlaws") == "talk_offer" and main.world.get_node_or_null("Npc_ivette") != null,
		"valen_heir = ivette，厄尔德家 +10；借据没给还在身上；埃德里克没做婚事支线、选了伊薇特：水门 unknown；阿尔里克的账册收尾，伊薇特的还在")
	main = await fl_go(main, "castle")
	main = await fl_go(main, "hall")
	await physics(2)
	check(main.world.get_node_or_null("Npc_alric") == null and main.world.get_node_or_null("Npc_envoy") == null and main.world.get_node_or_null("Npc_edric_hall") != null, "大厅：阿尔里克和信使走了，埃德里克还在")
	await free_main(main)
	# —— 没有印戒：继承人那里不显示（会剧透）；读档不再提示「离堡」
	heir_state()
	r.start("hall", "alric")
	check(not r.options().any(func(o): return str(o.text).begins_with("（拿出家主印戒")), "没有印戒：不显示交印戒")
	GameState.set_flag("valen_heir", "alric")
	GameState.pending_load = {"scene": "hall", "spawn": "front", "player": {}}
	main = await make_main(false)
	check(main.heir_seen == "alric", "读档进来：已经交过的不再提示")
	await free_main(main)
	check(Chapter1.later_daypart("dusk", "day") == "dusk" and Chapter1.later_daypart("dawn", "day") == "day", "时段只往前走：黄昏以后走旅行地图不会回到白天（审查）")
	heir_state()
	GameState.add_item("grain_writ")
	GameState.set_flag("valen_heir", "alric")
	check(not GameState.has_item("grain_writ"), "伊薇特走了：她的粮单收回")
	GameState.new_game()


## 4.8b：入夜备战——找赫尔曼定守断口还是石拱，他给你六个人；埃德里克提醒过水门的能分两个人去守；会开水门的，入夜后再找他一次；天黑透、小队列队、自动存档
func prepare_state(heir: String, edric: String) -> void:
	heir_state("deliver")
	GameState.set_flag("ch1_edric", edric)
	GameState.set_flag("osric_awake")
	GameState.set_flag("osric_ring_given")
	GameState.set_flag("valen_heir", heir)
	Chapter1.heir_chosen(heir)
	GameState.set_stage("ch1_main", "prepare")
	GameState.daypart = "dusk"


func test_prepare() -> void:
	Settings.set_value("third_person", false)
	wipe_test_saves()
	# —— 选伊薇特、埃德里克提醒过水门（warned）、泥炭工站在她这边：守断口，分两个人守水门
	prepare_state("ivette", "helped")
	GameState.set_flag("ch1_peat", "ivette")
	check(GameState.get_flag("ch1_water_gate") == "warned", "前提：水门 warned")
	var r := DialogueRunner.new()
	r.start("blackheron", "herman")
	check(r.node_id == "plan" and r.text().contains("断口") and r.text().contains("石拱") and r.text().contains("泥炭"), "备战时找赫尔曼：讲断口和石拱；托宾的人捎了话（泥炭垛）")
	GameState.pending_load = {"scene": "castle", "spawn": "gate", "player": {}}
	var main := await make_main(false)
	await physics(3)
	check(main.world.get_node_or_null("Npc_squad_0") == null and main.world.get_node_or_null("Npc_herman") != null, "说定以前：堡门里头还没有小队；赫尔曼在（黄昏在大厅门口）")
	check(await fl_say(main, "blackheron", "herman", ["守断口。", "埃德里克说，水门那道栅年久失修，夜里只有一个老头守着。", "分两个人去守水门。", "堤道上见。"]), "和赫尔曼说定：守断口、分两个人守水门")
	await frames(3)
	check(GameState.get_flag("ch1_hold") == "gap" and GameState.has_flag("ch1_gate_guard") and GameState.daypart == "night" and GameState.quest_stage("ch1_main") == "to_causeway",
		"ch1_hold = gap、ch1_gate_guard、天黑透了、主线推进到「上堤道」（%s / %s）" % [GameState.daypart, GameState.quest_stage("ch1_main")])
	var squad: Array = range(6).map(func(i): return main.world.get_node_or_null("Npc_squad_%d" % i))
	check(squad.all(func(n): return n != null), "六个卫兵当场摆出来")
	var at_gate := squad.filter(func(n): return n != null and (n as Node3D).position.z < 0.0)
	check(at_gate.size() == 2 and (squad[0] as Node3D).position.distance_to(Castle.SPAWNS.gate[0]) < 6.0, "两个站到水门里面，四个在堡门里头列队")
	await physics(2)
	var stuck := squad.filter(func(n): return n != null and not stands_clear(n)).map(func(n): return str(n.name))
	check(stuck.is_empty(), "小队都站在地上，没卡在桶、车、墙里（%s）" % str(stuck))
	var auto := Saves.read_slot("auto")
	check(auto.has("data") and str(auto.data.state.quests.ch1_main.stage) == "to_causeway" and str(auto.data.state.get("daypart", "")) == "night", "入夜自动存档（存的是「上堤道」、夜里）")
	r.start("blackheron", "herman")
	check(r.node_id == "ready", "再找赫尔曼：堤道上见")
	main = await fl_go(main, "hall")
	main = await fl_go(main, "castle")
	check(main.world.get_node_or_null("Npc_squad_5") != null and Castle.squad(main.world) == 0, "进出大厅回来：小队还在，不重摆")
	await free_main(main)
	# —— 选阿尔里克、伊薇特答应过退亲（埃德里克会开水门 opened）：守石拱；没有分人守水门的选项；入夜再找埃德里克
	prepare_state("alric", "helped")
	check(GameState.get_flag("ch1_water_gate") == "opened", "前提：水门 opened")
	r.start("blackheron", "herman")
	check(not r.text().contains("泥炭"), "泥炭工没站过来的：不提泥炭垛")
	r.choose(r.options().map(func(o): return str(o.text)).find("守石拱。"))
	check(r.text().contains("石拱") and not r.options().any(func(o): return str(o.text).begins_with("埃德里克说")), "守石拱；没人提醒过水门，不能分人去守（%s）" % str(r.options().map(func(o): return o.text)))
	r.start("hall", "edric_hall")
	check(r.node_id == "after_heir", "天还没黑：埃德里克还是那句「由不得我」")
	check(say_runner("herman", ["守石拱。", "天快黑了。走吧。", "堤道上见。"], "blackheron") == "" and GameState.daypart == "night" and GameState.get_flag("ch1_hold") == "arch" and not GameState.has_flag("ch1_gate_guard"), "说定：守石拱，人都跟着你")
	GameState.checks["edric_gate"] = false
	check(say_runner("edric_hall", ["今晚这道墙要是丢了，霜渡镇也保不住。你袖子里是什么？"], "hall") == "gate_hid" and GameState.get_flag("ch1_water_gate") == "opened" and GameState.has_flag("edric_gate_tried"), "入夜找埃德里克：没说动，他把东西藏起来（还是 opened）")
	r.start("hall", "edric_hall")
	check(r.node_id == "after_heir", "只能试一次")
	prepare_state("alric", "helped")
	say_runner("herman", ["守石拱。", "天快黑了。走吧。", "堤道上见。"], "blackheron")
	GameState.checks["edric_gate"] = true
	check(say_runner("edric_hall", ["今晚这道墙要是丢了，霜渡镇也保不住。你袖子里是什么？"], "hall") == "gate_talked" and GameState.get_flag("ch1_water_gate") == "kept" and GameState.has_item("water_gate_key"),
		"说动了：他交出水门的钥匙（kept）")
	r.start("hall", "edric_hall")
	check(r.node_id == "gate_after", "再找他：别让他们过来")
	# —— 小队的话：埃德里克会开门时，有一个兵提一句他
	prepare_state("alric", "helped")
	GameState.set_flag("ch1_ready")
	GameState.set_stage("ch1_main", "to_causeway")         # 小队只在「上堤道」时列队（4.10a：打完仗、天亮以后不再列队）
	var holder := Node3D.new()
	add_child(holder)
	check(Castle.squad(holder) == 6 and ((holder.get_node("Npc_squad_0") as Npc).lines as Array).has(Castle.SQUAD_LINE_EDRIC), "会开水门的：小队里有人说埃德里克一晚上坐在窗边")
	holder.free()
	GameState.new_game()


## 4.9a：堤道夜战——入夜备战说定了才摆；你的小队、赫尔曼守石拱、三波攻方；走到守点开打（先存档）；据点规则（6 个人冲过石拱就失守）；过半溃逃就守住；打完写 ch1_causeway
func causeway_state(hold: String, gate_guard := false) -> void:
	prepare_state("alric", "persuaded")
	GameState.set_flag("ch1_hold", hold)
	GameState.set_flag("ch1_ready")
	if gate_guard:
		GameState.set_flag("ch1_gate_guard")
	GameState.set_stage("ch1_main", "to_causeway")
	GameState.daypart = "night"


func make_causeway() -> Node3D:
	GameState.pending_load = {"scene": "marsh", "spawn": "castle_gate", "player": {}}
	var main := await make_main(false)
	await physics(3)
	return main


func test_causeway() -> void:
	Settings.set_value("third_person", false)
	wipe_test_saves()
	causeway_state("gap")
	GameState.set_stage("ch1_main", "prepare")
	var main := await make_causeway()
	check(main.battle == null and not CausewayBattle.due(), "还没和赫尔曼说定：堤道上没有仗")
	await free_main(main)
	# —— 守断口：摆好了，还没开打
	causeway_state("gap")
	main = await make_causeway()
	var b: Battle = main.battle
	check(b != null and not b.started and b.player_side == CausewayBattle.DEF and b.sides[CausewayBattle.ATK] == "伊薇特的人", "入夜、上堤道：鹭沼地图上摆好一场仗，攻方是伊薇特的人（选了阿尔里克）")
	var def := soldiers_of(main, CausewayBattle.DEF)
	var atk := soldiers_of(main, CausewayBattle.ATK)
	var herman := def.filter(func(x): return x.display_name == "赫尔曼")
	check(b.squad.size() == 6 and def.size() == 13 and herman.size() == 1 and herman[0].is_captain and herman[0].guard_post != Vector3.INF, "守方：你的小队 6 人、赫尔曼（队长）和他的 6 个人守石拱")
	check(atk.size() == 8 and b.waves.size() == 3 and b.side_total(CausewayBattle.ATK) == 33 and b.waves[1].soldiers.any(func(x): return x.display_override == "「芦刀」加斯帕" and x.kind == "captain"),
		"攻方：先头 8 人在村子那头，主力 14 人、加斯帕和 6 名精兵是后两波；没人提醒过水门，主力到时 4 个人从水门摸进来（一共 33 人）")
	check((def + atk).all(func(x): return x.collision_mask & FpController.LAYER_BOUNDARY != 0), "堤道上的兵都撞鹭沼的边墙（不走进深水）")
	check(b.squad.all(func(x): return x.order == "follow") and atk.all(func(x): return CausewayBattle.t_of(x.global_position) < 15.0), "小队跟着你；先头在堤道村子那头")
	await physics(30)
	check(not b.started and not main.in_combat(), "站在堡门前：还没开打（能存档、能走）")
	check(main.save_game("quick", true), "开打前能存档")
	main.player.global_position = CausewayBattle.hold_point() + Vector3(0, 0.3, 0)
	await frames(3)
	check(b.started and main.in_combat() and main.hud.toast_label.text.contains("守住断口"), "走到断口：开打，提示守住断口、按 2 坚守")
	var auto := Saves.read_slot("auto")
	check(auto.has("data") and str(auto.data.scene) == "marsh" and str(auto.data.state.quests.ch1_main.stage) == "to_causeway", "开打前自动存档（倒下读档从这里来）")
	# —— 窄路：先头沿堤道往前压，不卡在断口两头的墙角；掉进路边泥里的爬回路上
	var mud_guy: Soldier = atk[7]
	mud_guy.global_position = MarshLayout.cw3(20.0, 4.2, MarshLayout.MUD_Y + 0.3)
	var off_of := func(x: Node3D) -> float: return absf((Vector2(x.global_position.x, x.global_position.z) - MarshLayout.CW_START).dot(MarshLayout.CW_SIDE))
	var t0s: Array = atk.slice(0, 6).map(func(x): return CausewayBattle.t_of(x.global_position))
	await seconds(4.0)
	var gained: Array = range(6).map(func(i): return CausewayBattle.t_of(atk[i].global_position) - float(t0s[i]))
	check(gained.all(func(g): return g > 4.0) and atk.all(func(x): return x.global_position.y > MarshLayout.MUD_Y - 0.3), "先头沿堤道往堡这边压（4 秒走了 %s 米），没人掉进深水" % str(gained.map(func(g): return snappedf(g, 0.1))))
	check(off_of.call(mud_guy) < 2.0, "掉进路边泥里的兵爬回堤道上（离中线 %.1f 米）" % off_of.call(mud_guy))
	# —— 据点规则：攻方 6 个人冲过石拱就失守
	var runners := atk.slice(0, 6)
	for x in runners:
		x.global_position = MarshLayout.cw3(CausewayBattle.BREACH_T + 4.0)
	await seconds(0.6)
	check(b.finished and b.winner == CausewayBattle.ATK and b.breached.size() == 6, "6 个人冲过石拱：失守（%s）" % b.winner)
	check(GameState.get_flag("ch1_causeway") == "lost" and GameState.quest_stage("ch1_main") == "dawn_lost" and main.hud.toast_label.text.contains("失守"), "写 ch1_causeway = lost，主线推进到天亮（失守）")
	await frames(3)
	auto = Saves.read_slot("auto")
	check(str(auto.data.state.quests.ch1_main.stage) == "dawn_lost", "打完自动存档")
	await free_main(main)
	main = await make_causeway()
	check(main.battle == null, "打过了：再来堤道上没有仗")
	await free_main(main)
	# —— 守石拱、分了两个人守水门：小队 4 人；攻方过半倒下就溃逃，守住
	causeway_state("arch", true)
	main = await make_causeway()
	b = main.battle
	check(b.squad.size() == 4 and CausewayBattle.at_post(MarshLayout.cw3(80.0)) and not CausewayBattle.at_post(MarshLayout.SPAWNS.castle_gate[0]), "分了两个人守水门：小队 4 人；守石拱时走到石拱后面就开打")
	main.player.global_position = CausewayBattle.hold_point() + Vector3(0, 0.3, 0)
	await frames(3)
	check(b.started and main.hud.toast_label.text.contains("守住石拱"), "守石拱：开打")
	atk = soldiers_of(main, CausewayBattle.ATK)
	for x in atk:
		x.take_hit({"damage": 999, "kind": "heavy", "stop": 0.0, "attacker": main.player})
	b.elapsed = CausewayBattle.WAVE2_AT
	await seconds(0.5)
	var flank := soldiers_of(main, CausewayBattle.ATK).filter(func(x): return x.fighting() and x.has_meta("flank"))
	check(b.waves.size() == 1 and soldiers_of(main, CausewayBattle.ATK).filter(func(x): return x.fighting()).size() == 18 and flank.size() == 4, "开打 35 秒：主力 14 人上来，水门摸进来 4 个（分了人守水门，可没人提醒过——守的人不知道该守）")
	check(flank.all(func(x): return CausewayBattle.t_of(x.global_position) > CausewayBattle.BREACH_T) and b.breached.is_empty() and main.hud.toast_label.text.contains("水门那边摸进来"), "水门摸进来的人在堡门前（堡门背后有敌人），不算「冲过石拱」")
	var killed := 0
	while b.routed == "" and killed < 14:
		var left := soldiers_of(main, CausewayBattle.ATK).filter(func(x): return x.fighting())
		if left.is_empty():
			break
		left[0].take_hit({"damage": 999, "kind": "heavy", "stop": 0.0, "attacker": main.player})
		killed += 1
	await seconds(0.6)
	check(b.routed == CausewayBattle.ATK and b.waves.is_empty() and b.finished and b.winner == CausewayBattle.DEF, "攻方倒下过半（%d + %d）：剩下的溃逃，加斯帕那波不来了，守住" % [8, killed])
	check(GameState.get_flag("ch1_causeway") == "held" and main.hud.toast_label.text.contains("守住了"), "写 ch1_causeway = held")
	await free_main(main)
	# —— 4.9b 水门：交出了钥匙不开；提醒过又分了人守，挡回去；提醒了没分人、没人提醒，都摸进来
	var gates := []
	for row: Array in [["kept", false], ["warned", true], ["warned", false], ["unknown", true], ["opened", false]]:
		GameState.set_flag("ch1_water_gate", row[0])
		if row[1]:
			GameState.set_flag("ch1_gate_guard")
		else:
			GameState.flags.erase("ch1_gate_guard")
		gates.append(CausewayBattle.gate_state())
	check(gates == ["shut", "guarded", "breach", "breach", "breach"], "水门：kept 不开、warned + 分人守挡回去，其余都摸进来（%s）" % str(gates))
	# —— 4.9b 选伊薇特、收编了奥弗、泥炭工站过来、守断口、提醒过水门也分了人：奥弗杀出来、泥炭垛点火、水门挡回去
	prepare_state("ivette", "helped")
	GameState.set_flag("ch1_outlaws", "ally")
	GameState.set_flag("ch1_peat", "ivette")
	GameState.set_flag("ch1_hold", "gap")
	GameState.set_flag("ch1_gate_guard")
	GameState.set_flag("ch1_ready")
	GameState.set_stage("ch1_main", "to_causeway")
	GameState.daypart = "night"
	main = await make_causeway()
	b = main.battle
	var cw: CausewayBattle = main.world.get_node("Causeway")
	check(b.sides[CausewayBattle.ATK] == "阿尔里克的人" and cw.peat_fire and CausewayBattle.gate_state() == "guarded" and cw.get_node_or_null("PeatStacks") != null, "选了伊薇特：攻方是阿尔里克的人；断口边上码着泥炭垛，这一仗会点火；水门有人守")
	var ow: Array = b.waves.filter(func(w): return w.side == CausewayBattle.DEF)
	check(ow.size() == 1 and ow[0].soldiers.size() == 5 and ow[0].soldiers[0].display_override == "「灰手」奥弗" and ow[0].soldiers.all(func(x): return CausewayBattle.off_of(x.position) > CausewayBattle.REED_OFF),
		"收编了奥弗：主力到时他带 4 个人从芦苇里杀出来（藏在堤道外面）")
	check(cw.torches.size() == CausewayBattle.TORCHES and cw.torches.all(func(e): return (e[0] as Node3D).visible and CausewayBattle.t_of((e[0] as Node3D).position) < -20.0), "远处的火把线在村子那头的沼地上")
	# 芦苇挡视线：堤道外面的人远了看不见
	var a0: Soldier = soldiers_of(main, CausewayBattle.ATK)[0]
	var probe := Node3D.new()
	main.world.add_child(probe)
	probe.global_position = a0.global_position + Vector3(MarshLayout.CW_SIDE.x, 0, MarshLayout.CW_SIDE.y) * 5.0 + Vector3(MarshLayout.CW_DIR.x, 0, MarshLayout.CW_DIR.y) * 8.0
	var far_hidden: bool = not b.see_test.call(a0, probe)
	probe.global_position = a0.global_position + Vector3(MarshLayout.CW_SIDE.x, 0, MarshLayout.CW_SIDE.y) * 4.0
	var near_seen: bool = b.see_test.call(a0, probe)
	probe.global_position = a0.global_position + Vector3(MarshLayout.CW_DIR.x, 0, MarshLayout.CW_DIR.y) * 20.0
	check(far_hidden and near_seen and b.see_test.call(a0, probe), "芦苇挡视线：堤道外面 5 米、往前 8 米的人看不见；4 米内看得见；路上 20 米外的照样看得见")
	probe.queue_free()
	# 泥里走得慢
	var mud_v: Vector3 = a0._lane(Vector3(2, 0, 0))
	a0.global_position = MarshLayout.cw3(14.0, 4.5, MarshLayout.MUD_Y)
	await physics(2)
	check(a0._lane(Vector3(2, 0, 0)).x < mud_v.x * 0.7, "泥里走得慢（%.2f → %.2f）" % [mud_v.x, a0._lane(Vector3(2, 0, 0)).x])
	# 开打：小队坚守两人一排，顺着堤道朝村子排
	main.player.global_position = CausewayBattle.hold_point() + Vector3(0, 0.3, 0)
	await frames(3)
	main.give_order("hold")
	var anchors: Array = b.squad.map(func(x): return x.anchor)
	check(b.squad.size() == 4 and anchors.all(func(p): return CausewayBattle.off_of(p) <= 1.2) and CausewayBattle.t_of(anchors[0]) < CausewayBattle.t_of(main.player.global_position) and CausewayBattle.t_of(anchors[3]) < CausewayBattle.t_of(anchors[0]) - 1.0,
		"坚守：两人一排，顺着堤道朝村子排（都在路面上）")
	# 先头冲到断口前：泥炭工点火，火墙拦住堤道
	var v0: Soldier = soldiers_of(main, CausewayBattle.ATK)[1]
	var m0: float = v0.morale
	v0.global_position = MarshLayout.cw3(CausewayBattle.PEAT_TRIGGER_T + 1.0)
	await frames(3)
	check(cw.peat_lit and is_instance_valid(cw.barrier) and v0.morale <= m0 - 10.0 and main.hud.toast_label.text.contains("泥炭垛"), "先头冲到断口前：泥炭垛点着了，火边的人慌（士气 %.0f → %.0f）" % [m0, v0.morale])
	var sp := main.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(MarshLayout.cw3(CausewayBattle.PEAT_T - 2.0, 0.0, 1.2), MarshLayout.cw3(CausewayBattle.PEAT_T + 2.0, 0.0, 1.2), FpController.LAYER_BOUNDARY)
	check(not sp.intersect_ray(q).is_empty(), "火墙挡住堤道（边墙那一层：兵和你都过不去）")
	cw.burn_left = 0.01
	await frames(3)
	check(not is_instance_valid(cw.barrier) or cw.barrier.is_queued_for_deletion(), "火小了：火墙撤掉")
	# 主力到：奥弗杀出来、水门挡回去；火把线熄了
	b.elapsed = CausewayBattle.WAVE2_AT + 4.0
	await seconds(0.5)
	var outl := soldiers_of(main, CausewayBattle.DEF).filter(func(x): return x.display_override == "「灰手」奥弗")
	check(outl.size() == 1 and outl[0].is_inside_tree() and outl[0].fighting() and soldiers_of(main, CausewayBattle.ATK).filter(func(x): return x.has_meta("flank")).is_empty(), "主力到了：奥弗带人杀出来；水门那边没人摸进来")
	check(cw.torches.all(func(e): return not (e[0] as Node3D).visible), "主力上了堤道：远处的火把线熄了（就是他们）")
	await free_main(main)
	GameState.set_flag("ch1_outlaws", "ally")
	GameState.dead["ferry_offer"] = [0, 0, 0]
	GameState.flags.erase("ch1_causeway")
	GameState.set_stage("ch1_main", "to_causeway")
	main = await make_causeway()
	ow = main.battle.waves.filter(func(w): return w.side == CausewayBattle.DEF)
	check(ow.size() == 1 and ow[0].soldiers[0].display_override == "无旗者的头目", "奥弗死在渡口的：是无旗者的头目带人来")
	await free_main(main)
	GameState.new_game()


## 4.10a：天亮 · 家主临终——打完过一会儿天亮：守住从堡门回庭院、失守在芦苇里醒来从水门摸进去（庭院有人巡，被看见就押进病房）；
## 家主说出「铁冠是老王自己交出去的」，喝过白芦根汤的多说「双钥港」，按借据的下落说一句，让你去烽燧线，然后走了
func test_dawn() -> void:
	Settings.set_value("third_person", false)
	wipe_test_saves()
	causeway_state("gap")
	var main := await make_causeway()
	var b: Battle = main.battle
	main.player.global_position = CausewayBattle.hold_point() + Vector3(0, 0.3, 0)
	await frames(3)
	for x in soldiers_of(main, CausewayBattle.ATK).slice(0, 6):
		x.global_position = MarshLayout.cw3(CausewayBattle.BREACH_T + 4.0)
	await seconds(0.6)
	check(b.finished and GameState.quest_stage("ch1_main") == "dawn_lost", "堤道失守：主线到「天亮（失守）」")
	await seconds(7.0)
	var pl: Dictionary = GameState.pending_load
	check(main.leaving and str(pl.get("scene", "")) == "castle" and str(pl.get("spawn", "")) == "water_gate" and GameState.daypart == "dawn", "过一会儿天亮（第二天清晨）：从水门进黑鹭堡（%s）" % str(pl))
	main = await reload_main(main)
	await physics(3)
	var occ: Array = get_tree().get_nodes_in_group("enemy").filter(func(e): return not e is Soldier)
	check(main.area == "castle" and GameState.daypart == "dawn" and main.world.get_node_or_null("Npc_herman") == null and main.world.get_node_or_null("Npc_gate_guard_in") == null
		and main.world.get_node_or_null("Npc_water_keeper") != null and occ.size() == 3 and occ.all(func(e): return e.display_name == "伊薇特的人"), "庭院：赫尔曼和守门的不在了，守水门的老头还在；伊薇特的人巡着（%d 个）" % occ.size())
	check(main.hud.toast_label.text.contains("芦苇里醒过来") and main.world.get_node_or_null("Npc_squad_0") == null, "到了说一句：在芦苇里醒过来、从水门钻进来；昨晚的小队不再列队")
	var valen := GameState.get_rep("valen")
	(occ[0] as Enemy)._enter(Enemy.State.ALERT)
	await frames(2)
	check(GameState.get_flag("ch1_sneak") == "caught" and GameState.get_rep("valen") == valen - 10 and main.hud.toast_label.text.contains("站住"), "被看见：两个卫兵扭住你（瓦伦家 −10）")
	await seconds(3.0)
	check(main.leaving and str(GameState.pending_load.get("scene", "")) == "sickroom", "押进病房")
	main = await reload_main(main)
	await physics(2)
	check(main.area == "sickroom" and main.hud.toast_label.text.contains("让他进来"), "家主坚持要见你")
	var r := DialogueRunner.new()
	r.start("sickroom", "osric")
	check(r.node_id == "dawn_caught" and r.text().contains("伊薇特跟在后面"), "家主：让他留下——新家主（伊薇特）从此不信你")
	check(await fl_say(main, "sickroom", "osric", ["我在。您说。", "交出去？交给了谁？", "……", "您要我做什么？", "（替他把被子掖好）"]), "听家主说完")
	await frames(2)
	check(GameState.has_flag("ch1_osric_farewell") and GameState.quest_stage("ch1_main") == "farewell", "家主走了：主线到「去烽燧线」")
	r.start("sickroom", "osric")
	check(r.node_id == "gone", "再看他：不再动了")
	await free_main(main)
	# —— 结尾的钩子、白芦根、借据
	causeway_state("arch")
	GameState.set_stage("ch1_main", "dawn_held")
	GameState.set_flag("ch1_causeway", "held")
	r.start("sickroom", "osric")
	check(r.node_id == "dawn_held" and r.text().contains("阿尔里克站在床尾"), "守住了：阿尔里克（拿戒指的）站在床尾")
	r.choose(0)
	check(r.text().contains("铁冠没有被偷。是老王自己交出去的"), "结尾的钩子：铁冠没有被偷，是老王自己交出去的")
	r.choose(0)
	check(r.node_id == "who_none" and not r.text().contains("双钥港"), "没喝白芦根汤：想不起来交给了谁")
	GameState.set_flag("ch1_herb")
	GameState.set_flag("ch1_debt", "kept")
	r.start("sickroom", "osric")
	r.choose(0)
	r.choose(0)
	check(r.node_id == "who_herb" and r.text().contains("双钥港"), "喝过白芦根汤：交给了一户靠海的人家——双钥港")
	r.choose(0)
	check(r.text().contains("留着") and r.text().contains("证据"), "借据还在身上：留着，将来是证据")
	r.choose(0)
	check(r.text().contains("烽燧线") and GameState.quest_stage("ch1_main") == "farewell", "去北边的烽燧线找当年另一个侍从")
	# —— 守住了：天亮从堡门回来，赫尔曼在，没人巡；病房里阿尔里克守在床尾
	causeway_state("arch")
	GameState.set_flag("ch1_causeway", "held")
	GameState.set_stage("ch1_main", "dawn_held")
	GameState.daypart = "dawn"
	GameState.pending_load = {"scene": "castle", "spawn": "gate", "player": {}}
	main = await make_main(false)
	await physics(3)
	check(main.world.get_node_or_null("Npc_herman") != null and get_tree().get_nodes_in_group("enemy").is_empty(), "守住了：庭院里赫尔曼在，没人巡")
	main = await fl_go(main, "sickroom")
	await physics(2)
	var heir := main.world.get_node_or_null("Npc_heir") as Npc
	check(main.area == "sickroom" and heir != null and heir.display_name == "阿尔里克", "病房：阿尔里克守在床尾")
	await free_main(main)
	# —— 失守、没被看见：摸进病房
	causeway_state("gap")
	GameState.set_flag("ch1_causeway", "lost")
	GameState.set_stage("ch1_main", "dawn_lost")
	GameState.daypart = "dawn"
	GameState.pending_load = {"scene": "castle", "spawn": "water_gate", "player": {}}
	main = await make_main(false)
	await physics(3)
	main = await fl_go(main, "sickroom")
	await physics(2)
	check(GameState.get_flag("ch1_sneak") == "unseen" and main.hud.toast_label.text.contains("没人看见"), "没被看见就摸进了病房")
	r.start("sickroom", "osric")
	check(r.node_id == "dawn_lost" and r.text().contains("只有玛尔塔"), "病房里只有玛尔塔，家主在等你")
	main = await fl_go(main, "castle")
	await physics(2)
	check(get_tree().get_nodes_in_group("enemy").is_empty(), "摸进去以后再出来：不再巡了")
	await free_main(main)
	GameState.new_game()


## 4.10b：长眠者第一次露面、第一章完——家主走了以后回芦栈村，一个说过话的村民闭着眼往北走；章末画面「第二章 · 熄灭的烽燧」，按旗标写回顾
func test_sleeper() -> void:
	Settings.set_value("third_person", false)
	wipe_test_saves()
	# 是谁：说过信使的渡工 > 说过堤道的托宾 > 补网的女人
	GameState.new_game(1)
	var picks := [Sleeper.who()[0]]
	GameState.set_flag("heard_causeway")
	picks.append(Sleeper.who()[0])
	GameState.set_flag("heard_envoy")
	picks.append(Sleeper.who()[0])
	check(picks == ["netter", "tobin", "boatman"], "是谁：谁都没说过话是补网的女人，说过堤道是托宾，说过信使是渡工（%s）" % str(picks))
	# 家主走了：回到芦栈村
	causeway_state("arch")
	GameState.set_flag("ch1_causeway", "held")
	GameState.set_flag("ch1_herb")
	GameState.set_flag("ch1_outlaws", "ally")
	GameState.set_flag("heard_envoy")
	GameState.set_flag("ch1_osric_farewell")
	GameState.set_stage("ch1_main", "farewell")
	GameState.daypart = "dawn"
	var main := await make_main_marsh()
	var sl: Sleeper = main.sleeper
	check(sl != null and main.world.get_node_or_null("Npc_boatman") == null and sl.npc.display_name == "渡工" and not sl.walking, "回到芦栈村：渡工不在码头上了，站在客栈东边的栈道上")
	await physics(20)
	check(not sl.walking and sl.npc.position == Sleeper.START, "你没走近：他不动")
	main.player.global_position = Sleeper.START + Vector3(10, 0.3, 0)
	await frames(3)
	check(sl.walking and GameState.get_flag("ch1_sleeper") == "boatman" and main.hud.toast_label.text.contains("叫不醒"), "走近了：他闭着眼睛从你身边走过去，叫不醒")
	await seconds(3.0)
	check(sl.npc.position.x < Sleeper.START.x - 1.5, "他顺着栈道往西走（走了 %.1f 米）" % (Sleeper.START.x - sl.npc.position.x))
	await seconds(Sleeper.CHAPTER_END_AFTER - 2.5)
	check(GameState.has_flag("ch1_done") and GameState.quest_stage("ch1_main") == "ch1_end" and main.ending_panel.visible and main.ending_panel.title.text == "第二章 · 熄灭的烽燧" and main.ending_panel.header.text == "第一章「黑鹭堡」完",
		"过一会儿：章末画面「第一章「黑鹭堡」完 · 第二章 · 熄灭的烽燧 · 开发中」")
	var rc: String = main.ending_panel.recap.text
	var hk: String = main.ending_panel.seal.text
	check(rc.contains("印戒交给了阿尔里克") and rc.contains("堤道守住了") and rc.contains("奥弗") and hk.contains("老王自己交出去的") and hk.contains("双钥港") and hk.contains("没有醒来"),
		"回顾按旗标写（印戒、堤道、奥弗），钩子带上双钥港和长眠者（%s / %s）" % [rc, hk])
	check(main.ending_panel.continue_btn.visible and main.ending_panel.continue_btn.text == "继续：第二章 · 熄灭的烽燧" and main.ending_panel.back_btn.text == "在晨雾里再走走",
		"第二章做到章末了（5.8b）：「%s」「在晨雾里再走走」「从头再来」" % main.ending_panel.continue_btn.text)
	main.ending_panel.close()
	await frames(2)
	check(not get_tree().paused, "关掉画面接着走")
	var auto := Saves.read_slot("auto")
	check(str(auto.data.state.quests.ch1_main.stage) == "ch1_end", "章末自动存档")
	await free_main(main)
	main = await make_main_marsh()
	check(main.sleeper == null and main.world.get_node_or_null("Npc_boatman") == null, "以后再来：他走了，码头上没人")
	await free_main(main)
	# 失守、被押进病房的回顾
	GameState.set_flag("ch1_causeway", "lost")
	GameState.set_flag("ch1_sneak", "caught")
	check(Chapter1.recap().contains("新家主从此不信你") and Chapter1.recap().contains("伊薇特入主黑鹭堡"), "失守、被押进去的回顾：伊薇特入主黑鹭堡，新家主不信你")
	GameState.new_game()


## B.6a：军阵的兵换上真人外观——按兵种挑打扮、阵营色、胸前布带、铁盔、手里的兵器和盾；近处模型远处胶囊；动作跟着状态走
func test_uniforms() -> void:
	check(Looks.validate().is_empty(), "looks.json 的 soldiers 一节通过校验（兵种、预设、发型都认得）")
	GameState.new_game(7)
	var main := await make_battle()
	var b: Battle = main.battle
	var white := soldiers_of(main, "white")
	var black := soldiers_of(main, "black")
	var all_s: Array = white + black
	check(all_s.all(func(x): return x.dressed != null and x.model != null and x.model.loaded), "两边 %d 个兵都穿上了真人外观" % all_s.size())
	var by := func(list: Array, k: String) -> Soldier:
		for x in list:
			if x.kind == k:
				return x
		return null
	var lv: Soldier = by.call(white, "levy")
	var sw: Soldier = by.call(white, "soldier")
	var ar: Soldier = by.call(white, "archer")
	check(str(lv.model.parts[0]).ends_with("Outfit_Male_Peasant.gltf") and str(sw.model.parts[0]).ends_with("Outfit_Male_Ranger.gltf"), "民兵穿平民的衣服，剑兵穿游侠那套")
	var hood := func(x: Soldier) -> bool: return x.dressed.merged != null and Array(x.dressed.merged.get_meta("parts")).has("Male_Ranger_Head_Hood") if x.dressed.merged else (x.model.scene_root.find_child("Male_Ranger_Head_Hood", true, false) as Node3D).visible
	check(hood.call(ar) and not hood.call(sw), "弓手戴着兜帽，剑兵摘了")
	var tw := str(sw.model.look.tint.get("MI_Ranger", ""))
	var tb := str((by.call(black, "soldier") as Soldier).model.look.tint.get("MI_Ranger", ""))
	check(tw != "" and tb != "" and tw != tb, "外衣按阵营染色（白带 %s、黑带 %s）" % [tw, tb])
	var props := func(x: Soldier) -> Array: return x.model.find_children("Prop_*", "", true, false).map(func(n): return str(n.name))
	var sh: Soldier = by.call(white, "shield")
	var sp: Soldier = by.call(white, "spear")
	check(props.call(sw).has("Prop_sword") and props.call(lv).has("Prop_club") and props.call(sp).has("Prop_spear") and props.call(ar).has("Prop_bow") and props.call(sh).has("Prop_shield") and not props.call(sw).has("Prop_shield"),
		"手里的东西：剑、棍、长枪、弓；盾兵左手一面圆盾（%s）" % str(props.call(sh)))
	var helmets := all_s.filter(func(x): return x.model.skeleton.find_children("*", "BoneAttachment3D", false, false).any(func(a): return a.bone_name == "Head"))
	var cap: Soldier = captain_of(white)
	check(cap.model.skeleton.find_children("*", "BoneAttachment3D", false, false).any(func(a): return a.bone_name == "Head") and helmets.size() > 2 and helmets.size() < all_s.size(), "队长戴铁盔；一部分兵戴（%d / %d）" % [helmets.size(), all_s.size()])
	await physics(20)
	var cam := main.get_viewport().get_camera_3d()
	var near: Array = all_s.filter(func(x): return x.dressed.is_near())
	var nearest: Array = all_s.duplicate()
	nearest.sort_custom(func(a, c): return a.global_position.distance_to(cam.global_position) < c.global_position.distance_to(cam.global_position))
	var swap_ok: bool = all_s.all(func(x): return x.dressed.is_near() != x.look.visible and x.model.visible == x.dressed.is_near())
	check(near.size() >= 1 and near.size() <= SoldierLook.MAX_NEAR and nearest[0].dressed.is_near() and swap_ok,
		"离镜头最近的兵画真人（%d 个，最多 %d 个、%.0f 米内），其余画合并好的胶囊；画真人的时候胶囊藏起来" % [near.size(), SoldierLook.MAX_NEAR, SoldierLook.MODEL_FAR])
	var crowd := all_s.duplicate()
	for x in crowd:
		x.global_position = cam.global_position + Vector3(randf_range(-4, 4), -1.6, -6.0)
	await physics(20)
	check(all_s.filter(func(x): return x.dressed.is_near()).size() == SoldierLook.MAX_NEAR, "%d 个兵全挤在镜头前：也只画 %d 个真人（绘制调用有上限）" % [all_s.size(), SoldierLook.MAX_NEAR])
	check(all_s.all(func(x): return x.body.find_children("*", "MeshInstance3D", true, false).size() == 2), "占位胶囊照旧是两份网格（B.5 的绘制调用不变）")
	# 动作：站着持剑；出招；倒下；跪地求饶（要看动作的几个先换成真人，军阵先不排）
	b.look_t = 1e9
	for x in [sw, sp, lv]:
		x.dressed.set_near(true)
	await frames(3)
	check(sw.model.role in ["idle_armed", "walk", "run"], "开打前：持剑站着（%s）" % sw.model.role)
	b.start()
	sw._enter(Enemy.State.COMBAT)
	sw.attack_kind = "light"
	sw.action = "windup"
	sw.action_t = 0.0
	await frames(3)
	check(sw.model.playing() in ["Sword_Regular_A", "Sword_Regular_B"], "剑兵起手：播轻击（%s）" % sw.model.playing())
	sp._enter(Enemy.State.COMBAT)
	sp.action = "windup"
	sp.action_t = 0.0
	await frames(3)
	check(sp.model.playing() == "Sword_Dash", "长枪兵出招：往前突刺（%s）" % sp.model.playing())
	lv.take_hit({"damage": 999, "kind": "heavy", "stop": 0.0, "attacker": black[0]})
	await frames(3)
	check(lv.model.role in ["death", "kneel_fix"], "民兵倒下或跪地求饶：%s（%s）" % [lv.model.role, lv.state_name()])
	await free_main(main)
	Soldier.models_on = false
	GameState.new_game(7)
	main = await make_battle()
	check(soldiers_of(main, "white").all(func(x): return x.dressed == null), "关掉（基准测试比较用）：还是胶囊")
	await free_main(main)
	Soldier.models_on = true


## B.6b：少画几次（布带 / 铁盔 / 兵器 / 盾各压成一份，衣服、头、头发合成一块蒙皮网格）；弓手拉弓的姿势；军阵以外的敌人也穿上
func test_uniforms2() -> void:
	SoldierLook.merge_on = false
	GameState.new_game(7)
	var main := await make_battle()
	var raw := soldiers_of(main, "white").map(func(x): x.dressed.set_near(true); return x.dressed.draw_surfaces())
	await free_main(main)
	SoldierLook.merge_on = true
	GameState.new_game(7)
	main = await make_battle()
	var b: Battle = main.battle
	b.look_t = 1e9
	var white := soldiers_of(main, "white")
	var merged := white.map(func(x): x.dressed.set_near(true); return x.dressed.draw_surfaces())
	var avg := func(a: Array) -> float: return float(a.reduce(func(s, v): return s + v, 0)) / a.size()
	check(white.all(func(x): return x.dressed.merged != null and x.dressed.merged.skin.get_bind_count() > 10) and avg.call(merged) < avg.call(raw) * 0.7,
		"每个兵少画几次：合并前平均 %.1f 次、合并后 %.1f 次（%s）" % [avg.call(raw), avg.call(merged), str(merged)])
	var sw: Soldier = white.filter(func(x): return x.kind == "soldier")[0]
	await frames(4)
	var head := sw.model.skeleton.get_bone_global_pose(sw.model.skeleton.find_bone("Head")).origin
	check(head.y > 1.1 and head.y < 1.9 and sw.dressed.merged.visible and Array(sw.dressed.merged.get_meta("parts")).size() >= 3, "合并以后网格挂在同一副骨架上（头在 %.2f 米高，合了 %d 块）" % [head.y, Array(sw.dressed.merged.get_meta("parts")).size()])
	# 弓手：弓在左手；拉弓时左臂伸向前
	var ar: Soldier = white.filter(func(x): return x.kind == "archer")[0]
	var lh := ar.model.skeleton.get_node_or_null("HandL")
	check(ar.dressed.bow != null and lh != null and lh.find_child("Prop_bow", true, false) != null, "弓手左手拿弓，骨架上有拉弓的修改器")
	var sk := ar.model.skeleton
	var hand_l := sk.get_node("HandL") as Node3D          # 骨头挂件跟着修改器以后的姿势走（get_bone_global_pose 是动作本身的姿势）
	var fwd := func() -> float: return (hand_l.global_position - ar.global_position).dot(-ar.global_transform.basis.z)
	await frames(4)
	var before: float = fwd.call()
	b.start()
	ar._enter(Enemy.State.COMBAT)
	ar.action = "draw"
	await seconds(0.6)
	ar.action = "draw"
	await frames(3)
	var after: float = fwd.call()
	check(ar.dressed.bow.influence > 0.8 and after > before + 0.15, "拉弓：左手伸到身前（%.2f → %.2f 米）" % [before, after])
	await free_main(main)
	# 军阵以外的敌人：哨卡的无旗者穿上了；营地对峙说崩了，换成的敌人和原来那个人穿同一身
	GameState.new_game(1)
	GameState.pending_load = {"scene": "birch", "spawn": "north", "player": {}}
	main = await make_main(false)
	await physics(3)
	var outlaws: Array = get_tree().get_nodes_in_group("enemy").filter(func(e): return not e is Soldier)
	check(not outlaws.is_empty() and outlaws.all(func(e): return e.outfit != null and e.outfit.is_near() and not e.body.visible), "桦林哨卡的无旗者穿上了真人外观（%d 个），占位身子藏起来" % outlaws.size())
	await free_main(main)
	ch1_state("deliver")
	GameState.flags.erase("offer_left")
	GameState.pending_load = {"scene": "marsh", "spawn": "reedwharf", "player": {}}
	main = await make_main(false)
	await physics(2)
	var offer := main.world.get_node_or_null("Npc_offer_camp") as Npc
	var npc_parts: Array = offer.look_model.parts.duplicate() if offer and offer.look_model else []
	main.start_encounter(MarshLayout.CAMP_ENCOUNTER, "")
	await frames(3)
	var boss: Array = get_tree().get_nodes_in_group("enemy").filter(func(e): return e.display_name == "「灰手」奥弗")
	check(not npc_parts.is_empty() and boss.size() == 1 and boss[0].outfit != null and boss[0].outfit.model.parts == npc_parts, "营地对峙说崩了：奥弗换成敌人，还是原来那一身")
	await free_main(main)
	GameState.new_game()


## A.2a：NPC 换上真人模型（data/looks.json）
func test_looks() -> void:
	# —— 头只留脖子以上（2026-10-23：只按高度切时 T 姿势的两肩和整条胳膊也留着，从衣服里戳出来）
	for hf in ["Head_Male", "Head_Female"]:
		var hs := (load(Looks.DIR + hf + ".gltf") as PackedScene).instantiate() as Node3D
		var wide := 0.0
		for mi: MeshInstance3D in hs.find_children("*", "MeshInstance3D", true, false):
			var bb := mi.get_aabb()
			wide = maxf(wide, maxf(absf(bb.position.x), absf(bb.end.x)))
		hs.free()
		check(wide <= 0.13, "%s 只有脖子这么宽（左右最远 %.2f 米），不带肩膀和胳膊" % [hf, wide])
	var gm := CharacterModel.new()
	gm.parts = Looks.spec("老霍布").parts
	add_child(gm)
	await frames(2)
	var grow_ok := true
	for mi: MeshInstance3D in gm.scene_root.find_children("*", "MeshInstance3D", true, false):
		for si in mi.mesh.get_surface_count():
			var mm := mi.get_surface_override_material(si) as StandardMaterial3D
			if mm and CharacterModel.GROW.has(mm.resource_name):
				grow_ok = grow_ok and mm.grow and is_equal_approx(mm.grow_amount, float(CharacterModel.GROW[mm.resource_name]))
	check(grow_ok, "衣服往外撑一点、胳膊皮肤往里收一点（不从袖子里戳出来）")
	gm.queue_free()
	await frames(2)
	Settings.set_value("third_person", false)
	check(Looks.validate().is_empty(), "looks.json：预设、部件、贴图、颜色都对得上（%s）" % str(Looks.validate()))
	var v := Looks.spec("维克托")
	check(v.parts.size() == 4 and str(v.parts[0]).ends_with("Outfit_Male_Peasant.gltf") and str(v.parts[1]).ends_with("Head_Male.gltf") and v.look.tint.get("MI_Hair_1") == "#4a3a2a" and v.look.tint.get("MI_Peasant") == "#7a4a44",
		"维克托：平民那套换成深红、男头、分头加胡子、深棕发色")
	check(Looks.spec("灰盒路人").is_empty() and Looks.pose("奥斯瑞克") == "lying", "没配的人（测试场的路人）照旧是胶囊；躺着的家主也穿上了（A.2b）")
	check(Looks.pose("更夫") == "lantern" and Looks.prop("更夫") == "lantern" and Looks.pose("泥炭工", "Npc_peat_cutter") == "chop" and Looks.pose("泥炭工", "Npc_peat_stacker") == "kneel_fix",
		"A.2b 站姿：更夫提灯；两个泥炭工一个挖、一个跪着码垛（按节点编号分开配）")
	# 搭出来：头、头发挂在服装的骨架上，兜帽摘了
	var m := Looks.make("赫尔曼")
	add_child(m)
	Looks.finish(m)
	await frames(2)
	var meshes: Array = m.scene_root.find_children("*", "MeshInstance3D", true, false)
	var on_skel := meshes.all(func(mi): return mi.get_node_or_null(mi.skeleton) == m.skeleton)
	var names := meshes.map(func(mi): return str(mi.name))
	check(m.loaded and on_skel and names.has("Hair_Beard") and not (m.scene_root.find_child("Male_Ranger_Head_Hood", true, false) as Node3D).visible and meshes.all(func(mi): return mi.visibility_range_end == Looks.LOD_FAR),
		"赫尔曼：游侠那套、兜帽摘了、胡子挂在同一副骨架上、远处不画（%d 个网格）" % meshes.size())
	m.play_loop("idle")
	check(m.playing() != "", "能放站着的动作")
	m.queue_free()
	# 场景里：配了的人穿上、近处画模型远处画胶囊；对峙那一组、躺着的、没配的还是胶囊
	ch1_state("deliver")
	GameState.set_flag("ch1_victor_done")
	GameState.pending_load = {"scene": "frostford", "spawn": "", "player": {}}
	var main := await make_main(false)
	await physics(2)
	var victor := main.world.find_child("Npc_victor", true, false) as Npc
	if victor == null:
		for n in main.world.find_children("*", "Npc", true, false):
			if (n as Npc).display_name == "维克托":
				victor = n
	check(victor != null and victor.look_model != null and victor.look_model.loaded and victor.find_child("Coat", true, false).visibility_range_begin == Looks.LOD_FAR,
		"霜渡镇：维克托穿上了（近处画模型，%d 米外换回胶囊）" % int(Looks.LOD_FAR))
	await free_main(main)
	GameState.pending_load = {"scene": "tavern", "spawn": "", "player": {}}
	main = await make_main(false)
	await physics(2)
	var dressed := []
	var plain := []
	for n in main.world.find_children("*", "Npc", true, false):
		(dressed if (n as Npc).look_model != null else plain).append((n as Npc).display_name)
	check(dressed.has("玛蒂尔达") and plain.has("大桶"), "酒馆：玛蒂尔达穿上了，要打一架的大桶照旧是胶囊（穿上：%s；胶囊：%s）" % [str(dressed), str(plain)])
	var matilda: Npc = null
	var woodcutter: Npc = null
	for n in main.world.find_children("*", "Npc", true, false):
		if (n as Npc).display_name == "玛蒂尔达":
			matilda = n
		if (n as Npc).display_name == "伐木工":
			woodcutter = n
	check(matilda.look_model.role == "rail" and woodcutter.look_model.role == "drink" and woodcutter.look_model.skeleton.find_child("Prop_cup", true, false) != null,
		"A.2b：玛蒂尔达靠着吧台，伐木工左手端着杯子喝")
	var ph := [matilda.look_model.anim.current_animation_position, woodcutter.look_model.anim.speed_scale]
	check(absf(woodcutter.look_model.anim.speed_scale - 1.0) <= 0.121, "每个人动作快慢、起点不一样（%s）" % str(ph))
	main.open_dialogue("tavern", "matilda", matilda)
	await frames(2)
	check(matilda.look_model.role == "talk" and matilda.look_model.process_mode == Node.PROCESS_MODE_ALWAYS, "对话开始：玛蒂尔达比划着说（游戏暂停时她照样动）")
	main.dialogue.close()
	await frames(2)
	check(matilda.look_model.role == "rail" and not matilda.talking and matilda.look_model.process_mode == Node.PROCESS_MODE_INHERIT, "对话结束：回到靠着吧台")
	await free_main(main)
	ch1_state("deliver")
	GameState.flags.erase("offer_left")
	GameState.pending_load = {"scene": "marsh", "spawn": "reedwharf", "player": {}}
	main = await make_main(false)
	await physics(2)
	var offer := main.world.get_node_or_null("Npc_offer_camp") as Npc
	var tobin := main.world.get_node_or_null("Npc_tobin") as Npc
	check(offer != null and offer.look_model != null and tobin != null and tobin.look_model != null, "鹭沼：托宾穿上了；营地里能打起来的那伙人也穿上了（B.6b：开打时换成的敌人穿同一身）")
	var stacker := main.world.get_node_or_null("Npc_peat_stacker") as Npc
	var cutter := main.world.get_node_or_null("Npc_peat_cutter") as Npc
	check(stacker.look_model.role == "kneel_fix" and cutter.look_model.role == "chop" and cutter.look_model.grip.find_child("Prop_axe", true, false) != null, "泥炭场：一个跪着码垛、一个抡斧头挖")
	await free_main(main)
	# 家主：躺在床上（LayToIdle 第一帧），黄昏醒了撑着半坐起来
	heir_state()
	GameState.pending_load = {"scene": "sickroom", "spawn": "front", "player": {}}
	main = await make_main(false)
	await physics(2)
	var osric := main.world.get_node("Npc_osric") as Npc
	check(osric.look_model != null and osric.look_model.role == "lying" and osric.look_model.anim.current_animation_position < 0.05, "病房：家主穿上了，平躺在床上")
	GameState.set_flag("osric_awake")
	Sickroom.wake(main.world)
	await frames(2)
	check(absf(osric.look_model.anim.current_animation_position - 0.5) < 0.05, "家主醒了：撑着胳膊半坐起来")
	await free_main(main)
	GameState.new_game()


## 5.1a 余火高地地图底座：高度场、碰撞、分块、天空、风雪、章节包与第二章的入口
func test_plain() -> void:
	check(Areas.known("plain") and Areas.display_name("plain") == "金穗平原" and Areas.pack_chapter("plain") == 3 and Chapters.known(3) and Chapters.pack_of(3) == "ch3" and Chapters.PLAYABLE == 2 and Chapters.wip_of(3) != "",
		"金穗平原登记了：内容在第三章章节包（ch3）里；第三章还没对玩家打开（PLAYABLE = %d、标着制作中）" % Chapters.PLAYABLE)
	check(Plain.textures_ready() and ResourceLoader.exists(Plain.FIELD_PATH) and ResourceLoader.exists(Plain.PAINT_PATH), "第三章的贴图、天空照片、预先算好的高度场都在 chapters/ch3/")
	var tex_ok := true
	for layer: String in Plain.LAYERS.values():
		for kind in ["diff", "nor_gl"]:
			if not ResourceLoader.exists(Plain.TEX_DIR % [layer, kind]):
				tex_ok = false
	check(tex_ok, "地面四层贴图（雪田、泥雪路、麦茬土、泥岸）各有颜色和法线")
	Plain._field = PackedFloat32Array()
	Plain.ensure_field()
	var rng := RandomNumberGenerator.new()
	rng.seed = 61
	var worst := 0.0
	var paint_worst := 0.0
	for k in 300:
		var i := rng.randi_range(0, PlainLayout.NX - 1)
		var j := rng.randi_range(0, PlainLayout.NZ - 1)
		var x := PlainLayout.BOUNDS.position.x + i * PlainLayout.STEP
		var z := PlainLayout.BOUNDS.position.y + j * PlainLayout.STEP
		worst = maxf(worst, absf(Plain._field[j * PlainLayout.NX + i] - PlainLayout.height(x, z)))
		var m := PlainLayout.masks(x, z)
		var c := Plain._paint[j * PlainLayout.NX + i]
		paint_worst = maxf(paint_worst, maxf(absf(c.r - m.x), maxf(absf(c.g - m.y), absf(c.b - m.z))))
	check(worst < 0.01 and paint_worst < 0.01 and Plain.field_ms < 200.0, "高度场、地面颜色图和布局一致（最大差 %.4f 米 / %.4f；不一致就跑 tests/gen_plain_field.gd）；读文件 %.0f 毫秒" % [worst, paint_worst, Plain.field_ms])
	# 平原是平的（起伏不过十来米）；河：水面比河床高、比两岸低；庄园在坡上、坠星院在丘顶
	var lo := INF
	var hi := -INF
	for v in Plain._field:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	var river_ok := true
	var bed_max := -INF
	for k in range(1, PlainLayout.RIVER.size() - 1):
		var c: Vector2 = PlainLayout.RIVER[k]
		if not PlainLayout.BOUNDS.grow(-10.0).has_point(c):
			continue
		var bed := PlainLayout.height(c.x, c.y)
		bed_max = maxf(bed_max, bed)
		var a: Vector2 = PlainLayout.RIVER[k - 1]
		var b: Vector2 = PlainLayout.RIVER[k + 1]
		var n := Vector2(-(b - a).y, (b - a).x).normalized()
		for sgn in [-1.0, 1.0]:
			var q: Vector2 = c + n * sgn * (PlainLayout.RIVER_HALF + PlainLayout.RIVER_BANK + 3.0)
			if PlainLayout.height(q.x, q.y) < PlainLayout.WATER_Y + 1.0:
				river_ok = false
	var flat := PlainLayout.height(PlainLayout.VILLAGE.x, PlainLayout.VILLAGE.y)
	var manor := PlainLayout.height(PlainLayout.MANOR.x, PlainLayout.MANOR.y)
	var abbey := PlainLayout.height(PlainLayout.ABBEY.x, PlainLayout.ABBEY.y)
	check(hi - lo < 16.0 and river_ok and bed_max < PlainLayout.WATER_Y and manor - flat > 4.0 and abbey - flat > 5.0,
		"地形高差 %.1f 米（平原）；河床最高 %.2f 米低于水面 %.2f、两岸高出水面；庄园比村子高 %.1f 米、坠星院丘顶高 %.1f 米" % [hi - lo, bed_max, PlainLayout.WATER_Y, manor - flat, abbey - flat])
	var sp_ok := true
	for id: String in PlainLayout.SPAWN_XZ:
		var xz: Vector2 = PlainLayout.SPAWN_XZ[id][0]
		if PlainLayout.river_d(xz) < PlainLayout.RIVER_HALF + 1.5 or PlainLayout.height(xz.x, xz.y) < PlainLayout.WATER_Y + 0.5:
			sp_ok = false
	check(sp_ok and PlainLayout.SPAWN_XZ.has("dock") and Chapters.LIST[3].spawn == "dock", "%d 个出生点都在岸上、不在水里；第三章从渡口上岸" % PlainLayout.SPAWN_XZ.size())
	GameState.new_game(610)
	GameState.daypart = "day"
	var main := await make_area("plain")
	var space := main.get_world_3d().direct_space_state
	var col_worst := 0.0
	for k in 60:
		var x := rng.randf_range(-140.0, 140.0)
		var z := rng.randf_range(-120.0, 120.0)
		var rq := PhysicsRayQueryParameters3D.create(Vector3(x, 100.0, z), Vector3(x, -50.0, z), 1)
		rq.exclude = [(main.world.find_child("PlainFlora", true, false) as StaticBody3D).get_rid()]     # 树干、麦垛、篱笆不算（6.1b）
		var hit: Dictionary = space.intersect_ray(rq)
		col_worst = maxf(col_worst, absf((float(hit.position.y) if not hit.is_empty() else -999.0) - Plain.height_at(x, z)))
	check(col_worst < 0.05, "碰撞（高度图）和地形一致（60 个点最大差 %.3f 米）" % col_worst)
	await physics(10)
	var p: FpController = main.player
	var sp: Vector3 = Plain.spawn_points().dock[0]
	check(p.is_on_floor() and p.global_position.distance_to(sp) < 0.4, "新开进平原：站在渡口（%s）" % p.global_position)
	var st: ChunkStreamer = main.streamer
	st.build_all()
	check(st.chunks.size() == 25 and st.is_done() and float(st.stats.max_job_ms) < 60.0, "地形 %d 块全搭完，最慢一块 %.1f 毫秒" % [st.chunks.size(), st.stats.max_job_ms])
	check(main.world.find_child("RiverWater", true, false) != null and main.world.find_child("FarTerrain", true, false) != null and main.world.find_children("TerrainFar", "MeshInstance3D", true, false).size() == 25,
		"有河面、地图外的远景（砧山）、每块远处一份粗网格")
	var views_ok := Areas.views("plain").size() == PlainLayout.VIEW_NAMES.size()
	for v: Array in Areas.views("plain"):
		var vp: Vector3 = v[0]
		if absf(vp.y - 1.7 - Plain.height_at(vp.x, vp.z)) > 0.05 or PlainLayout.river_d(Vector2(vp.x, vp.z)) < PlainLayout.RIVER_HALF:
			views_ok = false
	check(views_ok, "%d 个固定机位都在岸上、地面上方 1.7 米" % PlainLayout.VIEW_NAMES.size())
	var env: Environment = main.env
	check(env.background_mode == Environment.BG_SKY and env.sky != null and Daypart.preset("plain", "day").fog_end > 0.0 and Cold.COLD_AREAS.get("plain", 0.0) < Cold.COLD_AREAS.highland,
		"天空是雾蒙蒙的冬天照片；平原有自己的时段预设；没有高地冷")
	await free_main(main)


func test_plainflora() -> void:
	PlainFlora.clear_cache()
	check(ResourceLoader.exists(PlainFlora.TWIG_TEX), "枝条贴图（代码画的：细枝、柳条、整棵树剪影）在第三章章节包里")
	var ws := PlainFlora.willows()
	var on_bank := true
	for w: Array in ws:
		var p := Vector2((w[0] as Vector3).x, (w[0] as Vector3).z)
		var d := PlainLayout.river_d(p)
		if d < PlainLayout.RIVER_HALF + 3.0 or d > PlainLayout.RIVER_HALF + 8.6 or PlainLayout.road_d(p) < PlainLayout.ROAD_HALF + 2.0:
			on_bank = false
	check(ws.size() >= 20 and on_bank, "麦河两岸 %d 棵截头柳，都在岸坡上（不下水、不上路）" % ws.size())
	var hs := PlainFlora.hedges()
	var ts := PlainFlora.trees()
	var clean := true
	for it: Array in hs + ts:
		var p := Vector2((it[0] as Vector3).x, (it[0] as Vector3).z)
		if PlainLayout.road_d(p) < PlainLayout.ROAD_HALF + 1.5 or PlainLayout.river_d(p) < PlainLayout.RIVER_HALF + PlainLayout.RIVER_BANK or p.distance_to(PlainLayout.VILLAGE) < PlainLayout.VILLAGE_R or p.distance_to(PlainLayout.MANOR) < PlainLayout.MANOR_R:
			clean = false
	check(hs.size() >= 400 and ts.size() >= 25 and clean and PlainFlora.hedge_runs().size() > hs.size() / 40,
		"田边 %d 丛篱笆（%d 段，段与段之间有豁口）、%d 棵落叶树；都不上路、不下河、不进村子和庄园" % [hs.size(), PlainFlora.hedge_runs().size(), ts.size()])
	var big := 0
	var small := 0
	var small_max := 0.0
	var big_min := 9.0
	for rk: Array in PlainFlora.ricks():
		var p := Vector2((rk[0] as Vector3).x, (rk[0] as Vector3).z)
		if bool(rk[3]):
			small += 1
			small_max = maxf(small_max, float(rk[2]))
		else:
			big += 1
			big_min = minf(big_min, float(rk[2]))
		if PlainLayout.road_d(p) < PlainLayout.ROAD_HALF + 3.0:
			clean = false
	check(big >= 10 and small >= 1 and small <= 3 and small_max < big_min * 0.8 and clean,
		"麦垛：洛蒙德家的田里 %d 个大的，佃农村边上 %d 个小的（最大 %.2f，比大垛最小的 %.2f 小一大截）——囤粮和挨饿" % [big, small, small_max, big_min])
	var fs := PlainFlora.fences()
	var fence_ok := fs.size() >= 30
	for f: Array in fs:
		var a: Vector3 = f[0]
		var b: Vector3 = f[1]
		var m := Vector2(a.x + b.x, a.z + b.z) * 0.5
		if PlainLayout.road_d(m) < PlainLayout.ROAD_HALF + 1.0 or absf(Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z)) - PlainFlora.FENCE_BAY) > 0.6:
			fence_ok = false
	check(fence_ok, "木栅 %d 跨：洛蒙德家的两处麦垛场四面围着、留门，路边一段；每跨约 %.1f 米、不压路" % [fs.size(), PlainFlora.FENCE_BAY])
	var far := PlainFlora.far_trees()
	var outside := true
	for t: Array in far:
		if PlainLayout.BOUNDS.has_point(Vector2((t[0] as Vector3).x, (t[0] as Vector3).z)):
			outside = false
	check(far.size() >= 500 and outside, "地平线上 %d 棵树（都在地图外面）" % far.size())
	GameState.new_game(611)
	GameState.daypart = "day"
	var main := await make_area("plain")
	var st: ChunkStreamer = main.streamer
	st.build_all()
	var nodes := get_tree().get_nodes_in_group("plain_flora")
	var inst := 0
	for n: MultiMeshInstance3D in nodes:
		inst += n.multimesh.instance_count
	check(main.world.find_child("FarTrees", true, false) != null and inst >= hs.size() + ws.size() and float(st.stats.max_job_ms) < 60.0,
		"分块搭完：%d 个多实例、%d 个实例；最慢一块 %.1f 毫秒" % [nodes.size(), inst, st.stats.max_job_ms])
	var body := main.world.find_child("PlainFlora", true, false) as StaticBody3D
	check(body != null and body.get_child_count() >= ts.size() + ws.size() + PlainFlora.ricks().size() + fs.size(), "树干、麦垛、篱笆、木栅有碰撞（%d 个）" % (body.get_child_count() if body else 0))
	# 走过去撞上一个麦垛
	await physics(6)
	var p: FpController = main.player
	var rk0: Array = PlainFlora.ricks()[0]
	var rp: Vector3 = rk0[0]
	var from := rp + Vector3(0, 0, 6.0 + 2.0 * float(rk0[2]))
	p.global_position = Vector3(from.x, Plain.height_at(from.x, from.z) + 0.3, from.z)
	p.rotation.y = 0.0                                # 面朝 -Z（朝麦垛）
	p.velocity = Vector3.ZERO
	await physics(6)
	Input.action_press("move_forward")
	await seconds(2.5)
	Input.action_release("move_forward")
	var gap := Vector2(p.global_position.x - rp.x, p.global_position.z - rp.z).length()
	check(gap > 1.9 * float(rk0[2]), "往麦垛走，被挡在外面（离中心 %.1f 米）" % gap)
	check(is_equal_approx(float(PlainFlora.material("twig").get_shader_parameter("wind")), 1.0), "枝条风里轻轻摆")
	await free_main(main)
	var tw := PlainFlora.material("twig", true)
	check(is_zero_approx(float(tw.get_shader_parameter("wind"))), "「减少动态效果」打开时不摆")
	PlainFlora.material("twig", false)


func test_maidu() -> void:
	# 布局：长屋、谷仓不压路、不下河；木桥两头落在岸上、中间拱起来高过水面；栈桥伸到水上
	var clear := true
	for h: Array in PlainVillage.LONGHOUSES + [["barn", PlainVillage.BARN[0]]]:
		var c: Vector2 = h[1]
		if PlainLayout.road_d(c) < PlainLayout.ROAD_HALF + 3.0 or PlainLayout.river_d(c) < PlainLayout.RIVER_HALF + PlainLayout.RIVER_BANK:
			clear = false
	var smoke := PlainVillage.LONGHOUSES.filter(func(h: Array) -> bool: return bool(h[5])).size()
	var holes := PlainVillage.LONGHOUSES.filter(func(h: Array) -> bool: return int(h[6]) >= 0).size()
	check(PlainVillage.LONGHOUSES.size() == 6 and clear and smoke == 2 and holes == 2,
		"麦渡：6 栋长屋（只有 %d 栋冒烟、%d 栋屋顶塌了一块）和谷仓，都不压路、不下河" % [smoke, holes])
	var mid_y := PlainVillage.bridge_y(0.5)
	var a: Vector2 = PlainLayout.BRIDGE[0]
	var b: Vector2 = PlainLayout.BRIDGE[1]
	check(PlainLayout.river_d(a) > PlainLayout.RIVER_HALF + 2.0 and PlainLayout.river_d(b) > PlainLayout.RIVER_HALF + 2.0 and mid_y > PlainLayout.WATER_Y + 1.5 and absf(PlainVillage.bridge_y(0.0) - PlainLayout.height(a.x, a.y)) < 0.3,
		"木桥两头在岸上、桥面中间比水面高 %.1f 米" % (mid_y - PlainLayout.WATER_Y))
	check(PlainLayout.river_d(PlainVillage.DOCK_TO) < PlainLayout.RIVER_HALF + 0.5 and PlainVillage.dock_y() > PlainLayout.WATER_Y + 0.8, "栈桥伸到水上（头上离河中线 %.1f 米）" % PlainLayout.river_d(PlainVillage.DOCK_TO))
	check(Travel.validate().is_empty() and Travel.region_title(3) == "南部" and Travel.places(3) == ["maidu", "mill", "manor", "abbey", "camp"] and Travel.built("maidu") and not Travel.built("abbey") and Travel.region_of_chapter(2) == "north",
		"旅行地图第三章是「南部」一页：麦渡（做好了）、磨坊、庄园、坠星院、营地（还没做好）；第二章还是北境北部 %s" % str(Travel.validate()))
	GameState.new_game(620)
	GameState.chapter = 3
	GameState.daypart = "day"
	var main := await make_area("plain")
	var st: ChunkStreamer = main.streamer
	st.build_all()
	await frames(2)
	var houses := main.world.find_children("Longhouse_*", "Node3D", true, false)
	check(houses.size() == 6 and main.world.find_child("Barn", true, false) != null and main.world.find_child("Bridge", true, false) != null and main.world.find_child("Dock", true, false) != null and main.world.find_child("Well", true, false) != null,
		"分块搭完：%d 栋长屋、谷仓、木桥、渡口、水井" % houses.size())
	var doors := main.world.find_children("LonghouseDoor_*", "", true, false)
	check(doors.size() == 5 and (doors[0] as Door).locked, "5 扇门（空屋没门），都闩着")
	# 走过木桥：从西头走到东头，一直踩在桥面上，没掉进河里
	await physics(6)
	var p: FpController = main.player
	var dir := (b - a).normalized()
	var start := a + dir * 1.0
	p.global_position = Vector3(start.x, PlainVillage.bridge_y(1.0 / a.distance_to(b)) + 0.4, start.y)
	p.rotation.y = atan2(-dir.x, -dir.y)
	p.velocity = Vector3.ZERO
	await physics(8)
	var min_y := INF
	Input.action_press("move_forward")
	Input.action_press("sprint")
	for k in 60:
		await seconds(0.1)
		min_y = minf(min_y, p.global_position.y)
	Input.action_release("sprint")
	Input.action_release("move_forward")
	var gone := Vector2(p.global_position.x, p.global_position.z).distance_to(start)
	check(gone > 20.0 and min_y > PlainLayout.WATER_Y + 0.5, "走过木桥：6 秒走了 %.1f 米，最低 %.2f 米（没掉进河）" % [gone, min_y])
	# 谷仓：大门敞着，走得进去
	var bo := PlainVillage.front_origin(PlainVillage.BARN[0], float(PlainVillage.BARN[1]), float(PlainVillage.BARN[3]))
	var fwd := Vector3(sin(deg_to_rad(float(PlainVillage.BARN[1]))), 0, cos(deg_to_rad(float(PlainVillage.BARN[1]))))
	var outside := bo + fwd * 4.0
	p.global_position = outside + Vector3(0, 0.4, 0)
	p.rotation.y = atan2(fwd.x, fwd.z)                  # 面朝谷仓（背对 fwd）
	p.velocity = Vector3.ZERO
	await physics(6)
	Input.action_press("move_forward")
	await seconds(2.0)
	Input.action_release("move_forward")
	check((p.global_position - bo).dot(fwd) < -1.0, "谷仓的大门敞着，走得进去（进去了 %.1f 米）" % -(p.global_position - bo).dot(fwd))
	# 村口的路牌：站在旁边打开地图是「南部」，在麦渡、能出发（但别处还没做好）
	p.global_position = Vector3(PlainVillage.SIGN_AT.x + 1.5, PlainLayout.height(PlainVillage.SIGN_AT.x + 1.5, PlainVillage.SIGN_AT.y) + 0.3, PlainVillage.SIGN_AT.y)
	await physics(4)
	check(main.near_travel_point() and Travel.place_of_area("plain", main.player_xz()) == "maidu", "村口路牌旁边：在麦渡、站在出发的地方")
	main.open_travel_map(true)
	await frames(2)
	check(main.travel_map.visible and main.travel_map.title.text.contains("南部") and main.travel_map.place_btns.size() == 5 and not Travel.check(3, "maidu", "abbey", true).ok,
		"旅行地图是「南部」，五个地点；坠星院还没做好：%s" % Travel.check(3, "maidu", "abbey", true).why)
	main.travel_map.close()
	get_tree().paused = false
	var spec := AreaMap.spec("plain")
	check(spec.shapes.filter(func(sh: Dictionary) -> bool: return sh.k == "house").size() == 7, "本地地图上画了 6 栋长屋和谷仓")
	await free_main(main)
	GameState.chapter = 0


func test_highland() -> void:
	check(Areas.known("highland") and Areas.pack_chapter("highland") == 2 and Chapters.known(2) and Chapters.pack_of(2) == "ch2" and Chapters.PLAYABLE == 2 and Chapters.wip_of(2) == "",
		"余火高地登记了：内容在第二章章节包（ch2）里；第二章对玩家打开了、做到章末不再标「制作中」（PLAYABLE = %d）" % Chapters.PLAYABLE)
	check(Highland.textures_ready() and ResourceLoader.exists(Highland.FIELD_PATH) and ResourceLoader.exists(Highland.PAINT_PATH), "第二章的贴图、天空照片、预先算好的高度场都在 chapters/ch2/")
	# 预先算好的高度场和布局对得上（布局改了忘了重新生成会在这里报）
	Highland._field = PackedFloat32Array()
	Highland.ensure_field()
	var rng := RandomNumberGenerator.new()
	rng.seed = 51
	var worst := 0.0
	for k in 300:
		var i := rng.randi_range(0, HighlandLayout.NX - 1)
		var j := rng.randi_range(0, HighlandLayout.NZ - 1)
		var x := HighlandLayout.BOUNDS.position.x + i * HighlandLayout.STEP
		var z := HighlandLayout.BOUNDS.position.y + j * HighlandLayout.STEP
		worst = maxf(worst, absf(Highland._field[j * HighlandLayout.NX + i] - HighlandLayout.height(x, z)))
	check(worst < 0.01 and Highland.field_ms < 200.0, "高度场文件和布局一致（300 个点最大差 %.4f 米；不一致就跑 tests/gen_highland_field.gd）；读文件 %.0f 毫秒" % [worst, Highland.field_ms])
	# 地形：有起伏（谷底到山脊 40 米上下）、盘山路每段坡度不超过 16%、村子是平的
	var lo := INF
	var hi := -INF
	for v in Highland._field:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	var steep := 0.0
	for i in HighlandLayout.ROAD.size() - 1:
		var len := (HighlandLayout.ROAD[i] as Vector2).distance_to(HighlandLayout.ROAD[i + 1])
		steep = maxf(steep, absf(HighlandLayout.road_y_at(i, 1.0) - HighlandLayout.road_y_at(i, 0.0)) / len)
	var v0 := HighlandLayout.height(HighlandLayout.VILLAGE.x - 20.0, HighlandLayout.VILLAGE.y)
	var v1 := HighlandLayout.height(HighlandLayout.VILLAGE.x + 20.0, HighlandLayout.VILLAGE.y)
	var b19 := HighlandLayout.height(HighlandLayout.BEACON19.x, HighlandLayout.BEACON19.y)
	check(hi - lo > 40.0 and steep <= 0.16 and absf(v0 - v1) < 0.6 and b19 - HighlandLayout.VILLAGE_Y > 35.0,
		"地形高差 %.0f 米；盘山路最陡一段 %.0f%%；村子两头差 %.2f 米；第十九烽比村子高 %.0f 米" % [hi - lo, steep * 100.0, absf(v0 - v1), b19 - HighlandLayout.VILLAGE_Y])
	# 伏击段：上坡一侧是岩坎（路边几米内高出好几米），下坡一侧是缓坡
	var a: Vector2 = HighlandLayout.ROAD[HighlandLayout.AMBUSH_LEG]
	var b: Vector2 = HighlandLayout.ROAD[HighlandLayout.AMBUSH_LEG + 1]
	var mid := (a + b) * 0.5
	var nrm := Vector2(-(b - a).y, (b - a).x).normalized()
	var up := nrm if HighlandLayout.height(mid.x + nrm.x * 8.0, mid.y + nrm.y * 8.0) > HighlandLayout.height(mid.x - nrm.x * 8.0, mid.y - nrm.y * 8.0) else -nrm
	var road_y := HighlandLayout.height(mid.x, mid.y)
	var wall := HighlandLayout.height(mid.x + up.x * 7.0, mid.y + up.y * 7.0) - road_y
	var dip := road_y - HighlandLayout.height(mid.x - up.x * 7.0, mid.y - up.y * 7.0)
	check(wall > 6.0 and dip < 4.0, "伏击段：上坡一侧离路 7 米高出 %.1f 米（岩坎），下坡一侧低 %.1f 米（缓坡）" % [wall, dip])
	# 载入：出生点、固定机位脚下都是地；碰撞和高度场一致；分块都搭得完、每件活不长
	GameState.new_game(510)
	GameState.daypart = "day"                         # 第二章从白天开始（Chapters.LIST[2]）
	var main := await make_area("highland")
	var space := main.get_world_3d().direct_space_state
	var hit_y := func(x: float, z: float) -> float:
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 200.0, z), Vector3(x, -50.0, z), 1)
		var h: Dictionary = space.intersect_ray(q)
		return float(h.position.y) if not h.is_empty() else -999.0
	var col_worst := 0.0
	for k in 60:
		var x := rng.randf_range(-150.0, 150.0)
		var z := rng.randf_range(-120.0, 120.0)
		col_worst = maxf(col_worst, absf(hit_y.call(x, z) - Highland.height_at(x, z)))
	check(col_worst < 0.05, "碰撞（高度图）和地形一致（60 个点最大差 %.3f 米）" % col_worst)
	await physics(10)
	var p: FpController = main.player
	var sp: Vector3 = Highland.spawn_points().village[0]
	check(p.is_on_floor() and p.global_position.distance_to(sp) < 0.4, "新开进高地：站在进村的路口（%s）" % p.global_position)
	var st: ChunkStreamer = main.streamer
	st.build_all()
	check(st.chunks.size() == 25 and st.is_done() and float(st.stats.max_job_ms) < 40.0, "地形 %d 块全搭完，最慢一块 %.1f 毫秒" % [st.chunks.size(), st.stats.max_job_ms])
	var t0: MeshInstance3D = main.world.find_children("Terrain", "MeshInstance3D", true, false)[0]
	var tf: MeshInstance3D = main.world.find_children("TerrainFar", "MeshInstance3D", true, false)[0]
	check(t0.visibility_range_end > 0.0 and tf.visibility_range_begin > 0.0 and t0.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and main.world.get_node_or_null("FarTerrain") != null,
		"每块近处一份 1 米网格、远处一份 4 米网格按距离切换；地形不投影子；地图外面有远景地形")
	var views_ok := Areas.views("highland").size() == HighlandLayout.VIEW_NAMES.size()
	for v: Array in Areas.views("highland"):
		var vp: Vector3 = v[0]
		var floor_y := Highland.height_at(vp.x, vp.z)
		if Vector2(vp.x, vp.z).distance_to(HighlandLayout.TOWER[0]) < HighlandLayout.TOWER_W * 0.5:
			floor_y = HighlandLayout.tower_base_y() + HighlandLayout.TOWER_H            # 第十九烽塔顶那个机位（5.3b）
		if absf(vp.y - 1.7 - floor_y) > 0.05:
			views_ok = false
	check(views_ok, "%d 个固定机位都在地面（塔顶那个在塔顶）上方 1.7 米" % HighlandLayout.VIEW_NAMES.size())
	# 走路：顺着盘山路往上走得动（坡不超过能走的角度）
	var r0: Vector2 = HighlandLayout.ROAD[3]
	var r1: Vector2 = HighlandLayout.ROAD[4]
	p.global_position = Vector3(r0.x, HighlandLayout.height(r0.x, r0.y) + 0.3, r0.y) + Vector3((r1 - r0).normalized().x, 0, (r1 - r0).normalized().y) * 3.0
	p.rotation.y = atan2(-(r1 - r0).x, -(r1 - r0).y)
	p.velocity = Vector3.ZERO
	await physics(10)
	var from := p.global_position
	Input.action_press("move_forward")
	await seconds(3.0)
	Input.action_release("move_forward")
	check(p.global_position.distance_to(from) > 6.0 and p.is_on_floor(), "顺着盘山路往前走得动（3 秒走了 %.1f 米）" % p.global_position.distance_to(from))
	# 四边的墙挡人；天空、雾、风雪
	p.global_position = Vector3(0.0, Highland.height_at(0.0, 120.0) + 0.3, HighlandLayout.BOUNDS.end.y - HighlandLayout.WALL_INSET - 2.0)
	p.rotation.y = PI                                 # 面朝 +Z（往南、往地图外）
	await physics(6)
	Input.action_press("move_forward")
	await seconds(2.0)
	Input.action_release("move_forward")
	check(p.global_position.z < HighlandLayout.BOUNDS.end.y - HighlandLayout.WALL_INSET, "南边地图边上有看不见的墙（走到 z = %.1f 停住）" % p.global_position.z)
	var env: Environment = main.env
	check(env.background_mode == Environment.BG_SKY and env.sky != null and is_zero_approx(env.fog_sky_affect) and env.fog_depth_end > 150.0,
		"天空是阴云照片（雾不盖天空）、雾远到 %.0f 米（远山一层层退进雾里）" % env.fog_depth_end)
	check(p.get_node_or_null("Snow") != null and (p.get_node("Snow") as CPUParticles3D).gravity.x > 1.0 and p.get_node_or_null("Drift") != null, "高地有风：雪斜着落、贴地有吹雪")
	var dark := Daypart.preset("highland", "night")
	check(Daypart.preset("highland", "day").fog_end > Daypart.PRESETS.day.fog_end and dark.fog_end < Daypart.preset("highland", "day").fog_end and Daypart.preset("frostford", "day") == Daypart.PRESETS.day,
		"时段：高地白天雾比镇上远（%.0f / %.0f 米）、夜里近；别的区域不受影响" % [Daypart.preset("highland", "day").fog_end, Daypart.PRESETS.day.fog_end])
	await free_main(main)
	# 第一章章末：第二章开放以前（playable_chapter = 1）没有「继续」；开放以后（2026-10-24 起）有，点了进高地村口、白天、存档记第二章
	GameState.new_game(511)
	GameState.chapter = 1
	main = await make_area("marsh")
	main.playable_chapter = 1
	main.show_ending("ch1")
	await frames(2)
	check(main.ending_panel.next_chapter == 0 and not main.ending_panel.continue_btn.visible, "第二章开放以前：第一章章末没有「继续」")
	main.ending_panel.hide()
	get_tree().paused = false
	main.playable_chapter = 2
	main.show_ending("ch1")
	await frames(2)
	check(main.ending_panel.next_chapter == 2 and main.ending_panel.continue_btn.visible and main.ending_panel.continue_btn.text.contains("熄灭的烽燧") and not main.ending_panel.continue_btn.text.contains("制作中"),
		"第一章章末多一行「%s」" % main.ending_panel.continue_btn.text)
	var reloaded := [false]
	main.reload_requested.connect(func(): reloaded[0] = true)
	main.start_chapter(2)
	await frames(3)
	check(reloaded[0] and GameState.chapter == 2 and GameState.daypart == "day" and str(GameState.pending_load.get("scene", "")) == "highland" and str(GameState.pending_load.get("spawn", "")) == "village",
		"点了：第二章、白天、去余火高地的村口（%s）" % str(GameState.pending_load))
	get_tree().paused = false
	await free_main(main)
	GameState.pending_load = {}


## 5.1b 高地的树、石头、远处的森林和烽燧塔
func test_flora() -> void:
	Highland.ensure_field()
	HighlandFlora.clear_cache()
	var tr := HighlandFlora.trees()
	var rk := HighlandFlora.rocks()
	var bc := HighlandFlora.beacons()
	check(tr.size() >= 300 and tr.size() <= 900 and rk.size() >= 80 and rk.size() <= 400, "树 %d 棵、石头 %d 块" % [tr.size(), rk.size()])
	var bad := []
	for t in tr:
		var p: Vector3 = t[0]
		var q := Vector2(p.x, p.z)
		if HighlandLayout.road_hit(q).d < HighlandLayout.ROAD_HALF + 3.0 or q.distance_to(HighlandLayout.VILLAGE) < HighlandLayout.VILLAGE_R \
				or p.y > HighlandFlora.TREELINE + 0.5 or q.y < HighlandLayout.crest_z(q.x) or HighlandFlora.slope_at(q) > 0.31:
			bad.append(q)
	check(bad.is_empty(), "树不长在路上、村里、林线以上、山脊北边和悬崖上（不合适的：%s）" % str(bad.slice(0, 5)))
	var rock_bad := rk.filter(func(r): return HighlandLayout.road_hit(Vector2(r[0].x, r[0].z)).d < HighlandLayout.ROAD_HALF + 1.0)
	check(rock_bad.is_empty(), "石头不压路")
	var lit := bc.filter(func(b): return bool(b[1])).size()
	check(bc.size() >= 8 and lit >= 2 and lit <= 4 and bc.all(func(b): return not HighlandLayout.BOUNDS.has_point(Vector2(b[0].x, b[0].z))),
		"远处山脊上 %d 座烽燧塔，亮着的 %d 座（大半是黑的），都在地图外面" % [bc.size(), lit])
	check(HighlandFlora.tree_mesh(0, 0).get_faces().size() / 3 <= 300 and HighlandFlora.tree_mesh(0, 1).get_faces().size() / 3 <= 80 and HighlandFlora.rock_mesh(0).get_faces().size() / 3 <= 300,
		"一棵树近处 %d 面、远处 %d 面；一块石头 %d 面" % [HighlandFlora.tree_mesh(0, 0).get_faces().size() / 3, HighlandFlora.tree_mesh(0, 1).get_faces().size() / 3, HighlandFlora.rock_mesh(0).get_faces().size() / 3])
	GameState.new_game(512)
	GameState.daypart = "day"
	var main := await make_area("highland")
	var st: ChunkStreamer = main.streamer
	st.build_all()
	check(float(st.stats.max_job_ms) < 40.0, "地形和树石分帧搭完，最慢一件 %.1f 毫秒" % st.stats.max_job_ms)
	var mms: Array = main.world.find_children("Trees*", "MultiMeshInstance3D", true, false)
	var count := 0
	for mi: MultiMeshInstance3D in mms:
		if mi.name.ends_with("near"):
			count += mi.multimesh.instance_count
	check(count == tr.size() and mms.all(func(mi): return mi.visibility_range_end > 0.0), "树按块用多实例画（近处那份共 %d 棵 = 全部）；按距离换远处那份" % count)
	check(main.world.get_node_or_null("FarForest") != null and (main.world.get_node("FarForest") as MultiMeshInstance3D).multimesh.instance_count > 1000 and main.world.get_node_or_null("FarBeacons") != null,
		"地图外面山坡上有针叶林，山脊上有那串烽燧塔")
	var glows: Array = main.world.find_children("BeaconGlow*", "MeshInstance3D", true, false)
	check(glows.size() == lit and glows.all(func(g): return ((g as MeshInstance3D).mesh.surface_get_material(0) as StandardMaterial3D).disable_fog),
		"亮着的烽燧塔光晕不受雾影响（%d 团）" % glows.size())
	var space := main.get_world_3d().direct_space_state
	var t0: Vector3 = tr[0][0]
	var q := PhysicsRayQueryParameters3D.create(t0 + Vector3(-3.0, 1.2, 0), t0 + Vector3(3.0, 1.2, 0), 1)
	var hit := space.intersect_ray(q)
	check(not hit.is_empty() and Vector2(hit.position.x, hit.position.z).distance_to(Vector2(t0.x, t0.z)) < 0.5, "树干挡人（横着打一条线打到树干）")
	await free_main(main)


## 5.2a 羊脊村：矮石屋、驿站（进得去、出得来）、铁匠棚、羊圈、石墙、冰溪、石圈、路牌；旅行地图「北境北部」
func test_yangji() -> void:
	Highland.ensure_field()
	HighlandFlora.clear_cache()
	# 布局：房子都在村子压平的那片里、不压路；树和石头不长在房子、石墙、溪、石圈上
	var bad := []
	for c in HighlandLayout.CROFTS:
		var p: Vector2 = c[1]
		if p.distance_to(HighlandLayout.VILLAGE) > HighlandLayout.VILLAGE_R - 3.0 or HighlandLayout.road_hit(p).d < HighlandLayout.ROAD_HALF + 2.0:
			bad.append(str(c[0]))
	var fl := Highland.height_at(HighlandLayout.VILLAGE.x, HighlandLayout.VILLAGE.y)
	check(bad.is_empty() and HighlandLayout.CROFTS.size() == 6, "6 栋矮石屋都在村子那片平地上、不压路（不合适的：%s）" % str(bad))
	var houses := []
	for c in HighlandLayout.CROFTS:
		houses.append(House.footprint(HighlandVillage.croft_pos(c), float(c[2]), float(c[3]) + 1.0, float(c[4]) + 1.0))
	houses.append(House.footprint(HighlandVillage.waystation_pos(), float(HighlandLayout.WAYSTATION[1]), float(HighlandLayout.WAYSTATION[2]) + 1.0, float(HighlandLayout.WAYSTATION[3]) + 1.0))
	var hit_house := HighlandFlora.trees().filter(func(t): return houses.any(func(h): return Geometry2D.is_point_in_polygon(Vector2(t[0].x, t[0].z), h)))
	var on_works := HighlandFlora.trees().filter(func(t): return HighlandFlora.near_village_works(Vector2(t[0].x, t[0].z), 1.0)).size() + HighlandFlora.rocks().filter(func(r): return HighlandFlora.near_village_works(Vector2(r[0].x, r[0].z), 0.5)).size()
	check(hit_house.is_empty() and on_works == 0, "树和石头不长在房子、田间石墙、溪和石圈上")
	var bed := Highland.height_at(-34.5, 80.0)
	var bank := Highland.height_at(-34.5 + HighlandLayout.STREAM_HALF + HighlandLayout.STREAM_BANK + 2.0, 80.0)
	check(bank - bed > 0.5, "溪床比岸低 %.2f 米（刻出来的沟）" % (bank - bed))
	# 载入：房子、驿站、铁匠棚、羊、石墙、石圈、冰溪都搭出来；门、路牌一进场就在
	GameState.new_game(520)
	GameState.chapter = 2
	GameState.daypart = "dusk"
	var main := await make_area("highland")
	var st: ChunkStreamer = main.streamer
	st.build_all()
	var w: Node3D = main.world
	var crofts: Array = w.find_children("Croft_*", "Node3D", true, false).filter(func(n): return n.name != "Croft_barracks")   # 第十九烽的营房也是矮石屋（5.3b）
	check(crofts.size() == 6 and crofts.all(func(c): return c.is_in_group("house")) and w.find_children("Smithy", "MeshInstance3D", true, false).size() == 1
		and w.find_children("Sheep", "MeshInstance3D", true, false).reduce(func(acc, m): return acc + int(m.get_meta("count", 0)), 0) == HighlandLayout.SHEEP.size()
		and w.find_children("RingStones", "MultiMeshInstance3D", true, false).size() == 1 and (w.find_children("RingStones", "MultiMeshInstance3D", true, false)[0] as MultiMeshInstance3D).multimesh.instance_count == HighlandLayout.STONES
		and w.find_children("DryWalls", "MeshInstance3D", true, false).size() >= 2 and w.get_node_or_null("StreamIce") != null,
		"村子搭出来了：6 栋矮石屋、铁匠棚、%d 只羊、%d 块立石、石墙、冰溪" % [HighlandLayout.SHEEP.size(), HighlandLayout.STONES])
	check(float(st.stats.max_job_ms) < 40.0, "加上村子以后每件活还是不长（最慢 %.1f 毫秒）" % st.stats.max_job_ms)
	var lit_houses := crofts.filter(func(c): return bool(c.get_meta("lit_now", true))).size()
	check(lit_houses >= 3, "黄昏：矮石屋的窗大多亮着（%d / 6）" % lit_houses)
	var doors: Array = w.find_children("CroftDoor_*", "Door", true, false)
	check(doors.size() == 6 and doors.all(func(d): return d.locked), "6 栋矮石屋的门都闩着（这一步还没有人，5.2b）")
	var wd := w.get_node_or_null("WaystationDoor") as Door
	check(wd != null and not wd.locked and wd.to_area == "waystation" and wd.to_spawn == "front", "驿站的门推得开，通往大堂")
	var space := main.get_world_3d().direct_space_state
	var wp := HighlandVillage.waystation_pos()
	var q := PhysicsRayQueryParameters3D.create(wp + Vector3(-6.0, 1.2, -3.0), wp + Vector3(2.0, 1.2, -3.0), 1)
	check(not space.intersect_ray(q).is_empty(), "驿站的墙挡人（房子是分帧搭的，碰撞一进场就在）")
	# 旅行地图：村北路牌旁边打开是「北境北部」，能去第十九烽
	var sv := HighlandLayout.SIGN_VILLAGE
	var p: FpController = main.player
	p.global_position = Vector3(sv.x - 1.5, Highland.height_at(sv.x - 1.5, sv.z + 1.0) + 0.1, sv.z + 1.0)
	await physics(4)
	check(main.near_travel_point() and Travel.place_of_area("highland", main.player_xz()) == "yangji", "村北路牌旁边：在羊脊村、站在出发的地方")
	main.open_travel_map(true)
	await frames(2)
	check(main.travel_map.visible and main.travel_map.title.text.contains("北境北部") and main.travel_map.place_btns.keys() == ["yangji", "beacon19"],
		"旅行地图是「北境北部」：羊脊村、第十九烽（%s）" % str(main.travel_map.place_btns.keys()))
	check(Travel.check(2, "yangji", "beacon19", true).ok and MapTabs.label_of("travel") == "北境北部" and Travel.places(1).all(func(id): return str(Travel.place(id).get("region", "west")) == "west"),
		"从羊脊村能去第十九烽；页签写「北境北部」；第一章的地图还是北境西部那几处")
	main.travel_map.close()
	get_tree().paused = false
	await free_main(main)
	# 驿站大堂：进得去、出得来（出来站在驿站门外）
	GameState.pending_load = {"scene": "waystation", "spawn": "front", "player": {}}
	main = await make_area("waystation")
	check(main.area == "waystation" and Areas.is_indoor("waystation") and main.world.get_node_or_null("Waystation") != null and main.world.find_children("Fire", "OmniLight3D", true, false).size() == 1,
		"驿站大堂：壁炉、长桌、罗薇娜的桌子、粮架（室内，壁炉是一盏会闪的火光）")
	var exit: Door = main.world.find_children("*", "Door", true, false).filter(func(d): return d.to_area == "highland")[0]
	check(exit.to_spawn == "waystation_door" and Areas.spawn("highland", "waystation_door") is Transform3D, "大堂的门通往驿站门外")
	var out_spawn: Transform3D = Areas.spawn("highland", "waystation_door")
	check(out_spawn.origin.distance_to(HighlandVillage.waystation_pos()) < 3.5 and absf(out_spawn.origin.y - Highland.height_at(out_spawn.origin.x, out_spawn.origin.z)) < 0.2, "从大堂出来站在驿站门外的地上")
	await free_main(main)
	GameState.pending_load = {}


## 5.2b 羊脊村的人：罗薇娜按第一章换开场白、指路推进主线；伊薇特的信；征粮人；妮尔和支线；铁匠卖火把；只说一句的人
func test_villagers() -> void:
	var errs := []
	for f in ["highland", "waystation"]:
		var d := DialogueRunner.load_file(f)
		for id in d:
			if not str(id).begins_with("_"):
				errs.append_array(DialogueRunner.validate(d[id]))
	check(errs.is_empty(), "高地和驿站的对话都走得通、旗标都登记了（%s）" % str(errs.slice(0, 3)))
	# 第二章开场：到了羊脊村，主线开始；选了伊薇特的身上有她的信
	GameState.new_game(530)
	GameState.chapter = 2
	GameState.daypart = "day"
	GameState.set_flag("valen_heir", "ivette")
	var main := await make_area("highland")
	check(GameState.quest_stage("ch2_main") == "ask_yangji" and GameState.has_item("ivette_letter"), "到了羊脊村：主线「熄灭的烽燧」开始（去驿站问路）；选了伊薇特的，身上有她给罗薇娜的信")
	var w: Node3D = main.world
	var names := []
	for p in HighlandLayout.PEOPLE:
		var n := w.get_node_or_null("Npc_" + str(p[0])) as Npc
		if n != null:
			names.append(n.display_name)
	check(names.size() == HighlandLayout.PEOPLE.size() and Looks.has("妮尔", "Npc_nell") and Looks.has("罗薇娜", "Npc_rowena"),
		"村里的人都在（%s），都有真人外观" % "、".join(names))
	var space := main.get_world_3d().direct_space_state
	var floating := []
	for p in HighlandLayout.PEOPLE:
		var n := w.get_node("Npc_" + str(p[0])) as Node3D
		var q := PhysicsRayQueryParameters3D.create(n.global_position + Vector3(0, 1.0, 0), n.global_position + Vector3(0, -1.0, 0), 1)
		var hit := space.intersect_ray(q)
		if hit.is_empty() or absf(float(hit.position.y) - n.global_position.y) > 0.25:
			floating.append(str(p[0]))
	check(floating.is_empty(), "村里的人都站在地上（不悬空、不埋进地里：%s）" % str(floating))
	# 妮尔：答应路上留意她父亲 → 支线开始
	var r := DialogueRunner.new()
	r.start("highland", "nell")
	pick(r, "你爹去哪了？")
	pick(r, "我要上烽燧线，路上替你留意他。")
	check(GameState.quest_active("ch2_nell") and str(GameState.get_flag("ch2_nell")) == "asked", "答应妮尔路上留意她父亲：支线「妮尔的父亲」开始")
	# 铁匠：3 银币一支火把
	var silver := GameState.silver
	r.start("highland", "smith")
	pick(r, "来一支火把。（3 银币）")
	check(GameState.has_item("torch") and GameState.silver == silver - 3, "铁匠卖火把：3 银币一支")
	await free_main(main)
	# 驿站：罗薇娜认得伊薇特的信；交信；指路以后主线推进到「上第十九烽」
	GameState.pending_load = {"scene": "waystation", "spawn": "front", "player": {}}
	main = await make_area("waystation")
	check(main.world.get_node_or_null("Npc_rowena") != null and main.world.get_node_or_null("Npc_requisitioner") != null, "驿站大堂里：罗薇娜、烽誓团的征粮人")
	r.start("waystation", "rowena")
	check(r.text().contains("伊薇特小姐"), "选了伊薇特、带着信：罗薇娜一开口就提伊薇特的信")
	pick(r, "（把伊薇特小姐的信递给她）")
	check(not GameState.has_item("ivette_letter") and GameState.has_flag("ch2_letter_given") and GameState.get_rep("eld") >= 5, "交了信：厄尔德家声望 +5")
	pick(r, "明白了。" if has_opt(r, "明白了。") else "我会的。")
	pick(r, "我从黑鹭堡来。老家主临终让我去烽燧线找一个人。")
	pick(r, "当年老王加冕礼上的另一个侍从。")
	check(GameState.quest_stage("ch2_main") == "to_beacon19" and r.text().contains("诺伯特"), "罗薇娜说出诺伯特、指了上山的路：主线推进到「上第十九烽」")
	await free_main(main)
	# 选了阿尔里克 / 堤道失守：开场白不一样
	GameState.new_game(531)
	GameState.chapter = 2
	GameState.set_flag("valen_heir", "alric")
	GameState.set_flag("ch1_causeway", "lost")
	r.start("waystation", "rowena")
	var alric_line := r.text()
	pick(r, "我从黑鹭堡来。老家主临终让我去烽燧线找一个人。")
	check(alric_line.contains("阿尔里克") and r.text().contains("易主") and not GameState.has_item("ivette_letter"), "选了阿尔里克：罗薇娜疑心你来谈价钱；堤道失守了：她说黑鹭堡易主了")
	GameState.pending_load = {}



## 5.2c 寒冷与冻伤
func test_cold() -> void:
	var day := Cold.rate("highland", "day", 5.0, 5, false, false)
	var night := Cold.rate("highland", "night", 5.0, 5, false, false)
	var high := Cold.rate("highland", "day", 40.0, 5, false, false)
	var skilled := Cold.rate("highland", "day", 5.0, 60, false, false)
	check(day > 0.0 and is_equal_approx(night, day * 2.0) and high > day and skilled < day and 100.0 / day > 360.0 and 100.0 / day < 600.0,
		"高地户外变冷：白天约 %.0f 秒满格，夜里快一倍，山脊上更快，「生存」高的慢" % (100.0 / day))
	check(Cold.rate("frostford", "night", 0.0, 5, false, false) == 0.0 and Cold.rate("highland", "night", 5.0, 5, true, false) < 0.0 and Cold.rate("waystation", "day", 0.0, 5, false, true) < 0.0,
		"别的区域不冷（第一章照旧）；火边、屋里暖回来")
	GameState.new_game(540)
	var full := GameState.stamina_max()
	GameState.cold = 99.95
	var st := {}
	var root := get_tree().root
	var ev := Cold.tick(get_tree(), "highland", false, "night", Vector3(0, 5, 0), 1.0, st)
	check(ev == "frostbite" and GameState.frostbite and is_equal_approx(GameState.stamina_max(), full * Cold.FROSTBITE_STAMINA) and Cold.text().begins_with("冻伤"),
		"涨满了冻伤：体力上限 %.0f → %.0f，那一行写「冻伤」" % [full, GameState.stamina_max()])
	var fire := OmniLight3D.new()
	fire.add_to_group("light_source")
	fire.set_meta("radius", 4.0)
	root.add_child(fire)
	fire.global_position = Vector3(0, 5, 0)
	var cured := ""
	for k in 10:
		var e := Cold.tick(get_tree(), "highland", false, "night", Vector3(1, 5, 0), 1.0, st)
		if e != "":
			cured = e
	check(cured == "cured" and not GameState.frostbite and GameState.cold == 0.0 and is_equal_approx(GameState.stamina_max(), full), "在火边歇够 %.0f 秒：冻伤好了，体力上限回来" % Cold.FIRE_CURE)
	fire.queue_free()
	GameState.cold = 70.0
	GameState.add_item("strong_spirit")
	GameState.use_item("strong_spirit")
	check(is_equal_approx(GameState.cold, 30.0) and Cold.text() == "寒冷：有点冷", "喝一瓶烈酒：寒冷值 -40（70 → 30，「有点冷」）")
	GameState.frostbite = true
	GameState.cold = 100.0
	var back := GameState.to_dict()
	GameState.new_game(541)
	GameState.from_dict(back)
	check(GameState.frostbite and GameState.cold == 100.0, "冻伤和寒冷值跟着存档走")
	GameState.from_dict({"seed": 1})
	check(not GameState.frostbite and GameState.cold == 0.0, "旧存档（没有这两项）读进来不冷")
	# 游戏里：高地户外冷到 35，体力条边上写「寒冷：有点冷」、弹一次教学提示；站到铁匠炉边慢慢暖回来
	GameState.new_game(542)
	GameState.chapter = 2
	GameState.daypart = "day"
	GameState.cold = 35.0
	var main := await make_area("highland")
	await frames(3)
	check(main.hud.cold_label.visible and main.hud.cold_label.text == "寒冷：有点冷" and ("cold" in GameState.tips_seen or main.tip_now == "cold" or "cold" in main.tip_queue),
		"高地户外：体力条边上写「%s」，弹教学提示「寒冷」" % main.hud.cold_label.text)
	var forge: Array = main.world.find_children("Forge", "OmniLight3D", true, false)
	if forge.is_empty():
		main.streamer.build_all()
		forge = main.world.find_children("Forge", "OmniLight3D", true, false)
	var p: FpController = main.player
	p.global_position = (forge[0] as Node3D).global_position + Vector3(-2.5, -1.0, 0)
	var before := GameState.cold
	await seconds(1.0)
	check(GameState.cold < before - 5.0, "站到铁匠炉边：一秒暖回来 %.1f" % (before - GameState.cold))
	await free_main(main)


## 5.4b 火把：点着、举着（不能格挡）、插在地上、被风吹灭 / 摔灭、拿点着的去点、拔起来、烧完；长眠者绕开；塔里那捆火把
func test_torch() -> void:
	GameState.new_game(550)
	GameState.chapter = 2
	GameState.daypart = "night"
	var main := await make_area("highland")
	await frames(3)
	var p: FpController = main.player
	var hand: TorchHand = p.torch
	check(hand.windy and hand.state == TorchHand.NONE, "高地户外有风，手里空着")
	var said := []
	hand.said.connect(func(t): said.append(t))
	hand.windy = false                   # 下面不让风随机吹灭（风的概率单独查）；点火的时间按有风的算
	hand.use_key()
	check(hand.state == TorchHand.NONE and said.size() == 1 and said[0].contains("没有火把"), "背包里没火把：按 T 说「%s」" % (said[0] if said.size() > 0 else ""))
	GameState.add_item("torch", 3)
	hand.use_key()
	check(hand.state == TorchHand.LIGHTING and GameState.count_item("torch") == 2, "有火把：拿出一支打火石点（背包剩 %d）" % GameState.count_item("torch"))
	await seconds(TorchHand.LIGHT_TIME + 0.3)
	check(hand.lit() and hand.light != null and hand.fp_visual.visible and hand.fire.is_in_group("light_source"), "打了 %.1f 秒火石（风里 %.1f）：点着了，左下角举着、带一盏光" % [TorchHand.LIGHT_TIME, TorchHand.LIGHT_TIME_WIND])
	check("torch" in GameState.tips_seen or main.tip_now == "torch" or "torch" in main.tip_queue, "第一次点着弹教学提示「火把」")
	check(not Cold.near_fire(get_tree(), hand.fire.global_position), "举着的火把暖不了身子")
	p.melee.block_press()
	await frames(2)
	check(not p.melee.blocking() and said.back().contains("挡不了"), "举着火把格挡：挡不了（「%s」）" % said.back())
	p.melee.block_release()
	var fires := SleeperCrowd.fires(get_tree())
	check(fires.any(func(f): return (f[0] as Vector2).distance_to(Vector2(hand.fire.global_position.x, hand.fire.global_position.z)) < 0.1),
		"长眠者把举着的火把也算一团火（会绕开）")
	# 插在地上
	var planted := hand.plant()
	await frames(2)
	check(planted != null and planted.lit and hand.state == TorchHand.NONE and planted.global_position.distance_to(p.global_position) < 1.5
		and absf(planted.global_position.y - Highland.height_at(planted.global_position.x, planted.global_position.z)) < 0.3 and PlantedTorch.lit_count(get_tree()) == 1,
		"T 插在面前的地上：亮着，手里空了")
	check(planted.verb_now() == "拔起" and SleeperCrowd.fires(get_tree()).size() >= 1, "对着插着的：「拔起」；长眠者绕开它")
	planted.blow_out()
	check(not planted.lit and planted.verb_now() == "点着" and not planted.is_in_group("light_source"), "被风吹灭：不亮了，对着它是「点着」")
	var r := planted.interact(p)
	check(not planted.lit and str(r.get("toast", "")).contains("点着的火把"), "手里没有点着的火把点不着")
	hand.use_key()
	await seconds(TorchHand.LIGHT_TIME + 0.3)
	r = planted.interact(p)
	check(planted.lit and hand.lit() and r.get("toast") == "点着了", "拿着点着的火把对着它按 E：点着了")
	# 被推倒：举着的摔灭；T 重新点
	p.knock_down(0.3, Vector3.FORWARD)
	check(hand.state == TorchHand.OUT and said.back().contains("灭"), "被推倒：火把摔进雪里灭了")
	await seconds(0.5)
	var fuel_before := hand.fuel
	hand.use_key()
	await seconds(TorchHand.LIGHT_TIME + 0.3)
	check(hand.lit() and GameState.count_item("torch") == 1 and hand.fuel <= fuel_before, "T 重新点着灭了的那支（不用新的，背包还是 %d）" % GameState.count_item("torch"))
	# 插四支：只有最新的三支带实时光源
	PlantedTorch.max_lights = 3
	var row := [planted]
	for k in 3:
		p.global_position += Vector3(2.0, 0, 0)
		row.append(hand.plant())
		if k < 2:
			GameState.add_item("torch")
			hand.use_key()
			await seconds(TorchHand.LIGHT_TIME + 0.3)
	await frames(2)
	var lights := row.filter(func(t): return t.light.visible).size()
	check(PlantedTorch.lit_count(get_tree()) == 4 and lights == 3 and not (row[0] as PlantedTorch).light.visible, "插了四支：都亮着，最新的三支带实时光源（%d）" % lights)
	# 拔起：手里空着才行
	r = (row[3] as PlantedTorch).interact(p)
	await frames(2)
	check(hand.lit() and PlantedTorch.lit_count(get_tree()) == 3 and r.get("toast") == "拔起火把", "手里空着：拔起来接着举")
	r = (row[2] as PlantedTorch).interact(p)
	check((row[2] as PlantedTorch).lit and str(r.get("toast")).contains("已经拿着"), "手里有了就拔不了")
	# 烧完
	(row[2] as PlantedTorch).fuel = 0.2
	hand.fuel = 0.2
	await seconds(0.5)
	check(hand.state == TorchHand.NONE and said.back().contains("烧完") and not (row[2] as PlantedTorch).lit and not (row[2] as PlantedTorch).can_interact(), "烧完：手里的没了，插着的剩一根黑棍")
	# 风：插着的被吹灭的机会比举着的大；室内没风
	check(PlantedTorch.BLOW > TorchHand.BLOW_HELD and 1.0 / TorchHand.BLOW_HELD > 120.0, "风里举着平均 %.0f 秒吹灭一次，插着的更容易" % (1.0 / TorchHand.BLOW_HELD))
	# 换区域跟着走
	GameState.add_item("torch")
	hand.use_key()
	await seconds(TorchHand.LIGHT_TIME + 0.3)
	check(not GameState.held_torch.is_empty() and GameState.held_torch.lit, "手里的火把记在 GameState（换区域跟着走）")
	await free_main(main)
	var tower := await make_area("beacon_tower")
	await frames(3)
	check(tower.player.torch.lit() and not tower.player.torch.windy, "进了塔：还举着，屋里没风")
	tower.player.torch.plant()
	var bundle: Array = tower.world.find_children("*", "Pickup", true, false).filter(func(n): return n.pickup_id == BeaconTower.TORCH_PICKUP)
	var before := GameState.count_item("torch")
	if bundle.size() == 1:
		tower._on_interacted((bundle[0] as Pickup).interact(tower.player))
	check(bundle.size() == 1 and GameState.count_item("torch") == before + 3 and GameState.picked.has(BeaconTower.TORCH_PICKUP), "塔里东南角那捆备用火把：拾取得 3 支")
	await free_main(tower)
	GameState.new_game(551)
	check(GameState.held_torch.is_empty(), "新游戏手里没火把")


## 5.4c 第一夜潮水：马蒂亚斯给火把 → 栅外那排木桩插满 → 潮水上来、碰到火的从营地西边绕过去 → 守住了 / 漫进营地少一个人 → 天亮
func test_firsttide() -> void:
	GameState.new_game(560)
	GameState.chapter = 2
	GameState.daypart = "dusk"
	GameState.set_stage("ch2_main", "first_night")
	GameState.set_flag("matthias_met")
	GameState.set_flag("norbert_met")
	GameState.set_flag("ch1_sleeper", "tobin")
	var r := DialogueRunner.new()
	r.start("beacon19", "matthias")
	var ask := "诺伯特说「先过了今夜」。入夜以后怎么守？"
	check(has_opt(r, ask), "主线「第一夜」：马蒂亚斯多一个选项「入夜以后怎么守？」")
	pick(r, ask)
	check(GameState.count_item("torch") == 4 and GameState.quest_stage("ch2_main") == "light_line" and r.text().contains("木桩") and GameState.daypart == "night",
		"马蒂亚斯塞给你四支火把，说栅外那排木桩一根插一支（主线「插火把」，天黑透了）")
	r.start("beacon19", "matthias")
	pick(r, "火把用完了。")
	check(GameState.count_item("torch") == 6 and not has_opt(r, "火把用完了。"), "火把用完了再要：又给两支（只给一次）")
	var main := await make_area("highland")
	await frames(3)
	var ft: FirstTide = main.first_tide
	check(ft != null and ft.state == FirstTide.PREP and ft.lit_spots() == 2 and GameState.daypart == "night", "高地：栅外西南坡上一排木桩，营里的兵插亮了两头")
	var sp := FirstTide.spots()
	var bad := sp.filter(func(q): return (q as Vector2).distance_to(HighlandLayout.BEACON19) < HighlandLayout.PALISADE_R + 4.0 or (q as Vector2).distance_to(HighlandLayout.BEACON19) > 30.0)
	check(bad.is_empty(), "木桩在木栅外 4–30 米（%s）" % str(bad))
	var p: FpController = main.player
	var hand: TorchHand = p.torch
	hand.windy = false
	for t in get_tree().get_nodes_in_group("planted_torch"):
		(t as PlantedTorch).windy = false
	for k in range(1, 5):
		var q: Vector2 = sp[k]
		p.global_position = Vector3(q.x, Highland.height_at(q.x, q.y + TorchHand.PLANT_DIST) + 0.2, q.y + TorchHand.PLANT_DIST)
		p.rotation.y = 0.0
		p.velocity = Vector3.ZERO
		await physics(2)
		hand.use_key()
		await seconds(TorchHand.LIGHT_TIME + 0.3)
		hand.plant()
		await physics(2)
	await physics(5)
	check(ft.lit_spots() == 6 and ft.state == FirstTide.TIDE and GameState.quest_stage("ch2_main") == "tide", "中间插上四支（六根桩亮着）：潮水上来了（主线「潮水」，%d 根）" % ft.lit_spots())
	check(ft.crowd != null and ft.crowd.count == FirstTide.COUNT and ft.crowd.hidden.has(FirstTide.SEEN_INDEX) and ft.seen_model != null,
		"%d 个长眠者；中间混着一张认得的脸（芦栈村的托宾，换成他的样子）" % FirstTide.COUNT)
	p.global_position = Vector3(44, Highland.height_at(44, -40) + 0.5, -40)
	Engine.time_scale = 6.0
	var t0 := Time.get_ticks_msec()
	while ft.state != FirstTide.DONE and Time.get_ticks_msec() - t0 < 150000:
		await seconds(1.0)
	Engine.time_scale = 1.0
	check(ft.state == FirstTide.DONE and ft.result == "held" and ft.intruded.size() < FirstTide.LOSE_AT and ft.crowd.rerouted >= FirstTide.COUNT * 0.6,
		"火没断：%d 个碰到火从营地西边绕过去，漫进营地的 %d 个 → 守住了（%s）" % [ft.crowd.rerouted if ft.crowd else 0, ft.intruded.size(), ft.result])
	await frames(3)
	check(str(GameState.get_flag("ch2_first_tide", "")) == "held" and GameState.quest_stage("ch2_main") == "after_tide" and GameState.daypart == "dawn",
		"天亮了：主线「天亮以后」，记下 held")
	await free_main(main)
	# 不插：两头那两支挡不住，潮水照直穿过营地 → 卷走一个人；天亮以后粮棚前数麻袋的兵不见了
	GameState.new_game(561)
	GameState.chapter = 2
	GameState.daypart = "night"
	GameState.set_stage("ch2_main", "light_line")
	var main2 := await make_area("highland")
	await frames(3)
	var ft2: FirstTide = main2.first_tide
	for t in get_tree().get_nodes_in_group("planted_torch"):
		(t as PlantedTorch).windy = false
	main2.player.global_position = Vector3(44, Highland.height_at(44, -40) + 0.5, -40)
	ft2.start_tide()
	Engine.time_scale = 6.0
	t0 = Time.get_ticks_msec()
	while ft2.state != FirstTide.DONE and Time.get_ticks_msec() - t0 < 150000:
		await seconds(1.0)
	Engine.time_scale = 1.0
	check(ft2.result == "lost_one" and ft2.intruded.size() >= FirstTide.LOSE_AT and str(GameState.get_flag("ch2_first_tide", "")) == "lost_one",
		"没插中间：%d 个漫进营地 → 卷走一个人（%s）" % [ft2.intruded.size(), ft2.result])
	await free_main(main2)
	var main3 := await make_area("highland")
	await frames(3)
	check(main3.world.find_children("Npc_sacks", "", true, false).is_empty() and not main3.world.find_children("Npc_chopper", "", true, false).is_empty() and main3.first_tide == null,
		"天亮以后：粮棚前数麻袋的兵不见了（劈柴的老兵还在），木桩那排不再搭")
	await free_main(main3)
	# 潮水进行中读档：从「插火把」重来
	GameState.set_stage("ch2_main", "tide")
	GameState.set_flag("ch2_first_tide", "")
	var main4 := await make_area("highland")
	await frames(3)
	check(main4.first_tide != null and main4.first_tide.state == FirstTide.PREP and GameState.quest_stage("ch2_main") == "light_line", "潮水进行到一半读档：从「插火把」重来")
	await free_main(main4)


## 5.5a 第二天：诺伯特下到小屋讲加冕礼、断角、第三章入口；第十八烽（柴、火油、梯子、点火）；石圈的刻字
func test_day2() -> void:
	GameState.new_game(570)
	GameState.chapter = 2
	GameState.daypart = "dawn"
	GameState.set_stage("ch2_main", "after_tide")
	for f in ["matthias_met", "norbert_met"]:
		GameState.set_flag(f)
	GameState.set_flag("ch2_first_tide", "lost_one")
	var main := await make_area("highland")
	await frames(3)
	var w: Node = main.world
	check(w.find_children("Npc_norbert", "", true, false).is_empty() and w.find_children("Npc_sacks", "", true, false).is_empty(), "第二天：塔顶上没有诺伯特了（数麻袋的兵也不在：潮水卷走了）")
	var b18 := w.find_children("Beacon18", "", true, false)
	var sleepers := w.find_children("Npc_beacon18_*", "", true, false)
	check(b18.size() == 1 and sleepers.size() == 3 and (sleepers[0] as Npc).display_name == "长眠的守塔人" and b18[0].get_node_or_null("Fire18") == null,
		"第十八烽：一座冷着的圆石塔，塔脚雪里站着三个长眠的守塔人")
	var space: PhysicsDirectSpaceState3D = main.player.get_world_3d().direct_space_state
	var floating := sleepers.filter(func(n):
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(n.global_position + Vector3(0, 1, 0), n.global_position - Vector3(0, 1, 0), 1))
		return hit.is_empty() or absf(float(hit.position.y) - n.global_position.y) > 0.3)
	check(floating.is_empty(), "三个守塔人都站在地上")
	# 马蒂亚斯给柴和火油
	var r := DialogueRunner.new()
	r.start("beacon19", "matthias")
	var ask := "西边那座第十八烽，就这么灭着？"
	check(has_opt(r, ask), "第一夜过后：马蒂亚斯多一个选项「第十八烽」")
	pick(r, ask)
	pick(r, "我去。")
	check(GameState.has_item("firewood") and GameState.has_item("lamp_oil") and GameState.quest_active("ch2_beacon18"), "马蒂亚斯给了一捆柴、一罐火油，支线「熄掉的第十八烽」开始")
	r.start("beacon19", "matthias")
	check(not has_opt(r, ask), "只给一次")
	# 爬梯子、点火
	var root: Node3D = b18[0]
	var p: FpController = main.player
	var up: Examine = root.get_node("Ladder18Up")
	var res := up.interact(p)
	await physics(10)
	check(res.get("kind") == "climb" and p.global_position.y > root.global_position.y + Beacon18.H - 0.3 and p.global_position.y < root.global_position.y + Beacon18.H + 1.5,
		"塔外的木梯「爬上去」：站到塔顶（高 %.1f 米），没掉下去" % (p.global_position.y - root.global_position.y))
	var brazier: Examine = root.get_node("Brazier18")
	GameState.take_item("lamp_oil")
	res = brazier.interact(p)
	check(str(res.get("toast", "")).contains("火油") and not Beacon18.lit(), "少了火油：点不着，说缺什么")
	GameState.add_item("lamp_oil")
	res = brazier.interact(p)
	await frames(2)
	var fire := root.get_node_or_null("Fire18")
	check(Beacon18.lit() and fire != null and not fire.find_children("*", "OmniLight3D", true, false).is_empty() and not GameState.has_item("firewood") and not GameState.has_item("lamp_oil")
		and GameState.quest_done("ch2_beacon18") and brazier.verb_now() == "看火", "添柴、浇油、点火：第十八烽着了（柴和油用掉，支线完成）")
	res = (root.get_node("Ladder18Down") as Examine).interact(p)
	await physics(10)
	check(p.global_position.y < root.global_position.y + 1.0, "「爬下去」回到塔脚")
	await free_main(main)
	var again := await make_area("highland")
	await frames(3)
	check(not again.world.find_children("Fire18", "", true, false).is_empty(), "重进高地：第十八烽的火还亮着")
	# 石圈
	GameState.set_flag("ch2_stones", "")
	var stones: Array = again.world.find_children("StoneWords", "", true, false)
	check(stones.size() == 1, "石圈：倒下的那块立石能「看刻字」")
	var t: Dictionary = HighlandVillage.read_stones()
	check(str(GameState.get_flag("ch2_stones", "")) == "copied" and GameState.clues.has("stones_seal") and str(t.toast).contains("冬井"), "没有旧书：认出「……于冬井……誓……断……」，记下线索")
	GameState.add_item("old_book")
	t = HighlandVillage.read_stones()
	check(str(GameState.get_flag("ch2_stones", "")) == "matched" and str(t.toast).contains("封于冬井，誓不可断"), "带着奥尔本修士的旧书：残卷上一模一样的一行「封于冬井，誓不可断」")
	await free_main(again)
	# 诺伯特在小屋
	var tower := await make_area("beacon_tower")
	await frames(3)
	var nb: Array = tower.world.find_children("Npc_norbert_room", "", true, false)
	check(nb.size() == 1 and (nb[0] as Npc).dialogue_id == "norbert" and (nb[0] as Npc).global_position.y > BeaconTower.UPPER - 0.1, "诺伯特蹲在顶层小屋的小铁炉边")
	await free_main(tower)
	r.start("beacon19", "norbert")
	var first := r.text()
	check(first.contains("少了一个人") and has_opt(r, "石圈上刻着一行字……"), "诺伯特：天亮了，火还亮着，少了一个人；刻过字的多一个选项")
	pick(r, "加冕礼那一夜，发生了什么？")
	check(r.text().contains("封誓") and GameState.has_flag("heard_coronation") and GameState.clues.has("beacon_seal"), "加冕礼：七步，最后一步「封誓」，那一夜少做了（记下线索）")
	pick(r, "为什么少做了？")
	check(r.text().contains("早就不用做了") and r.text().contains("我不知道"), "主祭说那一步早就不用做了；诺伯特：我不知道")
	pick(r, "还有谁知道那一夜？")
	check(r.text().contains("金穗平原") and GameState.clues.has("vigil_page"), "守灵夜的侍从去了金穗平原的修道院（第三章入口，记下线索）")
	pick(r, "我该做什么？")
	check(r.text().contains("先保住烽燧") and GameState.quest_stage("ch2_main") == "convoy_day" and GameState.has_flag("norbert_day2"), "先保住烽燧；粮车今天在羊脊村歇脚（主线「粮车到村」）")
	r.start("beacon19", "norbert")
	check(r.text().contains("先保住烽燧") and has_opt(r, "门楣上那只断了的号角……"), "再找他：还是那句；能问号角")
	pick(r, "门楣上那只断了的号角……")
	check(r.text().contains("断角烽"), "断角：三十年前吹断的那只号角——它们头一回走过山脊")
	GameState.set_flag("ch2_first_tide", "held")
	GameState.set_flag("norbert_day2", false)
	r.start("beacon19", "norbert")
	check(not r.text().contains("少了一个人"), "守住了营地：不提少了人")


## 5.5b 支线：妮尔的父亲（第一夜潮水里认出他；第二天她要往北去：告诉她 / 劝住 / 拉住 / 随她去）、第十年（卡斯滕：替他说、帮他溜、劝他留）
func test_sidequests2() -> void:
	GameState.new_game(580)
	GameState.chapter = 2
	GameState.daypart = "night"
	GameState.set_stage("ch2_main", "light_line")
	GameState.start_quest("ch2_nell")
	GameState.set_flag("ch2_nell", "asked")
	var main := await make_area("highland")
	await frames(3)
	var ft: FirstTide = main.first_tide
	for t in get_tree().get_nodes_in_group("planted_torch"):
		(t as PlantedTorch).windy = false
	ft.start_tide()
	await physics(3)
	var seen := []
	ft.recognized.connect(func(t): seen.append(t))
	check(ft.crowd.hidden.has(FirstTide.FATHER_INDEX) and ft.faces.size() == 1 and ft.faces[0].index == FirstTide.FATHER_INDEX,
		"答应过妮尔：潮水里混着她父亲（换成他的样子）")
	var a: Dictionary = ft.crowd.agents[FirstTide.FATHER_INDEX]
	main.player.global_position = Vector3(a.p.x + 3.0, Highland.height_at(a.p.x + 3.0, a.p.y) + 0.3, a.p.y)
	await physics(4)
	check(GameState.has_flag("ch2_nell_father_seen") and seen.size() == 1 and str(seen[0]).contains("少了两根指头"), "走近了：认出来——左手少两根指头，是妮尔的父亲")
	main._on_tide_ended("held")
	check(GameState.quest_stage("ch2_nell") == "decide", "天亮：支线推进到「妮尔要往北去」")
	await free_main(main)
	# 妮尔：告诉她看见了 → seen
	var r := DialogueRunner.new()
	r.start("highland", "nell")
	check(r.text().contains("包袱") and has_opt(r, "看见了。他在潮水里，往北走，走得很稳。") and has_opt(r, "（拉住她的胳膊）不行。") and has_opt(r, "要去就去吧。路上小心。"),
		"第二天：妮尔背着包袱要走；能告诉她看见了、劝、拉住、随她去")
	pick(r, "看见了。他在潮水里，往北走，走得很稳。")
	check(str(GameState.get_flag("ch2_nell", "")) == "seen" and GameState.quest_done("ch2_nell") and r.text().contains("我不去了"), "告诉她看见了：她不去了（seen，支线完成）")
	r.start("highland", "nell")
	check(r.text().contains("羊鞭"), "之后她在石圈边攥着她爹的旧羊鞭")
	# 没认出来的：选项里没有「看见了」；拉住 → stopped
	GameState.set_flag("ch2_nell", "asked")
	GameState.set_flag("ch2_nell_father_seen", false)
	r.start("highland", "nell")
	check(not has_opt(r, "看见了。他在潮水里，往北走，走得很稳。"), "潮水里没认出他：不能说看见了")
	pick(r, "（拉住她的胳膊）不行。")
	check(str(GameState.get_flag("ch2_nell", "")) == "stopped", "拉住她：她不去了（stopped）")
	# 随她去 → 村里没有她了
	GameState.set_flag("ch2_nell", "asked")
	r.start("highland", "nell")
	pick(r, "要去就去吧。路上小心。")
	check(str(GameState.get_flag("ch2_nell", "")) == "left", "随她去：她踩着脚印往北走了（left）")
	var m2 := await make_area("highland")
	await frames(3)
	check(m2.world.find_children("Npc_nell", "", true, false).is_empty(), "她走了以后，石圈边没有她了")
	# 卡斯滕
	var ch: Array = m2.world.find_children("Npc_chopper", "", true, false)
	check(ch.size() == 1 and (ch[0] as Npc).display_name == "卡斯滕" and (ch[0] as Npc).dialogue_id == "carsten", "第二天：劈柴的老兵报了名字，卡斯滕，有话说")
	await free_main(m2)
	r.start("beacon19", "carsten")
	check(r.text().contains("第十年") and GameState.quest_active("ch2_carsten"), "卡斯滕：今年是我第十年（支线「第十年」）")
	pick(r, "守满十年，就能走？")
	check(r.text().contains("一笔勾销") and r.text().contains("金穗平原"), "规矩：守十年罪和债一笔勾销；团长不放；南边有个姑娘等了十年")
	pick(r, "我去替你跟马蒂亚斯说。")
	GameState.set_flag("matthias_met")
	r.start("beacon19", "matthias")
	check(has_opt(r, "卡斯滕守满十年了。按规矩，你该放他走。"), "答应替他说：马蒂亚斯多一个选项（口才检定）")
	var rep0 := int(GameState.rep.get("beacon_oath", 0))
	r.start("beacon19", "carsten")
	pick(r, "守满十年，就能走？")
	pick(r, "今夜我替你看着门。你走。")
	check(str(GameState.get_flag("ch2_carsten", "")) == "fled" and int(GameState.rep.get("beacon_oath", 0)) == rep0 - 10 and GameState.quest_done("ch2_carsten"), "帮他夜里溜走：fled，烽誓团 −10")
	r.start("beacon19", "matthias")
	check(not has_opt(r, "卡斯滕守满十年了。按规矩，你该放他走。"), "他走了：不用再替他说")
	var m3 := await make_area("highland")
	await frames(3)
	check(m3.world.find_children("Npc_chopper", "", true, false).is_empty(), "柴棚前没有卡斯滕了")
	await free_main(m3)
	GameState.set_flag("ch2_carsten", false)
	GameState.quests.erase("ch2_carsten")
	var rep1 := int(GameState.rep.get("beacon_oath", 0))
	r.start("beacon19", "carsten")
	pick(r, "守满十年，就能走？")
	pick(r, "再守一年吧。这个冬天，烽燧缺不得人。")
	check(str(GameState.get_flag("ch2_carsten", "")) == "stayed" and int(GameState.rep.get("beacon_oath", 0)) == rep1 + 5, "劝他再守一年：stayed，烽誓团 +5")
	r.start("beacon19", "carsten")
	check(r.text().contains("再守一年"), "之后他说：再守一年，我自己答应的")


## 5.6 抉择：粮车到村（驿站门口五辆车、安塞尔姆、押车兵）；马蒂亚斯：劫（先断车头 / 车尾）或去谈；罗薇娜：几时出村、空白征粮令；
## 安塞尔姆：征粮令三车 / 账册 / 银币 → 分三车要你护车；谈不成回去：劫或者两手空空
func test_convoy() -> void:
	GameState.new_game(590)
	GameState.chapter = 2
	GameState.daypart = "day"
	for f in ["matthias_met", "norbert_met", "norbert_day2", "rowena_met", "saw_requisition"]:
		GameState.set_flag(f)
	GameState.set_flag("ch2_first_tide", "held")
	GameState.set_stage("ch2_main", "after_tide")
	var m0 := await make_area("highland")
	await frames(3)
	check(m0.world.find_children("Convoy", "", true, false).is_empty(), "粮车到村以前：驿站门口没有粮车")
	await free_main(m0)
	GameState.set_stage("ch2_main", "convoy_day")
	var main := await make_area("highland")
	await frames(3)
	var cv: Array = main.world.find_children("Convoy", "", true, false)
	check(cv.size() == 1 and cv[0].get_node_or_null("ConvoyCarts") != null and main.world.find_children("Npc_convoy_guard*", "", true, false).size() == 4
		and main.world.find_children("Npc_carter*", "", true, false).size() == 2, "主线「粮车到村」：驿站门口五辆满载的粮车、四个押车兵、两个车夫")
	var an: Array = main.world.find_children("Npc_anselm", "", true, false)
	check(an.size() == 1 and (an[0] as Npc).dialogue_id == "anselm" and (an[0] as Npc).display_name == "安塞尔姆", "车尾站着押粮官安塞尔姆，有对话")
	var space: PhysicsDirectSpaceState3D = main.player.get_world_3d().direct_space_state
	var fl: Array = main.world.find_children("Npc_convoy_guard*", "", true, false).filter(func(n):
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(n.global_position + Vector3(0, 1, 0), n.global_position - Vector3(0, 1, 0), 1))
		return hit.is_empty() or absf(float(hit.position.y) - n.global_position.y) > 0.3)
	check(fl.is_empty(), "押车兵都站在地上")
	await free_main(main)
	# 马蒂亚斯：劫 → 先断车头
	var r := DialogueRunner.new()
	r.start("beacon19", "matthias")
	check(has_opt(r, "粮车的事，你怎么打算？"), "马蒂亚斯：「粮车的事，你怎么打算？」")
	pick(r, "粮车的事，你怎么打算？")
	check(r.text().contains("十个人") and has_opt(r, "劫。") and has_opt(r, "我先去找押粮官谈。"), "他给你十个人，也听别的法子")
	pick(r, "劫。")
	check(has_opt(r, "先断车头：砍倒那棵枯松拦路。") and has_opt(r, "先断车尾：截住安塞尔姆。"), "劫：两处能下手——车头（枯松拦路）、车尾（截住安塞尔姆）")
	pick(r, "先断车头：砍倒那棵枯松拦路。")
	check(str(GameState.get_flag("beacon_grain", "")) == "rob" and str(GameState.get_flag("ch2_ambush", "")) == "head" and GameState.quest_stage("ch2_main") == "rob_ready",
		"先断车头：beacon_grain = rob，主线「天黑透以后设伏」")
	# 去谈：罗薇娜、安塞尔姆
	GameState.set_flag("beacon_grain", false)
	GameState.set_flag("ch2_ambush", false)
	GameState.set_stage("ch2_main", "convoy_day")
	r.start("beacon19", "matthias")
	pick(r, "粮车的事，你怎么打算？")
	pick(r, "我先去找押粮官谈。")
	check(GameState.quest_stage("ch2_main") == "talk_anselm", "去谈：主线「找押粮官安塞尔姆」")
	r.start("waystation", "rowena")
	check(has_opt(r, "粮车几时出村？") and has_opt(r, "桌上那张盖了印的空白文书，现在用得着了。"), "罗薇娜：几时出村、那张空白文书")
	pick(r, "粮车几时出村？")
	check(r.text().contains("天黑透以后") and GameState.has_flag("heard_convoy_time"), "天黑透以后出村；安塞尔姆一夜没合眼盯着山脊")
	pick(r, "……")
	pick(r, "桌上那张盖了印的空白文书，现在用得着了。")
	check(GameState.has_item("requisition") and r.text().contains("写多少"), "她把空白的征粮令推给你：写多少车你写")
	r.start("highland", "anselm")
	check(r.text().contains("押粮官") and GameState.has_flag("anselm_met"), "安塞尔姆：粮不卖，合同上写着日子")
	pick(r, "烽燧上的人快断粮了。")
	check(has_opt(r, "（摊开征粮令，写上「三车」）厄尔德家征三车粮，送上第十九烽。") and not has_opt(r, "（翻开皮毛税账册）这几笔「留北境」的账，洛蒙德家那边也有一份吧。"),
		"有征粮令才有那两条；没有账册就没有账册那条")
	pick(r, "（摊开征粮令，写上「三车」）厄尔德家征三车粮，送上第十九烽。")
	check(not GameState.has_item("requisition") and str(GameState.get_flag("ch2_requisition", "")) == "three", "征粮令写三车：他认了（厄尔德家的印）")
	pick(r, "……")
	check(str(GameState.get_flag("beacon_grain", "")) == "lawful" and str(GameState.get_flag("ch2_aid", "")) == "granted" and GameState.quest_stage("ch2_main") == "escort_ready",
		"分三车粮上山，要你护车过盘山路（ch2_aid = granted）")
	# 账册
	GameState.set_flag("ch2_aid", false)
	GameState.set_stage("ch2_main", "talk_anselm")
	GameState.add_item("fur_ledger")
	var lom := int(GameState.rep.get("lomond", 0))
	r.start("highland", "anselm")
	pick(r, "烽燧上的人快断粮了。")
	pick(r, "（翻开皮毛税账册）这几笔「留北境」的账，洛蒙德家那边也有一份吧。")
	check(r.text().contains("脸白了") and int(GameState.rep.get("lomond", 0)) == lom - 10, "亮出皮毛税账册：他脸白了，三车（洛蒙德家 −10）")
	pick(r, "……")
	check(str(GameState.get_flag("ch2_aid", "")) == "granted", "账册：谈成")
	# 银币
	GameState.set_flag("ch2_aid", false)
	GameState.set_stage("ch2_main", "talk_anselm")
	GameState.silver = 40
	r.start("highland", "anselm")
	pick(r, "烽燧上的人快断粮了。")
	pick(r, "（放下三十枚银币）就当是买三车粮上山的路钱。")
	pick(r, "……")
	check(GameState.silver == 10 and str(GameState.get_flag("ch2_aid", "")) == "granted", "三十银币：买三车的路钱（谈成）")
	# 谈不成：回去跟马蒂亚斯说
	GameState.set_flag("ch2_aid", "refused")
	GameState.set_stage("ch2_main", "aid_refused")
	r.start("beacon19", "matthias")
	pick(r, "安塞尔姆不肯。")
	check(has_opt(r, "那就劫。") and has_opt(r, "两手空空回去吧。"), "谈不成：马蒂亚斯——劫，或者两手空空")
	pick(r, "两手空空回去吧。")
	check(str(GameState.get_flag("beacon_grain", "")) == "lawful" and GameState.quest_stage("ch2_main") == "empty_handed", "两手空空：三夜变两夜（主线「两手空空」）")
	var m2 := await make_area("highland")
	await frames(3)
	check(m2.world.find_children("Convoy", "", true, false).size() == 1, "第二夜以前粮车还停在驿站门口")
	await free_main(m2)


## 5.7a 第二夜 · 劫粮：伏击段上五辆车、两边的人、车头的枯松；走到伏击点开打（先存档）；第二次潮水横穿山路、踩倒兵；火把点着车；结果旗标和声望
func _ambush_game(ambush: String, seed: int) -> void:
	GameState.new_game(seed)
	GameState.chapter = 2
	GameState.daypart = "night"
	for f in ["matthias_met", "norbert_met", "norbert_day2"]:
		GameState.set_flag(f)
	GameState.set_flag("ch2_first_tide", "held")
	GameState.set_flag("beacon_grain", "rob")
	GameState.set_flag("ch2_ambush", ambush)
	GameState.set_stage("ch2_main", "rob_ready")


func test_ambush() -> void:
	_ambush_game("head", 600)
	var main := await make_area("highland")
	await frames(3)
	var ca: ConvoyAmbush = main.world.get_node_or_null("ConvoyAmbush")
	var b: Battle = main.battle
	check(ca != null and b != null and not b.started and ca.get_node_or_null("AmbushCarts") != null and ca.get_node_or_null("FelledPine") != null
		and main.world.find_children("Convoy", "", true, false).is_empty(),
		"主线「设伏」：伏击段上五辆粮车、车头前锯倒的枯松（村里没有车了：出村了）")
	var ours := b.roster.filter(func(s): return s.side == ConvoyAmbush.OURS).size() + b.reserve.filter(func(e): return e[0].side == ConvoyAmbush.OURS).size()
	var foe := b.roster.filter(func(s): return s.side == ConvoyAmbush.FOE).size() + b.reserve.filter(func(e): return e[0].side == ConvoyAmbush.FOE).size()
	check(ours == 10 and foe == 16 and b.squad.size() == 10, "烽誓团 10 个人（小队）对洛蒙德家 16 个（押车队长、14 个押车兵、安塞尔姆）")
	var sp: Array = HighlandLayout.spawn_points().ambush
	check(absf(ConvoyAmbush.t_of(sp[0]) - ConvoyAmbush.SPAWN_T.head) < 0.5 and absf((sp[0] as Vector3).y - Highland.height_at(sp[0].x, sp[0].z)) < 0.3 and not ConvoyAmbush.at_post(sp[0]),
		"出生点在车头前的伏击段路上，离伏击点还有几步")
	var p: FpController = main.player
	p.global_position = ConvoyAmbush.leg_point(ConvoyAmbush.POST_T.head) + Vector3(0, 0.3, 0)
	await frames(3)
	check(b.started and not Saves.read_slot("auto").is_empty(), "走到伏击点：开打（先自动存档）")
	await seconds(2.0)
	b.elapsed = ConvoyAmbush.TIDE_AT + 0.1            # 跳到潮水那一刻（无头测试物理步数有上限，快进不了这么多）
	await physics(3)
	check(ca.tide_started and ca.crowd != null and ca.crowd.count == ConvoyAmbush.TIDE_COUNT and ca.crowd.victims.size() > 0,
		"开打 %d 秒后第二次潮水横穿山路：%d 个长眠者，兵也会被踩" % [ConvoyAmbush.TIDE_AT, ConvoyAmbush.TIDE_COUNT])
	var guard: Soldier = null
	for s in b.roster:
		if is_instance_valid(s) and s.side == ConvoyAmbush.FOE and s.fighting() and not s.is_captain:
			guard = s
			break
	if guard:
		var a: Dictionary = ca.crowd.agents[0]
		var m0 := guard.morale
		guard.global_position = Vector3(a.p.x, Highland.height_at(a.p.x, a.p.y) + 0.1, a.p.y)
		await physics(4)
		check(ca.crowd.trampled_soldiers > 0 and (guard.morale < m0 or not guard.fighting()), "挡在潮水前面的押车兵被推倒、踩过：士气 %.0f → %.0f" % [m0, guard.morale])
	else:
		check(false, "找得到一个押车兵")
	var c := ConvoyAmbush.leg_point(ConvoyAmbush.CART_T[1], 1.2)
	var pt := PlantedTorch.make(TorchHand.FUEL, false)
	main.world.add_child(pt)
	pt.global_position = c
	await physics(3)
	check(ca.carts_burning.has(1), "火把插在粮车边上：车上的麻袋着了")
	var lom := int(GameState.rep.get("lomond", 0))
	var oath := int(GameState.rep.get("beacon_oath", 0))
	main._on_battle_ended(ConvoyAmbush.OURS)
	check(str(GameState.get_flag("ch2_convoy", "")) == "burned" and GameState.quest_stage("ch2_main") == "dawn_after"
		and int(GameState.rep.get("lomond", 0)) == lom - 20 and int(GameState.rep.get("beacon_oath", 0)) == oath + 10,
		"赢了可烧了车：burned；洛蒙德家 −20、烽誓团 +10；主线「天亮以后」")
	await free_main(main)
	# 先断车尾：没有枯松；赢了车没烧 = taken；输了 = repelled
	_ambush_game("tail", 601)
	var m2 := await make_area("highland")
	await frames(3)
	var ca2: ConvoyAmbush = m2.world.get_node_or_null("ConvoyAmbush")
	check(ca2 != null and ca2.get_node_or_null("FelledPine") == null and absf(ConvoyAmbush.t_of(HighlandLayout.spawn_points().ambush[0]) - ConvoyAmbush.SPAWN_T.tail) < 0.5,
		"先断车尾：没有枯松，你在车尾后面")
	check(ca2.result(ConvoyAmbush.OURS) == "taken" and ca2.result(ConvoyAmbush.FOE) == "repelled", "车没烧赢了 = taken；输了 = repelled")
	await free_main(m2)
	# 卡斯滕留下来：多一个人；第十八烽点着：潮水小
	_ambush_game("head", 602)
	GameState.set_flag("ch2_carsten", "stayed")
	GameState.set_flag("ch2_beacon18", "lit")
	var m3 := await make_area("highland")
	await frames(3)
	check(m3.battle.squad.size() == 11 and m3.battle.squad.any(func(s): return s.display_override == "卡斯滕"), "卡斯滕留下来了：身边多一个人")
	var ca3: ConvoyAmbush = m3.world.get_node("ConvoyAmbush")
	ca3.player = m3.player
	m3.start_battle()
	ca3._start_tide()
	check(ca3.crowd.count == ConvoyAmbush.TIDE_COUNT_LIT18, "第十八烽点着了：第二夜的潮水小一些（%d 个）" % ConvoyAmbush.TIDE_COUNT_LIT18)
	await free_main(m3)


## 5.7b 第二夜 · 护粮：伏击段下头三辆车、举火把的兵、押车兵；动身前自动存档；车往上走；潮水；风吹灭火把、车夫慌了稳住 / 弃车；帮兵点火把；挡路就停；结果和声望
func _escort_game(seed: int) -> void:
	GameState.new_game(seed)
	GameState.chapter = 2
	GameState.daypart = "night"
	for f in ["matthias_met", "norbert_met", "norbert_day2"]:
		GameState.set_flag(f)
	GameState.set_flag("ch2_first_tide", "held")
	GameState.set_flag("beacon_grain", "lawful")
	GameState.set_flag("ch2_aid", "granted")
	GameState.set_stage("ch2_main", "escort_ready")


func test_escort() -> void:
	_escort_game(700)
	GameState.set_flag("ch2_requisition", "three")
	var main := await make_area("highland")
	await frames(3)
	var ce: ConvoyEscort = main.world.get_node_or_null("ConvoyEscort")
	check(ce != null and ce.carts.size() == 3 and ce.bearers.size() == 6 and ce.state == ConvoyEscort.WAIT
		and main.world.find_children("Convoy", "", true, false).is_empty() and main.world.get_node_or_null("ConvoyAmbush") == null,
		"主线「护车」：伏击段下头三辆粮车、六个举火把的兵（村里没有车了；没有劫粮那场仗）")
	check(ce.lit_bearers() == 6 and main.get_tree().get_nodes_in_group("light_source").filter(func(n): return ce.is_ancestor_of(n)).size() == 6,
		"六支火把都亮着（长眠者会绕开）")
	var sp: Array = HighlandLayout.spawn_points().escort
	check(absf(ConvoyAmbush.t_of(sp[0]) - ConvoyEscort.SPAWN_T) < 0.5 and ConvoyAmbush.t_of(sp[0]) < float(ce.carts[2].t),
		"出生点在车队后头的路上")
	ce.windy = false
	ce.wait_left = 0.0
	await frames(3)
	check(ce.state == ConvoyEscort.GO and not Saves.read_slot("auto").is_empty(), "到了几秒以后车队动身（先自动存档）")
	var t0 := float(ce.carts[0].t)
	await physics(30)
	check(float(ce.carts[0].t) > t0 + 0.2 and ce.carts.all(func(c): return c.state == "go"), "车往山脊上走（%.1f → %.1f 米）" % [t0, float(ce.carts[0].t)])
	ce.carts[0].t = ConvoyEscort.TIDE_START_T + 0.1
	await physics(3)
	check(ce.tide_started and ce.crowd != null and ce.crowd.count == ConvoyAmbush.TIDE_COUNT, "头车走到 %d 米：第二次潮水横穿山路（%d 个）" % [ConvoyEscort.TIDE_START_T, ConvoyAmbush.TIDE_COUNT])
	# 挡路：车头前有长眠者就停
	var a: Dictionary = ce.crowd.agents[0]
	var front := ConvoyAmbush.leg_point(float(ce.carts[1].t) + ConvoyEscort.BLOCK_AHEAD, 0.4)
	a.p = Vector2(front.x, front.z)
	check(ce._blocked(1), "车头前有长眠者挡着：车停下等")
	# 车夫慌：两边的火都灭了、长眠者在跟前
	for b in ce.bearers:
		if int(b.cart) == 0:
			ce._set_lit(b, false)
	var c0 := ce.cart_xz(0)
	a.p = c0 + Vector2(1.5, 0.0)
	main.player.global_position = ConvoyAmbush.leg_point(5.0) + Vector3(0, 0.3, 0)
	ce._panic(0, ConvoyEscort.PANIC_TIME * 0.6, [])
	var use0: Examine = ce.carts[0].use
	check(float(ce.carts[0].panic) > 0.5 and use0.verb_now() == "稳住车夫", "两边的火都灭了、长眠者在跟前：车夫慌了（对着车按 E 是「稳住车夫」）")
	var r := use0.interact(main.player)
	check(float(ce.carts[0].panic) == 0.0 and str(r.get("speech", "")) != "", "稳住车夫：他咬着牙点了点头")
	a.p = c0 + Vector2(1.5, 0.0)
	ce._panic(0, ConvoyEscort.PANIC_TIME + 1.0, [])
	check(ce.carts[0].state == "lost" and ce.lost() == 1, "慌满了：车夫扔下车跑了，这车粮丢了")
	# 火把：车上的油罐续火把；帮兵点上
	var k := ce.bearers.find(ce.bearers.filter(func(b): return int(b.cart) == 1)[0])
	ce._set_lit(ce.bearers[k], false)
	var hand: TorchHand = main.player.torch
	var bu: Examine = ce.bearers[k].use
	check(bu.verb_now() == "点着火把" and str(bu.interact(main.player).get("toast", "")).begins_with("得拿着") and not ce.bearers[k].lit, "手里没有点着的火把：帮不了他")
	(ce.carts[1].use as Examine).interact(main.player)
	check(hand.lit() and is_equal_approx(hand.fuel, TorchHand.FUEL), "对着车按 E：从油罐续火把（手里没有就拿一支点着的）")
	bu.interact(main.player)
	check(ce.bearers[k].lit, "举着点着的火把对着兵按 E：他的火把点着了")
	ce._set_lit(ce.bearers[k], false)
	ce.clock += ConvoyEscort.RELIGHT_SELF + 0.1
	ce._wind(0.0)
	check(ce.bearers[k].lit, "灭了没人管：过 %d 秒他自己从车上的油罐续上" % ConvoyEscort.RELIGHT_SELF)
	# 走完：两车上山 = delivered
	var lom := int(GameState.rep.get("lomond", 0))
	var oath := int(GameState.rep.get("beacon_oath", 0))
	var eld := int(GameState.rep.get("eld", 0))
	ce.carts[1].t = ConvoyEscort.END_T + 0.1
	ce.carts[2].t = ConvoyEscort.END_T + 0.1
	await physics(3)
	check(ce.state == ConvoyEscort.DONE and ce.through() == 2 and str(GameState.get_flag("ch2_convoy", "")) == "delivered" and GameState.quest_stage("ch2_main") == "dawn_after",
		"两车过了潮水：delivered；主线「天亮以后」")
	check(int(GameState.rep.get("lomond", 0)) == lom + 5 and int(GameState.rep.get("beacon_oath", 0)) == oath + 10 and int(GameState.rep.get("eld", 0)) == eld + 5,
		"护粮：洛蒙德家 +5、烽誓团 +10；用了征粮令的厄尔德家 +5")
	await free_main(main)
	# 一车也没上来：lost；第十八烽点着：潮水小
	_escort_game(701)
	GameState.set_flag("ch2_requisition", "five")
	GameState.set_flag("ch2_beacon18", "lit")
	var lom2 := int(GameState.rep.get("lomond", 0))
	var eld2 := int(GameState.rep.get("eld", 0))
	check(ConvoyEscort.finish("lost").begins_with("×") and int(GameState.rep.get("lomond", 0)) == lom2 - 5 and int(GameState.rep.get("eld", 0)) == eld2 - 5,
		"一车也没上来：lost（洛蒙德家 −5，用了征粮令的厄尔德家 −5）")
	_escort_game(702)
	GameState.set_flag("ch2_beacon18", "lit")
	var m2 := await make_area("highland")
	await frames(3)
	var ce2: ConvoyEscort = m2.world.get_node("ConvoyEscort")
	ce2._start_tide()
	check(ce2.crowd.count == ConvoyAmbush.TIDE_COUNT_LIT18, "第十八烽点着了：护粮那一夜的潮水也小一些（%d 个）" % ConvoyAmbush.TIDE_COUNT_LIT18)
	check(ConvoyEscort.finish("partial").begins_with("✓ 只有一车"), "一车上山：partial")
	await free_main(m2)


## 5.8a 天亮 · 火还在不在：粮上了山火亮着、没上来火熄了；诺伯特回到塔顶（亮着站着、灭了蹲在冷灰边），说完剩下的话、要带你去看冬井；马蒂亚斯按结果说一句；两手空空那一夜自己熬过去
func _dawn2_game(seed: int, grain: String, convoy: String) -> void:
	GameState.new_game(seed)
	GameState.chapter = 2
	GameState.daypart = "dawn"
	for f in ["matthias_met", "norbert_met", "norbert_day2"]:
		GameState.set_flag(f)
	GameState.set_flag("ch2_first_tide", "held")
	GameState.set_flag("beacon_grain", grain)
	if convoy != "":
		GameState.set_flag("ch2_convoy", convoy)
	GameState.set_stage("ch2_main", "rob_ready" if grain == "rob" else "escort_ready")
	Chapter2.dawn()


func test_dawn2() -> void:
	for pair in [["taken", "lit"], ["burned", "lit"], ["repelled", "out"], ["delivered", "lit"], ["partial", "lit"], ["lost", "out"], ["", "out"]]:
		_dawn2_game(800, "rob", str(pair[0]))
		check(str(GameState.get_flag("ch2_fire", "")) == str(pair[1]) and GameState.quest_stage("ch2_main") == "dawn_after",
			"第二夜 %s：天亮时火 %s，主线「天亮以后」" % [pair[0] if pair[0] != "" else "两手空空", pair[1]])
	# 火亮着：塔顶的火、诺伯特站在火盆边；小屋里没有他
	_dawn2_game(801, "rob", "taken")
	var main := await make_area("highland")
	(main.streamer as ChunkStreamer).build_all()
	await frames(3)
	var w: Node = main.world
	var flames: Array = w.find_children("BeaconFlames", "Node3D", true, false)
	var ash: Array = w.find_children("BeaconAsh", "Node3D", true, false)
	var nb: Array = w.find_children("Npc_norbert*", "", true, false)
	check(flames.size() == 1 and (flames[0] as Node3D).visible and ash.size() == 1 and not (ash[0] as Node3D).visible, "火亮着：塔顶火盆里的火在烧")
	check(nb.size() == 1 and nb[0].name == "Npc_norbert" and (nb[0] as Node3D).global_position.y > HighlandLayout.tower_base_y() + HighlandLayout.TOWER_H - 0.5,
		"诺伯特又上了塔顶，站在火盆边")
	await free_main(main)
	var tower := await make_area("beacon_tower")
	await frames(3)
	check(tower.world.find_children("Npc_norbert_room", "", true, false).is_empty(), "小屋里没有他了")
	await free_main(tower)
	var r := DialogueRunner.new()
	r.start("beacon19", "norbert")
	check(r.text().contains("劫来的") and r.text().contains("火还亮着"), "诺伯特（劫来的粮）：洛蒙德家会记着这一笔，可火还亮着")
	pick(r, "你说过，等火还亮着的时候再说。")
	check(r.text().contains("等了二十五年") and r.text().contains("来的是你"), "守满十年没走：等一个人上山来问那一夜")
	pick(r, "你在等什么？")
	check(r.text().contains("冬井") and GameState.quest_stage("ch2_main") == "to_well" and GameState.has_flag("norbert_dawn"),
		"老规矩：封好的誓瓶送到冬井；那一夜瓶是空的，他没去过——要带你去看（主线「冬井」）")
	r.start("beacon19", "norbert")
	check(r.text().contains("趁天亮"), "再找他：走吧，趁天亮")
	r.start("beacon19", "matthias")
	check(r.text().contains("五车") and r.text().contains("诺伯特在塔顶"), "马蒂亚斯：劫下了五车")
	# 刻过字的：他接上「封于冬井」
	_dawn2_game(802, "lawful", "delivered")
	GameState.set_flag("ch2_stones", "copied")
	r.start("beacon19", "norbert")
	check(r.text().contains("安塞尔姆送上来的"), "诺伯特（护粮）：洛蒙德家欠了北边一个人情")
	pick(r, "你说过，等火还亮着的时候再说。")
	pick(r, "你在等什么？")
	check(r.text().begins_with("石圈上那句话"), "念过石圈上的字：他接上「封于冬井」")
	# 火灭了：冷灰、诺伯特蹲在冷灰边，话短一些
	_dawn2_game(803, "rob", "repelled")
	var m2 := await make_area("highland")
	(m2.streamer as ChunkStreamer).build_all()
	await frames(3)
	var f2: Array = m2.world.find_children("BeaconFlames", "Node3D", true, false)
	var a2: Array = m2.world.find_children("BeaconAsh", "Node3D", true, false)
	check(not (f2[0] as Node3D).visible and (a2[0] as Node3D).visible and m2.world.find_children("Npc_norbert_cold", "", true, false).size() == 1
		and not SleeperCrowd.fires(m2.get_tree()).any(func(f): return (f[0] as Vector2).distance_to(HighlandLayout.TOWER[0]) < 3.0),
		"火灭了：火盆里一层冷灰，诺伯特蹲在边上（火不再让长眠者绕开）")
	await free_main(m2)
	r.start("beacon19", "norbert")
	check(r.text().contains("冷灰") and r.text().contains("抬着伤兵"), "诺伯特（被打退）：灭了，伤兵抬回来的时候只剩一点红")
	pick(r, "……火灭了。")
	check(r.text().contains("火却灭了"), "话短一些：来的是你，火却灭了")
	pick(r, "……")
	check(GameState.quest_stage("ch2_main") == "to_well", "照样要带你去看冬井")
	r.start("beacon19", "matthias")
	check(r.text().contains("没劫下来"), "马蒂亚斯：没劫下来，三个弟兄抬回来的")
	# 两手空空：那一夜自己熬过去（天黑 → 天亮，火熄了；天亮那一刻诺伯特上塔顶）
	GameState.new_game(804)
	GameState.chapter = 2
	GameState.daypart = "day"
	for f in ["matthias_met", "norbert_met", "norbert_day2"]:
		GameState.set_flag(f)
	GameState.set_flag("ch2_first_tide", "held")
	GameState.set_flag("beacon_grain", "lawful")
	GameState.set_flag("ch2_aid", "refused")
	GameState.set_stage("ch2_main", "empty_handed")
	var m3 := await make_area("highland")
	(m3.streamer as ChunkStreamer).build_all()
	await frames(3)
	check(m3.empty_night and GameState.daypart == "night", "两手空空：天黑了，柴省着烧")
	check(m3.world.find_children("Npc_norbert*", "", true, false).is_empty(), "夜里诺伯特不在塔顶")
	Chapter2.dawn()
	m3._ch2_dawn_world()
	await frames(2)
	var f3: Array = m3.world.find_children("BeaconFlames", "Node3D", true, false)
	check(GameState.daypart == "dawn" and str(GameState.get_flag("ch2_fire", "")) == "out" and not (f3[0] as Node3D).visible
		and m3.world.find_children("Npc_norbert_cold", "", true, false).size() == 1 and not Saves.read_slot("auto").is_empty(),
		"天亮：火熄了（冷灰），诺伯特上了塔顶，自动存档")
	await free_main(m3)
	r.start("beacon19", "matthias")
	check(r.text().contains("两手空空"), "马蒂亚斯：两手空空，火天亮前就灭了")


## 5.8b 白寂边缘 · 冬井：井一直在；主线「冬井」诺伯特从塔顶下去、在山脊背后等你，领你走到井边；一圈长眠的人、认得的脸；到了井边过一会儿章末（回顾、钩子、没有「继续」）
func _well_game(seed: int, stage: String) -> void:
	GameState.new_game(seed)
	GameState.chapter = 2
	GameState.daypart = "dawn"
	for f in ["matthias_met", "norbert_met", "norbert_day2"]:
		GameState.set_flag(f)
	GameState.set_flag("ch2_first_tide", "held")
	GameState.set_flag("beacon_grain", "rob")
	GameState.set_flag("ch2_convoy", "taken")
	GameState.set_stage("ch2_main", "rob_ready")
	Chapter2.dawn()
	GameState.set_stage("ch2_main", stage)


func test_well() -> void:
	# 天亮以后、还没说完：井在，圈和山脊上的诺伯特还没有；诺伯特在塔顶
	_well_game(900, "dawn_after")
	GameState.set_flag("ch1_sleeper", "tobin")
	GameState.set_flag("ch2_nell", "left")
	GameState.set_flag("ch2_beacon18", "lit")
	var main := await make_area("highland")
	(main.streamer as ChunkStreamer).build_all()
	await frames(3)
	var ww: WinterWell = main.world.get_node_or_null("WinterWell")
	check(ww != null and ww.get_node_or_null("WinterWellStones") != null and ww.ring == null and ww.norbert == null
		and main.world.find_children("Npc_norbert", "", true, false).size() == 1,
		"冰原上的石井一直在；诺伯特还在塔顶，井边还没有人")
	# 他说完了（主线「冬井」）：对话关了以后从塔顶下去，在山脊背后等你；圈摆上
	GameState.set_stage("ch2_main", "to_well")
	await frames(3)
	check(main.world.find_children("Npc_norbert", "", true, false).is_empty() and ww.norbert != null and ww.norbert.name == "Npc_norbert_well"
		and Vector2(ww.norbert.global_position.x, ww.norbert.global_position.z).distance_to(WinterWell.RIDGE_WAIT) < 0.5,
		"主线「冬井」：诺伯特从天窗下去，在山脊背后等你")
	check(ww.ring != null and ww.ring.get_child_count() == WinterWell.RING_N and ww.faces.size() == 6,
		"井边站着一圈 %d 个人；认得的脸 6 张（芦栈村的托宾、妮尔和她父亲、第十八烽的三个守塔人）" % WinterWell.RING_N)
	var y_ok := true
	for k in WinterWell.RING_N:
		var q := WinterWell.slot(k)
		y_ok = y_ok and absf(WinterWell.ground(q).y - Highland.height_at(q.x, q.y)) < 0.01 and q.distance_to(HighlandLayout.WELL) > 5.0
	check(y_ok, "一圈人都站在冰原上、离井 %.1f 米" % WinterWell.RING_R)
	var said: Array = []
	ww.recognized.connect(func(t: String): said.append(t))
	var p: FpController = main.player
	var np := WinterWell.RIDGE_WAIT + Vector2(2.0, 2.0)
	p.global_position = WinterWell.ground(np) + Vector3(0, 0.3, 0)
	await physics(2)
	check(ww.norbert_state == "walk", "走到他跟前：他往冰原下面走")
	var goal := WinterWell.stop_point()
	ww.norbert.global_position = WinterWell.ground(goal + (WinterWell.RIDGE_WAIT - goal).normalized() * 0.02)
	await physics(3)
	check(ww.norbert_state == "there" and Vector2(ww.norbert.global_position.x, ww.norbert.global_position.z).distance_to(HighlandLayout.WELL) < WinterWell.STOP_R + 0.1,
		"他停在井边 %.1f 米" % WinterWell.STOP_R)
	var a := WinterWell.slot(1) + (WinterWell.slot(1) - HighlandLayout.WELL).normalized() * 3.0
	p.global_position = WinterWell.ground(a) + Vector3(0, 0.3, 0)
	await physics(3)
	check(ww.revealed_said and said.any(func(t): return str(t).contains("托宾")), "走近了：一圈人一动不动；认出芦栈村的托宾")
	var b := WinterWell.slot(9) + (WinterWell.slot(9) - HighlandLayout.WELL).normalized() * 3.0
	p.global_position = WinterWell.ground(b) + Vector3(0, 0.3, 0)
	await physics(3)
	check(said.any(func(t): return str(t).contains("妮尔")), "圈里站着妮尔（随她去了的）")
	check(ww.reached_sent, "他到了、你也到了井边")
	await seconds(main.well_end_after + 0.6)
	var ep: EndingPanel = main.ending_panel
	check(GameState.has_flag("ch2_done") and GameState.quest_stage("ch2_main") == "ch2_end" and ep.visible and ep.title.text == "第三章 · 粮与铁"
		and ep.header.text.contains("熄灭的烽燧") and not ep.continue_btn.visible and not Saves.read_slot("auto").is_empty(),
		"过一会儿章末：「第二章「熄灭的烽燧」完 / 第三章 · 粮与铁 / 开发中」，没有「继续」（第三章还没有），自动存档")
	check(ep.recap.text.contains("劫下了洛蒙德家的五车粮") and ep.recap.text.contains("第十八烽") and ep.recap.text.contains("妮尔往北去了") and ep.recap.text.contains("火还亮着"),
		"回顾按旗标写：第一夜、第十八烽、劫下五车、火、妮尔")
	check(ep.seal.text.contains("冬井") and ep.seal.text.contains("芦栈村那个人") and ep.seal.text.contains("妮尔也在"), "钩子：封誓少做的一步、冬井边那一圈人、认得的脸")
	ep.close()
	await frames(2)
	check(not main.get_tree().paused, "在雪原上再站一会儿：关掉接着走")
	await free_main(main)
	# 章末以后再来：诺伯特在井边，圈还在；小屋、塔顶都没有他
	_well_game(901, "ch2_end")
	var m2 := await make_area("highland")
	(m2.streamer as ChunkStreamer).build_all()
	await frames(3)
	var w2: WinterWell = m2.world.get_node("WinterWell")
	check(w2.norbert_state == "there" and w2.ring != null and w2.ring.get_child_count() == WinterWell.RING_N and w2.faces.is_empty() and m2.world.find_children("Npc_norbert", "", true, false).is_empty(),
		"章末以后再来：诺伯特站在井边，那一圈人还在（没有认得的脸就都是生人）")
	await free_main(m2)
	# 回顾的另外几种
	_well_game(902, "to_well")
	GameState.set_flag("beacon_grain", "lawful")
	GameState.set_flag("ch2_convoy", "delivered")
	GameState.set_flag("ch2_requisition", "three")
	GameState.set_flag("ch2_carsten", "freed")
	check(Chapter2.recap().contains("护着粮车穿过了潮水") and Chapter2.recap().contains("征粮令") and Chapter2.recap().contains("卡斯滕守满了十年"), "回顾：护粮、征粮令、卡斯滕")
	_well_game(903, "to_well")
	GameState.set_flag("ch2_convoy", false)
	GameState.set_flag("ch2_aid", "refused")
	GameState.set_flag("ch2_fire", "out")
	check(Chapter2.recap().contains("两手空空") and Chapter2.recap().contains("火熄了"), "回顾：两手空空、火熄了")


## 5.9 第二章全流程：第一章两种继承人 × 堤道守住 / 失守 × 劫粮 / 求援，再加一条谈不成两手空空——
## 从第一章章末「继续：第二章」开始，按真的对话选项、真的换区域走到第二章章末（第一夜潮水、第二夜那一仗 / 护车只把最慢的一截快进：潮水直接收尾、仗直接判赢、车直接推到头）
func _ch2_go(main: Node3D) -> Node3D:
	for i in 6:
		await frames(1)
		if GameState.pending_load.has("scene"):
			return await reload_main(main)
	return main


func _ch2_at(main: Node3D, xz: Vector2) -> void:
	main.player.global_position = Vector3(xz.x, Highland.height_at(xz.x, xz.y) + 0.3, xz.y)
	await physics(3)


func _ch2_run(heir: String, causeway: String, grain: String, seed: int) -> void:
	var tag := "[%s · %s · %s]" % ["阿尔里克" if heir == "alric" else "伊薇特", "守住" if causeway == "held" else "失守", {"rob": "劫粮", "lawful": "求援", "empty": "两手空空"}[grain]]
	GameState.new_game(seed)
	GameState.pending_load = {}
	GameState.chapter = 1
	GameState.start_quest("ch1_main")
	GameState.set_stage("ch1_main", "ch1_end")
	for f in ["prologue_done", "ch1_started", "ch1_done", "ch1_sleeper"]:
		GameState.set_flag(f)
	GameState.set_flag("ch1_sleeper", "tobin")
	GameState.set_flag("valen_heir", heir)
	GameState.set_flag("ch1_causeway", causeway)
	var main := await make_main(false)
	main.show_ending("ch1")
	await frames(2)
	check(main.ending_panel.continue_btn.visible and main.ending_panel.next_chapter == 2, "%s 第一章章末：「继续：第二章」" % tag)
	main.ending_panel.continue_btn.pressed.emit()
	await frames(2)
	main = await reload_main(main)
	await frames(3)
	check(main.area == "highland" and GameState.chapter == 2 and GameState.daypart == "day" and GameState.quest_stage("ch2_main") == "ask_yangji"
		and GameState.has_item("ivette_letter") == (heir == "ivette"), "%s 到了羊脊村：第二章开始（白天，主线「问路」%s）" % [tag, "，带着伊薇特的信" if heir == "ivette" else ""])
	# 驿站：罗薇娜指路
	var picks := ["我从黑鹭堡来。老家主临终让我去烽燧线找一个人。", "当年老王加冕礼上的另一个侍从。", "明白了。", "告辞。"]
	if heir == "ivette":
		picks = ["（把伊薇特小姐的信递给她）", "我会的。"] + picks
	check(await fl_say(main, "waystation", "rowena", picks) and GameState.quest_stage("ch2_main") == "to_beacon19", "%s 罗薇娜：诺伯特在第十九烽" % tag)
	# 上第十九烽：天擦黑
	await _ch2_at(main, HighlandLayout.BEACON19 + Vector2(-2.0, 7.0))
	for i in 60:                                     # 整套跑的时候前面几组留下的东西多，几帧以后才轮到「到了烽燧」那一下（单跑这一组 3 帧就到）
		if GameState.quest_stage("ch2_main") == "meet_matthias":
			break
		await physics(1)
	check(GameState.quest_stage("ch2_main") == "meet_matthias" and GameState.daypart == "dusk", "%s 爬上山脊：天擦黑了（主线 %s，时段 %s）" % [tag, GameState.quest_stage("ch2_main"), GameState.daypart])
	check(await fl_say(main, "beacon19", "matthias", ["我从黑鹭堡来，找诺伯特烽长。", "明白了。"]) and GameState.quest_stage("ch2_main") == "see_norbert", "%s 马蒂亚斯：诺伯特在塔顶" % tag)
	if causeway == "lost":
		check(await fl_say(main, "beacon19", "norbert", ["我这就去柴棚扛。"]) and GameState.quest_stage("ch2_main") == "carry_wood", "%s 堤道失守：诺伯特先要你扛一捆柴上来" % tag)
		GameState.add_item("firewood")
		picks = ["（把那捆柴放到火盆边）", "奥斯瑞克·瓦伦临终让我来找你。", "加冕礼上发生了什么？", "……好。先过了今夜。"]
	else:
		picks = ["奥斯瑞克·瓦伦临终让我来找你。", "加冕礼上发生了什么？", "……好。先过了今夜。"]
	check(await fl_say(main, "beacon19", "norbert", picks) and GameState.quest_stage("ch2_main") == "first_night", "%s 诺伯特：先过了今夜" % tag)
	# 第一夜：四支火把、插满木桩、潮水
	check(await fl_say(main, "beacon19", "matthias", ["诺伯特说「先过了今夜」。入夜以后怎么守？", "我这就去。"]) and GameState.quest_stage("ch2_main") == "light_line"
		and GameState.daypart == "night" and GameState.count_item("torch") >= 4, "%s 马蒂亚斯给四支火把，天黑透了" % tag)
	await frames(3)
	var ft: FirstTide = main.first_tide
	var sp := FirstTide.spots()
	for k in range(1, FirstTide.SPOT_N - 1):
		var pt := PlantedTorch.make(TorchHand.FUEL, false)
		ft.add_child(pt)
		var q: Vector2 = sp[k]
		pt.global_position = Vector3(q.x, Highland.height_at(q.x, q.y), q.y)
	await physics(3)
	check(ft.state == FirstTide.TIDE and GameState.quest_stage("ch2_main") == "tide", "%s 木桩插满：潮水上来了" % tag)
	ft.finish()
	await frames(3)
	check(str(GameState.get_flag("ch2_first_tide", "")) == "held" and GameState.quest_stage("ch2_main") == "after_tide" and GameState.daypart == "dawn", "%s 第一夜守住了，天亮" % tag)
	# 第二天：诺伯特的加冕礼
	check(await fl_say(main, "beacon19", "norbert", ["加冕礼那一夜，发生了什么？", "为什么少做了？", "还有谁知道那一夜？", "我该做什么？", "……我下山去看看。"])
		and GameState.quest_stage("ch2_main") == "convoy_day", "%s 诺伯特：封誓少做了一步；先保住烽燧（主线「粮车到村」）" % tag)
	# 抉择
	match grain:
		"rob":
			check(await fl_say(main, "beacon19", "matthias", ["粮车的事，你怎么打算？", "劫。", "先断车头：砍倒那棵枯松拦路。", "……"]) and GameState.quest_stage("ch2_main") == "rob_ready", "%s 劫：先断车头" % tag)
			main = await _ch2_go(main)
			var ca: ConvoyAmbush = main.world.get_node_or_null("ConvoyAmbush")
			check(ca != null and main.battle != null and GameState.daypart == "night", "%s 天黑透了：伏击段上摆好了那一仗" % tag)
			main.player.global_position = ConvoyAmbush.leg_point(ConvoyAmbush.POST_T.head) + Vector3(0, 0.3, 0)
			await physics(3)
			check(main.battle.started, "%s 走到伏击点：开打" % tag)
			main._on_battle_ended(ConvoyAmbush.OURS)
			check(str(GameState.get_flag("ch2_convoy", "")) == "taken", "%s 劫下了五车粮" % tag)
		"lawful", "empty":
			check(await fl_say(main, "beacon19", "matthias", ["粮车的事，你怎么打算？", "我先去找押粮官谈。", "……"]) and GameState.quest_stage("ch2_main") == "talk_anselm", "%s 去找安塞尔姆谈" % tag)
			if grain == "lawful":
				check(await fl_say(main, "waystation", "rowena", ["桌上那张盖了印的空白文书，现在用得着了。", "……", "告辞。"]) and GameState.has_item("requisition"), "%s 罗薇娜给了空白征粮令" % tag)
				check(await fl_say(main, "highland", "anselm", ["烽燧上的人快断粮了。", "（摊开征粮令，写上「三车」）厄尔德家征三车粮，送上第十九烽。", "……"]) and GameState.quest_stage("ch2_main") == "escort_ready",
					"%s 安塞尔姆认了征粮令：分三车粮上山，要你护车" % tag)
				main = await _ch2_go(main)
				var ce: ConvoyEscort = main.world.get_node_or_null("ConvoyEscort")
				check(ce != null and GameState.daypart == "night", "%s 天黑透了：三辆车在盘山路上" % tag)
				ce.windy = false
				ce.wait_left = 0.0
				await frames(3)
				for c in ce.carts:
					c.t = ConvoyEscort.END_T + 0.1
				await physics(3)
				check(str(GameState.get_flag("ch2_convoy", "")) == "delivered", "%s 三车粮翻过了山脊" % tag)
			else:
				check(await fl_say(main, "highland", "anselm", ["烽燧上的人快断粮了。", "……我再想想。"]), "%s 安塞尔姆：粮不卖" % tag)
				GameState.set_flag("ch2_aid", "refused")
				GameState.set_stage("ch2_main", "aid_refused")
				check(await fl_say(main, "beacon19", "matthias", ["安塞尔姆不肯。", "两手空空回去吧。", "……"]) and GameState.quest_stage("ch2_main") == "empty_handed", "%s 两手空空" % tag)
				await frames(3)
				check(main.empty_night and GameState.daypart == "night", "%s 这一夜就这么熬过去" % tag)
				Chapter2.dawn()
	main._ch2_dawn_world()
	await frames(2)
	var lit := grain != "empty"
	check(GameState.quest_stage("ch2_main") == "dawn_after" and GameState.daypart == "dawn" and Chapter2.fire_out() != lit, "%s 天亮：第十九烽的火%s" % [tag, "还亮着" if lit else "熄了"])
	# 天亮：诺伯特说完，冬井
	picks = ["你说过，等火还亮着的时候再说。", "你在等什么？", "……走吧。"] if lit else ["……火灭了。", "……", "……走吧。"]
	check(await fl_say(main, "beacon19", "norbert", picks) and GameState.quest_stage("ch2_main") == "to_well", "%s 诺伯特说完剩下的话：去看冬井" % tag)
	await frames(3)
	var ww: WinterWell = main.world.get_node_or_null("WinterWell")
	check(ww != null and ww.ring != null and ww.norbert != null, "%s 诺伯特在山脊背后等你，井边站着一圈人" % tag)
	main.well_end_after = 0.2
	await _ch2_at(main, WinterWell.RIDGE_WAIT + Vector2(1.5, 1.5))
	var goal := WinterWell.stop_point()
	ww.norbert.global_position = WinterWell.ground(goal + (WinterWell.RIDGE_WAIT - goal).normalized() * 0.02)
	await physics(3)
	await _ch2_at(main, HighlandLayout.WELL + (WinterWell.slot(1) - HighlandLayout.WELL).normalized() * 9.0)
	await seconds(0.5)
	var ep: EndingPanel = main.ending_panel
	check(GameState.has_flag("ch2_done") and ep.visible and ep.title.text == "第三章 · 粮与铁" and ep.seal.text.contains("芦栈村那个人"), "%s 冬井边：第二章章末" % tag)
	var want: String = {"rob": "劫下了洛蒙德家的五车粮", "lawful": "护着粮车穿过了潮水", "empty": "两手空空"}[grain]
	check(ep.recap.text.contains(want), "%s 回顾：%s" % [tag, want])
	ep.close()
	await frames(2)
	await free_main(main)


func test_ch2flow() -> void:
	GameState.pending_daypart = "night"              # 前面的组留下的「对话关上以后换成夜」：新的一局不该带过来
	GameState.new_game(949)
	check(GameState.pending_daypart == "", "新的一局：上一局对话里没换完的时段清掉")
	var seed := 950
	for heir in ["alric", "ivette"]:
		for causeway in ["held", "lost"]:
			for grain in ["rob", "lawful"]:
				await _ch2_run(heir, causeway, grain, seed)
				seed += 1
	await _ch2_run("ivette", "held", "empty", seed)


## O.1 出身三选一：数据、加成只加一次、新游戏在标题卡上选（选的这一下开始开场）、数字键、存档带着、旧存档读进来问一次、角色面板写着
func test_origin() -> void:
	check(Origins.ids() == ["knight", "deserter", "ferry"] and Origins.name_of("deserter") == "烽誓团逃兵" and Origins.bonus_text("ferry").contains("口才 +5") and Origins.bonus_text("deserter").contains("烽誓团 −5"),
		"三种出身：落魄骑士之后 / 烽誓团逃兵 / 渡工之子，各有开局加成（%s）" % Origins.bonus_text("knight"))
	GameState.new_game(1001)
	var blade := int(GameState.skills.blade)
	var st := GameState.strength
	check(Origins.current() == "" and Origins.apply("knight") and Origins.current() == "knight" and int(GameState.skills.blade) == blade + 5 and GameState.strength == st + 1,
		"选落魄骑士之后：旗标 origin、剑术 +5、力量 +1")
	check(not Origins.apply("ferry") and Origins.current() == "knight" and int(GameState.skills.blade) == blade + 5, "选过了不能再选、加成不会加两次")
	var font: FontFile = load("res://assets/fonts/NotoSansSC-IC.ttf")
	var lack := ""
	var all_text := "你是谁？这份存档还没有出身——"
	for id in Origins.ids():
		all_text += Origins.name_of(id) + str(Origins.spec(id).short) + str(Origins.spec(id).desc) + Origins.bonus_text(id)
	for i in all_text.length():
		if all_text.unicode_at(i) > 32 and not font.has_char(all_text.unicode_at(i)) and not lack.contains(all_text[i]):
			lack += all_text[i]
	check(lack == "", "出身画面的字都在字体子集里（缺：%s）" % lack)
	var d := GameState.to_dict()
	GameState.new_game(1002)
	GameState.from_dict(d)
	check(Origins.current() == "knight" and int(GameState.skills.blade) == blade + 5, "存档带着出身")
	# 新游戏：标题卡上先选出身
	Engine.set_meta("ic_skip_opening", false)
	GameState.new_game(1003)
	var surv := int(GameState.skills.survival)
	var main := await make_main(false)
	await frames(3)
	var op: Opening = main.opening
	var panel: OriginPanel = main.origin_panel
	check(op != null and op.stage == "card" and panel.visible and panel.buttons.size() == 3 and main.title_card.prompt.text == "", "新游戏：标题卡上三个出身，选了才开始")
	op._input(key_ev(KEY_SPACE))
	await frames(1)
	check(op.stage == "card", "没选出身：按键不开始开场")
	(panel.buttons["deserter"] as Button).pressed.emit()
	await frames(2)
	check(not panel.visible and op.stage == "bell" and Origins.current() == "deserter" and int(GameState.skills.survival) == surv + 8 and GameState.get_rep("beacon_oath") == -5,
		"选烽誓团逃兵：开场开始（钟声），生存 +8、烽誓团 −5")
	main.char_panel.open()
	await frames(1)
	check(main.char_panel.header_text().begins_with("烽誓团逃兵"), "角色面板写着出身")
	main.char_panel.close()
	await free_main(main)
	# 数字键选
	GameState.new_game(1004)
	main = await make_main(false)
	await frames(3)
	main.origin_panel._unhandled_key_input(key_ev(KEY_3))
	await frames(2)
	check(Origins.current() == "ferry" and main.opening.stage == "bell" and GameState.get_rep("ferrymen") == 10, "按 3：渡工之子（渡工行会 +10）")
	await free_main(main)
	Engine.set_meta("ic_skip_opening", true)
	# 旧存档（没有出身）读进来：问一次
	GameState.new_game(1005)
	GameState.set_flag("opening_done")
	var old := GameState.to_dict()
	old.flags.erase("origin")
	Engine.set_meta("ic_skip_opening", false)
	GameState.from_dict(old)
	GameState.pending_load = {"scene": "frostford", "slot": "slot1", "player": {}}
	main = await make_main(false)
	await frames(4)
	check(main.origin_panel.visible and main.origin_panel.as_prompt and main.get_tree().paused and main.opening == null, "旧存档读进来：暂停着问一次出身（不播开场）")
	(main.origin_panel.buttons["knight"] as Button).pressed.emit()
	await frames(2)
	check(Origins.current() == "knight" and not main.get_tree().paused and not main.origin_panel.visible, "选了：加上出身，接着玩")
	await free_main(main)
	Engine.set_meta("ic_skip_opening", true)
	# 选过出身的存档不再问
	GameState.pending_load = {"scene": "frostford", "slot": "slot1", "player": {}}
	Engine.set_meta("ic_skip_opening", false)
	main = await make_main(false)
	await frames(4)
	check(not main.origin_panel.visible and not main.get_tree().paused, "有出身的存档：不再问")
	await free_main(main)
	Engine.set_meta("ic_skip_opening", true)


## O.2 一路上的对话随出身变：渡工之子（灰手奥弗、芦栈村的渡工）、落魄骑士之后（赫尔曼、阿尔里克、安塞尔姆）、烽誓团逃兵（马蒂亚斯、卡斯滕、安塞尔姆）；别的出身看不到这些
func _o2(origin: String) -> DialogueRunner:
	GameState.new_game(1100)
	if origin != "":
		GameState.set_flag("origin", origin)
	return DialogueRunner.new()


func test_origin2() -> void:
	# 渡工之子：灰手奥弗
	var r := _o2("ferry")
	r.start("ferry", "offer")
	pick(r, "我来接瓦伦家的少爷。")
	var ferry_opt := "灰鲸河上的人不卖河上的人。我爹在这渡口撑了二十年船——你手下那几个，有谁没坐过他的船？"
	check(has_opt(r, ferry_opt), "渡工之子：跟灰手奥弗多一条路（河上的人不卖河上的人，口才 9）")
	GameState.checks["offer_ferry_speech"] = true
	pick(r, ferry_opt)
	check(r.text().contains("老船头的儿子") and GameState.has_flag("offer_left"), "他认出你爹：收家伙走人")
	r = _o2("knight")
	r.start("ferry", "offer")
	pick(r, "我来接瓦伦家的少爷。")
	check(not has_opt(r, ferry_opt), "别的出身没有这条")
	# 渡工之子：芦栈村的渡工
	r = _o2("ferry")
	r.start("reedwharf", "boatman")
	check(r.text().contains("撑过船的手"), "芦栈村的渡工看你的手：撑过船的")
	pick(r, "南边最近有人过来吗？")
	pick(r, "我爹也是渡工行会的。规矩我懂——我不问你渡了谁，只问他往哪去了。")
	check(GameState.has_flag("heard_envoy") and GameState.silver == GameState.START_SILVER, "行会里的人：不花钱、不用检定就说了信使的事")
	r = _o2("")
	r.start("reedwharf", "boatman")
	check(not r.text().contains("撑过船的手"), "没出身：照旧")
	# 落魄骑士之后：赫尔曼
	r = _o2("knight")
	GameState.set_flag("castle_entry", "gate")
	r.start("blackheron", "herman")
	check(r.text().contains("老派的握法"), "落魄骑士之后：赫尔曼看你握剑的样子")
	GameState.set_flag("ledger_asked")
	r.start("blackheron", "herman")
	pick(r, "账房的钥匙……")
	var key_opt := "我家祖上替领主守过账房。钥匙交出去是什么分量，我知道——账拿出来，只给家主一个人看。"
	check(has_opt(r, key_opt), "要账房钥匙多一条路（口才 11，比原来的 15 容易）")
	GameState.checks["herman_key_knight"] = true
	pick(r, key_opt)
	check(GameState.has_item("counting_key"), "他给了钥匙")
	# 落魄骑士之后：阿尔里克
	r = _o2("knight")
	r.start("hall", "alric")
	check(r.text().contains("行的是老礼"), "阿尔里克看你行礼：老礼")
	var v0 := GameState.get_rep("valen")
	pick(r, "我家也有过封地。")
	check(r.text().contains("封地是守出来的") and GameState.get_rep("valen") == v0 + 3, "「封地是守出来的，不是传下来的」（瓦伦家 +3）")
	# 安塞尔姆：骑士之后 / 逃兵各一条路
	for pair in [["knight", "（报上你家的旧姓）", "anselm_knight"], ["deserter", "我在烽燧线上守过三年。", "anselm_deserter"]]:
		r = _o2(str(pair[0]))
		GameState.chapter = 2
		GameState.set_stage("ch2_main", "talk_anselm")
		r.start("highland", "anselm")
		pick(r, "烽燧上的人快断粮了。")
		var opt := ""
		for o in r.options():
			if str(o.text).begins_with(str(pair[1])):
				opt = str(o.text)
		check(opt != "", "%s：跟安塞尔姆多一条路" % Origins.name_of(str(pair[0])))
		GameState.checks[str(pair[2])] = true
		pick(r, opt)
		check(str(GameState.get_flag("ch2_aid", "")) == "granted", "%s：说动了，分三车粮上山" % Origins.name_of(str(pair[0])))
	r = _o2("ferry")
	GameState.chapter = 2
	GameState.set_stage("ch2_main", "talk_anselm")
	r.start("highland", "anselm")
	pick(r, "烽燧上的人快断粮了。")
	check(not r.options().any(func(o): return str(o.text).begins_with("（报上你家的旧姓）") or str(o.text).begins_with("我在烽燧线上守过三年。")), "渡工之子没有这两条")
	# 烽誓团逃兵：马蒂亚斯、卡斯滕
	r = _o2("deserter")
	GameState.chapter = 2
	GameState.set_stage("ch2_main", "meet_matthias")
	r.start("beacon19", "matthias")
	pick(r, "……我守过烽燧。三年。")
	check(r.text().contains("你看塔的样子就知道") and GameState.has_flag("matthias_knows_deserter"), "烽誓团逃兵：马蒂亚斯早看出来了（记下，O.3 名册用）")
	GameState.set_flag("ch2_first_tide", "held")
	r.start("beacon19", "carsten")
	pick(r, "守满十年，就能走？")
	pick(r, "我也下过山。第四年冬天，一个人。")
	check(r.text().contains("号角") and r.node_id == "deserter", "卡斯滕：下了山以后夜里还听得见号角")
	pick(r, "……")
	check(r.node_id == "rule" and not has_opt(r, "我也下过山。第四年冬天，一个人。"), "说过一次就不再出现，回到原来的话")
	# 对话里的字都在字体子集里（出身这一步加了不少新台词）
	var font: FontFile = load("res://assets/fonts/NotoSansSC-IC.ttf")
	var lack := ""
	for darea in dialogue_areas():
		var txt := FileAccess.get_file_as_string("res://data/dialogue/%s.json" % darea)
		for i in txt.length():
			var c := txt.unicode_at(i)
			if c > 127 and not font.has_char(c) and not lack.contains(txt[i]):
				lack += txt[i]
	check(lack == "", "所有对话文件里的字都在字体子集里（缺：%s）" % lack)


## O.3 支线「名册上的名字」（只对出身烽誓团逃兵）：第一夜过后马蒂亚斯翻开名册——认下来补守（烽誓团 +10、劫粮多两个人）/ 说动他抹掉 / 否认；回顾里有一句
func _o3(origin: String, seed: int) -> DialogueRunner:
	GameState.new_game(seed)
	GameState.chapter = 2
	if origin != "":
		GameState.set_flag("origin", origin)
	GameState.set_flag("matthias_met")
	GameState.set_flag("ch2_first_tide", "held")
	GameState.set_stage("ch2_main", "after_tide")
	return DialogueRunner.new()


func test_origin3() -> void:
	var ask := "那本名册……上面有我的名字吧？"
	var r := _o3("deserter", 1200)
	r.start("beacon19", "matthias")
	check(has_opt(r, ask), "烽誓团逃兵、第一夜过后：马蒂亚斯那里多一条「那本名册」")
	for o in ["knight", "ferry", ""]:
		var r2 := _o3(o, 1201)
		r2.start("beacon19", "matthias")
		check(not has_opt(r2, ask), "%s：没有名册这条" % (Origins.name_of(o) if o != "" else "没出身"))
	var r3 := _o3("deserter", 1202)
	GameState.set_flag("ch2_first_tide", false)
	GameState.set_stage("ch2_main", "first_night")
	r3.start("beacon19", "matthias")
	check(not has_opt(r3, ask), "第一夜以前还没有")
	# 认下来补守
	var oath := GameState.get_rep("beacon_oath")
	r = _o3("deserter", 1203)
	oath = GameState.get_rep("beacon_oath")
	r.start("beacon19", "matthias")
	pick(r, ask)
	check(r.text().contains("逃") and GameState.quest_active("ch2_roll"), "他翻开名册：第二十一烽，三年，名字后面一个「逃」（支线开始）")
	pick(r, "我认。剩下的年头，从这个冬天补起。")
	check(str(GameState.get_flag("ch2_roll", "")) == "served" and GameState.get_rep("beacon_oath") == oath + 10 and GameState.quest_done("ch2_roll"), "认下来补守：「逃」旁边写个「补」，烽誓团 +10，支线完成")
	r.start("beacon19", "matthias")
	check(not has_opt(r, ask), "办完了不再出现")
	check(Chapter2.recap().contains("补"), "回顾：认下了一个「补」字")
	GameState.set_flag("beacon_grain", "rob")
	GameState.set_flag("ch2_ambush", "head")
	GameState.set_stage("ch2_main", "rob_ready")
	GameState.daypart = "night"
	var main := await make_area("highland")
	await frames(3)
	check(main.battle != null and main.battle.squad.size() == 12 and main.battle.squad.filter(func(x): return x.display_override == "烽誓团 · 老守燧人").size() == 2,
		"劫粮那一夜：马蒂亚斯多给两个人（小队 12 人，两个老守燧人）")
	await free_main(main)
	# 说动他抹掉
	r = _o3("deserter", 1204)
	r.start("beacon19", "matthias")
	pick(r, ask)
	GameState.checks["roll_strike"] = true
	pick(r, "划掉吧。那个逃兵死在第四年冬天了——站在你面前的，是瓦伦家的誓剑。")
	check(str(GameState.get_flag("ch2_roll", "")) == "struck" and Chapter2.recap().contains("抹成了一团黑"), "说动了：名字抹成一团黑")
	# 没说动 → 只剩认或者否认；否认
	r = _o3("deserter", 1205)
	oath = GameState.get_rep("beacon_oath")
	r.start("beacon19", "matthias")
	pick(r, ask)
	GameState.checks["roll_strike"] = false
	pick(r, "划掉吧。那个逃兵死在第四年冬天了——站在你面前的，是瓦伦家的誓剑。")
	check(r.text().contains("划不掉") and not has_opt(r, "划掉吧。那个逃兵死在第四年冬天了——站在你面前的，是瓦伦家的誓剑。"), "没说动：「名册上的字，我划不掉」，只剩认或者否认")
	pick(r, "认错人了。")
	check(str(GameState.get_flag("ch2_roll", "")) == "denied" and GameState.get_rep("beacon_oath") == oath - 5 and GameState.quest_done("ch2_roll"), "否认：烽誓团 −5，支线完成")


## 5.3a 盘山路：深雪、倒树、废羊棚、雪杆、雪地上的脚印
func test_mountainroad() -> void:
	Highland.ensure_field()
	HighlandFlora.clear_cache()
	HighlandRoad.clear_cache()
	# 深雪：路面、村里、烽燧脚下、岩坎上不深；路边一条雪檐；整张图上不少地方深
	var on_road := 0
	var bank_ok := 0
	var legs := HighlandLayout.ROAD.size() - 1
	for i in legs:
		for k in 9:
			var a: Vector2 = HighlandLayout.ROAD[i]
			var b: Vector2 = HighlandLayout.ROAD[i + 1]
			var c := a.lerp(b, (k + 0.5) / 9.0)
			if HighlandLayout.deep(c.x, c.y) > 0.01:
				on_road += 1
	var bank := Vector2.INF
	for i in range(2, legs):
		if i == HighlandLayout.AMBUSH_LEG:
			continue
		var a: Vector2 = HighlandLayout.ROAD[i]
		var b: Vector2 = HighlandLayout.ROAD[i + 1]
		var dir := (b - a).normalized()
		var out_n := Vector2(-dir.y, dir.x) * -HighlandLayout._uphill_side(i)
		var q := a.lerp(b, 0.5) + out_n * (HighlandLayout.ROAD_HALF + 3.0)
		if HighlandLayout.deep(q.x, q.y) > 0.5 and HighlandLayout.road_hit(q).d > HighlandLayout.ROAD_HALF + 2.0:
			bank_ok += 1
			if bank == Vector2.INF:
				bank = q
	var deep_n := 0
	var all_n := 0
	for z in range(-125, 126, 5):
		for x in range(-155, 156, 5):
			all_n += 1
			if HighlandLayout.deep(x, z) > 0.5:
				deep_n += 1
	var v := HighlandLayout.VILLAGE
	check(on_road == 0 and HighlandLayout.deep(v.x, v.y) == 0.0 and HighlandLayout.deep(HighlandLayout.BEACON19.x, HighlandLayout.BEACON19.y) == 0.0,
		"踩出来的路面、村里、烽燧脚下不是深雪")
	check(bank_ok >= 3 and float(deep_n) / all_n > 0.2 and float(deep_n) / all_n < 0.55,
		"路边一条雪檐（%d 段路查到）、整张图约 %.0f%% 是深雪" % [bank_ok, 100.0 * deep_n / all_n])
	check(Surface.mult("deep_snow") < 0.7 and not Surface.can_run("deep_snow") and Surface.label("deep_snow").begins_with("深雪") and Surface.label("snow") == "",
		"深雪：走得慢、不能跑、HUD 写一行；普通的雪照常")
	# 倒树、废羊棚、雪杆：不压路、不长树
	var fallen := HighlandLayout.fallen()
	var min_d := INF
	for f in fallen:
		for k in 11:
			min_d = minf(min_d, HighlandLayout.road_hit((f.root as Vector2).lerp(f.tip, k / 10.0)).d)
	check(fallen.size() == 4 and min_d > HighlandLayout.ROAD_HALF + 0.5, "4 棵倒树都躺在路边、不压路面（最近离路中线 %.1f 米）" % min_d)
	var sc: Vector2 = HighlandLayout.SHED[0]
	var trees_in := HighlandFlora.trees().filter(func(t): return HighlandRoad.blocks(Vector2(t[0].x, t[0].z), 0.5)).size() + HighlandFlora.rocks().filter(func(r): return HighlandRoad.blocks(Vector2(r[0].x, r[0].z), 0.3)).size()
	check(HighlandFlora.slope_at(sc) < 0.05 and trees_in == 0 and HighlandLayout.road_hit(sc).d > HighlandLayout.ROAD_HALF + 8.0,
		"废羊棚在压平的一块地上、离路不远不近；树和石头不长在羊棚、倒树上")
	var poles := HighlandRoad.poles()
	check(poles.size() >= 8 and poles.all(func(pl): return HighlandLayout.road_hit(Vector2(pl[0].x, pl[0].z)).d > HighlandLayout.ROAD_HALF + 0.3),
		"路边 %d 根雪杆，都在路面外" % poles.size())
	check(HighlandLayout.VIEW_SPEC.size() == HighlandLayout.VIEW_NAMES.size() and HighlandLayout.SPAWN_XZ.has("shed"), "机位和名字对得上；有废羊棚的出生点")
	# 游戏里：搭出来、挡人、踩进深雪变慢、雪上留脚印
	GameState.new_game(530)
	GameState.chapter = 2
	GameState.daypart = "day"
	var main := await make_area("highland")
	var st: ChunkStreamer = main.streamer
	st.build_all()
	var w: Node3D = main.world
	var trees_n: int = w.find_children("FallenTrees*", "MultiMeshInstance3D", true, false).reduce(func(acc, m): return acc + (m as MultiMeshInstance3D).multimesh.instance_count, 0)
	check(trees_n == 4 and w.find_children("Shed", "MeshInstance3D", true, false).size() == 1 and w.find_children("SnowPoles", "MultiMeshInstance3D", true, false).size() >= 2,
		"倒树 %d 棵、废羊棚、雪杆都搭出来了" % trees_n)
	check(float(st.stats.max_job_ms) < 40.0, "加上盘山路的东西每件活还是不长（最慢 %.1f 毫秒）" % st.stats.max_job_ms)
	var space := main.get_world_3d().direct_space_state
	var sp := HighlandRoad.shed_place()
	var q := PhysicsRayQueryParameters3D.create(sp * Vector3(-0.8, 1.0, -4.0), sp * Vector3(-0.8, 1.0, 0.0), 1)
	var f0: Dictionary = HighlandRoad.fallen_specs()[0]
	var mid: Vector3 = (f0.root as Vector3) + (f0.axis as Vector3) * float(f0.len) * 0.3
	var q2 := PhysicsRayQueryParameters3D.create(mid + (f0.side as Vector3) * 2.0 + Vector3(0, 0.2, 0), mid - (f0.side as Vector3) * 2.0 + Vector3(0, 0.2, 0), 1)
	check(not space.intersect_ray(q).is_empty() and not space.intersect_ray(q2).is_empty(), "羊棚的后墙、倒树的树干挡人")
	var p: FpController = main.player
	p.global_position = Vector3(bank.x, Highland.height_at(bank.x, bank.y) + 0.1, bank.y)
	await physics(10)
	var deep_surface := p.surface
	var slow := p.current_speed(Vector2(0, -1))
	var r3: Vector2 = HighlandLayout.ROAD[3]
	var r4: Vector2 = HighlandLayout.ROAD[4]
	var rc := r3.lerp(r4, 0.5)
	p.global_position = Vector3(rc.x, Highland.height_at(rc.x, rc.y) + 0.1, rc.y)
	await physics(10)
	check(deep_surface == "deep_snow" and p.surface == "snow" and slow < p.current_speed(Vector2(0, -1)) and main.hud.surface_label.visible == false,
		"踩进路边的雪檐：脚下是深雪、变慢（%.1f → %.1f）；回到路面：照常" % [p.current_speed(Vector2(0, -1)), slow])
	var tracks := main.get_node_or_null("SnowTracks") as SnowTracks
	var dir := (r4 - r3).normalized()
	for k in 6:
		var at := rc + dir * (k + 1) * 0.9
		p.global_position = Vector3(at.x, Highland.height_at(at.x, at.y) + 0.05, at.y)
		await physics(3)
	check(tracks != null and tracks.multimesh.visible_instance_count >= 4, "在雪地上走：身后留下脚印（%d 个）" % (tracks.multimesh.visible_instance_count if tracks else 0))
	var spec := Highland.map_spec()
	check(spec.shapes.any(func(sh): return str(sh.get("label", "")) == "废羊棚"), "本地地图上标了废羊棚")
	await free_main(main)
	HighlandRoad.clear_cache()
	HighlandFlora.clear_cache()


## 5.3b 第十九烽：塔、塔顶的火盆、木栅营地、塔里面
func test_beacon19() -> void:
	Highland.ensure_field()
	HighlandFlora.clear_cache()
	HighlandBeacon.clear_cache()
	# 布局：塔、营房、两个棚都在木栅里、在压平的那片上；门对着盘山路进来的那边；营地里不长树和石头
	var c := HighlandLayout.BEACON19
	var inside := true
	for sp in [[HighlandLayout.TOWER[0], HighlandLayout.TOWER[1], HighlandLayout.TOWER_W, HighlandLayout.TOWER_W], HighlandLayout.BARRACKS, HighlandLayout.WOODSHED, HighlandLayout.GRANARY]:
		var at: Vector2 = sp[0]
		var b := Basis(Vector3.UP, deg_to_rad(float(sp[1])))
		for corner in [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(1, 0, 1), Vector3(-1, 0, 1)]:
			var off: Vector3 = b * (corner * Vector3(float(sp[2]), 0, float(sp[3])) * 0.5)
			var q := at + Vector2(off.x, off.z)
			if q.distance_to(c) > HighlandLayout.PALISADE_R - 0.4 or absf(Highland.height_at(q.x, q.y) - HighlandLayout.tower_base_y()) > 0.3:
				inside = false
	check(inside, "塔、营房、柴棚、粮棚都在木栅里、在烽燧脚下压平的那片上")
	var road_end: Vector2 = HighlandLayout.ROAD[HighlandLayout.ROAD.size() - 1]
	var gate := c + HighlandBeacon.gate_dir() * HighlandLayout.PALISADE_R
	check(road_end.distance_to(c) < HighlandLayout.PALISADE_R and HighlandLayout.road_hit(gate).d < HighlandLayout.ROAD_HALF + 0.5 and HighlandBeacon.posts().size() > 150,
		"木栅门开在盘山路进来的地方（门离路中线 %.1f 米）、一圈 %d 根木桩" % [HighlandLayout.road_hit(gate).d, HighlandBeacon.posts().size()])
	var in_camp := HighlandFlora.trees().filter(func(t): return Vector2(t[0].x, t[0].z).distance_to(c) < HighlandLayout.PALISADE_R + 1.0).size() + HighlandFlora.rocks().filter(func(r): return Vector2(r[0].x, r[0].z).distance_to(c) < HighlandLayout.PALISADE_R + 1.0).size()
	check(in_camp == 0, "营地里不长树、不摆石头")
	var top: Array = HighlandLayout.spawn_points().beacon_top
	check(absf((top[0] as Vector3).y - (HighlandLayout.tower_base_y() + HighlandLayout.TOWER_H)) < 0.2 and Vector2(top[0].x, top[0].z).distance_to(HighlandLayout.TOWER[0]) < HighlandLayout.TOWER_W * 0.5 - 0.5,
		"塔顶的出生点在塔顶的石板上")
	# 游戏里：搭出来、塔顶的火是暖的、木栅挡人、门通往塔里
	GameState.new_game(531)
	GameState.chapter = 2
	GameState.daypart = "dusk"
	var main := await make_area("highland")
	var st: ChunkStreamer = main.streamer
	st.build_all()
	var w: Node3D = main.world
	var pal: Array = w.find_children("Palisade", "MultiMeshInstance3D", true, false)
	var posts_n: int = pal.reduce(func(acc, m): return acc + (m as MultiMeshInstance3D).multimesh.instance_count, 0)
	check(w.find_children("BeaconTower", "MeshInstance3D", true, false).size() == 1 and w.find_children("BeaconBrazier", "MeshInstance3D", true, false).size() == 1
		and w.find_children("Flame*", "MeshInstance3D", true, false).size() == 4 and posts_n == HighlandBeacon.posts().size()
		and w.find_children("PalisadeGate", "MeshInstance3D", true, false).size() == 1 and w.find_children("Croft_barracks", "Node3D", true, false).size() == 1
		and w.find_children("Woodshed", "MeshInstance3D", true, false).size() == 1 and w.find_children("Granary", "MeshInstance3D", true, false).size() == 1,
		"塔、火盆和火苗、%d 根木桩、木栅门、营房、柴棚、粮棚都搭出来了" % posts_n)
	check(float(st.stats.max_job_ms) < 40.0, "加上第十九烽每件活还是不长（最慢 %.1f 毫秒）" % st.stats.max_job_ms)
	var fires: Array = w.find_children("BeaconFire", "OmniLight3D", true, false)
	var brightest := 0.0
	for l in w.find_children("*", "OmniLight3D", true, false):
		if not fires.has(l):
			brightest = maxf(brightest, (l as OmniLight3D).light_energy * (l as OmniLight3D).omni_range)
	var bf: OmniLight3D = fires[0] if not fires.is_empty() else null
	check(bf != null and bf.is_in_group("light_source") and bf.light_energy * bf.omni_range > brightest, "塔顶的火是全图最亮的光（ART.md 第十节），也算火边")
	var td := w.get_node_or_null("TowerDoor") as Door
	var hatch := w.get_node_or_null("TowerHatch") as Door
	var bd := w.get_node_or_null("BarracksDoor") as Door
	check(td != null and td.to_area == "beacon_tower" and td.to_spawn == "front" and hatch != null and hatch.to_area == "beacon_tower" and hatch.to_spawn == "top"
		and bd != null and bd.locked, "塔门通往塔里，塔顶的天窗下到诺伯特的小屋，营房的门从里面顶着")
	var space := main.get_world_3d().direct_space_state
	var y0 := HighlandLayout.tower_base_y() + 1.2
	var side := Vector2(HighlandBeacon.gate_dir().y, -HighlandBeacon.gate_dir().x)
	var wall_pt := c + side * HighlandLayout.PALISADE_R
	var q1 := PhysicsRayQueryParameters3D.create(Vector3(c.x, y0, c.y) + Vector3(side.x, 0, side.y) * (HighlandLayout.PALISADE_R - 2.0), Vector3(wall_pt.x, y0, wall_pt.y) + Vector3(side.x, 0, side.y) * 2.0, 1)
	var gd := HighlandBeacon.gate_dir()
	var q2 := PhysicsRayQueryParameters3D.create(Vector3(c.x, y0, c.y) + Vector3(gd.x, 0, gd.y) * (HighlandLayout.PALISADE_R - 2.0), Vector3(c.x, y0, c.y) + Vector3(gd.x, 0, gd.y) * (HighlandLayout.PALISADE_R + 2.0), 1)
	check(not space.intersect_ray(q1).is_empty() and space.intersect_ray(q2).is_empty(), "木栅挡人，门那儿走得过去")
	var p: FpController = main.player
	p.global_position = top[0]
	await physics(30)
	check(p.is_on_floor() and absf(p.global_position.y - (top[0] as Vector3).y) < 0.3 and Cold.near_fire(get_tree(), p.global_position),
		"站在塔顶：脚下是塔顶的石板（不掉下去），在火边（暖和）")
	check(Areas.is_indoor("beacon_tower") and Areas.chapter_of("beacon_tower") == 2 and Highland.map_spec().exits.any(func(e): return e.to == "beacon_tower"),
		"塔里算室内、是第二章的地方；本地地图上有塔门")
	await free_main(main)
	# 塔里：门、木梯、出生点；顺着石梯走得上楼
	GameState.new_game(532)
	GameState.chapter = 2
	var inn := await make_area("beacon_tower")
	var exit: Array = inn.world.find_children("*", "Door", true, false)
	var to_out := exit.filter(func(d): return d.to_area == "highland" and d.to_spawn == "beacon_door").size()
	var to_top := exit.filter(func(d): return d.to_area == "highland" and d.to_spawn == "beacon_top").size()
	check(to_out == 1 and to_top == 1 and BeaconTower.SPAWNS.has("top") and BeaconTower.VIEWS.size() == BeaconTower.VIEW_NAMES.size(),
		"塔里：门回到营地、东南角的木梯爬上塔顶；机位和名字对得上")
	var steps := BeaconTower.steps()
	var ok_rise := true
	var prev := 0.0
	for stp in steps:
		var top_y: float = (stp[0] as Vector3).y
		if top_y - prev > FpController.STEP_HEIGHT:
			ok_rise = false
		prev = top_y
	check(ok_rise and BeaconTower.UPPER - prev <= FpController.STEP_HEIGHT, "每一级石阶都不高过能跨上去的高度（%.2f 米）" % BeaconTower.RISE)
	var ip: FpController = inn.player
	var h := BeaconTower.IN * 0.5
	ip.global_position = Vector3(-h + BeaconTower.STAIR_W * 0.5, 0.55, 1.4)
	ip.rotation.y = 0.0
	await physics(10)
	await hold("move_forward", 2.6)
	var landing_y := ip.global_position.y
	ip.rotation.y = -PI * 0.5
	await hold("move_forward", 1.6)
	check(landing_y > 2.7 and ip.global_position.y > BeaconTower.UPPER - 0.2,
		"顺着石梯往北爬到拐角（%.1f 米），往东再走几步上到诺伯特的小屋（%.1f 米）" % [landing_y, ip.global_position.y])
	await free_main(inn)
	HighlandBeacon.clear_cache()
	HighlandFlora.clear_cache()


## 5.3c 第十九烽的人：黄昏到烽燧、马蒂亚斯、诺伯特、营里的兵、堤道失守那条线的一捆柴
func test_beaconpeople() -> void:
	var d := DialogueRunner.load_file("beacon19")
	var errs := []
	for id in d:
		if not str(id).begins_with("_"):
			errs.append_array(DialogueRunner.validate(d[id]))
	check(errs.is_empty() and d.has("matthias") and d.has("norbert"), "第十九烽的对话都走得通、旗标都登记了（%s）" % str(errs.slice(0, 3)))
	# 白天顺着盘山路走到烽燧：天擦黑了，主线推进到「找马蒂亚斯」
	GameState.new_game(533)
	GameState.chapter = 2
	GameState.daypart = "day"
	GameState.start_quest("ch2_main")
	GameState.set_stage("ch2_main", "to_beacon19")
	var main := await make_area("highland")
	var p: FpController = main.player
	var sp: Array = HighlandLayout.spawn_points().beacon
	p.global_position = sp[0]
	await physics(10)
	await seconds(1.5)                                       # 换时段先淡出、换光、再淡入
	check(GameState.quest_stage("ch2_main") == "meet_matthias" and GameState.daypart == "dusk" and main.daypart == "dusk",
		"走到烽燧门前：天擦黑了（黄昏），主线推进到「找马蒂亚斯」（%s / %s / %s）" % [GameState.quest_stage("ch2_main"), GameState.daypart, main.daypart])
	var w: Node3D = main.world
	var ids := ["matthias", "norbert", "gate", "chopper", "sacks", "door"]
	var names := []
	for id in ids:
		var n := w.get_node_or_null("Npc_" + id) as Npc
		if n != null and Looks.has(n.display_name, n.name):
			names.append(n.display_name)
	check(names.size() == ids.size(), "营里的人都在、都有真人外观（%s）" % "、".join(names))
	var nb := w.get_node("Npc_norbert") as Node3D
	var mt := w.get_node("Npc_matthias") as Npc
	check(absf(nb.global_position.y - (HighlandLayout.tower_base_y() + HighlandLayout.TOWER_H)) < 0.1 and Vector2(nb.global_position.x, nb.global_position.z).distance_to(HighlandLayout.TOWER[0]) < 2.0
		and mt.dialogue_area == "beacon19" and mt.dialogue_id == "matthias", "诺伯特站在塔顶火盆边；马蒂亚斯在柴棚前，有对话")
	var space := main.get_world_3d().direct_space_state
	var floating := []
	for id in ["matthias", "gate", "chopper", "sacks", "door"]:
		var n := w.get_node("Npc_" + id) as Node3D
		var q := PhysicsRayQueryParameters3D.create(n.global_position + Vector3(0, 1.0, 0), n.global_position + Vector3(0, -1.0, 0), 1)
		var hit := space.intersect_ray(q)
		if hit.is_empty() or absf(float(hit.position.y) - n.global_position.y) > 0.25:
			floating.append(id)
	check(floating.is_empty(), "营里的人都站在地上（%s）" % str(floating))
	check(w.find_children("*", "Pickup", true, false).filter(func(x): return x.item_id == "firewood").is_empty(), "堤道守住了：柴棚里没有要扛的那捆柴")
	# 马蒂亚斯 → 诺伯特 → 「先过了今夜」
	var r := DialogueRunner.new()
	r.start("beacon19", "matthias")
	var greet := r.text()
	pick(r, "只够三夜？")
	pick(r, "那怎么办？")
	check(greet.contains("三夜") and GameState.has_flag("heard_three_nights") and GameState.has_flag("heard_convoy") and r.text().contains("什么都没说"),
		"马蒂亚斯：粮和柴只够三夜；压低声音提了一句明天的粮车，「我什么都没说」")
	pick(r, "……我听见了。")
	pick(r, "我找诺伯特烽长。")
	check(GameState.quest_stage("ch2_main") == "see_norbert", "马蒂亚斯指路：诺伯特在塔顶看火（主线推进到「上塔顶找诺伯特」）")
	r.start("beacon19", "norbert")
	pick(r, "奥斯瑞克·瓦伦临终让我来找你。")
	pick(r, "加冕礼上发生了什么？")
	check(r.text().contains("先过了今夜") and GameState.quest_stage("ch2_main") == "first_night" and GameState.has_flag("norbert_met"),
		"诺伯特不肯谈加冕礼：「先过了今夜。」（主线推进到「第一夜」）")
	await free_main(main)
	# 堤道失守：诺伯特先要一捆柴；柴棚里有那捆柴，扛上去才肯说话
	GameState.new_game(534)
	GameState.chapter = 2
	GameState.daypart = "dusk"
	GameState.set_flag("ch1_causeway", "lost")
	GameState.set_flag("valen_heir", "alric")
	GameState.start_quest("ch2_main")
	GameState.set_stage("ch2_main", "see_norbert")
	main = await make_area("highland")
	var fw: Array = main.world.find_children("*", "Pickup", true, false).filter(func(x): return x.item_id == "firewood")
	check(fw.size() == 1, "堤道失守：柴棚里放着一捆要扛的柴")
	r.start("beacon19", "matthias")
	check(r.text().contains("瓦伦家") or r.text().contains("黑鹭堡丢了"), "选了阿尔里克：马蒂亚斯冷淡（%s）" % r.text().left(24))
	r.start("beacon19", "norbert")
	check(r.text().contains("先从柴棚扛一捆") and not has_opt(r, "奥斯瑞克·瓦伦临终让我来找你。") and not has_opt(r, "（把那捆柴放到火盆边）"), "诺伯特先要一捆柴：没扛来之前不说话")
	pick(r, "我这就去柴棚扛。")
	check(GameState.quest_stage("ch2_main") == "carry_wood", "主线推进到「扛一捆柴上塔顶」")
	var res: Dictionary = (fw[0] as Pickup).interact(main.player)
	GameState.add_item(str(res.item))                       # 捡起来进背包（main 处理交互结果时做的事）
	await frames(2)
	r.start("beacon19", "norbert")
	pick(r, "（把那捆柴放到火盆边）")
	check(GameState.has_flag("ch2_wood_carried") and not GameState.has_item("firewood") and has_opt(r, "奥斯瑞克·瓦伦临终让我来找你。"), "扛来了：柴放到火盆边，他肯说话了（%s）" % str(res.get("kind", "")))
	pick(r, "奥斯瑞克·瓦伦临终让我来找你。")
	check(r.text().contains("堡丢了"), "堤道失守：他问奥斯瑞克是在堡里走的，还是堡丢了以后")
	pick(r, "加冕礼上发生了什么？")
	check(GameState.quest_stage("ch2_main") == "first_night", "照样「先过了今夜」")
	await free_main(main)


## 5.4a 长眠者群：跟着路线走、互相让开、人越多越快、绕开火、推倒踩过挡路的人、走完就没了
func test_sleepercrowd() -> void:
	var route := [Vector2(0, 0), Vector2(0, -40), Vector2(10, -70)]
	var c := SleeperCrowd.make(route, 24, 5.0)
	c.near_enabled = false
	get_tree().root.add_child(c)
	await physics(2)
	var z0 := 0.0
	for a in c.agents:
		z0 += a.p.y
	await seconds(4.0)
	var z1 := 0.0
	var min_d := INF
	for a in c.agents:
		z1 += a.p.y
	for i in c.agents.size():
		for j in range(i + 1, c.agents.size()):
			min_d = minf(min_d, (c.agents[i].p as Vector2).distance_to(c.agents[j].p))
	var moved := (z0 - z1) / c.agents.size()
	check(moved > 2.0 and moved < 6.0 and min_d > 0.45, "跟着路线往前走（4 秒平均走了 %.1f 米）、互相让开（最近的两个人隔 %.2f 米）" % [moved, min_d])
	var small := SleeperCrowd.make(route, 8)
	var big := SleeperCrowd.make(route, 60)
	small.agents = range(8).map(func(_i): return {"done": false})
	big.agents = range(60).map(func(_i): return {"done": false})
	check(big.current_speed() > small.current_speed() * 1.25 and big.current_speed() <= small.speed_base * 1.46, "人越多走得越快（8 人 %.2f、60 人 %.2f 米每秒）" % [small.current_speed(), big.current_speed()])
	small.free()
	big.free()
	c.queue_free()
	# 火：路线正中间一团火（半径 2 米，算火边 4 米），它们顺着火边绕过去、照样往前走
	var fire := Node3D.new()
	fire.add_to_group("crowd_fire")
	fire.set_meta("radius", 2.0)
	get_tree().root.add_child(fire)
	fire.global_position = Vector3(0, 0, -8)
	var c2 := SleeperCrowd.make([Vector2(0, 0), Vector2(0, -20)], 20, 3.0)
	c2.near_enabled = false
	get_tree().root.add_child(c2)
	var closest := INF
	var past := 0
	for k in 240:
		await physics(15)
		for a in c2.agents:
			if not a.done:
				closest = minf(closest, (a.p as Vector2).distance_to(Vector2(0, -8)))
		past = c2.agents.filter(func(a): return a.done or a.p.y < -12.0).size()
		if past >= 20:
			break
	check(closest > 2.5 and past >= 18, "绕开火：没人走进火边 2.5 米以内（最近 %.1f 米），绕过去的 %d / 20" % [closest, past])
	for k in 80:
		if c2.alive() == 0:
			break
		await physics(15)
	check(c2.alive() == 0, "走到路线尽头就没了（还剩 %d）" % c2.alive())
	fire.queue_free()
	# 5.4b：一排插得密的火把（2.2 米一支，横在路上）是一堵墙：没人从两支中间钻过去，都绕到两头
	var row := []
	for k in 5:
		var t := Node3D.new()
		t.add_to_group("crowd_fire")
		t.set_meta("radius", 1.8)
		get_tree().root.add_child(t)
		t.global_position = Vector3((k - 2) * 2.2, 0, -10)
		row.append(t)
	var cw := SleeperCrowd.make([Vector2(0, 0), Vector2(0, -30)], 16, 3.0)
	cw.near_enabled = false
	get_tree().root.add_child(cw)
	var crossed := []
	var last := {}
	for k in 240:
		await physics(15)
		for i in cw.agents.size():
			var a: Dictionary = cw.agents[i]
			var py: float = last.get(i, 0.0)
			if not a.done and py >= -10.0 and a.p.y < -10.0:
				crossed.append(absf(a.p.x))
			last[i] = a.p.y
		if crossed.size() >= 16:
			break
	var through := crossed.filter(func(x): return x < 4.4).size()
	check(crossed.size() >= 14 and through == 0, "一排火把（5 支、2.2 米一支）：%d 个人走过去，从中间钻过去的 %d 个（都绕到两头，最近的离中线 %.1f 米）" % [crossed.size(), through, crossed.min() if crossed.size() > 0 else 0.0])
	cw.queue_free()
	for t in row:
		t.queue_free()
	c2.queue_free()
	# 挡在前面的主角：推倒、踩过（掉血、变冷）；它们杀不死、照样往前走
	GameState.new_game(541)
	GameState.chapter = 2
	GameState.daypart = "night"
	var main := await make_area("highland")
	var p: FpController = main.player
	var y := Highland.height_at(-6.0, -28.0)
	p.global_position = Vector3(-6.0, y + 0.1, -28.0)
	await physics(10)
	var hp: int = p.melee.health
	var cold0 := GameState.cold
	var c3 := SleeperCrowd.make([Vector2(-14.0, -12.0), Vector2(-6.0, -28.0), Vector2(5.0, -54.0)], 30, 3.0)
	c3.height_fn = Highland.height_at
	c3.player = p
	c3.spawn_gap = 0.4
	main.world.add_child(c3)
	var was_down := false
	for k in 200:
		await physics(10)
		was_down = was_down or p.knocked()
		if c3.tramples() >= 2:
			break
	check(was_down and c3.tramples() >= 1 and p.melee.health < hp and GameState.cold > cold0, "挡在路上：被推倒、踩过（踩了 %d 下，生命 %d → %d，寒冷 %.0f → %.0f）" % [c3.tramples(), hp, p.melee.health, cold0, GameState.cold])
	var near := c3.get_children().filter(func(n): return n is CharacterModel and n.visible).size()
	check(c3.models.size() <= SleeperCrowd.NEAR_MAX and near <= SleeperCrowd.NEAR_MAX and c3.mm.multimesh.instance_count == 30,
		"近处 %d 个画真人模型（最多 %d 个），其余一个多实例画完" % [near, SleeperCrowd.NEAR_MAX])
	var t0 := Time.get_ticks_usec()
	for k in 20:
		c3._step(SleeperCrowd.TICK)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0 / 20.0
	check(ms < 3.0, "30 个人一步的逻辑 %.2f 毫秒（每 0.05 秒一步）" % ms)
	await free_main(main)


## 测试用：选对话里文字是 label 的那个选项（没有就什么都不做，后面的检查会失败）
func pick(r: DialogueRunner, label: String) -> void:
	var opts := r.options()
	for k in opts.size():
		if str(opts[k].text) == label:
			r.choose(k)
			return


func has_opt(r: DialogueRunner, label: String) -> bool:
	return r.options().any(func(o): return str(o.text) == label)
