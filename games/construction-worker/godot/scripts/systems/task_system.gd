extends Node
## 通用任务系统（自动加载名：TaskSystem）。
##
## 使用方式：
##   TaskSystem.accept("haul_bricks")                         接任务
##   TaskSystem.wants("deliver", {"item":..,"zone":..})        当前任务还需要多少
##   TaskSystem.notify("deliver", {"item":..,"zone":..,"count":n})  上报进度
## 任务内容全部来自 task_catalog.gd，本脚本不包含任何具体任务的硬编码。

signal task_accepted(task: TaskDefinition)
signal task_progress(task: TaskDefinition, done: int, total: int)
signal task_completed(task: TaskDefinition)
signal tasks_changed()

var catalog: Dictionary = {}
var order: Array = []
var active_id := ""
## 与 active 任务 objectives 一一对应的完成数量
var progress: Array = []
## 今天完成过的任务 id -> 次数
var completed_today: Dictionary = {}
## 历史累计完成次数 id -> 次数
var completed_total: Dictionary = {}


func _ready() -> void:
	for t in TaskCatalog.build():
		register_task(t)


func register_task(t: TaskDefinition) -> void:
	if t.id == "":
		push_warning("TaskSystem: 任务缺少 id，已忽略")
		return
	if not catalog.has(t.id):
		order.append(t.id)
	catalog[t.id] = t


func reset() -> void:
	active_id = ""
	progress = []
	completed_today = {}
	completed_total = {}
	tasks_changed.emit()


func get_task(id: String) -> TaskDefinition:
	return catalog.get(id)


func get_active() -> TaskDefinition:
	if active_id == "":
		return null
	return catalog.get(active_id)


func has_active() -> bool:
	return active_id != ""


# ---------------------------------------------------------------- 可接取判断
## 返回不可接取的原因；空字符串表示可以接
func unavailable_reason(id: String) -> String:
	var t: TaskDefinition = catalog.get(id)
	if t == null:
		return "没有这个任务"
	if active_id == id:
		return "正在进行"
	if int(completed_today.get(id, 0)) >= t.daily_limit:
		return "今天已完成"
	if TimeSystem.day < t.min_day:
		return "第 %d 天起开放" % t.min_day
	if PlayerStats.reputation < t.min_reputation:
		return "需要声望 %d" % t.min_reputation
	for req in t.requires:
		if int(completed_total.get(req, 0)) <= 0:
			var rt: TaskDefinition = catalog.get(req)
			return "先完成「%s」" % (rt.title if rt != null else req)
	if t.work_hours_only and not TimeSystem.is_work_hours():
		return "下班时间"
	return ""


func is_available(id: String) -> bool:
	return unavailable_reason(id) == ""


func available_tasks() -> Array:
	var out: Array = []
	if active_id != "":
		return out
	for id in order:
		if is_available(id):
			out.append(catalog[id])
	return out


# ---------------------------------------------------------------- 接 / 放弃
func accept(id: String) -> bool:
	if active_id != "" or not is_available(id):
		return false
	var t: TaskDefinition = catalog[id]
	active_id = id
	progress = []
	for _o in t.objectives:
		progress.append(0)
	if t.grants_meal_ticket and int(completed_today.get("_meal_ticket", 0)) == 0:
		completed_today["_meal_ticket"] = 1
		EconomySystem.add_meal_ticket(1)
		Events.say("获得：饭票 ×1（去食堂换一份盒饭）", "good")
	task_accepted.emit(t)
	tasks_changed.emit()
	Events.objective_changed.emit()
	return true


func abandon() -> void:
	if active_id == "":
		return
	active_id = ""
	progress = []
	tasks_changed.emit()
	Events.objective_changed.emit()


# ---------------------------------------------------------------- 进度
## 当前任务里还没完成的第一个目标
func next_open_objective() -> Dictionary:
	var t := get_active()
	if t == null:
		return {}
	for i in t.objectives.size():
		if int(progress[i]) < int(t.objectives[i].get("count", 1)):
			return t.objectives[i]
	return {}


## 当前任务对某个事件还需要多少数量（0 表示不需要）
func wants(event_type: String, data: Dictionary) -> int:
	var t := get_active()
	if t == null:
		return 0
	for i in t.objectives.size():
		var o: Dictionary = t.objectives[i]
		if _matches(o, event_type, data):
			var remain := int(o.get("count", 1)) - int(progress[i])
			if remain > 0:
				return remain
	return 0


## 上报事件，返回被任务「吃掉」的数量
func notify(event_type: String, data: Dictionary) -> int:
	var t := get_active()
	if t == null:
		return 0
	var amount := int(data.get("count", 1))
	var used := 0
	for i in t.objectives.size():
		if amount <= 0:
			break
		var o: Dictionary = t.objectives[i]
		if not _matches(o, event_type, data):
			continue
		var remain := int(o.get("count", 1)) - int(progress[i])
		var take := mini(remain, amount)
		if take <= 0:
			continue
		progress[i] = int(progress[i]) + take
		amount -= take
		used += take
	if used > 0:
		task_progress.emit(t, done_count(), t.total_target())
		tasks_changed.emit()
		Events.objective_changed.emit()
		if is_complete():
			_complete()
	return used


func _matches(o: Dictionary, event_type: String, data: Dictionary) -> bool:
	if String(o.get("type", "")) != event_type:
		return false
	for key in ["item", "zone"]:
		if o.has(key) and String(o[key]) != String(data.get(key, "")):
			return false
	return true


func done_count() -> int:
	var n := 0
	for p in progress:
		n += int(p)
	return n


func is_complete() -> bool:
	var t := get_active()
	if t == null:
		return false
	return done_count() >= t.total_target()


## 已经送到某个区域的数量（用于区域里的码放显示）
func delivered_to(zone_id: String) -> int:
	var t := get_active()
	if t == null:
		return 0
	var n := 0
	for i in t.objectives.size():
		if String(t.objectives[i].get("zone", "")) == zone_id:
			n += int(progress[i])
	return n


func _complete() -> void:
	var t := get_active()
	if t == null:
		return
	completed_today[t.id] = int(completed_today.get(t.id, 0)) + 1
	completed_total[t.id] = int(completed_total.get(t.id, 0)) + 1
	active_id = ""
	progress = []
	EconomySystem.earn(t.reward, "完成任务：%s" % t.title)
	PlayerStats.reputation += t.reputation
	PlayerStats.stats_changed.emit()
	if t.id == "haul_bricks":
		GameState.building_progress += 1
	task_completed.emit(t)
	tasks_changed.emit()
	Events.objective_changed.emit()


## 睡觉后调用：清空当日完成记录
func new_day() -> void:
	completed_today = {}
	tasks_changed.emit()
	Events.objective_changed.emit()


func tasks_done_today() -> int:
	var n := 0
	for k in completed_today:
		if not String(k).begins_with("_"):
			n += int(completed_today[k])
	return n


func to_dict() -> Dictionary:
	return {
		"active_id": active_id,
		"progress": progress.duplicate(),
		"completed_today": completed_today.duplicate(),
		"completed_total": completed_total.duplicate(),
	}


func from_dict(d: Dictionary) -> void:
	active_id = String(d.get("active_id", ""))
	if active_id != "" and not catalog.has(active_id):
		active_id = ""
	progress = []
	var saved: Array = d.get("progress", [])
	if active_id != "":
		var t: TaskDefinition = catalog[active_id]
		for i in t.objectives.size():
			progress.append(int(saved[i]) if i < saved.size() else 0)
	completed_today = {}
	var ct: Dictionary = d.get("completed_today", {})
	for k in ct:
		completed_today[String(k)] = int(ct[k])
	completed_total = {}
	var tt: Dictionary = d.get("completed_total", {})
	for k in tt:
		completed_total[String(k)] = int(tt[k])
	tasks_changed.emit()
	Events.objective_changed.emit()
