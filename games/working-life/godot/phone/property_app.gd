class_name PropertyApp
extends RefCounted
## 房产 APP：我的房产（市价、贷款、月供、自住 / 出租、提前还款、卖房）、买房（全款或贷款）、装修（每套房九个位置的家具）。

## 正在装修的房子（""：主页）
static var decor_home := ""


static func build(box: VBoxContainer, refresh: Callable) -> void:
	if decor_home != "" and HousingManager.is_owned(decor_home):
		_decor_page(box, refresh)
		return
	decor_home = ""
	box.add_child(UIKit.label("可用资金：现金 %s + 银行卡 %s" % [Fmt.yuan(EconomyManager.cash), Fmt.yuan(EconomyManager.bank)], 15, UIKit.YELLOW))
	if not HousingManager.owned.is_empty():
		box.add_child(UIKit.label("我的房产", 18, UIKit.CYAN))
		for id in HousingManager.owned:
			_owned_card(box, String(id), refresh)
		box.add_child(UIKit.sep())
	box.add_child(UIKit.label("新澜房产 · 买房", 18, UIKit.CYAN))
	box.add_child(UIKit.label("贷款：首付 30%%，%d 期（10 年）等额本息，月利率 0.35%%，需要有工作或被动收入；另付 1.5%% 税费。自住不用交房租。" % HousingManager.LOAN_MONTHS, 14, UIKit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
	for id in DataDB.ids("housing"):
		if HousingManager.price_of(id) <= 0 or HousingManager.is_owned(id):
			continue
		_listing_card(box, id, refresh)


static func _owned_card(box: VBoxContainer, id: String, refresh: Callable) -> void:
	var d := HousingManager.data(id)
	var o: Dictionary = HousingManager.owned[id]
	var card := UIKit.card(UIKit.GOOD)
	box.add_child(card)
	var v := UIKit.vbox(2)
	card.add_child(v)
	var h := UIKit.hbox(8)
	v.add_child(h)
	h.add_child(UIKit.label("%s · %s" % [String(d["name"]), DataDB.location_name(String(d["location"]))], 18, UIKit.TEXT))
	h.add_child(UIKit.spacer())
	var status := "自住" if HousingManager.current == id else ("出租中" if bool(o.get("rented_out", false)) else "空置")
	h.add_child(UIKit.label(status, 15, UIKit.GOOD if status != "空置" else UIKit.DIM))
	var gain := int(o["value"]) - int(o["price"])
	v.add_child(UIKit.label("市价 %s（买入 %s，%s%s）" % [Fmt.yuan(int(o["value"])), Fmt.yuan(int(o["price"])), "涨" if gain >= 0 else "跌", Fmt.yuan(absi(gain))], 15, UIKit.TEXT))
	var loan := float(o.get("loan", 0.0))
	if loan > 0.5:
		v.add_child(UIKit.label("剩余贷款 %s · 月供 %s · 还剩 %d 期%s" % [Fmt.yuan(int(ceil(loan))), Fmt.yuan(int(o["payment"])), int(o["months_left"]), ("· 欠供 %s！" % Fmt.yuan(int(o["arrears"]))) if int(o.get("arrears", 0)) > 0 else ""], 14, UIKit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
	else:
		v.add_child(UIKit.label("无贷款 · 出租每月可收 %s" % Fmt.yuan(HousingManager.lease_income(id)), 14, UIKit.DIM))
	var furn := HousingManager.furniture_of(id)
	v.add_child(UIKit.label("装修：%d / 9 件家具 · 心情 %+.1f/天 · 睡眠 +%d%% · 体面度 %+.1f" % [furn.size(), HousingManager.decor_sum(id, "mood"), int(HousingManager.decor_sum(id, "sleep") * 100), HousingManager.decor_sum(id, "prestige")], 14, UIKit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	v.add_child(row)
	if HousingManager.current != id:
		row.add_child(UIKit.small_button("搬进去住", func():
			Events.say(HousingManager.move_into_owned(id), "info")
			refresh.call()))
		row.add_child(UIKit.small_button("收回" if bool(o.get("rented_out", false)) else "出租（%s/月）" % Fmt.yuan(HousingManager.lease_income(id)), func():
			Events.say(HousingManager.set_rented_out(id, not bool(o.get("rented_out", false))), "info")
			refresh.call()))
	row.add_child(UIKit.small_button("装修", func():
		decor_home = id
		refresh.call()))
	if loan > 0.5:
		row.add_child(UIKit.small_button("提前还 ¥100,000", func():
			Events.say(HousingManager.prepay(id, 100000), "info")
			refresh.call()))
		row.add_child(UIKit.small_button("全部还清（%s）" % Fmt.yuan(int(ceil(loan))), func():
			Events.say(HousingManager.prepay(id, 0), "info")
			refresh.call()))
	row.add_child(UIKit.small_button("卖掉", func():
		Events.say(HousingManager.sell_home(id), "info")
		refresh.call()))


static func _listing_card(box: VBoxContainer, id: String, refresh: Callable) -> void:
	var d := HousingManager.data(id)
	var price := HousingManager.price_of(id)
	var card := UIKit.card(UIKit.CYAN)
	box.add_child(card)
	var v := UIKit.vbox(2)
	card.add_child(v)
	var h := UIKit.hbox(8)
	v.add_child(h)
	h.add_child(UIKit.label("Lv.%d %s · %s" % [int(d["level"]), String(d["name"]), DataDB.location_name(String(d["location"]))], 18, UIKit.TEXT))
	h.add_child(UIKit.spacer())
	h.add_child(UIKit.label(Fmt.yuan(price), 17, UIKit.YELLOW))
	var loan_cost := HousingManager.purchase_cost(id, true)
	var full_cost := HousingManager.purchase_cost(id, false)
	var pay := HousingManager.mortgage_payment(float(price - int(loan_cost[0])), HousingManager.LOAN_MONTHS)
	v.add_child(UIKit.label("贷款：首付 %s + 税费 %s，月供 %s · 全款：%s + 税费 %s" % [Fmt.yuan(int(loan_cost[0])), Fmt.yuan(int(loan_cost[1])), Fmt.yuan(pay), Fmt.yuan(int(full_cost[0])), Fmt.yuan(int(full_cost[1]))], 14, UIKit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
	v.add_child(UIKit.label("对比：租金 %s/月 · 买下后出租可收 %s/月 · 住自己的房子体面度 +2，还能装修" % [Fmt.yuan(HousingManager.rent_of(id)), Fmt.yuan(HousingManager.lease_income(id))], 14, UIKit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
	var row := UIKit.hbox(6)
	v.add_child(row)
	var need_loan: int = loan_cost[0] + loan_cost[1]
	var need_full: int = full_cost[0] + full_cost[1]
	var b1 := UIKit.small_button("贷款买（需 %s）" % Fmt.yuan(need_loan), func():
		Events.say(HousingManager.buy_home(id, true), "info")
		refresh.call())
	b1.disabled = not EconomyManager.can_afford(need_loan)
	row.add_child(b1)
	var b2 := UIKit.small_button("全款买（需 %s）" % Fmt.yuan(need_full), func():
		Events.say(HousingManager.buy_home(id, false), "info")
		refresh.call())
	b2.disabled = not EconomyManager.can_afford(need_full)
	row.add_child(b2)
	if not EconomyManager.can_afford(need_loan):
		v.add_child(UIKit.label("首付还差 %s" % Fmt.yuan(need_loan - EconomyManager.liquid()), 14, UIKit.BAD))


static func _decor_page(box: VBoxContainer, refresh: Callable) -> void:
	var id := decor_home
	var d := HousingManager.data(id)
	box.add_child(UIKit.small_button("← 返回房产", func():
		decor_home = ""
		refresh.call()))
	box.add_child(UIKit.label("装修：%s（%s）" % [String(d["name"]), DataDB.location_name(String(d["location"]))], 18, UIKit.CYAN))
	box.add_child(UIKit.label("可用资金 %s · 家具当场送货安装；同一位置换新的，旧的按三成回收。加成上限：心情 +%d/天、睡眠 +%d%%、体面度 +%d。" % [Fmt.yuan(EconomyManager.liquid()), int(HousingManager.DECOR_MOOD_CAP), int(HousingManager.DECOR_SLEEP_CAP * 100), int(HousingManager.DECOR_PRESTIGE_CAP)], 14, UIKit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
	var slots: Dictionary = DataDB.furniture.get("_meta", {}).get("slots", {})
	var furn := HousingManager.furniture_of(id)
	for slot in slots:
		var card := UIKit.card(UIKit.CYAN)
		box.add_child(card)
		var v := UIKit.vbox(2)
		card.add_child(v)
		var cur := String(furn.get(slot, ""))
		var cur_name := String(DataDB.furniture.get(cur, {}).get("name", "空着"))
		v.add_child(UIKit.label("%s：%s" % [String(slots[slot]), cur_name], 16, UIKit.TEXT))
		for item_id in DataDB.ids("furniture"):
			var it: Dictionary = DataDB.furniture[item_id]
			if String(it["slot"]) != slot:
				continue
			var fx: Array = []
			if float(it.get("mood", 0)) > 0:
				fx.append("心情 +%s" % str(it["mood"]))
			if float(it.get("sleep", 0)) > 0:
				fx.append("睡眠 +%d%%" % int(float(it["sleep"]) * 100))
			if float(it.get("prestige", 0)) > 0:
				fx.append("体面 +%s" % str(it["prestige"]))
			match String(it.get("use", "")):
				"rest":
					fx.append("可躺下休息")
				"tv":
					fx.append("可看电视解压")
				"read":
					fx.append("可看书学习")
				"run":
					fx.append("可在家跑步")
			var mine: bool = cur == String(item_id)
			var b := UIKit.small_button("%s%s · %s · %s" % ["✓ " if mine else "", String(it["name"]), Fmt.yuan(int(it["price"])), " ".join(fx)], func():
				Events.say(HousingManager.buy_furniture(id, item_id), "info")
				refresh.call())
			b.disabled = mine or not EconomyManager.can_afford(int(it["price"]))
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			v.add_child(b)
