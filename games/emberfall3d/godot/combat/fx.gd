class_name Fx
extends RefCounted
## 特效（阶段 2.5）：纯代码与着色器，不用外部素材。
##   burst  一次性粒子（火星、碎骨、血雾、冰晶、烟、金光……），用 CPUParticles3D：兼容渲染器 / WebGL 2 都能跑
##   trail  跟着物体飞的拖尾（火球）
##   mark   地面痕迹（火球烧焦、寂霜环结霜），几秒后淡出
##   dissolve  怪物死亡时「烧尽消散」：边缘发光的溶解着色器（shaders/dissolve.gdshader）
## 数量按画质缩放（低画质一半）；系统开了「减少动态效果」再减到三分之一（V0.1 REDUCED 同样把粒子减到 1/3）。

static var amount_mul := 1.0
static var reduced := false
static var spawned := 0              # 测试用：一共生成过多少个特效
static var _mat_cache := {}
static var _dissolve_shader: Shader


static func _count(n: int) -> int:
	return maxi(1, roundi(n * amount_mul * (0.33 if reduced else 1.0)))


## 粒子用的发光小圆片材质（加法混合 = 发光；普通混合 = 烟、血这类不发光的）
static func _particle_mat(additive: bool) -> StandardMaterial3D:
	var key := "add" if additive else "mix"
	if not _mat_cache.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
		m.vertex_color_use_as_albedo = true
		m.albedo_texture = Look.radial_texture()
		m.no_depth_test = false
		_mat_cache[key] = m
	return _mat_cache[key]


static func _fade(c: Color) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, c)
	g.set_color(1, Color(c.r, c.g, c.b, 0.0))
	return g


## 一次性粒子。opt：speed（米/秒）、life（秒）、size（米）、gravity、spread（度，180 = 四面八方）、
## up（初速方向，默认向上）、ring（>0 时从这个半径的地面圆环上发射）、additive（默认 true）、sphere（发射球半径）
static func burst(parent: Node, pos: Vector3, color: Color, amount: int, opt: Dictionary = {}) -> CPUParticles3D:
	if parent == null or not parent.is_inside_tree():
		return null
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = opt.get("explosive", 0.9)
	p.amount = _count(amount)
	p.lifetime = opt.get("life", 0.6)
	var q := QuadMesh.new()
	var sz: float = opt.get("size", 0.18)
	q.size = Vector2(sz, sz)
	p.mesh = q
	p.material_override = _particle_mat(opt.get("additive", true))
	p.direction = opt.get("up", Vector3.UP)
	p.spread = opt.get("spread", 180.0)
	var spd: float = opt.get("speed", 3.0)
	p.initial_velocity_min = spd * 0.5
	p.initial_velocity_max = spd
	p.gravity = Vector3(0, -float(opt.get("gravity", 6.0)), 0)
	p.damping_min = opt.get("damping", 0.0)
	p.damping_max = opt.get("damping", 0.0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.3
	p.color_ramp = _fade(color)
	var ring: float = opt.get("ring", 0.0)
	if ring > 0.0:
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
		p.emission_ring_axis = Vector3.UP
		p.emission_ring_radius = ring
		p.emission_ring_inner_radius = ring * 0.85
		p.emission_ring_height = 0.1
	elif opt.has("sphere"):
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = opt.sphere
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	spawned += 1
	# 播完自己释放（信号挂在粒子节点自己身上：换层时整层释放也不会留下悬空的回调）
	p.finished.connect(p.queue_free)
	return p


## 跟着 node 走的连续拖尾（node 被释放时一起释放）
static func trail(node: Node3D, color: Color, amount: int = 24, size := 0.2) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = _count(amount)
	p.lifetime = 0.35
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	p.mesh = q
	p.material_override = _particle_mat(true)
	p.spread = 180.0
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.6
	p.gravity = Vector3(0, 1.5, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	p.color_ramp = _fade(color)
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(p)
	p.emitting = true
	spawned += 1
	return p


## 地面痕迹：一张贴地的圆形渐变片，停留 hold 秒后在 fade 秒内淡出（additive = 发光的，比如刚烧过还在发红的地面）
static func mark(parent: Node, pos: Vector3, color: Color, radius: float, hold := 2.5, fade := 1.5, additive := false) -> MeshInstance3D:
	if parent == null or not parent.is_inside_tree():
		return null
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(radius * 2.0, radius * 2.0)
	mi.mesh = pm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = Look.radial_texture()
	m.albedo_color = color
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.render_priority = -1
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = Vector3(pos.x, 0.03 if additive else 0.025, pos.z)
	mi.rotation.y = randf() * TAU
	spawned += 1
	var tw := mi.create_tween()
	tw.tween_interval(hold)
	tw.tween_property(m, "albedo_color:a", 0.0, fade)
	tw.tween_callback(mi.queue_free)
	return mi


## 溶解：把 root 下所有网格的材质换成溶解着色器（保留原来的颜色），返回这些材质；调用方把 progress 从 0 推到 1
static func dissolve_materials(root: Node, edge: Color = Color(1.0, 0.45, 0.12)) -> Array:
	if _dissolve_shader == null:
		_dissolve_shader = load("res://shaders/dissolve.gdshader")
	var mats: Array = []
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var src := (mi as MeshInstance3D).material_override as StandardMaterial3D
		var sm := ShaderMaterial.new()
		sm.shader = _dissolve_shader
		sm.set_shader_parameter("albedo", src.albedo_color if src else Color(0.5, 0.5, 0.5))
		sm.set_shader_parameter("edge_color", edge)
		sm.set_shader_parameter("progress", 0.0)
		(mi as MeshInstance3D).material_override = sm
		mats.append(sm)
	return mats


## 一闪而过的点光（爆炸照亮周围的地面和墙），life 秒内熄灭
static func flash(parent: Node, pos: Vector3, color: Color, energy := 4.0, radius := 5.0, life := 0.3) -> OmniLight3D:
	if parent == null or not parent.is_inside_tree():
		return null
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy * (0.6 if reduced else 1.0)
	l.omni_range = radius
	l.shadow_enabled = false
	parent.add_child(l)
	l.global_position = pos + Vector3(0, 0.8, 0)
	spawned += 1
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, life).set_ease(Tween.EASE_OUT)
	tw.tween_callback(l.queue_free)
	return l
