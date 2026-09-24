extends Node
## 通用任务系统（自动加载名：QuestManager）。任务内容全部来自 data/quests.json。
##
## 目标分两类：
##   事件型（visit / talk / buy / work_shift / ...）：由 Events.notify(kind, data) 推进；
##   条件型（skill / rent / networth / ...）：状态变化后重新判定（节流，最多每 0.4 秒一次）。
## 任务默认按顺序完成目标；parallel 为 true 的任务可以任意顺序完成。

signal quests_changed
signal quest_completed(id: String)

const CONDITION_TYPES := ["skill", "relation", "rent", "job_level", "reputation", "bank", "networth", "have_item",
	"employees", "invest_or_business", "ending_ready", "invest_profit", "cash", "get_job", "promote"]
const PARALLEL_BY_DEFAULT := ["m1_first_day", "m2_first_pay", "m3_skills", "m5_climb", "s_charity_run"]

## id -> {status: "active"/"done", progress: [float], day: int}
var states: Dictionary = {}
var tracked := ""
var _dirty := false
var _dirty_timer := 0.0


func _ready() -> void:
	Events.quest_event.connect(_on_event)
	Events.stats_changed.connect(_mark_dirty)
	Events.money_changed.connect(_mark_dirty)
	Events.job_changed.connect(_mark_dirty)
	Events.housing_changed.connect(_mark_dirty)


func reset() -> void:
	states.clear()
	tracked = ""


func _mark_dirty() -> void:
	_dirty = true


func _process(delta: float) -> void:
	if not _dirty:
		return
	_dirty_timer += delta
	if _dirty_timer < 0.4:
		return
	_dirty_timer = 0.0
	_dirty = false
	check_conditions()


func data(id: String) -> Dictionary:
	return DataDB.quest(id)


func status(id: String) -> String:
	return String(states.get(id, {}).get("status", ""))


func is_active(id: String) -> bool:
	return status(id) == "active"


func is_done(id: String) -> bool:
	return status(id) == "done"


func active_ids() -> Array:
	var out: Array = []
	for id in DataDB.ids("quests"):
		if is_active(id):
			out.append(id)
	return out


func done_count() -> int:
	var n := 0
	for id in states:
		if is_done(id):
			n += 1
	return n


func is_parallel(id: String) -> bool:
	return bool(data(id).get("parallel", PARALLEL_BY_DEFAULT.has(id)))


func start(id: String) -> bool:
	var q := data(id)
	if q.is_empty() or states.has(id):
		return false
	var objs: Array = q.get("objectives", [])
	var prog: Array = []
	for o in objs:
		prog.append(0.0)
	states[id] = {"status": "active", "progress": prog, "day": TimeManager.day}
	if String(q.get("type", "")) == "main":
		GameManager.set_chapter(int(q.get("chapter", GameManager.chapter)))
		tracked = id
	elif tracked == "" or not is_active(tracked):
		tracked = id
	Events.say("新任务：%s" % String(q.get("title", id)), "info")
	AudioManager.play_sfx("quest")
	quests_changed.emit()
	Events.world_spawns_changed.emit()
	check_conditions()
	return true


## 某个 NPC 可以发布的任务
func available_from(npc_id: String) -> Array:
	var out: Array = []
	for id in DataDB.ids("quests"):
		var q := data(id)
		if String(q.get("giver", "")) != npc_id or states.has(id):
			continue
		if Conditions.check(q.get("requires", {})):
			out.append(id)
	return out


func objectives(id: String) -> Array:
	return data(id).get("objectives", [])


func target_amount(o: Dictionary) -> float:
	match String(o.get("type", "")):
		"earn", "deposit", "bank", "networth", "cash", "invest_profit":
			return float(o.get("amount", 1))
	return float(o.get("count", 1))


func objective_done(id: String, i: int) -> bool:
	var st: Dictionary = states.get(id, {})
	var prog: Array = st.get("progress", [])
	if i >= prog.size():
		return false
	return float(prog[i]) >= target_amount(objectives(id)[i])


## 当前可以推进的目标下标
func open_indices(id: String) -> Array:
	var out: Array = []
	var objs := objectives(id)
	for i in objs.size():
		if objective_done(id, i):
			continue
		out.append(i)
		if not is_parallel(id):
			break
	return out


func current_objective_index(id: String) -> int:
	var o := open_indices(id)
	return int(o[0]) if not o.is_empty() else -1


func objective_text(id: String, i: int) -> String:
	var o: Dictionary = objectives(id)[i]
	var t := String(o.get("text", ""))
	var target := target_amount(o)
	var prog := float(states.get(id, {}).get("progress", [])[i]) if states.has(id) else 0.0
	match String(o.get("type", "")):
		"earn", "deposit", "bank", "networth", "cash", "invest_profit":
			t += "（%s / %s）" % [Fmt.yuan(minf(prog, target)), Fmt.yuan(target)]
		_:
			if target > 1.0:
				t += "（%d / %d）" % [int(minf(prog, target)), int(target)]
	return t


# ================================================================ 事件型目标
func _on_event(kind: String, d: Dictionary) -> void:
	var changed := false
	for id in active_ids():
		for i in open_indices(id):
			var o: Dictionary = objectives(id)[i]
			if String(o.get("type", "")) != kind:
				continue
			var inc := _match(o, d)
			if inc > 0.0:
				states[id]["progress"][i] = float(states[id]["progress"][i]) + inc
				changed = true
				if objective_done(id, i):
					Events.say("✓ %s" % String(o.get("text", "")), "good")
	if changed:
		_after_progress()


## 返回这个事件给目标加多少进度（0 表示不匹配）
func _match(o: Dictionary, d: Dictionary) -> float:
	match String(o.get("type", "")):
		"visit":
			return 1.0 if String(d.get("location", "")) == String(o.get("target", "")) else 0.0
		"talk":
			return 1.0 if String(d.get("npc", "")) == String(o.get("npc", "")) else 0.0
		"buy":
			if o.has("item") and String(d.get("item", "")) != String(o["item"]):
				return 0.0
			if o.has("category") and String(d.get("category", "")) != String(o["category"]):
				return 0.0
			return 1.0
		"work_shift":
			if o.has("job") and String(d.get("job", "")) != String(o["job"]):
				return 0.0
			if float(d.get("score", 0)) < float(o.get("min_score", 0)):
				return 0.0
			return 1.0
		"earn", "deposit":
			return float(d.get("amount", 0))
		"practice":
			return 1.0 if not o.has("skill") or String(d.get("skill", "")) == String(o["skill"]) else 0.0
		"eat_at":
			return 1.0 if String(d.get("location", "")) == String(o.get("location", "")) else 0.0
		"pickup", "deliver":
			if String(d.get("item", "")) != String(o.get("item", "")):
				return 0.0
			if o.has("npc") and String(d.get("npc", "")) != String(o["npc"]):
				return 0.0
			return 1.0
		"interact":
			return 1.0 if String(d.get("target", "")) == String(o.get("target", "")) else 0.0
	return 1.0


# ================================================================ 条件型目标
func check_conditions() -> void:
	var changed := false
	for id in active_ids():
		for i in open_indices(id):
			var o: Dictionary = objectives(id)[i]
			var t := String(o.get("type", ""))
			if not t in CONDITION_TYPES:
				continue
			var v := _condition_value(o)
			var old := float(states[id]["progress"][i])
			if absf(v - old) > 0.0001:
				states[id]["progress"][i] = v
				changed = true
				if objective_done(id, i):
					Events.say("✓ %s" % String(o.get("text", "")), "good")
	if changed:
		_after_progress()


func _condition_value(o: Dictionary) -> float:
	var target := target_amount(o)
	match String(o.get("type", "")):
		"skill":
			var s := String(o.get("skill", ""))
			var need := int(o.get("level", 1))
			var ok := false
			if s == "any_pro":
				for k in ["computer", "finance", "management"]:
					ok = ok or SkillManager.level(k) >= need
			else:
				ok = SkillManager.level(s) >= need
			return target if ok else 0.0
		"relation":
			return float(mini(NPCManager.count_at_least(int(o.get("value", 30))), int(target)))
		"rent":
			return target if HousingManager.is_monthly() and HousingManager.level() >= int(o.get("level", 2)) else 0.0
		"job_level":
			return target if JobManager.has_job() and JobManager.level() + 1 >= int(o.get("level", 1)) else 0.0
		"reputation":
			return target if PlayerManager.reputation >= float(o.get("value", 0)) else 0.0
		"bank":
			return float(EconomyManager.bank)
		"cash":
			return float(EconomyManager.cash)
		"networth":
			return float(EconomyManager.networth())
		"have_item":
			return target if PlayerManager.has_item(String(o.get("item", ""))) else 0.0
		"employees":
			return float(mini(BusinessManager.employee_count(), int(target)))
		"invest_or_business":
			return target if InvestmentManager.has_any_holding() or InvestmentManager.trades > 0 or BusinessManager.has_company() else 0.0
		"ending_ready":
			return target if not EndingSystem.achieved().is_empty() else 0.0
		"invest_profit":
			return maxf(0.0, InvestmentManager.total_pnl())
		"get_job":
			if not JobManager.has_job():
				return 0.0
			if o.has("pay_type") and String(JobManager.job().get("pay_type", "")) != String(o["pay_type"]):
				return 0.0
			return target
		"promote":
			return float(mini(JobManager.promotions, int(target)))
	return 0.0


func _after_progress() -> void:
	for id in active_ids():
		var all := true
		for i in objectives(id).size():
			if not objective_done(id, i):
				all = false
				break
		if all:
			complete(id)
	quests_changed.emit()
	Events.world_spawns_changed.emit()


func complete(id: String) -> void:
	if not is_active(id):
		return
	var q := data(id)
	states[id]["status"] = "done"
	states[id]["done_day"] = TimeManager.day
	var reward: Dictionary = q.get("reward", {})
	Effects.apply(reward, "任务：" + String(q.get("title", "")), "任务奖励")
	var desc := Effects.describe(reward)
	if String(q.get("type", "")) == "main":
		Events.banner.emit("任务完成：%s" % String(q.get("title", "")), desc)
	else:
		Events.say("任务完成：%s  %s" % [String(q.get("title", "")), desc], "good")
	AudioManager.play_sfx("quest_done")
	quest_completed.emit(id)
	if tracked == id:
		tracked = ""
	var nx := String(q.get("next", ""))
	if nx != "":
		start(nx)
	if tracked == "":
		var act := active_ids()
		if not act.is_empty():
			tracked = String(act[0])
	quests_changed.emit()


## 调试：直接完成当前追踪的任务
func debug_complete_tracked() -> void:
	var id := tracked_id()
	if id != "":
		var objs := objectives(id)
		for i in objs.size():
			states[id]["progress"][i] = target_amount(objs[i])
		_after_progress()


func tracked_id() -> String:
	if tracked != "" and is_active(tracked):
		return tracked
	for id in active_ids():
		if String(data(id).get("type", "")) == "main":
			return id
	var act := active_ids()
	return String(act[0]) if not act.is_empty() else ""


func main_quest_id() -> String:
	for id in active_ids():
		if String(data(id).get("type", "")) == "main":
			return id
	return ""


# ================================================================ 世界交互
## 需要在世界里生成的任务物品
func spawns() -> Array:
	var out: Array = []
	for id in active_ids():
		var sp: Dictionary = data(id).get("spawn", {})
		if sp.is_empty():
			continue
		var item := String(sp.get("item", ""))
		for i in open_indices(id):
			var o: Dictionary = objectives(id)[i]
			if String(o.get("type", "")) == "pickup" and String(o.get("item", "")) == item and not PlayerManager.has_item(item):
				out.append({"quest": id, "item": item, "location": String(sp.get("location", "")), "pos": sp.get("pos", [0, 0])})
	return out


## 可以交给某个 NPC 的任务物品：[{quest, index, item}]
func deliverables_for(npc_id: String) -> Array:
	var out: Array = []
	for id in active_ids():
		for i in open_indices(id):
			var o: Dictionary = objectives(id)[i]
			if String(o.get("type", "")) == "deliver" and String(o.get("npc", "")) == npc_id and PlayerManager.has_item(String(o.get("item", ""))):
				out.append({"quest": id, "index": i, "item": String(o["item"])})
	return out


func deliver(npc_id: String, item: String) -> void:
	if PlayerManager.remove_item(item, 1):
		Events.notify("deliver", {"item": item, "npc": npc_id})


## 当前追踪目标在哪里（用于引导标记）：{"kind": "location"/"npc"/"pos", "id": .., "pos": Vector3}
func objective_target(id := "") -> Dictionary:
	if id == "":
		id = tracked_id()
	if id == "":
		return {}
	var idx := current_objective_index(id)
	if idx < 0:
		return {}
	var o: Dictionary = objectives(id)[idx]
	match String(o.get("type", "")):
		"visit":
			return {"kind": "location", "id": String(o.get("target", ""))}
		"talk", "deliver":
			return {"kind": "npc", "id": String(o.get("npc", ""))}
		"pickup":
			var sp: Dictionary = data(id).get("spawn", {})
			return {"kind": "spawn", "id": String(sp.get("location", "")), "pos": sp.get("pos", [0, 0])}
		"interact":
			return {"kind": "location", "id": "park"}
		"work_shift":
			var jid := String(o.get("job", JobManager.job_id()))
			if jid == "":
				return {"kind": "location", "id": "talent_market"}
			return {"kind": "location", "id": String(DataDB.job(jid).get("workplace", ""))}
		"apply_job", "get_job":
			return {"kind": "location", "id": "talent_market"}
		"interview_pass":
			if not JobManager.invites.is_empty():
				return {"kind": "location", "id": String(DataDB.job(String(JobManager.invites[0]["job"])).get("venue", "talent_market"))}
			return {"kind": "location", "id": "talent_market"}
		"buy":
			return {"kind": "location", "id": "store"}
		"sleep":
			var home := HousingManager.home_location()
			return {"kind": "location", "id": home if home != "" else "hotel"}
		"course", "talk_teacher":
			return {"kind": "location", "id": "training_school"}
		"rent":
			return {"kind": "location", "id": "shared_house"}
		"eat_at":
			return {"kind": "location", "id": String(o.get("location", "restaurant"))}
		"workout":
			return {"kind": "location", "id": "gym"}
		"treatment":
			return {"kind": "location", "id": "hospital"}
		"deposit", "bank":
			return {"kind": "location", "id": "bank"}
		"have_item":
			var it := String(o.get("item", ""))
			return {"kind": "location", "id": "cafe" if it == "coffee" else ("supermarket" if it == "wrench" else "store")}
		"skill":
			return {"kind": "location", "id": "training_school"}
	return {}


func to_dict() -> Dictionary:
	return {"states": states, "tracked": tracked}


func from_dict(d: Dictionary) -> void:
	states = Dictionary(d.get("states", {})).duplicate(true)
	tracked = String(d.get("tracked", ""))
	quests_changed.emit()
	Events.world_spawns_changed.emit()
