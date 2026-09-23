extends Node
## 人物属性（自动加载名：PlayerStats）：体力、饥饿、水分、技能、声望、装备。
## 饥饿 / 水分为「饱足度」：100 = 饱，0 = 饿坏了 / 渴坏了。

signal stats_changed()
signal skill_level_up(skill: String, level: int)
signal equipment_changed()

const MAX_STAMINA := 100.0
## 每游戏分钟的基础消耗
const HUNGER_PER_MINUTE := 0.105
const THIRST_PER_MINUTE := 0.15
## 低于这个值不再自然恢复体力
const NEED_WARNING := 20.0

## 技能经验门槛：达到第 i 个门槛即为 i+1 级
const SKILL_THRESHOLDS := {
	"carry": [0, 4, 16, 60],
}
const SKILL_NAMES := {
	"carry": "搬运",
}
const TOOLS := [
	{"id": "hands", "name": "徒手", "requires": ""},
	{"id": "gloves", "name": "劳保手套", "requires": "gloves"},
	{"id": "wheelbarrow", "name": "独轮车", "requires": "locked", "hint": "独轮车还在仓库里，后续版本开放"},
	{"id": "trowel", "name": "瓦刀", "requires": "locked", "hint": "学会砌墙才用得上瓦刀，后续版本开放"},
	{"id": "wrench", "name": "扳手", "requires": "locked", "hint": "绑钢筋、支模板的工具，后续版本开放"},
]

var stamina := MAX_STAMINA
var hunger := 80.0
var thirst := 80.0
var reputation := 0
var skills := {"carry": 0}
var equipment := {"hardhat": false, "gloves": false}
var tool_index := 0
## 体力曾经耗尽：恢复到 30 之前不能奔跑
var exhausted := false


func reset() -> void:
	stamina = MAX_STAMINA
	hunger = 80.0
	thirst = 80.0
	reputation = 0
	skills = {"carry": 0}
	equipment = {"hardhat": false, "gloves": false}
	tool_index = 0
	exhausted = false
	stats_changed.emit()
	equipment_changed.emit()


# ---------------------------------------------------------------- 属性变化
func change_stamina(amount: float) -> void:
	stamina = clampf(stamina + amount, 0.0, MAX_STAMINA)
	if stamina <= 0.0:
		exhausted = true
	elif exhausted and stamina >= 30.0:
		exhausted = false
	stats_changed.emit()


func change_hunger(amount: float) -> void:
	hunger = clampf(hunger + amount, 0.0, 100.0)
	stats_changed.emit()


func change_thirst(amount: float) -> void:
	thirst = clampf(thirst + amount, 0.0, 100.0)
	stats_changed.emit()


## 随时间自然消耗饥饿与水分。exertion：0 = 休息，1 = 满负荷干活。
func tick_needs(game_minutes: float, exertion: float) -> void:
	hunger = clampf(hunger - game_minutes * HUNGER_PER_MINUTE * (1.0 + exertion * 0.5), 0.0, 100.0)
	thirst = clampf(thirst - game_minutes * THIRST_PER_MINUTE * (1.0 + exertion * 0.9), 0.0, 100.0)
	stats_changed.emit()


func needs_ok() -> bool:
	return hunger >= NEED_WARNING and thirst >= NEED_WARNING


func starving() -> bool:
	return hunger <= 0.0 or thirst <= 0.0


func can_sprint() -> bool:
	return not exhausted and stamina > 5.0


## 体力对移动速度的影响
func stamina_speed_factor() -> float:
	if stamina <= 0.0:
		return 0.5
	if stamina < 8.0:
		return 0.62
	if stamina < 20.0:
		return 0.82
	return 1.0


## 0 = 精神，1 = 快要倒下。用于镜头晃动与暗角
func fatigue_level() -> float:
	if stamina >= 25.0:
		return 0.0
	return clampf((25.0 - stamina) / 25.0, 0.0, 1.0)


func restore_after_sleep(quality := 1.0) -> void:
	stamina = MAX_STAMINA * clampf(quality, 0.3, 1.0)
	exhausted = false
	# 一觉醒来会饿、会渴
	hunger = clampf(hunger - 22.0, 5.0, 100.0)
	thirst = clampf(thirst - 28.0, 5.0, 100.0)
	stats_changed.emit()


# ---------------------------------------------------------------- 技能
func skill_xp(skill: String) -> int:
	return int(skills.get(skill, 0))


func skill_level(skill: String) -> int:
	var th: Array = SKILL_THRESHOLDS.get(skill, [0])
	var xp := skill_xp(skill)
	var level := 1
	for i in th.size():
		if xp >= int(th[i]):
			level = i + 1
	return level


func skill_max_level(skill: String) -> int:
	return (SKILL_THRESHOLDS.get(skill, [0]) as Array).size()


## 距离下一级还差多少经验，满级返回 0
func xp_to_next(skill: String) -> int:
	var th: Array = SKILL_THRESHOLDS.get(skill, [0])
	var lv := skill_level(skill)
	if lv >= th.size():
		return 0
	return int(th[lv]) - skill_xp(skill)


func add_skill_xp(skill: String, amount: int) -> void:
	var before := skill_level(skill)
	skills[skill] = skill_xp(skill) + amount
	var after := skill_level(skill)
	stats_changed.emit()
	if after > before:
		skill_level_up.emit(skill, after)


func carry_level() -> int:
	return skill_level("carry")


func carry_capacity(item_id: String) -> int:
	return ItemDB.capacity(item_id, carry_level())


## 职业称号（成长路线的第一阶段）
func job_title() -> String:
	var lv := carry_level()
	if reputation >= 12 and lv >= 4:
		return "熟练工"
	if lv >= 3:
		return "搬砖工 · 老手"
	return "临时工"


# ---------------------------------------------------------------- 装备 / 工具
func equip(item: String) -> void:
	equipment[item] = true
	equipment_changed.emit()
	stats_changed.emit()


func has_equipment(item: String) -> bool:
	return bool(equipment.get(item, false))


func current_tool() -> Dictionary:
	return TOOLS[clampi(tool_index, 0, TOOLS.size() - 1)]


## 切换工具，返回提示文本（空字符串表示切换成功且无需提示）
func select_tool(index: int) -> String:
	if index < 0 or index >= TOOLS.size():
		return ""
	var t: Dictionary = TOOLS[index]
	var req := String(t.get("requires", ""))
	if req == "locked":
		return String(t.get("hint", "还没有这个工具"))
	if req != "" and not has_equipment(req):
		return "还没有%s，小卖部有卖" % t["name"]
	tool_index = index
	equipment_changed.emit()
	return ""


## 搬运时的体力消耗倍率（戴手套 -25%）
func carry_drain_factor() -> float:
	if current_tool().get("id", "") == "gloves":
		return 0.75
	return 1.0


func to_dict() -> Dictionary:
	return {
		"stamina": stamina,
		"hunger": hunger,
		"thirst": thirst,
		"reputation": reputation,
		"skills": skills.duplicate(),
		"equipment": equipment.duplicate(),
		"tool_index": tool_index,
		"exhausted": exhausted,
	}


func from_dict(d: Dictionary) -> void:
	stamina = float(d.get("stamina", MAX_STAMINA))
	hunger = float(d.get("hunger", 80.0))
	thirst = float(d.get("thirst", 80.0))
	reputation = int(d.get("reputation", 0))
	skills = {"carry": 0}
	var s: Dictionary = d.get("skills", {})
	for k in s:
		skills[k] = int(s[k])
	equipment = {"hardhat": false, "gloves": false}
	var e: Dictionary = d.get("equipment", {})
	for k in e:
		equipment[k] = bool(e[k])
	tool_index = int(d.get("tool_index", 0))
	exhausted = bool(d.get("exhausted", false))
	stats_changed.emit()
	equipment_changed.emit()
