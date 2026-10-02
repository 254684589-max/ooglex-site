class_name DialoguePanel
extends Control
## 对话面板（路线图 2.1；GDD.md 7.1）：屏幕下方的深色条，说话人名字 + 台词 + 竖排选项。
## 选项可以用鼠标点、触屏点、数字键 1–9、方向键 + 回车；Esc 直接结束对话。打开时游戏暂停（本节点照常处理输入）。

signal closed

var runner := DialogueRunner.new()
var panel: PanelContainer
var name_label: Label
var text_label: Label
var options_box: VBoxContainer
var buttons: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.06, 0.09, 0.9)
	sb.border_color = Color("b8964e")
	sb.border_width_top = 2
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	name_label = Label.new()
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", Color("e8c88a"))
	box.add_child(name_label)
	text_label = Label.new()
	text_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	text_label.add_theme_color_override("font_color", Color("e8dcc0"))
	box.add_child(text_label)
	options_box = VBoxContainer.new()
	options_box.add_theme_constant_override("separation", 4)
	box.add_child(options_box)
	resized.connect(_layout)
	hide()


func open(area: String, dialogue_id: String) -> bool:
	if not runner.start(area, dialogue_id):
		return false
	show()
	_refresh()
	print("IC_DIALOG open id=%s node=%s" % [dialogue_id, runner.node_id])
	return true


func choose(i: int) -> void:
	if not visible:
		return
	var go_on := runner.choose(i)
	if go_on:
		_refresh()
		print("IC_DIALOG node=%s" % runner.node_id)
	else:
		close()


func close() -> void:
	if not visible:
		return
	hide()
	print("IC_DIALOG closed id=%s" % runner.id)
	closed.emit()


func _refresh() -> void:
	name_label.text = runner.speaker()
	if not runner.last_check.is_empty():     # 2.2：刚做过的检定结果（文字 + 符号，不只靠颜色）
		name_label.text += "  %s %s检定%s" % ["√" if runner.last_check.ok else "×", GameState.SKILL_NAMES.get(runner.last_check.skill, ""), "成功" if runner.last_check.ok else "失败"]
	text_label.text = runner.text()
	for b in buttons:
		options_box.remove_child(b)        # 立即移出：只 queue_free 的话，这一帧排版时新旧按钮叠在一起，面板会被撑高
		b.queue_free()
	buttons.clear()
	var opts := runner.options()
	for i in opts.size():
		var b := Button.new()
		b.text = "%d. %s" % [i + 1, DialogueRunner.option_label(opts[i])]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.y = 34          # 手机上手指好点
		b.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		b.pressed.connect(choose.bind(i))
		options_box.add_child(b)
		buttons.append(b)
	_focus_first.call_deferred()
	_layout()
	_layout.call_deferred()          # 选项按钮换行后高度下一帧才确定，再排一次


## 第一个选项拿到焦点（方向键 + 回车可用）；延迟调用时这一批按钮可能已经被下一次刷新换掉，先确认还在场景里
func _focus_first() -> void:
	if visible and not buttons.is_empty() and buttons[0].is_inside_tree():
		buttons[0].grab_focus()
		# 给网页冒烟测试用：第一个选项在窗口里的位置（窗口像素，已乘界面缩放）
		var c: Vector2 = (buttons[0] as Button).get_global_rect().get_center() * get_tree().root.content_scale_factor
		print("IC_DIALOG_OPT x=%d y=%d" % [c.x, c.y])


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.physical_keycode
		if k >= KEY_1 and k <= KEY_9 and k - KEY_1 < buttons.size():
			choose(k - KEY_1)
			get_viewport().set_input_as_handled()


func _layout() -> void:
	var w := minf(size.x - 24.0, 720.0)
	panel.custom_minimum_size = Vector2(w, 0)
	text_label.custom_minimum_size = Vector2(w - 28.0, 0)
	for b in buttons:
		b.custom_minimum_size.x = w - 28.0
	panel.reset_size()
	panel.position = Vector2((size.x - w) * 0.5, size.y - panel.size.y - 16.0)
