class_name DialogPanel
extends PanelContainer
## 对话面板（P7，对应 V0.1 dialog()）：左边人物字样，右边名字与几段话，下面一排选项按钮。
## 打开时暂停；Esc / ×（或选「告辞」）关闭。选项 = [{t: 文字, main: 是否主选项, fn: Callable}]。

signal closed

var who: Label
var ava: Label
var body: VBoxContainer
var opts: VBoxContainer
var close_btn: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.055, 0.045, 0.97)
	sb.border_color = Color(0.79, 0.64, 0.35)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(14)
	add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	v.add_child(top)
	ava = Label.new()
	ava.custom_minimum_size = Vector2(56, 56)
	ava.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ava.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ava.add_theme_font_size_override("font_size", 30)
	ava.add_theme_color_override("font_color", Color(1.0, 0.8, 0.45))
	var ab := StyleBoxFlat.new()
	ab.bg_color = Color(0.2, 0.13, 0.09)
	ab.border_color = Color(0.79, 0.64, 0.35)
	ab.set_border_width_all(1)
	ab.set_corner_radius_all(28)
	ava.add_theme_stylebox_override("normal", ab)
	top.add_child(ava)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	who = Label.new()
	who.add_theme_font_size_override("font_size", 19)
	who.add_theme_color_override("font_color", Color(1.0, 0.8, 0.45))
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(who)
	close_btn = Button.new()
	close_btn.text = "×"
	close_btn.tooltip_text = "关闭（Esc）"
	close_btn.custom_minimum_size = Vector2(40, 40)
	close_btn.pressed.connect(close)
	head.add_child(close_btn)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	col.add_child(body)
	opts = VBoxContainer.new()
	opts.add_theme_constant_override("separation", 6)
	v.add_child(opts)


func show_dialog(npc_name: String, glyph: String, lines: Array, options: Array) -> void:
	who.text = npc_name
	ava.text = glyph
	for c in body.get_children():
		body.remove_child(c)
		c.queue_free()
	for c in opts.get_children():
		opts.remove_child(c)
		c.queue_free()
	for t in lines:
		var l := Label.new()
		l.text = t
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		# 自动换行的标签要给定宽度，否则尺寸未定时会按一字一行算高度（P3 的教训）
		l.custom_minimum_size = Vector2(340, 0)
		l.add_theme_font_size_override("font_size", 16)
		l.add_theme_color_override("font_color", Color(0.9, 0.85, 0.76))
		body.add_child(l)
	var first: Button = null
	for o in options:
		var b := Button.new()
		b.text = o.t
		b.custom_minimum_size = Vector2(0, 44)
		b.add_theme_font_size_override("font_size", 16)
		if o.get("main", false):
			b.add_theme_color_override("font_color", Color(1.0, 0.82, 0.45))
		var fn: Callable = o.fn
		b.pressed.connect(fn)
		opts.add_child(b)
		if first == null:
			first = b
	visible = true
	get_tree().paused = true
	reset_size()
	set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	if first:
		first.grab_focus()
	Sfx.play("click")
	print("EF_DIALOG npc=%s" % npc_name)


func close() -> void:
	if not visible:
		return
	visible = false
	get_tree().paused = false
	closed.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_pressed() and not event.is_echo() and event.is_action("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
