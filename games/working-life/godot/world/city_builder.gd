class_name CityBuilder
extends Node3D
## 新澜市（NEO LAN）城市生成器。所有建筑、道路、街道设施都在这里用代码生成（无外部美术素材）：
##   5×5 条道路把城市分成 16 个街区 + 南边的火车站；
##   data/locations.json 里的地点按类型（shop / tower / home / station / park / site / warehouse / oldtown）
##   用 BuildingKit 的模块拼出来，剩余空地用填充高楼补齐；城市外围是远景天际线。
## 同时生成：碰撞体、导航网格、地点触发器、交互点、公交 / 地铁站、自动售货机。

const ROADS := [-160.0, -80.0, 0.0, 80.0, 160.0]
const BLOCK_CENTERS := [-120.0, -40.0, 40.0, 120.0]
const ROAD_HALF := 5.0
const WALK_HALF := 8.0
const LIMIT := 204.0
const NEON_COLORS := [Color(1.0, 0.18, 0.53), Color(0.13, 0.9, 1.0), Color(1.0, 0.82, 0.25), Color(0.69, 0.3, 1.0), Color(0.49, 1.0, 0.42), Color(1.0, 0.35, 0.2)]

var batcher := MeshBatcher.new()
var night_batcher := MeshBatcher.new()
var body: StaticBody3D
var kit: BuildingKit
var props_root: Node3D
var night_root: Node3D
var lamp_pool: LampPool
## 世界坐标矩形：已被建筑占用（填充高楼避开这些区域）
var occupied: Array = []
## 行人可以去的路点（人行道上）
var sidewalk_points: Array = []
## 搬运小游戏用的点
var carry_pile := Vector3.ZERO
var carry_zone := Vector3.ZERO
## 开场：列车轨道高度与站台位置
const TRACK_Z := 200.0
const TRACK_Y := 8.0
var nav_region: NavigationRegion3D
var station_spawn := Vector3(0, 0.1, 172)
var viewpoint := Vector3(-40, 4.2, -56)


func build() -> void:
	body = StaticBody3D.new()
	body.name = "WorldCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	props_root = Node3D.new()
	props_root.name = "Props"
	add_child(props_root)
	night_root = Node3D.new()
	night_root.name = "NightOnly"
	add_child(night_root)
	kit = BuildingKit.new(batcher, night_batcher, body, props_root)
	_ground()
	_roads()
	for id in DataDB.ids("locations"):
		_build_location(id, DataDB.location(id))
	_fillers()
	_transit_stops()
	_palms_and_parking()
	_intersections()
	_city_edge()
	_vending_machines()
	_street_props()
	_track()
	_skyline()
	_bounds()
	var geo := Node3D.new()
	geo.name = "Geometry"
	add_child(geo)
	batcher.build(geo, true)
	night_batcher.chunked = false
	night_batcher.build(night_root, false)
	lamp_pool = LampPool.new()
	lamp_pool.name = "LampPool"
	add_child(lamp_pool)
	lamp_pool.setup(kit.lamp_points)
	_build_navigation()


func set_night(on: bool) -> void:
	night_root.visible = on


# ================================================================ 地面与道路
func _ground() -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(LIMIT * 2 + 40, LIMIT * 2 + 40)
	mi.mesh = pm
	mi.material_override = Mats.photo_ground("main", "concrete_albedo", 6.0, Color(0.72, 0.72, 0.72))
	mi.name = "Ground"
	add_child(mi)
	kit.collide(Vector3(0, -0.5, 0), Vector3(LIMIT * 2 + 40, 1.0, LIMIT * 2 + 40))
	# 城外远景地面（更暗）
	var far := MeshInstance3D.new()
	var fp := PlaneMesh.new()
	fp.size = Vector2(1400, 1400)
	far.mesh = fp
	far.position = Vector3(0, -0.05, 0)
	far.material_override = Mats.photo_ground("far", "dirt_albedo", 10.0, Color(0.9, 0.9, 0.9))
	add_child(far)


func _roads() -> void:
	var road_col := Color(0.95, 0.95, 0.95)
	var walk_col := Color(1.0, 1.0, 1.0)
	var span := LIMIT + 8.0
	# 南北向道路（x 固定）：整条；东西向道路在路口之间分段，避免重叠闪烁
	for x in ROADS:
		batcher.box("road", Vector3(x, 0.012, 0), Vector3(ROAD_HALF * 2, 0.024, span * 2), road_col, Basis.IDENTITY, true)
		_lane_marks(Vector3(x, 0.026, 0), Vector3(0, 0, 1), span * 2)
	var edges := [-span] + ROADS + [span]
	for z in ROADS:
		for i in range(edges.size() - 1):
			var a: float = edges[i] + (ROAD_HALF if i > 0 else 0.0)
			var bb: float = edges[i + 1] - (ROAD_HALF if i + 1 < edges.size() - 1 else 0.0)
			if bb - a < 0.5:
				continue
			batcher.box("road", Vector3((a + bb) * 0.5, 0.012, z), Vector3(bb - a, 0.024, ROAD_HALF * 2), road_col, Basis.IDENTITY, true)
			_lane_marks(Vector3((a + bb) * 0.5, 0.026, z), Vector3(1, 0, 0), bb - a)
	# 人行道：在路口之间分段
	for road in ROADS:
		for i in range(edges.size() - 1):
			var a2: float = edges[i] + (WALK_HALF if i > 0 else 0.0)
			var b2: float = edges[i + 1] - (WALK_HALF if i + 1 < edges.size() - 1 else 0.0)
			if b2 - a2 < 0.5:
				continue
			var mid := (a2 + b2) * 0.5
			var length := b2 - a2
			for side in [-1.0, 1.0]:
				var off: float = road + side * (ROAD_HALF + 1.5)
				batcher.box("walk", Vector3(off, 0.03, mid), Vector3(3.0, 0.06, length), walk_col, Basis.IDENTITY, true)
				batcher.box("walk", Vector3(mid, 0.031, off), Vector3(length, 0.062, 3.0), walk_col, Basis.IDENTITY, true)
				# 路缘石
				batcher.box("concrete", Vector3(road + side * (ROAD_HALF + 0.15), 0.07, mid), Vector3(0.3, 0.14, length), Color(0.95, 0.95, 0.95), Basis.IDENTITY, true)
				batcher.box("concrete", Vector3(mid, 0.07, road + side * (ROAD_HALF + 0.15)), Vector3(length, 0.14, 0.3), Color(0.95, 0.95, 0.95), Basis.IDENTITY, true)
				# 路灯与行人路点
				# 两个方向的道路两侧每 24 米一盏；大多是钠灯暖黄，主干道（x / z = 0）是 LED 冷白
				var n := int(length / 24.0)
				for k in n:
					var t := a2 + 12.0 + k * 24.0
					var warm := absf(road) > 1.0
					kit.streetlight(Vector3(road + side * (ROAD_HALF + 2.6), 0, t), PI * 0.5 * (-side), warm)
					kit.streetlight(Vector3(t, 0, road + side * (ROAD_HALF + 2.6)), PI if side > 0 else 0.0, warm)
				var m := int(length / 10.0)
				for k in m:
					var t2 := a2 + 5.0 + k * 10.0
					if absf(t2) < LIMIT - 4:
						sidewalk_points.append(Vector3(road + side * (ROAD_HALF + 1.5), 0.05, t2))
						sidewalk_points.append(Vector3(t2, 0.05, road + side * (ROAD_HALF + 1.5)))
	# 斑马线（霓虹白）
	for x in ROADS:
		for z in ROADS:
			for k in 6:
				var o := -3.75 + k * 1.5
				batcher.box("decal", Vector3(x + o, 0.03, z - ROAD_HALF - 1.4), Vector3(0.7, 0.02, 2.2), Color(0.35, 0.38, 0.42), Basis.IDENTITY, true)
				batcher.box("decal", Vector3(x + o, 0.03, z + ROAD_HALF + 1.4), Vector3(0.7, 0.02, 2.2), Color(0.35, 0.38, 0.42), Basis.IDENTITY, true)


func _lane_marks(center: Vector3, dir: Vector3, length: float) -> void:
	var n := int(length / 8.0)
	for i in n:
		var t := -length * 0.5 + 4.0 + i * 8.0
		var p := center + dir * t
		var size := Vector3(0.15, 0.01, 3.0) if dir.z > 0.5 else Vector3(3.0, 0.01, 0.15)
		batcher.box("decal", p, size, Color(0.5, 0.42, 0.12), Basis.IDENTITY, true)


# ================================================================ 地点
func _build_location(id: String, d: Dictionary) -> void:
	var c: Array = d.get("center", [0, 0])
	var s: Array = d.get("size", [20, 20])
	var frame := BuildingKit.make_frame(Vector2(float(c[0]), float(c[1])), Vector2(float(s[0]), float(s[1])), String(d.get("facing", "s")))
	var neon := Mats.hex(String(d.get("neon", "#22e4ff")))
	var loc := LocationNode.new()
	props_root.add_child(loc)
	loc.setup(id, d, frame)
	var occ_w: float = frame["w"]
	var occ_d: float = frame["d"]
	if absf(sin(float(frame["yaw"]))) > 0.5:
		var tmp := occ_w
		occ_w = occ_d
		occ_d = tmp
	occupied.append(Rect2(float(c[0]) - occ_w * 0.5 - 4, float(c[1]) - occ_d * 0.5 - 4, occ_w + 8, occ_d + 8))
	match String(d.get("type", "shop")):
		"shop":
			_shop(id, d, frame, neon)
		"tower":
			_tower(id, d, frame, neon)
		"home":
			_home(id, d, frame, neon)
		"station":
			_station(id, d, frame, neon)
		"park":
			_park(id, d, frame, neon)
		"site":
			_site(id, d, frame, neon)
		"warehouse":
			_warehouse(id, d, frame, neon)
		"oldtown":
			_oldtown(id, d, frame, neon)
	_points(id, d, frame)


## 把 data 里的 points 变成交互点，并按类型摆上对应的家具
func _points(id: String, d: Dictionary, frame: Dictionary) -> void:
	var loc_type := String(d.get("type", ""))
	for p in d.get("points", []):
		var pos: Array = p.get("pos", [0, 0])
		var lx := float(pos[0])
		var lz := float(pos[1])
		var y := float(p.get("elevated", 0.0))
		var kind := String(p.get("kind", ""))
		var sp := ServicePoint.new()
		props_root.add_child(sp)
		sp.setup(kind, String(p.get("label", "")), id, p, String(p.get("key", "interact")))
		sp.global_transform = Transform3D(frame["basis"], BuildingKit.xf(frame, lx, y, lz))
		GameManager.register("point:%s:%s" % [id, kind if not p.has("job") else kind + "_" + String(p["job"])], sp)
		match kind:
			"shop", "interview", "bank_counter", "hotel_desk", "hospital", "lease", "incubator":
				if loc_type != "oldtown":
					kit.counter(frame, lx, lz - 1.3, 3.2)
			"workstation":
				if loc_type in ["tower", "shop"]:
					kit.desk(frame, lx, lz - 1.0)
				elif loc_type == "warehouse":
					kit.lbox(frame, "metal", Vector3(lx, 0.45, lz - 1.1), Vector3(3.0, 0.9, 1.2), Color(0.3, 0.32, 0.36))
					kit.lbox(frame, "neon", Vector3(lx, 1.2, lz - 1.6), Vector3(1.2, 0.6, 0.05), Color(1, 0.8, 0.2), false)
			"course":
				kit.lbox(frame, "solid", Vector3(lx, 0.55, lz - 1.2), Vector3(1.4, 1.1, 0.8), Color(0.25, 0.22, 0.3))
			"atm":
				kit.lbox(frame, "solid", Vector3(lx, 1.0, lz - 0.6), Vector3(1.0, 2.0, 0.6), Color(0.18, 0.2, 0.25))
				kit.lbox(frame, "neon", Vector3(lx, 1.35, lz - 0.28), Vector3(0.6, 0.45, 0.04), Color(1, 0.82, 0.25), false)
			"jobboard":
				kit.lbox(frame, "solid", Vector3(lx, 1.6, lz - 0.8), Vector3(3.6, 2.4, 0.2), Color(0.08, 0.08, 0.1))
				kit.lbox(frame, "neon", Vector3(lx, 1.6, lz - 0.68), Vector3(3.3, 2.1, 0.04), Color(1.0, 0.82, 0.25) * 0.55, false)
				kit.label("招聘信息", BuildingKit.xf(frame, lx, 2.4, lz - 0.6), float(frame["yaw"]), 64, Color(1.2, 1.1, 0.6), 0.01, 6)
			"gym":
				for k in 3:
					kit.lbox(frame, "metal", Vector3(lx - 2.0 + k * 2.0, 0.6, lz - 1.5), Vector3(0.8, 1.2, 1.8), Color(0.2, 0.2, 0.24))
					kit.lbox(frame, "neon", Vector3(lx - 2.0 + k * 2.0, 1.25, lz - 1.5), Vector3(0.82, 0.05, 1.82), Color(1, 0.2, 0.55), false)
			"bench":
				kit.bench(BuildingKit.xf(frame, lx, 0, lz - 0.8), float(frame["yaw"]))
			"relax":
				kit.table_set(frame, lx, lz - 1.2)
			"rooftop":
				kit.lbox(frame, "metal", Vector3(lx, y + 0.5, lz - 1.8), Vector3(3.0, 1.0, 0.1), Color(0.3, 0.3, 0.35), false)
				kit.lbox(frame, "neon", Vector3(lx, y + 1.02, lz - 1.8), Vector3(3.0, 0.05, 0.12), Color(0.5, 1.0, 0.4), false)


func _npc_counters(d: Dictionary, frame: Dictionary) -> void:
	pass


func _shop(id: String, d: Dictionary, frame: Dictionary, neon: Color) -> void:
	var h0 := 5.0
	var floors := int(d.get("floors", 3))
	kit.shell(frame, h0, BuildingKit.C_CONCRETE2)
	kit.tower_mass(frame, h0 + 0.3, maxf(3.6, (floors - 1) * 3.6), BuildingKit.C_CONCRETE, neon, 1)
	kit.sign(frame, h0, String(d.get("name", "")), String(d.get("en", "")), neon)
	kit.add_obstacle_frame(frame)
	var w: float = frame["w"]
	var dd: float = frame["d"]
	kit.omni(BuildingKit.xf(frame, 0, h0 - 0.8, 0), Color(0.9, 0.93, 1.0).lerp(neon, 0.2), 1.8, maxf(w, dd) * 0.9)
	match id:
		"store", "supermarket":
			kit.shelf(frame, -w * 0.5 + 0.9, 1.5, dd * 0.45, true)
			kit.shelf(frame, w * 0.5 - 0.9, 1.5, dd * 0.45, true)
			kit.shelf(frame, -w * 0.18, 2.0, dd * 0.28, true)
			if id == "supermarket":
				kit.shelf(frame, w * 0.18, 2.0, dd * 0.28, true)
				kit.shelf(frame, -w * 0.35, 2.0, dd * 0.28, true)
		"restaurant", "cafe":
			for t in [Vector2(-4, 2.5), Vector2(2.5, 3.5), Vector2(-4, 5.5)]:
				if absf(t.x) < w * 0.5 - 1.5:
					kit.table_set(frame, t.x, t.y)
		"talent_market":
			for k in 3:
				kit.lbox(frame, "prop", Vector3(-2 + k * 2.5, 0.25, 3.5), Vector3(1.8, 0.5, 0.6), Color(0.3, 0.3, 0.4), false)
		"training_school":
			for row in 2:
				for col in 4:
					kit.lbox(frame, "solid", Vector3(-6 + col * 3.0, 0.38, -3.5 + row * 2.2), Vector3(1.6, 0.76, 0.6), Color(0.28, 0.26, 0.32), false)
			kit.lbox(frame, "neon", Vector3(0, 2.8, -dd * 0.5 + 0.45), Vector3(6, 2.2, 0.05), Color(0.3, 1.0, 0.45) * 0.6, false)
		"hospital":
			for k in 3:
				kit.lbox(frame, "solid", Vector3(-w * 0.5 + 1.5, 0.4, -6 + k * 3.0), Vector3(1.0, 0.8, 2.1), Color(0.8, 0.85, 0.9))
			kit.label("新澜第一医院", BuildingKit.xf(frame, 0, 0.0, 0) + Vector3(0, 30, 0), float(frame["yaw"]), 96, Color(0.4, 1.4, 1.6), 0.03, 0)
		"bank":
			kit.lbox(frame, "glass", Vector3(0, 2.0, -3.9), Vector3(6.0, 1.8, 0.05), Color(0.4, 0.6, 0.7), false)
		"gym":
			for k in 3:
				kit.lbox(frame, "metal", Vector3(-5 + k * 2.5, 0.5, 3.0), Vector3(0.9, 1.0, 2.0), Color(0.18, 0.18, 0.22))


func _tower(id: String, d: Dictionary, frame: Dictionary, neon: Color) -> void:
	var h0 := 6.0
	var floors := int(d.get("floors", 12))
	kit.shell(frame, h0, BuildingKit.C_CONCRETE2, 6.0)
	kit.tower_mass(frame, h0 + 0.3, (floors - 1) * 3.6, BuildingKit.C_CONCRETE, neon, 1, "glass" if floors > 14 else "office", false)
	kit.sign(frame, h0, String(d.get("name", "")), String(d.get("en", "")), neon)
	kit.add_obstacle_frame(frame)
	var w: float = frame["w"]
	var dd: float = frame["d"]
	var top := h0 + (floors - 1) * 3.6
	# 楼顶巨型霓虹字
	kit.label(String(d.get("en", "")), BuildingKit.xf(frame, 0, top - 3.0, dd * 0.5 + 0.3), float(frame["yaw"]), 128, neon * 1.5, 0.05, 0)
	kit.omni(BuildingKit.xf(frame, -w * 0.25, h0 - 1.0, -2), Color(0.85, 0.92, 1.0), 1.0, w * 0.6)
	kit.omni(BuildingKit.xf(frame, w * 0.25, h0 - 1.0, -2), Color(0.85, 0.92, 1.0).lerp(neon, 0.3), 1.0, w * 0.6)
	# 办公区：几排工位
	if id != "mall":
		for row in 2:
			for col in 3:
				var lx := -w * 0.5 + 4.0 + col * 2.4
				kit.desk(frame, lx, -dd * 0.5 + 3.0 + row * 2.6)
				kit.desk(frame, -lx, -dd * 0.5 + 3.0 + row * 2.6)
		kit.plant(frame, -w * 0.5 + 1.5, dd * 0.5 - 2.0)
		kit.plant(frame, w * 0.5 - 1.5, dd * 0.5 - 2.0)
		# 大堂全息屏
		kit.lbox(frame, "holo", Vector3(0, 3.2, -dd * 0.5 + 0.5), Vector3(8, 3.5, 0.05), neon * 0.5, false)
	else:
		# 商场中庭：全息投影与店铺隔断
		b_atrium(frame, neon)


func b_atrium(frame: Dictionary, neon: Color) -> void:
	kit.lbox(frame, "solid", Vector3(0, 0.3, 0), Vector3(4, 0.6, 4), Color(0.2, 0.2, 0.25))
	kit.lbox(frame, "holo", Vector3(0, 3.0, 0), Vector3(3, 4, 3), neon * 0.5, false)
	for sx in [-1.0, 1.0]:
		kit.lbox(frame, "solid", Vector3(sx * 8.5, 2.5, -8), Vector3(0.3, 5, 8), BuildingKit.C_CONCRETE2)
		kit.shelf(frame, sx * 20.0, -6, 8.0, true)


func _home(id: String, d: Dictionary, frame: Dictionary, neon: Color) -> void:
	var h0 := 4.2
	var floors := int(d.get("floors", 5))
	var w: float = frame["w"]
	var dd: float = frame["d"]
	kit.shell(frame, h0, BuildingKit.C_CONCRETE2, 2.6)
	if id == "villa":
		kit.tower_mass(frame, h0 + 0.3, 3.6 * 2, Color(0.85, 0.85, 0.82), neon, 1, "res")
	else:
		kit.tower_mass(frame, h0 + 0.3, maxf(3.6, (floors - 1) * 3.6), BuildingKit.C_CONCRETE if id != "hotel" else Color(0.2, 0.14, 0.18), neon, 1, "cyber" if id == "hotel" else "res")
	kit.sign(frame, h0, String(d.get("name", "")), String(d.get("en", "")), neon)
	kit.add_obstacle_frame(frame)
	# 隔墙：前半是大堂 / 前台，后半是住户的房间
	var gap := 1.6
	var seg := (w - gap) * 0.5
	for sx in [-1.0, 1.0]:
		kit.lbox(frame, "solid", Vector3(sx * (gap * 0.5 + seg * 0.5), h0 * 0.5, 0), Vector3(seg, h0, 0.3), Color(0.3, 0.28, 0.32))
	kit.lbox(frame, "solid", Vector3(0, (h0 + 2.6) * 0.5, 0), Vector3(gap, h0 - 2.6, 0.3), Color(0.3, 0.28, 0.32))
	var door := Door.new()
	props_root.add_child(door)
	door.setup(id, gap, 2.5)
	door.global_transform = Transform3D(frame["basis"], BuildingKit.xf(frame, 0, 0, 0))
	GameManager.register("door:" + id, door)
	# 房间家具
	var bed_col := Color(0.25, 0.35, 0.6) if id != "hotel" else Color(0.5, 0.45, 0.4)
	kit.lbox(frame, "solid", Vector3(-w * 0.5 + 1.6, 0.3, -dd * 0.5 + 1.8), Vector3(2.0, 0.6, 2.8), Color(0.3, 0.25, 0.22))
	kit.lbox(frame, "prop", Vector3(-w * 0.5 + 1.6, 0.68, -dd * 0.5 + 1.8), Vector3(1.9, 0.18, 2.7), bed_col, false)
	kit.lbox(frame, "prop", Vector3(-w * 0.5 + 1.6, 0.8, -dd * 0.5 + 0.7), Vector3(1.4, 0.2, 0.5), Color(0.9, 0.9, 0.92), false)
	kit.lbox(frame, "solid", Vector3(w * 0.5 - 0.8, 1.1, -dd * 0.5 + 2.5), Vector3(1.0, 2.2, 2.0), Color(0.35, 0.28, 0.24))
	kit.desk(frame, w * 0.5 - 2.4, -1.9, Color(0.4, 0.9, 1.0))
	kit.lbox(frame, "neon", Vector3(0, h0 - 0.1, -dd * 0.25), Vector3(2.0, 0.05, 0.2), neon * 0.8, false)
	if id in ["luxury_apartment", "villa"]:
		kit.lbox(frame, "prop", Vector3(0, 0.4, -dd * 0.25 - 1.0), Vector3(3.0, 0.8, 1.0), Color(0.5, 0.2, 0.3), false)
		kit.plant(frame, -w * 0.5 + 1.0, -1.2)
	kit.omni(BuildingKit.xf(frame, 0, h0 - 0.6, -dd * 0.25), Color(1.0, 0.9, 0.8), 1.8, maxf(w, dd) * 0.7)
	kit.lbox(frame, "neon", Vector3(0, h0 - 0.08, -dd * 0.3), Vector3(3.0, 0.05, 1.2), Color(1.0, 0.92, 0.8), false)
	kit.omni(BuildingKit.xf(frame, 0, h0 - 0.6, dd * 0.25), Color(0.85, 0.9, 1.0).lerp(neon, 0.3), 0.8, maxf(w, dd) * 0.5)
	# 房间里的交互点
	var pts := [
		["bed", "睡觉 / 保存", Vector2(-w * 0.5 + 1.6, -dd * 0.5 + 3.6), "interact"],
		["wardrobe", "衣柜：换衣服 / 储物", Vector2(w * 0.5 - 2.0, -dd * 0.5 + 2.5), "interact"],
		["computer", "使用电脑", Vector2(w * 0.5 - 2.4, -1.0), "pickup"],
	]
	for p in pts:
		var sp := ServicePoint.new()
		props_root.add_child(sp)
		sp.setup(String(p[0]), String(p[1]), id, {"home": String(d.get("home", ""))}, String(p[3]))
		var v: Vector2 = p[2]
		sp.global_transform = Transform3D(frame["basis"], BuildingKit.xf(frame, v.x, 0, v.y))
		GameManager.register("point:%s:%s" % [id, String(p[0])], sp)
	if id == "villa":
		# 花园与泳池
		var gx := BuildingKit.xf(frame, 0, 0, dd * 0.5 + 8.0)
		batcher.box("solid", gx + Vector3(0, 0.02, 0), Vector3(w + 8, 0.04, 14), Color(0.08, 0.22, 0.14), frame["basis"], true)
		batcher.box("water", BuildingKit.xf(frame, w * 0.25, 0.06, dd * 0.5 + 7.0), Vector3(8, 0.05, 5), Color(0.1, 0.6, 0.9), frame["basis"], true)
		batcher.box("neon", BuildingKit.xf(frame, w * 0.25, 0.09, dd * 0.5 + 9.55), Vector3(8, 0.05, 0.1), Color(0.2, 0.9, 1.0), frame["basis"], true)
		for k in 4:
			kit.tree(BuildingKit.xf(frame, -w * 0.5 - 2 + k * 2.5, 0, dd * 0.5 + 13.0), 4.5)


func _station(id: String, d: Dictionary, frame: Dictionary, neon: Color) -> void:
	var h0 := 11.0
	var w: float = frame["w"]
	var dd: float = frame["d"]
	kit.shell(frame, h0, Color(0.62, 0.62, 0.64), 18.0)
	kit.tower_mass(frame, h0 + 0.3, 7.2, BuildingKit.C_CONCRETE, neon, 1)
	kit.sign(frame, h0, String(d.get("name", "")), String(d.get("en", "")), neon)
	kit.add_obstacle_frame(frame)
	kit.label("新澜市 · NEO LAN CITY", BuildingKit.xf(frame, 0, h0 + 5.5, dd * 0.5 + 0.3), float(frame["yaw"]), 128, neon * 1.4, 0.03, 0)
	# 候车大厅：柱子、长椅、闸机、到站大屏
	for k in 6:
		var lx := -w * 0.5 + 8 + k * (w - 16) / 5.0
		kit.lbox(frame, "solid", Vector3(lx, h0 * 0.5, -2), Vector3(1.2, h0, 1.2), Color(0.26, 0.26, 0.3))
		kit.lbox(frame, "neon", Vector3(lx, h0 * 0.5, -1.38), Vector3(0.1, h0 - 1, 0.05), neon * 0.8, false)
	for k in 4:
		kit.bench(BuildingKit.xf(frame, -24 + k * 16, 0, 4), float(frame["yaw"]))
	for k in 8:
		kit.lbox(frame, "metal", Vector3(-10.5 + k * 3.0, 0.55, -7), Vector3(0.4, 1.1, 1.6), Color(0.3, 0.3, 0.34))
	kit.lbox(frame, "neon", Vector3(0, 6.5, -dd * 0.5 + 0.5), Vector3(20, 3, 0.05), Color(0.1, 0.5, 0.9), false)
	kit.label("G1024 · 到站  已到达", BuildingKit.xf(frame, 0, 6.6, -dd * 0.5 + 0.6), float(frame["yaw"]), 96, Color(1.5, 1.4, 0.8), 0.022, 0)
	# 高架站台（列车停靠处，玩家不可到达）
	kit.lbox(frame, "solid", Vector3(0, TRACK_Y - 0.6, -dd * 0.5 + 5.5), Vector3(w - 1, 0.4, 7), Color(0.22, 0.22, 0.26), false)
	kit.omni(BuildingKit.xf(frame, -20, h0 - 1, 0), Color(0.8, 0.9, 1.0), 1.2, 22)
	kit.omni(BuildingKit.xf(frame, 20, h0 - 1, 0), Color(0.8, 0.9, 1.0), 1.2, 22)
	# 站前广场
	var plaza := BuildingKit.xf(frame, 0, 0.02, dd * 0.5 + 6)
	batcher.box("solid", plaza, Vector3(w, 0.04, 12), Color(0.17, 0.17, 0.2), frame["basis"], true)
	for k in 5:
		batcher.box("neon", BuildingKit.xf(frame, -w * 0.4 + k * w * 0.2, 0.06, dd * 0.5 + 6), Vector3(0.12, 0.03, 10), neon * 0.6, frame["basis"], true)
	station_spawn = BuildingKit.xf(frame, 0, 0.1, dd * 0.5 + 9.0)


func _park(id: String, d: Dictionary, frame: Dictionary, neon: Color) -> void:
	var w: float = frame["w"]
	var dd: float = frame["d"]
	# 草地与小路
	kit.lbox(frame, "grass", Vector3(0, 0.02, 0), Vector3(w, 0.04, dd), Color(1, 1, 1), false)
	kit.lbox(frame, "walk", Vector3(0, 0.045, 0), Vector3(4, 0.03, dd), Color(0.9, 0.86, 0.8), false)
	kit.lbox(frame, "walk", Vector3(0, 0.046, 6), Vector3(w, 0.03, 3.5), Color(0.9, 0.86, 0.8), false)
	for sx in [-1.0, 1.0]:
		kit.lbox(frame, "neon", Vector3(sx * 2.1, 0.07, 0), Vector3(0.08, 0.02, dd), Color(0.4, 1.0, 0.45) * 0.6, false)
	# 池塘
	var pond := BuildingKit.xf(frame, -14, 0.05, 2)
	batcher.cylinder("water", pond, 7.0, 0.04, Color(0.05, 0.25, 0.45), 20)
	batcher.cylinder("neon", pond + Vector3(0, 0.02, 0), 7.2, 0.02, Color(0.2, 0.9, 1.0) * 0.6, 20)
	kit.obstacles.append(Rect2(pond.x - 7, pond.z - 7, 14, 14))
	# 树
	var tree_spots := [Vector2(-24, -24), Vector2(-18, -26), Vector2(22, -24), Vector2(26, -14), Vector2(-26, 18), Vector2(-22, 26), Vector2(24, 24), Vector2(14, 26), Vector2(26, 12), Vector2(-8, 20), Vector2(10, 18), Vector2(-26, -6), Vector2(18, -12), Vector2(-12, -24), Vector2(12, -26)]
	for i in tree_spots.size():
		var t: Vector2 = tree_spots[i]
		if i % 3 == 0:
			kit.palm(BuildingKit.xf(frame, t.x, 0, t.y), kit.rng.randf_range(9.0, 14.0))
		else:
			kit.tree(BuildingKit.xf(frame, t.x, 0, t.y), kit.rng.randf_range(4.0, 6.5))
	# 观景台：高 4 米，前方台阶
	var deck_h := 4.0
	kit.lbox(frame, "concrete", Vector3(0, deck_h * 0.5, -19), Vector3(12, deck_h, 7), Color(0.85, 0.85, 0.85))
	kit.lbox(frame, "neon", Vector3(0, deck_h + 0.05, -15.5), Vector3(12, 0.06, 0.1), Color(0.5, 1.0, 0.4), false)
	for sx in [-1.0, 1.0]:
		kit.lbox(frame, "metal", Vector3(sx * 5.9, deck_h + 0.55, -19), Vector3(0.1, 1.1, 7), Color(0.3, 0.3, 0.35))
	kit.lbox(frame, "metal", Vector3(0, deck_h + 0.55, -22.45), Vector3(12, 1.1, 0.1), Color(0.3, 0.3, 0.35))
	var steps := 8
	for k in steps:
		var sy := (k + 0.5) * deck_h / steps
		var sz := -9.5 - k * 0.75
		kit.lbox(frame, "concrete", Vector3(0, sy * 0.5, sz), Vector3(4, sy, 0.75), Color(0.8, 0.8, 0.8), false)
	# 台阶的碰撞用一整块斜坡，走上去更顺滑
	var run := steps * 0.75
	var ang := atan2(deck_h, run)
	var ramp_len := sqrt(run * run + deck_h * deck_h)
	var rot: Basis = (frame["basis"] as Basis) * Basis(Vector3.RIGHT, ang)
	kit.collide(BuildingKit.xf(frame, 0, deck_h * 0.5 - 0.12, -9.5 - run * 0.5 + 0.375), Vector3(4, 0.2, ramp_len), rot)
	viewpoint = BuildingKit.xf(frame, 0, deck_h + 0.1, -16)
	kit.obstacles.append(_frame_rect(frame, Vector2(0, -19), Vector2(12, 7)))
	# 园区入口牌
	kit.label("中央公园 CENTRAL PARK", BuildingKit.xf(frame, 0, 3.0, dd * 0.5 - 0.5), float(frame["yaw"]), 72, Color(0.6, 1.5, 0.7), 0.02, 6)
	kit.holo_board(BuildingKit.xf(frame, 20, 5, -4), float(frame["yaw"]), Vector2(8, 4), "绿色新澜", Color(0.4, 1.0, 0.5))


func _frame_rect(frame: Dictionary, lc: Vector2, size: Vector2) -> Rect2:
	var c := BuildingKit.xf(frame, lc.x, 0, lc.y)
	var s := size
	if absf(sin(float(frame["yaw"]))) > 0.5:
		s = Vector2(size.y, size.x)
	return Rect2(c.x - s.x * 0.5, c.z - s.y * 0.5, s.x, s.y)


func _site(id: String, d: Dictionary, frame: Dictionary, neon: Color) -> void:
	var w: float = frame["w"]
	var dd: float = frame["d"]
	kit.lbox(frame, "solid", Vector3(0, 0.02, 0), Vector3(w, 0.04, dd), Color(0.2, 0.17, 0.13), false)
	# 围挡：正面留 8 米大门
	var fence := Color(0.12, 0.3, 0.6)
	kit.lbox(frame, "solid", Vector3(0, 1.25, -dd * 0.5), Vector3(w, 2.5, 0.2), fence)
	kit.lbox(frame, "solid", Vector3(-w * 0.5, 1.25, 0), Vector3(0.2, 2.5, dd), fence)
	kit.lbox(frame, "solid", Vector3(w * 0.5, 1.25, 0), Vector3(0.2, 2.5, dd), fence)
	var seg := (w - 8.0) * 0.5
	for sx in [-1.0, 1.0]:
		kit.lbox(frame, "solid", Vector3(sx * (4.0 + seg * 0.5), 1.25, dd * 0.5), Vector3(seg, 2.5, 0.2), fence)
		kit.lbox(frame, "neon", Vector3(sx * (4.0 + seg * 0.5), 2.55, dd * 0.5 + 0.12), Vector3(seg, 0.08, 0.05), Color(1, 0.8, 0.2), false)
	kit.label("滨江项目 · 安全第一", BuildingKit.xf(frame, -14, 1.3, dd * 0.5 + 0.12), float(frame["yaw"]), 64, Color(1.4, 1.2, 0.5), 0.016, 6)
	# 在建主体：柱子与楼板
	for fl in 4:
		var y := fl * 3.6
		kit.lbox(frame, "solid", Vector3(-10, y + 3.5, -12), Vector3(24, 0.3, 16), Color(0.45, 0.44, 0.42), fl == 0)
		for cx in [-21.0, -15.0, -9.0, -3.0, 1.5]:
			for cz in [-19.5, -12.0, -4.5]:
				kit.lbox(frame, "solid", Vector3(cx, y + 1.75, cz), Vector3(0.5, 3.5, 0.5), Color(0.5, 0.49, 0.47), fl == 0)
	kit.obstacles.append(_frame_rect(frame, Vector2(-10, -12), Vector2(25, 17)))
	# 塔吊
	var base := BuildingKit.xf(frame, 12, 0, -14)
	for k in 12:
		batcher.box("metal", base + Vector3(0, 1.5 + k * 3.0, 0), Vector3(1.4, 3.0, 1.4), Color(0.95, 0.7, 0.1))
	batcher.box("metal", base + Vector3(-8, 37, 0), Vector3(34, 1.0, 1.0), Color(0.95, 0.7, 0.1))
	batcher.box("neon", base + Vector3(-24, 37.8, 0), Vector3(0.6, 0.6, 0.6), Color(1, 0.1, 0.1))
	batcher.box("neon", base + Vector3(9, 37.8, 0), Vector3(0.6, 0.6, 0.6), Color(1, 0.1, 0.1))
	kit.collide(base + Vector3(0, 18, 0), Vector3(1.4, 36, 1.4))
	# 材料堆（搬运小游戏的取料点）与卸货区
	carry_pile = BuildingKit.xf(frame, -18, 0, 12)
	carry_zone = BuildingKit.xf(frame, 8, 0, 2)
	for k in 5:
		batcher.box("solid", carry_pile + Vector3(-2 + k, 0.3 + (k % 2) * 0.3, -1.5), Vector3(0.9, 0.6 + (k % 2) * 0.6, 1.2), Color(0.7, 0.3, 0.2))
	batcher.box("decal", carry_zone + Vector3(0, 0.05, 0), Vector3(5, 0.02, 5), Color(0.6, 0.5, 0.05), Basis.IDENTITY, true)
	# 工地办公室（集装箱）
	kit.lbox(frame, "solid", Vector3(22, 1.3, 22), Vector3(6, 2.6, 3), Color(0.8, 0.5, 0.1))
	kit.lbox(frame, "neon", Vector3(22, 2.2, 23.55), Vector3(3, 0.5, 0.05), Color(0.2, 0.9, 1.0) * 0.7, false)
	kit.omni(BuildingKit.xf(frame, 0, 8, 0), Color(1.0, 0.85, 0.6), 1.2, 30)


func _warehouse(id: String, d: Dictionary, frame: Dictionary, neon: Color) -> void:
	var h0 := 9.0
	var w: float = frame["w"]
	var dd: float = frame["d"]
	kit.shell(frame, h0, Color(0.7, 0.68, 0.64), 18.0, false)
	kit.lbox(frame, "metal", Vector3(0, h0 + 1.0, 0), Vector3(w + 1, 1.6, dd + 1), Color(0.3, 0.32, 0.36), false)
	kit.sign(frame, h0 - 3.2, String(d.get("name", "")), String(d.get("en", "")), neon)
	kit.add_obstacle_frame(frame)
	for row in 3:
		for k in 2:
			var lx := -w * 0.5 + 3 + row * 3.4
			kit.lbox(frame, "metal", Vector3(lx, 2.5, -dd * 0.5 + 4 + k * 8), Vector3(1.2, 5, 6), Color(0.35, 0.38, 0.42))
			kit.lbox(frame, "metal", Vector3(-lx, 2.5, -dd * 0.5 + 4 + k * 8), Vector3(1.2, 5, 6), Color(0.35, 0.38, 0.42))
	# 传送带
	kit.lbox(frame, "metal", Vector3(0, 0.5, -dd * 0.5 + 3), Vector3(14, 1.0, 1.2), Color(0.2, 0.2, 0.22))
	kit.lbox(frame, "neon", Vector3(0, 1.02, -dd * 0.5 + 3), Vector3(14, 0.03, 0.1), Color(1, 0.8, 0.2), false)
	for k in 8:
		kit.lbox(frame, "prop", Vector3(-6 + k * 1.7, 1.25, -dd * 0.5 + 3), Vector3(0.6, 0.45, 0.5), Color(0.7, 0.55, 0.35), false)
	kit.omni(BuildingKit.xf(frame, 0, h0 - 1, 0), Color(1.0, 0.92, 0.75), 1.3, 26)


func _oldtown(id: String, d: Dictionary, frame: Dictionary, neon: Color) -> void:
	var w: float = frame["w"]
	var dd: float = frame["d"]
	kit.lbox(frame, "solid", Vector3(0, 0.02, 0), Vector3(w, 0.04, dd), Color(0.14, 0.12, 0.12), false)
	var shops := ["拉面", "网吧", "修手机", "按摩", "麻将", "当铺", "理发", "烧烤", "奶茶", "药店"]
	var i := 0
	for side in [-1.0, 1.0]:
		for k in 5:
			var lx: float = side * (w * 0.5 - 6.0)
			var lz := -dd * 0.5 + 6.0 + k * 11.0
			var h := kit.rng.randf_range(6.0, 12.0)
			var col := Color(0.2, 0.17, 0.17).lerp(Color(0.3, 0.2, 0.18), kit.rng.randf())
			kit.lbox(frame, "solid", Vector3(lx, h * 0.5, lz), Vector3(9, h, 9), col)
			kit.obstacles.append(_frame_rect(frame, Vector2(lx, lz), Vector2(9.6, 9.6)))
			var nc: Color = NEON_COLORS[i % NEON_COLORS.size()]
			var face: float = -side * 4.55
			kit.lbox(frame, "neon", Vector3(lx + face, 3.2, lz), Vector3(0.1, 1.2, 4.0), nc * 0.9, false)
			var yaw := float(frame["yaw"]) + (PI * 0.5 if side > 0 else -PI * 0.5)
			kit.label(shops[i % shops.size()], BuildingKit.xf(frame, lx + face - side * 0.08, 3.2, lz), yaw, 96, nc * 1.5, 0.012, 6)
			kit.lbox(frame, "win_warm", Vector3(lx + face, h * 0.7, lz), Vector3(0.1, 1.2, 6), Color(0.12, 0.12, 0.16), false)
			i += 1
	# 小吃摊与灯笼
	var stall := Vector2(0, 20)
	kit.lbox(frame, "solid", Vector3(stall.x, 0.5, stall.y - 1.3), Vector3(3.5, 1.0, 1.2), Color(0.4, 0.2, 0.15))
	kit.lbox(frame, "solid", Vector3(stall.x, 2.6, stall.y - 1.3), Vector3(4.0, 0.1, 2.4), Color(0.7, 0.15, 0.15), false)
	for k in 8:
		var lz2 := -dd * 0.5 + 4 + k * 7.5
		batcher.box("neon", BuildingKit.xf(frame, 0, 5.0 + sin(k) * 0.3, lz2), Vector3(0.5, 0.6, 0.5), Color(1.0, 0.25, 0.15))
	kit.omni(BuildingKit.xf(frame, 0, 4, 18), Color(1.0, 0.6, 0.35), 1.2, 16)
	kit.omni(BuildingKit.xf(frame, 0, 4, -10), Color(1.0, 0.4, 0.6), 1.0, 16)


# ================================================================ 填充高楼
func _fillers() -> void:
	var skip_types := ["park", "site", "oldtown"]
	var open_blocks: Array = []
	for id in DataDB.ids("locations"):
		var dd := DataDB.location(id)
		if String(dd.get("type", "")) in skip_types:
			var c: Array = dd["center"]
			open_blocks.append(Vector2(float(c[0]), float(c[1])))
	var n := 0
	for bx in BLOCK_CENTERS:
		for bz in BLOCK_CENTERS:
			if open_blocks.has(Vector2(bx, bz)):
				continue
			for ox in [-20.0, 0.0, 20.0]:
				for oz in [-20.0, 0.0, 20.0]:
					var size := Vector2(kit.rng.randf_range(12.0, 16.0), kit.rng.randf_range(12.0, 16.0))
					var c := Vector2(bx + ox, bz + oz)
					var r := Rect2(c - size * 0.5, size)
					var bad := false
					for o in occupied:
						if (o as Rect2).grow(2.0).intersects(r):
							bad = true
							break
					if bad:
						continue
					occupied.append(r)
					var h := kit.rng.randf_range(24.0, 60.0)
					if bz < -100:
						h += 40.0
					if bz > 100:
						h *= 0.6
					var col := Color(0.12, 0.12, 0.15).lerp(Color(0.2, 0.19, 0.24), kit.rng.randf())
					var neon: Color = NEON_COLORS[n % NEON_COLORS.size()]
					var yaw := 0.0 if bz < 0 else PI
					var frame := BuildingKit.make_frame(c, size, "s" if bz < 0 else "n")
					kit.lbox(frame, "solid", Vector3(0, 2.5, 0), Vector3(size.x, 5, size.y), Color(0.42, 0.41, 0.4))
					kit.lbox(frame, "win_warm" if n % 2 == 0 else "win_cool", Vector3(0, 2.2, size.y * 0.5 + 0.05), Vector3(size.x * 0.8, 3.0, 0.1), Color(0.25, 0.3, 0.36), false)
					kit.lbox(frame, "solid", Vector3(0, 3.9, size.y * 0.5 + 0.7), Vector3(size.x * 0.86, 0.15, 1.4), Color(0.2, 0.2, 0.22), false)
					kit.tower_mass(frame, 5.0, h, col, neon, 0 if n % 3 else 1)
					kit.obstacles.append(r.grow(0.6))
					if n % 4 == 1:
						kit.holo_board(BuildingKit.xf(frame, 0, h * 0.6, size.y * 0.5 + 0.8), yaw, Vector2(size.x * 0.8, size.x * 0.5), _slogan(n), neon)
					n += 1


func _slogan(i: int) -> String:
	var s := ["未来已来", "NEURAL LINK 2.0", "云途集团", "加班？来罐能量饮料", "星链科技", "梦想从这里起飞", "澜海资本", "脉冲健身 7×24", "一键租房 押一付一", "新澜银行 · 懂你的钱"]
	return s[i % s.size()]


# ================================================================ 交通站点、售货机、街道设施
func _transit_stops() -> void:
	for mode_id in ["bus", "metro"]:
		var m: Dictionary = DataDB.transport.get(mode_id, {})
		for s in m.get("stops", []):
			var p: Array = s["pos"]
			var pos := Vector3(float(p[0]), 0, float(p[1]))
			var col := Color(1.0, 0.82, 0.25) if mode_id == "bus" else Color(0.2, 0.9, 1.0)
			if mode_id == "bus":
				batcher.box("glass", pos + Vector3(0, 1.3, -0.8), Vector3(3.6, 2.4, 0.08), Color(0.3, 0.5, 0.6))
				batcher.box("metal", pos + Vector3(0, 2.6, -0.3), Vector3(3.8, 0.12, 1.4), Color(0.2, 0.2, 0.24))
				batcher.box("neon", pos + Vector3(0, 2.72, 0.35), Vector3(3.8, 0.1, 0.06), col)
				kit.label("公交 · %s" % String(s["name"]), pos + Vector3(0, 3.1, 0.3), 0.0, 48, col * 1.4, 0.012, 6)
			else:
				batcher.box("metal", pos + Vector3(0, 1.3, 0), Vector3(3.2, 2.6, 0.3), Color(0.15, 0.15, 0.18))
				batcher.box("neon", pos + Vector3(0, 2.8, 0), Vector3(1.0, 1.0, 0.35), col)
				kit.label("M", pos + Vector3(0, 2.8, 0.2), 0.0, 96, Color(0.05, 0.05, 0.1), 0.01, 0)
				kit.label("地铁 · %s" % String(s["name"]), pos + Vector3(0, 1.9, 0.2), 0.0, 48, col * 1.4, 0.012, 6)
			var sp := ServicePoint.new()
			props_root.add_child(sp)
			sp.setup("transit", "乘坐%s" % String(m.get("name", "")), String(s.get("near", "")), {"mode": mode_id, "stop": String(s["id"]), "always_open": true})
			sp.global_position = pos + Vector3(0, 0, 1.0)
			GameManager.register("stop:" + String(s["id"]), sp)


## 人行道上的棕榈树 + 路边停着的车（避开路口、公交 / 地铁站、火车站出口）
func _palms_and_parking() -> void:
	var avoid: Array = [station_spawn]
	for mode_id in ["bus", "metro"]:
		for st in (DataDB.transport.get(mode_id, {}) as Dictionary).get("stops", []):
			var sp: Array = st["pos"]
			avoid.append(Vector3(float(sp[0]), 0, float(sp[1])))
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	var paints := [Color(0.85, 0.85, 0.86), Color(0.08, 0.08, 0.09), Color(0.45, 0.47, 0.5), Color(0.55, 0.06, 0.08), Color(0.1, 0.2, 0.45), Color(0.9, 0.9, 0.88), Color(0.2, 0.24, 0.22), Color(0.75, 0.55, 0.25)]
	var edges := [-LIMIT - 8.0] + ROADS + [LIMIT + 8.0]
	for road in ROADS:
		for i in range(edges.size() - 1):
			var a: float = edges[i] + WALK_HALF + 2.0
			var bb: float = edges[i + 1] - WALK_HALF - 2.0
			for side in [-1.0, 1.0]:
				for along_x in [false, true]:
					var t := a + 6.0
					while t < bb - 2.0:
						var off: float = road + side * (ROAD_HALF + 2.6)
						var p := Vector3(t, 0, off) if along_x else Vector3(off, 0, t)
						if absf(t) < LIMIT - 6.0 and _clear_of(p, avoid, 5.0):
							kit.palm(p, rng.randf_range(10.0, 16.0))
						t += 24.0
					# 路边停车：贴着路缘，车头朝行驶方向
					var c := a + rng.randf_range(4.0, 14.0)
					while c < bb - 4.0:
						if rng.randf() < 0.45:
							var lane: float = road + side * (ROAD_HALF - 0.98)
							var cp := Vector3(c, 0, lane) if along_x else Vector3(lane, 0, c)
							if absf(c) < LIMIT - 6.0 and _clear_of(cp, avoid, 7.0):
								var yaw: float = (-PI * 0.5 * side) if along_x else (0.0 if side > 0 else PI)
								var basis := Basis(Vector3.UP, yaw)
								BuildingKit.car_geometry(batcher, cp, basis, paints[rng.randi() % paints.size()])
								kit.collide_prop(cp + Vector3(0, 0.75, 0), Vector3(4.4, 1.5, 1.9) if along_x else Vector3(1.9, 1.5, 4.4))
								var ext := Vector2(2.2, 1.0) if along_x else Vector2(1.0, 2.2)
								kit.obstacles.append(Rect2(cp.x - ext.x, cp.z - ext.y, ext.x * 2, ext.y * 2))
						c += rng.randf_range(6.0, 11.0)


## 路名（南北向按 x、东西向按 z 排序）
const NS_NAMES := ["西岭路", "枫林路", "中央大道", "滨江路", "东港路"]
const EW_NAMES := ["北山街", "新华街", "人民路", "南湖街", "海湾街"]


## 每个路口四个角的红绿灯：横臂伸到来车车道上方，南北向绿灯、东西向红灯；两个角挂路名牌
func _intersections() -> void:
	var o := ROAD_HALF + 1.3
	for xi in ROADS.size():
		for zi in ROADS.size():
			var x: float = ROADS[xi]
			var z: float = ROADS[zi]
			# 北行车辆（-z 方向，车道在 +x 侧）从 +z 方向驶来
			kit.traffic_light(Vector3(x + o, 0, z + o), Vector3(-1, 0, 0), o - 2.2, Vector3(0, 0, 1), true, NS_NAMES[xi])
			kit.traffic_light(Vector3(x - o, 0, z - o), Vector3(1, 0, 0), o - 2.2, Vector3(0, 0, -1), true)
			kit.traffic_light(Vector3(x - o, 0, z + o), Vector3(0, 0, -1), o - 2.2, Vector3(-1, 0, 0), false, EW_NAMES[zi])
			kit.traffic_light(Vector3(x + o, 0, z - o), Vector3(0, 0, 1), o - 2.2, Vector3(1, 0, 0), false)


## 城市外缘（最外圈道路的外侧空地）：电线杆 + 电线、大型广告牌
func _city_edge() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 55
	var outer := [ROADS[0], ROADS[ROADS.size() - 1]]
	var design := 0
	for road in outer:
		var side := signf(road)
		for along_x in [false, true]:
			var prev_tops: Array = []
			var t := -LIMIT + 10.0
			while t < LIMIT - 10.0:
				var near_cross := false
				for rr in ROADS:
					if absf(t - float(rr)) < ROAD_HALF + 4.0:
						near_cross = true
				if near_cross:
					prev_tops = []
					t += 6.0
					continue
				var off: float = road + side * (WALK_HALF + 1.5)
				var p := Vector3(t, 0, off) if along_x else Vector3(off, 0, t)
				var dir := Vector3(1, 0, 0) if along_x else Vector3(0, 0, 1)
				var tops := kit.utility_pole(p, dir)
				if not prev_tops.is_empty():
					for k in 3:
						kit.wire(prev_tops[k], tops[k], rng.randf_range(0.4, 0.8))
				prev_tops = tops
				# 每隔一段在电线外侧立一块广告牌，画面朝向道路
				if rng.randf() < 0.28:
					var bp := p + (Vector3(0, 0, side) if along_x else Vector3(side, 0, 0)) * 9.0
					var face := (Vector3(0, 0, -side) if along_x else Vector3(-side, 0, 0))
					kit.billboard(bp, face, design % 4, rng.randf_range(7.0, 11.0), rng.randf_range(10.0, 14.0))
					design += 1
				t += 28.0


func _clear_of(p: Vector3, pts: Array, r: float) -> bool:
	for q in pts:
		if Vector2(p.x - (q as Vector3).x, p.z - (q as Vector3).z).length() < r:
			return false
	return true


func _vending_machines() -> void:
	var spots := [Vector3(8, 0, 170), Vector3(-86, 0, -14), Vector3(74, 0, -86), Vector3(-52, 0, 14), Vector3(86, 0, 94), Vector3(-14, 0, 86)]
	for p in spots:
		batcher.box("solid", p + Vector3(0, 1.0, 0), Vector3(1.1, 2.0, 0.8), Color(0.12, 0.12, 0.16))
		batcher.box("neon", p + Vector3(0, 1.2, 0.41), Vector3(0.9, 1.3, 0.02), Color(0.2, 0.9, 1.0) * 0.8)
		kit.collide(p + Vector3(0, 1.0, 0), Vector3(1.1, 2.0, 0.8))
		var sp := ServicePoint.new()
		props_root.add_child(sp)
		sp.setup("shop", "自动售货机", "", {"shop": "vending", "always_open": true})
		sp.global_position = p + Vector3(0, 0, 1.2)


func _street_props() -> void:
	# 垃圾桶、消防栓、全息广告柱
	var rng := kit.rng
	for i in 60:
		var p: Vector3 = sidewalk_points[rng.randi() % sidewalk_points.size()]
		if p.distance_to(station_spawn) < 10.0:
			continue
		var t := rng.randi() % 3
		match t:
			0:
				batcher.cylinder("prop", p + Vector3(1.2, 0.5, 0), 0.3, 1.0, Color(0.15, 0.3, 0.25), 8)
			1:
				batcher.cylinder("prop", p + Vector3(1.2, 0.4, 0), 0.18, 0.8, Color(0.7, 0.1, 0.1), 8)
			2:
				batcher.cylinder("metal", p + Vector3(1.4, 1.5, 0), 0.25, 3.0, Color(0.15, 0.15, 0.18), 8)
				batcher.cylinder("neon", p + Vector3(1.4, 2.4, 0), 0.27, 1.2, NEON_COLORS[i % NEON_COLORS.size()] * 0.8, 8)


func _track() -> void:
	var col := Color(0.24, 0.25, 0.3)
	batcher.box("metal", Vector3(0, TRACK_Y - 0.4, TRACK_Z), Vector3(900, 0.8, 4.0), col)
	batcher.box("neon", Vector3(0, TRACK_Y + 0.05, TRACK_Z - 2.0), Vector3(900, 0.08, 0.08), Color(0.2, 0.9, 1.0))
	batcher.box("neon", Vector3(0, TRACK_Y + 0.05, TRACK_Z + 2.0), Vector3(900, 0.08, 0.08), Color(1.0, 0.2, 0.55))
	for k in 30:
		var x := -435.0 + k * 30.0
		if absf(x) < 45.0:
			continue
		batcher.box("concrete", Vector3(x, (TRACK_Y - 0.8) * 0.5, TRACK_Z), Vector3(1.5, TRACK_Y - 0.8, 1.5), Color(0.9, 0.9, 0.9))


func _skyline() -> void:
	# 远景：北边的商务区与地标楼、四周的低层城区、高架快速路、铁路货场（world/outskirts.gd），再远是一圈山
	Outskirts.new().build(self, kit)
	_mountains()


## 城市外围的山：六圈同心环组成连绵起伏的山脊（宽而圆润，不是尖锥），北边更高；
## 离城越远颜色越偏蓝灰，再叠加大气雾，呈现层层远山的效果。
func _mountains() -> void:
	var broad := FastNoiseLite.new()
	broad.seed = 12
	broad.frequency = 0.9
	broad.fractal_octaves = 3
	var detail := FastNoiseLite.new()
	detail.seed = 31
	detail.frequency = 4.0
	detail.fractal_octaves = 3
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 240
	var rings := [640.0, 720.0, 820.0, 930.0, 1040.0, 1180.0]
	var profile := [0.0, 0.35, 0.8, 1.0, 0.75, 0.25]
	var cols := [Color(0.36, 0.32, 0.26), Color(0.34, 0.31, 0.27), Color(0.33, 0.31, 0.3), Color(0.34, 0.34, 0.36), Color(0.36, 0.37, 0.4), Color(0.4, 0.41, 0.45)]
	var pts: Array = []
	for ri in rings.size():
		var row: Array = []
		for i in seg + 1:
			var a := TAU * i / float(seg)
			var dir := Vector2(cos(a), sin(a))
			var n := broad.get_noise_2d(dir.x, dir.y) * 0.5 + 0.5
			var north := clampf(-dir.y * 0.6 + 0.6, 0.35, 1.0)
			var amp := (50.0 + n * n * 230.0) * north
			var bump := detail.get_noise_3d(dir.x * 1.5, dir.y * 1.5, ri * 0.7) * 0.22
			var h := float(profile[ri]) * amp * (1.0 + bump)
			row.append(Vector3(dir.x * rings[ri], h - 2.0, dir.y * rings[ri]))
		pts.append(row)
	for ri in rings.size() - 1:
		for i in seg:
			var a0: Vector3 = pts[ri][i]
			var a1: Vector3 = pts[ri][i + 1]
			var b0: Vector3 = pts[ri + 1][i]
			var b1: Vector3 = pts[ri + 1][i + 1]
			for pp in [[a0, cols[ri]], [b0, cols[ri + 1]], [a1, cols[ri]], [a1, cols[ri]], [b0, cols[ri + 1]], [b1, cols[ri + 1]]]:
				st.set_color(pp[1])
				st.add_vertex(pp[0])
	st.index()
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Mountains"
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _bounds() -> void:
	for s in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var c: Vector3 = s * (LIMIT + 1.0) + Vector3(0, 10, 0)
		var size := Vector3(2, 20, LIMIT * 2 + 4) if absf(s.x) > 0.5 else Vector3(LIMIT * 2 + 4, 20, 2)
		kit.collide(c, size)


# ================================================================ 导航网格
## 用 4 米网格生成：不在任何建筑 / 障碍范围内的格子都可以走。
func _build_navigation() -> void:
	var cell := 4.0
	var n := int(LIMIT * 2 / cell)
	var origin := -LIMIT
	var walk: Array = []
	walk.resize(n * n)
	var obs: Array = kit.obstacles
	for iz in n:
		for ix in n:
			var r := Rect2(origin + ix * cell + 0.3, origin + iz * cell + 0.3, cell - 0.6, cell - 0.6)
			var ok := true
			for o in obs:
				if (o as Rect2).intersects(r):
					ok = false
					break
			walk[iz * n + ix] = ok
	var nm := NavigationMesh.new()
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.agent_radius = 0.4
	var verts := PackedVector3Array()
	var index := {}
	for iz in n:
		for ix in n:
			if not walk[iz * n + ix]:
				continue
			var ids := PackedInt32Array()
			for corner in [Vector2i(ix, iz), Vector2i(ix + 1, iz), Vector2i(ix + 1, iz + 1), Vector2i(ix, iz + 1)]:
				if not index.has(corner):
					index[corner] = verts.size()
					verts.append(Vector3(origin + corner.x * cell, 0.0, origin + corner.y * cell))
				ids.append(int(index[corner]))
			nm.add_polygon(ids)
	nm.vertices = verts
	nav_region = NavigationRegion3D.new()
	nav_region.name = "Navigation"
	nav_region.navigation_mesh = nm
	add_child(nav_region)
