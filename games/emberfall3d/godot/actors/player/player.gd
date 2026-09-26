class_name Player
extends CharacterBody3D
## 玩家移动（TECH.md 第 4.1 节、GDD.md 第三节）：
## - 电脑：左键点地面移动，按住持续移动（每 0.15 秒刷新目标）；可选 WASD。
## - 手机：虚拟摇杆（TouchControls）直接按方向移动；点摇杆区域以外的地面也能移动。
## - 点击移动走导航网格（NavigationAgent3D）；摇杆 / 键盘不走寻路，靠碰撞体贴墙滑动。
## 占位外观：胶囊 + 方块武器（阶段 2 换成正式模型）。

signal arrived

const LAYER_WORLD := 1
const LAYER_GROUND := 4          # 碰撞层第 3 层：地面，只用于鼠标 / 触屏拾取和导航网格解析
const LAYER_PLAYER := 8
const HOLD_REFRESH := 0.15
const ARRIVE_DIST := 0.15

@export var speed := 5.0
var camera: IsoCamera
var stick := Vector2.ZERO        # 虚拟摇杆输入（-1..1，y 向下为正，与 Input.get_vector 一致）
var agent: NavigationAgent3D
var moving_to := false
var hold_active := false
var hold_screen := Vector2.ZERO
var hold_timer := 0.0
var touch_index := -1
var last_target := Vector3.ZERO
var marker: MeshInstance3D


func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	collision_layer = LAYER_PLAYER
	collision_mask = LAYER_WORLD
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	shape.shape = cap
	shape.position.y = 0.9
	add_child(shape)
	agent = NavigationAgent3D.new()
	agent.radius = 0.4
	agent.height = 1.8
	agent.path_desired_distance = 0.35
	agent.target_desired_distance = 0.25
	add_child(agent)
	_build_placeholder()


func _build_placeholder() -> void:
	var body := MeshInstance3D.new()
	var capm := CapsuleMesh.new()
	capm.radius = 0.35
	capm.height = 1.8
	body.mesh = capm
	body.material_override = _mat(Color(0.55, 0.47, 0.38))
	body.position.y = 0.9
	add_child(body)
	var blade := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.08, 1.1, 0.08)
	blade.mesh = bm
	blade.material_override = _mat(Color(0.8, 0.82, 0.86))
	blade.position = Vector3(0.45, 1.0, 0.1)
	blade.rotation_degrees.z = -20
	add_child(blade)
	# 「鼻子」：让朝向看得出来
	var nose := MeshInstance3D.new()
	var nm := BoxMesh.new()
	nm.size = Vector3(0.18, 0.12, 0.2)
	nose.mesh = nm
	nose.material_override = _mat(Color(0.91, 0.52, 0.23))
	nose.position = Vector3(0, 1.45, 0.34)
	add_child(nose)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.72, 0.45)
	light.light_energy = 1.3
	light.omni_range = 6.0
	light.position = Vector3(0, 2.4, 0)
	add_child(light)
	# 点击目标标记（占位：一个会淡出的圆环）
	marker = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.28
	tm.outer_radius = 0.38
	marker.mesh = tm
	var mm := _mat(Color(0.91, 0.64, 0.35))
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker.material_override = mm
	marker.top_level = true
	marker.visible = false
	add_child(marker)


static func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	return m


# ---------------- 输入 ----------------

func _unhandled_input(event: InputEvent) -> void:
	# 触屏会同时产生「模拟鼠标」事件（device = DEVICE_ID_EMULATION），这里只认真正的鼠标，
	# 触屏由下面的 ScreenTouch / ScreenDrag 处理，避免摇杆的触点被当成点地面。
	if event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
		if event.button_index == MOUSE_BUTTON_LEFT:
			hold_active = event.pressed
			hold_screen = event.position
			if event.pressed:
				click_at(event.position)
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION:
		if hold_active:
			hold_screen = event.position
	elif event is InputEventScreenTouch:
		if event.pressed and touch_index == -1:
			touch_index = event.index
			hold_active = true
			hold_screen = event.position
			click_at(event.position)
		elif not event.pressed and event.index == touch_index:
			touch_index = -1
			hold_active = false
	elif event is InputEventScreenDrag and event.index == touch_index:
		hold_screen = event.position


func click_at(screen_pos: Vector2) -> void:
	var p = pick_ground(screen_pos)
	if p != null:
		move_to(p)
		_show_marker(last_target)


func pick_ground(screen_pos: Vector2):
	## 屏幕坐标 → 地面上的点：先对地面碰撞层做射线检测，没打中就与 y = 0 平面求交。
	if camera == null:
		return null
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 200.0, LAYER_GROUND)
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	if not r.is_empty():
		return r.position
	var hit = Plane(Vector3.UP, 0.0).intersects_ray(from, dir)
	return hit


func move_to(p: Vector3) -> void:
	var map := get_world_3d().navigation_map
	last_target = NavigationServer3D.map_get_closest_point(map, p)
	agent.target_position = last_target
	moving_to = true


func stop() -> void:
	moving_to = false
	hold_active = false
	agent.target_position = global_position


func _show_marker(p: Vector3) -> void:
	marker.global_position = p + Vector3(0, 0.03, 0)
	marker.visible = true
	marker.scale = Vector3.ONE
	var mat := marker.material_override as StandardMaterial3D
	mat.albedo_color.a = 0.9


# ---------------- 移动 ----------------

func camera_relative(v: Vector2) -> Vector3:
	## 屏幕方向 → 世界方向：v.y < 0 是「屏幕上方」（远离相机），v.x > 0 是屏幕右方。
	var yaw := deg_to_rad(camera.yaw_deg if camera else 45.0)
	var forward := Vector3(-sin(yaw), 0, -cos(yaw))
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	return right * v.x + forward * (-v.y)


func _physics_process(delta: float) -> void:
	var dir := Vector3.ZERO
	var kb := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var s := stick if stick.length() > 0.15 else kb
	if s.length() > 0.15:
		moving_to = false
		hold_active = false
		dir = camera_relative(s.limit_length(1.0))
	else:
		if hold_active:
			hold_timer -= delta
			if hold_timer <= 0.0:
				hold_timer = HOLD_REFRESH
				var p = pick_ground(hold_screen)
				if p != null:
					move_to(p)
		if moving_to:
			# 到达判定按水平距离自己算：导航网格表面按格子高度量化，比地面略高，
			# NavigationAgent3D 的三维距离可能永远达不到阈值（1.3 实测 is_navigation_finished 不会变 true）。
			var flat := Vector2(global_position.x - last_target.x, global_position.z - last_target.z)
			if flat.length() < ARRIVE_DIST:
				moving_to = false
				if not hold_active:
					arrived.emit()
					print("EF_ARRIVED x=%.2f z=%.2f" % [global_position.x, global_position.z])
			else:
				var nxt := agent.get_next_path_position()
				var to := nxt - global_position
				to.y = 0.0
				if to.length() > 0.01:
					dir = to.normalized()
	velocity = dir * speed
	move_and_slide()
	global_position.y = 0.0
	if dir.length() > 0.05:
		rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), 1.0 - exp(-14.0 * delta))
	if marker.visible:
		var mat := marker.material_override as StandardMaterial3D
		mat.albedo_color.a -= delta * 1.6
		marker.scale *= 1.0 + delta * 0.8
		if mat.albedo_color.a <= 0.0:
			marker.visible = false
