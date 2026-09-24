extends Node
## 创业系统（自动加载名：BusinessManager）。
## 条件：管理 Lv.5 + 现金与存款合计 ¥100,000。在霓虹广场「创业孵化中心」注册公司。
## 每天结算：产能（员工 × 设备 × 运营效率 × 管理加成）先推进已接项目，剩余产能做零散业务；
## 成本 = 工资 + 办公室租金 + 市场预算。公司账户连续亏空超过 14 天就破产。

signal company_changed

var company: Dictionary = {}
var bankruptcies := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	TimeManager.day_changed.connect(_on_day)


func reset() -> void:
	company = {}
	bankruptcies = 0


func cfg() -> Dictionary:
	return DataDB.business


func has_company() -> bool:
	return not company.is_empty()


func stage() -> int:
	return int(company.get("stage", 0))


func stage_data(lvl := -1) -> Dictionary:
	if lvl < 0:
		lvl = stage()
	for s in cfg().get("stages", []):
		if int(s["level"]) == lvl:
			return s
	return {}


func stage_name() -> String:
	return String(stage_data().get("name", "")) if has_company() else "未创业"


func company_cash() -> int:
	return int(company.get("cash", 0))


func employee_count() -> int:
	if not has_company():
		return 0
	var n := 0
	var e: Dictionary = company.get("employees", {})
	for r in e:
		n += int(e[r])
	return n


func employee_cap() -> int:
	return [6, 15, 30, 60, 200][clampi(stage() - 1, 0, 4)]


func role(id: String) -> Dictionary:
	for r in cfg().get("roles", []):
		if String(r["id"]) == id:
			return r
	return {}


func can_found() -> Dictionary:
	if has_company():
		return {"ok": false, "reason": "你已经有一家公司了"}
	var req: Dictionary = cfg().get("require", {})
	var missing: Array = SkillManager.missing(req.get("skill", {}))
	if EconomyManager.liquid() < int(req.get("liquid_min", 100000)):
		missing.append("现金与存款合计 %s（当前 %s）" % [Fmt.yuan(int(req.get("liquid_min", 100000))), Fmt.yuan(EconomyManager.liquid())])
	if not missing.is_empty():
		return {"ok": false, "reason": "创业条件不足：" + "、".join(missing)}
	return {"ok": true}


func found_cost() -> int:
	return int(float(cfg().get("found_cost", 50000)) * (1.0 - NPCManager.perk_value("business_mentor")))


## 注册公司：支付注册与装修费用，并把 capital 注入公司账户
func found(company_name: String, capital: int) -> String:
	var chk := can_found()
	if not bool(chk["ok"]):
		return String(chk["reason"])
	var cost := found_cost()
	capital = maxi(capital, 10000)
	if EconomyManager.liquid() < cost + capital:
		return "钱不够：注册费 %s + 启动资金 %s" % [Fmt.yuan(cost), Fmt.yuan(capital)]
	EconomyManager.spend_bank_first(cost, "创业", "公司注册与装修")
	EconomyManager.spend_bank_first(capital, "创业", "注入启动资金")
	company = {
		"name": company_name if company_name != "" else "霓虹工作室", "founded_day": TimeManager.day, "cash": capital,
		"employees": {"dev": 0, "sales": 0, "ops": 0}, "equipment": 0, "marketing": 0, "rep": 10.0, "revenue_total": 0,
		"projects": [], "offers": [], "neg_days": 0, "dividend": 0.2, "boost_day": -1, "boost": 0.0, "history": [], "stage": 1,
		"projects_done": 0,
	}
	_refresh_offers()
	if NPCManager.has_perk("business_mentor"):
		var tpl: Dictionary = cfg().get("projects", [])[0]
		company["offers"].push_front(_make_offer(tpl, 1.3))
	Events.notify("business_found", {})
	company_changed.emit()
	Events.stats_changed.emit()
	Events.banner.emit("公司成立！", "「%s」在霓虹广场开张了" % String(company["name"]))
	return "公司注册成功！"


func capacity() -> float:
	if not has_company():
		return 0.0
	var e: Dictionary = company["employees"]
	var cap := 1.0
	for r in e:
		cap += float(role(String(r)).get("capacity", 0.5)) * int(e[r])
	var eq: Array = cfg().get("equipment", [])
	cap *= 1.0 + float(eq[clampi(int(company.get("equipment", 0)), 0, eq.size() - 1)].get("bonus", 0.0))
	cap *= 1.0 + minf(0.4, int(e.get("ops", 0)) * 0.04)
	cap *= 1.0 + SkillManager.level("management") * 0.03
	if int(company.get("boost_day", -1)) == TimeManager.day:
		cap *= 1.0 + float(company.get("boost", 0.0))
	return cap


func daily_salaries() -> int:
	if not has_company():
		return 0
	var t := 0
	var e: Dictionary = company["employees"]
	for r in e:
		t += int(role(String(r)).get("salary", 300)) * int(e[r])
	return t


func office_rent() -> int:
	var arr: Array = cfg().get("office_rent_per_day", [300])
	return int(arr[clampi(stage() - 1, 0, arr.size() - 1)])


func daily_cost() -> int:
	return daily_salaries() + office_rent() + int(company.get("marketing", 0))


func hire(role_id: String, n := 1) -> String:
	if not has_company():
		return "还没有公司"
	if employee_count() + n > employee_cap():
		return "办公室坐不下了（%s阶段上限 %d 人）" % [stage_name(), employee_cap()]
	var fee := 3000 * n
	if company_cash() < fee:
		return "公司账户不足以支付招聘费用 %s" % Fmt.yuan(fee)
	company["cash"] = company_cash() - fee
	company["employees"][role_id] = int(company["employees"].get(role_id, 0)) + n
	SkillManager.add_xp("management", 6 * n, "招聘")
	company_changed.emit()
	Events.stats_changed.emit()
	return "招聘了 %d 名%s（招聘费 %s）" % [n, String(role(role_id).get("name", role_id)), Fmt.yuan(fee)]


func fire_employee(role_id: String) -> String:
	if int(company.get("employees", {}).get(role_id, 0)) <= 0:
		return "没有可以裁的人"
	company["employees"][role_id] = int(company["employees"][role_id]) - 1
	var sev := int(role(role_id).get("salary", 300)) * 15
	company["cash"] = company_cash() - sev
	change_rep(-1)
	company_changed.emit()
	return "裁掉一名%s，支付补偿金 %s" % [String(role(role_id).get("name", "")), Fmt.yuan(sev)]


func lose_employee() -> void:
	if not has_company():
		return
	for r in ["dev", "sales", "ops"]:
		if int(company["employees"].get(r, 0)) > 0:
			company["employees"][r] = int(company["employees"][r]) - 1
			company_changed.emit()
			return


func set_marketing(amount: int) -> void:
	if has_company():
		company["marketing"] = clampi(amount, 0, 50000)
		company_changed.emit()


func set_dividend(rate: float) -> void:
	if has_company():
		company["dividend"] = clampf(rate, 0.0, 0.8)
		company_changed.emit()


func buy_equipment() -> String:
	if not has_company():
		return "还没有公司"
	var eq: Array = cfg().get("equipment", [])
	var lvl := int(company.get("equipment", 0)) + 1
	if lvl >= eq.size():
		return "设备已经是最高级"
	var cost := int(eq[lvl]["cost"])
	if company_cash() < cost:
		return "公司账户资金不足（需要 %s）" % Fmt.yuan(cost)
	company["cash"] = company_cash() - cost
	company["equipment"] = lvl
	company_changed.emit()
	return "购入%s，产能 +%d%%" % [String(eq[lvl]["name"]), int(float(eq[lvl]["bonus"]) * 100)]


func inject(amount: int) -> String:
	if not has_company() or amount <= 0:
		return "无效金额"
	if not EconomyManager.spend_bank_first(amount, "创业", "向公司注资"):
		return "个人资金不足"
	company["cash"] = company_cash() + amount
	company_changed.emit()
	return "向公司注资 %s" % Fmt.yuan(amount)


func withdraw(amount: int) -> String:
	if not has_company() or amount <= 0:
		return "无效金额"
	if company_cash() < amount:
		return "公司账户没这么多钱"
	company["cash"] = company_cash() - amount
	EconomyManager.earn(amount, "公司分红", "从公司提取", true, true)
	company_changed.emit()
	return "从公司提取 %s 到银行卡" % Fmt.yuan(amount)


func adjust_cash(amount: int, _note := "") -> void:
	if has_company():
		company["cash"] = company_cash() + amount
		company_changed.emit()


func change_rep(v: float) -> void:
	if has_company():
		company["rep"] = clampf(float(company.get("rep", 10)) + v, 0.0, 100.0)
		company_changed.emit()


func boost_today(score: float) -> String:
	if not has_company():
		return ""
	company["boost_day"] = TimeManager.day
	company["boost"] = clampf(score / 100.0 * 0.35, 0.0, 0.35)
	SkillManager.add_xp("management", 20 + score / 5.0, "管理公司")
	company_changed.emit()
	return "今天团队产能 +%d%%" % int(float(company["boost"]) * 100)


func _make_offer(tpl: Dictionary, scale := 1.0) -> Dictionary:
	var s := scale * (1.0 + float(company.get("rep", 10)) / 200.0)
	return {"id": String(tpl["id"]), "name": String(tpl["name"]), "client": String(tpl["client"]),
		"work": float(tpl["work"]), "value": int(float(tpl["value"]) * s), "days": int(tpl["days"]), "risk": float(tpl.get("risk", 0.05))}


func _refresh_offers() -> void:
	var cap := capacity()
	var out: Array = []
	var sales := int(company.get("employees", {}).get("sales", 0))
	var n := 2 + mini(4, int(sales / 2.0))
	var tpls: Array = cfg().get("projects", [])
	var fit: Array = []
	for t in tpls:
		if float(t["work"]) <= cap * float(t["days"]) * 1.6:
			fit.append(t)
	if fit.is_empty():
		fit.append(tpls[0])
	for i in n:
		# 偏向接近产能上限的大项目
		var t: Dictionary = fit[clampi(fit.size() - 1 - _rng.randi_range(0, 2), 0, fit.size() - 1)]
		out.append(_make_offer(t, _rng.randf_range(0.9, 1.2)))
	company["offers"] = out


func accept_offer(i: int) -> String:
	var offers: Array = company.get("offers", [])
	if i < 0 or i >= offers.size():
		return "无效项目"
	if (company.get("projects", []) as Array).size() >= 3:
		return "同时最多做 3 个项目"
	var o: Dictionary = offers[i]
	offers.remove_at(i)
	var p := o.duplicate()
	p["work_left"] = float(o["work"])
	p["days_left"] = int(o["days"])
	company["projects"].append(p)
	company_changed.emit()
	return "接下项目「%s」，%d 天内交付，报酬 %s" % [String(o["name"]), int(o["days"]), Fmt.yuan(int(o["value"]))]


func demand_factor() -> float:
	var f := 1.0
	match InvestmentManager.cycle:
		"boom":
			f = 1.2
		"recession":
			f = 0.7
	f += minf(0.5, float(company.get("marketing", 0)) / 20000.0)
	return f


## 一天的经营结算（也用于测试）
func simulate_day() -> Dictionary:
	if not has_company():
		return {}
	var cap := capacity()
	var revenue := 0
	var notes: Array = []
	var projects: Array = company.get("projects", [])
	for p in projects.duplicate():
		if cap <= 0.0:
			break
		var use := minf(cap, float(p["work_left"]))
		p["work_left"] = float(p["work_left"]) - use
		cap -= use
	for p in projects.duplicate():
		p["days_left"] = int(p["days_left"]) - 1
		if float(p["work_left"]) <= 0.001:
			var v := int(float(p["value"]) * (1.0 + float(company.get("rep", 10)) / 200.0))
			revenue += v
			projects.erase(p)
			company["projects_done"] = int(company.get("projects_done", 0)) + 1
			change_rep(3)
			notes.append("项目「%s」交付，收入 %s" % [String(p["name"]), Fmt.yuan(v)])
			Events.notify("project_done", {"project": String(p["id"])})
		elif int(p["days_left"]) < 0:
			var partial := int(float(p["value"]) * 0.25)
			revenue += partial
			projects.erase(p)
			change_rep(-6)
			notes.append("项目「%s」逾期，客户只付了 %s" % [String(p["name"]), Fmt.yuan(partial)])
	# 零散业务
	var mult := float(stage_data().get("mult", 1.0))
	var unit := float(cfg().get("unit_revenue", 500))
	var sales := int(company["employees"].get("sales", 0))
	var small := cap * unit * mult * (0.5 + float(company.get("rep", 10)) / 100.0) * demand_factor() * (0.6 + minf(0.6, sales * 0.08))
	revenue += int(small)
	var cost := daily_cost()
	var profit := revenue - cost
	company["cash"] = company_cash() + profit
	company["revenue_total"] = int(company.get("revenue_total", 0)) + revenue
	var div := 0
	if profit > 0 and company_cash() > 0:
		div = int(profit * float(company.get("dividend", 0.2)))
		if div > 0:
			company["cash"] = company_cash() - div
			EconomyManager.earn(div, "公司分红", "「%s」分红" % String(company["name"]), true, true)
	var h: Array = company.get("history", [])
	h.append({"day": TimeManager.day, "revenue": revenue, "cost": cost, "profit": profit})
	while h.size() > 30:
		h.pop_front()
	company["history"] = h
	# 阶段成长
	var st := stage()
	for s in cfg().get("stages", []):
		if int(s["level"]) > st and employee_count() >= int(s["employees"]) and int(company["revenue_total"]) >= int(s["revenue"]):
			st = int(s["level"])
	if st > stage():
		company["stage"] = st
		PlayerManager.change_reputation(5)
		Events.banner.emit("公司升级！", "「%s」成为%s" % [String(company["name"]), stage_name()])
	# 破产判定
	if company_cash() < 0:
		company["neg_days"] = int(company.get("neg_days", 0)) + 1
		var left := int(cfg().get("bankrupt_days", 14)) - int(company["neg_days"])
		if left <= 0:
			_bankrupt()
			return {"revenue": revenue, "cost": cost, "profit": profit, "bankrupt": true}
		Events.phone_message.emit("公司财务", "公司账户透支 %s，%d 天内不补足资金将破产清算！" % [Fmt.yuan(-company_cash()), left])
	else:
		company["neg_days"] = 0
	if (TimeManager.day - int(company.get("founded_day", 0))) % 3 == 0 or (company.get("offers", []) as Array).is_empty():
		_refresh_offers()
	for n in notes:
		Events.phone_message.emit("公司", n)
	company_changed.emit()
	return {"revenue": revenue, "cost": cost, "profit": profit, "dividend": div}


func _bankrupt() -> void:
	var nm := String(company.get("name", ""))
	company = {}
	bankruptcies += 1
	PlayerManager.change_reputation(-10)
	PlayerManager.change("mood", -30)
	PlayerManager.change("stress", 25)
	Events.banner.emit("公司破产", "「%s」资不抵债，清算关门" % nm)
	Events.phone_message.emit("法院", "「%s」已进入破产清算程序。" % nm)
	company_changed.emit()


func last_days(n := 30) -> Dictionary:
	var r := 0
	var c := 0
	for h in company.get("history", []).slice(-n):
		r += int(h["revenue"])
		c += int(h["cost"])
	return {"revenue": r, "cost": c, "profit": r - c}


## 公司权益（计入净资产）：账上现金 + 设备残值 + 近 30 天利润 × 6
func equity() -> int:
	if not has_company():
		return 0
	var eq: Array = cfg().get("equipment", [])
	var eq_val := 0
	for i in range(1, int(company.get("equipment", 0)) + 1):
		eq_val += int(int(eq[i]["cost"]) * 0.5)
	var profit30 := maxi(0, int(last_days(30)["profit"]))
	return maxi(0, company_cash()) + eq_val + profit30 * 6


func _on_day(_d: int) -> void:
	if has_company():
		simulate_day()


func to_dict() -> Dictionary:
	return {"company": company, "bankruptcies": bankruptcies}


func from_dict(d: Dictionary) -> void:
	company = Dictionary(d.get("company", {})).duplicate(true)
	bankruptcies = int(d.get("bankruptcies", 0))
	if not company.is_empty():
		for k in ["cash", "equipment", "marketing", "revenue_total", "neg_days", "boost_day", "stage", "founded_day", "projects_done"]:
			if company.has(k):
				company[k] = int(company[k])
		var e: Dictionary = company.get("employees", {})
		for r in e:
			e[r] = int(e[r])
	company_changed.emit()
