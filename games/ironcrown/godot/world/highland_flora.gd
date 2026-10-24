class_name HighlandFlora
extends RefCounted
## 余火高地的树、石头、远处的森林和那串烽燧塔（路线图 5.1b，D12；ART.md 第十节「真树、真石头」「天空和远景」「光讲故事」）。
## Poly Haven 的冷杉、松树是照片扫描的整棵树（一棵 780 万面、几百兆），网页用不了；这里用代码搭：
##   树 = 一根锥形的树干（树皮贴图，主包里已有）+ 一层层轮生的枝条，每根枝条两片交叉的枝片（一片平、一片竖），贴的是拿 fir_tree_01 的小枝照片拼成的整根枝条
##   （chapters/ch2/trees/conifer_branches.png，两种：密的冷杉、稀一点的云杉）；枝片的法线从树干往外、往上（整棵树像一个圆锥那样受光），上面积雪（shaders/conifer.gdshader）。
##   每种树两份网格：近处全的、远处每两层取一层；按块用多实例（MultiMesh）画，每块每种树一次。
##   石头 = 变形的二十面体细分球，半埋在地里，用地形的着色器（陡的侧面是灰岩、朝上的顶上积雪）。
##   远处的森林（地图外面的山坡上）= 几千个小圆锥，一次画完，雾里看就是一片黑压压的针叶林。
##   烽燧塔 = 山脊线往东西两边延下去，每隔一百多米一座（STORY.md 5.2「北边山脊上一串烽燧塔，大半是黑的」）：近的几座在雾里看得见轮廓，亮着的三座塔顶有火，
##   火的光晕不受雾影响（远处隔着雾也看得见一点暖光——整张图上唯一的暖色，ART.md 第十节「光讲故事」）。
## 摆在哪：按固定种子撒点，再按规则筛（不上路、不进村、不上悬崖、树不过林线 34 米、山脊北边和冰原上没有树）。碰撞：树干一根圆柱、大石头一个球（Highland._collision）。

const TREE_KINDS := 2                     # 0 冷杉（高、窄、密），1 云杉（矮一点、宽一点、稀）
const TREE_STEP := 4.0                    # 撒树的格子（米）
const ROCK_STEP := 7.0
const TREELINE := 34.0                    # 林线（米）：再高没有树
const TREE_LOD := 55.0                    # 多远换成远处那份树（米，按块的包围盒中心）
const TREE_FAR := 260.0                   # 多远以外不画树（雾早就吞了）
const FAR_FOREST := 2600                  # 地图外面的小圆锥
const BEACON_SPACING := 150.0             # 远处烽燧塔的间距（米）
const LIT_BEACONS := [-610.0, 320.0, 780.0]   # 亮着的那几座（x 坐标，就近取）
const BRANCH_TEX := "res://chapters/ch2/trees/conifer_branches.png"

static var _tree_meshes := {}
static var _rock_meshes: Array = []
static var _branch_mat: ShaderMaterial
static var _cache := {}


static func clear_cache() -> void:
	_tree_meshes.clear()
	_rock_meshes.clear()
	_branch_mat = null
	_cache.clear()


## 载入时先备好：材质、几种树和石头的网格、摆放（分帧的活里只剩搭多实例）
static func warm(reduced_motion := false) -> void:
	branch_material(reduced_motion)
	Look.mat("bark")
	for k in TREE_KINDS:
		for lod in 2:
			tree_mesh(k, lod)
	for v in 4:
		rock_mesh(v)
	trees()
	rocks()


# ---------------- 摆在哪 ----------------

## 树：[位置, 朝向（弧度）, 高（米）, 种类, 深浅 0..1, 雪 0..1, 风的相位 0..1]
static func trees() -> Array:
	if _cache.has("trees"):
		return _cache.trees
	var out := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 5101
	var forest := FastNoiseLite.new()                # 林子一片一片的
	forest.seed = 77
	forest.frequency = 0.022
	forest.fractal_octaves = 3
	var b := HighlandLayout.BOUNDS.grow(-3.0)
	var x := b.position.x
	while x < b.end.x:
		var z := b.position.y
		while z < b.end.y:
			var p := Vector2(x + rng.randf_range(-1.7, 1.7), z + rng.randf_range(-1.7, 1.7))
			var roll := rng.randf()
			var dens := tree_density(p, forest)
			if roll < dens:
				var h := rng.randf_range(7.0, 15.0) * (1.0 - 0.35 * clampf((Highland.height_at(p.x, p.y) - 18.0) / 16.0, 0.0, 1.0))   # 越往林线越矮
				var kind := 0 if rng.randf() < 0.62 else 1
				out.append([Vector3(p.x, Highland.height_at(p.x, p.y) - 0.15, p.y), rng.randf() * TAU, h, kind, rng.randf(), rng.randf_range(0.35, 1.0), rng.randf()])
			z += TREE_STEP
		x += TREE_STEP
	_cache.trees = out
	return out


## 这一点长树的概率：林子的噪声斑块 × 高度（林线以下）× 坡度（悬崖上没有）× 离路、村子、烽燧多远
static func tree_density(p: Vector2, forest: FastNoiseLite) -> float:
	if p.y < HighlandLayout.crest_z(p.x) + 6.0:
		return 0.0                                 # 山脊上、山脊北边（冰原）没有树
	var y := Highland.height_at(p.x, p.y)
	if y > TREELINE:
		return 0.0
	if p.distance_to(HighlandLayout.VILLAGE) < HighlandLayout.VILLAGE_R + 8.0:
		return 0.0                                 # 村子里、村边（5.2 盖房子）
	for c in [HighlandLayout.BEACON19, HighlandLayout.BEACON18]:
		if p.distance_to(c) < HighlandLayout.PAD_R + 4.0:
			return 0.0
	if slope_at(p) > 0.3 or near_village_works(p, 2.5):
		return 0.0
	var r := HighlandLayout.road_hit(p)
	if r.d < HighlandLayout.ROAD_HALF + 3.5:
		return 0.0
	var f := clampf(forest.get_noise_2d(p.x, p.y) * 1.8 + 0.25, 0.0, 1.0)
	var line := 1.0 - HighlandLayout._smooth(clampf((y - (TREELINE - 12.0)) / 12.0, 0.0, 1.0))
	var edge := clampf((r.d - HighlandLayout.ROAD_HALF - 3.5) / 6.0, 0.3, 1.0)       # 路边稀一点
	return 0.62 * f * line * edge


## 离溪、田间石墙、石圈太近（树、石头都不摆：5.2a）
static func near_village_works(p: Vector2, margin: float) -> bool:
	if HighlandLayout.stream_d(p) < HighlandLayout.STREAM_HALF + HighlandLayout.STREAM_BANK * 0.5 + margin:
		return true
	if p.distance_to(HighlandLayout.STONE_RING) < HighlandLayout.STONE_RING_R + 2.0 + margin:
		return true
	for line in HighlandLayout.FIELD_WALLS:
		for i in line.size() - 1:
			if HighlandLayout._seg_d(p, line[i], line[i + 1]) < HighlandLayout.WALL_W + margin:
				return true
	return false


## 坡度（1 - 法线的 y）
static func slope_at(p: Vector2) -> float:
	var e := 1.0
	var dx := (Highland.height_at(p.x + e, p.y) - Highland.height_at(p.x - e, p.y)) / (2.0 * e)
	var dz := (Highland.height_at(p.x, p.y + e) - Highland.height_at(p.x, p.y - e)) / (2.0 * e)
	return 1.0 - Vector3(-dx, 1.0, -dz).normalized().y


## 石头：[位置, 朝向（弧度）, 大小（米，大约是直径）, 变体, 歪多少（弧度）]。坡上、岩坎和山脊附近多，冰原上零星几块
static func rocks() -> Array:
	if _cache.has("rocks"):
		return _cache.rocks
	var out := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 5102
	var b := HighlandLayout.BOUNDS.grow(-3.0)
	var x := b.position.x
	while x < b.end.x:
		var z := b.position.y
		while z < b.end.y:
			var p := Vector2(x + rng.randf_range(-3.0, 3.0), z + rng.randf_range(-3.0, 3.0))
			var roll := rng.randf()
			var s := slope_at(p)
			var r := HighlandLayout.road_hit(p)
			var ok: bool = r.d > HighlandLayout.ROAD_HALF + 1.5 and p.distance_to(HighlandLayout.VILLAGE) > HighlandLayout.VILLAGE_R + 2.0
			for c in [HighlandLayout.BEACON19, HighlandLayout.BEACON18]:
				if p.distance_to(c) < HighlandLayout.PAD_R:
					ok = false
			if near_village_works(p, 1.6):
				ok = false
			var chance := 0.07 + 0.5 * clampf((s - 0.12) / 0.25, 0.0, 1.0)
			if p.y < HighlandLayout.crest_z(p.x) - 10.0:
				chance = 0.04                            # 冰原上零星几块
			if ok and roll < chance:
				var size := rng.randf_range(0.5, 1.4) * (1.0 + 1.4 * pow(rng.randf(), 4.0))   # 大多不大，偶尔一块两三米的
				var y := Highland.height_at(p.x, p.y) - size * 0.22
				out.append([Vector3(p.x, y, p.y), rng.randf() * TAU, size, rng.randi_range(0, 3), rng.randf_range(-0.25, 0.25)])
			z += ROCK_STEP
		x += ROCK_STEP
	_cache.rocks = out
	return out


## 远处那串烽燧塔：[位置（塔脚）, 亮不亮]——山脊线往东西两边延下去，地图里的两座（第十九、第十八烽，5.3 / 5.5）不在这里
static func beacons() -> Array:
	if _cache.has("beacons"):
		return _cache.beacons
	var out := []
	for dir in [-1.0, 1.0]:
		for k in range(1, 7):
			var bx: float = HighlandLayout.BEACON19.x + dir * (BEACON_SPACING * k + (35.0 if dir < 0 else 0.0))
			if absf(bx - HighlandLayout.BEACON18.x) < 60.0:
				continue
			var bz := HighlandLayout.crest_z(bx) - 4.0
			var lit := false
			for l in LIT_BEACONS:
				if absf(bx - float(l)) < BEACON_SPACING * 0.5:
					lit = true
			out.append([Vector3(bx, Highland.far_height(bx, bz), bz), lit])
	_cache.beacons = out
	return out


# ---------------- 网格 ----------------

## 一棵树的网格（高 1 米，实例按高度缩放）：第 0 个面是树干，第 1 个是枝叶。lod 1 = 远处那份（层数减半、每根枝条一片）
static func tree_mesh(kind: int, lod: int) -> ArrayMesh:
	var key := "%d_%d" % [kind, lod]
	if _tree_meshes.has(key):
		return _tree_meshes[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 900 + kind
	var mesh := ArrayMesh.new()
	# 树干：8 边（远处 5 边）的锥
	var sides := 8 if lod == 0 else 5
	var tr := SurfaceTool.new()
	tr.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r0 := 0.022 if kind == 0 else 0.026
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var p := [Vector3(cos(a0) * r0, -0.02, sin(a0) * r0), Vector3(cos(a1) * r0, -0.02, sin(a1) * r0),
			Vector3(cos(a1) * 0.003, 0.96, sin(a1) * 0.003), Vector3(cos(a0) * 0.003, 0.96, sin(a0) * 0.003)]
		var n0 := Vector3(cos(a0), 0.05, sin(a0)).normalized()
		var n1 := Vector3(cos(a1), 0.05, sin(a1)).normalized()
		var uv := [Vector2(float(i) / sides, 6.0), Vector2(float(i + 1) / sides, 6.0), Vector2(float(i + 1) / sides, 0.0), Vector2(float(i) / sides, 0.0)]
		for k in [0, 1, 2, 0, 2, 3]:
			tr.set_normal(n0 if k in [0, 3] else n1)
			tr.set_uv(uv[k])
			tr.add_vertex(p[k])
	tr.commit(mesh)
	# 枝叶：一层层轮生的枝条
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var layers := 12 if kind == 0 else 10
	var per := 5 if kind == 0 else 6
	var base := 0.14 if kind == 0 else 0.12
	var width := 0.34 if kind == 0 else 0.42        # 最下面一层枝条伸出去多长（相对树高）
	var row := 0.0 if kind == 0 else 0.5           # 贴图的上半（冷杉）还是下半（云杉）
	var spin := rng.randf() * TAU
	for li in layers:
		if lod == 1 and li % 2 == 1:
			continue
		var t := float(li) / float(layers - 1)
		var y := lerpf(base, 0.95, t)
		var length := width * pow(1.0 - t, 0.85) + 0.035
		var droop := deg_to_rad(lerpf(28.0, 8.0, t)) + rng.randf_range(-0.05, 0.05)
		var count := per if lod == 0 else maxi(per - 1, 4)
		for bi in count:
			spin += 2.39996                               # 黄金角：每层错开，不排成一列
			var dir := Vector3(cos(spin), 0.0, sin(spin))
			var axis := (dir * cos(droop) - Vector3.UP * sin(droop)).normalized()
			var side := dir.cross(Vector3.UP).normalized()
			var w := length * (0.5 if kind == 0 else 0.55)
			var root := Vector3(0, y, 0)
			var vside := axis.cross(side).normalized()
			if lod == 0:
				_card(st, root, axis, side, length, w, row, t)                        # 平的那片
				_card(st, root, axis, vside, length, w * 0.8, row, t)                 # 竖的那片
			else:
				_card(st, root, axis, (side + vside).normalized(), length, w * 1.15, row, t)   # 远处：一片斜 45° 的（平的那片从侧面看只是一条线）
	var topw := 0.05
	_card(st, Vector3(0, 0.88, 0), Vector3.UP, Vector3.RIGHT, 0.14, topw, row, 1.0)   # 树尖
	_card(st, Vector3(0, 0.88, 0), Vector3.UP, Vector3.BACK, 0.14, topw, row, 1.0)
	st.commit(mesh)
	_tree_meshes[key] = mesh
	return mesh


## 一片枝片：从 root 沿 axis 伸出 length，宽 w（沿 side 两边各一半）。法线从树干往外、往上（树冠整体受光像个圆锥）；
## 顶点色 r = 离树干多远（风摆的幅度），g = 遮蔽（靠里、靠下暗）
static func _card(st: SurfaceTool, root: Vector3, axis: Vector3, side: Vector3, length: float, w: float, row: float, t: float) -> void:
	var tip := root + axis * length
	var hw := side * w * 0.5
	var pts := [root - hw, tip - hw, tip + hw, root + hw]
	var uvs := [Vector2(0.0, row + 0.5), Vector2(1.0, row + 0.5), Vector2(1.0, row), Vector2(0.0, row)]
	var reach := [0.0, 1.0, 1.0, 0.0]
	for k in [0, 1, 2, 0, 2, 3]:
		var p: Vector3 = pts[k]
		var out := Vector3(p.x, 0.0, p.z)
		var n := (out.normalized() * 0.8 + Vector3.UP * 0.6).normalized() if out.length() > 0.001 else Vector3.UP
		st.set_normal(n)
		st.set_color(Color(reach[k], lerpf(0.45, 1.0, clampf(out.length() / 0.25, 0.0, 1.0)) * lerpf(0.75, 1.0, t), 0.0))
		st.set_uv(uvs[k])
		st.add_vertex(p)


## 石头的网格（直径约 1 米，实例按大小缩放）：二十面体细分两次，按噪声往里往外推，底下压平一点
static func rock_mesh(variant: int) -> ArrayMesh:
	if _rock_meshes.size() > variant and _rock_meshes[variant] != null:
		return _rock_meshes[variant]
	var n := FastNoiseLite.new()
	n.seed = 31 + variant
	n.frequency = 1.6
	n.fractal_octaves = 3
	var squash: Vector3 = [Vector3(1.0, 0.7, 0.85), Vector3(1.2, 0.55, 0.9), Vector3(0.9, 0.85, 0.9), Vector3(1.3, 0.6, 1.0)][variant % 4]
	var sm := SphereMesh.new()
	sm.radial_segments = 14
	sm.rings = 8
	sm.radius = 0.5
	sm.height = 1.0
	var arr := sm.get_mesh_arrays()
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	for i in v.size():
		var p := v[i]
		var d := 1.0 + 0.32 * n.get_noise_3dv(p * 2.0) + 0.12 * absf(n.get_noise_3dv(p * 6.0 + Vector3(5, 0, 0)))
		p = p * d * squash
		if p.y < -0.12:
			p.y = lerpf(p.y, -0.12, 0.6)               # 底下压平一点（半埋在地里）
		v[i] = p
	arr[Mesh.ARRAY_VERTEX] = v
	var colors := PackedColorArray()
	colors.resize(v.size())
	for i in v.size():
		colors[i] = Color(0.0, 0.0, lerpf(0.75, 1.0, clampf(v[i].y + 0.5, 0.0, 1.0)))   # 地形着色器的 b = 遮蔽：底下暗
	arr[Mesh.ARRAY_COLOR] = colors
	arr[Mesh.ARRAY_NORMAL] = null
	arr[Mesh.ARRAY_TANGENT] = null
	var st := SurfaceTool.new()
	st.create_from_arrays(arr)
	st.generate_normals()
	var mesh := st.commit()
	while _rock_meshes.size() <= variant:
		_rock_meshes.append(null)
	_rock_meshes[variant] = mesh
	return mesh


static func branch_material(reduced_motion := false) -> ShaderMaterial:
	if _branch_mat == null:
		_branch_mat = ShaderMaterial.new()
		_branch_mat.shader = load("res://shaders/conifer.gdshader")
		var t: Texture2D = load(BRANCH_TEX) as Texture2D if ResourceLoader.exists(BRANCH_TEX) else null
		_branch_mat.set_shader_parameter("branches", t)
		_branch_mat.set_shader_parameter("noise_tex", Look.noise_texture())
	_branch_mat.set_shader_parameter("wind", 0.0 if reduced_motion else 1.0)
	return _branch_mat


# ---------------- 搭 ----------------

## 一块里的树和石头（ChunkStreamer 的一件活）：每种树近 / 远各一个多实例，石头一个多实例
static func build_chunk(root: Node3D, r: Rect2, reduced_motion: bool) -> void:
	var c := r.get_center()
	var origin := Vector3(c.x, 0.0, c.y)
	var per := []
	for k in TREE_KINDS:
		per.append([])
	for t in trees():
		var p: Vector3 = t[0]
		if r.has_point(Vector2(p.x, p.z)):
			per[int(t[3])].append(t)
	for k in TREE_KINDS:
		var list: Array = per[k]
		if list.is_empty():
			continue
		for lod in 2:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.mesh = tree_mesh(k, lod)
			mm.instance_count = list.size()
			for i in list.size():
				var t: Array = list[i]
				var h := float(t[2])
				var xf := Transform3D(Basis(Vector3.UP, float(t[1])).scaled(Vector3(h * randf_range_seeded(i, 0.85, 1.15), h, h * randf_range_seeded(i + 7, 0.85, 1.15))), (t[0] as Vector3) - origin)
				mm.set_instance_transform(i, xf)
				mm.set_instance_custom_data(i, Color(float(t[4]), float(t[5]), float(t[6]), 0.0))
			var mi := MultiMeshInstance3D.new()
			mi.name = "Trees%d_%s" % [k, "near" if lod == 0 else "far"]
			mi.multimesh = mm
			mi.position = origin
			mi.material_override = null
			mm.mesh.surface_set_material(0, Look.mat("bark"))
			mm.mesh.surface_set_material(1, branch_material(reduced_motion))
			if lod == 0:
				mi.visibility_range_end = TREE_LOD + 6.0
				mi.visibility_range_end_margin = 6.0
			else:
				mi.visibility_range_begin = TREE_LOD
				mi.visibility_range_begin_margin = 6.0
				mi.visibility_range_end = TREE_FAR
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.add_to_group("highland_trees")
			root.add_child(mi)
	var rl := []
	for rk in rocks():
		var p: Vector3 = rk[0]
		if r.has_point(Vector2(p.x, p.z)):
			rl.append(rk)
	if rl.is_empty():
		return
	var by_variant := {}
	for rk in rl:
		var v := int(rk[3])
		if not by_variant.has(v):
			by_variant[v] = []
		by_variant[v].append(rk)
	for v in by_variant:
		var list: Array = by_variant[v]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = rock_mesh(int(v))
		mm.instance_count = list.size()
		for i in list.size():
			var rk: Array = list[i]
			var s := float(rk[2])
			var basis := Basis(Vector3.UP, float(rk[1])) * Basis(Vector3.RIGHT, float(rk[4]))
			mm.set_instance_transform(i, Transform3D(basis.scaled(Vector3(s, s, s)), (rk[0] as Vector3) - origin))
		var mi := MultiMeshInstance3D.new()
		mi.name = "Rocks%d" % int(v)
		mi.multimesh = mm
		mi.position = origin
		mi.material_override = Highland.ground_material()
		mi.visibility_range_end = TREE_FAR
		root.add_child(mi)


## 每棵树都不一样的那点随机（按下标固定，不用全局随机数：测试和每次载入都一样）
static func randf_range_seeded(i: int, lo: float, hi: float) -> float:
	return lerpf(lo, hi, float(absi(hash(i * 2654435761)) % 1000) / 1000.0)


## 地图外面山坡上的针叶林：几千个小圆锥（雾里一片黑压压的），一次画完
static func far_forest(parent: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5103
	var forest := FastNoiseLite.new()
	forest.seed = 78
	forest.frequency = 0.008
	var pts := []
	var tries := 0
	while pts.size() < FAR_FOREST and tries < FAR_FOREST * 8:
		tries += 1
		var x := rng.randf_range(-900.0, 900.0)
		var z := rng.randf_range(-200.0, 900.0)
		if HighlandLayout.BOUNDS.grow(70.0).has_point(Vector2(x, z)):
			continue                                   # 离地图边 70 米以内不放（近了一眼看出是圆锥，截图）
		if z < HighlandLayout.crest_z(x) + 10.0:
			continue                                   # 山脊北边是冰原
		var y := Highland.far_height(x, z)
		if y > 95.0 or forest.get_noise_2d(x, z) < -0.05:
			continue
		pts.append(Vector3(x, y - 0.5, z))
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.28
	cone.height = 1.0
	cone.radial_segments = 6
	cone.rings = 1
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("1c2420")
	m.roughness = 1.0
	cone.material = m
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = cone
	mm.instance_count = pts.size()
	for i in pts.size():
		var h := rng.randf_range(9.0, 16.0)
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(h, h, h)), (pts[i] as Vector3) + Vector3(0, h * 0.5, 0)))
	var mi := MultiMeshInstance3D.new()
	mi.name = "FarForest"
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


## 远处那串烽燧塔：石砌的塔身（主包的石墙贴图）、塔顶铁火盆；亮着的塔顶一团火 + 不受雾影响的暖光晕
static func far_beacons(parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "FarBeacons"
	parent.add_child(root)
	var body := CylinderMesh.new()
	body.top_radius = 1.7
	body.bottom_radius = 2.3
	body.height = 11.0
	body.radial_segments = 10
	body.rings = 1
	body.material = Look.mat("stone")
	var pan := CylinderMesh.new()
	pan.top_radius = 1.4
	pan.bottom_radius = 0.9
	pan.height = 0.9
	pan.radial_segments = 8
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color("2a2624")
	iron.roughness = 0.8
	pan.material = iron
	var list := beacons()
	for part in [[body, 5.0, "Towers"], [pan, 10.9, "Pans"]]:      # 塔身、火盆各一个多实例（一座一个网格时 11 座多画 22 次）
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = part[0]
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, (list[i][0] as Vector3) + Vector3(0, float(part[1]), 0)))
		var mi := MultiMeshInstance3D.new()
		mi.name = str(part[2])
		mi.multimesh = mm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	for bc in list:
		var at: Vector3 = bc[0]
		if bool(bc[1]):
			var fire := MeshInstance3D.new()
			var q := QuadMesh.new()
			q.size = Vector2(4.0, 4.6)
			var fm := StandardMaterial3D.new()
			fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			fm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
			fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			fm.albedo_texture = Look.halo_texture()
			fm.albedo_color = Color(1.0, 0.62, 0.25, 1.0)
			fm.disable_fog = true
			q.material = fm
			fire.mesh = q
			fire.position = at + Vector3(0, 12.3, 0)
			root.add_child(fire)
			var glow := MeshInstance3D.new()
			var g := QuadMesh.new()
			g.size = Vector2(46.0, 46.0)
			var gm := fm.duplicate() as StandardMaterial3D
			gm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
			gm.albedo_color = Color(1.0, 0.55, 0.22, 0.6)
			g.material = gm
			glow.mesh = g
			glow.position = at + Vector3(0, 12.0, 0)
			glow.name = "BeaconGlow%d" % root.get_child_count()
			root.add_child(glow)
