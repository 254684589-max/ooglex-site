class_name TouchControls
extends Control
## 手机 / 平板的双摇杆（GDD.md 第三节）：
## - 左半屏：按下处出现浮动摇杆，拖动走路，推到边缘 = 跑；
## - 右半屏：拖动转视角；右下角按钮「跳」「蹲」「攻」（2.4：点按轻击、按住 0.35 秒重击）「挡」（2.5：按住格挡）；对准可交互物体时，「跳」上方多出交互按钮（文字是动作：交谈 / 打开 / 拾取）。
## 顶部一条留给「菜单」按钮。只在有触屏的设备上显示；force_visible 用于测试。
## B.2：军阵里有小队时，「视角」上方多一个「令」，点一下往左展开「跟随」「坚守」「冲锋」三个按钮，点哪个就下哪个命令（order_pressed）。

const RADIUS := 60.0
const BTN_R := 34.0
const TOP_BAND := 56.0

var player: FpController
var force_visible := false
var move_index := -1
var move_center := Vector2.ZERO
var knob := Vector2.ZERO
var look_index := -1
signal camera_pressed
signal order_pressed(order: String)
const ORDER_BTNS := ["follow", "hold", "charge"]
const ORDER_LABELS := {"order": "令", "order_follow": "跟随", "order_hold": "坚守", "order_charge": "冲锋"}
var order_enabled := false        # 有小队可以指挥（main 设）
var order_open := false           # 三个命令按钮展开着
var attack_index := -1
var guard_index := -1


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
		"crouch": Vector2(r.x - 48.0 - BTN_R * 3.0, r.y - 24.0 - BTN_R),
		"attack": Vector2(r.x - 48.0 - BTN_R * 3.0, r.y - 48.0 - BTN_R * 3.0),
		"guard": Vector2(r.x - 48.0 - BTN_R * 3.0, r.y - 72.0 - BTN_R * 5.0),
		"camera": Vector2(r.x - 24.0 - BTN_R, r.y - 88.0 - BTN_R * 5.0)}
	if has_target():
		c["interact"] = Vector2(r.x - 24.0 - BTN_R, r.y - 64.0 - BTN_R * 3.0)
	if order_enabled:
		c["order"] = Vector2(r.x - 24.0 - BTN_R, r.y - 112.0 - BTN_R * 7.0)
		if order_open:
			for i in ORDER_BTNS.size():
				c["order_" + ORDER_BTNS[i]] = c.order - Vector2((i + 1) * (BTN_R * 2.0 + 12.0), 0.0)
	return c


## 右下角按钮列占的矩形（交互按钮不管有没有都算上，排版才稳定）；HUD 用它让开底部提示和字幕（3.8）
func buttons_rect() -> Rect2:
	var c := button_centers()
	c["interact"] = Vector2(size.x - 24.0 - BTN_R, size.y - 64.0 - BTN_R * 3.0)
	for b in ORDER_BTNS:
		c.erase("order_" + b)              # 展开的命令按钮是临时的，不算进按钮列（排版才稳定）
	var pad := Vector2.ONE * BTN_R * 1.25
	var r := Rect2(c.jump - pad, pad * 2.0)
	for id in c:
		r = r.merge(Rect2(c[id] - pad, pad * 2.0))
	return r


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
	attack_index = -1
	if guard_index != -1 and player:
		player.melee.block_release()
	guard_index = -1
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
			elif b == "attack" and attack_index == -1:
				attack_index = event.index       # 按下 = 开始蓄力，松开时按住的时间决定轻 / 重
				player.melee.press()
			elif b == "camera":
				camera_pressed.emit()          # 第一 / 第三人称切换（2.9）
			elif b == "order":
				order_open = not order_open    # 展开 / 收起三个命令（B.2）
			elif b.begins_with("order_"):
				order_open = false
				order_pressed.emit(b.trim_prefix("order_"))
			elif b == "guard" and guard_index == -1:
				guard_index = event.index        # 按住「挡」格挡，松开放下
				player.melee.block_press()
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
		elif event.index == attack_index:
			attack_index = -1
			player.melee.release()
		elif event.index == guard_index:
			guard_index = -1
			player.melee.block_release()
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
	var labels := {"jump": "跳", "crouch": "站" if player and player.crouch_wanted else "蹲", "attack": "攻", "guard": "挡", "camera": "视角"}
	labels.merge(ORDER_LABELS)
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
