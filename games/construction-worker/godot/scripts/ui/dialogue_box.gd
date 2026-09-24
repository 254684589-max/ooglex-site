class_name DialogueBox
extends Control
## 对话框：说话人、逐字显示的台词、选项按钮（鼠标点击、数字键 1~9、方向键 + 回车）。

signal closed(npc_id: String)

var npc_id := ""
var _node: Dictionary = {}
var _panel: PanelContainer
var _speaker: Label
var _text: Label
var _options: VBoxContainer
var _typing := 0.0
var _open := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIKit.full_rect(self)
	visible = false
	var anchor := MarginContainer.new()
	UIKit.full_rect(anchor)
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor.add_theme_constant_override("margin_bottom", 26)
	anchor.add_theme_constant_override("margin_left", 16)
	anchor.add_theme_constant_override("margin_right", 16)
	add_child(anchor)
	var col := UIKit.vbox(0)
	anchor.add_child(col)
	col.add_child(UIKit.spacer(false, true))
	_panel = UIKit.panel(Color(0.06, 0.065, 0.08, 0.94), 12, 20)
	_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_panel.custom_minimum_size = Vector2(minf(860.0, 1200.0), 0)
	col.add_child(_panel)
	var v := UIKit.vbox(10)
	_panel.add_child(v)
	_speaker = UIKit.label("", 20, UIKit.YELLOW)
	v.add_child(_speaker)
	_text = UIKit.label("", 21, UIKit.TEXT)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(300, 0)
	v.add_child(_text)
	_options = UIKit.vbox(6)
	v.add_child(_options)


func is_open() -> bool:
	return _open


func open(id: String) -> void:
	npc_id = id
	_open = true
	visible = true
	_fit_width()
	show_node(DialogueDB.start_node(id))


func _fit_width() -> void:
	var w := get_viewport_rect().size.x
	_panel.custom_minimum_size.x = clampf(w - 40.0, 300.0, 860.0)


func show_node(node_id: String) -> void:
	var n := DialogueDB.node_for(npc_id, node_id)
	if n.is_empty():
		close()
		return
	_node = n
	_speaker.text = String(n.get("speaker", ""))
	_text.text = String(n.get("text", ""))
	_text.visible_ratio = 0.0
	_typing = 0.0
	for c in _options.get_children():
		c.queue_free()
	var opts: Array = n.get("options", [])
	if opts.is_empty():
		opts = [{"text": "……", "next": ""}]
	for i in opts.size():
		var o: Dictionary = opts[i]
		var b := UIKit.button("%d. %s" % [i + 1, String(o.get("text", ""))], _choose.bind(i))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_options.add_child(b)
	await get_tree().process_frame
	if _options.get_child_count() > 0 and is_instance_valid(_options.get_child(0)):
		(_options.get_child(0) as Button).grab_focus()


## 立即选择（跳过逐字显示），测试与快捷操作用
func choose(index: int) -> void:
	_text.visible_ratio = 1.0
	_choose(index)


func current_node() -> Dictionary:
	return _node


func _choose(index: int) -> void:
	if not _open:
		return
	_text.visible_ratio = 1.0
	var opts: Array = _node.get("options", [])
	if index < 0 or index >= opts.size():
		close()
		return
	var o: Dictionary = opts[index]
	var next := String(o.get("next", ""))
	var override := DialogueDB.run_action(npc_id, String(o.get("action", "")))
	if override != "":
		next = override
	if not _open:
		return
	if next == "":
		close()
	else:
		show_node(next)


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	var id := npc_id
	npc_id = ""
	closed.emit(id)
	Events.dialogue_closed.emit(id)


func _process(delta: float) -> void:
	if _open and _text.visible_ratio < 1.0:
		_typing += delta
		var total := maxi(_text.text.length(), 1)
		_text.visible_ratio = clampf(_typing * 45.0 / float(total), 0.0, 1.0)


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.physical_keycode
		if k >= KEY_1 and k <= KEY_9:
			_choose(k - KEY_1)
			get_viewport().set_input_as_handled()
		elif event.is_action("interact"):
			# E：先显示完整台词；只有一个选项时再按一次 E 就选它
			if _text.visible_ratio < 1.0:
				_text.visible_ratio = 1.0
			elif (_node.get("options", []) as Array).size() <= 1:
				_choose(0)
			get_viewport().set_input_as_handled()
		elif event.is_action("pause"):
			close()
			get_viewport().set_input_as_handled()
