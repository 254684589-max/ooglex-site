class_name StreetLamp
extends Node3D
## 街灯（TECH.md 4.6）：木灯柱 + 横臂 + 吊着的灯笼（暖色玻璃）+ 一盏真实点光源 + 光晕。
## 火光轻微闪烁；系统「减少动态效果」时不闪。整条街的实时点光源不超过 4 盏（视野内预算）。

const HEIGHT := 3.4
const ENERGY := 2.0
const RANGE := 10.0

var light: OmniLight3D
var flicker := true
var t := 0.0
var seed_offset := 0.0


func _ready() -> void:
	add_to_group("street_lamp")
	seed_offset = randf() * 10.0
	var kit := MeshKit.new()
	kit.box("timber", Vector3(0, HEIGHT / 2, 0), Vector3(0.16, HEIGHT, 0.16), Basis.IDENTITY, 0.9, 0.55)
	kit.box("stone", Vector3(0, 0.2, 0), Vector3(0.4, 0.4, 0.4), Basis.IDENTITY, 0.8, 0.5)
	kit.box("timber", Vector3(0, HEIGHT - 0.1, -0.45), Vector3(0.1, 0.1, 1.0))
	kit.box("timber", Vector3(0, HEIGHT - 0.32, -0.25), Vector3(0.06, 0.4, 0.06), Basis(Vector3.RIGHT, deg_to_rad(-45)))
	kit.box("glass_lit", Vector3(0, HEIGHT - 0.42, -0.85), Vector3(0.24, 0.32, 0.24), Basis.IDENTITY, 1.0, 1.0, true)
	kit.box("timber", Vector3(0, HEIGHT - 0.23, -0.85), Vector3(0.32, 0.06, 0.32))
	kit.box("timber", Vector3(0, HEIGHT - 0.6, -0.85), Vector3(0.3, 0.04, 0.3))
	var mi := kit.build({"timber": Look.mat("timber"), "stone": Look.mat("stone"), "glass_lit": Look.glass_lit()})
	add_child(mi)
	var halo := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.6, 1.6)
	var hm := Look.halo(Look.LAMP_COLOR, 0.6).duplicate() as StandardMaterial3D
	hm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	q.material = hm
	halo.mesh = q
	halo.position = Vector3(0, HEIGHT - 0.42, -0.85)
	add_child(halo)
	light = OmniLight3D.new()
	light.light_color = Look.LAMP_COLOR
	light.light_energy = ENERGY
	light.omni_range = RANGE
	light.omni_attenuation = 1.2
	light.position = Vector3(0, HEIGHT - 0.6, -0.85)
	add_child(light)
	# 碰撞：灯柱
	var body := StaticBody3D.new()
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.4, HEIGHT, 0.4)
	cs.shape = bs
	cs.position.y = HEIGHT / 2
	body.add_child(cs)
	add_child(body)


func _process(delta: float) -> void:
	if not flicker:
		light.light_energy = ENERGY
		return
	t += delta
	var k := sin(t * 7.3 + seed_offset) * 0.04 + sin(t * 13.1 + seed_offset * 2.0) * 0.03
	light.light_energy = ENERGY * (1.0 + k)
