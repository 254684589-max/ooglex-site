class_name Decor
extends RefCounted
## 场景陈设（2026-10-23 所有者「在所有关卡建筑等场景的基础上美化，更漂亮美观逼真」）：一组用 MeshKit 搭的小物件，
## 各个区域按需摆：纹章旗、挂毯、墙上的盾、兵器架、地毯、烛台、墙上的火把、箱子、木桶、板条箱、麻袋、书架上的书和卷轴。
## 鹭沼村子里的：捕鳗的柳条笼、拴船桩、装泥炭的车（场景美化五）。
## 不用外部素材（网页包不变大）；一个房间的陈设合成一个网格（绘制调用少）。火苗、烛光是自发光（配合泛光），不另加点光源（点光源有画质档的上限）。
## 用法：var d := Decor.new()；d.banner(...)；d.shield(...)……；d.build(parent)。
## 朝向参数 n 是物件「正面朝着的方向」（挂在墙上的就是墙面往屋里的法线，水平单位向量）。

var kit := MeshKit.new()
var mats := {}
var solids: Array = []           # [中心, 尺寸]：箱子、桶这些挡人的东西，build 时加碰撞体（旗、毯子、火把不挡）
var lit: Array = []              # 带光的火把的火苗位置：build 时各加一盏小点光源（每个房间最多两三盏，别的火把只是自发光）


func _cloth(c: Color) -> String:
	var k := "cloth_" + c.to_html(false)
	if not mats.has(k):
		var m := Castle._cloth(c)
		m.roughness = 0.95
		mats[k] = m
	return k


func _solid(c: Color, rough := 0.8, metal := 0.0) -> String:
	var k := "solid_%s_%d_%d" % [c.to_html(false), int(rough * 10), int(metal * 10)]
	if not mats.has(k):
		var m := Castle._flat(c)
		m.roughness = rough
		m.metallic = metal
		mats[k] = m
	return k


func _flame() -> String:
	if not mats.has("flame"):
		var m := Castle._flat(Color("ffb050"), true)
		m.emission_enabled = true
		m.emission = Color("ff9a3a")
		m.emission_energy_multiplier = 2.5
		mats["flame"] = m
	return "flame"


func _wood() -> String:
	if not mats.has("timber"):
		mats["timber"] = Look.mat("timber")
	return "timber"


static func _basis(n: Vector3) -> Basis:
	var nz := Vector3(n.x, 0.0, n.z).normalized()
	return Basis(Vector3.UP.cross(nz), Vector3.UP, nz)


## 纹章旗：横杆两头带球、旗面下摆燕尾、四周压一道边；motif：heron（瓦伦家的黑鹭）/ chevron / cross / plain
func banner(top: Vector3, n: Vector3, w: float, h: float, field: Color, charge: Color, motif := "heron", trim := Color("b89a4a")) -> void:
	var b := _basis(n)
	var c := top - Vector3(0, h * 0.5, 0) + n * 0.02
	var f := _cloth(field)
	var t := _cloth(trim)
	var iron := _solid(Color("2a2a2e"), 0.5, 0.4)
	kit.cylinder(iron, top + n * 0.05 - b.x * (w * 0.5 + 0.12), top + n * 0.05 + b.x * (w * 0.5 + 0.12), 0.02, 0.02, 6)
	for s: float in [-1.0, 1.0]:
		kit.cylinder(_solid(Color("8a6a2a"), 0.4, 0.6), top + n * 0.05 + b.x * s * (w * 0.5 + 0.12), top + n * 0.05 + b.x * s * (w * 0.5 + 0.16), 0.04, 0.04, 6)
	var body_h := h * 0.82
	kit.box(f, c + Vector3(0, (h - body_h) * 0.5, 0), Vector3(w, body_h, 0.02), b)
	var tail := h - body_h
	for s: float in [-1.0, 1.0]:                       # 燕尾：两片往下收尖
		var tc := c + Vector3(0, -body_h * 0.5 + (h - body_h) * 0.5 - tail * 0.5, 0) + b.x * s * w * 0.25
		kit.box(f, tc, Vector3(w * 0.42, tail, 0.02), b * Basis(Vector3.BACK, s * 0.18))
	var face := c + n * 0.012
	kit.box(t, face + Vector3(0, (h - body_h) * 0.5 + body_h * 0.5 - 0.04, 0), Vector3(w, 0.06, 0.01), b)
	for s: float in [-1.0, 1.0]:
		kit.box(t, face + b.x * s * (w * 0.5 - 0.03) + Vector3(0, (h - body_h) * 0.5, 0), Vector3(0.05, body_h, 0.01), b)
	var ch := _cloth(charge)
	var m := face + n * 0.004 + Vector3(0, (h - body_h) * 0.5 + body_h * 0.05, 0)
	var u := minf(w, body_h) * 0.5                    # 图案的尺度
	match motif:
		"heron":                                      # 黑鹭：身子、长颈、头和喙、两条细腿
			kit.box(ch, m + b.x * 0.05 * u * 2 + Vector3(0, -0.05 * u, 0), Vector3(0.55 * u, 0.32 * u, 0.008), b * Basis(Vector3.BACK, -0.35))
			kit.box(ch, m + b.x * -0.22 * u + Vector3(0, 0.3 * u, 0), Vector3(0.09 * u, 0.55 * u, 0.008), b * Basis(Vector3.BACK, 0.35))
			kit.box(ch, m + b.x * -0.3 * u + Vector3(0, 0.62 * u, 0), Vector3(0.16 * u, 0.12 * u, 0.008), b)
			kit.box(ch, m + b.x * -0.5 * u + Vector3(0, 0.6 * u, 0), Vector3(0.3 * u, 0.04 * u, 0.008), b * Basis(Vector3.BACK, -0.12))
			for lx: float in [0.02, 0.16]:
				kit.box(ch, m + b.x * lx * u + Vector3(0, -0.6 * u, 0), Vector3(0.03 * u, 0.75 * u, 0.008), b)
		"chevron":
			for s: float in [-1.0, 1.0]:
				kit.box(ch, m + b.x * s * 0.28 * u, Vector3(0.75 * u, 0.16 * u, 0.008), b * Basis(Vector3.BACK, s * 0.6))
		"cross":
			kit.box(ch, m, Vector3(0.16 * u, 1.4 * u, 0.008), b)
			kit.box(ch, m + Vector3(0, 0.2 * u, 0), Vector3(1.0 * u, 0.16 * u, 0.008), b)
		"beacon":                                     # 厄尔德家：燃烧的烽燧（5.2a）——塔身、塔顶的火盆、三条往上蹿的火舌
			kit.box(ch, m + Vector3(0, -0.25 * u, 0), Vector3(0.32 * u, 0.85 * u, 0.008), b)
			kit.box(ch, m + Vector3(0, 0.2 * u, 0), Vector3(0.6 * u, 0.1 * u, 0.008), b)
			for k in 3:
				var fx := (k - 1) * 0.17 * u
				kit.box(ch, m + b.x * fx + Vector3(0, (0.45 + (0.12 if k == 1 else 0.0)) * u, 0), Vector3(0.1 * u, (0.4 + (0.18 if k == 1 else 0.0)) * u, 0.008), b * Basis(Vector3.BACK, -fx * 1.2 / u))
		"star":                                       # 星铁教会的八角星（坠星）
			for k in 4:
				kit.box(ch, m + n * 0.001 * k, Vector3(0.16 * u, 1.2 * u, 0.008), b * Basis(Vector3.BACK, PI * 0.25 * k))


## 挂毯：横杆、布面、上下两道花边、中间几块色块（像织出来的图案）
func tapestry(center: Vector3, n: Vector3, w: float, h: float, base: Color, accents: Array) -> void:
	var b := _basis(n)
	var c := center + n * 0.02
	kit.cylinder(_wood(), c + Vector3(0, h * 0.5 + 0.04, 0) - b.x * (w * 0.5 + 0.08), c + Vector3(0, h * 0.5 + 0.04, 0) + b.x * (w * 0.5 + 0.08), 0.025, 0.025, 6)
	kit.box(_cloth(base), c, Vector3(w, h, 0.02), b)
	var face := c + n * 0.012
	for s: float in [-1.0, 1.0]:
		kit.box(_cloth(accents[0]), face + Vector3(0, s * (h * 0.5 - 0.1), 0), Vector3(w, 0.08, 0.01), b)
	var cols := 3
	for i in cols:
		for j in 2:
			var a: Color = accents[(i + j) % accents.size()]
			var p := face + b.x * (float(i) - (cols - 1) * 0.5) * (w / cols) + Vector3(0, (float(j) - 0.5) * h * 0.38, 0)
			kit.box(_cloth(a), p, Vector3(w / cols * 0.55, h * 0.24, 0.01), b * Basis(Vector3.BACK, PI / 4 if (i + j) % 2 == 0 else 0.0))


## 墙上的圆盾：木面一色、中间一道竖条另一色（纹章的「竖条」），铁边一圈、中间铁包
func shield(center: Vector3, n: Vector3, r: float, a: Color, c2: Color) -> void:
	var b := _basis(n)
	var c := center + n * 0.03
	var nz := Vector3(n.x, 0.0, n.z).normalized()
	_disk(_solid(a, 0.85), c, b, r, 0.04)
	kit.box(_solid(c2, 0.85), c + nz * 0.024, Vector3(r * 0.55, r * 1.86, 0.008), b)
	var iron := _solid(Color("3a3a3e"), 0.45, 0.5)
	kit.cylinder(iron, c + nz * 0.02, c + nz * 0.09, r * 0.22, r * 0.14, 8)
	for k in 14:
		var ang := TAU * (k + 0.5) / 14.0
		kit.box(iron, c + nz * 0.01 + (b.x * cos(ang) + Vector3.UP * sin(ang)) * r * 0.97, Vector3(0.05, TAU * r / 14.0 + 0.01, 0.05), b * Basis(Vector3.BACK, ang))


## 实心的圆片：一摞横条拼成圆（MeshKit 的圆柱没有封口，从正面看是个圈）。b.x、b.y 是圆面里的两个方向，b.z 是厚度方向
func _disk(k: String, c: Vector3, b: Basis, r: float, t: float, slices := 9) -> void:
	for i in slices:
		var y := -r + (i + 0.5) * 2.0 * r / slices
		var half := sqrt(maxf(r * r - y * y, 0.0))
		kit.box(k, c + b.y * y, Vector3(half * 2.0, 2.0 * r / slices + 0.004, t), b)


## 兵器架：两根立柱、上下两根横杆，插着长枪和剑
func rack(base: Vector3, n: Vector3, w := 1.4) -> void:
	var b := _basis(n)
	var wood := _wood()
	var steel := _solid(Color("9aa2aa"), 0.35, 0.6)
	for s: float in [-1.0, 1.0]:
		kit.box(wood, base + b.x * s * w * 0.5 + Vector3(0, 0.8, 0), Vector3(0.08, 1.6, 0.12), b)
	kit.box(wood, base + Vector3(0, 1.35, 0) + n * 0.05, Vector3(w, 0.06, 0.08), b)
	kit.box(wood, base + Vector3(0, 0.35, 0) + n * 0.05, Vector3(w, 0.06, 0.18), b)
	for i in 4:
		var x := (float(i) - 1.5) * w / 4.5
		var p := base + b.x * x + n * 0.08
		if i % 2 == 0:
			kit.cylinder(wood, p + Vector3(0, 0.36, 0), p + Vector3(0, 2.1, 0), 0.02, 0.02, 5)
			kit.box(steel, p + Vector3(0, 2.2, 0), Vector3(0.05, 0.22, 0.015), b)
		else:
			kit.box(steel, p + Vector3(0, 0.95, 0), Vector3(0.05, 0.85, 0.01), b)
			kit.box(_solid(Color("4a4a4e"), 0.5, 0.4), p + Vector3(0, 1.4, 0), Vector3(0.2, 0.03, 0.03), b)
			kit.box(_solid(Color("3a2a1e"), 0.9), p + Vector3(0, 1.5, 0), Vector3(0.035, 0.18, 0.035), b)


## 地毯：底色、四周一道边、两头流苏（贴地，不挡脚）
func rug(r: Rect2, y: float, base: Color, border: Color) -> void:
	var c := Vector3(r.get_center().x, y + 0.006, r.get_center().y)
	kit.box(_cloth(base), c, Vector3(r.size.x, 0.012, r.size.y))
	var bk := _cloth(border)
	var t := 0.12
	kit.box(bk, c + Vector3(0, 0.004, r.size.y * 0.5 - t * 0.5 - 0.05), Vector3(r.size.x - 0.1, 0.012, t))
	kit.box(bk, c + Vector3(0, 0.004, -r.size.y * 0.5 + t * 0.5 + 0.05), Vector3(r.size.x - 0.1, 0.012, t))
	kit.box(bk, c + Vector3(r.size.x * 0.5 - t * 0.5 - 0.05, 0.004, 0), Vector3(t, 0.012, r.size.y - 0.1))
	kit.box(bk, c + Vector3(-r.size.x * 0.5 + t * 0.5 + 0.05, 0.004, 0), Vector3(t, 0.012, r.size.y - 0.1))
	var long_x := r.size.x >= r.size.y
	var ends := [r.position.x, r.end.x] if long_x else [r.position.y, r.end.y]
	for e: float in ends:
		var p := Vector3(e, y + 0.004, c.z) if long_x else Vector3(c.x, y + 0.004, e)
		kit.box(bk, p, Vector3(0.06, 0.008, r.size.y * 0.9) if long_x else Vector3(r.size.x * 0.9, 0.008, 0.06))


## 一簇蜡烛：粗细高低不一的几根，火苗自发光；dish = 下面垫一只铁盘
func candles(pos: Vector3, count := 3, dish := true) -> void:
	var wax := _solid(Color("e8dcc0"), 0.6)
	if dish:
		kit.cylinder(_solid(Color("3a3a3e"), 0.5, 0.5), pos, pos + Vector3(0, 0.015, 0), 0.09, 0.1, 8)
	for i in count:
		var a := TAU * i / count + 0.4
		var p := pos + Vector3(cos(a), 0, sin(a)) * (0.04 if count > 1 else 0.0)
		var h := 0.08 + 0.05 * ((i * 7) % 3)
		kit.cylinder(wax, p, p + Vector3(0, h, 0), 0.017, 0.016, 6)
		kit.box(_flame(), p + Vector3(0, h + 0.025, 0), Vector3(0.016, 0.04, 0.016))


## 落地的铁烛台：三脚、一根长杆、顶上一只铁盘点着几根蜡烛
func candle_stand(pos: Vector3, h := 1.4) -> void:
	var iron := _solid(Color("2a2a2e"), 0.5, 0.4)
	for k in 3:
		var a := TAU * k / 3.0
		kit.box(iron, pos + Vector3(cos(a) * 0.12, 0.04, sin(a) * 0.12), Vector3(0.26, 0.03, 0.03), Basis(Vector3.UP, -a))
	kit.cylinder(iron, pos, pos + Vector3(0, h, 0), 0.02, 0.018, 6)
	candles(pos + Vector3(0, h, 0), 3, true)


## 墙上的火把：铁托架、木柄、火苗（自发光）；light = 带一盏小点光源（不投影）
func sconce(pos: Vector3, n: Vector3, light := false) -> void:
	var b := _basis(n)
	var iron := _solid(Color("2a2a2e"), 0.5, 0.4)
	kit.box(iron, pos + n * 0.04, Vector3(0.1, 0.16, 0.06), b)
	kit.box(iron, pos + n * 0.14 + Vector3(0, 0.05, 0), Vector3(0.03, 0.03, 0.2), b)
	var top := pos + n * 0.24 + Vector3(0, 0.25, 0)
	kit.cylinder(_wood(), pos + n * 0.2 - Vector3(0, 0.12, 0), top, 0.025, 0.035, 6)
	kit.box(_flame(), top + Vector3(0, 0.1, 0), Vector3(0.1, 0.22, 0.1), b * Basis(Vector3.UP, PI / 4))
	kit.box(_flame(), top + Vector3(0, 0.25, 0), Vector3(0.05, 0.1, 0.05), b)
	if light:
		lit.append(top + Vector3(0, 0.12, 0) + n * 0.1)


## 包铁的木箱（盖子、两道铁箍、锁扣）
func chest(pos: Vector3, yaw: float, size := Vector3(0.9, 0.5, 0.55)) -> void:
	var b := Basis(Vector3.UP, yaw)
	var iron := _solid(Color("3a3a3e"), 0.5, 0.5)
	solids.append([pos + Vector3(0, size.y * 0.5, 0), (b * size).abs()])
	kit.box(_wood(), pos + Vector3(0, size.y * 0.42, 0), Vector3(size.x, size.y * 0.84, size.z), b)
	kit.box(_wood(), pos + Vector3(0, size.y * 0.92, 0), Vector3(size.x + 0.03, size.y * 0.16, size.z + 0.03), b, 1.1, 0.9)
	for s: float in [-0.3, 0.3]:
		kit.box(iron, pos + b * Vector3(s * size.x, size.y * 0.5, 0), Vector3(0.05, size.y * 1.02, size.z + 0.04), b)
	kit.box(iron, pos + b * Vector3(0, size.y * 0.75, size.z * 0.5 + 0.02), Vector3(0.08, 0.1, 0.02), b)


## 木桶：几圈板条和两道铁箍
func barrel(pos: Vector3, h := 0.85, r := 0.3) -> void:
	solids.append([pos + Vector3(0, h * 0.5, 0), Vector3(r * 1.8, h, r * 1.8)])
	kit.cylinder(_wood(), pos, pos + Vector3(0, h * 0.5, 0), r * 0.88, r, 10)
	kit.cylinder(_wood(), pos + Vector3(0, h * 0.5, 0), pos + Vector3(0, h, 0), r, r * 0.88, 10)
	_disk(_wood(), pos + Vector3(0, h - 0.01, 0), Basis(Vector3.RIGHT, Vector3.FORWARD, Vector3.UP), r * 0.86, 0.02, 7)     # 桶盖
	var iron := _solid(Color("2e2e32"), 0.5, 0.5)
	for f: float in [0.18, 0.82]:
		var y := h * f
		kit.cylinder(iron, pos + Vector3(0, y - 0.025, 0), pos + Vector3(0, y + 0.025, 0), r * 0.97, r * 0.97, 10)


## 板条箱
func crate(pos: Vector3, yaw: float, s := 0.6) -> void:
	var b := Basis(Vector3.UP, yaw)
	solids.append([pos + Vector3(0, s * 0.5, 0), Vector3(s * 1.2, s, s * 1.2)])
	kit.box(_wood(), pos + Vector3(0, s * 0.5, 0), Vector3(s, s, s), b, 1.0, 0.7)
	var dark := _solid(Color("3a2a1c"), 0.9)
	for side: Vector3 in [Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(-1, 0, 0)]:
		var o := b * side * (s * 0.5 + 0.005)
		var fb := b * Basis(Vector3.UP, atan2(side.x, side.z))
		kit.box(dark, pos + o + Vector3(0, s * 0.5, 0), Vector3(s * 1.2, 0.05, 0.01), fb * Basis(Vector3.BACK, 0.78))


## 麻袋（粮食、草料）
func sack(pos: Vector3, yaw: float) -> void:
	var k := _cloth(Color("8a7a5a"))
	var b := Basis(Vector3.UP, yaw)
	kit.box(k, pos + Vector3(0, 0.2, 0), Vector3(0.45, 0.4, 0.32), b, 1.0, 0.8)
	kit.box(k, pos + Vector3(0, 0.45, 0), Vector3(0.18, 0.12, 0.14), b * Basis(Vector3.BACK, 0.3))


## 柴堆：靠墙码一垛劈好的木柴（一层层交错），上面一层雪
func woodpile(pos: Vector3, along: Vector3, length := 1.4, h := 0.9, snow := true) -> void:
	var d := Vector3(along.x, 0, along.z).normalized()
	var side := d.cross(Vector3.UP)
	var wood := _wood()
	var end_grain := _solid(Color("8a6a46"), 0.9)
	var rows := int(h / 0.12)
	for r in rows:
		var n := int(length / 0.13)
		for i in n:
			var p := pos + d * (-length * 0.5 + (i + 0.5 + 0.5 * (r % 2)) * length / (n + 0.5)) + Vector3(0, 0.06 + r * 0.115, 0)
			kit.cylinder(wood, p - side * 0.22, p + side * 0.22, 0.06, 0.06, 5)
			kit.box(end_grain, p + side * 0.225, Vector3(0.1, 0.1, 0.004), Basis(d, Vector3.UP, side))
	if snow:
		kit.box(_snow(), pos + Vector3(0, rows * 0.115 + 0.04, 0), Vector3(0.5, 0.05, length) if absf(d.z) > absf(d.x) else Vector3(length, 0.05, 0.5))
	solids.append([pos + Vector3(0, h * 0.5, 0), (Vector3(0.5, h, length) if absf(d.z) > absf(d.x) else Vector3(length, h, 0.5))])


## 手推车：车斗、两只轮子、两根车把，斗里装点东西
func cart(pos: Vector3, yaw: float, load := "sacks") -> void:
	var b := Basis(Vector3.UP, yaw)
	var wood := _wood()
	var dark := _solid(Color("3a2a1c"), 0.9)
	kit.box(wood, pos + b * Vector3(0, 0.62, 0), Vector3(0.95, 0.05, 1.4), b)
	for s: float in [-1.0, 1.0]:
		kit.box(wood, pos + b * Vector3(s * 0.47, 0.78, 0), Vector3(0.04, 0.3, 1.4), b)
		kit.box(wood, pos + b * Vector3(0, 0.78, s * 0.7), Vector3(0.95, 0.3, 0.04), b)
		var hub := pos + b * Vector3(s * 0.56, 0.42, 0.1)
		kit.cylinder(dark, hub - b.x * 0.04 * s, hub + b.x * 0.04 * s, 0.42, 0.42, 12)
		kit.cylinder(wood, hub - b.x * 0.06 * s, hub + b.x * 0.06 * s, 0.07, 0.07, 6)
		kit.box(wood, pos + b * Vector3(s * 0.3, 0.6, -1.15), Vector3(0.05, 0.05, 1.0), b * Basis(Vector3.RIGHT, -0.35))
	kit.box(wood, pos + b * Vector3(0, 0.3, 0.55), Vector3(0.05, 0.6, 0.05), b)        # 歇着时撑地的腿
	if load == "sacks":
		for i in 3:
			sack(pos + b * Vector3(-0.25 + i * 0.25, 0.64, -0.2 + 0.25 * (i % 2)), yaw + i)
	elif load == "peat":                              # 切好的泥炭块，码两层
		if not mats.has("peat"):
			mats["peat"] = Look.mat("peat")
		for i in 6:
			var top := i >= 4
			var x := -0.22 + 0.44 * (i % 2)
			var z := 0.0 if top else -0.22 + 0.44 * (i / 2)
			var tw := Basis(Vector3.UP, 0.08 * (i % 3 - 1))
			kit.box("peat", pos + b * Vector3(x, 0.73 + (0.17 if top else 0.0), z), Vector3(0.4, 0.16, 0.38), b * tw, 0.95, 0.65)
	else:
		for i in 4:
			kit.cylinder(wood, pos + b * Vector3(-0.3 + i * 0.2, 0.72, -0.6), pos + b * Vector3(-0.3 + i * 0.2, 0.72, 0.6), 0.06, 0.06, 5)
	solids.append([pos + Vector3(0, 0.55, 0), (b * Vector3(1.2, 1.1, 1.6)).abs()])


## 草垛：一捆方草，上面一层雪
func hay(pos: Vector3, yaw: float, snow := true) -> void:
	var b := Basis(Vector3.UP, yaw)
	var straw := _solid(Color("b89a5a"), 0.95)
	kit.box(straw, pos + Vector3(0, 0.25, 0), Vector3(1.0, 0.5, 0.6), b, 1.0, 0.75)
	var twine := _solid(Color("6a5232"), 0.9)
	for s: float in [-0.25, 0.25]:
		kit.box(twine, pos + b * Vector3(s, 0.25, 0), Vector3(0.03, 0.52, 0.62), b)
	if snow:
		kit.box(_snow(), pos + Vector3(0, 0.52, 0), Vector3(0.9, 0.04, 0.55), b)
	solids.append([pos + Vector3(0, 0.25, 0), (b * Vector3(1.0, 0.5, 0.6)).abs()])


## 捕鳗的柳条笼：横躺着的一只长笼（口大尾小），三道箍
func creel(pos: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	var willow := _solid(Color("7a6440"), 0.95)
	var band := _solid(Color("4a3a24"), 0.9)
	var a := pos + b * Vector3(0, 0.22, -0.45)
	var e := pos + b * Vector3(0, 0.12, 0.45)
	kit.cylinder(willow, a, e, 0.21, 0.09, 9)
	_disk(willow, a, b, 0.2, 0.02, 7)          # 笼口（里面的倒须看不见，封上）
	for t: float in [0.15, 0.5, 0.85]:
		var c := a.lerp(e, t)
		var r := lerpf(0.215, 0.095, t)
		kit.cylinder(band, c - b.z * 0.015, c + b.z * 0.015, r, r, 9)


## 拴船桩：插在水里的一根粗木桩，比码头面高出一截，顶上绕几圈绳子
func post(pos: Vector3, h := 0.9) -> void:
	var rope := _solid(Color("8a7a5a"), 0.95)
	kit.cylinder(_wood(), Vector3(pos.x, MarshLayout.WATER_Y - 0.8, pos.z), pos + Vector3(0, h, 0), 0.14, 0.12, 7, 0.7)
	for k in 3:
		var y := h - 0.25 + k * 0.06
		kit.cylinder(rope, pos + Vector3(0, y, 0), pos + Vector3(0, y + 0.04, 0), 0.135, 0.135, 8)
	solids.append([pos + Vector3(0, h * 0.5, 0), Vector3(0.3, h, 0.3)])


func _snow() -> String:
	if not mats.has("snow"):
		mats["snow"] = Look.mat("snow")
	return "snow"


## 架子上的书和卷轴：沿着一层隔板排一溜，颜色、高矮不一
func books(start: Vector3, along: Vector3, length: float, seed := 1) -> void:
	var cols := [Color("5a2a22"), Color("2a3a4a"), Color("4a4028"), Color("3a2a1e"), Color("6a5a3a")]
	var x := 0.0
	var i := seed
	var d := along.normalized()
	var b := Basis(d, Vector3.UP, d.cross(Vector3.UP))
	while x < length - 0.08:
		var w := 0.04 + 0.02 * (i % 3)
		var h := 0.2 + 0.05 * ((i * 5) % 4)
		if i % 7 == 3:                                # 卷轴：横着放
			kit.cylinder(_solid(Color("d8c8a0"), 0.9), start + d * (x + 0.02) + Vector3(0, 0.04, 0), start + d * (x + 0.02) + Vector3(0, 0.04, 0) + d.cross(Vector3.UP) * 0.25, 0.035, 0.035, 6)
			w = 0.08
		else:
			kit.box(_solid(cols[i % cols.size()], 0.85), start + d * (x + w * 0.5) + Vector3(0, h * 0.5, 0), Vector3(w, h, 0.18), b)
		x += w + 0.008
		i += 1


func build(parent: Node3D, node_name := "Decor", flicker := true) -> MeshInstance3D:
	var mi := kit.build(mats)
	mi.name = node_name
	parent.add_child(mi)
	for s in solids:
		Castle._solid(parent, s[0], s[1])
	for i in lit.size():
		var l := Tavern.FireLight.new()
		l.name = "Sconce%d" % i
		l.light_color = Color("ff9a48")
		l.base = 1.3
		l.omni_range = 5.0
		l.flicker = flicker
		l.position = lit[i]
		parent.add_child(l)
	return mi
