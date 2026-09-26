class_name Npc
extends Node3D
## 烬原镇的人物（P7）：老祭司伊莲、铁匠格伦、药剂师玛拉（V0.1 genTown 的 npcs）。
## P8 加上学徒托比（交了「铁匠的学徒」后回到镇上）。
## 点他们走过去对话（Player.talk_target）；头顶显示名字与任务提示（「!」有新任务、「?」可以交任务，Quests.mark）。外观是占位几何体。

const TALK_RANGE := 2.4

var npc_id := ""
var npc_name := ""
var glyph := ""
var look := ""
var label: Label3D
var mark: Label3D
var _t := 0.0
var _body: Node3D


static func make(d: Dictionary) -> Npc:
	var n := Npc.new()
	n.npc_id = d.id
	n.npc_name = d.name
	n.glyph = d.glyph
	n.look = d.get("look", "")
	n.name = "Npc_" + String(d.id)
	return n


func _ready() -> void:
	add_to_group("npc")
	_t = randf() * 5.0
	_body = Node3D.new()
	add_child(_body)
	var robe: Color = {"priest": Color(0.82, 0.8, 0.74), "smith": Color(0.38, 0.26, 0.16), "alch": Color(0.24, 0.36, 0.26), "boy": Color(0.5, 0.4, 0.26)}.get(look, Color(0.5, 0.45, 0.4))
	if look == "boy":
		_body.scale = Vector3.ONE * 0.78
	var skin := Color(0.78, 0.62, 0.5)
	_part(LowPoly.cylinder(0.2, 0.34, 1.35), Vector3(0, 0.68, 0), robe)
	_part(LowPoly.sphere(0.19), Vector3(0, 1.55, 0), skin)
	match look:
		"priest":
			_part(LowPoly.cylinder(0.08, 0.24, 0.3), Vector3(0, 1.72, -0.02), robe.darkened(0.1))      # 兜帽
			_part(LowPoly.cylinder(0.025, 0.025, 1.7), Vector3(0.32, 0.85, 0.1), Color(0.45, 0.32, 0.18)) # 手杖
			_part(LowPoly.sphere(0.07), Vector3(0.32, 1.72, 0.1), Color(1.0, 0.7, 0.3), 3.0)             # 杖头的圣焰
		"smith":
			_part(LowPoly.cylinder(0.3, 0.3, 0.5), Vector3(0, 1.15, 0), Color(0.3, 0.2, 0.12))          # 皮坎肩
			var hammer := _part(EnemyBase.box(Vector3(0.08, 0.7, 0.08)), Vector3(0.36, 0.95, 0.15), Color(0.4, 0.28, 0.16))
			hammer.rotation_degrees.x = 20
			_part(EnemyBase.box(Vector3(0.26, 0.14, 0.14)), Vector3(0.36, 1.3, 0.28), Color(0.5, 0.5, 0.54))
		"alch":
			_part(LowPoly.sphere(0.13), Vector3(-0.28, 0.9, 0.12), Color(0.45, 0.3, 0.2))              # 挎包
			_part(LowPoly.sphere(0.06), Vector3(0.3, 1.05, 0.2), Color(0.3, 0.9, 0.5), 2.0)            # 手里的药瓶
		"boy":
			_part(LowPoly.cylinder(0.17, 0.2, 0.12), Vector3(0, 1.66, 0), Color(0.3, 0.2, 0.12))        # 乱蓬蓬的头发
			_part(EnemyBase.box(Vector3(0.36, 0.14, 0.05)), Vector3(0, 0.9, 0.3), Color(0.25, 0.18, 0.12)) # 皮围裙
	add_child(Look.blob_shadow(0.4))
	label = Label3D.new()
	label.text = npc_name
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0011
	label.font_size = 20
	label.outline_size = 8
	label.modulate = Color(1.0, 0.85, 0.5)
	label.position.y = 2.15
	add_child(label)
	mark = Label3D.new()
	mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	mark.no_depth_test = true
	mark.fixed_size = true
	mark.pixel_size = 0.0016
	mark.font_size = 36
	mark.outline_size = 8
	mark.modulate = Color(1.0, 0.85, 0.2)
	mark.position.y = 2.8
	add_child(mark)


## 头顶任务提示（「!」「?」或空）
func set_mark(m: String) -> void:
	mark.text = m
	mark.modulate = Color(1.0, 0.85, 0.2) if m == "!" else Color(0.75, 0.9, 1.0)


func _part(mesh: Mesh, pos: Vector3, c: Color, glow := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = glow
	Look.rim(m, 0.25)
	mi.material_override = m
	mi.position = pos
	_body.add_child(mi)
	return mi


## V0.1 的朝向是平面角（格子坐标 x 向右、y 向下）
func face_v01(a: float) -> void:
	rotation.y = atan2(cos(a), sin(a))


func _process(delta: float) -> void:
	_t += delta
	_body.position.y = sin(_t * 1.6) * 0.015
