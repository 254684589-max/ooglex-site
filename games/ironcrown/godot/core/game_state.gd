extends Node
## 游戏状态（路线图 2.2；GDD.md 5.3、7.2、7.4）：旗标、对话检定用的技能与属性、检定结果；2.3 起还有任务、线索、背包。
## 旗标清单登记在 data/flags.json（每个旗标写明在哪里设置、在哪里读取），没登记的旗标校验时报错。
## 检定结果由「存档种子 + 检定编号」决定，并记下来：读档、重开对话都刷不出别的结果（GDD.md 5.3「不能刷」）。
## 2.8 起由 core/saves.gd 存档：to_dict() / from_dict() 是游戏状态与存档之间唯一的转换。

signal flag_changed(name: String, value)
## 任务事件：kind = started / advanced / done / clue；id = 任务编号或线索编号
signal quest_event(kind: String, id: String)

const SKILL_NAMES := {"blade": "剑术", "blunt": "钝器", "brawl": "格斗", "speech": "口才", "intimidate": "威吓", "insight": "洞察", "stealth": "潜行", "survival": "生存"}
## 默认值（出身三选一在阶段 3 做，到时按出身改开局数值）
## 开局数值在 data/progression.json（2.7）；这里的常量只是读不到数据时的后备
const DEFAULT_SKILLS := {"blade": 15, "blunt": 5, "brawl": 5, "speech": 10, "intimidate": 6, "insight": 8, "stealth": 5, "survival": 5}
const DEFAULT_WITS := 3
const DEFAULT_STRENGTH := 5
const PROGRESSION_PATH := "res://data/progression.json"
const ATTRS := ["strength", "agility", "constitution", "wits"]
## 专长效果白名单（data/progression.json 的 effect 只能用这些）
const PERK_EFFECTS := ["combo3", "counter", "parry_window", "blunt_stagger", "armor_pierce", "fist_stagger", "guard_cheap", "check_bonus", "stealth_slow", "carry", "loot_bonus"]
const SKILL_MAX := 100
const LEVEL_EVERY := 10          # 技能每累计提升 10 次，角色升一级、得 1 个属性点
const REP_MIN := -100
const REP_MAX := 100
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
var agility := 5
var constitution := 5
var skill_xp := {}        # 技能 → 当前这一级的进度
var skill_ups := 0        # 开局以来技能一共提升了几次（每 LEVEL_EVERY 次升一级）
var level := 1
var attr_points := 0
var rep := {}             # 势力 → 声望 −100..100

## 技能提升 / 解锁专长 / 角色升级 / 声望变化（main 显示提示）
signal skill_up(skill: String, value: int)
signal perk_unlocked(skill: String, perk: Dictionary)
signal level_up(new_level: int)
signal rep_changed(faction: String, delta: int, value: int)
var seed_value := 0
var checks := {}          # 检定编号 → 是否成功（已经掷过的）
var quests := {}          # 任务编号 → {stage, done}
var clues: Array = []     # 得到的线索编号（按得到的先后）
var inventory: Array = [] # 物品编号（同一物品可以有多个；2.6 起装备中的物品也在这里）
var equipped := {}        # 部位 → 物品编号（2.6）
var silver := 0
var looted := {}          # 搜刮过的容器编号 → 剩下的东西
var picked: Array = []    # 已经捡走的地上物品（Pickup.pickup_id），读档后不再出现（2.8）
var dead := {}            # 已经倒下的敌人编号 → 倒下的位置 [x, y, z]，读档后直接是倒下的样子（2.8）
var yielded := {}         # 求饶（或逃跑后认输）的敌人编号 → 跪下的位置 [x, y, z]，读档后还跪在那里、能搜身（3.5）
var playtime := 0.0       # 游戏时间（秒，暂停时不算）
var pending_load := {}    # 读档：{scene, player}，场景重新载入后由 main 取走（2.8）
var pending_brawl := {}   # 对话里说好要打一架：{brawl, win, lose}，对话关上后由 main 取走开打（3.3；不存档）

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
	picked.clear()
	dead.clear()
	yielded.clear()
	playtime = 0.0
	var pd := progression()
	skills = DEFAULT_SKILLS.duplicate()
	for s in pd.get("skills", {}):
		skills[s] = int(pd.skills[s].start)
	var at: Dictionary = pd.get("attributes", {})
	strength = int(at.get("strength", {}).get("start", DEFAULT_STRENGTH))
	agility = int(at.get("agility", {}).get("start", 5))
	constitution = int(at.get("constitution", {}).get("start", 5))
	wits = int(at.get("wits", {}).get("start", DEFAULT_WITS))
	skill_xp.clear()
	skill_ups = 0
	level = 1
	attr_points = 0
	rep.clear()
	for f in pd.get("factions", {}):
		rep[f] = int(pd.factions[f].start)
	seed_value = seed_override if seed_override >= 0 else randi()


func set_flag(name: String, value = true) -> void:
	flags[name] = value
	flag_changed.emit(name, value)


func get_flag(name: String, default = null):
	return flags.get(name, default)


func has_flag(name: String) -> bool:
	return flags.has(name) and bool(flags[name])


## 检定值 = 技能 + 机敏 × 2 + 专长加成（情境修正：声望、情报、衣着、贿赂在之后的步骤加）
func check_value(skill: String) -> int:
	return int(skills.get(skill, 0)) + wits * 2 + (5 if has_perk(skill, "check_bonus") else 0)


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
	train(skill, 3.0 if ok else 1.0)        # 用什么涨什么：检定成功涨得多（2.7）
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
	# 物品数据里写了 clue 的（3.2：墓室里那封没写完的信），拿到手就记下线索
	var c := str(item(id).get("clue", ""))
	if c != "":
		add_clue(c)


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
	return CARRY_BASE + strength * CARRY_PER_STR + (10.0 if has_perk("survival", "carry") else 0.0)


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


## 阶段的 advance_when：{"clues_at_least": n, "to": 下一阶段}——线索够了自动推进；{"clue": 线索, "to": 下一阶段}——拿到这条线索就推进（3.5）。
## set_stage 推进以后会再查一次新阶段（先拿到雇佣信、后凑够线索时，一口气推到底）
func _auto_advance(id: String) -> void:
	if not quest_active(id):
		return
	var st: Dictionary = quest_data().quests[id].stages.get(quest_stage(id), {})
	var rule: Dictionary = st.get("advance_when", {})
	if rule.has("clues_at_least") and clues_for(id).size() >= int(rule.clues_at_least):
		set_stage(id, str(rule.to))
	elif rule.has("clue") and clues.has(str(rule.clue)):
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


# ---------------- 属性、技能、专长、声望（2.7） ----------------

static func progression() -> Dictionary:
	if not Engine.has_meta("ic_progression"):
		var f := FileAccess.open(PROGRESSION_PATH, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text()) if f else null
		Engine.set_meta("ic_progression", d if typeof(d) == TYPE_DICTIONARY else {})
	return Engine.get_meta("ic_progression")


## 成长数据校验（自动化测试用）
static func validate_progression(d: Dictionary) -> Array:
	var errs := []
	for a in ATTRS:
		if not d.get("attributes", {}).has(a):
			errs.append("缺属性 %s" % a)
	for s in SKILL_NAMES:
		if not d.get("skills", {}).has(s):
			errs.append("缺技能 %s" % s)
	for s in d.get("skills", {}):
		var sk: Dictionary = d.skills[s]
		if not SKILL_NAMES.has(s):
			errs.append("技能 %s 不在 SKILL_NAMES 里" % s)
		elif str(sk.get("name", "")) != SKILL_NAMES[s]:
			errs.append("技能 %s 的名字与 SKILL_NAMES 不一致" % s)
		var last := 0
		for p in sk.get("perks", []):
			if not int(p.get("at", 0)) in [25, 50, 75] or int(p.at) <= last:
				errs.append("%s 的专长门槛应是 25 / 50 / 75 且递增" % s)
			last = int(p.get("at", 0))
			if not str(p.get("effect", "")) in PERK_EFFECTS:
				errs.append("%s 的专长效果 %s 不在白名单里" % [s, p.get("effect", "")])
			for k in ["name", "desc"]:
				if str(p.get(k, "")) == "":
					errs.append("%s 的专长缺 %s" % [s, k])
	if (d.get("factions", {}) as Dictionary).size() != 8:
		errs.append("势力应有 8 个（五大家族 + 烽誓团 + 渡工行会 + 无旗者，GDD 7.3）")
	return errs


static func attr_name(a: String) -> String:
	return str(progression().get("attributes", {}).get(a, {}).get("name", a))


func attr(a: String) -> int:
	match a:
		"strength":
			return strength
		"agility":
			return agility
		"constitution":
			return constitution
		"wits":
			return wits
	return 0


## 花 1 个属性点
func raise_attr(a: String) -> bool:
	if attr_points <= 0 or not a in ATTRS:
		return false
	attr_points -= 1
	set(a, attr(a) + 1)
	inventory_changed.emit()              # 负重上限可能变了
	return true


## 生命上限、体力上限：80 + 体魄 × 4（体魄 5 = 100）
func health_max() -> int:
	return 80 + constitution * 4


func stamina_max() -> float:
	return 80.0 + constitution * 4.0


## 体力恢复倍率：敏捷每点 ±5%（以 5 为准）
func stamina_regen_mult() -> float:
	return 1.0 + (agility - 5) * 0.05


## 这一级还要多少进度才升到下一级
static func skill_need(value: int) -> float:
	return 2.0 + value * 0.2


func skill_progress(skill: String) -> float:
	return clampf(float(skill_xp.get(skill, 0.0)) / skill_need(int(skills.get(skill, 0))), 0.0, 1.0)


## 用了一次技能：加进度，够了就升级（可能连升），到 25 / 50 / 75 解锁专长；技能每累计升 10 次角色升一级
func train(skill: String, amount: float) -> void:
	if not skills.has(skill) or amount <= 0.0:
		return
	var xp := float(skill_xp.get(skill, 0.0)) + amount
	while int(skills[skill]) < SKILL_MAX and xp >= skill_need(int(skills[skill])):
		xp -= skill_need(int(skills[skill]))
		skills[skill] = int(skills[skill]) + 1
		skill_up.emit(skill, int(skills[skill]))
		for p in perks_of(skill):
			if int(p.at) == int(skills[skill]):
				perk_unlocked.emit(skill, p)
		skill_ups += 1
		if skill_ups % LEVEL_EVERY == 0:
			level += 1
			attr_points += 1
			level_up.emit(level)
	skill_xp[skill] = xp if int(skills[skill]) < SKILL_MAX else 0.0


static func perks_of(skill: String) -> Array:
	return progression().get("skills", {}).get(skill, {}).get("perks", [])


func has_perk(skill: String, effect: String) -> bool:
	for p in perks_of(skill):
		if str(p.effect) == effect and int(skills.get(skill, 0)) >= int(p.at):
			return true
	return false


static func faction_name(f: String) -> String:
	return str(progression().get("factions", {}).get(f, {}).get("name", f))


func get_rep(f: String) -> int:
	return int(rep.get(f, 0))


func change_rep(f: String, delta: int) -> void:
	if delta == 0 or not progression().get("factions", {}).has(f):
		return
	var before := get_rep(f)
	rep[f] = clampi(before + delta, REP_MIN, REP_MAX)
	if rep[f] != before:
		rep_changed.emit(f, rep[f] - before, rep[f])


## 声望五档（GDD 7.3）
static func rep_tier(v: int) -> String:
	if v <= -50:
		return "敌视"
	if v <= -15:
		return "冷淡"
	if v < 15:
		return "中立"
	if v < 50:
		return "友善"
	return "信任"


# ---------------- 存档转换（2.8） ----------------

## 游戏状态 → 可以写成 JSON 的字典
func to_dict() -> Dictionary:
	return {
		"seed": seed_value, "flags": flags.duplicate(true), "checks": checks.duplicate(), "quests": quests.duplicate(true), "clues": clues.duplicate(),
		"inventory": inventory.duplicate(), "equipped": equipped.duplicate(), "silver": silver, "looted": looted.duplicate(true),
		"picked": picked.duplicate(), "dead": dead.duplicate(true), "yielded": yielded.duplicate(true), "playtime": playtime,
		"attributes": {"strength": strength, "agility": agility, "constitution": constitution, "wits": wits},
		"skills": skills.duplicate(), "skill_xp": skill_xp.duplicate(), "skill_ups": skill_ups, "level": level, "attr_points": attr_points,
		"rep": rep.duplicate(),
	}


## 存档字典 → 游戏状态。JSON 读回来数字都是浮点，这里转回整数；缺的字段用新游戏的默认值（旧存档少字段也能读）
func from_dict(d: Dictionary) -> void:
	new_game(int(d.get("seed", 0)))
	flags = (d.get("flags", {}) as Dictionary).duplicate(true)
	checks = (d.get("checks", {}) as Dictionary).duplicate()
	quests = {}
	for q in d.get("quests", {}):
		var v: Dictionary = d.quests[q]
		quests[q] = {"stage": str(v.get("stage", "")), "done": bool(v.get("done", false))}
	clues = Array(d.get("clues", [])).map(func(x): return str(x))
	if d.has("inventory"):
		inventory = Array(d.inventory).map(func(x): return str(x))
	if d.has("equipped"):
		equipped = {}
		for s in d.equipped:
			equipped[str(s)] = str(d.equipped[s])
	silver = int(d.get("silver", silver))
	looted = {}
	for k in d.get("looted", {}):
		var c: Dictionary = d.looted[k]
		looted[k] = {"items": Array(c.get("items", [])).map(func(x): return str(x)), "silver": int(c.get("silver", 0))}
	picked = Array(d.get("picked", [])).map(func(x): return str(x))
	dead = {}
	for k in d.get("dead", {}):
		dead[str(k)] = Array(d.dead[k]).map(func(x): return float(x))
	yielded = {}
	for k in d.get("yielded", {}):
		yielded[str(k)] = Array(d.yielded[k]).map(func(x): return float(x))
	playtime = float(d.get("playtime", 0.0))
	var at: Dictionary = d.get("attributes", {})
	strength = int(at.get("strength", strength))
	agility = int(at.get("agility", agility))
	constitution = int(at.get("constitution", constitution))
	wits = int(at.get("wits", wits))
	for s in d.get("skills", {}):
		skills[s] = int(d.skills[s])
	skill_xp = {}
	for s in d.get("skill_xp", {}):
		skill_xp[s] = float(d.skill_xp[s])
	skill_ups = int(d.get("skill_ups", 0))
	level = int(d.get("level", 1))
	attr_points = int(d.get("attr_points", 0))
	for f in d.get("rep", {}):
		rep[f] = int(d.rep[f])
	inventory_changed.emit()
