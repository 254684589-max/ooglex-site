extends Node
## 住房系统（自动加载名：HousingManager）。五个等级：廉价旅馆（按晚）→ 合租房 → 普通公寓 → 高级公寓 → 豪华住宅（月租）。
## 住房影响：睡眠恢复、每天的心情、体面度（面试 / 声望）、储物空间。月租每月 1 日自动扣款；
## 拖欠超过 7 天会被请出门（押金抵扣欠款）。

## 当前月租住房 id（""：没有）
var current := ""
var deposit := 0
var rent_mult := 1.0
var arrears := 0
var arrears_days := 0
## 旅馆房间有效期：该天 12:00 之前（总分钟）
var hotel_until := -1.0
## 本月已付房租的月份 key
var paid_month := ""


func _ready() -> void:
	TimeManager.day_changed.connect(_on_day_changed)


func reset() -> void:
	current = ""
	deposit = 0
	rent_mult = 1.0
	arrears = 0
	arrears_days = 0
	hotel_until = -1.0
	paid_month = ""


func data(id: String) -> Dictionary:
	return DataDB.housing.get(id, {})


func has_hotel_room() -> bool:
	return TimeManager.total_minutes < hotel_until


## 当前住房等级：月租房优先，其次是有效的旅馆房间，都没有为 0
func level() -> int:
	if current != "":
		return int(data(current).get("level", 0))
	if has_hotel_room():
		return 1
	return 0


func home_id() -> String:
	if current != "":
		return current
	if has_hotel_room():
		return "hotel"
	return ""


func home_name() -> String:
	var id := home_id()
	if id == "":
		return "无固定住所"
	return String(data(id).get("name", id))


func is_monthly() -> bool:
	return current != ""


func home_location() -> String:
	var id := home_id()
	return String(data(id).get("location", "")) if id != "" else ""


## 玩家能否进入某处住房的房间
func can_enter(location_id: String) -> bool:
	if location_id == "":
		return false
	if current != "" and String(data(current).get("location", "")) == location_id:
		return true
	return location_id == "hotel" and has_hotel_room()


func rent_of(id: String) -> int:
	var d := data(id)
	var r := float(d.get("rent", 0)) * rent_mult
	if id in ["shared", "apartment"]:
		r *= 1.0 - NPCManager.perk_value("rent_discount")
	return int(round(r))


func sleep_quality() -> float:
	var id := home_id()
	if id == "":
		return 0.5
	return float(data(id).get("sleep", 1.0))


func mood_bonus() -> float:
	var id := home_id()
	if id == "":
		return -8.0
	return float(data(id).get("mood", 0))


func prestige() -> float:
	var id := home_id()
	if id == "":
		return -3.0
	return float(data(id).get("prestige", 0))


func storage_capacity() -> int:
	var id := home_id()
	if id == "":
		return 0
	return int(data(id).get("storage", 0))


func deposit_held() -> int:
	return deposit


## 旅馆：付一晚（或多晚）的房费
func book_hotel(nights := 1) -> String:
	var price := rent_of("hotel") * nights
	if not EconomyManager.spend(price, "住房", "安心旅馆 %d 晚" % nights):
		return "钱不够（需要 %s）" % Fmt.yuan(price)
	var start_day := TimeManager.day
	if has_hotel_room():
		start_day = int(hotel_until / 1440.0) + 1
	elif TimeManager.hour() < 6:
		start_day -= 1
	# 有效到第 start_day + nights 天中午 12 点
	hotel_until = (start_day + nights - 1) * 1440.0 + 12 * 60.0
	Events.housing_changed.emit()
	Events.stats_changed.emit()
	return "入住成功：%d 晚，%s。房间在大堂后面。" % [nights, Fmt.yuan(price)]


## 签约租房：押金 + 首月
func move_in(id: String) -> String:
	var d := data(id)
	if d.is_empty() or String(d.get("period", "")) != "month":
		return "无效的房源"
	if id == current:
		return "你已经住在这里了"
	var rent := rent_of(id)
	var need := rent * 2
	var refund := deposit
	if EconomyManager.liquid() + refund < need:
		return "钱不够：押一付一需要 %s" % Fmt.yuan(need)
	if current != "":
		_refund_deposit()
	if not EconomyManager.spend(need, "住房", "%s 押金+首月房租" % String(d["name"])):
		return "付款失败"
	current = id
	deposit = rent
	paid_month = TimeManager.month_key()
	arrears = 0
	arrears_days = 0
	Events.housing_changed.emit()
	Events.stats_changed.emit()
	Events.notify("rent", {"level": int(d["level"])})
	return "签约成功！你搬进了%s。" % String(d["name"])


func move_out() -> String:
	if current == "":
		return "你没有租房"
	var name := String(data(current).get("name", ""))
	_refund_deposit()
	current = ""
	Events.housing_changed.emit()
	Events.stats_changed.emit()
	return "已退租%s，押金退回银行卡。" % name


func _refund_deposit() -> void:
	var back := maxi(0, deposit - arrears)
	if back > 0:
		EconomyManager.earn(back, "押金退还", "退还押金", true)
	deposit = 0
	arrears = 0
	arrears_days = 0


func _on_day_changed(_d: int) -> void:
	if current == "":
		return
	var key := TimeManager.month_key()
	if TimeManager.day_of_month() == 1 and paid_month != key:
		var rent := rent_of(current)
		var paid := EconomyManager.charge(rent, "住房", "%s %s 房租" % [key, String(data(current).get("name", ""))])
		paid_month = key
		if paid < rent:
			arrears += rent - paid
			Events.phone_message.emit("房东", "这个月房租还差 %s，请在 7 天内补上，不然只能请你搬走了。" % Fmt.yuan(rent - paid))
		else:
			Events.phone_message.emit("房东", "%s 房租 %s 已扣款，谢谢。" % [key, Fmt.yuan(rent)])
	if arrears > 0:
		# 每天尝试补缴欠款
		var got := EconomyManager.charge(arrears, "住房", "补缴房租")
		arrears -= got
		if arrears > 0:
			arrears_days += 1
			if arrears_days > 7:
				var name := String(data(current).get("name", ""))
				deposit = 0
				current = ""
				arrears = 0
				arrears_days = 0
				Events.phone_message.emit("房东", "欠租超过一周，押金已抵扣。你的东西放在楼下了。")
				Events.say("你被请出了%s" % name, "bad")
				PlayerManager.change("mood", -20)
				Events.housing_changed.emit()
		else:
			arrears_days = 0


func to_dict() -> Dictionary:
	return {"current": current, "deposit": deposit, "rent_mult": rent_mult, "arrears": arrears, "arrears_days": arrears_days,
		"hotel_until": hotel_until, "paid_month": paid_month}


func from_dict(d: Dictionary) -> void:
	current = String(d.get("current", ""))
	deposit = int(d.get("deposit", 0))
	rent_mult = float(d.get("rent_mult", 1.0))
	arrears = int(d.get("arrears", 0))
	arrears_days = int(d.get("arrears_days", 0))
	hotel_until = float(d.get("hotel_until", -1.0))
	paid_month = String(d.get("paid_month", ""))
	Events.housing_changed.emit()
