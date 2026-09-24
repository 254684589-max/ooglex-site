extends Node
## 人物属性与背包（自动加载名：PlayerManager）。
## 属性：体力 Energy、饱腹 Hunger、心情 Mood、健康 Health、压力 Stress（0~100），声望 Reputation（0~100）。
## 背包：可堆叠的消耗品与任务物品；耐用品（电脑、滑板……）与服装单独记录；家中储物柜容量由住房决定。

signal collapsed(reason: String)

const STATS := ["energy", "hunger", "mood", "health", "stress"]
const STAT_NAMES := {"energy": "体力", "hunger": "饱腹", "mood": "心情", "health": "健康", "stress": "压力", "reputation": "声望"}
const BACKPACK_SLOTS := 16
const STACK_MAX := 20

var energy := 100.0
var hunger := 100.0
var mood := 75.0
var health := 100.0
var stress := 10.0
var reputation := 0.0

var backpack: Dictionary = {}
var storage: Dictionary = {}
var owned: Dictionary = {}      # 耐用品 / 服装：id -> true
var outfit := ""
var gym_until_day := 0
var books_read: Dictionary = {}
var _collapse_armed := true
## 换装后通知玩家模型刷新（由 Player 设置）
var stats_changed_outfit_hook: Callable = Callable()
var _stats_dirty_time := 0.0


func _ready() -> void:
	TimeManager.time_advanced.connect(_on_time_advanced)


func reset() -> void:
	energy = 100.0
	hunger = 100.0
	mood = 75.0
	health = 100.0
	stress = 10.0
	reputation = 0.0
	backpack.clear()
	storage.clear()
	owned.clear()
	books_read.clear()
	outfit = ""
	gym_until_day = 0
	_collapse_armed = true
	Events.stats_changed.emit()


func get_stat(id: String) -> float:
	if id == "reputation":
		return reputation
	return float(get(id))


func change(id: String, amount: float) -> void:
	if not id in STATS:
		return
	var v := clampf(float(get(id)) + amount, 0.0, 100.0)
	set(id, v)
	_mark_dirty()
	_check_collapse()


func set_stat(id: String, v: float) -> void:
	if id == "reputation":
		reputation = clampf(v, 0.0, 100.0)
	elif id in STATS:
		set(id, clampf(v, 0.0, 100.0))
	Events.stats_changed.emit()


func change_reputation(amount: float) -> void:
	reputation = clampf(reputation + amount, 0.0, 100.0)
	Events.stats_changed.emit()


## 工作 / 学习效率系数（压力高、体力低、生病都会降低）
func efficiency() -> float:
	var e := 1.0
	if stress > 60.0:
		e -= (stress - 60.0) / 100.0
	if energy < 30.0:
		e -= 0.15
	if health < 40.0:
		e -= 0.1
	if mood > 70.0:
		e += 0.05
	if hunger < 20.0:
		e -= 0.1
	return clampf(e, 0.5, 1.1)


func efficiency_notes() -> Array:
	var out: Array = []
	if stress > 60.0:
		out.append("压力过高")
	if energy < 30.0:
		out.append("体力不足")
	if health < 40.0:
		out.append("身体不适")
	if hunger < 20.0:
		out.append("饿着肚子")
	if mood > 70.0:
		out.append("心情不错")
	return out


## 移动速度系数（体力影响速度）
func speed_factor() -> float:
	var f := 1.0
	if energy < 25.0:
		f = lerpf(0.72, 1.0, energy / 25.0)
	if hunger <= 0.0:
		f *= 0.85
	if owned.has("skateboard"):
		f *= 1.25
	return f


func can_sprint() -> bool:
	return energy > 5.0


func _mark_dirty() -> void:
	_stats_dirty_time = 0.0
	Events.stats_changed.emit()


func _on_time_advanced(m: float, activity: String) -> void:
	if not GameManager.playing:
		return
	match activity:
		"sleep":
			hunger -= 0.04 * m
			stress -= 0.05 * m
			if hunger > 30.0:
				health += 0.012 * m
		"work":
			hunger -= 0.03 * m
		"study":
			hunger -= 0.08 * m
			energy -= 0.03 * m
		_:
			hunger -= 0.1 * m
			energy -= 0.022 * m
			stress -= 0.008 * m
	if hunger < 10.0:
		health -= 0.04 * m
	if stress > 85.0:
		health -= 0.012 * m
	if hunger < 25.0 or stress > 70.0:
		mood -= 0.012 * m
	else:
		mood = move_toward(mood, 60.0, 0.004 * m)
	for s in STATS:
		set(s, clampf(float(get(s)), 0.0, 100.0))
	Events.stats_changed.emit()
	if activity != "sleep":
		_check_collapse()


func _check_collapse() -> void:
	if not GameManager.playing:
		return
	if health <= 0.0 and _collapse_armed:
		_collapse_armed = false
		collapsed.emit("health")
	elif energy <= 0.0 and _collapse_armed:
		_collapse_armed = false
		collapsed.emit("energy")


func rearm_collapse() -> void:
	_collapse_armed = true


# ================================================================ 背包
func item_count(id: String) -> int:
	return int(backpack.get(id, 0))


func has_item(id: String) -> bool:
	return item_count(id) > 0 or owned.has(id)


func used_slots() -> int:
	var n := 0
	for id in backpack:
		n += int(ceil(float(backpack[id]) / STACK_MAX))
	return n


func can_add(id: String, n := 1) -> bool:
	var cur := item_count(id)
	var slots_now := int(ceil(float(cur) / STACK_MAX))
	var slots_after := int(ceil(float(cur + n) / STACK_MAX))
	return used_slots() - slots_now + slots_after <= BACKPACK_SLOTS


## 加入物品。耐用品和服装记入 owned；返回是否成功
func add_item(id: String, n := 1) -> bool:
	var it := DataDB.item(id)
	if it.is_empty():
		return false
	var use := String(it.get("use", "consume"))
	if use in ["durable", "outfit"]:
		owned[id] = true
		if use == "outfit" and outfit == "":
			set_outfit(id)
		Events.stats_changed.emit()
		return true
	if use == "membership":
		gym_until_day = maxi(gym_until_day, TimeManager.day) + int(it.get("days", 30))
		Events.stats_changed.emit()
		return true
	if not can_add(id, n):
		Events.say("背包满了（%d 格）" % BACKPACK_SLOTS, "warn")
		return false
	backpack[id] = item_count(id) + n
	Events.stats_changed.emit()
	return true


func remove_item(id: String, n := 1) -> bool:
	if item_count(id) < n:
		return false
	backpack[id] = item_count(id) - n
	if int(backpack[id]) <= 0:
		backpack.erase(id)
	Events.stats_changed.emit()
	return true


func gym_member() -> bool:
	return gym_until_day >= TimeManager.day


## 使用背包里的物品。返回提示文字（空字符串表示没用掉）
func use_item(id: String) -> String:
	var it := DataDB.item(id)
	if it.is_empty() or item_count(id) <= 0:
		return ""
	match String(it.get("use", "")):
		"consume":
			remove_item(id, 1)
			apply_consumable(it)
			AudioManager.play_sfx("eat")
			return "使用了%s" % String(it["name"])
		"read":
			return read_book(id)
		"gift":
			return "礼物要在和 NPC 对话时送出"
		"tool", "quest":
			return "这件东西现在用不上"
	return ""


func apply_consumable(it: Dictionary) -> void:
	var fx: Dictionary = it.get("effects", {})
	for k in fx:
		change(String(k), float(fx[k]))
	var cat := String(it.get("category", ""))
	if cat in ["food", "drink"]:
		Events.notify("eat", {"item": String(it.get("id", "")), "location": GameManager.get_value("current_location", "")})


func read_book(id: String) -> String:
	var it := DataDB.item(id)
	var sx: Dictionary = it.get("skill_xp", {})
	for s in sx:
		var lvl := SkillManager.level(String(s))
		if it.has("min_level") and lvl < int(it["min_level"]):
			return "看不懂……需要%s Lv.%d" % [DataDB.skill_name(String(s)), int(it["min_level"])]
		if it.has("max_level") and lvl >= int(it["max_level"]):
			return "这本书对你来说太基础了（适合 Lv.%d 以下）" % int(it["max_level"])
	if energy < 10.0:
		return "太困了，读不进去"
	remove_item(id, 1)
	var bonus := 1.0 + NPCManager.perk_value("study_buddy")
	var eff := efficiency()
	TimeManager.advance(float(it.get("time", 120)), "study")
	for s in sx:
		SkillManager.add_xp(String(s), float(sx[s]) * bonus * eff, "读书")
	books_read[id] = int(books_read.get(id, 0)) + 1
	change("stress", -3)
	Events.notify("read", {"item": id})
	return "读完了%s（%s）" % [String(it["name"]), Fmt.hours_text(float(it.get("time", 120)))]


func set_outfit(id: String) -> void:
	if id == "" or owned.has(id):
		outfit = id
		if stats_changed_outfit_hook.is_valid():
			stats_changed_outfit_hook.call()
		Events.stats_changed.emit()


func outfit_interview_bonus() -> float:
	if outfit == "":
		return 0.0
	return float(DataDB.item(outfit).get("interview", 0))


# ---------------------------------------------------------------- 储物柜
func storage_used() -> int:
	var n := 0
	for id in storage:
		n += int(storage[id])
	return n


func store_item(id: String, n := 1) -> bool:
	if item_count(id) < n:
		return false
	if storage_used() + n > HousingManager.storage_capacity():
		Events.say("储物柜放不下了（容量 %d）" % HousingManager.storage_capacity(), "warn")
		return false
	remove_item(id, n)
	storage[id] = int(storage.get(id, 0)) + n
	Events.stats_changed.emit()
	return true


func take_item(id: String, n := 1) -> bool:
	if int(storage.get(id, 0)) < n:
		return false
	if not can_add(id, n):
		Events.say("背包满了", "warn")
		return false
	storage[id] = int(storage[id]) - n
	if int(storage[id]) <= 0:
		storage.erase(id)
	backpack[id] = item_count(id) + n
	Events.stats_changed.emit()
	return true


func to_dict() -> Dictionary:
	return {
		"energy": energy, "hunger": hunger, "mood": mood, "health": health, "stress": stress, "reputation": reputation,
		"backpack": backpack, "storage": storage, "owned": owned.keys(), "outfit": outfit, "gym_until": gym_until_day,
		"books_read": books_read,
	}


func from_dict(d: Dictionary) -> void:
	reset()
	for s in STATS:
		set(s, clampf(float(d.get(s, get(s))), 0.0, 100.0))
	reputation = float(d.get("reputation", 0.0))
	for k in d.get("backpack", {}):
		backpack[String(k)] = int(d["backpack"][k])
	for k in d.get("storage", {}):
		storage[String(k)] = int(d["storage"][k])
	for k in d.get("owned", []):
		owned[String(k)] = true
	outfit = String(d.get("outfit", ""))
	gym_until_day = int(d.get("gym_until", 0))
	books_read = Dictionary(d.get("books_read", {})).duplicate()
	_collapse_armed = true
	Events.stats_changed.emit()
