class_name Hud
extends Control
## 平视显示（GDD.md 第十一节）：左上标题（标注占位）、屏幕中央准星、操作提示、右上「菜单」按钮；
## 1.3 起：准星下方的交互提示、屏幕上方的短提示（拾取、门锁着）、底部的 NPC 字幕。

signal menu_pressed
signal quest_pressed
signal bag_pressed
signal char_pressed
signal map_pressed             # 3.11：右上角「地图」

const TITLE := "铁冠之争 · 技术原型（NPC 与敌人为占位）"
const TITLE_SHORT := "铁冠之争（NPC 为占位）"     # 窄屏：右上角几个按钮放不下长标题（2.7）
const TITLE_FS := 18
const TITLE_FS_SMALL := 15     # 3.11：右上角五个按钮时，手机竖屏连短标题 18 号也放不下，再缩一号
const BTN_MIN := Vector2(44, 44)      # 右上角按钮最小 44 × 44（触屏点得准；都在触屏层放行的顶部 56 像素以内）

var title_label: Label
var hint_label: Label
var menu_btn: Button
var quest_btn: Button
var bag_btn: Button
var char_btn: Button
var map_btn: Button
var prompt_label: Label
var toast_label: Label
var subtitle_panel: PanelContainer
var subtitle_label: Label
var toast_left := 0.0
var subtitle_left := 0.0
var key_hint := "[E] "        # 触屏上不显示按键
var melee: Melee              # 体力条读它（2.4）
var bars_top := false         # 触屏：左下角是摇杆，体力条放到左上标题下面
var stamina_label: Label
var health_label: Label
var hurt_left := 0.0
var marker_left := 0.0
var marker_heavy := false
var touch_ref: Control        # 触屏按钮（TouchControls）：显示时底部提示和字幕要让开右下角的按钮列（3.8）
var battle: Battle            # 军阵（B.2）：有小队时，右上角按钮下面写小队还剩几个人、现在是什么命令
var squad_label: Label
var battle_label: Label       # 战况一行（B.3）：两边还剩几个人、士气怎样；打完写谁赢了
var surface_label: Label      # 脚下（4.4）：在泥潭里写「泥潭：走得慢，不能跑」（不只靠画面）；普通地面藏起来

const BAR_W := 180.0
const BAR_H := 6.0
const MARKER_TIME := 0.18
const HURT_TIME := 0.45
const ROW := 34.0             # 生命条与体力条的行距


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_label = Label.new()
	title_label.text = TITLE
	title_label.position = Vector2(16, 12)
	title_label.add_theme_font_size_override("font_size", TITLE_FS)
	title_label.add_theme_color_override("font_color", Color("e8dcc0"))
	add_child(title_label)
	hint_label = Label.new()
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	hint_label.add_theme_color_override("font_color", Color("e8dcc0"))
	hint_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	hint_label.add_theme_constant_override("outline_size", 6)
	add_child(hint_label)
	menu_btn = Button.new()
	menu_btn.text = "菜单"
	menu_btn.focus_mode = Control.FOCUS_NONE
	menu_btn.pressed.connect(func(): menu_pressed.emit())
	add_child(menu_btn)
	quest_btn = Button.new()
	quest_btn.text = "任务"
	quest_btn.focus_mode = Control.FOCUS_NONE
	quest_btn.pressed.connect(func(): quest_pressed.emit())
	add_child(quest_btn)
	bag_btn = Button.new()
	bag_btn.text = "背包"
	bag_btn.focus_mode = Control.FOCUS_NONE
	bag_btn.pressed.connect(func(): bag_pressed.emit())
	add_child(bag_btn)
	char_btn = Button.new()
	char_btn.text = "角色"
	char_btn.focus_mode = Control.FOCUS_NONE
	char_btn.pressed.connect(func(): char_pressed.emit())
	add_child(char_btn)
	map_btn = Button.new()
	map_btn.text = "地图"
	map_btn.focus_mode = Control.FOCUS_NONE
	map_btn.pressed.connect(func(): map_pressed.emit())
	add_child(map_btn)
	for b in [menu_btn, map_btn, quest_btn, bag_btn, char_btn]:
		b.custom_minimum_size = BTN_MIN
	prompt_label = _center_label(20)
	toast_label = _center_label(18)
	subtitle_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.06, 0.09, 0.82)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(12)
	subtitle_panel.add_theme_stylebox_override("panel", sb)
	subtitle_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	subtitle_label = Label.new()
	subtitle_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	subtitle_label.add_theme_color_override("font_color", Color("e8dcc0"))
	subtitle_panel.add_child(subtitle_label)
	subtitle_panel.hide()
	add_child(subtitle_panel)
	stamina_label = Label.new()
	stamina_label.add_theme_font_size_override("font_size", 14)
	stamina_label.add_theme_color_override("font_color", Color("e8dcc0"))
	stamina_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	stamina_label.add_theme_constant_override("outline_size", 4)
	stamina_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stamina_label.hide()
	add_child(stamina_label)
	health_label = stamina_label.duplicate()
	add_child(health_label)
	squad_label = Label.new()
	squad_label.add_theme_font_size_override("font_size", 15)
	squad_label.add_theme_color_override("font_color", Color("e8c88a"))
	squad_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	squad_label.add_theme_constant_override("outline_size", 4)
	squad_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	squad_label.hide()
	add_child(squad_label)
	battle_label = squad_label.duplicate()
	battle_label.add_theme_color_override("font_color", Color("e8dcc0"))
	battle_label.add_theme_font_size_override("font_size", 14)
	add_child(battle_label)
	surface_label = squad_label.duplicate()
	surface_label.name = "Surface"
	add_child(surface_label)
	resized.connect(_layout)
	_layout()


func _center_label(fs: int) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", Color("e8dcc0"))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


## 准星下方的交互提示；空字符串 = 隐藏
func show_prompt(text: String) -> void:
	prompt_label.text = (key_hint + text) if text != "" else ""
	_layout()


## 短提示；上一条还没消失时接在下面（一次对话里可能同时「新线索」+「任务更新」）
func toast(text: String, sec := 2.5) -> void:
	if toast_left > 0.0 and toast_label.text != "" and not toast_label.text.contains(text):
		toast_label.text += "\n" + text
	else:
		toast_label.text = text
	toast_left = maxf(toast_left, sec)
	_layout()


func say(text: String, sec := 4.5) -> void:
	subtitle_label.text = text
	subtitle_left = sec
	subtitle_panel.show()
	_layout()


## 命中时准星变成 ×（重击更大），文字之外再加形状，不只靠颜色
func hit_marker(heavy := false) -> void:
	marker_left = MARKER_TIME
	marker_heavy = heavy
	queue_redraw()


## 体力条：拔剑或体力没满时显示；文字写出数值，体力耗尽时写「喘息中」
func stamina_visible() -> bool:
	return melee != null and (melee.state != Melee.State.SHEATHED or melee.stamina < melee.stamina_max())


func bar_rect() -> Rect2:
	var y := 64.0 + ROW if bars_top else size.y - 28.0
	return Rect2(Vector2(16.0, y), Vector2(BAR_W, BAR_H))


## 生命条（2.5）：在体力条上面一行；受过伤或拔剑时显示
func health_rect() -> Rect2:
	return Rect2(bar_rect().position - Vector2(0, ROW), bar_rect().size)


func health_visible() -> bool:
	return melee != null and (melee.health < melee.health_max() or stamina_visible())


## 受伤：画面四周闪一圈暗红（同时生命条的数字变小，不只靠颜色）
func hurt_flash() -> void:
	hurt_left = HURT_TIME
	queue_redraw()


func _process(delta: float) -> void:
	if melee:
		var show := stamina_visible()
		stamina_label.visible = show
		if show:
			stamina_label.text = "体力 %d / %d%s" % [roundi(melee.stamina), roundi(melee.stamina_max()), " · 喘息中" if melee.exhausted else ""]
			stamina_label.position = bar_rect().position - Vector2(0, 22)
		var hs := health_visible()
		health_label.visible = hs
		if hs:
			health_label.text = "生命 %d / %d%s" % [melee.health, melee.health_max(), " · 失衡" if melee.staggered() else ""]
			health_label.position = health_rect().position - Vector2(0, 22)
		queue_redraw()
	refresh_squad()
	if hurt_left > 0.0:
		hurt_left -= delta
	if marker_left > 0.0:
		marker_left -= delta
		queue_redraw()
	if toast_left > 0.0:
		toast_left -= delta
		if toast_left <= 0.0:
			toast_label.text = ""
	if subtitle_left > 0.0:
		subtitle_left -= delta
		if subtitle_left <= 0.0:
			subtitle_panel.hide()
			_layout()                 # 竖屏触屏时提示排在字幕下面：字幕没了，提示往上挪


## 小队一行（B.2）：「◆ 小队 6 人：冲锋 · 1 跟随 2 坚守 3 冲锋」（触屏写「点「令」下命令」），右对齐在右上角按钮下面
func squad_text() -> String:
	if battle == null or not is_instance_valid(battle) or battle.squad.is_empty():
		return ""
	return "◆ 小队 %d 人：%s · %s" % [battle.squad_alive(), Battle.ORDERS.get(battle.squad_order, ""),
		"1 跟随 2 坚守 3 冲锋" if key_hint != "" else "点「令」下命令"]


func refresh_squad() -> void:
	var t := squad_text()
	squad_label.visible = t != ""
	if t != "" and t != squad_label.text:
		squad_label.text = t
		squad_label.reset_size()
	var y := menu_btn.position.y + menu_btn.size.y + 6.0
	if squad_label.visible:
		squad_label.position = Vector2(size.x - squad_label.size.x - 12.0, y)
		y += squad_label.size.y + 2.0
	var bt := battle_text()
	battle_label.visible = bt != ""
	if bt != "" and bt != battle_label.text:
		battle_label.text = bt
		battle_label.reset_size()
	if battle_label.visible:
		battle_label.position = Vector2(size.x - battle_label.size.x - 12.0, y)


## 战况一行（B.3）：「战况：白带 8 人（士气 稳）· 黑带 5 人 +4 援军（士气 动摇）」；打完「战况：白带胜（黑带溃逃）」
func battle_text() -> String:
	if battle == null or not is_instance_valid(battle) or not battle.started:
		return ""
	if battle.finished:
		if battle.winner == "":
			return "战况：两边都打光了"
		var why := "（%s溃逃）" % battle.sides.get(battle.routed, "") if battle.routed != "" and battle.routed != battle.winner else ""
		return "战况：%s胜%s" % [battle.sides.get(battle.winner, battle.winner), why]
	var parts: Array = []
	for side in battle.sides:
		var here := battle.side_count(side, false)
		var later := battle.side_count(side) - here
		parts.append("%s %d 人%s（士气 %s）" % [battle.sides[side], here, " +%d 援军" % later if later > 0 else "", Battle.morale_word(battle.side_morale(side))])
	return "战况：" + "· ".join(parts)


## 脚下的地面（Surface.label；"" = 藏起来）：电脑在左下角生命条上面，触屏在左上角体力条下面（左下角是摇杆）
func set_surface(text: String) -> void:
	surface_label.text = text
	surface_label.visible = text != ""
	_place_surface()


func _place_surface() -> void:
	if bars_top:
		surface_label.position = bar_rect().position + Vector2(BAR_W + 14.0, -22.0)   # 体力条右边（下面是屏幕上方的短提示、性能浮层，审查）
	else:
		surface_label.position = health_rect().position - Vector2(0, 46)


func set_hint(text: String) -> void:
	hint_label.text = text
	_layout()


func _layout() -> void:
	if surface_label:
		_place_surface()
	# 从右往左：菜单、地图（3.11）、任务、背包、角色
	var x := size.x - 12.0
	for b: Button in [menu_btn, map_btn, quest_btn, bag_btn, char_btn]:
		b.size = b.get_combined_minimum_size()
		x -= b.size.x
		b.position = Vector2(x, 10.0)
		x -= 8.0
	# 标题放不下就换短的，还放不下就再缩一号字
	title_label.text = TITLE
	title_label.add_theme_font_size_override("font_size", TITLE_FS)
	if title_label.get_minimum_size().x + 24.0 > char_btn.position.x:
		title_label.text = TITLE_SHORT
		if title_label.get_minimum_size().x + 24.0 > char_btn.position.x:
			title_label.add_theme_font_size_override("font_size", TITLE_FS_SMALL)
	var w := minf(size.x - 32.0, 760.0)
	for l in [prompt_label, toast_label]:
		l.size = Vector2(w, 0)
	prompt_label.position = Vector2((size.x - w) * 0.5, size.y * 0.5 + 18.0)
	toast_label.position = Vector2((size.x - w) * 0.5, size.y * 0.2)
	var sw := minf(size.x - 32.0, 640.0)
	var hint_y := size.y * 0.62
	var sub_y := size.y * 0.72
	var portrait_touch := false
	var landscape_touch := false
	if touch_ref and touch_ref.visible:
		# 触屏：右下角的按钮列会压住底部的提示和字幕。横屏收窄到摇杆和按钮列之间；竖屏放不下，挪到上半屏（短提示下面、准星上面）
		var side: float = size.x - touch_ref.buttons_rect().position.x + 8.0
		var band := size.x - side * 2.0
		if band >= 300.0:
			w = minf(w, band)
			sw = minf(sw, band)
			landscape_touch = true
		else:
			portrait_touch = true
			sub_y = size.y * 0.28
	# 自动换行的 Label 必须先给定宽度，否则按 0 宽度排版，字幕框变得很高却看不到字
	subtitle_label.custom_minimum_size = Vector2(sw - 24.0, 0)
	subtitle_panel.custom_minimum_size = Vector2(sw, 0)
	subtitle_panel.reset_size()
	if landscape_touch:                # 横屏触屏：字幕贴着底边（摇杆和按钮列都在两侧）
		sub_y = size.y - subtitle_panel.size.y - 12.0
	subtitle_panel.position = Vector2((size.x - sw) * 0.5, sub_y)
	if portrait_touch:
		hint_y = sub_y + (subtitle_panel.size.y + 8.0 if subtitle_panel.visible else 0.0)
	hint_label.size = Vector2(w, 0)
	if subtitle_panel.visible and not portrait_touch:      # 矮屏幕上提示放在字幕上面，不叠在一起
		hint_y = minf(hint_y, sub_y - hint_label.size.y - 6.0)
	hint_label.position = Vector2((size.x - w) * 0.5, hint_y)
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	if marker_left > 0.0:
		var r := 11.0 if marker_heavy else 7.0
		for s in [Vector2(1, 1), Vector2(1, -1)]:
			draw_line(c - s * r, c + s * r, Color(0, 0, 0, 0.7), 4.0)
			draw_line(c - s * r, c + s * r, Color("ffcf6a") if marker_heavy else Color("e8dcc0"), 2.0)
	else:
		draw_circle(c, 3.0, Color(0, 0, 0, 0.6))
		draw_circle(c, 2.0, Color("e8dcc0"))
	if hurt_left > 0.0:
		var a := 0.45 * hurt_left / HURT_TIME
		var t := 26.0
		var col := Color(0.55, 0.05, 0.03, a)
		draw_rect(Rect2(0, 0, size.x, t), col)
		draw_rect(Rect2(0, size.y - t, size.x, t), col)
		draw_rect(Rect2(0, 0, t, size.y), col)
		draw_rect(Rect2(size.x - t, 0, t, size.y), col)
	if melee and health_visible():
		var hr := health_rect()
		draw_rect(hr.grow(1.0), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(hr.position, Vector2(hr.size.x * clampf(float(melee.health) / melee.health_max(), 0.0, 1.0), hr.size.y)), Color("b0483a"))
	if melee and stamina_visible():
		var br := bar_rect()
		draw_rect(br.grow(1.0), Color(0, 0, 0, 0.6))
		var k := clampf(melee.stamina / melee.stamina_max(), 0.0, 1.0)
		draw_rect(Rect2(br.position, Vector2(br.size.x * k, br.size.y)), Color("b08a3e") if melee.exhausted else Color("d8c9a0"))
