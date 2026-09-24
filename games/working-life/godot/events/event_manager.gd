extends Node
## 随机事件系统（自动加载名：EventManager）。事件内容全部来自 data/events.json。
## 触发时机：起床后（morning）、下班后（shift_end）、18:00（evening）、12:00（day）。
## 选中的事件先进入队列，等玩家没有打开任何窗口时再弹出（UIRoot 取队列）。

signal queue_changed

var cooldowns: Dictionary = {}
var queue: Array = []
## 延迟生效的效果：[{day, effects, note}]
var delayed: Array = []
var history: Array = []
var enabled := true
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	TimeManager.hour_changed.connect(_on_hour)
	TimeManager.day_changed.connect(_on_day)


func reset() -> void:
	cooldowns.clear()
	queue.clear()
	delayed.clear()
	history.clear()


func chance_for(trigger: String) -> float:
	return float(DataDB.meta("events").get("chance", {}).get(trigger, 0.25))


func eligible(trigger: String) -> Array:
	var out: Array = []
	for id in DataDB.ids("events"):
		var e: Dictionary = DataDB.events[id]
		if String(e.get("trigger", "day")) != trigger:
			continue
		if int(cooldowns.get(id, -999)) > TimeManager.day:
			continue
		if not Conditions.check(e.get("conditions", {})):
			continue
		out.append(id)
	return out


## 按概率尝试触发一个事件，返回事件 id（没有触发返回空字符串）
func roll(trigger: String, force := false) -> String:
	if not enabled or not GameManager.playing:
		return ""
	# 前两天是新手期，不打扰
	if TimeManager.day <= 1 and not force:
		return ""
	if not force and _rng.randf() > chance_for(trigger):
		return ""
	var ids := eligible(trigger)
	if ids.is_empty():
		return ""
	var total := 0.0
	for id in ids:
		total += float(DataDB.events[id].get("weight", 1))
	var r := _rng.randf() * total
	for id in ids:
		r -= float(DataDB.events[id].get("weight", 1))
		if r <= 0.0:
			trigger_event(id)
			return id
	trigger_event(ids[-1])
	return ids[-1]


func trigger_event(id: String) -> void:
	var e: Dictionary = DataDB.events.get(id, {})
	if e.is_empty():
		return
	cooldowns[id] = TimeManager.day + int(e.get("cooldown", 5))
	history.append({"id": id, "day": TimeManager.day})
	if history.size() > 50:
		history.pop_front()
	queue.append(id)
	queue_changed.emit()


func pop_next() -> String:
	if queue.is_empty():
		return ""
	var id := String(queue.pop_front())
	queue_changed.emit()
	return id


## 可选项是否可用
func choice_available(choice: Dictionary) -> bool:
	return Conditions.check(choice.get("requires", {}))


## 执行事件（choice_index = -1 表示没有选项的事件）。返回结果文字。
func resolve(id: String, choice_index := -1) -> String:
	var e: Dictionary = DataDB.events.get(id, {})
	var effects: Dictionary = e.get("effects", {})
	var result := String(e.get("result", ""))
	var choices: Array = e.get("choices", [])
	if choice_index >= 0 and choice_index < choices.size():
		var c: Dictionary = choices[choice_index]
		effects = c.get("effects", {})
		result = String(c.get("result", ""))
	var notes := Effects.apply(effects, String(e.get("title", "事件")), "其他")
	var parts: Array = []
	if result != "":
		parts.append(result)
	parts.append_array(notes)
	var d := Effects.describe(effects)
	if d != "":
		parts.append("（%s）" % d)
	return "\n".join(parts)


func schedule_delayed(days: int, effects: Dictionary, note: String) -> void:
	delayed.append({"day": TimeManager.day + days, "effects": effects, "note": note})


func _on_hour(h: int) -> void:
	if not GameManager.playing:
		return
	if h == 12:
		roll("day")
	elif h == 18:
		roll("evening")


func _on_day(d: int) -> void:
	for x in delayed.duplicate():
		if int(x["day"]) <= d:
			delayed.erase(x)
			Effects.apply(x["effects"], String(x["note"]), "其他")
			Events.phone_message.emit("通知", "%s：%s" % [String(x["note"]), Effects.describe(x["effects"])])


func to_dict() -> Dictionary:
	return {"cooldowns": cooldowns, "delayed": delayed, "history": history}


func from_dict(d: Dictionary) -> void:
	cooldowns.clear()
	for k in d.get("cooldowns", {}):
		cooldowns[String(k)] = int(d["cooldowns"][k])
	delayed = Array(d.get("delayed", [])).duplicate(true)
	history = Array(d.get("history", [])).duplicate(true)
	queue.clear()
