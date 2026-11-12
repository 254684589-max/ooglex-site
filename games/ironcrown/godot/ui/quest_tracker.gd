class_name QuestTracker
extends Control
## 任务追踪（路线图 C.2）：左上角标题下面一块——任务名、做完的步骤打勾（灰）、现在这一步写「进行中」和说明；
## 再加一个跟着目标走的标记：目标在画面里就在它头顶画「◆ 名字 · 120 米」，在画面外（或者身后）就贴在屏幕边上、带一个指向它的箭头。
## 打开对话、菜单时由 HUD 跟着别的东西一起藏；main 每帧调 update_marker()，任务变了调 refresh()。

const WIDTH := 340.0
const WIDTH_NARROW := 230.0
const EDGE := 36.0
const GOLD := Color("e8c88a")
const TEXT := Color("e8dcc0")
const DONE := Color(0.72, 0.7, 0.64, 0.8)

var box: VBoxContainer
var panel: PanelContainer
var title: Label
var lines: Array[Label] = []
var marker: Label
var arrow: Polygon2D
var quest_id := ""
var narrow := false
var target := {}                   # 最近一次算出来的目标（测试看）
var marker_text := ""
var retarget_left := 0.0            # 每 RETARGET 秒重新找一次目标（找遍整个场景的可交互物不便宜），标记位置每帧跟着算
const RETARGET := 0.5


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.06, 0.09, 0.55)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)
	title = _label(16, GOLD)
	box.add_child(title)
	marker = _label(18, GOLD)                    # 雪地上看得清：大一号、金色、底下垫一块半透明的深色（第一版 15 号白字压在雪上看不清）
	var mb := StyleBoxFlat.new()
	mb.bg_color = Color(0.04, 0.06, 0.09, 0.6)
	mb.set_corner_radius_all(5)
	mb.content_margin_left = 8
	mb.content_margin_right = 8
	mb.content_margin_top = 2
	mb.content_margin_bottom = 2
	marker.add_theme_stylebox_override("normal", mb)
	marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	marker.autowrap_mode = TextServer.AUTOWRAP_OFF
	marker.hide()
	add_child(marker)
	arrow = Polygon2D.new()
	arrow.polygon = PackedVector2Array([Vector2(16, 0), Vector2(-9, -11), Vector2(-4, 0), Vector2(-9, 11)])
	arrow.color = GOLD
	arrow.hide()
	add_child(arrow)
	panel.hide()


func _label(fs: int, c: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", c)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 4)
	l.autowrap_mode = UiKit.wrap_mode()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## 放在哪儿：top = 标题下面的 y；窄屏（手机竖屏）窄一点、字小一点
func place(top: float, is_narrow: bool) -> void:
	narrow = is_narrow
	panel.position = Vector2(12, top)
	var w := WIDTH_NARROW if narrow else WIDTH
	panel.custom_minimum_size = Vector2(w, 0)
	for l in [title] + lines:
		(l as Label).custom_minimum_size = Vector2(w - 16, 0)
	panel.size = Vector2(w, 0)


## 任务变了：重写左上角
func refresh() -> void:
	quest_id = QuestGuide.tracked()
	retarget_left = 0.0
	for l in lines:
		l.queue_free()
	lines.clear()
	if quest_id == "":
		panel.hide()
		return
	title.text = "◆ " + QuestGuide.title_of(quest_id)
	var w := (WIDTH_NARROW if narrow else WIDTH) - 16
	for s: Array in QuestGuide.steps(quest_id, 1 if narrow else 2):
		var l := _label(13 if narrow else 14, DONE if s[1] else TEXT)
		l.text = ("✓ " if s[1] else I18n.t("▶ 进行中：")) + str(s[0])
		l.custom_minimum_size = Vector2(w, 0)
		box.add_child(l)
		lines.append(l)
	panel.show()
	panel.size = Vector2(w + 16, 0)


## 每帧：目标在哪、离多远
func update_marker(world: Node, cam: Camera3D, from: Vector3, area: String, delta := 0.0) -> void:
	retarget_left -= delta
	if retarget_left <= 0.0 or (target.has("node") and not is_instance_valid(target.node)):
		retarget_left = RETARGET
		target = QuestGuide.target(world, from, quest_id, area) if quest_id != "" and world else {}
	marker_text = ""
	if target.is_empty() or cam == null:
		marker.hide()
		arrow.hide()
		return
	if target.has("elsewhere"):
		marker_text = I18n.t("目标在%s（打开地图出发）") % target.elsewhere
		marker.text = marker_text
		marker.reset_size()
		marker.position = Vector2((size.x - marker.size.x) * 0.5, size.y - 150.0)
		marker.show()
		arrow.hide()
		return
	var at: Vector3 = (target.node as Node3D).global_position if target.has("node") else target.pos
	at += Vector3(0, 2.3, 0)
	var d := Vector2(at.x - from.x, at.z - from.z).length()
	marker_text = "◆ %s · %s" % [I18n.t(str(target.get("label", ""))), QuestGuide.distance_text(d)]
	marker.text = marker_text
	marker.reset_size()
	var local := cam.global_transform.affine_inverse() * at          # 相机坐标：-Z 是前方
	var front := local.z < -0.1                                       # 正好在相机侧面（深度 0）时不能投影（引擎报 p.d == 0）
	var sp := cam.unproject_position(at) if front else Vector2.ZERO
	var vr := Rect2(Vector2(EDGE, EDGE + 40.0), size - Vector2(EDGE * 2.0, EDGE * 2.0 + 120.0))
	if front and vr.has_point(sp):
		marker.position = sp - Vector2(marker.size.x * 0.5, marker.size.y)
		arrow.hide()
	else:
		var c := size * 0.5
		var dir := (sp - c) if front else Vector2(local.x, -local.y)    # 在身后、侧面：按它在你左边还是右边指
		if dir.length() < 1.0:
			dir = Vector2(0, 1)
		dir = dir.normalized()
		var k := minf(absf((vr.size.x * 0.5) / dir.x) if absf(dir.x) > 0.001 else INF, absf((vr.size.y * 0.5) / dir.y) if absf(dir.y) > 0.001 else INF)
		var edge := vr.get_center() + dir * k
		arrow.position = edge
		arrow.rotation = dir.angle()
		arrow.show()
		marker.position = (edge - dir * 44.0) - marker.size * 0.5
	marker.position.x = clampf(marker.position.x, 4.0, size.x - marker.size.x - 4.0)
	marker.position.y = clampf(marker.position.y, 4.0, size.y - marker.size.y - 4.0)
	marker.show()
