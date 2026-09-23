class_name TaskPanel
extends Control
## Tab 任务面板：身份、技能、今日任务列表、工程进度、流水账。不会暂停游戏。

var _panel: PanelContainer
var _body: VBoxContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIKit.full_rect(self)
	visible = false
	var center := CenterContainer.new()
	UIKit.full_rect(center)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_panel = UIKit.panel(Color(0.06, 0.065, 0.08, 0.93), 14, 20)
	_panel.custom_minimum_size = Vector2(620, 0)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(_panel)
	_body = UIKit.vbox(8)
	_panel.add_child(_body)
	TaskSystem.tasks_changed.connect(_maybe_refresh)
	PlayerStats.stats_changed.connect(_maybe_refresh_slow)


func toggle() -> void:
	visible = not visible
	if visible:
		refresh()


var _slow := 0.0


func _maybe_refresh() -> void:
	if visible:
		refresh()


func _maybe_refresh_slow() -> void:
	if visible and Time.get_ticks_msec() - _slow > 500:
		_slow = Time.get_ticks_msec()
		refresh()


func refresh() -> void:
	_panel.custom_minimum_size.x = clampf(get_viewport_rect().size.x - 40.0, 320.0, 620.0)
	for c in _body.get_children():
		c.queue_free()
	var head := UIKit.hbox(10)
	_body.add_child(head)
	head.add_child(UIKit.label("任务与成长", 24, UIKit.YELLOW))
	head.add_child(UIKit.spacer())
	head.add_child(UIKit.label("Tab 关闭", 15, UIKit.DIM))
	# 身份与技能
	var lv := PlayerStats.carry_level()
	var next := PlayerStats.xp_to_next("carry")
	var skill_text := "搬运 Lv%d（一次最多：红砖 %d 块 · 水泥 %d 袋 · 钢筋 %d 捆）" % [lv, PlayerStats.carry_capacity("brick"), PlayerStats.carry_capacity("cement"), PlayerStats.carry_capacity("rebar")]
	_body.add_child(UIKit.label("身份：%s　声望 %d　累计收入 ¥%d" % [PlayerStats.job_title(), PlayerStats.reputation, EconomySystem.total_income], 17, UIKit.TEXT))
	_body.add_child(UIKit.label(skill_text, 16, UIKit.TEXT))
	if next > 0:
		_body.add_child(UIKit.label("再搬 %d 件材料升到 Lv%d" % [next, lv + 1], 15, UIKit.DIM))
	else:
		_body.add_child(UIKit.label("搬运已满级", 15, UIKit.GOOD))
	var gloves := "已装备劳保手套（体力消耗 -25%）" if PlayerStats.current_tool().get("id", "") == "gloves" else ("有劳保手套，按 2 戴上" if PlayerStats.has_equipment("gloves") else "小卖部有劳保手套卖（¥25）")
	_body.add_child(UIKit.label(gloves, 15, UIKit.DIM))
	_body.add_child(HSeparator.new())
	# 任务列表
	_body.add_child(UIKit.label("老王手上的活（第 %d 天）" % TimeSystem.day, 18, UIKit.YELLOW))
	for id in TaskSystem.order:
		var t: TaskDefinition = TaskSystem.catalog[id]
		var row := UIKit.hbox(8)
		_body.add_child(row)
		var status := ""
		var col := UIKit.TEXT
		if TaskSystem.active_id == id:
			status = "进行中 %d/%d" % [TaskSystem.done_count(), t.total_target()]
			col = UIKit.YELLOW
		else:
			var reason := TaskSystem.unavailable_reason(id)
			if reason == "":
				status = "可接取（找老王）"
				col = UIKit.GOOD
			else:
				status = reason
				col = UIKit.DIM
		var name_l := UIKit.label("%s　¥%d" % [t.title, t.reward], 17, UIKit.TEXT)
		name_l.custom_minimum_size.x = 150
		row.add_child(name_l)
		var desc := UIKit.label(t.summary, 14, UIKit.DIM)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(desc)
		var st := UIKit.label(status, 15, col)
		st.custom_minimum_size.x = 120
		st.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(st)
	_body.add_child(HSeparator.new())
	# 工程进度
	_body.add_child(UIKit.label("滨江中心 1# 楼 · 你参与砌筑的墙体：%d 段" % GameState.building_progress, 16, UIKit.TEXT))
	# 最近流水
	var recent: Array = EconomySystem.ledger.slice(maxi(0, EconomySystem.ledger.size() - 4))
	if not recent.is_empty():
		_body.add_child(UIKit.label("最近收支", 15, UIKit.DIM))
		recent.reverse()
		for e in recent:
			var amt := int(e.get("amount", 0))
			var sign_text := "+¥%d" % amt if amt >= 0 else "-¥%d" % (-amt)
			_body.add_child(UIKit.label("第 %d 天 %s　%s　%s" % [int(e.get("day", 1)), String(e.get("time", "")), sign_text, String(e.get("reason", ""))], 14, UIKit.GOOD if amt >= 0 else UIKit.DIM))
