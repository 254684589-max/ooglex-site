class_name TitleStage
extends Node3D
## 主菜单背后的 3D 场景（2026-11-08 所有者「做开始主菜单页面……画面精美」）：自己一个 World3D（主菜单的 SubViewport 里），不碰游戏世界。
## 雪夜的山岩上一张断了的石王座，座上放着那顶铁冠，一道冷光从云缝里落下来照着它；两只铁火盆烧着；
## 王座背后是一望无际的雪原，一队长眠的人光着脚排成一线往北走，走向地平线上冬井那一点冷光；左边远山上是冠城的影子，几扇窗亮着；
## 天上有星和极光，雪一直在下。镜头很慢地晃（「减少动态效果」时不动）。
## 只用代码搭（同游戏里别的场景），原创构图：主体放在画面偏左，右边留给菜单。

const THRONE := Vector3(0.0, 2.1, 0.0)        # 王座台阶顶面的中心
const CAM_BASE := Vector3(5.6, 2.6, 8.8)
const CAM_LOOK := Vector3(3.0, 4.0, -3.0)
const WELL := Vector3(14.0, 0.0, -420.0)
const WALKERS := 64
const WALK_SPEED := 0.55

var motion := true
var cam: Camera3D
var t := 0.0
var walkers: MultiMeshInstance3D
var route: Curve3D
var route_len := 1.0
var crown: Node3D
var noise: FastNoiseLite


static func make(reduced_motion: bool) -> TitleStage:
	var s := TitleStage.new()
	s.name = "TitleStage"
	s.motion = not reduced_motion
	return s


func _ready() -> void:
	noise = FastNoiseLite.new()
	noise.seed = 1108
	noise.frequency = 0.012
	noise.fractal_octaves = 4
	_environment()
	_terrain()
	_crag()
	_throne()
	_braziers()
	_beam()
	_walkers()
	_castle()
	_snow()
	cam = Camera3D.new()
	cam.name = "TitleCam"
	cam.fov = 50.0
	cam.near = 0.1
	cam.far = 1500.0
	add_child(cam)
	cam.current = true
	_place_cam()


func _process(delta: float) -> void:
	if not motion:
		return
	t += delta
	_place_cam()
	if crown:
		crown.rotation.y = 0.25 + sin(t * 0.21) * 0.06
	_move_walkers()


func _place_cam() -> void:
	var p := CAM_BASE + Vector3(sin(t * 0.045) * 1.1, sin(t * 0.06) * 0.18, cos(t * 0.045) * 0.5 - 0.5)
	cam.position = p
	cam.look_at(CAM_LOOK + Vector3(sin(t * 0.03) * 0.25, 0.0, 0.0), Vector3.UP)


# ---------------- 天、光、雾 ----------------

func _environment() -> void:
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/title_sky.gdshader")
	sky_mat.set_shader_parameter("motion", 1.0 if motion else 0.0)
	sky_mat.set_shader_parameter("well_dir", Vector3(WELL.x, 0.0, WELL.z).normalized())
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("3a4766")
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.fog_enabled = true
	env.fog_light_color = Color("26324a")
	env.fog_density = 0.0065
	env.fog_sky_affect = 0.0
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 0.85
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var moon := DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color("a8bee8")
	moon.light_energy = 0.8
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 40.0
	moon.rotation_degrees = Vector3(-34.0, -142.0, 0.0)
	add_child(moon)


static func _rock_mat(line := 0.55, bumps := 0.0, rock := Color(0.13, 0.14, 0.17), rock2 := Color(0.22, 0.23, 0.26), snow := Color(0.78, 0.83, 0.92)) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/title_rock.gdshader")
	m.set_shader_parameter("snow_line", line)
	m.set_shader_parameter("bumps", bumps)
	m.set_shader_parameter("rock_color", rock)
	m.set_shader_parameter("rock_color2", rock2)
	m.set_shader_parameter("snow_color", snow)
	return m


static func _glow_mat(tint: Color, strength: float, mode: int, flicker := 0.0, motion_on := true) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/title_glow.gdshader")
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("strength", strength)
	m.set_shader_parameter("mode", mode)
	m.set_shader_parameter("flicker", flicker)
	m.set_shader_parameter("motion", 1.0 if motion_on else 0.0)
	return m


# ---------------- 地 ----------------

## 雪原：近处起伏小，北边远处抬成一道山脊；王座那块岩下面鼓起来
static func height_at(x: float, z: float, nz: FastNoiseLite) -> float:
	var h := nz.get_noise_2d(x, z) * 1.6
	var d := Vector2(x, z).length()
	h += exp(-d * d / 60.0) * 1.2                       # 王座那块地鼓起来
	var far := clampf((-z - 260.0) / 200.0, 0.0, 1.0)  # 北边地平线上的山
	h += far * far * (30.0 + nz.get_noise_2d(x * 0.4, 7.0) * 26.0)
	var west := clampf((-x - 160.0) / 140.0, 0.0, 1.0) # 西边（左边）冠城那座山
	h += west * west * 40.0 * clampf(1.0 - absf(z + 220.0) / 260.0, 0.0, 1.0)
	return h


func _terrain() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 110
	var x0 := -420.0
	var z0 := -620.0
	var sx := 840.0 / n
	var sz := 660.0 / n
	for j in n:
		for i in n:
			var a := Vector3(x0 + i * sx, 0, z0 + j * sz)
			var b := a + Vector3(sx, 0, 0)
			var c := a + Vector3(0, 0, sz)
			var d := a + Vector3(sx, 0, sz)
			for v in [a, b, c, b, d, c]:
				st.add_vertex(Vector3(v.x, height_at(v.x, v.z, noise), v.z))
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Snowfield"
	mi.mesh = st.commit()
	mi.material_override = _rock_mat(0.3, 0.0, Color(0.2, 0.21, 0.25), Color(0.3, 0.31, 0.35), Color(0.42, 0.47, 0.58))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## 王座底下那块岩：几块压扁的、表面鼓起来的石头堆在一起
func _crag() -> void:
	var rocks := [
		[Vector3(0.0, 0.6, 0.2), Vector3(4.8, 2.6, 4.2), 10.0],
		[Vector3(-2.6, 0.4, 1.8), Vector3(2.6, 1.8, 2.4), 40.0],
		[Vector3(2.8, 0.3, 1.6), Vector3(2.4, 1.6, 2.0), -25.0],
		[Vector3(-1.4, 0.7, -2.4), Vector3(3.4, 2.4, 2.6), 70.0],
		[Vector3(3.4, 0.2, -1.6), Vector3(2.0, 1.4, 1.8), 15.0],
		[Vector3(-4.2, 0.0, -0.4), Vector3(1.8, 1.2, 1.6), -50.0],
		[Vector3(5.8, -0.1, 3.4), Vector3(1.4, 0.9, 1.2), 30.0],
		[Vector3(-6.0, -0.2, 4.0), Vector3(1.2, 0.8, 1.1), 65.0],
	]
	var mat := _rock_mat(0.5, 0.35)
	for r in rocks:
		var sm := SphereMesh.new()
		sm.radius = 0.5
		sm.height = 1.0
		sm.radial_segments = 28
		sm.rings = 16
		var mi := MeshInstance3D.new()
		mi.mesh = sm
		mi.material_override = mat
		mi.position = r[0]
		mi.scale = r[1]
		mi.rotation_degrees = Vector3(0, r[2], 0)
		add_child(mi)


# ---------------- 王座与铁冠 ----------------

func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot
	parent.add_child(mi)
	return mi


func _throne() -> void:
	var root := Node3D.new()
	root.name = "Throne"
	root.position = THRONE
	root.rotation_degrees.y = 18.0
	add_child(root)
	var stone := _rock_mat(0.72, 0.0, Color(0.17, 0.18, 0.2), Color(0.27, 0.27, 0.29))
	# 三级台阶
	for k in 3:
		var w := 3.4 - k * 0.6
		_box(root, Vector3(w, 0.32, w * 0.8), Vector3(0, -0.8 + k * 0.32, 0.2 - k * 0.12), stone)
	var top := 0.16
	_box(root, Vector3(1.3, 0.55, 1.0), Vector3(0, top + 0.27, 0), stone)                         # 座
	_box(root, Vector3(1.35, 2.5, 0.3), Vector3(0, top + 1.25, -0.42), stone)                     # 靠背
	var tip := MeshInstance3D.new()                                                                  # 靠背顶上的尖（缺了一角）
	var pm := PrismMesh.new()
	pm.size = Vector3(1.35, 0.7, 0.3)
	pm.left_to_right = 0.62
	tip.mesh = pm
	tip.material_override = stone
	tip.position = Vector3(0, top + 2.85, -0.42)
	root.add_child(tip)
	for s in [-1.0, 1.0]:
		_box(root, Vector3(0.22, 0.42, 1.0), Vector3(s * 0.62, top + 0.75, 0), stone)               # 扶手
		_box(root, Vector3(0.3, 0.3, 0.3), Vector3(s * 0.62, top + 1.0, 0.42), stone, Vector3(0, 45, 0))
	# 两边的断柱：右边站着，左边断成两截
	var pillar := func(pos: Vector3, h: float, tilt: Vector3) -> void:
		var cm := CylinderMesh.new()
		cm.top_radius = 0.26
		cm.bottom_radius = 0.3
		cm.height = h
		cm.radial_segments = 18
		var mi := MeshInstance3D.new()
		mi.mesh = cm
		mi.material_override = stone
		mi.position = pos
		mi.rotation_degrees = tilt
		root.add_child(mi)
	pillar.call(Vector3(2.1, 0.9, -0.6), 3.4, Vector3.ZERO)
	pillar.call(Vector3(-2.1, -0.2, -0.6), 1.3, Vector3.ZERO)
	pillar.call(Vector3(-2.7, -0.55, 0.9), 1.8, Vector3(84, 30, 0))
	# 铁冠：放在座上，稍稍歪着
	crown = CutScenes._crown()
	crown.name = "TitleCrown"
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color("2e2c2b")
	iron.metallic = 0.85
	iron.roughness = 0.32
	iron.emission_enabled = true
	iron.emission = Color("2a3a55")
	iron.emission_energy_multiplier = 0.8
	for c in crown.get_children():
		(c as MeshInstance3D).material_override = iron
	crown.scale = Vector3.ONE * 4.6
	crown.position = Vector3(0.0, top + 0.56, 0.08)
	crown.rotation_degrees = Vector3(6.0, 14.0, -4.0)
	root.add_child(crown)
	var glint := OmniLight3D.new()                                                                   # 冷光照在冠上
	glint.light_color = Color("cfe0ff")
	glint.light_energy = 1.6
	glint.omni_range = 4.0
	glint.position = Vector3(0.4, top + 1.9, 1.0)
	root.add_child(glint)


## 两只铁火盆：火苗（shaders/flame.gdshader）、火光一闪一闪，暖色压住一片冷蓝
func _braziers() -> void:
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color("1e1c1b")
	iron.metallic = 0.7
	iron.roughness = 0.5
	var flame_sh := load("res://shaders/flame.gdshader") as Shader
	for p in [Vector3(-2.0, 1.55, 1.9), Vector3(2.3, 1.45, 1.6)]:
		var bowl := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.42
		cm.bottom_radius = 0.18
		cm.height = 0.35
		bowl.mesh = cm
		bowl.material_override = iron
		bowl.position = p + Vector3(0, 0.9, 0)
		add_child(bowl)
		for leg in 3:
			var a := TAU * leg / 3.0
			var lm := CylinderMesh.new()
			lm.top_radius = 0.03
			lm.bottom_radius = 0.03
			lm.height = 1.0
			var l := MeshInstance3D.new()
			l.mesh = lm
			l.material_override = iron
			l.position = p + Vector3(cos(a) * 0.2, 0.4, sin(a) * 0.2)
			l.rotation = Vector3(sin(a) * 0.2, 0, -cos(a) * 0.2)
			add_child(l)
		for k in 3:
			var q := QuadMesh.new()
			q.size = Vector2([0.9, 0.7, 0.6][k], [1.3, 1.0, 0.8][k])
			var fm := ShaderMaterial.new()
			fm.shader = flame_sh
			fm.set_shader_parameter("noise_tex", Look.noise_texture())
			fm.set_shader_parameter("phase", 0.31 * k + p.x)
			fm.set_shader_parameter("speed", 1.0 if motion else 0.0)
			fm.set_shader_parameter("strength", 1.2)
			q.material = fm
			var fl := MeshInstance3D.new()
			fl.mesh = q
			fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			fl.position = p + Vector3([0.0, 0.1, -0.08][k], 1.05 + q.size.y * 0.5, [0.0, 0.06, -0.05][k])
			add_child(fl)
		var fire := Tavern.FireLight.new()
		fire.light_color = Color("ff9346")
		fire.base = 1.2
		fire.omni_range = 5.0
		fire.omni_attenuation = 1.4
		fire.flicker = motion
		fire.position = p + Vector3(0, 1.6, 0)
		add_child(fire)
		var halo := MeshInstance3D.new()
		var hq := QuadMesh.new()
		hq.size = Vector2(3.0, 3.0)
		halo.mesh = hq
		halo.material_override = _glow_mat(Color("ff8a3a"), 0.35, 1, 1.0 if motion else 0.0, motion)
		var bb := halo.material_override as ShaderMaterial
		bb.render_priority = 1
		halo.position = p + Vector3(0, 1.55, 0)
		add_child(halo)
		_face_cam_later(halo)


## 光晕面片朝着镜头（只转一次；镜头只晃一点点，看不出来）
func _face_cam_later(n: Node3D) -> void:
	(func():
		if is_instance_valid(n) and cam:
			n.look_at(cam.global_position, Vector3.UP)
			n.rotate_object_local(Vector3.UP, PI)).call_deferred()


## 云缝里落下来的一道冷光，照在王座上；光里飘着细雪
func _beam() -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = 2.6
	cm.bottom_radius = 1.1
	cm.height = 34.0
	cm.radial_segments = 32
	cm.cap_top = false
	cm.cap_bottom = false
	var mi := MeshInstance3D.new()
	mi.name = "Beam"
	mi.mesh = cm
	mi.material_override = _glow_mat(Color("9fc0ff"), 0.55, 0, 0.0, motion)
	mi.position = THRONE + Vector3(-0.6, 16.0, -0.4)
	mi.rotation_degrees = Vector3(0, 0, -6.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var dust := CPUParticles3D.new()
	dust.name = "BeamDust"
	dust.amount = 90
	dust.lifetime = 9.0
	dust.preprocess = 9.0
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = Vector3(1.2, 4.0, 1.2)
	dust.direction = Vector3(0, -1, 0)
	dust.spread = 25.0
	dust.initial_velocity_min = 0.05
	dust.initial_velocity_max = 0.2
	dust.gravity = Vector3(0, -0.04, 0)
	var q := QuadMesh.new()
	q.size = Vector2(0.03, 0.03)
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	pm.albedo_color = Color(0.8, 0.9, 1.0, 0.8)
	q.material = pm
	dust.mesh = q
	dust.position = THRONE + Vector3(-0.2, 4.5, 0)
	dust.emitting = true
	dust.speed_scale = 1.0 if motion else 0.0
	add_child(dust)
	# 地平线上冬井那一点冷光：一大张朝着镜头的光晕 + 一根很淡的光柱
	var wg := MeshInstance3D.new()
	var wq := QuadMesh.new()
	wq.size = Vector2(90, 60)
	wg.mesh = wq
	wg.material_override = _glow_mat(Color("8fb4ff"), 0.45, 1, 0.0, motion)
	wg.position = WELL + Vector3(0, 8, 0)
	add_child(wg)
	_face_cam_later(wg)
	var wp := MeshInstance3D.new()
	var wc := CylinderMesh.new()
	wc.top_radius = 6.0
	wc.bottom_radius = 3.0
	wc.height = 160.0
	wc.cap_top = false
	wc.cap_bottom = false
	wp.mesh = wc
	wp.material_override = _glow_mat(Color("7fa6ff"), 0.22, 0, 0.0, motion)
	wp.position = WELL + Vector3(0, 70, 0)
	add_child(wp)


# ---------------- 长眠的人 ----------------

## 一队光着脚的人从王座右后方的雪原上排成一线往北走，越走越远、越走越小，没进地平线那点光里
func _walkers() -> void:
	route = Curve3D.new()
	for p in [Vector3(16, 0, 12), Vector3(11, 0, -14), Vector3(4, 0, -50), Vector3(9, 0, -120), Vector3(2, 0, -230), Vector3(14, 0, -380)]:
		route.add_point(p)
	route.bake_interval = 1.0
	route_len = route.get_baked_length()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = SleeperCrowd.figure_mesh()
	mm.instance_count = WALKERS
	walkers = MultiMeshInstance3D.new()
	walkers.name = "Walkers"
	walkers.multimesh = mm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("b7b9be")
	m.roughness = 0.9
	walkers.material_override = m
	walkers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(walkers)
	_move_walkers()


func _move_walkers() -> void:
	if walkers == null:
		return
	var mm := walkers.multimesh
	for i in WALKERS:
		var d := fposmod(i * (route_len / WALKERS) + t * WALK_SPEED + sin(i * 12.9898) * 1.6, route_len)
		var p := route.sample_baked(d)
		var ahead := route.sample_baked(minf(d + 2.0, route_len))
		p.x += sin(i * 78.233) * 1.4
		p.y = height_at(p.x, p.z, noise)
		var dir := ahead - p
		dir.y = 0.0
		var yaw := atan2(-dir.x, -dir.z) if dir.length() > 0.01 else 0.0
		var sway := sin(t * 1.9 + i) * 0.03
		var b := Basis(Vector3.UP, yaw) * Basis(Vector3.FORWARD, sway)
		mm.set_instance_transform(i, Transform3D(b, p))


# ---------------- 冠城的影子 ----------------

func _castle() -> void:
	var root := Node3D.new()
	root.name = "Castle"
	root.position = Vector3(-230.0, 0.0, -250.0)
	add_child(root)
	var base_y := height_at(root.position.x, root.position.z, noise) - 2.0
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color("2a2d36")
	dark.roughness = 1.0
	var parts := [
		[Vector3(0, 0, 0), Vector3(60, 16, 24)],
		[Vector3(-26, 0, 0), Vector3(10, 32, 10)],
		[Vector3(26, 0, 2), Vector3(10, 28, 10)],
		[Vector3(-4, 0, -4), Vector3(18, 40, 16)],
		[Vector3(8, 0, 6), Vector3(8, 52, 8)],
	]
	for pt in parts:
		var size: Vector3 = pt[1]
		_box(root, size, (pt[0] as Vector3) + Vector3(0, base_y + size.y * 0.5, 0), dark)
		var roof := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(size.x * 0.9, size.x * 0.6, size.z * 0.9)
		roof.mesh = pm
		roof.material_override = dark
		roof.position = (pt[0] as Vector3) + Vector3(0, base_y + size.y + pm.size.y * 0.5, 0)
		root.add_child(roof)
	var win := StandardMaterial3D.new()
	win.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	win.albedo_color = Color("ffb35c")
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for k in 14:
		var q := QuadMesh.new()
		q.size = Vector2(1.2, 2.0)
		var w := MeshInstance3D.new()
		w.mesh = q
		w.material_override = win
		var tower: Array = parts[rng.randi_range(0, parts.size() - 1)]
		var sz: Vector3 = tower[1]
		w.position = (tower[0] as Vector3) + Vector3(rng.randf_range(-sz.x * 0.4, sz.x * 0.4), base_y + rng.randf_range(sz.y * 0.3, sz.y * 0.85), sz.z * 0.5 + 0.1)
		root.add_child(w)


# ---------------- 雪 ----------------

func _snow() -> void:
	var snow := CPUParticles3D.new()
	snow.name = "Snow"
	snow.amount = 700
	snow.lifetime = 12.0
	snow.preprocess = 12.0
	snow.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	snow.emission_box_extents = Vector3(18, 1, 18)
	snow.direction = Vector3(0.3, -1, 0.1)
	snow.spread = 12.0
	snow.initial_velocity_min = 0.6
	snow.initial_velocity_max = 1.2
	snow.gravity = Vector3(0.25, -0.3, 0.0)
	var q := QuadMesh.new()
	q.size = Vector2(0.045, 0.045)
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.albedo_color = Color(0.92, 0.95, 1.0, 0.85)
	q.material = pm
	snow.mesh = q
	snow.position = Vector3(2.0, 12.0, 0.0)
	snow.emitting = true
	snow.speed_scale = 1.0 if motion else 0.0
	add_child(snow)
