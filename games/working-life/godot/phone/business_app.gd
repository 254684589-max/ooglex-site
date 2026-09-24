class_name BusinessApp
extends RefCounted
## 创业 APP：注册公司；经营面板（营收 / 成本 / 利润 / 员工 / 声誉 / 阶段）、招聘、项目、预算、设备、分红、注资。


static func build(box: VBoxContainer, refresh: Callable) -> void:
	if not BusinessManager.has_company():
		_found_page(box, refresh)
		return
	var c := BusinessManager.company
	box.add_child(UIKit.label("「%s」 · %s · 成立于第 %d 天" % [String(c["name"]), BusinessManager.stage_name(), int(c["founded_day"])], 19, UIKit.YELLOW, HORIZONTAL_ALIGNMENT_LEFT, true))
	var last := BusinessManager.last_days(30)
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 26)
	box.add_child(g)
	var cash := BusinessManager.company_cash()
	for pair in [["公司账户", Fmt.yuan(cash)], ["员工", "%d / %d 人" % [BusinessManager.employee_count(), BusinessManager.employee_cap()]], ["日产能", "%.1f" % BusinessManager.capacity()], ["每日成本", Fmt.yuan(BusinessManager.daily_cost())], ["近 30 天营收 Revenue", Fmt.yuan(int(last["revenue"]))], ["近 30 天成本 Cost", Fmt.yuan(int(last["cost"]))], ["近 30 天利润 Profit", Fmt.signed_yuan(int(last["profit"]))], ["声誉 Reputation", "%d" % int(float(c.get("rep", 0)))], ["累计营收", Fmt.yuan(int(c.get("revenue_total", 0)))], ["公司权益", Fmt.yuan(BusinessManager.equity())]]:
		g.add_child(UIKit.label(String(pair[0]), 15, UIKit.DIM))
		g.add_child(UIKit.label(String(pair[1]), 16, UIKit.BAD if (pair[0] == "公司账户" and cash < 0) else UIKit.TEXT))
	if cash < 0:
		box.add_child(UIKit.label("⚠ 公司账户透支！连续 %d 天后破产（已 %d 天）。赶紧注资或裁员。" % [int(BusinessManager.cfg().get("bankrupt_days", 14)), int(c.get("neg_days", 0))], 15, UIKit.BAD, HORIZONTAL_ALIGNMENT_LEFT, true))
	var hist: Array = c.get("history", [])
	if hist.size() >= 2:
		var rev: Array = []
		var prof: Array = []
		for hh in hist:
			rev.append(float(hh["revenue"]))
			prof.append(float(hh["profit"]))
		var chart := ChartView.new()
		chart.custom_minimum_size = Vector2(260, 120)
		chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chart.set_series([{"values": rev, "color": UIKit.CYAN}, {"values": prof, "color": UIKit.YELLOW}], "元", "近 %d 天 · 青 = 营收，黄 = 利润" % hist.size())
		box.add_child(chart)
	box.add_child(UIKit.sep())
	box.add_child(UIKit.label("团队", 17, UIKit.CYAN))
	for r in BusinessManager.cfg().get("roles", []):
		var h := UIKit.hbox(6)
		box.add_child(h)
		var n := int(c["employees"].get(String(r["id"]), 0))
		var l := UIKit.label("%s × %d（日薪 %s，%s）" % [String(r["name"]), n, Fmt.yuan(int(r["salary"])), String(r.get("desc", ""))], 15, UIKit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		h.add_child(UIKit.small_button("招 1 人", func():
			Events.say(BusinessManager.hire(String(r["id"]), 1), "info")
			refresh.call()))
		h.add_child(UIKit.small_button("裁 1 人", func():
			Events.say(BusinessManager.fire_employee(String(r["id"])), "info")
			refresh.call()))
	box.add_child(UIKit.sep())
	box.add_child(UIKit.label("项目（同时最多 3 个；按产能推进，逾期客户只付 25%）", 17, UIKit.CYAN, HORIZONTAL_ALIGNMENT_LEFT, true))
	for p in c.get("projects", []):
		var done_pct := 1.0 - float(p["work_left"]) / maxf(0.01, float(p["work"]))
		box.add_child(UIKit.label("▶ %s（%s）进度 %d%% · 剩 %d 天 · 报酬 %s" % [String(p["name"]), String(p["client"]), int(done_pct * 100), int(p["days_left"]), Fmt.yuan(int(p["value"]))], 15, UIKit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true))
	var offers: Array = c.get("offers", [])
	for i in offers.size():
		var o: Dictionary = offers[i]
		var h2 := UIKit.hbox(6)
		box.add_child(h2)
		var need_days := float(o["work"]) / maxf(0.1, BusinessManager.capacity())
		var l2 := UIKit.label("待接：%s · %s · 工作量 %d（按当前产能约 %.0f 天）· 期限 %d 天 · %s" % [String(o["name"]), String(o["client"]), int(o["work"]), need_days, int(o["days"]), Fmt.yuan(int(o["value"]))], 14, UIKit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true)
		l2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h2.add_child(l2)
		h2.add_child(UIKit.small_button("接单", func():
			Events.say(BusinessManager.accept_offer(i), "info")
			refresh.call()))
	box.add_child(UIKit.sep())
	box.add_child(UIKit.label("经营设置", 17, UIKit.CYAN))
	var row := UIKit.hbox(6)
	box.add_child(row)
	row.add_child(UIKit.label("市场预算/天 %s" % Fmt.yuan(int(c.get("marketing", 0))), 15, UIKit.TEXT))
	for m in [0, 2000, 8000, 20000]:
		row.add_child(UIKit.small_button(Fmt.yuan(m), func():
			BusinessManager.set_marketing(m)
			refresh.call()))
	var row2 := UIKit.hbox(6)
	box.add_child(row2)
	row2.add_child(UIKit.label("利润分红比例 %d%%（进你的银行卡，算被动收入）" % int(float(c.get("dividend", 0.2)) * 100), 15, UIKit.TEXT))
	for d in [0.0, 0.2, 0.5, 0.8]:
		row2.add_child(UIKit.small_button("%d%%" % int(d * 100), func():
			BusinessManager.set_dividend(d)
			refresh.call()))
	var eq: Array = BusinessManager.cfg().get("equipment", [])
	var lvl := int(c.get("equipment", 0))
	var row3 := UIKit.hbox(6)
	box.add_child(row3)
	row3.add_child(UIKit.label("设备：%s" % String(eq[lvl]["name"]), 15, UIKit.TEXT))
	if lvl + 1 < eq.size():
		row3.add_child(UIKit.small_button("升级为%s（%s）" % [String(eq[lvl + 1]["name"]), Fmt.yuan(int(eq[lvl + 1]["cost"]))], func():
			Events.say(BusinessManager.buy_equipment(), "info")
			refresh.call()))
	var row4 := UIKit.hbox(6)
	box.add_child(row4)
	for amt in [20000, 100000, 500000]:
		row4.add_child(UIKit.small_button("注资 %s" % Fmt.yuan(amt), func():
			Events.say(BusinessManager.inject(amt), "info")
			refresh.call()))
	var row5 := UIKit.hbox(6)
	box.add_child(row5)
	for amt in [20000, 100000, 500000]:
		row5.add_child(UIKit.small_button("提取 %s" % Fmt.yuan(amt), func():
			Events.say(BusinessManager.withdraw(amt), "info")
			refresh.call()))
	box.add_child(UIKit.label("到霓虹广场「创业孵化中心」可以亲自管理公司（管理决策小游戏，当天产能最多 +35%）。", 14, UIKit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))


static func _found_page(box: VBoxContainer, refresh: Callable) -> void:
	box.add_child(UIKit.label("自己当老板", 20, UIKit.YELLOW))
	box.add_child(UIKit.label("条件：管理技能 Lv.5 + 现金与存款合计 ¥100,000。注册费 %s（和周老板关系 50 以上可减 30%%），另需注入启动资金。" % Fmt.yuan(BusinessManager.found_cost()), 15, UIKit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true))
	var chk := BusinessManager.can_found()
	if not bool(chk["ok"]):
		box.add_child(UIKit.label(String(chk["reason"]), 15, UIKit.WARN, HORIZONTAL_ALIGNMENT_LEFT, true))
		if BusinessManager.bankruptcies > 0:
			box.add_child(UIKit.label("你曾经破产过 %d 次。失败是创业者的学费。" % BusinessManager.bankruptcies, 14, UIKit.DIM))
		return
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "公司名称，例如：霓虹工作室"
	name_edit.text = "霓虹工作室"
	name_edit.max_length = 12
	box.add_child(name_edit)
	var row := UIKit.hbox(6)
	box.add_child(row)
	for cap in [30000, 50000, 100000]:
		row.add_child(UIKit.button("注册并注资 %s" % Fmt.yuan(cap), func():
			var msg := BusinessManager.found(name_edit.text.strip_edges(), cap)
			Events.say(msg, "good" if msg.begins_with("公司注册成功") else "warn")
			refresh.call()))
