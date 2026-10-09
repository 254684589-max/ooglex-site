class_name TravelMap
extends Control
## 旅行地图（路线图 4.2；STORY.md 4.2）：一张手绘风格的北境西部地图——东边南北流的灰鲸河、河边的霜渡镇，往西是鹭沼边的芦栈村，
## 沼中石岛上的黑鹭堡由一条堤道连着芦栈村（WORLD.md 第三节的地理）。地点是地图上的按钮：点一下（或用方向键 / Tab 移过去）看介绍和路线，
## 「出发」去那里（main.depart：出发前自动存档）。还没做好的地方照样画出来，写明「还没做好」，出发按钮灰着。
## 打开时游戏暂停；Esc 或 M 关上。宽高跟着窗口收：竖着放不下时（横屏手机）介绍和按钮挪到地图右边。

signal depart_requested(id: String)
signal closed

const PARCHMENT := Color("d6c6a0")
const INK := Color("4a3a28")
const INK_SOFT := Color(0.29, 0.23, 0.16, 0.55)
const WATER := Color("6f8aa0")
const MARSH := Color(0.42, 0.5, 0.36, 0.32)
const REEDS := Color(0.3, 0.38, 0.26, 0.55)
const ROAD := Color("7a5f3e")
const HERE := Color("b8964e")
## 鹭沼的轮廓（地图坐标 0..1）
const MARSH_SHAPE := [Vector2(0.04, 0.16), Vector2(0.3, 0.1), Vector2(0.5, 0.2), Vector2(0.58, 0.42), Vector2(0.56, 0.7),
	Vector2(0.4, 0.86), Vector2(0.16, 0.9), Vector2(0.04, 0.7)]
## 灰鲸河（自北向南）
const RIVER := [Vector2(0.9, 0.0), Vector2(0.87, 0.2), Vector2(0.9, 0.38), Vector2(0.86, 0.56), Vector2(0.89, 0.78), Vector2(0.87, 1.0)]

var title: Label
var canvas: Control
var name_label: Label
var blurb: Label
var route_label: Label
var status: Label
var go_btn: Button
var close_btn: Button
var box: VBoxContainer
var body: BoxContainer            # 地图 + 介绍：竖排（默认）或横排（矮的窗口）
var info: VBoxContainer           # 名字、介绍、路线、状态、按钮
var wide := false                 # 横排了
var place_btns := {}              # 地点编号 → 按钮
var chapter := 1
var here := ""                    # 现在在地图上的哪个地点（"" = 不在地图上的地方，例如酒馆里）
var at_departure := false         # 站在出发的地方（能出发）；不是就只能看
var selected := ""


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
	title = Label.new()
	title.text = "旅行地图 · 北境西部"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", UiKit.TEXT)
	box.add_child(title)
	body = BoxContainer.new()
	body.vertical = true
	body.add_theme_constant_override("separation", 10)
	box.add_child(body)
	canvas = MapCanvas.new()
	canvas.map = self
	canvas.clip_contents = true
	body.add_child(canvas)
	info = VBoxContainer.new()
	info.add_theme_constant_override("separation", 6)
	body.add_child(info)
	name_label = Label.new()
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.add_theme_color_override("font_color", UiKit.TEXT)
	info.add_child(name_label)
	for i in 3:
		var l := Label.new()
		l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		l.add_theme_color_override("font_color", [UiKit.TEXT_DIM, Color("9fb2c6"), Color("c8a060")][i])
		info.add_child(l)
		match i:
			0: blurb = l
			1: route_label = l
			2: status = l
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	info.add_child(row)
	go_btn = Button.new()
	go_btn.custom_minimum_size = Vector2(160, 44)
	go_btn.pressed.connect(func():
		if selected != "" and not go_btn.disabled:
			depart_requested.emit(selected))
	row.add_child(go_btn)
	close_btn = Button.new()
	close_btn.text = "关上地图"
	close_btn.custom_minimum_size = Vector2(110, 44)
	close_btn.pressed.connect(close)
	row.add_child(close_btn)
	get_tree().root.size_changed.connect(_fit)
	hide()


## 打开：c 第几章，h 现在在哪个地点，departure 是否站在出发的地方
func open(c: int, h: String, departure: bool, reduced_motion := false) -> void:
	chapter = c
	here = h
	at_departure = departure
	for b in place_btns.values():
		b.queue_free()
	place_btns.clear()
	var ids := Travel.places(chapter)
	for id in ids:
		var b := Button.new()
		b.text = Travel.name_of(id) + ("（你在这里）" if id == here else "")
		b.custom_minimum_size = Vector2(0, 44)
		b.focus_entered.connect(select.bind(id))
		b.pressed.connect(func():
			select(id)
			if not go_btn.disabled:
				go_btn.grab_focus())
		canvas.add_child(b)
		place_btns[id] = b
	var first := ""
	for id in ids:                        # 默认选第一个能去的地方；都去不了就选第一个不是这里的地方
		if Travel.check(chapter, here, id, at_departure).ok:
			first = id
			break
	if first == "":
		for id in ids:
			if id != here:
				first = id
				break
	if first == "" and not ids.is_empty():
		first = ids[0]
	show()
	_fit()
	if first != "":
		select(first)
		(place_btns[first] as Button).grab_focus.call_deferred()
	if not reduced_motion:
		box.modulate.a = 0.0
		create_tween().tween_property(box, "modulate:a", 1.0, 0.35)


## 选中一个地点：写名字、介绍、路线、能不能去
func select(id: String) -> void:
	selected = id
	var p := Travel.place(id)
	name_label.text = Travel.name_of(id) + (" · 你在这里" if id == here else "")
	blurb.text = str(p.get("blurb", ""))
	var c := Travel.check(chapter, here, id, at_departure)
	var r: Dictionary = c.route
	var line := ""
	if not r.is_empty():
		line = "路：%s" % str(r.get("text", ""))
		var dp := str(r.get("daypart", ""))
		if Daypart.valid(dp):
			line += "，到了是%s" % Daypart.display_name(dp)
	route_label.text = line
	route_label.visible = line != ""
	status.text = str(c.why)
	status.visible = status.text != ""
	go_btn.text = "出发去%s" % Travel.name_of(id)
	go_btn.disabled = not c.ok
	canvas.queue_redraw()


## 出发没走成（例如有人在打你）：写在状态行
func show_status(text: String) -> void:
	status.text = text
	status.visible = true


func close() -> void:
	if not visible:
		return
	hide()
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("travel_map"):
		get_viewport().set_input_as_handled()
		close()


## 按窗口的逻辑尺寸摆：地图宽 280..560、高 = 宽 × 0.56。竖排时下面要留约 290 的高度给标题、介绍和按钮；
## 留下的不够画一张 220 高的地图（横屏手机：逻辑尺寸约 987 × 480）就横排——介绍和按钮放到地图右边（宽 300）
func _fit() -> void:
	if not is_inside_tree() or not visible:
		return
	var logical := UiKit.logical_size(self)
	var room := logical.y - 290.0
	wide = room < 220.0 and logical.x >= 640.0
	body.vertical = not wide
	var iw := 300.0
	var w: float
	var h: float
	if wide:
		w = clampf(logical.x - 32.0 - iw - 10.0, 280.0, 560.0)
		h = minf(w * 0.56, logical.y - 90.0)
		w = minf(w, h / 0.56)
	else:
		w = clampf(logical.x - 32.0, 280.0, 560.0)
		h = w * 0.56
		if h > room:
			h = maxf(room, 150.0)
			w = clampf(h / 0.56, 280.0, w)
		iw = w
	canvas.custom_minimum_size = Vector2(w, h)
	for l in [name_label, blurb, route_label, status]:
		l.custom_minimum_size = Vector2(iw, 0)
	_place_buttons.call_deferred()


## 地点按钮摆在图标下面（地图坐标 → 画布像素），不出画布的边
func _place_buttons() -> void:
	var s := canvas.custom_minimum_size
	for id in place_btns:
		var b: Button = place_btns[id]
		var pos: Array = Travel.place(id).get("pos", [0.5, 0.5])
		var sz := b.get_combined_minimum_size()
		var at := Vector2(float(pos[0]) * s.x - sz.x * 0.5, float(pos[1]) * s.y + 14.0)
		at.x = clampf(at.x, 4.0, s.x - sz.x - 4.0)
		at.y = clampf(at.y, 4.0, s.y - sz.y - 4.0)
		b.position = at
		b.size = sz
	canvas.queue_redraw()


## 地图本身：羊皮纸底、鹭沼、灰鲸河、路与堤道、三个地点的图标、指北
class MapCanvas extends Control:
	var map: TravelMap

	func _to(v: Vector2) -> Vector2:
		return v * size

	func _draw() -> void:
		var s := size
		var font := get_theme_default_font()
		draw_rect(Rect2(Vector2.ZERO, s), PARCHMENT)
		draw_rect(Rect2(Vector2(4, 4), s - Vector2(8, 8)), INK_SOFT, false, 2.0)
		# 鹭沼：一片淡绿，里面一行行短横线是芦苇
		var poly := PackedVector2Array()
		for p in MARSH_SHAPE:
			poly.append(_to(p))
		draw_colored_polygon(poly, MARSH)
		var step := maxf(s.x / 26.0, 12.0)
		var y := step * 0.6
		var row := 0
		while y < s.y:
			var x := step * (0.5 if row % 2 == 0 else 1.0)
			while x < s.x:
				if Geometry2D.is_point_in_polygon(Vector2(x, y), poly):
					draw_line(Vector2(x - step * 0.22, y), Vector2(x + step * 0.22, y), REEDS, 1.5)
					draw_line(Vector2(x - step * 0.08, y - step * 0.2), Vector2(x - step * 0.04, y), REEDS, 1.0)
				x += step
			y += step * 0.7
			row += 1
		var fs := maxi(int(s.x / 28.0), 13)
		draw_string(font, _to(Vector2(0.09, 0.76)), "鹭 沼", HORIZONTAL_ALIGNMENT_LEFT, -1, fs + 4, INK_SOFT)
		# 灰鲸河
		var river := PackedVector2Array()
		for p in RIVER:
			river.append(_to(p))
		draw_polyline(river, WATER, maxf(s.x / 90.0, 4.0), true)
		var ry := 0.14
		for ch in "灰鲸河":
			draw_string(font, _to(Vector2(0.925, ry)), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("4f6578"))
			ry += 0.075
		# 路：霜渡镇 → 芦栈村 是土路（虚线），芦栈村 → 黑鹭堡 是石砌堤道（粗实线）
		for r in Travel.data().get("routes", []):
			var a := str(r.get("from", ""))
			var b := str(r.get("to", ""))
			if a > b or not a in map.place_btns or not b in map.place_btns:
				continue                       # 来回两条路线只画一次
			var pa := _pos(a)
			var pb := _pos(b)
			if "castle" in [str(Travel.place(a).get("icon", "")), str(Travel.place(b).get("icon", ""))]:
				draw_line(pa, pb, INK, maxf(s.x / 80.0, 5.0))
				draw_line(pa, pb, Color("b4a68a"), maxf(s.x / 200.0, 2.0))
				draw_string(font, (pa + pb) * 0.5 + Vector2(6, -6), "堤道", HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 1, INK)
			else:
				draw_dashed_line(pa, pb, ROAD, 2.5, 9.0)
		# 地点图标
		for id in map.place_btns:
			var c := _pos(id)
			var built := Travel.built(id)
			var col := INK if built else Color(0.29, 0.23, 0.16, 0.45)
			if id == map.selected:
				draw_circle(c, 17.0, Color(0.72, 0.59, 0.31, 0.35))
			if id == map.here:
				draw_arc(c, 15.0, 0.0, TAU, 32, HERE, 3.0, true)
			match str(Travel.place(id).get("icon", "")):
				"town":
					for dx in [-9.0, 0.0, 9.0]:
						var h := 7.0 if dx != 0.0 else 9.0
						draw_rect(Rect2(c + Vector2(dx - 3.5, -h + 4.0), Vector2(7, h)), col)
						draw_colored_polygon(PackedVector2Array([c + Vector2(dx - 5, -h + 4), c + Vector2(dx + 5, -h + 4), c + Vector2(dx, -h - 2)]), col)
				"village":
					for dx in [-8.0, 3.0]:
						draw_rect(Rect2(c + Vector2(dx - 3.5, -6), Vector2(8, 5)), col)
						draw_colored_polygon(PackedVector2Array([c + Vector2(dx - 5, -6), c + Vector2(dx + 6, -6), c + Vector2(dx + 0.5, -11)]), col)
						for lx in [dx - 2.5, dx + 3.5]:
							draw_line(c + Vector2(lx, -1), c + Vector2(lx, 5), col, 1.5)
				"castle":
					draw_circle(c + Vector2(0, 4), 14.0, Color(0.55, 0.53, 0.48, 0.6))     # 石岛
					draw_rect(Rect2(c + Vector2(-9, -8), Vector2(18, 12)), col)
					draw_rect(Rect2(c + Vector2(-4, -16), Vector2(8, 10)), col)
					for k in 3:
						draw_rect(Rect2(c + Vector2(-9 + k * 7, -11), Vector2(4, 3)), col)
		# 指北
		var n := Vector2(s.x * 0.68, 30.0)       # 鹭沼和灰鲸河之间的空白处（右上角是河名）
		draw_line(n + Vector2(0, 14), n + Vector2(0, -10), INK, 2.0)
		draw_colored_polygon(PackedVector2Array([n + Vector2(0, -16), n + Vector2(-5, -6), n + Vector2(5, -6)]), INK)
		draw_string(font, n + Vector2(-fs * 0.5, 32), "北", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, INK)

	func _pos(id: String) -> Vector2:
		var p: Array = Travel.place(id).get("pos", [0.5, 0.5])
		return Vector2(float(p[0]), float(p[1])) * size
