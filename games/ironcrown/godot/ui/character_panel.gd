class_name CharacterPanel
extends Control
## 角色（路线图 2.7；GDD.md 第五节、7.3）：K 键或右上角「角色」按钮打开，打开时游戏暂停。
## 等级与属性点（有点数时属性旁出现「＋」）、四项属性、由属性算出的上限、八项技能（数值 + 到下一级的进度 + 专长）、八个势力的声望（档位文字 + 数值 + 符号条）。
## 专长写明解锁了没有（◆ 已解锁 / ◇ 未解锁），不只靠颜色。

signal closed

var f: Dictionary
var box: VBoxContainer
var header: Label


func _ready() -> void:
	f = UiKit.frame(self, "角色")
	box = f.box
	(f.close as Button).pressed.connect(close)
	get_tree().root.size_changed.connect(_fit)
	hide()


func open() -> void:
	show()
	refresh()
	(f.close as Button).grab_focus()
	print("IC_CHAR open level=%d points=%d" % [GameState.level, GameState.attr_points])


func close() -> void:
	if not visible:
		return
	hide()
	print("IC_CHAR closed")
	closed.emit()


func header_text() -> String:
	var left := GameState.LEVEL_EVERY - GameState.skill_ups % GameState.LEVEL_EVERY
	var t := "等级 %d · 再提升 %d 次技能升级" % [GameState.level, left]
	if GameState.attr_points > 0:
		t += " · 可分配属性点 %d" % GameState.attr_points
	return t


func refresh() -> void:
	UiKit.clear(box)
	header = UiKit.label(box, header_text(), false, 15)
	UiKit.label(box, "属性", true)
	var pd := GameState.progression()
	for a in GameState.ATTRS:
		var row := HBoxContainer.new()
		var l := UiKit.label(row, "%s %d　%s" % [GameState.attr_name(a), GameState.attr(a), pd.attributes[a].desc])
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if GameState.attr_points > 0:
			var b := Button.new()
			b.text = "＋"
			b.tooltip_text = "给%s加 1 点" % GameState.attr_name(a)
			b.custom_minimum_size = Vector2(44, 34)
			b.pressed.connect(func():
				GameState.raise_attr(a)
				refresh())
			row.add_child(b)
		box.add_child(row)
	UiKit.label(box, "生命上限 %d · 体力上限 %d · 负重上限 %.0f 斤 · 护甲 %d" % [GameState.health_max(), GameState.stamina_max(), GameState.carry_limit(), GameState.armor_total()], true, 14)
	box.add_child(HSeparator.new())
	UiKit.label(box, "技能（用什么涨什么）", true)
	for s in GameState.SKILL_NAMES:
		var sk: Dictionary = pd.skills[s]
		var v := int(GameState.skills.get(s, 0))
		UiKit.label(box, "%s %d　%s　%s" % [sk.name, v, _bar(GameState.skill_progress(s), 10), sk.desc])
		for p in sk.perks:
			var got := v >= int(p.at)
			UiKit.label(box, "    %s %d「%s」%s%s" % ["◆" if got else "◇", int(p.at), p.name, p.desc, "" if got else "（%s到 %d 解锁）" % [sk.name, int(p.at)]], not got, 14)
	box.add_child(HSeparator.new())
	UiKit.label(box, "声望", true)
	for fid in pd.factions:
		var v := GameState.get_rep(fid)
		UiKit.label(box, "%s　%s（%+d）　%s" % [pd.factions[fid].name, GameState.rep_tier(v), v, _rep_bar(v)])
	_fit()


## 进度条：■■■□□（文字符号，不只靠颜色；字体子集里只有 GB2312 的几何符号，没有更细的进度条字符）
static func _bar(k: float, n: int) -> String:
	var full := clampi(roundi(k * n), 0, n)
	return "■".repeat(full) + "□".repeat(n - full)


## 声望条：中间「｜」是 0，左边是负、右边是正，各 5 格
static func _rep_bar(v: int) -> String:
	var cells := clampi(roundi(absf(v) / 20.0), 0, 5)
	if v < 0:
		return "□".repeat(5 - cells) + "■".repeat(cells) + "｜" + "□".repeat(5)
	return "□".repeat(5) + "｜" + "■".repeat(cells) + "□".repeat(5 - cells)


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("pause") or event.is_action_pressed("character")):
		get_viewport().set_input_as_handled()
		close()


func _fit() -> void:
	if not is_inside_tree():
		return
	var w := UiKit.content_width(self)
	for c in box.get_children():
		if c is Label:
			c.custom_minimum_size.x = w - 12.0
		elif c is HBoxContainer:
			for l in c.get_children():
				if l is Label:
					l.custom_minimum_size.x = w - 70.0
	UiKit.fit(self, f)
	_refit.call_deferred()


func _refit() -> void:
	if is_inside_tree() and visible:
		UiKit.fit(self, f)
