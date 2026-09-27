class_name PauseMenu
extends Control
## 暂停菜单（GDD.md 第三、四、十二节）：继续、视野角、灵敏度、反转 Y 轴、镜头摆动、操作说明。
## 打开时游戏暂停；本节点在暂停时照常处理输入。设置暂时只存在内存里（2.7 存档时存到浏览器）。

signal resume_requested

var panel: PanelContainer
var resume_btn: Button
var fov_slider: HSlider
var sens_slider: HSlider
var invert_check: CheckButton
var bob_check: CheckButton
var fov_value: Label
var sens_value: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.05, 0.08, 0.72)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("1c2a3a")
	sb.border_color = Color("b8964e")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var title := Label.new()
	title.text = "已暂停"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("e8dcc0"))
	box.add_child(title)
	resume_btn = Button.new()
	resume_btn.text = "继续游戏"
	resume_btn.pressed.connect(func(): resume_requested.emit())
	box.add_child(resume_btn)
	fov_value = Label.new()
	fov_slider = _slider(box, "视野角", fov_value, Settings.FOV_MIN, Settings.FOV_MAX, 1.0, Settings.fov, "fov")
	sens_value = Label.new()
	sens_slider = _slider(box, "转视角灵敏度", sens_value, Settings.SENS_MIN, Settings.SENS_MAX, 0.1, Settings.sensitivity, "sensitivity")
	invert_check = _check(box, "反转上下视角", Settings.invert_y, "invert_y")
	bob_check = _check(box, "走路时镜头摆动", Settings.head_bob, "head_bob")
	var help := Label.new()
	help.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	help.add_theme_color_override("font_color", Color("a9b4c0"))
	help.text = "电脑：点击画面锁定鼠标 · WASD 移动 · 鼠标转视角 · Shift 跑 · C 蹲下 / 站起 · 空格 跳 · Esc 暂停\n手机：左半屏拖动走路（推到底是跑）· 右半屏拖动转视角 · 右下角「跳」「蹲」"
	box.add_child(help)
	get_tree().root.size_changed.connect(_fit)
	_fit()
	_refresh_values()
	hide()


func open() -> void:
	show()
	resume_btn.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		resume_requested.emit()


func _slider(box: VBoxContainer, text: String, value_label: Label, lo: float, hi: float, step: float, v: float, key: String) -> HSlider:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = text
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	row.add_child(value_label)
	box.add_child(row)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = v
	s.custom_minimum_size.y = 28
	s.value_changed.connect(func(nv: float):
		Settings.set_value(key, nv)
		_refresh_values())
	box.add_child(s)
	return s


func _check(box: VBoxContainer, text: String, v: bool, key: String) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = v
	c.toggled.connect(func(on: bool): Settings.set_value(key, on))
	box.add_child(c)
	return c


func _refresh_values() -> void:
	fov_value.text = "%d°" % roundi(Settings.fov)
	sens_value.text = "%.1f 倍" % Settings.sensitivity


func _fit() -> void:
	var w := get_tree().root
	var logical := Vector2(w.size) / maxf(w.content_scale_factor, 0.01)
	panel.custom_minimum_size.x = clampf(logical.x - 32.0, 240.0, 440.0)
