class_name PlainVillage
extends RefCounted
## 麦渡（路线图 6.2a，D12；STORY.md 6.2「西岸的佃农村：土坯墙、茅草屋顶塌了几处的长屋，空了一半的谷仓，村口一座小木桥过麦河；村里人瘦」）。
## 先回答「这里住着谁、缺什么、刚发生过什么」（ART.md 第十节）：住着洛蒙德家的佃农；缺粮——谷仓的大门敞着，里面只剩几袋，
## 柴垛矮，六栋长屋只有两栋冒烟；刚发生过的——去年冬天饿死过人，村西头那栋没人住了，屋顶塌了一半，门洞里灌满了雪。
##   长屋 6 栋（土坯墙 clay_plaster、石头墙脚、四坡茅草顶 thatch_roof_angled，两栋屋顶塌了一块露出椽子）、谷仓（木板墙、茅草顶、大门敞着）、
##   村口的水井、木桥（麦河上，桥面拱一点，木桩站在水里）、渡口（栈桥 + 一条拴着的平底渡船）、零碎（矮柴垛、空车、木桶）、村口的路牌（旅行地图出发的地方）。
## 同 Highland 的村子：碰撞、门、路牌同步建（一进场就挡得住）；画面每样一件活，交给所在那一块分帧搭。

const WALL_H := 2.1
const PLINTH := 0.45
const EAVE := 0.55
const THATCH := 0.34
const PITCH := 50.0
const BARN_H := 3.3
const COB_TEX := "res://chapters/ch3/tex/clay_plaster_%s_1k.jpg"
const THATCH_TEX := "res://chapters/ch3/tex/thatch_roof_angled_%s_1k.jpg"
const DOOR_TEXTS := ["门从里面闩着。屋里有个孩子在咳。", "门推不开。灶是冷的，屋里没人应声。", "门闩着。里面有人压低声音说：「不是收租的吧？」", "门从里面顶着一根木头。"]
const SIGN_TEXT := "往坠星院 · 洛蒙德庄园"
const SIGN_AT := Vector2(-45.0, 25.5)
const WELL := Vector2(-61.0, 33.0)
## 长屋：[id, 位置, 朝向（度：正面朝哪）, 长, 进深, 冒烟, 塌了哪一段（-1 = 没塌）, 空着（没人住、门洞敞着）]
const LONGHOUSES := [
	["west", Vector2(-77.0, 28.0), 90.0, 13.0, 5.8, true, -1, false],
	["south", Vector2(-66.0, 50.0), 160.0, 12.0, 5.6, false, 3, false],
	["east", Vector2(-40.0, 27.5), -90.0, 11.0, 5.4, true, -1, false],
	["north", Vector2(-48.0, 6.0), -24.0, 12.5, 5.6, false, -1, false],
	["empty", Vector2(-79.0, 8.0), 45.0, 11.0, 5.4, false, 1, true],
	["ida", Vector2(-50.0, 47.0), 200.0, 10.0, 5.2, false, -1, false],
]
const BARN := [Vector2(-84.0, 46.0), 120.0, 15.0, 9.0]           # 谷仓：位置、朝向、长、进深
const DOCK_FROM := Vector2(-18.5, 51.0)                           # 栈桥：岸上那头 → 水里那头
const DOCK_TO := Vector2(-6.0, 51.6)
const DOCK_W := 2.4
const BRIDGE_W := 3.0
const BRIDGE_ARCH := 0.9

static var _mats := {}


static func clear_cache() -> void:
	_mats.clear()


static func ground(p: Vector2) -> float:
	return PlainLayout.height(p.x, p.y)


# ---------------- 材质 ----------------

static func _photo(key: String, path: String, meters: float, tint: Color, fallback: Color) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.95
	var a: Texture2D = load(path % "diff") as Texture2D if ResourceLoader.exists(path % "diff") else null
	var n: Texture2D = load(path % "nor_gl") as Texture2D if ResourceLoader.exists(path % "nor_gl") else null
	if a != null:
		m.albedo_texture = a
		m.albedo_color = tint
		if n != null:
			m.normal_enabled = true
			m.normal_texture = n
		m.uv1_scale = Vector3(1.0 / meters, 1.0 / meters, 1.0)
	else:
		m.albedo_color = fallback
	_mats[key] = m
	return m


static func cob() -> StandardMaterial3D:
	return _photo("cob", COB_TEX, 2.6, Color(0.84, 0.76, 0.66), Color("8a7660"))


static func thatch() -> StandardMaterial3D:
	return _photo("thatch", THATCH_TEX, 2.2, Color(0.72, 0.66, 0.56), Color("7a6a4e"))


static func dark() -> StandardMaterial3D:
	if not _mats.has("dark"):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.05, 0.045, 0.04)
		m.roughness = 1.0
		_mats["dark"] = m
	return _mats["dark"]


static func mats() -> Dictionary:
	return {"cob": cob(), "stone": Look.mat("stone"), "timber": Look.mat("timber"), "thatch": thatch(), "snow": Look.mat("snow"),
		"bark": Look.mat("bark"), "dark": dark(), "glass_lit": Look.glass_lit(), "glass_dark": Look.glass_dark(), "halo": Look.halo(Look.WINDOW_COLOR, 0.32)}


# ---------------- 摆在哪 ----------------

static func house_pos(h: Array) -> Vector3:
	var p: Vector2 = h[1]
	return Vector3(p.x, ground(p) - 0.05, p.y)


## 本地（正面墙脚中点、正面朝 +Z）→ 世界：正面朝 yaw 度
static func place(pos: Vector3, yaw_deg: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), pos)


## 房子中心挪到正面墙脚：位置给的是屋子中心，往前半个进深
static func front_origin(center: Vector2, yaw_deg: float, d: float) -> Vector3:
	var f := Vector2(sin(deg_to_rad(yaw_deg)), cos(deg_to_rad(yaw_deg)))
	var p := center + f * d * 0.5
	return Vector3(p.x, ground(center) - 0.05, p.y)


static func bridge_y(t: float) -> float:
	var a: Vector2 = PlainLayout.BRIDGE[0]
	var b: Vector2 = PlainLayout.BRIDGE[1]
	return lerpf(ground(a), ground(b), t) + 0.12 + BRIDGE_ARCH * sin(PI * t)


static func dock_y() -> float:
	return ground(DOCK_FROM) + 0.12


# ---------------- 碰撞 ----------------

## 所有挡人的东西：[[变换, 尺寸], ...]；桥面和栈桥是能站上去的（同样是盒子）
static func solids() -> Array:
	var out := []
	for h: Array in LONGHOUSES:
		var o := front_origin(h[1], float(h[2]), float(h[4]))
		var xf := place(o, float(h[2]))
		if bool(h[7]):                                       # 空屋：门洞敞着，人进得去（墙四面分开）
			out.append_array(_open_walls(xf, float(h[3]), float(h[4]), WALL_H + 0.5, 1.1))
		else:
			out.append([xf * Transform3D(Basis.IDENTITY, Vector3(0, 1.4, -float(h[4]) * 0.5)), Vector3(float(h[3]) + 0.3, 2.8, float(h[4]) + 0.3)])
	var bo := front_origin(BARN[0], float(BARN[1]), float(BARN[3]))
	out.append_array(_open_walls(place(bo, float(BARN[1])), float(BARN[2]), float(BARN[3]), BARN_H, 4.2))
	var wp := Vector3(WELL.x, ground(WELL), WELL.y)
	out.append([Transform3D(Basis.IDENTITY, wp + Vector3(0, 0.45, 0)), Vector3(1.7, 0.9, 1.7)])
	# 木桥：桥面一段段（跟着拱）、两边栏杆
	var a: Vector2 = PlainLayout.BRIDGE[0]
	var b: Vector2 = PlainLayout.BRIDGE[1]
	var dir := (b - a).normalized()
	var side := Vector2(-dir.y, dir.x)
	var n := 12
	for k in n:
		var t0 := float(k) / n
		var t1 := float(k + 1) / n
		var p0 := Vector3(a.lerp(b, t0).x, bridge_y(t0), a.lerp(b, t0).y)
		var p1 := Vector3(a.lerp(b, t1).x, bridge_y(t1), a.lerp(b, t1).y)
		var x := (p1 - p0).normalized()
		var z := x.cross(Vector3.UP).normalized()
		var y := z.cross(x)
		var c := (p0 + p1) * 0.5
		out.append([Transform3D(Basis(x, y, z), c - y * 0.15), Vector3(p0.distance_to(p1) + 0.05, 0.3, BRIDGE_W)])
		if k > 0 and k < n - 1:
			for s in [-1.0, 1.0]:
				var rc: Vector3 = c + Vector3(side.x, 0, side.y) * s * (BRIDGE_W * 0.5 + 0.05) + Vector3(0, 0.55, 0)
				out.append([Transform3D(Basis(x, y, z), rc), Vector3(p0.distance_to(p1) + 0.05, 1.1, 0.12)])
	# 栈桥
	var dd := DOCK_TO - DOCK_FROM
	var mid := (DOCK_FROM + DOCK_TO) * 0.5
	out.append([Transform3D(Basis(Vector3.UP, -atan2(dd.y, dd.x)), Vector3(mid.x, dock_y() - 0.15, mid.y)), Vector3(dd.length(), 0.3, DOCK_W)])
	for s in props_decor().solids:
		out.append([Transform3D(Basis.IDENTITY, s[0]), s[1]])
	return out


## 四面墙、正面中间留一个门洞（宽 gap）：[[变换, 尺寸]...]
static func _open_walls(xf: Transform3D, w: float, d: float, h: float, gap: float) -> Array:
	var t := 0.4
	var side := (w - gap) * 0.5
	return [
		[xf * Transform3D(Basis.IDENTITY, Vector3(-(gap + side) * 0.5, h * 0.5, 0.0)), Vector3(side, h, t)],
		[xf * Transform3D(Basis.IDENTITY, Vector3((gap + side) * 0.5, h * 0.5, 0.0)), Vector3(side, h, t)],
		[xf * Transform3D(Basis.IDENTITY, Vector3(0, h * 0.5, -d)), Vector3(w, h, t)],
		[xf * Transform3D(Basis.IDENTITY, Vector3(-w * 0.5, h * 0.5, -d * 0.5)), Vector3(t, h, d)],
		[xf * Transform3D(Basis.IDENTITY, Vector3(w * 0.5, h * 0.5, -d * 0.5)), Vector3(t, h, d)],
	]


## 门、路牌（同步）
static func interactables(parent: Node3D) -> void:
	var k := 0
	for h: Array in LONGHOUSES:
		if bool(h[7]):
			continue
		var d := Door.make("门", 0.95, 1.8, true)
		d.locked_text = DOOR_TEXTS[k % DOOR_TEXTS.size()]
		k += 1
		d.name = "LonghouseDoor_" + str(h[0])
		d.transform = place(front_origin(h[1], float(h[2]), float(h[4])), float(h[2])) * Transform3D(Basis.IDENTITY, Vector3(door_x(h) - 0.475, 0, 0.12))
		parent.add_child(d)
	var rs := RoadSign.new()
	rs.text = SIGN_TEXT
	rs.position = Vector3(SIGN_AT.x, ground(SIGN_AT), SIGN_AT.y)
	rs.rotation_degrees.y = 120.0
	parent.add_child(rs)


static func door_x(h: Array) -> float:
	return -float(h[3]) * 0.18


# ---------------- 零碎 ----------------

## 村里的零碎：一份 Decor（碰撞同步建，画面按块）；rect 不空时只要那一块里的
static func props_decor(rect := Rect2()) -> Decor:
	var d := Decor.new()
	var inside := func(p: Vector2) -> bool: return rect.size == Vector2.ZERO or rect.has_point(p)
	for h: Array in LONGHOUSES:                          # 各家山墙边一垛柴，矮（柴不够烧）；空屋那家没有
		if bool(h[7]):
			continue
		var yaw := deg_to_rad(float(h[2]))
		var right := Vector2(cos(yaw), -sin(yaw))
		var fwd := Vector2(sin(yaw), cos(yaw))
		var p: Vector2 = (h[1] as Vector2) + right * (float(h[3]) * 0.5 + 0.8)
		if inside.call(p):
			d.woodpile(Vector3(p.x, ground(p), p.y), Vector3(fwd.x, 0, fwd.y), 1.4, 0.45)
	var bc: Vector2 = BARN[0]
	var items := [
		["cart", Vector2(-55.0, 38.0), 0.6, "wood"],               # 空车：车上几根木头，没有粮
		["cart", bc + Vector2(7.5, 4.0), -0.4, "wood"],
		["barrel", WELL + Vector2(1.5, 0.6)], ["barrel", Vector2(-38.0, 33.5)],
		["sack", bc + Vector2(-2.0, -1.0), 0.4], ["sack", bc + Vector2(-1.2, -1.6), 1.6], ["sack", bc + Vector2(-2.6, -2.0), 2.4],   # 谷仓里只剩三袋
		["crate", Vector2(-72.0, 36.5), 0.3], ["crate", Vector2(-16.5, 53.5), 0.9],
		["barrel", Vector2(-17.2, 48.6)],
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


# ---------------- 画面（分帧的活） ----------------

static func jobs_for(rect: Rect2, reduced_motion: bool) -> Array:
	var out := []
	for h: Array in LONGHOUSES:
		if rect.has_point(h[1]):
			out.append(func(root: Node3D): longhouse(root, h, reduced_motion))
	if rect.has_point(BARN[0]):
		out.append(func(root: Node3D): barn(root))
	if rect.has_point(WELL):
		out.append(func(root: Node3D): well(root))
	var bm := ((PlainLayout.BRIDGE[0] as Vector2) + (PlainLayout.BRIDGE[1] as Vector2)) * 0.5
	if rect.has_point(bm):
		out.append(func(root: Node3D): bridge(root))
	if rect.has_point((DOCK_FROM + DOCK_TO) * 0.5):
		out.append(func(root: Node3D): dock(root))
	if not props_decor(rect).kit.tools.is_empty():
		out.append(func(root: Node3D): _props(root, rect))
	return out


static func _props(root: Node3D, rect: Rect2) -> void:
	var d := props_decor(rect)
	var mi := d.kit.build(d.mats)
	mi.name = "MaiduProps"
	root.add_child(mi)


## 一栋长屋：土坯墙 + 石头墙脚 + 四坡茅草顶（塌了的那段露出椽子、底下黑洞洞的）+ 小窗 + 门
static func longhouse(parent: Node3D, h: Array, reduced_motion := false) -> Node3D:
	var w := float(h[3])
	var d := float(h[4])
	var yaw := float(h[2])
	var root := Node3D.new()
	root.name = "Longhouse_" + str(h[0])
	root.transform = place(front_origin(h[1], yaw, d), yaw)
	root.add_to_group("house")
	parent.add_child(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(h[0]))
	var kit := MeshKit.new()
	var windows := {"lit": 0, "dark": 0}
	var empty := bool(h[7])
	_walls(kit, w, d, WALL_H, "cob", empty, 1.1, rng)
	var dx := door_x(h)
	if not empty:
		kit.box("timber", Vector3(dx, 0.9, 0.04), Vector3(0.95, 1.8, 0.08), Basis.IDENTITY, 0.75, 0.6)
	else:
		kit.box("snow", Vector3(0, 0.12, -1.2), Vector3(1.6, 0.4, 2.2), Basis(Vector3.RIGHT, -0.18), 1.0, 0.9)   # 门洞里灌进来的雪
	kit.box("timber", Vector3(dx if not empty else 0.0, 1.92, 0.12), Vector3(1.5 if not empty else 1.6, 0.16, 0.3), Basis.IDENTITY, 0.8, 0.7)
	for x in [-w * 0.36, w * 0.3]:                       # 小窗：大半黑着（柴不够、灯油更不够）
		if absf(x - dx) > 1.4:
			House._window(kit, Vector3(x, 1.35, 0.0), 0.5, 0.42, (not empty) and rng.randf() < 0.3, rng.randf() < 0.5, windows, "timber")
	_roof(kit, w, d, WALL_H, int(h[6]), rng)
	if empty:
		kit.box("timber", Vector3(w * 0.15, 0.25, -d * 0.6), Vector3(3.0, 0.18, 0.22), Basis(Vector3.UP, 0.6) * Basis(Vector3.FORWARD, 0.4), 0.7, 0.6)   # 塌下来的椽子
	var mi := kit.build(mats())
	mi.name = "Mesh"
	root.add_child(mi)
	if bool(h[5]):
		Atmos.smoke(root, Vector3(w * 0.12, WALL_H + _rise(d) + 0.4, -d * 0.5))
	root.set_meta("windows", windows)
	root.set_meta("seed", hash(str(h[0])))
	root.set_meta("size", Vector2(w, d))
	return root


static func _rise(d: float) -> float:
	return (d * 0.5 + EAVE) * tan(deg_to_rad(PITCH))


## 四面墙：石头墙脚 + 土坯（往上微收、墙角圆一点）；open = 正面中间开一个门洞（宽 gap）
static func _walls(kit: MeshKit, w: float, d: float, h: float, key: String, open: bool, gap: float, rng: RandomNumberGenerator) -> void:
	var t := 0.45
	if open:
		var side := (w - gap) * 0.5
		for s in [-1.0, 1.0]:
			kit.box(key, Vector3(s * (gap + side) * 0.5, h * 0.5, -t * 0.5), Vector3(side, h, t), Basis.IDENTITY, 1.0, 0.55)
		kit.box("timber", Vector3(0, h - 0.1, -t * 0.5), Vector3(gap + 0.4, 0.2, t + 0.05), Basis.IDENTITY, 0.8, 0.7)
		kit.box(key, Vector3(0, h * 0.5, -d + t * 0.5), Vector3(w, h, t), Basis.IDENTITY, 1.0, 0.55)
		for s in [-1.0, 1.0]:
			kit.box(key, Vector3(s * (w * 0.5 - t * 0.5), h * 0.5, -d * 0.5), Vector3(t, h, d), Basis.IDENTITY, 1.0, 0.55)
		kit.box("dark", Vector3(0, 0.02, -d * 0.5), Vector3(w - t * 2.0, 0.04, d - t * 2.0))               # 屋里的地：暗
	else:
		kit.box(key, Vector3(0, h * 0.5, -d * 0.5), Vector3(w, h, d), Basis.IDENTITY, 1.0, 0.55)
	if key == "cob":
		kit.box("stone", Vector3(0, PLINTH * 0.5, -d * 0.5), Vector3(w + 0.12, PLINTH, d + 0.12), Basis.IDENTITY, 0.7, 0.45)
		for cx in [-w * 0.5, w * 0.5]:                         # 墙角一根粗木柱（土坯墙的骨架露出来）
			for cz in [0.0, -d]:
				kit.box("timber", Vector3(cx, h * 0.5, cz), Vector3(0.24, h, 0.24), Basis(Vector3.UP, rng.randf_range(-0.05, 0.05)), 0.8, 0.5)


## 四坡茅草顶：前后两个梯形坡 + 两头两个三角坡；厚 THATCH，檐口一道厚边；雪只盖上半截（茅草顶陡，雪往下滑）。
## hole = 前坡的第几段塌了（前坡按约 2 米分段；-1 = 没塌）：那一段不铺草，露出三根椽子、底下黑洞洞的
static func _roof(kit: MeshKit, w: float, d: float, h: float, hole: int, rng: RandomNumberGenerator) -> void:
	var rise := _rise(d)
	var top := h + rise
	var half_ridge := maxf(w * 0.5 - d * 0.5, 0.4)
	var x0 := -w * 0.5 - EAVE
	var x1 := w * 0.5 + EAVE
	var zf := EAVE
	var zb := -d - EAVE
	var zm := -d * 0.5
	var r0 := Vector3(-half_ridge, top, zm)
	var r1 := Vector3(half_ridge, top, zm)
	var segs := maxi(int(round(w / 2.0)), 3)
	for side in [1.0, -1.0]:
		var ez := zf if side > 0 else zb
		var a := Vector3(x0, h - 0.05, ez)
		var b := Vector3(x1, h - 0.05, ez)
		var n := (b - a).cross(r0 - a).normalized()
		if n.y < 0:
			n = -n
		var up := n * THATCH
		for k in segs:
			var t0 := float(k) / segs
			var t1 := float(k + 1) / segs
			var ea := a.lerp(b, t0)
			var eb := a.lerp(b, t1)
			var ra := r0.lerp(r1, clampf(inverse_lerp(-w * 0.5, w * 0.5, ea.x), 0.0, 1.0))
			var rb := r0.lerp(r1, clampf(inverse_lerp(-w * 0.5, w * 0.5, eb.x), 0.0, 1.0))
			# 屋脊那条线只有中间一段：两头的分段，屋脊端点收在 r0 / r1（和三角坡接上）
			ra = Vector3(clampf(ea.x, -half_ridge, half_ridge), top, zm)
			rb = Vector3(clampf(eb.x, -half_ridge, half_ridge), top, zm)
			if side > 0 and k == hole:
				for j in 3:                                    # 塌了的那段：三根椽子、底下黑
					var tx := lerpf(ea.x, eb.x, (j + 0.5) / 3.0)
					kit.cylinder("timber", Vector3(tx, h, ez * 0.6), Vector3(clampf(tx, -half_ridge, half_ridge), top - 0.1, zm), 0.06, 0.05, 5)
				kit.quad("dark", [Vector3(ea.x + 0.2, h - 0.02, 0.0), Vector3(eb.x - 0.2, h - 0.02, 0.0), Vector3(eb.x - 0.2, h - 0.02, -d * 0.5), Vector3(ea.x + 0.2, h - 0.02, -d * 0.5)], Vector3.UP)
				kit.quad("snow", [Vector3(ea.x + 0.3, h - 0.01, -0.3), Vector3(eb.x - 0.3, h - 0.01, -0.3), Vector3(eb.x - 0.5, h - 0.01, -d * 0.4), Vector3(ea.x + 0.5, h - 0.01, -d * 0.4)], Vector3.UP, [0.8, 0.8, 0.8, 0.8])
				continue
			var q := [ea + up, eb + up, rb + up, ra + up] if side > 0 else [eb + up, ea + up, ra + up, rb + up]
			kit.quad("thatch", q, n)
			kit.quad("thatch", [ea, eb, eb + up, ea + up] if side > 0 else [eb, ea, ea + up, eb + up], Vector3(0, 0, side))     # 檐口的厚边
			var sa := ea.lerp(ra, 0.52) + up + n * 0.05                                  # 雪：上半截
			var sb := eb.lerp(rb, 0.52) + up + n * 0.05
			var cov := rng.randf_range(0.85, 1.0)
			kit.quad("snow", [sa, sb, rb + up + n * 0.08, ra + up + n * 0.08] if side > 0 else [sb, sa, ra + up + n * 0.08, rb + up + n * 0.08], n, [cov, cov, 1.0, 1.0])
	for side in [-1.0, 1.0]:                                   # 两头的三角坡
		var a := Vector3(side * x1, h - 0.05, zf)
		var b := Vector3(side * x1, h - 0.05, zb)
		var r := r1 if side > 0 else r0
		var n := (b - a).cross(r - a).normalized()
		if n.x * side < 0:
			n = -n
		var up := n * THATCH
		if side > 0:
			kit.tri("thatch", a + up, b + up, r + up, n)
		else:
			kit.tri("thatch", b + up, a + up, r + up, n)
		kit.quad("thatch", [b, a, a + up, b + up] if side > 0 else [a, b, b + up, a + up], Vector3(side, 0, 0))
		var sa := a.lerp(r, 0.52) + up + n * 0.05
		var sb := b.lerp(r, 0.52) + up + n * 0.05
		if side > 0:
			kit.tri("snow", sa, sb, r + up + n * 0.08, n)
		else:
			kit.tri("snow", sb, sa, r + up + n * 0.08, n)
	kit.box("thatch", Vector3(0, top + THATCH * 0.7, zm), Vector3(half_ridge * 2.0 + 0.6, 0.3, 0.6), Basis.IDENTITY, 0.9, 0.7)     # 屋脊一道压草
	kit.box("snow", Vector3(0, top + THATCH + 0.02, zm), Vector3(half_ridge * 2.0 + 0.4, 0.14, 0.5), Basis.IDENTITY, 1.0, 0.9)


## 谷仓：木板墙、四坡茅草顶、正面一对大门敞着；里面空空的地上只有三袋（零碎里）
static func barn(parent: Node3D) -> Node3D:
	var w := float(BARN[2])
	var d := float(BARN[3])
	var yaw := float(BARN[1])
	var root := Node3D.new()
	root.name = "Barn"
	root.transform = place(front_origin(BARN[0], yaw, d), yaw)
	parent.add_child(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = 6201
	var kit := MeshKit.new()
	_walls(kit, w, d, BARN_H, "timber", true, 4.2, rng)
	kit.box("stone", Vector3(0, 0.15, -d * 0.5), Vector3(w + 0.1, 0.3, d + 0.1), Basis.IDENTITY, 0.7, 0.45)
	for s in [-1.0, 1.0]:                                     # 两扇大门往外敞着
		var hinge := Vector3(s * 2.1, 0, 0.1)
		var leaf := Basis(Vector3.UP, s * deg_to_rad(110.0))
		kit.box("timber", hinge + leaf * Vector3(-s * 1.05, 1.5, 0.0), Vector3(2.1, 3.0, 0.1), leaf, 0.8, 0.6)
	kit.box("timber", Vector3(0, 0.03, -d * 0.5), Vector3(w - 1.0, 0.06, d - 1.0), Basis.IDENTITY, 0.5, 0.5)     # 打谷的木地板（暗）
	for k in 3:                                               # 屋里的柱子
		var x := lerpf(-w * 0.3, w * 0.3, k / 2.0)
		kit.box("timber", Vector3(x, BARN_H * 0.5, -d * 0.5), Vector3(0.3, BARN_H, 0.3), Basis.IDENTITY, 0.7, 0.4)
	_roof(kit, w, d, BARN_H, -1, rng)
	var mi := kit.build(mats())
	mi.name = "Mesh"
	root.add_child(mi)
	return root


## 村口的水井：石砌井栏、两根木柱一根横梁、绳子吊着桶
static func well(parent: Node3D) -> void:
	var kit := MeshKit.new()
	for k in 10:
		var a := TAU * k / 10.0
		kit.box("stone", Vector3(cos(a) * 0.7, 0.42, sin(a) * 0.7), Vector3(0.48, 0.84, 0.3), Basis(Vector3.UP, -a + PI * 0.5), 0.9, 0.6)
	kit.box("snow", Vector3(0, 0.86, 0), Vector3(1.6, 0.05, 1.6), Basis.IDENTITY, 1.0, 1.0)
	kit.box("dark", Vector3(0, 0.88, 0), Vector3(1.05, 0.02, 1.05))
	for s in [-1.0, 1.0]:
		kit.box("timber", Vector3(s * 0.85, 1.2, 0), Vector3(0.14, 2.4, 0.14), Basis.IDENTITY, 0.8, 0.6)
	kit.cylinder("timber", Vector3(-0.95, 2.2, 0), Vector3(0.95, 2.2, 0), 0.08, 0.08, 6)
	kit.cylinder("bark", Vector3(0, 2.15, 0), Vector3(0, 1.3, 0), 0.012, 0.012, 4)
	kit.cylinder("timber", Vector3(0, 1.3, 0), Vector3(0, 1.02, 0), 0.16, 0.13, 8)
	var mi := kit.build(mats())
	mi.name = "Well"
	mi.position = Vector3(WELL.x, ground(WELL), WELL.y)
	parent.add_child(mi)


## 木桥：桥面一块块横铺的木板跟着拱、两根纵梁、栏杆；每 3 米一排木桩（两根）站进河里
static func bridge(parent: Node3D) -> void:
	var a: Vector2 = PlainLayout.BRIDGE[0]
	var b: Vector2 = PlainLayout.BRIDGE[1]
	var dir := (b - a).normalized()
	var side := Vector2(-dir.y, dir.x)
	var len := a.distance_to(b)
	var kit := MeshKit.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 6202
	var n := int(len / 0.45)
	for k in n:                                             # 横铺的木板
		var t := (k + 0.5) / n
		var p := a.lerp(b, t)
		var y := bridge_y(t)
		var basis := Basis(Vector3(side.x, 0, side.y), Vector3.UP, Vector3(-dir.x, 0, -dir.y)).orthonormalized()
		basis = basis * Basis(Vector3.RIGHT, -atan2(bridge_y(t + 0.01) - bridge_y(t - 0.01), len * 0.02))
		kit.box("timber", Vector3(p.x, y - 0.05, p.y), Vector3(BRIDGE_W + rng.randf_range(-0.1, 0.1), 0.1, 0.42), basis * Basis(Vector3.UP, rng.randf_range(-0.03, 0.03)), 0.95, 0.7)
	var m := 16
	for k in m:                                             # 纵梁、栏杆（一段段跟着拱）
		var t0 := float(k) / m
		var t1 := float(k + 1) / m
		for s in [-1.0, 1.0]:
			var o: Vector3 = Vector3(side.x, 0, side.y) * s
			var p0 := Vector3(a.lerp(b, t0).x, bridge_y(t0), a.lerp(b, t0).y)
			var p1 := Vector3(a.lerp(b, t1).x, bridge_y(t1), a.lerp(b, t1).y)
			kit.cylinder("timber", p0 + o * (BRIDGE_W * 0.5 - 0.3) - Vector3(0, 0.22, 0), p1 + o * (BRIDGE_W * 0.5 - 0.3) - Vector3(0, 0.22, 0), 0.13, 0.13, 6)
			if k > 0 and k < m - 1:
				kit.cylinder("timber", p0 + o * BRIDGE_W * 0.5 + Vector3(0, 1.0, 0), p1 + o * BRIDGE_W * 0.5 + Vector3(0, 1.0, 0), 0.06, 0.06, 5)
				kit.box("timber", p0 + o * BRIDGE_W * 0.5 + Vector3(0, 0.5, 0), Vector3(0.12, 1.05, 0.12), Basis.IDENTITY, 0.85, 0.6)
				kit.box("snow", p0 + o * BRIDGE_W * 0.5 + Vector3(0, 1.08, 0), Vector3(0.16, 0.05, 0.16), Basis.IDENTITY, 1.0, 1.0)
	var s := 1.5
	while s < len - 1.0:                                     # 木桩：站进水里 / 泥岸里
		var t := s / len
		var p := a.lerp(b, t)
		var y := bridge_y(t)
		var bed := ground(p)
		if y - bed > 0.6:
			for sd in [-1.0, 1.0]:
				var q: Vector2 = p + side * sd * (BRIDGE_W * 0.5 - 0.3)
				kit.cylinder("bark", Vector3(q.x, bed - 0.4, q.y), Vector3(q.x, y - 0.25, q.y), 0.17, 0.15, 7)
			kit.cylinder("timber", Vector3((p - side * 1.4).x, y - 0.32, (p - side * 1.4).y), Vector3((p + side * 1.4).x, y - 0.32, (p + side * 1.4).y), 0.1, 0.1, 5)
		s += 3.0
	var mi := kit.build(mats())
	mi.name = "Bridge"
	parent.add_child(mi)


## 渡口：栈桥（木板、两排木桩）+ 一条拴着的平底渡船（船里一根撑篙）+ 拴船桩
static func dock(parent: Node3D) -> void:
	var kit := MeshKit.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 6203
	var dd := DOCK_TO - DOCK_FROM
	var dir := dd.normalized()
	var side := Vector2(-dir.y, dir.x)
	var y := dock_y()
	var basis := Basis(Vector3(side.x, 0, side.y), Vector3.UP, Vector3(-dir.x, 0, -dir.y)).orthonormalized()
	var n := int(dd.length() / 0.4)
	for k in n:
		var p := DOCK_FROM + dir * ((k + 0.5) * dd.length() / n)
		kit.box("timber", Vector3(p.x, y - 0.05, p.y), Vector3(DOCK_W + rng.randf_range(-0.12, 0.12), 0.1, 0.37), basis * Basis(Vector3.UP, rng.randf_range(-0.04, 0.04)), 0.95, 0.7)
	var s := 1.0
	while s <= dd.length():
		var p := DOCK_FROM + dir * s
		for sd in [-1.0, 1.0]:
			var q: Vector2 = p + side * sd * (DOCK_W * 0.5 - 0.1)
			kit.cylinder("bark", Vector3(q.x, ground(q) - 0.4, q.y), Vector3(q.x, y + (0.5 if s > dd.length() - 1.5 else -0.1), q.y), 0.14, 0.13, 7)
		s += 2.4
	# 渡船：拴在栈桥南边，浮在水面上
	var bc := DOCK_TO - dir * 2.6 - side * (DOCK_W * 0.5 + 1.15)
	var wy := PlainLayout.WATER_Y
	var bb := Basis(Vector3(dir.x, 0, dir.y), Vector3.UP, Vector3(side.x, 0, side.y) * -1.0).orthonormalized()
	var bp := Vector3(bc.x, wy + 0.12, bc.y)
	kit.box("timber", bp, Vector3(6.4, 0.12, 1.7), bb, 0.6, 0.5)                                     # 船底
	for sd in [-1.0, 1.0]:
		kit.box("timber", bp + bb * Vector3(0, 0.25, sd * 0.85), Vector3(6.4, 0.5, 0.1), bb, 0.85, 0.6)    # 两舷
		kit.box("timber", bp + bb * Vector3(sd * 3.2, 0.3, 0), Vector3(0.1, 0.42, 1.7), bb * Basis(Vector3.FORWARD, sd * 0.5), 0.85, 0.6)   # 两头斜着翘起来
	kit.box("snow", bp + bb * Vector3(0.6, 0.09, 0), Vector3(3.6, 0.04, 1.4), bb, 1.0, 1.0)
	kit.cylinder("timber", bp + bb * Vector3(-2.8, 0.3, 0.4), bp + bb * Vector3(2.6, 0.55, -0.2), 0.035, 0.03, 5)   # 撑篙
	kit.cylinder("bark", Vector3(bp.x, wy + 0.4, bp.z) + Vector3(dir.x, 0, dir.y) * 2.6 + Vector3(side.x, 0, side.y) * 0.85, Vector3((DOCK_TO - dir * 0.2).x, y + 0.3, (DOCK_TO - dir * 0.2).y) - Vector3(side.x, 0, side.y) * (DOCK_W * 0.5 - 0.1), 0.012, 0.012, 4)  # 缆绳
	var mi := kit.build(mats())
	mi.name = "Dock"
	parent.add_child(mi)


## 地图上的房子（本地地图 map_spec 用）
static func map_shapes() -> Array:
	var out := []
	for h: Array in LONGHOUSES:
		out.append({"k": "house", "pts": House.footprint(front_origin(h[1], float(h[2]), float(h[4])), float(h[2]), float(h[3]), float(h[4]))})
	out.append({"k": "house", "pts": House.footprint(front_origin(BARN[0], float(BARN[1]), float(BARN[3])), float(BARN[1]), float(BARN[2]), float(BARN[3])), "label": "谷仓"})
	return out
