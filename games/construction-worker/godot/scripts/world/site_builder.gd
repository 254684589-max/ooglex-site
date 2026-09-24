class_name SiteBuilder
extends Node3D
## 灰盒工地地图生成器。全部用方块 / 圆柱拼成，没有外部美术素材也能完整游玩。
##
## 坐标约定：X 向东，Z 向南（-Z 为北），单位米，地面 y = 0。
## 地图布局（俯视）：
##
##            北  ← 施工楼（1#楼）+ 塔吊 + 钢筋堆场 / 搅拌站 →
##   钢筋堆场     施工楼             塔吊
##                 │ 砖块堆放区   │水泥库 搅拌站
##   宿舍  项目部 ─┼─ 东西主路 ───┼── 小卖部  食堂
##                 │ 大门（南）
##   ──────────── 城市街道 ────────────
##
## build() 生成：静态几何（合批）、碰撞体、标牌文字、可交互物体、NPC 站位、小地图数据。

const FX0 := -64.0
const FX1 := 64.0
const FZ0 := -72.0
const FZ1 := 52.0
const GATE_HALF := 7.0
const FLOOR_H := 3.6

const C_FENCE := Color(0.13, 0.36, 0.72)
const C_WHITE := Color(0.92, 0.93, 0.92)
const C_CONCRETE := Color(0.62, 0.62, 0.6)
const C_CONCRETE_DARK := Color(0.47, 0.47, 0.46)
const C_ROAD := Color(0.5, 0.5, 0.49)
const C_ASPHALT := Color(0.2, 0.21, 0.23)
const C_BRICK := Color(0.64, 0.25, 0.17)
const C_BRICK_DARK := Color(0.52, 0.2, 0.14)
const C_WOOD := Color(0.56, 0.41, 0.25)
const C_STEEL := Color(0.36, 0.38, 0.41)
const C_RUST := Color(0.36, 0.26, 0.21)
const C_YELLOW := Color(0.96, 0.75, 0.1)
const C_RED := Color(0.78, 0.14, 0.12)
const C_BLUE_ROOF := Color(0.18, 0.4, 0.7)
const C_GLASS := Color(0.45, 0.62, 0.72, 0.55)
const C_NET := Color(0.12, 0.5, 0.2, 0.72)
const C_CEMENT_BAG := Color(0.8, 0.77, 0.7)
const C_SCAFFOLD := Color(0.72, 0.72, 0.7)

var font: Font
var mb := MeshBatcher.new()
var colliders: StaticBody3D
var labels_root: Node3D
var interact_root: Node3D

## 生成结果，供 main.gd 使用
var info: Dictionary = {}


func build() -> Dictionary:
	font = load("res://assets/fonts/NotoSansSC-CW.ttf")
	colliders = StaticBody3D.new()
	colliders.name = "Colliders"
	colliders.collision_layer = 1
	colliders.collision_mask = 0
	add_child(colliders)
	labels_root = Node3D.new()
	labels_root.name = "Labels"
	add_child(labels_root)
	interact_root = Node3D.new()
	interact_root.name = "Interactables"
	add_child(interact_root)
	GameState.map_features.clear()
	GameState.registry.clear()
	info = {"night_lights": [], "npcs": []}

	_ground()
	_street()
	_city()
	_fence()
	_gate()
	_guard_booth()
	_project_billboard()
	_roads()
	_project_office()
	_dorm()
	_canteen()
	_store()
	_main_building()
	_scaffolding()
	_brick_yard()
	_cement_area()
	_mixer_station()
	_rebar_yard()
	_water_station()
	_props()
	_lamps()
	info["crane_pivot"] = _tower_crane(Vector3(31, 0, -38))
	info["bus"] = _bus(Vector3(-18, 0, 62.8))
	_npc_defs()

	var batches := Node3D.new()
	batches.name = "StaticGeometry"
	add_child(batches)
	mb.build(batches)
	info["spawn"] = Vector3(3.0, 0.1, 55.6)
	info["spawn_yaw"] = 0.0
	info["wake_pos"] = Vector3(-41.0, 0.1, 36.2)
	info["wake_yaw"] = 0.0
	return info


# ================================================================ 工具函数
func solid(center: Vector3, size: Vector3, col: Color, kind := "solid", rot := Basis.IDENTITY) -> void:
	mb.box(kind, center, size, col, rot)
	collider(center, size, rot)


func deco(center: Vector3, size: Vector3, col: Color, kind := "solid", rot := Basis.IDENTITY) -> void:
	mb.box(kind, center, size, col, rot)


## 放在地上的方块：pos 为底面中心
func block(pos: Vector3, size: Vector3, col: Color, collide := true, kind := "solid") -> void:
	var c := pos + Vector3(0, size.y * 0.5, 0)
	if collide:
		solid(c, size, col, kind)
	else:
		deco(c, size, col, kind)


func collider(center: Vector3, size: Vector3, rot := Basis.IDENTITY) -> void:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.transform = Transform3D(rot, center)
	colliders.add_child(cs)


func text3d(text: String, pos: Vector3, yaw: float, size := 96, col := Color.WHITE, outline := Color(0, 0, 0, 0.85), pixel := 0.01) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = font
	l.font_size = size
	l.pixel_size = pixel
	l.modulate = col
	l.outline_modulate = outline
	l.outline_size = maxi(4, int(size / 8.0))
	l.position = pos
	l.rotation.y = yaw
	l.double_sided = false
	l.shaded = false
	labels_root.add_child(l)
	return l


## 横幅：红底黄字
func banner(text: String, pos: Vector3, yaw: float, width: float, height := 0.9) -> void:
	var rot := Basis(Vector3.UP, yaw)
	deco(pos, Vector3(width, height, 0.04), C_RED, "solid", rot)
	var fwd := rot * Vector3(0, 0, 1)
	text3d(text, pos + fwd * 0.04, yaw, 128, Color(1.0, 0.88, 0.3), Color(0.4, 0.05, 0.03, 0.9), height * 0.0055)


func map_rect(feature_name: String, x0: float, z0: float, x1: float, z1: float, col: Color, kind := "building") -> void:
	GameState.add_map_feature(feature_name, Rect2(Vector2(minf(x0, x1), minf(z0, z1)), Vector2(absf(x1 - x0), absf(z1 - z0))), col, kind)


func _add_interactable(node: Interactable, pos: Vector3, reg_id := "") -> Interactable:
	node.position = pos
	interact_root.add_child(node)
	if reg_id != "":
		GameState.register(reg_id, node)
	return node


func tree(pos: Vector3, scale_f := 1.0) -> void:
	mb.cylinder("solid", pos + Vector3(0, 1.2 * scale_f, 0), 0.16 * scale_f, 2.4 * scale_f, Color(0.35, 0.25, 0.17), 6)
	mb.cylinder("solid", pos + Vector3(0, 3.3 * scale_f, 0), 1.5 * scale_f, 2.6 * scale_f, Color(0.2, 0.42, 0.2), 7, Basis.IDENTITY, 0.0)
	mb.cylinder("solid", pos + Vector3(0, 4.5 * scale_f, 0), 1.1 * scale_f, 2.0 * scale_f, Color(0.24, 0.48, 0.23), 7, Basis.IDENTITY, 0.0)


# ================================================================ 地面与道路
func _ground() -> void:
	var outer := MeshInstance3D.new()
	outer.name = "OuterGround"
	var pm := PlaneMesh.new()
	pm.size = Vector2(1400, 1400)
	outer.mesh = pm
	outer.material_override = Mats.ground(Color(0.42, 0.47, 0.33), Color(0.36, 0.38, 0.28), 0.03)
	outer.position = Vector3(0, -0.02, 0)
	outer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(outer)
	var site := MeshInstance3D.new()
	site.name = "SiteGround"
	var sm := PlaneMesh.new()
	sm.size = Vector2(FX1 - FX0, FZ1 - FZ0)
	site.mesh = sm
	site.material_override = Mats.ground(Color(0.58, 0.5, 0.4), Color(0.46, 0.39, 0.31), 0.06)
	site.position = Vector3((FX0 + FX1) * 0.5, 0.0, (FZ0 + FZ1) * 0.5)
	site.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(site)
	# 一个超大的地面碰撞体
	collider(Vector3(0, -1.0, 0), Vector3(1400, 2.0, 1400))


func _roads() -> void:
	# 南北主路（大门 → 施工楼）
	deco(Vector3(0, 0.015, 17), Vector3(8, 0.03, 70), C_ROAD)
	# 东西主路（宿舍、项目部 ↔ 小卖部、食堂）
	deco(Vector3(0, 0.016, 27), Vector3(118, 0.03, 6), C_ROAD)
	# 施工楼南侧的施工便道
	deco(Vector3(0, 0.017, -15), Vector3(84, 0.03, 6), C_ROAD)
	# 路面中线（黄色虚线）
	for i in range(-9, 9):
		deco(Vector3(0, 0.035, 17 + i * 3.8), Vector3(0.14, 0.01, 1.8), C_YELLOW)
	map_rect("", -4, -18, 4, 52, C_ROAD, "road")
	map_rect("", -59, 24, 59, 30, C_ROAD, "road")
	map_rect("", -42, -18, 42, -12, C_ROAD, "road")


func _street() -> void:
	# 工地外的城市道路
	deco(Vector3(0, 0.01, 60), Vector3(900, 0.02, 12), C_ASPHALT)
	deco(Vector3(0, 0.08, 53.2), Vector3(900, 0.16, 2.2), Color(0.66, 0.65, 0.62))
	deco(Vector3(0, 0.08, 67.2), Vector3(900, 0.16, 2.4), Color(0.66, 0.65, 0.62))
	for i in range(-40, 40):
		deco(Vector3(i * 7.0, 0.03, 60), Vector3(3.2, 0.01, 0.15), C_WHITE)
	# 人行横道
	for i in 6:
		deco(Vector3(-2.5 + i * 1.0, 0.03, 60), Vector3(0.5, 0.01, 10), C_WHITE)
	for i in range(-12, 13):
		var x := i * 14.0 + 5.0
		tree(Vector3(x, 0, 69.6), 1.0 + 0.15 * float(absi(i) % 3))
	# 公交站牌
	block(Vector3(-16, 0.16, 53.4), Vector3(0.12, 2.4, 0.12), C_STEEL, false)
	deco(Vector3(-16, 2.4, 53.4), Vector3(1.2, 0.5, 0.06), Color(0.1, 0.45, 0.25))
	text3d("滨江路站", Vector3(-16, 2.4, 53.44), 0.0, 64, C_WHITE, Color(0, 0, 0, 0.6), 0.005)
	map_rect("城市道路", -64, 54, 64, 66, C_ASPHALT, "road")


func _city() -> void:
	# 远处的城市单独合成一两个网格（不分格子），绘制调用最少
	var cb := MeshBatcher.new()
	cb.chunked = false
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260923
	var placed := 0
	var tries := 0
	while placed < 90 and tries < 800:
		tries += 1
		var ang := rng.randf_range(0.0, TAU)
		var dist := rng.randf_range(115.0, 360.0)
		var pos := Vector3(cos(ang) * dist, 0, sin(ang) * dist)
		# 街道两侧留空，保证站在工地门口能看到开阔的街景
		if pos.z > 50.0 and pos.z < 90.0 and absf(pos.x) < 200.0:
			continue
		var w := rng.randf_range(14.0, 34.0)
		var d := rng.randf_range(14.0, 30.0)
		var h := rng.randf_range(18.0, 95.0) * (1.4 if dist > 220.0 else 1.0)
		var tint := rng.randf_range(0.0, 1.0)
		var col := Color(0.55, 0.58, 0.62).lerp(Color(0.7, 0.68, 0.63), tint)
		if rng.randf() < 0.25:
			col = Color(0.36, 0.46, 0.58)
		cb.box("solid", pos + Vector3(0, h * 0.5, 0), Vector3(w, h, d), col, Basis.IDENTITY, true)
		# 朝向工地一侧的窗户（夜里发光）
		var to_center := -pos.normalized()
		var face_z := absf(to_center.z) > absf(to_center.x)
		var rows := int(h / 3.2) - 1
		for r in range(1, rows, 2):
			var y := r * 3.2 + 1.2
			if face_z:
				var fz := pos.z + signf(to_center.z) * (d * 0.5 + 0.05)
				cb.box("glow", Vector3(pos.x, y, fz), Vector3(w * 0.84, 1.1, 0.1), Color(0.3, 0.33, 0.38))
			else:
				var fx := pos.x + signf(to_center.x) * (w * 0.5 + 0.05)
				cb.box("glow", Vector3(fx, y, pos.z), Vector3(0.1, 1.1, d * 0.84), Color(0.3, 0.33, 0.38))
		placed += 1
	var city := Node3D.new()
	city.name = "City"
	add_child(city)
	cb.build(city, false)


# ================================================================ 围挡与大门
func _fence() -> void:
	var h := 2.5
	var segs := [
		[Vector3(FX0, 0, FZ0), Vector3(FX1, 0, FZ0)],
		[Vector3(FX0, 0, FZ0), Vector3(FX0, 0, FZ1)],
		[Vector3(FX1, 0, FZ0), Vector3(FX1, 0, FZ1)],
		[Vector3(FX0, 0, FZ1), Vector3(-GATE_HALF - 0.6, 0, FZ1)],
		[Vector3(GATE_HALF + 0.6, 0, FZ1), Vector3(FX1, 0, FZ1)],
	]
	for s in segs:
		var a: Vector3 = s[0]
		var b: Vector3 = s[1]
		var mid := (a + b) * 0.5
		var along_x := absf(b.x - a.x) > absf(b.z - a.z)
		var length := a.distance_to(b)
		var size := Vector3(length, h - 0.5, 0.12) if along_x else Vector3(0.12, h - 0.5, length)
		solid(mid + Vector3(0, (h - 0.5) * 0.5, 0), size, C_FENCE)
		var top := Vector3(length, 0.5, 0.13) if along_x else Vector3(0.13, 0.5, length)
		deco(mid + Vector3(0, h - 0.25, 0), top, C_WHITE)
		var n := int(length / 4.0)
		for i in n + 1:
			var p := a.lerp(b, float(i) / float(maxi(n, 1)))
			deco(p + Vector3(0, h * 0.5 + 0.05, 0), Vector3(0.18, h + 0.1, 0.18), Color(0.85, 0.86, 0.86))
	# 围挡内侧标语
	var slogans := [
		["安全第一  预防为主", Vector3(-36, 1.2, FZ1 - 0.1), PI],
		["进入施工现场  必须佩戴安全帽", Vector3(36, 1.2, FZ1 - 0.1), PI],
		["百年大计  质量第一", Vector3(FX0 + 0.1, 1.2, 0), PI * 0.5],
		["文明施工  安全生产", Vector3(FX1 - 0.1, 1.2, 0), -PI * 0.5],
		["安全生产  人人有责", Vector3(0, 1.2, FZ0 + 0.1), 0.0],
	]
	for s in slogans:
		text3d(String(s[0]), s[1], float(s[2]), 150, C_WHITE, Color(0.05, 0.15, 0.35, 0.9), 0.009)
	# 围挡外侧（面向街道）
	text3d("宏远建设  ·  建设美好城市", Vector3(-36, 1.25, FZ1 + 0.08), 0.0, 150, C_WHITE, Color(0.05, 0.15, 0.35, 0.9), 0.009)
	map_rect("围挡", FX0, FZ0, FX1, FZ1, C_FENCE, "fence")


func _gate() -> void:
	for sx in [-1.0, 1.0]:
		solid(Vector3(sx * (GATE_HALF + 0.6), 3.0, FZ1), Vector3(1.2, 6.0, 1.2), Color(0.85, 0.85, 0.83))
		# 收起的电动伸缩门
		deco(Vector3(sx * (GATE_HALF + 2.2), 0.8, FZ1 - 0.7), Vector3(2.4, 1.6, 0.35), C_STEEL, "metal")
	deco(Vector3(0, 6.4, FZ1), Vector3(GATE_HALF * 2 + 2.6, 1.2, 1.2), C_FENCE)
	text3d("宏远建设 · 滨江中心项目", Vector3(0, 6.4, FZ1 + 0.62), 0.0, 128, C_WHITE, Color(0.02, 0.1, 0.3, 0.9), 0.012)
	text3d("欢迎来到滨江中心项目部", Vector3(0, 6.4, FZ1 - 0.62), PI, 110, C_WHITE, Color(0.02, 0.1, 0.3, 0.9), 0.011)
	# 门口的旗杆
	for i in 3:
		var x := 14.0 + i * 1.6
		block(Vector3(x, 0, FZ1 - 3.0), Vector3(0.1, 9.0, 0.1), C_STEEL, false, "metal")
		deco(Vector3(x + 0.7, 8.4, FZ1 - 3.0), Vector3(1.3, 0.85, 0.02), [C_RED, Color(0.9, 0.2, 0.15), C_FENCE][i])


func _guard_booth() -> void:
	var p := Vector3(11.5, 0, 47.5)
	block(p, Vector3(3.2, 2.7, 3.0), C_WHITE)
	deco(p + Vector3(0, 2.8, 0), Vector3(3.6, 0.2, 3.4), C_BLUE_ROOF)
	deco(p + Vector3(-1.62, 1.6, 0), Vector3(0.05, 1.0, 2.2), C_GLASS, "glass")
	text3d("门卫室", p + Vector3(-1.66, 2.35, 0), -PI * 0.5, 72, C_FENCE, Color(1, 1, 1, 0.9), 0.006)
	map_rect("门卫", p.x - 1.6, p.z - 1.5, p.x + 1.6, p.z + 1.5, Color(0.8, 0.8, 0.8))


func _project_billboard() -> void:
	# 立在大门东侧、面向街道的项目效果图
	var c := Vector3(27, 0, FZ1 + 0.9)
	for sx in [-5.0, 5.0]:
		block(c + Vector3(sx, 0, 0), Vector3(0.3, 8.2, 0.3), C_STEEL, true, "metal")
	deco(c + Vector3(0, 5.6, 0), Vector3(12.4, 5.2, 0.25), Color(0.08, 0.14, 0.26))
	# 效果图里的摩天楼剪影
	deco(c + Vector3(-3.6, 5.5, 0.14), Vector3(1.1, 4.4, 0.02), Color(0.55, 0.74, 0.9))
	deco(c + Vector3(-3.6, 7.85, 0.14), Vector3(0.6, 0.4, 0.02), Color(0.55, 0.74, 0.9))
	deco(c + Vector3(-3.6, 8.2, 0.14), Vector3(0.08, 0.5, 0.02), Color(0.9, 0.95, 1.0))
	deco(c + Vector3(-4.8, 4.4, 0.14), Vector3(0.9, 2.2, 0.02), Color(0.35, 0.5, 0.65))
	deco(c + Vector3(-2.5, 4.1, 0.14), Vector3(0.8, 1.6, 0.02), Color(0.35, 0.5, 0.65))
	text3d("滨江中心", c + Vector3(1.4, 6.9, 0.15), 0.0, 170, Color(1.0, 0.86, 0.35), Color(0, 0, 0, 0.8), 0.011)
	text3d("城市第一高楼 · 建成后高 328 米", c + Vector3(1.4, 5.5, 0.15), 0.0, 96, C_WHITE, Color(0, 0, 0, 0.8), 0.008)
	text3d("宏远建设集团 承建", c + Vector3(1.4, 4.4, 0.15), 0.0, 80, Color(0.75, 0.82, 0.9), Color(0, 0, 0, 0.8), 0.007)


# ================================================================ 生活区
func _project_office() -> void:
	var x0 := -30.0
	var x1 := -16.0
	var z0 := 33.0
	var z1 := 39.0
	var cx := (x0 + x1) * 0.5
	var cz := (z0 + z1) * 0.5
	for level in 2:
		var y := level * 2.95
		solid(Vector3(cx, y + 1.45, cz), Vector3(x1 - x0, 2.9, z1 - z0), C_WHITE)
		deco(Vector3(cx, y + 2.9, cz), Vector3(x1 - x0 + 0.1, 0.12, z1 - z0 + 0.1), C_FENCE)
		deco(Vector3(cx, y + 0.05, cz), Vector3(x1 - x0 + 0.1, 0.12, z1 - z0 + 0.1), C_FENCE)
		for i in 4:
			var wx := x0 + 2.0 + i * 3.4
			deco(Vector3(wx, y + 1.6, z0 - 0.02), Vector3(1.6, 1.1, 0.05), C_GLASS, "glass")
			deco(Vector3(wx, y + 1.6, z1 + 0.02), Vector3(1.6, 1.1, 0.05), C_GLASS, "glass")
		deco(Vector3(x1 + 0.02, y + 1.6, cz - 1.8), Vector3(0.05, 1.1, 1.4), C_GLASS, "glass")
	# 东侧的门与台阶
	deco(Vector3(x1 + 0.03, 1.05, cz + 0.9), Vector3(0.06, 2.1, 1.0), Color(0.4, 0.45, 0.52))
	block(Vector3(x1 + 0.6, 0, cz + 0.9), Vector3(1.2, 0.15, 1.6), C_CONCRETE)
	# 西侧楼梯（装饰）
	for i in 10:
		deco(Vector3(x0 - 0.7, 0.15 + i * 0.29, z1 - 1.0 - i * 0.28), Vector3(1.2, 0.08, 0.3), C_STEEL, "metal")
	text3d("项目部", Vector3(x1 + 0.08, 4.5, cz), PI * 0.5, 150, C_RED, Color(1, 1, 1, 0.95), 0.01)
	text3d("滨江中心项目经理部", Vector3(cx, 4.4, z0 - 0.08), PI, 110, C_FENCE, Color(1, 1, 1, 0.95), 0.009)
	# 老王身边的图纸桌
	block(Vector3(-13.0, 0, 38.2), Vector3(1.4, 0.85, 0.8), C_WOOD)
	deco(Vector3(-13.0, 0.87, 38.2), Vector3(1.2, 0.02, 0.6), Color(0.85, 0.9, 0.98))
	map_rect("项目部", x0, z0, x1, z1, Color(0.85, 0.88, 0.95))


func _dorm() -> void:
	var x0 := -56.0
	var x1 := -38.0
	var z0 := 33.0
	var z1 := 40.0
	var cx := (x0 + x1) * 0.5
	var cz := (z0 + z1) * 0.5
	var t := 0.15
	var h := 2.9
	# 一层：三间宿舍，只有最东边的 1 号宿舍能进
	# 北墙（带门洞）
	var door_x := -41.0
	var door_w := 1.1
	solid(Vector3((x0 + door_x - door_w * 0.5) * 0.5, h * 0.5, z0), Vector3(door_x - door_w * 0.5 - x0, h, t), C_WHITE)
	solid(Vector3((door_x + door_w * 0.5 + x1) * 0.5, h * 0.5, z0), Vector3(x1 - door_x - door_w * 0.5, h, t), C_WHITE)
	solid(Vector3(door_x, h - 0.35, z0), Vector3(door_w, 0.7, t), C_WHITE)
	solid(Vector3(cx, h * 0.5, z1), Vector3(x1 - x0, h, t), C_WHITE)
	solid(Vector3(x0, h * 0.5, cz), Vector3(t, h, z1 - z0), C_WHITE)
	solid(Vector3(x1, h * 0.5, cz), Vector3(t, h, z1 - z0), C_WHITE)
	solid(Vector3(-50.0, h * 0.5, cz), Vector3(t, h, z1 - z0), C_WHITE)
	solid(Vector3(-44.0, h * 0.5, cz), Vector3(t, h, z1 - z0), C_WHITE)
	# 另外两间的门（关着）
	for dx in [-53.0, -47.0]:
		deco(Vector3(dx, 1.05, z0 - 0.09), Vector3(1.0, 2.1, 0.05), Color(0.55, 0.6, 0.66))
	# 窗户
	for wx in [-54.5, -48.5, -42.8, -39.2]:
		deco(Vector3(wx, 1.7, z0 - 0.09), Vector3(1.2, 0.9, 0.04), C_GLASS, "glass")
	# 一层顶板 / 二层 / 屋顶
	solid(Vector3(cx, h + 0.08, cz), Vector3(x1 - x0 + 0.2, 0.16, z1 - z0 + 0.2), C_FENCE)
	deco(Vector3(cx, h - 0.005, cz), Vector3(x1 - x0 - 0.2, 0.01, z1 - z0 - 0.2), Color(0.9, 0.9, 0.88))
	deco(Vector3(cx, h + 0.16 + 1.45, cz), Vector3(x1 - x0, 2.9, z1 - z0), C_WHITE)
	deco(Vector3(cx, h * 2 + 0.25, cz), Vector3(x1 - x0 + 0.3, 0.2, z1 - z0 + 0.3), C_BLUE_ROOF)
	for i in 6:
		deco(Vector3(x0 + 1.5 + i * 3.0, h + 1.8, z0 - 1.25), Vector3(1.1, 0.9, 0.04), C_GLASS, "glass")
		deco(Vector3(x0 + 2.5 + i * 3.0, h + 1.2, z0 - 1.23), Vector3(0.9, 2.0, 0.04), Color(0.55, 0.6, 0.66))
	# 二层外走廊与栏杆
	deco(Vector3(cx, h + 0.1, z0 - 0.7), Vector3(x1 - x0, 0.1, 1.4), C_STEEL, "metal")
	deco(Vector3(cx, h + 1.1, z0 - 1.38), Vector3(x1 - x0, 0.06, 0.06), C_STEEL, "metal")
	for i in 10:
		deco(Vector3(x0 + i * 2.0, h + 0.6, z0 - 1.38), Vector3(0.06, 1.0, 0.06), C_STEEL, "metal")
	for i in 3:
		deco(Vector3(x0 + i * 9.0, h * 0.5, z0 - 1.38), Vector3(0.12, h, 0.12), C_STEEL, "metal")
	text3d("职工宿舍", Vector3(cx, h * 2 - 0.3, z0 - 1.45), PI, 150, C_FENCE, Color(1, 1, 1, 0.95), 0.01)
	text3d("1 号宿舍", Vector3(door_x, 2.4, z0 - 0.1), PI, 64, C_FENCE, Color(1, 1, 1, 0.95), 0.006)
	# 1 号宿舍内部：两张上下铺、桌子、柜子
	for bx in [-43.35, -38.65]:
		_bunk_bed(Vector3(bx, 0, 38.45))
	block(Vector3(-41.0, 0, 39.3), Vector3(1.2, 0.75, 0.6), C_WOOD)
	deco(Vector3(-41.3, 0.8, 39.3), Vector3(0.25, 0.1, 0.2), Color(0.9, 0.5, 0.2))
	block(Vector3(-43.5, 0, 33.6), Vector3(0.7, 1.9, 0.5), Color(0.6, 0.64, 0.7))
	var door := Door.new()
	door.width = door_w
	door.display_name = "宿舍门"
	_add_interactable(door, Vector3(door_x, 0, z0), "door_dorm")
	var bed := SimpleInteractable.new()
	bed.kind = "bed"
	bed.display_name = "你的床铺"
	bed.focus_priority = 3
	bed.set_sphere_shape(1.3, Vector3(0, 0.8, 0))
	_add_interactable(bed, Vector3(-42.5, 0, 38.3), "bed_player")
	text3d("你的铺", Vector3(-43.35, 1.25, 37.35), PI, 48, Color(1, 0.9, 0.4), Color(0, 0, 0, 0.8), 0.005)
	# 室内灯
	# 室内灯常亮（屋里照不到太阳）
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(-41, 2.5, 36.5)
	lamp.omni_range = 6.0
	lamp.light_energy = 0.9
	lamp.light_color = Color(1.0, 0.9, 0.75)
	add_child(lamp)
	deco(Vector3(-41, 2.84, 36.5), Vector3(0.8, 0.05, 0.12), Color(1, 0.95, 0.85), "glow")
	map_rect("宿舍", x0, z0, x1, z1, Color(0.8, 0.86, 0.95))


func _bunk_bed(p: Vector3) -> void:
	for level in 2:
		var y := 0.45 + level * 1.15
		deco(Vector3(p.x, y, p.z), Vector3(0.95, 0.08, 2.0), C_STEEL, "metal")
		deco(Vector3(p.x, y + 0.08, p.z), Vector3(0.9, 0.1, 1.95), Color(0.3, 0.45, 0.75))
		deco(Vector3(p.x, y + 0.17, p.z - 0.7), Vector3(0.6, 0.1, 0.35), C_WHITE)
	for sx in [-0.45, 0.45]:
		for sz in [-0.98, 0.98]:
			deco(Vector3(p.x + sx, 1.0, p.z + sz), Vector3(0.05, 2.0, 0.05), C_STEEL, "metal")
	collider(Vector3(p.x, 1.0, p.z), Vector3(0.95, 2.0, 2.0))


func _canteen() -> void:
	var x0 := 32.0
	var x1 := 48.0
	var z0 := 33.0
	var z1 := 43.0
	var cx := (x0 + x1) * 0.5
	var cz := (z0 + z1) * 0.5
	var h := 3.6
	var t := 0.2
	var col := Color(0.93, 0.88, 0.78)
	# 北墙：门洞 35~38，右侧一排窗
	solid(Vector3((x0 + 35.0) * 0.5, h * 0.5, z0), Vector3(35.0 - x0, h, t), col)
	solid(Vector3((38.0 + x1) * 0.5, 0.5, z0), Vector3(x1 - 38.0, 1.0, t), col)
	solid(Vector3((38.0 + x1) * 0.5, h - 0.5, z0), Vector3(x1 - 38.0, 1.0, t), col)
	solid(Vector3(36.5, h - 0.4, z0), Vector3(3.0, 0.8, t), col)
	for wx in [40.0, 43.0, 46.0]:
		solid(Vector3(wx - 1.5, 1.8, z0), Vector3(0.3, 1.6, t), col)
	deco(Vector3((38.0 + x1) * 0.5, 1.8, z0), Vector3(x1 - 38.0, 1.6, 0.05), C_GLASS, "glass")
	collider(Vector3((38.0 + x1) * 0.5, 1.8, z0), Vector3(x1 - 38.0, 1.6, t))
	solid(Vector3(cx, h * 0.5, z1), Vector3(x1 - x0, h, t), col)
	solid(Vector3(x0, h * 0.5, cz), Vector3(t, h, z1 - z0), col)
	solid(Vector3(x1, h * 0.5, cz), Vector3(t, h, z1 - z0), col)
	deco(Vector3(cx, h + 0.12, cz), Vector3(x1 - x0 + 0.6, 0.24, z1 - z0 + 0.6), C_BLUE_ROOF)
	deco(Vector3(cx, h - 0.005, cz), Vector3(x1 - x0 - 0.3, 0.01, z1 - z0 - 0.3), Color(0.92, 0.91, 0.88))
	# 门头招牌
	deco(Vector3(36.5, h + 0.55, z0 - 0.15), Vector3(5.0, 0.8, 0.1), C_RED)
	text3d("职工食堂", Vector3(36.5, h + 0.55, z0 - 0.22), PI, 110, Color(1.0, 0.9, 0.4), Color(0.4, 0.05, 0.03, 0.9), 0.008)
	# 打饭窗口
	solid(Vector3(43.5, 0.5, 40.2), Vector3(7.0, 1.0, 0.7), Color(0.75, 0.77, 0.8), "metal")
	for i in 6:
		deco(Vector3(40.7 + i * 1.1, 1.06, 40.2), Vector3(0.8, 0.1, 0.45), [Color(0.7, 0.3, 0.15), Color(0.3, 0.55, 0.25), Color(0.9, 0.8, 0.5), Color(0.8, 0.5, 0.2), Color(0.4, 0.6, 0.3), Color(0.95, 0.92, 0.85)][i])
	# 后厨灶台
	block(Vector3(43.5, 0, 42.4), Vector3(7.0, 0.9, 0.8), C_STEEL, true, "metal")
	for i in 3:
		mb.cylinder("metal", Vector3(41.2 + i * 2.2, 1.05, 42.4), 0.35, 0.3, Color(0.25, 0.25, 0.27), 10)
	text3d("今日菜单\n红烧肉盒饭 ¥15（饭票可换）\n馒头+咸菜 ¥3　绿豆汤 ¥3　矿泉水 ¥2", Vector3(43.5, 2.55, z1 - 0.12), PI, 56, Color(1, 0.95, 0.8), Color(0.2, 0.1, 0.05, 0.9), 0.0055)
	deco(Vector3(43.5, 2.55, z1 - 0.1), Vector3(3.6, 1.0, 0.04), Color(0.15, 0.25, 0.2))
	# 餐桌
	for i in 3:
		var tz := 35.4 + i * 2.5
		block(Vector3(35.5, 0, tz), Vector3(3.2, 0.75, 0.8), Color(0.85, 0.85, 0.82))
		block(Vector3(35.5, 0, tz - 0.75), Vector3(3.0, 0.42, 0.3), C_FENCE, false)
		block(Vector3(35.5, 0, tz + 0.75), Vector3(3.0, 0.42, 0.3), C_FENCE, false)
	var shop := SimpleInteractable.new()
	shop.kind = "shop"
	shop.target = "canteen"
	shop.prompt = "打饭（职工食堂）"
	shop.display_name = "食堂打饭窗口"
	shop.focus_priority = 1
	shop.set_box_shape(Vector3(7.0, 2.0, 2.2), Vector3(0, 1.0, 0))
	_add_interactable(shop, Vector3(43.5, 0, 38.9), "shop_canteen")
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(40, 3.0, 38)
	lamp.omni_range = 11.0
	lamp.light_energy = 1.0
	lamp.light_color = Color(1.0, 0.92, 0.8)
	add_child(lamp)
	for lx in [36.0, 40.0, 44.0]:
		deco(Vector3(lx, h - 0.05, 38.0), Vector3(1.2, 0.05, 0.2), Color(1, 0.96, 0.9), "glow")
	map_rect("食堂", x0, z0, x1, z1, Color(0.95, 0.85, 0.7))


func _store() -> void:
	var x0 := 18.0
	var x1 := 24.0
	var z0 := 34.0
	var z1 := 39.0
	var cx := (x0 + x1) * 0.5
	var cz := (z0 + z1) * 0.5
	var col := Color(0.95, 0.93, 0.88)
	solid(Vector3(cx, 0.45, z0), Vector3(x1 - x0, 0.9, 0.2), col)
	solid(Vector3(cx, 2.6, z0), Vector3(x1 - x0, 0.8, 0.2), col)
	solid(Vector3(x0 + 0.5, 1.6, z0), Vector3(1.0, 1.4, 0.2), col)
	solid(Vector3(x1 - 0.5, 1.6, z0), Vector3(1.0, 1.4, 0.2), col)
	collider(Vector3(cx, 1.6, z0), Vector3(x1 - x0, 1.4, 0.2))
	solid(Vector3(cx, 1.5, z1), Vector3(x1 - x0, 3.0, 0.2), col)
	solid(Vector3(x0, 1.5, cz), Vector3(0.2, 3.0, z1 - z0), col)
	solid(Vector3(x1, 1.5, cz), Vector3(0.2, 3.0, z1 - z0), col)
	deco(Vector3(cx, 3.1, cz), Vector3(x1 - x0 + 0.8, 0.2, z1 - z0 + 0.8), Color(0.2, 0.55, 0.3))
	deco(Vector3(cx, 2.995, cz), Vector3(x1 - x0 - 0.3, 0.01, z1 - z0 - 0.3), Color(0.92, 0.91, 0.88))
	deco(Vector3(cx, 0.95, z0 - 0.25), Vector3(x1 - x0 - 1.8, 0.08, 0.5), C_WOOD)
	# 货架与商品
	for i in 3:
		deco(Vector3(cx, 0.6 + i * 0.6, z1 - 0.5), Vector3(4.6, 0.05, 0.6), C_STEEL, "metal")
		for k in 10:
			var c: Color = [Color(0.9, 0.2, 0.2), Color(0.2, 0.5, 0.9), Color(0.95, 0.8, 0.2), Color(0.3, 0.7, 0.4)][(k + i) % 4]
			deco(Vector3(cx - 2.0 + k * 0.45, 0.78 + i * 0.6, z1 - 0.5), Vector3(0.22, 0.3, 0.22), c)
	# 冰柜
	block(Vector3(x0 + 1.0, 0, cz + 0.5), Vector3(1.2, 1.9, 0.8), Color(0.85, 0.9, 0.95), false)
	deco(Vector3(x0 + 1.0, 1.1, cz + 0.08), Vector3(1.0, 1.4, 0.03), C_GLASS, "glass")
	# 招牌与收款码
	deco(Vector3(cx, 3.6, z0 - 0.2), Vector3(4.0, 0.7, 0.1), Color(0.2, 0.55, 0.3))
	text3d("小卖部", Vector3(cx, 3.6, z0 - 0.27), PI, 110, C_WHITE, Color(0.05, 0.25, 0.1, 0.9), 0.008)
	deco(Vector3(x1 - 1.2, 1.25, z0 - 0.35), Vector3(0.5, 0.6, 0.03), C_WHITE)
	deco(Vector3(x1 - 1.2, 1.25, z0 - 0.37), Vector3(0.36, 0.36, 0.01), Color(0.1, 0.1, 0.1))
	text3d("扫码付款", Vector3(x1 - 1.2, 1.62, z0 - 0.38), PI, 40, Color(0.1, 0.1, 0.1), Color(1, 1, 1, 0.9), 0.004)
	var shop := SimpleInteractable.new()
	shop.kind = "shop"
	shop.target = "store"
	shop.prompt = "买东西（小卖部）"
	shop.display_name = "小卖部"
	shop.set_box_shape(Vector3(5.0, 2.0, 2.2), Vector3(0, 1.0, 0))
	_add_interactable(shop, Vector3(cx, 0, z0 - 1.2), "shop_store")
	map_rect("小卖部", x0, z0, x1, z1, Color(0.7, 0.9, 0.75))


# ================================================================ 施工楼
func _main_building() -> void:
	var x0 := -20.0
	var x1 := 20.0
	var z0 := -54.0
	var z1 := -22.0
	var cx := (x0 + x1) * 0.5
	var cz := (z0 + z1) * 0.5
	var xs := [-20.0, -12.0, -4.0, 4.0, 12.0, 20.0]
	var zs := [-54.0, -46.0, -38.0, -30.0, -22.0]
	# 首层地坪
	solid(Vector3(cx, -0.1, cz), Vector3(x1 - x0 + 1.0, 0.3, z1 - z0 + 1.0), C_CONCRETE_DARK)
	var full_floors := 5
	for k in range(1, full_floors + 2):
		var y := k * FLOOR_H
		var partial := k == full_floors + 1
		var sx1 := 4.0 if partial else x1
		# 楼板
		if not partial:
			deco(Vector3(cx, y, cz), Vector3(x1 - x0 + 0.8, 0.28, z1 - z0 + 0.8), C_CONCRETE)
		else:
			deco(Vector3((x0 + sx1) * 0.5, y, cz), Vector3(sx1 - x0 + 0.8, 0.28, z1 - z0 + 0.8), C_CONCRETE)
			# 顶层在支模板
			for i in 5:
				deco(Vector3(8.0 + i * 2.2, y - 0.1, cz), Vector3(1.8, 0.08, z1 - z0), Color(0.72, 0.52, 0.3))
		# 柱子
		for x in xs:
			for z in zs:
				if partial and x > sx1 + 0.1:
					continue
				var colc := Vector3(x, y - FLOOR_H * 0.5, z)
				if k == 1:
					solid(colc, Vector3(0.6, FLOOR_H, 0.6), C_CONCRETE)
				else:
					deco(colc, Vector3(0.6, FLOOR_H, 0.6), C_CONCRETE)
		# 顶层柱头伸出的钢筋
		if partial:
			for x in xs:
				for z in zs:
					if x <= sx1 + 0.1:
						continue
					for r in 4:
						var off := Vector3((r % 2) * 0.3 - 0.15, 0, int(r / 2.0) * 0.3 - 0.15)
						mb.beam("solid", Vector3(x, y - FLOOR_H + 0.1, z) + off, Vector3(x, y - FLOOR_H + 1.6, z) + off, 0.04, C_RUST)
		# 北面、西面的临边防护栏杆（红白相间）
		if k <= full_floors:
			var seg := 2.0
			var n := int((x1 - x0) / seg)
			for i in n:
				var c := C_RED if i % 2 == 0 else C_WHITE
				deco(Vector3(x0 + (i + 0.5) * seg, y + 1.1, z0 - 0.35), Vector3(seg, 0.08, 0.08), c)
				deco(Vector3(x0 + (i + 0.5) * seg, y + 0.6, z0 - 0.35), Vector3(seg, 0.08, 0.08), c)
			var nz := int((z1 - z0) / seg)
			for i in nz:
				var c2 := C_RED if i % 2 == 0 else C_WHITE
				deco(Vector3(x0 - 0.35, y + 1.1, z0 + (i + 0.5) * seg), Vector3(0.08, 0.08, seg), c2)
				deco(Vector3(x0 - 0.35, y + 0.6, z0 + (i + 0.5) * seg), Vector3(0.08, 0.08, seg), c2)
		# 二至四层砌了一部分砖墙
		if k >= 2 and k <= 4:
			for i in 5:
				var wx := x0 + 4.0 + i * 8.0
				if (i + k) % 3 == 0:
					continue
				var wy := y - FLOOR_H + 1.3
				deco(Vector3(wx, wy, z0 + 0.15), Vector3(7.3, 2.4, 0.24), C_BRICK)
				deco(Vector3(x0 + 0.15, wy, z0 + 4.0 + i * 6.5), Vector3(0.24, 2.4, 5.8), C_BRICK_DARK)
	# 一层的楼梯间（封闭，暂不能上楼）
	solid(Vector3(16.0, FLOOR_H * 0.5, -50.0), Vector3(7.6, FLOOR_H, 7.6), Color(0.66, 0.66, 0.64))
	text3d("楼梯间 · 暂未开放", Vector3(16.0, 2.2, -46.15), 0.0, 64, C_YELLOW, Color(0, 0, 0, 0.85), 0.006)
	# 施工电梯（北面）
	for i in 2:
		deco(Vector3(-1.0 + i * 1.6, 14.0, z0 - 1.6), Vector3(0.25, 28.0, 0.25), C_YELLOW, "metal")
	deco(Vector3(-0.2, 9.0, z0 - 2.8), Vector3(2.6, 2.6, 2.0), Color(0.85, 0.85, 0.85), "metal")
	# 楼号
	text3d("1# 楼", Vector3(0, FLOOR_H * 5 + 1.6, z1 + 0.45), 0.0, 220, C_RED, Color(1, 1, 1, 0.95), 0.012)
	# 一层南侧入口的安全通道棚
	for sx in [-2.2, 2.2]:
		for sz in [-17.0, -20.5]:
			block(Vector3(sx, 0, sz), Vector3(0.14, 3.2, 0.14), C_SCAFFOLD, false, "metal")
	deco(Vector3(0, 3.25, -18.75), Vector3(5.0, 0.12, 4.2), C_WOOD)
	deco(Vector3(0, 3.45, -18.75), Vector3(5.0, 0.12, 4.2), Color(0.5, 0.36, 0.22))
	deco(Vector3(0, 2.85, -16.85), Vector3(4.6, 0.6, 0.06), C_YELLOW)
	text3d("安全通道", Vector3(0, 2.85, -16.8), 0.0, 90, Color(0.1, 0.1, 0.1), Color(1, 0.9, 0.3, 0.6), 0.006)
	# 砌筑作业面：随着搬砖任务完成逐日长高的砖墙
	var wall := MeshInstance3D.new()
	wall.name = "GrowingWall"
	var wm := BoxMesh.new()
	wm.size = Vector3(6.0, 1.0, 0.24)
	wall.mesh = wm
	wall.material_override = Mats.color(C_BRICK)
	wall.position = Vector3(-8.0, 0.4, -29.4)
	add_child(wall)
	var wall_body := StaticBody3D.new()
	wall_body.collision_layer = 1
	var wall_shape := CollisionShape3D.new()
	var wbox := BoxShape3D.new()
	wbox.size = Vector3(6.0, 1.0, 0.24)
	wall_shape.shape = wbox
	wall_body.add_child(wall_shape)
	wall.add_child(wall_body)
	info["growing_wall"] = wall
	text3d("正在砌筑的墙：每完成一次搬砖任务，第二天长高一截", Vector3(-8.0, 3.0, -29.25), 0.0, 44, C_WHITE, Color(0, 0, 0, 0.8), 0.006)
	# 卸货区
	var brick_zone := DeliveryZone.new()
	brick_zone.zone_id = "brick_zone"
	brick_zone.item_id = "brick"
	brick_zone.display_name = "一层砌筑作业面"
	brick_zone.zone_size = Vector3(5.0, 2.5, 4.0)
	_add_interactable(brick_zone, Vector3(-8.0, 0.05, -26.5), "brick_zone")
	var rebar_zone := DeliveryZone.new()
	rebar_zone.zone_id = "rebar_zone"
	rebar_zone.item_id = "rebar"
	rebar_zone.display_name = "钢筋绑扎区"
	rebar_zone.zone_size = Vector3(3.4, 2.5, 6.0)
	_add_interactable(rebar_zone, Vector3(-16.0, 0.05, -40.0), "rebar_zone")
	map_rect("1# 施工楼", x0, z0, x1, z1, Color(0.7, 0.7, 0.68))
	map_rect("砌筑作业面", -10.5, -28.5, -5.5, -24.5, Color(1.0, 0.8, 0.1), "zone")
	map_rect("钢筋绑扎区", -17.7, -43.0, -14.3, -37.0, Color(1.0, 0.8, 0.1), "zone")


func _scaffolding() -> void:
	# 南立面与东立面的双排脚手架 + 绿色密目安全网（首层留出通行空间）
	var top := 21.6
	var step := 1.8
	# 南立面：z = -21.0 / -20.1
	var xs := []
	var x := -19.8
	while x <= 19.9:
		xs.append(x)
		x += step
	for zz in [-21.0, -20.1]:
		for px in xs:
			mb.box("metal", Vector3(px, top * 0.5, zz), Vector3(0.06, top, 0.06), C_SCAFFOLD)
		var y := 1.8
		while y <= top:
			mb.box("metal", Vector3(0, y, zz), Vector3(40.0, 0.05, 0.05), C_SCAFFOLD)
			y += step
	var yy := 3.6
	while yy <= top:
		deco(Vector3(0, yy + 0.03, -20.55), Vector3(40.0, 0.05, 0.85), C_WOOD)
		yy += FLOOR_H
	deco(Vector3(0, (top + 2.3) * 0.5, -19.98), Vector3(40.6, top - 2.3, 0.02), C_NET, "net")
	banner("百年大计  质量第一", Vector3(-8, 12.0, -19.9), 0.0, 12.0, 1.3)
	banner("安全生产  警钟长鸣", Vector3(10, 12.0, -19.9), 0.0, 12.0, 1.3)
	# 东立面：x = 21.0 / 21.9
	var zs := []
	var z := -53.8
	while z <= -22.0:
		zs.append(z)
		z += step
	for xx in [21.0, 21.9]:
		for pz in zs:
			mb.box("metal", Vector3(xx, top * 0.5, pz), Vector3(0.06, top, 0.06), C_SCAFFOLD)
		var y2 := 1.8
		while y2 <= top:
			mb.box("metal", Vector3(xx, y2, -38.0), Vector3(0.05, 0.05, 32.0), C_SCAFFOLD)
			y2 += step
	deco(Vector3(22.02, (top + 2.3) * 0.5, -38.0), Vector3(0.02, top - 2.3, 32.4), C_NET, "net")
	banner("安全第一  预防为主", Vector3(22.1, 13.0, -38.0), PI * 0.5, 12.0, 1.3)


# ================================================================ 材料区
func _brick_yard() -> void:
	var center := Vector3(-10.5, 0, -6.0)
	for ix in 3:
		for iz in 2:
			var p := center + Vector3((ix - 1) * 3.5, 0, (iz - 0.5) * 4.0)
			_brick_pallet(p)
	block(Vector3(-17.0, 0, -9.0), Vector3(0.12, 2.6, 0.12), C_STEEL, false, "metal")
	deco(Vector3(-17.0, 2.4, -9.0), Vector3(2.4, 0.7, 0.06), C_FENCE)
	text3d("砖块堆放区", Vector3(-17.0, 2.4, -8.96), 0.0, 80, C_WHITE, Color(0, 0, 0, 0.6), 0.007)
	# 旁边一辆手推车（装饰）
	_wheelbarrow(Vector3(-4.8, 0, -3.0), 0.6)
	var pile := MaterialPile.new()
	pile.item_id = "brick"
	pile.display_name = "砖块堆放区"
	pile.area_size = Vector3(12.0, 3.0, 8.6)
	_add_interactable(pile, center, "pile_brick")
	map_rect("砖块堆放区", center.x - 6.0, center.z - 4.3, center.x + 6.0, center.z + 4.3, C_BRICK, "pile")


func _brick_pallet(p: Vector3) -> void:
	block(p, Vector3(1.2, 0.14, 1.05), C_WOOD)
	var bs := Vector3(0.26, 0.075, 0.13)
	var cols := 4
	var rows := 7
	var lower_layers := 6
	var lh := bs.y + 0.006
	var stack_w := cols * (bs.x + 0.01)
	var stack_d := rows * (bs.z + 0.01)
	block(p + Vector3(0, 0.14, 0), Vector3(stack_w - 0.02, lower_layers * lh, stack_d - 0.02), C_BRICK_DARK)
	collider(p + Vector3(0, 0.5, 0), Vector3(1.2, 1.0, 1.05))
	for layer in 2:
		var y := 0.14 + (lower_layers + layer) * lh + bs.y * 0.5
		for c in cols:
			for r in rows:
				if layer == 1 and (c + r) % 5 == 0:
					continue
				var bx := (c - (cols - 1) * 0.5) * (bs.x + 0.01)
				var bz := (r - (rows - 1) * 0.5) * (bs.z + 0.01)
				var shade := 0.92 + 0.08 * float((c * 7 + r * 3 + layer) % 3) / 2.0
				deco(p + Vector3(bx, y, bz), bs, Color(C_BRICK.r * shade, C_BRICK.g * shade, C_BRICK.b * shade))


func _cement_area() -> void:
	var center := Vector3(22.0, 0, 1.0)
	var w := 10.0
	var d := 8.0
	for sx in [-0.5, 0.0, 0.5]:
		for sz in [-0.5, 0.5]:
			block(center + Vector3(sx * w, 0, sz * d), Vector3(0.16, 3.4, 0.16), C_STEEL, true, "metal")
	deco(center + Vector3(0, 3.5, 0), Vector3(w + 0.8, 0.12, d + 0.8), C_BLUE_ROOF, "metal", Basis(Vector3.RIGHT, 0.05))
	# 水泥袋垛
	for ix in 2:
		for iz in 2:
			var p := center + Vector3((ix - 0.5) * 3.6, 0, (iz - 0.5) * 3.2)
			block(p, Vector3(1.3, 0.14, 1.2), C_WOOD)
			collider(p + Vector3(0, 0.55, 0), Vector3(1.3, 1.1, 1.2))
			for layer in 6:
				for k in 6:
					var bx := (k % 2 - 0.5) * 0.56
					var bz := (int(k / 2.0) - 1) * 0.38
					if layer % 2 == 1:
						bx += 0.03
					var shade := 0.95 + 0.05 * float((k + layer) % 2)
					deco(p + Vector3(bx, 0.14 + 0.07 + layer * 0.145, bz), Vector3(0.52, 0.14, 0.36), Color(C_CEMENT_BAG.r * shade, C_CEMENT_BAG.g * shade, C_CEMENT_BAG.b * shade))
	deco(center + Vector3(0, 3.0, d * 0.5 + 0.45), Vector3(4.6, 0.7, 0.06), C_FENCE)
	text3d("水泥库 · 防潮防雨", center + Vector3(0, 3.0, d * 0.5 + 0.49), 0.0, 80, C_WHITE, Color(0, 0, 0, 0.6), 0.007)
	var pile := MaterialPile.new()
	pile.item_id = "cement"
	pile.display_name = "水泥库"
	pile.area_size = Vector3(w, 3.0, d)
	_add_interactable(pile, center, "pile_cement")
	map_rect("水泥库", center.x - w * 0.5, center.z - d * 0.5, center.x + w * 0.5, center.z + d * 0.5, C_CEMENT_BAG, "pile")


func _mixer_station() -> void:
	var p := Vector3(30.8, 0, -8.0)
	# 机架
	for sx in [-0.9, 0.9]:
		for sz in [-0.8, 0.8]:
			block(p + Vector3(sx, 0, sz), Vector3(0.14, 1.4, 0.14), C_STEEL, false, "metal")
	collider(p + Vector3(0, 1.3, 0), Vector3(2.2, 2.6, 2.0))
	# 滚筒
	mb.cylinder("solid", p + Vector3(0, 2.0, 0), 0.95, 1.9, Color(0.95, 0.5, 0.12), 14, Basis(Vector3.FORWARD, PI * 0.5))
	mb.cylinder("solid", p + Vector3(-1.05, 2.0, 0), 0.55, 0.3, Color(0.25, 0.25, 0.27), 12, Basis(Vector3.FORWARD, PI * 0.5))
	# 上料斗
	mb.cylinder("metal", p + Vector3(-1.6, 1.0, 0), 0.35, 1.3, C_STEEL, 10, Basis.IDENTITY, 0.9)
	# 电机与水箱
	block(p + Vector3(1.2, 1.2, -0.6), Vector3(0.7, 0.6, 0.6), Color(0.2, 0.45, 0.25), false)
	mb.cylinder("solid", p + Vector3(1.6, 1.1, 1.3), 0.5, 2.2, Color(0.2, 0.45, 0.8), 12)
	collider(p + Vector3(1.6, 1.1, 1.3), Vector3(1.0, 2.2, 1.0))
	block(Vector3(33.5, 0, -10.8), Vector3(0.12, 2.6, 0.12), C_STEEL, false, "metal")
	deco(Vector3(33.5, 2.4, -10.8), Vector3(2.0, 0.7, 0.06), C_FENCE)
	text3d("搅拌站", Vector3(33.5, 2.4, -10.76), 0.0, 80, C_WHITE, Color(0, 0, 0, 0.6), 0.007)
	# 砂石堆
	mb.cylinder("solid", Vector3(38.0, 1.1, -17.5), 3.2, 2.2, Color(0.8, 0.7, 0.5), 12, Basis.IDENTITY, 0.25)
	mb.cylinder("solid", Vector3(44.5, 0.9, -17.0), 2.6, 1.8, Color(0.55, 0.55, 0.53), 12, Basis.IDENTITY, 0.2)
	collider(Vector3(38.0, 0.6, -17.5), Vector3(4.2, 1.2, 4.2))
	_wheelbarrow(Vector3(27.5, 0, -11.5), -0.8)
	var zone := DeliveryZone.new()
	zone.zone_id = "cement_zone"
	zone.item_id = "cement"
	zone.display_name = "搅拌站上料点"
	zone.zone_size = Vector3(4.0, 2.5, 3.5)
	_add_interactable(zone, Vector3(26.2, 0, -7.6), "cement_zone")
	map_rect("搅拌站", 29.0, -10.0, 33.0, -6.0, Color(0.95, 0.55, 0.15))
	map_rect("上料点", 24.2, -9.35, 28.2, -5.85, Color(1.0, 0.8, 0.1), "zone")
	# 混凝土罐车
	_mixer_truck(Vector3(41.0, 0, -4.0))


func _rebar_yard() -> void:
	var center := Vector3(-38.0, 0, -30.0)
	var w := 16.0
	var d := 12.0
	# 加工棚
	for sx in [-0.5, 0.0, 0.5]:
		for sz in [-0.5, 0.5]:
			block(center + Vector3(sx * w, 0, sz * d), Vector3(0.18, 4.0, 0.18), C_STEEL, true, "metal")
	deco(center + Vector3(0, 4.1, 0), Vector3(w + 1.0, 0.12, d + 1.0), C_BLUE_ROOF, "metal", Basis(Vector3.FORWARD, 0.04))
	# 钢筋架
	for r in 3:
		var rz := center.z - 4.0 + r * 4.0
		for k in 4:
			var rx := center.x - 6.0 + k * 4.0
			block(Vector3(rx, 0, rz), Vector3(0.14, 1.1, 0.9), Color(0.45, 0.45, 0.47), false, "metal")
		collider(Vector3(center.x, 0.5, rz), Vector3(13.0, 1.0, 1.0))
		for layer in 2:
			for b in 12:
				var bz := rz - 0.35 + b * 0.064
				deco(Vector3(center.x, 1.15 + layer * 0.07, bz), Vector3(13.5, 0.035, 0.035), C_RUST)
	# 弯曲机
	block(center + Vector3(5.0, 0, 4.8), Vector3(1.2, 0.8, 0.9), Color(0.2, 0.45, 0.3))
	deco(center + Vector3(5.0, 0.85, 4.8), Vector3(0.6, 0.1, 0.6), C_STEEL, "metal")
	block(Vector3(center.x + w * 0.5 + 0.6, 0, center.z + d * 0.5 - 0.5), Vector3(0.12, 2.8, 0.12), C_STEEL, false, "metal")
	deco(Vector3(center.x + w * 0.5 + 0.6, 2.6, center.z + d * 0.5 - 0.5), Vector3(0.06, 0.7, 2.6), C_FENCE)
	text3d("钢筋堆场", Vector3(center.x + w * 0.5 + 0.64, 2.6, center.z + d * 0.5 - 0.5), PI * 0.5, 80, C_WHITE, Color(0, 0, 0, 0.6), 0.007)
	text3d("钢筋加工棚", center + Vector3(0, 3.5, d * 0.5 + 0.55), 0.0, 90, C_WHITE, Color(0.05, 0.15, 0.35, 0.9), 0.008)
	var pile := MaterialPile.new()
	pile.item_id = "rebar"
	pile.display_name = "钢筋堆场"
	pile.area_size = Vector3(w, 3.0, d)
	_add_interactable(pile, center, "pile_rebar")
	map_rect("钢筋堆场", center.x - w * 0.5, center.z - d * 0.5, center.x + w * 0.5, center.z + d * 0.5, C_RUST, "pile")
	# 木方模板堆
	for i in 3:
		block(Vector3(-40.0 + i * 3.0, 0, -52.0), Vector3(2.4, 0.9 + i * 0.2, 1.2), Color(0.66, 0.5, 0.3))
	map_rect("模板堆", -41.5, -53, -34, -51, Color(0.66, 0.5, 0.3), "pile")


func _water_station() -> void:
	var p := Vector3(6.5, 0, -8.0)
	block(p, Vector3(1.4, 0.8, 0.9), C_STEEL, true, "metal")
	mb.cylinder("solid", p + Vector3(-0.3, 1.2, 0), 0.32, 0.8, Color(0.2, 0.5, 0.85), 12)
	mb.cylinder("solid", p + Vector3(0.35, 1.05, 0), 0.22, 0.5, Color(0.9, 0.3, 0.2), 10)
	block(Vector3(p.x + 0.9, 0, p.z), Vector3(0.1, 2.2, 0.1), C_STEEL, false, "metal")
	deco(Vector3(p.x + 0.9, 2.1, p.z), Vector3(1.4, 0.5, 0.05), Color(0.1, 0.5, 0.25))
	text3d("凉茶 · 免费饮用", Vector3(p.x + 0.9, 2.1, p.z + 0.04), 0.0, 56, C_WHITE, Color(0, 0, 0, 0.6), 0.0055)
	var w := SimpleInteractable.new()
	w.kind = "water"
	w.display_name = "凉茶桶"
	w.set_sphere_shape(1.6, Vector3(0, 1.0, 0))
	_add_interactable(w, p, "water_station")
	map_rect("凉茶", p.x - 0.7, p.z - 0.5, p.x + 0.7, p.z + 0.5, Color(0.2, 0.5, 0.85), "point")


# ================================================================ 杂项
func _props() -> void:
	# 移动厕所
	for i in 2:
		block(Vector3(-60.0 + i * 1.5, 0, 18.0), Vector3(1.3, 2.3, 1.3), Color(0.2, 0.45, 0.75))
	text3d("卫生间", Vector3(-59.25, 2.55, 18.7), 0.0, 60, C_WHITE, Color(0, 0, 0, 0.6), 0.006)
	# 洗漱台
	block(Vector3(-47.0, 0, 44.0), Vector3(6.0, 0.9, 0.8), C_STEEL, true, "metal")
	for i in 5:
		mb.cylinder("metal", Vector3(-49.4 + i * 1.2, 1.2, 44.0), 0.03, 0.6, C_STEEL, 6)
	# 停着的皮卡
	_pickup_truck(Vector3(-9.0, 0, 44.0))
	# 生活区与施工区之间的隔离栏（中间与两侧留出通道）
	for i in 35:
		var x := -61.0 + i * 3.5 + 1.75
		if absf(x) < 7.0 or absf(absf(x) - 40.0) < 3.0:
			continue
		solid(Vector3(x, 0.55, 20.5), Vector3(3.3, 1.1, 0.06), C_YELLOW)
		deco(Vector3(x, 0.55, 20.5), Vector3(3.3, 0.25, 0.08), Color(0.1, 0.1, 0.1))
	text3d("前方施工区 · 必须佩戴安全帽", Vector3(-14.0, 1.6, 20.56), 0.0, 64, C_YELLOW, Color(0, 0, 0, 0.85), 0.007)
	text3d("前方生活区", Vector3(14.0, 1.6, 20.44), PI, 64, C_WHITE, Color(0, 0, 0, 0.85), 0.007)
	# 灭火器箱
	block(Vector3(5.2, 0, -21.0), Vector3(0.5, 0.9, 0.35), C_RED)
	text3d("消防", Vector3(5.2, 0.65, -20.8), 0.0, 40, C_WHITE, Color(0, 0, 0, 0.6), 0.005)


func _wheelbarrow(p: Vector3, yaw: float) -> void:
	var rot := Basis(Vector3.UP, yaw)
	deco(p + rot * Vector3(0, 0.55, 0), Vector3(0.65, 0.35, 0.9), Color(0.2, 0.5, 0.3), "metal", rot)
	mb.cylinder("solid", p + rot * Vector3(0, 0.2, -0.6), 0.2, 0.1, Color(0.1, 0.1, 0.1), 10, rot * Basis(Vector3.FORWARD, PI * 0.5))
	for sx in [-0.25, 0.25]:
		deco(p + rot * Vector3(sx, 0.6, 0.7), Vector3(0.05, 0.05, 0.9), C_STEEL, "metal", rot)


func _mixer_truck(p: Vector3) -> void:
	deco(p + Vector3(0, 0.9, 0), Vector3(2.4, 0.4, 8.0), Color(0.2, 0.2, 0.22))
	deco(p + Vector3(0, 1.9, -3.3), Vector3(2.4, 1.8, 1.8), Color(0.92, 0.92, 0.9))
	deco(p + Vector3(0, 2.3, -4.21), Vector3(2.2, 0.8, 0.04), C_GLASS, "glass")
	mb.cylinder("solid", p + Vector3(0, 2.4, 0.8), 1.2, 4.6, Color(0.95, 0.45, 0.1), 14, Basis(Vector3.RIGHT, PI * 0.5 - 0.15), 0.7)
	for sz in [-3.2, -0.2, 1.6, 3.0]:
		for sx in [-1.15, 1.15]:
			mb.cylinder("solid", p + Vector3(sx, 0.5, sz), 0.5, 0.35, Color(0.08, 0.08, 0.08), 12, Basis(Vector3.FORWARD, PI * 0.5))
	collider(p + Vector3(0, 1.6, 0), Vector3(2.6, 3.2, 8.2))
	map_rect("罐车", p.x - 1.3, p.z - 4.1, p.x + 1.3, p.z + 4.1, Color(0.95, 0.45, 0.1), "vehicle")


func _pickup_truck(p: Vector3) -> void:
	deco(p + Vector3(0, 0.75, 0), Vector3(1.9, 0.7, 5.0), Color(0.75, 0.75, 0.78))
	deco(p + Vector3(0, 1.45, -0.8), Vector3(1.8, 0.7, 2.0), Color(0.75, 0.75, 0.78))
	deco(p + Vector3(0, 1.5, -1.81), Vector3(1.6, 0.5, 0.03), C_GLASS, "glass")
	for sz in [-1.6, 1.6]:
		for sx in [-0.95, 0.95]:
			mb.cylinder("solid", p + Vector3(sx, 0.38, sz), 0.38, 0.28, Color(0.08, 0.08, 0.08), 12, Basis(Vector3.FORWARD, PI * 0.5))
	collider(p + Vector3(0, 0.9, 0), Vector3(2.0, 1.8, 5.1))


func _lamps() -> void:
	# 工地照明灯塔：夜里点亮
	var towers := [Vector3(5.5, 0, 12.0), Vector3(-34.0, 0, 22.0), Vector3(34.0, 0, 22.0), Vector3(-26.0, 0, -12.0), Vector3(26.0, 0, -20.0)]
	for i in towers.size():
		var p: Vector3 = towers[i]
		block(p, Vector3(0.3, 10.0, 0.3), C_STEEL, true, "metal")
		deco(p + Vector3(0, 10.1, 0), Vector3(1.6, 0.5, 0.6), Color(0.95, 0.95, 0.9), "glow")
		if i < 3:
			var light := OmniLight3D.new()
			light.position = p + Vector3(0, 9.0, 0)
			light.omni_range = 30.0
			light.omni_attenuation = 1.2
			light.light_energy = 1.3
			light.light_color = Color(1.0, 0.93, 0.8)
			light.visible = false
			add_child(light)
			info["night_lights"].append(light)
	# 街灯
	for i in range(-6, 7):
		var p2 := Vector3(i * 24.0 + 10.0, 0, 67.8)
		block(p2, Vector3(0.14, 7.0, 0.14), C_STEEL, false, "metal")
		deco(p2 + Vector3(0, 7.0, -1.0), Vector3(0.1, 0.1, 2.0), C_STEEL, "metal")
		deco(p2 + Vector3(0, 6.9, -1.9), Vector3(0.5, 0.12, 0.3), Color(1, 0.95, 0.85), "glow")


# ================================================================ 塔吊
func _tower_crane(base: Vector3) -> Node3D:
	var mast_h := 42.0
	solid(base + Vector3(0, 0.6, 0), Vector3(5.0, 1.2, 5.0), C_CONCRETE_DARK)
	collider(base + Vector3(0, mast_h * 0.5, 0), Vector3(2.0, mast_h, 2.0))
	# 标准节：四根主肢 + 斜腹杆
	var hw := 0.9
	var corners := [Vector3(-hw, 0, -hw), Vector3(hw, 0, -hw), Vector3(hw, 0, hw), Vector3(-hw, 0, hw)]
	for c in corners:
		mb.box("metal", base + c + Vector3(0, 1.2 + mast_h * 0.5, 0), Vector3(0.16, mast_h, 0.16), C_YELLOW)
	var y := 1.2
	var seg := 3.0
	var flip := false
	while y < mast_h:
		for i in 4:
			var a: Vector3 = corners[i]
			var b: Vector3 = corners[(i + 1) % 4]
			var y0 := y if flip else y + seg
			var y1 := y + seg if flip else y
			mb.beam("metal", base + a + Vector3(0, y0, 0), base + b + Vector3(0, y1, 0), 0.07, C_YELLOW)
			mb.beam("metal", base + a + Vector3(0, y, 0), base + b + Vector3(0, y, 0), 0.08, C_YELLOW)
		flip = not flip
		y += seg
	# 回转部分（单独节点，慢慢转）
	var pivot := Node3D.new()
	pivot.name = "CranePivot"
	pivot.position = base + Vector3(0, mast_h + 1.2, 0)
	add_child(pivot)
	var cm := MeshBatcher.new()
	cm.chunked = false
	cm.box("metal", Vector3(0, 0.5, 0), Vector3(2.6, 1.0, 2.6), C_YELLOW)
	# 司机室
	cm.box("solid", Vector3(1.9, 0.2, 1.0), Vector3(1.4, 1.8, 1.6), Color(0.95, 0.95, 0.92))
	cm.box("glass", Vector3(1.9, 0.4, 1.81), Vector3(1.2, 1.0, 0.03), C_GLASS)
	# 塔帽
	for c in corners:
		cm.beam("metal", Vector3(c.x * 0.8, 1.0, c.z * 0.8), Vector3(0, 8.0, 0), 0.14, C_YELLOW)
	# 起重臂（-X 方向）
	var jib_len := 48.0
	var jy := 1.2
	var jh := 1.6
	cm.box("metal", Vector3(-jib_len * 0.5, jy, -0.6), Vector3(jib_len, 0.12, 0.12), C_YELLOW)
	cm.box("metal", Vector3(-jib_len * 0.5, jy, 0.6), Vector3(jib_len, 0.12, 0.12), C_YELLOW)
	cm.box("metal", Vector3(-jib_len * 0.5, jy + jh, 0), Vector3(jib_len, 0.12, 0.12), C_YELLOW)
	var x := 0.0
	while x > -jib_len + 0.5:
		var x2 := x - 2.0
		cm.beam("metal", Vector3(x, jy, -0.6), Vector3(x2, jy + jh, 0), 0.06, C_YELLOW)
		cm.beam("metal", Vector3(x, jy, 0.6), Vector3(x2, jy + jh, 0), 0.06, C_YELLOW)
		cm.beam("metal", Vector3(x2, jy + jh, 0), Vector3(x2 - 2.0, jy, -0.6), 0.06, C_YELLOW)
		cm.beam("metal", Vector3(x2, jy + jh, 0), Vector3(x2 - 2.0, jy, 0.6), 0.06, C_YELLOW)
		cm.box("metal", Vector3(x, jy, 0), Vector3(0.06, 0.06, 1.2), C_YELLOW)
		x -= 4.0
	# 平衡臂（+X）与配重
	cm.box("metal", Vector3(7.5, jy, 0), Vector3(15.0, 0.25, 1.4), C_YELLOW)
	for i in 3:
		cm.box("solid", Vector3(11.5 + i * 1.1, jy - 1.0, 0), Vector3(1.0, 1.8, 1.8), C_CONCRETE)
	# 拉杆
	cm.beam("metal", Vector3(0, 8.0, 0), Vector3(-30.0, jy + jh, 0), 0.05, C_STEEL)
	cm.beam("metal", Vector3(0, 8.0, 0), Vector3(14.5, jy, 0), 0.05, C_STEEL)
	# 小车、吊钩与吊着的一托盘砖
	cm.box("metal", Vector3(-26.0, jy - 0.2, 0), Vector3(1.2, 0.4, 1.4), Color(0.3, 0.3, 0.32))
	var hook_y := -22.0
	cm.box("metal", Vector3(-26.0, (jy - 0.4 + hook_y) * 0.5, 0), Vector3(0.04, jy - 0.4 - hook_y, 0.04), Color(0.15, 0.15, 0.15))
	cm.box("solid", Vector3(-26.0, hook_y, 0), Vector3(0.5, 0.6, 0.3), C_YELLOW)
	cm.box("solid", Vector3(-26.0, hook_y - 1.6, 0), Vector3(1.2, 0.14, 1.0), C_WOOD)
	cm.box("solid", Vector3(-26.0, hook_y - 1.2, 0), Vector3(1.05, 0.66, 0.9), C_BRICK)
	for sx in [-0.5, 0.5]:
		cm.beam("metal", Vector3(-26.0, hook_y - 0.3, 0), Vector3(-26.0 + sx, hook_y - 0.9, 0.4), 0.02, Color(0.15, 0.15, 0.15))
	cm.build(pivot)
	text3d("塔吊", base + Vector3(0, 6.0, 1.0), 0.0, 90, C_YELLOW, Color(0, 0, 0, 0.8), 0.01)
	map_rect("塔吊", base.x - 2.5, base.z - 2.5, base.x + 2.5, base.z + 2.5, C_YELLOW, "crane")
	return pivot


# ================================================================ 开场的大巴
func _bus(p: Vector3) -> Node3D:
	var bus := Node3D.new()
	bus.name = "Bus"
	bus.position = p
	add_child(bus)
	var bm := MeshBatcher.new()
	bm.chunked = false
	bm.box("solid", Vector3(0, 1.75, 0), Vector3(11.0, 2.7, 2.5), Color(0.92, 0.9, 0.84))
	bm.box("solid", Vector3(0, 0.6, 0), Vector3(11.0, 0.5, 2.5), Color(0.2, 0.45, 0.35))
	bm.box("glass", Vector3(0, 2.2, 1.26), Vector3(9.6, 1.0, 0.03), Color(0.25, 0.35, 0.42, 0.85))
	bm.box("glass", Vector3(0, 2.2, -1.26), Vector3(9.6, 1.0, 0.03), Color(0.25, 0.35, 0.42, 0.85))
	bm.box("glass", Vector3(5.51, 2.1, 0), Vector3(0.03, 1.3, 2.2), Color(0.25, 0.35, 0.42, 0.85))
	bm.box("solid", Vector3(0, 1.3, 1.27), Vector3(10.6, 0.2, 0.02), Color(0.85, 0.3, 0.1))
	for sx in [-3.6, 3.4]:
		for sz in [-1.2, 1.2]:
			bm.cylinder("solid", Vector3(sx, 0.5, sz), 0.5, 0.3, Color(0.08, 0.08, 0.08), 12, Basis(Vector3.RIGHT, PI * 0.5))
	bm.build(bus)
	var l := Label3D.new()
	l.text = "长途客运"
	l.font = font
	l.font_size = 72
	l.pixel_size = 0.008
	l.outline_size = 8
	l.modulate = Color(0.85, 0.3, 0.1)
	l.position = Vector3(0, 2.95, 1.27)
	bus.add_child(l)
	return bus


# ================================================================ NPC 站位
func _npc_defs() -> void:
	info["npcs"] = [
		{
			"id": "wang", "name": "老王", "role": "工头", "pos": Vector3(-13.8, 0.1, 35.8), "yaw": -PI * 0.5,
			"look": {"shirt": Color(0.14, 0.15, 0.18), "pants": Color(0.3, 0.27, 0.22), "hat": "red", "belly": true, "skin": Color(0.8, 0.6, 0.45)},
		},
		{
			"id": "liu", "name": "大刘", "role": "工友", "pos": Vector3(-9.0, 0.1, -10.8), "yaw": 0.0,
			"patrol": PackedVector3Array([Vector3(-9.0, 0, -10.8), Vector3(-4.9, 0, -23.4)]), "carry": "brick", "speed": 1.9,
			"look": {"shirt": Color(0.45, 0.32, 0.22), "pants": Color(0.22, 0.24, 0.3), "vest": Color(1.0, 0.45, 0.05), "hat": "yellow", "scale": 1.05},
		},
		{
			"id": "chen", "name": "老陈", "role": "食堂老板", "pos": Vector3(43.5, 0.1, 41.5), "yaw": 0.0,
			"look": {"shirt": Color(0.95, 0.95, 0.93), "pants": Color(0.25, 0.25, 0.3), "vest": Color(0.9, 0.9, 0.88), "hat": "chef", "belly": true},
		},
		{
			"id": "xiaoli", "name": "小李", "role": "", "pos": Vector3(20.5, 0.1, -3.9), "yaw": 0.0, "talkable": false,
			"patrol": PackedVector3Array([Vector3(20.5, 0, -3.9), Vector3(28.6, 0, -5.4)]), "carry": "cement", "speed": 1.5,
			"look": {"shirt": Color(0.3, 0.4, 0.55), "hat": "yellow", "vest": Color(1.0, 0.45, 0.05)},
			"barks": ["忙着呢，有事找老王。", "这水泥是真沉，一袋五十斤。", "搅拌站今天要打圈梁，料得备足。"],
		},
		{
			"id": "laozhao", "name": "老赵", "role": "", "pos": Vector3(-32.5, 0.1, -23.2), "yaw": PI * 0.75, "talkable": false,
			"look": {"shirt": Color(0.35, 0.35, 0.3), "hat": "blue"},
			"barks": ["钢筋按规格码放，别乱扔。", "这批是二十五的螺纹钢，沉着呢。", "小心脚底下，钢筋头扎人。"],
		},
		{
			"id": "guard", "name": "门卫大爷", "role": "", "pos": Vector3(9.0, 0.1, 49.2), "yaw": PI * 0.6, "talkable": false,
			"look": {"shirt": Color(0.2, 0.25, 0.4), "pants": Color(0.18, 0.2, 0.28), "hat": "none"},
			"barks": ["新来的？项目部在左手边，找老王。", "进了工地就把安全帽戴好！", "晚上十点锁大门啊。"],
		},
	]
