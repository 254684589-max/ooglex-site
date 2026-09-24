class_name UIKit
extends RefCounted
## 界面工具：赛博朋克主题（深色半透明面板 + 青色描边 + 洋红高亮）和常用控件的快捷创建。
## 所有界面都用代码搭建，方便直接修改。

const FONT_PATH := "res://assets/fonts/NotoSansSC-WL.ttf"
const CYAN := Color(0.13, 0.9, 1.0)
const MAGENTA := Color(1.0, 0.18, 0.53)
const YELLOW := Color(1.0, 0.82, 0.25)
const PURPLE := Color(0.69, 0.3, 1.0)
const TEXT := Color(0.93, 0.95, 0.98)
const DIM := Color(0.62, 0.66, 0.74)
const GOOD := Color(0.45, 1.0, 0.55)
const WARN := Color(1.0, 0.72, 0.25)
const BAD := Color(1.0, 0.36, 0.4)
const PANEL_BG := Color(0.035, 0.03, 0.07, 0.9)

static var _theme: Theme
static var _font: Font


static func clear_cache() -> void:
	_theme = null
	_font = null


static func font() -> Font:
	if _font == null:
		_font = load(FONT_PATH)
	return _font


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 18
	var panel := box(PANEL_BG, 8, Color(CYAN.r, CYAN.g, CYAN.b, 0.35), 1)
	_margins(panel, 14, 10)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)
	var normal := box(Color(0.08, 0.08, 0.14, 0.95), 6, Color(CYAN.r, CYAN.g, CYAN.b, 0.45), 1)
	var hover := box(Color(MAGENTA.r * 0.8, MAGENTA.g * 0.8, MAGENTA.b * 0.8, 1.0), 6, MAGENTA, 1)
	var pressed := box(Color(0.6, 0.08, 0.3, 1.0), 6, MAGENTA, 1)
	var focus := box(Color(0, 0, 0, 0), 6, YELLOW, 2)
	var disabled := box(Color(0.06, 0.06, 0.09, 0.8), 6, Color(1, 1, 1, 0.06), 1)
	for sb in [normal, hover, pressed, focus, disabled]:
		_margins(sb, 14, 7)
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("hover_pressed", "Button", pressed)
	t.set_stylebox("focus", "Button", focus)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_focus_color", "Button", TEXT)
	t.set_color("font_disabled_color", "Button", Color(0.45, 0.47, 0.52))
	t.set_color("font_color", "Label", TEXT)
	var bar_bg := box(Color(0, 0, 0, 0.55), 3, Color(1, 1, 1, 0.1), 1)
	t.set_stylebox("background", "ProgressBar", bar_bg)
	t.set_stylebox("fill", "ProgressBar", box(CYAN, 3))
	t.set_color("font_color", "CheckButton", TEXT)
	t.set_color("font_color", "CheckBox", TEXT)
	var le := box(Color(0.02, 0.02, 0.05, 0.9), 5, Color(CYAN.r, CYAN.g, CYAN.b, 0.5), 1)
	_margins(le, 10, 6)
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", box(Color(0.02, 0.02, 0.05, 0.9), 5, YELLOW, 1))
	t.set_stylebox("normal", "OptionButton", normal)
	t.set_stylebox("hover", "OptionButton", hover)
	t.set_stylebox("pressed", "OptionButton", pressed)
	t.set_stylebox("focus", "OptionButton", focus)
	var sep := StyleBoxLine.new()
	sep.color = Color(CYAN.r, CYAN.g, CYAN.b, 0.2)
	sep.thickness = 1
	t.set_stylebox("separator", "HSeparator", sep)
	t.set_stylebox("slider", "HSlider", box(Color(1, 1, 1, 0.12), 3))
	t.set_stylebox("grabber_area", "HSlider", box(CYAN, 3))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(MAGENTA, 3))
	_theme = t
	return t


static func _margins(sb: StyleBoxFlat, h: float, v: float) -> void:
	sb.content_margin_left = h
	sb.content_margin_right = h
	sb.content_margin_top = v
	sb.content_margin_bottom = v


static func box(bg: Color, radius := 6, border := Color(0, 0, 0, 0), border_w := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	if border_w > 0:
		sb.border_color = border
		sb.set_border_width_all(border_w)
	return sb


static func label(text: String, size := 18, col := TEXT, align := HORIZONTAL_ALIGNMENT_LEFT, wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.custom_minimum_size.x = 80
	return l


static func hud_label(text: String, size := 18, col := TEXT) -> Label:
	var l := label(text, size, col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 6)
	return l


static func button(text: String, callback: Callable, min_width := 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	if min_width > 0.0:
		b.custom_minimum_size.x = min_width
	b.pressed.connect(func(): AudioManager.play_sfx("click", -6.0))
	if callback.is_valid():
		b.pressed.connect(callback)
	return b


static func small_button(text: String, callback: Callable) -> Button:
	var b := button(text, callback)
	b.add_theme_font_size_override("font_size", 15)
	return b


static func panel(bg := PANEL_BG, radius := 8, margin := 14, border := Color(0.13, 0.9, 1.0, 0.3)) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := box(bg, radius, border, 1)
	_margins(sb, margin, margin * 0.7)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	return p


static func card(accent := CYAN) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := box(Color(0.07, 0.07, 0.12, 0.95), 6, Color(accent.r, accent.g, accent.b, 0.35), 1)
	sb.border_width_left = 3
	_margins(sb, 12, 8)
	p.add_theme_stylebox_override("panel", sb)
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


static func bar(fill: Color, width := 150.0, height := 12.0) -> ProgressBar:
	var b := ProgressBar.new()
	b.min_value = 0
	b.max_value = 100
	b.show_percentage = false
	b.custom_minimum_size = Vector2(width, height)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.add_theme_stylebox_override("fill", box(fill, 3))
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


static func key_cap(text: String) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := box(Color(0.92, 0.95, 1.0, 0.95), 4, CYAN, 1)
	_margins(sb, 8, 1)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(label(text, 17, Color(0.05, 0.05, 0.1), HORIZONTAL_ALIGNMENT_CENTER))
	return p


static func spacer(expand_h := true, expand_v := false) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if expand_h:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if expand_v:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


static func sep() -> HSeparator:
	return HSeparator.new()


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


static func signed_color(v: float) -> Color:
	# 中文市场习惯：红涨绿跌；同时总会带 +/- 符号，不只靠颜色
	return BAD if v > 0 else (GOOD if v < 0 else DIM)
