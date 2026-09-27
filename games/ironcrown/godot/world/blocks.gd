class_name Blocks
extends RefCounted
## 灰盒搭建工具：带碰撞的盒子、材质、场景标签。所有灰盒都是占位几何体（1.4 起逐步换成正式的场景件）。

const FONT_PATH := "res://assets/fonts/NotoSansSC-IC.ttf"


static func mat(color: Color, emission := Color.BLACK, energy := 0.8) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	if emission != Color.BLACK:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = energy
	return m


## 放一个盒子；collide = true 时同时放一个静态碰撞体（物理层 1「世界」）。rot 是角度。
static func box(parent: Node, size: Vector3, pos: Vector3, material: Material, collide := true, rot := Vector3.ZERO) -> Node3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = material
	mi.mesh = bm
	if not collide:
		mi.position = pos
		mi.rotation_degrees = rot
		parent.add_child(mi)
		return mi
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation_degrees = rot
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)
	body.add_child(mi)
	parent.add_child(body)
	return body


static func label(parent: Node, text: String, pos: Vector3, size := 48, pixel := 0.006) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = load(FONT_PATH)
	l.font_size = size
	l.pixel_size = pixel
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.modulate = Color("e8dcc0")
	l.outline_size = 8
	l.position = pos
	parent.add_child(l)
	return l
