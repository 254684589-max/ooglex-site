class_name DevTools
extends Node
## 开发者快捷键（给开发、调试、截图用，正式玩家看不到）。
## 只在以下情况开启：在 Godot 编辑器里运行（调试版），或网页地址带 ?dev=1。
##
##   F6  依次传送到：老王 → 砖堆 → 砌筑作业面 → 水泥库 → 上料点 → 钢筋堆场 → 绑扎区 → 食堂 → 小卖部 → 宿舍床铺
##   F7  时间 +1 小时
##   F8  直接完成当前任务
##   F9  体力 / 饥饿 / 水分回满，现金 +100
##   F5  回到工地大门口
##   F10 隐藏 / 显示全部界面（截图用）
## 网页地址加 &quiet=1 时不显示通知条与横幅（截图用）。
## 网页地址再加 &fps=1 时左上角显示帧率与绘制调用数（编辑器里默认显示）。

const WAYPOINTS := [
	["npc_wang", Vector3(1.5, 0.1, 0.0), -PI * 0.5],
	["pile_brick", Vector3(0.0, 0.1, -3.7), PI],
	["brick_zone", Vector3(0.0, 0.1, 0.4), PI],
	["pile_cement", Vector3(0.0, 0.1, -3.3), PI],
	["cement_zone", Vector3(0.0, 0.1, 0.0), 0.0],
	["pile_rebar", Vector3(0.0, 0.1, 6.9), 0.0],
	["rebar_zone", Vector3(0.0, 0.1, 0.0), 0.0],
	["shop_canteen", Vector3(0.0, 0.1, -0.5), PI],
	["shop_store", Vector3(0.0, 0.1, -0.2), PI],
	["bed_player", Vector3(0.7, 0.1, -1.1), PI],
]

var enabled := false
var _wp := -1
var _stats: Label


func _ready() -> void:
	enabled = OS.is_debug_build()
	if OS.has_feature("web"):
		var search = JavaScriptBridge.eval("window.location.search", true)
		enabled = typeof(search) == TYPE_STRING and String(search).contains("dev=1")
	var show_fps := OS.is_debug_build() and not OS.has_feature("web")
	if OS.has_feature("web") and enabled:
		show_fps = String(JavaScriptBridge.eval("window.location.search", true)).contains("fps=1")
	if enabled:
		print("DevTools: F5 回大门 · F6 传送 · F7 +1 小时 · F8 完成任务 · F9 回满状态 · F10 隐藏界面")
		if OS.has_feature("web") and String(JavaScriptBridge.eval("window.location.search", true)).contains("quiet=1"):
			var ui = get_parent().get_node_or_null("UI")
			if ui != null and "toasts" in ui and ui.toasts != null:
				ui.toasts.visible = false
	if enabled and show_fps:
		var layer := CanvasLayer.new()
		layer.layer = 50
		add_child(layer)
		_stats = Label.new()
		_stats.position = Vector2(8, 4)
		_stats.add_theme_font_size_override("font_size", 13)
		_stats.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
		_stats.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		_stats.add_theme_constant_override("outline_size", 4)
		layer.add_child(_stats)


func _process(_delta: float) -> void:
	if _stats != null:
		_stats.text = "FPS %d · 绘制 %d · 物体 %d" % [
			Engine.get_frames_per_second(),
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		]


func _unhandled_input(event: InputEvent) -> void:
	if not enabled or not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_F10:
		_toggle_ui()
		get_viewport().set_input_as_handled()
		return
	if not GameState.playing:
		return
	match event.keycode:
		KEY_F5:
			var main := get_parent()
			if "info" in main and GameState.player != null:
				GameState.player.teleport(main.info["spawn"], main.info["spawn_yaw"])
		KEY_F6:
			_teleport_next()
		KEY_F7:
			TimeSystem.advance(60.0)
			Events.say("[开发] 时间 +1 小时 → %s" % TimeSystem.clock_text(), "info")
		KEY_F8:
			var t := TaskSystem.get_active()
			if t != null:
				for o in t.objectives:
					TaskSystem.notify(String(o.get("type", "")), {"item": o.get("item", ""), "zone": o.get("zone", ""), "count": int(o.get("count", 1))})
				Events.say("[开发] 已完成当前任务", "info")
		KEY_F9:
			PlayerStats.change_stamina(100.0)
			PlayerStats.change_hunger(100.0)
			PlayerStats.change_thirst(100.0)
			EconomySystem.earn(100, "开发调试")
		_:
			return
	get_viewport().set_input_as_handled()


func _toggle_ui() -> void:
	var ui = get_parent().get_node_or_null("UI")
	if ui != null:
		ui.visible = not ui.visible
	GameState.settings["guide"] = ui == null or ui.visible


func _teleport_next() -> void:
	var p := GameState.player
	if p == null:
		return
	_wp = (_wp + 1) % WAYPOINTS.size()
	var w: Array = WAYPOINTS[_wp]
	var node := GameState.lookup(String(w[0]))
	if node == null:
		return
	p.teleport(node.global_position + (w[1] as Vector3), float(w[2]))
	Events.say("[开发] 传送到：%s" % String(w[0]), "info")
