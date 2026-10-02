class_name QuestPanel
extends Control
## 任务日志（路线图 2.3；GDD.md 7.2）：J 键或右上角「任务」按钮打开，打开时游戏暂停。
## 上面是「主线 / 支线」两页和任务列表，下面是选中任务的简介、当前目标、已得到的线索；完成的任务标「（已完成）」。
## 不在地图上标点：只写目标和线索，靠对话找人（GDD.md 7.2）。

signal closed

var panel: PanelContainer
var tab_main: Button
var tab_side: Button
var list_box: VBoxContainer
var detail: Label
var close_btn: Button
var kind := "main"
var selected := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.05, 0.08, 0.72)
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("1c2a3a")
	sb.border_color = Color("b8964e")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var head := HBoxContainer.new()
	var title := Label.new()
	title.text = "任务日志"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color("e8dcc0"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	close_btn = Button.new()
	close_btn.text = "关闭"
	close_btn.pressed.connect(close)
	head.add_child(close_btn)
	box.add_child(head)
	var tabs := HBoxContainer.new()
	var group := ButtonGroup.new()
	tab_main = _tab(tabs, "主线", "main", group)
	tab_side = _tab(tabs, "支线", "side", group)
	box.add_child(tabs)
	list_box = VBoxContainer.new()
	box.add_child(list_box)
	box.add_child(HSeparator.new())
	detail = Label.new()
	detail.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	detail.add_theme_color_override("font_color", Color("d8d0bc"))
	box.add_child(detail)
	get_tree().root.size_changed.connect(_fit)
	_fit()
	hide()


func _tab(parent: HBoxContainer, text: String, k: String, group: ButtonGroup) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_group = group
	b.custom_minimum_size = Vector2(72, 32)
	b.pressed.connect(func():
		kind = k
		selected = ""
		refresh())
	parent.add_child(b)
	return b


func open() -> void:
	show()
	# 默认选第一个进行中的主线任务
	kind = "main"
	selected = ""
	refresh()
	close_btn.grab_focus()
	print("IC_QUEST open quests=%d clues=%d" % [GameState.quests.size(), GameState.clues.size()])


func close() -> void:
	if not visible:
		return
	hide()
	print("IC_QUEST closed")
	closed.emit()


## 当前页的任务（进行中的排前面）
func quest_ids() -> Array:
	var qd: Dictionary = GameState.quest_data().quests
	var active := []
	var done := []
	for id in GameState.quests:
		if str(qd[id].kind) != kind:
			continue
		(done if GameState.quest_done(id) else active).append(id)
	return active + done


func refresh() -> void:
	tab_main.set_pressed_no_signal(kind == "main")
	tab_side.set_pressed_no_signal(kind == "side")
	for c in list_box.get_children():
		list_box.remove_child(c)
		c.queue_free()
	var ids := quest_ids()
	if selected == "" or not selected in ids:
		selected = ids[0] if not ids.is_empty() else ""
	var qd: Dictionary = GameState.quest_data().quests
	for id in ids:
		var b := Button.new()
		b.text = ("▶ " if id == selected else "    ") + str(qd[id].title) + ("（已完成）" if GameState.quest_done(id) else "")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.y = 32
		b.pressed.connect(func():
			selected = id
			refresh())
		list_box.add_child(b)
	detail.text = detail_text(selected)


func detail_text(id: String) -> String:
	if id == "":
		return "还没有%s任务。" % ("主线" if kind == "main" else "支线")
	var q: Dictionary = GameState.quest_data().quests[id]
	var lines := [str(q.title) + ("（已完成）" if GameState.quest_done(id) else ""), str(q.summary), ""]
	if GameState.quest_done(id):
		lines.append("这件事已经办完了。")
	else:
		lines.append("当前目标：" + str(q.stages[GameState.quest_stage(id)].objective))
	var cl := GameState.clues_for(id)
	if not cl.is_empty():
		lines.append("")
		lines.append("线索：")
		for c in cl:
			lines.append("· " + str(GameState.quest_data().clues[c].text))
	return "\n".join(lines)


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("pause") or event.is_action_pressed("quest_log")):
		get_viewport().set_input_as_handled()
		close()


func _fit() -> void:
	var w := get_tree().root
	var logical := Vector2(w.size) / maxf(w.content_scale_factor, 0.01)
	panel.custom_minimum_size.x = clampf(logical.x - 32.0, 260.0, 600.0)
	detail.custom_minimum_size.x = panel.custom_minimum_size.x - 32.0
