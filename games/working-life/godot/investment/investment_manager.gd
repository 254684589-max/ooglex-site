extends Node
## 投资系统（自动加载名：InvestmentManager）。
## 五种虚构资产（指数基金、科技股、银行股、黄金、债券），价格由游戏内部模型每天生成：
##   日收益 = 周期漂移 + 波动率 × 正态随机数 + 新闻冲击
## 经济周期：繁荣 / 平稳 / 衰退，每 18~40 天切换一次（也会被随机事件改变）。
## 不连接任何真实金融接口。买卖通过银行卡结算，手续费 0.1%。分红与票息每天计入银行卡（被动收入）。

signal market_updated

const HISTORY_DAYS := 60
const CYCLE_NAMES := {"boom": "繁荣", "normal": "平稳", "recession": "衰退"}

var prices: Dictionary = {}
var history: Dictionary = {}
## id -> {units: float, cost: float(总成本)}
var holdings: Dictionary = {}
var realized := 0.0
var trades := 0
var cycle := "normal"
var cycle_days_left := 25
var last_change: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	TimeManager.day_changed.connect(_on_day)


func reset() -> void:
	prices.clear()
	history.clear()
	holdings.clear()
	last_change.clear()
	realized = 0.0
	trades = 0
	cycle = "normal"
	cycle_days_left = 25
	for id in DataDB.ids("assets"):
		var a: Dictionary = DataDB.assets[id]
		prices[id] = float(a.get("price", 100.0))
		last_change[id] = 0.0
		# 预先生成 30 天历史，让走势图一开始就有内容
		var h: Array = []
		var p := float(a.get("price", 100.0))
		var back: Array = [p]
		for i in 29:
			p = p / exp(float(a["drift"]["normal"]) + float(a["vol"]) * _gauss())
			back.push_front(p)
		h = back
		history[id] = h
		prices[id] = float(h[-1])


func unlocked() -> bool:
	return Conditions.check(DataDB.meta("assets").get("unlock", {}))


func fee_rate() -> float:
	return float(DataDB.meta("assets").get("fee", 0.001))


func asset(id: String) -> Dictionary:
	return DataDB.assets.get(id, {})


func price(id: String) -> float:
	return float(prices.get(id, 0.0))


func units(id: String) -> float:
	return float(holdings.get(id, {}).get("units", 0.0))


func avg_cost(id: String) -> float:
	var u := units(id)
	if u <= 0.0:
		return 0.0
	return float(holdings[id]["cost"]) / u


func position_value(id: String) -> float:
	return units(id) * price(id)


func position_pnl(id: String) -> float:
	if units(id) <= 0.0:
		return 0.0
	return position_value(id) - float(holdings[id]["cost"])


func market_value() -> float:
	var v := 0.0
	for id in holdings:
		v += position_value(id)
	return v


func unrealized() -> float:
	var v := 0.0
	for id in holdings:
		v += position_pnl(id)
	return v


func total_pnl() -> float:
	return realized + unrealized()


func has_any_holding() -> bool:
	for id in holdings:
		if units(id) > 0.0001:
			return true
	return false


func cycle_name() -> String:
	return CYCLE_NAMES.get(cycle, cycle)


## 买入：花 amount 元（含手续费）。返回提示文字
func buy(id: String, amount: int) -> String:
	if not unlocked():
		return String(DataDB.meta("assets").get("unlock_text", "尚未开户"))
	if amount < 100:
		return "单笔至少 ¥100"
	if not EconomyManager.spend_bank_first(amount, "投资", "买入 %s" % String(asset(id).get("name", id))):
		return "资金不足"
	var net := float(amount) * (1.0 - fee_rate())
	var u := net / price(id)
	if not holdings.has(id):
		holdings[id] = {"units": 0.0, "cost": 0.0}
	holdings[id]["units"] = units(id) + u
	holdings[id]["cost"] = float(holdings[id]["cost"]) + float(amount)
	trades += 1
	SkillManager.add_xp("finance", 4, "投资")
	Events.notify("invest", {"asset": id, "amount": amount})
	Events.stats_changed.emit()
	market_updated.emit()
	return "买入 %s %.2f 份（%s）" % [String(asset(id).get("short", id)), u, Fmt.yuan(amount)]


## 卖出一定比例的持仓（0..1）
func sell(id: String, fraction: float) -> String:
	var u := units(id) * clampf(fraction, 0.0, 1.0)
	if u <= 0.000001:
		return "没有可卖的持仓"
	var cost_part := float(holdings[id]["cost"]) * clampf(fraction, 0.0, 1.0)
	var proceeds := u * price(id) * (1.0 - fee_rate())
	holdings[id]["units"] = units(id) - u
	holdings[id]["cost"] = float(holdings[id]["cost"]) - cost_part
	if units(id) <= 0.000001:
		holdings.erase(id)
	var pnl := proceeds - cost_part
	realized += pnl
	trades += 1
	EconomyManager.earn(int(round(proceeds)), "投资收回", "卖出 %s" % String(asset(id).get("name", id)), true)
	if pnl > 0:
		SkillManager.add_xp("finance", 6, "投资")
	Events.stats_changed.emit()
	market_updated.emit()
	return "卖出 %s，回款 %s（盈亏 %s）" % [String(asset(id).get("short", id)), Fmt.yuan(proceeds), Fmt.signed_yuan(pnl)]


func market_shock(d: Dictionary) -> void:
	for id in d:
		if prices.has(id):
			var f := 1.0 + float(d[id])
			prices[id] = maxf(0.01, price(id) * f)
			last_change[id] = float(last_change.get(id, 0.0)) + float(d[id])
			var h: Array = history[id]
			h[-1] = price(id)
	market_updated.emit()


func set_cycle(c: String) -> void:
	if not CYCLE_NAMES.has(c):
		return
	cycle = c
	var r: Array = DataDB.meta("assets").get("cycle_days", [18, 40])
	cycle_days_left = _rng.randi_range(int(r[0]), int(r[1]))
	market_updated.emit()


func _gauss() -> float:
	var u1 := maxf(_rng.randf(), 1e-6)
	var u2 := _rng.randf()
	return sqrt(-2.0 * log(u1)) * cos(TAU * u2)


func step_day() -> void:
	cycle_days_left -= 1
	if cycle_days_left <= 0:
		var r := _rng.randf()
		match cycle:
			"normal":
				set_cycle("boom" if r < 0.5 else "recession")
			_:
				set_cycle("normal" if r < 0.7 else ("recession" if cycle == "boom" else "boom"))
	var common := _gauss()
	for id in prices:
		var a := asset(id)
		var drift := float(a.get("drift", {}).get(cycle, 0.0))
		var vol := float(a.get("vol", 0.01))
		var beta := float(a.get("beta", 1.0))
		var z := common * clampf(absf(beta), 0.0, 1.0) * signf(beta) + _gauss() * sqrt(maxf(0.0, 1.0 - minf(1.0, beta * beta)))
		var ret := drift + vol * z
		var old := price(id)
		prices[id] = maxf(0.01, old * exp(ret))
		last_change[id] = prices[id] / old - 1.0
		var h: Array = history.get(id, [])
		h.append(prices[id])
		while h.size() > HISTORY_DAYS:
			h.pop_front()
		history[id] = h
	# 分红 / 票息（按日）→ 银行卡，计入被动收入
	var income := 0.0
	for id in holdings:
		income += position_value(id) * float(asset(id).get("yield", 0.0)) / 365.0
	if income >= 1.0:
		EconomyManager.earn(int(income), "分红", "投资分红与利息", true, true)
	market_updated.emit()


func _on_day(_d: int) -> void:
	step_day()


func to_dict() -> Dictionary:
	return {"prices": prices, "history": history, "holdings": holdings, "realized": realized, "trades": trades,
		"cycle": cycle, "cycle_days_left": cycle_days_left, "last_change": last_change}


func from_dict(d: Dictionary) -> void:
	reset()
	if d.is_empty():
		return
	for k in d.get("prices", {}):
		prices[String(k)] = float(d["prices"][k])
	for k in d.get("history", {}):
		history[String(k)] = Array(d["history"][k]).duplicate()
	holdings.clear()
	for k in d.get("holdings", {}):
		holdings[String(k)] = {"units": float(d["holdings"][k]["units"]), "cost": float(d["holdings"][k]["cost"])}
	for k in d.get("last_change", {}):
		last_change[String(k)] = float(d["last_change"][k])
	realized = float(d.get("realized", 0.0))
	trades = int(d.get("trades", 0))
	cycle = String(d.get("cycle", "normal"))
	cycle_days_left = int(d.get("cycle_days_left", 20))
