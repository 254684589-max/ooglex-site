extends Node
## NPC 管理（自动加载名：NPCManager）。
## 保存关系值（-100~100）、每天的闲聊 / 送礼次数、关系带来的帮助（perks），
## 并在整点时根据日程给每个 NPC 分配目的地——不在每帧扫描 NPC。

signal schedule_updated

const TIERS := [[-101, "cold"], [0, "stranger"], [20, "acquaint"], [50, "friend"], [80, "close"]]
const TIER_NAMES := {"cold": "冷淡", "stranger": "陌生", "acquaint": "熟人", "friend": "朋友", "close": "挚友"}

var relations: Dictionary = {}
var chatted_day: Dictionary = {}
var gifted_day: Dictionary = {}
var met: Dictionary = {}
## 场景中的 NPC 节点：id -> NPC
var nodes: Dictionary = {}


func _ready() -> void:
	TimeManager.hour_changed.connect(func(_h): refresh_schedules())
	TimeManager.day_changed.connect(func(_d): refresh_schedules())


func reset() -> void:
	relations.clear()
	chatted_day.clear()
	gifted_day.clear()
	met.clear()
	for id in DataDB.ids("npcs"):
		relations[id] = 0


func relation(id: String) -> int:
	return int(relations.get(id, 0))


func change_relation(id: String, amount: int) -> void:
	if not DataDB.npcs.has(id):
		return
	var before := tier(id)
	relations[id] = clampi(relation(id) + amount, -100, 100)
	met[id] = true
	Events.relationship_changed.emit(id, relation(id))
	Events.stats_changed.emit()
	var after := tier(id)
	if after != before and amount > 0:
		Events.say("与%s的关系变为「%s」" % [DataDB.npc_name(id), TIER_NAMES[after]], "good")
		for p in DataDB.npc(id).get("perks", []):
			if relation(id) >= int(p.get("min_rel", 0)) and relation(id) - amount < int(p.get("min_rel", 0)):
				Events.phone_message.emit(DataDB.npc_name(id), String(p.get("text", "")))


func tier(id: String) -> String:
	var r := relation(id)
	var t := "cold"
	for pair in TIERS:
		if r >= int(pair[0]):
			t = String(pair[1])
	return t


func tier_name(id: String) -> String:
	return TIER_NAMES[tier(id)]


func count_at_least(v: int) -> int:
	var n := 0
	for id in relations:
		if int(relations[id]) >= v:
			n += 1
	return n


func can_chat(id: String) -> bool:
	return int(chatted_day.get(id, -1)) != TimeManager.day


func mark_chatted(id: String) -> void:
	chatted_day[id] = TimeManager.day


func can_gift(id: String) -> bool:
	return int(gifted_day.get(id, -1)) != TimeManager.day


func give_gift(id: String, item_id: String) -> String:
	if not can_gift(id):
		return "今天已经送过礼了"
	if not PlayerManager.remove_item(item_id, 1):
		return "你没有这件礼物"
	gifted_day[id] = TimeManager.day
	var it := DataDB.item(item_id)
	var v := int(it.get("gift", 5))
	var likes: Array = DataDB.npc(id).get("gifts", [])
	if likes.has(item_id):
		v = int(v * 1.5)
	change_relation(id, v)
	return "%s很喜欢这份%s（关系 +%d）" % [DataDB.npc_name(id), String(it.get("name", "")), v] if likes.has(item_id) else "%s收下了%s（关系 +%d）" % [DataDB.npc_name(id), String(it.get("name", "")), v]


func greeting(id: String) -> String:
	var g: Dictionary = DataDB.npc(id).get("greet", {})
	var lines: Array = g.get(tier(id), g.get("stranger", ["你好。"]))
	return String(lines[randi() % lines.size()])


## 今天的闲聊话题（每人每天一个，按日期轮换）
func topic_for(id: String) -> Dictionary:
	var topics: Array = DataDB.npc(id).get("topics", [])
	if topics.is_empty():
		return {}
	return topics[(TimeManager.day + id.length()) % topics.size()]


# ================================================================ 帮助（perks）
func active_perks() -> Array:
	var out: Array = []
	for id in DataDB.ids("npcs"):
		for p in DataDB.npc(id).get("perks", []):
			if relation(id) >= int(p.get("min_rel", 999)):
				var e: Dictionary = p.duplicate()
				e["npc"] = id
				out.append(e)
	return out


func has_perk(type: String) -> bool:
	for p in active_perks():
		if String(p.get("type", "")) == type:
			return true
	return false


func perk_value(type: String) -> float:
	var v := 0.0
	for p in active_perks():
		if String(p.get("type", "")) == type:
			v = maxf(v, float(p.get("value", 1.0)))
	return v


func interview_bonus(job_id: String) -> float:
	var v := 0.0
	for p in active_perks():
		if String(p.get("type", "")) == "interview_bonus":
			var j := String(p.get("job", "any"))
			if j == "any" or j == job_id:
				v += float(p.get("value", 0))
	return v


## 某个 NPC 能直接录用的职位（没有则返回空字符串）
func direct_hire_job(id: String) -> String:
	for p in DataDB.npc(id).get("perks", []):
		if String(p.get("type", "")) == "direct_hire" and relation(id) >= int(p.get("min_rel", 999)):
			return String(p.get("job", ""))
	return ""


# ================================================================ 日程
func _days_ok(days: String, d: int) -> bool:
	var wd := (d - 1) % 7
	match days:
		"weekdays":
			return wd <= 4
		"weekend":
			return wd >= 5
		"six":
			return wd <= 5
	return true


## 某个 NPC 此刻应该在的地点（"loc.spot"），不在日程里返回 ""（回家）
func spot_for(id: String) -> String:
	var h := TimeManager.hour_f()
	for s in DataDB.npc(id).get("schedule", []):
		if s.has("flag") and not GameManager.has_flag(String(s["flag"])):
			continue
		if s.has("not_flag") and GameManager.has_flag(String(s["not_flag"])):
			continue
		if not _days_ok(String(s.get("days", "all")), TimeManager.day):
			continue
		if h >= float(s.get("from", 0)) and h < float(s.get("to", 24)):
			return String(s.get("spot", ""))
	return ""


func where_text(id: String) -> String:
	var spot := spot_for(id)
	if spot == "":
		return "不在外面（回家了）"
	return DataDB.location_name(spot.split(".")[0])


func register_node(id: String, n: Node) -> void:
	nodes[id] = n


## instant 为真时（新游戏、读档）所有 NPC 直接出现在该在的位置
func refresh_schedules(instant := false) -> void:
	for id in nodes:
		var n = nodes[id]
		if is_instance_valid(n) and n.has_method("go_to_spot"):
			n.go_to_spot(spot_for(id), instant)
	schedule_updated.emit()


func to_dict() -> Dictionary:
	return {"relations": relations, "chatted": chatted_day, "gifted": gifted_day, "met": met.keys()}


func from_dict(d: Dictionary) -> void:
	reset()
	for k in d.get("relations", {}):
		relations[String(k)] = int(d["relations"][k])
	for k in d.get("chatted", {}):
		chatted_day[String(k)] = int(d["chatted"][k])
	for k in d.get("gifted", {}):
		gifted_day[String(k)] = int(d["gifted"][k])
	for k in d.get("met", []):
		met[String(k)] = true
