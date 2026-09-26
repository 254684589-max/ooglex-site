class_name InteractSpot
extends Node3D
## 可以点的东西（P8，对应 V0.1 useProp 里的 wp / portal / well）：点它，主角走到跟前后使用（Player.talk_target → main._use_spot）。
##   wp     传送石：打开楼层列表，传到到过的任何一层（外观由 TownBuilder 搭，这里只加名字）
##   well   水井：回满生命（V0.1）
##   portal 回城卷轴打开的蓝色传送门（这里搭外观）：地下那一头通往镇上，镇上那一头通回原处；走进门里也会直接使用
## 外观是程序生成的占位几何体。

const PORTAL_ENTER := 0.8      # 走到离传送门中心这么近就直接穿过去（米）

var kind := ""
var caption := ""
var to := ""                   # 传送门：「town」地下通往镇上 /「dungeon」镇上通回原处
var use_range := 1.9           # 走到这么近开始使用（米）
var pick_heights := [0.5, 1.2]
var label: Label3D
var _ring: MeshInstance3D
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
	return s


func _ready() -> void:
	add_to_group("interact")
	if kind == "portal":
		_build_portal()
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


func _process(delta: float) -> void:
	if _ring:
		_t += delta
		_ring.position.y = sin(_t * 2.0) * 0.03
