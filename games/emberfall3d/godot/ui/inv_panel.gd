class_name InvPanel
extends PanelContainer
## 背包面板（P6，对应 V0.1 openInv / detailHtml）：8 个装备部位 + 40 格背包 + 选中物品的说明、与已装备的比较、
## 「装备 / 卸下 / 丢在地上」。打开时游戏暂停（同 V0.1），I / Esc / × 关闭；按钮都能用键盘操作。
## 规则在 rules/inventory.gd。

signal closed
signal drop_requested(item: Dictionary)

const CELL := 46
const COLS := 8

var hero: Player
var title: Label
var eq_btns := {}
var inv_btns: Array[Button] = []
var detail: VBoxContainer
var act_equip: Button
var act_unequip: Button
var act_drop: Button
var foot: Label
var close_btn: Button
var sel := {}                # {where: "inv"/"eq", idx: int, slot: String}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.055, 0.045, 0.97)
	sb.border_color = Color(0.79, 0.64, 0.35)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(12)
	add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	title = _label(20, Color(1.0, 0.8, 0.45))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	close_btn = Button.new()
	close_btn.text = "×"
	close_btn.tooltip_text = "关闭（I / Esc）"
	close_btn.custom_minimum_size = Vector2(40, 40)
	close_btn.pressed.connect(close)
	top.add_child(close_btn)
	var eg := GridContainer.new()
	eg.columns = 8
	eg.add_theme_constant_override("h_separation", 4)
	v.add_child(eg)
	for s in Act1Data.items().slots:
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 0)
		var b := _slot_button()
		var sid: String = s.id
		b.pressed.connect(func(): _select({"where": "eq", "slot": sid}))
		cell.add_child(b)
		var n := _label(11, Color(0.66, 0.6, 0.5))
		n.text = s.name
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(n)
		eg.add_child(cell)
		eq_btns[sid] = b
	var g := GridContainer.new()
	g.columns = COLS
	g.add_theme_constant_override("h_separation", 4)
	g.add_theme_constant_override("v_separation", 4)
	v.add_child(g)
	for i in int(Act1Data.rules().hero.inventory_cap):
		var b := _slot_button()
		var idx := i
		b.pressed.connect(func(): _select({"where": "inv", "idx": idx}))
		g.add_child(b)
		inv_btns.append(b)
	v.add_child(HSeparator.new())
	# 说明区固定高度、内容多了可滚动：词缀 + 比较最多近 20 行，不滚动的话面板会超出 720 像素高的屏幕
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 170)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	detail = VBoxContainer.new()
	detail.add_theme_constant_override("separation", 1)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(detail)
	var acts := HBoxContainer.new()
	acts.add_theme_constant_override("separation", 8)
	v.add_child(acts)
	act_equip = _act("装备", func(): _do_equip())
	act_unequip = _act("卸下", func(): _do_unequip())
	act_drop = _act("丢在地上", func(): _do_drop())
	for b in [act_equip, act_unequip, act_drop]:
		acts.add_child(b)
	foot = _label(12, Color(0.6, 0.55, 0.46))
	v.add_child(foot)


func _label(size: int, c: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	return l


func _slot_button() -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(CELL, CELL)
	b.add_theme_font_size_override("font_size", 20)
	b.clip_text = true
	return b


func _act(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(96, 40)
	b.pressed.connect(cb)
	return b


func bind(h: Player) -> void:
	hero = h
	hero.progress.changed.connect(refresh)


func open() -> void:
	visible = true
	get_tree().paused = true
	sel = {}
	refresh()
	reset_size()
	set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	(inv_btns[0] if not inv_btns.is_empty() else close_btn).grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	get_tree().paused = false
	closed.emit()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_pressed() and not event.is_echo() and (event.is_action("inv_panel") or event.is_action("ui_cancel")):
		close()
		get_viewport().set_input_as_handled()


func selected_item() -> Dictionary:
	if hero == null or sel.is_empty():
		return {}
	var sh: Dictionary = hero.progress.sheet
	if sel.where == "inv":
		return sh.inv[sel.idx] if sel.idx < sh.inv.size() else {}
	var it = sh.eq.get(sel.slot)
	return it if it != null else {}


func _select(s: Dictionary) -> void:
	sel = s
	if selected_item().is_empty():
		sel = {}
	refresh()


func _style(b: Button, it, selected: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(6)
	sb.set_border_width_all(3 if selected else 1)
	if it == null:
		b.text = ""
		sb.bg_color = Color(0.13, 0.1, 0.08)
		sb.border_color = Color(0.3, 0.25, 0.2)
		b.tooltip_text = "空"
	else:
		var c: Color = GroundItem.RARITY_COLORS[int(it.rarity)]
		b.text = Act1Data.base(it.base).glyph
		b.add_theme_color_override("font_color", c)
		b.add_theme_color_override("font_hover_color", c)
		b.add_theme_color_override("font_focus_color", c)
		b.tooltip_text = "%s %s" % [ItemGen.RARITY_NAMES[int(it.rarity)], it.name]
		# 等级不够：底色发红（V0.1 .cant）
		sb.bg_color = Color(0.35, 0.08, 0.06) if int(hero.progress.sheet.lvl) < int(it.req) else Color(0.16, 0.12, 0.1)
		sb.border_color = c.lightened(0.3) if selected else c.darkened(0.35)
	for st in ["normal", "hover", "pressed", "focus"]:
		var s2: StyleBoxFlat = sb.duplicate()
		if st in ["hover", "focus"]:
			s2.border_color = Color(1.0, 0.85, 0.45)
			s2.set_border_width_all(2 if not selected else 3)
		b.add_theme_stylebox_override(st, s2)


func refresh() -> void:
	if hero == null or not is_inside_tree():
		return
	var sh: Dictionary = hero.progress.sheet
	var cap := int(Act1Data.rules().hero.inventory_cap)
	title.text = "背包 %d / %d　金币 %d" % [sh.inv.size(), cap, sh.gold]
	for slot in eq_btns:
		_style(eq_btns[slot], sh.eq.get(slot), not sel.is_empty() and sel.where == "eq" and sel.slot == slot)
	for i in inv_btns.size():
		_style(inv_btns[i], sh.inv[i] if i < sh.inv.size() else null, not sel.is_empty() and sel.where == "inv" and sel.idx == i)
	for c in detail.get_children():
		c.queue_free()
	var it := selected_item()
	if it.is_empty():
		var hint := _label(14, Color(0.66, 0.6, 0.5))
		hint.text = "点选一件物品查看详情。装备后属性立即生效。"
		detail.add_child(hint)
	else:
		var colors := {"base": Color(0.66, 0.6, 0.5), "stat": Color(0.94, 0.9, 0.84), "affix": Color(0.55, 0.62, 1.0), "req": Color(0.66, 0.6, 0.5), "req_bad": Color(0.95, 0.4, 0.3)}
		for ln in Inventory.item_lines(it, sh.lvl):
			var l := _label(18 if ln[1] == "name" else 14, GroundItem.RARITY_COLORS[int(it.rarity)] if ln[1] == "name" else colors[ln[1]])
			l.text = ln[0]
			detail.add_child(l)
		if sel.where == "inv":
			var cmp = sh.eq.get(Inventory.slot_of(it))
			var diffs := Inventory.compare(it, cmp)
			if not diffs.is_empty():
				var h := _label(13, Color(0.66, 0.6, 0.5))
				h.text = "与已装备的「%s」相比：" % cmp.name
				detail.add_child(h)
				for dd in diffs:
					var l := _label(13, Color(0.44, 0.83, 0.44) if dd[1] > 0 else Color(0.95, 0.4, 0.3))
					l.text = ("▲ +%s %s" if dd[1] > 0 else "▼ %s %s") % [str(dd[1]).trim_suffix(".0"), dd[0]]
					detail.add_child(l)
	# 三个按钮一直占位（不适用时置灰），面板尺寸不随选中与否变化
	var in_inv: bool = not it.is_empty() and sel.where == "inv"
	var on_body: bool = not it.is_empty() and sel.where == "eq"
	act_equip.disabled = not in_inv or not Inventory.can_equip(sh, it)
	act_unequip.disabled = not on_body or sh.inv.size() >= cap
	act_drop.disabled = not in_inv
	foot.text = "药水与卷轴放在腰带里：生命 %d · 法力 %d · 回城 %d" % [sh.pots.hp, sh.pots.mp, sh.pots.tp]


func _do_equip() -> void:
	if sel.is_empty() or sel.where != "inv":
		return
	var it := selected_item()
	if Inventory.equip(hero.progress.sheet, sel.idx):
		sel = {"where": "eq", "slot": Inventory.slot_of(it)}
		hero.stats_changed()


func _do_unequip() -> void:
	if sel.is_empty() or sel.where != "eq":
		return
	if Inventory.unequip(hero.progress.sheet, sel.slot):
		sel = {"where": "inv", "idx": hero.progress.sheet.inv.size() - 1}
		hero.stats_changed()
	else:
		hero.message.emit("背包已满", Color(0.88, 0.38, 0.29))


func _do_drop() -> void:
	if sel.is_empty() or sel.where != "inv":
		return
	var it := Inventory.take(hero.progress.sheet, sel.idx)
	if not it.is_empty():
		sel = {}
		drop_requested.emit(it)
		hero.progress.changed.emit()
