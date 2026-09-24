class_name CharacterModel
extends Node3D
## 用基础几何体拼出来的占位人物（玩家与 NPC 共用），带赛博朋克风的发光条。
## 模型正面朝 -Z。动画由 AnimationController 驱动：它只调用这里的关节节点（hips / head / 四肢）。
## 以后换成正式骨骼模型时，保留 apply_look() 与关节接口（或让 AnimationController 改用 AnimationPlayer）即可。

@export var skin_color := Color(0.87, 0.68, 0.52)
@export var shirt_color := Color(0.2, 0.36, 0.6)
@export var pants_color := Color(0.18, 0.2, 0.26)
@export var shoe_color := Color(0.1, 0.1, 0.12)
@export var hair_color := Color(0.08, 0.07, 0.07)
@export var accent_color := Color(0.13, 0.9, 1.0)
@export var hat := "none"
@export var body_scale := 1.0
## 远处不渲染（米，0 = 不限制）；NPC 与路人关闭阴影以减少绘制调用
@export var draw_distance := 0.0
@export var casts_shadow := true

var hips: Node3D
var torso: Node3D
var head_pivot: Node3D
var hat_node: Node3D
var arm_l: Node3D
var arm_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var hand_r: Node3D
var _shirt_parts: Array = []
var _pants_parts: Array = []
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
	torso = Node3D.new()
	hips.add_child(torso)
	_shirt_parts.append(_part(torso, "box", Vector3(0.46, 0.58, 0.26), Vector3(0, 0.31, 0), shirt_color))
	# 发光条（赛博朋克外套的灯带）
	_part(torso, "glow", Vector3(0.03, 0.5, 0.02), Vector3(0.14, 0.33, -0.135), accent_color)
	_pants_parts.append(_part(hips, "box", Vector3(0.42, 0.14, 0.24), Vector3(0, 0.0, 0), pants_color))
	head_pivot = Node3D.new()
	head_pivot.name = "Head"
	head_pivot.position = Vector3(0, 0.62, 0)
	torso.add_child(head_pivot)
	_part(head_pivot, "box", Vector3(0.1, 0.08, 0.1), Vector3(0, 0.03, 0), skin_color)
	_part(head_pivot, "sphere", Vector3(0.26, 0.3, 0.26), Vector3(0, 0.2, 0), skin_color)
	_part(head_pivot, "box", Vector3(0.035, 0.035, 0.02), Vector3(-0.055, 0.22, -0.125), Color(0.08, 0.07, 0.07))
	_part(head_pivot, "box", Vector3(0.035, 0.035, 0.02), Vector3(0.055, 0.22, -0.125), Color(0.08, 0.07, 0.07))
	_part(head_pivot, "sphere", Vector3(0.27, 0.16, 0.27), Vector3(0, 0.3, 0.02), hair_color)
	hat_node = Node3D.new()
	hat_node.position = Vector3(0, 0.32, 0)
	head_pivot.add_child(hat_node)
	set_hat(hat)
	arm_l = _limb(torso, Vector3(-0.3, 0.55, 0), 0.58, 0.12, shirt_color, skin_color)
	arm_r = _limb(torso, Vector3(0.3, 0.55, 0), 0.58, 0.12, shirt_color, skin_color)
	hand_r = Node3D.new()
	hand_r.position = Vector3(0, -0.62, 0)
	arm_r.add_child(hand_r)
	leg_l = _limb(self, Vector3(-0.12, 0.95, 0), 0.88, 0.17, pants_color, shoe_color, true)
	leg_r = _limb(self, Vector3(0.12, 0.95, 0), 0.88, 0.17, pants_color, shoe_color, true)


func _part(parent: Node3D, mesh_type: String, size: Vector3, pos: Vector3, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh
	if mesh_type == "box" or mesh_type == "glow":
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
	mi.material_override = Mats.glow(col) if mesh_type == "glow" else Mats.color(col)
	mi.position = pos
	if draw_distance > 0.0:
		mi.visibility_range_end = draw_distance
	if not casts_shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _limb(parent: Node3D, joint: Vector3, length: float, thick: float, col: Color, end_col: Color, is_leg := false) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = joint
	parent.add_child(pivot)
	var seg := _part(pivot, "box", Vector3(thick, length, thick * 1.05), Vector3(0, -length * 0.5, 0), col)
	if is_leg:
		_pants_parts.append(seg)
		_part(pivot, "box", Vector3(thick * 1.05, 0.08, thick * 1.7), Vector3(0, -length, -thick * 0.3), end_col)
	else:
		_shirt_parts.append(seg)
		_part(pivot, "sphere", Vector3(thick * 1.1, thick * 1.1, thick * 1.1), Vector3(0, -length - 0.02, 0), end_col)
	return pivot


## 外观数据：{"skin": "#..", "shirt": "#..", "pants": "#..", "hair": "#..", "hat": "yellow"}
func apply_look(look: Dictionary) -> void:
	skin_color = Mats.hex(String(look.get("skin", "")), skin_color)
	shirt_color = Mats.hex(String(look.get("shirt", "")), shirt_color)
	pants_color = Mats.hex(String(look.get("pants", "")), pants_color)
	hair_color = Mats.hex(String(look.get("hair", "")), hair_color)
	hat = String(look.get("hat", hat))


## 换衣服：只改上衣和裤子颜色
func set_clothes(shirt: Color, pants: Color) -> void:
	shirt_color = shirt
	pants_color = pants
	for p in _shirt_parts:
		(p as MeshInstance3D).material_override = Mats.color(shirt)
	for p in _pants_parts:
		(p as MeshInstance3D).material_override = Mats.color(pants)


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
		"visor":
			_part(hat_node, "glow", Vector3(0.28, 0.06, 0.05), Vector3(0, -0.1, -0.13), accent_color)
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
