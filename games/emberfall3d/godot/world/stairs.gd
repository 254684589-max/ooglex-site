class_name Stairs
extends Area3D
## 楼梯（阶段 P2）：主角走进这一格就换层（V0.1：踩上楼梯格即换层）。
## 外观（2.6 之七，代码搭的模型 PropModels「stairs_down」/「stairs_up」）：
##   下楼 = 三面石砌井栏 + 四根角柱，井口里四级一级比一级暗的台阶没入黑暗；上楼 = 四级往北升起的石阶、两侧扶墙，尽头一座门洞漆黑的石拱门。
##   石头用本层墙的写实材质（stone_material，由 DungeonBuilder 传入；没有就用地窖石墙），黑洞与往下的台阶不受光照。
## 头顶飘一行字说明通往哪里。只是外观，不挡路（主角走进这一格就换层）。

signal used(kind: String)

const SIZE := 2.0

var kind := "down"            # "down" / "up"
var caption := ""
var stone_material: Material  # 石头的材质（本层墙的写实材质）；null = 地窖石墙
var model: MeshInstance3D
var label: Label3D


static func make(kind_: String, caption_: String, stone: Material = null) -> Stairs:
	var s := Stairs.new()
	s.kind = kind_
	s.caption = caption_
	s.stone_material = stone
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
	_build_model()
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


func _build_model() -> void:
	var m: Dictionary = PropModels.get_model("stairs_down" if kind == "down" else "stairs_up")
	model = MeshInstance3D.new()
	model.name = "Model"
	model.mesh = m.mesh
	var stone: Material = stone_material if stone_material != null else Look.wall_material(Color(1.1, 1.05, 1.0))
	var dark := StandardMaterial3D.new()
	dark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dark.vertex_color_use_as_albedo = true
	var surfaces: Array = m.surfaces
	for i in surfaces.size():
		match surfaces[i]:
			RigBuilder.GLOW:
				model.set_surface_override_material(i, dark)
			RigBuilder.METAL:
				model.set_surface_override_material(i, CharRig.surface_material(RigBuilder.METAL, Color(0, 0, 0), 0.15))
			_:
				model.set_surface_override_material(i, stone)
	add_child(model)
