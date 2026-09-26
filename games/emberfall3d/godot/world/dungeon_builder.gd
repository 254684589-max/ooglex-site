class_name DungeonBuilder
extends RefCounted
## 把 DungeonGen 的格子布局搭成 3D 关卡（阶段 P2）。
## - 1 格 = 2 米（V0.1 的房间 5–10 格 → 10–20 米，走廊 2 格 → 4 米宽，与灰盒大厅的门同宽）；墙高 3.2 米。
## - 地面与墙按 4 × 4 格分块合并成网格：一块一次绘制调用，屏幕外的块被视锥剔除；
##   每块墙有自己的材质，相机只把挡住主角的那一块变半透明。墙只画朝向非墙格子的面和顶面。
## - 碰撞：每块一个静态体，同一行连续的格子合并成一个盒子。
## - 导航：直接用格子生成烘焙源几何（不从节点解析），整层一次同步烘焙（网页实测约 40 毫秒）。
## - 装饰（白骨、碎石、熔岩裂缝）用 MultiMesh，每种一次绘制调用。
## - 2.6 样板间（纯代码）：墙脚石基（带倒角）、墙顶压檐、墙角与门洞两侧和长墙每 6 米一根壁柱（柱础 + 柱身 + 柱头），
##   两种件各只生成一次网格，每块墙用 MultiMesh 摆放（每块多 1–2 次绘制调用，但搭建几乎不花时间），
##   和墙共用同一个材质：跟着墙一起半透明，也一起被迷雾藏起；
##   地面每格细分成 2 × 2，顶点色做「环境光遮蔽」：靠墙的地面、墙脚更暗，房间不再像平铺的贴图。

const TILE := 2.0
const WALL_H := 3.2
const CHUNK := 4
const WORLD_MASK := Layers.WORLD | Layers.OCCLUDER
const AO_FLOOR := 0.42          # 贴墙那条地面边的亮度（1 = 不遮蔽）
const AO_REACH := 1.3           # 遮蔽从墙边向外延伸的距离（米）
const PILASTER_EVERY := 3       # 长墙上每隔几格（1 格 2 米）立一根壁柱

static var _face_mesh: ArrayMesh       # 一面墙（2 米宽）：遮蔽渐变的墙面 + 石基 + 倒角 + 压檐，面朝 +Z，面中心在原点
static var _pilaster_mesh: ArrayMesh   # 一根壁柱，立在原点


static func face_mesh() -> ArrayMesh:
	if _face_mesh == null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_wall_face(st, Vector3(0, 0, -TILE / 2), Vector3.BACK)
		_face_mesh = st.commit()
	return _face_mesh


static func pilaster_mesh() -> ArrayMesh:
	if _pilaster_mesh == null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_pilaster(st, 0, 0)
		_pilaster_mesh = st.commit()
	return _pilaster_mesh


static func _multi(mesh: Mesh, xforms: Array, mat: Material, name: String) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.name = name
	return mmi



static func cell_center(c: Vector2i) -> Vector3:
	return Vector3((c.x + 0.5) * TILE, 0.0, (c.y + 0.5) * TILE)


static func world_to_cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / TILE), floori(p.z / TILE))


## 主题染色：以修道院地窖为 1.0，按 V0.1 的地面 / 墙面颜色换算
static func theme_tints(theme: String) -> Dictionary:
	var th: Dictionary = Act1Data.rules().floors.themes
	var base_f: Array = th.crypt.floor_rgb
	var f: Array = th[theme].floor_rgb
	var base_w := Color(th.crypt.wall_hex)
	var w := Color(th[theme].wall_hex)
	return {
		"floor": Color(f[0] / base_f[0], f[1] / base_f[1], f[2] / base_f[2]) * Color(0.85, 0.82, 0.8),
		"wall": Color(w.r / base_w.r, w.g / base_w.g, w.b / base_w.b),
	}


## opt：seed（装饰随机）、on_stairs（Callable(kind)）、down_caption / up_caption、open_boss_stairs（首领层的下楼梯是否直接出现：P9 起只在首领已被击败时为 true）、
##   fog（P10 战争迷雾：地面、墙、装饰、火把先藏起来，按 4 × 4 格的块在走近看见后用 reveal_chunk 显示）
static func build(parent: Node3D, m: Dictionary, opt: Dictionary = {}) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var tints := theme_tints(m.theme)
	var region := NavBuilder.make_region()
	region.name = "Level"
	parent.add_child(region)
	var w: int = m.w
	var h: int = m.h
	var t: PackedByteArray = m.t
	var floor_mat: Material = opt.get("floor_material", Look._triplanar(Look.floor_texture(), 4.0, tints.floor, Look.floor_normal()))
	var pillars_used := {}            # 已经立过壁柱的格点（相邻两面墙、跨块时都只立一根）
	var chunks := 0
	var fog: Dictionary = {}          # 块坐标 → {meshes, deco: [[多实例网格, 下标, 变换]], torches}（只在 opt.fog 时填）
	var use_fog: bool = opt.get("fog", false)
	if use_fog:
		fog["_on"] = true
	for cy in ceili(h / float(CHUNK)):
		for cx in ceili(w / float(CHUNK)):
			if _build_chunk(region, m, cx, cy, floor_mat, tints.wall, fog if use_fog else {}, pillars_used):
				chunks += 1
	var geo_ms := (Time.get_ticks_usec() - t0) / 1000.0

	# 导航：由格子直接生成源几何
	var t1 := Time.get_ticks_usec()
	var src := NavigationMeshSourceGeometryData3D.new()
	for y in h:
		var x := 0
		while x < w:
			var k := _kind(t[y * w + x])
			var x1 := x
			while x1 + 1 < w and _kind(t[y * w + x1 + 1]) == k:
				x1 += 1
			var x0m := x * TILE
			var x1m := (x1 + 1) * TILE
			var z0m := y * TILE
			var z1m := (y + 1) * TILE
			# 与测试区一致：地面是顶面在 y = 0、厚 0.2 米的薄板（与点击用的地面碰撞体同形）。
			# 零厚度的面片烘焙出的导航面会高出地面约 0.5 米，NavigationAgent 按三维距离判断「到达路径点」（阈值 0.35 米），
			# 主角会卡在第一个路径点不动（P2 实测）。盒子直接写成三角形，不用 add_mesh（那会从显卡回读网格，很慢）。
			if k == 2:
				_box_faces(src, Vector3(x0m, 0, z0m), Vector3(x1m, WALL_H, z1m))
			elif k == 1:
				_box_faces(src, Vector3(x0m, -0.2, z0m), Vector3(x1m, 0, z1m))
			x = x1 + 1
	# 额外的障碍物（烬原镇的篝火、水井、铁砧、传送石）：导航避开，并加碰撞
	var obstacles: Array = opt.get("obstacles", [])
	if not obstacles.is_empty():
		var ob := StaticBody3D.new()
		ob.name = "Obstacles"
		ob.collision_layer = Layers.WORLD
		ob.collision_mask = 0
		region.add_child(ob)
		for o in obstacles:
			var sz: Vector3 = o.size
			var c: Vector3 = o.pos
			# 导航源按墙高：矮道具（篝火 0.6 米）顶面会被烘成可走面
			_box_faces(src, c - Vector3(sz.x / 2, 0, sz.z / 2), c + Vector3(sz.x / 2, maxf(sz.y, WALL_H), sz.z / 2))
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = sz
			cs.shape = bs
			cs.position = c + Vector3(0, sz.y / 2, 0)
			ob.add_child(cs)
	var nm := NavBuilder.make_navmesh()
	NavigationServer3D.bake_from_source_geometry_data(nm, src, Callable())
	region.navigation_mesh = nm
	var nav_ms := (Time.get_ticks_usec() - t1) / 1000.0

	# 装饰
	var rng := RandomNumberGenerator.new()
	rng.seed = int(opt.get("seed", 1)) ^ 0x5eed
	_build_deco(region, m, rng, fog if use_fog else {})

	# 火把
	var torches: Array[Torch] = []
	for tc in m.torches:
		var c: Vector2i = tc.cell
		var f: Vector2i = tc.face
		var tch := Torch.new()
		parent.add_child(tch)
		tch.position = cell_center(c) + Vector3(f.x, 0, f.y) * (TILE / 2 + 0.12) + Vector3(0, 1.8, 0)
		tch.light.distance_fade_enabled = true
		tch.light.distance_fade_begin = 22.0
		tch.light.distance_fade_length = 6.0
		torches.append(tch)
		if use_fog:
			_fog_add(fog, c / CHUNK, "torches", tch)
			tch.visible = false

	# 楼梯
	var stairs := {}
	var down_cell: Vector2i = m.down
	if down_cell.x < 0 and opt.get("open_boss_stairs", false):
		down_cell = m.boss_stairs
	if down_cell.x >= 0:
		stairs.down = _stairs(parent, "down", opt.get("down_caption", "↓ 下一层"), down_cell, opt.get("on_stairs", Callable()))
	if m.up.x >= 0:
		stairs.up = _stairs(parent, "up", opt.get("up_caption", "↑ 上一层"), m.up, opt.get("on_stairs", Callable()))

	return {"region": region, "torches": torches, "stairs": stairs, "down_cell": down_cell, "chunks": chunks, "fog": fog, "pillars": pillars_used.keys(),
		"geo_ms": geo_ms, "nav_ms": nav_ms, "build_ms": (Time.get_ticks_usec() - t0) / 1000.0}


## 轴对齐盒子的 12 个三角形（导航烘焙源几何用）
static func _box_faces(src: NavigationMeshSourceGeometryData3D, lo: Vector3, hi: Vector3) -> void:
	var c := [Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, lo.y, hi.z),
		Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z)]
	var faces := PackedVector3Array()
	for q in [[4, 5, 6, 7], [3, 2, 1, 0], [0, 1, 5, 4], [2, 3, 7, 6], [1, 2, 6, 5], [3, 0, 4, 7]]:
		faces.append_array([c[q[0]], c[q[1]], c[q[2]], c[q[0]], c[q[2]], c[q[3]]])
	src.add_faces(faces, Transform3D.IDENTITY)


## 格子分三类：0 空、1 可走（地面与楼梯）、2 墙
static func _kind(tt: int) -> int:
	return 1 if DungeonGen.walkable(tt) else (2 if tt == DungeonGen.WALL else 0)


static func _stairs(parent: Node3D, kind: String, caption: String, c: Vector2i, cb: Callable) -> Stairs:
	var s := Stairs.make(kind, caption)
	parent.add_child(s)
	s.position = cell_center(c)
	if cb.is_valid():
		s.used.connect(cb)
	return s


static func _quad(st: SurfaceTool, c: Vector3, n: Vector3, v: Vector3, hu: float, hv: float, shade := -1.0) -> void:
	## 一个朝外法线为 n 的矩形面：从外面看，v 朝上、u = v × n 朝右，按顺时针（Godot 的正面）出两个三角形
	var u := v.cross(n)
	var tl := c - u * hu + v * hv
	var tr := c + u * hu + v * hv
	var br := c + u * hu - v * hv
	var bl := c - u * hu - v * hv
	for p in [tl, tr, br, tl, br, bl]:
		st.set_normal(n)
		if shade >= 0.0:
			st.set_color(Color(shade, shade, shade))
		st.add_vertex(p)


## 带顶点色的矩形面（顶点色 = 遮蔽亮度）：ctop 上边、cbot 下边
static func _quad_c(st: SurfaceTool, c: Vector3, n: Vector3, v: Vector3, hu: float, hv: float, ctop: float, cbot: float) -> void:
	var u := v.cross(n)
	var tl := c - u * hu + v * hv
	var tr := c + u * hu + v * hv
	var br := c + u * hu - v * hv
	var bl := c - u * hu - v * hv
	var a := Color(ctop, ctop, ctop)
	var b := Color(cbot, cbot, cbot)
	for pc in [[tl, a], [tr, a], [br, b], [tl, a], [br, b], [bl, b]]:
		st.set_normal(n)
		st.set_color(pc[1])
		st.add_vertex(pc[0])


## 四个角各自一个顶点色的矩形面：p0..p3 沿边依次给出，绕向自动按法线 n 调成 Godot 的正面（从外面看顺时针）
static func _quad4(st: SurfaceTool, n: Vector3, pts: Array, cols: Array) -> void:
	var order := [0, 1, 2, 0, 2, 3]
	if (pts[1] - pts[0]).cross(pts[2] - pts[0]).dot(n) > 0.0:
		order = [0, 2, 1, 0, 3, 2]
	for i in order:
		st.set_normal(n)
		var k: float = cols[i]
		st.set_color(Color(k, k, k))
		st.add_vertex(pts[i])


## 贴地的点离最近的墙格有多远 → 遮蔽亮度
static func _floor_ao(m: Dictionary, p: Vector3) -> float:
	var cx := floori(p.x / TILE)
	var cy := floori(p.z / TILE)
	var best := AO_REACH
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var gx := cx + dx
			var gy := cy + dy
			if DungeonGen.tile(m, gx, gy) != DungeonGen.WALL:
				continue
			var qx := clampf(p.x, gx * TILE, (gx + 1) * TILE)
			var qz := clampf(p.z, gy * TILE, (gy + 1) * TILE)
			best = minf(best, Vector2(p.x - qx, p.z - qz).length())
	var t := clampf(best / AO_REACH, 0.0, 1.0)
	return lerpf(AO_FLOOR, 1.0, t * t * (3.0 - 2.0 * t))


## 轴对齐盒子（不画底面），侧面上下两端的顶点色分别是 ctop / cbot
static func _box(st: SurfaceTool, c: Vector3, sz: Vector3, ctop: float, cbot: float) -> void:
	var h := sz / 2.0
	_quad_c(st, c + Vector3(0, h.y, 0), Vector3.UP, Vector3.FORWARD, h.x, h.z, ctop, ctop)
	_quad_c(st, c + Vector3(h.x, 0, 0), Vector3.RIGHT, Vector3.UP, h.z, h.y, ctop, cbot)
	_quad_c(st, c - Vector3(h.x, 0, 0), Vector3.LEFT, Vector3.UP, h.z, h.y, ctop, cbot)
	_quad_c(st, c + Vector3(0, 0, h.z), Vector3.BACK, Vector3.UP, h.x, h.y, ctop, cbot)
	_quad_c(st, c - Vector3(0, 0, h.z), Vector3.FORWARD, Vector3.UP, h.x, h.y, ctop, cbot)


## 壁柱：柱础 + 柱身 + 柱头，立在格点（格子的角）上，一半嵌在墙里
static func _pilaster(st: SurfaceTool, gx: int, gy: int) -> void:
	var base := Vector3(gx * TILE, 0, gy * TILE)
	_box(st, base + Vector3(0, 0.2, 0), Vector3(0.78, 0.4, 0.78), 0.62, 0.4)          # 柱础
	_box(st, base + Vector3(0, 1.76, 0), Vector3(0.54, 2.5, 0.54), 1.0, 0.7)          # 柱身
	_box(st, base + Vector3(0, 3.08, 0), Vector3(0.7, 0.24, 0.7), 0.85, 0.75)         # 柱头（顶面与墙顶齐平）


## 墙面：下部遮蔽渐变 + 墙脚石基（正面 + 倒角斜面）+ 墙顶压檐。cc 为墙格中心，n 为朝外法线
static func _wall_face(st: SurfaceTool, cc: Vector3, n: Vector3) -> void:
	var f := cc + n * (TILE / 2)
	var low := 1.1
	# 墙面整体比壁柱暗一档（0.8），壁柱才从墙上「站出来」
	_quad_c(st, f + Vector3(0, low / 2, 0), n, Vector3.UP, TILE / 2, low / 2, 0.72, 0.45)
	_quad_c(st, f + Vector3(0, low + (WALL_H - low) / 2, 0), n, Vector3.UP, TILE / 2, (WALL_H - low) / 2, 0.8, 0.72)
	# 石基：高 0.28 米、外凸 0.12 米的正面，上面一条 0.12 米高的倒角斜面收回墙面
	var out := 0.12
	_quad_c(st, f + n * out + Vector3(0, 0.14, 0), n, Vector3.UP, TILE / 2, 0.14, 0.62, 0.42)
	var u := Vector3.UP.cross(n)
	var p0 := f + n * out + Vector3(0, 0.28, 0)
	var p1 := f + Vector3(0, 0.4, 0)
	var sn := (n + Vector3.UP).normalized()
	_quad4(st, sn, [p1 - u * (TILE / 2), p1 + u * (TILE / 2), p0 + u * (TILE / 2), p0 - u * (TILE / 2)], [0.66, 0.66, 0.64, 0.64])
	# 压檐：墙顶外凸 0.08 米的一圈（正面 + 底面），让墙顶有厚度
	var lip := 0.08
	_quad_c(st, f + n * lip + Vector3(0, WALL_H - 0.09, 0), n, Vector3.UP, TILE / 2, 0.09, 0.9, 0.8)
	var q0 := f + Vector3(0, WALL_H - 0.18, 0)
	var q1 := f + n * lip + Vector3(0, WALL_H - 0.18, 0)
	_quad4(st, Vector3.DOWN, [q0 - u * (TILE / 2), q0 + u * (TILE / 2), q1 + u * (TILE / 2), q1 - u * (TILE / 2)], [0.55, 0.55, 0.55, 0.55])
	var t0 := f + Vector3(0, WALL_H, 0)
	var t1 := f + n * lip + Vector3(0, WALL_H, 0)
	_quad4(st, Vector3.UP, [t0 + u * (TILE / 2), t0 - u * (TILE / 2), t1 - u * (TILE / 2), t1 + u * (TILE / 2)], [0.9, 0.9, 0.9, 0.9])


## 这面墙两端的格点要不要立壁柱：墙到头（门洞、外角）、内角、长墙每隔 PILASTER_EVERY 格
static func _face_pillars(m: Dictionary, x: int, y: int, d: Vector2i, used: Dictionary) -> Array:
	var out: Array = []
	var u := Vector2i(-d.y, d.x)
	for sgn in [-1, 1]:
		var s: Vector2i = u * int(sgn)
		# 格点坐标（格子角）：面中心 = 格子中心 + d/2，端点 = 面中心 + s/2
		var gx := int(round(x + 0.5 + d.x * 0.5 + s.x * 0.5))
		var gy := int(round(y + 0.5 + d.y * 0.5 + s.y * 0.5))
		var key := Vector2i(gx, gy)
		if used.has(key):
			continue
		var nb: Vector2i = Vector2i(x, y) + s
		var want := false
		if DungeonGen.tile(m, nb.x, nb.y) != DungeonGen.WALL:
			want = true                                   # 墙到头：门洞两侧、外角
		elif DungeonGen.tile(m, nb.x + d.x, nb.y + d.y) == DungeonGen.WALL:
			want = true                                   # 内角
		elif posmod(gx + gy, PILASTER_EVERY) == 0:
			want = true                                   # 长墙上的节奏
		if want:
			used[key] = true
			out.append(key)
	return out


static func _build_chunk(region: Node3D, m: Dictionary, cx: int, cy: int, floor_mat: Material, wall_tint: Color, fog: Dictionary = {}, pillars_used: Dictionary = {}) -> bool:
	var w: int = m.w
	var t: PackedByteArray = m.t
	var fst := SurfaceTool.new()
	fst.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wst := SurfaceTool.new()
	wst.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n_floor := 0
	var n_wall := 0
	var ground_runs: Array = []
	var wall_runs: Array = []
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var ao_cache := {}                # 半格格点 → 遮蔽亮度（相邻小块共用顶点，只算一次）
	var face_xf: Array = []
	var pil_xf: Array = []
	for y in range(cy * CHUNK, mini((cy + 1) * CHUNK, m.h)):
		var run_kind := -1
		var run_start := 0
		for x in range(cx * CHUNK, mini((cx + 1) * CHUNK, w) + 1):
			var tt := DungeonGen.tile(m, x, y) if x < mini((cx + 1) * CHUNK, w) else DungeonGen.VOID
			var k := _kind(tt)
			if k != run_kind:
				if run_kind == 1:
					ground_runs.append([run_start, x - 1, y])
				elif run_kind == 2:
					wall_runs.append([run_start, x - 1, y])
				run_kind = k
				run_start = x
			if x >= mini((cx + 1) * CHUNK, w):
				break
			var cc := cell_center(Vector2i(x, y))
			if DungeonGen.walkable(tt) and tt != DungeonGen.DOWN:
				# 靠墙的格子细分成 2 × 2，四角按离墙远近写遮蔽亮度；周围 8 格都没有墙的格子离墙至少 2 米，不遮蔽，一个整面就够
				var near_wall := false
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						if DungeonGen.tile(m, x + dx, y + dy) == DungeonGen.WALL:
							near_wall = true
				if not near_wall:
					_quad(fst, cc, Vector3.UP, Vector3.FORWARD, TILE / 2, TILE / 2, 1.0)
					n_floor += 1
					continue
				var x0 := x * TILE
				var z0 := y * TILE
				var hs := TILE / 2
				for sy in 2:
					for sx in 2:
						var a := Vector3(x0 + sx * hs, 0, z0 + sy * hs)
						var pts := [a, a + Vector3(hs, 0, 0), a + Vector3(hs, 0, hs), a + Vector3(0, 0, hs)]
						var cols := []
						for pp in pts:
							var key := Vector2i(roundi(pp.x / hs), roundi(pp.z / hs))
							if not ao_cache.has(key):
								ao_cache[key] = _floor_ao(m, pp)
							cols.append(ao_cache[key])
						_quad4(fst, Vector3.UP, pts, cols)
				n_floor += 1
			elif tt == DungeonGen.WALL:
				_quad_c(wst, cc + Vector3(0, WALL_H, 0), Vector3.UP, Vector3.FORWARD, TILE / 2, TILE / 2, 0.8, 0.8)
				for d in dirs:
					if DungeonGen.walkable(DungeonGen.tile(m, x + d.x, y + d.y)):
						var nf := Vector3(d.x, 0, d.y)
						face_xf.append(Transform3D(Basis(Vector3.UP, atan2(nf.x, nf.z)), cc + nf * (TILE / 2)))
						for g in _face_pillars(m, x, y, d, pillars_used):
							pil_xf.append(Transform3D(Basis.IDENTITY, Vector3(g.x * TILE, 0, g.y * TILE)))
					elif DungeonGen.tile(m, x + d.x, y + d.y) != DungeonGen.WALL:
						var n := Vector3(d.x, 0, d.y)
						_quad_c(wst, cc + n * (TILE / 2) + Vector3(0, WALL_H / 2, 0), n, Vector3.UP, TILE / 2, WALL_H / 2, 0.8, 0.8)
				n_wall += 1
	if n_floor == 0 and n_wall == 0:
		return false
	if n_floor > 0:
		var fmi := MeshInstance3D.new()
		fmi.mesh = fst.commit()
		fmi.material_override = floor_mat
		fmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # 地面在最底下，投影没用，省掉阴影绘制
		fmi.name = "Floor_%d_%d" % [cx, cy]
		var gbody := StaticBody3D.new()
		gbody.collision_layer = Layers.GROUND
		gbody.collision_mask = 0
		for r in ground_runs:
			_add_run_box(gbody, r, 0.2, -0.1)
		gbody.add_child(fmi)
		region.add_child(gbody)
		_fog_add(fog, Vector2i(cx, cy), "meshes", fmi)
	if n_wall > 0:
		var wmi := MeshInstance3D.new()
		wmi.mesh = wst.commit()
		wmi.material_override = Look.wall_material(wall_tint)
		wmi.name = "Walls_%d_%d" % [cx, cy]
		var wbody := StaticBody3D.new()
		wbody.collision_layer = WORLD_MASK
		wbody.collision_mask = 0
		for r in wall_runs:
			_add_run_box(wbody, r, WALL_H, WALL_H / 2)
		wbody.add_child(wmi)
		wbody.set_meta("fade_meshes", [wmi])
		region.add_child(wbody)
		_fog_add(fog, Vector2i(cx, cy), "meshes", wmi)
		for pair in [[face_mesh(), face_xf, "WallFaces_%d_%d"], [pilaster_mesh(), pil_xf, "Pilasters_%d_%d"]]:
			if not (pair[1] as Array).is_empty():
				var mmi := _multi(pair[0], pair[1], wmi.material_override, pair[2] % [cx, cy])
				wbody.add_child(mmi)
				_fog_add(fog, Vector2i(cx, cy), "meshes", mmi)
	return true


static func _add_run_box(body: StaticBody3D, r: Array, height: float, y: float) -> void:
	var x0: int = r[0]
	var x1: int = r[1]
	var row: int = r[2]
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3((x1 - x0 + 1) * TILE, height, TILE)
	cs.shape = b
	cs.position = Vector3((x0 + x1 + 1) * TILE / 2, y, (row + 0.5) * TILE)
	body.add_child(cs)


static func _build_deco(parent: Node3D, m: Dictionary, rng: RandomNumberGenerator, fog: Dictionary = {}) -> void:
	var lists := {DungeonGen.DECO_BONES: [], DungeonGen.DECO_RUBBLE: [], DungeonGen.DECO_LAVA: []}
	var deco: PackedByteArray = m.deco
	for i in deco.size():
		if lists.has(deco[i]):
			lists[deco[i]].append(Vector2i(i % m.w, i / m.w))
	var bone := StandardMaterial3D.new()
	bone.albedo_color = Color(0.78, 0.74, 0.64)
	bone.roughness = 1.0
	var rubble := StandardMaterial3D.new()
	rubble.albedo_color = Color(0.46, 0.43, 0.4)
	rubble.roughness = 1.0
	var lava := StandardMaterial3D.new()
	lava.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lava.albedo_color = Color(1.0, 0.38, 0.1)
	lava.emission_enabled = true
	lava.emission = Color(1.0, 0.35, 0.08)
	lava.emission_energy_multiplier = 2.2
	var bone_mesh := BoxMesh.new()
	bone_mesh.size = Vector3(0.55, 0.08, 0.1)
	# 碎石用小方块（12 个三角形）：多实例绘制时不会被视锥逐个剔除，面数要低（P2 实测低分段球体一层就有 2.6 万个图元）
	var rubble_mesh := BoxMesh.new()
	rubble_mesh.size = Vector3(0.26, 0.14, 0.2)
	var lava_mesh := PlaneMesh.new()
	lava_mesh.size = Vector2(1.1, 0.22)
	var specs := [[DungeonGen.DECO_BONES, bone_mesh, bone, 3, "Bones"], [DungeonGen.DECO_RUBBLE, rubble_mesh, rubble, 4, "Rubble"], [DungeonGen.DECO_LAVA, lava_mesh, lava, 3, "Lava"]]
	for s in specs:
		var cells: Array = lists[s[0]]
		if cells.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = s[1]
		mm.instance_count = cells.size() * int(s[3])
		var idx := 0
		for c in cells:
			var cc := cell_center(c)
			for j in int(s[3]):
				var p := cc + Vector3(rng.randf_range(-0.8, 0.8), 0.04 if s[0] != DungeonGen.DECO_LAVA else 0.02, rng.randf_range(-0.8, 0.8))
				var basis := Basis(Vector3.UP, rng.randf() * TAU)
				if s[0] == DungeonGen.DECO_RUBBLE:
					basis = (basis * Basis(Vector3(1, 0, 0), rng.randf_range(-0.4, 0.4))).scaled(Vector3.ONE * rng.randf_range(0.5, 1.3))
				mm.set_instance_transform(idx, Transform3D(basis, p))
				if fog.has("_on"):
					_fog_add(fog, c / CHUNK, "deco", [mm, idx, Transform3D(basis, p)])
					mm.set_instance_transform(idx, Transform3D(Basis().scaled(Vector3.ZERO), p))
				idx += 1
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = s[2]
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.name = s[4]
		parent.add_child(mmi)


static func _fog_add(fog: Dictionary, key: Vector2i, what: String, v) -> void:
	if not fog.has("_on"):
		return
	if not fog.has(key):
		fog[key] = {"meshes": [], "deco": [], "torches": [], "shown": false}
	fog[key][what].append(v)
	if what == "meshes":
		v.visible = false


## 战争迷雾（P10）：显示这一块的地面、墙、装饰与火把；返回这次是否新显示
static func reveal_chunk(fog: Dictionary, key: Vector2i) -> bool:
	if not fog.has(key) or fog[key].shown:
		return false
	var e: Dictionary = fog[key]
	e.shown = true
	for mi in e.meshes:
		if is_instance_valid(mi):
			mi.visible = true
	for d in e.deco:
		d[0].set_instance_transform(d[1], d[2])
	for tch in e.torches:
		if is_instance_valid(tch):
			tch.visible = true
	return true
