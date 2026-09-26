class_name CharPanel
extends PanelContainer
## 角色面板（P3，对应 V0.1 openChar）：等级、经验、属性点分配（力量 / 体能 / 魔力）与计算后的属性。
## 打开时游戏暂停（V0.1：打开面板自动暂停），C / Esc / × 关闭。完整的装备与背包界面在 P6。

signal closed

const STATS := [
	["str", "力量", "每点 +1% 伤害"],
	["vit", "体能", "每点 +2 生命"],
	["mag", "魔力", "每点 +1.5 法力、+2.5% 法术伤害"],
]

var hero: Player
var head: Label
var xp_label: Label
var pts_label: Label
var values := {}
var plus := {}
var derived: Label
var close_btn: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	set_anchors_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	custom_minimum_size = Vector2(430, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.055, 0.045, 0.96)
	sb.border_color = Color(0.79, 0.64, 0.35)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(16)
	add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	head = _label(22, Color(1.0, 0.8, 0.45))
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(head)
	close_btn = Button.new()
	close_btn.text = "×"
	close_btn.tooltip_text = "关闭（C / Esc）"
	close_btn.custom_minimum_size = Vector2(44, 44)
	close_btn.pressed.connect(close)
	top.add_child(close_btn)
	xp_label = _label(15, Color(0.85, 0.78, 0.66))
	v.add_child(xp_label)
	pts_label = _label(16, Color(1.0, 0.82, 0.29))
	v.add_child(pts_label)
	for s in STATS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var n := _label(18, Color(0.94, 0.9, 0.84))
		n.text = s[1]
		n.custom_minimum_size = Vector2(52, 0)
		row.add_child(n)
		var val := _label(18, Color(1, 1, 1))
		val.custom_minimum_size = Vector2(44, 0)
		row.add_child(val)
		values[s[0]] = val
		var hint := _label(13, Color(0.66, 0.6, 0.5))
		hint.text = s[2]
		hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(hint)
		var b := Button.new()
		b.text = "+"
		b.tooltip_text = "给%s加 1 点" % s[1]
		b.custom_minimum_size = Vector2(44, 44)
		b.pressed.connect(func(): hero.allocate(s[0]))
		row.add_child(b)
		plus[s[0]] = b
		v.add_child(row)
	v.add_child(HSeparator.new())
	# 不开自动换行：尺寸还没定时，自动换行的标签会按一字一行算最小高度，把面板撑到几千像素高（P3 实测）。
	# 各行都已手动断好，最长一行约 400 像素，手机竖屏（逻辑宽 480）也放得下。
	derived = _label(15, Color(0.88, 0.82, 0.72))
	v.add_child(derived)


func _label(size: int, c: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	return l


func bind(h: Player) -> void:
	hero = h
	hero.progress.changed.connect(refresh)


func open() -> void:
	visible = true
	get_tree().paused = true
	refresh()
	# 内容填好后按最小尺寸重新居中（_ready 时尺寸还是 0，居中锚点会算偏）
	reset_size()
	set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	var first: Button = plus.str if not plus.str.disabled else close_btn
	first.grab_focus()


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
	if visible and event.is_pressed() and not event.is_echo() and (event.is_action("char_panel") or event.is_action("ui_cancel")):
		close()
		get_viewport().set_input_as_handled()


func refresh() -> void:
	if hero == null or not is_inside_tree():
		return
	var sh: Dictionary = hero.progress.sheet
	var S: Dictionary = hero.progress.S
	head.text = "角色 · 流浪者　%d 级" % sh.lvl
	if sh.lvl >= int(Act1Data.rules().hero.level_cap):
		xp_label.text = "经验：已满级"
	else:
		xp_label.text = "经验 %d / %d（升到 %d 级）" % [sh.xp, HeroStats.xp_need(sh.lvl), sh.lvl + 1]
	pts_label.text = "可分配属性点：%d" % sh.pts if sh.pts > 0 else "没有可分配的属性点（每升 1 级得 5 点）"
	for s in STATS:
		var bonus: int = int(S[s[0]]) - int(sh[s[0]])
		values[s[0]].text = str(int(S[s[0]])) + (" (+%d)" % bonus if bonus > 0 else "")
		plus[s[0]].disabled = sh.pts <= 0
	var dr := HeroStats.damage_reduction(S, sh.lvl) * 100.0
	derived.text = "\n".join([
		"生命 %d　法力 %d" % [S.maxHp, S.maxMp],
		"伤害 %d-%d　攻击速度 %.2f 次/秒　暴击 %d%%" % [S.dmg[0], S.dmg[1], S.aps, S.crit],
		"护甲 %d（对同级敌人减伤 %d%%）　生命偷取 %d%%" % [S.arm, roundi(dr), S.ls],
		"每秒回复：生命 %.1f、法力 %.1f" % [S.regen, S.mregen],
		"法术伤害 ×%.2f　移动速度 %d%%" % [S.spell, roundi(S.ms / Act1Data.rules().hero.stats.base_move_speed * 100.0)],
		"金币 %d　击杀 %d　倒下 %d 次" % [sh.gold, sh.kills, sh.deaths],
	])
