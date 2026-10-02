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
const ITEMS_PATH := "res://data/items.json"
const SLOTS := ["weapon", "head", "body", "hands", "legs"]
const SLOT_NAMES := {"weapon": "武器", "head": "头", "body": "身", "hands": "手", "legs": "腿"}
const KIND_NAMES := {"weapon": "武器", "armor": "护甲", "consumable": "消耗品", "quest": "任务物品", "misc": "杂物"}
## 开局随身（出身三选一在阶段 3，到时按出身改）
const START_ITEMS := ["short_sword", "padded_jacket"]
const START_EQUIP := {"weapon": "short_sword", "body": "padded_jacket"}
const START_SILVER := 12
const CARRY_BASE := 30.0          # 负重上限 = 30 + 力量 × 2（斤）
const CARRY_PER_STR := 2.0

var flags := {}
var skills := DEFAULT_SKILLS.duplicate()
var wits := DEFAULT_WITS
var strength := DEFAULT_STRENGTH
var seed_value := 0
var checks := {}          # 检定编号 → 是否成功（已经掷过的）
var quests := {}          # 任务编号 → {stage, done}
var clues: Array = []     # 得到的线索编号（按得到的先后）
var inventory: Array = [] # 物品编号（同一物品可以有多个；2.6 起装备中的物品也在这里）
var equipped := {}        # 部位 → 物品编号（2.6）
var silver := 0
var looted := {}          # 搜刮过的容器编号 → 剩下的东西（2.8 一起存档）

signal inventory_changed


func _ready() -> void:
	new_game()


func new_game(seed_override := -1) -> void:
	flags.clear()
	checks.clear()
	quests.clear()
	clues.clear()
	inventory.clear()
	inventory.append_array(START_ITEMS)
	equipped = START_EQUIP.duplicate()
	silver = START_SILVER
	looted.clear()
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


# ---------------- 物品、装备、银币（2.6） ----------------

## 物品数据（data/items.json），缓存在 Engine 元数据里（静态变量退出时释放不掉，见 2.1）
static func items() -> Dictionary:
	if not Engine.has_meta("ic_items"):
		var f := FileAccess.open(ITEMS_PATH, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text()) if f else null
		Engine.set_meta("ic_items", d if typeof(d) == TYPE_DICTIONARY else {})
	return Engine.get_meta("ic_items")


static func item(id: String) -> Dictionary:
	return items().get(id, {})


static func item_name(id: String) -> String:
	return str(item(id).get("name", id))


## 物品数据校验（自动化测试用）：返回错误列表
static func validate_items(d: Dictionary) -> Array:
	var errs := []
	var need := {"weapon": ["base", "model"], "armor": ["slot", "armor", "noise"], "consumable": ["health", "stamina"], "quest": [], "misc": []}
	for id in d:
		if str(id).begins_with("_"):
			continue
		var it: Dictionary = d[id]
		for k in ["name", "kind", "weight", "value", "desc"]:
			if not it.has(k):
				errs.append("%s 缺少 %s" % [id, k])
		var kind := str(it.get("kind", ""))
		if not need.has(kind):
			errs.append("%s 的种类 %s 不认识" % [id, kind])
			continue
		for k in need[kind]:
			if not it.has(k):
				errs.append("%s（%s）缺少 %s" % [id, kind, k])
		if kind == "armor" and not str(it.get("slot", "")) in ["head", "body", "hands", "legs"]:
			errs.append("%s 的部位不对" % id)
		if kind == "weapon" and not str(it.get("model", "")) in ["sword", "club"]:
			errs.append("%s 的外观不对" % id)
		if float(it.get("weight", -1)) < 0.0:
			errs.append("%s 的重量不对" % id)
	return errs


func add_item(id: String, n := 1) -> void:
	for i in n:
		inventory.append(id)
	inventory_changed.emit()


func has_item(id: String) -> bool:
	return inventory.has(id)


func count_item(id: String) -> int:
	return inventory.count(id)


## 拿走一个；装备着的最后一件会先卸下
func take_item(id: String) -> bool:
	var i := inventory.find(id)
	if i < 0:
		return false
	inventory.remove_at(i)
	if not inventory.has(id):
		for s in equipped.keys():
			if equipped[s] == id:
				equipped.erase(s)
	inventory_changed.emit()
	return true


func add_silver(n: int) -> void:
	silver = maxi(silver + n, 0)
	inventory_changed.emit()


func is_equipped(id: String) -> bool:
	return id in equipped.values()


func slot_of(id: String) -> String:
	var it := item(id)
	if it.get("kind") == "weapon":
		return "weapon"
	if it.get("kind") == "armor":
		return str(it.slot)
	return ""


## 装备：同部位原来的那件换下来（还在背包里）；返回是否成功
func equip(id: String) -> bool:
	var s := slot_of(id)
	if s == "" or not has_item(id):
		return false
	equipped[s] = id
	inventory_changed.emit()
	return true


## 卸下：武器卸下后就拔不出剑（空手打架在之后的步骤）
func unequip(slot: String) -> void:
	if equipped.erase(slot):
		inventory_changed.emit()


func weapon_id() -> String:
	return str(equipped.get("weapon", ""))


func armor_total() -> float:
	var a := 0.0
	for s in ["head", "body", "hands", "legs"]:
		if equipped.has(s):
			a += float(item(equipped[s]).get("armor", 0))
	return a


## 护甲越重越吵：走动时声音多传出去的米数（敌人听觉，2.5）
func armor_noise() -> float:
	var n := 0.0
	for s in ["head", "body", "hands", "legs"]:
		if equipped.has(s):
			n += float(item(equipped[s]).get("noise", 0))
	return n


func carry_weight() -> float:
	var w := 0.0
	for id in inventory:
		w += float(item(id).get("weight", 0))
	return w


func carry_limit() -> float:
	return CARRY_BASE + strength * CARRY_PER_STR


## 超重：不能跑（GDD.md 第八节）
func over_encumbered() -> bool:
	return carry_weight() > carry_limit()


## 用掉一个消耗品；返回 {health, stamina}（由 main 交给玩家），不是消耗品返回空字典
func use_item(id: String) -> Dictionary:
	var it := item(id)
	if it.get("kind") != "consumable" or not has_item(id):
		return {}
	take_item(id)
	return {"health": int(it.get("health", 0)), "stamina": float(it.get("stamina", 0))}


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
