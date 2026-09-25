class_name PlayerCamera
extends Node3D
## 第三人称跟随镜头：鼠标 / 触屏拖动旋转，SpringArm 防穿墙，
## 右键按住拉近，滚轮缩放。体力低时镜头轻微晃动。

@export var target_path: NodePath
@export var height := 1.55
@export var distance := 4.6
@export var min_distance := 2.2
@export var max_distance := 7.5
@export var aim_distance := 2.3
@export var follow_speed := 14.0
@export var mouse_sensitivity := 0.0032
@export var touch_sensitivity := 0.006
@export var min_pitch := -1.15
@export var max_pitch := 0.55

var yaw := 0.0
var pitch := -0.28
var sway := 0.0
var aiming := false

var target: Node3D
## 开车时跟随的车（镜头更高更远，车在动时自动转到车后方）
var vehicle: Node3D = null
var _walk_distance := 4.6
var _manual_t := 0.0
var _yaw_node: Node3D
var _pitch_node: Node3D
var _arm: SpringArm3D
var camera: Camera3D
var _sway_time := 0.0


func _ready() -> void:
	top_level = true
	_yaw_node = Node3D.new()
	_yaw_node.name = "Yaw"
	add_child(_yaw_node)
	_pitch_node = Node3D.new()
	_pitch_node.name = "Pitch"
	_yaw_node.add_child(_pitch_node)
	_arm = SpringArm3D.new()
	_arm.name = "SpringArm3D"
	_arm.spring_length = distance
	_arm.margin = 0.25
	_arm.collision_mask = 1
	var probe := SphereShape3D.new()
	probe.radius = 0.25
	_arm.shape = probe
	_pitch_node.add_child(_arm)
	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.fov = 70.0
	camera.near = 0.08
	camera.far = 1800.0
	_arm.add_child(camera)
	if target_path != NodePath():
		target = get_node_or_null(target_path)
	if target != null:
		_arm.add_excluded_object(target.get_rid())
		global_position = target.global_position + Vector3(0, height, 0)


func set_target(t: Node3D) -> void:
	target = t
	if t is CollisionObject3D:
		_arm.add_excluded_object(t.get_rid())
	snap()


func follow_vehicle(car: Node3D) -> void:
	if car != null:
		if vehicle == null:
			_walk_distance = distance
		vehicle = car
		target = car
		if car is CollisionObject3D:
			_arm.add_excluded_object(car.get_rid())
		distance = 7.5
		yaw = car.rotation.y
		pitch = -0.26
		snap()
	else:
		if vehicle is CollisionObject3D and is_instance_valid(vehicle):
			_arm.remove_excluded_object(vehicle.get_rid())
		vehicle = null
		distance = _walk_distance


func snap() -> void:
	if target != null:
		global_position = target.global_position + Vector3(0, height, 0)
	_apply_rotation()


func rotate_by(delta_yaw: float, delta_pitch: float) -> void:
	_manual_t = 1.5
	yaw -= delta_yaw
	pitch = clampf(pitch - delta_pitch, min_pitch, max_pitch)
	_apply_rotation()


func handle_mouse_motion(rel: Vector2) -> void:
	var s: float = mouse_sensitivity * float(SettingsManager.get_v("sensitivity", 1.0))
	var inv := -1.0 if bool(SettingsManager.get_v("invert_y", false)) else 1.0
	rotate_by(rel.x * s, rel.y * s * inv)


func handle_touch_drag(rel: Vector2) -> void:
	var s: float = touch_sensitivity * float(SettingsManager.get_v("sensitivity", 1.0))
	rotate_by(rel.x * s, rel.y * s)


func zoom(step: float) -> void:
	distance = clampf(distance + step, min_distance, max_distance + (4.0 if vehicle != null else 0.0))


## 水平面上镜头的前方向（玩家移动以此为参考）
func forward_flat() -> Vector3:
	return Vector3(-sin(yaw), 0, -cos(yaw))


func right_flat() -> Vector3:
	return Vector3(cos(yaw), 0, -sin(yaw))


func _apply_rotation() -> void:
	if _yaw_node == null:
		return
	_yaw_node.rotation = Vector3(0, yaw, 0)
	_pitch_node.rotation = Vector3(pitch, 0, 0)


func _process(delta: float) -> void:
	if target == null:
		return
	var goal := target.global_position + Vector3(0, height, 0)
	if vehicle != null and is_instance_valid(vehicle):
		goal = vehicle.global_position + Vector3(0, 2.2, 0)
		# 车在开、玩家一会儿没拖视角：镜头慢慢转到车后方
		_manual_t = maxf(_manual_t - delta, 0.0)
		var sp := absf(float(vehicle.get("speed")))
		if _manual_t <= 0.0 and sp > 2.0:
			var behind: float = vehicle.rotation.y + (PI if float(vehicle.get("speed")) < -2.0 else 0.0)
			yaw = lerp_angle(yaw, behind, clampf(delta * (1.0 + sp * 0.12), 0.0, 1.0))
			pitch = lerpf(pitch, -0.26, clampf(delta, 0.0, 1.0))
	global_position = global_position.lerp(goal, clampf(delta * follow_speed, 0.0, 1.0))
	var want := aim_distance if aiming else distance
	_arm.spring_length = lerpf(_arm.spring_length, want, clampf(delta * 8.0, 0.0, 1.0))
	# 右键瞄准时镜头略微偏右肩
	var offset_x := 0.45 if aiming else 0.0
	_arm.position.x = lerpf(_arm.position.x, offset_x, clampf(delta * 8.0, 0.0, 1.0))
	# 体力低：镜头晃动
	_sway_time += delta
	var s := sway * 0.05
	camera.rotation = Vector3(sin(_sway_time * 1.7) * s, 0, sin(_sway_time * 1.1) * s * 1.4)
	_apply_rotation()
