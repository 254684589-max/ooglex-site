class_name ProfileView
extends RefCounted
## 「人物」页（C 键 / 手机「人物」APP）：属性、职业与晋升条件、人生目标（结局条件）。


static func build(box: VBoxContainer, refresh: Callable) -> void:
	box.add_child(UIKit.label("属性", 18, UIKit.CYAN))
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 24)
	box.add_child(g)
	for id in ["energy", "hunger", "mood", "health", "stress", "reputation"]:
		var v := PlayerManager.get_stat(id)
		g.add_child(UIKit.label("%s  %d / 100" % [PlayerManager.STAT_NAMES[id], int(v)], 16, UIKit.TEXT))
	var eff := PlayerManager.efficiency()
	var notes := PlayerManager.efficiency_notes()
	box.add_child(UIKit.label("工作效率 %d%%%s" % [int(eff * 100), ("（%s）" % "、".join(notes)) if not notes.is_empty() else ""], 15, UIKit.YELLOW if eff < 0.95 else UIKit.GOOD, HORIZONTAL_ALIGNMENT_LEFT, true))
	box.add_child(UIKit.label("住处：%s · 体面度 %+d" % [HousingManager.home_name(), int(HousingManager.prestige())], 15, UIKit.DIM))
	box.add_child(UIKit.sep())
	box.add_child(UIKit.label("职业", 18, UIKit.CYAN))
	if not JobManager.has_job():
		box.add_child(UIKit.label("目前无业。打开「招聘」APP 或去人才市场找工作。", 16, UIKit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
	else:
		var j := JobManager.job()
		var c := JobManager.current
		box.add_child(UIKit.label("%s · %s（第 %d 级）" % [String(j.get("company", "")), JobManager.title(), JobManager.level() + 1], 17, UIKit.TEXT))
		box.add_child(UIKit.label("工资 %s · 上班 %s（%s）· 地点 %s" % [JobManager.pay_text(JobManager.job_id(), JobManager.level()), JobManager.hours_text(JobManager.job_id()), JobManager.workdays_text(JobManager.job_id()), DataDB.location_name(String(j.get("workplace", "")))], 15, UIKit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
		box.add_child(UIKit.label("绩效 %d · 上司评价 %d · 工作经验 %d · 出勤 %d 班 · 旷工 %d 次 · 迟到 %d 次" % [int(JobManager.perf()), int(float(c.get("boss_rel", 50))), int(float(c.get("xp", 0))), int(c.get("shifts_total", 0)), int(c.get("absences", 0)), int(c.get("late_count", 0))], 15, UIKit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true))
		if JobManager.is_monthly():
			box.add_child(UIKit.label("本周已累计工资 %s（周五晚发到银行卡）" % Fmt.yuan(int(c.get("pending_pay", 0))), 15, UIKit.YELLOW))
		var nx := JobManager.next_step()
		if nx.is_empty():
			box.add_child(UIKit.label("已经是这条职业路线的最高职位。", 15, UIKit.GOOD))
		else:
			var miss := JobManager.promotion_missing()
			box.add_child(UIKit.label("下一级：%s（%s）" % [String(nx.get("title", "")), JobManager.pay_text(JobManager.job_id(), JobManager.level() + 1)], 15, UIKit.CYAN))
			box.add_child(UIKit.label(("还差：" + "、".join(miss)) if not miss.is_empty() else "条件已满足，下一个班次表现合格就会升职！", 15, UIKit.WARN if not miss.is_empty() else UIKit.GOOD, HORIZONTAL_ALIGNMENT_LEFT, true))
		var row := UIKit.hbox(8)
		box.add_child(row)
		row.add_child(UIKit.small_button("今天请假", func():
			Events.say(JobManager.take_leave(false), "info")
			refresh.call()))
		row.add_child(UIKit.small_button("辞职", func():
			Events.say(JobManager.quit_job(), "warn")
			refresh.call()))
	if not JobManager.history.is_empty():
		var hs: Array = []
		for h in JobManager.history.slice(-4):
			hs.append("%s（%d 班，%s）" % [String(h.get("title", "")), int(h.get("shifts", 0)), String(h.get("reason", ""))])
		box.add_child(UIKit.label("履历：" + "；".join(hs), 14, UIKit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
	box.add_child(UIKit.sep())
	box.add_child(UIKit.label("人生目标（达成任意一个即可在中央公园观景台迎来结局）", 18, UIKit.CYAN, HORIZONTAL_ALIGNMENT_LEFT, true))
	var got := EndingSystem.achieved()
	for id in DataDB.ids("endings"):
		var e: Dictionary = DataDB.endings[id]
		var ok := got.has(id)
		var seen := GameManager.endings_seen.has(id)
		var card := UIKit.card(Mats.hex(String(e.get("color", "#22e4ff"))))
		box.add_child(card)
		var v := UIKit.vbox(2)
		card.add_child(v)
		v.add_child(UIKit.label("%s %s%s" % ["✓" if ok else "○", String(e.get("title", "")), "（已看过结局）" if seen else ""], 17, UIKit.GOOD if ok else UIKit.TEXT))
		v.add_child(UIKit.label(String(e.get("goal", "")), 14, UIKit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
	box.add_child(UIKit.label("净资产 %s · 近 30 天被动收入折合每月 %s" % [Fmt.yuan(EconomyManager.networth()), Fmt.yuan(EconomyManager.passive_income_monthly())], 15, UIKit.YELLOW, HORIZONTAL_ALIGNMENT_LEFT, true))
