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
var root: Node3D
## 导航障碍（世界坐标矩形）
var obstacles: Array = []
var rng := RandomNumberGenerator.new()
var lights: Array = []
var _font: Font

## 常用颜色
const C_CONCRETE := Color(0.16, 0.17, 0.2)
const C_CONCRETE2 := Color(0.22, 0.22, 0.26)
const C_DARK := Color(0.07, 0.07, 0.09)
const C_FLOOR := Color(0.22, 0.22, 0.27)
const C_TRIM := Color(0.3, 0.31, 0.36)
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


# ================================================================ 上部体块与窗带
func tower_mass(frame: Dictionary, y0: float, height: float, col: Color, accent: Color, detail := 1) -> void:
	var w: float = frame["w"]
	var d: float = frame["d"]
	lbox(frame, "solid", Vector3(0, y0 + height * 0.5, 0), Vector3(w, height, d), col, false)
	collide(xf(frame, 0, y0 + height * 0.5, 0), Vector3(w, height, d), frame["basis"])
	if height > 12.0:
		occluder(xf(frame, 0, y0 + height * 0.5, 0), Vector3(w - 0.6, height - 0.6, d - 0.6), frame["basis"])
	# 窗带：每层一条，四个面
	var floors := int(height / FLOOR_H)
	var step := 1 if detail >= 1 else 2
	for f in range(0, floors, step):
		var y := y0 + f * FLOOR_H + FLOOR_H * 0.55
		var r := rng.randf()
		var kind := "win_warm" if r < 0.42 else ("win_cool" if r < 0.8 else "solid")
		# 白天是深色玻璃，夜里靠材质自发光亮起
		var wc := Color(0.1, 0.13, 0.19) if kind != "solid" else C_WIN_OFF
		lbox(frame, kind, Vector3(0, y, d * 0.5 + 0.06), Vector3(w * 0.9, 1.3, 0.1), wc, false)
		lbox(frame, kind, Vector3(0, y, -d * 0.5 - 0.06), Vector3(w * 0.9, 1.3, 0.1), wc, false)
		lbox(frame, kind, Vector3(w * 0.5 + 0.06, y, 0), Vector3(0.1, 1.3, d * 0.9), wc, false)
		lbox(frame, kind, Vector3(-w * 0.5 - 0.06, y, 0), Vector3(0.1, 1.3, d * 0.9), wc, false)
	# 转角霓虹竖条
	var top := y0 + height
	for sx in [-1.0, 1.0]:
		lbox(frame, "neon", Vector3(sx * (w * 0.5 + 0.08), y0 + height * 0.5, d * 0.5 + 0.08), Vector3(0.14, height, 0.14), accent, false)
	# 屋顶
	lbox(frame, "solid", Vector3(0, top + 0.3, 0), Vector3(w + 0.4, 0.6, d + 0.4), C_TRIM, false)
	lbox(frame, "neon", Vector3(0, top + 0.62, d * 0.5 + 0.2), Vector3(w + 0.4, 0.08, 0.08), accent, false)
	if detail >= 1:
		lbox(frame, "metal", Vector3(w * 0.2, top + 1.6, -d * 0.15), Vector3(4, 2.4, 3), C_CONCRETE2, false)
		b.beam("metal", xf(frame, -w * 0.3, top, d * 0.2), xf(frame, -w * 0.3, top + 9.0, d * 0.2), 0.25, C_TRIM)
		b.box("neon", xf(frame, -w * 0.3, top + 9.2, d * 0.2), Vector3(0.5, 0.5, 0.5), Color(1, 0.2, 0.3))


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
	b.cylinder("solid", pos + Vector3(0, h * 0.3, 0), 0.18, h * 0.6, Color(0.22, 0.16, 0.12), 6)
	b.cylinder("prop", pos + Vector3(0, h * 0.7, 0), 1.5, h * 0.6, Color(0.08, 0.3, 0.2), 7, Basis.IDENTITY, 0.4)
	b.cylinder("prop", pos + Vector3(0, h * 0.95, 0), 1.1, h * 0.4, Color(0.1, 0.36, 0.24), 7, Basis.IDENTITY, 0.1)
	collide(pos + Vector3(0, 1.5, 0), Vector3(0.4, 3.0, 0.4))


func holo_board(pos: Vector3, yaw: float, size: Vector2, text: String, col: Color) -> void:
	var r := Basis(Vector3.UP, yaw)
	b.box("holo", pos, Vector3(size.x, size.y, 0.05), col * 0.6, r)
	b.box("neon", pos + Vector3(0, size.y * 0.5 + 0.05, 0), Vector3(size.x, 0.1, 0.1), col, r)
	b.box("neon", pos - Vector3(0, size.y * 0.5 + 0.05, 0), Vector3(size.x, 0.1, 0.1), col, r)
	var l := label(text, pos + r * Vector3(0, 0, 0.1), yaw, 96, Color(1.2, 1.2, 1.3), size.y / 3.2 / 96.0 * 1.6, 0)
	l.visibility_range_end = 420.0
