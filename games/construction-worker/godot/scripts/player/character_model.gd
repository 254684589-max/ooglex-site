class_name CharacterModel
extends Node3D
## 用基础几何体拼出来的人物模型 + 程序化走路动画。玩家与 NPC 共用。
## 模型正面朝 -Z。以后换成正式骨骼模型时，只要保留 animate() 与 set_hat() 接口即可。

@export var skin_color := Color(0.87, 0.68, 0.52)
@export var shirt_color := Color(0.2, 0.36, 0.6)
@export var pants_color := Color(0.18, 0.2, 0.26)
@export var shoe_color := Color(0.12, 0.1, 0.09)
@export var vest_color := Color(0, 0, 0, 0)
@export var hat := "none"
@export var belly := false
@export var body_scale := 1.0

var hips: Node3D
var head_pivot: Node3D
var hat_node: Node3D
var arm_l: Node3D
var arm_r: Node3D
var leg_l: Node3D
var leg_r: Node3D

var _phase := 0.0
var _move_amount := 0.0
var _carry_pose := ""
var _gesture := 0.0
var _gesture_kind := ""
var _built := false


func _ready() -> void:
	build()


func build() -> void:
	if _built:
		return
	_built = true
	scale = Vector3.ONE * body_scale
	hips = Node3D.new()
	hips.name = "Hips"
	hips.position = Vector3(0, 0.95, 0)
	add_child(hips)
	# 躯干
	_part(hips, "box", Vector3(0.46, 0.58, 0.26), Vector3(0, 0.31, 0), shirt_color)
	if belly:
		_part(hips, "sphere", Vector3(0.44, 0.4, 0.34), Vector3(0, 0.2, -0.06), shirt_color)
	if vest_color.a > 0.0:
		_part(hips, "box", Vector3(0.48, 0.44, 0.28), Vector3(0, 0.36, 0), vest_color)
		_part(hips, "box", Vector3(0.49, 0.05, 0.29), Vector3(0, 0.3, 0), Color(0.92, 0.92, 0.85))
	# 胯部
	_part(hips, "box", Vector3(0.42, 0.14, 0.24), Vector3(0, 0.0, 0), pants_color)
	# 头
	head_pivot = Node3D.new()
	head_pivot.name = "Head"
	head_pivot.position = Vector3(0, 0.62, 0)
	hips.add_child(head_pivot)
	_part(head_pivot, "box", Vector3(0.1, 0.08, 0.1), Vector3(0, 0.03, 0), skin_color)
	_part(head_pivot, "sphere", Vector3(0.26, 0.3, 0.26), Vector3(0, 0.2, 0), skin_color)
	# 眼睛（看出朝向）
	_part(head_pivot, "box", Vector3(0.035, 0.035, 0.02), Vector3(-0.055, 0.22, -0.125), Color(0.08, 0.07, 0.07))
	_part(head_pivot, "box", Vector3(0.035, 0.035, 0.02), Vector3(0.055, 0.22, -0.125), Color(0.08, 0.07, 0.07))
	# 头发
	_part(head_pivot, "sphere", Vector3(0.27, 0.16, 0.27), Vector3(0, 0.3, 0.02), Color(0.1, 0.09, 0.08))
	hat_node = Node3D.new()
	hat_node.name = "Hat"
	hat_node.position = Vector3(0, 0.32, 0)
	head_pivot.add_child(hat_node)
	set_hat(hat)
	# 手臂
	arm_l = _limb(hips, Vector3(-0.3, 0.55, 0), 0.58, 0.12, shirt_color, skin_color)
	arm_r = _limb(hips, Vector3(0.3, 0.55, 0), 0.58, 0.12, shirt_color, skin_color)
	# 腿
	leg_l = _limb(self, Vector3(-0.12, 0.95, 0), 0.88, 0.17, pants_color, shoe_color, true)
	leg_r = _limb(self, Vector3(0.12, 0.95, 0), 0.88, 0.17, pants_color, shoe_color, true)


func _part(parent: Node3D, mesh_type: String, size: Vector3, pos: Vector3, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh
	if mesh_type == "box":
		mesh = BoxMesh.new()
		mesh.size = size
	elif mesh_type == "sphere":
		mesh = SphereMesh.new()
		mesh.radius = size.x * 0.5
		mesh.height = size.y
		mesh.radial_segments = 12
		mesh.rings = 6
		mi.scale = Vector3(1, 1, size.z / maxf(size.x, 0.001))
	else:
		mesh = CylinderMesh.new()
		mesh.top_radius = size.x * 0.5
		mesh.bottom_radius = size.z * 0.5
		mesh.height = size.y
		mesh.radial_segments = 12
	mi.mesh = mesh
	mi.material_override = Mats.color(col)
	mi.position = pos
	parent.add_child(mi)
	return mi


## 四肢：以关节为轴心，向下延伸
func _limb(parent: Node3D, joint: Vector3, length: float, thick: float, col: Color, end_col: Color, is_leg := false) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = joint
	parent.add_child(pivot)
	_part(pivot, "box", Vector3(thick, length, thick * 1.05), Vector3(0, -length * 0.5, 0), col)
	if is_leg:
		_part(pivot, "box", Vector3(thick * 1.05, 0.08, thick * 1.7), Vector3(0, -length + 0.0, -thick * 0.3), end_col)
	else:
		_part(pivot, "sphere", Vector3(thick * 1.1, thick * 1.1, thick * 1.1), Vector3(0, -length - 0.02, 0), end_col)
	return pivot


func set_hat(kind: String) -> void:
	hat = kind
	if hat_node == null:
		return
	for c in hat_node.get_children():
		c.queue_free()
	var col := Color.WHITE
	match kind:
		"yellow":
			col = Color(0.98, 0.78, 0.1)
		"red":
			col = Color(0.85, 0.15, 0.12)
		"white":
			col = Color(0.95, 0.95, 0.93)
		"blue":
			col = Color(0.15, 0.4, 0.85)
		"chef":
			_part(hat_node, "cyl", Vector3(0.28, 0.2, 0.26), Vector3(0, 0.02, 0), Color(0.97, 0.97, 0.97))
			return
		_:
			return
	var dome := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.165
	sm.height = 0.165
	sm.is_hemisphere = true
	sm.radial_segments = 14
	sm.rings = 5
	dome.mesh = sm
	dome.material_override = Mats.color(col, 0.4)
	dome.position = Vector3(0, -0.04, 0)
	hat_node.add_child(dome)
	_part(hat_node, "cyl", Vector3(0.4, 0.025, 0.4), Vector3(0, -0.04, -0.02), col)
	_part(hat_node, "box", Vector3(0.03, 0.03, 0.3), Vector3(0, 0.11, 0), col.darkened(0.15))


## pose: "" 空手；"stack" 抱在胸前；"shoulder"/"bundle" 扛在肩上
func set_carry_pose(pose: String) -> void:
	_carry_pose = pose


func gesture(kind: String) -> void:
	_gesture_kind = kind
	_gesture = 1.0


## speed：水平速度（米/秒）
func animate(delta: float, speed: float, on_floor := true) -> void:
	if not _built:
		return
	var target_amount := clampf(speed / 4.0, 0.0, 1.4)
	_move_amount = lerpf(_move_amount, target_amount, clampf(delta * 8.0, 0.0, 1.0))
	_phase += delta * (4.0 + speed * 1.6) * (1.0 if _move_amount > 0.05 else 0.0)
	var swing := sin(_phase) * 0.62 * minf(_move_amount, 1.0)
	if not on_floor:
		swing = 0.35
	leg_l.rotation.x = swing
	leg_r.rotation.x = -swing if on_floor else -0.2
	var bob := absf(sin(_phase)) * 0.045 * minf(_move_amount, 1.0)
	var breathe := sin(Time.get_ticks_msec() / 700.0) * 0.008
	hips.position.y = 0.95 + bob + breathe
	match _carry_pose:
		"stack":
			arm_l.rotation = Vector3(1.25, 0, 0.18)
			arm_r.rotation = Vector3(1.25, 0, -0.18)
		"shoulder", "bundle":
			arm_r.rotation = Vector3(2.7, 0, 0.35)
			arm_l.rotation = Vector3(-swing * 0.7, 0, 0.08)
		_:
			arm_l.rotation = Vector3(-swing * 0.8, 0, 0.08)
			arm_r.rotation = Vector3(swing * 0.8, 0, -0.08)
	# 手势（弯腰拿东西 / 点头）
	if _gesture > 0.0:
		_gesture = maxf(0.0, _gesture - delta * 2.2)
		var g := sin((1.0 - _gesture) * PI)
		match _gesture_kind:
			"pickup":
				hips.rotation.x = -g * 0.55
			"nod":
				head_pivot.rotation.x = -g * 0.3
			"wave":
				arm_r.rotation = Vector3(2.6 + sin(_gesture * 18.0) * 0.3, 0, -0.5)
	else:
		hips.rotation.x = lerpf(hips.rotation.x, 0.0, clampf(delta * 10.0, 0.0, 1.0))
		head_pivot.rotation.x = lerpf(head_pivot.rotation.x, 0.0, clampf(delta * 10.0, 0.0, 1.0))
