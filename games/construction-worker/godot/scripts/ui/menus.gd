class_name Menus
extends Control
## 全屏 / 居中的菜单集合：暂停菜单、设置、操作说明、床铺菜单、每日结算、确认框。
## 统一用一个居中面板，内容按需要重建。

signal action(name: String)

var _dim: ColorRect
var _panel: PanelContainer
var _body: VBoxContainer
var current := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	UIKit.full_rect(self)
	visible = false
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.55)
	UIKit.full_rect(_dim)
	add_child(_dim)
	var center := CenterContainer.new()
	UIKit.full_rect(center)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_panel = UIKit.panel(Color(0.06, 0.065, 0.08, 0.97), 14, 24)
	center.add_child(_panel)
	_body = UIKit.vbox(10)
	_panel.add_child(_body)


func is_open() -> bool:
	return visible


func close() -> void:
	visible = false
	current = ""


func _begin(name_id: String, title: String, width := 420.0) -> void:
	current = name_id
	visible = true
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	_panel.custom_minimum_size = Vector2(clampf(get_viewport_rect().size.x - 40.0, 300.0, width), 0)
	if title != "":
		_body.add_child(UIKit.label(title, 26, UIKit.YELLOW, HORIZONTAL_ALIGNMENT_CENTER))


func _btn(text: String, act: String) -> Button:
	var b := UIKit.button(text, func(): action.emit(act))
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(b)
	return b


func _text(text: String, size := 17, col := UIKit.TEXT) -> Label:
	var l := UIKit.label(text, size, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(l)
	return l


func _focus_first() -> void:
	for c in _body.get_children():
		if c is Button:
			(c as Button).grab_focus()
			return


# ================================================================ 暂停菜单
func show_pause() -> void:
	_begin("pause", "暂停")
	_text("第 %d 天 %s · 现金 ¥%d" % [TimeSystem.day, TimeSystem.clock_text(), EconomySystem.cash], 16, UIKit.DIM)
	_btn("继续游戏", "resume")
	_btn("保存游戏", "save")
	_btn("读取存档", "load")
	_btn("设置", "settings")
	_btn("操作说明", "help")
	_btn("回到标题画面", "title")
	if OS.has_feature("web"):
		_btn("返回 Ooglex 游戏中心", "exit_web")
	_focus_first()


# ================================================================ 设置
func show_settings(back_to: String) -> void:
	_begin("settings", "设置", 460.0)
	var s := GameState.settings
	var row := UIKit.hbox(10)
	_body.add_child(row)
	row.add_child(UIKit.label("镜头灵敏度", 17))
	var slider := HSlider.new()
	slider.min_value = 0.3
	slider.max_value = 2.5
	slider.step = 0.1
	slider.value = float(s.get("mouse_sensitivity", 1.0))
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size.x = 160
	var val := UIKit.label("%.1f" % slider.value, 17, UIKit.YELLOW)
	slider.value_changed.connect(func(v):
		GameState.settings["mouse_sensitivity"] = v
		val.text = "%.1f" % v
		GameState.save_settings())
	row.add_child(slider)
	row.add_child(val)
	_check("镜头上下反转", "invert_y")
	_check("阴影（关闭可提升帧率）", "shadows")
	_check("抗锯齿（关闭可提升帧率）", "msaa")
	_check("目标指引箭头", "guide")
	if not GameState.touch_mode or OS.has_feature("web"):
		var fs := CheckButton.new()
		fs.text = "全屏"
		fs.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		fs.toggled.connect(func(on): DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED))
		_body.add_child(fs)
	_btn("返回", back_to)
	_focus_first()


func _check(text: String, key: String) -> void:
	var cb := CheckButton.new()
	cb.text = text
	cb.button_pressed = bool(GameState.settings.get(key, false))
	cb.toggled.connect(func(on):
		GameState.settings[key] = on
		GameState.save_settings()
		action.emit("quality_changed"))
	_body.add_child(cb)


# ================================================================ 操作说明
func show_help(back_to: String) -> void:
	_begin("help", "操作说明", 620.0)
	var rows := [
		["WASD / 方向键", "移动"],
		["Shift", "奔跑（消耗体力；扛太重时跑不动）"],
		["鼠标", "转动视角（先点一下画面锁定鼠标）"],
		["空格", "跳跃"],
		["E", "交互 / 对话 / 开门 / 买东西 / 睡觉"],
		["F", "拿起材料 / 在卸货区放下 / 放在地上"],
		["鼠标左键", "施工、在卸货区放下材料"],
		["鼠标右键（按住）", "拉近镜头，精确对准"],
		["滚轮", "镜头远近"],
		["1 ~ 5", "切换工具（徒手、劳保手套……）"],
		["Tab", "任务与成长面板"],
		["M", "工地图"],
		["Esc", "暂停菜单 / 关闭窗口"],
	]
	if GameState.touch_mode:
		rows = [
			["左下摇杆", "移动（推到底会走得更快）"],
			["右半屏拖动", "转动视角"],
			["交互", "对话 / 开门 / 买东西 / 睡觉"],
			["拿/放", "拿起材料 / 在卸货区放下"],
			["跑", "切换奔跑"],
			["跳", "跳跃"],
			["任务 / 地图 / 菜单", "右上角按钮"],
		]
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 6)
	_body.add_child(grid)
	for r in rows:
		grid.add_child(UIKit.label(String(r[0]), 17, UIKit.YELLOW))
		var d := UIKit.label(String(r[1]), 17)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size.x = 260
		grid.add_child(d)
	_text("玩法：找工头老王接活 → 去材料区拿材料 → 送进黄框卸货区 → 拿工资 → 吃饭喝水 → 回宿舍睡觉，第二天继续。搬得越多，一次能拿得越多。", 15, UIKit.DIM)
	_btn("返回", back_to)
	_focus_first()


# ================================================================ 床铺
func show_bed() -> void:
	_begin("bed", "你的床铺")
	if TimeSystem.can_sleep():
		_text("忙了一天，该睡了。睡一觉体力全满，醒来就是第 %d 天早上 6 点。" % (TimeSystem.day + 1))
		_btn("睡觉（进入第二天）", "sleep_night")
	else:
		_text("现在才 %s。白天睡到明天，今天剩下的活就干不了了。" % TimeSystem.clock_text())
		_btn("小睡一小时（体力 +40）", "sleep_nap")
		_btn("直接睡到明天早上", "sleep_night")
	_btn("算了，不睡", "close")
	_focus_first()


# ================================================================ 每日结算
func show_summary(data: Dictionary) -> void:
	_begin("summary", "第 %d 天 · 收工" % int(data.get("day", 1)))
	_text("今日收入　¥%d" % int(data.get("income", 0)), 20, UIKit.GOOD)
	_text("今日支出　¥%d" % int(data.get("expense", 0)), 20, UIKit.TEXT)
	_text("完成任务　%d 项" % int(data.get("tasks", 0)), 20, UIKit.TEXT)
	_text("现在现金　¥%d" % EconomySystem.cash, 22, UIKit.YELLOW)
	var note := String(data.get("note", ""))
	if note != "":
		_text(note, 16, UIKit.DIM)
	_text("进度已自动保存。", 15, UIKit.DIM)
	_btn("起床干活 →（第 %d 天）" % TimeSystem.day, "wake")
	_focus_first()


# ================================================================ 确认框
func show_confirm(title: String, text: String, yes_action: String, back_action: String) -> void:
	_begin("confirm", title)
	_text(text)
	_btn("确定", yes_action)
	_btn("取消", back_action)
	_focus_first()
