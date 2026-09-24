class_name BuildingKit
extends RefCounted
## 模块化建筑工具：所有建筑都由「底层可进入的外壳 + 上部体块 + 窗带 + 霓虹招牌 + 室内家具」拼成，
## 统一材质与比例，保证整座城市风格一致。几何体进 MeshBatcher 合批，碰撞体进同一个 StaticBody3D。

const FONT_PATH := "res://assets/fonts/NotoSansSC-WL.ttf"
const WALL_T := 0.4
const FLOOR_H := 3.6

var b: MeshBatcher
## 只在夜里显示的几何体（路灯光斑等）
var night: MeshBatcher
var body: StaticBody3D
var prop_body: StaticBody3D
var root: Node3D
## 导航障碍（世界坐标矩形）
var obstacles: Array = []
var rng := RandomNumberGenerator.new()
var lights: Array = []
var _font: Font

## 常用颜色
const C_CONCRETE := Color(0.3, 0.3, 0.32)
const C_CONCRETE2 := Color(0.46, 0.45, 0.44)
const C_DARK := Color(0.07, 0.07, 0.09)
const C_FLOOR := Color(0.22, 0.22, 0.27)
const C_TRIM := Color(0.5, 0.5, 0.53)
const C_WIN_OFF := Color(0.05, 0.07, 0.1)


func _init(batcher: MeshBatcher, night_batcher: MeshBatcher, static_body: StaticBody3D, parent: Node3D) -> void:
	b = batcher
	night = night_batcher
	body = static_body
	root = parent
	rng.seed = 20880301
	_font = load(FONT_PATH)


# ================================================================ 基础
static func facing_yaw(f: String) -> float:
	match f:
		"n":
			return PI
		"e":
			return PI * 0.5
		"w":
			return -PI * 0.5
	return 0.0


## 建筑本地坐标 → 世界坐标
static func xf(frame: Dictionary, lx: float, y: float, lz: float) -> Vector3:
	var basis: Basis = frame["basis"]
	return (frame["c"] as Vector3) + basis * Vector3(lx, y, lz)


static func make_frame(center: Vector2, size: Vector2, facing: String) -> Dictionary:
	return {"c": Vector3(center.x, 0, center.y), "basis": Basis(Vector3.UP, facing_yaw(facing)), "w": size.x, "d": size.y, "yaw": facing_yaw(facing)}


func collide(center: Vector3, size: Vector3, rot := Basis.IDENTITY) -> void:
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	cs.transform = Transform3D(rot, center)
	body.add_child(cs)


## 细小物体（树干、棕榈）的碰撞：单独放在第 6 层（prop），玩家会被挡住，但相机弹簧臂不会因为它们突然拉近
func collide_prop(center: Vector3, size: Vector3) -> void:
	if prop_body == null:
		prop_body = StaticBody3D.new()
		prop_body.name = "PropCollision"
		prop_body.collision_layer = 32
		prop_body.collision_mask = 0
		if body.get_parent() != null:
			body.get_parent().add_child(prop_body)
		else:
			body.add_child(prop_body)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	cs.position = center
	prop_body.add_child(cs)


## 遮挡体：大楼挡住的东西不渲染（桌面版画质中 / 高时开启遮挡剔除）
func occluder(center: Vector3, size: Vector3, rot := Basis.IDENTITY) -> void:
	# 网页版导出模板没有编译遮挡剔除，不生成遮挡体
	if OS.has_feature("web"):
		return
	var oi := OccluderInstance3D.new()
	var bo := BoxOccluder3D.new()
	bo.size = size
	oi.occluder = bo
	oi.transform = Transform3D(rot, center)
	root.add_child(oi)


func solid(kind: String, center: Vector3, size: Vector3, col: Color, rot := Basis.IDENTITY, with_collision := true) -> void:
	b.box(kind, center, size, col, rot, center.y - size.y * 0.5 < 0.05)
	if with_collision:
		collide(center, size, rot)


## 本地坐标下的方块
func lbox(frame: Dictionary, kind: String, lc: Vector3, size: Vector3, col: Color, with_collision := true) -> void:
	solid(kind, xf(frame, lc.x, lc.y, lc.z), size, col, frame["basis"], with_collision)


func add_obstacle_frame(frame: Dictionary, margin := 0.6) -> void:
	var c: Vector3 = frame["c"]
	var w: float = frame["w"]
	var d: float = frame["d"]
	var yaw: float = frame["yaw"]
	if absf(sin(yaw)) > 0.5:
		var t := w
		w = d
		d = t
	obstacles.append(Rect2(c.x - w * 0.5 - margin, c.z - d * 0.5 - margin, w + margin * 2, d + margin * 2))


func label(text: String, pos: Vector3, yaw: float, font_size := 64, col := Color.WHITE, pixel := 0.012, outline := 8) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = _font
	l.font_size = font_size
	l.pixel_size = pixel
	l.modulate = col
	l.outline_size = outline
	l.outline_modulate = Color(0, 0, 0, 0.75)
	l.position = pos
	l.rotation.y = yaw
	l.double_sided = false
	l.visibility_range_end = 160.0 if font_size < 90 else 320.0
	root.add_child(l)
	return l


func omni(pos: Vector3, col: Color, energy := 1.2, rng_m := 10.0) -> OmniLight3D:
	var o := OmniLight3D.new()
	o.position = pos
	o.light_color = col
	o.light_energy = energy
	o.omni_range = rng_m
	o.shadow_enabled = false
	o.distance_fade_enabled = true
	o.distance_fade_begin = 60.0
	o.distance_fade_length = 20.0
	root.add_child(o)
	lights.append(o)
	return o


# ================================================================ 上部体块（贴图立面）
## 立面风格：玻璃幕墙 / 办公石材 / 住宅 / 赛博深色。窗户、窗框、夜间灯光都在程序贴图里（ProcTex），
## 所以一栋楼只要几个方块：主体（可能分 2~3 段退台）+ 檐口 + 屋顶设备。
static func pick_style(r: float) -> String:
	if r < 0.3:
		return "glass"
	if r < 0.58:
		return "office"
	if r < 0.8:
		return "res"
	return "cyber"


## 立面底色（乘在贴图上）：接近白色的轻微色差，住宅偏暖色系
func style_tint(style: String) -> Color:
	var r := rng.randf()
	match style:
		"glass":
			return Color(0.85, 0.92, 1.0).lerp(Color(1.0, 0.95, 0.9), r)
		"office":
			return Color(1.0, 0.97, 0.9).lerp(Color(0.82, 0.84, 0.88), r)
		"res":
			var pastel := [Color(1.0, 0.9, 0.8), Color(1.0, 0.96, 0.84), Color(0.98, 0.86, 0.84), Color(0.9, 0.92, 0.9), Color(1.0, 1.0, 0.98)]
			return pastel[rng.randi() % pastel.size()]
	return Color(0.9, 0.9, 1.0).lerp(Color(1.0, 0.9, 0.95), r)


func tower_mass(frame: Dictionary, y0: float, height: float, _col: Color, accent: Color, detail := 1, style := "", setback := true) -> void:
	var w: float = frame["w"]
	var d: float = frame["d"]
	if style == "":
		style = pick_style(rng.randf())
	var tint := style_tint(style)
	var kind := "fac_" + style
	collide(xf(frame, 0, y0 + height * 0.5, 0), Vector3(w, height, d), frame["basis"])
	if height > 12.0:
		occluder(xf(frame, 0, y0 + height * 0.5, 0), Vector3(w - 0.6, height - 0.6, d - 0.6), frame["basis"])
	# 退台：高楼分成 2~3 段，越往上越窄
	var tiers: Array = [[1.0, 1.0]]
	if setback and height > 36.0 and rng.randf() < 0.65:
		tiers = [[0.62, 1.0], [0.38, 0.78]]
		if height > 70.0 and rng.randf() < 0.5:
			tiers = [[0.5, 1.0], [0.3, 0.8], [0.2, 0.58]]
	var y := y0
	var tw := w
	var td := d
	for ti in tiers.size():
		var th: float = height * float(tiers[ti][0])
		th = maxf(FLOOR_H, roundf(th / FLOOR_H) * FLOOR_H) if ti < tiers.size() - 1 else maxf(FLOOR_H, y0 + height - y)
		tw = w * float(tiers[ti][1])
		td = d * float(tiers[ti][1])
		b.box(kind, xf(frame, 0, y + th * 0.5, 0), Vector3(tw, th, td), tint, frame["basis"], true)
		y += th
		# 檐口 / 退台处的挑檐
		var ledge := Color(0.62, 0.62, 0.64) if style != "cyber" else Color(0.14, 0.15, 0.18)
		lbox(frame, "solid", Vector3(0, y + 0.2, 0), Vector3(tw + 0.5, 0.4, td + 0.5), ledge, false)
	var top := y + 0.4
	# 赛博风格保留霓虹：转角竖条 + 屋顶边
	if style == "cyber" or (detail >= 1 and rng.randf() < 0.3):
		for sx in [-1.0, 1.0]:
			lbox(frame, "neon", Vector3(sx * (w * 0.5 + 0.08), y0 + height * float(tiers[0][0]) * 0.5, d * 0.5 + 0.08), Vector3(0.14, height * float(tiers[0][0]), 0.14), accent, false)
		lbox(frame, "neon", Vector3(0, top + 0.05, td * 0.5 + 0.25), Vector3(tw + 0.5, 0.08, 0.08), accent, false)
	# 女儿墙
	var pc := Color(0.5, 0.5, 0.52)
	lbox(frame, "solid", Vector3(0, top + 0.5, td * 0.5 - 0.1), Vector3(tw, 1.0, 0.2), pc, false)
	lbox(frame, "solid", Vector3(0, top + 0.5, -td * 0.5 + 0.1), Vector3(tw, 1.0, 0.2), pc, false)
	lbox(frame, "solid", Vector3(tw * 0.5 - 0.1, top + 0.5, 0), Vector3(0.2, 1.0, td), pc, false)
	lbox(frame, "solid", Vector3(-tw * 0.5 + 0.1, top + 0.5, 0), Vector3(0.2, 1.0, td), pc, false)
	if detail < 1:
		return
	rooftop(frame, top, tw, td, style)


## 屋顶设备：空调机组、水箱、电梯机房、天线（带航空障碍灯）；少数玻璃高塔加尖顶
func rooftop(frame: Dictionary, top: float, tw: float, td: float, style: String) -> void:
	var grey := Color(0.55, 0.56, 0.58)
	lbox(frame, "solid", Vector3(-tw * 0.18, top + 1.5, -td * 0.12), Vector3(minf(5.0, tw * 0.35), 3.0, minf(4.0, td * 0.3)), Color(0.45, 0.45, 0.47), false)
	for i in rng.randi_range(1, 3):
		var p := Vector3(rng.randf_range(-0.3, 0.3) * tw, top + 0.6, rng.randf_range(0.05, 0.3) * td)
		lbox(frame, "metal", p, Vector3(2.2, 1.2, 1.4), grey, false)
		lbox(frame, "solid", p + Vector3(0, 0.62, 0), Vector3(1.4, 0.05, 0.9), Color(0.2, 0.2, 0.22), false)
	if style == "res" or rng.randf() < 0.25:
		var tp := xf(frame, tw * 0.25, top, -td * 0.2)
		b.cylinder("solid", tp + Vector3(0, 3.2, 0), 1.3, 2.4, Color(0.42, 0.34, 0.28), 10)
		for k in 4:
			var a := TAU * k / 4.0
			b.beam("metal", tp + Vector3(cos(a) * 1.0, 0, sin(a) * 1.0), tp + Vector3(cos(a) * 1.0, 2.0, sin(a) * 1.0), 0.12, Color(0.25, 0.25, 0.27))
	if style == "glass" and tw > 10.0 and rng.randf() < 0.35:
		var sp := xf(frame, 0, top, 0)
		b.cylinder("metal", sp + Vector3(0, 9.0, 0), 1.0, 18.0, Color(0.7, 0.72, 0.75), 8, Basis.IDENTITY, 0.12)
		b.box("neon", sp + Vector3(0, 18.2, 0), Vector3(0.5, 0.5, 0.5), Color(1, 0.15, 0.2))
	else:
		var ap := xf(frame, tw * 0.3, top, td * 0.25)
		var ah := rng.randf_range(4.0, 10.0)
		b.beam("metal", ap, ap + Vector3(0, ah, 0), 0.18, Color(0.3, 0.3, 0.33))
		b.box("neon", ap + Vector3(0, ah + 0.2, 0), Vector3(0.35, 0.35, 0.35), Color(1, 0.15, 0.2))


## 底层可进入的外壳：三面墙 + 带门洞的正面（玻璃橱窗）+ 天花板
func shell(frame: Dictionary, h0: float, wall_col: Color, door_w := 3.4, glass := true) -> void:
	var w: float = frame["w"]
	var d: float = frame["d"]
	var t := WALL_T
	# 室内地面
	lbox(frame, "solid", Vector3(0, 0.015, 0), Vector3(w - t, 0.03, d - t), C_FLOOR, false)
	# 墙
	lbox(frame, "solid", Vector3(0, h0 * 0.5, -d * 0.5 + t * 0.5), Vector3(w, h0, t), wall_col)
	lbox(frame, "solid", Vector3(-w * 0.5 + t * 0.5, h0 * 0.5, 0), Vector3(t, h0, d), wall_col)
	lbox(frame, "solid", Vector3(w * 0.5 - t * 0.5, h0 * 0.5, 0), Vector3(t, h0, d), wall_col)
	# 正面：门洞两侧
	var seg := (w - door_w) * 0.5
	for sx in [-1.0, 1.0]:
		var cx: float = sx * (door_w * 0.5 + seg * 0.5)
		if glass:
			lbox(frame, "solid", Vector3(cx, 0.35, d * 0.5 - t * 0.5), Vector3(seg, 0.7, t), wall_col, false)
			lbox(frame, "glass", Vector3(cx, (h0 - 0.7) * 0.5 + 0.7, d * 0.5 - t * 0.5), Vector3(seg - 0.1, h0 - 0.7, 0.08), Color(0.3, 0.5, 0.6), false)
			collide(xf(frame, cx, h0 * 0.5, d * 0.5 - t * 0.5), Vector3(seg, h0, t), frame["basis"])
		else:
			lbox(frame, "solid", Vector3(cx, h0 * 0.5, d * 0.5 - t * 0.5), Vector3(seg, h0, t), wall_col)
	# 门楣
	lbox(frame, "solid", Vector3(0, (h0 + 2.9) * 0.5, d * 0.5 - t * 0.5), Vector3(door_w, h0 - 2.9, t), wall_col)
	# 天花板
	lbox(frame, "solid", Vector3(0, h0 + 0.15, 0), Vector3(w, 0.3, d), C_CONCRETE)
	# 室内灯带
	lbox(frame, "neon", Vector3(0, h0 - 0.05, 0), Vector3(w * 0.6, 0.06, 0.3), Color(0.9, 0.95, 1.0), false)


## 招牌：门头上方的发光字 + 英文
func sign(frame: Dictionary, h0: float, name: String, en: String, neon: Color) -> void:
	var w: float = frame["w"]
	var d: float = frame["d"]
	var bw := minf(w * 0.8, maxf(6.0, name.length() * 1.1 + 2.0))
	lbox(frame, "solid", Vector3(0, h0 + 1.1, d * 0.5 + 0.2), Vector3(bw, 1.9, 0.3), C_DARK, false)
	lbox(frame, "neon", Vector3(0, h0 + 0.12, d * 0.5 + 0.38), Vector3(bw, 0.07, 0.07), neon, false)
	lbox(frame, "neon", Vector3(0, h0 + 2.08, d * 0.5 + 0.38), Vector3(bw, 0.07, 0.07), neon, false)
	var yaw: float = frame["yaw"]
	label(name, xf(frame, 0, h0 + 1.35, d * 0.5 + 0.4), yaw, 72, neon * 1.4, 0.013, 10)
	if en != "":
		label(en, xf(frame, 0, h0 + 0.55, d * 0.5 + 0.4), yaw, 36, Color(0.85, 0.9, 1.0), 0.011, 6)
	# 竖向霓虹灯箱
	lbox(frame, "neon", Vector3(w * 0.5 - 0.5, h0 + 3.5, d * 0.5 + 0.5), Vector3(0.5, 4.5, 0.25), neon * 0.8, false)


# ================================================================ 室内家具
func counter(frame: Dictionary, lx: float, lz: float, width: float, col := Color(0.2, 0.2, 0.24), top := Color(0.1, 0.8, 0.9)) -> void:
	lbox(frame, "solid", Vector3(lx, 0.5, lz), Vector3(width, 1.0, 0.8), col)
	lbox(frame, "neon", Vector3(lx, 1.02, lz + 0.41), Vector3(width, 0.04, 0.03), top, false)


func shelf(frame: Dictionary, lx: float, lz: float, length: float, along_z := true) -> void:
	var size := Vector3(0.6, 2.0, length) if along_z else Vector3(length, 2.0, 0.6)
	lbox(frame, "metal", Vector3(lx, 1.0, lz), size, Color(0.25, 0.26, 0.3))
	var n := int(length / 0.7)
	for i in n:
		for level in 3:
			var off := -length * 0.5 + 0.35 + i * 0.7
			var col := Color.from_hsv(rng.randf(), 0.55, 0.85)
			var p := Vector3(lx + (0.0 if along_z else off), 0.5 + level * 0.6, lz + (off if along_z else 0.0))
			lbox(frame, "prop", p, Vector3(0.45, 0.32, 0.45) if along_z else Vector3(0.45, 0.32, 0.45), col, false)


func desk(frame: Dictionary, lx: float, lz: float, screen := Color(0.2, 0.9, 1.0)) -> void:
	lbox(frame, "solid", Vector3(lx, 0.38, lz), Vector3(1.6, 0.76, 0.8), Color(0.22, 0.22, 0.26))
	lbox(frame, "neon", Vector3(lx, 1.05, lz - 0.25), Vector3(0.9, 0.5, 0.05), screen, false)
	lbox(frame, "solid", Vector3(lx, 0.45, lz + 0.7), Vector3(0.5, 0.9, 0.5), Color(0.1, 0.1, 0.12), false)


func plant(frame: Dictionary, lx: float, lz: float) -> void:
	var p := xf(frame, lx, 0, lz)
	b.cylinder("solid", p + Vector3(0, 0.3, 0), 0.3, 0.6, Color(0.2, 0.2, 0.22), 8)
	b.box("prop", p + Vector3(0, 1.0, 0), Vector3(0.7, 0.9, 0.7), Color(0.1, 0.45, 0.25))


func table_set(frame: Dictionary, lx: float, lz: float) -> void:
	lbox(frame, "solid", Vector3(lx, 0.38, lz), Vector3(1.2, 0.76, 1.2), Color(0.3, 0.22, 0.16))
	for s in [Vector2(-0.9, 0), Vector2(0.9, 0)]:
		lbox(frame, "prop", Vector3(lx + s.x, 0.25, lz + s.y), Vector3(0.45, 0.5, 0.45), Color(0.5, 0.15, 0.2), false)


# ================================================================ 街道设施
func streetlight(pos: Vector3, yaw: float, col: Color) -> void:
	var arm := Basis(Vector3.UP, yaw) * Vector3(0, 0, 1.4)
	b.cylinder("metal", pos + Vector3(0, 3.2, 0), 0.09, 6.4, Color(0.2, 0.21, 0.24), 6)
	b.beam("metal", pos + Vector3(0, 6.3, 0), pos + Vector3(0, 6.3, 0) + arm, 0.1, Color(0.2, 0.21, 0.24))
	b.box("neon", pos + Vector3(0, 6.2, 0) + arm, Vector3(0.5, 0.12, 0.5), col)
	night.cylinder("decal", pos + arm + Vector3(0, 0.03, 0), 3.2, 0.02, Color(col.r * 0.35, col.g * 0.35, col.b * 0.35), 10)


func bench(pos: Vector3, yaw: float) -> void:
	var r := Basis(Vector3.UP, yaw)
	b.box("solid", pos + Vector3(0, 0.45, 0), Vector3(1.8, 0.1, 0.6), Color(0.35, 0.25, 0.18), r)
	b.box("metal", pos + r * Vector3(0, 0.75, -0.28), Vector3(1.8, 0.5, 0.08), Color(0.35, 0.25, 0.18), r)
	b.box("metal", pos + Vector3(0, 0.22, 0), Vector3(1.6, 0.44, 0.4), Color(0.15, 0.15, 0.17), r)


func tree(pos: Vector3, h := 5.0) -> void:
	b.cylinder("solid", pos + Vector3(0, h * 0.3, 0), 0.18, h * 0.6, Color(0.3, 0.22, 0.16), 6)
	# 圆润的阔叶树冠：三段圆台叠成近似球体，每棵树的绿色略有不同
	var g := Color(0.16, 0.32, 0.14).lerp(Color(0.28, 0.4, 0.16), rng.randf())
	var r := rng.randf_range(1.5, 2.1)
	var cy := h * 0.72
	b.cylinder("prop", pos + Vector3(0, cy - r * 0.45, 0), r * 0.55, r * 0.5, g.darkened(0.15), 9, Basis.IDENTITY, r)
	b.cylinder("prop", pos + Vector3(0, cy + r * 0.1, 0), r, r * 0.6, g, 9)
	b.cylinder("prop", pos + Vector3(0, cy + r * 0.65, 0), r, r * 0.5, g.lightened(0.08), 9, Basis.IDENTITY, r * 0.45)
	collide_prop(pos + Vector3(0, 1.5, 0), Vector3(0.4, 3.0, 0.4))


## 棕榈树：略弯的分段树干 + 一圈下垂的羽状叶（贴图面片，双面）
func palm(pos: Vector3, h := 9.0) -> void:
	var lean := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized() * rng.randf_range(0.3, 1.2)
	var segs := 5
	var prev := pos
	for i in segs:
		var t := float(i + 1) / segs
		var p := pos + Vector3(0, h * t, 0) + lean * t * t
		b.beam("solid", prev, p, lerpf(0.42, 0.28, t), Color(0.42, 0.36, 0.28).darkened(0.1 * (i % 2)))
		prev = p
	var top := prev
	b.box("prop", top + Vector3(0, 0.1, 0), Vector3(0.7, 0.6, 0.7), Color(0.3, 0.34, 0.14))
	var fronds := 9
	var base_a := rng.randf() * TAU
	var uv_in := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 0.5), Vector2(0, 0.5)])
	var uv_out := PackedVector2Array([Vector2(0, 0.5), Vector2(1, 0.5), Vector2(1, 1), Vector2(0, 1)])
	for f in fronds:
		var a := base_a + TAU * f / fronds + rng.randf_range(-0.15, 0.15)
		var dir := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-dir.z, 0, dir.x)
		var length := rng.randf_range(3.6, 4.8)
		var width := 1.3
		var up := rng.randf_range(0.3, 0.8)
		var p0 := top
		var p1 := top + dir * length * 0.5 + Vector3(0, up, 0)
		var p2 := top + dir * length + Vector3(0, up - rng.randf_range(1.6, 2.6), 0)
		# 叶片沿长度方向微微向下卷：两侧边缘比中脉低
		var sag := Vector3(0, -0.25, 0)
		var col := Color(1, 1, 1).darkened(rng.randf() * 0.25)
		b.quad_uv("leaf", p0 - side * width * 0.2, p0 + side * width * 0.2, p1 + side * width * 0.5 + sag, p1 - side * width * 0.5 + sag, col, uv_in)
		b.quad_uv("leaf", p1 - side * width * 0.5 + sag, p1 + side * width * 0.5 + sag, p2 + side * width * 0.15, p2 - side * width * 0.15, col, uv_out)
	collide_prop(pos + Vector3(0, 1.5, 0), Vector3(0.5, 3.0, 0.5))


## 汽车（停在路边的静态车，或 StreetTraffic 里行驶的车共用同一套几何体）。原点在车底中心，车头朝 -Z
static func car_geometry(mb: MeshBatcher, origin: Vector3, basis: Basis, paint: Color, kind := "metal") -> void:
	var glass := Color(0.08, 0.1, 0.13)
	mb.box(kind, origin + basis * Vector3(0, 0.62, 0), Vector3(1.86, 0.62, 4.4), paint, basis)
	mb.box(kind, origin + basis * Vector3(0, 0.95, -1.55), Vector3(1.8, 0.1, 1.1), paint, basis)
	# 车舱：四棱台（上窄下宽，前后挡风玻璃是斜的）
	var cab := basis * Basis.from_scale(Vector3(1.174, 1.0, 1.84)) * Basis(Vector3.UP, PI * 0.25)
	mb.cylinder(kind, origin + basis * Vector3(0, 1.24, 0.25), 1.0, 0.62, glass, 4, cab, 0.72)
	mb.box(kind, origin + basis * Vector3(0, 1.56, 0.25), Vector3(1.22, 0.05, 1.8), paint, basis)
	mb.box(kind, origin + basis * Vector3(0, 0.34, -2.21), Vector3(1.8, 0.22, 0.06), Color(0.12, 0.12, 0.13), basis)
	var wheel := basis * Basis(Vector3.FORWARD, PI * 0.5)
	for wx in [-0.86, 0.86]:
		for wz in [-1.38, 1.38]:
			mb.cylinder(kind, origin + basis * Vector3(wx, 0.36, wz), 0.36, 0.26, Color(0.05, 0.05, 0.06), 10, wheel)
	for sx in [-0.62, 0.62]:
		mb.box("neon", origin + basis * Vector3(sx, 0.72, -2.21), Vector3(0.42, 0.14, 0.04), Color(1.0, 0.96, 0.85), basis)
		mb.box("neon", origin + basis * Vector3(sx, 0.78, 2.21), Vector3(0.4, 0.12, 0.04), Color(0.9, 0.06, 0.1), basis)


func holo_board(pos: Vector3, yaw: float, size: Vector2, text: String, col: Color) -> void:
	var r := Basis(Vector3.UP, yaw)
	b.box("holo", pos, Vector3(size.x, size.y, 0.05), col * 0.6, r)
	b.box("neon", pos + Vector3(0, size.y * 0.5 + 0.05, 0), Vector3(size.x, 0.1, 0.1), col, r)
	b.box("neon", pos - Vector3(0, size.y * 0.5 + 0.05, 0), Vector3(size.x, 0.1, 0.1), col, r)
	var l := label(text, pos + r * Vector3(0, 0, 0.1), yaw, 96, Color(1.2, 1.2, 1.3), size.y / 3.2 / 96.0 * 1.6, 0)
	l.visibility_range_end = 420.0
