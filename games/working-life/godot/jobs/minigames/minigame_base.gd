class_name MinigameBase
extends VBoxContainer
## 工作小游戏基类：标题、说明、倒计时条、得分显示；子类实现 _setup() 与玩法，结束时调用 finish()。
## 所有小游戏都能用鼠标 / 触屏点按，也支持数字键 1~4 快速选择。

signal finished(score: float)

var title := "工作"
var instructions := ""
var duration := 60.0
var time_left := 60.0
var difficulty := 0
var done := false
var rng := RandomNumberGenerator.new()
var _bar: ProgressBar
var _time_label: Label
var _score_label: Label
var content: VBoxContainer
var feedback: Label
var _started := false


func _init(p_difficulty := 0) -> void:
	difficulty = p_difficulty
	rng.randomize()
	add_theme_constant_override("separation", 8)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL


func _ready() -> void:
	_configure()
	var head := UIKit.hbox(10)
	add_child(head)
	var t := UIKit.label(title, 20, UIKit.CYAN)
	head.add_child(t)
	head.add_child(UIKit.spacer())
	_score_label = UIKit.label("", 17, UIKit.YELLOW)
	head.add_child(_score_label)
	_time_label = UIKit.label("", 17, UIKit.TEXT)
	head.add_child(_time_label)
	_bar = UIKit.bar(UIKit.MAGENTA, 200, 8)
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_bar)
	add_child(UIKit.label(instructions, 15, UIKit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
	content = UIKit.vbox(10)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(content)
	feedback = UIKit.label("", 17, UIKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	add_child(feedback)
	time_left = duration
	_setup()
	_started = true
	update_score()


## 子类覆盖：设置 title / instructions / duration
func _configure() -> void:
	pass


func _setup() -> void:
	pass


## 子类覆盖：当前得分文字
func score_text() -> String:
	return ""


## 子类覆盖：最终得分 0~100
func final_score() -> float:
	return 0.0


func update_score() -> void:
	if _score_label != null:
		_score_label.text = score_text()


func say(text: String, good := true) -> void:
	feedback.text = text
	feedback.add_theme_color_override("font_color", UIKit.GOOD if good else UIKit.BAD)
	AudioManager.play_sfx("ok" if good else "error", -6.0)


func _process(delta: float) -> void:
	if done or not _started:
		return
	time_left -= delta
	_bar.value = clampf(time_left / duration * 100.0, 0.0, 100.0)
	_time_label.text = "剩余 %d 秒" % int(ceil(maxf(time_left, 0.0)))
	_tick(delta)
	if time_left <= 0.0:
		finish()


func _tick(_delta: float) -> void:
	pass


func finish() -> void:
	if done:
		return
	done = true
	finished.emit(clampf(final_score(), 0.0, 100.0))


func clear_content() -> void:
	for c in content.get_children():
		content.remove_child(c)
		c.queue_free()


func grid(columns: int) -> GridContainer:
	var g := GridContainer.new()
	g.columns = columns
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 8)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return g


func big_button(text: String, cb: Callable, col := UIKit.CYAN) -> Button:
	var b := UIKit.button(text, cb)
	b.custom_minimum_size = Vector2(120, 56)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_color_override("font_color", col)
	return b


func _unhandled_key_input(event: InputEvent) -> void:
	if done or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k: int = event.physical_keycode
	if k >= KEY_1 and k <= KEY_9:
		_number_key(k - KEY_1)
		get_viewport().set_input_as_handled()


func _number_key(_i: int) -> void:
	pass
