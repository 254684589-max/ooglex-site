extends Node
## 存档系统（自动加载名：SaveManager）。3 个存档槽，JSON 格式：user://working_life_slot_<n>.json。
## 网页版的 user:// 由 Godot 映射到浏览器 IndexedDB。
## 保存：玩家位置、现金 / 存款、属性、技能、职业与职位、工资、任务、日期与时间、住房、背包与购买物、
## 投资、NPC 关系、创业状态、剧情状态、天气、随机事件冷却。
## 自动保存：每天睡醒以后；手动保存：暂停菜单。

signal saved(slot: int, ok: bool)

const SLOTS := 3
const VERSION := 1

var current_slot := 1


func path(slot: int) -> String:
	return "user://working_life_slot_%d.json" % slot


func has_save(slot: int) -> bool:
	return not read(slot).is_empty()


func any_save() -> bool:
	for i in range(1, SLOTS + 1):
		if has_save(i):
			return true
	return false


## 最近保存的槽位（继续游戏用），没有返回 0
func latest_slot() -> int:
	var best := 0
	var best_t := -1.0
	for i in range(1, SLOTS + 1):
		var d := read(i)
		if d.is_empty():
			continue
		var t := float(d.get("unix", 0))
		if t > best_t:
			best_t = t
			best = i
	return best


func read(slot: int) -> Dictionary:
	var p := path(slot)
	if not FileAccess.file_exists(p):
		return {}
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY or int(data.get("version", 0)) < 1:
		return {}
	return data


func build() -> Dictionary:
	var d := {
		"version": VERSION,
		"game": "WorkingLife",
		"saved_at": Time.get_datetime_string_from_system(false, true),
		"unix": Time.get_unix_time_from_system(),
		"summary": summary_now(),
		"game_state": GameManager.to_dict(),
		"time": TimeManager.to_dict(),
		"weather": WeatherManager.to_dict(),
		"economy": EconomyManager.to_dict(),
		"skills": SkillManager.to_dict(),
		"player_stats": PlayerManager.to_dict(),
		"housing": HousingManager.to_dict(),
		"jobs": JobManager.to_dict(),
		"npcs": NPCManager.to_dict(),
		"quests": QuestManager.to_dict(),
		"events": EventManager.to_dict(),
		"investment": InvestmentManager.to_dict(),
		"business": BusinessManager.to_dict(),
		"vehicles": VehicleManager.to_dict(),
	}
	var p := GameManager.player
	if p != null and p.has_method("to_save_dict"):
		d["player"] = p.to_save_dict()
	return d


func save(slot := -1) -> bool:
	if slot < 0:
		slot = current_slot
	if not GameManager.playing:
		return false
	var f := FileAccess.open(path(slot), FileAccess.WRITE)
	if f == null:
		push_warning("SaveManager: 无法写入存档 %s" % error_string(FileAccess.get_open_error()))
		saved.emit(slot, false)
		return false
	f.store_string(JSON.stringify(build(), "\t"))
	f.close()
	current_slot = slot
	saved.emit(slot, true)
	return true


## 把存档数据应用到各系统（场景必须已经创建）
func apply(d: Dictionary) -> bool:
	if d.is_empty():
		return false
	GameManager.from_dict(d.get("game_state", {}))
	TimeManager.from_dict(d.get("time", {}))
	WeatherManager.from_dict(d.get("weather", {}))
	EconomyManager.from_dict(d.get("economy", {}))
	SkillManager.from_dict(d.get("skills", {}))
	PlayerManager.from_dict(d.get("player_stats", {}))
	HousingManager.from_dict(d.get("housing", {}))
	JobManager.from_dict(d.get("jobs", {}))
	NPCManager.from_dict(d.get("npcs", {}))
	QuestManager.from_dict(d.get("quests", {}))
	EventManager.from_dict(d.get("events", {}))
	InvestmentManager.from_dict(d.get("investment", {}))
	BusinessManager.from_dict(d.get("business", {}))
	VehicleManager.from_dict(d.get("vehicles", {}))
	var p := GameManager.player
	if p != null and p.has_method("apply_save_dict"):
		p.apply_save_dict(d.get("player", {}))
	NPCManager.refresh_schedules(true)
	Events.stats_changed.emit()
	return true


func delete(slot: int) -> void:
	if FileAccess.file_exists(path(slot)):
		DirAccess.remove_absolute(path(slot))


func summary_now() -> String:
	return "第 %d 天 %s · %s · %s" % [TimeManager.day, TimeManager.clock_text(), JobManager.title(), Fmt.yuan(EconomyManager.liquid())]


func slot_text(slot: int) -> String:
	var d := read(slot)
	if d.is_empty():
		return "空"
	return "%s\n%s" % [String(d.get("summary", "")), String(d.get("saved_at", "")).replace("T", " ")]
