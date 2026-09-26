class_name Stairs
extends Area3D
## 楼梯（阶段 P2）：主角走进这一格就换层（V0.1：踩上楼梯格即换层）。
## 下楼 = 地面上一个黑洞 + 石框 + 往下渐暗的台阶；上楼 = 三级往上的石阶。
## 头顶飘一行字说明通往哪里。外观是程序生成的占位几何体。

signal used(kind: String)

const SIZE := 2.0

var kind := "down"            # "down" / "up"
var caption := ""
var label: Label3D


static func make(kind_: String, caption_: String) -> Stairs:
	var s := Stairs.new()
	s.kind = kind_
	s.caption = caption_
	s.name = "Stairs_" + kind_
	return s


func _ready() -> void:
	collision_layer = 0
	collision_mask = Layers.PLAYER
	monitoring = true
	monitorable = false
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(SIZE * 0.8, 2.0, SIZE * 0.8)
	shape.shape = box
	shape.position.y = 1.0
	add_child(shape)
	body_entered.connect(func(b): if b is Player: used.emit(kind))
	if kind == "down":
		_build_down()
	else:
		_build_up()
	label = Label3D.new()
	label.text = caption
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.008
	label.font_size = 40
	label.outline_size = 10
	label.modulate = Color(1.0, 0.8, 0.45)
	label.outline_modulate = Color(0.08, 0.04, 0.02)
	label.position.y = 2.6
	label.no_depth_test = true
	add_child(label)


func _unshaded(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	return m


func _slab(size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = pos
	mi.material_override = mat
	add_child(mi)


func _build_down() -> void:
	# 黑洞：一块不受光照的黑色面片，面片上三条由亮到暗的「台阶」，四周一圈低矮石框
	var hole := MeshInstance3D.new()
	var q := PlaneMesh.new()
	q.size = Vector2(SIZE, SIZE)
	hole.mesh = q
	hole.material_override = _unshaded(Color(0.0, 0.0, 0.0))
	hole.position.y = 0.012
	add_child(hole)
	for i in 3:
		var step := MeshInstance3D.new()
		var sq := PlaneMesh.new()
		sq.size = Vector2(SIZE * 0.84, SIZE * 0.2)
		step.mesh = sq
		var v := 0.2 - i * 0.06
		step.material_override = _unshaded(Color(v * 1.1, v * 0.95, v * 0.85))
		step.position = Vector3(0, 0.014, -SIZE * 0.3 + i * SIZE * 0.22)
		add_child(step)
	var frame := Look.wall_material(Color(1.1, 1.05, 1.0))
	var t := 0.22
	_slab(Vector3(SIZE + t, 0.25, t), Vector3(0, 0.125, -SIZE / 2), frame)
	_slab(Vector3(SIZE + t, 0.25, t), Vector3(0, 0.125, SIZE / 2), frame)
	_slab(Vector3(t, 0.25, SIZE), Vector3(-SIZE / 2, 0.125, 0), frame)
	_slab(Vector3(t, 0.25, SIZE), Vector3(SIZE / 2, 0.125, 0), frame)


func _build_up() -> void:
	# 三级往北升起的石阶（只是外观，不挡路）
	var mat := Look.wall_material(Color(1.15, 1.1, 1.05))
	for i in 3:
		var hgt := 0.16 * (i + 1)
		_slab(Vector3(SIZE * 0.9, hgt, SIZE * 0.28), Vector3(0, hgt / 2, SIZE * 0.3 - i * SIZE * 0.3), mat)
