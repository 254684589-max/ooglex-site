class_name InteractSpot
extends Node3D
## 可以点的东西（P8，对应 V0.1 useProp 里的 wp / portal / well）：点它，主角走到跟前后使用（Player.talk_target → main._use_spot）。
##   wp     传送石：打开楼层列表，传到到过的任何一层（外观由 TownBuilder 搭，这里只加名字）
##   well   水井：回满生命（V0.1）
##   portal 回城卷轴打开的蓝色传送门（这里搭外观）：地下那一头通往镇上，镇上那一头通回原处；走进门里也会直接使用
##   barrel 木桶、chest 宝箱、shrine 神殿（P10，地下城房间里；这里搭外观）：用过后 set_used()，不能再点
## 外观是程序生成的占位几何体。

const PORTAL_ENTER := 0.8      # 走到离传送门中心这么近就直接穿过去（米）

var kind := ""
var caption := ""
var to := ""                   # 传送门：「town」地下通往镇上 /「dungeon」镇上通回原处
var use_range := 1.9           # 走到这么近开始使用（米）
var pick_heights := [0.5, 1.2]
var index := -1                # 地下城道具在本层 props 里的下标（P10：记住哪些已经用过）
var used := false
var label: Label3D
var _ring: MeshInstance3D
var _lid: Node3D
var _glow: MeshInstance3D
var _glow_light: OmniLight3D
var _t := 0.0


static func make(kind_: String, caption_: String = "", to_: String = "") -> InteractSpot:
	var s := InteractSpot.new()
	s.kind = kind_
	s.caption = caption_
	s.to = to_
	s.name = "Spot_" + kind_ + ("_" + to_ if to_ != "" else "")
	if kind_ == "portal":
		s.use_range = PORTAL_ENTER
		s.pick_heights = [0.4, 1.1, 1.9]
	elif kind_ == "well":
		s.use_range = 1.8
	elif kind_ in ["barrel", "chest"]:
		s.use_range = 1.5
		s.pick_heights = [0.3, 0.7]
	elif kind_ == "shrine":
		s.use_range = 1.7
		s.pick_heights = [0.6, 1.3]
	return s


func _ready() -> void:
	add_to_group("interact")
	if kind == "portal":
		_build_portal()
	elif kind == "barrel":
		_build_barrel()
	elif kind == "chest":
		_build_chest()
	elif kind == "shrine":
		_build_shrine()
	if caption != "":
		label = Label3D.new()
		label.text = caption
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.fixed_size = true
		label.pixel_size = 0.0011
		label.font_size = 18
		label.outline_size = 8
		label.modulate = Color(0.55, 0.82, 1.0)
		label.position.y = 3.4 if kind == "portal" else 2.3
		add_child(label)


func _build_portal() -> void:
	# 竖立的蓝色椭圆光环 + 半透明的门面 + 蓝色点光源。门面朝向斜视角镜头（偏航 45°），
	# 竖向拉长放在只绕竖轴转的支点上，这样拉长的方向一定是竖直的
	var pivot := Node3D.new()
	# 镜头俯角 55°，竖直的东西看起来只剩约六成高：门拉长到 1.8 倍并往后仰 25°，看起来才像一道竖着的门
	pivot.position.y = 1.5
	pivot.rotation_degrees = Vector3(-25, 45, 0)
	pivot.scale = Vector3(1.0, 1.8, 1.0)
	add_child(pivot)
	_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.72
	tm.outer_radius = 0.86
	tm.rings = 24
	tm.ring_segments = 6
	_ring.mesh = tm
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Color(0.45, 0.8, 1.0)
	_ring.material_override = rm
	_ring.rotation_degrees.x = 90
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(_ring)
	var face := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.72
	cm.bottom_radius = 0.72
	cm.height = 0.02
	cm.radial_segments = 20
	cm.rings = 1
	face.mesh = cm
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.albedo_color = Color(0.25, 0.55, 1.0, 0.45)
	fm.cull_mode = BaseMaterial3D.CULL_DISABLED
	face.material_override = fm
	face.rotation_degrees.x = 90
	face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(face)
	var light := OmniLight3D.new()
	light.light_color = Color(0.4, 0.7, 1.0)
	light.light_energy = 1.6
	light.omni_range = 5.0
	light.position.y = 1.2
	add_child(light)
	add_child(Look.blob_shadow(0.7))


func _part(mesh: Mesh, pos: Vector3, c: Color, parent: Node3D = self, glow := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = glow
	Look.rim(m, 0.2)
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


func _build_barrel() -> void:
	var wood := Color(0.4, 0.26, 0.14)
	_part(LowPoly.cylinder(0.36, 0.36, 0.9), Vector3(0, 0.45, 0), wood)
	for y in [0.18, 0.72]:
		_part(LowPoly.cylinder(0.38, 0.38, 0.06), Vector3(0, y, 0), Color(0.22, 0.2, 0.2))   # 铁箍
	add_child(Look.blob_shadow(0.45))


func _build_chest() -> void:
	var wood := Color(0.45, 0.28, 0.13)
	var gold := Color(0.75, 0.58, 0.25)
	_part(EnemyBase.box(Vector3(0.9, 0.5, 0.55)), Vector3(0, 0.25, 0), wood)
	_part(EnemyBase.box(Vector3(0.94, 0.06, 0.59)), Vector3(0, 0.12, 0), gold)
	# 盖子绕后边的铰链打开
	_lid = Node3D.new()
	_lid.position = Vector3(0, 0.5, -0.275)
	add_child(_lid)
	_part(EnemyBase.box(Vector3(0.9, 0.2, 0.55)), Vector3(0, 0.1, 0.275), wood, _lid)
	_part(EnemyBase.box(Vector3(0.14, 0.14, 0.06)), Vector3(0, 0.02, 0.56), gold, _lid)       # 锁扣
	add_child(Look.blob_shadow(0.55))


func _build_shrine() -> void:
	# 石台 + 悬浮的蓝色晶石（用过后熄灭）
	var stone := Color(0.42, 0.4, 0.44)
	_part(LowPoly.cylinder(0.55, 0.65, 0.35), Vector3(0, 0.17, 0), stone)
	_part(LowPoly.cylinder(0.22, 0.3, 0.8), Vector3(0, 0.75, 0), stone)
	_glow = _part(LowPoly.sphere(0.2), Vector3(0, 1.4, 0), Color(0.45, 0.8, 1.0), self, 3.0)
	_glow_light = OmniLight3D.new()
	_glow_light.light_color = Color(0.45, 0.75, 1.0)
	_glow_light.light_energy = 1.2
	_glow_light.omni_range = 4.0
	_glow_light.position.y = 1.4
	add_child(_glow_light)
	add_child(Look.blob_shadow(0.6))


## 用过：宝箱开盖、神殿熄灭、木桶碎掉消失；之后不能再点
func set_used(animate := true) -> void:
	used = true
	remove_from_group("interact")
	match kind:
		"chest":
			if animate:
				create_tween().tween_property(_lid, "rotation_degrees:x", -105.0, 0.35).set_trans(Tween.TRANS_BACK)
			else:
				_lid.rotation_degrees.x = -105.0
		"shrine":
			(_glow.material_override as StandardMaterial3D).emission_energy_multiplier = 0.0
			(_glow.material_override as StandardMaterial3D).albedo_color = Color(0.25, 0.28, 0.32)
			_glow_light.visible = false
		"barrel":
			if animate:
				var tw := create_tween()
				tw.tween_property(self, "scale", Vector3(1.4, 0.15, 1.4), 0.18)
				tw.tween_callback(queue_free)
			else:
				queue_free()


func _process(delta: float) -> void:
	if _glow and not used:
		_t += delta
		_glow.position.y = 1.4 + sin(_t * 2.2) * 0.06
	if _ring:
		_t += delta
		_ring.position.y = sin(_t * 2.0) * 0.03
