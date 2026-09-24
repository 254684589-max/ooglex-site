class_name UIRoot
extends CanvasLayer
## 界面总管：创建所有界面、管理「模态」状态（对话 / 商店 / 菜单打开时暂停时间与操作）、
## 鼠标锁定、Tab / M / Esc 快捷键，并把菜单按钮转给 main.gd。

var main: Node
var root: Control
var hud: HUD
var touch: TouchControls
var toasts: Toasts
var tasks: TaskPanel
var site_map: SiteMap
var dialogue: DialogueBox
var shop: ShopPanel
var title: TitleScreen
var menus: Menus
var story: StoryOverlay

var _was_captured := false
var _menu_origin := ""


func setup(main_node: Node) -> void:
	main = main_node
	layer = 10
	root = Control.new()
	root.name = "Root"
	UIKit.full_rect(root)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UIKit.theme()
	add_child(root)
	hud = HUD.new()
	root.add_child(hud)
	touch = TouchControls.new()
	touch.player = GameState.player
	root.add_child(touch)
	toasts = Toasts.new()
	root.add_child(toasts)
	tasks = TaskPanel.new()
	root.add_child(tasks)
	site_map = SiteMap.new()
	root.add_child(site_map)
	dialogue = DialogueBox.new()
	root.add_child(dialogue)
	shop = ShopPanel.new()
	root.add_child(shop)
	title = TitleScreen.new()
	root.add_child(title)
	# 黑屏字幕在菜单下面：睡觉结算面板要显示在黑屏之上
	story = StoryOverlay.new()
	root.add_child(story)
	menus = Menus.new()
	root.add_child(menus)

	Events.dialogue_requested.connect(open_dialogue)
	Events.shop_requested.connect(open_shop)
	Events.bed_requested.connect(open_bed)
	dialogue.closed.connect(func(_id): _after_modal_closed())
	shop.closed.connect(_after_modal_closed)
	menus.action.connect(_on_menu_action)
	title.action.connect(_on_title_action)
	story.finished.connect(_after_modal_closed)
	_sync()


# ================================================================ 模态
func _sync() -> void:
	var n := 0
	for open in [dialogue.is_open(), shop.is_open(), menus.is_open(), story.is_playing(), title.visible]:
		if open:
			n += 1
	GameState.clear_modal()
	for i in n:
		GameState.push_modal()
	hud.visible = GameState.playing and not title.visible
	touch.visible = GameState.touch_mode and GameState.playing and not title.visible
	if n > 0:
		tasks.visible = false
		site_map.visible = false


func _after_modal_closed() -> void:
	_sync()
	if not GameState.is_modal():
		capture_mouse()


func capture_mouse() -> void:
	if GameState.playing and not GameState.is_modal() and not GameState.touch_mode:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func release_mouse() -> void:
	_was_captured = false
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(_delta: float) -> void:
	_sync()
	var want := GameState.playing and not GameState.is_modal() and not GameState.touch_mode
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


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if story.is_playing():
			return
		if dialogue.is_open() or shop.is_open():
			return
		if menus.is_open():
			_menu_back()
		elif GameState.playing and not title.visible:
			if tasks.visible or site_map.visible:
				tasks.visible = false
				site_map.visible = false
			else:
				open_pause()
		get_viewport().set_input_as_handled()
		return
	if not GameState.playing or GameState.is_modal():
		return
	if event.is_action_pressed("task_list"):
		site_map.visible = false
		tasks.toggle()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("site_map"):
		tasks.visible = false
		site_map.toggle()
		get_viewport().set_input_as_handled()


# ================================================================ 打开各界面
func open_dialogue(npc_id: String) -> void:
	release_mouse()
	dialogue.open(npc_id)
	_sync()


func open_shop(shop_id: String) -> void:
	release_mouse()
	shop.open(shop_id)
	_sync()


func open_bed() -> void:
	release_mouse()
	_menu_origin = "game"
	menus.show_bed()
	_sync()


func open_pause() -> void:
	release_mouse()
	_menu_origin = "game"
	menus.show_pause()
	_sync()


func show_title() -> void:
	release_mouse()
	menus.close()
	dialogue.close()
	shop.close()
	title.visible = true
	title.refresh()
	_sync()


func hide_title() -> void:
	title.visible = false
	_sync()


func enter_play() -> void:
	title.visible = false
	hud.refresh_all()
	_sync()
	capture_mouse()


func show_summary(data: Dictionary) -> void:
	release_mouse()
	_menu_origin = "sleep"
	menus.show_summary(data)
	_sync()


func close_all_modals() -> void:
	if dialogue.is_open():
		dialogue.close()
	if shop.is_open():
		shop.close()
	menus.close()
	_sync()


func _menu_back() -> void:
	match menus.current:
		"settings", "help":
			if _menu_origin == "title":
				menus.close()
			else:
				menus.show_pause()
		"summary":
			_on_menu_action("wake")
		"pause", "bed":
			menus.close()
			_after_modal_closed()
		_:
			menus.close()
			_after_modal_closed()
	_sync()


# ================================================================ 菜单动作
func _on_menu_action(act: String) -> void:
	match act:
		"resume", "close":
			menus.close()
			_after_modal_closed()
		"pause":
			menus.show_pause()
		"save":
			if SaveSystem.save_game():
				Events.say("已保存：%s" % SaveSystem.describe_save(), "good")
			else:
				Events.say("保存失败", "bad")
			menus.show_pause()
		"load":
			if SaveSystem.has_save():
				menus.close()
				main.continue_game()
			else:
				Events.say("还没有存档", "warn")
		"settings":
			menus.show_settings("pause" if _menu_origin != "title" else "close")
		"help":
			menus.show_help("pause" if _menu_origin != "title" else "close")
		"quality_changed":
			main.apply_quality()
		"title":
			menus.show_confirm("回到标题画面", "当前进度会先自动保存。", "title_yes", "pause")
		"title_yes":
			SaveSystem.save_game()
			menus.close()
			main.go_to_title()
		"exit_web":
			SaveSystem.save_game()
			if OS.has_feature("web"):
				JavaScriptBridge.eval("window.location.href = '/games/hub/';")
		"sleep_night":
			menus.close()
			main.sleep("night")
		"sleep_nap":
			menus.close()
			main.sleep("nap")
		"wake":
			menus.close()
			main.wake_up()
		"new_yes":
			menus.close()
			main.start_new_game()
	_sync()


func _on_title_action(act: String) -> void:
	match act:
		"continue":
			main.continue_game()
		"new":
			if SaveSystem.has_save():
				_menu_origin = "title"
				menus.show_confirm("开始新游戏", "会覆盖现在的存档（%s），确定吗？" % SaveSystem.describe_save(), "new_yes", "close")
			else:
				main.start_new_game()
		"help":
			_menu_origin = "title"
			menus.show_help("close")
	_sync()
