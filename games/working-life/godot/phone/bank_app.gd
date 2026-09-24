class_name BankApp
extends RefCounted
## 手机银行：现金、银行存款、总资产、本月收入 / 支出（按类别）、本月现金流、流水；存款与取款。


static func build(box: VBoxContainer, refresh: Callable) -> void:
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 30)
	box.add_child(g)
	for pair in [["现金", EconomyManager.cash], ["银行存款", EconomyManager.bank], ["投资市值", int(InvestmentManager.market_value())], ["公司权益", BusinessManager.equity()], ["住房押金", HousingManager.deposit_held()], ["净资产", EconomyManager.networth()]]:
		g.add_child(UIKit.label(String(pair[0]), 16, UIKit.DIM))
		g.add_child(UIKit.label(Fmt.yuan(float(pair[1])), 18, UIKit.YELLOW if pair[0] == "净资产" else UIKit.TEXT))
	box.add_child(UIKit.label("存款年化利率 %.2f%%（按日计息，计入被动收入）" % (EconomyManager.deposit_rate() * 100.0), 14, UIKit.DIM))
	var row := UIKit.hbox(6)
	box.add_child(row)
	for amt in [100, 1000, 10000]:
		row.add_child(UIKit.small_button("存 %s" % Fmt.yuan(amt), _dep.bind(amt, refresh)))
	row.add_child(UIKit.small_button("现金全部存入", func(): _dep(EconomyManager.cash, refresh)))
	var row2 := UIKit.hbox(6)
	box.add_child(row2)
	for amt in [100, 1000, 10000]:
		row2.add_child(UIKit.small_button("取 %s" % Fmt.yuan(amt), _wd.bind(amt, refresh)))
	box.add_child(UIKit.sep())
	var key := TimeManager.month_key()
	var inc := EconomyManager.month_total("income", key)
	var exp := EconomyManager.month_total("expense", key)
	box.add_child(UIKit.label("%s 本月：收入 %s · 支出 %s · 现金流 %s" % [key, Fmt.yuan(inc), Fmt.yuan(exp), Fmt.signed_yuan(inc - exp)], 16, UIKit.CYAN, HORIZONTAL_ALIGNMENT_LEFT, true))
	var st := EconomyManager.month_stats(key)
	for kind in ["income", "expense"]:
		var d: Dictionary = st.get(kind, {})
		var parts: Array = []
		for c in d:
			parts.append("%s %s" % [c, Fmt.yuan(int(d[c]))])
		box.add_child(UIKit.label(("收入：" if kind == "income" else "支出：") + ("、".join(parts) if not parts.is_empty() else "无"), 14, UIKit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true))
	box.add_child(UIKit.label("近 30 天被动收入折合每月 %s" % Fmt.yuan(EconomyManager.passive_income_monthly()), 14, UIKit.DIM))
	box.add_child(UIKit.sep())
	box.add_child(UIKit.label("最近流水", 16, UIKit.CYAN))
	var led := EconomyManager.ledger
	for i in range(led.size() - 1, maxi(-1, led.size() - 16), -1):
		var e: Dictionary = led[i]
		var amt2 := int(e.get("amount", 0))
		var txt := "第%d天 %s  %s  %s" % [int(e.get("day", 0)), String(e.get("time", "")), String(e.get("note", "")), (Fmt.signed_yuan(amt2) if amt2 != 0 else "")]
		box.add_child(UIKit.label(txt, 14, UIKit.GOOD if amt2 > 0 else (UIKit.TEXT if amt2 == 0 else UIKit.WARN), HORIZONTAL_ALIGNMENT_LEFT, true))


static func _dep(amt: int, refresh: Callable) -> void:
	if EconomyManager.deposit(mini(amt, EconomyManager.cash)):
		Events.say("存入 %s" % Fmt.yuan(mini(amt, EconomyManager.cash)), "good")
	else:
		Events.say("现金不足", "warn")
	refresh.call()


static func _wd(amt: int, refresh: Callable) -> void:
	if EconomyManager.withdraw(amt):
		Events.say("取出 %s" % Fmt.yuan(amt), "good")
	else:
		Events.say("存款不足", "warn")
	refresh.call()
