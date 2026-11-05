class_name PlainManor
extends RefCounted
## 洛蒙德庄园（路线图 6.3a，D12；STORY.md 6.2「东岸高处的石砌庄园：围墙、门楼挂着绿底金麦束的旗；大厅里炉火很旺，桌上摆满吃的——和对岸是两个世界」）。
## 先回答「这里住着谁、缺什么、刚发生过什么」（ART.md 第十节）：住着女家主伊莎贝拉·洛蒙德、管家塞缪尔和一院子的仆人、护院；什么都不缺——
## 院子里停着装满麻袋的车、柴垛码得比人高、每个烟囱都冒烟、窗户都亮着；刚发生过的——塞弗林家的兵从砧山下来「征粮」，门楼上多站了两个护院。
##   围墙（石砌、3.2 米、墙头垛口）、西边门楼（拱门洞、两面绿底金麦束的旗、门边两个火盆）、北墙一道后门（往塞弗林营地的路）、
##   主楼（House：两层石楼、门通往大厅 manor_hall）、东边仓房和马厩（House）、院子里的水井、两辆装满麻袋的车、高高的柴垛、几只木桶箱子、门外的路牌。
## 同坠星院：碰撞、门、路牌同步建；画面每样一件活。坐标就是平原的世界坐标（庄园在 PlainLayout.MANOR 压平的那块上）。

const WALL_RECT := Rect2(58.0, -63.0, 36.0, 30.0)
const WALL_H := 3.2
const WALL_T := 0.8
const GATE := Vector2(58.0, -41.5)            # 西墙上的门楼（大车道从磨坊上来）
const GATE_W := 3.6
const BACK_GATE := Vector2(85.0, -63.0)       # 北墙的后门（往塞弗林营地）
const BACK_W := 3.2
const HALL := [Vector3(72.0, 0, -50.0), -90.0, 16.0, 10.0]       # 主楼：正面墙脚中点（朝西对着门楼）、朝向（度）、宽、进深
const BARN := [Vector3(86.0, 0, -42.0), -90.0, 12.0, 7.0]        # 东边仓房和马厩（正面朝西，往东 7 米到围墙边）
const WELL := Vector2(67.0, -40.0)
const SIGN_AT := Vector2(54.0, -44.5)
const SIGN_TEXT := "往磨坊 · 麦渡"
const HALL_DOOR := "大厅的门"
const BARN_DOOR_TEXT := "仓房的门上了两道锁。门缝里一股麦子的味道。"
const FIELD := Color("2e5a32")                 # 洛蒙德家：绿底金麦束（WORLD.md 第五节）
const CHARGE := Color("c8a440")

static var _y := NAN


static func clear_cache() -> void:
	_y = NAN


static func base_y() -> float:
	if is_nan(_y):
		_y = PlainLayout.height(PlainLayout.MANOR.x, PlainLayout.MANOR.y)
	return _y


static func ground(p: Vector2) -> float:
	return PlainLayout.height(p.x, p.y)


static func hall_spec() -> Dictionary:
	return {"w": float(HALL[2]), "d": float(HALL[3]), "floors": 2, "stone_upper": true, "roof": "eaves", "seed": 64, "lit": 0.95, "door_x": 0.0, "chimney": true,
		"solid": false, "door": {"name": HALL_DOOR, "to_area": "manor_hall", "to_spawn": "front", "verb": "进入", "node": false}}


static func barn_spec() -> Dictionary:
	return {"w": float(BARN[2]), "d": float(BARN[3]), "floors": 1, "stone_upper": true, "roof": "eaves", "seed": 65, "lit": 0.6, "door_x": -2.0, "chimney": true,
		"solid": false, "door": {"name": "仓房的门", "text": BARN_DOOR_TEXT}}


static func house_pos(h: Array) -> Vector3:
	var p: Vector3 = h[0]
	return Vector3(p.x, base_y(), p.z)


# ---------------- 碰撞 ----------------

static func solids() -> Array:
	var out := []
	for seg: Array in wall_segments():
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		var m := (a + b) * 0.5
		out.append([Transform3D(Basis(Vector3.UP, -atan2(b.y - a.y, b.x - a.x)), Vector3(m.x, ground(m) + WALL_H * 0.5 - 0.3, m.y)), Vector3(a.distance_to(b) + WALL_T, WALL_H + 0.6, WALL_T)])
	for s in [-1.0, 1.0]:                                   # 门楼两边的塔
		out.append([Transform3D(Basis.IDENTITY, Vector3(GATE.x, base_y() + 3.0, GATE.y + s * (GATE_W * 0.5 + 1.1))), Vector3(2.6, 6.0, 2.2)])
	out.append_array(House.solids(house_pos(HALL), float(HALL[1]), hall_spec()))
	out.append_array(House.solids(house_pos(BARN), float(BARN[1]), barn_spec()))
	out.append([Transform3D(Basis.IDENTITY, Vector3(WELL.x, base_y() + 0.45, WELL.y)), Vector3(1.7, 0.9, 1.7)])
	for sd in props_decor().solids:
		out.append([Transform3D(Basis.IDENTITY, sd[0]), sd[1]])
	return out


## 围墙一段段：[起点, 终点]；西墙在门楼处断开、北墙在后门处断开
static func wall_segments() -> Array:
	var r := WALL_RECT
	var nw := r.position
	var ne := Vector2(r.end.x, r.position.y)
	var se := r.end
	var sw := Vector2(r.position.x, r.end.y)
	var g0 := GATE.y - GATE_W * 0.5 - 2.2
	var g1 := GATE.y + GATE_W * 0.5 + 2.2
	return [[nw, Vector2(BACK_GATE.x - BACK_W * 0.5, nw.y)], [Vector2(BACK_GATE.x + BACK_W * 0.5, ne.y), ne], [ne, se], [se, sw],
		[sw, Vector2(sw.x, g1)], [Vector2(nw.x, g0), nw]]


static func interactables(parent: Node3D) -> void:
	var hs := hall_spec()
	var d := House.door_node(hs.door)
	d.name = "ManorHallDoor"
	d.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(float(HALL[1]))), house_pos(HALL)) * Transform3D(Basis.IDENTITY, Vector3(float(hs.door_x) - 0.55, 0, 0.05))
	parent.add_child(d)
	var bs := barn_spec()
	var bd := House.door_node(bs.door)
	bd.name = "ManorBarnDoor"
	bd.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(float(BARN[1]))), house_pos(BARN)) * Transform3D(Basis.IDENTITY, Vector3(float(bs.door_x) - 0.55, 0, 0.05))
	parent.add_child(bd)
	var rs := RoadSign.new()
	rs.text = SIGN_TEXT
	rs.position = Vector3(SIGN_AT.x, ground(SIGN_AT), SIGN_AT.y)
	rs.rotation_degrees.y = 70.0
	parent.add_child(rs)


## 院子里的东西（满）：两辆装满麻袋的车、比人高的柴垛、木桶、箱子、堆在仓房门口的麻袋
## part：""（全部，碰撞用）、"items"（车、桶、箱子、麻袋）、"wood0".."wood5"（半垛柴：几百根小圆柱，半垛一件活——三垛合一件要 100 多毫秒，6.3a；一垛一件全量测试里 78–145 毫秒，6.3c）
static func props_decor(rect := Rect2(), part := "") -> Decor:
	var d := Decor.new()
	var inside := func(p: Vector2) -> bool: return rect.size == Vector2.ZERO or rect.has_point(p)
	var y := base_y()
	var items := [
		["cart", Vector2(80.0, -38.0), 0.4], ["cart", Vector2(83.5, -55.0), -0.3],
		["barrel", Vector2(84.6, -49.6)], ["barrel", Vector2(85.3, -50.4)], ["barrel", Vector2(84.7, -51.3)],
		["crate", Vector2(85.0, -34.8), 0.2], ["crate", Vector2(86.0, -34.6), 1.1],
		["sack", Vector2(84.8, -38.2), 0.2], ["sack", Vector2(85.0, -39.0), 1.3], ["sack", Vector2(84.6, -39.8), 2.2], ["sack", Vector2(85.1, -40.6), 0.7],
	]
	for it: Array in items:
		var p: Vector2 = it[1]
		if not inside.call(p) or part not in ["", "items"]:
			continue
		var pos := Vector3(p.x, y, p.y)
		match str(it[0]):
			"cart":
				d.cart(pos, float(it[2]), "sacks")
			"barrel":
				d.barrel(pos)
			"crate":
				d.crate(pos, float(it[2]))
			"sack":
				d.sack(pos, float(it[2]))
	for k in 6:                                              # 柴垛：沿南墙码得比人高（三垛，每垛按半垛一件活：一垛一件 40–70 毫秒、全量测试里抢 CPU 时 78–145，6.3c 实测）
		var p := Vector2(66.0 + (k / 2) * 3.2 + (k % 2 - 0.5) * 1.5, WALL_RECT.end.y - 1.4)
		if inside.call(p) and part in ["", "wood%d" % k]:
			d.woodpile(Vector3(p.x, y, p.y), Vector3(1, 0, 0), 1.5, 1.9)
	return d


# ---------------- 画面 ----------------

static func jobs_for(rect: Rect2, reduced_motion: bool) -> Array:
	var out := []
	if rect.has_point(WALL_RECT.get_center()):
		out.append(func(root: Node3D): walls(root, reduced_motion))
		out.append(func(root: Node3D): House.build(root, house_pos(HALL), float(HALL[1]), hall_spec()))
		out.append(func(root: Node3D): House.build(root, house_pos(BARN), float(BARN[1]), barn_spec()))
		out.append(func(root: Node3D): well(root))
		for part in ["items", "wood0", "wood1", "wood2", "wood3", "wood4", "wood5"]:
			out.append(func(root: Node3D): _props(root, part))
	return out


static func _props(root: Node3D, part: String) -> void:
	var d := props_decor(Rect2(), part)
	var mi := d.kit.build(d.mats)
	mi.name = "ManorProps" if part == "items" else "ManorWood"
	root.add_child(mi)


## 围墙（墙头一排垛口）、门楼（两座方塔夹拱门洞、塔顶垛口、两面旗、门边两个火盆）、后门（木门敞着）
static func walls(parent: Node3D, reduced_motion := false) -> void:
	var kit := MeshKit.new()
	var y := base_y()
	for seg: Array in wall_segments():
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		var len := a.distance_to(b)
		var n := maxi(int(len / 6.0), 1)
		var basis := Basis(Vector3.UP, -atan2(b.y - a.y, b.x - a.x))
		var dir := (b - a).normalized()
		for k in n:
			var p0 := a.lerp(b, float(k) / n)
			var p1 := a.lerp(b, float(k + 1) / n)
			var m := (p0 + p1) * 0.5
			var g := minf(ground(p0), ground(p1))
			var top := y + WALL_H
			kit.box("stone", Vector3(m.x, (g - 0.8 + top) * 0.5, m.y), Vector3(len / n + 0.05, top - g + 0.8, WALL_T), basis, 0.85, 0.5)
			kit.box("snow", Vector3(m.x, top + 0.04, m.y), Vector3(len / n + 0.05, 0.08, WALL_T * 0.9), basis, 1.0, 0.95)
			var merlons := int(len / n / 1.4)
			for j in merlons:                                # 垛口
				var q := p0 + dir * ((j + 0.5) * (len / n) / merlons)
				kit.box("stone", Vector3(q.x, top + 0.35, q.y), Vector3(0.7, 0.7, WALL_T), basis, 0.95, 0.8)
				kit.box("snow", Vector3(q.x, top + 0.73, q.y), Vector3(0.72, 0.06, WALL_T * 0.9), basis, 1.0, 1.0)
	# 门楼
	var gx := GATE.x
	for s in [-1.0, 1.0]:
		var tz: float = GATE.y + s * (GATE_W * 0.5 + 1.1)
		kit.box("stone", Vector3(gx, y + 2.6, tz), Vector3(2.6, 6.2, 2.2), Basis.IDENTITY, 0.9, 0.5)
		for j in 3:
			kit.box("stone", Vector3(gx - 1.0 + j * 1.0, y + 6.05, tz - 0.8 * s), Vector3(0.55, 0.6, 0.5), Basis.IDENTITY, 0.95, 0.8)
		kit.box("snow", Vector3(gx, y + 5.73, tz), Vector3(2.6, 0.06, 2.2), Basis.IDENTITY, 1.0, 1.0)
		kit.cylinder("iron", Vector3(gx - 1.6, y, GATE.y + s * (GATE_W * 0.5 + 0.4)), Vector3(gx - 1.6, y + 1.1, GATE.y + s * (GATE_W * 0.5 + 0.4)), 0.04, 0.04, 5)     # 火盆的架子
		kit.cylinder("iron", Vector3(gx - 1.6, y + 1.1, GATE.y + s * (GATE_W * 0.5 + 0.4)), Vector3(gx - 1.6, y + 1.35, GATE.y + s * (GATE_W * 0.5 + 0.4)), 0.22, 0.32, 8)
		kit.box("ember", Vector3(gx - 1.6, y + 1.36, GATE.y + s * (GATE_W * 0.5 + 0.4)), Vector3(0.4, 0.06, 0.4))
	kit.box("stone", Vector3(gx, y + 4.4, GATE.y), Vector3(2.6, 2.6, GATE_W + 0.1), Basis.IDENTITY, 0.85, 0.6)          # 门洞上面
	kit.box("dark", Vector3(gx, y + 0.02, GATE.y), Vector3(2.6, 0.04, GATE_W))
	for s in [-1.0, 1.0]:                                                                                              # 两扇门往里敞着
		kit.box("timber", Vector3(gx + 1.5, y + 1.55, GATE.y + s * (GATE_W * 0.5 - 0.1)), Vector3(1.6, 3.1, 0.12), Basis(Vector3.UP, s * 0.2), 0.8, 0.6)
	for s in [-1.0, 1.0]:                                                                                              # 后门：两扇木门往外敞着
		kit.box("timber", Vector3(BACK_GATE.x + s * (BACK_W * 0.5 - 0.1), y + 1.4, BACK_GATE.y - 1.0), Vector3(0.12, 2.8, 1.5), Basis(Vector3.UP, -s * 0.3), 0.8, 0.6)
	var mi := kit.build({"stone": Look.mat("stone"), "snow": Look.mat("snow"), "timber": Look.mat("timber"), "dark": PlainVillage.dark(), "iron": Inn._iron_mat(), "ember": Inn._unshaded(Color("ff7a28"))})
	mi.name = "ManorWalls"
	parent.add_child(mi)
	var d := Decor.new()                                                                                               # 门楼上两面旗（朝外）
	for s in [-1.0, 1.0]:
		d.banner(Vector3(gx - 1.32, y + 5.2, GATE.y + s * (GATE_W * 0.5 + 1.1)), Vector3(-1, 0, 0), 1.2, 2.4, FIELD, CHARGE, "wheat")
	d.banner(house_pos(HALL) + Vector3(-0.08, 6.6, 3.2), Vector3(-1, 0, 0), 1.0, 1.9, FIELD, CHARGE, "wheat")
	d.build(parent, "ManorBanners", not reduced_motion)
	for s in [-1.0, 1.0]:                                                                                              # 火盆的光
		var l := Tavern.FireLight.new()
		l.light_color = Color("ff9040")
		l.base = 1.6
		l.omni_range = 7.0
		l.position = Vector3(gx - 1.6, y + 1.8, GATE.y + s * (GATE_W * 0.5 + 0.4))
		l.flicker = not reduced_motion
		l.add_to_group("night_light")
		parent.add_child(l)


static func well(parent: Node3D) -> void:
	var kit := MeshKit.new()
	for k in 10:
		var a := TAU * k / 10.0
		kit.box("stone", Vector3(cos(a) * 0.7, 0.45, sin(a) * 0.7), Vector3(0.48, 0.9, 0.3), Basis(Vector3.UP, -a + PI * 0.5), 0.95, 0.65)
	kit.box("snow", Vector3(0, 0.92, 0), Vector3(1.6, 0.05, 1.6), Basis.IDENTITY, 1.0, 1.0)
	kit.box("dark", Vector3(0, 0.94, 0), Vector3(1.05, 0.02, 1.05))
	for s in [-1.0, 1.0]:
		kit.box("timber", Vector3(s * 0.85, 1.25, 0), Vector3(0.16, 2.5, 0.16), Basis.IDENTITY, 0.8, 0.6)
	kit.box("roof", Vector3(0, 2.6, 0), Vector3(2.2, 0.08, 1.4), Basis(Vector3.RIGHT, 0.0), 0.9, 0.8)        # 井上一块小顶棚
	kit.box("snow", Vector3(0, 2.67, 0), Vector3(2.2, 0.06, 1.4), Basis.IDENTITY, 1.0, 1.0)
	var mi := kit.build({"stone": Look.mat("stone"), "snow": Look.mat("snow"), "timber": Look.mat("timber"), "roof": Look.mat("roof"), "dark": PlainVillage.dark()})
	mi.name = "ManorWell"
	mi.position = Vector3(WELL.x, base_y(), WELL.y)
	parent.add_child(mi)


static func map_shapes() -> Array:
	return [
		{"k": "house", "pts": House.footprint(house_pos(HALL), float(HALL[1]), float(HALL[2]), float(HALL[3])), "label": "主楼"},
		{"k": "house", "pts": House.footprint(house_pos(BARN), float(BARN[1]), float(BARN[2]), float(BARN[3])), "label": "仓房"},
	]
