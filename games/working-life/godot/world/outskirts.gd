class_name Outskirts
extends RefCounted
## 城外远景（玩家走不到，但从高处、观景台、开场列车上看得到）：
##   北边：中央商务区（CBD）高楼群 + 几栋轮廓独特的地标楼 + 在建高楼与塔吊；
##   其余方向：大片低层城区（双坡屋顶住宅、商业街、仓库）、街道、成片路灯与棕榈；
##   两条高架快速路（有车流）、南边的铁路货场。
## 所有几何体合成少数几个大网格（不分块）；路灯与棕榈用 MultiMesh，各一两次绘制调用。

const PITCH := 44.0
const R_MAX := 612.0
const CITY := 218.0
## 快速路：东西向在 z = FW_Z，南北向在 x = FW_X（更高一层，从上方跨过）
const FW_Z := -236.0
const FW_X := 242.0
const FW_Y_EW := 11.0
const FW_Y_NS := 18.0
const FW_W := 24.0
## 铁路货场（南边，开场磁悬浮轨道 z = 200 的外侧）
const YARD_Z0 := 222.0
const YARD_Z1 := 264.0
## 中央商务区范围
const CBD := Rect2(-360.0, -560.0, 720.0, 298.0)

var kit: BuildingKit
var b: MeshBatcher
var rng := RandomNumberGenerator.new()
var lamps: Array = []
var palms: Array = []
var reserved: Array = []


func build(parent: Node3D, k: BuildingKit) -> void:
	kit = k
	rng.seed = 2088
	b = MeshBatcher.new()
	b.chunked = false
	_landmarks()
	_cbd()
	_sprawl()
	_freeway(true)
	_freeway(false)
	_rail_yard()
	var node := Node3D.new()
	node.name = "Outskirts"
	parent.add_child(node)
	b.build(node, false)
	_multimesh(node, "Lamps", _lamp_mesh(), lamps)
	# 低画质与触屏设备不画远处的棕榈
	if int(SettingsManager.get_v("quality", 1)) >= 1 and not GameManager.touch_mode:
		_multimesh(node, "Palms", _palm_mesh(), palms)
	var ft := FreewayTraffic.new()
	ft.name = "FreewayTraffic"
	node.add_child(ft)
	ft.setup()


# ================================================================ 区域判断
func _blocked(r: Rect2) -> bool:
	if Rect2(-CITY, -CITY, CITY * 2.0, CITY * 2.0).intersects(r):
		return true
	if r.position.y < YARD_Z1 + 10.0 and r.end.y > 186.0:
		return true
	if r.position.y < FW_Z + FW_W * 0.5 + 6.0 and r.end.y > FW_Z - FW_W * 0.5 - 6.0:
		return true
	if r.position.x < FW_X + FW_W * 0.5 + 6.0 and r.end.x > FW_X - FW_W * 0.5 - 6.0:
		return true
	for o in reserved:
		if (o as Rect2).intersects(r):
			return true
	return false


# ================================================================ 地标与商务区
## 带退台的方塔（远景用，不带碰撞）
func _tower(c: Vector3, w: float, d: float, h: float, style: String, tint: Color) -> float:
	var parts := 1 if h < 70.0 else (2 if h < 140.0 else 3)
	var y := 0.0
	for pi in parts:
		var ph := h / parts if pi < parts - 1 else h - y
		var sc := 1.0 - pi * 0.16
		b.box("fac_" + style, c + Vector3(0, y + ph * 0.5, 0), Vector3(w * sc, ph, d * sc), tint, Basis.IDENTITY, true)
		y += ph
		b.box("roof", c + Vector3(0, y + 0.3, 0), Vector3(w * sc + 0.6, 0.6, d * sc + 0.6), Color(1, 1, 1))
	if h > 90.0:
		b.box("metal", c + Vector3(0, y + 4.0, 0), Vector3(w * 0.3, 7.0, d * 0.3), Color(0.5, 0.5, 0.52))
		b.box("neon", c + Vector3(0, y + 8.0, 0), Vector3(0.9, 0.9, 0.9), Color(1, 0.15, 0.2))
	return y


func _landmarks() -> void:
	# 1. 圆柱形摩天楼，顶部三级收分 + 玻璃冠（类似洛杉矶美国银行大厦）
	var c1 := Vector3(-30, 0, -370)
	b.cylinder("fac_glass", c1 + Vector3(0, 110, 0), 24.0, 220.0, Color(0.9, 0.95, 1.0), 24)
	for i in 3:
		var r := 22.0 - i * 4.0
		b.cylinder("fac_office", c1 + Vector3(0, 224 + i * 8, 0), r, 8.0, Color(0.95, 0.93, 0.88), 24)
	b.cylinder("neon", c1 + Vector3(0, 246.5, 0), 10.5, 1.0, Color(0.95, 0.97, 1.0), 24)
	b.cylinder("metal", c1 + Vector3(0, 251, 0), 8.0, 8.0, Color(0.55, 0.56, 0.6), 16, Basis.IDENTITY, 2.0)
	reserved.append(Rect2(c1.x - 30, c1.z - 30, 60, 60))
	# 2. 高耸的方塔，四棱锥顶 + 尖塔（类似威尔希尔大厦）
	var c2 := Vector3(70, 0, -420)
	b.box("fac_glass", c2 + Vector3(0, 140, 0), Vector3(34, 280, 30), Color(0.8, 0.88, 0.98), Basis.IDENTITY, true)
	b.cylinder("fac_glass", c2 + Vector3(0, 292, 0), 24.0, 24.0, Color(0.8, 0.88, 0.98), 4, Basis(Vector3.UP, PI * 0.25), 3.0)
	b.beam("metal", c2 + Vector3(0, 300, 0), c2 + Vector3(0, 336, 0), 0.8, Color(0.75, 0.76, 0.8))
	b.box("neon", c2 + Vector3(0, 337, 0), Vector3(1.2, 1.2, 1.2), Color(1, 0.15, 0.2))
	reserved.append(Rect2(c2.x - 24, c2.z - 22, 48, 44))
	# 3. 深色玻璃方塔，顶部斜切缺口
	var c3 := Vector3(150, 0, -330)
	b.box("fac_cyber", c3 + Vector3(0, 90, 0), Vector3(38, 180, 30), Color(0.7, 0.72, 0.8), Basis.IDENTITY, true)
	b.box("fac_cyber", c3 + Vector3(-9.5, 195, 0), Vector3(19, 30, 30), Color(0.7, 0.72, 0.8), Basis.IDENTITY, true)
	b.box("roof", c3 + Vector3(0, 180.3, 0), Vector3(38.6, 0.6, 30.6), Color(1, 1, 1))
	reserved.append(Rect2(c3.x - 26, c3.z - 22, 52, 44))
	# 4. 双子塔
	for dx in [-20.0, 20.0]:
		var c4 := Vector3(-160 + dx, 0, -330)
		_tower(c4, 22, 22, 175, "office", Color(0.96, 0.94, 0.9))
	reserved.append(Rect2(-195, -350, 70, 40))
	# 5. 在建高楼 + 塔吊
	var c5 := Vector3(-100, 0, -290)
	var built := 118.0
	b.box("solid", c5 + Vector3(0, built * 0.5, 0), Vector3(12, built, 12), Color(0.62, 0.61, 0.58), Basis.IDENTITY, true)
	var floors := int(built / 3.6)
	for f in floors:
		var y := 3.6 * (f + 1)
		b.box("solid", c5 + Vector3(0, y, 0), Vector3(28, 0.35, 28), Color(0.6, 0.59, 0.56))
		if f < floors - 6:
			b.box("fac_glass", c5 + Vector3(0, y - 1.8, 0), Vector3(27.4, 3.2, 27.4), Color(0.85, 0.9, 1.0))
	for sx in [-13.5, 13.5]:
		for sz in [-13.5, 13.5]:
			b.box("solid", c5 + Vector3(sx, built * 0.5, sz), Vector3(0.9, built, 0.9), Color(0.58, 0.57, 0.54))
	_crane(c5 + Vector3(22, 0, 8), 175.0, 0.6)
	reserved.append(Rect2(c5.x - 20, c5.z - 20, 50, 40))


## 塔吊：格构塔身（四根立柱 + 斜撑）、起重臂、平衡臂与配重、司机室、臂端红灯
func _crane(base: Vector3, h: float, yaw: float) -> void:
	var yellow := Color(0.92, 0.7, 0.1)
	var s := 1.1
	for cx in [-s, s]:
		for cz in [-s, s]:
			b.beam("metal", base + Vector3(cx, 0, cz), base + Vector3(cx, h, cz), 0.22, yellow)
	var y := 0.0
	while y < h - 4.0:
		b.beam("metal", base + Vector3(-s, y, -s), base + Vector3(s, y + 4.0, -s), 0.12, yellow)
		b.beam("metal", base + Vector3(s, y, s), base + Vector3(-s, y + 4.0, s), 0.12, yellow)
		b.beam("metal", base + Vector3(-s, y, s), base + Vector3(-s, y + 4.0, -s), 0.12, yellow)
		b.beam("metal", base + Vector3(s, y, -s), base + Vector3(s, y + 4.0, s), 0.12, yellow)
		y += 4.0
	var dir := Vector3(cos(yaw), 0, sin(yaw))
	var top := base + Vector3(0, h, 0)
	b.beam("metal", top - dir * 18.0, top + dir * 62.0, 1.4, yellow)
	b.beam("metal", top + Vector3(0, 1.4, 0) - dir * 18.0, top + Vector3(0, 1.4, 0) + dir * 62.0, 0.3, yellow)
	b.box("solid", top - dir * 16.0 - Vector3(0, 1.8, 0), Vector3(3.2, 3.0, 3.2), Color(0.55, 0.55, 0.55))
	b.box("metal", top + Vector3(0, -2.2, 0) + dir * 2.5, Vector3(2.2, 2.2, 2.2), Color(0.9, 0.9, 0.88))
	b.beam("metal", top + Vector3(0, 1.4, 0), top + Vector3(0, 8.0, 0), 0.5, yellow)
	b.beam("metal", top + Vector3(0, 8.0, 0), top + dir * 40.0 + Vector3(0, 1.4, 0), 0.08, Color(0.2, 0.2, 0.2))
	b.beam("metal", top + Vector3(0, 8.0, 0), top - dir * 16.0 + Vector3(0, 1.4, 0), 0.08, Color(0.2, 0.2, 0.2))
	b.beam("metal", top + dir * 38.0, top + dir * 38.0 - Vector3(0, 40, 0), 0.05, Color(0.15, 0.15, 0.15))
	for p in [top + dir * 62.0, top - dir * 18.0, top + Vector3(0, 8.4, 0)]:
		b.box("neon", p + Vector3(0, 0.9, 0), Vector3(0.7, 0.7, 0.7), Color(1, 0.12, 0.15))


## 商务区：40 米网格，越靠近中心 (0, -380) 越高
func _cbd() -> void:
	var center := Vector2(0, -390)
	var x := CBD.position.x + 20.0
	while x < CBD.end.x:
		var z := CBD.position.y + 20.0
		while z < CBD.end.y:
			var c := Vector3(x + rng.randf_range(-3, 3), 0, z + rng.randf_range(-3, 3))
			var w := rng.randf_range(18.0, 30.0)
			var d := rng.randf_range(18.0, 30.0)
			var r := Rect2(c.x - w * 0.5, c.z - d * 0.5, w, d)
			if Vector2(c.x, c.z).length() < R_MAX and rng.randf() < 0.88 and not _blocked(r):
				var k := clampf(Vector2(c.x, c.z).distance_to(center) / 330.0, 0.0, 1.0)
				var h := lerpf(190.0, 40.0, k) * rng.randf_range(0.55, 1.1)
				var style := BuildingKit.pick_style(rng.randf())
				if style == "cyber":
					style = "glass"
				if h > 110.0 and rng.randf() < 0.55:
					style = "glass"
				_tower(c, w, d, h, style, kit.style_tint(style))
			z += 40.0
		x += 40.0


# ================================================================ 低层城区
func _sprawl() -> void:
	var n := int(R_MAX / PITCH) + 1
	for gx in range(-n, n):
		for gz in range(-n, n):
			var cx := gx * PITCH + PITCH * 0.5
			var cz := gz * PITCH + PITCH * 0.5
			var r := Vector2(cx, cz).length()
			var rect := Rect2(cx - 20.0, cz - 20.0, 40.0, 40.0)
			if r > R_MAX or _blocked(rect) or CBD.intersects(rect):
				continue
			var c := Vector3(cx, 0, cz)
			# 街道：每个街区只铺北边与西边两段，拼起来就是整张路网
			b.box("road", c + Vector3(0, 0.03, -PITCH * 0.5), Vector3(PITCH, 0.05, 8.0), Color(0.95, 0.95, 0.95), Basis.IDENTITY, true)
			b.box("road", c + Vector3(-PITCH * 0.5, 0.032, 0), Vector3(8.0, 0.05, PITCH), Color(0.95, 0.95, 0.95), Basis.IDENTITY, true)
			for k in [-10.0, 10.0]:
				lamps.append(Transform3D(Basis.IDENTITY, c + Vector3(k, 0, -PITCH * 0.5 + 4.6)))
				lamps.append(Transform3D(Basis.IDENTITY, c + Vector3(-PITCH * 0.5 + 4.6, 0, k)))
			# 每隔两条街是一条棕榈大道
			if posmod(gz, 3) == 0:
				for k in [-15.0, 0.0, 15.0]:
					var s := rng.randf_range(0.8, 1.25)
					palms.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), c + Vector3(k, 0, -PITCH * 0.5 + 5.2)))
			var roll := rng.randf()
			if r < 330.0:
				if roll < 0.55:
					_commercial(c)
				elif roll < 0.8:
					_houses(c)
				else:
					_industrial(c)
			else:
				if roll < 0.62:
					_houses(c)
				elif roll < 0.84:
					_commercial(c)
				else:
					_industrial(c)


## 住宅：2×2 块宅基地，每栋一层到两层，双坡屋顶；部分后院有泳池或树
func _houses(c: Vector3) -> void:
	var roofs := [Color(0.55, 0.28, 0.2), Color(0.42, 0.4, 0.4), Color(0.6, 0.36, 0.26), Color(0.3, 0.3, 0.33)]
	for ox in [-9.0, 9.0]:
		for oz in [-9.0, 9.0]:
			if rng.randf() < 0.1:
				continue
			var w := rng.randf_range(8.0, 12.0)
			var d := rng.randf_range(8.0, 11.0)
			var h := rng.randf_range(3.2, 6.6)
			var p := c + Vector3(ox + rng.randf_range(-1, 1), 0, oz + rng.randf_range(-1, 1))
			var tint := kit.style_tint("res")
			b.box("fac_res", p + Vector3(0, h * 0.5, 0), Vector3(w, h, d), tint, Basis.IDENTITY, true)
			var along_x := w >= d
			b.gable_roof("solid", p + Vector3(0, h, 0), w + 0.8, d + 0.8, rng.randf_range(1.6, 2.8), roofs[rng.randi() % roofs.size()], along_x, "fac_res", tint)
			var back := p + Vector3(ox * 0.35, 0, oz * 0.35)
			if rng.randf() < 0.18:
				b.box("water", back + Vector3(0, 0.08, 0), Vector3(3.5, 0.12, 6.0), Color(0.2, 0.6, 0.75))
			elif rng.randf() < 0.35:
				var g := Color(0.2, 0.34, 0.16).lerp(Color(0.3, 0.42, 0.2), rng.randf())
				b.cylinder("solid", back + Vector3(0, 1.2, 0), 0.2, 2.4, Color(0.3, 0.22, 0.16), 5)
				b.cylinder("solid", back + Vector3(0, 3.4, 0), 2.2, 2.6, g, 7, Basis.IDENTITY, 1.0)


## 商业：沿街商铺一排 + 若干多层办公 / 公寓
func _commercial(c: Vector3) -> void:
	var sw := rng.randf_range(24.0, 36.0)
	var sh := rng.randf_range(4.5, 7.0)
	var sp := c + Vector3(0, 0, -11.0)
	b.box("fac_office", sp + Vector3(0, sh * 0.5, 0), Vector3(sw, sh, 12.0), kit.style_tint("office"), Basis.IDENTITY, true)
	b.box("roof", sp + Vector3(0, sh + 0.25, 0), Vector3(sw + 0.4, 0.5, 12.4), Color(1, 1, 1))
	b.box("solid", sp + Vector3(0, sh - 1.2, -6.4), Vector3(sw, 0.9, 0.5), Color.from_hsv(rng.randf(), 0.5, 0.7))
	for i in rng.randi_range(1, 2):
		var w := rng.randf_range(14.0, 20.0)
		var d := rng.randf_range(12.0, 16.0)
		var h := rng.randf_range(10.0, 34.0)
		var p := c + Vector3(-9.0 + i * 18.0, 0, 9.0)
		var style := BuildingKit.pick_style(rng.randf())
		if style == "cyber":
			style = "res"
		b.box("fac_" + style, p + Vector3(0, h * 0.5, 0), Vector3(w, h, d), kit.style_tint(style), Basis.IDENTITY, true)
		b.box("roof", p + Vector3(0, h + 0.25, 0), Vector3(w + 0.4, 0.5, d + 0.4), Color(1, 1, 1))
		if rng.randf() < 0.3:
			b.box("metal", p + Vector3(0, h + 2.5, 0), Vector3(w * 0.7, 3.6, 0.3), Color(0.3, 0.3, 0.32))


## 工业：大仓库 + 卷帘门 + 储罐
func _industrial(c: Vector3) -> void:
	var w := rng.randf_range(28.0, 36.0)
	var d := rng.randf_range(22.0, 32.0)
	var h := rng.randf_range(7.0, 11.0)
	var col := Color(0.66, 0.62, 0.55).lerp(Color(0.55, 0.58, 0.6), rng.randf())
	b.box("solid", c + Vector3(0, h * 0.5, 0), Vector3(w, h, d), col, Basis.IDENTITY, true)
	b.box("roof", c + Vector3(0, h + 0.2, 0), Vector3(w + 0.3, 0.4, d + 0.3), Color(1, 1, 1))
	for k in 4:
		b.box("solid", c + Vector3(-w * 0.35 + k * w * 0.23, 2.2, d * 0.5 + 0.05), Vector3(3.6, 4.2, 0.1), Color(0.3, 0.32, 0.34))
	if rng.randf() < 0.4:
		b.cylinder("metal", c + Vector3(w * 0.5 + 3.0, 5.0, 0), 2.6, 10.0, Color(0.75, 0.75, 0.73), 12)


# ================================================================ 高架快速路
func _freeway(ew: bool) -> void:
	var y := FW_Y_EW if ew else FW_Y_NS
	var along := Vector3(1, 0, 0) if ew else Vector3(0, 0, 1)
	var across := Vector3(0, 0, 1) if ew else Vector3(1, 0, 0)
	var line := FW_Z if ew else FW_X
	var half := sqrt(R_MAX * R_MAX - line * line)
	var center := across * line + Vector3(0, y, 0)
	var length := half * 2.0
	var deck := (Vector3(length, 1.2, FW_W) if ew else Vector3(FW_W, 1.2, length))
	b.box("road", center, deck, Color(0.95, 0.95, 0.95))
	for off in [-FW_W * 0.5 + 0.2, 0.0, FW_W * 0.5 - 0.2]:
		var bs := (Vector3(length, 1.0, 0.4) if ew else Vector3(0.4, 1.0, length))
		b.box("solid", center + across * off + Vector3(0, 1.1, 0), bs, Color(0.66, 0.65, 0.62))
	# 车道虚线
	for off in [-7.6, -3.9, 3.9, 7.6]:
		var t := -half + 6.0
		while t < half:
			var ds := (Vector3(4.0, 0.05, 0.2) if ew else Vector3(0.2, 0.05, 4.0))
			b.box("solid", center + along * t + across * off + Vector3(0, 0.62, 0), ds, Color(0.85, 0.85, 0.8))
			t += 14.0
	# 桥墩：每 36 米一组双柱 + 盖梁；中央隔离带上每 40 米一根双头路灯
	var t2 := -half + 18.0
	while t2 < half:
		var p := along * t2 + across * line
		if not _in_city_square(p, 4.0):
			for sx in [-6.0, 6.0]:
				b.cylinder("solid", p + across * sx + Vector3(0, (y - 0.6) * 0.5, 0), 1.1, y - 0.6, Color(0.62, 0.61, 0.58), 10)
			var cap := (Vector3(1.8, 1.2, FW_W - 4.0) if ew else Vector3(FW_W - 4.0, 1.2, 1.8))
			b.box("solid", p + Vector3(0, y - 1.1, 0), cap, Color(0.6, 0.59, 0.56))
		t2 += 36.0
	var t3 := -half + 20.0
	while t3 < half:
		var lp := along * t3 + across * line + Vector3(0, y + 0.6, 0)
		lamps.append(Transform3D(Basis.IDENTITY, lp + across * 1.2))
		lamps.append(Transform3D(Basis.IDENTITY, lp - across * 1.2))
		t3 += 40.0


func _in_city_square(p: Vector3, margin: float) -> bool:
	return absf(p.x) < CITY + margin and absf(p.z) < CITY + margin


# ================================================================ 铁路货场
func _rail_yard() -> void:
	var half := sqrt(R_MAX * R_MAX - YARD_Z1 * YARD_Z1)
	var zc := (YARD_Z0 + YARD_Z1) * 0.5
	b.box("solid", Vector3(0, 0.08, zc), Vector3(half * 2.0, 0.16, YARD_Z1 - YARD_Z0), Color(0.42, 0.38, 0.34), Basis.IDENTITY, true)
	var tracks := 8
	var cols := [Color(0.55, 0.22, 0.14), Color(0.2, 0.3, 0.45), Color(0.42, 0.42, 0.4), Color(0.6, 0.5, 0.25), Color(0.25, 0.35, 0.28), Color(0.7, 0.7, 0.68)]
	for k in tracks:
		var z := YARD_Z0 + 3.0 + k * ((YARD_Z1 - YARD_Z0 - 6.0) / (tracks - 1))
		for rz in [-0.72, 0.72]:
			b.box("metal", Vector3(0, 0.26, z + rz), Vector3(half * 2.0, 0.16, 0.1), Color(0.35, 0.33, 0.3))
		if rng.randf() < 0.7:
			var cars := rng.randi_range(8, 22)
			var x := rng.randf_range(-half + 20.0, half - cars * 15.5 - 20.0)
			for i in cars:
				var cc: Color = cols[rng.randi() % cols.size()]
				var cp := Vector3(x + i * 15.5, 0, z)
				if rng.randf() < 0.25:
					b.cylinder("metal", cp + Vector3(0, 2.4, 0), 1.45, 14.0, Color(0.2, 0.2, 0.22), 10, Basis(Vector3.FORWARD, PI * 0.5))
				else:
					b.box("solid", cp + Vector3(0, 2.4, 0), Vector3(14.4, 3.6, 3.0), cc)
				b.box("metal", cp + Vector3(0, 0.55, 0), Vector3(14.0, 0.5, 2.4), Color(0.12, 0.12, 0.12))
	var t := -half + 40.0
	while t < half:
		lamps.append(Transform3D(Basis.IDENTITY.scaled(Vector3(1.4, 2.4, 1.4)), Vector3(t, 0, YARD_Z1 + 2.0)))
		t += 70.0


# ================================================================ MultiMesh：路灯与棕榈
func _lamp_mesh() -> Mesh:
	var mb := MeshBatcher.new()
	mb.chunked = false
	# 远处的灯杆细到看不见，只保留灯头（几千盏，省下大量三角形）
	mb.box("lamp_warm", Vector3(0, 7.1, 0), Vector3(0.8, 0.3, 0.8), Color(0.9, 0.9, 0.88))
	return mb.to_mesh()


func _palm_mesh() -> Mesh:
	var mb := MeshBatcher.new()
	mb.chunked = false
	var h := 13.0
	mb.cylinder("solid", Vector3(0, h * 0.5, 0), 0.34, h, Color(0.46, 0.4, 0.33), 5, Basis.IDENTITY, 0.26)
	var top := Vector3(0, h, 0)
	var skirt := BuildingKit._atlas(ProcTex.FOLIAGE_SKIRT, 0.0, 0.0, 1.0, 1.0)
	for k in 4:
		var a0 := TAU * k / 4.0
		var a1 := TAU * (k + 1) / 4.0
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		mb.quad_uv("leaf", top + d0 * 0.8 - Vector3(0, 1.8, 0), top + d1 * 0.8 - Vector3(0, 1.8, 0), top + d1 * 0.55, top + d0 * 0.55, Color(1, 1, 1), skirt)
	var fan := BuildingKit._atlas(ProcTex.FOLIAGE_FAN, 0.0, 0.0, 1.0, 1.0)
	for f in 10:
		var az := TAU * f / 10.0
		var el := deg_to_rad(55.0 - (f % 3) * 40.0)
		var horiz := Vector3(cos(az), 0, sin(az))
		var dir := (horiz * cos(el) + Vector3.UP * sin(el)).normalized()
		var side := horiz.cross(Vector3.UP).normalized()
		var base := top + dir * 0.15
		var tip := base + dir * 4.0
		mb.quad_uv("leaf", base - side * 2.0, base + side * 2.0, tip + side * 2.0, tip - side * 2.0, Color(1, 1, 1), fan)
	return mb.to_mesh()


func _multimesh(parent: Node3D, name: String, mesh: Mesh, xforms: Array) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = name
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)
