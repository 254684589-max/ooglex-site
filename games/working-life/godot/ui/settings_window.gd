class_name SettingsWindow
extends UIWindow
## 设置：分辨率、窗口 / 全屏、音量（总 / 音乐 / 音效 / 环境）、鼠标灵敏度、画质、阴影、抗锯齿、帧率上限、任务指引。

signal quality_changed


func _init() -> void:
	super("设置", Vector2(700, 620))
	window_id = "settings"


func _ready() -> void:
	super()
	_build()


func _row(title: String) -> HBoxContainer:
	var h := UIKit.hbox(10)
	body.add_child(h)
	var l := UIKit.label(title, 17, UIKit.TEXT)
	l.custom_minimum_size.x = 170
	h.add_child(l)
	return h


func _slider(title: String, key: String, lo: float, hi: float, step: float) -> void:
	var h := _row(title)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(SettingsManager.get_v(key, lo))
	s.custom_minimum_size = Vector2(240, 24)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(s)
	var v := UIKit.label("%.2f" % s.value if step < 1 else "%d" % int(s.value), 15, UIKit.DIM)
	v.custom_minimum_size.x = 50
	h.add_child(v)
	s.value_changed.connect(func(x):
		v.text = "%.2f" % x if step < 1 else "%d" % int(x)
		SettingsManager.set_v(key, x))


func _option(title: String, key: String, items: Array, cb := Callable()) -> void:
	var h := _row(title)
	var o := OptionButton.new()
	for it in items:
		o.add_item(String(it))
	o.select(clampi(int(SettingsManager.get_v(key, 0)), 0, items.size() - 1))
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(o)
	o.item_selected.connect(func(i):
		SettingsManager.set_v(key, i)
		if cb.is_valid():
			cb.call())


func _check(title: String, key: String, cb := Callable()) -> void:
	var h := _row(title)
	var c := CheckButton.new()
	c.button_pressed = bool(SettingsManager.get_v(key, false))
	h.add_child(c)
	c.toggled.connect(func(on):
		SettingsManager.set_v(key, on)
		if cb.is_valid():
			cb.call())


func _build() -> void:
	clear_body()
	var web := OS.has_feature("web")
	body.add_child(UIKit.label("画面", 18, UIKit.CYAN))
	if not web:
		var res: Array = []
		for r in SettingsManager.RESOLUTIONS:
			res.append("%d × %d" % [r.x, r.y])
		_option("分辨率", "resolution", res)
		_check("全屏", "fullscreen")
	else:
		body.add_child(UIKit.label("网页版的分辨率与全屏由浏览器决定（可按 F11 全屏）。", 14, UIKit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
	_option("画质", "quality", SettingsManager.QUALITY_NAMES, func(): quality_changed.emit())
	_check("阴影", "shadows", func(): quality_changed.emit())
	_check("抗锯齿（MSAA 2×）", "msaa", func(): quality_changed.emit())
	_option("帧率上限", "fps", ["30", "60", "120", "不限"])
	body.add_child(UIKit.label("声音", 18, UIKit.CYAN))
	_slider("总音量", "master", 0.0, 1.0, 0.05)
	_slider("音乐", "music", 0.0, 1.0, 0.05)
	_slider("音效", "sfx", 0.0, 1.0, 0.05)
	_slider("环境声", "ambience", 0.0, 1.0, 0.05)
	body.add_child(UIKit.label("操作", 18, UIKit.CYAN))
	_slider("鼠标灵敏度", "sensitivity", 0.3, 2.5, 0.05)
	_check("反转 Y 轴", "invert_y")
	_check("显示任务指引光柱", "show_marker")
	body.add_child(UIKit.label("画质「低」会降低渲染分辨率、关闭泛光并减少路人与空中车辆，适合手机与轻薄本。部分画质选项在下次进入游戏时完全生效。", 13, UIKit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
