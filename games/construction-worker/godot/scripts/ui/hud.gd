class_name HUD
extends Control
## 游戏内常驻界面：
##   左上：第几天、时间、现金、饭票
##   左下：体力 / 饥饿 / 水分（触屏模式挪到左上）
##   右侧：当前任务、进度、报酬、目标
##   中央：交互提示 [E] [F]
##   下方：搬运状态、工具栏 1~5

var _day_label: Label
var _clock_label: Label
var _cash_label: Label
var _ticket_label: Label
var _stat_rows: Dictionary = {}
var _task_title: Label
var _task_progress: ProgressBar
var _task_progress_label: Label
var _task_reward: Label
var _task_place: Label
var _objective_label: Label
var _task_box: VBoxContainer
var _prompt_box: VBoxContainer
var _carry_label: Label
var _hotbar: HBoxContainer
var _hotbar_slots: Array = []
var _hint_label: Label
var _vignette: ColorRect
var _vignette_mat: ShaderMaterial
var _stats_panel: PanelContainer
var _last_prompt_key := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIKit.full_rect(self)
	_build_vignette()
	var margin := MarginContainer.new()
	UIKit.full_rect(margin)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	add_child(margin)
	var root := UIKit.vbox(8)
	margin.add_child(root)
	# ---------------- 顶部
	var top := UIKit.hbox(12)
	root.add_child(top)
	var left_col := UIKit.vbox(8)
	left_col.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(left_col)
	left_col.add_child(_build_time_panel())
	_stats_panel = _build_stats_panel()
	if GameState.touch_mode:
		left_col.add_child(_stats_panel)
	top.add_child(UIKit.spacer())
	var task_panel := _build_task_panel()
	task_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	if GameState.touch_mode:
		# 右上角留给触屏的「任务 / 地图 / 菜单」按钮
		var right_col := UIKit.vbox(0)
		right_col.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		var pad := Control.new()
		pad.custom_minimum_size = Vector2(10, 62)
		pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
		right_col.add_child(pad)
		right_col.add_child(task_panel)
		top.add_child(right_col)
	else:
		top.add_child(task_panel)
	# ---------------- 中部（交互提示）
	var middle := UIKit.vbox(0)
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(middle)
	var s1 := UIKit.spacer(false, true)
	s1.size_flags_stretch_ratio = 1.5
	middle.add_child(s1)
	_prompt_box = UIKit.vbox(6)
	_prompt_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	middle.add_child(_prompt_box)
	_hint_label = UIKit.hud_label("", 17, UIKit.DIM)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	middle.add_child(_hint_label)
	var s2 := UIKit.spacer(false, true)
	s2.size_flags_stretch_ratio = 1.0
	middle.add_child(s2)
	# ---------------- 底部
	var bottom := UIKit.hbox(12)
	root.add_child(bottom)
	if not GameState.touch_mode:
		_stats_panel.size_flags_vertical = Control.SIZE_SHRINK_END
		bottom.add_child(_stats_panel)
	bottom.add_child(UIKit.spacer())
	var center_col := UIKit.vbox(6)
	center_col.size_flags_vertical = Control.SIZE_SHRINK_END
	bottom.add_child(center_col)
	_carry_label = UIKit.hud_label("", 17, UIKit.TEXT)
	_carry_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_col.add_child(_carry_label)
	_hotbar = UIKit.hbox(6)
	_hotbar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	center_col.add_child(_hotbar)
	_build_hotbar()
	bottom.add_child(UIKit.spacer())
	if not GameState.touch_mode:
		var keys := UIKit.hud_label("Tab 任务　M 地图　Esc 菜单", 15, UIKit.DIM)
		keys.size_flags_vertical = Control.SIZE_SHRINK_END
		bottom.add_child(keys)
	else:
		# 给右下角的触屏按钮让出位置
		var pad := Control.new()
		pad.custom_minimum_size = Vector2(250, 10)
		pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bottom.add_child(pad)
		_hotbar.visible = false

	TimeSystem.clock_ticked.connect(func(_d, _m): _refresh_time())
	EconomySystem.cash_changed.connect(func(_c, _d, _r): _refresh_cash())
	EconomySystem.meal_tickets_changed.connect(func(_n): _refresh_cash())
	PlayerStats.stats_changed.connect(_refresh_stats)
	PlayerStats.equipment_changed.connect(_refresh_hotbar)
	TaskSystem.tasks_changed.connect(_refresh_task)
	Events.objective_changed.connect(_refresh_task)
	refresh_all()


func refresh_all() -> void:
	_refresh_time()
	_refresh_cash()
	_refresh_stats()
	_refresh_task()
	_refresh_hotbar()


# ================================================================ 构建
func _build_time_panel() -> PanelContainer:
	var p := UIKit.panel()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := UIKit.vbox(0)
	p.add_child(v)
	_day_label = UIKit.label("第 1 天 · 早晨", 17, UIKit.DIM)
	v.add_child(_day_label)
	_clock_label = UIKit.label("06:00", 34, UIKit.TEXT)
	v.add_child(_clock_label)
	var h := UIKit.hbox(10)
	v.add_child(h)
	_cash_label = UIKit.label("¥300", 26, UIKit.YELLOW)
	h.add_child(_cash_label)
	_ticket_label = UIKit.label("", 16, UIKit.GOOD)
	_ticket_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_ticket_label)
	return p


func _build_stats_panel() -> PanelContainer:
	var p := UIKit.panel()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := UIKit.vbox(5)
	p.add_child(v)
	var defs := [
		["stamina", "体力", Color(0.4, 0.85, 0.45)],
		["hunger", "饥饿", Color(0.98, 0.6, 0.2)],
		["thirst", "水分", Color(0.35, 0.65, 1.0)],
	]
	for d in defs:
		var row := UIKit.hbox(8)
		v.add_child(row)
		var name_l := UIKit.label(String(d[1]), 16, UIKit.DIM)
		name_l.custom_minimum_size.x = 36
		row.add_child(name_l)
		var b := UIKit.bar(d[2], 150.0 if GameState.touch_mode else 180.0)
		row.add_child(b)
		var val := UIKit.label("100", 16, UIKit.TEXT)
		val.custom_minimum_size.x = 30
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(val)
		var state := UIKit.label("", 14, UIKit.WARN)
		state.custom_minimum_size.x = 30
		row.add_child(state)
		_stat_rows[d[0]] = {"bar": b, "value": val, "state": state, "color": d[2]}
	return p


func _build_task_panel() -> PanelContainer:
	var p := UIKit.panel()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.custom_minimum_size.x = 250 if GameState.touch_mode else 300
	_task_box = UIKit.vbox(4)
	p.add_child(_task_box)
	_task_box.add_child(UIKit.label("当前任务", 14, UIKit.DIM))
	_task_title = UIKit.label("暂无任务", 22, UIKit.YELLOW)
	_task_box.add_child(_task_title)
	_task_progress = UIKit.bar(UIKit.YELLOW, 200)
	_task_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_task_box.add_child(_task_progress)
	_task_progress_label = UIKit.label("", 17, UIKit.TEXT)
	_task_box.add_child(_task_progress_label)
	_task_reward = UIKit.label("", 16, UIKit.GOOD)
	_task_box.add_child(_task_reward)
	_task_place = UIKit.label("", 15, UIKit.DIM)
	_task_place.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_task_box.add_child(_task_place)
	_task_box.add_child(HSeparator.new())
	_objective_label = UIKit.label("", 16, UIKit.TEXT)
	_objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_task_box.add_child(_objective_label)
	return p


func _build_hotbar() -> void:
	for i in PlayerStats.TOOLS.size():
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(62, 54)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var v := UIKit.vbox(0)
		slot.add_child(v)
		var num := UIKit.label(str(i + 1), 13, UIKit.DIM)
		v.add_child(num)
		var name_l := UIKit.label(String(PlayerStats.TOOLS[i]["name"]), 14, UIKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
		v.add_child(name_l)
		_hotbar.add_child(slot)
		_hotbar_slots.append({"panel": slot, "name": name_l})


func _build_vignette() -> void:
	_vignette = ColorRect.new()
	UIKit.full_rect(_vignette)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform float strength = 0.0;
void fragment() {
	vec2 uv = UV - vec2(0.5);
	float d = length(uv * vec2(1.25, 1.0)) * 1.55;
	float a = smoothstep(0.45, 1.05, d) * strength;
	COLOR = vec4(0.18, 0.0, 0.0, a);
}
"""
	_vignette_mat = ShaderMaterial.new()
	_vignette_mat.shader = sh
	_vignette.material = _vignette_mat
	add_child(_vignette)


# ================================================================ 刷新
func _refresh_time() -> void:
	var extra := "（已过午夜）" if TimeSystem.is_after_midnight() else ""
	_day_label.text = "第 %d 天 · %s%s" % [TimeSystem.day, TimeSystem.phase(), extra]
	_clock_label.text = TimeSystem.clock_text()


func _refresh_cash() -> void:
	_cash_label.text = "¥%d" % EconomySystem.cash
	_ticket_label.text = "饭票 ×%d" % EconomySystem.meal_tickets if EconomySystem.meal_tickets > 0 else ""


func _refresh_stats() -> void:
	var vals := {"stamina": PlayerStats.stamina, "hunger": PlayerStats.hunger, "thirst": PlayerStats.thirst}
	for k in vals:
		var row: Dictionary = _stat_rows[k]
		var v: float = vals[k]
		(row["bar"] as ProgressBar).value = v
		(row["value"] as Label).text = str(int(round(v)))
		var state: Label = row["state"]
		if v < 10.0:
			state.text = "危险"
			state.add_theme_color_override("font_color", UIKit.BAD)
		elif v < 25.0:
			state.text = "偏低"
			state.add_theme_color_override("font_color", UIKit.WARN)
		else:
			state.text = ""
	if k_is_exhausted():
		(_stat_rows["stamina"]["state"] as Label).text = "力竭"
	var fatigue := PlayerStats.fatigue_level()
	_vignette_mat.set_shader_parameter("strength", fatigue * 0.85)


func k_is_exhausted() -> bool:
	return PlayerStats.exhausted and PlayerStats.stamina < 30.0


func _refresh_task() -> void:
	var task := TaskSystem.get_active()
	if task == null:
		_task_title.text = "暂无任务"
		_task_progress.visible = false
		_task_progress_label.text = ""
		_task_reward.text = ""
		_task_place.text = ""
		_task_progress_label.visible = false
		_task_reward.visible = false
		_task_place.visible = false
	else:
		var total := task.total_target()
		var done := TaskSystem.done_count()
		var obj := task.primary_objective()
		var item := String(obj.get("item", ""))
		_task_title.text = task.title
		_task_progress.visible = true
		_task_progress.max_value = total
		_task_progress.value = done
		_task_progress_label.visible = true
		_task_progress_label.text = "%s进度：%d / %d" % [task.title, done, total]
		_task_reward.visible = true
		_task_reward.text = "报酬：¥%d" % task.reward
		_task_place.visible = true
		_task_place.text = "从 %s 搬到 %s（每次最多 %d%s）" % [GameState.pile_name(item), GameState.zone_name(String(obj.get("zone", ""))), PlayerStats.carry_capacity(item), ItemDB.unit(item)]
	var o := GameState.current_objective() if GameState.playing else {}
	_objective_label.text = "目标：" + String(o.get("text", "")) if not o.is_empty() else ""


func _refresh_hotbar() -> void:
	for i in _hotbar_slots.size():
		var slot: Dictionary = _hotbar_slots[i]
		var tool: Dictionary = PlayerStats.TOOLS[i]
		var req := String(tool.get("requires", ""))
		var owned := req == "" or (req != "locked" and PlayerStats.has_equipment(req))
		var selected := i == PlayerStats.tool_index
		var bg := Color(0.07, 0.075, 0.09, 0.8)
		var border := Color(1, 1, 1, 0.1)
		if selected:
			border = UIKit.YELLOW
			bg = Color(0.25, 0.2, 0.05, 0.85)
		var sb := UIKit._box(bg, 8, border, 2 if selected else 1)
		sb.content_margin_left = 6
		sb.content_margin_right = 6
		sb.content_margin_top = 3
		sb.content_margin_bottom = 3
		(slot["panel"] as PanelContainer).add_theme_stylebox_override("panel", sb)
		var nl: Label = slot["name"]
		nl.text = String(tool["name"]) if owned else ("未解锁" if req == "locked" else "未购买")
		nl.add_theme_color_override("font_color", UIKit.TEXT if owned else Color(0.5, 0.5, 0.52))


func _process(_delta: float) -> void:
	var p := GameState.player
	if p == null:
		return
	# 交互提示
	var acts: Array = []
	if GameState.playing and not GameState.is_modal():
		acts = p.detector.current_actions()
	var key := ""
	for a in acts:
		key += "%s|%s|%s;" % [a.get("action", ""), a.get("label", ""), a.get("enabled", true)]
	if key != _last_prompt_key:
		_last_prompt_key = key
		for c in _prompt_box.get_children():
			c.queue_free()
		for a in acts:
			_prompt_box.add_child(_prompt_row(a))
	# 搬运状态
	var inv: Inventory = p.inventory
	if inv.is_empty():
		_carry_label.text = ""
	else:
		var kg := inv.weight()
		var slow := int(round((1.0 - clampf(1.0 - kg * 0.012, 0.45, 1.0)) * 100.0))
		_carry_label.text = "搬着：%s（%s 公斤）· 速度 -%d%%" % [ItemDB.describe(inv.item_id, inv.count), str(snappedf(kg, 0.1)), slow]


func _prompt_row(a: Dictionary) -> Control:
	var row := UIKit.hbox(8)
	row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var enabled := bool(a.get("enabled", true))
	var action := String(a.get("action", ""))
	var key_text := "E" if action == "interact" else "F"
	if GameState.touch_mode:
		key_text = "交互" if action == "interact" else "拿/放"
	var cap := UIKit.key_cap(key_text)
	if not enabled:
		cap.modulate = Color(1, 1, 1, 0.4)
	row.add_child(cap)
	var l := UIKit.hud_label(String(a.get("label", "")), 20, UIKit.TEXT if enabled else UIKit.WARN)
	row.add_child(l)
	return row


func set_hint(text: String) -> void:
	_hint_label.text = text
