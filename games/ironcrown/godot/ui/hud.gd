class_name Hud
extends Control
## 平视显示（GDD.md 第十一节）：左上标题（标注占位）、屏幕中央准星、操作提示、右上「菜单」按钮；
## 1.3 起：准星下方的交互提示、屏幕上方的短提示（拾取、门锁着）、底部的 NPC 字幕。

signal menu_pressed

const TITLE := "铁冠之争 · 灰盒原型（占位几何体）"

var title_label: Label
var hint_label: Label
var menu_btn: Button
var prompt_label: Label
var toast_label: Label
var subtitle_panel: PanelContainer
var subtitle_label: Label
var toast_left := 0.0
var subtitle_left := 0.0
var key_hint := "[E] "        # 触屏上不显示按键


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_label = Label.new()
	title_label.text = TITLE
	title_label.position = Vector2(16, 12)
	title_label.add_theme_font_size_override("font_size", 18)
	title_label.add_theme_color_override("font_color", Color("e8dcc0"))
	add_child(title_label)
	hint_label = Label.new()
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	hint_label.add_theme_color_override("font_color", Color("e8dcc0"))
	hint_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	hint_label.add_theme_constant_override("outline_size", 6)
	add_child(hint_label)
	menu_btn = Button.new()
	menu_btn.text = "菜单"
	menu_btn.focus_mode = Control.FOCUS_NONE
	menu_btn.pressed.connect(func(): menu_pressed.emit())
	add_child(menu_btn)
	prompt_label = _center_label(20)
	toast_label = _center_label(18)
	subtitle_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.06, 0.09, 0.82)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(12)
	subtitle_panel.add_theme_stylebox_override("panel", sb)
	subtitle_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	subtitle_label = Label.new()
	subtitle_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	subtitle_label.add_theme_color_override("font_color", Color("e8dcc0"))
	subtitle_panel.add_child(subtitle_label)
	subtitle_panel.hide()
	add_child(subtitle_panel)
	resized.connect(_layout)
	_layout()


func _center_label(fs: int) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", Color("e8dcc0"))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


## 准星下方的交互提示；空字符串 = 隐藏
func show_prompt(text: String) -> void:
	prompt_label.text = (key_hint + text) if text != "" else ""
	_layout()


func toast(text: String, sec := 2.5) -> void:
	toast_label.text = text
	toast_left = sec
	_layout()


func say(text: String, sec := 4.5) -> void:
	subtitle_label.text = text
	subtitle_left = sec
	subtitle_panel.show()
	_layout()


func _process(delta: float) -> void:
	if toast_left > 0.0:
		toast_left -= delta
		if toast_left <= 0.0:
			toast_label.text = ""
	if subtitle_left > 0.0:
		subtitle_left -= delta
		if subtitle_left <= 0.0:
			subtitle_panel.hide()


func set_hint(text: String) -> void:
	hint_label.text = text
	_layout()


func _layout() -> void:
	menu_btn.position = Vector2(size.x - menu_btn.size.x - 12.0, 10.0)
	var w := minf(size.x - 32.0, 760.0)
	hint_label.size = Vector2(w, 0)
	hint_label.position = Vector2((size.x - w) * 0.5, size.y * 0.62)
	for l in [prompt_label, toast_label]:
		l.size = Vector2(w, 0)
	prompt_label.position = Vector2((size.x - w) * 0.5, size.y * 0.5 + 18.0)
	toast_label.position = Vector2((size.x - w) * 0.5, size.y * 0.2)
	var sw := minf(size.x - 32.0, 640.0)
	# 自动换行的 Label 必须先给定宽度，否则按 0 宽度排版，字幕框变得很高却看不到字
	subtitle_label.custom_minimum_size = Vector2(sw - 24.0, 0)
	subtitle_panel.custom_minimum_size = Vector2(sw, 0)
	subtitle_panel.reset_size()
	subtitle_panel.position = Vector2((size.x - sw) * 0.5, size.y * 0.72)
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	draw_circle(c, 3.0, Color(0, 0, 0, 0.6))
	draw_circle(c, 2.0, Color("e8dcc0"))
