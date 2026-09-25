class_name InvestApp
extends RefCounted
## 投资 APP：五种游戏内虚构资产，价格每天由内部经济模型生成（不是真实行情）。
## 显示价格、日涨跌、近 60 天走势、持仓、平均成本、盈亏；买入 / 卖出。


static func build(box: VBoxContainer, refresh: Callable) -> void:
	box.add_child(UIKit.label("模拟市场 · 游戏内虚构资产 · 每天收盘更新一次（非真实行情）", 14, UIKit.WARN, HORIZONTAL_ALIGNMENT_LEFT, true))
	if not InvestmentManager.unlocked():
		box.add_child(UIKit.label(String(DataDB.meta("assets").get("unlock_text", "")), 16, UIKit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
		return
	var cyc := "经济周期：%s（还剩约 %d 天）" % [InvestmentManager.cycle_name(), InvestmentManager.cycle_days_left] if NPCManager.has_perk("market_tip") else "经济周期：看不透（和投资爱好者老K混熟了他会告诉你）"
	box.add_child(UIKit.label(cyc, 15, UIKit.CYAN))
	box.add_child(UIKit.label("持仓市值 %s · 浮动盈亏 %s · 已实现盈亏 %s · 银行卡可用 %s" % [Fmt.yuan(InvestmentManager.market_value()), Fmt.signed_yuan(InvestmentManager.unrealized()), Fmt.signed_yuan(InvestmentManager.realized), Fmt.yuan(EconomyManager.bank)], 15, UIKit.YELLOW, HORIZONTAL_ALIGNMENT_LEFT, true))
	box.add_child(UIKit.label("买入优先从银行卡扣款，手续费 0.1%。涨跌颜色：红涨绿跌（同时标 +/-）。", 13, UIKit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
	for id in DataDB.ids("assets"):
		var a := InvestmentManager.asset(id)
		var card := UIKit.card(UIKit.PURPLE)
		box.add_child(card)
		var v := UIKit.vbox(3)
		card.add_child(v)
		var h := UIKit.hbox(8)
		v.add_child(h)
		h.add_child(UIKit.label(String(a.get("name", id)), 17, UIKit.TEXT))
		h.add_child(UIKit.spacer())
		var chg := float(InvestmentManager.last_change.get(id, 0.0))
		h.add_child(UIKit.label("%.2f" % InvestmentManager.price(id), 17, UIKit.TEXT))
		h.add_child(UIKit.label(Fmt.pct(chg, 2), 16, UIKit.signed_color(chg)))
		var chart := ChartView.new()
		chart.custom_minimum_size = Vector2(260, 110)
		chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chart.set_series([{"values": InvestmentManager.history.get(id, []), "color": UIKit.CYAN, "width": 1.6}], "元/份", "近 %d 个交易日" % (InvestmentManager.history.get(id, []) as Array).size())
		v.add_child(chart)
		v.add_child(UIKit.label("%s  年化分红/票息 %.1f%%" % [String(a.get("desc", "")), float(a.get("yield", 0)) * 100.0], 13, UIKit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
		var u := InvestmentManager.units(id)
		if u > 0.0:
			var pnl := InvestmentManager.position_pnl(id)
			v.add_child(UIKit.label("持有 %.2f 份 · 成本价 %.2f · 市值 %s · 盈亏 %s" % [u, InvestmentManager.avg_cost(id), Fmt.yuan(InvestmentManager.position_value(id)), Fmt.signed_yuan(pnl)], 14, UIKit.signed_color(pnl), HORIZONTAL_ALIGNMENT_LEFT, true))
		var row := UIKit.hbox(6)
		v.add_child(row)
		for amt in [1000, 10000, 100000]:
			row.add_child(UIKit.small_button("买 %s" % _short(amt), func():
				Events.say(InvestmentManager.buy(id, amt), "info")
				refresh.call()))
		if u > 0.0:
			for f in [0.5, 1.0]:
				row.add_child(UIKit.small_button("卖 %d%%" % int(f * 100), func():
					Events.say(InvestmentManager.sell(id, f), "info")
					refresh.call()))


static func _short(v: int) -> String:
	if v >= 10000:
		return "%d万" % int(v / 10000.0)
	return "%d" % v
