class_name CreditsPanel
extends Control
## 制作人员（2026-11-08 所有者「制作人员，加入郑翊名字，其它可以添加别的名字」）：主菜单上点开，盖在标题画面上，
## 名单从下往上慢慢滚（像片尾）；滚轮、拖动、方向键自己翻（自己翻了就不再自动滚）；「返回」或 Esc 回主菜单。
## 别的名字只写真有其事的：用到的引擎、素材、字体的作者和许可（见 assets/SOURCES.md）。

signal closed

const SPEED := 32.0                      # 自动滚的速度（像素 / 秒，逻辑像素）
## [职位, 名字]；职位为空 = 大标题；名字为空 = 小节标题
const ROLL := [
	["", "铁冠之争"],
	["", "THE IRON CROWN"],
	["出品人 · 制作人 · 总策划", "郑翊"],
	["程序 · 关卡 · 剧本执笔 · 代码作曲与音效", "Claude（Anthropic）\n在郑翊的策划与指导下完成"],
	["游戏引擎", "Godot Engine（MIT 许可）\nJuan Linietsky、Ariel Manzur 与 Godot 社区的贡献者"],
	["人物模型与动作", "Quaternius\nUniversal Base Characters · Universal Animation Library · Modular Character Outfits – Fantasy（CC0）"],
	["贴图", "Poly Haven（CC0）"],
	["字体", "Noto Sans SC（思源黑体）· Google\nSIL 开放字体许可 1.1"],
	["音乐与音效", "全部为本作原创，由代码合成"],
	["特别鸣谢", "每一位试玩并提出意见的玩家"],
	["", "Ooglex 游戏中心 · 2026"],
]

var scroll: ScrollContainer
var box: VBoxContainer
var back_btn: Button
var auto := true
var pos := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.015, 0.02, 0.035, 0.82)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)
	var center := HBoxContainer.new()
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	center.add_child(box)
	_fill()
	back_btn = Button.new()
	back_btn.text = "返回"
	back_btn.custom_minimum_size = Vector2(96, 40)
	back_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	back_btn.position = Vector2(-112, 16)
	back_btn.add_theme_stylebox_override("normal", StartMenu._sb(Color(0.07, 0.09, 0.13, 0.9), StartMenu.GOLD.darkened(0.4), 1))
	back_btn.add_theme_stylebox_override("hover", StartMenu._sb(Color(0.13, 0.12, 0.1, 0.95), StartMenu.GOLD, 2, true))
	back_btn.add_theme_stylebox_override("focus", StartMenu._sb(Color(0, 0, 0, 0), StartMenu.GOLD_HI, 2, true, false))
	back_btn.pressed.connect(close)
	add_child(back_btn)
	scroll.get_v_scroll_bar().scrolling.connect(func(): auto = false)
	scroll.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton or e is InputEventScreenDrag:
			auto = false)
	get_tree().root.size_changed.connect(_fit)
	hide()


func _fill() -> void:
	UiKit.clear(box)
	var top := Control.new()
	top.name = "TopGap"
	box.add_child(top)
	for row in ROLL:
		var role: String = row[0]
		var who: String = row[1]
		if role == "":
			var l := _label(who, 40 if who == "铁冠之争" else 22, Color("e9cf8c") if who != "THE IRON CROWN" else Color("b9c6d8"))
			if who == "铁冠之争" or who == "THE IRON CROWN":
				l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			box.add_child(_gap(10 if who != "THE IRON CROWN" else 26))
			continue
		_label(role, 16, Color("9fb2c6"))
		var n := _label(who, 26 if who == "郑翊" else 19, Color("f0e4c6"))
		if who == "郑翊":
			n.add_theme_color_override("font_shadow_color", Color(0.9, 0.7, 0.3, 0.3))
			n.add_theme_constant_override("shadow_outline_size", 14)
			n.add_theme_constant_override("shadow_offset_y", 0)
		box.add_child(_gap(30))
	var bottom := Control.new()
	bottom.name = "BottomGap"
	box.add_child(bottom)


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("outline_size", 4)
	box.add_child(l)
	return l


func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = h
	return c


func open() -> void:
	show()
	auto = not Settings.reduced_motion
	_fit()
	pos = 0.0
	scroll.scroll_vertical = 0
	back_btn.grab_focus.call_deferred()
	print("IC_CREDITS open")


func close() -> void:
	if not visible:
		return
	hide()
	closed.emit()


func _fit() -> void:
	if not is_inside_tree():
		return
	var sz := UiKit.logical_size(self)
	var w := minf(620.0, sz.x - 40.0)
	for c in box.get_children():
		if c is Label:
			c.custom_minimum_size.x = w
	# 上下各留一屏空：从屏幕底下滚上来，滚完离开屏幕顶
	(box.get_node("TopGap") as Control).custom_minimum_size.y = sz.y * (0.85 if auto else 0.12)
	(box.get_node("BottomGap") as Control).custom_minimum_size.y = sz.y * 0.6


func _process(delta: float) -> void:
	if not visible or not auto:
		return
	pos += SPEED * delta
	var max_v := scroll.get_v_scroll_bar().max_value - scroll.size.y
	if pos >= max_v:
		pos = 0.0                                          # 滚完从头再来
	scroll.scroll_vertical = int(pos)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
	elif event.is_action_pressed("ui_down") or event.is_action_pressed("ui_up"):
		auto = false
		scroll.scroll_vertical += 60 if event.is_action_pressed("ui_down") else -60
