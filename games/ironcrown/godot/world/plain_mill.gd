class_name PlainMill
extends RefCounted
## 洛蒙德家的水磨坊与粮仓（路线图 6.3b，D12；STORY.md 6.2「庄园下游的水磨坊（石砌底座、木轮在冰下慢慢转）、旁边三座高高的粮仓（满的）、院墙、水渠、一道院墙缺口」）。
## 磨坊之战（6.7）就在这儿打：院子三面围着矮石墙、西边是麦河（河就是墙），北墙一道缺口（塞弗林家的第二波从这儿进），大车道从南门进、东门出。
## 先回答「这里住着谁、缺什么、刚发生过什么」：磨坊主和几个护院；不缺粮——三座粮仓都是满的，门口还码着麻袋；
## 刚发生过的——北墙去年冬天冻塌了一段，没人修（石头还散在雪里），磨轮冻上了，木槽上挂满冰溜子，轮子慢慢转。
##   磨坊（House：石砌底层 + 木板墙上层，门通往磨坊里面 mill_inside）、西墙外的大水轮（顶上一道木槽从上游引水下来，冰溜子）、
##   三座粮仓（House：两层石楼、山墙朝路，门锁着）、院墙（南门、东门、北墙缺口和散落的石头）、门口码着的麻袋、两辆车、南门外的路牌。

const RECT := Rect2(12.0, -38.0, 32.0, 36.0)            # 院子：西边是麦河岸（不砌墙）
const WALL_H := 1.9
const WALL_T := 0.6
const SOUTH_GATE := Vector2(14.6, -2.0)                  # 大车道从木桥东头上来
const EAST_GATE := Vector2(44.0, -33.6)                  # 往粮仓上头、庄园去
const GATE_W := 3.6
const BREACH := Vector2(27.5, -38.0)                     # 北墙塌了的一段（6.7 第二波从这儿进）
const BREACH_W := 3.4
const MILL := [Vector3(22.0, 0, -13.0), 90.0, 10.0, 8.0]          # 磨坊：正面墙脚中点（朝东对着院子）、朝向、宽、进深
const WHEEL_C := Vector2(13.3, -13.0)                    # 水轮的轴（磨坊西墙外，轴沿东西）
const WHEEL_R := 2.2
const FLUME_FROM := Vector2(13.3, -37.0)                 # 木槽：从上游沿岸边引过来，落在水轮顶上
const GRANARIES := [[Vector3(32.0, 0, -12.0), 180.0], [Vector3(39.0, 0, -15.0), 200.0], [Vector3(38.5, 0, -24.0), 230.0]]
const GRANARY_W := 5.0
const GRANARY_D := 5.0
const SIGN_AT := Vector2(18.0, 1.0)
const SIGN_TEXT := "往庄园 · 坠星院"
const GRANARY_DOOR_TEXT := "粮仓锁着。门缝底下漏出来几粒麦子，冻在雪里。"
const MILL_DOOR := "磨坊的门"


static func ground(p: Vector2) -> float:
	return PlainLayout.height(p.x, p.y)


static func mill_y() -> float:
	return PlainLayout.height(PlainLayout.MILL.x, PlainLayout.MILL.y)


static func mill_spec() -> Dictionary:
	return {"w": float(MILL[2]), "d": float(MILL[3]), "floors": 1, "upper": "timber", "roof": "eaves", "seed": 66, "lit": 0.7, "door_x": 1.5, "chimney": false,
		"solid": false, "door": {"name": MILL_DOOR, "to_area": "mill_inside", "to_spawn": "front", "verb": "进入", "node": false}}


static func granary_spec(i: int) -> Dictionary:
	return {"w": GRANARY_W, "d": GRANARY_D, "floors": 2, "stone_upper": true, "roof": "gable", "seed": 67 + i, "lit": 0.0, "door_x": 0.0, "chimney": false,
		"solid": false, "door": {"name": "粮仓的门", "text": GRANARY_DOOR_TEXT}}


static func mill_pos() -> Vector3:
	var p: Vector3 = MILL[0]
	return Vector3(p.x, mill_y(), p.z)


## 粮仓不在压平的地上：取四角最低的那点，墙脚埋下去
static func granary_pos(i: int) -> Vector3:
	var g: Array = GRANARIES[i]
	var p: Vector3 = g[0]
	var lo := INF
	for fp: Vector2 in House.footprint(Vector3(p.x, 0, p.z), float(g[1]), GRANARY_W, GRANARY_D):
		lo = minf(lo, ground(fp))
	return Vector3(p.x, lo - 0.05, p.z)


## 出了磨坊：门外、面朝东（院子）
static func mill_exit() -> Array:
	return [Vector2(23.8, -11.5), -90.0]


# ---------------- 碰撞 ----------------

static func solids() -> Array:
	var out := []
	for seg: Array in wall_segments():
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		var m := (a + b) * 0.5
		out.append([Transform3D(Basis(Vector3.UP, -atan2(b.y - a.y, b.x - a.x)), Vector3(m.x, ground(m) + WALL_H * 0.5 - 0.2, m.y)), Vector3(a.distance_to(b) + WALL_T, WALL_H + 0.4, WALL_T)])
	out.append_array(House.solids(mill_pos(), float(MILL[1]), mill_spec()))
	for i in GRANARIES.size():
		out.append_array(House.solids(granary_pos(i), float((GRANARIES[i] as Array)[1]), granary_spec(i)))
	out.append([Transform3D(Basis.IDENTITY, Vector3(WHEEL_C.x, mill_y() + 1.6, WHEEL_C.y)), Vector3(1.4, 4.6, WHEEL_R * 2.0 + 0.4)])
	for sd in props_decor().solids:
		out.append([Transform3D(Basis.IDENTITY, sd[0]), sd[1]])
	return out


## 院墙一段段：南墙（南门断开）、东墙（东门断开）、北墙（缺口断开）；西边是河，不砌
static func wall_segments() -> Array:
	var r := RECT
	var nw := r.position
	var ne := Vector2(r.end.x, r.position.y)
	var se := r.end
	var sw := Vector2(r.position.x, r.end.y)
	return [
		[sw, Vector2(SOUTH_GATE.x - GATE_W * 0.5, sw.y)], [Vector2(SOUTH_GATE.x + GATE_W * 0.5, se.y), se],
		[se, Vector2(se.x, EAST_GATE.y + GATE_W * 0.5)], [Vector2(ne.x, EAST_GATE.y - GATE_W * 0.5), ne],
		[ne, Vector2(BREACH.x + BREACH_W * 0.5, ne.y)], [Vector2(BREACH.x - BREACH_W * 0.5, nw.y), nw],
	]


static func interactables(parent: Node3D) -> void:
	var ms := mill_spec()
	var d := House.door_node(ms.door)
	d.name = "MillDoor"
	d.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(float(MILL[1]))), mill_pos()) * Transform3D(Basis.IDENTITY, Vector3(float(ms.door_x) - 0.55, 0, 0.05))
	parent.add_child(d)
	for i in GRANARIES.size():
		var gs := granary_spec(i)
		var gd := House.door_node(gs.door)
		gd.name = "GranaryDoor%d" % i
		gd.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(float((GRANARIES[i] as Array)[1]))), granary_pos(i)) * Transform3D(Basis.IDENTITY, Vector3(float(gs.door_x) - 0.55, 0, 0.05))
		parent.add_child(gd)
	var rs := RoadSign.new()
	rs.text = SIGN_TEXT
	rs.position = Vector3(SIGN_AT.x, ground(SIGN_AT), SIGN_AT.y)
	rs.rotation_degrees.y = 200.0
	parent.add_child(rs)


## 院子里：粮仓门口码着的麻袋、两辆车（一辆装满）、木桶；北墙缺口外散在雪里的石头
static func props_decor(rect := Rect2()) -> Decor:
	var d := Decor.new()
	var inside := func(p: Vector2) -> bool: return rect.size == Vector2.ZERO or rect.has_point(p)
	var items := [
		["cart", Vector2(27.5, -18.0), 0.9, "sacks"], ["cart", Vector2(24.5, -30.0), -0.6, "wood"],
		["barrel", Vector2(24.2, -7.5)], ["barrel", Vector2(24.9, -6.9)],
		["sack", Vector2(30.2, -9.2), 0.3], ["sack", Vector2(30.9, -8.7), 1.4], ["sack", Vector2(31.6, -9.3), 2.2], ["sack", Vector2(33.8, -9.0), 0.6], ["sack", Vector2(34.5, -9.6), 1.9],
		["sack", Vector2(36.0, -20.4), 0.1], ["sack", Vector2(35.4, -21.1), 1.2],
		["crate", Vector2(23.5, -19.2), 0.3],
	]
	for it: Array in items:
		var p: Vector2 = it[1]
		if not inside.call(p):
			continue
		var pos := Vector3(p.x, ground(p), p.y)
		match str(it[0]):
			"cart":
				d.cart(pos, float(it[2]), str(it[3]))
			"barrel":
				d.barrel(pos)
			"crate":
				d.crate(pos, float(it[2]))
			"sack":
				d.sack(pos, float(it[2]))
	return d


# ---------------- 画面 ----------------

static func jobs_for(rect: Rect2, reduced_motion: bool) -> Array:
	var out := []
	if rect.has_point(RECT.get_center()):
		out.append(func(root: Node3D): walls(root))
		out.append(func(root: Node3D): House.build(root, mill_pos(), float(MILL[1]), mill_spec()))
		out.append(func(root: Node3D): wheel(root, reduced_motion))
		for i in GRANARIES.size():
			out.append(func(root: Node3D): House.build(root, granary_pos(i), float((GRANARIES[i] as Array)[1]), granary_spec(i)))
		out.append(func(root: Node3D): _props(root))
	return out


static func _props(root: Node3D) -> void:
	var d := props_decor()
	var mi := d.kit.build(d.mats)
	mi.name = "MillProps"
	root.add_child(mi)


## 院墙：矮的干砌石墙（墙头积雪）；北墙缺口两头参差、塌下来的石头散在缺口里外
static func walls(parent: Node3D) -> void:
	var kit := MeshKit.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 6301
	for seg: Array in wall_segments():
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		var len := a.distance_to(b)
		var n := maxi(int(len / 1.7), 1)
		var dir := (b - a).normalized()
		var basis := Basis(Vector3.UP, -atan2(b.y - a.y, b.x - a.x))
		for k in n:
			var p0 := a + dir * (k * len / n)
			var p1 := a + dir * ((k + 1) * len / n)
			var m := (p0 + p1) * 0.5
			var h := WALL_H + rng.randf_range(-0.12, 0.1)
			var near_breach := m.distance_to(BREACH) < BREACH_W * 0.5 + 1.8
			if near_breach:
				h *= rng.randf_range(0.55, 0.8)                      # 缺口两头塌了半截
			var g := ground(m)
			kit.box("stone", Vector3(m.x, g - 0.3 + (h + 0.3) * 0.5, m.y), Vector3(len / n + 0.04, h + 0.3, WALL_T), basis * Basis(Vector3.UP, rng.randf_range(-0.02, 0.02)), 0.85, 0.5)
			kit.box("snow", Vector3(m.x, g + h + 0.04, m.y), Vector3(len / n + 0.02, 0.08, WALL_T * 0.9), basis, 1.0, 0.95)
	for k in 9:                                                     # 缺口里外散的石头
		var p := BREACH + Vector2(rng.randf_range(-2.5, 2.5), rng.randf_range(-2.2, 1.2))
		kit.box("stone", Vector3(p.x, ground(p) + 0.12, p.y), Vector3(rng.randf_range(0.35, 0.6), rng.randf_range(0.2, 0.35), rng.randf_range(0.3, 0.5)), Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.3, 0.3)), 0.9, 0.6)
	for s in [-1.0, 1.0]:                                             # 南门、东门的门柱
		kit.box("stone", Vector3(SOUTH_GATE.x + s * (GATE_W * 0.5 + 0.2), ground(SOUTH_GATE) + 1.2, SOUTH_GATE.y), Vector3(0.7, 2.4, 0.8), Basis.IDENTITY, 0.9, 0.6)
		kit.box("stone", Vector3(EAST_GATE.x, ground(EAST_GATE) + 1.2, EAST_GATE.y + s * (GATE_W * 0.5 + 0.2)), Vector3(0.8, 2.4, 0.7), Basis.IDENTITY, 0.9, 0.6)
	var mi := kit.build({"stone": Look.mat("stone"), "snow": Look.mat("snow")})
	mi.name = "MillWalls"
	parent.add_child(mi)


## 水轮（直径 4.4 米、十六块叶板、两圈轮缘、轴伸进磨坊西墙）挂满冰溜子、慢慢转；顶上一道木槽从上游引水（木槽在一排木架上，槽沿挂冰）、
## 水轮下面一个石砌的轮坑（暗）
static func wheel(parent: Node3D, reduced_motion := false) -> void:
	var y := mill_y()
	var kit := MeshKit.new()
	var axle := Vector3(WHEEL_C.x, y + 1.6, WHEEL_C.y)
	kit.box("stone", axle + Vector3(0.0, -1.6, 0), Vector3(1.8, 0.6, WHEEL_R * 2.0 + 0.6), Basis.IDENTITY, 0.8, 0.5)          # 轮坑的石沿
	kit.box("dark", axle + Vector3(0.0, -1.29, 0), Vector3(1.4, 0.02, WHEEL_R * 2.0 + 0.2))
	kit.cylinder("timber", axle + Vector3(-0.2, 0, 0), axle + Vector3(1.4, 0, 0), 0.18, 0.18, 8)                                # 轴伸进墙里
	var a0 := Vector2(FLUME_FROM.x, FLUME_FROM.y)
	var a1 := Vector2(WHEEL_C.x, WHEEL_C.y - WHEEL_R * 0.4)
	var top := y + 1.6 + WHEEL_R + 0.35
	var n := int(a0.distance_to(a1) / 3.0)
	for k in n + 1:                                                                                                             # 木槽的木架
		var p := a0.lerp(a1, float(k) / n)
		var g := ground(p)
		var ty := lerpf(top + 0.5, top, float(k) / n)
		kit.cylinder("timber", Vector3(p.x - 0.4, g - 0.3, p.y), Vector3(p.x - 0.4, ty - 0.2, p.y), 0.09, 0.08, 5)
		kit.cylinder("timber", Vector3(p.x + 0.4, g - 0.3, p.y), Vector3(p.x + 0.4, ty - 0.2, p.y), 0.09, 0.08, 5)
	var f0 := Vector3(a0.x, top + 0.5, a0.y)
	var f1 := Vector3(a1.x, top, a1.y)
	var fx := (f1 - f0).normalized()
	var fz := fx.cross(Vector3.UP).normalized()
	var fm := (f0 + f1) * 0.5
	var flen := f0.distance_to(f1)
	kit.box("timber", fm, Vector3(0.9, 0.08, flen), Basis.looking_at(f1 - f0, Vector3.UP), 0.85, 0.6)                          # 槽底
	for s in [-1.0, 1.0]:
		kit.box("timber", fm + fz * s * 0.45 + Vector3(0, 0.2, 0), Vector3(0.06, 0.4, flen), Basis.looking_at(f1 - f0, Vector3.UP), 0.85, 0.6)
	kit.box("ice", fm + Vector3(0, 0.08, 0), Vector3(0.8, 0.06, flen), Basis.looking_at(f1 - f0, Vector3.UP), 1.0, 1.0)         # 槽里的水冻了一层
	var rng := RandomNumberGenerator.new()
	rng.seed = 6302
	for k in 18:                                                                                                                # 槽沿挂的冰溜子
		var p := f0.lerp(f1, rng.randf()) + fz * (0.48 if k % 2 == 0 else -0.48)
		var l := rng.randf_range(0.2, 0.6)
		kit.cylinder("ice", p, p - Vector3(0, l, 0), 0.04, 0.005, 4)
	var flume := kit.build({"stone": Look.mat("stone"), "timber": Look.mat("timber"), "dark": PlainVillage.dark(), "ice": _ice()})
	flume.name = "MillFlume"
	parent.add_child(flume)
	var w := MeshKit.new()                                                                                                      # 轮子本身（绕本地 X 转）
	for ring in [-0.45, 0.45]:
		for k in 24:
			var t0 := TAU * k / 24.0
			var t1 := TAU * (k + 1) / 24.0
			w.cylinder("timber", Vector3(ring, sin(t0) * WHEEL_R, cos(t0) * WHEEL_R), Vector3(ring, sin(t1) * WHEEL_R, cos(t1) * WHEEL_R), 0.07, 0.07, 4)
	for k in 8:                                                                                                                 # 辐条
		var t := TAU * k / 8.0
		for ring in [-0.45, 0.45]:
			w.cylinder("timber", Vector3(ring, 0, 0), Vector3(ring, sin(t) * WHEEL_R, cos(t) * WHEEL_R), 0.06, 0.05, 4)
	for k in 16:                                                                                                                # 叶板 + 冰溜子
		var t := TAU * k / 16.0
		var c := Vector3(0, sin(t) * (WHEEL_R - 0.25), cos(t) * (WHEEL_R - 0.25))
		w.box("timber", c, Vector3(1.0, 0.06, 0.5), Basis(Vector3.RIGHT, t), 0.85, 0.6)
		if k % 2 == 0:
			w.cylinder("ice", c + Vector3(0.3, 0, 0), c + Vector3(0.3, -0.35, 0), 0.035, 0.005, 4)
	w.cylinder("timber", Vector3(-0.6, 0, 0), Vector3(0.6, 0, 0), 0.3, 0.3, 10)
	var wm := w.build({"timber": Look.mat("timber"), "ice": _ice()})
	var spin := MillWheel.new()
	spin.name = "MillWheel"
	spin.position = axle
	spin.speed = 0.0 if reduced_motion else 0.12
	spin.add_child(wm)
	parent.add_child(spin)


static func _ice() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.78, 0.86, 0.92)
	m.roughness = 0.15
	m.metallic = 0.0
	m.vertex_color_use_as_albedo = true
	return m


static func map_shapes() -> Array:
	var out := [{"k": "house", "pts": House.footprint(mill_pos(), float(MILL[1]), float(MILL[2]), float(MILL[3])), "label": "水磨坊"}]
	for i in GRANARIES.size():
		out.append({"k": "house", "pts": House.footprint(granary_pos(i), float((GRANARIES[i] as Array)[1]), GRANARY_W, GRANARY_D), "label": "粮仓" if i == 0 else ""})
	return out


## 水轮：慢慢转（「减少动态效果」时不转）
class MillWheel extends Node3D:
	var speed := 0.12

	func _process(delta: float) -> void:
		rotate_x(-speed * delta)
