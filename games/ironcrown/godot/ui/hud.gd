class_name Hud
extends Control
## 平视显示（GDD.md 第十一节，阶段 1.2 只有这几样）：左上标题（标注占位）、屏幕中央准星、底部操作提示、右上「菜单」按钮。

signal menu_pressed

const TITLE := "铁冠之争 · 灰盒原型（占位几何体）"

var title_label: Label
var hint_label: Label
var menu_btn: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_label = Label.new()
	title_label.text = TITLE
	title_label.position = Vector2(16, 12)
	title_label.add_theme_font_size_override("font_size", 18)
	title_label.add_theme_color_override("font_color", Color("e8dcc0"))
	add_child(title_label)
	hint_label = Label.new()
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	hint_label.add_theme_color_override("font_color", Color("e8dcc0"))
	hint_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	hint_label.add_theme_constant_override("outline_size", 6)
	add_child(hint_label)
	menu_btn = Button.new()
	menu_btn.text = "菜单"
	menu_btn.focus_mode = Control.FOCUS_NONE
	menu_btn.pressed.connect(func(): menu_pressed.emit())
	add_child(menu_btn)
	resized.connect(_layout)
	_layout()


func set_hint(text: String) -> void:
	hint_label.text = text
	_layout()


func _layout() -> void:
	menu_btn.position = Vector2(size.x - menu_btn.size.x - 12.0, 10.0)
	var w := minf(size.x - 32.0, 620.0)
	hint_label.size = Vector2(w, 0)
	hint_label.position = Vector2((size.x - w) * 0.5, size.y * 0.62)
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	draw_circle(c, 3.0, Color(0, 0, 0, 0.6))
	draw_circle(c, 2.0, Color("e8dcc0"))
