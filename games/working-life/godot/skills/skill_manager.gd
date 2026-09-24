extends Node
## 技能系统（自动加载名：SkillManager）。六项技能 Lv.0~10。
## 升级方式：工作、上课、读书、练习、任务奖励——全部调用 add_xp()。

var xp: Dictionary = {}


func _ready() -> void:
	reset()


func reset() -> void:
	xp.clear()
	for id in DataDB.ids("skills"):
		xp[id] = 0.0


func ids() -> Array:
	return DataDB.ids("skills")


func max_level() -> int:
	return int(DataDB.meta("skills").get("max_level", 10))


## 从 L 级升到 L+1 级需要的经验
func xp_for_next(lvl: int) -> float:
	var m := DataDB.meta("skills")
	return float(m.get("base", 80)) + float(m.get("step", 40)) * lvl


## 达到某级需要的总经验
func total_for(lvl: int) -> float:
	var t := 0.0
	for i in lvl:
		t += xp_for_next(i)
	return t


func level(id: String) -> int:
	var x: float = xp.get(id, 0.0)
	var lvl := 0
	while lvl < max_level() and x >= total_for(lvl + 1):
		lvl += 1
	return lvl


## 当前等级内的进度 0..1
func progress(id: String) -> float:
	var lvl := level(id)
	if lvl >= max_level():
		return 1.0
	var base := total_for(lvl)
	return clampf((float(xp.get(id, 0.0)) - base) / xp_for_next(lvl), 0.0, 1.0)


func add_xp(id: String, amount: float, source := "") -> void:
	if not xp.has(id) or amount <= 0.0:
		return
	var before := level(id)
	var cap := total_for(max_level())
	xp[id] = minf(float(xp[id]) + amount, cap)
	var after := level(id)
	if after > before:
		for l in range(before + 1, after + 1):
			Events.skill_level_up.emit(id, l)
		Events.say("%s 技能升到 Lv.%d！" % [DataDB.skill_name(id), after], "good")
		AudioManager.play_sfx("levelup")
	Events.stats_changed.emit()


## 把等级直接设成某值（调试面板用）
func set_level(id: String, lvl: int) -> void:
	if not xp.has(id):
		return
	xp[id] = total_for(clampi(lvl, 0, max_level()))
	Events.stats_changed.emit()


func meets(req: Dictionary) -> bool:
	for s in req:
		if level(String(s)) < int(req[s]):
			return false
	return true


## 不满足的要求列表：["电脑 Lv.3（当前 1）"]
func missing(req: Dictionary) -> Array:
	var out: Array = []
	for s in req:
		var cur := level(String(s))
		if cur < int(req[s]):
			out.append("%s Lv.%d（当前 %d）" % [DataDB.skill_name(String(s)), int(req[s]), cur])
	return out


func to_dict() -> Dictionary:
	return xp.duplicate()


func from_dict(d: Dictionary) -> void:
	reset()
	for k in d:
		if xp.has(k):
			xp[k] = float(d[k])
