class_name UIWindow
extends Control
## 通用窗口：半透明遮罩 + 居中面板（标题栏、关闭按钮、可滚动内容区、底部按钮栏）。
## 手机、商店、对话、结算……所有弹窗都基于它。窗口大小会根据屏幕自动收缩（手机横屏也能用）。

signal closed

var panel: PanelContainer
var body: VBoxContainer
var footer: HBoxContainer
var title_label: Label
var scroll: ScrollContainer
var want_size := Vector2(760, 520)
var closable := true
var window_id := ""
var _close_btn: Button


func _init(title := "", size := Vector2(760, 520), use_scroll := true) -> void:
	want_size = size
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.02, 0.5)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	UIKit.full_rect(dim)
	add_child(dim)
	panel = UIKit.panel(UIKit.PANEL_BG, 10, 16, Color(UIKit.CYAN.r, UIKit.CYAN.g, UIKit.CYAN.b, 0.55))
	add_child(panel)
	var outer := UIKit.vbox(10)
	panel.add_child(outer)
	var head := UIKit.hbox(8)
	outer.add_child(head)
	var stripe := ColorRect.new()
	stripe.color = UIKit.MAGENTA
	stripe.custom_minimum_size = Vector2(4, 24)
	head.add_child(stripe)
	title_label = UIKit.label(title, 22, UIKit.CYAN)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title_label)
	_close_btn = UIKit.small_button("× 关闭", close)
	head.add_child(_close_btn)
	outer.add_child(UIKit.sep())
	body = UIKit.vbox(8)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if use_scroll:
		scroll = ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		outer.add_child(scroll)
		scroll.add_child(body)
	else:
		outer.add_child(body)
	footer = UIKit.hbox(10)
	footer.alignment = BoxContainer.ALIGNMENT_END
	outer.add_child(footer)


func _ready() -> void:
	UIKit.full_rect(self)
	resized.connect(_layout)
	_layout()
	await get_tree().process_frame
	_focus_first()


func _layout() -> void:
	var vp := size
	if vp.x <= 0:
		return
	var s := Vector2(minf(want_size.x, vp.x - 24), minf(want_size.y, vp.y - 24))
	panel.custom_minimum_size = s
	panel.size = s
	panel.position = (vp - s) * 0.5


func set_title(t: String) -> void:
	title_label.text = t


func set_closable(c: bool) -> void:
	closable = c
	_close_btn.visible = c


func clear_body() -> void:
	for c in body.get_children():
		body.remove_child(c)
		c.queue_free()


func clear_footer() -> void:
	for c in footer.get_children():
		footer.remove_child(c)
		c.queue_free()


func add_text(text: String, size := 18, col := UIKit.TEXT) -> Label:
	var l := UIKit.label(text, size, col, HORIZONTAL_ALIGNMENT_LEFT, true)
	body.add_child(l)
	return l


func add_button(text: String, cb: Callable, to_footer := false) -> Button:
	var b := UIKit.button(text, cb)
	if to_footer:
		footer.add_child(b)
	else:
		body.add_child(b)
	return b


func _focus_first() -> void:
	if not is_inside_tree():
		return
	for b in find_children("*", "Button", true, false):
		if (b as Button).visible and not (b as Button).disabled and b != _close_btn:
			(b as Button).grab_focus()
			return


func close() -> void:
	if not closable:
		return
	force_close()


func force_close() -> void:
	closed.emit()
	queue_free()
