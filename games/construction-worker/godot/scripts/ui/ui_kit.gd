class_name UIKit
extends RefCounted
## 界面工具：主题、常用控件的快捷创建。所有界面都用代码搭建，方便直接改。

const FONT_PATH := "res://assets/fonts/NotoSansSC-CW.ttf"
const YELLOW := Color(1.0, 0.8, 0.16)
const TEXT := Color(0.95, 0.95, 0.94)
const DIM := Color(0.7, 0.72, 0.76)
const GOOD := Color(0.45, 0.9, 0.5)
const WARN := Color(1.0, 0.72, 0.25)
const BAD := Color(1.0, 0.42, 0.38)
const PANEL_BG := Color(0.07, 0.075, 0.09, 0.84)

static var _theme: Theme


static func font() -> Font:
	return load(FONT_PATH)


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 18
	var panel := _box(PANEL_BG, 10, Color(1, 1, 1, 0.08), 1)
	panel.content_margin_left = 14
	panel.content_margin_right = 14
	panel.content_margin_top = 10
	panel.content_margin_bottom = 10
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)
	var normal := _box(Color(0.17, 0.18, 0.21, 0.96), 8, Color(1, 1, 1, 0.14), 1)
	var hover := _box(Color(0.98, 0.76, 0.14, 1.0), 8, Color(1, 0.9, 0.5, 1), 1)
	var pressed := _box(Color(0.86, 0.62, 0.06, 1.0), 8, Color(1, 0.9, 0.5, 1), 1)
	var focus := _box(Color(0, 0, 0, 0), 8, YELLOW, 2)
	var disabled := _box(Color(0.12, 0.12, 0.14, 0.75), 8, Color(1, 1, 1, 0.05), 1)
	for sb in [normal, hover, pressed, focus, disabled]:
		sb.content_margin_left = 16
		sb.content_margin_right = 16
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("hover_pressed", "Button", pressed)
	t.set_stylebox("focus", "Button", focus)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color(0.08, 0.07, 0.05))
	t.set_color("font_pressed_color", "Button", Color(0.08, 0.07, 0.05))
	t.set_color("font_hover_pressed_color", "Button", Color(0.08, 0.07, 0.05))
	t.set_color("font_focus_color", "Button", TEXT)
	t.set_color("font_disabled_color", "Button", Color(0.5, 0.5, 0.52))
	t.set_color("font_color", "Label", TEXT)
	t.set_constant("outline_size", "Label", 0)
	var bar_bg := _box(Color(0.0, 0.0, 0.0, 0.5), 5, Color(1, 1, 1, 0.1), 1)
	var bar_fill := _box(YELLOW, 5)
	t.set_stylebox("background", "ProgressBar", bar_bg)
	t.set_stylebox("fill", "ProgressBar", bar_fill)
	t.set_color("font_color", "CheckButton", TEXT)
	t.set_color("font_hover_color", "CheckButton", YELLOW)
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_color("font_hover_color", "CheckBox", YELLOW)
	var sep := StyleBoxLine.new()
	sep.color = Color(1, 1, 1, 0.12)
	sep.thickness = 1
	t.set_stylebox("separator", "HSeparator", sep)
	_theme = t
	return t


static func _box(bg: Color, radius := 8, border := Color(0, 0, 0, 0), border_w := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	if border_w > 0:
		sb.border_color = border
		sb.set_border_width_all(border_w)
	return sb


static func label(text: String, size := 18, col := TEXT, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## 带阴影描边的标签（直接盖在 3D 画面上时更清楚）
static func hud_label(text: String, size := 18, col := TEXT) -> Label:
	var l := label(text, size, col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 6)
	return l


static func button(text: String, callback: Callable, min_width := 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	if min_width > 0.0:
		b.custom_minimum_size.x = min_width
	b.pressed.connect(callback)
	return b


static func panel(bg := PANEL_BG, radius := 10, margin := 14) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := _box(bg, radius, Color(1, 1, 1, 0.08), 1)
	sb.content_margin_left = margin
	sb.content_margin_right = margin
	sb.content_margin_top = margin * 0.75
	sb.content_margin_bottom = margin * 0.75
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	return p


static func vbox(sep := 6) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return v


static func hbox(sep := 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return h


static func bar(fill: Color, width := 190.0) -> ProgressBar:
	var b := ProgressBar.new()
	b.min_value = 0
	b.max_value = 100
	b.show_percentage = false
	b.custom_minimum_size = Vector2(width, 14)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.add_theme_stylebox_override("fill", _box(fill, 5))
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


## 键帽：[E]
static func key_cap(text: String) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := _box(Color(0.95, 0.95, 0.93, 0.95), 5, Color(0, 0, 0, 0.4), 1)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := label(text, 17, Color(0.08, 0.08, 0.08), HORIZONTAL_ALIGNMENT_CENTER)
	p.add_child(l)
	return p


static func spacer(expand_h := true, expand_v := false) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if expand_h:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if expand_v:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


static func full_rect(c: Control) -> Control:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return c


static func kind_color(kind: String) -> Color:
	match kind:
		"good":
			return GOOD
		"warn":
			return WARN
		"bad":
			return BAD
	return TEXT


## 控件的 min_size 变化后，重新贴到父容器指定位置（用于绝对定位的浮动面板）
static func center_in_parent(c: Control) -> void:
	c.reset_size()
	var parent_size := c.get_parent_area_size()
	c.position = (parent_size - c.size) * 0.5
