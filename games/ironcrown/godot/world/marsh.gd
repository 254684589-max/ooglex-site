class_name Marsh
extends RefCounted
## 鹭沼连片地图（路线图 4.4a，D10-B；STORY.md 第四节「芦栈村」「堤道」）：芦栈村、堤道、黑鹭堡门前是一张连续的户外地图，
## 旅行地图上的芦栈村、黑鹭堡是这张图上的两个出生点（reedwharf / castle_gate）。布局全在 world/marsh_layout.gd。
## 搭法（TECH.md 4.15）：
##   1. 同步：水面（一整块）、所有碰撞（地面、泥滩、看不见的墙、房子、泥炭垛、堡墙）、路牌和堡门、东头路口外的收边（Edges）；
##   2. 画面分块：每块 64 米一个根节点（Chunk_x_z），活交给 ChunkStreamer 分帧做——这块的地面网格、每栋高脚屋、每 32 米一片芦苇、雾带、灯，
##      主角附近的块在载入时同步做完（prime），其余的进场以后每帧做几件；块按距离显示 / 隐藏。
## 看不见的墙在物理层 5「边界」（只挡人走，不挡视线、镜头、箭、交互）：从地面的边自动生成——边外面 0.3 米不是任何地面的地方就立一段墙；
## 墙外面的水里总有芦苇（_reed_chance：岸边 SHORE 米之内长满），不会有「空地上一堵看不见的墙」。
## 泥滩的碰撞体带元数据 surface = "mud"（core/surface.gd：走得慢、不能跑）；栈道铺在泥滩上面，踩着栈道不算泥。
## 4.4a 只有地形和房子：人（客栈老板、托宾、渡工、吉尔伯特）和客栈里面是 4.4b，鹭沼深处和营地是 4.4c，堡里是 4.5。

const SPAWNS := MarshLayout.SPAWNS
const VIEWS := MarshLayout.VIEWS
const VIEW_NAMES := MarshLayout.VIEW_NAMES
const GRID := 16.0                  # 查「附近有哪些地面」用的格子（米）
const REED_STEP := 1.5              # 芦苇：每隔多少米一个候选点（格子里随机偏一点）
const SUB := 32.0                   # 芦苇按 32 米一片做多实例（一块 64 米分四片：看不见的片整片裁掉）
const REED_KINDS := 3
const REED_LOW_SHARE := 0.5         # 低画质只画一半
const WALL_H := 4.5
const THICK := {"mud": 0.4, "land": 0.6, "deck": 0.2, "stone": 1.2, "slope": 0.4, "bridge": 0.15}
const GATE_NAME := "黑鹭堡的堡门"
const GATE_TEXT := "堡门紧闭，叫了也没人应。（黑鹭堡还在开发中）"
const SIGN_TEXT_VILLAGE := "往霜渡镇 · 黑鹭堡"
const SIGN_TEXT_GATE := "往芦栈村 · 霜渡镇"
const EXIT_NAME := "回霜渡镇的路"

var parent: Node3D
var reduced_motion := false
var floors: Array = []
var grid := {}                      # Vector2i → 地面下标
var reed_meshes: Array = []
var walls: Array = []


## 搭场景：同步的部分做完，分帧的活交给 world 下的 Streamer（main 载入后先 prime 主角附近的块）。返回默认出生点（村口）
static func build(p_parent: Node3D, p_reduced_motion := false) -> Transform3D:
	var t0 := Time.get_ticks_usec()
	var m := Marsh.new()
	m.parent = p_parent
	m.reduced_motion = p_reduced_motion
	m.floors = MarshLayout.floors()
	m.grid = make_index(m.floors, MarshLayout.SHORE + 1.0)
	_warm()
	m._water()
	m._collision()
	m._interactables()
	Edges.dress(p_parent, MarshLayout.BANK, [{"at": MarshLayout.EXIT_AT, "out": Vector3(1, 0, 0), "half": 1.8, "fence": true, "lantern": true, "frame": "霜渡镇"}],
		[Rect2(-400, -400, 528, 800), Rect2(128, -400, 400, 412), Rect2(128, 50, 400, 400)], 4401, "bank")   # 只在东头路口外面：干岸接着往东铺，两边白桦
	var st := ChunkStreamer.new()
	st.name = "Streamer"
	st.host = p_parent
	st.builder = m
	p_parent.add_child(st)
	m._jobs(st)
	print("IC_MARSH sync ms=%.0f floors=%d walls=%d chunks=%d" % [float(Time.get_ticks_usec() - t0) / 1000.0, m.floors.size(), m.walls.size(), st.chunks.size()])
	var s: Array = SPAWNS.reedwharf
	return Transform3D(Basis(Vector3.UP, deg_to_rad(float(s[1]))), s[0])


## 分帧搭的块要用的材质先在载入时（黑屏里）备好：头一次载入贴图、画茅草和雾的噪声要几十到几百毫秒（本机无头实测：石墙、石板路、
## 灰泥各约 70 毫秒），放在分帧的活里就是进场以后卡一下。从霜渡镇走过来时这些多半已经在缓存里（Look 的材质是静态缓存）
static func _warm() -> void:
	for k in ["street", "stone", "timber", "peat", "plaster", "roof", "snow", "bark"]:
		Look.mat(k)
	Look.ground("mud")
	Look.ground("bank")
	Look.thatch()
	Look.noise_texture()
	Look.water(true)
	Look.reed()
	Look.glass_lit()
	Look.glass_dark()
	Look.halo(Look.WINDOW_COLOR, 0.32)


# ---------------- 查地面 ----------------

## 按 GRID 米的格子记下每块地面（外接矩形放大 grow）落在哪些格子里
static func make_index(fl: Array, grow: float) -> Dictionary:
	var g := {}
	for i in fl.size():
		var r := MarshLayout.aabb(fl[i]).grow(grow)
		for x in range(floori(r.position.x / GRID), floori(r.end.x / GRID) + 1):
			for z in range(floori(r.position.y / GRID), floori(r.end.y / GRID) + 1):
				var k := Vector2i(x, z)
				if not g.has(k):
					g[k] = []
				g[k].append(i)
	return g


static func near(g: Dictionary, p: Vector2) -> Array:
	return g.get(Vector2i(floori(p.x / GRID), floori(p.y / GRID)), [])


## 这一点脚下有没有地面（任何一种：泥滩也算，深水不算）
static func on_floor(fl: Array, g: Dictionary, p: Vector2, grow := 0.0) -> bool:
	for i in near(g, p):
		if MarshLayout.contains(fl[i], p, grow):
			return true
	return false


## 看不见的墙：每块地面的四条边每隔约 1 米看一下，边外 0.3 米不是任何地面的地方连成一段墙；墙的两头二分查找到「外面从地面变成水」的那一点
## 为止（第一版两头各多伸 0.3 米，伸到了旁边的木板上：断口的木板桥、码头两头只剩 1.4 米宽，审查）。凸角（角外面也不是地面）再伸出去一个墙厚，
## 和另一条边的墙搭上（不然两段墙只在角尖上碰着）。返回 [{a, b（XZ）, n（朝外）}]
static func wall_segments(fl: Array, g: Dictionary) -> Array:
	var out := []
	for f in fl:
		var pts := MarshLayout.corners(f)
		for e in 4:
			var a: Vector2 = pts[e]
			var b: Vector2 = pts[(e + 1) % 4]
			var length := a.distance_to(b)
			if length < 0.05:
				continue
			var dir := (b - a) / length
			var n := Vector2(dir.y, -dir.x)
			if n.dot((a + b) * 0.5 - (f.c as Vector2)) < 0.0:
				n = -n
			var steps := maxi(1, roundi(length))
			var step := length / steps
			var need := func(t: float) -> bool: return not on_floor(fl, g, a + dir * t + n * 0.3)
			var run := -1
			for k in steps + 1:
				var here: bool = k < steps and bool(need.call((k + 0.5) * step))
				if here and run < 0:
					run = k
				elif not here and run >= 0:
					var s0 := _edge_cut(need, (run - 0.5) * step if run > 0 else 0.0, (run + 0.5) * step, true)
					var s1 := _edge_cut(need, (k - 0.5) * step, (k + 0.5) * step if k < steps else length, false)
					if s0 <= 0.001 and not on_floor(fl, g, a - dir * 0.2 + n * 0.2):
						s0 = -0.4
					if s1 >= length - 0.001 and not on_floor(fl, g, b + dir * 0.2 + n * 0.2):
						s1 = length + 0.4
					out.append({"a": a + dir * s0, "b": a + dir * s1, "n": n})
					run = -1
	return out


## 一段墙的端点：在 lo..hi 之间二分找「要墙」和「不要墙」的分界。rising = lo 那头不要墙、hi 那头要墙（墙的起点）
static func _edge_cut(need: Callable, lo: float, hi: float, rising: bool) -> float:
	if rising and bool(need.call(lo + 0.001)):
		return lo                                      # 一开头就要墙（边的起点）
	if not rising and bool(need.call(hi - 0.001)):
		return hi                                      # 一直要到头（边的终点）
	for i in 10:
		var mid := (lo + hi) * 0.5
		if bool(need.call(mid)) == rising:
			hi = mid
		else:
			lo = mid
	return hi if rising else lo


# ---------------- 同步：水、碰撞、门和路牌 ----------------

## 水面：一整块，铺到图外 90 米（和区域收边一样远，雾里看不见尽头）。只画面，没有碰撞（深水走不进去，靠看不见的墙）
func _water() -> void:
	var kit := MeshKit.new()
	var r := MarshLayout.BOUNDS.grow(Edges.GROUND_MARGIN)
	var c := r.get_center()
	kit.box("water", Vector3(c.x, MarshLayout.WATER_Y, c.y), Vector3(r.size.x, 0.02, r.size.y))
	var mi := kit.build({"water": Look.water(true)})
	mi.name = "MarshWater"
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


func _body(node_name: String, layer: int) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.name = node_name
	b.collision_layer = layer
	b.collision_mask = 0
	parent.add_child(b)
	return b


static func _shape(body: StaticBody3D, xf: Transform3D, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.transform = xf
	body.add_child(cs)


## 所有碰撞一次建完：地面（泥滩单独一个碰撞体，带 surface = mud）、看不见的墙（层 5）、房子 / 泥炭垛 / 堡墙 / 石拱 / 木架
func _collision() -> void:
	var ground := _body("MarshFloor", 1)
	var mud := _body("MarshMud", 1)
	mud.set_meta("surface", "mud")
	for f in floors:
		var b := MarshLayout.box_of(f, float(THICK[f.k]))
		_shape(mud if f.k == "mud" else ground, b[0], b[1])
	var wb := _body("MarshWalls", FpController.LAYER_BOUNDARY)
	walls = wall_segments(floors, grid)
	for w in walls:
		var a: Vector2 = w.a
		var b: Vector2 = w.b
		var n: Vector2 = w.n
		var mid := (a + b) * 0.5 + n * 0.2
		var d := b - a
		var basis := Basis(Vector3.UP, atan2(-d.y, d.x))           # 本地 x 沿着这段边
		_shape(wb, Transform3D(basis, Vector3(mid.x, 1.0, mid.y)), Vector3(d.length(), WALL_H, 0.4))
	var solids := _body("MarshSolids", 1)
	for h in MarshLayout.HOUSES:
		for s in House.solids(MarshLayout.house_pos(h), float(h[2]), MarshLayout.house_spec(h)):
			_shape(solids, s[0], s[1])
	var th: Vector2 = MarshLayout.TOBIN_HUT[0]
	for s in House.solids(Vector3(th.x, MarshLayout.BANK_Y, th.y), float(MarshLayout.TOBIN_HUT[1]), MarshLayout.tobin_spec()):
		_shape(solids, s[0], s[1])
	var ps := MarshLayout.PEAT_SIZE
	for p in MarshLayout.PEAT:
		var c: Vector2 = p[0]
		_shape(solids, Transform3D(Basis(Vector3.UP, deg_to_rad(float(p[1]))), Vector3(c.x, MarshLayout.BANK_Y + ps.y * 0.5, c.y)), ps)
	for r in MarshLayout.RACKS:
		var c: Vector2 = r[0]
		_shape(solids, Transform3D(Basis(Vector3.UP, deg_to_rad(float(r[1]))), Vector3(c.x, 0.9, c.y)), Vector3(3.2, 1.8, 0.4))
	for p in MarshLayout.PUNTS:
		if str(p[2]) == "mud":
			var c: Vector2 = p[0]
			_shape(solids, Transform3D(Basis(Vector3.UP, deg_to_rad(float(p[1]))), Vector3(c.x, MarshLayout.MUD_Y + 0.25, c.y)), Vector3(1.5, 0.5, 4.6))
	for s in _arch_solids():
		_shape(solids, s[0], s[1])
	for s in _castle_solids():
		_shape(solids, s[0], s[1])


## 路牌（出发的地方：村口、堡门前）和堡门（锁着）。是可交互物，跟着碰撞一起建（分帧搭的只有画面）
func _interactables() -> void:
	var sv := RoadSign.new()
	sv.text = SIGN_TEXT_VILLAGE
	sv.position = MarshLayout.SIGN_VILLAGE
	sv.rotation_degrees.y = -90.0                 # 字朝东（对着从霜渡镇来的人），木板伸向路中间
	parent.add_child(sv)
	var sg := RoadSign.new()
	sg.text = SIGN_TEXT_GATE
	sg.position = MarshLayout.SIGN_GATE
	sg.rotation_degrees.y = -45.0                 # 立在石台西南边，字朝东北（对着石台中间：从堤道走上来、在出生点转个身都看得到，审查）
	parent.add_child(sg)
	var gate := Door.make(GATE_NAME, 3.2, 4.2, true)
	gate.locked_text = GATE_TEXT
	var xf := MarshLayout.castle_xform()
	gate.transform = xf * Transform3D(Basis.IDENTITY, Vector3(-1.6, 0.3, MarshLayout.CASTLE_SIZE.y * 0.5 + 0.1))
	parent.add_child(gate)
	# 东头路口（收边做的门柱「霜渡镇」）：不是走得出去的门，横一个出发点——对着它交互打开旅行地图，人也挡在门柱里（审查：原来门洞开着、
	# 走过去被看不见的墙默默挡住）
	var gw := TravelPoint.make(EXIT_NAME, Vector3(3.6, 2.4, 0.4))
	gw.position = MarshLayout.EXIT_AT + Vector3(-0.35, 0, 0)
	gw.rotation_degrees.y = 90.0
	parent.add_child(gw)


# ---------------- 分帧的活 ----------------

func _jobs(st: ChunkStreamer) -> void:
	var per := {}
	for cx in MarshLayout.COLS:
		for cz in MarshLayout.ROWS:
			per[MarshLayout.cell_id(Vector2i(cx, cz))] = []
	var pieces := {}                               # 块 → 这块里的地面（大块地面按方格切开，沿堤道的按 8 米一截）
	for f in floors:
		for pc in _pieces(f):
			var id := MarshLayout.cell_id(MarshLayout.cell_of(pc.c))
			if not pieces.has(id):
				pieces[id] = []
			pieces[id].append(pc)
	for id in per:
		if pieces.has(id) or _has_props(id):
			per[id].append(_job_ground.bind(id, pieces.get(id, [])))
	for i in MarshLayout.HOUSES.size():
		var h: Array = MarshLayout.HOUSES[i]
		per[MarshLayout.cell_id(MarshLayout.cell_of(h[1]))].append(_job_house.bind(i))
	per[MarshLayout.cell_id(MarshLayout.cell_of(MarshLayout.TOBIN_HUT[0]))].append(_job_tobin)
	per[MarshLayout.cell_id(MarshLayout.cell_of(MarshLayout.cw(MarshLayout.ARCH_T)))].append(_job_arch)
	per[MarshLayout.cell_id(MarshLayout.cell_of(MarshLayout.cw(MarshLayout.CASTLE_T)))].append(_job_castle)
	for k in REED_KINDS:
		reed_meshes.append(reed_mesh(k))
	var b := MarshLayout.BOUNDS
	var i := 0
	for x in range(int(b.position.x), int(b.end.x), int(SUB)):
		for z in range(int(b.position.y), int(b.end.y), int(SUB)):
			var r := Rect2(x, z, SUB, SUB)
			per[MarshLayout.cell_id(MarshLayout.cell_of(r.get_center()))].append(_job_reeds.bind(r, i % REED_KINDS))
			i += 1
	for id in per:
		var fog := []                                  # [在 FOG 表里的下标, 那一条]：低画质按下标隔一片藏一片（和先搭哪块无关，审查）
		for fi in MarshLayout.FOG.size():
			var fp: Vector3 = MarshLayout.FOG[fi][0]
			if MarshLayout.cell_id(MarshLayout.cell_of(Vector2(fp.x, fp.z))) == id:
				fog.append([fi, MarshLayout.FOG[fi]])
		if not fog.is_empty():
			per[id].append(_job_fog.bind(fog))
		if not _lamps_in(id).is_empty():
			per[id].append(_job_lamps.bind(id))
	for id in per:
		var parts := (id as String).split("_")
		st.add_chunk(id, MarshLayout.cell_rect(Vector2i(int(parts[0]), int(parts[1]))), per[id])


## 一块地面切成画面用的小块：轴对齐的按方格切，沿堤道的按 8 米一截（每截归它中心所在的块）
func _pieces(f: Dictionary) -> Array:
	var out := []
	if is_zero_approx(float(f.yaw)):
		var r := Rect2((f.c as Vector2) - (f.size as Vector2) * 0.5, f.size)
		for cx in MarshLayout.COLS:
			for cz in MarshLayout.ROWS:
				var part := r.intersection(MarshLayout.cell_rect(Vector2i(cx, cz)))
				if part.size.x > 0.01 and part.size.y > 0.01:
					var pc := f.duplicate()
					pc.c = part.get_center()
					pc.size = part.size
					out.append(pc)
		return out
	var length := float(f.size.y)
	var n := maxi(1, ceili(length / 8.0))
	var tanp := tan(deg_to_rad(float(f.get("pitch", 0.0))))
	for k in n:
		var lz := -length * 0.5 + (k + 0.5) * length / n
		var pc := f.duplicate()
		pc.c = MarshLayout.world_of(f, Vector2(0, lz))
		pc.size = Vector2(f.size.x, length / n)
		pc.top = float(f.top) - lz * tanp                   # 缓坡：-Z 那头高
		out.append(pc)
	return out


func _has_props(id: String) -> bool:
	for p in MarshLayout.PEAT:
		if MarshLayout.cell_id(MarshLayout.cell_of(p[0])) == id:
			return true
	return false


## 一块的地面网格：泥滩、干地、栈道（木板、板缝、桩子）、堤道（石砌、路面、石坡）、断口的木板桥；泥炭垛、木架、平底船、指路牌
func _job_ground(root: Node3D, id: String, pieces: Array) -> void:
	var kit := MeshKit.new()
	for pc in pieces:
		match str(pc.k):
			"mud":
				var b := MarshLayout.box_of(pc, 0.3)
				kit.box("mud", b[0].origin, b[1], b[0].basis, 0.95, 0.5)
				_puddles(kit, pc)
			"land":
				var b := MarshLayout.box_of(pc, 0.5)
				kit.box("bank", b[0].origin, b[1], b[0].basis, 1.0, 0.55)
			"deck":
				_deck(kit, pc)
			"stone":
				var b := MarshLayout.box_of(pc, 1.4)
				kit.box("stone", b[0].origin, b[1], b[0].basis, 0.85, 0.35)
				var top := MarshLayout.box_of(pc, 0.02)
				kit.box("street", top[0].origin + top[0].basis.y * 0.012, Vector3(top[1].x - 0.3, 0.02, top[1].z), top[0].basis, 0.9, 0.9)
			"slope":
				var b := MarshLayout.box_of(pc, 0.4)
				kit.box("stone", b[0].origin, b[1], b[0].basis, 0.7, 0.4)
			"bridge":
				_bridge(kit, pc)
	var rect := _cell_rect(id)
	if rect.has_point(Vector2(110, MarshLayout.ROAD_Z)):            # 村口的路：干岸上踩出来的一道（比干岸深一点）
		kit.box("bank", Vector3(114, MarshLayout.BANK_Y + 0.006, MarshLayout.ROAD_Z), Vector3(28, 0.02, 3.4), Basis.IDENTITY, 0.6, 0.6)
	if rect.has_point(MarshLayout.PEAT_CUT.get_center()):
		var pc := MarshLayout.PEAT_CUT
		kit.box("peat", Vector3(pc.get_center().x, MarshLayout.BANK_Y + 0.004, pc.get_center().y), Vector3(pc.size.x, 0.02, pc.size.y), Basis.IDENTITY, 0.7, 0.7)
	for p in MarshLayout.PEAT:
		if rect.has_point(p[0]):
			_peat_stack(kit, p[0], float(p[1]))
	for r in MarshLayout.RACKS:
		if rect.has_point(r[0]):
			_rack(kit, r[0], float(r[1]))
	for p in MarshLayout.PUNTS:
		if rect.has_point(p[0]):
			_punt(kit, p[0], float(p[1]), str(p[2]) == "mud")
	if rect.has_point(Vector2(MarshLayout.SIGN_CAUSEWAY.x, MarshLayout.SIGN_CAUSEWAY.z)):
		_causeway_sign(root, kit)
	if rect.has_point(MarshLayout.cw((MarshLayout.GAP.x + MarshLayout.GAP.y) * 0.5)):
		_gap_rubble(kit)
	var mi := kit.build({"mud": Look.ground("mud"), "bank": Look.ground("bank"), "water": Look.water(true), "street": Look.mat("street"), "stone": Look.mat("stone"),
		"timber": Look.mat("timber"), "peat": Look.mat("peat"), "thatch": Look.thatch(), "rope": _rope_mat()})
	mi.name = "Ground"
	root.add_child(mi)


func _cell_rect(id: String) -> Rect2:
	var parts := id.split("_")
	return MarshLayout.cell_rect(Vector2i(int(parts[0]), int(parts[1])))


## 泥滩上的积水：几片贴着泥面的水（只是画面），避开栈道、房子；每 60 平方米一片左右
func _puddles(kit: MeshKit, pc: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(pc.c)
	var s: Vector2 = pc.size
	var n := int(s.x * s.y / 60.0)
	for k in n:
		var l := Vector2(rng.randf_range(-0.5, 0.5) * s.x, rng.randf_range(-0.5, 0.5) * s.y)
		var p := MarshLayout.world_of(pc, l)
		var walkway := false
		for i in near(grid, p):
			var f: Dictionary = floors[i]
			if f.k != "mud" and MarshLayout.distance(f, p) < 1.0:
				walkway = true
				break
		if walkway or MarshLayout.HOUSES.any(func(h): return _in_house(h, p, 0.5)):
			continue
		var b := Basis(Vector3.UP, rng.randf() * TAU)
		var size := Vector3(rng.randf_range(1.2, 4.0), 0.02, rng.randf_range(0.8, 2.6))
		kit.box("water", Vector3(p.x, float(pc.top) + 0.012, p.y), size, b)
		kit.box("water", Vector3(p.x, float(pc.top) + 0.011, p.y) + b.x * size.x * 0.3, size * Vector3(0.6, 1, 1.3), b)    # 两片叠着，边不那么方


## 木栈道的一截：木板面、横着的板缝、两边每 3 米一根桩、底下两根纵梁
func _deck(kit: MeshKit, pc: Dictionary) -> void:
	var c: Vector2 = pc.c
	var s: Vector2 = pc.size
	var top := float(pc.top)
	var along_x := s.x > s.y
	var length := s.x if along_x else s.y
	var width := s.y if along_x else s.x
	kit.box("timber", Vector3(c.x, top - 0.04, c.y), Vector3(s.x, 0.08, s.y), Basis.IDENTITY, 1.0, 0.55)
	var ax := Vector2(1, 0) if along_x else Vector2(0, 1)
	var side := Vector2(0, 1) if along_x else Vector2(1, 0)
	var n := floori(length)
	for k in n:
		var p := c + ax * (-length * 0.5 + k + 0.5)
		kit.box("timber", Vector3(p.x, top + 0.004, p.y), Vector3(0.05 if along_x else width, 0.01, width if along_x else 0.05), Basis.IDENTITY, 0.45, 0.45)
	for sgn: float in [-1.0, 1.0]:
		var q: Vector2 = c + side * (width * 0.5 - 0.12) * sgn
		kit.box("timber", Vector3(q.x, top - 0.16, q.y), Vector3(length if along_x else 0.12, 0.14, 0.12 if along_x else length), Basis.IDENTITY, 0.6, 0.45)
		var k := 0.0
		while k <= length + 0.01:
			var pp: Vector2 = q + ax * (-length * 0.5 + k)
			kit.cylinder("timber", Vector3(pp.x, MarshLayout.WATER_Y - 0.8, pp.y), Vector3(pp.x, top - 0.08, pp.y), 0.1, 0.09, 5, 0.6)
			k += 3.0


## 断口上的木板桥：横铺的木板（和石面齐平）、两边各三根桩、一道绳栏
func _bridge(kit: MeshKit, pc: Dictionary) -> void:
	var b := MarshLayout.basis_of(pc)
	var c: Vector2 = pc.c
	var top := float(pc.top)
	var s: Vector2 = pc.size
	var o := Vector3(c.x, top, c.y)
	kit.box("timber", o - b.y * 0.06, Vector3(s.x, 0.12, s.y), b, 1.0, 0.5)
	var k := -s.y * 0.5 + 0.15
	while k < s.y * 0.5:
		kit.box("timber", o + b.z * k + b.y * 0.004, Vector3(s.x, 0.01, 0.04), b, 0.45, 0.45)
		k += 0.32
	for sx: float in [-1.0, 1.0]:
		var posts := []
		for lz: float in [-s.y * 0.5 + 0.2, 0.0, s.y * 0.5 - 0.2]:
			var p: Vector3 = o + b.x * (sx * (s.x * 0.5 + 0.08)) + b.z * lz
			kit.cylinder("timber", Vector3(p.x, MarshLayout.WATER_Y - 0.8, p.z), Vector3(p.x, top + 1.05, p.z), 0.09, 0.08, 5, 0.7)
			posts.append(p)
		for j in 2:
			kit.cylinder("rope", posts[j] + Vector3(0, 0.95, 0), posts[j + 1] + Vector3(0, 0.95, 0), 0.025, 0.025, 4, 0.8)


## 断口两头塌下来的石块
func _gap_rubble(kit: MeshKit) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4402
	for t in [MarshLayout.GAP.x, MarshLayout.GAP.y]:
		for k in 5:
			var off := rng.randf_range(-2.6, 2.6)
			if absf(off) < MarshLayout.BRIDGE_W * 0.5 + 0.3:
				off = signf(off + 0.01) * (MarshLayout.BRIDGE_W * 0.5 + 0.5)
			var tt: float = t + (rng.randf_range(0.2, 1.4) * (1.0 if t < 40.0 else -1.0))     # 掉进断口里
			var p := MarshLayout.cw3(tt, off, rng.randf_range(-0.35, 0.05))
			var bb := Basis(Vector3(rng.randf(), rng.randf(), rng.randf()).normalized(), rng.randf_range(0.2, 0.7))
			kit.box("stone", p, Vector3(rng.randf_range(0.6, 1.2), rng.randf_range(0.4, 0.7), rng.randf_range(0.6, 1.1)), bb, 0.8, 0.5)


## 泥炭垛：一块块切好的泥炭码成三层，上面一层歪一点
func _peat_stack(kit: MeshKit, c: Vector2, yaw: float) -> void:
	var b := Basis(Vector3.UP, deg_to_rad(yaw))
	var s := MarshLayout.PEAT_SIZE
	var o := Vector3(c.x, MarshLayout.BANK_Y, c.y)
	for layer in 3:
		var h := s.y / 3.0
		var shrink := layer * 0.18
		var tw := Basis(Vector3.UP, deg_to_rad((layer - 1) * 4.0))
		kit.box("peat", o + Vector3(0, h * (layer + 0.5), 0), Vector3(s.x - shrink, h - 0.02, s.z - shrink), b * tw, 0.95 - layer * 0.05, 0.6)
	kit.box("thatch", o + Vector3(0, s.y + 0.06, 0), Vector3(s.x - 0.3, 0.12, s.z - 0.3), b, 0.8, 0.7)        # 顶上盖一层草


## 晾鱼、晾芦苇的木架：两根立柱、两道横杆，杆上挂几束（深色）
func _rack(kit: MeshKit, c: Vector2, yaw: float) -> void:
	var b := Basis(Vector3.UP, deg_to_rad(yaw))
	var o := Vector3(c.x, MarshLayout.MUD_Y, c.y)
	for sx in [-1.5, 1.5]:
		kit.cylinder("timber", o + b * Vector3(sx, -0.3, 0), o + b * Vector3(sx, 1.9, 0), 0.07, 0.06, 5, 0.7)
	for y in [1.2, 1.75]:
		kit.cylinder("timber", o + b * Vector3(-1.6, y, 0), o + b * Vector3(1.6, y, 0), 0.04, 0.04, 4, 0.8)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(c.x * 7.0 + c.y)
	for k in 7:
		var x := -1.3 + k * 0.43
		kit.box("thatch", o + b * Vector3(x, 1.45 + rng.randf_range(-0.05, 0.05), 0), Vector3(0.12, rng.randf_range(0.4, 0.6), 0.1), b, 0.7, 0.5)


## 平底船：平底、矮舷，船头翘一点；泥上的那条歪着搁浅
func _punt(kit: MeshKit, c: Vector2, yaw: float, beached: bool) -> void:
	var tilt := Basis(Vector3.BACK, deg_to_rad(6.0)) if beached else Basis.IDENTITY
	var b := Basis(Vector3.UP, deg_to_rad(yaw)) * tilt
	var y := MarshLayout.MUD_Y + 0.12 if beached else MarshLayout.WATER_Y + 0.12
	var o := Vector3(c.x, y, c.y)
	kit.box("timber", o, Vector3(1.4, 0.18, 4.4), b, 0.9, 0.4, true)
	for sx in [-1.0, 1.0]:
		kit.box("timber", o + b * Vector3(sx * 0.66, 0.2, 0), Vector3(0.08, 0.32, 4.4), b, 0.8, 0.5)
	for sz in [-1.0, 1.0]:
		kit.box("timber", o + b * Vector3(0, 0.26, sz * 2.25), Vector3(1.4, 0.36, 0.1), b * Basis(Vector3.RIGHT, deg_to_rad(-sz * 20.0)), 0.8, 0.5)
	kit.cylinder("timber", o + b * Vector3(0.3, 0.2, -1.2), o + b * Vector3(-0.2, 0.3, 1.9), 0.03, 0.03, 4, 0.8)        # 撑篙横在船里


## 堤道头的指路牌：一根桩、一块板，两面写字（不能交互：出发走村口、堡门的路牌）
func _causeway_sign(root: Node3D, kit: MeshKit) -> void:
	var p := MarshLayout.SIGN_CAUSEWAY
	kit.box("timber", p + Vector3(0, 1.0, 0), Vector3(0.12, 2.0, 0.12), Basis.IDENTITY, 0.85, 0.5)
	kit.box("timber", p + Vector3(-0.55, 1.72, 0), Vector3(1.3, 0.34, 0.06), Basis.IDENTITY, 0.9, 0.8)
	for s in [[1.0, "堤道 · 往黑鹭堡"], [-1.0, "往芦栈村"]]:
		var l := Label3D.new()
		l.text = str(s[1])
		l.font = load(Blocks.FONT_PATH)
		l.font_size = 32
		l.pixel_size = 0.0048
		l.modulate = Color("e8dcc0")
		l.outline_size = 6
		l.double_sided = false
		l.position = p + Vector3(-0.55, 1.72, 0.04 * float(s[0]))
		l.rotation_degrees.y = 0.0 if float(s[0]) > 0.0 else 180.0
		root.add_child(l)


func _job_house(root: Node3D, i: int) -> void:
	var h: Array = MarshLayout.HOUSES[i]
	var house := House.build(root, MarshLayout.house_pos(h), float(h[2]), MarshLayout.house_spec(h))
	house.name = "House_" + str(h[0])


func _job_tobin(root: Node3D) -> void:
	var th: Vector2 = MarshLayout.TOBIN_HUT[0]
	var house := House.build(root, Vector3(th.x, MarshLayout.BANK_Y, th.y), float(MarshLayout.TOBIN_HUT[1]), MarshLayout.tobin_spec())
	house.name = "House_tobin"


# ---------------- 石拱、黑鹭堡 ----------------

## 石拱（靠堡门）：两根墩子压在路两边、上面一道拱；拱下能走 ARCH_GAP 米宽（4.9 的窄口之一）。
## 墩子外面各一道矮石墙横过两边的泥滩（审查：第一版只有墩子，从泥里绕得过去，不成窄口）
static func _arch_solids() -> Array:
	var out := []
	var b := Basis(Vector3.UP, deg_to_rad(MarshLayout.CW_YAW))
	var outer := MarshLayout.CW_W * 0.5 + MarshLayout.slope_width() + MarshLayout.CW_MUD + 0.3
	for side in [1.0, -1.0]:
		var off: float = side * (MarshLayout.ARCH_GAP * 0.5 + 1.25)
		out.append([Transform3D(b, MarshLayout.cw3(MarshLayout.ARCH_T, off, 2.2)), Vector3(2.5, 5.6, 2.2)])
		var w0 := MarshLayout.ARCH_GAP * 0.5 + 2.5
		out.append([Transform3D(b, MarshLayout.cw3(MarshLayout.ARCH_T, side * (w0 + outer) * 0.5, 0.6)), Vector3(outer - w0, 2.4, 1.2)])
	return out


func _job_arch(root: Node3D) -> void:
	var kit := MeshKit.new()
	var b := Basis(Vector3.UP, deg_to_rad(MarshLayout.CW_YAW))
	for s in _arch_solids():
		kit.box("stone", s[0].origin, s[1], b, 0.9, 0.45)
	var o := MarshLayout.cw3(MarshLayout.ARCH_T, 0.0, MarshLayout.CAUSE_Y)
	kit.box("stone", o + Vector3(0, 4.85, 0), Vector3(MarshLayout.ARCH_GAP + 5.4, 0.9, 2.4), b, 1.0, 0.7)     # 压在墩子顶上（墩子顶 5.0）
	kit.box("timber", MarshLayout.cw3(MarshLayout.ARCH_T - 1.0, 2.0, MarshLayout.CAUSE_Y + 3.6), Vector3(0.08, 0.08, 0.55), b, 0.6, 0.6)   # 挂灯的铁臂
	var r := MarshLayout.ARCH_GAP * 0.5
	for k in 7:                                     # 拱券：沿半圆排的几块楔石
		var a := PI * (k + 0.5) / 7.0
		var p := o + b * Vector3(cos(a) * r, 3.2 + sin(a) * (r * 0.75), 0)
		kit.box("stone", p, Vector3(0.62, 0.42, 2.2), b * Basis(Vector3.BACK, a - PI * 0.5), 0.9, 0.6)
	kit.box("stone", o + b * Vector3(0, 4.25, 0), Vector3(MarshLayout.ARCH_GAP + 0.4, 1.0, 2.2), b, 0.9, 0.6)
	var mi := kit.build({"stone": Look.mat("stone"), "timber": Look.mat("timber")})
	mi.name = "Arch"
	root.add_child(mi)


## 黑鹭堡的碰撞（4.5 才走得进去）：四面堡墙（正面中间留门洞，门是锁着的 Door）、四角的塔、门两边的塔、主楼
static func _castle_solids() -> Array:
	var xf := MarshLayout.castle_xform()
	var hw := MarshLayout.CASTLE_SIZE.x * 0.5
	var hd := MarshLayout.CASTLE_SIZE.y * 0.5
	var out := []
	var parts := [
		[Vector3((-hw - 1.8) * 0.5, 4.8, hd - 1.2), Vector3(hw - 1.8, 9.6, 2.4)],
		[Vector3((hw + 1.8) * 0.5, 4.8, hd - 1.2), Vector3(hw - 1.8, 9.6, 2.4)],
		[Vector3(0, 4.8, -hd + 1.2), Vector3(hw * 2.0, 9.6, 2.4)],
		[Vector3(-hw + 1.2, 4.8, 0), Vector3(2.4, 9.6, hd * 2.0)],
		[Vector3(hw - 1.2, 4.8, 0), Vector3(2.4, 9.6, hd * 2.0)],
		[Vector3(0, 9.6, -6), Vector3(14, 19.2, 14)],
		[Vector3(0, 7.0, hd - 3.0), Vector3(3.4, 14.0, 3.6)],          # 门洞里面堵上（门锁着，4.5 再开）
	]
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			parts.append([Vector3(sx * hw, 7.0, sz * hd), Vector3(6.4, 14.0, 6.4)])
		parts.append([Vector3(sx * 4.4, 6.25, hd + 0.4), Vector3(4.6, 12.5, 4.6)])
	for p in parts:
		out.append([xf * Transform3D(Basis.IDENTITY, p[0]), p[1]])
	return out


## 黑鹭堡外景（粗模：堡墙、雉堞、塔、尖顶、主楼；4.5 细化）。石岛在水面上露一圈
func _job_castle(root: Node3D) -> void:
	var kit := MeshKit.new()
	var hw := MarshLayout.CASTLE_SIZE.x * 0.5
	var hd := MarshLayout.CASTLE_SIZE.y * 0.5
	kit.box("stone", Vector3(0, -0.6, -2.5), Vector3(hw * 2.0 + 12.0, 1.8, hd * 2.0 + 7.0), Basis.IDENTITY, 0.55, 0.3)       # 石岛（正面只露 1 米：石台两边是水，不像走得上去的石台，审查）
	for sx in [-1.0, 1.0]:                                       # 石台两边的矮护墙
		kit.box("stone", Vector3(sx * (MarshLayout.APRON_W * 0.5 - 0.2), MarshLayout.CAUSE_Y + 0.2, hd + (MarshLayout.APRON_T.y - MarshLayout.APRON_T.x) * 0.5), Vector3(0.4, 0.5, MarshLayout.APRON_T.y - MarshLayout.APRON_T.x - 0.6), Basis.IDENTITY, 0.9, 0.5)
	var wall_h := 9.6
	var y0 := 0.3
	# 堡墙
	kit.box("stone", Vector3((-hw - 1.8) * 0.5, y0 + wall_h * 0.5, hd - 1.2), Vector3(hw - 1.8, wall_h, 2.4), Basis.IDENTITY, 0.95, 0.4)
	kit.box("stone", Vector3((hw + 1.8) * 0.5, y0 + wall_h * 0.5, hd - 1.2), Vector3(hw - 1.8, wall_h, 2.4), Basis.IDENTITY, 0.95, 0.4)
	kit.box("stone", Vector3(0, y0 + 4.4 + (wall_h - 4.4) * 0.5, hd - 1.2), Vector3(3.6, wall_h - 4.4, 2.4), Basis.IDENTITY, 0.95, 0.7)   # 门洞上面
	kit.box("stone", Vector3(0, y0 + wall_h * 0.5, -hd + 1.2), Vector3(hw * 2.0, wall_h, 2.4), Basis.IDENTITY, 0.95, 0.4)
	for sx in [-1.0, 1.0]:
		kit.box("stone", Vector3(sx * (hw - 1.2), y0 + wall_h * 0.5, 0), Vector3(2.4, wall_h, hd * 2.0), Basis.IDENTITY, 0.95, 0.4)
	kit.box("timber", Vector3(0, y0 + 2.1, hd - 2.6), Vector3(3.4, 4.2, 0.2), Basis.IDENTITY, 0.5, 0.4)            # 门洞深处的暗色
	# 雉堞：沿四面墙顶外沿
	var top := y0 + wall_h
	for side in 4:
		var length := hw * 2.0 if side < 2 else hd * 2.0
		var k := -length * 0.5 + 0.8
		while k < length * 0.5 - 0.6:
			var p := Vector3(k, top + 0.45, (hd - 0.3) * (1.0 if side == 0 else -1.0)) if side < 2 else Vector3((hw - 0.3) * (1.0 if side == 2 else -1.0), top + 0.45, k)
			kit.box("stone", p, Vector3(0.8 if side < 2 else 0.5, 0.9, 0.5 if side < 2 else 0.8), Basis.IDENTITY, 1.0, 0.8)
			k += 1.6
	# 塔：四角、门两边；石板尖顶
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_tower(kit, Vector3(sx * hw, y0, sz * hd), 3.6, 14.0, 5.5)
		_tower(kit, Vector3(sx * 4.4, y0, hd + 0.4), 2.6, 12.5, 4.2)
	# 主楼：方楼、四坡尖顶、几道窄窗
	var ky := y0 + 19.0
	kit.box("stone", Vector3(0, y0 + 9.5, -6), Vector3(14, 19.0, 14), Basis.IDENTITY, 1.0, 0.45)
	var apex := Vector3(0, ky + 6.5, -6)
	var cs := [Vector3(-7.6, ky, -13.6), Vector3(7.6, ky, -13.6), Vector3(7.6, ky, 1.6), Vector3(-7.6, ky, 1.6)]
	for k in 4:
		var a: Vector3 = cs[k]
		var b: Vector3 = cs[(k + 1) % 4]
		var n := (b - a).cross(apex - a).normalized()
		if n.dot(((a + b) * 0.5 - Vector3(0, ky, -6))) < 0.0:
			n = -n
		kit.tri("roof", a, b, apex, n, 0.9)
	for k in 3:
		kit.quad("glass_dark", [Vector3(-3.0 + k * 3.0 - 0.3, y0 + 14.0, 1.01), Vector3(-3.0 + k * 3.0 + 0.3, y0 + 14.0, 1.01),
			Vector3(-3.0 + k * 3.0 + 0.3, y0 + 12.4, 1.01), Vector3(-3.0 + k * 3.0 - 0.3, y0 + 12.4, 1.01)], Vector3.BACK)
	var mi := kit.build({"stone": Look.mat("stone"), "roof": Look.mat("roof"), "timber": Look.mat("timber"), "glass_dark": Look.glass_dark()})
	mi.name = "Castle"
	mi.transform = MarshLayout.castle_xform()
	root.add_child(mi)


func _tower(kit: MeshKit, base: Vector3, r: float, h: float, cone: float) -> void:
	kit.cylinder("stone", base + Vector3(0, -0.6, 0), base + Vector3(0, h, 0), r, r * 0.94, 10, 0.85)
	kit.cylinder("stone", base + Vector3(0, h - 0.2, 0), base + Vector3(0, h + 0.5, 0), r * 1.08, r * 1.08, 10, 0.9)
	kit.cylinder("roof", base + Vector3(0, h + 0.5, 0), base + Vector3(0, h + 0.5 + cone, 0), r * 1.15, 0.05, 10, 0.95)


# ---------------- 芦苇 ----------------

## 一丛芦苇的模型（k：三种，相邻的片轮流用）：10 根细长的叶，每根两截（下截四边形、上截三角），往外弯；根部灰绿、梢头枯黄。
## 每次现做（不放静态缓存，退出时会报资源没释放）
static func reed_mesh(k: int) -> Mesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4410 + k
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base_c := Color(0.15, 0.17, 0.11)
	var mid_c := Color(0.3, 0.28, 0.18)
	var tip_c := Color(0.46, 0.39, 0.25)
	for i in 10:
		var a := rng.randf() * TAU
		var dir := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-dir.z, 0, dir.x)
		var h := rng.randf_range(1.5, 2.5)
		var lean := rng.randf_range(0.1, 0.45)
		var w := rng.randf_range(0.035, 0.06)
		var root_p := dir * rng.randf_range(0.0, 0.18)
		var mid := root_p + dir * lean * 0.35 + Vector3(0, h * 0.55, 0)
		var tip := root_p + dir * lean + Vector3(0, h, 0)
		var up := Vector3(0, 1, 0)
		var n := (up + dir * 0.3).normalized()
		var verts := [[root_p - side * w, base_c], [root_p + side * w, base_c], [mid + side * w * 0.7, mid_c],
			[root_p - side * w, base_c], [mid + side * w * 0.7, mid_c], [mid - side * w * 0.7, mid_c],
			[mid - side * w * 0.7, mid_c], [mid + side * w * 0.7, mid_c], [tip, tip_c]]
		for v in verts:
			st.set_normal(n)
			st.set_color(v[1])
			st.add_vertex(v[0])
	var mesh := st.commit()
	mesh.surface_set_material(0, Look.reed())
	return mesh


## 这一点长芦苇的机会：栈道、干地、石砌 1.3 米内不长（路要看得清）；泥滩上稀稀拉拉；走得到的地方外面 SHORE 米内的水里长满；
## 芦苇荡（REED_BEDS）里成片；码头前面的开阔水面、房子和小东西旁边不长
func _reed_chance(p: Vector2) -> float:
	if not MarshLayout.BOUNDS.grow(-0.5).has_point(p):
		return 0.0
	for r: Rect2 in MarshLayout.OPEN_WATER:
		if r.has_point(p):
			return 0.0
	var on_mud := false
	var shore := false
	for i in near(grid, p):
		var f: Dictionary = floors[i]
		var d := MarshLayout.distance(f, p)
		if f.k == "mud":
			if d <= 0.0:
				on_mud = true
			elif d < MarshLayout.SHORE:
				shore = true
		else:
			if d < 1.3:
				return 0.0
			if d < MarshLayout.SHORE:
				shore = true
	for h in MarshLayout.HOUSES:
		var hp: Vector2 = h[1]
		if hp.distance_to(p) < 12.0 and _in_house(h, p, 1.6):
			return 0.0
	for list in [MarshLayout.RACKS, MarshLayout.PUNTS]:
		for q in list:
			if (q[0] as Vector2).distance_to(p) < 3.2:
				return 0.0
	var hw := MarshLayout.CASTLE_SIZE.x * 0.5 + 7.0
	var cl := MarshLayout.castle_xform().basis.inverse() * (Vector3(p.x, 0, p.y) - MarshLayout.castle_xform().origin)
	if absf(cl.x) < hw and cl.z > -MarshLayout.CASTLE_SIZE.y * 0.5 - 7.0 and cl.z < MarshLayout.CASTLE_SIZE.y * 0.5 + 2.0:
		return 0.0                                 # 石岛上不长（石台两边的水里照样长）
	if on_mud:
		return 0.28                                # 泥滩上是矮的草丛（_job_reeds 缩小）
	if shore:
		return 0.85
	for r: Rect2 in MarshLayout.REED_BEDS:
		if r.has_point(p):
			return 0.7
	return 0.0


static func _in_house(h: Array, p: Vector2, grow: float) -> bool:
	var s: Dictionary = h[3]
	var w := float(s.w)
	var d := float(s.d)
	var reach := House.stair_reach(MarshLayout.STILTS)
	var f := {"c": House.local_xz(MarshLayout.house_pos(h), float(h[2]), Vector2(0, (reach - d) * 0.5)), "size": Vector2(w, d + reach), "yaw": float(h[2])}
	return MarshLayout.contains(f, p, grow)


## 一片芦苇（32 米见方）：网格抖动取点，按 _reed_chance 留下，做成一个多实例（不投影子）；位置另记在元数据 spots（无头测试读不回多实例的变换）
func _job_reeds(root: Node3D, r: Rect2, kind: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(r.position)
	var spots := PackedVector3Array()
	var x := r.position.x
	while x < r.end.x:
		var z := r.position.y
		while z < r.end.y:
			var p := Vector2(x + rng.randf_range(0.1, 0.9) * REED_STEP, z + rng.randf_range(0.1, 0.9) * REED_STEP)
			var roll := rng.randf()
			z += REED_STEP
			if roll < _reed_chance(p):
				var y := MarshLayout.MUD_Y if on_floor(floors, grid, p) else MarshLayout.WATER_Y - 0.05
				spots.append(Vector3(p.x, y, p.y))
		x += REED_STEP
	if spots.is_empty():
		return
	for i in range(spots.size() - 1, 0, -1):                 # 打乱：低画质只画前一半时也是均匀的
		var j := rng.randi_range(0, i)
		var t := spots[i]
		spots[i] = spots[j]
		spots[j] = t
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = reed_meshes[kind]
	mm.instance_count = spots.size()
	for i in spots.size():
		var sc := rng.randf_range(0.8, 1.25) if spots[i].y < MarshLayout.MUD_Y - 0.01 else rng.randf_range(0.3, 0.55)     # 泥滩上是矮草丛
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc * rng.randf_range(0.85, 1.15), sc))
		mm.set_instance_transform(i, Transform3D(b, spots[i]))
		var v := rng.randf_range(0.85, 1.12)
		mm.set_instance_color(i, Color(v, v * rng.randf_range(0.96, 1.03), v * rng.randf_range(0.9, 1.0)))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Reeds_%d_%d" % [int(r.position.x), int(r.position.y)]
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.add_to_group("reeds")
	mmi.set_meta("spots", spots)
	root.add_child(mmi)


## 按画质画多少芦苇（低画质一半）：main 换画质、换时段（_refresh_edges）时对全部，后搭的块搭好时对这一块
static func refresh(tree: SceneTree, low: bool) -> void:
	for n in tree.get_nodes_in_group("reeds"):
		_reed_share(n, low)


static func refresh_in(root: Node, low: bool) -> void:
	for n in root.find_children("Reeds_*", "MultiMeshInstance3D", true, false):
		_reed_share(n, low)


static func _reed_share(n: Node, low: bool) -> void:
	var mm := (n as MultiMeshInstance3D).multimesh
	mm.visible_instance_count = int(mm.instance_count * REED_LOW_SHARE) if low else -1


# ---------------- 雾带、灯 ----------------

func _job_fog(root: Node3D, list: Array) -> void:
	for item in list:
		var f: Array = item[1]
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(12.0, 10.0)
		mi.mesh = pm
		mi.material_override = Look.fog_material(float(f[1]), reduced_motion)
		mi.position = f[0]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.set_meta("fog_index", int(item[0]))
		mi.add_to_group("fog_band")
		root.add_child(mi)


## 灯：[位置, 真的光源？]——客栈门口、小码头、堡门两边是真的（火光，站在下面谁都看得见你）；几户门口、石拱上是假的（发光的玻璃 + 光晕）。都是夜灯，白天灭
func _lamps_in(id: String) -> Array:
	var out := []
	var rect := _cell_rect(id)
	var inn: Array = MarshLayout.HOUSES[0]
	var spec: Dictionary = inn[3]
	var door := House.door_xz(MarshLayout.house_pos(inn), float(inn[2]), float(spec.door_x))
	var list := [
		[Vector3(door.x - 1.0, MarshLayout.DECK_Y + MarshLayout.STILTS + 2.3, door.y + 1.0), true, MarshLayout.DECK_Y + MarshLayout.STILTS],     # 门西边（东边是招牌）
		[Vector3(55.6, MarshLayout.DECK_Y + 1.9, 61.6), true, MarshLayout.DECK_Y],
		[Vector3(88 - 1.5 + 0.9, MarshLayout.DECK_Y + MarshLayout.STILTS + 2.1, 25.96 + 0.9), false, MarshLayout.DECK_Y + MarshLayout.STILTS],
		[Vector3(64 + 1.4 - 0.9, MarshLayout.DECK_Y + MarshLayout.STILTS + 2.1, 34.04 - 0.9), false, MarshLayout.DECK_Y + MarshLayout.STILTS],
		[Vector3(49.25, MarshLayout.DECK_Y + 1.9, 47.0), false, MarshLayout.DECK_Y],
		[MarshLayout.cw3(MarshLayout.ARCH_T - 1.25, 2.0, MarshLayout.CAUSE_Y + 3.4), false, -1.0],     # 挂在石拱墩子上（_job_arch 搭铁臂）
	]
	var xf := MarshLayout.castle_xform()
	for sx in [-1.0, 1.0]:
		list.append([xf * Vector3(sx * 2.4, 3.6, MarshLayout.CASTLE_SIZE.y * 0.5 + 2.0), true, -1.0])
	for l in list:
		var p: Vector3 = l[0]
		if rect.has_point(Vector2(p.x, p.z)):
			out.append(l)
	return out


func _job_lamps(root: Node3D, id: String) -> void:
	var kit := MeshKit.new()
	for l in _lamps_in(id):
		var p: Vector3 = l[0]
		var foot := float(l[2])
		kit.box("ember", p, Vector3(0.18, 0.26, 0.18))
		kit.box("timber", p + Vector3(0, 0.16, 0), Vector3(0.24, 0.05, 0.24))
		if foot > -0.5:                                      # 立在栈道 / 平台上的灯杆
			kit.box("timber", Vector3(p.x, (p.y + foot) * 0.5, p.z), Vector3(0.1, p.y - foot, 0.1), Basis.IDENTITY, 0.8, 0.5)
		var halo := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(1.3, 1.3)
		var hm := Look.halo(Look.LAMP_COLOR, 0.55).duplicate() as StandardMaterial3D
		hm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		q.material = hm
		halo.mesh = q
		halo.position = p
		root.add_child(halo)
		if bool(l[1]):
			var light := Tavern.FireLight.new()
			light.light_color = Look.LAMP_COLOR
			light.base = 1.5
			light.omni_range = 8.0
			light.omni_attenuation = 1.15
			light.position = p + Vector3(0, -0.1, 0)
			light.flicker = not reduced_motion
			light.add_to_group("light_source")
			light.set_meta("radius", 5.0)
			Daypart.mark_night_light(light, halo)
			root.add_child(light)
		else:
			var lamp := Node3D.new()                         # 假灯：只有光晕，白天跟着藏起来
			lamp.position = p
			root.add_child(lamp)
			Daypart.mark_night_light(lamp, halo)
	root.add_child(kit.build({"ember": _ember_mat(), "timber": Look.mat("timber")}))


static func _ember_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color("ffb060")
	return m


static func _rope_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("6a5a40")
	m.roughness = 1.0
	m.vertex_color_use_as_albedo = true
	return m


# ---------------- 地图（3.11 的格式，由布局表生成） ----------------

## 整张图：水面、芦苇荡、泥滩、干地、栈道、堤道、房子、黑鹭堡、路牌；分块（芦栈村 / 堤道 / 黑鹭堡外）。
## 4.4a 还没有通往别的区域的门（出发走路牌、旅行地图），出口是空的
static func map_spec() -> Dictionary:
	var shapes := []
	shapes.append({"k": "water", "rect": MarshLayout.BOUNDS})      # 不写字：图中心正好在断口上，字会盖住它（审查）
	for i in MarshLayout.REED_BEDS.size():
		var sh := {"k": "reeds", "rect": (MarshLayout.REED_BEDS[i] as Rect2).intersection(MarshLayout.BOUNDS)}
		if i == 0:
			sh["label"] = "芦苇荡"
		shapes.append(sh)
	var labels := {"village_mud": "泥潭", "peat_yard": "泥炭场", "bank": "村口", "cw_b": "堤道", "dock": "小码头"}
	for f in MarshLayout.floors():
		var k := str(f.k)
		var kind := str({"mud": "mud", "land": "land", "deck": "pier", "bridge": "pier", "stone": "road", "slope": "road"}.get(k, ""))
		if kind == "":
			continue
		var sh := {"k": kind, "pts": MarshLayout.corners(f)}
		if labels.has(str(f.id)):
			sh["label"] = labels[str(f.id)]
		shapes.append(sh)
	for h in MarshLayout.HOUSES:
		var s: Dictionary = h[3]
		var sh := {"k": "house", "pts": House.footprint(MarshLayout.house_pos(h), float(h[2]), float(s.w), float(s.d))}
		if str(h[0]) == "inn":
			sh["label"] = "客栈"
		shapes.append(sh)
	var th: Vector2 = MarshLayout.TOBIN_HUT[0]
	var ts: Dictionary = MarshLayout.TOBIN_HUT[2]
	shapes.append({"k": "house", "pts": House.footprint(Vector3(th.x, 0, th.y), float(MarshLayout.TOBIN_HUT[1]), float(ts.w), float(ts.d))})
	var xf := MarshLayout.castle_xform()
	var hw := MarshLayout.CASTLE_SIZE.x * 0.5
	var hd := MarshLayout.CASTLE_SIZE.y * 0.5
	var castle := PackedVector2Array()
	for c in [Vector3(-hw, 0, -hd), Vector3(hw, 0, -hd), Vector3(hw, 0, hd), Vector3(-hw, 0, hd)]:
		var w3: Vector3 = xf * c
		castle.append(Vector2(w3.x, w3.z))
	shapes.append({"k": "house", "pts": castle, "label": "黑鹭堡"})
	shapes.append({"k": "mark", "at": Vector2(MarshLayout.SIGN_VILLAGE.x, MarshLayout.SIGN_VILLAGE.z), "icon": "sign", "label": "路牌"})
	shapes.append({"k": "mark", "at": Vector2(MarshLayout.SIGN_GATE.x, MarshLayout.SIGN_GATE.z), "icon": "sign", "label": "路牌"})
	return {"bounds": MarshLayout.BOUNDS, "shapes": shapes, "exits": [], "zones": MarshLayout.zones()}
