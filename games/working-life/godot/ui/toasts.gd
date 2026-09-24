class_name Toasts
extends Control
## 顶部中间的通知条（最多同时 4 条，几秒后淡出）和屏幕中央的大字横幅。

const MAX_TOASTS := 4

var _list: VBoxContainer
var _banner: VBoxContainer
var _banner_title: Label
var _banner_sub: Label
var _banner_tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIKit.full_rect(self)
	_list = UIKit.vbox(6)
	_list.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_list.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_list.position.y = 16
	_list.alignment = BoxContainer.ALIGNMENT_BEGIN
	add_child(_list)
	var center := CenterContainer.new()
	UIKit.full_rect(center)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_banner = UIKit.vbox(8)
	center.add_child(_banner)
	_banner_title = UIKit.hud_label("", 38, UIKit.CYAN)
	_banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_title.add_theme_constant_override("outline_size", 10)
	_banner.add_child(_banner_title)
	_banner_sub = UIKit.hud_label("", 22, UIKit.TEXT)
	_banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_child(_banner_sub)
	_banner.modulate.a = 0.0
	Events.toast.connect(push)
	Events.banner.connect(show_banner)


func push(text: String, kind := "info") -> void:
	var p := UIKit.panel(Color(0.03, 0.03, 0.07, 0.88), 6, 10)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UIKit.label(text, 18, UIKit.kind_color(kind), HORIZONTAL_ALIGNMENT_CENTER)
	p.add_child(l)
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_list.add_child(p)
	while _list.get_child_count() > MAX_TOASTS:
		var old := _list.get_child(0)
		_list.remove_child(old)
		old.queue_free()
	_list.reset_size()
	_list.position.x = (size.x - _list.size.x) * 0.5
	var tw := p.create_tween()
	tw.tween_interval(3.6)
	tw.tween_property(p, "modulate:a", 0.0, 0.6)
	tw.tween_callback(p.queue_free)


func show_banner(title: String, subtitle := "") -> void:
	_banner_title.text = title
	_banner_sub.text = subtitle
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	_banner_tween = create_tween()
	_banner_tween.tween_property(_banner, "modulate:a", 1.0, 0.4)
	_banner_tween.tween_interval(3.4)
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, 0.8)


func _process(_delta: float) -> void:
	# 打开窗口时不让大字横幅盖在窗口上
	_banner.visible = not GameManager.is_modal() or not GameManager.playing
	if _list.get_child_count() > 0:
		_list.reset_size()
		_list.position = Vector2((size.x - _list.size.x) * 0.5, size.y * 0.2)
