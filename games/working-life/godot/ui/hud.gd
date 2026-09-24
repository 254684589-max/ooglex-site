class_name HUD
extends Control
## 游戏 HUD：
##   左上：日期、星期、时间、天气、现金（与时间倍速）
##   左下：体力 / 饱腹 / 心情 / 健康 / 压力
##   右侧：当前任务与目标（距离）、上班状态
##   中央：交互提示（[E] 与老板交谈  [F] 使用电脑）
## 文字每 0.2 秒刷新一次，不逐帧重建。

var _date: Label
var _clock: Label
var _weather: Label
var _cash: Label
var _speed: Label
var _bars: Dictionary = {}
var _bar_vals: Dictionary = {}
var _quest_title: Label
var _quest_obj: Label
var _quest_dist: Label
var _job: Label
var _prompts: VBoxContainer
var _hint: Label
var _msg_badge: Label
var _timer := 0.0
var _last_prompt_key := ""
var player: Player

const BAR_DEFS := [["energy", "体力", Color(0.2, 0.9, 1.0)], ["hunger", "饱腹", Color(1.0, 0.72, 0.25)], ["mood", "心情", Color(1.0, 0.3, 0.65)], ["health", "健康", Color(0.45, 1.0, 0.5)], ["stress", "压力", Color(0.7, 0.4, 1.0)]]


var _tl: Control
var _bl: Control
var _tr: Control
var _keys_hint: Label
var _bar_nodes: Array = []
var _layout_key := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIKit.full_rect(self)
	resized.connect(_relayout)
	# ---- 左上
	var tl := UIKit.panel(Color(0.02, 0.02, 0.05, 0.62), 6, 10)
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tl.position = Vector2(14, 12)
	add_child(tl)
	_tl = tl
	var tlv := UIKit.vbox(2)
	tl.add_child(tlv)
	_date = UIKit.label("", 15, UIKit.DIM)
	tlv.add_child(_date)
	var row := UIKit.hbox(10)
	tlv.add_child(row)
	_clock = UIKit.label("", 30, UIKit.CYAN)
	row.add_child(_clock)
	var col := UIKit.vbox(0)
	row.add_child(col)
	_weather = UIKit.label("", 15, UIKit.TEXT)
	col.add_child(_weather)
	_speed = UIKit.label("", 13, UIKit.DIM)
	col.add_child(_speed)
	_cash = UIKit.label("", 22, UIKit.YELLOW)
	tlv.add_child(_cash)
	# ---- 左下：属性条
	var bl := UIKit.panel(Color(0.02, 0.02, 0.05, 0.62), 6, 10)
	bl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bl.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bl.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bl.offset_left = 14
	bl.offset_bottom = -14
	bl.offset_top = -14
	add_child(bl)
	_bl = bl
	var blv := UIKit.vbox(3)
	bl.add_child(blv)
	for d in BAR_DEFS:
		var h := UIKit.hbox(6)
		blv.add_child(h)
		var nl := UIKit.label(String(d[1]), 14, UIKit.DIM)
		nl.custom_minimum_size.x = 32
		h.add_child(nl)
		var b := UIKit.bar(d[2], 132, 10)
		h.add_child(b)
		var vl := UIKit.label("", 14, UIKit.TEXT)
		vl.custom_minimum_size.x = 64
		h.add_child(vl)
		_bar_nodes.append([b, vl])
		_bars[d[0]] = b
		_bar_vals[d[0]] = vl
	# ---- 右侧：任务
	var tr := UIKit.panel(Color(0.02, 0.02, 0.05, 0.62), 6, 10)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tr.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	tr.custom_minimum_size = Vector2(320, 0)
	tr.offset_right = -14
	tr.offset_left = -334
	tr.offset_top = 12
	add_child(tr)
	_tr = tr
	var trv := UIKit.vbox(3)
	tr.add_child(trv)
	var qh := UIKit.hbox(6)
	trv.add_child(qh)
	qh.add_child(UIKit.label("◆ 当前任务", 13, UIKit.MAGENTA))
	qh.add_child(UIKit.spacer())
	_keys_hint = UIKit.label("[J] 任务  [Tab] 手机", 12, UIKit.DIM)
	qh.add_child(_keys_hint)
	_quest_title = UIKit.label("", 19, UIKit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)
	trv.add_child(_quest_title)
	_quest_obj = UIKit.label("", 15, UIKit.CYAN, HORIZONTAL_ALIGNMENT_LEFT, true)
	trv.add_child(_quest_obj)
	_quest_dist = UIKit.label("", 13, UIKit.DIM)
	trv.add_child(_quest_dist)
	trv.add_child(UIKit.sep())
	_job = UIKit.label("", 14, UIKit.YELLOW, HORIZONTAL_ALIGNMENT_LEFT, true)
	trv.add_child(_job)
	_msg_badge = UIKit.label("", 14, UIKit.MAGENTA)
	trv.add_child(_msg_badge)
	# ---- 中央：交互提示
	_prompts = UIKit.vbox(6)
	_prompts.set_anchors_preset(Control.PRESET_CENTER)
	_prompts.position = Vector2(-160, 70)
	_prompts.custom_minimum_size = Vector2(320, 0)
	_prompts.alignment = BoxContainer.ALIGNMENT_CENTER
	_prompts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_prompts)
	_hint = UIKit.hud_label("", 16, UIKit.DIM)
	_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.position = Vector2(-150, -40)
	_hint.custom_minimum_size = Vector2(300, 0)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hint)
	# 准星
	var dot := ColorRect.new()
	dot.color = Color(1, 1, 1, 0.5)
	dot.size = Vector2(4, 4)
	dot.set_anchors_preset(Control.PRESET_CENTER)
	dot.position = Vector2(-2, -2)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dot)


func set_hint(t: String) -> void:
	_hint.text = t


## 触屏布局：右上角有「手机 / 地图 / 菜单」按钮、左下角是摇杆，面板要让开。
##   竖屏：属性条挪到左上时间面板下面，任务面板下移到按钮下方；
##   横屏：属性条放在时间面板右边（紧凑），任务面板变窄并下移。
func _relayout() -> void:
	if _tl == null or size.x <= 0.0:
		return
	var touch := GameManager.touch_mode
	var portrait := size.y > size.x
	var key := "%s|%s|%d|%d|%d" % [touch, portrait, int(size.x), int(_tl.size.x), int(_tl.size.y)]
	if key == _layout_key:
		return
	_layout_key = key
	_keys_hint.visible = not touch
	for pair in _bar_nodes:
		(pair[0] as Control).custom_minimum_size.x = 96.0 if touch else 132.0
		(pair[1] as Control).custom_minimum_size.x = 34.0 if touch else 64.0
	if not touch:
		_bl.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		_bl.grow_vertical = Control.GROW_DIRECTION_BEGIN
		_bl.offset_left = 14
		_bl.offset_bottom = -14
		_bl.offset_top = -14
		_tr.custom_minimum_size.x = 320
		_tr.offset_left = -334
		_tr.offset_top = 12
		return
	_bl.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_bl.grow_vertical = Control.GROW_DIRECTION_END
	_bl.size = Vector2.ZERO
	if portrait:
		_bl.position = Vector2(14, _tl.position.y + _tl.size.y + 8)
		_tr.custom_minimum_size.x = minf(320.0, size.x - 28.0)
	else:
		_bl.position = Vector2(_tl.position.x + _tl.size.x + 10, 12)
		_tr.custom_minimum_size.x = 220.0
	_tr.offset_left = -14.0 - _tr.custom_minimum_size.x
	_tr.offset_top = 80


func _process(delta: float) -> void:
	_relayout()
	if not visible:
		return
	_update_prompts()
	_timer += delta
	if _timer < 0.2:
		return
	_timer = 0.0
	refresh()


func refresh() -> void:
	_date.text = "%s  %s  第 %d 天" % [TimeManager.date_text(), TimeManager.weekday_name(), TimeManager.day]
	_clock.text = TimeManager.clock_text()
	_weather.text = "%s %s" % [WeatherManager.icon(), WeatherManager.display_name()]
	_speed.text = "‖ 暂停" if TimeManager.speed == 0 else ("▶▶ 2 倍速 [T]" if TimeManager.speed == 2 else "▶ 1 倍速 [T]")
	_cash.text = "¥ %s" % Fmt.money(EconomyManager.cash)
	if EconomyManager.bank > 0:
		_cash.text += "   卡 ¥%s" % Fmt.money(EconomyManager.bank)
	for d in BAR_DEFS:
		var id: String = d[0]
		var v := PlayerManager.get_stat(id)
		(_bars[id] as ProgressBar).value = v
		var tag := ""
		if id == "stress":
			tag = " 过高" if v > 70 else ""
		elif v < 20:
			tag = " 危险"
		elif v < 35:
			tag = " 偏低"
		var l: Label = _bar_vals[id]
		l.text = "%d%s" % [int(v), tag]
		l.add_theme_color_override("font_color", UIKit.BAD if tag != "" else UIKit.TEXT)
	var qid := QuestManager.tracked_id()
	if qid == "":
		_quest_title.text = "自由人生" if GameManager.infinite_mode else "暂无任务"
		_quest_obj.text = "打开手机查看人生目标" if GameManager.infinite_mode else ""
		_quest_dist.text = ""
	else:
		var q := QuestManager.data(qid)
		var prefix := "第%d章 · " % int(q.get("chapter", 1)) if String(q.get("type", "")) == "main" else ""
		_quest_title.text = prefix + String(q.get("title", ""))
		var idx := QuestManager.current_objective_index(qid)
		_quest_obj.text = "▶ " + QuestManager.objective_text(qid, idx) if idx >= 0 else ""
		_quest_dist.text = _distance_text()
	_job.text = "" + JobManager.status_text()
	var unread := int(GameManager.get_value("unread_messages", 0))
	_msg_badge.text = "信 %d 条新消息（Tab 打开手机）" % unread if unread > 0 else ""


func _distance_text() -> String:
	var marker = GameManager.lookup("objective_marker")
	if marker == null or player == null:
		return ""
	var p: Vector3 = marker.target_pos
	if not marker.has_target:
		return ""
	var d := Vector2(p.x - player.global_position.x, p.z - player.global_position.z).length()
	if d < 4.0:
		return "就在附近"
	return "距离 %d 米 · %s" % [int(d), String(marker.target_name)]


func _update_prompts() -> void:
	if player == null:
		return
	var acts: Array = player.detector.current_actions()
	var key := ""
	for a in acts:
		key += "%s|%s|%s;" % [a["action"], a["label"], a.get("enabled", true)]
	if key == _last_prompt_key:
		return
	_last_prompt_key = key
	for c in _prompts.get_children():
		c.queue_free()
	for a in acts:
		var h := UIKit.hbox(8)
		h.alignment = BoxContainer.ALIGNMENT_CENTER
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var k := "E" if String(a["action"]) == "interact" else "F"
		if GameManager.touch_mode:
			k = "交互" if k == "E" else "使用"
		h.add_child(UIKit.key_cap(k))
		var enabled := bool(a.get("enabled", true))
		var l := UIKit.hud_label(String(a["label"]), 19, UIKit.TEXT if enabled else UIKit.WARN)
		h.add_child(l)
		_prompts.add_child(h)
