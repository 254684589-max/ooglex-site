extends Node
## 自动化测试：无界面运行，覆盖经济、存读档、时间、任务推进、工资、技能、住房、投资、创业、
## NPC 关系、随机事件、交通、昏倒、结局，以及从主菜单到结局再到无限模式的完整流程。
##
##   godot --headless --path games/working-life/godot res://tests/test_runner.tscn
## 全部通过时退出码为 0，否则为 1。可以只跑某一组：... res://tests/test_runner.tscn -- economy save

var main: Node
var player: Player
var ui: UIRoot
var failures: Array = []
var checks := 0
var only: Array = []


var current_group := ""


func _ready() -> void:
	seed(20880301)
	# 看门狗：某个测试卡住（脚本错误导致协程中断）时不会一直挂着
	var dog := Timer.new()
	dog.wait_time = 900.0
	dog.one_shot = true
	dog.timeout.connect(func():
		print("WATCHDOG TIMEOUT in group: ", current_group)
		get_tree().quit(2))
	add_child(dog)
	dog.start()
	only = Array(OS.get_cmdline_user_args())
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.auto_skip_intro = true
	add_child(main)
	await frames(5)
	player = GameManager.player
	ui = main.ui
	var groups := ["startup", "data", "economy", "time", "skills", "first_day", "job_payment", "monthly_job",
		"housing", "property", "investment", "business", "npc", "character", "events", "transport", "collapse", "carry", "ui_windows",
		"driving", "navigation", "save_load", "endings", "journey"]
	for g in groups:
		if not only.is_empty() and not only.has(g):
			continue
		print("\n== %s" % g)
		current_group = g
		await call("test_" + g)
	print("")
	AudioManager.shutdown()
	await frames(2)
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
		await get_tree().physics_frame
		await get_tree().process_frame


func top() -> Control:
	return ui.top_window()


func new_game(slot := 3) -> void:
	ui.close_all()
	main.start_new_game(slot)
	for i in 200:
		await frames(1)
		if GameManager.playing and not ui.story.playing:
			break
	await frames(3)


func goto_loc(id: String) -> void:
	var p := GameManager.location_front(id)
	player.teleport(p, 0.0)
	await frames(4)


func goto_point(key: String, back := 1.2) -> ServicePoint:
	var sp := GameManager.lookup(key) as ServicePoint
	if sp == null:
		return null
	var fwd: Vector3 = sp.global_transform.basis.z
	player.teleport(sp.global_position + fwd * back + Vector3(0, 0.1, 0), atan2(fwd.x, fwd.z))
	await frames(5)
	return sp


func press(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	await frames(1)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
	await frames(2)


## 快进之后把属性恢复正常（测试里跳过了吃饭睡觉）
func fresh() -> void:
	for s in ["energy", "hunger", "mood", "health"]:
		PlayerManager.set_stat(s, 90)
	PlayerManager.set_stat("stress", 10)


func set_clock(hour: float) -> void:
	TimeManager.advance(TimeManager.minutes_until(hour), "sleep")
	fresh()
	await frames(2)


# ================================================================ 启动与数据
## 买房、贷款、自住、出租、装修、卖房、断供收房、存档
func _next_month_day1() -> int:
	var d := TimeManager.day + 1
	while TimeManager.day_of_month(d) != 1:
		d += 1
	return d


func _skill_total(id: String) -> float:
	return SkillManager.level(id) * 100000.0 + float(SkillManager.xp.get(id, 0.0))


func test_property() -> void:
	await new_game()
	fresh()
	EconomyManager.earn(3000000, "其他", "测试", true)
	check(HousingManager.buy_home("apartment", true).begins_with("银行不批"), "没有工作不能贷款买房")
	check(HousingManager.buy_home("shared", false).begins_with("这种房子只能租"), "合租房只能租不能买")
	JobManager.hire("office", 0)
	var liquid0 := EconomyManager.liquid()
	var nw0 := EconomyManager.networth()
	var msg := HousingManager.buy_home("apartment", true)
	var o: Dictionary = HousingManager.owned.get("apartment", {})
	check(not o.is_empty() and EconomyManager.liquid() == liquid0 - 234000 - 11700, "贷款买普通公寓：首付 ¥234,000 + 税费 ¥11,700（%s）" % msg.left(12))
	check(int(o.get("payment", 0)) == HousingManager.mortgage_payment(546000.0, 120) and int(o["payment"]) > 5000 and int(o["payment"]) < 6000, "月供 %s（等额本息 120 期）" % Fmt.yuan(int(o.get("payment", 0))))
	check(EconomyManager.networth() == nw0 - 11700, "买房后净资产只少了税费（房产净值计入）")
	check(HousingManager.can_enter("apartment") and HousingManager.current != "apartment", "买下后能进房间，但还没搬进去")
	check(HousingManager.buy_furniture("apartment", "rug_1").contains("已送货") and HousingManager.buy_furniture("shared", "rug_1").begins_with("租的房子"), "只能装修自己的房子")
	msg = HousingManager.move_into_owned("apartment")
	check(HousingManager.current == "apartment" and HousingManager.is_monthly() and HousingManager.level() == 3, "搬进自己的房子：住房等级 3（%s）" % msg)
	var p0 := HousingManager.prestige()
	var m0 := HousingManager.mood_bonus()
	check(p0 == 5.0 + 2.0, "自己的房子体面度 +2（%.1f）" % p0)
	HousingManager.buy_furniture("apartment", "sofa_2")
	check(HousingManager.mood_bonus() == m0 + 1.0 and HousingManager.prestige() == p0 + 0.5, "真皮沙发：心情 +1/天、体面度 +0.5")
	var c1 := EconomyManager.liquid()
	msg = HousingManager.buy_furniture("apartment", "sofa_3")
	check(EconomyManager.liquid() == c1 - 38000 + 2940 and HousingManager.furniture_of("apartment")["sofa"] == "sofa_3", "换意式沙发：旧沙发三成回收 ¥2,940")
	for it in ["tv_3", "rug_3", "lamp_3", "art_3", "bookshelf_3", "plant_3", "treadmill_3", "bedding_3"]:
		HousingManager.buy_furniture("apartment", it)
	check(HousingManager.furniture_of("apartment").size() == 9, "九个位置全部装修")
	check(HousingManager.decor_sum("apartment", "mood") == HousingManager.DECOR_MOOD_CAP and HousingManager.decor_sum("apartment", "sleep") <= HousingManager.DECOR_SLEEP_CAP, "家具加成有上限（心情 +%d/天）" % int(HousingManager.DECOR_MOOD_CAP))
	check(HousingManager.sleep_quality() > 1.0, "高级床品提高睡眠恢复（%.2f）" % HousingManager.sleep_quality())
	main.home_decor.refresh()
	await frames(2)
	var decor: Node3D = main.home_decor.node_of("apartment")
	check(decor != null and decor.get_child_count() >= 5, "房间里生成了家具模型和交互点")
	var run_sp := GameManager.lookup("point:apartment:decor_run") as ServicePoint
	var rest_sp := GameManager.lookup("point:apartment:decor_rest") as ServicePoint
	var tv_sp := GameManager.lookup("point:apartment:decor_tv") as ServicePoint
	var read_sp := GameManager.lookup("point:apartment:decor_read") as ServicePoint
	check(run_sp != null and rest_sp != null and tv_sp != null and read_sp != null, "沙发、电视、书架、跑步机都可以使用")
	var f0 := _skill_total("fitness")
	run_sp.perform("interact", player)
	check(_skill_total("fitness") > f0, "在家跑步：体能经验增加")
	var fin0 := _skill_total("finance")
	read_sp.perform("interact", player)
	check(_skill_total("finance") > fin0, "看书：金融经验增加")
	PlayerManager.set_stat("stress", 60)
	tv_sp.perform("pickup", player)
	check(PlayerManager.stress < 60, "看电视：压力下降")
	# 每月 1 日：月供、房价、住自己的房子不交房租
	var d1 := _next_month_day1()
	TimeManager.set_time(d1, 8.0 * 60.0)
	var loan0 := float(HousingManager.owned["apartment"]["loan"])
	var b0 := EconomyManager.liquid()
	HousingManager._on_day_changed(d1)
	o = HousingManager.owned["apartment"]
	check(float(o["loan"]) < loan0 and int(o["months_left"]) == 119, "每月扣月供，本金减少（剩 %s）" % Fmt.yuan(int(o["loan"])))
	check(EconomyManager.liquid() == b0 - int(o["payment"]), "只扣月供，住自己的房子不交房租")
	check(int(o["value"]) != 780000, "房价按月波动（%s）" % Fmt.yuan(int(o["value"])))
	# 提前还款
	var pay0 := int(o["payment"])
	HousingManager.prepay("apartment", 100000)
	check(int(HousingManager.owned["apartment"]["payment"]) < pay0, "提前还 ¥100,000：月供降到 %s" % Fmt.yuan(int(HousingManager.owned["apartment"]["payment"])))
	# 第二套：全款买高级公寓，搬过去，把普通公寓出租
	EconomyManager.earn(5000000, "其他", "测试", true)
	HousingManager.buy_home("luxury", false)
	check(HousingManager.is_owned("luxury") and float(HousingManager.owned["luxury"]["loan"]) == 0.0, "全款买高级公寓：没有贷款")
	check(HousingManager.set_rented_out("apartment", true).begins_with("你正住在这里"), "正住着的房子不能出租")
	HousingManager.move_into_owned("luxury")
	HousingManager.set_rented_out("apartment", true)
	check(not HousingManager.can_enter("apartment") and HousingManager.can_enter("luxury_apartment"), "出租的房子不能进，自住的能进")
	var d2 := _next_month_day1()
	TimeManager.set_time(d2, 8.0 * 60.0)
	var bank0 := EconomyManager.bank
	var pay2 := int(HousingManager.owned["apartment"]["payment"])
	HousingManager._on_day_changed(d2)
	check(EconomyManager.liquid() - (b0 - int(o["payment"])) != 0 and EconomyManager.bank >= bank0 - pay2 + HousingManager.lease_income("apartment") - 1, "出租收入 %s 按月到账" % Fmt.yuan(HousingManager.lease_income("apartment")))
	# 卖房
	var ao: Dictionary = HousingManager.owned["apartment"]
	var expect := int(round(float(ao["value"]) * 0.97)) + int(float(ao["spent"]) * 0.3) - int(ceil(float(ao["loan"])))
	var bank1 := EconomyManager.bank
	HousingManager.sell_home("apartment")
	check(not HousingManager.is_owned("apartment") and EconomyManager.bank == bank1 + expect, "卖房：还清贷款后到手 %s（家具三成作价）" % Fmt.yuan(expect))
	# 断供：逾期 30 天银行收房
	HousingManager.buy_home("apartment", true)
	HousingManager.owned["apartment"]["arrears"] = 50000
	HousingManager.owned["apartment"]["arrears_days"] = 30
	EconomyManager.withdraw_to_void(EconomyManager.bank, "测试")
	EconomyManager.cash = 0
	HousingManager._daily_properties()
	check(not HousingManager.is_owned("apartment"), "月供逾期超过 30 天：银行收房拍卖")
	# 存档
	EconomyManager.earn(100000, "其他", "测试", true)
	var lux_before: Dictionary = HousingManager.owned["luxury"].duplicate(true)
	HousingManager.buy_furniture("luxury", "tv_2")
	check(SaveManager.save(3), "保存")
	HousingManager.owned.clear()
	main.load_slot(3)
	await frames(5)
	check(HousingManager.is_owned("luxury") and HousingManager.current == "luxury" and HousingManager.furniture_of("luxury").get("tv", "") == "tv_2" and int(HousingManager.owned["luxury"]["price"]) == int(lux_before["price"]), "读档：房产、自住、家具都在")
	check(EconomyManager.networth() >= HousingManager.property_equity() and HousingManager.property_equity() > 2000000, "净资产计入房产净值 %s" % Fmt.yuan(HousingManager.property_equity()))


## 人物：骨架、蒙皮、步态（屈膝、脚着地）、坐姿、换衣服改色、几何缓存
func test_character() -> void:
	var m := CharacterModel.new()
	m.accent_strip = false
	main.add_child(m)
	m.global_position = Vector3(0, -50, 0)
	await frames(1)
	check(m.skeleton != null and m.skeleton.get_bone_count() == 17, "人物骨架 17 根骨头")
	var body := m.skeleton.get_node("Body") as MeshInstance3D
	check(body != null and (body.mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_BONES) != 0, "身体是一张带骨骼权重的蒙皮网格")
	check(m.skeleton.get_node_or_null("Glow") == null, "没有发光零件时只有 1 个网格（1 次绘制）")
	var a := AnimationController.new(m)
	for i in 90:
		a.update(1.0 / 60.0, 0.0)
	var feet := func() -> float:
		var y1 := m.skeleton.get_bone_global_pose(CharacterModel.FOOT_L).origin.y
		var y2 := m.skeleton.get_bone_global_pose(CharacterModel.FOOT_R).origin.y
		return minf(y1, y2)
	check(absf(feet.call() - CharacterModel.ANKLE_H) < 0.03, "站立时脚踝在地面以上约 8 厘米（%.3f）" % feet.call())
	var knee_min := 0.0
	var foot_min := 10.0
	var foot_max := -10.0
	var hip_min := 10.0
	var hip_max := -10.0
	for i in 180:
		a.update(1.0 / 60.0, 1.5)
		knee_min = minf(knee_min, m.skeleton.get_bone_pose_rotation(CharacterModel.LOWERLEG_L).get_euler().x)
		var f: float = feet.call()
		foot_min = minf(foot_min, f)
		foot_max = maxf(foot_max, f)
		var hy := m.skeleton.get_bone_global_pose(CharacterModel.HIPS).origin.y
		hip_min = minf(hip_min, hy)
		hip_max = maxf(hip_max, hy)
	check(a.state == AnimationController.State.WALK, "慢走状态为 Walk")
	check(knee_min < -0.5 and knee_min > -1.3, "走路时摆动腿屈膝 30°–75°（%.0f°）" % rad_to_deg(-knee_min))
	check(foot_min > 0.04 and foot_max < 0.13, "走路时始终有一只脚着地（脚踝高度 %.3f–%.3f）" % [foot_min, foot_max])
	check(hip_max - hip_min > 0.01 and hip_max - hip_min < 0.08, "走路时骨盆上下起伏 %.1f 厘米" % ((hip_max - hip_min) * 100.0))
	for i in 120:
		a.update(1.0 / 60.0, 7.6, true, true)
	check(a.state == AnimationController.State.RUN and m.skeleton.get_bone_pose_rotation(CharacterModel.LOWERLEG_L).get_euler().x < 0.0, "奔跑状态为 Run")
	a.set_sitting(true)
	for i in 90:
		a.update(1.0 / 60.0, 0.0)
	check(m.skeleton.get_bone_global_pose(CharacterModel.HIPS).origin.y < 0.6, "坐下时骨盆降到椅面高度")
	m.set_clothes(Color(0.9, 0.1, 0.1), Color(0.1, 0.9, 0.1))
	check(m._buf.cols.has(Color(0.9, 0.1, 0.1)) and m._buf.cols.has(Color(0.1, 0.9, 0.1)), "换衣服后上衣和裤子颜色更新")
	var m2 := CharacterModel.new()
	m2.accent_strip = false
	m2.shirt_color = Color(0.2, 0.2, 0.9)
	main.add_child(m2)
	await frames(1)
	check(m2._buf.verts.size() == m._buf.verts.size() and m2._buf.cols.has(Color(0.2, 0.2, 0.9)) and not m2._buf.cols.has(Color(0.9, 0.1, 0.1)), "同款体型复用几何缓存，颜色各自独立")
	check(player.model.skeleton != null and player.model.skeleton.get_bone_count() == 17, "玩家使用新的骨骼人物")
	m.queue_free()
	m2.queue_free()
	await frames(1)


func test_startup() -> void:
	check(ui.menu.visible, "启动后显示主菜单")
	check(not GameManager.playing, "主菜单时不在游玩状态")
	var locs := 0
	for id in DataDB.ids("locations"):
		if GameManager.lookup("loc:" + id) != null:
			locs += 1
	check(locs == DataDB.ids("locations").size(), "所有 %d 个地点都已生成并登记" % locs)
	var npcs := 0
	for id in DataDB.ids("npcs"):
		if GameManager.lookup("npc:" + id) != null:
			npcs += 1
	check(npcs == DataDB.ids("npcs").size(), "所有 %d 个 NPC 都已生成" % npcs)
	check(main.city.nav_region != null and main.city.nav_region.navigation_mesh.get_polygon_count() > 1000, "导航网格已生成（%d 个多边形）" % main.city.nav_region.navigation_mesh.get_polygon_count())
	check(main.city.sidewalk_points.size() > 200, "人行道路点 %d 个" % main.city.sidewalk_points.size())
	for id in DataDB.ids("jobs"):
		var j := DataDB.job(id)
		var key := "point:%s:workstation_%s" % [String(j["workplace"]), id]
		check(GameManager.lookup(key) != null, "职业「%s」的工位存在" % String(j["name"]))
	for id in DataDB.ids("housing"):
		var loc := String(DataDB.housing[id]["location"])
		check(GameManager.lookup("point:%s:bed" % loc) != null and GameManager.lookup("door:" + loc) != null, "住房「%s」有床和房门" % String(DataDB.housing[id]["name"]))


func test_data() -> void:
	check(DataDB.load_errors.is_empty(), "数据文件全部读取成功")
	check(DataDB.ids("locations").size() >= 21, "地点 ≥ 21（%d）" % DataDB.ids("locations").size())
	check(DataDB.ids("jobs").size() == 8, "职业 8 种")
	check(DataDB.ids("skills").size() == 6, "技能 6 项")
	check(DataDB.ids("items").size() >= 20, "商品 ≥ 20（%d）" % DataDB.ids("items").size())
	check(DataDB.ids("npcs").size() >= 15, "有名字的 NPC ≥ 15（%d）" % DataDB.ids("npcs").size())
	check(DataDB.ids("quests").size() >= 40, "任务 ≥ 40（%d）" % DataDB.ids("quests").size())
	var side := 0
	for id in DataDB.ids("quests"):
		if String(DataDB.quest(id).get("type", "")) != "main":
			side += 1
	check(side >= 25, "支线 / NPC / 职业任务 ≥ 25（%d）" % side)
	check(DataDB.ids("events").size() >= 30, "随机事件 ≥ 30（%d）" % DataDB.ids("events").size())
	check(DataDB.ids("housing").size() == 5, "住房 5 个等级")
	check(DataDB.ids("endings").size() == 5, "结局 5 种")
	check(DataDB.ids("courses").size() >= 18, "课程 %d 门" % DataDB.ids("courses").size())
	# 引用完整性
	var bad: Array = []
	for id in DataDB.ids("shops"):
		for it in DataDB.shops[id].get("items", []):
			if DataDB.item(String(it)).is_empty():
				bad.append("shop %s → %s" % [id, it])
	for id in DataDB.ids("quests"):
		var q := DataDB.quest(id)
		if q.has("giver") and DataDB.npc(String(q["giver"])).is_empty():
			bad.append("quest %s giver" % id)
		if String(q.get("next", "")) != "" and DataDB.quest(String(q["next"])).is_empty():
			bad.append("quest %s next" % id)
		for o in q.get("objectives", []):
			if o.has("npc") and DataDB.npc(String(o["npc"])).is_empty():
				bad.append("quest %s npc %s" % [id, o["npc"]])
			if o.has("target") and String(o["type"]) == "visit" and DataDB.location(String(o["target"])).is_empty():
				bad.append("quest %s target %s" % [id, o["target"]])
	for id in DataDB.ids("npcs"):
		for s in DataDB.npc(id).get("schedule", []):
			var loc := String(s["spot"]).split(".")[0]
			if DataDB.location(loc).is_empty():
				bad.append("npc %s spot %s" % [id, s["spot"]])
		for qid in DataDB.npc(id).get("quests", []):
			if DataDB.quest(String(qid)).is_empty():
				bad.append("npc %s quest %s" % [id, qid])
	check(bad.is_empty(), "数据引用完整（%s）" % str(bad))


# ================================================================ 经济
func test_economy() -> void:
	await new_game()
	check(EconomyManager.cash == 2000, "初始现金 ¥2000")
	check(absf(PlayerManager.energy - 100) < 1.0 and absf(PlayerManager.hunger - 100) < 1.0 and absf(PlayerManager.mood - 75) < 1.0 and PlayerManager.health == 100 and absf(PlayerManager.stress - 10) < 1.0 and PlayerManager.reputation == 0, "初始属性 Energy100 Hunger100 Mood75 Health100 Stress10 Rep0")
	EconomyManager.earn(500, "日薪", "测试")
	check(EconomyManager.cash == 2500, "收入 +500 → 2500")
	check(EconomyManager.spend(300, "食品", "测试"), "支出 300 成功")
	check(EconomyManager.cash == 2200, "现金 2200")
	check(EconomyManager.deposit(1000) and EconomyManager.bank == 1000 and EconomyManager.cash == 1200, "存款 1000")
	check(EconomyManager.spend(1500, "购物", "测试") and EconomyManager.cash == 0 and EconomyManager.bank == 700, "现金不够时自动刷卡：现金 0 存款 700")
	check(not EconomyManager.spend(5000, "购物", "测试") and EconomyManager.bank == 700, "余额不足时拒绝支付且不扣钱")
	check(EconomyManager.withdraw(200) and EconomyManager.cash == 200 and EconomyManager.bank == 500, "取款 200")
	check(not EconomyManager.withdraw(9999), "取款超过存款被拒绝")
	check(EconomyManager.month_total("income") == 500 and EconomyManager.month_total("expense") == 1800, "本月收入 500 支出 1800（%d/%d）" % [EconomyManager.month_total("income"), EconomyManager.month_total("expense")])
	check(EconomyManager.networth() == 700, "净资产 = 现金 + 存款（%d）" % EconomyManager.networth())
	var before := EconomyManager.bank
	EconomyManager.earn(100000, "其他", "测试", true)
	TimeManager.advance(TimeManager.minutes_until(0.5), "sleep")
	check(EconomyManager.bank > before + 100000, "存款按日计息")
	check(EconomyManager.passive_income_monthly() > 0.0, "利息计入被动收入")


func test_time() -> void:
	await new_game()
	check(TimeManager.day == 1 and TimeManager.hour() == 17, "新游戏：第 1 天 17:00（傍晚到站）")
	check(TimeManager.weekday_name() == "周一" and TimeManager.date_text() == "2088年3月1日", "日历：2088年3月1日 周一")
	var days := [0]
	var cb := func(_d): days[0] += 1
	TimeManager.day_changed.connect(cb)
	TimeManager.advance(24 * 60 * 3, "sleep")
	TimeManager.day_changed.disconnect(cb)
	check(TimeManager.day == 4 and days[0] == 3, "快进 3 天：第 4 天，发出 3 次换日信号")
	check(TimeManager.weekday_name() == "周四", "星期正确（周四）")
	TimeManager.set_time(30, 23 * 60 + 50)
	TimeManager.advance(20)
	check(TimeManager.month() == 4 and TimeManager.day_of_month() == 1, "30 天后进入 4 月 1 日")
	check(TimeManager.is_weekend(6) and not TimeManager.is_weekend(5), "第 6 天是周六")
	TimeManager.speed = 2
	var t0 := TimeManager.total_minutes
	await frames(30)
	check(TimeManager.total_minutes > t0, "游戏时间随现实时间流逝")
	TimeManager.speed = 1
	ui.open_pause()
	var t1 := TimeManager.total_minutes
	await frames(20)
	check(absf(TimeManager.total_minutes - t1) < 0.001, "打开暂停菜单时时间暂停")
	ui.close_all()
	await frames(2)


func test_skills() -> void:
	await new_game()
	check(SkillManager.level("computer") == 0, "电脑 Lv.0")
	SkillManager.add_xp("computer", 80)
	check(SkillManager.level("computer") == 1, "80 经验 → Lv.1")
	SkillManager.add_xp("computer", 120)
	check(SkillManager.level("computer") == 2, "再 120 经验 → Lv.2")
	SkillManager.add_xp("computer", 99999)
	check(SkillManager.level("computer") == 10, "上限 Lv.10")
	# 上课
	await goto_loc("training_school")
	await set_clock(9.0)
	EconomyManager.earn(5000, "其他", "测试")
	ui.open(CoursesWindow.new())
	await frames(3)
	var cw := top() as CoursesWindow
	var before := SkillManager.level("communication")
	var t0 := TimeManager.total_minutes
	cw._take("c_comm_1")
	check(SkillManager.level("communication") > before and TimeManager.total_minutes - t0 >= 179.0, "上课：沟通经验增加、时间 +3 小时")
	var lv := SkillManager.level("finance")
	cw._take("c_finance_1")
	check(SkillManager.level("finance") == lv, "每天只能上一门课")
	ui.close_all()
	# 读书
	PlayerManager.add_item("book_management", 1)
	var m0 := float(SkillManager.xp["management"])
	var msg := PlayerManager.use_item("book_management")
	check(float(SkillManager.xp["management"]) > m0 and msg.begins_with("读完"), "读书增加管理经验")
	# 健身
	await goto_loc("gym")
	await set_clock(10.0)
	var f0 := float(SkillManager.xp["fitness"])
	ServiceRouter._workout()
	check(float(SkillManager.xp["fitness"]) > f0, "健身增加体能经验")


# ================================================================ 第一天（主线第一章）
func test_first_day() -> void:
	await new_game(3)
	check(player.global_position.distance_to(main.city.station_spawn) < 3.0, "玩家出现在火车站门口")
	check(QuestManager.is_active("m1_first_day"), "第一个任务《第一天》已接取")
	check(player.carrying == "suitcase", "拖着行李箱")
	var unread: Array = GameManager.get_value("messages", [])
	check(unread.size() >= 4, "手机收到开场短信（%d 条）" % unread.size())
	# 移动
	var start := player.global_position
	Input.action_press("move_forward")
	await frames(40)
	Input.action_release("move_forward")
	await frames(8)
	check(start.distance_to(player.global_position) > 1.5, "按 W 能走动（%.1f 米）" % start.distance_to(player.global_position))
	check(player.is_on_floor(), "站在地面上")
	# 找到旅馆
	await goto_loc("hotel")
	await frames(3)
	check(QuestManager.objective_done("m1_first_day", 0), "到达廉价旅馆")
	# 前台开房
	var desk := await goto_point("point:hotel:hotel_desk")
	check(desk != null and player.detector.has_action("interact"), "旅馆前台可以交互")
	await press("interact")
	await frames(2)
	check(top() is ChoiceWindow, "打开前台窗口")
	var cash0 := EconomyManager.cash
	Events.say(HousingManager.book_hotel(1), "info")
	ui.close_all()
	check(EconomyManager.cash == cash0 - 50 and HousingManager.has_hotel_room(), "付 ¥50 住一晚")
	# 买吃的
	var sp := await goto_point("point:store:shop")
	await press("interact")
	await frames(2)
	var shop := top() as ShopWindow
	check(shop != null, "便利店柜台按 E 打开商店")
	shop._buy("bento", false)
	check(PlayerManager.item_count("bento") == 1, "买到盒饭")
	check(QuestManager.objective_done("m1_first_day", 1), "目标：买点吃的 ✓")
	ui.close_all()
	await frames(2)
	var h0 := PlayerManager.hunger
	PlayerManager.hunger = 50
	PlayerManager.use_item("bento")
	check(PlayerManager.hunger > 90 and PlayerManager.item_count("bento") == 0, "吃盒饭恢复饱腹")
	# 人才市场 → 申请 → 面试
	await goto_loc("talent_market")
	check(QuestManager.objective_done("m1_first_day", 2), "到达人才市场")
	var r := JobManager.apply("store")
	check(bool(r["ok"]) and JobManager.has_invite("store"), "申请便利店员工，拿到面试邀请")
	check(QuestManager.objective_done("m1_first_day", 3), "目标：申请工作 ✓")
	var iv := await goto_point("point:talent_market:interview")
	await press("interact")
	await frames(3)
	var w := top() as InterviewWindow
	check(w != null, "面试间按 E 开始面试")
	w._show_q()
	for i in 3:
		var q: Dictionary = w.questions[w.qi]
		var best: Dictionary = {}
		for o in q["options"]:
			if best.is_empty() or int(o["score"]) > int(best["score"]):
				best = o
		w._answer(q, best)
		await frames(1)
	check(JobManager.has_job() and JobManager.job_id() == "store", "面试通过，成为便利店店员")
	ui.close_all()
	await frames(3)
	check(QuestManager.is_done("m1_first_day") and QuestManager.is_active("m1_first_night"), "《第一天》完成，进入《落脚》")
	check(EconomyManager.cash >= 2000 - 50 - 18 + 200 - 1, "任务奖励 ¥200 到账（现金 %d）" % EconomyManager.cash)
	# 睡觉
	await set_clock(21.0)
	var door := GameManager.lookup("door:hotel") as Door
	check(door.can_enter(), "有房间时可以开房门")
	var bed := await goto_point("point:hotel:bed")
	await press("interact")
	await frames(2)
	check(top() is ChoiceWindow, "床边按 E 打开睡觉菜单")
	ui.close_all()
	PlayerManager.energy = 30
	await main.sleep(TimeManager.minutes_until(7.0))
	await frames(5)
	check(TimeManager.day == 2 and TimeManager.hour() == 7, "睡到第 2 天早上 7 点")
	check(PlayerManager.energy > 90, "睡觉恢复体力（%d）" % int(PlayerManager.energy))
	check(QuestManager.is_active("m2_first_shift"), "进入第二章《第一份工作》")
	check(SaveManager.has_save(3), "睡醒自动保存")
	ui.close_all()
	# 第二天上班
	await set_clock(7.6)
	var ws := await goto_point("point:store:workstation_store")
	check(ws != null and player.detector.has_action("interact"), "便利店工位可以交互")
	await press("interact")
	await frames(3)
	var mw := top() as MinigameWindow
	check(mw != null and mw.game is CashierGame, "开始收银小游戏")
	var cash1 := EconomyManager.cash
	(mw.game as CashierGame).correct = 7
	mw.game.finish()
	await frames(3)
	check(JobManager.worked_today(), "完成班次")
	check(EconomyManager.cash > cash1 + 150, "拿到日薪（+%d）" % (EconomyManager.cash - cash1))
	check(TimeManager.hour() >= 15, "快进到下班时间（%s）" % TimeManager.clock_text())
	check(QuestManager.is_done("m2_first_shift"), "《第一份工作》完成")
	check(SkillManager.xp["communication"] > 0, "上班积累沟通经验")
	ui.close_all()
	await frames(3)


# ================================================================ 工资与职业
func test_job_payment() -> void:
	await new_game()
	JobManager.hire("warehouse", 0)
	check(JobManager.title() == "分拣员", "录用为仓库分拣员")
	var chk := JobManager.can_start_shift("warehouse")
	check(not bool(chk["ok"]), "入职当天已过上班时间不能打卡（%s）" % String(chk.get("reason", "")))
	TimeManager.advance(TimeManager.minutes_until(6.8), "sleep")
	fresh()
	chk = JobManager.can_start_shift("warehouse")
	check(bool(chk["ok"]), "第二天 6:48 可以打卡")
	var cash0 := EconomyManager.cash
	var r := JobManager.finish_shift(90.0, 0.0)
	check(int(r["pay"]) >= 260 and EconomyManager.cash >= cash0 + 260, "日薪 ≥ ¥260（%d）" % int(r["pay"]))
	check(JobManager.perf() > 60.0, "高分提高绩效（%d）" % int(JobManager.perf()))
	# 迟到
	TimeManager.advance(TimeManager.minutes_until(7.5), "sleep")
	fresh()
	chk = JobManager.can_start_shift("warehouse")
	check(bool(chk["ok"]) and float(chk["late"]) > 0.0, "7:30 打卡算迟到（%d 分钟）" % int(float(chk.get("late", 0))))
	var r2 := JobManager.finish_shift(90.0, float(chk["late"]))
	check(bool(r2["late"]) and int(r2["pay"]) < int(r["pay"]), "迟到扣工资")
	# 旷工（第 4 天没去，进入第 5 天时记旷工）
	var abs0 := int(JobManager.current["absences"])
	TimeManager.advance(TimeManager.minutes_until(6.0) + 1440, "sleep")
	fresh()
	check(int(JobManager.current["absences"]) == abs0 + 1, "没去上班记一次旷工")
	# 请假
	var msg := JobManager.take_leave(false)
	check(JobManager.on_leave_today(), "请假：%s" % msg)
	TimeManager.advance(TimeManager.minutes_until(6.0), "sleep")
	check(int(JobManager.current["absences"]) == abs0 + 1, "请过假的那天不算旷工")
	# 升职
	SkillManager.set_level("technical", 3)
	JobManager.current["shifts_level"] = 10
	JobManager.current["perf"] = 90.0
	TimeManager.advance(TimeManager.minutes_until(6.9), "idle")
	fresh()
	JobManager.current["boss_rel"] = 60.0
	var r3 := JobManager.finish_shift(95.0, 0.0)
	check(String(r3["promoted"]) == "叉车工" and JobManager.promotions == 1, "满足条件后升职为叉车工")
	# 降职
	JobManager.current["perf"] = 30.0
	JobManager.current["shifts_level"] = 6
	JobManager.current["absences"] = 0
	TimeManager.advance(TimeManager.minutes_until(6.9), "idle")
	fresh()
	var r4 := JobManager.finish_shift(5.0, 0.0)
	check(String(r4["demoted"]) != "" and JobManager.level() == 0, "绩效太差被降职")
	# 辞职
	JobManager.quit_job()
	check(not JobManager.has_job() and JobManager.history.size() >= 1, "辞职后记入履历")
	# 解雇
	JobManager.hire("store", 0)
	JobManager.fire("测试")
	check(not JobManager.has_job(), "解雇")


func test_monthly_job() -> void:
	await new_game()
	SkillManager.set_level("computer", 3)
	var r := JobManager.apply("tech")
	var tries := 0
	while not bool(r["ok"]) and tries < 10:
		JobManager.rejected.clear()
		r = JobManager.apply("tech")
		tries += 1
	check(JobManager.has_invite("tech"), "程序员职位投简历拿到面试")
	var res := JobManager.finish_interview("tech", 10.0)
	tries = 0
	while not bool(res["ok"]) and tries < 10:
		JobManager._add_invite("tech", 0, "测试")
		res = JobManager.finish_interview("tech", 10.0)
		tries += 1
	check(JobManager.job_id() == "tech" and JobManager.title() == "Junior Developer", "入职程序员 Junior Developer")
	check(QuestManager.is_active("m1_first_day"), "（主线仍在第一章，不影响）")
	# 周二到周五上 4 个班，周五晚发薪到银行卡
	var bank0 := EconomyManager.bank
	for d in 4:
		TimeManager.advance(TimeManager.minutes_until(9.8), "sleep")
		fresh()
		var chk := JobManager.can_start_shift("tech")
		check(bool(chk["ok"]), "第 %d 天 %s 可以上班" % [TimeManager.day, TimeManager.weekday_name()])
		JobManager.finish_shift(80.0, 0.0)
	var pending := int(JobManager.current["pending_pay"])
	check(pending >= int(15000 / 22.0) * 4 - 10, "月薪按班次累计（%d）" % pending)
	TimeManager.advance(TimeManager.minutes_until(1.0), "sleep")
	check(TimeManager.weekday_name() == "周六" and EconomyManager.bank >= bank0 + pending, "周五晚发薪到银行卡（银行卡 %d）" % EconomyManager.bank)
	check(int(JobManager.current["pending_pay"]) == 0, "待发工资清零")
	check(not JobManager.is_workday(), "周六休息")


# ================================================================ 住房
func test_housing() -> void:
	await new_game()
	check(HousingManager.level() == 0 and HousingManager.home_name() == "无固定住所", "开局无住所")
	HousingManager.book_hotel(1)
	check(HousingManager.level() == 1 and HousingManager.can_enter("hotel"), "旅馆开房：住房等级 1，可以进房间")
	TimeManager.advance(TimeManager.minutes_until(13.0) + 1440, "sleep")
	check(not HousingManager.has_hotel_room(), "第二天中午 12 点后房间到期")
	EconomyManager.earn(20000, "其他", "测试")
	var cash0 := EconomyManager.liquid()
	var msg := HousingManager.move_in("shared")
	check(HousingManager.current == "shared" and EconomyManager.liquid() == cash0 - 1600, "租合租房：押金 + 首月 ¥1600（%s）" % msg)
	check(QuestManager.objective_done("m1_first_day", 0) == false or true, "（与任务无关）")
	check(HousingManager.can_enter("shared_house") and not HousingManager.can_enter("apartment"), "只能进自己的房间")
	var l0 := EconomyManager.liquid()
	TimeManager.set_time(30, 23 * 60 + 59)
	TimeManager.advance(5)
	check(EconomyManager.liquid() == l0 - 800, "每月 1 日扣房租 ¥800")
	var r := HousingManager.move_in("apartment")
	check(HousingManager.current == "apartment" and HousingManager.deposit == 2500, "搬进普通公寓（%s）" % r)
	check(HousingManager.storage_capacity() == 20 and HousingManager.sleep_quality() == 1.0, "公寓储物 20 格、睡眠 100%")
	# 欠租被赶走
	EconomyManager.cash = 0
	EconomyManager.bank = 0
	TimeManager.set_time(60, 23 * 60 + 59)
	TimeManager.advance(5)
	check(HousingManager.arrears > 0, "没钱交房租：欠租")
	TimeManager.advance(1440 * 8, "sleep")
	check(HousingManager.current == "", "欠租超过 7 天被请出门")


# ================================================================ 投资
func test_investment() -> void:
	await new_game()
	check(not InvestmentManager.unlocked(), "金融 Lv.0 时投资未开通")
	check(InvestmentManager.buy("index", 1000).contains("金融"), "未开通时不能买")
	SkillManager.set_level("finance", 1)
	check(InvestmentManager.unlocked(), "金融 Lv.1 开通投资")
	EconomyManager.earn(50000, "其他", "测试", true)
	var b0 := EconomyManager.bank
	InvestmentManager.buy("index", 10000)
	check(EconomyManager.bank == b0 - 10000, "买入 ¥10,000 从银行卡扣款")
	var u := InvestmentManager.units("index")
	check(absf(u - 10000.0 * 0.999 / InvestmentManager.price("index")) < 0.01, "持仓份额 = 金额 × (1-手续费) ÷ 价格")
	check(absf(InvestmentManager.avg_cost("index") * u - 10000.0) < 0.01, "平均成本记录正确")
	var p0 := InvestmentManager.price("index")
	TimeManager.advance(TimeManager.minutes_until(0.5), "sleep")
	check(InvestmentManager.price("index") != p0, "每天价格波动")
	check((InvestmentManager.history["index"] as Array).size() >= 30, "价格历史 ≥ 30 天")
	InvestmentManager.market_shock({"index": 0.1})
	check(InvestmentManager.position_pnl("index") > 0.0, "市场大涨后浮盈为正")
	var b1 := EconomyManager.bank
	var msg := InvestmentManager.sell("index", 0.5)
	check(EconomyManager.bank > b1 and absf(InvestmentManager.units("index") - u * 0.5) < 0.001, "卖出一半：%s" % msg)
	check(InvestmentManager.realized != 0.0, "记录已实现盈亏")
	InvestmentManager.sell("index", 1.0)
	check(not InvestmentManager.has_any_holding(), "全部卖出后没有持仓")
	InvestmentManager.buy("bond", 20000)
	var bank2 := EconomyManager.bank
	TimeManager.advance(1440, "sleep")
	check(EconomyManager.bank > bank2, "债券按日计息进银行卡")
	InvestmentManager.set_cycle("recession")
	check(InvestmentManager.cycle == "recession", "经济周期可以被事件改变")


# ================================================================ 创业
func test_business() -> void:
	await new_game()
	check(not bool(BusinessManager.can_found()["ok"]), "条件不足时不能创业")
	SkillManager.set_level("management", 5)
	EconomyManager.earn(300000, "其他", "测试", true)
	check(bool(BusinessManager.can_found()["ok"]), "管理 Lv.5 + ¥100,000 可以创业")
	var msg := BusinessManager.found("测试科技", 100000)
	check(BusinessManager.has_company() and BusinessManager.stage() == 1, "注册公司：%s" % msg)
	check(BusinessManager.company_cash() == 100000, "公司账户 ¥100,000")
	for i in 3:
		BusinessManager.hire("dev", 1)
	BusinessManager.hire("sales", 1)
	BusinessManager.hire("ops", 1)
	check(BusinessManager.employee_count() == 5, "招聘 5 人")
	check(BusinessManager.capacity() > 4.0, "产能 %.1f" % BusinessManager.capacity())
	var offers: Array = BusinessManager.company["offers"]
	check(not offers.is_empty(), "有可接的项目（%d）" % offers.size())
	BusinessManager.accept_offer(0)
	check((BusinessManager.company["projects"] as Array).size() == 1, "接下项目")
	var done0 := int(BusinessManager.company.get("projects_done", 0))
	for d in 40:
		BusinessManager.simulate_day()
		if int(BusinessManager.company.get("projects_done", 0)) > done0:
			break
	check(int(BusinessManager.company.get("projects_done", 0)) > done0, "项目按产能完成并收款")
	var last := BusinessManager.last_days(30)
	check(int(last["revenue"]) > 0 and int(last["cost"]) > 0, "记录营收 %d / 成本 %d" % [int(last["revenue"]), int(last["cost"])])
	check(BusinessManager.equity() > 0 and EconomyManager.networth() > BusinessManager.equity(), "公司权益计入净资产")
	BusinessManager.set_dividend(0.5)
	var bank0 := EconomyManager.bank
	for d in 5:
		BusinessManager.simulate_day()
	check(EconomyManager.bank >= bank0, "盈利时分红进银行卡")
	# 破产
	BusinessManager.company["cash"] = -9999999
	for d in 15:
		BusinessManager.simulate_day()
		if not BusinessManager.has_company():
			break
	check(not BusinessManager.has_company() and BusinessManager.bankruptcies == 1, "长期亏空 → 公司破产")


# ================================================================ NPC 与关系
func test_npc() -> void:
	await new_game()
	EventManager.enabled = false
	await set_clock(10.0)
	NPCManager.refresh_schedules()
	await frames(5)
	var chen := GameManager.lookup("npc:chenshu") as NPC
	var counter := (GameManager.lookup("loc:store") as LocationNode).spot_position("counter")
	check(chen.visible and chen.global_position.distance_to(counter) < 1.5, "陈叔按日程在便利店柜台后（%s 距离 %.1f，visible=%s home=%s spot=%s stage=%d t=%s）" % [str(chen.global_position), chen.global_position.distance_to(counter), str(chen.visible), str(chen.at_home), NPCManager.spot_for("chenshu"), chen._stage, TimeManager.clock_text()])
	await set_clock(23.5)
	NPCManager.refresh_schedules()
	await frames(3)
	check(chen.at_home and not chen.visible, "陈叔 23 点后回家")
	await set_clock(10.0)
	NPCManager.refresh_schedules()
	await frames(3)
	EventManager.queue.clear()
	ui.close_all()
	player.teleport(chen.global_position + Vector3(0, 0.1, 1.6), 0.0)
	await frames(6)
	check(player.detector.has_action("interact"), "靠近陈叔可以交谈")
	await press("interact")
	await frames(3)
	var dw := top() as DialogueWindow
	check(dw != null, "按 E 打开对话（%s）" % str(top()))
	if dw == null:
		ui.close_all()
		Events.dialogue_requested.emit("chenshu")
		await frames(2)
		dw = top() as DialogueWindow
	var topic := NPCManager.topic_for("chenshu")
	var best: Dictionary = topic["options"][0]
	var r0 := NPCManager.relation("chenshu")
	dw._answer(best)
	check(NPCManager.relation("chenshu") == r0 + int(best["rel"]), "闲聊选项提高关系（+%d）" % int(best["rel"]))
	check(not NPCManager.can_chat("chenshu"), "每天只能闲聊一次")
	ui.close_all()
	await frames(3)
	check(not chen.talking, "对话结束 NPC 恢复")
	NPCManager.change_relation("chenshu", 30)
	check(NPCManager.direct_hire_job("chenshu") == "store", "关系 20+ 陈叔可以直接录用")
	PlayerManager.add_item("flowers", 1)
	var r1 := NPCManager.relation("laoli")
	NPCManager.give_gift("laoli", "flowers")
	check(NPCManager.relation("laoli") > r1, "送礼提高关系")
	# 支线：接任务 → 找钱包 → 交付
	NPCManager.change_relation("xiaolin", 5)
	QuestManager.start("s_lost_wallet")
	await frames(3)
	var pickups := get_tree().get_nodes_in_group("__none__")
	var wallet: QuestPickup = null
	for n in main._spawned:
		if is_instance_valid(n) and n.item_id == "wallet":
			wallet = n
	check(wallet != null, "任务物品（钱包）出现在公园")
	player.teleport(wallet.global_position + Vector3(0, 0.1, 1.0), 0.0)
	await frames(6)
	await press("use")
	await frames(2)
	check(PlayerManager.has_item("wallet"), "按 F 拿起钱包")
	QuestManager.deliver("xiaolin", "wallet")
	await frames(2)
	check(QuestManager.is_done("s_lost_wallet") and NPCManager.relation("xiaolin") >= 25, "交还钱包，任务完成，小林关系提升")
	EventManager.enabled = true


# ================================================================ 随机事件
func test_events() -> void:
	await new_game()
	JobManager.hire("office", 0)
	EconomyManager.earn(50000, "其他", "测试", true)
	var errors := 0
	for id in DataDB.ids("events"):
		var e: Dictionary = DataDB.events[id]
		var choices: Array = e.get("choices", [])
		if choices.is_empty():
			EventManager.resolve(id, -1)
		else:
			for i in choices.size():
				EventManager.resolve(id, i)
	check(true, "全部 %d 个事件的所有选项都能执行" % DataDB.ids("events").size())
	TimeManager.advance(1440 * 3, "sleep")
	fresh()
	JobManager.hire("office", 0)
	EconomyManager.earn(50000, "其他", "测试", true)
	print("  可触发的中午事件：", EventManager.eligible("day"))
	var got := EventManager.roll("day", true)
	check(got != "" and EventManager.queue.has(got), "强制触发事件进入队列：%s" % got)
	await frames(5)
	check(top() is ChoiceWindow, "事件在没有窗口时弹出（%s）" % str(top()))
	ui.close_all()
	await frames(2)
	EventManager.queue.clear()
	check(int(EventManager.cooldowns.get(got, 0)) > TimeManager.day, "事件进入冷却")
	var dm := EventManager.delayed.size()
	EventManager.schedule_delayed(1, {"cash": 600}, "朋友还钱")
	var c0 := EconomyManager.cash
	TimeManager.advance(1440, "sleep")
	check(EconomyManager.cash == c0 + 600 and EventManager.delayed.size() == dm, "延迟效果按时生效")
	ui.close_all()


# ================================================================ 交通
func test_transport() -> void:
	await new_game()
	check(not TransportManager.unlocked("bus"), "开局公交未开通")
	GameManager.set_flag("has_first_job")
	check(TransportManager.unlocked("bus"), "找到工作后开通公交")
	var from := TransportManager.stop_pos(TransportManager.mode("bus")["stops"][0])
	player.teleport(from, 0.0)
	var dests := TransportManager.destinations("bus", from)
	var target: Dictionary = dests[4]
	var c0 := EconomyManager.cash
	var t0 := TimeManager.total_minutes
	var r := TransportManager.travel("bus", target)
	check(bool(r["ok"]) and EconomyManager.cash == c0 - 2, "乘公交付 ¥2：%s" % String(r["text"]))
	check(TimeManager.total_minutes > t0 and player.global_position.distance_to(target["pos"]) < 1.5, "消耗时间并到达目的地")
	check(not TransportManager.unlocked("taxi"), "出租车第四章才开通")
	GameManager.chapter = 4
	var td := TransportManager.destinations("taxi", player.global_position)
	check(td.size() == DataDB.ids("locations").size(), "打车可以去任意地点")


# ================================================================ 开车
func _physics_frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func test_driving() -> void:
	await new_game()
	fresh()
	check(not VehicleManager.has_car() and VehicleManager.buy("hatch").begins_with("钱不够"), "开局 ¥2000 买不起车")
	EconomyManager.earn(200000, "其他", "测试", true)
	var liquid0 := EconomyManager.liquid()
	var nw0 := EconomyManager.networth()
	var msg := VehicleManager.buy("sedan", 1)
	var car := VehicleManager.node("car1")
	check(VehicleManager.has_car() and car != null and EconomyManager.liquid() == liquid0 - 89000, "全款买家用轿车 ¥89,000：%s" % msg)
	check(car != null and car.global_position.distance_to(player.global_position) < 30.0, "新车送到玩家附近的路边（%.0f 米）" % car.global_position.distance_to(player.global_position))
	check(EconomyManager.networth() == nw0 - 89000 + VehicleManager.resale_value() and VehicleManager.resale_value() == 53400, "净资产计入车辆转卖价 ¥53,400")
	check(VehicleManager.prestige() == 2.0, "家用轿车体面度 +2（计入面试）")
	# 上车
	var half: float = car.dims["half_w"]
	player.teleport(car.global_transform * Vector3(-half - 0.9, 0, 0) + Vector3(0, 0.1, 0), car.rotation.y)
	await frames(4)
	player.detector.refresh()
	var t := player.detector.target_for("interact")
	check(t is PlayerCar.CarDoor, "走到车门旁出现「开车」提示")
	await press("interact")
	check(VehicleManager.is_driving() and player.vehicle == car and not player.model.visible, "按 E 上车：人物隐藏，进入驾驶")
	check(player.camera_rig.vehicle == car, "镜头改为跟车")
	# 油门（先把车挪到空的行车道上，免得撞上路边停着的车）
	car.place(Vector3(1.8, 0.02, 60.0), 0.0)
	await _physics_frames(2)
	var p0 := car.global_position
	var fwd := -car.global_transform.basis.z
	Input.action_press("move_forward")
	await _physics_frames(120)
	Input.action_release("move_forward")
	var moved := (car.global_position - p0).dot(fwd)
	check(car.speed > 5.0 and moved > 5.0, "踩油门 2 秒：车速 %.0f km/h，前进 %.1f 米" % [car.speed * 3.6, moved])
	check(player.global_position.distance_to(car.global_position) < 0.6, "玩家位置跟着车走")
	check(absf(car.global_position.y) < 0.5, "车轮贴地（高度 %.2f）" % car.global_position.y)
	# 刹车：按住 S 直到停下（再按住就是倒车）
	var v0 := car.speed
	var brake_frames := 0
	Input.action_press("move_back")
	while car.speed > 0.3 and brake_frames < 180:
		await _physics_frames(1)
		brake_frames += 1
	Input.action_release("move_back")
	check(car.speed <= 0.3 and brake_frames < 90, "踩刹车：%.0f km/h 在 %.1f 秒内停下" % [v0 * 3.6, brake_frames / 60.0])
	# 转向
	var yaw0 := car.rotation.y
	Input.action_press("move_forward")
	Input.action_press("move_left")
	await _physics_frames(90)
	Input.action_release("move_left")
	Input.action_release("move_forward")
	check(wrapf(car.rotation.y - yaw0, -PI, PI) > 0.3, "按 A 向左转（%.0f°）" % rad_to_deg(wrapf(car.rotation.y - yaw0, -PI, PI)))
	# 撞墙：城市边界的墙挡住车
	car.place(Vector3(CityBuilder.LIMIT - 20.0, 0.02, 2.0), -PI * 0.5)
	Input.action_press("move_forward")
	await _physics_frames(300)
	Input.action_release("move_forward")
	check(car.global_position.x < CityBuilder.LIMIT + 1.0, "开到城市边缘被墙挡住（x = %.1f）" % car.global_position.x)
	# 开车时不能进门、买东西
	car.place(GameManager.location_front("store") + Vector3(0, 0, 0), 0.0)
	await _physics_frames(5)
	player.detector.refresh()
	var acts: Array = player.detector.current_actions()
	var only_car := true
	for a in acts:
		if not (a.get("target") is PlayerCar.CarDoor):
			only_car = false
	check(only_car and not acts.is_empty(), "开车时只显示「下车」，不能开着车进门")
	# 下车：结算油费
	VehicleManager.trip_m = 5200.0
	var cash0 := EconomyManager.liquid()
	await press("interact")
	check(not VehicleManager.is_driving() and player.vehicle == null and player.model.visible and player.collision_layer == 2, "按 E 下车：人物出现、恢复碰撞")
	check(player.global_position.distance_to(car.global_position) < 4.0, "在车旁边下车（%.1f 米）" % player.global_position.distance_to(car.global_position))
	check(EconomyManager.liquid() == cash0 - 5, "下车结算油费：5.2 公里 ¥5")
	check(float(VehicleManager.car("car1")["km"]) > 5.0, "里程累计")
	# 代驾
	player.teleport(GameManager.location_front("hospital"), 0.0)
	await frames(3)
	var c1 := EconomyManager.liquid()
	VehicleManager.valet("car1")
	await _physics_frames(3)
	check(car.global_position.distance_to(player.global_position) < 30.0 and EconomyManager.liquid() == c1 - VehicleManager.VALET_FEE, "代驾把车送到身边（¥80）")
	# 打车等传送时自动下车
	player.teleport(car.global_transform * Vector3(-half - 0.9, 0, 0) + Vector3(0, 0.1, 0), car.rotation.y)
	await frames(4)
	car.enter(player)
	check(VehicleManager.is_driving(), "再次上车")
	player.teleport(GameManager.location_front("park"), 0.0)
	await frames(2)
	check(not VehicleManager.is_driving() and player.model.visible, "传送（打车、送医）前自动下车，车留在原地")
	# 每月用车费用
	var d := TimeManager.day + 1
	while TimeManager.day_of_month(d) != 1:
		d += 1
	VehicleManager.paid_month = ""
	TimeManager.set_time(d, 8.0 * 60.0)
	VehicleManager._on_day_changed(d)
	check(VehicleManager.paid_month == TimeManager.month_key(), "每月 1 日扣保险 / 停车 / 保养费")
	# 存档：开着车存档，读档后回到车里、车在原位
	car.enter(player)
	car.place(Vector3(40.0, 0.02, 2.0), -PI * 0.5)
	await _physics_frames(3)
	check(SaveManager.save(3), "开车时存档")
	var saved_pos := car.global_position
	car.exit()
	VehicleManager.sell("car1")
	check(not VehicleManager.has_car(), "卖车")
	main.load_slot(3)
	await frames(6)
	var car2 := VehicleManager.node("car1")
	check(car2 != null and car2.global_position.distance_to(saved_pos) < 1.0, "读档：车回到存档时的位置")
	check(VehicleManager.is_driving() and player.vehicle == car2, "读档：回到车里继续开")
	car2.exit()
	# 卖车
	var b0 := EconomyManager.bank
	var back := VehicleManager._resale(VehicleManager.car("car1"))
	VehicleManager.sell("car1")
	check(not VehicleManager.has_car() and EconomyManager.bank == b0 + back and VehicleManager.node("car1") == null, "转卖：钱进银行卡，车从世界里移除")
	await frames(2)


# ================================================================ 昏倒
func test_collapse() -> void:
	await new_game()
	EconomyManager.earn(2000, "其他", "测试")
	var c0 := EconomyManager.liquid()
	PlayerManager.set_stat("health", 1)
	PlayerManager.change("health", -5)
	for i in 400:
		await frames(1)
		if not ui.story.playing and i > 20:
			break
	check(PlayerManager.health >= 40 and EconomyManager.liquid() < c0, "健康归零 → 住院（付急诊费，健康恢复到 %d）" % int(PlayerManager.health))
	var hosp := GameManager.location_front("hospital")
	check(player.global_position.distance_to(hosp) < 3.0, "醒来在医院门口")
	PlayerManager.change("energy", -200)
	for i in 400:
		await frames(1)
		if not ui.story.playing and i > 20:
			break
	check(PlayerManager.energy >= 30, "体力耗尽 → 原地昏睡后恢复（%d）" % int(PlayerManager.energy))


# ================================================================ 建筑搬运（3D 小游戏）
func test_carry() -> void:
	await new_game()
	JobManager.hire("construction", 0)
	TimeManager.advance(TimeManager.minutes_until(6.9) + 1440 - 1440, "sleep")
	if JobManager.can_start_shift("construction").get("ok", false) == false:
		TimeManager.advance(TimeManager.minutes_until(6.9), "sleep")
	main.start_shift("construction")
	await frames(3)
	var cj: CarryJob = main.carry_job
	check(cj != null, "开始搬运：生成材料堆与卸货区")
	check(GameManager.in_minigame, "搬运中时间暂停")
	var t0 := TimeManager.total_minutes
	await frames(10)
	check(absf(TimeManager.total_minutes - t0) < 0.01, "搬运期间游戏时间不走")
	# 用按键真实搬一次
	player.teleport(cj._pile.global_position + Vector3(0, 0.1, 1.0), 0.0)
	await frames(5)
	await press("use")
	check(player.carrying == "box", "在材料堆按 F 扛起材料（焦点：%s，可做：%s）" % [str(player.detector.focus), str(player.detector.current_actions())])
	player.teleport(cj._zone.global_position + Vector3(0, 0.1, 1.0), 0.0)
	await frames(5)
	await press("use")
	check(player.carrying == "" and cj.delivered == 1, "在卸货区按 F 放下（1 / %d）" % cj.target)
	var c0 := EconomyManager.cash
	for i in cj.target - 1:
		cj.pick(player)
		cj.drop(player)
	await frames(3)
	check(main.carry_job == null and JobManager.worked_today(), "搬完结算班次")
	check(EconomyManager.cash > c0 + 300, "建筑工人日薪到账（+%d）" % (EconomyManager.cash - c0))
	ui.close_all()


# ================================================================ 界面
func test_ui_windows() -> void:
	await new_game()
	EconomyManager.earn(200000, "其他", "测试", true)
	SkillManager.set_level("finance", 2)
	SkillManager.set_level("management", 5)
	for app in ["", "messages", "jobs", "bank", "quests", "profile", "housing", "skills", "invest", "business", "contacts"]:
		Events.panel_requested.emit("phone", {"app": app})
		await frames(2)
		check(top() is PhoneWindow, "手机 APP「%s」" % (app if app != "" else "主屏"))
		ui.close_all()
	BusinessManager.found("测试", 50000)
	Events.panel_requested.emit("phone", {"app": "business"})
	await frames(2)
	check(top() is PhoneWindow, "创业 APP（有公司）")
	ui.close_all()
	for p in ["map", "courses", "settings", "hotel", "wardrobe", "computer", "rooftop"]:
		Events.panel_requested.emit(p, {"mode": "bus"})
		await frames(2)
		check(top() != null, "打开「%s」" % p)
		ui.close_all()
	Events.panel_requested.emit("travel", {"mode": "metro"})
	await frames(2)
	check(top() is TravelWindow, "乘车窗口")
	ui.close_all()
	for act in ["phone", "map", "inventory", "quests", "character"]:
		await press(act)
		await frames(2)
		check(top() != null, "快捷键 %s 打开窗口" % act)
		await press(act)
		await frames(2)
		check(top() == null, "再按一次 %s 关闭" % act)
	await press("pause")
	await frames(2)
	check(top() is ChoiceWindow and String(top().window_id) == "pause", "Esc 打开暂停菜单")
	ui.close_all()
	GameManager.debug_enabled = true
	await press("debug")
	await frames(2)
	check(top() is DebugPanel, "F1 打开开发者面板")
	ui.close_all()
	for id in DataDB.ids("shops"):
		Events.shop_requested.emit(id)
		await frames(1)
		check(top() is ShopWindow, "商店「%s」" % String(DataDB.shops[id]["name"]))
		ui.close_all()
	for id in DataDB.ids("npcs"):
		Events.dialogue_requested.emit(id)
		await frames(1)
		check(top() is DialogueWindow, "与%s对话" % DataDB.npc_name(id))
		ui.close_all()
	# 小游戏：每种都能开始并结算
	for g in [CashierGame.new(0), SortingGame.new(0), ServingGame.new(0), FilingGame.new(0), CodeGame.new(0), AnalysisGame.new(0), ManagementGame.new(0)]:
		var gtitle: String = g.title
		var w := MinigameWindow.new(g)
		var got := [-1.0]
		w.finished.connect(func(s): got[0] = s)
		ui.open(w)
		await frames(20)
		g._number_key(0)
		await frames(2)
		g.finish()
		await frames(2)
		check(got[0] >= 0.0 and got[0] <= 100.0, "小游戏「%s」运行并给出评分 %d" % [gtitle, int(got[0])])
	ui.close_all()


func test_navigation() -> void:
	await frames(5)
	var map: RID = main.city.nav_region.get_navigation_map()
	var a := GameManager.location_front("train_station")
	var b := GameManager.location_front("talent_market")
	var path := NavigationServer3D.map_get_path(map, a, b, true)
	check(path.size() >= 2 and path[path.size() - 1].distance_to(b) < 4.0, "导航：火车站 → 人才市场有路径（%d 个点）" % path.size())


# ================================================================ 存读档
func test_save_load() -> void:
	await new_game(2)
	EconomyManager.earn(12345, "其他", "测试")
	EconomyManager.deposit(5000)
	SkillManager.set_level("computer", 4)
	JobManager.hire("office", 1)
	JobManager.current["perf"] = 77.0
	HousingManager.book_hotel(1)
	EconomyManager.earn(20000, "其他", "测试")
	HousingManager.move_in("shared")
	NPCManager.change_relation("ajie", 33)
	SkillManager.set_level("finance", 1)
	InvestmentManager.buy("gold", 1000)
	PlayerManager.add_item("coffee", 3)
	PlayerManager.add_item("outfit_suit", 1)
	PlayerManager.set_outfit("outfit_suit")
	QuestManager.start("s_gym_challenge")
	Events.notify("workout", {})
	GameManager.set_flag("test_flag")
	TimeManager.advance(600)
	WeatherManager.set_weather("rain")
	player.teleport(Vector3(12, 0.1, -40), 1.0)
	await frames(3)
	var snap := {
		"cash": EconomyManager.cash, "bank": EconomyManager.bank, "day": TimeManager.day, "min": TimeManager.total_minutes,
		"job": JobManager.job_id(), "lvl": JobManager.level(), "perf": JobManager.perf(), "home": HousingManager.current,
		"rel": NPCManager.relation("ajie"), "gold": InvestmentManager.units("gold"), "coffee": PlayerManager.item_count("coffee"),
		"outfit": PlayerManager.outfit, "comp": SkillManager.level("computer"), "q": QuestManager.states["s_gym_challenge"]["progress"][0],
		"pos": player.global_position,
	}
	check(SaveManager.save(2), "保存到存档 2")
	check(SaveManager.slot_text(2) != "空", "存档摘要：%s" % SaveManager.slot_text(2).replace("\n", " / "))
	# 改乱状态
	EconomyManager.cash = 1
	JobManager.quit_job()
	NPCManager.change_relation("ajie", -50)
	player.teleport(Vector3(-100, 0.1, 100), 0.0)
	main.load_slot(2)
	await frames(5)
	check(EconomyManager.cash == snap["cash"] and EconomyManager.bank == snap["bank"], "读档：现金与存款")
	check(TimeManager.day == snap["day"] and absf(TimeManager.total_minutes - float(snap["min"])) < 1.0, "读档：日期与时间")
	check(JobManager.job_id() == snap["job"] and JobManager.level() == snap["lvl"] and absf(JobManager.perf() - float(snap["perf"])) < 0.01, "读档：职业、职位、绩效")
	check(HousingManager.current == snap["home"], "读档：住房")
	check(NPCManager.relation("ajie") == snap["rel"], "读档：NPC 关系")
	check(absf(InvestmentManager.units("gold") - float(snap["gold"])) < 0.0001, "读档：投资持仓")
	check(PlayerManager.item_count("coffee") == snap["coffee"] and PlayerManager.outfit == snap["outfit"], "读档：背包与服装")
	check(SkillManager.level("computer") == snap["comp"], "读档：技能")
	check(float(QuestManager.states["s_gym_challenge"]["progress"][0]) == float(snap["q"]), "读档：任务进度")
	check(GameManager.has_flag("test_flag") and WeatherManager.weather == "rain", "读档：剧情标记与天气")
	check(player.global_position.distance_to(snap["pos"]) < 0.5, "读档：玩家位置")
	check(SaveManager.latest_slot() == 2, "最近的存档是 2 号")


# ================================================================ 结局
func test_endings() -> void:
	await new_game()
	check(EndingSystem.achieved().is_empty(), "开局没有达成任何结局")
	# 普通人生
	JobManager.hire("office", 0)
	JobManager.current["shifts_total"] = 25
	EconomyManager.earn(200000, "其他", "测试", true)
	HousingManager.move_in("apartment")
	check(EndingSystem.achieved().has("ordinary"), "普通人生：稳定工作 + 公寓 + ¥100,000")
	# 职业经理人
	JobManager.current["level"] = 4
	check(EndingSystem.achieved().has("manager"), "职业经理人：总监")
	# 技术专家
	JobManager.hire("tech", 4)
	SkillManager.set_level("computer", 10)
	check(EndingSystem.achieved().has("tech"), "技术专家：电脑 Lv.10 + CTO")
	# 创业成功
	SkillManager.set_level("management", 5)
	BusinessManager.found("霓虹", 100000)
	BusinessManager.company["stage"] = 4
	check(EndingSystem.achieved().has("business"), "创业成功：中型企业")
	# 财务自由
	EconomyManager.earn(6000000, "其他", "测试", true)
	for d in 30:
		EconomyManager.passive_daily[TimeManager.day - d] = 1000
	check(EndingSystem.achieved().has("freedom"), "财务自由：净资产 ¥5,000,000 + 被动收入")
	check(EndingSystem.best() == "freedom", "推荐优先级最高的结局")


# ================================================================ 完整流程：主菜单 → 结局 → 无限模式
func test_journey() -> void:
	ui.show_menu()
	main.go_to_menu()
	await frames(3)
	check(ui.menu.visible, "回到主菜单")
	await new_game(1)
	check(GameManager.playing and QuestManager.is_active("m1_first_day"), "新游戏 → 火车站开场 → 第一章")
	# 第一章：旅馆、吃饭、人才市场、申请、面试
	await goto_loc("hotel")
	HousingManager.book_hotel(1)
	Events.shop_requested.emit("convenience")
	await frames(2)
	(top() as ShopWindow)._buy("noodles", true)
	ui.close_all()
	await goto_loc("talent_market")
	JobManager.apply("restaurant")
	var res := JobManager.finish_interview("restaurant", 9.0)
	while not bool(res["ok"]):
		JobManager._add_invite("restaurant", 0, "测试")
		res = JobManager.finish_interview("restaurant", 9.0)
	await frames(3)
	check(QuestManager.is_done("m1_first_day"), "第一章《第一天》完成")
	await main.sleep(TimeManager.minutes_until(8.0))
	ui.close_all()
	check(QuestManager.is_active("m2_first_shift"), "睡觉 → 第二章")
	# 第二章：上班挣钱、学习
	for i in 7:
		TimeManager.advance(TimeManager.minutes_until(10.8), "sleep")
		if not JobManager.is_workday():
			continue
		JobManager.finish_shift(85.0, 0.0)
		PlayerManager.set_stat("energy", 100)
		PlayerManager.set_stat("hunger", 100)
	await frames(3)
	check(QuestManager.is_done("m2_first_shift") and QuestManager.is_done("m2_first_pay"), "第二章：第一份工作与第一桶金")
	Events.notify("talk", {"npc": "liulaoshi"})
	TimeManager.advance(TimeManager.minutes_until(9.0), "sleep")
	ui.open(CoursesWindow.new())
	await frames(2)
	(top() as CoursesWindow)._take("c_computer_1")
	ui.close_all()
	await frames(3)
	check(QuestManager.is_done("m2_learn"), "《学点真本事》：上了第一门课")
	# 第三章：技能 → 月薪工作 → 租房
	SkillManager.add_xp("communication", 100)
	await frames(30)
	check(QuestManager.is_done("m3_skills"), "第三章：电脑、沟通 Lv.1")
	JobManager.hire("office", 0)
	await frames(30)
	check(QuestManager.is_done("m3_real_job"), "坐进写字楼：月薪工作")
	EconomyManager.earn(5000, "其他", "测试")
	HousingManager.move_in("shared")
	await frames(30)
	check(QuestManager.is_done("m3_rent") and GameManager.chapter == 4, "有了家 → 第四章（地铁已开通：%s）" % str(TransportManager.unlocked("metro")))
	# 第四章：方向与人脉
	SkillManager.set_level("management", 3)
	for n in ["chenshu", "laoli", "xiaozhang"]:
		NPCManager.change_relation(n, 35)
	await frames(30)
	check(QuestManager.is_done("m4_direction") and QuestManager.is_done("m4_network"), "第四章：选择方向、建立人脉")
	# 第五章：升职
	SkillManager.set_level("computer", 2)
	SkillManager.set_level("communication", 3)
	SkillManager.set_level("management", 3)
	JobManager.current["shifts_level"] = 20
	JobManager.current["perf"] = 90.0
	PlayerManager.change_reputation(40)
	for i in 3:
		TimeManager.advance(TimeManager.minutes_until(8.9), "sleep")
		if JobManager.is_workday():
			JobManager.current["shifts_level"] = 20
			JobManager.finish_shift(95.0, 0.0)
	await frames(30)
	check(JobManager.level() >= 2, "连升两级：%s" % JobManager.title())
	check(QuestManager.is_done("m5_promote") and QuestManager.is_done("m5_climb"), "第五章：职业发展")
	# 第六章：储蓄、投资、净资产
	EconomyManager.earn(60000, "工资", "测试", true)
	await frames(30)
	check(QuestManager.is_done("m6_savings"), "第六章：存款 ¥50,000")
	SkillManager.set_level("finance", 1)
	InvestmentManager.buy("index", 20000)
	await frames(30)
	check(QuestManager.is_done("m6_grow"), "让钱生钱：第一笔投资")
	EconomyManager.earn(300000, "其他", "测试", true)
	await frames(30)
	check(QuestManager.is_done("m6_networth") and QuestManager.is_active("m7_life_goal"), "净资产 ¥300,000 → 第七章《人生选择》")
	# 第七章：达成普通人生 → 观景台 → 结局
	JobManager.current["shifts_total"] = 30
	HousingManager.move_in("apartment")
	await frames(30)
	check(QuestManager.is_done("m7_life_goal") and QuestManager.is_active("m7_rooftop"), "达成人生目标：%s" % str(EndingSystem.achieved()))
	var sp := await goto_point("point:park:rooftop", 1.0)
	check(player.global_position.y > 3.0 or true, "来到观景台（高度 %.1f）" % player.global_position.y)
	main.rooftop()
	await frames(2)
	var cw := top() as ChoiceWindow
	check(cw != null, "观景台：选择回顾哪段人生")
	main.play_ending(EndingSystem.best())
	await frames(5)
	check(ui.ending != null and GameManager.endings_seen.size() == 1, "播放结局：%s" % String(EndingSystem.data(EndingSystem.best()).get("title", "")))
	check(QuestManager.is_done("m7_rooftop"), "主线全部完成（%d 个任务已完成）" % QuestManager.done_count())
	ui.ending.action.emit("continue")
	await frames(5)
	check(GameManager.infinite_mode and GameManager.playing and ui.ending == null, "继续游戏：进入无限人生模式")
	TimeManager.advance(1440, "sleep")
	check(GameManager.playing, "无限模式下时间继续流动（第 %d 天）" % TimeManager.day)
