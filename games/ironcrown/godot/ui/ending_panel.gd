class_name EndingPanel
extends Control
## 结束画面（路线图 3.7；STORY.md 第三节第 6 步「切片到此结束，画面停在渡口的雾里，出现『第一章 · 黑鹭堡　开发中』」）。
## 半透明的夜色压在渡口的画面上（不全黑：雾还看得见），慢慢浮出章节名、这一夜的回顾（按抉择 prologue_edric 写）和两个按钮：
## 「在雾里再走走」关掉画面接着玩；「从头再来」开一局新游戏（存档不动）。打开时游戏暂停，减少动态效果时不做渐显。
## 4.1：下一章能玩了（Chapters.PLAYABLE，main.playable_chapter）时，上面多一行「继续：第一章 · 黑鹭堡」，默认焦点在它上面。

signal closed
signal restart_requested
signal continue_requested(chapter: int)

const ENDINGS := ["prologue"]
## 抉择 → 这一夜的回顾
const RECAP := {
	"deliver": "你把埃德里克和借据交回了瓦伦家。维克托会感激你，埃德里克不会原谅你；塞拉斯空着手回了双钥港。",
	"release": "你放埃德里克带着借据坐船南下。他欠你一个人情；维克托还不知道真相。",
	"extort": "你扣下了借据，收了塞拉斯一百二十枚银币。埃德里克一个人回了镇上，双钥港的人会记住你。",
}
const SEAL := "借据背面压着一枚星铁冠印——老王生前亲手担保过这笔债。奥尔本修士把一本烧焦的旧书交给你：去黑鹭堡，别让任何人看见。"

var title: Label
var sub: Label
var recap: Label
var seal: Label
var back_btn: Button
var restart_btn: Button
var continue_btn: Button
var next_chapter := 0             # 「继续」去第几章（0 = 没有这个按钮）
var box: VBoxContainer
var choice := ""


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
	box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.custom_minimum_size = Vector2(300, 0)
	center.add_child(box)
	var prologue := Label.new()
	prologue.text = "序章「霜渡镇之夜」完"
	prologue.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prologue.add_theme_color_override("font_color", Color("9fb2c6"))
	box.add_child(prologue)
	title = Label.new()
	title.text = "第一章 · 黑鹭堡"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", Color("e8dcc0"))
	box.add_child(title)
	sub = Label.new()
	sub.text = "开发中"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 22)
	sub.add_theme_color_override("font_color", Color("c8a060"))
	box.add_child(sub)
	for i in 2:
		var l := Label.new()
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		l.custom_minimum_size = Vector2(300, 0)
		l.add_theme_color_override("font_color", Color("c8bca0"))
		box.add_child(l)
		if i == 0:
			recap = l
		else:
			seal = l
	continue_btn = Button.new()         # 自己占一行：手机竖屏上三个按钮排一行放不下
	continue_btn.custom_minimum_size = Vector2(260, 48)
	continue_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	continue_btn.pressed.connect(func(): continue_requested.emit(next_chapter))
	continue_btn.visible = false
	box.add_child(continue_btn)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	back_btn = Button.new()
	back_btn.text = "在雾里再走走"
	back_btn.custom_minimum_size = Vector2(140, 44)
	back_btn.pressed.connect(close)
	row.add_child(back_btn)
	restart_btn = Button.new()
	restart_btn.text = "从头再来"
	restart_btn.custom_minimum_size = Vector2(120, 44)
	restart_btn.pressed.connect(func(): restart_requested.emit())
	row.add_child(restart_btn)
	hide()


## 打开：按抉择写回顾；宽度跟着窗口收（手机竖屏不溢出）
func open(c: String, reduced_motion := false, next := 0) -> void:
	choice = c
	next_chapter = next if Chapters.known(next) else 0
	continue_btn.visible = next_chapter > 0
	continue_btn.text = "继续：%s" % Chapters.name_of(next_chapter)
	recap.text = str(RECAP.get(c, ""))
	recap.visible = recap.text != ""
	seal.text = SEAL
	var w := clampf(get_viewport_rect().size.x - 48.0, 260.0, 560.0)
	for l in [recap, seal]:
		l.custom_minimum_size = Vector2(w, 0)
	show()
	if not reduced_motion:
		box.modulate.a = 0.0
		create_tween().tween_property(box, "modulate:a", 1.0, 1.6)
	(continue_btn if next_chapter > 0 else back_btn).grab_focus.call_deferred()


func close() -> void:
	if not visible:
		return
	hide()
	closed.emit()
