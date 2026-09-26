class_name QuestPanel
extends PanelContainer
## 任务日志（P8，对应 V0.1 questLog；V0.1 放在角色面板里，3D 版单独一个面板）：J 键或右上角「任务」。
## 每条任务：名字 +（可交付）/（已完成）+ 当前该做什么。打开时暂停，J / Esc / × 关闭。

signal closed

var hero: Player
var list: VBoxContainer
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
	v.add_child(top)
	var title := Label.new()
	title.text = "任务"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(1.0, 0.8, 0.45))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	close_btn = Button.new()
	close_btn.text = "×"
	close_btn.tooltip_text = "关闭（J / Esc）"
	close_btn.custom_minimum_size = Vector2(40, 40)
	close_btn.pressed.connect(close)
	top.add_child(close_btn)
	list = VBoxContainer.new()
	list.add_theme_constant_override("separation", 12)
	v.add_child(list)


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	refresh()
	visible = true
	get_tree().paused = true
	reset_size()
	set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	close_btn.grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	get_tree().paused = false
	closed.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_pressed() and not event.is_echo() and (event.is_action("ui_cancel") or event.is_action("quest_panel")):
		close()
		get_viewport().set_input_as_handled()


func _label(text: String, fs: int, c: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# 自动换行的标签要给定宽度（P3 的教训）
	l.custom_minimum_size = Vector2(320, 0)
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", c)
	return l


func refresh() -> void:
	for c in list.get_children():
		list.remove_child(c)
		c.queue_free()
	var entries := Quests.log_entries(hero.progress.sheet)
	if entries.is_empty():
		list.add_child(_label(Act1Data.dialogs().quest_log.empty, 15, Color(0.66, 0.6, 0.5)))
		return
	for e in entries:
		var done: bool = e.state == 3
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		box.add_child(_label(String(e.title) + ("（已完成）" if done else "（可交付）" if e.state == 2 else ""), 17, Color(0.6, 0.56, 0.48) if done else Color(1.0, 0.82, 0.45)))
		box.add_child(_label(e.text, 15, Color(0.6, 0.56, 0.48) if done else Color(0.9, 0.85, 0.76)))
		list.add_child(box)
