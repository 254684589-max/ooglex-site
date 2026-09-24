class_name ChartView
extends Control
## 简单折线图：用于投资 APP 的价格走势、金融分析小游戏、创业 APP 的收支。
## 带纵轴最小 / 最大值、单位、时间范围说明；可以叠加一条均线。

var series: Array = []      # [{values: Array, color: Color, width: float}]
var unit := ""
var x_caption := ""
var marker_index := -1
var _font: Font


func _init() -> void:
	custom_minimum_size = Vector2(300, 160)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = UIKit.font()


func set_series(s: Array, p_unit := "", caption := "") -> void:
	series = s
	unit = p_unit
	x_caption = caption
	queue_redraw()


static func moving_average(values: Array, n: int) -> Array:
	var out: Array = []
	for i in values.size():
		var a := maxi(0, i - n + 1)
		var s := 0.0
		for j in range(a, i + 1):
			s += float(values[j])
		out.append(s / float(i - a + 1))
	return out


func _draw() -> void:
	var rect := Rect2(Vector2(46, 8), size - Vector2(56, 34))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.02, 0.05, 0.8))
	var lo := INF
	var hi := -INF
	for s in series:
		for v in s["values"]:
			lo = minf(lo, float(v))
			hi = maxf(hi, float(v))
	if lo == INF:
		draw_string(_font, Vector2(12, size.y * 0.5), "暂无数据", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UIKit.DIM)
		return
	if hi - lo < 0.0001:
		hi += 1.0
		lo -= 1.0
	var pad := (hi - lo) * 0.08
	lo -= pad
	hi += pad
	for k in 5:
		var y := rect.position.y + rect.size.y * k / 4.0
		draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), Color(1, 1, 1, 0.07), 1.0)
		var v := hi - (hi - lo) * k / 4.0
		draw_string(_font, Vector2(2, y + 5), _fmt(v), HORIZONTAL_ALIGNMENT_LEFT, 42, 11, UIKit.DIM)
	for s in series:
		var vals: Array = s["values"]
		if vals.size() < 2:
			continue
		var pts := PackedVector2Array()
		for i in vals.size():
			var x := rect.position.x + rect.size.x * i / float(vals.size() - 1)
			var y2 := rect.end.y - (float(vals[i]) - lo) / (hi - lo) * rect.size.y
			pts.append(Vector2(x, y2))
		draw_polyline(pts, s.get("color", UIKit.CYAN), float(s.get("width", 2.0)), true)
	if marker_index >= 0 and not series.is_empty():
		var n: int = (series[0]["values"] as Array).size()
		var mx := rect.position.x + rect.size.x * marker_index / float(maxi(1, n - 1))
		draw_line(Vector2(mx, rect.position.y), Vector2(mx, rect.end.y), Color(1, 0.8, 0.25, 0.6), 1.0)
	var cap := x_caption
	if unit != "":
		cap += "（单位：%s）" % unit
	draw_string(_font, Vector2(rect.position.x, size.y - 6), cap, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIKit.DIM)


func _fmt(v: float) -> String:
	if absf(v) >= 10000:
		return "%.1f万" % (v / 10000.0)
	if absf(v) >= 100:
		return "%d" % int(v)
	return "%.2f" % v
