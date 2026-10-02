class_name DefeatPanel
extends Control
## 倒下画面（路线图 2.5）：生命归零时游戏暂停，显示「你倒下了」与「重来」按钮（重新载入当前场景）。
## 存档在 2.8：到时改成「读取最近的存档」。

signal retry_requested

var retry_btn: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.02, 0.02, 0.78)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(box)
	var title := Label.new()
	title.text = "你倒下了"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color("e8dcc0"))
	box.add_child(title)
	var tip := Label.new()
	tip.text = "举剑格挡能把伤害换成体力；对方劈下前一瞬间格挡，能让他失衡。"
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	tip.custom_minimum_size = Vector2(300, 0)
	tip.add_theme_color_override("font_color", Color("c8bca0"))
	box.add_child(tip)
	retry_btn = Button.new()
	retry_btn.text = "重来"
	retry_btn.custom_minimum_size = Vector2(160, 44)
	retry_btn.pressed.connect(func(): retry_requested.emit())
	box.add_child(retry_btn)
	hide()


func open() -> void:
	show()
	retry_btn.grab_focus.call_deferred()
