extends Node
## 约会与恋爱（自动加载名：RomanceManager）。数据见 data/romance.json。
## 关系够了（min_rel）就能约 TA 出去：选地点（咖啡馆、吃饭、电影、公园、夜景、高级餐厅、来家里），两人一起到那里，
## 聊三轮（回答影响好感），结束时按「地点基础分 × TA 的喜好 + 聊天得分」加好感，时间与花费照常结算。
## 好感 65 以上可以表白成为恋人（一次只能有一位）；恋爱 7 天以上、好感 90、有自己的住处（普通公寓及以上）可以求婚。
## 恋人 / 配偶每天加心情、减压力；太久不约会好感下降，恋人好感跌破 35 会分手。

const RING_PRICE := 52000
const CONFESS_AT := 65
const PROPOSE_AT := 90
const BREAKUP_AT := 35
## 恋人多少天不约会开始掉好感（配偶宽松一些）
const NEGLECT_DAYS := 7
const NEGLECT_DAYS_MARRIED := 14

## 好感 0～100
var affection: Dictionary = {}
## none / dating / married
var status: Dictionary = {}
## 当前的恋人或配偶
var partner := ""
var partner_since := 0
var last_date: Dictionary = {}
var confess_cooldown: Dictionary = {}
var dates_total := 0
## 进行中的约会：{npc, venue, topics: [索引], round, score}
var current: Dictionary = {}


func _ready() -> void:
	TimeManager.day_changed.connect(_on_day_changed)


func reset() -> void:
	affection.clear()
	status.clear()
	partner = ""
	partner_since = 0
	last_date.clear()
	confess_cooldown.clear()
	dates_total = 0
	current = {}


func is_candidate(id: String) -> bool:
	return DataDB.romance.has(id) and id != "_meta"


func candidates() -> Array:
	return DataDB.ids("romance")


func data(id: String) -> Dictionary:
	return DataDB.romance.get(id, {})


func venues() -> Array:
	return DataDB.romance.get("_meta", {}).get("venues", [])


func venue(vid: String) -> Dictionary:
	for v in venues():
		if String(v["id"]) == vid:
			return v
	return {}


func affection_of(id: String) -> int:
	return int(affection.get(id, 0))


func status_of(id: String) -> String:
	return String(status.get(id, "none"))


func stage_text(id: String) -> String:
	match status_of(id):
		"dating":
			return "恋人"
		"married":
			return "配偶"
	var a := affection_of(id)
	if a >= CONFESS_AT:
		return "心动"
	if a >= 30:
		return "有好感"
	if a > 0:
		return "约会过"
	return "还没约过"


func change_affection(id: String, v: int) -> void:
	affection[id] = clampi(affection_of(id) + v, 0, 100)
	Events.stats_changed.emit()


## TA 现在在上班吗
func busy_now(id: String) -> bool:
	var h := TimeManager.hour_f()
	for b in data(id).get("busy", []):
		if b.has("flag") and not GameManager.has_flag(String(b["flag"])):
			continue
		if not NPCManager._days_ok(String(b.get("days", "all")), TimeManager.day):
			continue
		if h >= float(b["from"]) and h < float(b["to"]):
			return true
	return false


## 约会不行的原因（"" 表示可以约）
func date_block(id: String) -> String:
	if not is_candidate(id):
		return "只是普通朋友"
	var name := DataDB.npc_name(id)
	if not current.is_empty():
		return "正在约会中"
	if NPCManager.relation(id) < int(data(id).get("min_rel", 30)):
		return "和%s还不够熟（关系 %d / %d）" % [name, NPCManager.relation(id), int(data(id).get("min_rel", 30))]
	if partner != "" and partner != id:
		return "你已经有恋人了"
	if int(last_date.get(id, -99)) == TimeManager.day:
		return "今天已经和%s约过会了" % name
	if busy_now(id):
		return "%s正在上班，下班后再约" % name
	return ""


func _hour_in(hours: Array) -> bool:
	var h := TimeManager.hour_f()
	var a := float(hours[0])
	var b := float(hours[1])
	if b > 24.0:
		return h >= a or h < b - 24.0
	return h >= a and h < b


## 某个地点现在去不了的原因（"" 表示可以）
func venue_block(v: Dictionary) -> String:
	if not _hour_in(v.get("hours", [0, 24])):
		var hh: Array = v["hours"]
		return "%02d:00-%02d:00 才能去" % [int(hh[0]), int(hh[1]) % 24]
	if String(v["loc"]) == "home" and HousingManager.level() < 3:
		return "需要住在普通公寓及以上"
	if not EconomyManager.can_afford(int(v.get("cost", 0))):
		return "钱不够（%s）" % Fmt.yuan(int(v.get("cost", 0)))
	return ""


## 开始约会：付钱、两人到见面地点，抽三道聊天题
func start_date(id: String, vid: String) -> Dictionary:
	var why := date_block(id)
	var v := venue(vid)
	if why == "" and v.is_empty():
		why = "没有这个地点"
	if why == "":
		why = venue_block(v)
	if why != "":
		return {"ok": false, "text": why}
	var cost := int(v.get("cost", 0))
	if cost > 0 and not EconomyManager.spend(cost, "娱乐", "约会：%s" % String(v["name"])):
		return {"ok": false, "text": "付款失败"}
	var topics: Array = data(id).get("topics", [])
	var idx: Array = range(topics.size())
	idx.shuffle()
	current = {"npc": id, "venue": vid, "topics": idx.slice(0, mini(3, idx.size())), "round": 0, "score": 0}
	_meet(id, v)
	return {"ok": true, "text": "你和%s来到了%s。" % [DataDB.npc_name(id), String(v["name"])]}


## 两人到约会地点：玩家站在 TA 面前
func _meet(id: String, v: Dictionary) -> void:
	var p := GameManager.player as Player
	var npc := GameManager.lookup("npc:" + id) as NPC
	var spot := Vector3.ZERO
	var face := Vector3.FORWARD
	if String(v["loc"]) == "home":
		var loc := HousingManager.home_location()
		var door := GameManager.lookup("door:" + loc) as Node3D
		var ld: Dictionary = DataDB.locations.get(loc, {})
		if door != null:
			var d := float((ld.get("size", [18, 16]) as Array)[1])
			spot = door.global_transform * Vector3(-3.2, 0.1, -d * 0.5 + 5.2)
			face = door.global_transform.basis * Vector3(0, 0, 1)
	else:
		var parts := String(v["loc"]).split(".")
		var ln := GameManager.lookup("loc:" + parts[0]) as LocationNode
		if ln != null:
			spot = ln.spot_position(parts[1] if parts.size() > 1 else "front")
			face = (ln.front_position() - spot)
			face.y = 0.0
			face = face.normalized() if face.length() > 0.1 else Vector3.FORWARD
	if p != null and spot != Vector3.ZERO:
		# 玩家站在 TA 斜前方，镜头从侧面拍两个人
		var side := face.cross(Vector3.UP).normalized()
		var pp := spot + face * 1.2 + side * 0.5
		var to := spot - pp
		p.teleport(pp + Vector3(0, 0.1, 0), atan2(-to.x, -to.z))
		p.camera_rig.yaw = p.rotation.y + 0.9
		p.camera_rig.pitch = -0.12
		p.camera_rig.snap()
	if npc != null and spot != Vector3.ZERO:
		npc._set_home(false)
		npc.global_position = spot
		npc.begin_talk()


func current_topic() -> Dictionary:
	if current.is_empty() or int(current["round"]) >= (current["topics"] as Array).size():
		return {}
	var topics: Array = data(String(current["npc"])).get("topics", [])
	return topics[int(current["topics"][int(current["round"])])]


## 回答一轮聊天，返回 [回答, 好感变化]
func answer(option_index: int) -> Array:
	var t := current_topic()
	if t.is_empty():
		return ["", 0]
	var o: Dictionary = t["options"][clampi(option_index, 0, (t["options"] as Array).size() - 1)]
	var a := int(o.get("a", 0))
	current["score"] = int(current["score"]) + a
	current["round"] = int(current["round"]) + 1
	return [String(o.get("reply", "")), a]


## 结束约会：结算好感、关系、心情、时间；返回说明文字
func finish_date() -> String:
	if current.is_empty():
		return ""
	var id := String(current["npc"])
	var v := venue(String(current["venue"]))
	var like := float(data(id).get("likes", {}).get(String(v["id"]), 1.0))
	var base := float(v.get("base", 5)) * like
	if bool(v.get("outdoor", false)) and WeatherManager.is_raining():
		base *= 0.5
	# 在家约会：装修加成（家具心情加成越高气氛越好）
	if String(v["loc"]) == "home":
		base += HousingManager.decor_sum(HousingManager.home_id(), "mood")
	var gain := maxi(int(round(base)) + int(current["score"]), 0 if int(current["score"]) >= 0 else -5)
	change_affection(id, gain)
	NPCManager.change_relation(id, 3)
	PlayerManager.change("mood", 8)
	PlayerManager.change("stress", -10)
	last_date[id] = TimeManager.day
	dates_total += 1
	var minutes := int(v.get("minutes", 90))
	current = {}
	TimeManager.advance(minutes, "idle")
	var npc := GameManager.lookup("npc:" + id) as NPC
	if npc != null:
		npc.end_talk()
		npc.go_to_spot(NPCManager.spot_for(id), true)
	Events.notify("date", {"npc": id})
	var mood := "很开心" if gain >= 12 else ("还不错" if gain >= 5 else "有点冷场")
	var liked := "（TA 很喜欢这里）" if like >= 1.3 else ("（TA 对这里兴趣一般）" if like < 1.0 else "")
	return "和%s的约会%s%s：好感 %+d（现在 %d），心情 +8，压力 -10，用了 %d 分钟。" % [DataDB.npc_name(id), mood, liked, gain, affection_of(id), minutes]


func can_confess(id: String) -> String:
	if not is_candidate(id):
		return "只是普通朋友"
	if status_of(id) != "none":
		return "你们已经在一起了"
	if partner != "":
		return "你已经有恋人了"
	if TimeManager.day < int(confess_cooldown.get(id, 0)):
		return "上次被拒还没过去几天，再等等"
	if affection_of(id) < 50:
		return "好感还不够（%d / 50 以上才敢开口）" % affection_of(id)
	return ""


## 表白：好感 65 以上答应
func confess(id: String) -> Array:
	var why := can_confess(id)
	if why != "":
		return [false, why]
	var d := data(id)
	if affection_of(id) >= CONFESS_AT:
		status[id] = "dating"
		partner = id
		partner_since = TimeManager.day
		PlayerManager.change("mood", 20)
		NPCManager.change_relation(id, 10)
		AudioManager.play_sfx("levelup", -4.0)
		Events.notify("romance", {"npc": id, "stage": "dating"})
		return [true, String(d.get("confess_yes", ""))]
	change_affection(id, -8)
	confess_cooldown[id] = TimeManager.day + 3
	PlayerManager.change("mood", -10)
	return [false, String(d.get("confess_no", ""))]


func can_propose(id: String) -> String:
	if status_of(id) != "dating":
		return "还不是恋人"
	if TimeManager.day - partner_since < 7:
		return "在一起还不到 7 天"
	if affection_of(id) < PROPOSE_AT:
		return "好感还不够（%d / %d）" % [affection_of(id), PROPOSE_AT]
	if HousingManager.level() < 3:
		return "先有个像样的家（普通公寓及以上）"
	if not EconomyManager.can_afford(RING_PRICE):
		return "钻戒要 %s" % Fmt.yuan(RING_PRICE)
	return ""


func propose(id: String) -> Array:
	var why := can_propose(id)
	if why != "":
		return [false, why]
	EconomyManager.spend(RING_PRICE, "娱乐", "求婚钻戒")
	status[id] = "married"
	PlayerManager.change("mood", 30)
	GameManager.set_flag("married")
	AudioManager.play_sfx("levelup", -2.0)
	Events.notify("romance", {"npc": id, "stage": "married"})
	Events.phone_message.emit(DataDB.npc_name(id), "以后每天回家，都有人等你了。")
	return [true, String(data(id).get("propose_yes", ""))]


func _on_day_changed(_d: int) -> void:
	if partner == "":
		return
	var id := partner
	var st := status_of(id)
	var married := st == "married"
	PlayerManager.change("mood", 5.0 if married else 3.0)
	PlayerManager.change("stress", -3.0 if married else -2.0)
	var gap := TimeManager.day - int(last_date.get(id, partner_since))
	if gap > (NEGLECT_DAYS_MARRIED if married else NEGLECT_DAYS):
		change_affection(id, -3)
		if gap == (NEGLECT_DAYS_MARRIED if married else NEGLECT_DAYS) + 1:
			Events.phone_message.emit(DataDB.npc_name(id), "你最近好忙……我们好久没一起出去了。")
	if not married and affection_of(id) < BREAKUP_AT:
		status[id] = "none"
		partner = ""
		NPCManager.change_relation(id, -20)
		PlayerManager.change("mood", -20)
		Events.phone_message.emit(DataDB.npc_name(id), "我们还是分开吧。你太忙了，我一直一个人。")
		Events.say("%s和你分手了……" % DataDB.npc_name(id), "bad")
		return
	var lines: Array = data(id).get("lover", [])
	if not lines.is_empty() and randf() < 0.35:
		Events.phone_message.emit(DataDB.npc_name(id), String(lines[randi() % lines.size()]))


func to_dict() -> Dictionary:
	return {"affection": affection.duplicate(), "status": status.duplicate(), "partner": partner, "since": partner_since,
		"last_date": last_date.duplicate(), "cooldown": confess_cooldown.duplicate(), "dates": dates_total}


func from_dict(d: Dictionary) -> void:
	reset()
	for k in d.get("affection", {}):
		affection[String(k)] = int(d["affection"][k])
	for k in d.get("status", {}):
		status[String(k)] = String(d["status"][k])
	for k in d.get("last_date", {}):
		last_date[String(k)] = int(d["last_date"][k])
	for k in d.get("cooldown", {}):
		confess_cooldown[String(k)] = int(d["cooldown"][k])
	partner = String(d.get("partner", ""))
	partner_since = int(d.get("since", 0))
	dates_total = int(d.get("dates", 0))
