class_name MapCanvas
extends Control
## 地图绘制（CityMapWindow 使用）。

const EXTENT := 215.0
var window: CityMapWindow
var _font: Font
var _hits: Array = []   # [{rect, id}]


func _init() -> void:
	_font = UIKit.font()
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(300, 300)


func _process(_d: float) -> void:
	queue_redraw()


func _scale() -> float:
	return minf(size.x, size.y) / (EXTENT * 2.0)


func _to_map(p: Vector3) -> Vector2:
	var s := _scale()
	var origin := size * 0.5
	return origin + Vector2(p.x, p.z) * s


func _draw() -> void:
	_hits.clear()
	var s := _scale()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.02, 0.05, 1.0))
	# 道路
	for r in CityBuilder.ROADS:
		var a := _to_map(Vector3(r, 0, -EXTENT + 10))
		var b := _to_map(Vector3(r, 0, EXTENT - 10))
		draw_line(a, b, Color(0.25, 0.25, 0.32), 10.0 * s + 1.0)
		var c := _to_map(Vector3(-EXTENT + 10, 0, r))
		var d := _to_map(Vector3(EXTENT - 10, 0, r))
		draw_line(c, d, Color(0.25, 0.25, 0.32), 10.0 * s + 1.0)
	# 轨道
	draw_line(_to_map(Vector3(-EXTENT, 0, CityBuilder.TRACK_Z)), _to_map(Vector3(EXTENT, 0, CityBuilder.TRACK_Z)), Color(0.13, 0.9, 1.0, 0.4), 2.0)
	# 地点
	var tracked_loc := ""
	var t := QuestManager.objective_target()
	if String(t.get("kind", "")) in ["location", "spawn"]:
		tracked_loc = String(t.get("id", ""))
	for id in DataDB.ids("locations"):
		var dd := DataDB.location(id)
		var c2: Array = dd["center"]
		var sz: Array = dd["size"]
		var w := float(sz[0])
		var h := float(sz[1])
		if String(dd.get("facing", "s")) in ["e", "w"]:
			var tmp := w
			w = h
			h = tmp
		var tl := _to_map(Vector3(float(c2[0]) - w * 0.5, 0, float(c2[1]) - h * 0.5))
		var rect := Rect2(tl, Vector2(w, h) * s)
		var col := Mats.hex(String(dd.get("neon", "#22e4ff")))
		var ln := GameManager.lookup("loc:" + id) as LocationNode
		var open := ln == null or ln.is_open()
		draw_rect(rect, Color(col.r, col.g, col.b, 0.28 if open else 0.1))
		draw_rect(rect, Color(col.r, col.g, col.b, 0.9 if open else 0.35), false, 2.0 if id == tracked_loc else 1.0)
		var name := String(dd.get("short", dd.get("name", id)))
		var fs := 12 if rect.size.x < 40 else 14
		var tw := _font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var pos := rect.get_center() + Vector2(-tw * 0.5, 5)
		if tw > rect.size.x + 6:
			# 小建筑：名字交错写在上方 / 下方，避免挤在一起
			pos.y = rect.position.y - 4 if (_hits.size() % 2 == 0) else rect.end.y + 13
		draw_string_outline(_font, pos, name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.9))
		draw_string(_font, pos, name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE if open else UIKit.DIM)
		if id == HousingManager.home_location():
			draw_string(_font, rect.position + Vector2(2, 14), "家", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UIKit.GOOD)
		_hits.append({"rect": rect, "id": id})
	# 站点
	for mode_id in ["bus", "metro"]:
		for st in TransportManager.mode(mode_id).get("stops", []):
			var p: Array = st["pos"]
			draw_circle(_to_map(Vector3(float(p[0]), 0, float(p[1]))), 4.0, UIKit.YELLOW if mode_id == "bus" else UIKit.CYAN)
	# 任务目标
	var marker = GameManager.lookup("objective_marker")
	if marker != null and bool(marker.has_target):
		var mp := _to_map(marker.target_pos)
		draw_colored_polygon(PackedVector2Array([mp + Vector2(0, -9), mp + Vector2(9, 0), mp + Vector2(0, 9), mp + Vector2(-9, 0)]), UIKit.MAGENTA)
	# 玩家
	var pl := GameManager.player
	if pl != null:
		var pp := _to_map(pl.global_position)
		var f: Vector3 = pl.call("facing_direction")
		var tip := pp + Vector2(f.x, f.z) * 12.0
		draw_line(pp, tip, UIKit.GOOD, 3.0)
		draw_circle(pp, 6.0, UIKit.GOOD)
		draw_arc(pp, 10.0 + sin(Time.get_ticks_msec() / 250.0) * 2.0, 0, TAU, 24, UIKit.GOOD, 1.5)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for h in _hits:
			if (h["rect"] as Rect2).has_point(event.position):
				window.show_location(String(h["id"]))
				accept_event()
				return
