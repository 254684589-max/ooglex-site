extends Node
## 游戏状态（路线图 2.2；GDD.md 5.3、7.2、7.4）：旗标、对话检定用的技能与属性、检定结果；2.3 起还有任务、线索、背包。
## 旗标清单登记在 data/flags.json（每个旗标写明在哪里设置、在哪里读取），没登记的旗标校验时报错。
## 检定结果由「存档种子 + 检定编号」决定，并记下来：读档、重开对话都刷不出别的结果（GDD.md 5.3「不能刷」）。
## 存档在 2.8：到时把 flags / seed / checks / skills 一起写进存档；现在每次打开页面是一局新游戏。

signal flag_changed(name: String, value)
## 任务事件：kind = started / advanced / done / clue；id = 任务编号或线索编号
signal quest_event(kind: String, id: String)

const SKILL_NAMES := {"speech": "口才", "intimidate": "威吓", "insight": "洞察", "blade": "剑术"}
## 默认值（出身三选一在阶段 3 做，到时按出身改开局数值）
const DEFAULT_SKILLS := {"speech": 10, "intimidate": 6, "insight": 8, "blade": 15}
const DEFAULT_WITS := 3
const DEFAULT_STRENGTH := 5     # 力量（近战伤害，GDD.md 6.3；属性界面在 2.7）
const FLAGS_PATH := "res://data/flags.json"
const QUESTS_PATH := "res://data/quests.json"

var flags := {}
var skills := DEFAULT_SKILLS.duplicate()
var wits := DEFAULT_WITS
var strength := DEFAULT_STRENGTH
var seed_value := 0
var checks := {}          # 检定编号 → 是否成功（已经掷过的）
var quests := {}          # 任务编号 → {stage, done}
var clues: Array = []     # 得到的线索编号（按得到的先后）
var inventory: Array = [] # 物品编号（2.3 从 main 挪过来；背包界面在 2.6）


func _ready() -> void:
	new_game()


func new_game(seed_override := -1) -> void:
	flags.clear()
	checks.clear()
	quests.clear()
	clues.clear()
	inventory.clear()
	skills = DEFAULT_SKILLS.duplicate()
	wits = DEFAULT_WITS
	strength = DEFAULT_STRENGTH
	seed_value = seed_override if seed_override >= 0 else randi()


func set_flag(name: String, value = true) -> void:
	flags[name] = value
	flag_changed.emit(name, value)


func get_flag(name: String, default = null):
	return flags.get(name, default)


func has_flag(name: String) -> bool:
	return flags.has(name) and bool(flags[name])


## 检定值 = 技能 + 机敏 × 2（情境修正：声望、情报、衣着、贿赂在之后的步骤加）
func check_value(skill: String) -> int:
	return int(skills.get(skill, 0)) + wits * 2


## 成功把握 0.05..0.95：检定值每比难度高 1 点，把握 +5%
func check_chance(skill: String, dc: int) -> float:
	return clampf(0.5 + (check_value(skill) - dc) * 0.05, 0.05, 0.95)


static func chance_label(chance: float) -> String:
	if chance >= 0.8:
		return "把握很大"
	if chance >= 0.6:
		return "把握较大"
	if chance >= 0.4:
		return "一半一半"
	if chance >= 0.2:
		return "把握较小"
	return "几乎没把握"


## 这次检定的掷骰（0..1）：只由存档种子和检定编号决定
## 不直接用哈希的低位：编号相近的检定（a_1、a_2……）低位分布不均，实测把握 70% 成功了 85%（2.2）；哈希只当随机数生成器的种子
func roll_for(check_id: String) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d:%s" % [seed_value, check_id])
	return rng.randf()


## 做检定：第一次按把握判定并记下来，之后同一个检定永远返回同样的结果
func check(check_id: String, skill: String, dc: int) -> bool:
	if checks.has(check_id):
		return checks[check_id]
	var ok := roll_for(check_id) < check_chance(skill, dc)
	checks[check_id] = ok
	return ok


# ---------------- 物品（2.6 做背包界面） ----------------

func add_item(item: String) -> void:
	inventory.append(item)


func has_item(item: String) -> bool:
	return inventory.has(item)


func take_item(item: String) -> bool:
	var i := inventory.find(item)
	if i < 0:
		return false
	inventory.remove_at(i)
	return true


# ---------------- 任务与线索（2.3） ----------------

## 任务数据（data/quests.json）：{quests: {编号: {title, kind, summary, stages: {阶段: {objective, advance_when?}}, first}}, clues: {编号: {text, quest}}}
static func quest_data() -> Dictionary:
	if Engine.has_meta("ic_quests"):
		return Engine.get_meta("ic_quests")
	var f := FileAccess.open(QUESTS_PATH, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f else null
	if typeof(d) != TYPE_DICTIONARY:
		push_warning("任务数据打不开：" + QUESTS_PATH)
		d = {"quests": {}, "clues": {}}
	Engine.set_meta("ic_quests", d)
	return d


func quest_active(id: String) -> bool:
	return quests.has(id) and not quests[id].done


func quest_done(id: String) -> bool:
	return quests.has(id) and quests[id].done


func quest_stage(id: String) -> String:
	return str(quests[id].stage) if quests.has(id) else ""


func start_quest(id: String, stage := "") -> void:
	var q: Dictionary = quest_data().quests.get(id, {})
	if q.is_empty() or quests.has(id):
		return
	quests[id] = {"stage": stage if stage != "" else str(q.first), "done": false}
	quest_event.emit("started", id)
	_auto_advance(id)


func set_stage(id: String, stage: String) -> void:
	if not quests.has(id):
		start_quest(id, stage)
		return
	if quests[id].done or quests[id].stage == stage:
		return
	quests[id].stage = stage
	quest_event.emit("advanced", id)
	_auto_advance(id)


func complete_quest(id: String) -> void:
	if not quests.has(id):
		start_quest(id)
	if quests[id].done:
		return
	quests[id].done = true
	quest_event.emit("done", id)


func add_clue(clue: String) -> void:
	if clues.has(clue) or not quest_data().clues.has(clue):
		return
	clues.append(clue)
	quest_event.emit("clue", clue)
	_auto_advance(str(quest_data().clues[clue].quest))


## 某个任务已经得到的线索
func clues_for(quest: String) -> Array:
	var out := []
	for c in clues:
		if str(quest_data().clues[c].quest) == quest:
			out.append(c)
	return out


## 阶段的 advance_when：{"clues_at_least": n, "to": 下一阶段}——线索够了自动推进
func _auto_advance(id: String) -> void:
	if not quest_active(id):
		return
	var st: Dictionary = quest_data().quests[id].stages.get(quest_stage(id), {})
	var rule: Dictionary = st.get("advance_when", {})
	if rule.has("clues_at_least") and clues_for(id).size() >= int(rule.clues_at_least):
		set_stage(id, str(rule.to))


## 已登记的旗标（data/flags.json）
static func flag_registry() -> Dictionary:
	if Engine.has_meta("ic_flags"):
		return Engine.get_meta("ic_flags")
	var f := FileAccess.open(FLAGS_PATH, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f else null
	if typeof(d) != TYPE_DICTIONARY:
		push_warning("旗标清单打不开：" + FLAGS_PATH)
		d = {}
	Engine.set_meta("ic_flags", d)
	return d
