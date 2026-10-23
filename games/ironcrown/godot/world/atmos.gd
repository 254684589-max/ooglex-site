class_name Atmos
extends RefCounted
## 户外的气氛（2026-10-23 场景美化二）：烟囱冒烟、天上落雪。都是 CPU 粒子（网页兼容渲染器上 GPU 粒子不稳），贴图在代码里生成（不加外部素材）。
## 低画质时减半（main.apply_quality 调 Atmos.apply_quality）。

const SMOKE_GROUP := "chimney_smoke"
const SNOW_GROUP := "falling_snow"
const SMOKE_AMOUNT := 10
const SNOW_AMOUNT := 700
const SNOW_BOX := Vector3(13.0, 0.5, 13.0)       # 落雪的发射盒（半边长）：跟着玩家，头顶 9 米
const SNOW_HEIGHT := 9.0
const DRIFT_GROUP := "drift_snow"
const DRIFT_AMOUNT := 46
## 高地的风（5.1a，ART.md 第十节「天气是活的」）：西北风往东南吹，雪斜着落、贴地有一缕缕吹雪
const HIGHLAND_WIND := Vector3(1.5, 0.0, 1.1)


## 一团柔和的圆形贴图（中间不透明、边缘透明）
static func _soft_dot() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 64
	t.height = 64
	return t


## lit = 受场景光照（烟：夜里是暗的，不会发亮）；不受光的（雪）靠一点自发光在夜里也看得见
static func _particle_mat(emission := 0.0, lit := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX if lit else BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft_dot()
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = Color.WHITE
		m.emission_energy_multiplier = emission
	return m


## 烟囱的烟：一团团灰白的烟往上飘、慢慢变大变淡，被风往一边带
static func smoke(parent: Node3D, at: Vector3) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "ChimneySmoke"
	p.position = at
	p.amount = SMOKE_AMOUNT
	p.lifetime = 6.0
	p.preprocess = 6.0                    # 一进区域就已经在冒，不是刚点着
	p.randomness = 0.4
	var q := QuadMesh.new()
	q.size = Vector2(1.3, 1.3)
	q.material = _particle_mat(0.0, true)
	p.mesh = q
	p.direction = Vector3(0.15, 1, 0)
	p.spread = 12.0
	p.initial_velocity_min = 0.35
	p.initial_velocity_max = 0.55
	p.gravity = Vector3(0.28, 0.12, 0.05)  # 一点点风（往东）、热烟往上
	p.damping_min = 0.05
	p.damping_max = 0.1
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.1
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.4))
	sc.add_point(Vector2(1, 2.6))
	p.scale_amount_curve = sc
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.62, 0.62, 0.64, 0.0))
	ramp.add_point(0.12, Color(0.6, 0.6, 0.62, 0.62))
	ramp.set_color(ramp.get_point_count() - 1, Color(0.66, 0.67, 0.7, 0.0))
	p.color_ramp = ramp
	p.local_coords = false
	p.add_to_group(SMOKE_GROUP)
	parent.add_child(p)
	return p


## 落雪：挂在玩家身上（发射盒跟着人走，雪花留在世界里）。wind：风（米 / 秒²，高地 5.1a）——雪斜着落，发射盒往上风挪一点，落到人身边的还是一样多
static func snow(player: Node3D, wind := Vector3.ZERO) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Snow"
	p.position = Vector3(0, SNOW_HEIGHT, 0)
	p.amount = SNOW_AMOUNT
	p.lifetime = 8.0
	p.preprocess = 8.0
	var q := QuadMesh.new()
	q.size = Vector2(0.085, 0.085)
	q.material = _particle_mat(0.6)
	p.mesh = q
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = SNOW_BOX
	p.direction = Vector3(0, -1, 0)
	p.spread = 15.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.0
	p.gravity = Vector3(0.15, -0.35, 0.05) + wind
	p.position -= Vector3(wind.x, 0.0, wind.z) * 4.0
	p.color = Color(0.95, 0.97, 1.0, 0.85)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	p.local_coords = false
	p.add_to_group(SNOW_GROUP)
	player.add_child(p)
	return p


## 贴地的吹雪（高地 5.1a）：几十团很淡、拉长的雪雾贴着地面被风吹过去。挂在玩家身上（发射盒跟着人走）
static func drift(player: Node3D, wind := HIGHLAND_WIND) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Drift"
	p.position = Vector3(0, 0.25, 0) - wind.normalized() * 10.0
	p.amount = DRIFT_AMOUNT
	p.lifetime = 5.0
	p.preprocess = 5.0
	var q := QuadMesh.new()
	q.size = Vector2(2.4, 0.5)
	var m := _particle_mat(0.0, true)                  # 受光：夜里是暗的，不会发亮（截图：夜里一团团白光）
	m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	m.distance_fade_min_distance = 1.5               # 贴着镜头的那团淡掉（不然一团雪雾占半个屏幕）
	m.distance_fade_max_distance = 6.0
	q.material = m
	p.mesh = q
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(16.0, 0.25, 16.0)
	p.direction = wind.normalized()
	p.spread = 12.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 5.5
	p.gravity = Vector3(0, 0.05, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.5
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.92, 0.94, 0.98, 0.0))
	ramp.add_point(0.35, Color(0.92, 0.94, 0.98, 0.16))
	ramp.set_color(ramp.get_point_count() - 1, Color(0.92, 0.94, 0.98, 0.0))
	p.color_ramp = ramp
	p.local_coords = false
	p.add_to_group(DRIFT_GROUP)
	player.add_child(p)
	return p


## 画质：低画质烟和雪都减半
static func apply_quality(tree: SceneTree, low: bool) -> void:
	for p: CPUParticles3D in tree.get_nodes_in_group(SMOKE_GROUP):
		p.amount = SMOKE_AMOUNT / 2 if low else SMOKE_AMOUNT
	for p: CPUParticles3D in tree.get_nodes_in_group(SNOW_GROUP):
		p.amount = SNOW_AMOUNT / 2 if low else SNOW_AMOUNT
	for p: CPUParticles3D in tree.get_nodes_in_group(DRIFT_GROUP):
		p.amount = DRIFT_AMOUNT / 2 if low else DRIFT_AMOUNT
