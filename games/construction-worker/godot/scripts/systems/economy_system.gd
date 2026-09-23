extends Node
## 经济系统（自动加载名：EconomySystem）：现金、饭票、流水账。

signal cash_changed(cash: int, delta: int, reason: String)
signal meal_tickets_changed(count: int)

const START_CASH := 300
const LEDGER_LIMIT := 40

var cash := START_CASH
var meal_tickets := 0
var today_income := 0
var today_expense := 0
var total_income := 0
## 流水：[{day, time, amount, reason}]，最新的在最后
var ledger: Array = []


func reset() -> void:
	cash = START_CASH
	meal_tickets = 0
	today_income = 0
	today_expense = 0
	total_income = 0
	ledger = []
	cash_changed.emit(cash, 0, "")
	meal_tickets_changed.emit(meal_tickets)


func earn(amount: int, reason: String) -> void:
	if amount <= 0:
		return
	cash += amount
	today_income += amount
	total_income += amount
	_log(amount, reason)
	cash_changed.emit(cash, amount, reason)


func can_afford(amount: int) -> bool:
	return cash >= amount


## 付钱。钱不够返回 false，不会扣成负数。
func spend(amount: int, reason: String) -> bool:
	if amount < 0 or cash < amount:
		return false
	if amount == 0:
		return true
	cash -= amount
	today_expense += amount
	_log(-amount, reason)
	cash_changed.emit(cash, -amount, reason)
	return true


func add_meal_ticket(n := 1) -> void:
	meal_tickets += n
	meal_tickets_changed.emit(meal_tickets)


func use_meal_ticket() -> bool:
	if meal_tickets <= 0:
		return false
	meal_tickets -= 1
	meal_tickets_changed.emit(meal_tickets)
	return true


## 新的一天：清零当日收支（结算界面已经读取过）。
func new_day() -> void:
	today_income = 0
	today_expense = 0


func _log(amount: int, reason: String) -> void:
	ledger.append({
		"day": TimeSystem.day,
		"time": TimeSystem.clock_text(),
		"amount": amount,
		"reason": reason,
	})
	while ledger.size() > LEDGER_LIMIT:
		ledger.pop_front()


func to_dict() -> Dictionary:
	return {
		"cash": cash,
		"meal_tickets": meal_tickets,
		"today_income": today_income,
		"today_expense": today_expense,
		"total_income": total_income,
		"ledger": ledger.duplicate(true),
	}


func from_dict(d: Dictionary) -> void:
	cash = int(d.get("cash", START_CASH))
	meal_tickets = int(d.get("meal_tickets", 0))
	today_income = int(d.get("today_income", 0))
	today_expense = int(d.get("today_expense", 0))
	total_income = int(d.get("total_income", 0))
	ledger = (d.get("ledger", []) as Array).duplicate(true)
	cash_changed.emit(cash, 0, "")
	meal_tickets_changed.emit(meal_tickets)
