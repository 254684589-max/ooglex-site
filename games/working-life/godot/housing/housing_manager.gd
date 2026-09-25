extends Node
## 住房系统（自动加载名：HousingManager）。五个等级：廉价旅馆（按晚）→ 合租房 → 普通公寓 → 高级公寓 → 豪华住宅（月租）。
## 住房影响：睡眠恢复、每天的心情、体面度（面试 / 声望）、储物空间。月租每月 1 日自动扣款；
## 拖欠超过 7 天会被请出门（押金抵扣欠款）。
## 买房（普通公寓及以上）：全款或贷款（首付三成、120 期等额本息），房价每月小幅波动；自住免房租，也可以出租收租；
## 月供拖欠超过 30 天，银行收房拍卖。自己的房子可以装修（data/furniture.json），家具加成心情、睡眠、体面度。

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
## 自己买下的房子：id → {price, value, loan, payment, months_left, arrears, arrears_days, rented_out, furniture: {slot: item_id}, spent}
var owned: Dictionary = {}
## 已处理过月供 / 房价 / 租金的月份 key
var property_month := ""

const DOWN_RATIO := 0.3
const LOAN_MONTHS := 120
const MONTHLY_RATE := 0.0035
const TAX_RATE := 0.015
## 出租时到手的租金比例（扣中介与维修）
const LEASE_SHARE := 0.85
## 家具加成上限
const DECOR_MOOD_CAP := 6.0
const DECOR_SLEEP_CAP := 0.12
const DECOR_PRESTIGE_CAP := 8.0


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
	owned.clear()
	property_month = ""


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
	# 自己的房子（没租出去）随时能进
	for id in owned:
		if String(data(id).get("location", "")) == location_id and not bool(owned[id].get("rented_out", false)):
			return true
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
	return float(data(id).get("sleep", 1.0)) + decor_sum(id, "sleep")


func mood_bonus() -> float:
	var id := home_id()
	if id == "":
		return -8.0
	return float(data(id).get("mood", 0)) + decor_sum(id, "mood")


func prestige() -> float:
	var id := home_id()
	if id == "":
		return -3.0
	# 住自己的房子再加 2（有产权）
	return float(data(id).get("prestige", 0)) + decor_sum(id, "prestige") + (2.0 if owned.has(id) else 0.0)


func storage_capacity() -> int:
	var id := home_id()
	if id == "":
		return 0
	return int(data(id).get("storage", 0))


func deposit_held() -> int:
	return deposit


# ================================================================ 买房

func is_owned(id: String) -> bool:
	return owned.has(id)


func price_of(id: String) -> int:
	return int(data(id).get("price", 0))


## 当前市价（买下后随月份波动；没买的按标价）
func value_of(id: String) -> int:
	if owned.has(id):
		return int(owned[id].get("value", price_of(id)))
	return price_of(id)


## 等额本息月供
static func mortgage_payment(principal: float, months: int, rate := MONTHLY_RATE) -> int:
	if principal <= 0.0 or months <= 0:
		return 0
	return int(ceil(principal * rate / (1.0 - pow(1.0 + rate, -months))))


## 买房需要准备的钱：[首付或全款, 税费]
func purchase_cost(id: String, loan: bool) -> Array:
	var price := price_of(id)
	var down := int(round(price * DOWN_RATIO)) if loan else price
	return [down, int(round(price * TAX_RATE))]


func buy_home(id: String, loan: bool) -> String:
	var d := data(id)
	var price := price_of(id)
	if price <= 0:
		return "这种房子只能租，不能买"
	if owned.has(id):
		return "你已经买下这里了"
	var cost := purchase_cost(id, loan)
	var need: int = cost[0] + cost[1]
	if loan and not JobManager.has_job() and EconomyManager.passive_income_monthly() <= 0.0:
		return "银行不批贷款：需要有稳定工作或被动收入"
	if not EconomyManager.can_afford(need):
		return "钱不够：%s需要 %s（%s %s + 税费 %s）" % [String(d["name"]), Fmt.yuan(need), "首付" if loan else "全款", Fmt.yuan(cost[0]), Fmt.yuan(cost[1])]
	if not EconomyManager.spend(need, "住房", "买房：%s（%s）" % [String(d["name"]), "贷款" if loan else "全款"]):
		return "付款失败"
	var principal := float(price - int(cost[0]))
	owned[id] = {"price": price, "value": price, "loan": principal, "payment": mortgage_payment(principal, LOAN_MONTHS) if loan else 0,
		"months_left": LOAN_MONTHS if loan else 0, "arrears": 0, "arrears_days": 0, "rented_out": false, "furniture": {}, "spent": 0,
		"bought_day": TimeManager.day}
	PlayerManager.change("mood", 15.0)
	AudioManager.play_sfx("levelup", -4.0)
	Events.housing_changed.emit()
	Events.stats_changed.emit()
	Events.notify("buy_home", {"level": int(d.get("level", 0))})
	var tip := "月供 %s，每月 1 日扣款，共 %d 期。" % [Fmt.yuan(int(owned[id]["payment"])), LOAN_MONTHS] if loan else ""
	return "恭喜！你买下了%s（%s）。%s到手机「房产」里选择搬进去或出租。" % [String(d["name"]), DataDB.location_name(String(d["location"])), tip]


## 搬进自己的房子（原来租的房子自动退租、押金退回）
func move_into_owned(id: String) -> String:
	if not owned.has(id):
		return "这不是你的房子"
	if current == id:
		return "你已经住在这里了"
	var o: Dictionary = owned[id]
	if bool(o.get("rented_out", false)):
		o["rented_out"] = false
		Events.phone_message.emit("中介", "已经和租客解约，房子空出来了。")
	if current != "" and not owned.has(current):
		_refund_deposit()
	current = id
	arrears = 0
	arrears_days = 0
	Events.housing_changed.emit()
	Events.stats_changed.emit()
	Events.notify("rent", {"level": int(data(id).get("level", 0))})
	return "你搬进了自己的%s。" % String(data(id).get("name", ""))


## 出租 / 收回
func set_rented_out(id: String, on: bool) -> String:
	if not owned.has(id):
		return "这不是你的房子"
	if on and current == id:
		return "你正住在这里，先搬到别处才能出租"
	owned[id]["rented_out"] = on
	Events.housing_changed.emit()
	if on:
		return "已委托中介出租，每月 1 日租金 %s 打到银行卡（扣掉中介与维修费）。" % Fmt.yuan(lease_income(id))
	return "已收回，房子空着。"


func lease_income(id: String) -> int:
	return int(round(float(data(id).get("rent", 0)) * LEASE_SHARE))


## 提前还款（0：全部还清）
func prepay(id: String, amount := 0) -> String:
	if not owned.has(id):
		return "这不是你的房子"
	var o: Dictionary = owned[id]
	var loan := float(o.get("loan", 0.0))
	if loan <= 0.5:
		return "这套房没有贷款"
	var pay := int(ceil(loan)) if amount <= 0 else mini(amount, int(ceil(loan)))
	if not EconomyManager.can_afford(pay):
		return "钱不够提前还 %s" % Fmt.yuan(pay)
	EconomyManager.spend(pay, "住房", "提前还房贷")
	loan = maxf(0.0, loan - pay)
	o["loan"] = loan
	if loan <= 0.5:
		o["loan"] = 0.0
		o["payment"] = 0
		o["months_left"] = 0
		PlayerManager.change("mood", 10.0)
		Events.housing_changed.emit()
		return "房贷全部还清！这套房子完完全全是你的了。"
	o["payment"] = mortgage_payment(loan, int(o["months_left"]))
	Events.housing_changed.emit()
	return "提前还款 %s，剩余本金 %s，月供降到 %s。" % [Fmt.yuan(pay), Fmt.yuan(int(loan)), Fmt.yuan(int(o["payment"]))]


## 卖房：按市价扣 3% 税费中介费，还清贷款，家具按三成随房作价
func sell_home(id: String) -> String:
	if not owned.has(id):
		return "这不是你的房子"
	var o: Dictionary = owned[id]
	var gross := int(round(float(o["value"]) * 0.97)) + int(float(o.get("spent", 0)) * 0.3)
	var net := gross - int(ceil(float(o.get("loan", 0.0)))) - int(o.get("arrears", 0))
	owned.erase(id)
	if current == id:
		current = ""
	if net > 0:
		EconomyManager.earn(net, "住房", "卖房：%s" % String(data(id).get("name", "")), true)
	elif net < 0:
		EconomyManager.charge(-net, "住房", "卖房后补足房贷")
	Events.housing_changed.emit()
	Events.stats_changed.emit()
	return "卖掉了%s：成交 %s，还清贷款后到手 %s（已转入银行卡）。" % [String(data(id).get("name", "")), Fmt.yuan(gross), Fmt.yuan(net)]


## 房产净值（市价 - 剩余贷款 - 欠供），计入净资产
func property_equity() -> int:
	var total := 0
	for id in owned:
		var o: Dictionary = owned[id]
		total += int(o["value"]) - int(ceil(float(o.get("loan", 0.0)))) - int(o.get("arrears", 0))
	return total


func monthly_mortgage() -> int:
	var total := 0
	for id in owned:
		total += int(owned[id].get("payment", 0))
	return total


# ================================================================ 装修

func furniture_of(id: String) -> Dictionary:
	return owned[id].get("furniture", {}) if owned.has(id) else {}


## 某套房里全部家具某项加成之和（有上限）
func decor_sum(id: String, key: String) -> float:
	if not owned.has(id):
		return 0.0
	var total := 0.0
	for slot in furniture_of(id):
		total += float(DataDB.furniture.get(String(furniture_of(id)[slot]), {}).get(key, 0.0))
	match key:
		"mood":
			return minf(total, DECOR_MOOD_CAP)
		"sleep":
			return minf(total, DECOR_SLEEP_CAP)
		"prestige":
			return minf(total, DECOR_PRESTIGE_CAP)
	return total


## 买家具（同一位置的旧家具按三成折价回收）
func buy_furniture(home: String, item_id: String) -> String:
	if not owned.has(home):
		return "租的房子不能装修（房东不同意），先买下一套房吧"
	var it: Dictionary = DataDB.furniture.get(item_id, {})
	if it.is_empty():
		return "没有这件家具"
	var slot := String(it["slot"])
	var furn: Dictionary = owned[home]["furniture"]
	if String(furn.get(slot, "")) == item_id:
		return "已经摆着这件了"
	var price := int(it["price"])
	var refund := 0
	if furn.has(slot):
		refund = int(float(DataDB.furniture.get(String(furn[slot]), {}).get("price", 0)) * 0.3)
	if not EconomyManager.can_afford(price - refund):
		return "钱不够：%s %s" % [String(it["name"]), Fmt.yuan(price)]
	EconomyManager.spend(price, "住房", "装修：%s" % String(it["name"]))
	if refund > 0:
		EconomyManager.earn(refund, "住房", "旧家具回收", true)
	furn[slot] = item_id
	owned[home]["spent"] = int(owned[home].get("spent", 0)) + price
	Events.housing_changed.emit()
	Events.stats_changed.emit()
	return "%s 已送货安装%s。" % [String(it["name"]), ("（旧的回收 %s）" % Fmt.yuan(refund)) if refund > 0 else ""]


## 每月 1 日：月供、租金、房价波动
func _process_properties() -> void:
	var key := TimeManager.month_key()
	if property_month == key:
		return
	property_month = key
	for id in owned.keys():
		var o: Dictionary = owned[id]
		# 房价：每月 +0.4% 的趋势，上下随机 1.2%
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(key + id)
		o["value"] = int(round(float(o["value"]) * (1.004 + rng.randf_range(-0.012, 0.012))))
		var pay := int(o.get("payment", 0))
		if pay > 0 and float(o.get("loan", 0.0)) > 0.5:
			var got := EconomyManager.charge(pay, "住房", "%s 房贷月供" % String(data(id).get("name", "")))
			var interest := float(o["loan"]) * MONTHLY_RATE
			o["loan"] = maxf(0.0, float(o["loan"]) - (pay - interest))
			o["months_left"] = maxi(0, int(o["months_left"]) - 1)
			if o["months_left"] == 0 or float(o["loan"]) <= 0.5:
				o["loan"] = 0.0
				o["payment"] = 0
			if got < pay:
				o["arrears"] = int(o.get("arrears", 0)) + pay - got
				Events.phone_message.emit("银行", "%s 本月房贷还差 %s，请尽快存钱补缴，逾期 30 天将收回房产。" % [String(data(id).get("name", "")), Fmt.yuan(pay - got)])
		if bool(o.get("rented_out", false)):
			var inc := lease_income(id)
			EconomyManager.earn(inc, "租金", "%s 出租收入" % String(data(id).get("name", "")), true, true)
			Events.phone_message.emit("中介", "%s 本月租金 %s 已打到你的银行卡。" % [String(data(id).get("name", "")), Fmt.yuan(inc)])


## 每天：补缴拖欠的月供；逾期 30 天银行收房
func _daily_properties() -> void:
	for id in owned.keys():
		var o: Dictionary = owned[id]
		var owe := int(o.get("arrears", 0))
		if owe <= 0:
			o["arrears_days"] = 0
			continue
		var got := EconomyManager.charge(owe, "住房", "补缴房贷")
		o["arrears"] = owe - got
		if int(o["arrears"]) <= 0:
			o["arrears_days"] = 0
			continue
		o["arrears_days"] = int(o.get("arrears_days", 0)) + 1
		if int(o["arrears_days"]) > 30:
			var auction := int(float(o["value"]) * 0.8)
			var net := auction - int(ceil(float(o.get("loan", 0.0)))) - int(o["arrears"])
			owned.erase(id)
			if current == id:
				current = ""
			if net > 0:
				EconomyManager.earn(net, "住房", "法拍房款余额", true)
			Events.phone_message.emit("银行", "房贷逾期超过 30 天，%s 已被收回拍卖，扣除欠款后退回 %s。" % [String(data(id).get("name", "")), Fmt.yuan(maxi(net, 0))])
			Events.say("房子被银行收走了……", "bad")
			PlayerManager.change("mood", -30)
			Events.housing_changed.emit()


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
	if not owned.is_empty():
		if TimeManager.day_of_month() == 1:
			_process_properties()
		_daily_properties()
	# 住在自己的房子里：不交房租
	if current == "" or owned.has(current):
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
		"hotel_until": hotel_until, "paid_month": paid_month, "owned": owned.duplicate(true), "property_month": property_month}


func from_dict(d: Dictionary) -> void:
	current = String(d.get("current", ""))
	deposit = int(d.get("deposit", 0))
	rent_mult = float(d.get("rent_mult", 1.0))
	arrears = int(d.get("arrears", 0))
	arrears_days = int(d.get("arrears_days", 0))
	hotel_until = float(d.get("hotel_until", -1.0))
	paid_month = String(d.get("paid_month", ""))
	owned = {}
	var od: Dictionary = d.get("owned", {})
	for id in od:
		if not data(String(id)).is_empty():
			owned[String(id)] = od[id]
	property_month = String(d.get("property_month", ""))
	Events.housing_changed.emit()
