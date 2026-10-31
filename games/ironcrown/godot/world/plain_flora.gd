class_name PlainFlora
extends RefCounted
## 金穗平原的树、篱笆、麦垛、木栅和地平线上的树（路线图 6.1b，D12；STORY.md 6.2「河边的柳树光秃秃的」「洛蒙德家的粮仓满着，佃农却在挨饿」）。
## 全部用代码搭，枝条贴图也是代码画的（tests/gen_plain_twigs.gd → chapters/ch3/trees/plain_twigs.png，三格：细枝、柳条、整棵树剪影）：
##   截头柳 = 一截粗短的树干 + 鼓起来的树头 + 四片交叉的柳条片（冬天的黄枝柳：下面暗、梢上金黄带红——一片白里唯一的暖色），沿麦河两岸一棵接一棵；
##   落叶树（篱笆里的老橡树、路边的树）= 树干 + 四五根主枝 + 二级枝（锥形的管子，树皮贴图）+ 枝梢上交叉的细枝片；远了换成两片交叉的整棵树剪影；
##   篱笆 = 田埂上一丛丛光秃的灌木（三片交叉的细枝片），按地面着色器里田的分块（40 × 34 米）长在田边，每段留一个豁口；
##   麦垛 = 车床旋出来的圆垛、顶上积雪：洛蒙德家的田里又大又多，佃农村边上只有两三个小的、被扯掉了一角；
##   木栅 = 磨坊到庄园那条路边一道柱子加两根横木的栅栏（洛蒙德家的地）；
##   地平线上的树 = 地图外面几百片交叉的剪影，一排排、一丛丛（砧山那一侧少）。
## 摆在哪：按固定种子撒，再按布局筛（不上路、不下河、不进村子 / 磨坊 / 庄园那几块平地）。碰撞：树干圆柱、麦垛圆柱、篱笆和木栅一段段的盒子（Plain._collision）。

const TWIG_TEX := "res://chapters/ch3/trees/plain_twigs.png"
const TREE_LOD := 70.0                 # 落叶树多远换成剪影
const TREE_FAR := 320.0
const WILLOW_FAR := 240.0
const HEDGE_FAR := 150.0
const RICK_FAR := 320.0
const FENCE_FAR := 150.0
const HEDGE_GAP := 1.35                # 篱笆里一丛灌木隔多远
const FIELD_CELL := Vector2(40.0, 34.0)
const FIELD_OFF := Vector2(7.0, -3.0)  # 和 plain_ground.gdshader 里田的分块一样
const FENCE_BAY := 2.5
## 麦垛堆在哪：[中心, 几个, 大小, 「村里」（小的、扯掉一角）]
const RICK_YARDS := [
	[Vector2(100.0, -12.0), 4, 1.0, false], [Vector2(58.0, 22.0), 3, 1.05, false], [Vector2(124.0, -52.0), 3, 0.95, false], [Vector2(50.0, -72.0), 2, 1.0, false],
	[Vector2(-96.0, 62.0), 2, 0.62, true], [Vector2(-112.0, 8.0), 1, 0.58, true],
]

static var _meshes := {}
static var _mats := {}
static var _cache := {}


static func clear_cache() -> void:
	_meshes.clear()
	_mats.clear()
	_cache.clear()


static func warm(reduced_motion := false) -> void:
	material("bark", reduced_motion)
	material("twig", reduced_motion)
	material("straw", reduced_motion)
	for v in 3:
		tree_mesh(v)
	for v in 2:
		willow_mesh(v)
	shrub_mesh()
	far_card_mesh()
	rick_mesh(false)
	rick_mesh(true)
	fence_mesh()
	willows()
	hedges()
	trees()
	ricks()
	fences()


# ---------------- 摆在哪 ----------------

## 能不能摆东西：在地图里、离河 / 路 / 几块平地够远
static func _free(p: Vector2, road_margin: float, river_min: float) -> bool:
	if not PlainLayout.BOUNDS.grow(-(PlainLayout.WALL_INSET + 2.0)).has_point(p):
		return false
	if PlainLayout.road_d(p) < PlainLayout.ROAD_HALF + road_margin:
		return false
	if PlainLayout.river_d(p) < river_min:
		return false
	for pad: Array in PlainLayout.pads() + [[PlainLayout.ABBEY, PlainLayout.ABBEY_R, 0.0], [PlainLayout.GRANARY, 14.0, 0.0]]:
		if p.distance_to(pad[0]) < float(pad[1]) + 3.0:
			return false
	return true


## 在麦垛场里（篱笆不穿过去）
static func _in_yard(p: Vector2) -> bool:
	for y: Array in RICK_YARDS:
		var d := p - (y[0] as Vector2)
		if absf(d.x) < 15.0 and absf(d.y) < 12.5:
			return true
	return false


static func _bridge_d(p: Vector2) -> float:
	var a: Vector2 = PlainLayout.BRIDGE[0]
	var b: Vector2 = PlainLayout.BRIDGE[1]
	return p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))


## 截头柳：[位置, 朝向, 大小, 样子, 深浅, 雪, 风的相位]，沿河两岸，岸坡上半截（离河中线 RIVER_HALF + 3.5..8 米）
static func willows() -> Array:
	if _cache.has("willows"):
		return _cache.willows
	var out := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 6111
	var pts: Array = PlainLayout.RIVER
	for k in pts.size() - 1:
		var a: Vector2 = pts[k]
		var b: Vector2 = pts[k + 1]
		var n := Vector2(-(b - a).y, (b - a).x).normalized()
		var len := a.distance_to(b)
		for side in [-1.0, 1.0]:
			var s := rng.randf_range(0.0, 6.0)
			while s < len:
				var t := s / len
				var p: Vector2 = a.lerp(b, t) + n * side * (PlainLayout.RIVER_HALF + rng.randf_range(3.5, 8.0))
				s += rng.randf_range(6.5, 11.0)
				if rng.randf() < 0.22:
					s += rng.randf_range(8.0, 20.0)                 # 一段一段的，中间空着
					continue
				if PlainLayout.river_d(p) < PlainLayout.RIVER_HALF + 3.0 or _bridge_d(p) < 9.0 or p.distance_to(PlainLayout.DOCK) < 13.0:
					continue
				if not PlainLayout.BOUNDS.grow(-(PlainLayout.WALL_INSET + 2.0)).has_point(p) or PlainLayout.road_d(p) < PlainLayout.ROAD_HALF + 2.5:
					continue
				var y := PlainLayout.height(p.x, p.y)
				out.append([Vector3(p.x, y - 0.1, p.y), rng.randf() * TAU, rng.randf_range(0.85, 1.15), rng.randi() % 2, rng.randf(), rng.randf_range(0.5, 1.0), rng.randf()])
	_cache.willows = out
	return out


## 篱笆：田的分块边上，选一半左右的边；[位置, 朝向, 大小, 0, 深浅, 雪, 相位]。「hedge_runs」= 每段连着的几丛（碰撞用：起点、终点）
static func hedges() -> Array:
	if _cache.has("hedges"):
		return _cache.hedges
	var out := []
	var runs := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 6112
	var b := PlainLayout.BOUNDS
	var edges := []                                    # [起点, 终点]
	var x0 := ceilf((b.position.x + FIELD_OFF.x) / FIELD_CELL.x) * FIELD_CELL.x - FIELD_OFF.x
	var z0 := ceilf((b.position.y + FIELD_OFF.y) / FIELD_CELL.y) * FIELD_CELL.y - FIELD_OFF.y
	var x := x0
	while x < b.end.x:
		var z := z0 - FIELD_CELL.y
		while z < b.end.y:
			edges.append([Vector2(x, z), Vector2(x, z + FIELD_CELL.y)])
			z += FIELD_CELL.y
		x += FIELD_CELL.x
	var z := z0
	while z < b.end.y:
		x = x0 - FIELD_CELL.x
		while x < b.end.x:
			edges.append([Vector2(x, z), Vector2(x + FIELD_CELL.x, z)])
			x += FIELD_CELL.x
		z += FIELD_CELL.y
	for e: Array in edges:
		if rng.randf() > 0.5:
			continue
		var a: Vector2 = e[0]
		var c: Vector2 = e[1]
		var dir := (c - a).normalized()
		var len := a.distance_to(c)
		var gate := rng.randf_range(0.2, 0.8) * len        # 豁口（人走得过去）
		var s := 0.8
		var run_start := Vector2.INF
		var run_last := Vector2.INF
		while s < len - 0.8:
			var p := a + dir * s + Vector2(-dir.y, dir.x) * rng.randf_range(-0.35, 0.35)
			var ok := absf(s - gate) > 2.4 and _free(p, 2.0, PlainLayout.RIVER_HALF + PlainLayout.RIVER_BANK + 3.0) and not _in_yard(p) and PlainLayout.masks(p.x, p.y).y > 0.6
			if ok:
				out.append([Vector3(p.x, PlainLayout.height(p.x, p.y), p.y), rng.randf() * TAU, rng.randf_range(0.75, 1.2), 0, rng.randf(), rng.randf_range(0.6, 1.0), rng.randf()])
				if run_start == Vector2.INF:
					run_start = p
				run_last = p
			elif run_start != Vector2.INF:
				runs.append([run_start, run_last])
				run_start = Vector2.INF
			s += HEDGE_GAP * rng.randf_range(0.8, 1.2)
		if run_start != Vector2.INF:
			runs.append([run_start, run_last])
	_cache.hedges = out
	_cache.hedge_runs = runs
	return out


static func hedge_runs() -> Array:
	hedges()
	return _cache.hedge_runs


## 落叶树：篱笆里每隔一段一棵老橡树，路边稀稀落落几棵；[位置, 朝向, 高, 样子, 深浅, 雪, 相位]
static func trees() -> Array:
	if _cache.has("trees"):
		return _cache.trees
	var out := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 6113
	var hs := hedges()
	var last := Vector2(1e9, 1e9)
	for h: Array in hs:
		var p := Vector2((h[0] as Vector3).x, (h[0] as Vector3).z)
		if p.distance_to(last) > 22.0 and rng.randf() < 0.09:
			out.append([h[0] as Vector3 - Vector3(0, 0.1, 0), rng.randf() * TAU, rng.randf_range(8.5, 12.5), rng.randi() % 3, rng.randf(), rng.randf_range(0.5, 1.0), rng.randf()])
			last = p
	for r: Array in PlainLayout.ROADS:
		for k in r.size() - 1:
			var a: Vector2 = r[k]
			var c: Vector2 = r[k + 1]
			var dir := (c - a).normalized()
			var s := rng.randf_range(4.0, 20.0)
			while s < a.distance_to(c):
				var side := 1.0 if rng.randf() < 0.5 else -1.0
				var p := a + dir * s + Vector2(-dir.y, dir.x) * side * rng.randf_range(4.8, 6.5)
				s += rng.randf_range(22.0, 40.0)
				if rng.randf() < 0.45 and _free(p, 2.4, PlainLayout.RIVER_HALF + PlainLayout.RIVER_BANK + 2.0):
					out.append([Vector3(p.x, PlainLayout.height(p.x, p.y) - 0.1, p.y), rng.randf() * TAU, rng.randf_range(7.5, 11.0), rng.randi() % 3, rng.randf(), rng.randf_range(0.5, 1.0), rng.randf()])
	_cache.trees = out
	return out


## 麦垛：[位置, 朝向, 大小, 村里的（扯掉一角）, 深浅, 雪, 0]
static func ricks() -> Array:
	if _cache.has("ricks"):
		return _cache.ricks
	var out := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 6114
	for y: Array in RICK_YARDS:
		var c: Vector2 = y[0]
		var placed := 0
		var tries := 0
		while placed < int(y[1]) and tries < 40:
			tries += 1
			var p := c + Vector2(rng.randf_range(-9.0, 9.0), rng.randf_range(-7.0, 7.0))
			var s := float(y[2]) * rng.randf_range(0.9, 1.1)
			var clash := false
			for o: Array in out:
				if Vector2((o[0] as Vector3).x, (o[0] as Vector3).z).distance_to(p) < 6.0 * maxf(s, float(o[2])):
					clash = true
			if clash or not _free(p, 3.0, PlainLayout.RIVER_HALF + PlainLayout.RIVER_BANK + 4.0):
				continue
			out.append([Vector3(p.x, PlainLayout.height(p.x, p.y) - 0.15, p.y), rng.randf() * TAU, s, bool(y[3]), rng.randf(), rng.randf_range(0.7, 1.0), 0.0])
			placed += 1
	_cache.ricks = out
	return out


## 木栅：一跨一跨 [起点（地上）, 终点（地上）]。洛蒙德家的麦垛场（三个以上大垛的那两处）四面围着栅栏、朝路那面留门（粮是看着的）；
## 磨坊到庄园那条路（ROADS[3]）南边能摆的地方也有一段
static func fences() -> Array:
	if _cache.has("fences"):
		return _cache.fences
	var out := []
	for y: Array in RICK_YARDS:
		if bool(y[3]) or int(y[1]) < 3:
			continue
		var c: Vector2 = y[0]
		var hx := 12.5
		var hz := 10.0
		var corners := [c + Vector2(-hx, -hz), c + Vector2(hx, -hz), c + Vector2(hx, hz), c + Vector2(-hx, hz)]
		var to_road := Vector2.ZERO
		var best := INF
		for k in 4:
			var m: Vector2 = ((corners[k] as Vector2) + (corners[(k + 1) % 4] as Vector2)) * 0.5
			if PlainLayout.road_d(m) < best:
				best = PlainLayout.road_d(m)
				to_road = m
		for k in 4:
			var a: Vector2 = corners[k]
			var b: Vector2 = corners[(k + 1) % 4]
			var gate := ((a + b) * 0.5).distance_to(to_road) < 0.1
			_fence_line(out, a, b, gate)
	var r: Array = PlainLayout.ROADS[3]
	for k in r.size() - 1:
		var a: Vector2 = r[k]
		var c: Vector2 = r[k + 1]
		var dir := (c - a).normalized()
		var off := Vector2(-dir.y, dir.x) * 4.2
		if off.y < 0.0:
			off = -off                                       # 路的南边
		_fence_line(out, a + off, c + off, false)
	_cache.fences = out
	return out


## 一条栅栏：从 a 到 b 一跨一跨，能摆的才摆（不上路、不进平地）；gate = 中间留一个四米多的门
static func _fence_line(out: Array, a: Vector2, b: Vector2, gate: bool) -> void:
	var dir := (b - a).normalized()
	var len := a.distance_to(b)
	var bays := maxi(1, int(round(len / FENCE_BAY)))
	var step := len / bays
	for i in bays:
		var p0 := a + dir * (i * step)
		var p1 := a + dir * ((i + 1) * step)
		var mid := (p0 + p1) * 0.5
		if gate and absf(i + 0.5 - bays * 0.5) < 1.0:
			continue
		if mid.distance_to(PlainLayout.GRANARY) < 16.0 or mid.distance_to(PlainLayout.MANOR) < PlainLayout.MANOR_R + 2.0 or mid.distance_to(PlainLayout.MILL) < PlainLayout.MILL_R + 2.0:
			continue
		if PlainLayout.road_d(mid) < PlainLayout.ROAD_HALF + 1.2 or not PlainLayout.BOUNDS.grow(-(PlainLayout.WALL_INSET + 1.0)).has_point(mid):
			continue
		out.append([Vector3(p0.x, PlainLayout.height(p0.x, p0.y), p0.y), Vector3(p1.x, PlainLayout.height(p1.x, p1.y), p1.y)])


## 地图外面的树：[位置, 朝向, 高, 深浅]
static func far_trees() -> Array:
	if _cache.has("far"):
		return _cache.far
	var out := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 6115
	var b := PlainLayout.BOUNDS
	var rows := FastNoiseLite.new()
	rows.seed = 61
	rows.frequency = 0.012
	var tries := 0
	while out.size() < 900 and tries < 20000:
		tries += 1
		var p := Vector2(rng.randf_range(-700.0, 700.0), rng.randf_range(-650.0, 650.0))
		if b.grow(6.0).has_point(p):
			continue
		var dist := p.length()
		if dist > 720.0:
			continue
		var toward := p.normalized().dot(PlainLayout.ANVIL_DIR)
		if toward > 0.6 and rng.randf() < 0.8:
			continue                                         # 砧山那一侧是光秃秃的坡
		var clump := rows.get_noise_2dv(p)
		if clump < 0.15 and rng.randf() < 0.9:
			continue                                         # 一丛一丛、一排一排
		out.append([Vector3(p.x, Plain.far_height(p.x, p.y) - 0.3, p.y), rng.randf() * TAU, rng.randf_range(9.0, 16.0), rng.randf()])
	_cache.far = out
	return out


# ---------------- 网格 ----------------

## 一段锥形的管子（树枝）：a → b，半径 r0 → r1；UV 的 u 绕一圈、v 沿长（树皮贴图按米）
static func _tube(st: SurfaceTool, a: Vector3, b: Vector3, r0: float, r1: float, sides: int, v0: float, vscale: float) -> float:
	var ax := (b - a).normalized()
	var ref := Vector3.UP if absf(ax.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var u := ax.cross(ref).normalized()
	var w := ax.cross(u).normalized()
	var len := a.distance_to(b)
	var v1 := v0 + len * vscale
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var d0 := u * cos(a0) + w * sin(a0)
		var d1 := u * cos(a1) + w * sin(a1)
		var q := [a + d0 * r0, a + d1 * r0, b + d1 * r1, b + d0 * r1]
		var nn := [d0, d1, d1, d0]
		var uv := [Vector2(float(i) / sides, v0), Vector2(float(i + 1) / sides, v0), Vector2(float(i + 1) / sides, v1), Vector2(float(i) / sides, v1)]
		for k in [0, 1, 2, 0, 2, 3]:
			st.set_normal(nn[k])
			st.set_uv(uv[k])
			st.set_color(Color(0.0, 1.0, 0.0))
			st.add_vertex(q[k])
	return v1


## 一片枝片：根在 root，沿 up 长 height，宽 width（沿 side）；tile = 贴图第几格。法线从树干往外、往上（整丛像一团受光）；顶点色 r = 离根多远（风摆）
static func _card(st: SurfaceTool, root: Vector3, up: Vector3, side: Vector3, height: float, width: float, tile: int, center: Vector3) -> void:
	var hw := side.normalized() * width * 0.5
	var top := root + up.normalized() * height
	var pts := [root - hw, root + hw, top + hw, top - hw]
	var u0 := tile / 3.0
	var u1 := (tile + 1) / 3.0
	var uvs := [Vector2(u0, 1.0), Vector2(u1, 1.0), Vector2(u1, 0.0), Vector2(u0, 0.0)]
	var reach := [0.0, 0.0, 1.0, 1.0]
	for k in [0, 1, 2, 0, 2, 3]:
		var p: Vector3 = pts[k]
		var out := p - center
		out.y *= 0.3
		var n := (out.normalized() * 0.75 + Vector3.UP * 0.65).normalized() if out.length() > 0.01 else Vector3.UP
		st.set_normal(n)
		st.set_uv(uvs[k])
		st.set_color(Color(reach[k], 1.0, 0.0))
		st.add_vertex(p)


## 落叶树（高 1，实例按高缩放）：树干 + 主枝 + 二级枝（管子）+ 枝梢的细枝片
static func tree_mesh(variant: int) -> ArrayMesh:
	var key := "tree%d" % variant
	if _meshes.has(key):
		return _meshes[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 6200 + variant
	var bark := SurfaceTool.new()
	bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	var twig := SurfaceTool.new()
	twig.begin(Mesh.PRIMITIVE_TRIANGLES)
	var fork := rng.randf_range(0.3, 0.4)
	var top := Vector3(rng.randf_range(-0.02, 0.02), fork, rng.randf_range(-0.02, 0.02))
	var center := Vector3(0, 0.62, 0)
	_tube(bark, Vector3(0, -0.05, 0), top, 0.034, 0.024, 7, 0.0, 6.0)
	var limbs := 4 + rng.randi() % 2
	var spin := rng.randf() * TAU
	for li in limbs:
		spin += TAU / limbs + rng.randf_range(-0.3, 0.3)
		var tilt := deg_to_rad(rng.randf_range(24.0, 50.0))
		var dir := Vector3(cos(spin) * sin(tilt), cos(tilt), sin(spin) * sin(tilt))
		var start := top + Vector3(0, rng.randf_range(-0.03, 0.04), 0)
		var len := rng.randf_range(0.3, 0.42)
		var mid := start + dir * len * 0.55 + Vector3(rng.randf_range(-0.03, 0.03), 0.02, rng.randf_range(-0.03, 0.03))
		var end := mid + (dir + Vector3(0, 0.25, 0)).normalized() * len * 0.5
		var v := _tube(bark, start, mid, 0.017, 0.011, 5, 0.0, 6.0)
		_tube(bark, mid, end, 0.011, 0.005, 4, v, 6.0)
		_twigs(twig, end, (dir + Vector3(0, 0.6, 0)).normalized(), 0.26, center, rng)
		for si in 2:
			var a := spin + (1.0 if si == 0 else -1.0) * rng.randf_range(0.5, 1.0)
			var sd := (Vector3(cos(a) * 0.8, 0.9, sin(a) * 0.8)).normalized()
			var base := mid if si == 0 else start.lerp(mid, 0.5)
			var se := base + sd * rng.randf_range(0.16, 0.24)
			_tube(bark, base, se, 0.008, 0.003, 4, 0.0, 6.0)
			_twigs(twig, se, sd, 0.22, center, rng)
	_twigs(twig, top + Vector3(0, 0.45, 0), Vector3.UP, 0.24, center, rng)   # 树冠顶上
	var mesh := ArrayMesh.new()
	bark.commit(mesh)
	twig.commit(mesh)
	_meshes[key] = mesh
	return mesh


## 一簇细枝：两片交叉、根往回缩一点（接在枝头上）
static func _twigs(st: SurfaceTool, tip: Vector3, dir: Vector3, size: float, center: Vector3, rng: RandomNumberGenerator) -> void:
	var up := (dir + Vector3(0, 0.5, 0)).normalized()
	var root := tip - up * size * 0.25
	var ref := Vector3.RIGHT if absf(up.x) < 0.8 else Vector3.BACK
	var s1 := up.cross(ref).normalized().rotated(up, rng.randf() * PI)
	var s2 := s1.rotated(up, PI * 0.5)
	_card(st, root, up, s1, size, size * 1.1, 0, center)
	_card(st, root, up, s2, size, size * 1.1, 0, center)


## 截头柳（米）：粗短的树干、鼓起来的树头、四片交叉的柳条
static func willow_mesh(variant: int) -> ArrayMesh:
	var key := "willow%d" % variant
	if _meshes.has(key):
		return _meshes[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 6300 + variant
	var bark := SurfaceTool.new()
	bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lean := Vector3(rng.randf_range(0.15, 0.4), 0.0, rng.randf_range(-0.1, 0.1))
	var h := 2.3 if variant == 0 else 2.0
	var v := _tube(bark, Vector3(0, -0.15, 0), Vector3(0, 0.6, 0) + lean * 0.3, 0.42, 0.33, 8, 0.0, 0.8)
	v = _tube(bark, Vector3(0, 0.6, 0) + lean * 0.3, Vector3(0, h, 0) + lean, 0.33, 0.36, 8, v, 0.8)
	var head := Vector3(0, h, 0) + lean
	v = _tube(bark, head, head + Vector3(0, 0.32, 0), 0.36, 0.46, 8, v, 0.8)       # 年年截枝，树头鼓成一个疙瘩
	_tube(bark, head + Vector3(0, 0.32, 0), head + Vector3(0, 0.5, 0), 0.46, 0.2, 8, v, 0.8)
	var twig := SurfaceTool.new()
	twig.begin(Mesh.PRIMITIVE_TRIANGLES)
	var root := head + Vector3(0, 0.3, 0)
	var center := root + Vector3(0, 1.2, 0)
	var spin := rng.randf() * PI
	for i in 4:
		var a := spin + PI * i / 4.0
		var side := Vector3(cos(a), 0, sin(a))
		_card(twig, root, Vector3.UP, side, rng.randf_range(3.0, 3.6), rng.randf_range(3.2, 3.8), 1, center)
	var mesh := ArrayMesh.new()
	bark.commit(mesh)
	twig.commit(mesh)
	_meshes[key] = mesh
	return mesh


## 篱笆里的一丛灌木（米）：三片交叉的细枝片
static func shrub_mesh() -> ArrayMesh:
	if _meshes.has("shrub"):
		return _meshes.shrub
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := Vector3(0, 0.8, 0)
	for i in 3:
		var a := PI * i / 3.0
		_card(st, Vector3(0, -0.15, 0), Vector3.UP, Vector3(cos(a), 0, sin(a)), 2.0, 2.3, 0, center)
	var mesh := st.commit()
	_meshes.shrub = mesh
	return mesh


## 远处的树（高 1）：两片交叉的整棵树剪影
static func far_card_mesh() -> ArrayMesh:
	if _meshes.has("far"):
		return _meshes.far
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := Vector3(0, 0.6, 0)
	_card(st, Vector3(0, -0.02, 0), Vector3.UP, Vector3.RIGHT, 1.0, 1.0, 2, center)
	_card(st, Vector3(0, -0.02, 0), Vector3.UP, Vector3.BACK, 1.0, 1.0, 2, center)
	var mesh := st.commit()
	_meshes.far = mesh
	return mesh


## 麦垛（米，大小 1 = 直径 4.2、高 4.3）：车床旋出来；村里的那种矮、被扯掉一角（一侧往里凹）
static func rick_mesh(village: bool) -> ArrayMesh:
	var key := "rick_v" if village else "rick"
	if _meshes.has(key):
		return _meshes[key]
	var prof := [Vector2(1.95, -0.2), Vector2(2.1, 0.3), Vector2(2.12, 1.2), Vector2(2.05, 2.0), Vector2(1.75, 2.6), Vector2(1.25, 3.25), Vector2(0.65, 3.85), Vector2(0.18, 4.25), Vector2(0.0, 4.32)]
	if village:
		prof = [Vector2(1.9, -0.2), Vector2(2.0, 0.3), Vector2(1.95, 1.1), Vector2(1.7, 1.7), Vector2(1.2, 2.3), Vector2(0.6, 2.8), Vector2(0.0, 3.0)]
	var seg := 16
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ring := func(i: int, j: int) -> Vector3:
		var a := TAU * float(i % seg) / seg
		var r: float = (prof[j] as Vector2).x
		var y: float = (prof[j] as Vector2).y
		if village:
			var bite := maxf(0.0, cos(a - 0.6)) # 扯掉的那一角
			r *= 1.0 - 0.45 * pow(bite, 3.0) * clampf(1.2 - y / 2.5, 0.0, 1.0)
		var wob := 1.0 + 0.04 * sin(a * 3.0 + y * 2.0)
		return Vector3(cos(a) * r * wob, y, sin(a) * r * wob)
	for j in prof.size() - 1:
		var pa: Vector2 = prof[j]
		var pb: Vector2 = prof[j + 1]
		var tg := (pb - pa).normalized()
		for i in seg:
			var q := [ring.call(i, j), ring.call(i + 1, j), ring.call(i + 1, j + 1), ring.call(i, j + 1)]
			var uv := [Vector2(float(i) / seg, pa.y), Vector2(float(i + 1) / seg, pa.y), Vector2(float(i + 1) / seg, pb.y), Vector2(float(i) / seg, pb.y)]
			for k in [0, 1, 2, 0, 2, 3]:
				var a := TAU * float((i + (1 if k in [1, 2] else 0)) % seg) / seg
				st.set_normal(Vector3(cos(a) * tg.y, -tg.x, sin(a) * tg.y).normalized())     # 轮廓切线 (dr, dy) 的外法线 (dy, −dr)
				st.set_uv(uv[k])
				st.set_color(Color(0.0, 1.0, 0.0))
				st.add_vertex(q[k])
	var mesh := st.commit()
	_meshes[key] = mesh
	return mesh


## 木栅的一跨（米）：沿 +X 长 FENCE_BAY：起点一根柱子 + 两根横木
static func fence_mesh() -> ArrayMesh:
	if _meshes.has("fence"):
		return _meshes.fence
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_tube(st, Vector3(0, -0.3, 0), Vector3(0, 1.25, 0), 0.08, 0.07, 6, 0.0, 1.0)
	_tube(st, Vector3(-0.05, 0.55, 0.06), Vector3(FENCE_BAY + 0.05, 0.53, 0.06), 0.045, 0.045, 5, 0.0, 1.0)
	_tube(st, Vector3(-0.05, 1.02, 0.06), Vector3(FENCE_BAY + 0.05, 1.0, 0.06), 0.045, 0.045, 5, 0.0, 1.0)
	var mesh := st.commit()
	_meshes.fence = mesh
	return mesh


# ---------------- 材质 ----------------

## bark：树皮（树干、枝、柳树干、木栅），朝上的面积雪；twig：枝条片（透明处剪掉、风摆、朝上的落一点雪）；straw：麦垛（麦秆的竖纹、顶上积雪）
static func material(kind: String, reduced_motion := false) -> ShaderMaterial:
	if not _mats.has(kind):
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/plain_flora.gdshader")
		m.set_shader_parameter("mode", {"bark": 0, "twig": 1, "straw": 2}[kind])
		m.set_shader_parameter("noise_tex", Look.noise_texture())
		var bm := Look.mat("bark")
		m.set_shader_parameter("bark_tex", bm.albedo_texture if bm.albedo_texture != null else Plain._flat(Color("3a3430")))
		var t: Texture2D = load(TWIG_TEX) as Texture2D if ResourceLoader.exists(TWIG_TEX) else null
		m.set_shader_parameter("twig_tex", t if t != null else Plain._flat(Color(0.3, 0.27, 0.24)))
		_mats[kind] = m
	(_mats[kind] as ShaderMaterial).set_shader_parameter("wind", 0.0 if reduced_motion else 1.0)
	return _mats[kind]


# ---------------- 搭 ----------------

static func _mm(root: Node3D, name: String, mesh: Mesh, list: Array, origin: Vector3, xf_of: Callable, begin: float, end: float, shadow: bool) -> void:
	if list.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = list.size()
	for i in list.size():
		var it: Array = list[i]
		mm.set_instance_transform(i, xf_of.call(it).translated(-origin))
		mm.set_instance_custom_data(i, Color(float(it[4]) if it.size() > 4 else 0.5, float(it[5]) if it.size() > 5 else 0.8, float(it[6]) if it.size() > 6 else 0.0, 0.0))
	var mi := MultiMeshInstance3D.new()
	mi.name = name
	mi.multimesh = mm
	mi.position = origin
	if begin > 0.0:
		mi.visibility_range_begin = begin
		mi.visibility_range_begin_margin = 6.0
	if end > 0.0:
		mi.visibility_range_end = end
		mi.visibility_range_end_margin = 6.0
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.add_to_group("plain_flora")
	root.add_child(mi)


static func _in(list: Array, r: Rect2) -> Array:
	var out := []
	for it: Array in list:
		var p: Vector3 = it[0]
		if r.has_point(Vector2(p.x, p.z)):
			out.append(it)
	return out


static func _scaled(it: Array) -> Transform3D:
	var s := float(it[2])
	return Transform3D(Basis(Vector3.UP, float(it[1])).scaled(Vector3(s, s, s)), it[0])


## 一块里的东西（ChunkStreamer 的一件活）
static func build_chunk(root: Node3D, r: Rect2, reduced_motion: bool) -> void:
	var c := r.get_center()
	var origin := Vector3(c.x, 0.0, c.y)
	var bark := material("bark", reduced_motion)
	var twig := material("twig", reduced_motion)
	var ts := _in(trees(), r)
	for v in 3:
		var list := ts.filter(func(t: Array) -> bool: return int(t[3]) == v)
		var m := tree_mesh(v)
		m.surface_set_material(0, bark)
		m.surface_set_material(1, twig)
		_mm(root, "Trees%d" % v, m, list, origin, _scaled, 0.0, TREE_LOD + 6.0, true)
	var fm := far_card_mesh()
	fm.surface_set_material(0, twig)
	_mm(root, "TreesFar", fm, ts, origin, _scaled, TREE_LOD, TREE_FAR, false)
	var ws := _in(willows(), r)
	for v in 2:
		var m := willow_mesh(v)
		m.surface_set_material(0, bark)
		m.surface_set_material(1, twig)
		_mm(root, "Willows%d" % v, m, ws.filter(func(t: Array) -> bool: return int(t[3]) == v), origin, _scaled, 0.0, WILLOW_FAR, true)
	var sm := shrub_mesh()
	sm.surface_set_material(0, twig)
	_mm(root, "Hedges", sm, _in(hedges(), r), origin, _scaled, 0.0, HEDGE_FAR, false)
	var rs := _in(ricks(), r)
	for village in [false, true]:
		var m := rick_mesh(village)
		m.surface_set_material(0, material("straw", reduced_motion))
		_mm(root, "Ricks" + ("Village" if village else ""), m, rs.filter(func(t: Array) -> bool: return bool(t[3]) == village), origin, _scaled, 0.0, RICK_FAR, true)
	var fs := []
	for f: Array in fences():
		var a: Vector3 = f[0]
		if r.has_point(Vector2(a.x, a.z)):
			fs.append(f)
	var fe := fence_mesh()
	fe.surface_set_material(0, bark)
	_mm(root, "Fence", fe, fs, origin, func(f: Array) -> Transform3D:
		var a: Vector3 = f[0]
		var b: Vector3 = f[1]
		var d := b - a
		var x := d.normalized()
		var z := x.cross(Vector3.UP).normalized()
		var y := z.cross(x).normalized()
		return Transform3D(Basis(x * (d.length() / FENCE_BAY), y, z), a), 0.0, FENCE_FAR, false)


## 地图外面那几百棵树：一个多实例画完
static func far_ring(parent: Node3D) -> void:
	var m := far_card_mesh().duplicate() as ArrayMesh
	m.surface_set_material(0, material("twig"))
	var list := []
	for t: Array in far_trees():
		list.append([t[0], t[1], t[2], 0, t[3], 0.6, 0.0])
	_mm(parent, "FarTrees", m, list, Vector3.ZERO, _scaled, 0.0, 0.0, false)


## 碰撞：树干、柳树干、麦垛是圆柱，篱笆每段、木栅每跨是一个薄盒子
static func add_collision(body: StaticBody3D) -> void:
	var trunk := CylinderShape3D.new()
	trunk.radius = 0.3
	trunk.height = 3.0
	for t: Array in trees() + willows():
		var cs := CollisionShape3D.new()
		cs.shape = trunk
		cs.position = (t[0] as Vector3) + Vector3(0, 1.5, 0)
		body.add_child(cs)
	for rk: Array in ricks():
		var cs := CollisionShape3D.new()
		var cy := CylinderShape3D.new()
		cy.radius = 2.0 * float(rk[2])
		cy.height = 3.0 * float(rk[2])
		cs.shape = cy
		cs.position = (rk[0] as Vector3) + Vector3(0, cy.height * 0.5, 0)
		body.add_child(cs)
	for run: Array in hedge_runs():
		_wall(body, run[0], run[1], 0.9, 1.4)
	for f: Array in fences():
		var a: Vector3 = f[0]
		var b: Vector3 = f[1]
		_wall(body, Vector2(a.x, a.z), Vector2(b.x, b.z), 0.25, 1.2)


static func _wall(body: StaticBody3D, a: Vector2, b: Vector2, thick: float, h: float) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	var len := a.distance_to(b) + thick
	bs.size = Vector3(len, h, thick)
	cs.shape = bs
	var m := (a + b) * 0.5
	var y := PlainLayout.height(m.x, m.y)
	cs.position = Vector3(m.x, y + h * 0.5, m.y)
	cs.rotation.y = -atan2(b.y - a.y, b.x - a.x)
	body.add_child(cs)
