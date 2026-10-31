class_name Plain
extends RefCounted
## 金穗平原连片地图（路线图 6.1a，D10-B、D12；STORY.md 6.2；布局在 world/plain_layout.gd）。照余火高地（world/highland.gd）的做法：
##   1. 同步：整张高度场（每 1 米一个点；先读第三章章节包里预先算好的文件）、一整块高度图碰撞、四边看不见的墙（层 5「边界」）、
##      麦河的水面（一条贴着河道的带子，两边结着薄冰）、地图外面的远景（平原一直铺到地平线，东北角是砧山的黑影）；
##   2. 画面分块：每 64 米一块，交给 ChunkStreamer 分帧搭——近处 1 米的网格、远处 4 米的网格（按距离切换，带裙边）。
## 地面一个着色器混四种写实贴图（shaders/plain_ground.gdshader：雪盖着的田、收割后露出来的麦茬和土、踩成泥雪的路、河边的泥岸），田里画一垄一垄；
## 天空是一张起雾的冬日天空照片（shaders/highland_sky.gdshader，同高地的天空着色器，换一张照片），按时段染色。
## 贴图和照片在第三章章节包里（chapters/ch3/）：包没到时退回纯色，main 随后下载章节包、重新载入。

const TEX_DIR := "res://chapters/ch3/tex/%s_%s_1k.jpg"
const SKY_PATH := "res://chapters/ch3/sky/misty_sky.jpg"
const FIELD_PATH := "res://chapters/ch3/plain_field.res"
const PAINT_PATH := "res://chapters/ch3/plain_paint.res"
const LO_STEP := 2                       # 远处那份网格每 2 个点取一个（4 时坡上和近处那份接不上，裙边露成一排梳齿，截图）
const LOD_DIST := 80.0
const SKIRT := 1.2
const FAR_EXTENT := 1600.0
const LAYERS := {"snow": "snow_field_aerial", "track": "snow_03", "soil": "snow_04", "bank": "brown_mud_02"}

## 时段 → 天空（照片的染色、亮度、转多少：亮的那片对着太阳那边）
const SKY := {
	"dawn": {"tint": Color(1.06, 0.88, 0.8), "energy": 0.95, "spin": 0.08},
	"day": {"tint": Color(1.0, 0.98, 0.95), "energy": 1.05, "spin": 0.0},
	"dusk": {"tint": Color(1.02, 0.8, 0.7), "energy": 0.75, "spin": 0.55},
	"night": {"tint": Color(0.3, 0.38, 0.55), "energy": 0.22, "spin": 0.3},
}

static var _field := PackedFloat32Array()
static var _paint := PackedColorArray()        # r 路、g 田、b 遮蔽
static var _mat: ShaderMaterial
static var _water_mat: ShaderMaterial
static var _sky_mat: ShaderMaterial
static var field_ms := 0.0

var parent: Node3D
var reduced_motion := false


static func build(p_parent: Node3D, reduced_motion := false) -> Transform3D:
	var t0 := Time.get_ticks_usec()
	var pl := Plain.new()
	pl.parent = p_parent
	pl.reduced_motion = reduced_motion
	var s: Array = spawn_points().dock
	if not textures_ready():
		pl._placeholder()
		print("IC_PLAIN placeholder (章节包没到)")
		return Transform3D(Basis(Vector3.UP, deg_to_rad(float(s[1]))), s[0])
	ensure_field()
	PlainFlora.warm(reduced_motion)                    # 树、篱笆、麦垛、木栅（6.1b）：材质、网格、摆放先备好
	PlainVillage.mats()                                # 麦渡的材质先备好（6.2a：土坯、茅草贴图在分帧的活里第一次读，那一块要 70–80 毫秒）
	pl._collision()
	ground_material()
	water_material()
	pl._river()
	pl._far()
	PlainFlora.far_ring(p_parent)                    # 地平线上的树（6.1b）
	PlainVillage.interactables(p_parent)             # 麦渡（6.2a）：长屋的门、村口的路牌（同步：一进场就推得开）
	var st := ChunkStreamer.new()
	st.name = "Streamer"
	st.host = p_parent
	st.builder = pl
	p_parent.add_child(st)
	pl._jobs(st)
	print("IC_PLAIN sync ms=%.0f field_ms=%.0f chunks=%d tex=%s" % [float(Time.get_ticks_usec() - t0) / 1000.0, field_ms, st.chunks.size(), textures_ready()])
	return Transform3D(Basis(Vector3.UP, deg_to_rad(float(s[1]))), s[0])


static func spawn_points() -> Dictionary:
	return PlainLayout.spawn_points()


static func views() -> Array:
	return PlainLayout.views()


static func textures_ready() -> bool:
	return ResourceLoader.exists(SKY_PATH)


# ---------------- 高度场 ----------------

static func ensure_field() -> void:
	if _field.size() == PlainLayout.NX * PlainLayout.NZ:
		return
	var t0 := Time.get_ticks_usec()
	if ResourceLoader.exists(FIELD_PATH) and ResourceLoader.exists(PAINT_PATH):
		var fi := load(FIELD_PATH) as Image
		var pi := load(PAINT_PATH) as Image
		if fi != null and pi != null and fi.get_width() == PlainLayout.NX and fi.get_height() == PlainLayout.NZ:
			_field = fi.get_data().to_float32_array()
			var bytes := pi.get_data()
			_paint.resize(PlainLayout.NX * PlainLayout.NZ)
			for k in _paint.size():
				_paint[k] = Color8(bytes[k * 3], bytes[k * 3 + 1], bytes[k * 3 + 2])
			field_ms = float(Time.get_ticks_usec() - t0) / 1000.0
			return
	compute_field()
	field_ms = float(Time.get_ticks_usec() - t0) / 1000.0


static func compute_field() -> void:
	var nx := PlainLayout.NX
	var nz := PlainLayout.NZ
	var x0 := PlainLayout.BOUNDS.position.x
	var z0 := PlainLayout.BOUNDS.position.y
	_field.resize(nx * nz)
	_paint.resize(nx * nz)
	for j in nz:
		var z := z0 + j * PlainLayout.STEP
		for i in nx:
			var x := x0 + i * PlainLayout.STEP
			_field[j * nx + i] = PlainLayout.height(x, z)
			var m := PlainLayout.masks(x, z)
			_paint[j * nx + i] = Color(m.x, m.y, m.z)


static func save_field() -> void:
	var fi := Image.create_from_data(PlainLayout.NX, PlainLayout.NZ, false, Image.FORMAT_RF, _field.to_byte_array())
	var bytes := PackedByteArray()
	bytes.resize(_paint.size() * 3)
	for k in _paint.size():
		var c := _paint[k]
		bytes[k * 3] = c.r8
		bytes[k * 3 + 1] = c.g8
		bytes[k * 3 + 2] = c.b8
	var pi := Image.create_from_data(PlainLayout.NX, PlainLayout.NZ, false, Image.FORMAT_RGB8, bytes)
	ResourceSaver.save(fi, FIELD_PATH, ResourceSaver.FLAG_COMPRESS)
	ResourceSaver.save(pi, PAINT_PATH, ResourceSaver.FLAG_COMPRESS)


static func height_at(x: float, z: float) -> float:
	ensure_field()
	var fx := (x - PlainLayout.BOUNDS.position.x) / PlainLayout.STEP
	var fz := (z - PlainLayout.BOUNDS.position.y) / PlainLayout.STEP
	if fx < 0.0 or fz < 0.0 or fx > PlainLayout.NX - 1 or fz > PlainLayout.NZ - 1:
		return PlainLayout.height(x, z)
	var i := mini(int(fx), PlainLayout.NX - 2)
	var j := mini(int(fz), PlainLayout.NZ - 2)
	var tx := fx - i
	var tz := fz - j
	var n := PlainLayout.NX
	var a := lerpf(_field[j * n + i], _field[j * n + i + 1], tx)
	var b := lerpf(_field[(j + 1) * n + i], _field[(j + 1) * n + i + 1], tx)
	return lerpf(a, b, tz)


static func _h(i: int, j: int) -> float:
	return _field[clampi(j, 0, PlainLayout.NZ - 1) * PlainLayout.NX + clampi(i, 0, PlainLayout.NX - 1)]


static func _normal(i: int, j: int, step: int) -> Vector3:
	var dx := (_h(i + step, j) - _h(i - step, j)) / (2.0 * step)
	var dz := (_h(i, j + step) - _h(i, j - step)) / (2.0 * step)
	return Vector3(-dx, 1.0, -dz).normalized()


# ---------------- 碰撞 ----------------

func _placeholder() -> void:
	var b := StaticBody3D.new()
	b.name = "PlainPlaceholder"
	parent.add_child(b)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(400, 1, 400)
	cs.shape = bs
	var s: Array = spawn_points().dock
	cs.position = (s[0] as Vector3) - Vector3(0, 0.5, 0)
	b.add_child(cs)


func _collision() -> void:
	var ground := StaticBody3D.new()
	ground.name = "PlainGround"
	ground.collision_layer = 1
	ground.collision_mask = 0
	ground.set_meta("surface", "snow")
	parent.add_child(ground)
	var cs := CollisionShape3D.new()
	var hm := HeightMapShape3D.new()
	hm.map_width = PlainLayout.NX
	hm.map_depth = PlainLayout.NZ
	hm.map_data = _field
	cs.shape = hm
	cs.position = Vector3(PlainLayout.BOUNDS.get_center().x, 0.0, PlainLayout.BOUNDS.get_center().y)
	ground.add_child(cs)
	var flora := StaticBody3D.new()                  # 树干、麦垛、篱笆、木栅挡人（6.1b）
	flora.name = "PlainFlora"
	flora.collision_layer = 1
	flora.collision_mask = 0
	parent.add_child(flora)
	PlainFlora.add_collision(flora)
	var village := StaticBody3D.new()                # 麦渡：长屋、谷仓、水井、木桥、栈桥、零碎（6.2a）
	village.name = "MaiduSolids"
	village.collision_layer = 1
	village.collision_mask = 0
	parent.add_child(village)
	for so: Array in PlainVillage.solids():
		var vs := CollisionShape3D.new()
		var vb := BoxShape3D.new()
		vb.size = so[1]
		vs.shape = vb
		vs.transform = so[0]
		village.add_child(vs)
	var wb := StaticBody3D.new()
	wb.name = "PlainWalls"
	wb.collision_layer = FpController.LAYER_BOUNDARY
	wb.collision_mask = 0
	parent.add_child(wb)
	var r := PlainLayout.BOUNDS.grow(-PlainLayout.WALL_INSET)
	var hh := PlainLayout.WALL_H
	var c := r.get_center()
	for w in [[Vector3(c.x, hh * 0.5, r.position.y), Vector3(r.size.x, hh * 2.0, 1.0)], [Vector3(c.x, hh * 0.5, r.end.y), Vector3(r.size.x, hh * 2.0, 1.0)],
			[Vector3(r.position.x, hh * 0.5, c.y), Vector3(1.0, hh * 2.0, r.size.y)], [Vector3(r.end.x, hh * 0.5, c.y), Vector3(1.0, hh * 2.0, r.size.y)]]:
		var ws := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = w[1]
		ws.shape = bs
		ws.position = w[0]
		wb.add_child(ws)


# ---------------- 材质 ----------------

static func ground_material() -> ShaderMaterial:
	if _mat != null:
		return _mat
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/plain_ground.gdshader")
	_mat.set_shader_parameter("macro_noise", Look.noise_texture())
	var fallback := {"snow": Color("d6d9dc"), "track": Color("8a7f74"), "soil": Color("7a6a58"), "bank": Color("5f4e3e")}
	for k in LAYERS:
		var id: String = LAYERS[k]
		var alb: Texture2D = _tex(TEX_DIR % [id, "diff"])
		var nrm: Texture2D = _tex(TEX_DIR % [id, "nor_gl"])
		_mat.set_shader_parameter(k + "_alb", alb if alb != null else _flat(fallback[k]))
		_mat.set_shader_parameter(k + "_nrm", nrm if nrm != null else _flat(Color(0.5, 0.5, 1.0)))
	return _mat


## 麦河的水：深色、慢慢流、两边结着薄冰（shaders/plain_water.gdshader）
static func water_material() -> ShaderMaterial:
	if _water_mat != null:
		return _water_mat
	_water_mat = ShaderMaterial.new()
	_water_mat.shader = load("res://shaders/plain_water.gdshader")
	_water_mat.set_shader_parameter("noise_tex", Look.noise_texture())
	return _water_mat


static func clear_cache() -> void:
	PlainFlora.clear_cache()
	PlainVillage.clear_cache()
	_mat = null
	_water_mat = null
	_sky_mat = null


static func _tex(path: String) -> Texture2D:
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


static func _flat(c: Color) -> Texture2D:
	var img := Image.create(4, 4, false, Image.FORMAT_RGB8)
	img.fill(c)
	return ImageTexture.create_from_image(img)


static func sky_material() -> ShaderMaterial:
	if _sky_mat == null:
		_sky_mat = ShaderMaterial.new()
		_sky_mat.shader = load("res://shaders/highland_sky.gdshader")
		var t: Texture2D = _tex(SKY_PATH)
		_sky_mat.set_shader_parameter("pano", t if t != null else _flat(Color("b4b7bb")))
		_sky_mat.set_shader_parameter("horizon_fade", 0.14)
	return _sky_mat


## 时段：背景换成天空照片（按时段染色），雾不盖天空（天空自己在地平线渐变到雾色）
static func apply_sky(env: Environment, id: String, horizon: Color) -> void:
	var s: Dictionary = SKY.get(id, SKY.day)
	var sm := sky_material()
	sm.set_shader_parameter("tint", s.tint)
	sm.set_shader_parameter("energy", s.energy)
	sm.set_shader_parameter("spin", s.spin)
	sm.set_shader_parameter("horizon", horizon)
	if env.sky == null:
		env.sky = Sky.new()
	env.sky.sky_material = sm
	env.sky.radiance_size = Sky.RADIANCE_SIZE_32
	env.background_mode = Environment.BG_SKY
	env.fog_sky_affect = 0.0
	env.tonemap_exposure = 0.7                    # 满眼是雪：曝光压低（0.82 时整片发白、看不出垄，截图）


# ---------------- 麦河的水面 ----------------

## 一条贴着河道的带子：每 2 米一节，横着 6 个点（两边的点伸进岸里一点，被岸上的地形盖住；顶点色 r = 离岸多近，着色器在两边画薄冰）
func _river() -> void:
	var pts := PackedVector2Array()
	for k in PlainLayout.RIVER.size() - 1:
		var a: Vector2 = PlainLayout.RIVER[k]
		var b: Vector2 = PlainLayout.RIVER[k + 1]
		var n := int(ceil(a.distance_to(b) / 2.0))
		for s in n:
			pts.append(a.lerp(b, float(s) / n))
	pts.append(PlainLayout.RIVER[PlainLayout.RIVER.size() - 1])
	var smooth := PackedVector2Array()                 # 拐角处磨圆一点（三点平均两遍）
	smooth.append_array(pts)
	for it in 3:
		var t := smooth.duplicate()
		for k in range(1, smooth.size() - 1):
			t[k] = (smooth[k - 1] + smooth[k] * 2.0 + smooth[k + 1]) * 0.25
		smooth = t
	var half := PlainLayout.RIVER_HALF + 1.4
	var across := [-1.0, -0.72, -0.3, 0.3, 0.72, 1.0]
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var along := 0.0
	for k in smooth.size():
		var p := smooth[k]
		var d := (smooth[mini(k + 1, smooth.size() - 1)] - smooth[maxi(k - 1, 0)]).normalized()
		var side := Vector2(-d.y, d.x)
		if k > 0:
			along += p.distance_to(smooth[k - 1])
		for a: float in across:
			var q := p + side * a * half
			verts.append(Vector3(q.x, PlainLayout.WATER_Y, q.y))
			colors.append(Color(absf(a), 0.0, 0.0))
			uvs.append(Vector2(a * half, along))
	var idx := PackedInt32Array()
	var w := across.size()
	for k in smooth.size() - 1:
		for c in w - 1:
			var a := k * w + c
			idx.append_array(PackedInt32Array([a, a + w, a + 1, a + 1, a + w, a + w + 1]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	var norms := PackedVector3Array()
	norms.resize(verts.size())
	norms.fill(Vector3.UP)
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = colors
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.name = "RiverWater"
	mi.mesh = m
	mi.material_override = water_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


# ---------------- 画面 ----------------

func _jobs(st: ChunkStreamer) -> void:
	var b := PlainLayout.BOUNDS
	var cs := PlainLayout.CHUNK
	var cx := 0
	var x := b.position.x
	while x < b.end.x - 0.01:
		var cz := 0
		var z := b.position.y
		while z < b.end.y - 0.01:
			var r := Rect2(x, z, minf(cs, b.end.x - x), minf(cs, b.end.y - z))
			var jobs: Array = [_job_terrain.bind(r), _job_flora.bind(r)]
			jobs.append_array(PlainVillage.jobs_for(r, reduced_motion))           # 麦渡的长屋、谷仓、水井、木桥、渡口、零碎（6.2a）
			st.add_chunk("%d_%d" % [cx, cz], r, jobs)
			z += cs
			cz += 1
		x += cs
		cx += 1


## 一块里的树、柳、篱笆、麦垛、木栅（6.1b，PlainFlora）
func _job_flora(root: Node3D, r: Rect2) -> void:
	PlainFlora.build_chunk(root, r, reduced_motion)


func _job_terrain(root: Node3D, r: Rect2) -> void:
	var i0 := int(round((r.position.x - PlainLayout.BOUNDS.position.x) / PlainLayout.STEP))
	var j0 := int(round((r.position.y - PlainLayout.BOUNDS.position.y) / PlainLayout.STEP))
	var i1 := i0 + int(round(r.size.x / PlainLayout.STEP))
	var j1 := j0 + int(round(r.size.y / PlainLayout.STEP))
	var hi := MeshInstance3D.new()
	hi.name = "Terrain"
	hi.mesh = grid_mesh(i0, j0, i1, j1, 1, 0.0)
	hi.material_override = ground_material()
	hi.visibility_range_end = LOD_DIST + 6.0
	hi.visibility_range_end_margin = 6.0
	hi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	hi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(hi)
	var lo := MeshInstance3D.new()
	lo.name = "TerrainFar"
	lo.mesh = grid_mesh(i0, j0, i1, j1, LO_STEP, SKIRT)
	lo.material_override = ground_material()
	lo.visibility_range_begin = LOD_DIST
	lo.visibility_range_begin_margin = 6.0
	lo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(lo)
	var c := r.get_center()
	hi.position = Vector3(c.x, 0.0, c.y)
	lo.position = Vector3(c.x, 0.0, c.y)


static func grid_mesh(i0: int, j0: int, i1: int, j1: int, step: int, skirt: float) -> ArrayMesh:
	var bx := PlainLayout.BOUNDS.position.x
	var bz := PlainLayout.BOUNDS.position.y
	var cx := bx + (i0 + i1) * 0.5 * PlainLayout.STEP
	var cz := bz + (j0 + j1) * 0.5 * PlainLayout.STEP
	var cols: Array[int] = []
	var i := i0
	while i < i1:
		cols.append(i)
		i += step
	cols.append(i1)
	var rows: Array[int] = []
	var j := j0
	while j < j1:
		rows.append(j)
		j += step
	rows.append(j1)
	var nc := cols.size()
	var nr := rows.size()
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var colors := PackedColorArray()
	verts.resize(nc * nr)
	norms.resize(nc * nr)
	colors.resize(nc * nr)
	var nx := PlainLayout.NX
	for rj in nr:
		var jj := rows[rj]
		for ci in nc:
			var ii := cols[ci]
			var k := rj * nc + ci
			verts[k] = Vector3(bx + ii * PlainLayout.STEP - cx, _field[jj * nx + ii], bz + jj * PlainLayout.STEP - cz)
			norms[k] = _normal(ii, jj, 1 if step == 1 else 2)
			colors[k] = _paint[jj * nx + ii]
	var idx := PackedInt32Array()
	idx.resize((nc - 1) * (nr - 1) * 6)
	var w := 0
	for rj in nr - 1:
		for ci in nc - 1:
			var a := rj * nc + ci
			var b := a + 1
			var c := a + nc
			var d := c + 1
			idx[w] = a
			idx[w + 1] = b
			idx[w + 2] = c
			idx[w + 3] = b
			idx[w + 4] = d
			idx[w + 5] = c
			w += 6
	if skirt > 0.0:
		var top: Array[int] = []
		var bottom: Array[int] = []
		for ci in nc:
			top.append(ci)
			bottom.append((nr - 1) * nc + ci)
		var left: Array[int] = []
		var right: Array[int] = []
		for rj in nr:
			left.append(rj * nc)
			right.append(rj * nc + nc - 1)
		for e: Array[int] in [top, bottom, left, right]:
			var base := verts.size()
			for k in e:
				verts.append(verts[k] - Vector3(0, skirt, 0))
				norms.append(norms[k])
				var ck := colors[k]
				ck.a = 0.0                                   # 裙边：着色器里不贴图（竖着拉长的贴图远看是一排梳齿，截图）
				colors.append(ck)
			for n in e.size() - 1:
				var a := e[n]
				var b := e[n + 1]
				var a2 := base + n
				var b2 := base + n + 1
				idx.append_array(PackedInt32Array([a, a2, b, b, a2, b2, a, b, a2, b, b2, a2]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = colors
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## 远景：地图外面一圈（越往外越稀），平原接着往外铺、慢慢起伏；东北方向远处抬成砧山（一排黑的山，雾里还看得见轮廓）。
## 颜色：田（g = 1，着色器在远处不画垄，只是雪和土的斑驳）
func _far() -> void:
	var lines := _far_lines()
	var b := PlainLayout.BOUNDS
	var n := lines.size()
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var colors := PackedColorArray()
	verts.resize(n * n)
	norms.resize(n * n)
	colors.resize(n * n)
	for j in n:
		for i in n:
			var x: float = lines[i]
			var z: float = lines[j]
			verts[j * n + i] = Vector3(x, far_height(x, z), z)
			colors[j * n + i] = Color(0.0, 0.6, 1.0)
	for j in n:
		for i in n:
			var dx := verts[j * n + mini(i + 1, n - 1)] - verts[j * n + maxi(i - 1, 0)]
			var dz := verts[mini(j + 1, n - 1) * n + i] - verts[maxi(j - 1, 0) * n + i]
			norms[j * n + i] = dz.cross(dx).normalized()
	var idx := PackedInt32Array()
	var inner := b.grow(-2.0)
	for j in n - 1:
		for i in n - 1:
			var cell := Rect2(lines[i], lines[j], lines[i + 1] - lines[i], lines[j + 1] - lines[j])
			if inner.encloses(cell):
				continue
			var a := j * n + i
			idx.append_array(PackedInt32Array([a, a + 1, a + n, a + 1, a + n + 1, a + n]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = colors
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.name = "FarTerrain"
	mi.mesh = m
	mi.material_override = ground_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 50.0
	parent.add_child(mi)


static func _far_lines() -> Array:
	var out := []
	var x := -FAR_EXTENT
	while x < FAR_EXTENT:
		out.append(x)
		var ax := absf(x)
		x += 16.0 if ax < 360.0 else (40.0 if ax < 800.0 else 100.0)
	out.append(FAR_EXTENT)
	return out


## 远景的高度：地图里面和地形一致（往下压一点），外面接着平原慢慢起伏；东北方向（砧山）远处抬成一排黑山；麦河在地图外接着往北、往南（压低一道）
static func far_height(x: float, z: float) -> float:
	var b := PlainLayout.BOUNDS
	var dx := maxf(maxf(b.position.x - x, x - b.end.x), 0.0)
	var dz := maxf(maxf(b.position.y - z, z - b.end.y), 0.0)
	var out := sqrt(dx * dx + dz * dz)
	var y := PlainLayout.natural(x, z) - 0.4
	if out <= 0.0:
		return y
	var p := Vector2(x, z)
	var hills := 6.0 * sin(x / 170.0 + 0.4) * sin(z / 210.0) + 3.0 * sin(x / 61.0) * sin(z / 47.0 + 1.0)
	var along := p.dot(PlainLayout.ANVIL_DIR)                         # 往砧山那边走了多远
	var side := absf(p.dot(Vector2(-PlainLayout.ANVIL_DIR.y, PlainLayout.ANVIL_DIR.x)))
	var anvil := 0.0
	if along > 500.0:
		var k := PlainLayout._smooth(clampf((along - 500.0) / 500.0, 0.0, 1.0))
		var ridge := 160.0 + 70.0 * sin(side / 90.0 + 1.1) + 40.0 * sin(side / 37.0)
		anvil = ridge * k * PlainLayout._smooth(clampf(1.0 - side / 1300.0, 0.0, 1.0))
	var k2 := clampf(out / 60.0, 0.0, 1.0)
	return y + (hills * clampf(out / 200.0, 0.0, 1.0) + anvil) * k2


## 地图册（3.11）「本地」页：麦河、路、几处地点（6.2 起换成真的房子）
static func map_spec() -> Dictionary:
	var shapes := []
	for i in PlainLayout.RIVER.size() - 1:
		var sh := {"k": "water", "pts": _strip(PlainLayout.RIVER[i], PlainLayout.RIVER[i + 1], PlainLayout.RIVER_HALF)}
		if i == 2:
			sh["label"] = "麦河"
		shapes.append(sh)
	for r in PlainLayout.ROADS:
		for i in r.size() - 1:
			shapes.append({"k": "road", "pts": _strip(r[i], r[i + 1], PlainLayout.ROAD_HALF)})
	for m in [[PlainLayout.VILLAGE, "麦渡"], [PlainLayout.DOCK, "渡口"], [PlainLayout.MILL, "水磨坊"], [PlainLayout.GRANARY, "粮仓"], [PlainLayout.MANOR, "洛蒙德庄园"],
			[PlainLayout.ABBEY, "坠星院"], [PlainLayout.CAMP, "塞弗林营地"]]:
		shapes.append({"k": "mark", "at": m[0], "label": m[1]})
	shapes.append_array(PlainVillage.map_shapes())
	shapes.append({"k": "road", "pts": _strip(PlainLayout.BRIDGE[0], PlainLayout.BRIDGE[1], PlainVillage.BRIDGE_W * 0.5), "label": "木桥"})
	return {"bounds": PlainLayout.BOUNDS, "shapes": shapes, "exits": [], "zones": [
		{"name": "麦渡", "place": "maidu", "pts": _circle(PlainLayout.VILLAGE, PlainLayout.VILLAGE_R + 10.0)},
		{"name": "坠星院", "pts": _circle(PlainLayout.ABBEY, PlainLayout.ABBEY_HILL_R)},
		{"name": "洛蒙德庄园", "pts": _circle(PlainLayout.MANOR, PlainLayout.MANOR_R + 14.0)},
		{"name": "金穗平原", "pts": PackedVector2Array([Vector2(-150, -130), Vector2(150, -130), Vector2(150, 130), Vector2(-150, 130)])},
	]}


static func _strip(a: Vector2, b: Vector2, half: float) -> PackedVector2Array:
	var side := (b - a).normalized().orthogonal() * half
	return PackedVector2Array([a + side, b + side, b - side, a - side])


static func _circle(c: Vector2, r: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in 16:
		out.append(c + Vector2.from_angle(TAU * k / 16.0) * r)
	return out
