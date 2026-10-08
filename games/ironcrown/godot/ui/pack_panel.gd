class_name PackPanel
extends Control
## 章节资源包的下载画面（路线图 4.1；TECH.md 第六节「加载画面显示真实进度与失败重试」）。
## 压在画面最上层：章节名、进度条、「已下载 1.2 / 3.4 MB」；失败时写明原因，给「重试」「返回」两个按钮（键盘、触屏都能点）。
## 打开时游戏暂停；包很小、一下就好时也闪一下（不做假进度）。减少动态效果时不做渐显。

signal retry_requested
signal cancel_requested

var title: Label
var bar: ProgressBar
var detail: Label
var retry_btn: Button
var cancel_btn: Button
var box: VBoxContainer
var failed := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.05, 0.08, 0.92)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.custom_minimum_size = Vector2(280, 0)
	center.add_child(box)
	title = Label.new()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color("e8dcc0"))
	box.add_child(title)
	bar = ProgressBar.new()
	bar.custom_minimum_size = Vector2(280, 14)
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 1.0
	box.add_child(bar)
	detail = Label.new()
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	detail.custom_minimum_size = Vector2(280, 0)
	detail.add_theme_color_override("font_color", Color("c8bca0"))
	box.add_child(detail)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	retry_btn = Button.new()
	retry_btn.text = "重试"
	retry_btn.custom_minimum_size = Vector2(110, 44)
	retry_btn.pressed.connect(func(): retry_requested.emit())
	row.add_child(retry_btn)
	cancel_btn = Button.new()
	cancel_btn.text = "返回"
	cancel_btn.custom_minimum_size = Vector2(110, 44)
	cancel_btn.pressed.connect(func(): cancel_requested.emit())
	row.add_child(cancel_btn)
	hide()


## 开始下载：章节名，进度清零，按钮藏起来
func open(chapter_name: String, reduced_motion := false) -> void:
	failed = false
	title.text = "正在载入 %s" % chapter_name
	bar.value = 0.0
	bar.visible = true
	detail.text = "正在下载这一章的内容……"
	retry_btn.visible = false
	cancel_btn.visible = false
	var w := clampf(get_viewport_rect().size.x - 48.0, 240.0, 420.0)
	for c in [bar, detail]:
		c.custom_minimum_size.x = w
	show()
	if not reduced_motion:
		box.modulate.a = 0.0
		create_tween().tween_property(box, "modulate:a", 1.0, 0.3)


## 进度：知道总大小就写「1.2 / 3.4 MB」并走进度条；不知道就只写已经下了多少
func set_progress(done: int, total: int) -> void:
	if failed:
		return
	if total > 0:
		bar.value = clampf(float(done) / total, 0.0, 1.0)
		detail.text = "已下载 %.1f / %.1f MB" % [done / 1048576.0, total / 1048576.0]
	else:
		detail.text = "已下载 %.1f MB" % (done / 1048576.0)


## 失败：写明原因，给「重试」「返回」
func fail(why: String) -> void:
	failed = true
	bar.visible = false
	detail.text = "× 没能载入：%s" % why
	retry_btn.visible = true
	cancel_btn.visible = true
	retry_btn.grab_focus.call_deferred()


func close() -> void:
	hide()
