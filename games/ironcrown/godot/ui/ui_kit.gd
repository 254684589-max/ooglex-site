class_name UiKit
extends RefCounted
## 面板的公共外框（2.6 起背包、搜刮面板共用；任务日志在 2.3 里自己搭，样子相同）：
## 半透明遮罩 + 居中的深蓝面板（金色描边）+ 标题行（标题、「关闭」按钮）+ 可滚动的内容区。
## 返回 {panel, scroll, box, title, close}；fit() 按窗口逻辑尺寸限制宽高，手机上不会超出屏幕。

const TEXT := Color("e8dcc0")
const TEXT_DIM := Color("c8bca0")


static func frame(root: Control, title_text: String) -> Dictionary:
	root.process_mode = Node.PROCESS_MODE_ALWAYS
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.05, 0.08, 0.72)
	root.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	root.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("1c2a3a")
	sb.border_color = Color("b8964e")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	panel.add_child(outer)
	var head := HBoxContainer.new()
	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	head.add_child(title)
	var close := Button.new()
	close.text = "关闭"
	close.custom_minimum_size = Vector2(64, 36)
	head.add_child(close)
	outer.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	return {"panel": panel, "scroll": scroll, "box": box, "title": title, "close": close}


static func logical_size(root: Control) -> Vector2:
	var w := root.get_tree().root
	return Vector2(w.size) / maxf(w.content_scale_factor, 0.01)


## 内容区宽度（面板宽 260..max_w 减去边距）
static func content_width(root: Control, max_w := 600.0) -> float:
	return clampf(logical_size(root).x - 32.0, 260.0, max_w) - 32.0


## 按窗口逻辑尺寸定面板宽度（260..max_w）、内容区高度（不超过窗口高度 - 120）
static func fit(root: Control, f: Dictionary, max_w := 600.0) -> float:
	var logical := logical_size(root)
	var pw := clampf(logical.x - 32.0, 260.0, max_w)
	(f.panel as Control).custom_minimum_size.x = pw
	var scroll: ScrollContainer = f.scroll
	var box: Control = f.box
	scroll.custom_minimum_size = Vector2(pw - 32.0, minf(box.get_combined_minimum_size().y, logical.y - 120.0))
	return pw - 32.0


static func label(parent: Node, text: String, dim := false, size := 0) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	l.add_theme_color_override("font_color", TEXT_DIM if dim else TEXT)
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	parent.add_child(l)
	return l


static func button(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size.y = 34
	b.clip_text = true
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


static func clear(box: Node) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
