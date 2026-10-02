class_name PerfOverlay
extends PanelContainer
## 性能浮层（路线图 1.5）：左上角显示帧率、最慢一帧、绘制调用、图元、画质档、分辨率、显卡。
## 每 0.5 秒刷新；基准测试的结果表也显示在这里，方便所有者在真机上截图。
## 开关：F3、暂停菜单「显示性能数据」、网页 ?perf=1。

var main: Node
var label: Label
var bench_text := ""
var acc := 0.0
var worst_us := 0
var last_us := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.05, 0.08, 0.78)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(10)
	add_theme_stylebox_override("panel", sb)
	position = Vector2(12, 44)
	label = Label.new()
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color("e8dcc0"))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	visible = Settings.show_perf
	Settings.changed.connect(func(): visible = Settings.show_perf)
	last_us = Time.get_ticks_usec()


func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	worst_us = maxi(worst_us, now - last_us)
	last_us = now
	if not visible:
		return
	acc += delta
	if acc < 0.5:
		return
	acc = 0.0
	label.text = text_now()
	worst_us = 0
	reset_size()


func text_now() -> String:
	var vp := get_viewport()
	var size := Vector2(get_tree().root.size)
	var q: String = main.quality if main else ""
	var lines := [
		"性能 · %s画质 · %d×%d · 3D 分辨率 ×%.2f" % [PerfOverlay.tier_name(q), size.x, size.y, vp.scaling_3d_scale],
		"帧率 %d（最慢一帧 %d 毫秒）" % [Engine.get_frames_per_second(), worst_us / 1000],
		"绘制调用 %d · 图元 %.1f 万 · 物体 %d" % [Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 10000.0, Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)],
		"显卡：%s" % RenderingServer.get_video_adapter_name(),
	]
	if bench_text != "":
		lines.append("")
		lines.append(bench_text)
	return "\n".join(lines)


static func tier_name(q: String) -> String:
	return {"low": "低", "medium": "中", "high": "高"}.get(q, q)
