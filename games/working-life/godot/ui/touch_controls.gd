class_name TouchControls
extends Control
## 手机 / 平板触屏操作：
##   左下：虚拟摇杆（移动）
##   右半屏空白处拖动：转视角
##   右下：交互(E)、使用(F)、跳、跑（切换）
##   右上：手机、地图、菜单
## 按钮通过 Input.parse_input_event 发出与键盘相同的输入动作，玩家脚本无需区分来源。

const JOY_RADIUS := 70.0

var player: Node = null
var _joy_index := -1
var _joy_center := Vector2.ZERO
var _joy_vec := Vector2.ZERO
var _look_index := -1
var _look_last := Vector2.ZERO
var _buttons: Array = []   # [{rect, action, label, toggle, pressed_index, color}]
var _sprint_on := false
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIKit.full_rect(self)
	_font = UIKit.font()
	resized.connect(_layout)
	_layout()


func _layout() -> void:
	var s := size
	if s.x <= 0:
		return
	var r := clampf(minf(s.x, s.y) * 0.085, 34.0, 52.0)
	var base := Vector2(s.x - r * 1.5 - 18.0, s.y - r * 1.5 - 18.0)
	_buttons = [
		_mk(base + Vector2(0, 0), r * 1.15, "interact", "交互", Color(0.2, 0.9, 1.0)),
		_mk(base + Vector2(-r * 2.5, r * 0.15), r, "use", "使用", Color(1.0, 0.3, 0.6)),
		_mk(base + Vector2(r * 0.1, -r * 2.5), r * 0.9, "jump", "跳", Color(0.8, 0.8, 0.85)),
		_mk(base + Vector2(-r * 2.4, -r * 2.2), r * 0.9, "sprint_toggle", "跑", Color(0.5, 0.95, 0.55)),
		_mk(Vector2(s.x - 44.0, 44.0), 26.0, "pause", "菜单", Color(0.85, 0.85, 0.85)),
		_mk(Vector2(s.x - 108.0, 44.0), 26.0, "map", "地图", Color(0.85, 0.85, 0.85)),
		_mk(Vector2(s.x - 172.0, 44.0), 26.0, "phone", "手机", Color(0.85, 0.85, 0.85)),
	]
	queue_redraw()


func _mk(center: Vector2, radius: float, act: String, text: String, col: Color) -> Dictionary:
	return {"center": center, "radius": radius, "action": act, "label": text, "color": col, "index": -1}


func _hit_button(pos: Vector2) -> int:
	for i in _buttons.size():
		var b: Dictionary = _buttons[i]
		if pos.distance_to(b["center"]) <= float(b["radius"]) * 1.15:
			return i
	return -1


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if not GameManager.playing or GameManager.is_modal():
		_release_all()
		return
	if event is InputEventScreenTouch:
		var pos: Vector2 = event.position
		if event.pressed:
			var bi := _hit_button(pos)
			if bi >= 0:
				_press_button(bi, event.index)
				get_viewport().set_input_as_handled()
			elif pos.x < size.x * 0.45 and pos.y > size.y * 0.35 and _joy_index < 0:
				_joy_index = event.index
				_joy_center = pos
				_joy_vec = Vector2.ZERO
				get_viewport().set_input_as_handled()
			elif pos.x >= size.x * 0.45 and _look_index < 0:
				_look_index = event.index
				_look_last = pos
				get_viewport().set_input_as_handled()
		else:
			if event.index == _joy_index:
				_joy_index = -1
				_joy_vec = Vector2.ZERO
				_apply_move()
			if event.index == _look_index:
				_look_index = -1
			for i in _buttons.size():
				if int(_buttons[i]["index"]) == event.index:
					_release_button(i)
		queue_redraw()
	elif event is InputEventScreenDrag:
		if event.index == _joy_index:
			var d: Vector2 = event.position - _joy_center
			_joy_vec = d.limit_length(JOY_RADIUS) / JOY_RADIUS
			_apply_move()
			queue_redraw()
			get_viewport().set_input_as_handled()
		elif event.index == _look_index:
			var rel: Vector2 = event.position - _look_last
			_look_last = event.position
			if player != null:
				player.camera_rig.handle_touch_drag(rel)
			get_viewport().set_input_as_handled()


func _apply_move() -> void:
	if player != null:
		player.touch_move = _joy_vec


func _press_button(i: int, touch_index: int) -> void:
	var b: Dictionary = _buttons[i]
	b["index"] = touch_index
	var act := String(b["action"])
	if act == "sprint_toggle":
		_sprint_on = not _sprint_on
		if player != null:
			player.touch_sprint = _sprint_on
		return
	_send(act, true)


func _release_button(i: int) -> void:
	var b: Dictionary = _buttons[i]
	b["index"] = -1
	var act := String(b["action"])
	if act != "sprint_toggle":
		_send(act, false)


func _send(act: String, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = act
	ev.pressed = pressed
	ev.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(ev)


func _release_all() -> void:
	if _joy_index >= 0 or _joy_vec != Vector2.ZERO:
		_joy_index = -1
		_joy_vec = Vector2.ZERO
		_apply_move()
		queue_redraw()
	_look_index = -1
	for i in _buttons.size():
		if int(_buttons[i]["index"]) >= 0:
			_release_button(i)


func _draw() -> void:
	if not GameManager.playing:
		return
	# 摇杆
	var jc := _joy_center if _joy_index >= 0 else Vector2(110, size.y - 120)
	draw_circle(jc, JOY_RADIUS, Color(1, 1, 1, 0.1))
	draw_arc(jc, JOY_RADIUS, 0, TAU, 40, Color(1, 1, 1, 0.35), 2.0)
	draw_circle(jc + _joy_vec * JOY_RADIUS, 28.0, Color(1, 1, 1, 0.4 if _joy_index >= 0 else 0.22))
	if _joy_index < 0:
		_draw_text_centered(jc + Vector2(0, JOY_RADIUS + 20), "移动", 15, Color(1, 1, 1, 0.55))
	# 按钮
	for b in _buttons:
		var c: Vector2 = b["center"]
		var r: float = b["radius"]
		var col: Color = b["color"]
		var active := int(b["index"]) >= 0 or (String(b["action"]) == "sprint_toggle" and _sprint_on)
		draw_circle(c, r, Color(col.r, col.g, col.b, 0.55 if active else 0.24))
		draw_arc(c, r, 0, TAU, 36, Color(col.r, col.g, col.b, 0.9), 2.0)
		_draw_text_centered(c + Vector2(0, 6), String(b["label"]), 17 if r > 30 else 13, Color(1, 1, 1, 0.95))


func _draw_text_centered(pos: Vector2, text: String, fs: int, col: Color) -> void:
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string_outline(_font, pos - Vector2(w * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.6))
	draw_string(_font, pos - Vector2(w * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
