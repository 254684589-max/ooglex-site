class_name TouchControls
extends Control
## 手机虚拟摇杆（GDD.md 第三节）：左下区域按下即在按下处出现摇杆（浮动摇杆），拖动控制方向。
## 摇杆认领的触点会标记为已处理，不会再被当成「点地面移动」；摇杆区域以外的触点照常点地面。
## 只在有触屏的设备上显示；也可以用 force_visible 强制显示（测试用）。

signal changed(value: Vector2)

const RADIUS := 64.0
const ZONE_W := 0.45     # 屏幕左侧 45% 宽
const ZONE_H := 0.5      # 屏幕下方 50% 高

var force_visible := false
var value := Vector2.ZERO
var active_index := -1
var center := Vector2.ZERO
var knob := Vector2.ZERO


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = force_visible or DisplayServer.is_touchscreen_available()


func in_zone(p: Vector2) -> bool:
	var r := get_viewport_rect().size
	return p.x < r.x * ZONE_W and p.y > r.y * (1.0 - ZONE_H)


func rest_center() -> Vector2:
	var r := get_viewport_rect().size
	return Vector2(24.0 + RADIUS * 1.4, r.y - 24.0 - RADIUS * 1.4)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		if event.pressed and active_index == -1 and in_zone(event.position):
			active_index = event.index
			center = event.position
			knob = Vector2.ZERO
			_set_value(Vector2.ZERO)
			get_viewport().set_input_as_handled()
		elif not event.pressed and event.index == active_index:
			active_index = -1
			knob = Vector2.ZERO
			_set_value(Vector2.ZERO)
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index == active_index:
		knob = (event.position - center).limit_length(RADIUS)
		_set_value(knob / RADIUS)
		get_viewport().set_input_as_handled()


func _set_value(v: Vector2) -> void:
	value = v
	changed.emit(v)
	queue_redraw()


func _draw() -> void:
	var c := center if active_index != -1 else rest_center()
	var a := 0.55 if active_index != -1 else 0.25
	draw_circle(c, RADIUS, Color(0.08, 0.05, 0.04, a))
	draw_arc(c, RADIUS, 0.0, TAU, 48, Color(0.79, 0.64, 0.35, a + 0.2), 2.0)
	draw_circle(c + knob, RADIUS * 0.42, Color(0.91, 0.52, 0.23, a + 0.25))
