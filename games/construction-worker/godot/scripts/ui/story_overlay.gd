class_name StoryOverlay
extends Control
## 黑屏剧情字幕 + 全屏淡入淡出。
## play_lines(文字数组, 结束回调)：逐句淡入，点击 / 任意键加速，右下角可跳过。

signal finished()

var _black: ColorRect
var _label: Label
var _skip: Label
var _lines: PackedStringArray = PackedStringArray()
var _index := -1
var _timer := 0.0
var _playing := false
var _on_done: Callable = Callable()
var _label_tween: Tween
var _black_tween: Tween

const LINE_TIME := 3.4


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIKit.full_rect(self)
	_black = ColorRect.new()
	_black.color = Color(0.02, 0.02, 0.025, 1.0)
	UIKit.full_rect(_black)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_black.modulate.a = 0.0
	add_child(_black)
	var center := CenterContainer.new()
	UIKit.full_rect(center)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_label = UIKit.label("", 28, Color(0.95, 0.93, 0.88), HORIZONTAL_ALIGNMENT_CENTER)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size.x = 320
	_label.modulate.a = 0.0
	center.add_child(_label)
	_skip = UIKit.label("点击继续 · Esc 跳过", 15, UIKit.DIM)
	_skip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_skip.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_skip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_skip.position -= Vector2(24, 20)
	_skip.visible = false
	add_child(_skip)


func is_playing() -> bool:
	return _playing


func play_lines(lines: PackedStringArray, on_done: Callable) -> void:
	_lines = lines
	_on_done = on_done
	_index = -1
	_playing = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_black.modulate.a = 1.0
	_skip.visible = true
	_label.custom_minimum_size.x = clampf(get_viewport_rect().size.x - 60.0, 280.0, 900.0)
	_next()


func _next() -> void:
	_index += 1
	if _index >= _lines.size():
		_finish()
		return
	_timer = LINE_TIME
	_label.text = _lines[_index]
	_label.modulate.a = 0.0
	_fade_label(1.0, 0.6)


func _fade_label(to: float, duration: float) -> void:
	if _label_tween != null and _label_tween.is_valid():
		_label_tween.kill()
	_label_tween = create_tween()
	_label_tween.tween_property(_label, "modulate:a", to, duration)
	if to <= 0.0:
		_label_tween.tween_callback(func(): _label.text = "")


func _finish() -> void:
	if not _playing:
		return
	_playing = false
	_skip.visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_label(0.0, 0.3)
	_fade_black(0.0, 1.2)
	var cb := _on_done
	_on_done = Callable()
	if cb.is_valid():
		cb.call()
	finished.emit()


func skip() -> void:
	if _playing:
		_index = _lines.size()
		_finish()


func _process(delta: float) -> void:
	if not _playing:
		return
	_timer -= delta
	if _timer <= 0.0:
		_next()


func _gui_input(event: InputEvent) -> void:
	if _playing and event is InputEventMouseButton and event.pressed:
		_next()
		accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if not _playing:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.is_action("pause"):
			skip()
		else:
			_next()
		get_viewport().set_input_as_handled()


func _fade_black(to: float, duration: float) -> Tween:
	if _black_tween != null and _black_tween.is_valid():
		_black_tween.kill()
	_black_tween = create_tween()
	_black_tween.tween_property(_black, "modulate:a", to, duration)
	return _black_tween


## 淡出到黑屏，结束后调用回调
func fade_out(duration: float, on_done: Callable) -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_fade_black(1.0, duration).tween_callback(on_done)


func fade_in(duration: float) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_black(0.0, duration)


func set_black(alpha: float) -> void:
	_black.modulate.a = alpha
