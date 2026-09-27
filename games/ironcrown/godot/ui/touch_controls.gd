class_name TouchControls
extends Control
## 手机 / 平板的双摇杆（GDD.md 第三节）：
## - 左半屏：按下处出现浮动摇杆，拖动走路，推到边缘 = 跑；
## - 右半屏：拖动转视角；右下角两个按钮「跳」「蹲」；对准可交互物体时，「跳」上方多出交互按钮（文字是动作：交谈 / 打开 / 拾取）。
## 顶部一条留给「菜单」按钮。只在有触屏的设备上显示；force_visible 用于测试。

const RADIUS := 60.0
const BTN_R := 34.0
const TOP_BAND := 56.0

var player: FpController
var force_visible := false
var move_index := -1
var move_center := Vector2.ZERO
var knob := Vector2.ZERO
var look_index := -1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = force_visible or DisplayServer.is_touchscreen_available()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED:
		release_all()


func button_centers() -> Dictionary:
	var r := size
	var c := {"jump": Vector2(r.x - 24.0 - BTN_R, r.y - 40.0 - BTN_R),
		"crouch": Vector2(r.x - 48.0 - BTN_R * 3.0, r.y - 24.0 - BTN_R)}
	if has_target():
		c["interact"] = Vector2(r.x - 24.0 - BTN_R, r.y - 64.0 - BTN_R * 3.0)
	return c


func has_target() -> bool:
	return player != null and player.interactor != null and player.interactor.target != null


func button_at(p: Vector2) -> String:
	var c := button_centers()
	for id in c:
		if p.distance_to(c[id]) <= BTN_R * 1.25:
			return id
	return ""


func rest_center() -> Vector2:
	return Vector2(24.0 + RADIUS * 1.4, size.y - 24.0 - RADIUS * 1.4)


func release_all() -> void:
	move_index = -1
	look_index = -1
	knob = Vector2.ZERO
	if player:
		player.touch_move = Vector2.ZERO
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not visible or player == null:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			if event.position.y < TOP_BAND:
				return
			var b := button_at(event.position)
			if b == "jump":
				player.request_jump()
			elif b == "crouch":
				player.toggle_crouch()
			elif b == "interact":
				player.interactor.use()
			elif event.position.x < size.x * 0.5 and move_index == -1:
				move_index = event.index
				move_center = event.position
				knob = Vector2.ZERO
			elif event.position.x >= size.x * 0.5 and look_index == -1:
				look_index = event.index
			else:
				return
			get_viewport().set_input_as_handled()
			queue_redraw()
		elif event.index == move_index:
			move_index = -1
			knob = Vector2.ZERO
			player.touch_move = Vector2.ZERO
			queue_redraw()
		elif event.index == look_index:
			look_index = -1
	elif event is InputEventScreenDrag:
		if event.index == move_index:
			knob = (event.position - move_center).limit_length(RADIUS)
			player.touch_move = knob / RADIUS
			get_viewport().set_input_as_handled()
			queue_redraw()
		elif event.index == look_index:
			player.look_touch(event.relative)
			get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	queue_redraw()     # 「蹲 / 站」按钮文字跟随玩家状态


func _draw() -> void:
	var c := move_center if move_index != -1 else rest_center()
	var a := 0.55 if move_index != -1 else 0.28
	draw_circle(c, RADIUS, Color(0.06, 0.09, 0.13, a))
	draw_arc(c, RADIUS, 0.0, TAU, 48, Color(0.72, 0.59, 0.31, a + 0.2), 2.0)
	draw_circle(c + knob, RADIUS * 0.42, Color(0.91, 0.86, 0.75, a + 0.2))
	var font := get_theme_default_font()
	var labels := {"jump": "跳", "crouch": "站" if player and player.crouch_wanted else "蹲"}
	if has_target():
		labels["interact"] = player.interactor.target.verb_now()
	var centers := button_centers()
	for id in centers:
		var p: Vector2 = centers[id]
		draw_circle(p, BTN_R, Color(0.06, 0.09, 0.13, 0.5))
		draw_arc(p, BTN_R, 0.0, TAU, 40, Color(0.72, 0.59, 0.31, 0.8), 2.0)
		var t: String = labels.get(id, "")
		var fs := 22 if t.length() == 1 else 16
		var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, p + Vector2(-w * 0.5, fs * 0.35), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("e8dcc0"))
