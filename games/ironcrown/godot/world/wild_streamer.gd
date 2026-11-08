class_name WildStreamer
extends Node3D
## 无尽荒野（2026-11-08 所有者「地图好像一个不大的四方块，走到边缘就走不动了，能扩大展开吗，玩家可自由无尽探索」）：
## 手工地图（core）外面不再有空气墙，换成边走边生成的荒野——
##   以 CHUNK 米为一块，跟手工地图的分块对齐；你周围 radius 块以内、在 core 外面的块按离你远近一块一块搭（每帧最多一块，不卡）；
##   超出 radius + 1 块的拆掉（理论上可以一直走，内存不涨）；
##   每块：一张地形网格（SAMPLE 米一格、四边垂裙边）+ 一块高度图碰撞（1 米一格）+ scatter（树、石头……按块的坐标定种子，回来还是一样）；
##   far_fn：你离远景地形的中心超过 FAR_RECENTER 米，就以你为中心重搭远景（Highland._far），天边永远有山。
## 高度 height_fn(x, z) 由区域给（高地：远景那套 far_height 往上抬回 0.4 米，在手工地图边上和它接得上）。

const CHUNK := 64.0
const SAMPLE := 2.0
const SKIRT := 2.0
const FAR_RECENTER := 600.0

var core := Rect2()
var origin := Vector2.ZERO              # 分块对齐的原点（手工地图的左上角）
var radius := 3
var height_fn: Callable                 # (x, z) -> float（荒野）
var ground_fn: Callable                 # (x, z) -> float（手工地图里外都对的地面高度：玩家掉出地图的判断用，main 交给 FpController）
var color_fn: Callable                  # (x, z, slope) -> Color（地面着色器的顶点色）；没给就 (0, 坡度, 1)
var scatter_fn: Callable                # (root: Node3D, body: StaticBody3D, rect: Rect2, seed: int) -> void
var material: Material
var surface := "snow"
var carve_core := true                 # 和手工地图重叠的块切掉重叠那条（大地图）；false：整块照搭（小的林中空地比一块还小，切不成矩形；荒野在空地里面压到空地自己的地面底下）
var deep_y := -INF                      # 比这个低的是深水（海、河）：荒野里同样在深水边立看不见的墙（层 5「边界」），浅滩走得下去，深水走不进去
var deep_wall_top := 1.5
var far_fn: Callable                    # (center: Vector2) -> void
var region := ""                        # 荒野里的小发现（WildFinds）按哪一套：highland / plain / harbor / forest；"" = 不放
var area_id := ""                       # 区域名（小发现拿过东西的旗标用）
var finds := {}                         # 块 → 这块里的小发现 {kind, name, pos, key}（小地图画）
var far_center := Vector2.ZERO
var chunks := {}                        # "i_j" → Node3D
var built := 0                          # 一共搭过几块（测试看）


static func make(p_core: Rect2, p_height: Callable, p_material: Material, p_radius := 3) -> WildStreamer:
	var w := WildStreamer.new()
	w.name = "Wild"
	w.core = p_core
	w.origin = p_core.position
	w.height_fn = p_height
	w.material = p_material
	w.radius = p_radius
	w.add_to_group("wild")                     # Cold.wild_rate 找它：走出地图越远越冷
	return w


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return
	update_around(Vector2(cam.global_position.x, cam.global_position.z), 1)


## 你在 p：缺的块搭最多 budget 块（近的先搭），远的拆掉；必要时重搭远景
func update_around(p: Vector2, budget: int) -> void:
	var ci := int(floor((p.x - origin.x) / CHUNK))
	var cj := int(floor((p.y - origin.y) / CHUNK))
	var want := []
	for dj in range(-radius, radius + 1):
		for di in range(-radius, radius + 1):
			var key := "%d_%d" % [ci + di, cj + dj]
			if chunks.has(key):
				continue
			var r := _rect(ci + di, cj + dj)
			if r.size.x <= 0.5 or r.size.y <= 0.5:
				continue
			want.append([di * di + dj * dj, ci + di, cj + dj])
	want.sort_custom(func(a, b): return a[0] < b[0])
	for k in mini(budget, want.size()):
		_build(int(want[k][1]), int(want[k][2]))
	for key in chunks.keys():
		var ij: PackedStringArray = (key as String).split("_")
		if absi(int(ij[0]) - ci) > radius + 1 or absi(int(ij[1]) - cj) > radius + 1:
			(chunks[key] as Node).queue_free()
			chunks.erase(key)
			finds.erase(key)
	if far_fn.is_valid() and p.distance_to(far_center) > FAR_RECENTER:
		far_center = p.snapped(Vector2(200.0, 200.0))
		far_fn.call(far_center)


## 第 (i, j) 块在 core 外面的那部分（core 里面由手工地图画；和 core 只沾一条边的块把重叠那一条切掉）
func _rect(i: int, j: int) -> Rect2:
	var r := Rect2(origin.x + i * CHUNK, origin.y + j * CHUNK, CHUNK, CHUNK)
	if not r.intersects(core) or not carve_core:
		return r
	if core.encloses(r):
		return Rect2()
	if r.position.y < core.end.y and r.end.y > core.end.y and r.position.x >= core.position.x and r.end.x <= core.end.x:
		return Rect2(r.position.x, core.end.y, r.size.x, r.end.y - core.end.y)
	if r.position.y < core.position.y and r.end.y > core.position.y and r.position.x >= core.position.x and r.end.x <= core.end.x:
		return Rect2(r.position.x, r.position.y, r.size.x, core.position.y - r.position.y)
	if r.position.x < core.end.x and r.end.x > core.end.x and r.position.y >= core.position.y and r.end.y <= core.end.y:
		return Rect2(core.end.x, r.position.y, r.end.x - core.end.x, r.size.y)
	if r.position.x < core.position.x and r.end.x > core.position.x and r.position.y >= core.position.y and r.end.y <= core.end.y:
		return Rect2(r.position.x, r.position.y, core.position.x - r.position.x, r.size.y)
	return Rect2()


func _build(i: int, j: int) -> void:
	var r := _rect(i, j)
	var c := r.get_center()
	var root := Node3D.new()
	root.name = "Wild_%d_%d" % [i, j]
	root.position = Vector3(c.x, 0, c.y)
	add_child(root)
	chunks["%d_%d" % [i, j]] = root
	built += 1
	var sx := int(round(r.size.x / SAMPLE)) + 1  # 高度每 SAMPLE 米算一个（噪声贵：网页上一块 4000 多次会卡一下）
	var sz := int(round(r.size.y / SAMPLE)) + 1
	var g := PackedFloat32Array()
	g.resize(sx * sz)
	for zz in sz:
		for xx in sx:
			g[zz * sx + xx] = float(height_fn.call(r.position.x + xx * SAMPLE, r.position.y + zz * SAMPLE))
	var nx := int(round(r.size.x)) + 1          # 碰撞：1 米一格，从上面那些点双线性插出来
	var nz := int(round(r.size.y)) + 1
	var hs := PackedFloat32Array()
	hs.resize(nx * nz)
	for zz in nz:
		var fz := minf(zz / SAMPLE, sz - 1.001)
		var j0 := int(fz)
		var tz := fz - j0
		for xx in nx:
			var fx := minf(xx / SAMPLE, sx - 1.001)
			var i0 := int(fx)
			var tx := fx - i0
			var a := lerpf(g[j0 * sx + i0], g[j0 * sx + i0 + 1], tx)
			var b := lerpf(g[(j0 + 1) * sx + i0], g[(j0 + 1) * sx + i0 + 1], tx)
			hs[zz * nx + xx] = lerpf(a, b, tz)
	var body := StaticBody3D.new()
	body.name = "Ground"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", surface)
	root.add_child(body)
	var cs := CollisionShape3D.new()
	var hm := HeightMapShape3D.new()
	hm.map_width = nx
	hm.map_depth = nz
	hm.map_data = hs
	cs.shape = hm
	cs.position = Vector3(r.position.x + (nx - 1) * 0.5 - c.x, 0, r.position.y + (nz - 1) * 0.5 - c.y)
	body.add_child(cs)
	if deep_y > -INF:
		_deep_walls(root, r, g, sx, sz)
	var mi := MeshInstance3D.new()
	mi.name = "WildTerrain"
	mi.mesh = _mesh(r, g, sx, sz)
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	if scatter_fn.is_valid():
		scatter_fn.call(root, body, r, hash("%d_%d" % [i, j]))
	if region != "":
		var f := WildFinds.place(root, body, r, hash("%d_%d" % [i, j]), height_fn, region, area_id, core)
		if not f.is_empty():
			finds["%d_%d" % [i, j]] = f


func _mesh(r: Rect2, g: PackedFloat32Array, sx: int, sz: int) -> ArrayMesh:
	var c := r.get_center()
	var nc := sx
	var nr := sz
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()             # 世界坐标（米）当 UV：普通贴图材质（序章的雪地，Look.mat）按米平铺
	var H := func(xx: int, zz: int) -> float: return g[clampi(zz, 0, sz - 1) * sx + clampi(xx, 0, sx - 1)]
	for rj in nr:
		for ci in nc:
			var wx := r.position.x + ci * SAMPLE
			var wz := r.position.y + rj * SAMPLE
			var y: float = H.call(ci, rj)
			verts.append(Vector3(wx - c.x, y, wz - c.y))
			uvs.append(Vector2(wx, wz))
			var dx: float = (H.call(ci + 1, rj) - H.call(ci - 1, rj)) / (2.0 * SAMPLE)
			var dz: float = (H.call(ci, rj + 1) - H.call(ci, rj - 1)) / (2.0 * SAMPLE)
			var n := Vector3(-dx, 1.0, -dz).normalized()
			norms.append(n)
			var slope := 1.0 - n.y
			colors.append(color_fn.call(wx, wz, slope) if color_fn.is_valid() else Color(0.0, clampf((slope - 0.12) * 2.2, 0.0, 0.85), 1.0))
	var idx := PackedInt32Array()
	for rj in nr - 1:
		for ci in nc - 1:
			var a := rj * nc + ci
			idx.append_array(PackedInt32Array([a, a + 1, a + nc, a + 1, a + nc + 1, a + nc]))
	var edges := []                               # 四边往下垂的裙边：和手工地图、远景之间不露天
	var top: Array[int] = []
	var bottom: Array[int] = []
	var left: Array[int] = []
	var right: Array[int] = []
	for ci in nc:
		top.append(ci)
		bottom.append((nr - 1) * nc + ci)
	for rj in nr:
		left.append(rj * nc)
		right.append(rj * nc + nc - 1)
	edges = [top, bottom, left, right]
	for e: Array[int] in edges:
		var base := verts.size()
		for k in e:
			verts.append(verts[k] - Vector3(0, SKIRT, 0))
			norms.append(norms[k])
			colors.append(colors[k])
			uvs.append(uvs[k])
		for n in e.size() - 1:
			var a := e[n]
			var b := e[n + 1]
			idx.append_array(PackedInt32Array([a, base + n, b, b, base + n, base + n + 1, a, b, base + n, b, base + n + 1, base + n]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = colors
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## 深水边的墙：采样格（SAMPLE 米）里深、浅相邻的地方立一面竖的（一个凹多边形碰撞体、两面都挡；同 Harbor._deep_walls）
func _deep_walls(root: Node3D, r: Rect2, g: PackedFloat32Array, sx: int, sz: int) -> void:
	var c := r.get_center()
	var faces := PackedVector3Array()
	var lo := deep_y - 4.0
	var hi := deep_wall_top
	var D := func(i: int, j: int) -> bool: return g[j * sx + i] < deep_y
	var wall := func(a: Vector2, b: Vector2) -> void:
		var a0 := Vector3(a.x - c.x, lo, a.y - c.y)
		var b0 := Vector3(b.x - c.x, lo, b.y - c.y)
		var a1 := Vector3(a.x - c.x, hi, a.y - c.y)
		var b1 := Vector3(b.x - c.x, hi, b.y - c.y)
		faces.append_array(PackedVector3Array([a0, b0, b1, a0, b1, a1]))
	for j in sz:
		for i in sx:
			var here: bool = D.call(i, j)
			var x := r.position.x + i * SAMPLE
			var z := r.position.y + j * SAMPLE
			if i + 1 < sx and here != D.call(i + 1, j):
				wall.call(Vector2(x + SAMPLE * 0.5, z - SAMPLE * 0.5), Vector2(x + SAMPLE * 0.5, z + SAMPLE * 0.5))
			if j + 1 < sz and here != D.call(i, j + 1):
				wall.call(Vector2(x - SAMPLE * 0.5, z + SAMPLE * 0.5), Vector2(x + SAMPLE * 0.5, z + SAMPLE * 0.5))
	if faces.is_empty():
		return
	var body := StaticBody3D.new()
	body.name = "DeepWalls"
	body.collision_layer = FpController.LAYER_BOUNDARY
	body.collision_mask = 0
	root.add_child(body)
	var cs := CollisionShape3D.new()
	var sh := ConcavePolygonShape3D.new()
	sh.backface_collision = true
	sh.set_faces(faces)
	cs.shape = sh
	body.add_child(cs)
