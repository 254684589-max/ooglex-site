class_name InventoryPanel
extends Control
## 背包（路线图 2.6；GDD.md 第八节）：I 键或右上角「背包」按钮打开，打开时游戏暂停。
## 最上面一行写护甲、负重、银币（超重时写明「超重：不能跑」）；然后是五个装备部位；再往下按种类列出随身物品。
## 选中一件看说明，按钮：装备 / 卸下 / 使用（消耗品）。任务物品不能丢；丢弃与出售在之后的步骤。

signal closed
signal used(effect: Dictionary, item_id: String)

var f: Dictionary
var box: VBoxContainer
var summary: Label
var detail: Label
var actions: HBoxContainer
var selected := ""
var focus_btn: Button             # 重建列表后把键盘焦点放回选中的那一件


func _ready() -> void:
	f = UiKit.frame(self, "背包")
	box = f.box
	(f.close as Button).pressed.connect(close)
	get_tree().root.size_changed.connect(_fit)
	hide()


func open() -> void:
	selected = ""
	show()
	refresh()
	(f.close as Button).grab_focus()
	print("IC_BAG open items=%d silver=%d" % [GameState.inventory.size(), GameState.silver])


func close() -> void:
	if not visible:
		return
	hide()
	print("IC_BAG closed")
	closed.emit()


func summary_text() -> String:
	var t := "护甲 %d · 负重 %.1f / %.0f 斤 · 银币 %d" % [GameState.armor_total(), GameState.carry_weight(), GameState.carry_limit(), GameState.silver]
	if GameState.over_encumbered():
		t += " · 超重：不能跑"
	return t


## 背包里的物品种类（去重，按 武器 → 护甲 → 消耗品 → 任务物品 → 杂物）
func item_ids() -> Array:
	var order := GameState.KIND_NAMES.keys()
	var ids := []
	for id in GameState.inventory:
		if not id in ids:
			ids.append(id)
	ids.sort_custom(func(a, b):
		var ka := order.find(str(GameState.item(a).get("kind", "misc")))
		var kb := order.find(str(GameState.item(b).get("kind", "misc")))
		return ka < kb if ka != kb else GameState.item_name(a) < GameState.item_name(b))
	return ids


func refresh() -> void:
	focus_btn = null
	UiKit.clear(box)
	summary = UiKit.label(box, summary_text(), false, 15)
	UiKit.label(box, "装备", true)
	for s in GameState.SLOTS:
		var id := str(GameState.equipped.get(s, ""))
		var text := "%s：%s" % [GameState.SLOT_NAMES[s], GameState.item_name(id) if id != "" else "（空）"]
		var b := UiKit.button(box, ("▶ " if id != "" and id == selected else "    ") + text, func():
			if id != "":
				selected = id
				refresh())
		b.disabled = id == ""
	var last_kind := ""
	for id in item_ids():
		var it := GameState.item(id)
		var k := str(it.get("kind", "misc"))
		if k != last_kind:
			last_kind = k
			UiKit.label(box, str(GameState.KIND_NAMES.get(k, k)), true)
		var n := GameState.count_item(id)
		var text := "%s%s%s" % [GameState.item_name(id), " ×%d" % n if n > 1 else "", "（已装备）" if GameState.is_equipped(id) else ""]
		var b := UiKit.button(box, ("▶ " if id == selected else "    ") + text, func():
			selected = id
			refresh())
		if id == selected:
			focus_btn = b
	box.add_child(HSeparator.new())
	detail = UiKit.label(box, detail_text(selected), false)
	actions = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	box.add_child(actions)
	if selected != "" and GameState.has_item(selected):
		var it := GameState.item(selected)
		if GameState.slot_of(selected) != "":
			if GameState.is_equipped(selected):
				_action("卸下", func():
					GameState.unequip(GameState.slot_of(selected))
					refresh())
			else:
				_action("装备", func():
					GameState.equip(selected)
					refresh())
		if it.get("kind") == "consumable":
			_action("使用", func(): _use(selected))
	_fit()
	if focus_btn and visible:
		_focus_later.call_deferred(focus_btn)


## 列表可能在同一帧里又重建了一次：按钮已经不在树里就不抢焦点
func _focus_later(b: Button) -> void:
	if is_instance_valid(b) and b.is_inside_tree():
		b.grab_focus()


func _action(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(88, 38)
	b.pressed.connect(cb)
	actions.add_child(b)
	return b


func _use(id: String) -> void:
	var eff := GameState.use_item(id)
	if eff.is_empty():
		return
	if not GameState.has_item(id):
		selected = ""
	used.emit(eff, id)
	refresh()


func detail_text(id: String) -> String:
	if id == "" or not GameState.has_item(id):
		return "选一件东西看看。"
	var it := GameState.item(id)
	var lines := [GameState.item_name(id), str(it.get("desc", ""))]
	var facts := ["%s" % GameState.KIND_NAMES.get(str(it.kind), ""), "%.1f 斤" % float(it.weight)]
	match str(it.kind):
		"weapon":
			facts.append("伤害 %d" % int(it.base))
		"armor":
			facts.append("%s部 · 护甲 %d" % [GameState.SLOT_NAMES[it.slot], int(it.armor)])
			if float(it.noise) > 0.0:
				facts.append("走动更吵")
		"quest":
			facts.append("不能丢弃")
	if int(it.get("value", 0)) > 0:
		facts.append("值 %d 银币" % int(it.value))
	lines.append(" · ".join(facts))
	return "\n".join(lines)


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("pause") or event.is_action_pressed("inventory")):
		get_viewport().set_input_as_handled()
		close()


func _fit() -> void:
	if not is_inside_tree():
		return
	# 自动换行的 Label 在第一次排版前按 0 宽度算高度（一个字一行），面板会被撑满整屏：
	# 先定宽度，排版一帧后再按真实高度定一次（2.6 截图）
	var w := UiKit.content_width(self)
	for c in box.get_children():
		if c is Label:
			c.custom_minimum_size.x = w - 12.0
	UiKit.fit(self, f)
	_refit.call_deferred()


func _refit() -> void:
	if is_inside_tree() and visible:
		UiKit.fit(self, f)
