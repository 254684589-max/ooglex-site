class_name SiteMap
extends Control
## M 工地图：俯视示意图，显示建筑、材料区、卸货区、NPC、玩家位置与朝向、当前目标。

const WORLD_RECT := Rect2(Vector2(-68, -76), Vector2(136, 146))

var _canvas: Control
var _font: Font
var _panel: PanelContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIKit.full_rect(self)
	visible = false
	_font = UIKit.font()
	var center := CenterContainer.new()
	UIKit.full_rect(center)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_panel = UIKit.panel(Color(0.06, 0.065, 0.08, 0.94), 14, 16)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(_panel)
	var v := UIKit.vbox(8)
	_panel.add_child(v)
	var head := UIKit.hbox(10)
	v.add_child(head)
	head.add_child(UIKit.label("工地图 · 滨江中心项目", 22, UIKit.YELLOW))
	head.add_child(UIKit.spacer())
	head.add_child(UIKit.label("M 关闭　↑ 为北", 15, UIKit.DIM))
	_canvas = Control.new()
	_canvas.custom_minimum_size = Vector2(520, 540)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_map)
	v.add_child(_canvas)
	var legend := UIKit.label("■ 黄框 = 卸货区　● 白点 = 工友　▲ 你　◆ 当前目标", 14, UIKit.DIM)
	v.add_child(legend)


func toggle() -> void:
	visible = not visible
	if visible:
		var vs := get_viewport_rect().size
		var s := clampf(minf(vs.x - 60.0, (vs.y - 150.0) * 136.0 / 146.0), 240.0, 560.0)
		_canvas.custom_minimum_size = Vector2(s, s * 146.0 / 136.0)
		_canvas.queue_redraw()


func _process(_delta: float) -> void:
	if visible:
		_canvas.queue_redraw()


func _to_map(p: Vector2) -> Vector2:
	var s := _canvas.size
	return Vector2((p.x - WORLD_RECT.position.x) / WORLD_RECT.size.x * s.x, (p.y - WORLD_RECT.position.y) / WORLD_RECT.size.y * s.y)


func _rect_to_map(r: Rect2) -> Rect2:
	var a := _to_map(r.position)
	var b := _to_map(r.position + r.size)
	return Rect2(a, b - a)


func _draw_map() -> void:
	var c := _canvas
	c.draw_rect(Rect2(Vector2.ZERO, c.size), Color(0.36, 0.4, 0.3))
	for f in GameState.map_features:
		var kind := String(f["kind"])
		var r := _rect_to_map(f["rect"])
		var col: Color = f["color"]
		match kind:
			"fence":
				c.draw_rect(r, Color(0.5, 0.44, 0.36))
				c.draw_rect(r, col, false, 3.0)
			"road":
				c.draw_rect(r, col.darkened(0.1))
			"zone":
				c.draw_rect(r, Color(col.r, col.g, col.b, 0.35))
				c.draw_rect(r, col, false, 2.0)
			_:
				c.draw_rect(r, col)
				c.draw_rect(r, Color(0, 0, 0, 0.35), false, 1.0)
	for f in GameState.map_features:
		var fname := String(f["name"])
		if fname == "" or String(f["kind"]) in ["fence", "road"]:
			continue
		var r2 := _rect_to_map(f["rect"])
		var fs := 13
		var tw := _font.get_string_size(fname, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var pos := r2.get_center() + Vector2(-tw * 0.5, 5)
		c.draw_string_outline(_font, pos, fname, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.8))
		c.draw_string(_font, pos, fname, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1))
	# 大门
	var gate := _to_map(Vector2(0, 52))
	c.draw_string_outline(_font, gate + Vector2(-14, 18), "大门", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color(0, 0, 0, 0.8))
	c.draw_string(_font, gate + Vector2(-14, 18), "大门", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UIKit.YELLOW)
	# NPC
	for n in get_tree().get_nodes_in_group("npc"):
		var np := _to_map(Vector2(n.global_position.x, n.global_position.z))
		c.draw_circle(np, 4.0, Color(1, 1, 1, 0.9))
	# 目标
	var obj := GameState.current_objective()
	var target := GameState.lookup(String(obj.get("target", "")))
	if target != null:
		var tp := _to_map(Vector2(target.global_position.x, target.global_position.z))
		var pts := PackedVector2Array([tp + Vector2(0, -9), tp + Vector2(9, 0), tp + Vector2(0, 9), tp + Vector2(-9, 0)])
		c.draw_colored_polygon(pts, UIKit.YELLOW)
		c.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0, 0, 0), 1.5)
	# 玩家
	var p := GameState.player
	if p != null:
		var pp := _to_map(Vector2(p.global_position.x, p.global_position.z))
		var fwd: Vector3 = p.facing_direction()
		var d := Vector2(fwd.x, fwd.z).normalized()
		var side := Vector2(-d.y, d.x)
		var tri := PackedVector2Array([pp + d * 11.0, pp - d * 6.0 + side * 7.0, pp - d * 6.0 - side * 7.0])
		c.draw_colored_polygon(tri, Color(1.0, 0.35, 0.25))
		c.draw_polyline(tri + PackedVector2Array([tri[0]]), Color(1, 1, 1), 1.5)
	# 目标文字
	var text := "目标：" + String(obj.get("text", ""))
	c.draw_string_outline(_font, Vector2(8, c.size.y - 10), text, HORIZONTAL_ALIGNMENT_LEFT, c.size.x - 16, 15, 4, Color(0, 0, 0, 0.85))
	c.draw_string(_font, Vector2(8, c.size.y - 10), text, HORIZONTAL_ALIGNMENT_LEFT, c.size.x - 16, 15, UIKit.YELLOW)
