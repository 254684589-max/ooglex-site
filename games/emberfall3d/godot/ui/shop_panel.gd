class_name ShopPanel
extends PanelContainer
## 商店面板（P7，对应 V0.1 openShop / buy / sell）：「购买」「出售」两页。
## 格伦卖武器护甲；玛拉卖药水、回城卷轴与戒指护符。价格 = V0.1 itemValue，卖价 = 1/4；药水 25、回城卷轴 40 金币。
## 进货在每次进镇时刷新（FloorRules.refresh_shop）。打开时暂停，Esc / × 关闭。

signal closed

const POTIONS := [["hp", "生命药水", "血"], ["mp", "法力药水", "蓝"], ["tp", "回城卷轴", "城"]]

var hero: Player
var which := "smith"
var stock: Array = []           # 商人的货（物品字典），买走就从这里删掉
var tab := "buy"
var title: Label
var tab_buy: Button
var tab_sell: Button
var list: VBoxContainer
var detail: VBoxContainer
var act: Button
var close_btn: Button
var sel = null                  # 选中的：{kind: "item"/"pot"/"inv", ...}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	custom_minimum_size = Vector2(440, 0)
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
	title = Label.new()
	title.add_theme_font_size_override("font_size", 19)
	title.add_theme_color_override("font_color", Color(1.0, 0.8, 0.45))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	close_btn = Button.new()
	close_btn.text = "×"
	close_btn.tooltip_text = "关闭（Esc）"
	close_btn.custom_minimum_size = Vector2(40, 40)
	close_btn.pressed.connect(close)
	top.add_child(close_btn)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	v.add_child(tabs)
	tab_buy = _btn("购买", func(): _set_tab("buy"))
	tab_sell = _btn("出售", func(): _set_tab("sell"))
	tabs.add_child(tab_buy)
	tabs.add_child(tab_sell)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, 250)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 3)
	sc.add_child(list)
	v.add_child(HSeparator.new())
	var sd := ScrollContainer.new()
	sd.custom_minimum_size = Vector2(0, 150)
	sd.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sd)
	detail = VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 1)
	sd.add_child(detail)
	act = _btn("购买", func(): _do_act())
	act.custom_minimum_size = Vector2(0, 44)
	v.add_child(act)


func _btn(t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = Vector2(90, 40)
	b.pressed.connect(cb)
	return b


func open_shop(h: Player, shop_id: String, goods: Array) -> void:
	hero = h
	which = shop_id
	stock = goods
	tab = "buy"
	sel = null
	visible = true
	get_tree().paused = true
	refresh()
	reset_size()
	set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	tab_buy.grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	get_tree().paused = false
	closed.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_pressed() and not event.is_echo() and event.is_action("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _set_tab(t: String) -> void:
	tab = t
	sel = null
	refresh()


func price_of(s: Dictionary) -> int:
	if s.kind == "pot":
		return int(Act1Data.rules().shop.prices[s.pot])
	if s.kind == "item":
		return ItemGen.value(s.item)
	return ItemGen.sell_value(s.item)


func _row(text: String, c: Color, s: Dictionary) -> void:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 38)
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_color", c)
	b.add_theme_color_override("font_hover_color", c.lightened(0.2))
	if sel != null and sel == s:
		b.add_theme_color_override("font_color", c.lightened(0.35))
		b.text = "▶ " + text
	b.pressed.connect(func():
		sel = s
		refresh())
	list.add_child(b)


func refresh() -> void:
	if hero == null or not is_inside_tree():
		return
	var sh: Dictionary = hero.progress.sheet
	title.text = "%s　持有 %d 金币" % ["格伦的货架" if which == "smith" else "玛拉的货架", sh.gold]
	tab_buy.disabled = tab == "buy"
	tab_sell.disabled = tab == "sell"
	for c in list.get_children():
		list.remove_child(c)
		c.queue_free()
	for c in detail.get_children():
		detail.remove_child(c)
		c.queue_free()
	if tab == "buy":
		if which == "alchemist":
			for p in POTIONS:
				var s := {"kind": "pot", "pot": p[0]}
				if sel != null and sel.kind == "pot" and sel.pot == p[0]:
					s = sel
				_row("[%s] %s　持有 %d　—　%d 金币" % [p[2], p[1], sh.pots[p[0]], price_of(s)], Color(0.91, 0.86, 0.78), s)
		for it in stock:
			var s := {"kind": "item", "item": it}
			if sel != null and sel.kind == "item" and sel.item == it:
				s = sel
			_row("[%s] %s　—　%d 金币" % [Act1Data.base(it.base).glyph, it.name, ItemGen.value(it)], GroundItem.RARITY_COLORS[int(it.rarity)], s)
	else:
		if sh.inv.is_empty():
			var e := Label.new()
			e.text = "背包是空的。"
			e.add_theme_color_override("font_color", Color(0.66, 0.6, 0.5))
			list.add_child(e)
		for it in sh.inv:
			var s := {"kind": "inv", "item": it}
			if sel != null and sel.kind == "inv" and sel.item == it:
				s = sel
			_row("[%s] %s　—　卖 %d 金币" % [Act1Data.base(it.base).glyph, it.name, ItemGen.sell_value(it)], GroundItem.RARITY_COLORS[int(it.rarity)], s)
	if sel == null:
		var hint := Label.new()
		hint.text = "点选一件看详情。" if tab == "buy" else "点选背包里的物品，查看卖价后出售。"
		hint.add_theme_color_override("font_color", Color(0.66, 0.6, 0.5))
		detail.add_child(hint)
		act.text = "购买" if tab == "buy" else "出售"
		act.disabled = true
		return
	var price := price_of(sel)
	if sel.kind == "pot":
		var l := Label.new()
		l.text = {"hp": "回复 45% 生命 + 10", "mp": "回复 50% 法力 + 5", "tp": "在地下打开一道回镇上的传送门（T 键 / 手机「城」）"}[sel.pot]
		l.add_theme_color_override("font_color", Color(0.9, 0.85, 0.76))
		detail.add_child(l)
	else:
		var it: Dictionary = sel.item
		for ln in Inventory.item_lines(it, sh.lvl):
			var l := Label.new()
			l.text = ln[0]
			l.add_theme_font_size_override("font_size", 17 if ln[1] == "name" else 14)
			l.add_theme_color_override("font_color", GroundItem.RARITY_COLORS[int(it.rarity)] if ln[1] == "name" else {"base": Color(0.66, 0.6, 0.5), "stat": Color(0.94, 0.9, 0.84), "affix": Color(0.55, 0.62, 1.0), "req": Color(0.66, 0.6, 0.5), "req_bad": Color(0.95, 0.4, 0.3)}[ln[1]])
			detail.add_child(l)
		if sel.kind == "item":
			var cmp = sh.eq.get(Inventory.slot_of(it))
			for dd in Inventory.compare(it, cmp):
				var l := Label.new()
				l.text = ("▲ +%s %s" if dd[1] > 0 else "▼ %s %s") % [str(dd[1]).trim_suffix(".0"), dd[0]]
				l.add_theme_font_size_override("font_size", 13)
				l.add_theme_color_override("font_color", Color(0.44, 0.83, 0.44) if dd[1] > 0 else Color(0.95, 0.4, 0.3))
				detail.add_child(l)
	if tab == "buy":
		act.text = "购买（%d 金币）" % price
		act.disabled = sh.gold < price or (sel.kind == "item" and sh.inv.size() >= int(Act1Data.rules().hero.inventory_cap))
	else:
		act.text = "出售（%d 金币）" % price
		act.disabled = false


## 买 / 卖（V0.1 buy / sell）：金币不够、背包满时买不了
func _do_act() -> void:
	if sel == null:
		return
	var sh: Dictionary = hero.progress.sheet
	var price := price_of(sel)
	if tab == "buy":
		if sh.gold < price:
			hero.message.emit("金币不足", Color(0.88, 0.38, 0.29))
			return
		if sel.kind == "pot":
			sh.gold -= price
			sh.pots[sel.pot] += 1
		else:
			if sh.inv.size() >= int(Act1Data.rules().hero.inventory_cap):
				hero.message.emit("背包已满", Color(0.88, 0.38, 0.29))
				return
			sh.gold -= price
			sh.inv.append(sel.item)
			stock.erase(sel.item)
			hero.message.emit("购买 " + String(sel.item.name), Color(0.79, 0.64, 0.35))
			sel = null
	else:
		var it: Dictionary = sel.item
		sh.gold += price
		sh.inv.erase(it)
		hero.message.emit("出售 %s，获得 %d 金币" % [it.name, price], Color(0.79, 0.64, 0.35))
		sel = null
	Sfx.play("gold")
	print("EF_SHOP %s gold=%d" % [tab, sh.gold])
	hero.progress.changed.emit()
	refresh()
