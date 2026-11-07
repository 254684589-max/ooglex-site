class_name SwordKit
extends RefCounted
## 主角的剑（路线图 C.3；所有者 2026-11-07「帮我挑一下主角手中的剑，选4个看看」→「所有剑保留，让玩家自行选择，一开始先设定一把剑」）。
## 四种样式都是代码建模的原创形制（不用外部模型）：武装剑（开局）、手半剑、法尔钦弯刀、北境长刀；在「角色」面板里换（GameState.sword_style，存档里有）。
## 只换外观，伤害、手感照旧（剑的数值还是看背包里装备的那一把）。
## 剑身按截面放样（双刃带血槽 / 单刃），护手、缠绳握柄、剑首。材质槽记在顶点色里（红 = 钢、绿 = 铁、蓝 = 握柄），shaders/sword.gdshader 按它上色。
## 本地坐标：握柄中心在原点附近，剑尖朝 +Y，刃朝 ±X，剑面朝 ±Z（同 WeaponView、Avatar 原来的剑：护手在 y = 0.08）。

const DESIGNS := ["arming", "longsword", "falchion", "messer"]
const NAMES := {"arming": "武装剑", "longsword": "手半剑", "falchion": "法尔钦弯刀", "messer": "北境长刀"}
const DESCS := {"arming": "单手剑，直护手、轮形剑首，剑身带血槽：骑士最常佩的那种。", "longsword": "更长更尖的手半剑，护手两头往剑尖弯，握柄能单手也能双手。",
	"falchion": "单刃，越往刀头越宽，劈砍有力：佣兵和平民手里常见。", "messer": "单刃微弯的长刀，护手一侧一根护钉，木片夹柄：北境人用的。"}
const DEFAULT := "arming"

static var _cache := {}
static var _mats := {}


## 这一种样式的网格（做一次就缓存）
static func mesh(design: String) -> ArrayMesh:
	var d := design if design in DESIGNS else DEFAULT
	if not _cache.has(d):
		_cache[d] = build(d)
	return _cache[d]


## 按顶点色上色的材质；glow = 一点点自发光（第一人称背光时剑不变成一根黑棍，同原来的剑）
static func material(glow := 0.0) -> ShaderMaterial:
	var key := str(glow)
	if not _mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/sword.gdshader")
		m.set_shader_parameter("glow", glow)
		_mats[key] = m
	return _mats[key]


static func build(design: String) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mats := []
	match design:
		"arming":
			# 剑身 76 厘米，根部 5 厘米宽，渐收到尖；全长血槽；直护手；轮形剑首
			_blade(st, 0.09, 0.76, [[0.0, 0.026], [0.6, 0.022], [0.88, 0.017], [1.0, 0.0]], 0.0055, true, false)
			_bar(st, Vector3(-0.11, 0.075, 0), Vector3(0.11, 0.075, 0), 0.011, 0.009)
			_grip(st, 0.06, -0.06, 0.016, 7)
			_disk(st, Vector3(0, -0.085, 0), 0.03, 0.016)
		"longsword":
			# 剑身 90 厘米，更窄更尖（刺甲缝）；护手两头往剑尖弯；长握柄（双手）；梨形剑首
			_blade(st, 0.09, 0.9, [[0.0, 0.025], [0.45, 0.02], [0.85, 0.013], [1.0, 0.0]], 0.0065, true, false)
			_curved_bar(st, 0.075, 0.14, 0.018, 0.01)
			_grip(st, 0.06, -0.15, 0.015, 11)
			_pear(st, Vector3(0, -0.175, 0), 0.024)
		"falchion":
			# 单刃，刀身往刀尖变宽、尖头斜切（劈砍）；短直护手；平头剑首
			_blade(st, 0.09, 0.66, [[0.0, 0.022], [0.55, 0.031], [0.82, 0.04], [1.0, 0.0]], 0.006, false, true)
			_bar(st, Vector3(-0.08, 0.075, 0), Vector3(0.08, 0.075, 0), 0.012, 0.012)
			_grip(st, 0.06, -0.06, 0.017, 6)
			_box(st, Vector3(0, -0.08, 0), Vector3(0.04, 0.025, 0.026))
		"messer":
			# 单刃略弯的长刀，护手一侧有一根护钉；木片夹柄；剑首往刃那边弯
			_blade(st, 0.09, 0.78, [[0.0, 0.022], [0.7, 0.02], [0.9, 0.014], [1.0, 0.0]], 0.0055, false, true, 0.035)
			_bar(st, Vector3(-0.08, 0.075, 0), Vector3(0.08, 0.075, 0), 0.01, 0.01)
			_bar(st, Vector3(0, 0.075, 0.004), Vector3(0, 0.075, 0.05), 0.006, 0.006)        # 护钉
			_grip(st, 0.06, -0.1, 0.017, 0)
			_box(st, Vector3(0.012, -0.115, 0), Vector3(0.045, 0.022, 0.026))
	st.generate_normals()
	return st.commit()


## 剑身：从 y0 到 y0 + length 放样；profile = [[0..1, 半宽], …]；t = 剑脊厚度的一半；fuller = 双刃中间的血槽；single = 单刃（刀背在 -X）；curve = 刀尖往 +X 偏多少米（弯刀）
static func _blade(st: SurfaceTool, y0: float, length: float, profile: Array, t: float, fuller: bool, single: bool, curve := 0.0) -> void:
	var n := 40
	var rings := []
	for i in n + 1:
		var u := float(i) / n
		var w := _lerp_profile(profile, u)
		var tt := t * (1.0 - 0.75 * u * u)
		var y := y0 + u * length
		var off := curve * u * u
		var ring := []
		if single:
			# 刀背（-X，厚）→ 两面 → 刃（+X，薄）
			ring = [Vector2(-w, tt * 0.9), Vector2(-w * 0.2, tt), Vector2(w * 0.55, tt * 0.55), Vector2(w, 0.0005),
				Vector2(w * 0.55, -tt * 0.55), Vector2(-w * 0.2, -tt), Vector2(-w, -tt * 0.9)]
		elif fuller and u < 0.7:
			var f := 0.55
			ring = [Vector2(-w, 0.0004), Vector2(-w * 0.55, tt * 0.8), Vector2(-w * 0.22, tt), Vector2(0, tt * f), Vector2(w * 0.22, tt), Vector2(w * 0.55, tt * 0.8), Vector2(w, 0.0004),
				Vector2(w * 0.55, -tt * 0.8), Vector2(w * 0.22, -tt), Vector2(0, -tt * f), Vector2(-w * 0.22, -tt), Vector2(-w * 0.55, -tt * 0.8)]
		else:
			ring = [Vector2(-w, 0.0004), Vector2(-w * 0.55, tt * 0.8), Vector2(-w * 0.22, tt), Vector2(0, tt), Vector2(w * 0.22, tt), Vector2(w * 0.55, tt * 0.8), Vector2(w, 0.0004),
				Vector2(w * 0.55, -tt * 0.8), Vector2(w * 0.22, -tt), Vector2(0, -tt), Vector2(-w * 0.22, -tt), Vector2(-w * 0.55, -tt * 0.8)]
		rings.append([y, off, ring])
	# 截面点数可能前后不一样（血槽到 0.7 为止，点数相同：都是 12 点），单刃 7 点
	for i in n:
		var a: Array = rings[i]
		var b: Array = rings[i + 1]
		var ra: Array = a[2]
		var rb: Array = b[2]
		var m := ra.size()
		for k in m:
			var k2 := (k + 1) % m
			var p0 := Vector3(ra[k].x + a[1], a[0], ra[k].y)
			var p1 := Vector3(ra[k2].x + a[1], a[0], ra[k2].y)
			var q0 := Vector3(rb[k].x + b[1], b[0], rb[k].y)
			var q1 := Vector3(rb[k2].x + b[1], b[0], rb[k2].y)
			_quad(st, p0, p1, q1, q0, 0)
	# 剑根封口
	var r0: Array = rings[0][2]
	for k in range(1, r0.size() - 1):
		_tri(st, Vector3(r0[0].x, y0, r0[0].y), Vector3(r0[k + 1].x, y0, r0[k + 1].y), Vector3(r0[k].x, y0, r0[k].y), 0)


static func _lerp_profile(profile: Array, u: float) -> float:
	for i in profile.size() - 1:
		var a: Array = profile[i]
		var b: Array = profile[i + 1]
		if u <= float(b[0]):
			var k := (u - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.0001)
			if i == profile.size() - 2:
				return float(a[1]) * pow(1.0 - k, 0.75)     # 最后一段：剑尖两边鼓着收拢（不是一根针）
			return lerpf(float(a[1]), float(b[1]), k)
	return 0.0


## 直护手：两头稍粗
static func _bar(st: SurfaceTool, a: Vector3, b: Vector3, ry: float, rz: float) -> void:
	_tube(st, [a, a.lerp(b, 0.5), b], [ry * 1.15, ry * 0.85, ry * 1.15], rz / ry, 1)


## 往剑尖弯的护手
static func _curved_bar(st: SurfaceTool, y: float, half: float, lift: float, r: float) -> void:
	var pts := []
	var rs := []
	for i in 9:
		var x := lerpf(-half, half, i / 8.0)
		pts.append(Vector3(x, y + lift * pow(absf(x) / half, 2.0), 0))
		rs.append(r * (1.2 if i in [0, 8] else 1.0))
	_tube(st, pts, rs, 0.9, 1)


## 握柄：缠绳（每一圈一道细细的起伏）；wraps = 0 是木片夹柄（扁一点、两颗铆钉）
static func _grip(st: SurfaceTool, top: float, bottom: float, r: float, wraps: int) -> void:
	var pts := []
	var rs := []
	var n := maxi(wraps * 2, 6)
	for i in n + 1:
		var u := float(i) / n
		pts.append(Vector3(0, lerpf(top, bottom, u), 0))
		var bulge := 1.0 + 0.12 * sin(u * PI)
		rs.append(r * bulge * ((0.9 if i % 2 == 1 else 1.0) if wraps > 0 else 1.0))
	_tube(st, pts, rs, 1.0 if wraps > 0 else 0.62, 2)
	if wraps == 0:
		for y in [lerpf(top, bottom, 0.3), lerpf(top, bottom, 0.7)]:
			_disk(st, Vector3(0, y, 0), 0.006, 0.026)


## 轮形剑首（扁圆盘，面朝 ±Z）
static func _disk(st: SurfaceTool, c: Vector3, r: float, depth: float) -> void:
	var n := 16
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var p0 := c + Vector3(cos(a0) * r, sin(a0) * r, 0)
		var p1 := c + Vector3(cos(a1) * r, sin(a1) * r, 0)
		var dz := Vector3(0, 0, depth * 0.5)
		_quad(st, p0 - dz, p1 - dz, p1 + dz, p0 + dz, 1)
		_tri(st, c + dz, p0 + dz, p1 + dz, 1)
		_tri(st, c - dz, p1 - dz, p0 - dz, 1)


## 梨形剑首
static func _pear(st: SurfaceTool, c: Vector3, r: float) -> void:
	var pts := []
	var rs := []
	for i in 9:
		var u := float(i) / 8.0
		pts.append(c + Vector3(0, lerpf(0.035, -0.03, u), 0))
		rs.append(r * sin(PI * (0.08 + 0.92 * u)) * (0.7 + 0.3 * u))
	_tube(st, pts, rs, 1.0, 1)


static func _box(st: SurfaceTool, c: Vector3, s: Vector3) -> void:
	var h := s * 0.5
	var v := [Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, 1, -1), Vector3(-1, 1, -1), Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(-1, 1, 1)]
	var f := [[0, 1, 2, 3], [5, 4, 7, 6], [4, 0, 3, 7], [1, 5, 6, 2], [3, 2, 6, 7], [4, 5, 1, 0]]
	for q: Array in f:
		_quad(st, c + v[q[0]] * h, c + v[q[1]] * h, c + v[q[2]] * h, c + v[q[3]] * h, 1)


## 一根沿折线走的管子（截面是椭圆：z 方向按 zk 压扁）
static func _tube(st: SurfaceTool, pts: Array, rs: Array, zk: float, mat: int) -> void:
	var seg := 10
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var d := (b - a).normalized()
		var side := Vector3(0, 0, 1)
		var up := d.cross(side).normalized()
		for k in seg:
			var a0 := TAU * k / seg
			var a1 := TAU * (k + 1) / seg
			var o0 := up * cos(a0) + side * sin(a0) * zk
			var o1 := up * cos(a1) + side * sin(a1) * zk
			_quad(st, a + o0 * float(rs[i]), a + o1 * float(rs[i]), b + o1 * float(rs[i + 1]), b + o0 * float(rs[i + 1]), mat)
	for e in [[pts[0], rs[0], -1.0], [pts[pts.size() - 1], rs[rs.size() - 1], 1.0]]:
		var c: Vector3 = e[0]
		var d2: Vector3 = ((pts[1] - pts[0]) if e[2] < 0 else (pts[pts.size() - 1] - pts[pts.size() - 2])).normalized()
		var up2: Vector3 = d2.cross(Vector3(0, 0, 1)).normalized()
		for k in seg:
			var a0 := TAU * k / seg
			var a1 := TAU * (k + 1) / seg
			_tri(st, c, c + (up2 * cos(a0) + Vector3(0, 0, sin(a0) * zk)) * float(e[1]), c + (up2 * cos(a1) + Vector3(0, 0, sin(a1) * zk)) * float(e[1]), mat)


## 材质槽用顶点色记：0 钢，1 铁 / 铜，2 握柄
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, mat: int) -> void:
	_tri(st, a, b, c, mat)
	_tri(st, a, c, d, mat)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, mat: int) -> void:
	var col: Color = [Color(1, 0, 0), Color(0, 1, 0), Color(0, 0, 1)][mat]
	for p in [a, b, c]:
		st.set_color(col)
		st.add_vertex(p)
