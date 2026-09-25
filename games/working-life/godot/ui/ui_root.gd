class_name UIRoot
extends CanvasLayer
## 界面总管：创建 HUD / 通知 / 触屏按钮 / 主菜单 / 剧情层，管理弹窗栈（任何窗口打开时暂停时间与操作）、
## 鼠标锁定、快捷键（Tab 手机、M 地图、I 背包、J 任务、C 人物、Esc 菜单、T 倍速、F1 调试），
## 响应各系统的界面请求，并在合适的时机弹出随机事件与手机短信。

var main: Node
var root: Control
var hud: HUD
var touch: TouchControls
var drive_hud: DriveHud
var toasts: Toasts
var menu: MainMenu
var story: StoryOverlay
var ending: EndingScreen
var carry_status: Label
var windows: Array = []
var _was_captured := false


func setup(main_node: Node) -> void:
	main = main_node
	layer = 10
	root = Control.new()
	root.name = "UI"
	UIKit.full_rect(root)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UIKit.theme()
	add_child(root)
	hud = HUD.new()
	hud.player = GameManager.player
	root.add_child(hud)
	drive_hud = DriveHud.new()
	drive_hud.hud = hud
	root.add_child(drive_hud)
	carry_status = UIKit.hud_label("", 22, UIKit.YELLOW)
	carry_status.set_anchors_preset(Control.PRESET_CENTER_TOP)
	carry_status.position = Vector2(-300, 90)
	carry_status.custom_minimum_size = Vector2(600, 0)
	carry_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(carry_status)
	touch = TouchControls.new()
	touch.player = GameManager.player
	root.add_child(touch)
	toasts = Toasts.new()
	root.add_child(toasts)
	story = StoryOverlay.new()
	root.add_child(story)
	menu = MainMenu.new()
	root.add_child(menu)
	menu.action.connect(_on_menu_action)
	Events.dialogue_requested.connect(func(id): open(DialogueWindow.new(id)))
	Events.shop_requested.connect(func(id): open(ShopWindow.new(id)))
	Events.interview_requested.connect(func(id): open(InterviewWindow.new(id)))
	Events.panel_requested.connect(_on_panel)
	Events.phone_message.connect(_on_message)
	_sync()


# ================================================================ 窗口栈
func open(w: Control) -> Control:
	root.add_child(w)
	# 通知层永远在最上面
	root.move_child(toasts, -1)
	windows.append(w)
	if w.has_signal("closed"):
		w.closed.connect(_on_window_closed.bind(w))
	release_mouse()
	_sync()
	return w


func _on_window_closed(w: Control) -> void:
	windows.erase(w)
	_sync()
	if not GameManager.is_modal():
		capture_mouse()


func top_window() -> Control:
	for i in range(windows.size() - 1, -1, -1):
		if is_instance_valid(windows[i]):
			return windows[i]
	return null


func has_window(id: String) -> bool:
	for w in windows:
		if is_instance_valid(w) and String(w.get("window_id")) == id:
			return true
	return false


func close_all() -> void:
	for w in windows.duplicate():
		if is_instance_valid(w):
			if w.has_method("force_close"):
				w.force_close()
			else:
				w.queue_free()
	windows.clear()
	_sync()


func _sync() -> void:
	for w in windows.duplicate():
		if not is_instance_valid(w):
			windows.erase(w)
	var n := windows.size()
	if menu.visible:
		n += 1
	if story.playing:
		n += 1
	if ending != null and is_instance_valid(ending):
		n += 1
	GameManager.modal_count = n
	var in_game := GameManager.playing and not menu.visible and (ending == null or not is_instance_valid(ending))
	hud.visible = in_game and not story.playing
	touch.visible = GameManager.touch_mode and in_game and not story.playing
	carry_status.visible = in_game


func capture_mouse() -> void:
	if GameManager.playing and not GameManager.is_modal() and not GameManager.touch_mode:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func release_mouse() -> void:
	_was_captured = false
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(_delta: float) -> void:
	_sync()
	var want := GameManager.playing and not GameManager.is_modal() and not GameManager.touch_mode
	if want:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			_was_captured = true
			hud.set_hint("")
		else:
			if _was_captured:
				# 浏览器里按 Esc 会直接解除鼠标锁定：当作打开暂停菜单
				_was_captured = false
				open_pause()
			else:
				hud.set_hint("点击画面，用鼠标控制视角")
	else:
		hud.set_hint("")
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			release_mouse()
		_was_captured = false
	var cj = main.get("carry_job")
	carry_status.text = cj.status_text() if cj != null and is_instance_valid(cj) else ""
	# 随机事件：没有窗口、不在小游戏时才弹出
	if GameManager.playing and not GameManager.is_modal() and not GameManager.in_minigame and not EventManager.queue.is_empty():
		_show_event(EventManager.pop_next())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		if story.playing or menu.visible:
			return
		var w := top_window()
		if w != null:
			if w.has_method("close"):
				w.close()
			return
		if GameManager.playing:
			open_pause()
		return
	if event.is_action_pressed("debug") and GameManager.debug_enabled and GameManager.playing and not has_window("debug"):
		open(DebugPanel.new())
		get_viewport().set_input_as_handled()
		return
	# 快捷键：再按一次关闭同一个窗口
	var hot := {"phone": "phone", "map": "map", "inventory": "inventory", "quests": "quests", "character": "character"}
	for act in hot:
		if event.is_action_pressed(act):
			var w2 := top_window()
			if w2 != null and String(w2.get("window_id")) == hot[act]:
				w2.close()
				get_viewport().set_input_as_handled()
				return
	if not GameManager.can_act():
		return
	if event.is_action_pressed("phone"):
		open(PhoneWindow.new(""))
	elif event.is_action_pressed("map"):
		open(CityMapWindow.new())
	elif event.is_action_pressed("inventory"):
		open(ViewWindow.new("背包", func(b, r): InventoryView.build(b, r, false), Vector2(700, 580), "inventory"))
	elif event.is_action_pressed("quests"):
		open(ViewWindow.new("任务", func(b, r): QuestsView.build(b, r), Vector2(760, 620), "quests"))
	elif event.is_action_pressed("character"):
		open(ViewWindow.new("人物", func(b, r): ProfileView.build(b, r), Vector2(760, 640), "character"))
	elif event.is_action_pressed("time_speed"):
		TimeManager.speed = 2 if TimeManager.speed == 1 else 1
		SettingsManager.set_v("time_speed", TimeManager.speed)
		Events.say("时间：%d 倍速" % TimeManager.speed, "info")
	else:
		return
	get_viewport().set_input_as_handled()


# ================================================================ 界面请求
func _on_panel(id: String, args: Dictionary) -> void:
	match id:
		"_window":
			open(args["window"])
		"phone":
			open(PhoneWindow.new(String(args.get("app", ""))))
		"date":
			open(DateWindow.new(String(args.get("npc", ""))))
		"map":
			open(CityMapWindow.new())
		"courses":
			open(CoursesWindow.new())
		"travel":
			open(TravelWindow.new(String(args.get("mode", "bus"))))
		"settings":
			open_settings()
		"shift":
			main.start_shift(String(args.get("job", "")))
		"hotel":
			_hotel()
		"sleep":
			_sleep_menu(bool(args.get("bench", false)))
		"wardrobe":
			open(ViewWindow.new("衣柜 · 储物柜", _wardrobe_view, Vector2(720, 600), "wardrobe"))
		"computer":
			_computer()
		"rooftop":
			main.rooftop()
		"manage_company":
			main.manage_company()


func _hotel() -> void:
	var price := HousingManager.rent_of("hotel")
	var info := "前台阿姨：「单人间 %s 一晚，退房时间中午 12 点。」" % Fmt.yuan(price)
	if HousingManager.has_hotel_room():
		info += "\n你的房间有效到第 %d 天中午。" % (int(HousingManager.hotel_until / 1440.0) + 1)
	open(ChoiceWindow.new("安心旅馆 · 前台", info, [
		{"text": "住一晚（%s）" % Fmt.yuan(price), "cb": func(): Events.say(HousingManager.book_hotel(1), "info")},
		{"text": "连住 7 晚（%s）" % Fmt.yuan(price * 7), "cb": func(): Events.say(HousingManager.book_hotel(7), "info")},
		{"text": "算了", "cb": Callable()},
	]))


func _sleep_menu(bench: bool) -> void:
	var h := TimeManager.hour_f()
	var opts: Array = []
	var until7 := TimeManager.minutes_until(7.0)
	var quality := HousingManager.sleep_quality() if not bench else 0.45
	var where := "长椅上" if bench else HousingManager.home_name()
	if h >= 19.0 or h < 5.0 or bench:
		opts.append({"text": "睡到早上 7:00（%s）" % Fmt.hours_text(until7), "cb": func(): main.sleep(until7, bench)})
	opts.append({"text": "睡 8 小时", "cb": func(): main.sleep(480.0, bench)})
	if not bench:
		opts.append({"text": "小睡 2 小时", "cb": func(): main.sleep(120.0, bench)})
		opts.append({"text": "保存游戏（存档 %d）" % SaveManager.current_slot, "cb": func():
			Events.say("已保存到存档 %d" % SaveManager.current_slot if SaveManager.save() else "保存失败", "good")})
	opts.append({"text": "不睡了", "cb": Callable()})
	open(ChoiceWindow.new("睡觉", "在%s休息。睡眠恢复效率 %d%%。睡醒后会自动保存。" % [where, int(quality * 100)], opts))


func _wardrobe_view(box: VBoxContainer, refresh: Callable) -> void:
	box.add_child(UIKit.label("换衣服（着装影响面试与心情）", 18, UIKit.CYAN))
	var any := false
	for id in PlayerManager.owned:
		var it := DataDB.item(String(id))
		if String(it.get("use", "")) != "outfit":
			continue
		any = true
		var h := UIKit.hbox(8)
		box.add_child(h)
		var l := UIKit.label("%s（面试 +%d）%s" % [String(it["name"]), int(it.get("interview", 0)), "　← 穿着" if String(id) == PlayerManager.outfit else ""], 16, UIKit.TEXT)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		h.add_child(UIKit.small_button("穿上", func():
			PlayerManager.set_outfit(String(id))
			PlayerManager.change("mood", float(it.get("mood", 0)))
			refresh.call()))
	if not any:
		box.add_child(UIKit.label("只有身上这套旧衣服。超市和霓虹广场服装店可以买新衣服。", 15, UIKit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
	box.add_child(UIKit.small_button("换回旧衣服", func():
		PlayerManager.set_outfit("")
		refresh.call()))
	box.add_child(UIKit.sep())
	InventoryView.build(box, refresh, true)


func _computer() -> void:
	var has_laptop := PlayerManager.owned.has("laptop")
	var xp := 40 if has_laptop else 20
	open(ChoiceWindow.new("电脑", "家里的旧电脑%s。练习会消耗体力和 2 小时。" % ("，外加你的新笔记本" if has_laptop else "（买台笔记本电脑，练习效果翻倍）"), [
		{"text": "练习编程（电脑经验 +%d）" % xp, "cb": func(): main.practice("computer", xp)},
		{"text": "研究市场与财报（金融经验 +%d）" % xp, "cb": func(): main.practice("finance", xp)},
		{"text": "看管理课程视频（管理经验 +%d）" % int(xp * 0.8), "cb": func(): main.practice("management", int(xp * 0.8))},
		{"text": "打开招聘网站", "cb": func(): open(PhoneWindow.new("jobs"))},
		{"text": "打开投资软件", "cb": func(): open(PhoneWindow.new("invest"))},
		{"text": "打开公司后台", "cb": func(): open(PhoneWindow.new("business"))},
		{"text": "追一集剧（1 小时，心情 +8 压力 -8）", "cb": func():
			TimeManager.advance(60)
			PlayerManager.change("mood", 8)
			PlayerManager.change("stress", -8)
			Events.say("看完一集《霓虹之下》，心情好多了", "good")},
		{"text": "关机", "cb": Callable()},
	]))


func _show_event(id: String) -> void:
	if id == "":
		return
	var e: Dictionary = DataDB.events.get(id, {})
	var choices: Array = e.get("choices", [])
	var opts: Array = []
	if choices.is_empty():
		var result := EventManager.resolve(id, -1)
		opts.append({"text": "知道了", "cb": Callable()})
		open(ChoiceWindow.new("事件 · " + String(e.get("title", "")), String(e.get("text", "")) + "\n\n" + result, opts, Vector2(640, 420)))
		AudioManager.play_sfx("message")
		return
	for i in choices.size():
		var c: Dictionary = choices[i]
		var ok := EventManager.choice_available(c)
		opts.append({"text": String(c.get("text", "")) + ("" if ok else "（条件不足）"), "enabled": ok, "cb": func():
			var r := EventManager.resolve(id, i)
			open(ChoiceWindow.new(String(e.get("title", "")), r, [{"text": "好", "cb": Callable()}], Vector2(560, 320)))})
	open(ChoiceWindow.new("事件 · " + String(e.get("title", "")), String(e.get("text", "")), opts, Vector2(640, 440)))
	AudioManager.play_sfx("message")


func _on_message(from: String, text: String) -> void:
	var msgs: Array = GameManager.get_value("messages", [])
	msgs.append({"from": from, "text": text, "day": TimeManager.day, "time": TimeManager.clock_text()})
	while msgs.size() > 40:
		msgs.pop_front()
	GameManager.set_value("messages", msgs)
	GameManager.set_value("unread_messages", int(GameManager.get_value("unread_messages", 0)) + 1)
	if GameManager.playing and not story.playing:
		Events.say("短信 · %s：%s" % [from, text.left(36) + ("…" if text.length() > 36 else "")], "info")
		AudioManager.play_sfx("message", -6.0)


# ================================================================ 菜单
func open_pause() -> void:
	if not GameManager.playing:
		return
	var opts := [
		{"text": "继续游戏", "cb": Callable()},
		{"text": "保存游戏", "cb": func(): _slots("save")},
		{"text": "读取存档", "cb": func(): _slots("load")},
		{"text": "设置", "cb": open_settings},
		{"text": "操作说明", "cb": _help},
		{"text": "回到主菜单（自动保存）", "cb": func():
			SaveManager.save()
			main.go_to_menu()},
	]
	if not OS.has_feature("web"):
		opts.append({"text": "保存并退出游戏", "cb": func():
			SaveManager.save()
			get_tree().quit()})
	var w := ChoiceWindow.new("暂停", "第 %d 天 %s · 存档 %d" % [TimeManager.day, TimeManager.clock_text(), SaveManager.current_slot], opts, Vector2(480, 520))
	w.window_id = "pause"
	open(w)


func _help() -> void:
	open(ChoiceWindow.new("操作说明", "WASD 移动 · Shift 奔跑（耗体力）· 空格 跳跃 · 鼠标 转视角（先点一下画面）· 滚轮 远近\nE 交互 / 对话 · F 使用 / 拿起 / 放下 · 鼠标左键 执行当前动作\nTab 手机 · M 地图 · I 背包 · J 任务 · C 人物 · T 时间倍速 · Esc 暂停 / 关闭窗口\n\n玩法：找工作 → 按时上班（小游戏评分）→ 领工资 → 吃饭睡觉交房租 → 上课读书练技能 → 跳槽升职 → 结交朋友 → 投资或创业 → 达成人生目标。\n\n手机「人物」页可以看到上班时间、升职条件和五种人生目标。", [{"text": "明白了", "cb": Callable()}], Vector2(760, 520)))


func open_settings() -> void:
	var s := SettingsWindow.new()
	s.quality_changed.connect(func(): main.apply_quality())
	open(s)


func _slots(mode: String) -> void:
	var w := SaveSlotsWindow.new(mode)
	w.slot_chosen.connect(func(slot): _on_slot(mode, slot))
	open(w)


func _on_slot(mode: String, slot: int) -> void:
	match mode:
		"save":
			Events.say("已保存到存档 %d" % slot if SaveManager.save(slot) else "保存失败", "good")
		"load":
			close_all()
			main.load_slot(slot)
		"new":
			main.start_new_game(slot)


func _on_menu_action(id: String) -> void:
	match id:
		"continue":
			var s := SaveManager.latest_slot()
			if s > 0:
				main.load_slot(s)
		"new":
			_slots("new")
		"load":
			_slots("load")
		"settings":
			open_settings()
		"credits":
			open(CreditsWindow.new())
		"quit":
			if OS.has_feature("web"):
				JavaScriptBridge.eval("window.location.href = '/games/hub/';")
			else:
				get_tree().quit()


func show_menu() -> void:
	close_all()
	menu.visible = true
	menu.refresh()
	release_mouse()
	_sync()


func hide_menu() -> void:
	menu.visible = false
	_sync()


func show_ending(id: String) -> void:
	close_all()
	ending = EndingScreen.new()
	ending.setup(id)
	root.add_child(ending)
	root.move_child(toasts, -1)
	release_mouse()
	ending.action.connect(func(a):
		ending.queue_free()
		ending = null
		_sync()
		main.after_ending(a))
	_sync()
