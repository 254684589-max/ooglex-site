class_name TitleCard
extends Control
## 开场标题卡（路线图 3.8）：雾夜街景上压一层夜色，中间「序章 / 霜渡镇之夜 / 灰鲸河畔 · 入夜」，下面一行「点击画面开始」。
## 整张卡不挡鼠标和触屏（第一下点击同时锁定鼠标、开始开场）；开始后慢慢淡出，减少动态效果时直接消失。

signal gone

var box: VBoxContainer
var title: Label
var prompt: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.05, 0.55)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	box = VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)
	for spec in [["序章", 20, "9fb2c6"], ["霜渡镇之夜", 44, "e8dcc0"], ["灰鲸河畔 · 入夜", 18, "c8bca0"], ["", 18, "c8a060"]]:
		var l := Label.new()
		l.text = spec[0]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", spec[1])
		l.add_theme_color_override("font_color", Color(spec[2]))
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
		l.add_theme_constant_override("outline_size", 4)
		box.add_child(l)
		if spec[1] == 44:
			title = l
		prompt = l
	prompt.add_theme_constant_override("line_spacing", 4)
	box.get_child(2).custom_minimum_size.y = 40     # 地名和开始提示之间空一段


func setup(touch: bool) -> void:
	prompt.text = "轻触画面开始" if touch else "点击画面或按任意键开始"


## 开始了：提示行先藏起来，整张卡淡出（减少动态效果时直接消失）
func dismiss(reduced_motion := false) -> void:
	prompt.text = ""
	if reduced_motion or not is_inside_tree():
		_done()
		return
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 2.2).set_delay(0.8)
	tw.tween_callback(_done)


func _done() -> void:
	hide()
	gone.emit()
