class_name TaskDefinition
extends Resource
## 通用任务定义。任务由若干「目标 objectives」组成，每个目标监听一种事件：
##
##   {"type": "deliver", "item": "brick", "zone": "brick_zone", "count": 20}
##
## TaskSystem.notify(事件类型, 数据) 会把事件分发给当前任务里匹配的目标。
## 以后加入「砌墙 lay_brick」「抹灰 plaster」「推独轮车 wheelbarrow」等玩法时，
## 只需要让对应的场景物体调用 TaskSystem.notify("lay_brick", {...})，
## 再在 task_catalog.gd 里写一条新任务，不需要改动任务系统本身。

@export var id := ""
@export var title := ""
@export var summary := ""
@export var giver := "wang"
@export var reward := 0
@export var reputation := 1
@export var min_day := 1
@export var min_reputation := 0
@export var requires: PackedStringArray = PackedStringArray()
@export var daily_limit := 1
@export var work_hours_only := true
@export var grants_meal_ticket := false
@export var objectives: Array = []
@export var accept_line := ""
@export var complete_line := ""


static func from_dict(d: Dictionary) -> TaskDefinition:
	var t := TaskDefinition.new()
	t.id = String(d.get("id", ""))
	t.title = String(d.get("title", t.id))
	t.summary = String(d.get("summary", ""))
	t.giver = String(d.get("giver", "wang"))
	t.reward = int(d.get("reward", 0))
	t.reputation = int(d.get("reputation", 1))
	t.min_day = int(d.get("min_day", 1))
	t.min_reputation = int(d.get("min_reputation", 0))
	t.requires = PackedStringArray(d.get("requires", []))
	t.daily_limit = int(d.get("daily_limit", 1))
	t.work_hours_only = bool(d.get("work_hours_only", true))
	t.grants_meal_ticket = bool(d.get("grants_meal_ticket", false))
	t.objectives = (d.get("objectives", []) as Array).duplicate(true)
	t.accept_line = String(d.get("accept_line", ""))
	t.complete_line = String(d.get("complete_line", ""))
	return t


func total_target() -> int:
	var n := 0
	for o in objectives:
		n += int(o.get("count", 1))
	return n


## 第一个「搬运」目标，用于 HUD 与引导标记。
func primary_objective() -> Dictionary:
	if objectives.is_empty():
		return {}
	return objectives[0]
