class_name CharacterModel
extends Node3D
## 用基础几何体拼出来的占位人物（玩家与 NPC 共用），带赛博朋克风的发光条。
## 模型正面朝 -Z。动画由 AnimationController 驱动：它只调用这里的关节节点（hips / head / 四肢）。
## 以后换成正式骨骼模型时，保留 apply_look() 与关节接口（或让 AnimationController 改用 AnimationPlayer）即可。
## 同一关节下的所有零件合并成一个顶点色网格（发光零件另成一个），一个人大约 10 次绘制调用。

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
## 关节节点 → 零件列表 {mesh, xf, col, tag, glow}；tag 为 shirt / pants 的零件换衣服时改色
var _parts: Dictionary = {}
var _mis: Dictionary = {}
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
	# 躯干：胸腔（圆润的胶囊，前后压扁）+ 腰 + 肩
	_part(torso, "capsule", Vector3(0.44, 0.66, 0.26), Vector3(0, 0.33, 0), shirt_color, Vector3.ZERO, "shirt")
	_part(torso, "capsule", Vector3(0.56, 0.2, 0.26), Vector3(0, 0.54, 0), shirt_color, Vector3(0, 0, PI * 0.5), "shirt")
	# 发光条（赛博朋克外套的灯带）
	_part(torso, "glow", Vector3(0.03, 0.46, 0.02), Vector3(0.12, 0.33, -0.135), accent_color)
	_part(hips, "capsule", Vector3(0.4, 0.26, 0.25), Vector3(0, 0.0, 0), pants_color, Vector3.ZERO, "pants")
	_part(hips, "box", Vector3(0.41, 0.05, 0.255), Vector3(0, 0.08, 0), Color(0.08, 0.07, 0.07))
	head_pivot = Node3D.new()
	head_pivot.name = "Head"
	head_pivot.position = Vector3(0, 0.62, 0)
	torso.add_child(head_pivot)
	_part(head_pivot, "cylinder", Vector3(0.1, 0.12, 0.11), Vector3(0, 0.03, 0), skin_color)
	_part(head_pivot, "sphere", Vector3(0.22, 0.27, 0.25), Vector3(0, 0.2, 0), skin_color)
	# 下颌、鼻子、耳朵、眼睛、眉毛
	_part(head_pivot, "sphere", Vector3(0.17, 0.12, 0.17), Vector3(0, 0.12, -0.025), skin_color)
	_part(head_pivot, "box", Vector3(0.03, 0.05, 0.04), Vector3(0, 0.19, -0.125), skin_color.darkened(0.05))
	for sx in [-1.0, 1.0]:
		_part(head_pivot, "sphere", Vector3(0.035, 0.06, 0.03), Vector3(sx * 0.11, 0.2, 0.0), skin_color.darkened(0.08))
		_part(head_pivot, "sphere", Vector3(0.03, 0.022, 0.012), Vector3(sx * 0.047, 0.225, -0.117), Color(0.06, 0.05, 0.05))
		_part(head_pivot, "box", Vector3(0.05, 0.012, 0.012), Vector3(sx * 0.048, 0.252, -0.117), hair_color)
	_part(head_pivot, "box", Vector3(0.05, 0.012, 0.01), Vector3(0, 0.14, -0.118), Color(0.55, 0.3, 0.28))
	# 头发：盖住头顶与后脑
	_part(head_pivot, "sphere", Vector3(0.235, 0.2, 0.26), Vector3(0, 0.29, 0.015), hair_color)
	_part(head_pivot, "sphere", Vector3(0.22, 0.2, 0.12), Vector3(0, 0.22, 0.07), hair_color)
	hat_node = Node3D.new()
	hat_node.position = Vector3(0, 0.32, 0)
	head_pivot.add_child(hat_node)
	set_hat(hat)
	arm_l = _limb(torso, Vector3(-0.28, 0.55, 0), 0.58, 0.11, shirt_color, skin_color)
	arm_r = _limb(torso, Vector3(0.28, 0.55, 0), 0.58, 0.11, shirt_color, skin_color)
	hand_r = Node3D.new()
	hand_r.position = Vector3(0, -0.62, 0)
	arm_r.add_child(hand_r)
	leg_l = _limb(self, Vector3(-0.12, 0.95, 0), 0.88, 0.17, pants_color, shoe_color, true)
	leg_r = _limb(self, Vector3(0.12, 0.95, 0), 0.88, 0.17, pants_color, shoe_color, true)
	for n in _parts:
		_flush(n)


func _part(parent: Node3D, mesh_type: String, size: Vector3, pos: Vector3, col: Color, rot := Vector3.ZERO, tag := "") -> void:
	var mesh: PrimitiveMesh
	var sc := Vector3.ONE
	if mesh_type == "box" or mesh_type == "glow":
		var bm := BoxMesh.new()
		bm.size = size
		mesh = bm
	elif mesh_type == "sphere":
		var sm := SphereMesh.new()
		sm.radius = size.x * 0.5
		sm.height = size.y
		sm.radial_segments = 12
		sm.rings = 6
		mesh = sm
		sc = Vector3(1, 1, size.z / maxf(size.x, 0.001))
	elif mesh_type == "capsule":
		var cm := CapsuleMesh.new()
		cm.radius = size.x * 0.5 if rot == Vector3.ZERO else size.y * 0.5
		cm.height = maxf(size.y if rot == Vector3.ZERO else size.x, cm.radius * 2.0)
		cm.radial_segments = 12
		cm.rings = 4
		mesh = cm
		if rot == Vector3.ZERO:
			sc = Vector3(1, 1, size.z / maxf(size.x, 0.001))
	elif mesh_type == "dome":
		var hm := SphereMesh.new()
		hm.radius = size.x * 0.5
		hm.height = size.y
		hm.is_hemisphere = true
		hm.radial_segments = 14
		hm.rings = 5
		mesh = hm
	else:
		var cy := CylinderMesh.new()
		cy.top_radius = size.x * 0.5
		cy.bottom_radius = size.z * 0.5
		cy.height = size.y
		cy.radial_segments = 12
		mesh = cy
	var xf := Transform3D(Basis.from_euler(rot) * Basis.from_scale(sc), pos)
	if not _parts.has(parent):
		_parts[parent] = []
	(_parts[parent] as Array).append({"mesh": mesh, "xf": xf, "col": col, "tag": tag, "glow": mesh_type == "glow"})


## 把一个关节下的零件合并成网格（普通 + 发光各一个）
func _flush(parent: Node3D) -> void:
	for mi in _mis.get(parent, []):
		(mi as Node).queue_free()
	var made: Array = []
	for glow in [false, true]:
		var verts := PackedVector3Array()
		var norms := PackedVector3Array()
		var cols := PackedColorArray()
		var idx := PackedInt32Array()
		for part in _parts.get(parent, []):
			if bool(part["glow"]) != glow:
				continue
			var arr: Array = (part["mesh"] as PrimitiveMesh).get_mesh_arrays()
			var xf: Transform3D = part["xf"]
			var nb := xf.basis.inverse().transposed()
			var base := verts.size()
			var col: Color = part["col"]
			for v in arr[Mesh.ARRAY_VERTEX] as PackedVector3Array:
				verts.append(xf * v)
				cols.append(col)
			for nn in arr[Mesh.ARRAY_NORMAL] as PackedVector3Array:
				norms.append((nb * nn).normalized())
			for i in arr[Mesh.ARRAY_INDEX] as PackedInt32Array:
				idx.append(base + i)
		if verts.is_empty():
			continue
		var out := []
		out.resize(Mesh.ARRAY_MAX)
		out[Mesh.ARRAY_VERTEX] = verts
		out[Mesh.ARRAY_NORMAL] = norms
		out[Mesh.ARRAY_COLOR] = cols
		out[Mesh.ARRAY_INDEX] = idx
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
		var mi := MeshInstance3D.new()
		mi.mesh = am
		mi.material_override = Mats.batch("neon" if glow else "skin")
		if draw_distance > 0.0:
			mi.visibility_range_end = draw_distance
		if not casts_shadow or glow:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
		made.append(mi)
	_mis[parent] = made


func _limb(parent: Node3D, joint: Vector3, length: float, thick: float, col: Color, end_col: Color, is_leg := false) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = joint
	parent.add_child(pivot)
	_part(pivot, "capsule", Vector3(thick, length + thick * 0.4, thick * 1.05), Vector3(0, -length * 0.5, 0), col, Vector3.ZERO, "pants" if is_leg else "shirt")
	if is_leg:
		# 鞋：前端圆头 + 鞋底
		_part(pivot, "capsule", Vector3(thick * 1.3, 0.1, thick * 1.05), Vector3(0, -length + 0.02, -thick * 0.35), end_col, Vector3(PI * 0.5, 0, 0))
		_part(pivot, "box", Vector3(thick * 1.1, 0.03, thick * 1.9), Vector3(0, -length - 0.03, -thick * 0.3), Color(0.85, 0.85, 0.82))
	else:
		_part(pivot, "capsule", Vector3(thick * 0.85, 0.16, thick * 0.6), Vector3(0, -length - 0.04, 0), end_col)
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
	for n in _parts:
		var changed := false
		for part in _parts[n]:
			if part["tag"] == "shirt":
				part["col"] = shirt
				changed = true
			elif part["tag"] == "pants":
				part["col"] = pants
				changed = true
		if changed and _built:
			_flush(n)


func set_hat(kind: String) -> void:
	hat = kind
	if hat_node == null:
		return
	_parts[hat_node] = []
	match kind:
		"yellow":
			_part(hat_node, "dome", Vector3(0.33, 0.165, 0.33), Vector3(0, -0.04, 0), Color(0.98, 0.78, 0.1))
		"visor":
			_part(hat_node, "glow", Vector3(0.28, 0.06, 0.05), Vector3(0, -0.1, -0.13), accent_color)
	_flush(hat_node)
