class_name Harbor
extends RefCounted
## 双钥港连片地图（路线图 7.1，D10-B、D12；STORY.md 7.2、7.7；布局在 world/harbor_layout.gd）。照金穗平原（world/plain.gd）的做法：
##   1. 同步：整张高度场（每 1 米一个点；先读第四章章节包里预先算好的文件）、一整块高度图碰撞（脚下泥滩、浅水按位置查）、
##      四边看不见的墙和深水边的一圈墙（层 5「边界」：河道、泥滩外的海走不进去）、水面（河、潮沟、泥滩、海一整片，按潮位升降）、
##      地图外面的远景（南边一直是海，北边、西边是低低的岸，河往北接着流）；
##   2. 画面分块：每 64 米一块，交给 ChunkStreamer 分帧搭——近处 1 米的网格、远处 2 米的网格（按距离切换，带裙边）。
## 地面一个着色器混五种写实贴图（shaders/harbor_ground.gdshader：城里踩成泥雪的地、铺石的街和码头边、退潮露出来的泥滩、沙嘴的沙、潮线上的卵石），
## 陡的地方（码头的石岸、潮沟两壁）按石头砌的墙贴；天空是一张压得很低的海上阴云照片（shaders/highland_sky.gdshader），按时段染色。
## 潮汐（STORY.md 7.7）：潮位按时段（TIDE：白天涨、夜里退），换时段时 set_tide 把水面挪上挪下；不做实时涨落。
## 贴图和照片在第四章章节包里（chapters/ch4/）：包没到时退回纯色，main 随后下载章节包、重新载入。

const TEX_DIR := "res://chapters/ch4/tex/%s_%s_1k.jpg"
const SKY_PATH := "res://chapters/ch4/sky/sea_cloud_sky.jpg"
const FIELD_PATH := "res://chapters/ch4/harbor_field.res"
const PAINT_PATH := "res://chapters/ch4/harbor_paint.res"
const LO_STEP := 2
const LOD_DIST := 80.0
const SKIRT := 1.2
const FAR_EXTENT := 1600.0
const LAYERS := {"ground": "snow_03", "paved": "cobblestone_floor_08", "mud": "brown_mud_03", "sand": "coast_sand_01", "shingle": "coast_sand_rocks_02"}
const WATER_STEP := 2.0
## 潮位（米）：白天涨（泥滩盖在水下、潮沟里能走船），夜里退（泥滩、潮沟底露出来）；清晨、黄昏在中间
const TIDE := {"dawn": -1.45, "day": -0.5, "dusk": -1.05, "night": -2.1}
const DEEP_WALL_TOP := 1.0                # 深水边那圈墙的顶：比码头、盐沼低（码头上走的人从上面过，7.2 的栈桥也一样）

## 时段 → 天空（照片的染色、亮度、转多少）
const SKY := {
	"dawn": {"tint": Color(1.02, 0.92, 0.88), "energy": 0.92, "spin": 0.12},
	"day": {"tint": Color(0.98, 1.0, 1.02), "energy": 1.0, "spin": 0.0},
	"dusk": {"tint": Color(1.0, 0.84, 0.76), "energy": 0.7, "spin": 0.5},
	"night": {"tint": Color(0.36, 0.44, 0.62), "energy": 0.42, "spin": 0.3},      # 云很厚：再暗就是一片黑（截图）
}

static var _field := PackedFloat32Array()
static var _paint := PackedColorArray()        # r 铺石、g 沙、b 遮蔽
static var _mat: ShaderMaterial
static var _water_mat: ShaderMaterial
static var _sky_mat: ShaderMaterial
static var field_ms := 0.0
static var tide_override := NAN               # 测试用：不按时段，直接给潮位

var parent: Node3D
var reduced_motion := false


static func build(p_parent: Node3D, reduced_motion := false) -> Transform3D:
	var t0 := Time.get_ticks_usec()
	var hb := Harbor.new()
	hb.parent = p_parent
	hb.reduced_motion = reduced_motion
	var s: Array = spawn_points().quay
	if not textures_ready():
		hb._placeholder()
		print("IC_HARBOR placeholder (章节包没到)")
		return Transform3D(Basis(Vector3.UP, deg_to_rad(float(s[1]))), s[0])
	ensure_field()
	for k in ["roof", "plaster", "castle", "stone", "timber", "snow"]:
		Look.mat(k)                                    # 房子的贴图先读（第一块房子在分帧的活里才读，那一块要多七八十毫秒，6.3b）
	HarborTown.mats()
	hb._collision()
	hb._deep_walls()
	ground_material()
	water_material()
	hb._water()
	hb._far()
	hb._wild()                                        # 地图外面：无尽荒野（2026-11-08）
	HarborTown.interactables(p_parent)               # 双钥港的城（7.2）：门、路牌、钥楼门口的告示（同步：一进场就看得见、推得开）
	HarborTown.ships(p_parent)                       # 河口停着的两条船（跟着潮位上下）
	HarborPeople.build(p_parent)                     # 城里的人（7.4）：码头、鱼市、钥楼街上只说一句的
	for n in p_parent.get_children():                # 门、路牌远了不画（同平原，6.7a）
		if n is Door or n is RoadSign:
			Plain._cut_far(n, Plain.DETAIL_FAR)
	var st := ChunkStreamer.new()
	st.name = "Streamer"
	st.host = p_parent
	st.builder = hb
	p_parent.add_child(st)
	hb._jobs(st)
	set_tide(p_parent)
	print("IC_HARBOR sync ms=%.0f field_ms=%.0f chunks=%d tide=%.2f tex=%s" % [float(Time.get_ticks_usec() - t0) / 1000.0, field_ms, st.chunks.size(), tide(), textures_ready()])
	return Transform3D(Basis(Vector3.UP, deg_to_rad(float(s[1]))), s[0])


static func spawn_points() -> Dictionary:
	return HarborLayout.spawn_points()


static func views() -> Array:
	return HarborLayout.views()


static func textures_ready() -> bool:
	return ResourceLoader.exists(SKY_PATH)


## 现在的潮位
static func tide() -> float:
	if not is_nan(tide_override):
		return tide_override
	return float(TIDE.get(Daypart.current, TIDE.day))                 # 时段由 Daypart.apply 记下（不直接读 GameState：生成高度场的脚本里没有自动加载）


## 退潮了没有（泥滩、潮沟底露出来）
static func low_tide() -> bool:
	return tide() < HarborLayout.CANAL_BED - 0.2


## 换时段：水面挪到这个时段的潮位（Daypart.apply 调）
static func set_tide(root: Node) -> void:
	var y := tide()
	for nm in ["HarborWater", "FarSea"]:
		var w := root.find_child(nm, true, false) as Node3D
		if w:
			w.position.y = y
	for n in root.get_children():                    # 停在河口的船跟着潮位浮起来、落下去（7.2）
		if n.is_in_group("tide_float"):
			(n as Node3D).position.y = y + float(n.get_meta("float_off", 0.0))
	if _water_mat:
		_water_mat.set_shader_parameter("tide", y)
	if _mat:
		_mat.set_shader_parameter("tide", y)                          # 地面：潮位以下、刚退潮的地方是湿的


# ---------------- 高度场 ----------------

static func ensure_field() -> void:
	if _field.size() == HarborLayout.NX * HarborLayout.NZ:
		return
	var t0 := Time.get_ticks_usec()
	if ResourceLoader.exists(FIELD_PATH) and ResourceLoader.exists(PAINT_PATH):
		var fi := load(FIELD_PATH) as Image
		var pi := load(PAINT_PATH) as Image
		if fi != null and pi != null and fi.get_width() == HarborLayout.NX and fi.get_height() == HarborLayout.NZ:
			_field = fi.get_data().to_float32_array()
			var bytes := pi.get_data()
			_paint.resize(HarborLayout.NX * HarborLayout.NZ)
			for k in _paint.size():
				_paint[k] = Color8(bytes[k * 3], bytes[k * 3 + 1], bytes[k * 3 + 2])
			field_ms = float(Time.get_ticks_usec() - t0) / 1000.0
			return
	compute_field()
	field_ms = float(Time.get_ticks_usec() - t0) / 1000.0


static func compute_field() -> void:
	var nx := HarborLayout.NX
	var nz := HarborLayout.NZ
	var x0 := HarborLayout.BOUNDS.position.x
	var z0 := HarborLayout.BOUNDS.position.y
	_field.resize(nx * nz)
	_paint.resize(nx * nz)
	for j in nz:
		var z := z0 + j * HarborLayout.STEP
		for i in nx:
			var x := x0 + i * HarborLayout.STEP
			_field[j * nx + i] = HarborLayout.height(x, z)
			var m := HarborLayout.masks(x, z)
			_paint[j * nx + i] = Color(m.x, m.y, m.z)


static func save_field() -> void:
	var fi := Image.create_from_data(HarborLayout.NX, HarborLayout.NZ, false, Image.FORMAT_RF, _field.to_byte_array())
	var bytes := PackedByteArray()
	bytes.resize(_paint.size() * 3)
	for k in _paint.size():
		var c := _paint[k]
		bytes[k * 3] = c.r8
		bytes[k * 3 + 1] = c.g8
		bytes[k * 3 + 2] = c.b8
	var pi := Image.create_from_data(HarborLayout.NX, HarborLayout.NZ, false, Image.FORMAT_RGB8, bytes)
	ResourceSaver.save(fi, FIELD_PATH, ResourceSaver.FLAG_COMPRESS)
	ResourceSaver.save(pi, PAINT_PATH, ResourceSaver.FLAG_COMPRESS)


static func height_at(x: float, z: float) -> float:
	ensure_field()
	var fx := (x - HarborLayout.BOUNDS.position.x) / HarborLayout.STEP
	var fz := (z - HarborLayout.BOUNDS.position.y) / HarborLayout.STEP
	if fx < 0.0 or fz < 0.0 or fx > HarborLayout.NX - 1 or fz > HarborLayout.NZ - 1:
		return HarborLayout.height(x, z)
	var i := mini(int(fx), HarborLayout.NX - 2)
	var j := mini(int(fz), HarborLayout.NZ - 2)
	var tx := fx - i
	var tz := fz - j
	var n := HarborLayout.NX
	var a := lerpf(_field[j * n + i], _field[j * n + i + 1], tx)
	var b := lerpf(_field[(j + 1) * n + i], _field[(j + 1) * n + i + 1], tx)
	return lerpf(a, b, tz)


static func _h(i: int, j: int) -> float:
	return _field[clampi(j, 0, HarborLayout.NZ - 1) * HarborLayout.NX + clampi(i, 0, HarborLayout.NX - 1)]


static func _normal(i: int, j: int, step: int) -> Vector3:
	var dx := (_h(i + step, j) - _h(i - step, j)) / (2.0 * step)
	var dz := (_h(i, j + step) - _h(i, j - step)) / (2.0 * step)
	return Vector3(-dx, 1.0, -dz).normalized()


# ---------------- 碰撞 ----------------

func _placeholder() -> void:
	var b := StaticBody3D.new()
	b.name = "HarborPlaceholder"
	parent.add_child(b)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(400, 1, 400)
	cs.shape = bs
	var s: Array = spawn_points().quay
	cs.position = (s[0] as Vector3) - Vector3(0, 0.5, 0)
	b.add_child(cs)


func _collision() -> void:
	var ground := StaticBody3D.new()
	ground.name = "HarborGround"
	ground.collision_layer = 1
	ground.collision_mask = 0
	ground.set_meta("surface", "")
	ground.set_meta("surface_at", HarborLayout.surface_at)        # 泥滩、浅水按位置和潮位查
	parent.add_child(ground)
	var cs := CollisionShape3D.new()
	var hm := HeightMapShape3D.new()
	hm.map_width = HarborLayout.NX
	hm.map_depth = HarborLayout.NZ
	hm.map_data = _field
	cs.shape = hm
	cs.position = Vector3(HarborLayout.BOUNDS.get_center().x, 0.0, HarborLayout.BOUNDS.get_center().y)
	ground.add_child(cs)
	var tb := StaticBody3D.new()                     # 城（7.2）：房子、钥楼、会馆、债牢、灯塔、盐仓、栈桥、桥、闸墩、栏石、零碎
	tb.name = "HarborSolids"
	tb.collision_layer = 1
	tb.collision_mask = 0
	parent.add_child(tb)
	for so: Array in HarborTown.solids():
		var scs := CollisionShape3D.new()
		var sbs := BoxShape3D.new()
		sbs.size = so[1]
		scs.shape = sbs
		scs.transform = so[0]
		tb.add_child(scs)
	# 四边原来的空气墙去掉了：地图外面是边走边生成的荒野（2026-11-08，WildStreamer，见 _wild）；深水边照样有墙（_deep_walls、荒野里 WildStreamer.deep_y）


## 深水边一圈看不见的墙（层 5「边界」）：每 2 米一格，比 DEEP_Y 低的格子和不低的格子之间立一面竖的（一个凹多边形碰撞体，两面都挡）。
## 墙顶在 DEEP_WALL_TOP：码头、盐沼上走的人从上面过；走下泥滩、浅水的人走到深水边就停住
func _deep_walls() -> void:
	var faces := deep_wall_faces()
	var body := StaticBody3D.new()
	body.name = "HarborDeepWalls"
	body.collision_layer = FpController.LAYER_BOUNDARY
	body.collision_mask = 0
	parent.add_child(body)
	var cs := CollisionShape3D.new()
	var sh := ConcavePolygonShape3D.new()
	sh.backface_collision = true
	sh.set_faces(faces)
	cs.shape = sh
	body.add_child(cs)


static func deep_cell(i: int, j: int) -> bool:
	return _h(i, j) < HarborLayout.DEEP_Y


static func deep_wall_faces() -> PackedVector3Array:
	ensure_field()
	var faces := PackedVector3Array()
	var s := 2
	var bx := HarborLayout.BOUNDS.position.x
	var bz := HarborLayout.BOUNDS.position.y
	var lo := HarborLayout.SEA_Y - 3.0
	var hi := DEEP_WALL_TOP
	var j := 0
	while j < HarborLayout.NZ - s:
		var i := 0
		while i < HarborLayout.NX - s:
			var here := deep_cell(i, j)
			for d in [[s, 0], [0, s]]:
				var i2: int = i + int(d[0])
				var j2: int = j + int(d[1])
				if i2 >= HarborLayout.NX or j2 >= HarborLayout.NZ or deep_cell(i2, j2) == here:
					continue
				var a: Vector2
				var b: Vector2
				if int(d[0]) != 0:                       # 东边那格不一样：墙立在两格中间、南北走向
					var x := bx + (i + s * 0.5) * HarborLayout.STEP
					a = Vector2(x, bz + (j - s * 0.5) * HarborLayout.STEP)
					b = Vector2(x, bz + (j + s * 0.5) * HarborLayout.STEP)
				else:
					var z := bz + (j + s * 0.5) * HarborLayout.STEP
					a = Vector2(bx + (i - s * 0.5) * HarborLayout.STEP, z)
					b = Vector2(bx + (i + s * 0.5) * HarborLayout.STEP, z)
				var a0 := Vector3(a.x, lo, a.y)
				var b0 := Vector3(b.x, lo, b.y)
				var a1 := Vector3(a.x, hi, a.y)
				var b1 := Vector3(b.x, hi, b.y)
				faces.append_array(PackedVector3Array([a0, b0, a1, b0, b1, a1]))
			i += s
		j += s
	return faces


# ---------------- 材质 ----------------

static func ground_material() -> ShaderMaterial:
	if _mat != null:
		return _mat
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/harbor_ground.gdshader")
	_mat.set_shader_parameter("macro_noise", Look.noise_texture())
	_mat.set_shader_parameter("tide", tide())
	var fallback := {"ground": Color("8f8a84"), "paved": Color("6e6a66"), "mud": Color("4c4238"), "sand": Color("a8997e"), "shingle": Color("7a7268")}
	for k in LAYERS:
		var id: String = LAYERS[k]
		var alb: Texture2D = _tex(TEX_DIR % [id, "diff"])
		var nrm: Texture2D = _tex(TEX_DIR % [id, "nor_gl"])
		_mat.set_shader_parameter(k + "_alb", alb if alb != null else _flat(fallback[k]))
		_mat.set_shader_parameter(k + "_nrm", nrm if nrm != null else _flat(Color(0.5, 0.5, 1.0)))
	return _mat


## 河口的水：灰绿、浑，海那边有涌；靠岸浅处颜色淡、泡沫一道（顶点的 UV2.x = 底下的地多高，着色器按潮位算水深）
static func water_material() -> ShaderMaterial:
	if _water_mat != null:
		return _water_mat
	_water_mat = ShaderMaterial.new()
	_water_mat.shader = load("res://shaders/harbor_water.gdshader")
	_water_mat.set_shader_parameter("noise_tex", Look.noise_texture())
	_water_mat.set_shader_parameter("tide", tide())
	return _water_mat


static func clear_cache() -> void:
	HarborTown.clear_cache()
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
		_sky_mat.set_shader_parameter("pano", t if t != null else _flat(Color("a4a8ad")))
		_sky_mat.set_shader_parameter("horizon_fade", 0.12)
	return _sky_mat


## 时段：背景换成天空照片（按时段染色），雾不盖天空；潮位跟着时段
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
	env.tonemap_exposure = 0.76                   # 城里一片雪：曝光压低一点（0.85 时西北角往下看整座城是一张白纸，截图）


# ---------------- 水面 ----------------

## 一整片水（河、潮沟、泥滩、海）：每 2 米一格的网格，只留底下的地可能被水盖住的格子（比最高的潮位高一截的台地不要）；
## UV2.x = 这一点的地面高度（着色器里水深 = 潮位 - 地面）。整片跟着潮位上下挪（set_tide）
func _water() -> void:
	var b := HarborLayout.BOUNDS
	var nx := int(b.size.x / WATER_STEP) + 1
	var nz := int(b.size.y / WATER_STEP) + 1
	var top := float(TIDE.day) + 0.6
	var verts := PackedVector3Array()
	var uv2 := PackedVector2Array()
	verts.resize(nx * nz)
	uv2.resize(nx * nz)
	for j in nz:
		for i in nx:
			var x := b.position.x + i * WATER_STEP
			var z := b.position.y + j * WATER_STEP
			verts[j * nx + i] = Vector3(x, 0.0, z)
			uv2[j * nx + i] = Vector2(height_at(x, z), 0.0)
	var idx := PackedInt32Array()
	for j in nz - 1:
		for i in nx - 1:
			var a := j * nx + i
			if minf(minf(uv2[a].x, uv2[a + 1].x), minf(uv2[a + nx].x, uv2[a + nx + 1].x)) > top:
				continue
			idx.append_array(PackedInt32Array([a, a + 1, a + nx, a + 1, a + nx + 1, a + nx]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	var norms := PackedVector3Array()
	norms.resize(verts.size())
	norms.fill(Vector3.UP)
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV2] = uv2
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.name = "HarborWater"
	mi.mesh = m
	mi.material_override = water_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	# 地图外面的海：一圈大的平面（底下当作很深），被岸上的远景盖住的地方看不见
	var lines := _far_lines()
	var n := lines.size()
	var fv := PackedVector3Array()
	var fuv := PackedVector2Array()
	for jj in n:
		for ii in n:
			fv.append(Vector3(lines[ii], 0.0, lines[jj]))
			fuv.append(Vector2(-12.0, 1.0))
	var fidx := PackedInt32Array()
	var inner := b.grow(-1.0)
	for jj in n - 1:
		for ii in n - 1:
			var cell := Rect2(lines[ii], lines[jj], lines[ii + 1] - lines[ii], lines[jj + 1] - lines[jj])
			if inner.encloses(cell):
				continue
			var a := jj * n + ii
			fidx.append_array(PackedInt32Array([a, a + 1, a + n, a + 1, a + n + 1, a + n]))
	var farr := []
	farr.resize(Mesh.ARRAY_MAX)
	farr[Mesh.ARRAY_VERTEX] = fv
	var fn := PackedVector3Array()
	fn.resize(fv.size())
	fn.fill(Vector3.UP)
	farr[Mesh.ARRAY_NORMAL] = fn
	farr[Mesh.ARRAY_TEX_UV2] = fuv
	farr[Mesh.ARRAY_INDEX] = fidx
	var fm := ArrayMesh.new()
	fm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, farr)
	var fmi := MeshInstance3D.new()
	fmi.name = "FarSea"
	fmi.mesh = fm
	fmi.material_override = water_material()
	fmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fmi.extra_cull_margin = 50.0
	parent.add_child(fmi)


# ---------------- 画面 ----------------

func _jobs(st: ChunkStreamer) -> void:
	var b := HarborLayout.BOUNDS
	var cs := HarborLayout.CHUNK
	var cx := 0
	var x := b.position.x
	while x < b.end.x - 0.01:
		var cz := 0
		var z := b.position.y
		while z < b.end.y - 0.01:
			var r := Rect2(x, z, minf(cs, b.end.x - x), minf(cs, b.end.y - z))
			var jobs: Array = [_job_terrain.bind(r)]
			for j: Callable in HarborTown.jobs_for(r):            # 城（7.2）：一块里的房子合成一个网格、钥楼、会馆、债牢、灯塔、码头和水边、零碎
				jobs.append(Plain._with_lod.bind(j))               # 远处换单色网格、门板远了不画（同平原，6.7a）
			st.add_chunk("%d_%d" % [cx, cz], r, jobs)
			z += cs
			cz += 1
		x += cs
		cx += 1


func _job_terrain(root: Node3D, r: Rect2) -> void:
	var i0 := int(round((r.position.x - HarborLayout.BOUNDS.position.x) / HarborLayout.STEP))
	var j0 := int(round((r.position.y - HarborLayout.BOUNDS.position.y) / HarborLayout.STEP))
	var i1 := i0 + int(round(r.size.x / HarborLayout.STEP))
	var j1 := j0 + int(round(r.size.y / HarborLayout.STEP))
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
	var bx := HarborLayout.BOUNDS.position.x
	var bz := HarborLayout.BOUNDS.position.y
	var cx := bx + (i0 + i1) * 0.5 * HarborLayout.STEP
	var cz := bz + (j0 + j1) * 0.5 * HarborLayout.STEP
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
	var nx := HarborLayout.NX
	for rj in nr:
		var jj := rows[rj]
		for ci in nc:
			var ii := cols[ci]
			var k := rj * nc + ci
			verts[k] = Vector3(bx + ii * HarborLayout.STEP - cx, _field[jj * nx + ii], bz + jj * HarborLayout.STEP - cz)
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
				ck.a = 0.0
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


## 远景：地图外面一圈（越往外越稀）。南边、东南一直是海底（被海面盖住），北边、西边是低低的岸、慢慢起伏，河往北接着流
func _far(center := Vector2.ZERO) -> void:
	var old_far := parent.get_node_or_null("FarTerrain")
	if old_far:
		old_far.name = "FarTerrainOld"
		old_far.queue_free()
	var lines := _far_lines()                         # 以 center 为中心（走远了 WildStreamer 让它跟过去）
	var b := HarborLayout.BOUNDS
	var n := lines.size()
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var colors := PackedColorArray()
	verts.resize(n * n)
	norms.resize(n * n)
	colors.resize(n * n)
	for j in n:
		for i in n:
			var x: float = float(lines[i]) + center.x
			var z: float = float(lines[j]) + center.y
			var y := far_height(x, z)
			verts[j * n + i] = Vector3(x, y, z)
			colors[j * n + i] = Color(0.0, 0.25 if y < 0.5 else 0.0, 1.0)
	for j in n:
		for i in n:
			var dx := verts[j * n + mini(i + 1, n - 1)] - verts[j * n + maxi(i - 1, 0)]
			var dz := verts[mini(j + 1, n - 1) * n + i] - verts[maxi(j - 1, 0) * n + i]
			norms[j * n + i] = dz.cross(dx).normalized()
	var idx := PackedInt32Array()
	var inner := b.grow(-2.0)
	for j in n - 1:
		for i in n - 1:
			var cell := Rect2(float(lines[i]) + center.x, float(lines[j]) + center.y, lines[i + 1] - lines[i], lines[j + 1] - lines[j])
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


## 无尽荒野（2026-11-08 所有者「玩家可自由无尽探索」）：地图外面边走边生成（WildStreamer）。高度用远景那套 far_height（北边、西边低岸和缓坡，往南是海）往上抬回 0.3 米；
## 南边的海、河照样走不进去：荒野里比 DEEP_Y 低的地方边上同样立墙（WildStreamer.deep_y）。不撒东西：海边盐沼、泥滩，空旷
const WILD_RADIUS := 2


static func wild_height(x: float, z: float) -> float:
	return far_height(x, z) + 0.3


static func ground_at(x: float, z: float) -> float:
	return height_at(x, z) if HarborLayout.BOUNDS.has_point(Vector2(x, z)) else wild_height(x, z)


func _wild() -> void:
	var w := WildStreamer.make(HarborLayout.BOUNDS, Harbor.wild_height, ground_material(), WILD_RADIUS)
	w.surface = "mud"
	w.ground_fn = Harbor.ground_at
	w.region = "harbor"                                   # 荒野里的小发现（WildFinds）
	w.area_id = "harbor"
	w.deep_y = HarborLayout.DEEP_Y
	w.deep_wall_top = DEEP_WALL_TOP
	w.color_fn = func(x: float, z: float, _slope: float) -> Color: return Color(0.0, 0.25 if wild_height(x, z) < 0.5 else 0.0, 1.0)
	w.far_fn = func(c: Vector2) -> void: _far(c)
	parent.add_child(w)


static func _far_lines() -> Array:
	var out := []
	var x := -FAR_EXTENT
	while x < FAR_EXTENT:
		out.append(x)
		var ax := absf(x)
		x += 16.0 if ax < 360.0 else (40.0 if ax < 800.0 else 100.0)
	out.append(FAR_EXTENT)
	return out


## 远景的高度：地图里面和地形一致（往下压一点）；外面——往南（SEA_DIR）是海底，北边、西边是低岸和缓坡，河往北接着流
static func far_height(x: float, z: float) -> float:
	var b := HarborLayout.BOUNDS
	var dx := maxf(maxf(b.position.x - x, x - b.end.x), 0.0)
	var dz := maxf(maxf(b.position.y - z, z - b.end.y), 0.0)
	var out := sqrt(dx * dx + dz * dz)
	if out <= 0.0:
		return HarborLayout.height(x, z) - 0.3
	var p := Vector2(x, z)
	var edge := Vector2(clampf(x, b.position.x, b.end.x), clampf(z, b.position.y, b.end.y))
	var y0 := HarborLayout.height(edge.x, edge.y)
	var land := 2.0 + 5.0 * sin(x / 150.0 + 0.4) * sin(z / 190.0) + 2.5 * sin(x / 57.0) * sin(z / 43.0 + 1.0)
	land += clampf(-(z + 110.0) / 600.0, 0.0, 1.0) * 18.0 + clampf(-(x + 130.0) / 700.0, 0.0, 1.0) * 14.0   # 北边、西边远处慢慢抬成低丘
	var sea_k := PlainLayout._smooth(clampf((p.dot(HarborLayout.SEA_DIR.normalized()) - 70.0) / 90.0, 0.0, 1.0))   # 南边、东南边是海
	var target := lerpf(land, -10.0, sea_k)
	if z < b.position.y:                                                    # 河往北接着流（地图外刻一道）
		var rx := (HarborLayout.RIVER[0] as Vector2).x + (z - b.position.y) * 0.08
		var rd := absf(x - rx) - HarborLayout.RIVER_HALF_N
		if rd < 10.0:
			target = lerpf(target, HarborLayout.RIVER_BED, 1.0 - PlainLayout._smooth(clampf(rd / 10.0, 0.0, 1.0)))
	return lerpf(y0 - 0.3, target, PlainLayout._smooth(clampf(out / 50.0, 0.0, 1.0)))


## 地图册（3.11）「本地」页：河、潮沟、泥滩、街、几处地点（7.2 起换成真的房子）
static func map_spec() -> Dictionary:
	var shapes := []
	for i in HarborLayout.RIVER.size() - 1:
		var a: Vector2 = HarborLayout.RIVER[i]
		var c: Vector2 = HarborLayout.RIVER[i + 1]
		var sh := {"k": "water", "pts": _strip(a, c, HarborLayout.river_half((a.y + c.y) * 0.5))}
		if i == 2:
			sh["label"] = "灰鲸河"
		shapes.append(sh)
	for cn in HarborLayout.CANALS:
		for i in cn.size() - 1:
			shapes.append({"k": "water", "pts": _strip(cn[i], cn[i + 1], HarborLayout.CANAL_HALF)})
	var sea := PackedVector2Array()
	var x := HarborLayout.BOUNDS.position.x
	while x <= HarborLayout.BOUNDS.end.x:
		sea.append(Vector2(x, HarborLayout.flats_end_z(x)))
		x += 10.0
	sea.append(HarborLayout.BOUNDS.end)
	sea.append(Vector2(HarborLayout.BOUNDS.position.x, HarborLayout.BOUNDS.end.y))
	shapes.append({"k": "water", "pts": sea, "label": "海"})
	for r in HarborLayout.STREETS:
		for i in r.size() - 1:
			shapes.append({"k": "road", "pts": _strip(r[i], r[i + 1], HarborLayout.STREET_HALF)})
	shapes.append_array(HarborTown.map_shapes())                   # 房子、钥楼、会馆、债牢、盐仓、栈桥（7.2）
	for m in [[HarborLayout.QUAY, "木栈码头"], [HarborLayout.FISH, "鱼市"], [HarborLayout.LIGHTHOUSE, "灯塔"], [Vector2(-20.0, 66.0), "泥滩"], [HarborTown.WRECK[0], "搁浅的粮船"]]:
		shapes.append({"k": "mark", "at": m[0], "label": m[1]})
	return {"bounds": HarborLayout.BOUNDS, "shapes": shapes, "exits": [], "zones": [
		{"name": "钥楼街", "pts": _rect(Rect2(-100, -74, 120, 22))},
		{"name": "鱼市", "pts": _rect(Rect2(-70, 24, 80, 26))},
		{"name": "沙嘴", "pts": _rect(Rect2(56, 0, 60, 110))},
		{"name": "双钥港", "pts": _rect(HarborLayout.BOUNDS)},
	]}


static func _strip(a: Vector2, b: Vector2, half: float) -> PackedVector2Array:
	var side := (b - a).normalized().orthogonal() * half
	return PackedVector2Array([a + side, b + side, b - side, a - side])


static func _rect(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
