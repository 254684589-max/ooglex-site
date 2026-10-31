class_name OriginPanel
extends Control
## 出身三选一（路线图 O.1）：新游戏压在开场的标题卡上（选了才开始，这一下同时是开场的「第一次操作」）；旧存档读进来时问一次（暂停着）。
## 三个大按钮竖着排（手机竖屏放得下）：出身名 + 一句话 + 开局多了什么；下面一行小字是选中那个的来历。数字键 1–3 也能选。

signal chosen(id: String)

var box: VBoxContainer
var title: Label
var desc: Label
var buttons := {}                  # 编号 → Button
var as_prompt := false             # 旧存档补问：背景压暗一些、写明「这份存档还没有出身」


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.name = "Dim"
	bg.color = Color(0.02, 0.03, 0.05, 0.35)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)
	title = Label.new()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color("e8dcc0"))
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	title.add_theme_constant_override("outline_size", 4)
	box.add_child(title)
	for id: String in Origins.ids():
		var b := Button.new()
		b.name = "Origin_" + id
		b.text = "%s\n%s\n%s" % [Origins.name_of(id), str(Origins.spec(id).get("short", "")), Origins.bonus_text(id)]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_constant_override("line_spacing", 2)
		b.pressed.connect(func(): _pick(id))
		b.focus_entered.connect(func(): desc.text = str(Origins.spec(id).get("desc", "")))
		b.mouse_entered.connect(func(): desc.text = str(Origins.spec(id).get("desc", "")))
		box.add_child(b)
		buttons[id] = b
	desc = Label.new()
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	desc.add_theme_color_override("font_color", Color("c8bca0"))
	desc.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	desc.add_theme_constant_override("outline_size", 3)
	box.add_child(desc)
	hide()


## 打开：prompt = true 是旧存档补问
func open(prompt := false) -> void:
	as_prompt = prompt
	title.text = "这份存档还没有出身——你是谁？" if prompt else "你是谁？"
	(get_node("Dim") as ColorRect).color = Color(0.02, 0.03, 0.05, 0.72 if prompt else 0.35)
	var w := clampf(get_viewport_rect().size.x - 40.0, 280.0, 520.0)
	for id in buttons:
		(buttons[id] as Button).custom_minimum_size = Vector2(w, 78)
	desc.custom_minimum_size = Vector2(w, 0)
	desc.text = str(Origins.spec(Origins.ids()[0]).get("desc", ""))
	show()
	(buttons[Origins.ids()[0]] as Button).grab_focus.call_deferred()
	print("IC_ORIGIN open prompt=%s" % prompt)
	await get_tree().process_frame
	await get_tree().process_frame
	var c := (buttons[Origins.ids()[0]] as Button).get_global_rect().get_center() * get_tree().root.content_scale_factor
	print("IC_ORIGIN_SCREEN x=%d y=%d" % [c.x, c.y])        # 给网页冒烟测试点（窗口像素，已乘界面缩放）


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed:
		return
	var k := (event as InputEventKey).keycode
	if k >= KEY_1 and k <= KEY_3 and k - KEY_1 < Origins.ids().size():
		get_viewport().set_input_as_handled()
		_pick(str(Origins.ids()[k - KEY_1]))


func _pick(id: String) -> void:
	if not visible:
		return
	hide()
	chosen.emit(id)
