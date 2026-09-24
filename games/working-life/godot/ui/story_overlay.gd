class_name StoryOverlay
extends Control
## 剧情层：黑边（电影画幅）、字幕、手机消息卡片、黑屏淡入淡出、跳过按钮。开场与睡觉、昏倒都用它。

signal skip_requested

var playing := false
var _top: ColorRect
var _bottom: ColorRect
var _fade: ColorRect
var _caption: Label
var _phone: VBoxContainer
var _skip: Button


func _ready() -> void:
	UIKit.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top = ColorRect.new()
	_top.color = Color.BLACK
	_top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_top.custom_minimum_size = Vector2(0, 0)
	_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_top)
	_bottom = ColorRect.new()
	_bottom.color = Color.BLACK
	_bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bottom)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIKit.full_rect(_fade)
	add_child(_fade)
	_caption = UIKit.hud_label("", 24, UIKit.TEXT)
	_caption.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.custom_minimum_size = Vector2(900, 0)
	_caption.position = Vector2(-450, -110)
	add_child(_caption)
	_phone = UIKit.vbox(8)
	_phone.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_phone.position = Vector2(-420, 80)
	_phone.custom_minimum_size = Vector2(390, 0)
	add_child(_phone)
	_skip = UIKit.small_button("跳过 ▶▶", func(): skip_requested.emit())
	_skip.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_skip.position = Vector2(20, 20)
	_skip.visible = false
	add_child(_skip)


func begin(skippable := true) -> void:
	playing = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_skip.visible = skippable
	letterbox(true)


func end() -> void:
	playing = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skip.visible = false
	_caption.text = ""
	letterbox(false)
	clear_phone()


func letterbox(on: bool) -> void:
	var h := size.y * 0.11 if on else 0.0
	var tw := create_tween().set_parallel()
	tw.tween_property(_top, "size:y", h, 0.5)
	tw.tween_property(_bottom, "size:y", h, 0.5)
	tw.tween_property(_bottom, "position:y", size.y - h, 0.5)


func caption(text: String) -> void:
	_caption.text = text
	_caption.modulate.a = 0.0
	create_tween().tween_property(_caption, "modulate:a", 1.0, 0.4)


func phone(from: String, text: String) -> void:
	var card := UIKit.panel(Color(0.03, 0.03, 0.08, 0.92), 10, 12, UIKit.CYAN)
	var v := UIKit.vbox(2)
	card.add_child(v)
	v.add_child(UIKit.label("手机 · " + from, 14, UIKit.CYAN))
	v.add_child(UIKit.label(text, 18, UIKit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true))
	card.modulate.a = 0.0
	_phone.add_child(card)
	create_tween().tween_property(card, "modulate:a", 1.0, 0.35)
	AudioManager.play_sfx("message")


func clear_phone() -> void:
	for c in _phone.get_children():
		c.queue_free()


func fade(to_black: bool, dur := 0.6) -> Tween:
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0 if to_black else 0.0, dur)
	return tw


func set_black(a: float) -> void:
	_fade.color.a = a
