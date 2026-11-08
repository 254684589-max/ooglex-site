class_name StartMenu
extends Control
## 开始主菜单（2026-11-08 所有者：「做开始主菜单页面……加入中英文切换、制作人员……存档等，要求画面精美」）。
## 打开网页先到这里（截图、测试参数照旧直接进游戏）：背后是 TitleStage（雪夜断王座上的铁冠、往北走的长眠者，自己的 3D 世界），
## 左上是标题，右边一块铁框金边的菜单：继续游戏（最近的存档）/ 新游戏 / 读取存档 / 设置 / 制作人员 / 中文 · English / 返回游戏中心（电脑版是「退出游戏」）。
## 窄屏（手机竖屏、平板竖屏）标题放上面、菜单放下面。键盘上下键选、回车确认（Godot 的焦点）。
## 菜单本身不改游戏状态，只发信号，由 main 去做（读档、开新游戏、开存档面板 / 设置）。

signal continue_requested
signal new_game_requested
signal load_requested
signal settings_requested
signal credits_requested
signal exit_requested

const GOLD := Color("c9a65a")
const GOLD_HI := Color("f0d79a")
const TEXT := Color("e8dcc0")
const DIM := Color("8f8a80")
const NARROW := 760.0

var stage: TitleStage
var view: SubViewportContainer
var logo: VBoxContainer
var title_zh: Label
var title_en: Label
var tagline: Label
var panel: PanelContainer
var box: VBoxContainer
var continue_btn: Button
var continue_note: Label
var new_btn: Button
var load_btn: Button
var settings_btn: Button
var credits_btn: Button
var exit_btn: Button
var lang_btns := {}
var footer: Label
var confirm: Control
var confirm_yes: Button
var shade: ColorRect
var reduced := false


## 打开网页先到主菜单：不是读档、换区域进来的，网址没带截图 / 测试参数，这次打开页面还没离开过主菜单；测试里由 Engine 元数据关掉（startmenu 组单独测）
static func wanted(main_node: Node, pending: Dictionary, query: Callable) -> bool:
	if Engine.get_meta("ic_skip_menu", false) or Engine.get_meta("ic_menu_done", false) or not pending.is_empty():
		return false
	if main_node.use_test_range or main_node.use_arena or main_node.area != "frostford":
		return false
	for k in Opening.SKIP_QUERY + ["menu_off", "talk", "cutscene", "q"]:
		if str(query.call(k)) != "":
			return false
	return true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	reduced = Settings.reduced_motion
	var bg := ColorRect.new()
	bg.color = Color("05080d")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	view = SubViewportContainer.new()
	view.name = "TitleView"
	view.stretch = true
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(view)
	var sv := SubViewport.new()
	sv.own_world_3d = true
	sv.process_mode = Node.PROCESS_MODE_ALWAYS
	sv.msaa_3d = Viewport.MSAA_2X
	view.add_child(sv)
	stage = TitleStage.make(reduced)
	sv.add_child(stage)
	_gradients()
	_logo()
	_panel()
	footer = Label.new()
	footer.add_theme_font_size_override("font_size", 13)
	footer.add_theme_color_override("font_color", Color(0.75, 0.72, 0.66, 0.75))
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	footer.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(footer)
	_confirm()
	shade = ColorRect.new()                     # 进来时从黑里亮起来
	shade.color = Color.BLACK
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	get_tree().root.size_changed.connect(_layout)
	Settings.changed.connect(_refresh_lang)
	hide()


func open() -> void:
	show()
	refresh()
	_layout()
	shade.color.a = 1.0
	if reduced:
		shade.color.a = 0.0
	else:
		var tw := create_tween()
		tw.tween_property(shade, "color:a", 0.0, 1.6).set_trans(Tween.TRANS_SINE)
	(continue_btn if not continue_btn.disabled else new_btn).grab_focus.call_deferred()
	print("IC_MENU open saves=%s lang=%s" % [Saves.has_any(), Settings.lang])


func close() -> void:
	hide()
	confirm.hide()
	if stage:
		stage.queue_free()            # 进了游戏就不再要那个 3D 场景（回主菜单是重新载入）
		stage = null
	view.hide()


## 存档变了、语言变了：继续游戏那一行的说明、底部一行
func refresh() -> void:
	var slot := Saves.latest_slot()
	continue_btn.disabled = slot == ""
	if slot == "":
		continue_note.text = I18n.t("还没有存档")
	else:
		var info: Dictionary = Saves.list_slots().get(slot, {})
		continue_note.text = "%s · %s" % [I18n.t(str(Saves.SLOT_NAMES.get(slot, slot))), I18n.t(str(info.get("summary", ""))).split("\n")[0]]
	load_btn.disabled = not Saves.has_any()
	footer.text = I18n.t("技术原型 · 开发中") + "    © 2026 Ooglex"
	for k in lang_btns:
		(lang_btns[k] as Button).button_pressed = Settings.lang == k
	title_en.visible = true


func _refresh_lang() -> void:
	if visible:
		refresh()
		_layout()


# ---------------- 搭界面 ----------------

## 左边、底下、右边压暗一点：标题和菜单的字看得清，中间的王座和冠不暗
func _gradients() -> void:
	for spec in [[Control.PRESET_LEFT_WIDE, Vector2(0.0, 0.5), Vector2(1.0, 0.5), 0.62, 0.42],
			[Control.PRESET_RIGHT_WIDE, Vector2(1.0, 0.5), Vector2(0.0, 0.5), 0.55, 0.38],
			[Control.PRESET_BOTTOM_WIDE, Vector2(0.5, 1.0), Vector2(0.5, 0.0), 0.7, 0.22],
			[Control.PRESET_TOP_WIDE, Vector2(0.5, 0.0), Vector2(0.5, 1.0), 0.45, 0.18]]:
		var g := Gradient.new()
		g.set_color(0, Color(0.01, 0.015, 0.03, spec[3]))
		g.set_color(1, Color(0.01, 0.015, 0.03, 0.0))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill_from = spec[1]
		gt.fill_to = spec[2]
		gt.width = 64
		gt.height = 64
		var tr := TextureRect.new()
		tr.texture = gt
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.set_anchors_and_offsets_preset(spec[0])
		tr.set_meta("frac", spec[4])
		tr.set_meta("preset", spec[0])
		tr.name = "Shade%d" % get_child_count()
		add_child(tr)


func _logo() -> void:
	logo = VBoxContainer.new()
	logo.name = "Logo"
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo.add_theme_constant_override("separation", 2)
	add_child(logo)
	var emblem := CrownEmblem.new()
	emblem.custom_minimum_size = Vector2(84, 58)
	logo.add_child(emblem)
	title_zh = Label.new()
	title_zh.text = "铁冠之争"
	title_zh.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED     # 标题两种语言都留着中文
	title_zh.add_theme_font_size_override("font_size", 76)
	title_zh.add_theme_color_override("font_color", Color("e9cf8c"))
	title_zh.add_theme_color_override("font_outline_color", Color("1a1209"))
	title_zh.add_theme_constant_override("outline_size", 12)
	title_zh.add_theme_color_override("font_shadow_color", Color(0.9, 0.7, 0.3, 0.28))
	title_zh.add_theme_constant_override("shadow_offset_x", 0)
	title_zh.add_theme_constant_override("shadow_offset_y", 0)
	title_zh.add_theme_constant_override("shadow_outline_size", 26)
	logo.add_child(title_zh)
	title_en = Label.new()
	title_en.text = "T H E   I R O N   C R O W N"
	title_en.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	title_en.add_theme_font_size_override("font_size", 20)
	title_en.add_theme_color_override("font_color", Color("b9c6d8"))
	title_en.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	title_en.add_theme_constant_override("outline_size", 4)
	logo.add_child(title_en)
	var rule := Ornament.new()
	rule.custom_minimum_size = Vector2(360, 18)
	logo.add_child(rule)
	tagline = Label.new()
	tagline.text = "王已死，冠未落。雪原上的人，一个接一个往北走去。"
	tagline.add_theme_font_size_override("font_size", 16)
	tagline.add_theme_color_override("font_color", Color("c8bca0"))
	tagline.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	tagline.add_theme_constant_override("outline_size", 4)
	tagline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	logo.add_child(tagline)


func _panel() -> void:
	panel = PanelContainer.new()
	panel.name = "MenuPanel"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.035, 0.05, 0.075, 0.84)
	sb.border_color = GOLD.darkened(0.15)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(3)
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 18
	sb.content_margin_left = 26
	sb.content_margin_right = 26
	sb.content_margin_top = 30
	sb.content_margin_bottom = 22
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	var deco := PanelFrame.new()                     # 内框、四角的花、顶上的小冠
	deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	deco.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(deco)
	box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	continue_btn = _menu_btn("继续游戏", func(): continue_requested.emit())
	continue_note = Label.new()
	continue_note.add_theme_font_size_override("font_size", 13)
	continue_note.add_theme_color_override("font_color", DIM)
	continue_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	continue_note.clip_text = true
	continue_note.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(continue_note)
	new_btn = _menu_btn("新游戏", _on_new)
	load_btn = _menu_btn("读取存档", func(): load_requested.emit())
	settings_btn = _menu_btn("设置", func(): settings_requested.emit())
	credits_btn = _menu_btn("制作人员", func(): credits_requested.emit())
	var lang_row := HBoxContainer.new()
	lang_row.alignment = BoxContainer.ALIGNMENT_CENTER
	lang_row.add_theme_constant_override("separation", 0)
	var group := ButtonGroup.new()
	for k in ["zh", "en"]:
		var b := Button.new()
		b.text = "中文" if k == "zh" else "English"
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(108, 36)
		b.focus_mode = Control.FOCUS_ALL
		_style_toggle(b, k == "zh")
		b.pressed.connect(func():
			Settings.set_value("lang", k)
			print("IC_LANG %s" % k))
		lang_row.add_child(b)
		lang_btns[k] = b
	box.add_child(_spacer(4))
	box.add_child(lang_row)
	box.add_child(_spacer(4))
	exit_btn = _menu_btn("返回游戏中心" if OS.has_feature("web") else "退出游戏", func(): exit_requested.emit())


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = h
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _menu_btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(280, 50)
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", GOLD_HI)
	b.add_theme_color_override("font_focus_color", GOLD_HI)
	b.add_theme_color_override("font_pressed_color", Color("fff3d6"))
	b.add_theme_color_override("font_disabled_color", Color("5d5a54"))
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	b.add_theme_constant_override("outline_size", 3)
	b.add_theme_stylebox_override("normal", _sb(Color(0.07, 0.09, 0.13, 0.9), GOLD.darkened(0.45), 1))
	b.add_theme_stylebox_override("hover", _sb(Color(0.13, 0.12, 0.1, 0.95), GOLD, 2, true))
	b.add_theme_stylebox_override("focus", _sb(Color(0.13, 0.12, 0.1, 0.0), GOLD_HI, 2, true, false))
	b.add_theme_stylebox_override("pressed", _sb(Color(0.05, 0.05, 0.05, 0.95), GOLD_HI, 2))
	b.add_theme_stylebox_override("disabled", _sb(Color(0.05, 0.06, 0.08, 0.7), Color(0.3, 0.28, 0.24), 1))
	b.pressed.connect(cb)
	box.add_child(b)
	return b


static func _sb(bg: Color, border: Color, w: int, glow := false, fill := true) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.draw_center = fill
	s.border_color = border
	s.set_border_width_all(w)
	s.set_corner_radius_all(2)
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 6
	s.content_margin_bottom = 8
	if glow:
		s.shadow_color = Color(0.85, 0.65, 0.3, 0.22)
		s.shadow_size = 10
	return s


func _style_toggle(b: Button, left: bool) -> void:
	for st in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
		var on: bool = st in ["pressed", "hover_pressed"]
		var s := _sb(Color(0.6, 0.47, 0.22, 0.85) if on else Color(0.06, 0.08, 0.11, 0.9), GOLD if st != "normal" else GOLD.darkened(0.35), 1 if st != "focus" else 2, false, st != "focus")
		s.corner_radius_top_left = 14 if left else 0
		s.corner_radius_bottom_left = 14 if left else 0
		s.corner_radius_top_right = 0 if left else 14
		s.corner_radius_bottom_right = 0 if left else 14
		b.add_theme_stylebox_override(st, s)
	b.add_theme_font_size_override("font_size", 16)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_pressed_color", Color("120c04"))
	b.add_theme_color_override("font_hover_pressed_color", Color("120c04"))
	b.add_theme_color_override("font_hover_color", GOLD_HI)


## 新游戏：有存档时先问一句（存档不会删）
func _on_new() -> void:
	if Saves.has_any():
		confirm.show()
		confirm_yes.grab_focus()
		return
	new_game_requested.emit()


func _confirm() -> void:
	confirm = Control.new()
	confirm.name = "Confirm"
	confirm.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(confirm)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	confirm.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	confirm.add_child(cc)
	var p := PanelContainer.new()
	var sb := _sb(Color(0.04, 0.055, 0.08, 0.96), GOLD, 2)
	sb.set_content_margin_all(24)
	p.add_theme_stylebox_override("panel", sb)
	cc.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	p.add_child(v)
	var q := Label.new()
	q.text = "开始新游戏？"
	q.add_theme_font_size_override("font_size", 22)
	q.add_theme_color_override("font_color", GOLD_HI)
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(q)
	var n := Label.new()
	n.text = "已有的存档不会删除，随时可以从「读取存档」回去。"
	n.add_theme_color_override("font_color", TEXT)
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	n.custom_minimum_size.x = 320
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(n)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	v.add_child(row)
	confirm_yes = Button.new()
	confirm_yes.text = "开始"
	confirm_yes.custom_minimum_size = Vector2(120, 42)
	confirm_yes.pressed.connect(func():
		confirm.hide()
		new_game_requested.emit())
	row.add_child(confirm_yes)
	var no := Button.new()
	no.text = "取消"
	no.custom_minimum_size = Vector2(120, 42)
	no.pressed.connect(func():
		confirm.hide()
		new_btn.grab_focus())
	row.add_child(no)
	for b in [confirm_yes, no]:
		b.add_theme_stylebox_override("normal", _sb(Color(0.07, 0.09, 0.13, 0.9), GOLD.darkened(0.4), 1))
		b.add_theme_stylebox_override("hover", _sb(Color(0.13, 0.12, 0.1, 0.95), GOLD, 2, true))
		b.add_theme_stylebox_override("focus", _sb(Color(0, 0, 0, 0), GOLD_HI, 2, true, false))
		b.add_theme_color_override("font_hover_color", GOLD_HI)
	confirm.hide()


func _unhandled_input(event: InputEvent) -> void:
	if visible and confirm.visible and event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		confirm.hide()
		new_btn.grab_focus()


# ---------------- 排版 ----------------

func _layout() -> void:
	if not is_inside_tree():
		return
	var sz := UiKit.logical_size(self)
	var narrow := sz.x < NARROW
	var short := sz.y < 560.0
	for c in get_children():
		if c is TextureRect and c.has_meta("frac"):
			var f: float = c.get_meta("frac")
			match int(c.get_meta("preset")):
				Control.PRESET_LEFT_WIDE:
					c.offset_right = sz.x * (0.0 if narrow else f)
				Control.PRESET_RIGHT_WIDE:
					c.offset_left = -sz.x * (0.0 if narrow else f)
				Control.PRESET_BOTTOM_WIDE:
					c.offset_top = -sz.y * (0.55 if narrow else f)
				Control.PRESET_TOP_WIDE:
					c.offset_bottom = sz.y * (0.4 if narrow else f)
	var big := 76 if not (narrow or short) else (54 if not short else 46)
	title_zh.add_theme_font_size_override("font_size", big)
	title_en.add_theme_font_size_override("font_size", 20 if big == 76 else 15)
	tagline.visible = not short or not narrow
	tagline.custom_minimum_size.x = minf(420.0, sz.x - 48.0)
	var bh := 50.0 if not short else 38.0
	var fs := 22 if not short else 18
	box.add_theme_constant_override("separation", 10 if not short else 5)
	for b in [continue_btn, new_btn, load_btn, settings_btn, credits_btn, exit_btn]:
		b.custom_minimum_size = Vector2(minf(300.0, sz.x - 100.0) if narrow else 290.0, bh)
		b.add_theme_font_size_override("font_size", fs)
	var sb := panel.get_theme_stylebox("panel") as StyleBoxFlat
	sb.content_margin_top = 30 if not short else 18
	sb.content_margin_bottom = 22 if not short else 12
	logo.reset_size()
	panel.reset_size()
	var ls := logo.get_combined_minimum_size()
	var ps := panel.get_combined_minimum_size()
	if narrow:
		logo.position = Vector2((sz.x - ls.x) * 0.5, maxf(16.0, sz.y * 0.05))
		for c in logo.get_children():
			if c is Label:
				c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		panel.position = Vector2((sz.x - ps.x) * 0.5, maxf(logo.position.y + ls.y + 10.0, sz.y - ps.y - 44.0))
	else:
		logo.position = Vector2(maxf(28.0, sz.x * 0.055), maxf(18.0, sz.y * (0.09 if not short else 0.05)))
		for c in logo.get_children():
			if c is Label:
				c.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		panel.position = Vector2(sz.x - ps.x - maxf(24.0, sz.x * 0.06), (sz.y - ps.y) * 0.5)
	footer.position = Vector2(16.0, sz.y - 26.0)
	footer.visible = not narrow or sz.y - (panel.position.y + ps.y) > 30.0


## 标题上面的小冠：铁色的冠身、金边、中间一颗暖色的石头
class CrownEmblem extends Control:
	func _draw() -> void:
		var w := size.x
		var h := size.y
		var pts := PackedVector2Array([Vector2(0.08, 0.88), Vector2(0.12, 0.3), Vector2(0.3, 0.55), Vector2(0.5, 0.08), Vector2(0.7, 0.55), Vector2(0.88, 0.3), Vector2(0.92, 0.88)])
		for i in pts.size():
			pts[i] = Vector2(pts[i].x * w, pts[i].y * h)
		draw_colored_polygon(pts, Color("3c4048"))
		var outline := pts.duplicate()
		outline.append(pts[0])
		draw_polyline(outline, Color("c9a65a"), 2.0, true)
		draw_rect(Rect2(Vector2(0.06 * w, 0.86 * h), Vector2(0.88 * w, 0.12 * h)), Color("c9a65a"))
		draw_circle(Vector2(0.5 * w, 0.66 * h), 0.07 * h, Color("ffc873"))
		for tip in [Vector2(0.12, 0.3), Vector2(0.5, 0.08), Vector2(0.88, 0.3)]:
			draw_circle(Vector2(tip.x * w, tip.y * h), 0.05 * h, Color("e9cf8c"))


## 标题下面的一道线：两头渐细、中间一颗菱形
class Ornament extends Control:
	func _draw() -> void:
		var y := size.y * 0.5
		var w := size.x
		var c := Color("c9a65a")
		draw_line(Vector2(0, y), Vector2(w * 0.44, y), Color(c, 0.75), 1.5, true)
		draw_line(Vector2(w * 0.56, y), Vector2(w, y), Color(c, 0.75), 1.5, true)
		draw_colored_polygon(PackedVector2Array([Vector2(w * 0.5, y - 6), Vector2(w * 0.5 + 9, y), Vector2(w * 0.5, y + 6), Vector2(w * 0.5 - 9, y)]), c)
		draw_circle(Vector2(w * 0.46, y), 2.0, c)
		draw_circle(Vector2(w * 0.54, y), 2.0, c)


## 菜单板的内框：离外框 6 像素一道细金线，四角各一个小菱形，顶上正中一顶小冠
class PanelFrame extends Control:
	func _draw() -> void:
		var c := Color("c9a65a")
		var r := Rect2(Vector2(6, 6), size - Vector2(12, 12))
		draw_rect(r, Color(c, 0.35), false, 1.0)
		for p in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -5), p + Vector2(5, 0), p + Vector2(0, 5), p + Vector2(-5, 0)]), c)
		var m := Vector2(size.x * 0.5, 6)
		var crown := PackedVector2Array([m + Vector2(-16, 6), m + Vector2(-14, -8), m + Vector2(-7, -1), m + Vector2(0, -12), m + Vector2(7, -1), m + Vector2(14, -8), m + Vector2(16, 6)])
		draw_colored_polygon(crown, Color("1a2230"))
		var ol := crown.duplicate()
		ol.append(crown[0])
		draw_polyline(ol, c, 1.5, true)
