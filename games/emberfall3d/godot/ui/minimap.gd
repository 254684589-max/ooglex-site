class_name Minimap
extends Control
## 小地图与自动地图（P8，移植 V0.1 drawMinimap）：画到过的格子（Fog.seen）里的墙、楼梯、传送石 / 传送门、镇上的人、
## 视野内的怪物与主角。方向与镜头一致（屏幕上方 = 镜头朝向），纵向略压扁，看起来和斜视角的画面一样。
##   小地图：右上角按钮下方，电脑 160 × 110、手机 110 × 80；
##   自动地图（Tab / 「地图」按钮）：铺满全屏的半透明地图，不暂停（V0.1 同）。
## 每秒重画约 10 次（格子多，不必每帧画）。

const SQUASH := 0.75

var main: Node                  # scenes/main.gd：取楼层格子、视野、主角、镜头、楼梯、NPC、怪物
var big := false
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	process_mode = Node.PROCESS_MODE_ALWAYS


func set_big(b: bool) -> void:
	big = b
	layout()
	queue_redraw()


func layout() -> void:
	var vs := get_viewport_rect().size
	if big:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		offset_left = 0
		offset_top = 0
		offset_right = 0
		offset_bottom = 0
	else:
		var small := vs.x < 640
		var sz := Vector2(110, 80) if small else Vector2(160, 110)
		anchor_left = 1.0
		anchor_right = 1.0
		anchor_top = 0.0
		anchor_bottom = 0.0
		offset_right = -16
		offset_left = -16 - sz.x
		offset_top = 64
		offset_bottom = 64 + sz.y


func _process(delta: float) -> void:
	_t -= delta
	if _t <= 0.0:
		_t = 0.1
		queue_redraw()


## 每米多少像素
func px_per_m() -> float:
	var vs := get_viewport_rect().size
	if big:
		return clampf(minf(vs.x, vs.y) / 90.0, 3.0, 6.0) * 0.75
	return 1.2 if vs.x < 640 else 1.6


## 世界坐标 → 本控件内的像素坐标（以主角为中心）
func project(p: Vector3) -> Vector2:
	var cam: Camera3D = main.camera
	var hero: Node3D = main.hero
	var b := cam.global_transform.basis
	var right := Vector2(b.x.x, b.x.z).normalized()
	var fwd := Vector2(-b.z.x, -b.z.z).normalized()
	var d := Vector2(p.x - hero.global_position.x, p.z - hero.global_position.z)
	var k := px_per_m()
	return size / 2.0 + Vector2(d.dot(right), -d.dot(fwd) * SQUASH) * k


func _draw() -> void:
	if main == null or main.hero == null or main.camera == null:
		return
	var m: Dictionary = main.map_grid()
	if big:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.55))
	else:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.5))
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.79, 0.64, 0.35, 0.35), false, 1.0)
	var k := px_per_m()
	var cell := DungeonBuilder.TILE * k
	var clip := Rect2(Vector2(-cell, -cell), size + Vector2(cell, cell) * 2)
	if not m.is_empty():
		var seen: PackedByteArray = main.seen
		var town: bool = m.get("theme", "") == "town"
		var wall_c := Color(0.78, 0.67, 0.47, 0.8 if big else 0.7)
		var ws := Vector2(cell * 0.75, cell * 0.75 * SQUASH)
		for y in m.h:
			for x in m.w:
				var i: int = y * m.w + x
				if seen.size() > i and not seen[i]:
					continue
				var tt: int = m.t[i]
				if tt == DungeonGen.WALL or (tt == TownGen.TREE and not town):
					var sp := project(DungeonBuilder.cell_center(Vector2i(x, y)))
					if clip.has_point(sp):
						draw_rect(Rect2(sp - ws / 2, ws), wall_c)
				elif tt == DungeonGen.DOWN or tt == DungeonGen.UP:
					_dot(project(DungeonBuilder.cell_center(Vector2i(x, y))), Color(1.0, 0.82, 0.29), 2.5)
	for s in main.get_tree().get_nodes_in_group("interact"):
		if s.kind in ["wp", "portal"]:
			_dot(project(s.global_position), Color(0.42, 0.78, 1.0), 2.5)
	for n in main.npcs:
		if is_instance_valid(n):
			_dot(project(n.global_position), Color(0.79, 0.64, 0.35), 2.0)
	for e in main.monsters:
		if is_instance_valid(e) and not e.dead and main.cell_visible(e.global_position):
			_dot(project(e.global_position), Color(1.0, 0.54, 0.16) if e.def.get("boss", false) else Color(0.88, 0.25, 0.16), 1.6)
	draw_circle(size / 2.0, 4.0 if big else 2.6, Color.WHITE)
	if big:
		var f: Font = get_theme_default_font()
		var txt: String = "%s · 自动地图（按 Tab 或点「地图」关闭）" % main.floor_title()
		var fs := 15
		var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		if w > size.x - 24:
			txt = "自动地图（点「地图」关闭）"
			w = f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, Vector2((size.x - w) / 2.0, size.y / 2.0 + 130.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.79, 0.64, 0.35))


func _dot(p: Vector2, c: Color, r: float) -> void:
	if Rect2(Vector2.ZERO, size).has_point(p):
		draw_rect(Rect2(p - Vector2(r, r), Vector2(r, r) * 2), c)
