class_name MapPanel
extends Control
## 地图册的「本地」「一带」两页（路线图 3.11；所有者 2026-10-09「区域地图 / 总图界面——加上」）。第三页「北境西部」就是旅行地图（ui/travel_map.gd），
## 两个面板顶上是同一种页签条（MapTabs），切到「北境西部」时发 view_requested，由 main 换面板（main._switch_map）。
## 本地：当前区域的平面图，北朝上、按真实比例——走得到的范围、街和路、房子、水、树林、墓地、出口（带编号，信息栏里同样列出），你在哪、面朝哪。
## 一带：附近几处怎么连的示意图（不按比例），节点是按钮，选中看它和哪里相连。
## 地图只读区域规格（core/area_map.gd），不画人、不画东西、不标任务；只能看，不能从这里出发或传送。
## 打开时游戏暂停（main 管）；Esc 或 M 关上。宽高跟着窗口：横着的窗口信息栏放地图右边，竖着的放下面。
## 4.4 鹭沼那种大地图整张放不下（每米不到 4 像素）时可以缩放、拖动，「回到你这里」；现有的六个区域都整张放得下，不出缩放按钮。

signal closed
signal view_requested(view: String)       # 只会发 "travel"；本地、一带在面板里自己切

const PARCHMENT := TravelMap.PARCHMENT
const INK := TravelMap.INK
const INK_SOFT := TravelMap.INK_SOFT
const WATER := TravelMap.WATER
const ROAD := TravelMap.ROAD
const MUD := Color("7a6448")               # 泥潭（4.4 鹭沼）
const HERE := TravelMap.HERE
const MIN_PX_PER_M := 4.0                 # 整张放得下且每米不少于 4 像素：整张显示，不出缩放按钮
const DEFAULT_PX_PER_M := 6.0             # 放不下时一打开的缩放
const MAX_PX_PER_M := 24.0
const INFO_W := 300.0                     # 横排时信息栏宽
const INFO_H := 230.0                     # 竖排时信息栏最矮
const LABEL_FS := 15                      # 图上的字不小于 15 号，带羊皮纸色描边
const SCALES := [1, 2, 5, 10, 20, 50, 100]
const NO_MAP := "这里没有地图。"
const EXIT_HINT := "图上带编号的三角是出口；选一个出口，看它通往哪里、在你哪边。"
const NODE_HINT := "示意图：只画各处怎么连，不按比例。"
## 图例：只列这张图里真有的
const LEGEND := {"exit": "▲ 出口", "house": "■ 房屋", "furniture": "■ 家具", "road": "□ 路", "water": "≈ 水", "wood": "○ 树林",
	"graves": "+ 墓地", "mud": "褐色：泥潭（走得慢）", "reeds": "| 芦苇", "you": "△ 你（尖头朝你面对的方向）"}
## 面板上会显示的固定文字（字体测试用，AreaMap.texts() 收）
const TEXTS := ["关上地图", "放大", "缩小", "回到你这里", NO_MAP, EXIT_HINT, NODE_HINT, "你在：", "，面朝", " · ", "：通往", "。在你", "。就在你旁边。",
	"边约", " 米", "就在你旁边", "离你约", "；", " → ", "你", "北", "▲ 出口 · ■ 房屋 · ■ 家具 · □ 路 · ≈ 水 · ○ 树林 · + 墓地 · △ 你（尖头朝你面对的方向）", "1234567890",
	"褐色：泥潭（走得慢） · | 芦苇"]

var tabs: MapTabs
var title: Label
var canvas: MapCanvas
var body: BoxContainer
var info: VBoxContainer
var where_label: Label
var detail_label: Label
var scroll: ScrollContainer
var list: VBoxContainer
var legend: Label
var zoom_row: HBoxContainer
var zoom_in_btn: Button
var zoom_out_btn: Button
var recenter_btn: Button
var close_btn: Button
var box: VBoxContainer
var wide := false
var view := "local"
var views: Array = ["local"]
var area := ""
var player_xz := Vector2.ZERO
var player_yaw := 0.0
var exit_btns: Array[Button] = []
var node_btns := {}                       # 区域 → 按钮（一带页）
var selected_exit := -1
var selected_node := ""
var fade: Tween                           # 渐显：再打开 / 关上时先停掉（审查：快速关了又开，上一次的渐显还在跑，减少动态效果时也会半透明）


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.05, 0.08, 0.82)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	center.add_child(box)
	tabs = MapTabs.new()
	tabs.view_requested.connect(show_view)
	box.add_child(tabs)
	title = Label.new()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", UiKit.TEXT)
	box.add_child(title)
	body = BoxContainer.new()
	body.vertical = true
	body.add_theme_constant_override("separation", 10)
	box.add_child(body)
	canvas = MapCanvas.new()
	canvas.panel = self
	canvas.clip_contents = true
	canvas.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	canvas.focus_mode = Control.FOCUS_NONE
	body.add_child(canvas)
	info = VBoxContainer.new()
	info.add_theme_constant_override("separation", 6)
	body.add_child(info)
	where_label = Label.new()
	where_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	where_label.add_theme_font_size_override("font_size", 18)
	where_label.add_theme_color_override("font_color", UiKit.TEXT)
	info.add_child(where_label)
	detail_label = Label.new()
	detail_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	detail_label.add_theme_color_override("font_color", Color("c8a060"))
	info.add_child(detail_label)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info.add_child(scroll)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 6)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inner)
	list = VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	inner.add_child(list)
	legend = Label.new()
	legend.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	legend.add_theme_color_override("font_color", UiKit.TEXT_DIM)
	inner.add_child(legend)
	zoom_row = HBoxContainer.new()
	zoom_row.alignment = BoxContainer.ALIGNMENT_CENTER
	zoom_row.add_theme_constant_override("separation", 8)
	info.add_child(zoom_row)
	zoom_out_btn = _small_button(zoom_row, "缩小", func(): canvas.zoom(-1))
	zoom_in_btn = _small_button(zoom_row, "放大", func(): canvas.zoom(1))
	recenter_btn = _small_button(zoom_row, "回到你这里", func(): canvas.recenter())
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	info.add_child(row)
	close_btn = Button.new()
	close_btn.text = "关上地图"
	close_btn.custom_minimum_size = Vector2(110, 44)
	close_btn.add_theme_stylebox_override("focus", UiKit.focus_style())
	close_btn.pressed.connect(close)
	row.add_child(close_btn)
	get_tree().root.size_changed.connect(_fit)
	hide()


func _small_button(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(72, 44)
	b.add_theme_stylebox_override("focus", UiKit.focus_style())
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


## 打开：p_area 现在在哪个区域，p_view 先看哪一页，p_views 地图册有哪几页，xz / yaw_deg 你的位置和朝向
func open(p_area: String, p_view: String, p_views: Array, xz: Vector2, yaw_deg: float, reduced_motion := false) -> void:
	area = p_area
	views = p_views
	player_xz = xz
	player_yaw = yaw_deg
	show()
	show_view(p_view, false)
	var first: Control = tabs.active_button() if tabs.visible else close_btn
	_focus_later.call_deferred(first)
	if fade:
		fade.kill()
	if not reduced_motion:
		box.modulate.a = 0.0
		fade = create_tween()
		fade.tween_property(box, "modulate:a", 1.0, 0.35)
	else:
		box.modulate.a = 1.0


func _focus_later(c: Control) -> void:
	if is_instance_valid(c) and c.is_inside_tree() and c.is_visible_in_tree():
		c.grab_focus()


## 换一页：本地、一带在这里搭；北境西部交给 main（换成旅行地图）
func show_view(v: String, log_switch := true) -> void:
	if v == "travel":
		view_requested.emit("travel")
		return
	if not v in views:
		v = "local"
	view = v
	tabs.setup(views, v)
	selected_exit = -1
	selected_node = ""
	UiKit.clear(list)
	exit_btns.clear()
	for b in node_btns.values():
		canvas.remove_child(b)
		b.queue_free()
	node_btns.clear()
	if view == "region":
		_build_region()
	else:
		_build_local()
	_fit()
	if log_switch:
		print("IC_AREAMAP view=%s area=%s exits=%d nodes=%d links=%d" % [view, area, AreaMap.exits(area).size(), node_btns.size(),
			AreaMap.links(AreaMap.region_of(area)).size() if view == "region" else 0])
		var t := tabs.active_button()
		if t:
			_focus_later.call_deferred(t)
		print_screen()


## 给网页冒烟测试点：三个页签和「关上地图」的中心（窗口像素，已乘界面缩放；没有的写 -1）。布局摆好以后再打（等两帧）
func print_screen() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not visible:
		return
	var k := get_tree().root.content_scale_factor
	var pts := []
	for t in MapTabs.ORDER:
		var b: Button = tabs.btns.get(t)
		var c := b.get_global_rect().get_center() * k if b and b.is_visible_in_tree() else Vector2(-1, -1)
		pts.append_array([c.x, c.y])
	var cc := close_btn.get_global_rect().get_center() * k
	pts.append_array([cc.x, cc.y])
	print("IC_AREAMAP_SCREEN lx=%d ly=%d rx=%d ry=%d tx=%d ty=%d cx=%d cy=%d" % pts)


func _build_local() -> void:
	title.text = Areas.display_name(area)
	where_label.text = where_text()
	if not AreaMap.has_map(area):
		detail_label.text = ""
		legend.text = ""
		canvas.mode = "none"
		return
	canvas.mode = "local"
	var ex := AreaMap.exits(area)
	for i in ex.size():
		var e: Dictionary = ex[i]
		var b := Button.new()
		b.text = "%d → %s" % [i + 1, Areas.display_name(str(e.to))]
		b.custom_minimum_size = Vector2(0, 44)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_stylebox_override("focus", UiKit.focus_style())
		b.focus_entered.connect(select_exit.bind(i))
		b.pressed.connect(select_exit.bind(i))
		list.add_child(b)
		exit_btns.append(b)
	detail_label.text = EXIT_HINT if not ex.is_empty() else ""
	legend.text = legend_text()


func _build_region() -> void:
	var region := AreaMap.region_of(area)
	title.text = AreaMap.region_title(region)
	where_label.text = where_text()
	canvas.mode = "region"
	for a in AreaMap.region_areas(region):
		var b := Button.new()
		b.text = AreaMap.node_text(str(a), area)
		b.custom_minimum_size = Vector2(0, 44)
		b.add_theme_stylebox_override("focus", UiKit.focus_style())
		b.focus_entered.connect(select_node.bind(str(a)))
		b.pressed.connect(select_node.bind(str(a)))
		canvas.add_child(b)
		node_btns[str(a)] = b
	legend.text = NODE_HINT
	select_node(area)


## 你在哪、面朝哪（有分块的大地图写成「鹭沼 · 芦栈村」）
func where_text() -> String:
	if not AreaMap.has_map(area):
		return NO_MAP
	var t := "你在：" + Areas.display_name(area)
	var z := AreaMap.zone_at(area, player_xz)
	if z != "":
		t += " · " + z
	if view == "region" or not AreaMap.has_compass(area):
		return t                                         # 室内不说朝向（屋里的图和镇上的东南西北对不上）
	return t + "，面朝" + AreaMap.heading_text(player_yaw)


## 图例：这张图里真有的几种
func legend_text() -> String:
	var kinds := {}
	for sh in AreaMap.shapes(area):
		var k := str(sh.get("k", ""))
		kinds[{"square": "road", "pier": "road", "wall": "house", "boat": "house", "land": ""}.get(k, k)] = true
	var parts := []
	if not AreaMap.exits(area).is_empty():
		parts.append(LEGEND.exit)
	for k in ["house", "furniture", "road", "water", "mud", "reeds", "wood", "graves"]:
		if kinds.has(k):
			parts.append(LEGEND[k])
	parts.append(LEGEND.you)
	return " · ".join(parts)


## 选中一个出口：写它通往哪里、在你哪个方向多远；图上那个编号加圈
func select_exit(i: int) -> void:
	var ex := AreaMap.exits(area)
	if i < 0 or i >= ex.size():
		return
	selected_exit = i
	var e: Dictionary = ex[i]
	var compass := AreaMap.has_compass(area)
	var b := AreaMap.bearing_text(player_xz, e.at, compass)
	var where := "就在你旁边。" if b == "就在你旁边" else (("在你" + b + "。") if compass else (b + "。"))
	detail_label.text = "%s：通往%s。%s" % [e.name, Areas.display_name(str(e.to)), where]
	canvas.queue_redraw()


## 选中一带里的一处：它的出口都通往哪里
func select_node(a: String) -> void:
	selected_node = a
	var parts := []
	for e in AreaMap.exits(a):
		parts.append("%s → %s" % [e.name, Areas.display_name(str(e.to))])
	detail_label.text = "%s：%s" % [Areas.display_name(a), "；".join(parts)]
	canvas.queue_redraw()


func close() -> void:
	if not visible:
		return
	if fade:
		fade.kill()
	box.modulate.a = 1.0
	hide()
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("travel_map"):
		get_viewport().set_input_as_handled()
		close()


## 按窗口的逻辑尺寸摆。横着的窗口（宽 > 高）：地图在左、信息栏在右（宽 300）；竖着的：地图在上、信息栏在下（最矮 230）
func _fit() -> void:
	if not is_inside_tree() or not visible:
		return
	var logical := UiKit.logical_size(self)
	wide = logical.x > logical.y
	body.vertical = not wide
	var th := (MapTabs.HEIGHT + 8.0) if tabs.visible else 0.0
	var head := 30.0 + 8.0 + 24.0 + th                   # 标题、间距、上下留边、页签条
	var w: float
	var h: float
	var iw: float
	var ih := INFO_H
	if wide:
		w = minf(logical.x - 32.0 - INFO_W - 12.0, 900.0)
		h = clampf(logical.y - head - 10.0, 160.0, 600.0)
		iw = INFO_W
	else:
		w = minf(logical.x - 32.0, 600.0)
		ih = clampf(logical.y * 0.3, INFO_H, 300.0)        # 高的手机上信息栏高一点，三个出口不用滚动就看得全
		h = clampf(logical.y - head - ih - 10.0 - 10.0, 200.0, w * 1.4)
		iw = w
	# 本地页：画布按地图的长宽比收窄，不留一大片走不到的地方（竖排时宽度还是给信息栏用满）；一带页不用比高还宽太多
	if view == "region":
		w = minf(w, maxf(h * 1.3, 320.0))
	elif canvas.mode == "local":
		var vr := AreaMap.view_rect(area)
		if vr.size.y > 0.0:
			var px := minf(w / vr.size.x, h / vr.size.y)
			w = clampf(vr.size.x * px + 40.0, minf(280.0, w), w)
	canvas.custom_minimum_size = Vector2(w, h)
	info.custom_minimum_size = Vector2(iw, h if wide else ih)
	for l in [where_label, detail_label, legend]:
		l.custom_minimum_size = Vector2(iw - 12.0, 0)
	canvas.setup(Vector2(w, h))
	zoom_row.visible = canvas.zoomable
	_place_nodes.call_deferred()


## 一带页的节点按钮摆在示意图的位置上（0..1 → 画布像素），不出画布的边
func _place_nodes() -> void:
	var s := canvas.custom_minimum_size
	var members: Dictionary = AreaMap.regions().get(AreaMap.region_of(area), {}).get("areas", {})
	for a in node_btns:
		var b: Button = node_btns[a]
		var pos: Array = members.get(a, {}).get("pos", [0.5, 0.5])
		var sz := b.get_combined_minimum_size()
		var at := Vector2(float(pos[0]) * s.x, float(pos[1]) * s.y) - sz * 0.5
		at.x = clampf(at.x, 4.0, s.x - sz.x - 4.0)
		at.y = clampf(at.y, 4.0, s.y - sz.y - 4.0)
		b.position = at
		b.size = sz
	canvas.queue_redraw()


## 节点按钮的中心（画布坐标）：连线从这里画
func node_center(a: String) -> Vector2:
	var b: Button = node_btns.get(a)
	return b.position + b.size * 0.5 if b else Vector2.ZERO


## 画布：本地平面图 / 一带示意图
class MapCanvas extends Control:
	var panel: MapPanel
	var mode := "local"              # local / region / none
	var center := Vector2.ZERO       # 画布中心对着的世界 XZ
	var px_per_m := 1.0
	var fit_px := 1.0
	var zoomable := false
	var skipped_labels: Array = []
	var _drag_from := Vector2.INF

	## 按画布大小定缩放：整张放得下（每米不少于 4 像素）就整张显示；放不下就从你这里放大看，可以缩放、拖动
	func setup(s: Vector2) -> void:
		zoomable = false
		focus_mode = Control.FOCUS_NONE
		if mode != "local":
			queue_redraw()
			return
		var vr := AreaMap.view_rect(panel.area)
		fit_px = minf(s.x / vr.size.x, s.y / vr.size.y) * 0.92
		if fit_px >= MIN_PX_PER_M:
			px_per_m = fit_px
			center = vr.get_center()
		else:
			zoomable = true
			focus_mode = Control.FOCUS_ALL
			px_per_m = maxf(DEFAULT_PX_PER_M, fit_px)
			center = _clamp_center(panel.player_xz, s)
		queue_redraw()

	func world_to_canvas(p: Vector2) -> Vector2:
		return (p - center) * px_per_m + _size() * 0.5

	func _size() -> Vector2:
		return size if size.x > 0.0 else custom_minimum_size

	## 中心不出地图范围（放大以后看得到的那一块也不全是范围外）
	func _clamp_center(c: Vector2, s: Vector2) -> Vector2:
		var vr := AreaMap.view_rect(panel.area)
		var half := s * 0.5 / px_per_m
		var lo := vr.position + half
		var hi := vr.end - half
		return Vector2(clampf(c.x, minf(lo.x, vr.get_center().x), maxf(hi.x, vr.get_center().x)),
			clampf(c.y, minf(lo.y, vr.get_center().y), maxf(hi.y, vr.get_center().y)))

	func zoom(step: int) -> void:
		if not zoomable:
			return
		px_per_m = clampf(px_per_m * pow(1.5, step), fit_px, MAX_PX_PER_M)
		center = _clamp_center(center, _size())
		queue_redraw()

	func pan(delta_m: Vector2) -> void:
		if not zoomable:
			return
		center = _clamp_center(center + delta_m, _size())
		queue_redraw()

	func recenter() -> void:
		if not zoomable:
			return
		center = _clamp_center(panel.player_xz, _size())
		queue_redraw()

	func _gui_input(e: InputEvent) -> void:
		if not zoomable:
			return
		if (e is InputEventMouseButton or e is InputEventMouseMotion) and e.device == InputEvent.DEVICE_ID_EMULATION:
			return                 # 触屏拖动由 ScreenDrag 管；工程开着「触屏模拟鼠标」，模拟出来的鼠标再拖一遍就走两倍远（审查）
		if e is InputEventMouseButton:
			var mb := e as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT:
				_drag_from = mb.position if mb.pressed else Vector2.INF
				accept_event()
			elif mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
				zoom(1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1)
				accept_event()
		elif e is InputEventMouseMotion and _drag_from != Vector2.INF:
			var mm := e as InputEventMouseMotion
			pan(-mm.relative / px_per_m)
			accept_event()
		elif e is InputEventScreenDrag:
			pan(-(e as InputEventScreenDrag).relative / px_per_m)
			accept_event()
		elif e is InputEventKey and e.is_pressed() and has_focus():
			var k := e as InputEventKey
			var step := _size() * 0.1 / px_per_m
			match k.keycode:
				KEY_LEFT: pan(Vector2(-step.x, 0))
				KEY_RIGHT: pan(Vector2(step.x, 0))
				KEY_UP: pan(Vector2(0, -step.y))
				KEY_DOWN: pan(Vector2(0, step.y))
				KEY_EQUAL, KEY_PLUS, KEY_KP_ADD: zoom(1)
				KEY_MINUS, KEY_KP_SUBTRACT: zoom(-1)
				_: return
			accept_event()

	func _draw() -> void:
		var s := _size()
		match mode:
			"local":
				_draw_local(s)
			"region":
				_draw_region(s)
			_:
				draw_rect(Rect2(Vector2.ZERO, s), PARCHMENT.darkened(0.25))
				_hatch(s)
		if has_focus():
			draw_rect(Rect2(Vector2(2, 2), s - Vector2(4, 4)), HERE, false, 2.0)

	## 走不到的地方：压暗的羊皮纸 + 斜线
	func _hatch(s: Vector2) -> void:
		var x := -s.y
		while x < s.x:
			draw_line(Vector2(x, s.y), Vector2(x + s.y, 0), INK_SOFT, 1.0)
			x += 10.0

	func _rect_pts(r: Rect2) -> PackedVector2Array:
		return PackedVector2Array([world_to_canvas(r.position), world_to_canvas(Vector2(r.end.x, r.position.y)),
			world_to_canvas(r.end), world_to_canvas(Vector2(r.position.x, r.end.y))])

	func _shape_pts(sh: Dictionary) -> PackedVector2Array:
		if sh.has("pts"):
			var out := PackedVector2Array()
			for p in sh.pts:
				out.append(world_to_canvas(p))
			return out
		return _rect_pts(sh.get("rect", Rect2()))

	func _draw_local(s: Vector2) -> void:
		draw_rect(Rect2(Vector2.ZERO, s), PARCHMENT.darkened(0.25))
		_hatch(s)
		var area := panel.area
		var indoor := Areas.is_indoor(area)
		var b := _rect_pts(AreaMap.bounds(area))
		draw_colored_polygon(b, PARCHMENT)
		var shown := Rect2(center - s * 0.5 / px_per_m, s / px_per_m).grow(2.0)      # 只画看得见的
		var shs := AreaMap.shapes(area).filter(func(sh): return shown.intersects(AreaMap.shape_rect(sh), true))
		for k in ["water", "reeds", "land", "mud", "wood", "graves", "road", "square", "pier", "wall", "boat", "house", "furniture", "mark"]:
			for sh in shs:
				if str(sh.k) == k:
					_draw_shape(sh)
		var bl := b.duplicate()
		bl.append(b[0])
		draw_polyline(bl, INK, 4.0 if indoor else 2.0)
		var font := get_theme_default_font()
		var ex := AreaMap.exits(area)
		for i in ex.size():
			_draw_exit(ex[i], i, i == panel.selected_exit, font)
		var lab := place_labels()
		skipped_labels = lab.skipped
		for pl in lab.placed:
			var r: Rect2 = pl[1]
			var at := Vector2(r.position.x, r.position.y + LABEL_FS)
			draw_string_outline(font, at, str(pl[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FS, 4, PARCHMENT)
			draw_string(font, at, str(pl[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FS, INK)
		_draw_player(font)
		if AreaMap.has_compass(area):
			_draw_north(s, font)                           # 室内不画指北（屋里的图按屋子自己的朝向画）
		_draw_scale(s, font)

	func _draw_shape(sh: Dictionary) -> void:
		var k := str(sh.k)
		if k == "mark":
			_draw_mark(sh)
			return
		var pts := _shape_pts(sh)
		var r := Rect2(pts[0], Vector2.ZERO)
		for p in pts:
			r = r.expand(p)
		match k:
			"water":
				draw_colored_polygon(pts, Color(WATER, 0.55))
				_pattern(r, pts, 18.0, func(c: Vector2):
					draw_arc(c + Vector2(-3, 2), 3.5, PI * 1.1, PI * 1.9, 6, Color("4f6578"), 1.2)
					draw_arc(c + Vector2(3, 2), 3.5, PI * 1.1, PI * 1.9, 6, Color("4f6578"), 1.2))
			"wood":
				_pattern(r, pts, 14.0, func(c: Vector2): draw_arc(c, 3.2, 0.0, TAU, 10, INK_SOFT, 1.2))
			"land":                                                    # 干地（4.4 鹭沼）：羊皮纸底色，和走得到的地面一样
				draw_colored_polygon(pts, PARCHMENT)
			"mud":                                                     # 泥潭：褐色底、一点点的点
				draw_colored_polygon(pts, Color(MUD, 0.55))
				_pattern(r, pts, 10.0, func(c: Vector2): draw_circle(c, 1.3, Color(INK, 0.55)))
			"reeds":                                                   # 芦苇：一簇簇短竖线
				_pattern(r, pts, 12.0, func(c: Vector2):
					for dx in [-2.5, 0.0, 2.5]:
						draw_line(c + Vector2(dx, 3), c + Vector2(dx * 1.3, -4), Color("5d6a48"), 1.2))
			"graves":
				_pattern(r, pts, 14.0, func(c: Vector2):
					draw_line(c + Vector2(-3, 0), c + Vector2(3, 0), INK_SOFT, 1.4)
					draw_line(c + Vector2(0, -4), c + Vector2(0, 3), INK_SOFT, 1.4))
			"road", "square", "pier":
				draw_colored_polygon(pts, Color(ROAD, 0.5))
				var ol := pts.duplicate()
				ol.append(pts[0])
				draw_polyline(ol, INK_SOFT, 1.0)
			"wall":
				draw_colored_polygon(pts, INK)
				if r.size.x < 2.0 or r.size.y < 2.0:
					draw_rect(r.grow(1.0), INK)
			"boat":
				var c := r.get_center()
				var long := r.size.y >= r.size.x
				var boat := PackedVector2Array()
				if long:
					boat = PackedVector2Array([Vector2(c.x, r.position.y), Vector2(r.end.x, r.position.y + r.size.y * 0.2), Vector2(r.end.x, r.end.y - r.size.y * 0.2),
						Vector2(c.x, r.end.y), Vector2(r.position.x, r.end.y - r.size.y * 0.2), Vector2(r.position.x, r.position.y + r.size.y * 0.2)])
				else:
					boat = PackedVector2Array([Vector2(r.position.x, c.y), Vector2(r.position.x + r.size.x * 0.2, r.position.y), Vector2(r.end.x - r.size.x * 0.2, r.position.y),
						Vector2(r.end.x, c.y), Vector2(r.end.x - r.size.x * 0.2, r.end.y), Vector2(r.position.x + r.size.x * 0.2, r.end.y)])
				draw_colored_polygon(boat, Color(INK, 0.75))
			"house":
				draw_colored_polygon(pts, Color(INK, 0.85))
				var inset := pts.duplicate()
				inset.append(pts[0])
				draw_polyline(inset, Color(PARCHMENT, 0.6), 1.0)
			"furniture":
				draw_colored_polygon(pts, INK_SOFT)
				var ol := pts.duplicate()
				ol.append(pts[0])
				draw_polyline(ol, INK, 1.0)

	## 在多边形里每隔 step 像素画一个小花纹（水的波纹、树林的圈、墓地的十字）
	## 只在画布看得见的那一块里画（放大看大地图时，一大片树林、水面的外接矩形有几千像素）；花纹的格子仍按图形的左上角对齐，拖动时不跳
	func _pattern(r: Rect2, pts: PackedVector2Array, step: float, f: Callable) -> void:
		var vis := r.intersection(Rect2(Vector2.ZERO, _size()).grow(step))
		if vis.size.x <= 0.0 or vis.size.y <= 0.0:
			return
		var dy := step * 0.8
		var row := maxi(0, floori((vis.position.y - r.position.y - step * 0.5) / dy))
		var y := r.position.y + step * 0.5 + row * dy
		while y < vis.end.y:
			var x0 := r.position.x + step * (0.5 if row % 2 == 0 else 1.0)
			var x := x0 + maxi(0, floori((vis.position.x - x0) / step)) * step
			while x < vis.end.x:
				if Geometry2D.is_point_in_polygon(Vector2(x, y), pts):
					f.call(Vector2(x, y))
				x += step
			y += dy
			row += 1

	func _draw_mark(sh: Dictionary) -> void:
		var c := world_to_canvas(sh.at)
		match str(sh.get("icon", "")):
			"well":
				draw_arc(c, 6.0, 0.0, TAU, 16, INK, 2.0)
				draw_line(c + Vector2(-4, 0), c + Vector2(4, 0), INK, 1.5)
				draw_line(c + Vector2(0, -4), c + Vector2(0, 4), INK, 1.5)
			"tree":
				draw_circle(c, 4.0, INK)
				draw_circle(c, 2.0, Color(PARCHMENT, 0.5))
			"sign":
				draw_line(c + Vector2(0, 7), c + Vector2(0, -8), INK, 2.0)
				draw_rect(Rect2(c + Vector2(-1, -9), Vector2(10, 5)), INK)
			"fire":
				draw_arc(c + Vector2(0, 3), 6.0, PI, TAU, 10, INK, 2.0)
				draw_circle(c + Vector2(0, 1), 2.5, Color("c8702a"))

	## 出口：朝外的实心三角 + 旁边一个带编号的小圆（编号往区域里面挪一点）；选中的加金圈
	func _draw_exit(e: Dictionary, i: int, sel: bool, font: Font) -> void:
		var c := world_to_canvas(e.at)
		var d: Vector2 = e.dir
		var side := Vector2(-d.y, d.x)
		var tip := c + d * 10.0
		draw_colored_polygon(PackedVector2Array([tip, c - d * 2.0 + side * 7.0, c - d * 2.0 - side * 7.0]), INK)
		var n := exit_number_pos(e)
		if sel:
			draw_circle(n, 13.0, Color(HERE, 0.9))
		draw_circle(n, 10.0, PARCHMENT)
		draw_arc(n, 10.0, 0.0, TAU, 20, INK, 2.0)
		var t := str(i + 1)
		var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		draw_string(font, n + Vector2(-tw * 0.5, 5), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, INK)

	func exit_number_pos(e: Dictionary) -> Vector2:
		var d: Vector2 = e.dir
		return world_to_canvas(e.at) - d * 16.0 + Vector2(-d.y, d.x) * 16.0

	## 你：金色三角，尖头朝你面对的方向（yaw 0 = 北 = 图的上方），墨色描边、羊皮纸色光晕，旁边写「你」
	func _draw_player(font: Font) -> void:
		var c := world_to_canvas(panel.player_xz)
		var r := deg_to_rad(panel.player_yaw)
		var f := Vector2(-sin(r), -cos(r))
		var sd := Vector2(-f.y, f.x)
		var tri := PackedVector2Array([c + f * 12.0, c - f * 7.0 + sd * 8.0, c - f * 7.0 - sd * 8.0])
		draw_circle(c, 13.0, Color(PARCHMENT, 0.7))
		draw_colored_polygon(tri, HERE)
		var ol := tri.duplicate()
		ol.append(tri[0])
		draw_polyline(ol, INK, 2.0)
		var at := c + Vector2(13, -10)
		draw_string_outline(font, at, "你", HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FS, 4, PARCHMENT)
		draw_string(font, at, "你", HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FS, INK)

	func _draw_north(s: Vector2, font: Font) -> void:
		var n := Vector2(s.x - 22.0, 26.0)
		draw_circle(n + Vector2(0, 6), 16.0, Color(PARCHMENT, 0.8))
		draw_line(n + Vector2(0, 14), n + Vector2(0, -6), INK, 2.0)
		draw_colored_polygon(PackedVector2Array([n + Vector2(0, -12), n + Vector2(-5, -3), n + Vector2(5, -3)]), INK)
		draw_string_outline(font, n + Vector2(-7, 32), "北", HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FS, 4, PARCHMENT)
		draw_string(font, n + Vector2(-7, 32), "北", HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FS, INK)

	## 比例尺：挑一档（1、2、5…100 米）画成 40–120 像素长
	func _draw_scale(s: Vector2, font: Font) -> void:
		var m := int(SCALES[-1])
		for v in SCALES:
			if float(v) * px_per_m >= 40.0:
				m = int(v)
				break
		var len := float(m) * px_per_m
		var a := Vector2(12.0, s.y - 14.0)
		draw_rect(Rect2(a + Vector2(-4, -22), Vector2(len + 8, 30)), Color(PARCHMENT, 0.8))
		draw_line(a, a + Vector2(len, 0), INK, 2.0)
		for x in [0.0, len]:
			draw_line(a + Vector2(x, -5), a + Vector2(x, 3), INK, 2.0)
		draw_string(font, a + Vector2(0, -8), "%d 米" % m, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, INK)

	## 标签往哪儿摆：出口编号先占位，再按「有名字的房子 → 地标 → 其余」摆，和已经摆好的重叠就不写（记在 skipped 里）
	func place_labels() -> Dictionary:
		var font := get_theme_default_font()
		var s := _size()
		var taken: Array = []
		for e in AreaMap.exits(panel.area):
			taken.append(Rect2(exit_number_pos(e) - Vector2(11, 11), Vector2(22, 22)))
		taken.append(Rect2(world_to_canvas(panel.player_xz) - Vector2(14, 22), Vector2(46, 36)))     # 你和「你」字
		taken.append(Rect2(Vector2(s.x - 44, 0), Vector2(44, 62)))                                   # 指北
		var cands: Array = []
		for sh in AreaMap.shapes(panel.area):
			var t := str(sh.get("label", ""))
			if t == "":
				continue
			var k := str(sh.k)
			var pri := 0 if k == "house" else (1 if k == "mark" else 2)
			var at: Vector2
			if k == "mark":
				at = world_to_canvas(sh.at) + Vector2(0, -16)
			elif sh.has("pts"):
				var c := Vector2.ZERO
				for p in sh.pts:
					c += p
				at = world_to_canvas(c / float((sh.pts as PackedVector2Array).size()))
			else:
				at = world_to_canvas((sh.rect as Rect2).get_center())
			cands.append([pri, t, at])
		cands.sort_custom(func(a, b): return a[0] < b[0])
		var placed: Array = []
		var skipped: Array = []
		var area_r := Rect2(Vector2.ZERO, s)
		for c in cands:
			var sz := font.get_string_size(str(c[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FS)
			var h := LABEL_FS * 1.3
			var base := Rect2(c[2] - Vector2(sz.x * 0.5, LABEL_FS * 0.6), Vector2(sz.x, h))
			var done := false
			# 先摆在正中，挤了就往上、下、左、右挪一点
			for off in [Vector2.ZERO, Vector2(0, -h - 2.0), Vector2(0, h + 2.0), Vector2(-sz.x * 0.5 - 12.0, 0), Vector2(sz.x * 0.5 + 12.0, 0),
					Vector2(0, -2.0 * h - 4.0), Vector2(0, 2.0 * h + 4.0)]:
				var r := Rect2(base.position + off, base.size)
				if not area_r.encloses(r) or taken.any(func(t: Rect2): return t.grow(2.0).intersects(r)):
					continue
				placed.append([c[1], r])
				taken.append(r)
				done = true
				break
			if not done:
				skipped.append(c[1])
		return {"placed": placed, "skipped": skipped}

	## 一带示意图：羊皮纸底、河、各处之间的路（虚线）、室内连到它所在的室外（短实线）、你所在的地方加金圈；节点本身是按钮
	func _draw_region(s: Vector2) -> void:
		var font := get_theme_default_font()
		draw_rect(Rect2(Vector2.ZERO, s), PARCHMENT)
		draw_rect(Rect2(Vector2(4, 4), s - Vector2(8, 8)), INK_SOFT, false, 2.0)
		var region := AreaMap.region_of(panel.area)
		var rd: Dictionary = AreaMap.regions().get(region, {})
		var river: Dictionary = rd.get("river", {})
		if not river.is_empty():
			var pl := PackedVector2Array()
			for p in river.get("pts", []):
				pl.append(Vector2(float(p[0]), float(p[1])) * s)
			if pl.size() >= 2:
				draw_polyline(pl, WATER, maxf(s.x / 70.0, 5.0), true)
				var mid := pl[pl.size() / 2]
				draw_string_outline(font, mid + Vector2(-24, -10), str(river.get("label", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FS, 4, PARCHMENT)
				draw_string(font, mid + Vector2(-24, -10), str(river.get("label", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FS, Color("4f6578"))
		var members: Dictionary = rd.get("areas", {})
		for pair in AreaMap.links(region):
			var a := str(pair[0])
			var b := str(pair[1])
			var pa := panel.node_center(a)
			var pb := panel.node_center(b)
			if members.get(a, {}).has("host") or members.get(b, {}).has("host"):
				draw_line(pa, pb, INK_SOFT, 3.0)              # 进屋：短实线
			else:
				draw_dashed_line(pa, pb, ROAD, 3.0, 9.0)
		for a in panel.node_btns:
			var bt: Button = panel.node_btns[a]
			var r := Rect2(bt.position, bt.size)
			if a == panel.area:
				draw_rect(r.grow(5.0), HERE, false, 3.0)
			if a == panel.selected_node:
				draw_rect(r.grow(2.0), Color(HERE, 0.35))
		_draw_north(s, font)
