class_name PlainCamp
extends RefCounted
## 塞弗林营地（路线图 6.3c，D12；STORY.md 6.2「平原东北角、砧山来的路口：帐篷、熔炉车（流动的铁匠炉）、拴马桩、红底铁砧托冠的旗」）。
## 先回答「这里住着谁、缺什么、刚发生过什么」（ART.md 第十节）：
##   住着——摄政的征粮官奥迪隆（第一章那个灰斗篷信使）和二十来个从砧山下来的兵、一个跟车的铁匠和他的学徒（6.5 支线）；
##   缺的是粮——四辆大车空着排在路边，等着装磨坊的粮上砧山；火上那锅汤稀得见底；铁多得是：熔炉车整天烧着，打的是枪头和马掌；
##   刚发生过的——营地才扎下两三天：帐篷之间的雪踩成了泥，路口朝庄园那边插了两排削尖的木桩（他们等着打一仗）。
##   指挥帐（圆顶、红白相间，能走进去：桌上摊着地图、酒壶和杯子，奥迪隆请你喝酒就在这儿，6.4）、六顶人字帐篷、熔炉车（车上一个泥砌的炉膛、
##   铁皮烟囱、皮风箱，旁边树墩上的铁砧、淬火的桶）、营火和吊锅、拴马桩和四匹披着马衣的马、四辆空粮车、两面红底铁砧托冠的旗、兵器架、木桩。
## 帐篷的帆布：Poly Haven 的粗麻布照片（hessian_380，CC0；6.M 原定从 ambientCG 挑，2026-11-05 本环境连不上 ambientCG 的下载服务器）。
## 同庄园、磨坊：碰撞、路牌同步建；画面每样一件活（ChunkStreamer 每件活 40 毫秒以内）。坐标是平原的世界坐标。
##
## 营地顺着大车道摆：路从西南（庄园）进来、往东北（砧山）出去。at(u, v)：u 沿路往东北，v 往路的东南边（负的是西北边）。

const CANVAS_TEX := "res://chapters/ch3/tex/hessian_380_%s_1k.jpg"
const ALONG := Vector2(0.576, -0.818)        # 路的方向（往砧山）：两段路方向的平均
const SIDE := Vector2(0.818, 0.576)          # 路的东南边
const YAW_ALONG := -35.2                    # 面朝砧山的朝向（度）：-sin(yaw) = ALONG.x、-cos(yaw) = ALONG.y

const FIELD := Color("8e1f1c")               # 塞弗林家：红底铁砧托冠（WORLD.md 第五节）
const CHARGE := Color("c4c8cc")              # 铁砧：铁灰
const CROWN := Color("c8a440")               # 冠：金

## 指挥帐：[u, v, 半径]；门朝路（东南）。2026-11-07 所有者反馈「建筑物太小人物无法进出、找不到人物对话」：
## 原来半径 3.1、帐墙 1.7 米（檐口垂边再往下 0.32，门比人还矮），放大成半径 4.4、帐墙 2.5、顶 5.4；里头的桌子、床、箱子、奥迪隆按 PAV_K 一起往外挪
const PAVILION := [3.0, -11.0, 4.4]
const PAV_WALL := 2.5
const PAV_PEAK := 5.4
const PAV_K := 4.4 / 3.1
## 人字帐篷：[u, v, 门朝哪边（1 = 东南、-1 = 西北，门对着路）]
const TENTS := [[-9.0, 7.8, -1], [-3.5, 8.2, -1], [2.0, 7.8, -1], [7.5, 8.2, -1], [-13.0, -10.5, 1], [-7.0, -15.5, 1]]
const TENT_W := 2.4
const TENT_L := 3.4
const TENT_H := 2.0
const FORGE := [11.5, -6.5]                  # 熔炉车（车身沿路）
const FIRE := [-6.0, -8.0]                   # 营火
const HITCH := [13.5, 8.5]                   # 拴马桩（沿路，4.4 米）
const HORSES := 4
const WAGONS := [[-9.0, 13.2], [-3.2, 13.6], [2.6, 13.2], [8.4, 13.6]]   # 四辆空粮车（车头朝东北）
const STAKES_U := -17.0                      # 朝庄园那边的两排木桩（路两边各一排，路当中留着）
const BANNERS := [[0.0, -5.6], [-16.0, 4.2]] # 两面旗：指挥帐前一面，营地口一面
const RACK := [-1.0, -6.4]
const SIGN := [-18.5, -3.6]
const SIGN_TEXT := "往庄园 · 往砧山"

static var _mats := {}


static func clear_cache() -> void:
	_mats.clear()


static func at(u: float, v: float) -> Vector2:
	return PlainLayout.CAMP + ALONG * u + SIDE * v


static func at3(u: float, v: float, lift := 0.0) -> Vector3:
	var p := at(u, v)
	return Vector3(p.x, ground(p) + lift, p.y)


static func ground(p: Vector2) -> float:
	return PlainLayout.height(p.x, p.y)


## 沿路的朝向（Basis）：本地 -Z 朝砧山、+X 朝路的东南边
static func road_basis() -> Basis:
	return Basis(Vector3.UP, deg_to_rad(YAW_ALONG))


# ---------------- 材质 ----------------

static func canvas(red := false) -> StandardMaterial3D:
	var key := "canvas_red" if red else "canvas"
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.95
	m.cull_mode = BaseMaterial3D.CULL_DISABLED            # 帐篷里头看得见帆布的反面
	m.set_meta("avg", Color("8a2a22") if red else Color("c9b590"))     # FarLod（6.7a）
	var a: Texture2D = load(CANVAS_TEX % "diff") as Texture2D if ResourceLoader.exists(CANVAS_TEX % "diff") else null
	var n: Texture2D = load(CANVAS_TEX % "nor_gl") as Texture2D if ResourceLoader.exists(CANVAS_TEX % "nor_gl") else null
	if a != null:
		m.albedo_texture = a
		m.albedo_color = Color(0.8, 0.22, 0.19) if red else Color(0.94, 0.92, 0.86)    # 照片是麻布的黄褐色：本色帆布提亮一点、红的压成暗红
		if n != null:
			m.normal_enabled = true
			m.normal_texture = n
			m.normal_scale = 0.6
		m.uv1_scale = Vector3(1.0 / 3.5, 1.0 / 3.5, 1.0)              # 0.9 / 2 米一次近看有摩尔纹（截图）：粗帆布
	else:
		m.albedo_color = Color("8a2a22") if red else Color("c9b590")
	_mats[key] = m
	return m


static func mats() -> Dictionary:
	if not _mats.has("all"):
		_mats["all"] = {"canvas": canvas(), "red": canvas(true), "timber": _wood(), "snow": Look.mat("snow"), "stone": Look.mat("stone"),
			"dark": PlainVillage.dark(), "iron": Inn._iron_mat(), "ember": Inn._unshaded(Color("ff6a1e")), "rope": _flat(Color("8a7a5a")),
			"straw": _flat(Color("8a7448")), "clay": PlainVillage.cob(), "leather": _flat(Color("4a3424")), "horse": _flat(Color("4e3626")),
			"horse2": _flat(Color("2e2620")), "mane": _flat(Color("1c1814")), "gold": _flat(Color("b89a4a"), 0.5, 0.5)}
	return _mats["all"]


## 营地的木头（车、桩、杆）：Look 的旧木板照片压得很暗，阴天里车成了一团黑（截图）：提亮一点
static func _wood() -> StandardMaterial3D:
	var m := Look.mat("timber").duplicate() as StandardMaterial3D
	m.albedo_color = Color(0.95, 0.85, 0.74)
	return m


static func _flat(c: Color, rough := 0.9, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	m.vertex_color_use_as_albedo = true
	return m


# ---------------- 碰撞 ----------------

static func solids() -> Array:
	var out := []
	var rb := road_basis()
	var pc: Vector3 = at3(PAVILION[0], PAVILION[1])
	var r: float = PAVILION[2]
	for k in 8:                                            # 指挥帐八面墙，朝路的那面是门
		if k == _pav_door():
			continue
		var a0 := TAU * k / 8.0
		var a1 := TAU * (k + 1) / 8.0
		var m := (Vector3(cos(a0), 0, sin(a0)) + Vector3(cos(a1), 0, sin(a1))) * 0.5 * r
		out.append([Transform3D(Basis(Vector3.UP, -(a0 + a1) * 0.5 + PI * 0.5), pc + m + Vector3(0, 1.0, 0)), Vector3(r * 0.78, 2.0, 0.25)])
	out.append([Transform3D(Basis.IDENTITY, pc + Vector3(0, 1.5, 0)), Vector3(0.2, 3.0, 0.2)])          # 中间的柱子
	for it in _pav_furniture():
		out.append([Transform3D(Basis(Vector3.UP, float(it[2])), pc + (it[0] as Vector3)), it[1]])
	for t: Array in TENTS:
		out.append([Transform3D(_tent_basis(t), at3(t[0], t[1], TENT_H * 0.4)), Vector3(TENT_W + 0.2, TENT_H * 0.8, TENT_L + 0.2)])
	out.append([Transform3D(rb, at3(FORGE[0], FORGE[1], 1.0)), Vector3(1.9, 2.0, 3.6)])
	out.append([Transform3D(rb, at3(FORGE[0] - 0.4, FORGE[1] + 1.6, 0.4)), Vector3(0.6, 0.8, 0.6)])     # 铁砧和树墩（同 forge() 里 an 的位置）
	out.append([Transform3D(rb, at3(FIRE[0], FIRE[1], 0.5)), Vector3(1.4, 1.0, 1.4)])
	for w: Array in WAGONS:
		out.append([Transform3D(rb, at3(w[0], w[1], 0.8)), Vector3(1.9, 1.6, 3.6)])
	out.append([Transform3D(rb, at3(HITCH[0], HITCH[1], 0.6)), Vector3(0.3, 1.2, 4.6)])
	for k in HORSES:
		out.append([Transform3D(rb * Basis(Vector3.UP, PI * 0.5), at3(HITCH[0] - 1.9 + k * 1.25, HITCH[1] + 1.4, 0.9)), Vector3(0.7, 1.8, 2.2)])
	for s in [-1.0, 1.0]:                                  # 两排木桩
		var v0: float = s * 4.0
		var v1: float = s * 14.0
		var m := at((STAKES_U), (v0 + v1) * 0.5)
		out.append([Transform3D(rb, Vector3(m.x, ground(m) + 0.6, m.y)), Vector3(absf(v1 - v0), 1.2, 0.9)])
	for b: Array in BANNERS:
		out.append([Transform3D(Basis.IDENTITY, at3(b[0], b[1], 2.5)), Vector3(0.25, 5.0, 0.25)])
	out.append([Transform3D(rb, at3(RACK[0], RACK[1], 0.8)), Vector3(1.6, 1.6, 0.4)])
	for sd in props_decor().solids:
		out.append([Transform3D(Basis.IDENTITY, sd[0]), sd[1]])
	return out


## 指挥帐哪一面是门（朝路：东南）：八边形第 k 面的中点方向最接近 SIDE 的那面
static func _pav_door() -> int:
	var best := 0
	var bd := -2.0
	for k in 8:
		var a := TAU * (k + 0.5) / 8.0
		var d := Vector2(cos(a), sin(a)).dot(-SIDE * signf(float(PAVILION[1])))
		if d > bd:
			bd = d
			best = k
	return best


## 帐里的东西（相对帐中心）：[位置, 碰撞尺寸, 朝向]
static func _pav_furniture() -> Array:
	var back := Vector3(SIDE.x, 0, SIDE.y) * signf(float(PAVILION[1]))      # 门的反方向（帐子后头）
	var yaw := deg_to_rad(YAW_ALONG)
	var along := Vector3(ALONG.x, 0, ALONG.y)
	return [[(back * 0.9 - along * 1.25) * PAV_K + Vector3(0, 0.4, 0), Vector3(1.5, 0.8, 0.85), yaw],            # 桌子（摊着地图；让开中柱）
		[back * 2.15 * PAV_K + Vector3(0, 0.25, 0), Vector3(1.9, 0.5, 0.75), yaw],              # 行军床
		[(back * 1.2 + Vector3(ALONG.x, 0, ALONG.y) * 1.9) * PAV_K + Vector3(0, 0.3, 0), Vector3(0.9, 0.6, 0.55), yaw]]   # 箱子（6.5 摄政的信就在里头）


static func _tent_basis(t: Array) -> Basis:
	return road_basis() * Basis(Vector3.UP, PI * 0.5 * float(t[2]))    # 帐篷本地 +Z 是门那头：朝着路


static func interactables(parent: Node3D) -> void:
	var rs := RoadSign.new()
	rs.name = "CampSign"
	rs.text = SIGN_TEXT
	rs.position = at3(SIGN[0], SIGN[1])
	rs.rotation_degrees.y = YAW_ALONG + 180.0 + 20.0                 # 字朝西南（从庄园来的路上读得到）
	parent.add_child(rs)


## part：""（全部，碰撞用）、"items_w" / "items_e"（路西北边 / 东南边的零碎，分开合网格：火在西北边）、"wood"（劈好的柴）
## 营地里的零碎：兵器架旁的盾、木桶（水和麦酒）、箱子、两只瘪麻袋、劈好的柴
static func props_decor(rect := Rect2(), part := "") -> Decor:
	var d := Decor.new()
	var inside := func(p: Vector2) -> bool: return rect.size == Vector2.ZERO or rect.has_point(p)
	var items := [
		["barrel", -3.0, -10.2], ["barrel", -2.4, -10.8], ["barrel", 6.6, -9.0],
		["crate", 6.8, -7.8, 0.4], ["crate", -10.4, -7.0, 1.2], ["crate", 9.0, 4.6, 0.3],
		["sack", 5.6, -7.2, 0.5], ["sack", -11.0, 5.0, 1.8],
		["hay", 15.6, 11.2, 0.6], ["hay", 11.0, 11.4, 2.0],
	]
	if part in ["", "items_w", "items_e"]:
		for it: Array in items:
			var p := at(float(it[1]), float(it[2]))
			if not inside.call(p) or (part == "items_w" and float(it[2]) > 0.0) or (part == "items_e" and float(it[2]) < 0.0):
				continue
			var pos := Vector3(p.x, ground(p), p.y)
			match str(it[0]):
				"barrel":
					d.barrel(pos)
				"crate":
					d.crate(pos, float(it[3]))
				"sack":
					d.sack(pos, float(it[3]))
				"hay":
					d.hay(pos, float(it[3]))
		var rp := at3(RACK[0], RACK[1])
		if inside.call(Vector2(rp.x, rp.z)) and part != "items_e":
			var n := Vector3(SIDE.x, 0, SIDE.y)
			d.rack(rp, n, 1.5)
			for k in 2:
				d.shield(rp + n * 0.25 + Vector3(ALONG.x, 0, ALONG.y) * (1.2 + k * 0.7) + Vector3(0, 0.45, 0), n, 0.38, FIELD, CHARGE)
	if part in ["", "wood"]:
		var wp := at3(-9.0, -5.6)
		if inside.call(Vector2(wp.x, wp.z)):
			d.woodpile(wp, Vector3(ALONG.x, 0, ALONG.y), 2.0, 0.8)
	return d



# ---------------- 画面 ----------------

static func jobs_for(rect: Rect2, reduced_motion: bool) -> Array:
	var out := []
	if rect.has_point(PlainLayout.CAMP):
		out.append(func(root: Node3D): pavilion(root, reduced_motion))
		out.append(func(root: Node3D): tents(root))
		out.append(func(root: Node3D): forge(root, reduced_motion))
		out.append(func(root: Node3D): campfire(root, reduced_motion))
		out.append(func(root: Node3D): wagons(root))
		out.append(func(root: Node3D): horses(root))
		out.append(func(root: Node3D): stakes(root))
		out.append(func(root: Node3D): banners(root, reduced_motion))
		for part in ["items_w", "items_e", "wood"]:
			out.append(func(root: Node3D): _props(root, part))
	return out


static func _props(root: Node3D, part: String) -> void:
	var d := props_decor(Rect2(), part)
	var mi := _build(d.kit, d.mats)
	mi.name = {"items_w": "CampProps", "items_e": "CampPropsEast"}.get(part, "CampWood")
	root.add_child(mi)


static func _add(root: Node3D, kit: MeshKit, node_name: String, m: Dictionary = {}) -> MeshInstance3D:
	var mi := _build(kit, mats() if m.is_empty() else m)
	mi.name = node_name
	root.add_child(mi)
	return mi


## 合成网格：带贴图的材质（帆布、木头、雪、石头、土坯）一种一个表面；纯色的（绳子、干草、皮子、马、铁……）压成一个表面、颜色写进顶点色
## （6.3c 实测：营地东北头那个机位 574 次绘制——每样东西十几种纯色材质，再乘上火光照到的那几遍；预算 400）。自发光、不受光、双面的不压。
static func _build(kit: MeshKit, m: Dictionary) -> MeshInstance3D:
	var keep := {}
	var flat := {}
	for k in m:
		var mat: Material = m[k]
		var bm := mat as BaseMaterial3D
		if bm != null and bm.albedo_texture == null and bm.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED and not bm.emission_enabled and bm.cull_mode == BaseMaterial3D.CULL_BACK:
			flat[k] = mat
		else:
			keep[k] = mat
	var mi := kit.build(keep)
	var fm := kit.build(flat)
	if fm.mesh.get_surface_count() > 0:
		var one := MeshKit.flatten([fm], fm)
		var mesh := mi.mesh as ArrayMesh
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, one.surface_get_arrays(0))
		if not _mats.has("flat"):
			_mats["flat"] = MeshKit.flat_mat(0.9)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _mats["flat"])
	fm.free()
	return mi


## 指挥帐：八面帆布墙（1.7 米）、红白相间的圆锥顶（3.9 米）、檐口一圈红布垂边、顶上一颗铜球和一面小三角旗；
## 朝路那面是门（两片门帘往两边系起来）；拉绳和木桩；里头一根中柱挂着油灯、地上铺干草、桌上摊着地图和酒壶杯子、行军床、箱子
static func pavilion(root: Node3D, reduced_motion := false) -> void:
	var kit := MeshKit.new()
	var c := at3(PAVILION[0], PAVILION[1])
	var r: float = PAVILION[2]
	var door := _pav_door()
	var apex := c + Vector3(0, PAV_PEAK, 0)
	for k in 8:
		var a0 := TAU * k / 8.0
		var a1 := TAU * (k + 1) / 8.0
		var e0 := c + Vector3(cos(a0) * r, 0, sin(a0) * r)
		var e1 := c + Vector3(cos(a1) * r, 0, sin(a1) * r)
		var out := Vector3(cos((a0 + a1) * 0.5), 0, sin((a0 + a1) * 0.5))
		var top0 := e0 + Vector3(0, PAV_WALL, 0)
		var top1 := e1 + Vector3(0, PAV_WALL, 0)
		if k != door:
			kit.quad("canvas", [e0 + Vector3(0, -0.05, 0), e1 + Vector3(0, -0.05, 0), top1, top0], out, [0.62, 0.62, 0.95, 0.95])
		else:                                                        # 门：两片门帘系到两边
			for s in [0.0, 1.0]:
				var hinge: Vector3 = e0 if s == 0.0 else e1
				var mid := e0.lerp(e1, 0.5 + (-0.32 if s == 0.0 else 0.32))
				kit.tri("canvas", hinge + Vector3(0, PAV_WALL, 0), hinge + Vector3(0, -0.02, 0), mid + Vector3(0, PAV_WALL, 0), out, 0.85)
				kit.cylinder("rope", hinge.lerp(mid, 0.55) + Vector3(0, 1.0, 0) + out * 0.02, hinge + Vector3(0, 1.0, 0) + out * 0.02, 0.015, 0.015, 4)
		var nrm := (out * (PAV_PEAK - PAV_WALL) + Vector3(0, r, 0)).normalized()
		kit.tri("red" if k % 2 == 0 else "canvas", top0, top1, apex, nrm, 1.0)
		kit.quad("red", [top0 + out * 0.03, top1 + out * 0.03, top1 + out * 0.03 + Vector3(0, -0.32, 0), top0 + out * 0.03 + Vector3(0, -0.32, 0)], out, [1.0, 1.0, 0.8, 0.8])   # 檐口垂边
		for t in [0.25, 0.75]:                                       # 垂边下摆的齿
			var q := top0.lerp(top1, t) + out * 0.03 + Vector3(0, -0.32, 0)
			var w := top0.distance_to(top1) * 0.25
			var dir := (top1 - top0).normalized()
			kit.tri("red", q - dir * w, q + dir * w, q + Vector3(0, -0.16, 0), out, 0.8)
		var peg := c + Vector3(cos(a0), 0, sin(a0)) * (r + 1.5)          # 拉绳从檐角拉到地上的木桩
		var peg_y := ground(Vector2(peg.x, peg.z))
		peg.y = peg_y
		kit.cylinder("rope", top0 + Vector3(0, -0.05, 0), peg + Vector3(0, 0.25, 0), 0.012, 0.012, 3)
		kit.cylinder("timber", peg + Vector3(0, -0.1, 0), peg + Vector3(0, 0.3, 0), 0.04, 0.03, 4)
		kit.box("snow", peg + Vector3(0, 0.02, 0), Vector3(0.35, 0.04, 0.3), Basis(Vector3.UP, a0), 1.0, 1.0)
	kit.cylinder("timber", c, apex + Vector3(0, 0.25, 0), 0.07, 0.06, 6)                # 中柱
	kit.cylinder("gold", apex + Vector3(0, 0.25, 0), apex + Vector3(0, 0.45, 0), 0.08, 0.08, 6)
	kit.cylinder("timber", apex + Vector3(0, 0.45, 0), apex + Vector3(0, 1.1, 0), 0.02, 0.02, 4)
	kit.tri("red", apex + Vector3(0, 1.1, 0), apex + Vector3(0, 0.82, 0), apex + Vector3(0.55, 0.98, 0.1), Vector3(0, 0, 1), 1.0)    # 小三角旗
	for k in 8:                                                                                 # 地上铺的干草（八边形，贴着帐墙里头）
		var a0 := TAU * k / 8.0
		var a1 := TAU * (k + 1) / 8.0
		kit.tri("straw", c + Vector3(0, 0.03, 0), c + Vector3(cos(a0) * (r - 0.08), 0.03, sin(a0) * (r - 0.08)), c + Vector3(cos(a1) * (r - 0.08), 0.03, sin(a1) * (r - 0.08)), Vector3.UP, 0.75)
	var rb := road_basis()
	var fur := _pav_furniture()
	var tb := rb
	var tp: Vector3 = c + (fur[0][0] as Vector3)
	kit.box("timber", tp + Vector3(0, 0.36, 0), Vector3(1.5, 0.06, 0.85), tb, 0.95, 0.8)                                       # 桌面
	for sx in [-0.65, 0.65]:
		for sz in [-0.32, 0.32]:
			kit.box("timber", tp + tb * Vector3(sx, 0.0, sz) + Vector3(0, 0.0, 0), Vector3(0.07, 0.72, 0.07), tb, 0.8, 0.6)
	kit.box("map", tp + Vector3(0, 0.40, 0), Vector3(0.9, 0.01, 0.6), tb * Basis(Vector3.UP, 0.12), 1.0, 1.0)                  # 地图
	kit.cylinder("leather", tp + tb * Vector3(0.5, 0.39, -0.2), tp + tb * Vector3(0.5, 0.62, -0.2), 0.09, 0.07, 8)            # 酒壶
	for k in 2:
		kit.cylinder("iron", tp + tb * Vector3(0.25 - k * 0.2, 0.39, 0.25), tp + tb * Vector3(0.25 - k * 0.2, 0.5, 0.25), 0.04, 0.045, 7)   # 两只杯子
	for s in [-1.0, 1.0]:                                                                                                    # 两张折凳
		var sp: Vector3 = tp + Vector3(ALONG.x, 0, ALONG.y) * s * 0.8                                                  # 桌子两头各一张（奥迪隆站在桌子朝门那边）
		kit.box("leather", sp + Vector3(0, 0.45, 0), Vector3(0.42, 0.04, 0.36), tb, 0.9, 0.8)
		kit.cylinder("timber", sp + tb * Vector3(-0.18, 0, -0.15), sp + tb * Vector3(0.18, 0.44, 0.15), 0.02, 0.02, 4)
		kit.cylinder("timber", sp + tb * Vector3(0.18, 0, -0.15), sp + tb * Vector3(-0.18, 0.44, 0.15), 0.02, 0.02, 4)
	var bp: Vector3 = c + (fur[1][0] as Vector3)
	kit.box("timber", bp + Vector3(0, 0.0, 0), Vector3(1.9, 0.3, 0.75), tb, 0.8, 0.6)                                         # 行军床
	kit.box("red", bp + Vector3(0, 0.19, 0), Vector3(1.8, 0.1, 0.7), tb, 1.0, 0.8)
	kit.box("hide", bp + tb * Vector3(0.6, 0.25, 0.05), Vector3(0.6, 0.06, 0.65), tb, 1.0, 0.8)
	var cp: Vector3 = c + (fur[2][0] as Vector3)
	kit.box("timber", cp + Vector3(0, 0.0, 0), Vector3(0.9, 0.6, 0.55), tb, 0.9, 0.6)                                        # 箱子
	kit.box("iron", cp + Vector3(0, 0.0, 0), Vector3(0.92, 0.08, 0.57), tb)
	kit.box("iron", cp + Vector3(0, 0.25, 0), Vector3(0.92, 0.06, 0.57), tb)
	var lamp := c + Vector3(0, 2.9, 0) + (Vector3(SIDE.x, 0, SIDE.y) * 0.09)                                               # 中柱上挂的油灯
	kit.cylinder("iron", lamp + Vector3(0, 0.25, 0), lamp + Vector3(0, 0.05, 0), 0.01, 0.01, 3)
	kit.box("iron", lamp, Vector3(0.16, 0.2, 0.16), Basis.IDENTITY, 0.9, 0.9)
	kit.box("flame", lamp, Vector3(0.1, 0.13, 0.1))
	var m := mats().duplicate()
	m["map"] = _flat(Color("c8b48a"), 0.95)
	m["hide"] = Marsh._hide_mat()
	m["flame"] = Inn._unshaded(Color("ffc070"))
	_add(root, kit, "CampPavilion", m)
	var l := Tavern.FireLight.new()
	l.name = "PavilionLamp"
	l.light_color = Color("ffb060")
	l.base = 1.1
	l.omni_range = 5.5
	l.flicker = not reduced_motion
	l.position = lamp + Vector3(0, -0.1, 0)
	l.add_to_group("light_source")
	l.set_meta("radius", 2.5)
	root.add_child(l)


## 人字帐篷：两片斜面搭在横杆上、两边一截矮墙、后头封死、门那头两片门帘半掀着（里头黑、地上铺着干草）；
## 前后两根立杆、拉绳和木桩；斜面脚下一道积雪
static func tents(root: Node3D) -> void:
	for side in [-1, 1]:
		_tents_side(root, side)


## 路一边的帐篷合成一个网格（两边分开：东南那排离火远，火光不用多画它一遍）
static func _tents_side(root: Node3D, side: int) -> void:
	var kit := MeshKit.new()
	var hw := TENT_W * 0.5
	var hl := TENT_L * 0.5
	var eave := 0.35
	for t: Array in TENTS:
		if signi(int(signf(float(t[1])))) != side:
			continue
		var b := _tent_basis(t)
		var o := at3(t[0], t[1], -0.03)
		var P := func(x: float, y: float, z: float) -> Vector3: return o + b * Vector3(x, y, z)
		for s in [-1.0, 1.0]:
			var n := (b * Vector3(s * TENT_H, hw, 0)).normalized()
			kit.quad("canvas", [P.call(0, TENT_H, -hl), P.call(0, TENT_H, hl), P.call(s * hw, eave, hl), P.call(s * hw, eave, -hl)], n, [1.0, 1.0, 0.78, 0.78])
			kit.quad("canvas", [P.call(s * hw, eave, -hl), P.call(s * hw, eave, hl), P.call(s * hw, -0.05, hl), P.call(s * hw, -0.05, -hl)], b * Vector3(s, 0, 0), [0.75, 0.75, 0.6, 0.6])
			kit.box("snow", P.call(s * (hw + 0.18), 0.06, 0), Vector3(0.4, 0.14, TENT_L + 0.2), b, 1.0, 0.95)
			for z in [-hl * 0.6, hl * 0.6]:                                                           # 檐边两根拉绳往外拉
				var peg: Vector3 = P.call(s * (hw + 1.0), 0, z)
				peg.y = ground(Vector2(peg.x, peg.z))
				kit.cylinder("rope", P.call(s * hw, eave + 0.05, z), peg + Vector3(0, 0.2, 0), 0.01, 0.01, 3)
				kit.cylinder("timber", peg + Vector3(0, -0.1, 0), peg + Vector3(0, 0.25, 0), 0.03, 0.025, 4)
		var back_n := b * Vector3(0, 0, -1)
		kit.tri("canvas", P.call(-hw, eave, -hl), P.call(hw, eave, -hl), P.call(0, TENT_H, -hl), back_n, 0.85)
		kit.quad("canvas", [P.call(-hw, -0.05, -hl), P.call(hw, -0.05, -hl), P.call(hw, eave, -hl), P.call(-hw, eave, -hl)], back_n, [0.65, 0.65, 0.8, 0.8])
		var front_n := b * Vector3(0, 0, 1)
		kit.tri("dark", P.call(-hw * 0.8, 0.0, hl - 0.25), P.call(hw * 0.8, 0.0, hl - 0.25), P.call(0, TENT_H - 0.1, hl - 0.25), front_n)      # 门里头
		for s in [-1.0, 1.0]:                                                                         # 两片门帘掀到两边
			kit.tri("canvas", P.call(0, TENT_H, hl), P.call(s * hw, eave, hl), P.call(s * hw * 0.55, 0.9, hl + 0.06), front_n, 0.9)
			kit.quad("canvas", [P.call(s * hw, -0.05, hl), P.call(s * hw, eave, hl), P.call(s * hw * 0.55, 0.9, hl + 0.06), P.call(s * hw * 0.82, -0.05, hl + 0.04)], front_n, [0.7, 0.8, 0.9, 0.7])
		kit.box("straw", P.call(0, 0.02, 0), Vector3(TENT_W - 0.3, 0.03, TENT_L - 0.2), b, 0.7, 0.7)
		kit.cylinder("timber", P.call(0, TENT_H + 0.04, -hl - 0.2), P.call(0, TENT_H + 0.04, hl + 0.2), 0.035, 0.035, 5)
		for z in [-hl - 0.02, hl + 0.02]:
			kit.cylinder("timber", P.call(0, -0.1, z), P.call(0, TENT_H + 0.15, z), 0.04, 0.035, 5)
			var zz: float = z + signf(z) * 1.2
			var peg: Vector3 = P.call(0, 0, zz)
			peg.y = ground(Vector2(peg.x, peg.z))
			kit.cylinder("rope", P.call(0, TENT_H + 0.1, z), peg + Vector3(0, 0.2, 0), 0.01, 0.01, 3)
			kit.cylinder("timber", peg + Vector3(0, -0.1, 0), peg + Vector3(0, 0.25, 0), 0.03, 0.025, 4)
	_add(root, kit, "CampTents" if side > 0 else "CampTentsWest")


## 熔炉车：四轮大车，车斗上一个泥砌的炉膛（炭火通红）、铁皮烟囱冒烟、一侧挂着皮风箱；车尾一截挂着火钳和锤子；
## 车旁一个树墩上的铁砧、淬火的水桶、一捆铁条、两袋炭
static func forge(root: Node3D, reduced_motion := false) -> void:
	var kit := MeshKit.new()
	var b := road_basis()
	var o := at3(FORGE[0], FORGE[1])
	var P := func(x: float, y: float, z: float) -> Vector3: return o + b * Vector3(x, y, z)
	_wagon_body(kit, P, b, 1.6, 3.4, 0.22)
	kit.box("stone", P.call(0, 1.13, 0.3), Vector3(1.35, 0.06, 1.5), b, 0.9, 0.8)
	kit.box("clay", P.call(0, 1.48, 0.3), Vector3(1.25, 0.64, 1.4), b, 1.0, 0.65)                   # 炉膛（泥砌在一块石板上）
	kit.box("clay", P.call(0, 1.86, -0.3), Vector3(1.25, 0.14, 0.2), b, 1.0, 0.9)                  # 炉膛后沿
	kit.box("ember", P.call(0, 1.81, 0.35), Vector3(0.85, 0.04, 0.95))
	kit.box("dark", P.call(0, 1.55, 1.01), Vector3(0.55, 0.32, 0.02), b)                                # 炉口
	kit.box("ember", P.call(0, 1.48, 1.02), Vector3(0.4, 0.08, 0.01), b)
	kit.cylinder("iron", P.call(0, 1.75, -0.2), P.call(0, 3.3, -0.25), 0.13, 0.11, 8)                    # 铁皮烟囱
	kit.cylinder("iron", P.call(0, 3.3, -0.25), P.call(0, 3.38, -0.25), 0.18, 0.18, 8)
	var bel: Vector3 = P.call(-0.95, 1.4, 0.2)                                                                  # 皮风箱（楔形，挂在车斗外侧）
	kit.box("leather", bel, Vector3(0.22, 0.5, 0.9), b * Basis(Vector3.FORWARD, -0.12), 0.9, 0.7)
	kit.box("timber", bel + b * Vector3(0, 0.26, 0), Vector3(0.24, 0.04, 0.95), b, 0.9, 0.7)
	kit.cylinder("timber", bel + b * Vector3(0, 0.2, -0.45), bel + b * Vector3(0, 0.45, -0.9), 0.025, 0.025, 4)
	for k in 3:                                                                                         # 车尾挂的火钳、锤子
		var hp: Vector3 = P.call(-0.3 + k * 0.3, 1.3, -1.72)
		kit.cylinder("iron", hp, hp + Vector3(0, -0.55, 0), 0.015, 0.015, 4)
		kit.box("iron", hp + Vector3(0, -0.58, 0), Vector3(0.1, 0.06, 0.05), b)
	var an: Vector3 = P.call(-0.4 + 0.0, 0, 0) + Vector3(SIDE.x, 0, SIDE.y) * 2.0 - Vector3(ALONG.x, 0, ALONG.y) * 0.4
	an.y = ground(Vector2(an.x, an.z))
	kit.cylinder("bark", an, an + Vector3(0, 0.55, 0), 0.3, 0.27, 8)                                     # 树墩
	kit.box("snow", an + Vector3(0, 0.56, 0), Vector3(0.1, 0.01, 0.1))
	kit.box("iron", an + Vector3(0, 0.62, 0), Vector3(0.22, 0.14, 0.18), b)                              # 铁砧：腰、面、角
	kit.box("iron", an + Vector3(0, 0.74, 0), Vector3(0.24, 0.1, 0.55), b)
	kit.box("iron", an + b * Vector3(0, 0.75, -0.36), Vector3(0.12, 0.07, 0.2), b * Basis(Vector3.RIGHT, -0.15))
	kit.box("iron", an + b * Vector3(0.0, 0.83, 0.1), Vector3(0.04, 0.03, 0.3), b)                       # 砧上一根打了一半的枪头
	var qb: Vector3 = an + b * Vector3(0.7, 0, 0.6)
	kit.cylinder("timber", qb, qb + Vector3(0, 0.62, 0), 0.3, 0.32, 10)                                  # 淬火的桶
	kit.box("dark", qb + Vector3(0, 0.6, 0), Vector3(0.46, 0.01, 0.46))
	var bars: Vector3 = an + b * Vector3(-0.8, 0.08, 0.3)
	for k in 6:
		kit.box("iron", bars + Vector3(0, (k / 3) * 0.05, 0) + b * Vector3((k % 3) * 0.06, 0, 0), Vector3(0.04, 0.04, 1.1), b)
	var dec := Decor.new()
	_add(root, kit, "CampForge")
	dec.sack(an + b * Vector3(-0.6, 0, -0.9), 0.4)
	dec.sack(an + b * Vector3(-1.1, 0, -0.6), 1.7)
	var sm := _build(dec.kit, dec.mats)
	sm.name = "ForgeSacks"
	root.add_child(sm)
	Atmos.smoke(root, P.call(0, 3.5, -0.25))
	var fire := Tavern.FireLight.new()
	fire.name = "ForgeFire"
	fire.add_to_group("night_light")                # 实时光只在黄昏和夜里亮（同庄园门口的火盆）：白天炭火靠自发光和光晕（6.3c：每盏火光让照到的东西多画一遍）
	fire.light_color = Color("ff7a32")
	fire.base = 2.2
	fire.omni_range = 6.0
	fire.flicker = not reduced_motion
	fire.position = P.call(0, 2.2, 1.0)
	fire.add_to_group("light_source")
	fire.set_meta("radius", 4.0)
	root.add_child(fire)
	_halo(root, P.call(0, 1.85, 0.6), Vector2(1.3, 0.8), Color("ff7a32"))


static func _halo(root: Node3D, pos: Vector3, size: Vector2, c: Color) -> void:
	var halo := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	var hm := Look.halo(c, 0.5).duplicate() as StandardMaterial3D
	hm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	q.material = hm
	halo.mesh = q
	halo.position = pos
	root.add_child(halo)


## 大车的车身：车斗（底板、两边和前后挡板）、四个带辐条的轮子、车辕（往东北）；P 是本地 → 世界的换算
static func _wagon_body(kit: MeshKit, P: Callable, b: Basis, w: float, l: float, side_h := 0.5) -> void:
	var bed := 1.0
	kit.box("timber", P.call(0, bed, 0), Vector3(w, 0.08, l), b, 0.9, 0.6)
	for s in [-1.0, 1.0]:
		kit.box("timber", P.call(s * w * 0.5, bed + side_h * 0.5 + 0.03, 0), Vector3(0.06, side_h, l), b, 0.95, 0.7)
		kit.box("timber", P.call(0, bed + side_h * 0.5 + 0.03, s * l * 0.5), Vector3(w, side_h, 0.06), b, 0.95, 0.7)
		kit.box("timber", P.call(s * w * 0.35, bed - 0.12, 0), Vector3(0.12, 0.14, l + 0.1), b, 0.7, 0.5)
	for sz in [-1.0, 1.0]:                                                                  # 车轴
		kit.cylinder("timber", P.call(-w * 0.5 - 0.2, 0.55, sz * l * 0.32), P.call(w * 0.5 + 0.2, 0.55, sz * l * 0.32), 0.06, 0.06, 6, 0.6)
		kit.box("timber", P.call(0, 0.78, sz * l * 0.32), Vector3(w * 0.8, 0.36, 0.14), b, 0.7, 0.5)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var hub: Vector3 = P.call(sx * (w * 0.5 + 0.12), 0.55, sz * l * 0.32)
			var u: Vector3 = b.y
			var v: Vector3 = b.z
			for k in 16:                                                                        # 轮圈：一圈短木段
				var a0 := TAU * k / 16.0
				var a1 := TAU * (k + 1) / 16.0
				kit.cylinder("timber", hub + (u * cos(a0) + v * sin(a0)) * 0.52, hub + (u * cos(a1) + v * sin(a1)) * 0.52, 0.045, 0.045, 5, 0.85)
			for k in 8:                                                                         # 辐条
				var a := TAU * (k + 0.5) / 8.0
				kit.cylinder("timber", hub, hub + (u * cos(a) + v * sin(a)) * 0.5, 0.022, 0.018, 4, 0.8)
			kit.cylinder("timber", hub - b.x * sx * 0.1, hub + b.x * sx * 0.1, 0.09, 0.08, 7, 0.7)
	for s in [-1.0, 1.0]:                                                                    # 车辕：往前（东北）放在雪里
		kit.cylinder("timber", P.call(s * 0.35, bed - 0.1, -l * 0.5), P.call(s * 0.3, 0.12, -l * 0.5 - 2.2), 0.05, 0.045, 5)
	kit.box("snow", P.call(0, bed + 0.06, 0), Vector3(w - 0.12, 0.03, l - 0.12), b, 1.0, 1.0)


## 四辆空粮车：排在路东南边，车头朝砧山；车斗里只有一层薄雪和一两条叠起来的空麻袋
static func wagons(root: Node3D) -> void:
	var kit := MeshKit.new()
	var b := road_basis()
	for i in WAGONS.size():
		var w: Array = WAGONS[i]
		var o := at3(w[0], w[1])
		var tb := b * Basis(Vector3.UP, 0.05 * (i % 3 - 1))
		var P := func(x: float, y: float, z: float) -> Vector3: return o + tb * Vector3(x, y, z)
		_wagon_body(kit, P, tb, 1.6, 3.4)
		if i % 2 == 0:
			kit.box("straw", P.call(0.2, 1.13, 0.6), Vector3(0.7, 0.05, 0.5), tb * Basis(Vector3.UP, 0.3), 0.9, 0.9)    # 一条叠起来的空麻袋
	_add(root, kit, "CampWagons")


## 营火：石头围一圈、木柴、炭火；三脚架吊着一口锅（汤稀得见底）；火边两根圆木当凳子
static func campfire(root: Node3D, reduced_motion := false) -> void:
	var kit := MeshKit.new()
	var f := at3(FIRE[0], FIRE[1])
	for k in 10:
		var a := TAU * k / 10.0
		kit.box("stone", f + Vector3(cos(a) * 0.68, 0.1, sin(a) * 0.68), Vector3(0.3, 0.22, 0.26), Basis(Vector3.UP, -a), 0.8, 0.5)
	for k in 5:
		var a := TAU * k / 5.0 + 0.3
		kit.cylinder("timber", f + Vector3(cos(a) * 0.5, 0.05, sin(a) * 0.5), f + Vector3(cos(a) * 0.06, 0.42, sin(a) * 0.06), 0.06, 0.05, 5, 0.45)
	kit.box("ember", f + Vector3(0, 0.08, 0), Vector3(0.65, 0.08, 0.65))
	for k in 3:                                                                           # 三脚架
		var a := TAU * k / 3.0
		kit.cylinder("iron", f + Vector3(cos(a) * 0.95, 0, sin(a) * 0.95), f + Vector3(0, 1.55, 0), 0.025, 0.02, 4)
	kit.cylinder("iron", f + Vector3(0, 1.55, 0), f + Vector3(0, 0.95, 0), 0.01, 0.01, 3)
	kit.cylinder("iron", f + Vector3(0, 0.55, 0), f + Vector3(0, 0.95, 0), 0.24, 0.3, 10)    # 锅
	kit.box("soup", f + Vector3(0, 0.62, 0), Vector3(0.34, 0.01, 0.34))
	var lb := road_basis()
	for s in [-1.0, 1.0]:
		var lp := f + lb * Vector3(s * 1.7, 0.22, 0.3 * s)
		lp.y = ground(Vector2(lp.x, lp.z)) + 0.22
		kit.cylinder("bark", lp - lb.z * 1.0, lp + lb.z * 1.0, 0.23, 0.21, 7, 0.8)
	var m := mats().duplicate()
	m["bark"] = Look.mat("bark")
	m["soup"] = _flat(Color("7a6a4a"), 0.3)
	_add(root, kit, "CampFire", m)
	Atmos.smoke(root, f + Vector3(0, 1.0, 0))
	var fire := Tavern.FireLight.new()
	fire.name = "CampFireLight"
	fire.add_to_group("night_light")
	fire.light_color = Color("ff8a3a")
	fire.base = 2.0
	fire.omni_range = 6.5
	fire.flicker = not reduced_motion
	fire.position = f + Vector3(0, 0.8, 0)
	fire.add_to_group("light_source")
	fire.set_meta("radius", 4.5)
	root.add_child(fire)
	_halo(root, f + Vector3(0, 0.45, 0), Vector2(1.6, 1.1), Color("ff8a3a"))


## 拴马桩：两根桩一根横木；四匹马披着红马衣、头朝横木拴着（两匹低头吃草垛上的干草）；横木上搭着两副马鞍
static func horses(root: Node3D) -> void:
	var kit := MeshKit.new()
	var b := road_basis()
	var o := at3(HITCH[0], HITCH[1])
	for z in [-2.2, 2.2]:
		kit.cylinder("timber", o + b * Vector3(0, -0.2, z), o + b * Vector3(0, 1.25, z), 0.09, 0.08, 6)
	kit.cylinder("timber", o + b * Vector3(0, 1.05, -2.35), o + b * Vector3(0, 1.05, 2.35), 0.06, 0.06, 6)
	for k in 2:
		var sp := o + b * Vector3(0, 1.1, -1.2 + k * 2.6)
		kit.box("leather", sp, Vector3(0.6, 0.2, 0.5), b, 0.9, 0.6)
		kit.box("red", sp + b * Vector3(0, -0.2, 0), Vector3(0.75, 0.4, 0.04), b * Basis(Vector3.UP, PI * 0.5), 1.0, 0.8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 6303
	for k in HORSES:
		var z := -1.9 + k * 1.25
		var hp := o + b * Vector3(1.45, 0, z)
		hp.y = ground(Vector2(hp.x, hp.z))
		var hb := b * Basis(Vector3.UP, -PI * 0.5 + rng.randf_range(-0.12, 0.12))      # 马头（本地 -Z）朝横木
		_horse(kit, hp, hb, "horse" if k % 2 == 0 else "horse2", k % 2 == 1)
	_add(root, kit, "CampHorses")


## 一匹马：HorseKit（2026-11-07 换成更像马的搭法），披红马衣；脚下一小块踩实的雪
static func _horse(kit: MeshKit, o: Vector3, b: Basis, coat: String, grazing: bool) -> void:
	HorseKit.build(kit, o, b, coat, grazing, true)
	kit.box("snow", o + b * Vector3(0, 0.02, 0), Vector3(0.8, 0.02, 0.4))


## 朝庄园那边两排削尖的木桩（斜着指向西南），路当中留出车道
static func stakes(root: Node3D) -> void:
	var kit := MeshKit.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 6304
	var toward := Vector3(-ALONG.x, 0, -ALONG.y)
	for s in [-1.0, 1.0]:
		var v := 4.0
		while v <= 14.0:
			var p := at(STAKES_U + rng.randf_range(-0.2, 0.2), s * v)
			var g := ground(p)
			var base := Vector3(p.x, g - 0.2, p.y)
			var tip := base + toward * rng.randf_range(0.8, 1.0) + Vector3(0, rng.randf_range(1.2, 1.5), 0) + Vector3(SIDE.x, 0, SIDE.y) * rng.randf_range(-0.15, 0.15)
			kit.cylinder("timber", base, base.lerp(tip, 0.82), 0.07, 0.065, 5, 0.85)
			kit.cylinder("bare", base.lerp(tip, 0.82), tip, 0.065, 0.005, 5)
			kit.box("snow", Vector3(p.x, g + 0.03, p.y), Vector3(0.4, 0.06, 0.35), Basis(Vector3.UP, rng.randf() * TAU), 1.0, 1.0)
			v += 0.62
	var bk := Vector3(ALONG.x, 0, ALONG.y) * 0.6                                                 # 木桩后头一根横木把它们串起来
	for s in [-1.0, 1.0]:
		var a := at3(STAKES_U, s * 4.0, 0.35) + bk
		var e := at3(STAKES_U, s * 14.0, 0.35) + bk
		kit.cylinder("timber", a, e, 0.08, 0.08, 6, 0.8)
	var m := mats().duplicate()
	m["bare"] = _flat(Color("b89a72"), 0.9)
	_add(root, kit, "CampStakes", m)


## 两面红底铁砧托冠的旗：挂在高杆上的横杆下（旗面朝西南，从庄园来的路上看得见）
static func banners(root: Node3D, _reduced_motion := false) -> void:
	var kit := MeshKit.new()
	var d := Decor.new()
	var face := Vector3(-ALONG.x, 0, -ALONG.y)
	for k in BANNERS.size():
		var bn: Array = BANNERS[k]
		var p := at3(bn[0], bn[1])
		var h := 6.2 if k == 0 else 5.4
		kit.cylinder("timber", p + Vector3(0, -0.3, 0), p + Vector3(0, h, 0), 0.08, 0.06, 6)
		kit.cylinder("gold", p + Vector3(0, h, 0), p + Vector3(0, h + 0.14, 0), 0.07, 0.03, 6)
		d.banner(p + Vector3(0, h - 0.35, 0) + face * 0.1, face, 1.3, 2.6, FIELD, CHARGE, "anvil", CROWN)
		for a in [0.0, TAU / 3.0, TAU * 2.0 / 3.0]:
			var foot := p + Vector3(cos(a) * 0.7, 0, sin(a) * 0.7)
			foot.y = ground(Vector2(foot.x, foot.z))
			kit.cylinder("timber", foot + Vector3(0, -0.1, 0), p + Vector3(0, 1.2, 0), 0.04, 0.035, 4)
	_add(root, kit, "CampBannerPoles")
	var bm := _build(d.kit, d.mats)
	bm.name = "CampBanners"
	root.add_child(bm)


static func map_shapes() -> Array:
	var out := []
	var c := at(PAVILION[0], PAVILION[1])
	var ring := PackedVector2Array()
	for k in 8:
		ring.append(c + Vector2.from_angle(TAU * k / 8.0) * float(PAVILION[2]))
	out.append({"k": "house", "pts": ring, "label": "指挥帐"})
	for t: Array in TENTS:
		var b := _tent_basis(t)
		var o := at3(t[0], t[1])
		var pts := PackedVector2Array()
		for q in [Vector3(-TENT_W * 0.5, 0, -TENT_L * 0.5), Vector3(TENT_W * 0.5, 0, -TENT_L * 0.5), Vector3(TENT_W * 0.5, 0, TENT_L * 0.5), Vector3(-TENT_W * 0.5, 0, TENT_L * 0.5)]:
			var w: Vector3 = o + b * q
			pts.append(Vector2(w.x, w.z))
		out.append({"k": "house", "pts": pts})
	var f := at(FORGE[0], FORGE[1])
	out.append({"k": "mark", "at": f, "label": "熔炉车"})
	return out
