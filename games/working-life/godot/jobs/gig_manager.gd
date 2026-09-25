extends Node
## 零工（自动加载名：GigManager）：下班以后也能接的活，手机「零工」APP 里接单。
##   外卖骑手：到餐馆取餐 → 送到住处 / 写字楼，限时送达，按时越早评分越高。
##   网约车司机：要有自己的车；开车到上车点接乘客 → 送到目的地，开得稳、到得快评分高。
##   主播：在家开播 2 小时，涨粉、收打赏；粉丝 500 以上可以直播带货。
## 同一时间只能接一单。完成订单按距离与等级付钱（计入「兼职」收入），并通知任务系统（Events.notify("gig", …)）。
## 地图箭头与屏幕上方的状态行会指向取餐点 / 上车点 / 目的地。

## 外卖取餐点（餐馆、便利店……）与送达点（住处、写字楼……）
const FOOD := ["restaurant", "cafe", "store", "supermarket", "old_street", "mall"]
const DROP := ["shared_house", "apartment", "luxury_apartment", "office_tower", "tech_company", "finance_center", "hotel",
	"hospital", "training_school", "talent_market", "gym", "bank", "warehouse", "construction_site", "villa"]
const ARRIVE_DIST := 7.0
## 等级：[需要完成的单数, 需要的平均评分, 收入倍数, 名称]
const LEVELS := [[0, 0.0, 1.0, "新手"], [20, 4.5, 1.2, "熟手"], [60, 4.7, 1.4, "金牌"]]
## 直播内容：[id, 名称, 涨粉倍数, 收入倍数, 需要粉丝]
const STREAMS := [["chat", "聊天", 1.0, 1.0, 0], ["game", "打游戏", 1.3, 0.8, 0], ["talent", "才艺", 1.1, 1.2, 100], ["sell", "直播带货", 0.5, 4.0, 500]]

## 每种零工的累计：{done, stars, earned}
var stats: Dictionary = {}
## 进行中的订单：{gig, stage: pickup / dropoff, from, to, dist, start, deadline, bumps}
var order: Dictionary = {}
var followers := 0
var _timer := 0.0
var _passenger: CharacterModel


func _ready() -> void:
	reset()


func reset() -> void:
	stats = {"delivery": {"done": 0, "stars": 0, "earned": 0}, "ride": {"done": 0, "stars": 0, "earned": 0}, "stream": {"done": 0, "stars": 0, "earned": 0}}
	order = {}
	followers = 0
	_clear_passenger()


func done_count(gig: String) -> int:
	return int(stats.get(gig, {}).get("done", 0))


func rating(gig: String) -> float:
	var n := done_count(gig)
	return float(stats[gig]["stars"]) / n if n > 0 else 5.0


func level(gig: String) -> int:
	var lv := 0
	for i in LEVELS.size():
		if done_count(gig) >= int(LEVELS[i][0]) and rating(gig) >= float(LEVELS[i][1]):
			lv = i
	return lv


func level_name(gig: String) -> String:
	return String(LEVELS[level(gig)][3])


func has_order() -> bool:
	return not order.is_empty()


func _front(loc: String) -> Vector3:
	var ln := GameManager.lookup("loc:" + loc) as LocationNode
	return ln.front_position() if ln != null else Vector3.ZERO


## 接单不行的原因（"" 表示可以）
func accept_block(gig: String) -> String:
	if has_order():
		return "先把手上这单做完"
	if not GameManager.playing:
		return "现在不能接单"
	if PlayerManager.energy < 12.0:
		return "体力不够了，先休息"
	if gig == "ride" and not VehicleManager.has_car():
		return "要有自己的车（手机「汽车」APP）"
	return ""


## 接一单：从玩家附近挑起点，再挑一个合适距离的终点
func accept(gig: String) -> String:
	var why := accept_block(gig)
	if why != "":
		return why
	var p := GameManager.player
	var here := p.global_position if p != null else Vector3.ZERO
	var from_pool: Array = FOOD if gig == "delivery" else DataDB.ids("locations")
	var to_pool: Array = DROP if gig == "delivery" else DataDB.ids("locations")
	var froms: Array = []
	for id in from_pool:
		var f := _front(String(id))
		if f != Vector3.ZERO:
			froms.append([f.distance_to(here), String(id)])
	froms.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	if froms.is_empty():
		return "附近没有订单"
	var from := String(froms[randi() % mini(3, froms.size())][1])
	var fp := _front(from)
	var lo := 120.0 if gig == "delivery" else 220.0
	var hi := 460.0 if gig == "delivery" else 720.0
	var tos: Array = []
	for id in to_pool:
		if String(id) == from:
			continue
		var t := _front(String(id))
		var d := t.distance_to(fp)
		if t != Vector3.ZERO and d >= lo and d <= hi:
			tos.append(String(id))
	if tos.is_empty():
		for id in to_pool:
			if String(id) != from and _front(String(id)) != Vector3.ZERO:
				tos.append(String(id))
	var to: String = tos[randi() % tos.size()]
	var dist := fp.distance_to(_front(to)) + fp.distance_to(here)
	var now := TimeManager.total_minutes
	# 限时：外卖按跑步能到的时间再宽裕一些；网约车按开车
	var allowed := 15.0 + dist * (0.28 if gig == "delivery" else 0.12)
	order = {"gig": gig, "stage": "pickup", "from": from, "to": to, "dist": fp.distance_to(_front(to)), "start": now, "deadline": now + allowed, "bumps": 0}
	if gig == "ride":
		_spawn_passenger(fp)
	Events.stats_changed.emit()
	var verb := "到%s取餐" % DataDB.location_name(from) if gig == "delivery" else "开车到%s接乘客" % DataDB.location_name(from)
	return "接单成功：%s，送到%s（%d 米，限时 %d 分钟）。地图箭头会带路。" % [verb, DataDB.location_name(to), int(order["dist"]), int(allowed)]


func cancel() -> String:
	if not has_order():
		return "没有进行中的订单"
	var gig := String(order["gig"])
	stats[gig]["done"] = int(stats[gig]["done"]) + 1
	stats[gig]["stars"] = int(stats[gig]["stars"]) + 1
	order = {}
	_clear_passenger()
	Events.stats_changed.emit()
	return "订单已取消，平台给了你一个差评（1 星）"


## 地图箭头要指的地方
func target() -> Dictionary:
	if not has_order():
		return {}
	var loc := String(order["from"] if order["stage"] == "pickup" else order["to"])
	var what := ("取餐" if order["gig"] == "delivery" else "接乘客") if order["stage"] == "pickup" else "送达"
	return {"pos": _front(loc), "name": "%s · %s" % [what, DataDB.location_name(loc)]}


## 屏幕上方的状态行
func status_text() -> String:
	if not has_order():
		return ""
	var left := float(order["deadline"]) - TimeManager.total_minutes
	var t := target()
	var clock := "剩 %d 分钟" % int(left) if left >= 0.0 else "已超时 %d 分钟" % int(-left)
	return "%s订单：%s（%s）" % ["外卖" if order["gig"] == "delivery" else "网约车", String(t["name"]), clock]


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0 or not has_order() or not GameManager.playing:
		return
	_timer = 0.25
	var p := GameManager.player as Player
	if p == null:
		return
	var gig := String(order["gig"])
	# 超时太久顾客取消
	if TimeManager.total_minutes > float(order["deadline"]) + 120.0:
		Events.say("超时太久，顾客取消了订单（1 星）", "bad")
		cancel()
		return
	var t := target()
	var here := p.global_position
	if gig == "ride":
		# 网约车必须开着车到
		if p.vehicle == null:
			return
		here = p.vehicle.global_position
	if Vector2(here.x - t["pos"].x, here.z - t["pos"].z).length() > ARRIVE_DIST + (3.0 if gig == "ride" else 0.0):
		return
	if order["stage"] == "pickup":
		order["stage"] = "dropoff"
		if gig == "delivery":
			Events.say("取到餐了，送到%s" % DataDB.location_name(String(order["to"])), "info")
			AudioManager.play_sfx("pickup")
		else:
			_clear_passenger()
			Events.say("乘客上车了：去%s" % DataDB.location_name(String(order["to"])), "info")
			AudioManager.play_sfx("door")
		return
	_complete()


func _complete() -> void:
	var gig := String(order["gig"])
	var late := TimeManager.total_minutes - float(order["deadline"])
	var used := TimeManager.total_minutes - float(order["start"])
	var allowed := float(order["deadline"]) - float(order["start"])
	var stars := 5
	if late > 0.0:
		stars = 3 if late < 15.0 else (2 if late < 45.0 else 1)
	elif used > allowed * 0.75:
		stars = 4
	if gig == "ride":
		stars = maxi(1, stars - mini(2, int(order.get("bumps", 0))))
	var mult := float(LEVELS[level(gig)][2])
	var dist := float(order["dist"])
	var pay := int(round(((10.0 + dist * 0.025) if gig == "delivery" else (10.0 + dist * 0.035)) * mult))
	var tip := 5 if stars == 5 else 0
	if WeatherManager.is_raining():
		pay += 4
	EconomyManager.earn(pay + tip, "兼职", "%s订单" % ("外卖" if gig == "delivery" else "网约车"))
	stats[gig]["done"] = int(stats[gig]["done"]) + 1
	stats[gig]["stars"] = int(stats[gig]["stars"]) + stars
	stats[gig]["earned"] = int(stats[gig]["earned"]) + pay + tip
	PlayerManager.change("energy", -4.0 if gig == "delivery" else -3.0)
	PlayerManager.change("hunger", -3.0)
	PlayerManager.change("stress", 2.0)
	var h := TimeManager.hour_f()
	Events.notify("gig", {"gig": gig, "stars": stars, "rain": WeatherManager.is_raining(), "night": h >= 23.0 or h < 5.0})
	order = {}
	_clear_passenger()
	AudioManager.play_sfx("coin")
	Events.stats_changed.emit()
	Events.say("送达！%s · 收入 %s%s" % ["★".repeat(stars) + "☆".repeat(5 - stars), Fmt.yuan(pay), ("，小费 %s" % Fmt.yuan(tip)) if tip > 0 else ""], "good" if stars >= 4 else "warn")


## 网约车：开车时撞了东西（PlayerCar 调用），乘客不舒服
func on_bump() -> void:
	if has_order() and order["gig"] == "ride" and order["stage"] == "dropoff":
		order["bumps"] = int(order.get("bumps", 0)) + 1


func _spawn_passenger(at: Vector3) -> void:
	_clear_passenger()
	var main := GameManager.main
	if main == null:
		return
	_passenger = CharacterModel.new()
	_passenger.shirt_color = Color.from_hsv(randf(), 0.5, 0.6)
	_passenger.pants_color = Color(0.15, 0.15, 0.2)
	_passenger.casts_shadow = false
	main.add_child(_passenger)
	_passenger.global_position = at + Vector3(0, 0.05, 0)
	var a := AnimationController.new(_passenger)
	a.update(0.016, 0.0)


func _clear_passenger() -> void:
	if _passenger != null and is_instance_valid(_passenger):
		_passenger.queue_free()
	_passenger = null


# ================================================================ 直播

func stream_block(content: String) -> String:
	if has_order():
		return "先把手上的订单做完"
	if HousingManager.home_id() == "":
		return "要有自己的住处才能开播"
	var p := GameManager.player
	var home := HousingManager.home_location()
	if p == null or _front(home).distance_to(p.global_position) > 30.0:
		return "回家才能开播（%s）" % DataDB.location_name(home)
	if PlayerManager.energy < 20.0:
		return "体力不够，播不动了"
	for s in STREAMS:
		if String(s[0]) == content and followers < int(s[4]):
			return "粉丝 %d 以上才能%s" % [int(s[4]), String(s[1])]
	return ""


## 开播 2 小时：涨粉看口才、心情、家里的装修；收入看粉丝数
func stream(content: String) -> String:
	var why := stream_block(content)
	if why != "":
		return why
	var spec: Array = STREAMS[0]
	for s in STREAMS:
		if String(s[0]) == content:
			spec = s
	var comm := SkillManager.level("communication")
	var decor := HousingManager.decor_sum(HousingManager.home_id(), "prestige")
	var base := 12.0 + comm * 5.0 + PlayerManager.mood * 0.1 + decor * 3.0
	var gain := int(round(base * float(spec[2]) * randf_range(0.7, 1.3) * (1.0 + minf(followers / 3000.0, 1.5))))
	followers += gain
	var income := int(round((2.0 + followers * 0.04) * float(spec[3]) * randf_range(0.8, 1.25)))
	TimeManager.advance(120, "work")
	PlayerManager.change("energy", -14.0)
	PlayerManager.change("stress", 4.0 if content == "sell" else -2.0)
	PlayerManager.change("mood", 3.0)
	SkillManager.add_xp("communication", 12.0 + comm, "直播")
	EconomyManager.earn(income, "兼职", "直播%s" % String(spec[1]))
	stats["stream"]["done"] = int(stats["stream"]["done"]) + 1
	stats["stream"]["stars"] = int(stats["stream"]["stars"]) + 5
	stats["stream"]["earned"] = int(stats["stream"]["earned"]) + income
	Events.notify("stream", {"content": content, "income": income})
	Events.stats_changed.emit()
	return "直播%s两小时：新增粉丝 %d（共 %d），收入 %s，口才经验 +%d。" % [String(spec[1]), gain, followers, Fmt.yuan(income), int(12.0 + comm)]


func to_dict() -> Dictionary:
	return {"stats": stats.duplicate(true), "followers": followers}


func from_dict(d: Dictionary) -> void:
	reset()
	var s: Dictionary = d.get("stats", {})
	for k in s:
		if stats.has(k):
			stats[k] = s[k]
	followers = int(d.get("followers", 0))
