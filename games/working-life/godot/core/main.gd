extends Node3D
## 游戏主流程（场景根节点脚本）：
##   启动 → 生成城市 / 玩家 / NPC / 界面 → 主菜单
##   新游戏 → 开场（列车进站 → 走出火车站 → 手机短信）→ 第一章
##   上班（小游戏 → 结算）、睡觉（快进 → 自动存档 → 早晨事件）、昏倒 / 住院、结局与无限人生模式。
## 各系统的规则都在自己的管理器里，这里只负责「串起来」。

const START_CASH := 2000
const START_HOUR := 17.0

var city: CityBuilder
var day_night: DayNight
var weather_fx: WeatherFX
var traffic: Traffic
var train: Train
var crowd: Crowd
var player: Player
var ui: UIRoot
var menu_camera: Camera3D
var marker: ObjectiveMarker
var carry_job: CarryJob = null
var _skip_intro := false
## 自动化测试用：跳过开场
var auto_skip_intro := false
var _menu_t := 0.0
var _last_loc := ""


func _ready() -> void:
	InputSetup.register()
	GameManager.main = self
	city = CityBuilder.new()
	city.name = "City"
	add_child(city)
	city.build()
	day_night = DayNight.new()
	day_night.city = city
	add_child(day_night)
	weather_fx = WeatherFX.new()
	add_child(weather_fx)
	traffic = Traffic.new()
	add_child(traffic)
	train = Train.new()
	train.position = Vector3(0, CityBuilder.TRACK_Y, CityBuilder.TRACK_Z)
	add_child(train)
	player = (load("res://scenes/player.tscn") as PackedScene).instantiate()
	add_child(player)
	GameManager.player = player
	player.set_spawn(city.station_spawn, 0.0)
	player.teleport(city.station_spawn, 0.0)
	weather_fx.target = player
	_spawn_npcs()
	crowd = Crowd.new()
	add_child(crowd)
	crowd.setup(city.sidewalk_points)
	marker = ObjectiveMarker.new()
	add_child(marker)
	menu_camera = Camera3D.new()
	menu_camera.far = 1200.0
	menu_camera.fov = 60.0
	add_child(menu_camera)
	ui = UIRoot.new()
	add_child(ui)
	ui.setup(self)
	PlayerManager.collapsed.connect(_on_collapsed)
	Events.location_entered.connect(_on_location)
	Events.world_spawns_changed.connect(_refresh_spawns)
	QuestManager.quest_completed.connect(_on_quest_completed)
	SettingsManager.apply_runtime()
	# 标题画面用的「预览世界」：随机时间与天气
	NPCManager.reset()
	InvestmentManager.reset()
	TimeManager.set_time(1, 21.0 * 60.0)
	NPCManager.refresh_schedules(true)
	go_to_menu()


func _spawn_npcs() -> void:
	for id in DataDB.ids("npcs"):
		var n := NPC.new()
		n.setup(id)
		add_child(n)
		n.global_position = Vector3(0, 0, 150)
		n._set_home(true)


func apply_quality() -> void:
	day_night.apply_quality()


# ================================================================ 菜单
func go_to_menu() -> void:
	GameManager.set_playing(false)
	GameManager.in_minigame = false
	_end_carry(false)
	menu_camera.current = true
	ui.show_menu()
	AudioManager.play_music("menu")
	AudioManager.set_ambience(0, "city")


func _process(delta: float) -> void:
	if not GameManager.playing and ui.menu.visible:
		# 标题画面：镜头绕城市缓慢旋转
		_menu_t += delta * 0.03
		var c := Vector3(-20, 0, -20)
		menu_camera.global_position = c + Vector3(cos(_menu_t) * 170.0, 70.0, sin(_menu_t) * 170.0)
		menu_camera.look_at(c + Vector3(0, 20, 0))


# ================================================================ 新游戏 / 读档
func _reset_all() -> void:
	GameManager.reset()
	TimeManager.reset(START_HOUR)
	EconomyManager.reset(START_CASH)
	SkillManager.reset()
	PlayerManager.reset()
	HousingManager.reset()
	JobManager.reset()
	NPCManager.reset()
	QuestManager.reset()
	EventManager.reset()
	InvestmentManager.reset()
	BusinessManager.reset()
	WeatherManager.reset()
	_clear_spawns()


func start_new_game(slot: int) -> void:
	SaveManager.current_slot = slot
	_reset_all()
	ui.hide_menu()
	player.set_carry("suitcase")
	player.refresh_outfit()
	GameManager.set_playing(true)
	NPCManager.refresh_schedules(true)
	await _intro()
	_begin_play()
	QuestManager.start("m1_first_day")
	SaveManager.save(slot)


func _intro() -> void:
	_skip_intro = auto_skip_intro
	var cam := menu_camera
	cam.current = true
	ui.story.begin(true)
	var on_skip := func(): _skip_intro = true
	ui.story.skip_requested.connect(on_skip)
	ui.story.set_black(1.0)
	AudioManager.play_music("intro")
	# 镜头一：高架上的列车驶入城市
	train.start()
	cam.global_position = Vector3(110, 14, 186)
	ui.story.fade(false, 1.2)
	ui.story.caption("2088 年，春。新澜市。")
	var t := 0.0
	var second_caption := false
	while t < 9.5 and not _skip_intro:
		var dt := get_process_delta_time()
		t += dt
		var tp := train.global_position + Vector3(10, 2, 0)
		cam.global_position = cam.global_position.lerp(Vector3(tp.x + 40, 16, 180), clampf(dt * 0.8, 0.0, 1.0))
		cam.look_at(tp)
		if t > 4.0 and not second_caption:
			second_caption = true
			ui.story.caption("一列从远方驶来的磁悬浮列车，缓缓驶入这座不眠的城市。")
		await get_tree().process_frame
	train.place_at_stop()
	if not _skip_intro:
		await ui.story.fade(true, 0.6).finished
	# 镜头二：玩家拖着行李箱走出火车站
	player.teleport(city.station_spawn + Vector3(0, 0, 6), 0.0)
	cam.global_position = city.station_spawn + Vector3(4, 2.2, -8)
	cam.look_at(city.station_spawn + Vector3(0, 1.4, 4))
	ui.story.caption("你拖着行李箱走出火车站。")
	if not _skip_intro:
		ui.story.fade(false, 0.8)
		var t2 := 0.0
		while t2 < 3.0 and not _skip_intro:
			var dt2 := get_process_delta_time()
			t2 += dt2
			player.global_position = player.global_position.move_toward(city.station_spawn, dt2 * 1.4)
			player.anim.update(dt2, 1.4)
			await get_tree().process_frame
	player.teleport(city.station_spawn, 0.0)
	# 手机消息
	var msgs := [
		["新澜市政务", "欢迎来到新城市。"],
		["新澜银行", "当前余额：¥2000"],
		["新澜市政务", "你现在没有工作，也没有固定住所。"],
		["？？？", "今晚之前，先想办法活下来。"],
	]
	for m in msgs:
		if _skip_intro:
			break
		ui.story.phone(m[0], m[1])
		await get_tree().create_timer(1.6).timeout
	if not _skip_intro:
		await get_tree().create_timer(1.2).timeout
	for m in msgs:
		Events.phone_message.emit(m[0], m[1])
	ui.story.skip_requested.disconnect(on_skip)
	ui.story.end()
	ui.story.set_black(0.0)
	GameManager.set_value("unread_messages", 0)


func _begin_play() -> void:
	player.camera_rig.camera.current = true
	ui.hide_menu()
	GameManager.set_playing(true)
	AudioManager.play_music("city")
	NPCManager.refresh_schedules(true)
	_refresh_spawns()
	ui.capture_mouse()
	Events.banner.emit("第一章 · 活下来", "现金 ¥%s · 没有工作 · 没有住处" % Fmt.money(EconomyManager.cash) if GameManager.chapter == 1 and TimeManager.day == 1 else "")


func load_slot(slot: int) -> void:
	var d := SaveManager.read(slot)
	if d.is_empty():
		Events.say("存档 %d 读取失败" % slot, "bad")
		return
	_reset_all()
	GameManager.set_playing(true)
	SaveManager.apply(d)
	SaveManager.current_slot = slot
	player.set_carry("suitcase" if not GameManager.has_flag("dropped_suitcase") else "")
	player.refresh_outfit()
	_begin_play()
	Events.say("已读取存档 %d：%s" % [slot, SaveManager.summary_now()], "good")


# ================================================================ 上班
func start_shift(job_id: String) -> void:
	var guest := ServiceRouter.guest_shift_available(job_id)
	var late := 0.0
	if not guest:
		var chk := JobManager.can_start_shift(job_id)
		if not bool(chk.get("ok", false)):
			Events.say(String(chk.get("reason", "")), "warn")
			return
		late = float(chk.get("late", 0.0))
	var job := DataDB.job(job_id)
	var diff := JobManager.level() if not guest else 0
	var kind := String(job.get("minigame", "cashier"))
	GameManager.in_minigame = true
	player.anim.state = AnimationController.State.WORK
	if kind == "carry":
		_start_carry(job_id, diff, late, guest)
		return
	var game: MinigameBase
	match kind:
		"cashier":
			game = CashierGame.new(diff)
		"serving":
			game = ServingGame.new(diff)
		"sorting":
			game = SortingGame.new(diff)
		"filing":
			game = FilingGame.new(diff)
		"code":
			game = CodeGame.new(diff)
		"analysis":
			game = AnalysisGame.new(diff)
		_:
			game = ManagementGame.new(diff)
	var w := MinigameWindow.new(game)
	w.finished.connect(func(score): _finish_shift(job_id, score, late, guest))
	ui.open(w)
	AudioManager.set_ambience(0, "office" if kind in ["filing", "code", "analysis", "management"] else "shop")


func _start_carry(job_id: String, diff: int, late: float, guest: bool) -> void:
	player.set_carry("")
	GameManager.set_flag("dropped_suitcase")
	carry_job = CarryJob.new()
	add_child(carry_job)
	carry_job.setup(city.carry_pile, city.carry_zone, diff)
	player.teleport(city.carry_pile + Vector3(3, 0.2, 3), 0.0)
	player.anim.state = AnimationController.State.IDLE
	Events.banner.emit("开工！", "在材料堆按 F 扛起材料，送到黄色卸货区按 F 放下")
	carry_job.finished.connect(func(score):
		_end_carry(true)
		_finish_shift(job_id, score, late, guest))


func _end_carry(_ok: bool) -> void:
	if carry_job != null and is_instance_valid(carry_job):
		carry_job.queue_free()
	carry_job = null
	if player != null:
		player.set_carry("")


func _finish_shift(job_id: String, score: float, late: float, guest: bool) -> void:
	GameManager.in_minigame = false
	player.anim.state = AnimationController.State.IDLE
	var r: Dictionary
	if guest:
		r = JobManager.finish_guest_shift(job_id, score)
	else:
		r = JobManager.finish_shift(score, late)
	_show_shift_result(r)
	_on_location(String(GameManager.get_value("current_location", "")))


func _show_shift_result(r: Dictionary) -> void:
	var lines: Array = []
	lines.append("小游戏成绩 %d · 效率 %d%% · 最终评分 %d" % [int(r["raw"]), int(float(r["eff"]) * 100), int(r["score"])])
	if bool(r.get("guest", false)):
		lines.append("帮忙顶班结束，报酬按任务结算。")
	else:
		if bool(r["late"]):
			lines.append("迟到了：工资 -10%，绩效 -4。")
		if bool(r["monthly"]):
			lines.append("本班工资 %s（累计到周五发薪）" % Fmt.yuan(int(r["pay"])))
		else:
			lines.append("日薪 %s 已发放现金" % Fmt.yuan(int(r["pay"])))
		if int(r["rain_bonus"]) > 0:
			lines.append("雨天补贴 %s" % Fmt.yuan(int(r["rain_bonus"])))
		lines.append("绩效 %d（%+.1f）" % [int(r["perf"]), float(r["perf_delta"])])
		if String(r["promoted"]) != "":
			lines.append("★ 升职为「%s」！" % String(r["promoted"]))
		if String(r["demoted"]) != "":
			lines.append("降职为「%s」……" % String(r["demoted"]))
		if bool(r["fired"]):
			lines.append("你被解雇了。")
	lines.append("现在 %s，下班了。" % TimeManager.clock_text())
	AudioManager.play_sfx("coin")
	ui.open(ChoiceWindow.new("下班 · %s" % String(r.get("title", "")), "\n".join(lines), [{"text": "收工", "cb": func(): EventManager.roll("shift_end")}], Vector2(600, 420)))


# ================================================================ 睡觉 / 昏倒
func sleep(minutes: float, bench := false) -> void:
	var before := EconomyManager.liquid()
	var quality := HousingManager.sleep_quality() if not bench else 0.45
	var mood_bonus := HousingManager.mood_bonus() if not bench else -10.0
	ui.story.begin(false)
	await ui.story.fade(true, 0.6).finished
	var start_day := TimeManager.day
	TimeManager.advance(minutes, "sleep")
	var gain := minutes / 60.0 * 13.0 * quality
	PlayerManager.change("energy", gain)
	if minutes >= 360.0:
		PlayerManager.change("mood", mood_bonus)
	if bench:
		PlayerManager.change("health", -6)
		PlayerManager.change("stress", 6)
	PlayerManager.rearm_collapse()
	Events.notify("sleep", {"where": HousingManager.home_id() if not bench else "bench"})
	# 旅馆：过了中午还没续住就算退房
	await get_tree().create_timer(0.4).timeout
	ui.story.fade(false, 0.8)
	ui.story.end()
	var new_day := TimeManager.day != start_day
	if new_day:
		SaveManager.save()
		var delta := EconomyManager.liquid() - before
		Events.banner.emit("第 %d 天 · %s" % [TimeManager.day, TimeManager.weekday_name()], "%s %s · %s%s" % [TimeManager.date_text(), TimeManager.clock_text(), WeatherManager.display_name(), "（已自动保存）"])
		if delta != 0:
			Events.say("睡觉期间资金变动 %s（房租 / 利息 / 分红 / 工资）" % Fmt.signed_yuan(delta), "info")
		if JobManager.has_job() and JobManager.is_workday():
			Events.say("今天要上班：%s" % JobManager.status_text(), "info")
		EventManager.roll("morning")
	else:
		Events.say("睡了 %s（体力 +%d）" % [Fmt.hours_text(minutes), int(gain)], "good")


func _on_collapsed(reason: String) -> void:
	if not GameManager.playing:
		return
	await get_tree().process_frame
	ui.close_all()
	GameManager.in_minigame = false
	_end_carry(false)
	ui.story.begin(false)
	await ui.story.fade(true, 0.8).finished
	if reason == "health":
		var bill := EconomyManager.charge(800, "医疗", "急诊住院")
		TimeManager.advance(8 * 60, "sleep")
		PlayerManager.set_stat("health", 45)
		PlayerManager.set_stat("energy", 60)
		PlayerManager.set_stat("hunger", 60)
		PlayerManager.change("mood", -15)
		var h := GameManager.location_front("hospital")
		if h != Vector3.INF:
			player.teleport(h, PI)
		ui.story.caption("你眼前一黑倒在了路边……醒来时已经躺在新澜第一医院。急诊费 %s。" % Fmt.yuan(bill))
	else:
		TimeManager.advance(6 * 60, "sleep")
		PlayerManager.set_stat("energy", 35)
		PlayerManager.change("mood", -12)
		PlayerManager.change("health", -8)
		ui.story.caption("你累得直接睡倒在地上……六个小时后才被路人叫醒。")
	await get_tree().create_timer(2.6).timeout
	PlayerManager.rearm_collapse()
	ui.story.fade(false, 0.8)
	ui.story.end()
	Events.say("要按时吃饭睡觉，身体是本钱！", "bad")


# ================================================================ 学习 / 公司 / 结局
func practice(skill: String, xp: int) -> void:
	if PlayerManager.energy < 12.0:
		Events.say("太累了，练不动", "warn")
		return
	TimeManager.advance(120, "study")
	PlayerManager.change("energy", -10)
	var got := xp * PlayerManager.efficiency()
	SkillManager.add_xp(skill, got, "练习")
	Events.notify("practice", {"skill": skill})
	Events.say("练习了两小时（%s经验 +%d）" % [DataDB.skill_name(skill), int(got)], "good")


func manage_company() -> void:
	if not BusinessManager.has_company():
		return
	if int(BusinessManager.company.get("boost_day", -1)) == TimeManager.day:
		ui.open(PhoneWindow.new("business"))
		Events.say("今天已经开过管理会了", "info")
		return
	var g := ManagementGame.new(clampi(BusinessManager.stage() - 1, 0, 3))
	g.company_mode = true
	GameManager.in_minigame = true
	var w := MinigameWindow.new(g)
	w.finished.connect(func(score):
		GameManager.in_minigame = false
		TimeManager.advance(180, "work")
		PlayerManager.change("energy", -12)
		PlayerManager.change("stress", 6)
		var msg := BusinessManager.boost_today(score)
		ui.open(ChoiceWindow.new("经营会议结束", "决策评分 %d。%s" % [int(score), msg], [{"text": "查看公司", "cb": func(): ui.open(PhoneWindow.new("business"))}, {"text": "好", "cb": Callable()}])))
	ui.open(w)


func rooftop() -> void:
	var got := EndingSystem.achieved()
	var ready := QuestManager.is_active("m7_rooftop") or (GameManager.infinite_mode and not got.is_empty())
	if got.is_empty() or not ready:
		TimeManager.advance(20)
		PlayerManager.change("mood", 5)
		PlayerManager.change("stress", -5)
		var txt := "霓虹灯一盏盏亮起，整座城市在脚下铺开。你想起刚下火车的那天。"
		if got.is_empty():
			txt += "\n\n（还没有达成任何人生目标。手机「人物」页可以查看五种人生目标。）"
		elif not ready:
			txt += "\n\n（完成主线「人生选择」后，就可以在这里迎来结局。）"
		ui.open(ChoiceWindow.new("观景台", txt, [{"text": "再看一会儿", "cb": Callable()}]))
		Events.notify("interact", {"target": "rooftop_view"})
		return
	var opts: Array = []
	for id in got:
		var e := EndingSystem.data(id)
		opts.append({"text": "回顾这段人生：%s%s" % [String(e.get("title", "")), "（推荐）" if id == EndingSystem.best() else ""], "cb": func(): play_ending(id)})
	opts.append({"text": "还没准备好", "cb": Callable()})
	ui.open(ChoiceWindow.new("观景台", "城市的灯火在你脚下流动。你已经走了很远的路。\n是时候回头看看了。", opts))


func play_ending(id: String) -> void:
	Events.notify("interact", {"target": "rooftop"})
	if not GameManager.endings_seen.has(id):
		GameManager.endings_seen.append(id)
	Events.ending_reached.emit(id)
	SaveManager.save()
	ui.show_ending(id)


func after_ending(action: String) -> void:
	GameManager.infinite_mode = true
	SaveManager.save()
	if action == "menu":
		go_to_menu()
	else:
		AudioManager.play_music("city")
		Events.banner.emit("无限人生", "你的故事还在继续。其他人生目标依然可以达成。")
		ui.capture_mouse()


func _on_quest_completed(id: String) -> void:
	if id == "m1_first_day":
		player.set_carry("")
		GameManager.set_flag("dropped_suitcase")
	var q := QuestManager.data(id)
	var nx := String(q.get("next", ""))
	if nx != "" and String(q.get("type", "")) == "main":
		var nq := QuestManager.data(nx)
		if int(nq.get("chapter", 0)) > int(q.get("chapter", 0)):
			var names := ["", "活下来", "第一份工作", "真正的职业", "选择方向", "职业发展", "财富积累", "人生选择"]
			var c := int(nq.get("chapter", 1))
			Events.banner.emit("第%s章 · %s" % ["一二三四五六七"[c - 1], names[c]], String(nq.get("desc", "")).left(40))


# ================================================================ 世界联动
func _on_location(id: String) -> void:
	if id == _last_loc:
		return
	_last_loc = id
	var t := String(DataDB.location(id).get("type", ""))
	var amb := "city"
	if id in ["office_tower", "tech_company", "finance_center", "bank", "training_school", "talent_market"]:
		amb = "office"
	elif t == "shop" or id == "mall":
		amb = "shop"
	AudioManager.set_ambience(0, amb)
	if id == "hotel" and not GameManager.has_flag("dropped_suitcase") and HousingManager.has_hotel_room():
		player.set_carry("")
		GameManager.set_flag("dropped_suitcase")


var _spawned: Array = []


func _clear_spawns() -> void:
	for n in _spawned:
		if is_instance_valid(n):
			n.queue_free()
	_spawned.clear()


func _refresh_spawns() -> void:
	var want := QuestManager.spawns()
	var keep: Array = []
	for n in _spawned:
		if is_instance_valid(n) and not n.is_queued_for_deletion():
			keep.append(n)
	_spawned = keep
	for s in want:
		var exists := false
		for n in _spawned:
			if String(n.item_id) == String(s["item"]):
				exists = true
		if exists:
			continue
		var ln := GameManager.lookup("loc:" + String(s["location"])) as LocationNode
		if ln == null:
			continue
		var p: Array = s["pos"]
		var qp := QuestPickup.new()
		add_child(qp)
		qp.setup(String(s["item"]), String(s["quest"]))
		qp.global_position = BuildingKit.xf(ln.frame, float(p[0]), 0.05, float(p[1]))
		_spawned.append(qp)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and GameManager.playing:
		SaveManager.save()


func _exit_tree() -> void:
	# 释放静态缓存（材质、主题、字体），避免退出时报资源泄漏
	Mats.clear()
	UIKit.clear_cache()
	AudioManager.shutdown()
