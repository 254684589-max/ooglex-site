class_name Highland
extends RefCounted
## 余火高地连片地图（路线图 5.1a，D10-B、D12；STORY.md 5.2；布局在 world/highland_layout.gd）。第一张有起伏的地图：
##   1. 同步：整张高度场（每 1 米一个点，算一次就缓存，换区域回来不再算）、一整块高度图碰撞（HeightMapShape3D）、四边看不见的墙（层 5「边界」）、
##      地图外面的远景地形（一圈越往外越稀的网格，东西两边抬成大山、北边是一望无际的冰原，雾里一层层淡下去）；
##   2. 画面分块：每 64 米一块，交给 ChunkStreamer 分帧搭——近处一份 1 米的网格、远处一份 4 米的网格（按距离切换，带裙边不露缝）。
## 地面一个着色器混四种写实贴图（shaders/highland_ground.gdshader）；天空是阴云照片（shaders/highland_sky.gdshader），按时段染色（apply_sky）。
## 贴图和天空照片在第二章章节包里（chapters/ch2/）：包没到（网页上直接 ?area=highland）时退回纯色，main 随后下载章节包再重新载入。

const SPAWNS_FN := "spawn_points"
const TEX_DIR := "res://chapters/ch2/tex/%s_%s_1k.jpg"
const SKY_PATH := "res://chapters/ch2/sky/overcast_sky.jpg"
## 预先算好的高度场和贴图分布（tests/gen_highland_field.gd 生成，放在章节包里）：现场算整张要 1 秒多（无头实测 1.2 秒，网页更慢），
## 读文件几毫秒。布局（HighlandLayout）改了要重新生成；测试会抽点对照，旧了就报错
const FIELD_PATH := "res://chapters/ch2/highland_field.res"
const PAINT_PATH := "res://chapters/ch2/highland_paint.res"
const LO_STEP := 4                       # 远处那份网格每几个采样点取一个
const LOD_DIST := 70.0                   # 多远换成远处那份（米，按块的包围盒算）
const SKIRT := 1.5                       # 远处那份网格四边往下垂的裙边（米）：和近处的块接缝处不露天
const FAR_EXTENT := 1400.0               # 远景地形铺多远
const SNOW_LAYERS := {"snow": "snow_02", "track": "snow_01", "scree": "gray_rocks", "rock": "mossy_rock"}

## 时段 → 天空：照片的染色、亮度，地平线（= 雾）的颜色（Daypart.PRESETS_AREA.highland 的 sky 就是这个地平线色）
const SKY := {
	"dawn": {"tint": Color(1.0, 0.9, 0.86), "energy": 0.85, "spin": 0.15},
	"day": {"tint": Color(0.95, 0.97, 1.0), "energy": 1.0, "spin": 0.0},
	"dusk": {"tint": Color(0.82, 0.72, 0.78), "energy": 0.55, "spin": 0.6},
	"night": {"tint": Color(0.32, 0.4, 0.55), "energy": 0.24, "spin": 0.3},
}

static var _field := PackedFloat32Array()     # 高度：z 一行一行、每行 x 从西到东（HeightMapShape3D 的顺序）
static var _paint := PackedColorArray()       # 每个点的贴图分布：r 路、g 碎石、b 遮蔽
static var _mat: ShaderMaterial
static var _sky_mat: ShaderMaterial
static var field_ms := 0.0

var parent: Node3D
var reduced_motion := false


static func build(p_parent: Node3D, reduced_motion := false) -> Transform3D:
	var t0 := Time.get_ticks_usec()
	var h := Highland.new()
	h.parent = p_parent
	h.reduced_motion = reduced_motion
	if not textures_ready():                         # 章节包没到（网页上直接进来）：不算地形，铺一块平地接住人；main 随后下载章节包、重新载入
		h._placeholder()
		print("IC_HIGHLAND placeholder (章节包没到)")
		var s0: Array = spawn_points().village
		return Transform3D(Basis(Vector3.UP, deg_to_rad(float(s0[1]))), s0[0])
	ensure_field()
	h._collision()
	ground_material()                                 # 分帧的活要用的材质、网格先在载入时（黑屏里）备好：头一次取贴图、编着色器要几十到上百毫秒
	HighlandFlora.warm(reduced_motion)
	for k in ["stone", "timber", "snow", "roof", "plaster", "peat", "bark"]:    # 村里的房子（5.2a）要用的材质：头一次载入贴图、画茅草几十毫秒
		Look.mat(k)
	Look.thatch()
	Look.glass_lit()
	Look.glass_dark()
	Look.halo(Look.WINDOW_COLOR, 0.32)
	HighlandRoad.warm()                               # 盘山路上的倒树、废羊棚、雪杆（5.3a）
	HighlandBeacon.warm()                             # 第十九烽：木栅的木桩（5.3b）
	h._far()
	HighlandFlora.far_forest(p_parent)               # 地图外面山坡上的针叶林、山脊上远处那串烽燧塔（5.1b）
	HighlandFlora.far_beacons(p_parent)
	HighlandVillage.stream_ice(p_parent)              # 羊脊村（5.2a）：结冰的溪、门、路牌（同步：一进场就推得开）
	HighlandVillage.interactables(p_parent)
	HighlandVillage.people(p_parent)
	HighlandBeacon.interactables(p_parent)            # 第十九烽的塔门、塔顶的天窗、营房的门（5.3b）
	HighlandBeacon.people(p_parent)                   # 第十九烽的人：马蒂亚斯、诺伯特、营里的兵（5.3c）
	var st := ChunkStreamer.new()
	st.name = "Streamer"
	st.host = p_parent
	st.builder = h
	p_parent.add_child(st)
	h._jobs(st)
	print("IC_HIGHLAND sync ms=%.0f field_ms=%.0f chunks=%d tex=%s" % [float(Time.get_ticks_usec() - t0) / 1000.0, field_ms, st.chunks.size(), textures_ready()])
	var s: Array = spawn_points().village
	return Transform3D(Basis(Vector3.UP, deg_to_rad(float(s[1]))), s[0])


static func spawn_points() -> Dictionary:
	return HighlandLayout.spawn_points()


static func views() -> Array:
	return HighlandLayout.views()


## 第二章章节包里的贴图到了没有（编辑器、无头测试里本来就在）
static func textures_ready() -> bool:
	return ResourceLoader.exists(SKY_PATH)


# ---------------- 高度场 ----------------

## 整张高度场和贴图分布（缓存在静态变量里：换区域、读档回来不再读）：先读预先算好的文件，没有（章节包没到）才现场算
static func ensure_field() -> void:
	if _field.size() == HighlandLayout.NX * HighlandLayout.NZ:
		return
	var t0 := Time.get_ticks_usec()
	if ResourceLoader.exists(FIELD_PATH) and ResourceLoader.exists(PAINT_PATH):
		var fi := load(FIELD_PATH) as Image
		var pi := load(PAINT_PATH) as Image
		if fi != null and pi != null and fi.get_width() == HighlandLayout.NX and fi.get_height() == HighlandLayout.NZ:
			_field = fi.get_data().to_float32_array()
			var bytes := pi.get_data()
			_paint.resize(HighlandLayout.NX * HighlandLayout.NZ)
			for k in _paint.size():
				_paint[k] = Color8(bytes[k * 3], bytes[k * 3 + 1], bytes[k * 3 + 2])
			field_ms = float(Time.get_ticks_usec() - t0) / 1000.0
			return
	compute_field()
	field_ms = float(Time.get_ticks_usec() - t0) / 1000.0


## 现场算整张高度场和贴图分布（生成文件、章节包没到时用）
static func compute_field() -> void:
	var nx := HighlandLayout.NX
	var nz := HighlandLayout.NZ
	var x0 := HighlandLayout.BOUNDS.position.x
	var z0 := HighlandLayout.BOUNDS.position.y
	_field.resize(nx * nz)
	_paint.resize(nx * nz)
	for j in nz:
		var z := z0 + j * HighlandLayout.STEP
		for i in nx:
			var x := x0 + i * HighlandLayout.STEP
			_field[j * nx + i] = HighlandLayout.height(x, z)
			var m := HighlandLayout.masks(x, z)
			_paint[j * nx + i] = Color(m.x, m.y, 1.0)
	for j in range(1, nz - 1):                         # 遮蔽：比周围低的地方（沟、路边的切口）暗一点
		for i in range(1, nx - 1):
			var k := j * nx + i
			var around := (_field[k - 1] + _field[k + 1] + _field[k - nx] + _field[k + nx]) * 0.25
			var c := _paint[k]
			c.b = clampf(1.0 - maxf(around - _field[k], 0.0) * 0.35, 0.72, 1.0)
			_paint[k] = c


## 把现在的高度场和贴图分布存成文件（tests/gen_highland_field.gd 调）
static func save_field() -> void:
	var fi := Image.create_from_data(HighlandLayout.NX, HighlandLayout.NZ, false, Image.FORMAT_RF, _field.to_byte_array())
	var bytes := PackedByteArray()
	bytes.resize(_paint.size() * 3)
	for k in _paint.size():
		var c := _paint[k]
		bytes[k * 3] = c.r8
		bytes[k * 3 + 1] = c.g8
		bytes[k * 3 + 2] = c.b8
	var pi := Image.create_from_data(HighlandLayout.NX, HighlandLayout.NZ, false, Image.FORMAT_RGB8, bytes)
	ResourceSaver.save(fi, FIELD_PATH, ResourceSaver.FLAG_COMPRESS)
	ResourceSaver.save(pi, PAINT_PATH, ResourceSaver.FLAG_COMPRESS)


## 高度场里一点的高度（双线性插值；出了地图按 HighlandLayout.height 算）
static func height_at(x: float, z: float) -> float:
	ensure_field()
	var fx := (x - HighlandLayout.BOUNDS.position.x) / HighlandLayout.STEP
	var fz := (z - HighlandLayout.BOUNDS.position.y) / HighlandLayout.STEP
	if fx < 0.0 or fz < 0.0 or fx > HighlandLayout.NX - 1 or fz > HighlandLayout.NZ - 1:
		return HighlandLayout.height(x, z)
	var i := mini(int(fx), HighlandLayout.NX - 2)
	var j := mini(int(fz), HighlandLayout.NZ - 2)
	var tx := fx - i
	var tz := fz - j
	var n := HighlandLayout.NX
	var a := lerpf(_field[j * n + i], _field[j * n + i + 1], tx)
	var b := lerpf(_field[(j + 1) * n + i], _field[(j + 1) * n + i + 1], tx)
	return lerpf(a, b, tz)


static func _h(i: int, j: int) -> float:
	return _field[clampi(j, 0, HighlandLayout.NZ - 1) * HighlandLayout.NX + clampi(i, 0, HighlandLayout.NX - 1)]


static func _normal(i: int, j: int, step: int) -> Vector3:
	var dx := (_h(i + step, j) - _h(i - step, j)) / (2.0 * step)
	var dz := (_h(i, j + step) - _h(i, j - step)) / (2.0 * step)
	return Vector3(-dx, 1.0, -dz).normalized()


# ---------------- 碰撞 ----------------

## 章节包没到时的占位：出生点脚下一块平地（看不见，下载画面盖着）
func _placeholder() -> void:
	var b := StaticBody3D.new()
	b.name = "HighlandPlaceholder"
	parent.add_child(b)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(400, 1, 400)
	cs.shape = bs
	var s: Array = spawn_points().village
	cs.position = (s[0] as Vector3) - Vector3(0, 0.5, 0)
	b.add_child(cs)


func _collision() -> void:
	var ground := StaticBody3D.new()
	ground.name = "HighlandGround"
	ground.collision_layer = 1
	ground.collision_mask = 0
	ground.set_meta("surface", "snow")
	ground.set_meta("surface_at", HighlandLayout.surface_at)     # 深雪按位置查（5.3a）
	parent.add_child(ground)
	var cs := CollisionShape3D.new()
	var hm := HeightMapShape3D.new()
	hm.map_width = HighlandLayout.NX
	hm.map_depth = HighlandLayout.NZ
	hm.map_data = _field
	cs.shape = hm
	cs.position = Vector3(HighlandLayout.BOUNDS.get_center().x, 0.0, HighlandLayout.BOUNDS.get_center().y)   # 高度图以自己的中心为原点、每格 1 米
	ground.add_child(cs)
	var flora := StaticBody3D.new()                  # 树干（圆柱）和大石头（球）挡人（5.1b）
	flora.name = "HighlandFlora"
	flora.collision_layer = 1
	flora.collision_mask = 0
	parent.add_child(flora)
	var trunk := CylinderShape3D.new()
	trunk.radius = 0.28
	trunk.height = 3.0
	for t in HighlandFlora.trees():
		var tc := CollisionShape3D.new()
		tc.shape = trunk
		tc.position = (t[0] as Vector3) + Vector3(0, 1.5, 0)
		flora.add_child(tc)
	for rk in HighlandFlora.rocks():
		var size := float(rk[2])
		if size < 0.9:
			continue                                     # 小石头跨得过去（台阶 0.3 米以内能直接迈上去）
		var rc := CollisionShape3D.new()
		var sp := SphereShape3D.new()
		sp.radius = size * 0.42
		rc.shape = sp
		rc.position = (rk[0] as Vector3) + Vector3(0, size * 0.12, 0)
		flora.add_child(rc)
	var village := StaticBody3D.new()                # 羊脊村：房子、驿站、铁匠棚、石墙、羊圈、立石、零碎（5.2a）
	village.name = "VillageSolids"
	village.collision_layer = 1
	village.collision_mask = 0
	parent.add_child(village)
	for so in HighlandVillage.solids():
		var vc := CollisionShape3D.new()
		var vb := BoxShape3D.new()
		vb.size = so[1]
		vc.shape = vb
		vc.transform = so[0]
		village.add_child(vc)
	var road := StaticBody3D.new()                   # 盘山路上：倒树的树干和根盘、废羊棚的墙（5.3a）
	road.name = "RoadSolids"
	road.collision_layer = 1
	road.collision_mask = 0
	parent.add_child(road)
	for so in HighlandRoad.solids() + HighlandBeacon.solids():          # 第十九烽的塔、雉堞、火盆、木栅、营房、两个棚（5.3b）
		var rc := CollisionShape3D.new()
		var rb := BoxShape3D.new()
		rb.size = so[1]
		rc.shape = rb
		rc.transform = so[0]
		road.add_child(rc)
	var wb := StaticBody3D.new()
	wb.name = "HighlandWalls"
	wb.collision_layer = FpController.LAYER_BOUNDARY
	wb.collision_mask = 0
	parent.add_child(wb)
	var r := HighlandLayout.BOUNDS.grow(-HighlandLayout.WALL_INSET)
	var hh := HighlandLayout.WALL_H
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
	_mat.shader = load("res://shaders/highland_ground.gdshader")
	_mat.set_shader_parameter("macro_noise", Look.noise_texture())
	var fallback := {"snow": Color("c9d3dc"), "track": Color("aeb4bc"), "scree": Color("6a6c70"), "rock": Color("5a5e60")}
	for k in SNOW_LAYERS:
		var id: String = SNOW_LAYERS[k]
		var alb: Texture2D = _tex(TEX_DIR % [id, "diff"])
		var nrm: Texture2D = _tex(TEX_DIR % [id, "nor_gl"])
		if alb == null:
			alb = _flat(fallback[k])                   # 章节包没到：纯色（main 随后下载章节包、重新载入）
		if nrm == null:
			nrm = _flat(Color(0.5, 0.5, 1.0))
		_mat.set_shader_parameter(k + "_alb", alb)
		_mat.set_shader_parameter(k + "_nrm", nrm)
	return _mat


## 章节包换了（下载完重新载入）：材质重新取贴图
static func clear_cache() -> void:
	HighlandFlora.clear_cache()
	HighlandRoad.clear_cache()
	HighlandBeacon.clear_cache()
	_mat = null
	_sky_mat = null


static func _tex(path: String) -> Texture2D:
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


static func _flat(c: Color) -> Texture2D:
	var img := Image.create(4, 4, false, Image.FORMAT_RGB8)
	img.fill(c)
	return ImageTexture.create_from_image(img)


## 天空材质（Daypart 套时段时调 apply_sky 改参数）
static func sky_material() -> ShaderMaterial:
	if _sky_mat == null:
		_sky_mat = ShaderMaterial.new()
		_sky_mat.shader = load("res://shaders/highland_sky.gdshader")
		var t: Texture2D = _tex(SKY_PATH)
		_sky_mat.set_shader_parameter("pano", t if t != null else _flat(Color("9aa3ae")))
	return _sky_mat


## 时段：背景换成天空（照片按时段染色），雾不盖天空（天空自己在地平线渐变到雾色）。main.env、Daypart 的预设都已经套过
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
	env.tonemap_exposure = 0.76                     # 满眼是雪：曝光压一点，坡的明暗才不被冲白


# ---------------- 画面 ----------------

func _jobs(st: ChunkStreamer) -> void:
	var b := HighlandLayout.BOUNDS
	var cs := HighlandLayout.CHUNK
	var cx := 0
	var x := b.position.x
	while x < b.end.x - 0.01:
		var cz := 0
		var z := b.position.y
		while z < b.end.y - 0.01:
			var r := Rect2(x, z, minf(cs, b.end.x - x), minf(cs, b.end.y - z))
			var jobs: Array = [_job_terrain.bind(r), _job_flora.bind(r)]
			jobs.append_array(HighlandVillage.jobs_for(r, reduced_motion))      # 村里的房子、石墙、羊、石圈、零碎（5.2a）
			jobs.append_array(HighlandRoad.jobs_for(r))                         # 盘山路上的倒树、废羊棚、雪杆（5.3a）
			jobs.append_array(HighlandBeacon.jobs_for(r, reduced_motion))       # 第十九烽：塔、火盆、木栅、营房、棚（5.3b）
			st.add_chunk("%d_%d" % [cx, cz], r, jobs)
			z += cs
			cz += 1
		x += cs
		cx += 1


## 一块里的树和石头（5.1b，HighlandFlora）
func _job_flora(root: Node3D, r: Rect2) -> void:
	HighlandFlora.build_chunk(root, r, reduced_motion)


## 一块地形：近处 1 米的网格 + 远处 4 米的网格（按距离切换）
func _job_terrain(root: Node3D, r: Rect2) -> void:
	var i0 := int(round((r.position.x - HighlandLayout.BOUNDS.position.x) / HighlandLayout.STEP))
	var j0 := int(round((r.position.y - HighlandLayout.BOUNDS.position.y) / HighlandLayout.STEP))
	var i1 := i0 + int(round(r.size.x / HighlandLayout.STEP))
	var j1 := j0 + int(round(r.size.y / HighlandLayout.STEP))
	var hi := MeshInstance3D.new()
	hi.name = "Terrain"
	hi.mesh = grid_mesh(i0, j0, i1, j1, 1, 0.0)
	hi.material_override = ground_material()
	hi.visibility_range_end = LOD_DIST + 6.0
	hi.visibility_range_end_margin = 6.0
	hi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	hi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF      # 阴天没有硬影子；山脊的影子在阴影距离（25 米）边上会切出一条直线（截图）
	root.add_child(hi)
	var lo := MeshInstance3D.new()
	lo.name = "TerrainFar"
	lo.mesh = grid_mesh(i0, j0, i1, j1, LO_STEP, SKIRT)
	lo.material_override = ground_material()
	lo.visibility_range_begin = LOD_DIST
	lo.visibility_range_begin_margin = 6.0
	lo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(lo)
	# 包围盒按块的中心算距离：块的原点放在块中心（网格顶点按世界坐标减掉它）
	var c := r.get_center()
	hi.position = Vector3(c.x, 0.0, c.y)
	lo.position = Vector3(c.x, 0.0, c.y)


## 高度场上 [i0, i1] × [j0, j1] 这一片的网格（每 step 个点取一个；skirt > 0 时四边加往下垂的裙边）。顶点相对这一片的中心
static func grid_mesh(i0: int, j0: int, i1: int, j1: int, step: int, skirt: float) -> ArrayMesh:
	var bx := HighlandLayout.BOUNDS.position.x
	var bz := HighlandLayout.BOUNDS.position.y
	var cx := bx + (i0 + i1) * 0.5 * HighlandLayout.STEP
	var cz := bz + (j0 + j1) * 0.5 * HighlandLayout.STEP
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
	var nx := HighlandLayout.NX
	for rj in nr:
		var jj := rows[rj]
		for ci in nc:
			var ii := cols[ci]
			var k := rj * nc + ci
			verts[k] = Vector3(bx + ii * HighlandLayout.STEP - cx, _field[jj * nx + ii], bz + jj * HighlandLayout.STEP - cz)
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
		var edges := []                                # 四条边：沿边的顶点下标（按顺序）、往外的方向
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
		edges = [top, bottom, left, right]
		for e: Array[int] in edges:
			var base := verts.size()
			for k in e:
				verts.append(verts[k] - Vector3(0, skirt, 0))
				norms.append(norms[k])
				colors.append(colors[k])
			for n in e.size() - 1:
				var a := e[n]
				var b := e[n + 1]
				var a2 := base + n
				var b2 := base + n + 1
				idx.append_array(PackedInt32Array([a, a2, b, b, a2, b2, a, b, a2, b, b2, a2]))    # 两面都画（哪边朝外不用管）
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = colors
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## 远景地形：地图外面一圈（越往外越稀），高度接着 HighlandLayout.height 往外算，再加：东西两边抬成大山、南边是起伏的山谷、北边是平的冰原。
## 一个网格、不投影子；颜色只有雪（远处都被雾吞了，看的是轮廓）。地图边上一圈和地形块重叠、往下压 0.4 米，不会盖住近处
func _far() -> void:
	var lines := _far_lines()
	var b := HighlandLayout.BOUNDS
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
			colors[j * n + i] = Color(0.0, 0.0, 1.0)
	for j in n:
		for i in n:
			var i0 := maxi(i - 1, 0)
			var i1 := mini(i + 1, n - 1)
			var j0 := maxi(j - 1, 0)
			var j1 := mini(j + 1, n - 1)
			var dx := verts[j * n + i1] - verts[j * n + i0]
			var dz := verts[j1 * n + i] - verts[j0 * n + i]
			norms[j * n + i] = dz.cross(dx).normalized()
	var idx := PackedInt32Array()
	var inner := b.grow(-2.0)
	for j in n - 1:
		for i in n - 1:
			var cell := Rect2(lines[i], lines[j], lines[i + 1] - lines[i], lines[j + 1] - lines[j])
			if inner.encloses(cell):
				continue                                   # 地图里面由地形块画
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


## 远景网格的格线（x、z 共用）：地图里每 16 米，地图边外 200 米内每 16 米，再往外越来越稀
static func _far_lines() -> Array:
	var out := []
	var x := -FAR_EXTENT
	while x < FAR_EXTENT:
		out.append(x)
		var ax := absf(x)
		var step := 16.0 if ax < 380.0 else (40.0 if ax < 700.0 else 100.0)
		x += step
	out.append(FAR_EXTENT)
	return out


## 远景地形的高度：地图里面和地形一致（往下压一点，免得盖住地形块的边），外面接着往外长
static func far_height(x: float, z: float) -> float:
	var b := HighlandLayout.BOUNDS
	var dx := maxf(maxf(b.position.x - x, x - b.end.x), 0.0)
	var dz := maxf(maxf(b.position.y - z, z - b.end.y), 0.0)
	var out := sqrt(dx * dx + dz * dz)
	var y := HighlandLayout.natural(x, z) - 0.4
	if out <= 0.0:
		return y
	var ax := absf(x)
	var mountains := 120.0 * HighlandLayout._smooth(clampf((ax - 170.0) / 500.0, 0.0, 1.0)) * (0.7 + 0.3 * sin(z / 90.0 + x / 140.0))
	mountains += 45.0 * maxf(sin(x / 61.0 + 0.5) * sin(z / 47.0), 0.0) * clampf((ax - 200.0) / 200.0, 0.0, 1.0)
	if z < -130.0:                                  # 北边：冰原，越往北越平，东西的大山也矮下去
		var k := clampf((-130.0 - z) / 500.0, 0.0, 1.0)
		mountains *= 1.0 - 0.75 * k
		y = lerpf(y, 29.0 + 0.6 * sin(x / 33.0) * sin(z / 27.0), clampf((-130.0 - z) / 60.0, 0.0, 1.0))
	elif z > 130.0:                                 # 南边：山谷往下、两边丘陵
		y -= minf((z - 130.0) * 0.06, 25.0)
		y += 30.0 * HighlandLayout._smooth(clampf((ax - 60.0) / 300.0, 0.0, 1.0)) * clampf((z - 130.0) / 200.0, 0.0, 1.0)
	var k2 := clampf(out / 40.0, 0.0, 1.0)          # 地图边外 40 米内慢慢接上
	return y + mountains * k2


## 地图册（3.11）「本地」页：路、溪、村里的房子、羊圈、田间石墙、石圈、两座烽燧、路牌；驿站的门是出口。
## 分块（zones）：羊脊村、第十九烽是旅行地图上的两个地点（Travel.place_of_area 按你站在哪块分），盘山路、白寂边缘只是地名
static func map_spec() -> Dictionary:
	var shapes := []
	for i in HighlandLayout.ROAD.size() - 1:
		shapes.append({"k": "road", "pts": _strip(HighlandLayout.ROAD[i], HighlandLayout.ROAD[i + 1], HighlandLayout.ROAD_HALF)})
	for i in HighlandLayout.STREAM.size() - 1:
		var sh := {"k": "water", "pts": _strip(HighlandLayout.STREAM[i], HighlandLayout.STREAM[i + 1], HighlandLayout.STREAM_HALF)}
		if i == 3:
			sh["label"] = "冻住的溪"
		shapes.append(sh)
	for c in HighlandLayout.CROFTS:
		shapes.append({"k": "house", "pts": House.footprint(HighlandVillage.croft_pos(c), float(c[2]), float(c[3]), float(c[4]))})
	var wy := float(HighlandLayout.WAYSTATION[1])
	shapes.append({"k": "house", "pts": House.footprint(HighlandVillage.waystation_pos(), wy, float(HighlandLayout.WAYSTATION[2]), float(HighlandLayout.WAYSTATION[3])), "label": "驿站"})
	var sm: Vector2 = HighlandLayout.SMITHY[0]
	shapes.append({"k": "house", "pts": House.footprint(Vector3(sm.x, 0, sm.y), float(HighlandLayout.SMITHY[1]), 4.2, 3.2), "label": "铁匠"})
	for seg in HighlandVillage.wall_pieces():
		var a := Vector2(seg.c.x, seg.c.z)
		var dir := Vector2(cos(float(seg.yaw)), -sin(float(seg.yaw))) * float(seg.len) * 0.5
		shapes.append({"k": "wall", "pts": _strip(a - dir, a + dir, HighlandLayout.WALL_W * 0.5)})
	shapes.append({"k": "mark", "at": HighlandLayout.PEN_ROUND[0], "label": "羊圈"})
	shapes.append({"k": "mark", "at": HighlandLayout.STONE_RING, "label": "石圈"})
	shapes.append({"k": "mark", "at": HighlandLayout.SHED[0], "label": "废羊棚"})
	var tp := HighlandBeacon.tower_place()                         # 第十九烽（5.3b）：塔、营房、两个棚、木栅
	shapes.append({"k": "house", "pts": _square(Vector2(tp.origin.x, tp.origin.z), float(HighlandLayout.TOWER[1]), HighlandLayout.TOWER_W, HighlandLayout.TOWER_W), "label": "塔"})
	for b in [[HighlandLayout.BARRACKS, "营房"], [HighlandLayout.WOODSHED, "柴棚"], [HighlandLayout.GRANARY, "粮棚"]]:
		var sp: Array = b[0]
		shapes.append({"k": "house", "pts": _square(sp[0], float(sp[1]), float(sp[2]), float(sp[3])), "label": b[1]})
	var ring := _circle(HighlandLayout.BEACON19, HighlandLayout.PALISADE_R)
	var gate := HighlandLayout.BEACON19 + HighlandBeacon.gate_dir() * HighlandLayout.PALISADE_R
	for k in ring.size():
		var a: Vector2 = ring[k]
		var b2: Vector2 = ring[(k + 1) % ring.size()]
		if ((a + b2) * 0.5).distance_to(gate) > HighlandLayout.GATE_W * 0.8:
			shapes.append({"k": "wall", "pts": _strip(a, b2, 0.25)})
	shapes.append({"k": "mark", "at": HighlandLayout.BEACON19, "icon": "fire", "label": "第十九烽"})
	shapes.append({"k": "mark", "at": HighlandLayout.BEACON18, "label": "第十八烽"})
	for sp in [HighlandLayout.SIGN_VILLAGE, HighlandLayout.SIGN_BEACON]:
		shapes.append({"k": "mark", "at": Vector2(sp.x, sp.z), "icon": "sign", "label": "路牌"})
	var door := House.door_xz(HighlandVillage.waystation_pos(), wy, float(HighlandLayout.WAYSTATION[4]))
	var exits := [{"at": door, "dir": -House.facing(wy), "to": "waystation", "spawn": "front", "name": HighlandVillage.WAYSTATION_DOOR}]
	var td := tp * Vector3(0, 0, HighlandLayout.TOWER_W * 0.5)
	var tdir := tp.basis * Vector3.BACK
	exits.append({"at": Vector2(td.x, td.z), "dir": Vector2(tdir.x, tdir.z), "to": "beacon_tower", "spawn": "front", "name": HighlandBeacon.TOWER_DOOR})
	return {"bounds": HighlandLayout.BOUNDS, "shapes": shapes, "exits": exits, "zones": zones()}


## 地图上的分块：先具体的（两座烽燧、村子），再大片的
static func zones() -> Array:
	return [
		{"name": "第十九烽", "place": "beacon19", "pts": _circle(HighlandLayout.BEACON19, 26.0)},
		{"name": "第十八烽", "pts": _circle(HighlandLayout.BEACON18, 20.0)},
		{"name": "羊脊村", "place": "yangji", "pts": _circle(HighlandLayout.VILLAGE, HighlandLayout.VILLAGE_R + 12.0)},
		{"name": "白寂边缘", "pts": PackedVector2Array([Vector2(-160, -130), Vector2(160, -130), Vector2(160, -92), Vector2(-160, -92)])},
		{"name": "盘山路", "pts": PackedVector2Array([Vector2(-160, -92), Vector2(160, -92), Vector2(160, 130), Vector2(-160, 130)])},
	]


static func _strip(a: Vector2, b: Vector2, half: float) -> PackedVector2Array:
	var side := (b - a).normalized().orthogonal() * half
	return PackedVector2Array([a + side, b + side, b - side, a - side])


## 一块长方形（中心、朝向（度，同 Basis(UP, yaw)）、宽、纵深）
static func _square(c: Vector2, yaw: float, w: float, d: float) -> PackedVector2Array:
	var b := Basis(Vector3.UP, deg_to_rad(yaw))
	var out := PackedVector2Array()
	for p in [Vector3(-w, 0, -d), Vector3(w, 0, -d), Vector3(w, 0, d), Vector3(-w, 0, d)]:
		var q: Vector3 = b * (p * 0.5)
		out.append(c + Vector2(q.x, q.z))
	return out


static func _circle(c: Vector2, r: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in 16:
		out.append(c + Vector2.from_angle(TAU * k / 16.0) * r)
	return out
