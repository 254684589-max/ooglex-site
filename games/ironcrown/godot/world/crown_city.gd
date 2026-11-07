class_name CrownCity
extends RefCounted
## 冠城一角（路线图 7.6，D10-B、D12；STORY.md 7.2、7.5 第 6 步；布局在 world/crown_layout.gd）。照双钥港（world/harbor.gd）的做法，大半段代码一样：
## 同步搭高度场、高度图碰撞、深水边一圈看不见的墙、一整片按水深着色的河面、地图外的远景（东边是岛上越来越高的城和王宫的影子，西边、北边、南边是河岸）；
## 画面每 64 米一块分帧搭（地形 + 城：CrownTown）。冠城在中游，河面不跟潮走（RIVER_Y）。地面、水用双钥港那两个着色器和第四章章节包里的贴图。

const TEX_DIR := "res://chapters/ch4/tex/%s_%s_1k.jpg"
const SKY_PATH := "res://chapters/ch4/sky/sea_cloud_sky.jpg"
const FIELD_PATH := "res://chapters/ch4/crown_field.res"
const PAINT_PATH := "res://chapters/ch4/crown_paint.res"
const LO_STEP := 2
const LOD_DIST := 80.0
const SKIRT := 1.2
const FAR_EXTENT := 1600.0
const LAYERS := Harbor.LAYERS
const WATER_STEP := 2.0
const DEEP_WALL_TOP := 1.0
const SKY := Harbor.SKY

static var _field := PackedFloat32Array()
static var _paint := PackedColorArray()
static var _mat: ShaderMaterial
static var _water_mat: ShaderMaterial
static var _sky_mat: ShaderMaterial
static var field_ms := 0.0

var parent: Node3D
var reduced_motion := false


static func build(p_parent: Node3D, reduced_motion := false) -> Transform3D:
	var t0 := Time.get_ticks_usec()
	var cc := CrownCity.new()
	cc.parent = p_parent
	cc.reduced_motion = reduced_motion
	var s: Array = spawn_points().bridge
	if not textures_ready():
		cc._placeholder()
		print("IC_CROWN placeholder (章节包没到)")
		return Transform3D(Basis(Vector3.UP, deg_to_rad(float(s[1]))), s[0])
	ensure_field()
	for k in ["roof", "plaster", "castle", "stone", "timber", "snow"]:
		Look.mat(k)
	HarborTown.mats()
	cc._collision()
	cc._deep_walls()
	ground_material()
	water_material()
	cc._water()
	cc._far()
	CrownTown.palace(p_parent)                       # 岛东头越来越高的城、王宫的影子（地图外）
	CrownTown.interactables(p_parent)               # 桥门的路牌、玛蒂尔达的小酒馆和议事厅的门、面包坊（7.6）
	CrownPeople.build(p_parent)                      # 斜街上的人、排队买面包的、桥上的行会船工；冠在你手里时斜街上三个蒙面的人
	for n in p_parent.get_children():
		if n is Door or n is RoadSign:
			Plain._cut_far(n, Plain.DETAIL_FAR)
	var st := ChunkStreamer.new()
	st.name = "Streamer"
	st.host = p_parent
	st.builder = cc
	p_parent.add_child(st)
	cc._jobs(st)
	print("IC_CROWN sync ms=%.0f field_ms=%.0f chunks=%d tex=%s" % [float(Time.get_ticks_usec() - t0) / 1000.0, field_ms, st.chunks.size(), textures_ready()])
	return Transform3D(Basis(Vector3.UP, deg_to_rad(float(s[1]))), s[0])


static func spawn_points() -> Dictionary:
	return CrownLayout.spawn_points()


static func views() -> Array:
	return CrownLayout.views()


static func textures_ready() -> bool:
	return ResourceLoader.exists(SKY_PATH)


## 河面（冠城在中游，没有潮）：water 着色器的 tide 就是河面
static func tide() -> float:
	return CrownLayout.RIVER_Y


static func clear_cache() -> void:
	CrownTown.clear_cache()
	_mat = null
	_water_mat = null
	_sky_mat = null


## 石桥桥面的高度（x 处）：两头接河西岸和桥门，当中拱起一点
static func bridge_y(x: float) -> float:
	var a: Vector2 = CrownLayout.BRIDGE[0]
	var b: Vector2 = CrownLayout.BRIDGE[1]
	var t := clampf((x - a.x) / (b.x - a.x), 0.0, 1.0)
	var ya := CrownLayout.height(a.x - 2.0, a.y)
	var yb := CrownLayout.height(b.x + 2.0, b.y)
	return lerpf(ya, yb, t) + 0.9 * sin(PI * t) + 0.05


static func ensure_field() -> void:
	if _field.size() == CrownLayout.NX * CrownLayout.NZ:
		return
	var t0 := Time.get_ticks_usec()
	if ResourceLoader.exists(FIELD_PATH) and ResourceLoader.exists(PAINT_PATH):
		var fi := load(FIELD_PATH) as Image
		var pi := load(PAINT_PATH) as Image
		if fi != null and pi != null and fi.get_width() == CrownLayout.NX and fi.get_height() == CrownLayout.NZ:
			_field = fi.get_data().to_float32_array()
			var bytes := pi.get_data()
			_paint.resize(CrownLayout.NX * CrownLayout.NZ)
			for k in _paint.size():
				_paint[k] = Color8(bytes[k * 3], bytes[k * 3 + 1], bytes[k * 3 + 2])
			field_ms = float(Time.get_ticks_usec() - t0) / 1000.0
			return
	compute_field()
	field_ms = float(Time.get_ticks_usec() - t0) / 1000.0


static func compute_field() -> void:
	var nx := CrownLayout.NX
	var nz := CrownLayout.NZ
	var x0 := CrownLayout.BOUNDS.position.x
	var z0 := CrownLayout.BOUNDS.position.y
	_field.resize(nx * nz)
	_paint.resize(nx * nz)
	for j in nz:
		var z := z0 + j * CrownLayout.STEP
		for i in nx:
			var x := x0 + i * CrownLayout.STEP
			_field[j * nx + i] = CrownLayout.height(x, z)
			var m := CrownLayout.masks(x, z)
			_paint[j * nx + i] = Color(m.x, m.y, m.z)


static func save_field() -> void:
	var fi := Image.create_from_data(CrownLayout.NX, CrownLayout.NZ, false, Image.FORMAT_RF, _field.to_byte_array())
	var bytes := PackedByteArray()
	bytes.resize(_paint.size() * 3)
	for k in _paint.size():
		var c := _paint[k]
		bytes[k * 3] = c.r8
		bytes[k * 3 + 1] = c.g8
		bytes[k * 3 + 2] = c.b8
	var pi := Image.create_from_data(CrownLayout.NX, CrownLayout.NZ, false, Image.FORMAT_RGB8, bytes)
	ResourceSaver.save(fi, FIELD_PATH, ResourceSaver.FLAG_COMPRESS)
	ResourceSaver.save(pi, PAINT_PATH, ResourceSaver.FLAG_COMPRESS)


static func height_at(x: float, z: float) -> float:
	ensure_field()
	var fx := (x - CrownLayout.BOUNDS.position.x) / CrownLayout.STEP
	var fz := (z - CrownLayout.BOUNDS.position.y) / CrownLayout.STEP
	if fx < 0.0 or fz < 0.0 or fx > CrownLayout.NX - 1 or fz > CrownLayout.NZ - 1:
		return CrownLayout.height(x, z)
	var i := mini(int(fx), CrownLayout.NX - 2)
	var j := mini(int(fz), CrownLayout.NZ - 2)
	var tx := fx - i
	var tz := fz - j
	var n := CrownLayout.NX
	var a := lerpf(_field[j * n + i], _field[j * n + i + 1], tx)
	var b := lerpf(_field[(j + 1) * n + i], _field[(j + 1) * n + i + 1], tx)
	return lerpf(a, b, tz)


static func _h(i: int, j: int) -> float:
	return _field[clampi(j, 0, CrownLayout.NZ - 1) * CrownLayout.NX + clampi(i, 0, CrownLayout.NX - 1)]


static func _normal(i: int, j: int, step: int) -> Vector3:
	var dx := (_h(i + step, j) - _h(i - step, j)) / (2.0 * step)
	var dz := (_h(i, j + step) - _h(i, j - step)) / (2.0 * step)
	return Vector3(-dx, 1.0, -dz).normalized()


func _placeholder() -> void:
	var b := StaticBody3D.new()
	b.name = "CrownPlaceholder"
	parent.add_child(b)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(400, 1, 400)
	cs.shape = bs
	var s: Array = spawn_points().bridge
	cs.position = (s[0] as Vector3) - Vector3(0, 0.5, 0)
	b.add_child(cs)


func _collision() -> void:
	var ground := StaticBody3D.new()
	ground.name = "CrownGround"
	ground.collision_layer = 1
	ground.collision_mask = 0
	ground.set_meta("surface", "")
	ground.set_meta("surface_at", CrownLayout.surface_at)        # 泥滩、浅水按位置和潮位查
	parent.add_child(ground)
	var cs := CollisionShape3D.new()
	var hm := HeightMapShape3D.new()
	hm.map_width = CrownLayout.NX
	hm.map_depth = CrownLayout.NZ
	hm.map_data = _field
	cs.shape = hm
	cs.position = Vector3(CrownLayout.BOUNDS.get_center().x, 0.0, CrownLayout.BOUNDS.get_center().y)
	ground.add_child(cs)
	var tb := StaticBody3D.new()                     # 城（7.2）：房子、钥楼、会馆、债牢、灯塔、盐仓、栈桥、桥、闸墩、栏石、零碎
	tb.name = "CrownSolids"
	tb.collision_layer = 1
	tb.collision_mask = 0
	parent.add_child(tb)
	for so: Array in CrownTown.solids():
		var scs := CollisionShape3D.new()
		var sbs := BoxShape3D.new()
		sbs.size = so[1]
		scs.shape = sbs
		scs.transform = so[0]
		tb.add_child(scs)
	var wb := StaticBody3D.new()
	wb.name = "CrownWalls"
	wb.collision_layer = FpController.LAYER_BOUNDARY
	wb.collision_mask = 0
	parent.add_child(wb)
	var r := CrownLayout.BOUNDS.grow(-CrownLayout.WALL_INSET)
	var hh := CrownLayout.WALL_H
	var c := r.get_center()
	for w in [[Vector3(c.x, hh * 0.5, r.position.y), Vector3(r.size.x, hh * 2.0, 1.0)], [Vector3(c.x, hh * 0.5, r.end.y), Vector3(r.size.x, hh * 2.0, 1.0)],
			[Vector3(r.position.x, hh * 0.5, c.y), Vector3(1.0, hh * 2.0, r.size.y)], [Vector3(r.end.x, hh * 0.5, c.y), Vector3(1.0, hh * 2.0, r.size.y)]]:
		var ws := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = w[1]
		ws.shape = bs
		ws.position = w[0]
		wb.add_child(ws)


## 深水边一圈看不见的墙（层 5「边界」）：每 2 米一格，比 DEEP_Y 低的格子和不低的格子之间立一面竖的（一个凹多边形碰撞体，两面都挡）。
## 墙顶在 DEEP_WALL_TOP：码头、盐沼上走的人从上面过；走下泥滩、浅水的人走到深水边就停住


func _deep_walls() -> void:
	var faces := deep_wall_faces()
	var body := StaticBody3D.new()
	body.name = "CrownDeepWalls"
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
	return _h(i, j) < CrownLayout.DEEP_Y


static func deep_wall_faces() -> PackedVector3Array:
	ensure_field()
	var faces := PackedVector3Array()
	var s := 2
	var bx := CrownLayout.BOUNDS.position.x
	var bz := CrownLayout.BOUNDS.position.y
	var lo := CrownLayout.RIVER_BED - 3.0
	var hi := DEEP_WALL_TOP
	var j := 0
	while j < CrownLayout.NZ - s:
		var i := 0
		while i < CrownLayout.NX - s:
			var here := deep_cell(i, j)
			for d in [[s, 0], [0, s]]:
				var i2: int = i + int(d[0])
				var j2: int = j + int(d[1])
				if i2 >= CrownLayout.NX or j2 >= CrownLayout.NZ or deep_cell(i2, j2) == here:
					continue
				var a: Vector2
				var b: Vector2
				if int(d[0]) != 0:                       # 东边那格不一样：墙立在两格中间、南北走向
					var x := bx + (i + s * 0.5) * CrownLayout.STEP
					a = Vector2(x, bz + (j - s * 0.5) * CrownLayout.STEP)
					b = Vector2(x, bz + (j + s * 0.5) * CrownLayout.STEP)
				else:
					var z := bz + (j + s * 0.5) * CrownLayout.STEP
					a = Vector2(bx + (i - s * 0.5) * CrownLayout.STEP, z)
					b = Vector2(bx + (i + s * 0.5) * CrownLayout.STEP, z)
				var a0 := Vector3(a.x, lo, a.y)
				var b0 := Vector3(b.x, lo, b.y)
				var a1 := Vector3(a.x, hi, a.y)
				var b1 := Vector3(b.x, hi, b.y)
				faces.append_array(PackedVector3Array([a0, b0, a1, b0, b1, a1]))
			i += s
		j += s
	return faces


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


func _water() -> void:
	var b := CrownLayout.BOUNDS
	var nx := int(b.size.x / WATER_STEP) + 1
	var nz := int(b.size.y / WATER_STEP) + 1
	var top := CrownLayout.RIVER_Y + 0.6
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
	mi.name = "CrownWater"
	mi.position.y = tide()
	mi.mesh = m
	mi.material_override = water_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	# 地图外面的河：一圈大的平面（底下当作很深），被岸上的远景盖住的地方看不见
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
	fmi.name = "FarRiver"
	fmi.position.y = tide()
	fmi.mesh = fm
	fmi.material_override = water_material()
	fmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fmi.extra_cull_margin = 50.0
	parent.add_child(fmi)


func _jobs(st: ChunkStreamer) -> void:
	var b := CrownLayout.BOUNDS
	var cs := CrownLayout.CHUNK
	var cx := 0
	var x := b.position.x
	while x < b.end.x - 0.01:
		var cz := 0
		var z := b.position.y
		while z < b.end.y - 0.01:
			var r := Rect2(x, z, minf(cs, b.end.x - x), minf(cs, b.end.y - z))
			var jobs: Array = [_job_terrain.bind(r)]
			for j: Callable in CrownTown.jobs_for(r):            # 城（7.2）：一块里的房子合成一个网格、钥楼、会馆、债牢、灯塔、码头和水边、零碎
				jobs.append(Plain._with_lod.bind(j))               # 远处换单色网格、门板远了不画（同平原，6.7a）
			st.add_chunk("%d_%d" % [cx, cz], r, jobs)
			z += cs
			cz += 1
		x += cs
		cx += 1


func _job_terrain(root: Node3D, r: Rect2) -> void:
	var i0 := int(round((r.position.x - CrownLayout.BOUNDS.position.x) / CrownLayout.STEP))
	var j0 := int(round((r.position.y - CrownLayout.BOUNDS.position.y) / CrownLayout.STEP))
	var i1 := i0 + int(round(r.size.x / CrownLayout.STEP))
	var j1 := j0 + int(round(r.size.y / CrownLayout.STEP))
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
	var bx := CrownLayout.BOUNDS.position.x
	var bz := CrownLayout.BOUNDS.position.y
	var cx := bx + (i0 + i1) * 0.5 * CrownLayout.STEP
	var cz := bz + (j0 + j1) * 0.5 * CrownLayout.STEP
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
	var nx := CrownLayout.NX
	for rj in nr:
		var jj := rows[rj]
		for ci in nc:
			var ii := cols[ci]
			var k := rj * nc + ci
			verts[k] = Vector3(bx + ii * CrownLayout.STEP - cx, _field[jj * nx + ii], bz + jj * CrownLayout.STEP - cz)
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


## 远景：地图外面一圈（越往外越稀）。东边是岛上越来越高的城，西边、北边、南边是河岸和低丘
func _far() -> void:
	var lines := _far_lines()
	var b := CrownLayout.BOUNDS
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


static func _strip(a: Vector2, b: Vector2, half: float) -> PackedVector2Array:
	var side := (b - a).normalized().orthogonal() * half
	return PackedVector2Array([a + side, b + side, b - side, a - side])


static func _rect(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


## 远景的高度：地图里面和地形一致（往下压一点）；外面——东边岛上越往东越高（王宫在高处），西边、北边、南边是河岸和低丘，河接着绕过去
static func far_height(x: float, z: float) -> float:
	var b := CrownLayout.BOUNDS
	var dx := maxf(maxf(b.position.x - x, x - b.end.x), 0.0)
	var dz := maxf(maxf(b.position.y - z, z - b.end.y), 0.0)
	var out := sqrt(dx * dx + dz * dz)
	if out <= 0.0:
		return CrownLayout.height(x, z) - 0.3
	var edge := Vector2(clampf(x, b.position.x, b.end.x), clampf(z, b.position.y, b.end.y))
	var y0 := CrownLayout.height(edge.x, edge.y)
	var target: float
	if x > b.end.x and absf(z) < CrownLayout.ISLAND_HALF_Z + 10.0:            # 岛往东接着高上去（王宫那块高地）
		target = CrownLayout.SQUARE_Y + 2.0 + clampf((x - b.end.x) / 160.0, 0.0, 1.0) * 12.0
	elif absf(z) > CrownLayout.ISLAND_HALF_Z + 4.0 and absf(z) < CrownLayout.FAR_BANK_Z + 2.0 and x > b.position.x:
		target = CrownLayout.RIVER_BED                                           # 南北两股河接着往东流
	else:
		target = CrownLayout.BANK_Y + 3.0 * sin(x / 140.0 + 0.4) * sin(z / 170.0) + clampf((out - 120.0) / 600.0, 0.0, 1.0) * 16.0
	return lerpf(y0 - 0.3, target, PlainLayout._smooth(clampf(out / 40.0, 0.0, 1.0)))


static func map_spec() -> Dictionary:
	var shapes := []
	var water := PackedVector2Array([Vector2(CrownLayout.WEST_BANK_X, -80), Vector2(CrownLayout.ISLAND_W, -80), Vector2(CrownLayout.ISLAND_W, 80), Vector2(CrownLayout.WEST_BANK_X, 80)])
	shapes.append({"k": "water", "pts": water, "label": "灰鲸河"})
	shapes.append({"k": "water", "pts": _rect(Rect2(CrownLayout.ISLAND_W, -CrownLayout.FAR_BANK_Z, 134, CrownLayout.FAR_BANK_Z - CrownLayout.ISLAND_HALF_Z))})
	shapes.append({"k": "water", "pts": _rect(Rect2(CrownLayout.ISLAND_W, CrownLayout.ISLAND_HALF_Z, 134, CrownLayout.FAR_BANK_Z - CrownLayout.ISLAND_HALF_Z))})
	shapes.append({"k": "road", "pts": _strip(CrownLayout.BRIDGE[0], CrownLayout.BRIDGE[1], CrownLayout.BRIDGE_HALF), "label": "石桥"})
	for i in CrownLayout.STREET.size() - 1:
		shapes.append({"k": "road", "pts": _strip(CrownLayout.STREET[i], CrownLayout.STREET[i + 1], CrownLayout.STREET_HALF)})
	for l in CrownLayout.LANES:
		for i in l.size() - 1:
			shapes.append({"k": "road", "pts": _strip(l[i], l[i + 1], CrownLayout.LANE_HALF)})
	shapes.append({"k": "road", "pts": _rect(CrownLayout.SQUARE), "label": "议事厅广场"})
	shapes.append_array(CrownTown.map_shapes())
	return {"bounds": CrownLayout.BOUNDS, "shapes": shapes, "exits": [], "zones": [
		{"name": "斜街", "pts": _rect(Rect2(-38, -14, 74, 26))},
		{"name": "议事厅广场", "pts": _rect(CrownLayout.SQUARE.grow(4.0))},
		{"name": "河西岸", "pts": _rect(Rect2(-90, -80, 28, 160))},
		{"name": "冠城", "pts": _rect(CrownLayout.BOUNDS)},
	]}
