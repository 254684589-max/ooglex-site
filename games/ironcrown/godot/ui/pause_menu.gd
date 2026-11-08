class_name PauseMenu
extends Control
## 暂停菜单（GDD.md 第三、四、十二节）：继续、视野角、灵敏度、反转 Y 轴、镜头摆动、操作说明。
## 打开时游戏暂停；本节点在暂停时照常处理输入。设置暂时只存在内存里（2.7 存档时存到浏览器）。

signal resume_requested
signal quality_selected(tier: String)
signal saves_requested
signal main_menu_requested           # 回到主菜单（2026-11-08）

var panel: PanelContainer
var resume_btn: Button
var saves_btn: Button
var menu_btn: Button
var title_label: Label
var lang_btns := {}
var menu_mode := false             # 从主菜单打开（只当「设置」用）：没有「存档」「回到主菜单」，「继续游戏」变成「返回」
var menu_armed := false
var help_label: Label
var sound_check: CheckButton
var tips_check: CheckButton
var scroll: ScrollContainer
var box: VBoxContainer
var music_check: CheckButton
var music_slider: HSlider
var music_value: Label

const HELP_DESKTOP := "电脑：点击画面锁定鼠标 · WASD 移动 · 鼠标转视角 · Shift 跑 · C 蹲下 / 站起 · 空格 跳 · E 交互 · 左键 / F 出剑 · 右键 / Q 格挡 · 拔剑时按着 A / D / S 再按空格是闪避 · 跑着出剑是突刺 · R 收剑 · V 切换视角 · I 背包 · J 任务 · K 角色 · M 地图 · N 小地图（小 / 大 / 隐藏） · F8 快速存档 · F9 快速读档 · F3 性能数据 · 军阵里 1 / 2 / 3 指挥小队（跟随 / 坚守 / 冲锋）· Esc 暂停"
const HELP_TOUCH := "手机：左半屏拖动走路（推到底是跑）· 右半屏拖动转视角 · 右下角「跳」「蹲」「攻」「挡」「视角」· 拔剑时摇杆往侧面或后面推着点「跳」是闪避，跑着点「攻」是突刺 · 右上角「角色」「背包」「任务」「地图」「菜单」· 第一章起站在路牌旁打开地图（或对着路牌点交互按钮）才能出发 · 军阵里点「令」指挥小队"
var fov_slider: HSlider
var sens_slider: HSlider
var invert_check: CheckButton
var bob_check: CheckButton
var tp_check: CheckButton
var fov_value: Label
var sens_value: Label
var perf_check: CheckButton
var quality_btns := {}
var minimap_btns := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.05, 0.08, 0.72)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("1c2a3a")
	sb.border_color = Color("b8964e")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	scroll = ScrollContainer.new()                  # 矮屏手机放不下时能上下滑（M.1 加了音乐两行，审查）
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	panel.add_child(scroll)
	box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	var title := Label.new()
	title_label = title
	title.text = "已暂停"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("e8dcc0"))
	box.add_child(title)
	resume_btn = Button.new()
	resume_btn.text = "继续游戏"
	resume_btn.pressed.connect(func(): resume_requested.emit())
	box.add_child(resume_btn)
	saves_btn = Button.new()
	saves_btn.text = "存档 / 读档"
	saves_btn.pressed.connect(func(): saves_requested.emit())
	box.add_child(saves_btn)
	menu_btn = Button.new()
	menu_btn.text = "回到主菜单"
	menu_btn.pressed.connect(func():
		if not menu_armed:                      # 先确认一下：没存的进度会丢
			menu_armed = true
			menu_btn.text = "再点一次回到主菜单（没存的进度会丢）"
			return
		main_menu_requested.emit())
	box.add_child(menu_btn)
	var lrow := HBoxContainer.new()                     # 语言（2026-11-08）：中文 / English
	lrow.name = "LangRow"
	var ll := Label.new()
	ll.text = "语言 Language"
	ll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lrow.add_child(ll)
	var lgroup := ButtonGroup.new()
	for k in I18n.LANGS:
		var b := Button.new()
		b.name = "Lang_" + k
		b.text = "中文" if k == "zh" else "English"
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.toggle_mode = true
		b.button_group = lgroup
		b.button_pressed = Settings.lang == k
		b.custom_minimum_size = Vector2(72, 32)
		b.pressed.connect(func(): Settings.set_value("lang", k))
		lrow.add_child(b)
		lang_btns[k] = b
	box.add_child(lrow)
	fov_value = Label.new()
	fov_slider = _slider(box, "视野角", fov_value, Settings.FOV_MIN, Settings.FOV_MAX, 1.0, Settings.fov, "fov")
	sens_value = Label.new()
	sens_slider = _slider(box, "转视角灵敏度", sens_value, Settings.SENS_MIN, Settings.SENS_MAX, 0.1, Settings.sensitivity, "sensitivity")
	invert_check = _check(box, "反转上下视角", Settings.invert_y, "invert_y")
	bob_check = _check(box, "走路时镜头摆动", Settings.head_bob, "head_bob")
	tp_check = _check(box, "第三人称越肩视角（V）", Settings.third_person, "third_person")
	# 画质三档（TECH.md 第五节；1.5 起可以在菜单里切换，方便在同一台设备上对比）
	var qrow := HBoxContainer.new()
	var ql := Label.new()
	ql.text = "画质"
	ql.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	qrow.add_child(ql)
	var group := ButtonGroup.new()
	for t in Look.TIERS:
		var b := Button.new()
		b.text = PerfOverlay.tier_name(t)
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(52, 32)
		b.pressed.connect(func(): quality_selected.emit(t))
		qrow.add_child(b)
		quality_btns[t] = b
	box.add_child(qrow)
	var mrow := HBoxContainer.new()                     # 右上角的小地图（C.4）：小 / 大 / 隐藏
	mrow.name = "MinimapRow"
	var ml := Label.new()
	ml.text = "小地图（N）"
	ml.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mrow.add_child(ml)
	var mgroup := ButtonGroup.new()
	for m in Settings.MINIMAP_SIZES:
		var b := Button.new()
		b.name = "Minimap_" + m
		b.text = {"small": "小", "large": "大", "off": "隐藏"}[m]
		b.toggle_mode = true
		b.button_group = mgroup
		b.button_pressed = Settings.minimap == m
		b.custom_minimum_size = Vector2(52, 32)
		b.pressed.connect(func(): Settings.set_value("minimap", m))
		mrow.add_child(b)
		minimap_btns[m] = b
	box.add_child(mrow)
	sound_check = _check(box, "声音", Settings.sound, "sound")
	music_check = _check(box, "背景音乐", Settings.music, "music")            # M.1
	music_check.disabled = not Settings.sound                               # 「声音」关了，音乐跟着关（灰着，审查）
	music_value = Label.new()
	music_slider = _slider(box, "音乐音量", music_value, 0.0, 1.0, 0.05, Settings.music_volume, "music_volume")
	tips_check = _check(box, "教学提示", Settings.tips, "tips")
	perf_check = _check(box, "显示性能数据（F3）", Settings.show_perf, "show_perf")
	var help := Label.new()
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if I18n.en() else TextServer.AUTOWRAP_ARBITRARY
	help.add_theme_color_override("font_color", Color("a9b4c0"))
	help.text = HELP_DESKTOP + "\n" + HELP_TOUCH
	box.add_child(help)
	help_label = help
	Settings.changed.connect(func():
		music_check.disabled = not Settings.sound
		perf_check.set_pressed_no_signal(Settings.show_perf)
		tp_check.set_pressed_no_signal(Settings.third_person)
		if minimap_btns.has(Settings.minimap):
			minimap_btns[Settings.minimap].set_pressed_no_signal(true)
		if lang_btns.has(Settings.lang):
			lang_btns[Settings.lang].set_pressed_no_signal(true)
		help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if I18n.en() else TextServer.AUTOWRAP_ARBITRARY
		_refresh_values())
	get_tree().root.size_changed.connect(_fit)
	_fit()
	_refresh_values()
	hide()


## 操作说明只写这台设备的（3.8 加了两个开关，手机竖屏上菜单放不下两段说明）
func set_touch(touch: bool) -> void:
	help_label.text = HELP_TOUCH if touch else HELP_DESKTOP


func show_quality(tier: String) -> void:
	if quality_btns.has(tier):
		quality_btns[tier].set_pressed_no_signal(true)


func open() -> void:
	show()
	menu_armed = false
	menu_btn.text = "回到主菜单"
	resume_btn.grab_focus()


## 从主菜单打开时只当「设置」用
func set_menu_mode(on: bool) -> void:
	menu_mode = on
	title_label.text = "设置" if on else "已暂停"
	resume_btn.text = "返回" if on else "继续游戏"
	saves_btn.visible = not on
	menu_btn.visible = not on


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		resume_requested.emit()


func _slider(box: VBoxContainer, text: String, value_label: Label, lo: float, hi: float, step: float, v: float, key: String) -> HSlider:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = text
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	row.add_child(value_label)
	box.add_child(row)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = v
	s.custom_minimum_size.y = 28
	s.value_changed.connect(func(nv: float):
		Settings.set_value(key, nv)
		_refresh_values())
	box.add_child(s)
	return s


func _check(box: VBoxContainer, text: String, v: bool, key: String) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = v
	c.toggled.connect(func(on: bool): Settings.set_value(key, on))
	box.add_child(c)
	return c


func _refresh_values() -> void:
	fov_value.text = "%d°" % roundi(Settings.fov)
	sens_value.text = I18n.t("%.1f 倍") % Settings.sensitivity
	if music_value:
		music_value.text = "%d%%" % roundi(Settings.music_volume * 100.0)


func _fit() -> void:
	var w := get_tree().root
	var logical := Vector2(w.size) / maxf(w.content_scale_factor, 0.01)
	panel.custom_minimum_size.x = clampf(logical.x - 32.0, 240.0, 440.0)
	scroll.custom_minimum_size.y = minf(box.get_combined_minimum_size().y, logical.y - 32.0 - 36.0)     # 面板上下的边距和描边
