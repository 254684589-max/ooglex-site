extends Node
## 经济系统（自动加载名：EconomyManager）。
## 所有现金与银行存款的变动都必须经过这里：earn() 收入、spend() 支出、deposit()/withdraw() 存取。
## 同时记录流水、按月统计收支，并计算净资产与被动收入。

const LEDGER_MAX := 300
const BASE_DEPOSIT_RATE := 0.025  # 年化，按日计息

var cash := 0
var bank := 0
## 流水：[{day, time, amount, category, note, account}]
var ledger: Array = []
## 按月统计：{"2088-03": {"income": {cat: n}, "expense": {cat: n}}}
var monthly: Dictionary = {}
## 每日被动收入：{day: amount}
var passive_daily: Dictionary = {}
var total_earned_work := 0


func _ready() -> void:
	TimeManager.day_changed.connect(_on_day_changed)


func reset(start_cash := 2000) -> void:
	cash = start_cash
	bank = 0
	ledger.clear()
	monthly.clear()
	passive_daily.clear()
	total_earned_work = 0
	Events.money_changed.emit()


func liquid() -> int:
	return cash + bank


func can_afford(amount: int) -> bool:
	return liquid() >= amount


## 收入。to_bank 为 true 时直接进银行卡（月薪、分红）；passive 表示计入被动收入。
func earn(amount: int, category: String, note := "", to_bank := false, passive := false) -> void:
	if amount <= 0:
		return
	if to_bank:
		bank += amount
	else:
		cash += amount
	_record(amount, category, note, "bank" if to_bank else "cash")
	if category in ["奖金", "加班费", "兼职"]:
		note_work_income(amount)
	if passive:
		passive_daily[TimeManager.day] = int(passive_daily.get(TimeManager.day, 0)) + amount
	Events.money_changed.emit()


## 工作收入（任务「挣到 ¥X」按这个累计；月薪在下班时按班次计入，发薪日再实际到账）
func note_work_income(amount: int) -> void:
	total_earned_work += amount
	Events.notify("earn", {"amount": amount})


## 支出：默认先用现金，不够再刷银行卡。余额不足返回 false，不扣钱。
func spend(amount: int, category: String, note := "", allow_bank := true) -> bool:
	if amount <= 0:
		return true
	var available := cash + (bank if allow_bank else 0)
	if available < amount:
		return false
	var from_cash := mini(cash, amount)
	cash -= from_cash
	var rest := amount - from_cash
	if rest > 0:
		bank -= rest
	_record(-amount, category, note, "cash" if rest == 0 else "bank")
	Events.money_changed.emit()
	return true


## 优先从银行卡扣款（投资、创业注资）
func spend_bank_first(amount: int, category: String, note := "") -> bool:
	if amount <= 0:
		return true
	if liquid() < amount:
		return false
	var from_bank := mini(bank, amount)
	bank -= from_bank
	cash -= amount - from_bank
	_record(-amount, category, note, "bank")
	Events.money_changed.emit()
	return true


## 强制扣款（房租、罚款）：余额不够时扣到 0，返回实际扣到的金额
func charge(amount: int, category: String, note := "") -> int:
	var paid := mini(amount, liquid())
	if paid <= 0:
		return 0
	spend(paid, category, note, true)
	return paid


func deposit(amount: int) -> bool:
	if amount <= 0 or amount > cash:
		return false
	cash -= amount
	bank += amount
	_record(0, "存款", "存入 %s" % Fmt.yuan(amount), "bank")
	Events.notify("deposit", {"amount": amount})
	Events.money_changed.emit()
	return true


func withdraw(amount: int) -> bool:
	if amount <= 0 or amount > bank:
		return false
	bank -= amount
	cash += amount
	_record(0, "取款", "取出 %s" % Fmt.yuan(amount), "bank")
	Events.money_changed.emit()
	return true


## 资金凭空损失（被骗）
func withdraw_to_void(amount: int, note: String) -> void:
	var a := mini(amount, bank)
	bank -= a
	_record(-a, "其他", note, "bank")
	Events.money_changed.emit()


## 净资产 = 现金 + 存款 + 投资市值 + 公司权益 + 押金 + 车辆转卖价
func networth() -> int:
	return cash + bank + int(InvestmentManager.market_value()) + BusinessManager.equity() + HousingManager.deposit_held() + VehicleManager.resale_value()


## 近 30 天被动收入，折算为月
func passive_income_monthly() -> float:
	var total := 0
	for d in passive_daily:
		if int(d) > TimeManager.day - 30:
			total += int(passive_daily[d])
	var days := clampi(TimeManager.day - 1, 1, 30)
	return float(total) / float(days) * 30.0


func deposit_rate() -> float:
	var r := BASE_DEPOSIT_RATE
	var bonus: float = NPCManager.perk_value("deposit_rate")
	return r * (1.0 + bonus)


func month_stats(key := "") -> Dictionary:
	if key == "":
		key = TimeManager.month_key()
	return monthly.get(key, {"income": {}, "expense": {}})


func month_total(kind: String, key := "") -> int:
	var d: Dictionary = month_stats(key).get(kind, {})
	var t := 0
	for c in d:
		t += int(d[c])
	return t


func _record(amount: int, category: String, note: String, account: String) -> void:
	ledger.append({"day": TimeManager.day, "time": TimeManager.clock_text(), "amount": amount, "category": category, "note": note, "account": account})
	while ledger.size() > LEDGER_MAX:
		ledger.pop_front()
	if amount == 0:
		return
	var key := TimeManager.month_key()
	if not monthly.has(key):
		monthly[key] = {"income": {}, "expense": {}}
	var kind := "income" if amount > 0 else "expense"
	var bucket: Dictionary = monthly[key][kind]
	bucket[category] = int(bucket.get(category, 0)) + absi(amount)


func _on_day_changed(_day: int) -> void:
	if bank > 0:
		var interest := int(floor(bank * deposit_rate() / 365.0))
		if interest > 0:
			earn(interest, "利息", "存款利息", true, true)
	# 只保留最近 60 天的被动收入记录
	for d in passive_daily.keys():
		if int(d) < TimeManager.day - 60:
			passive_daily.erase(d)


func to_dict() -> Dictionary:
	return {"cash": cash, "bank": bank, "ledger": ledger, "monthly": monthly, "passive": passive_daily, "earned_work": total_earned_work}


func from_dict(d: Dictionary) -> void:
	cash = int(d.get("cash", 0))
	bank = int(d.get("bank", 0))
	ledger = Array(d.get("ledger", [])).duplicate(true)
	monthly = Dictionary(d.get("monthly", {})).duplicate(true)
	passive_daily.clear()
	var p: Dictionary = d.get("passive", {})
	for k in p:
		passive_daily[int(k)] = int(p[k])
	total_earned_work = int(d.get("earned_work", 0))
	Events.money_changed.emit()
