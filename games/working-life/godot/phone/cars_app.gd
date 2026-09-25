class_name CarsApp
extends RefCounted
## 汽车 APP：我的车（位置、里程、代驾送车、转卖）与购车（四款车型，选车漆，全款购买）。


static func build(box: VBoxContainer, refresh: Callable) -> void:
	var p := GameManager.player
	if VehicleManager.has_car():
		box.add_child(UIKit.label("我的车", 18, UIKit.CYAN))
		for c in VehicleManager.owned:
			var m := VehicleManager.model(String(c["model"]))
			var card := UIKit.card(UIKit.GOOD)
			box.add_child(card)
			var v := UIKit.vbox(2)
			card.add_child(v)
			var h := UIKit.hbox(8)
			v.add_child(h)
			h.add_child(UIKit.label(String(m.get("name", "")), 18, UIKit.TEXT))
			h.add_child(UIKit.spacer())
			var uid := String(c["uid"])
			var n := VehicleManager.node(uid)
			var where := "正在驾驶" if VehicleManager.driving == uid else ""
			if where == "" and n != null and p != null:
				where = "停在 %d 米外" % int(n.global_position.distance_to(p.global_position))
			h.add_child(UIKit.label(where, 15, UIKit.DIM))
			v.add_child(UIKit.label("累计里程 %.1f 公里 · 现在转卖可得 %s" % [float(c.get("km", 0.0)), Fmt.yuan(VehicleManager._resale(c))], 14, UIKit.DIM))
			var row := UIKit.hbox(8)
			v.add_child(row)
			if VehicleManager.driving != uid:
				row.add_child(UIKit.small_button("代驾送到身边（%s）" % Fmt.yuan(VehicleManager.VALET_FEE), func():
					Events.say(VehicleManager.valet(uid), "info")
					refresh.call()))
				row.add_child(UIKit.small_button("转卖", func():
					Events.say(VehicleManager.sell(uid), "info")
					refresh.call()))
		box.add_child(UIKit.label("每月 1 日扣保险、停车、保养共 %s；油费按里程在下车时结算。" % Fmt.yuan(VehicleManager.monthly_cost()), 14, UIKit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
		box.add_child(UIKit.sep())
	box.add_child(UIKit.label("新澜汽车城 · 全款购车，提车后直接送到你身边的路边", 18, UIKit.CYAN, HORIZONTAL_ALIGNMENT_LEFT, true))
	box.add_child(UIKit.label("可用资金：现金 %s + 银行卡 %s" % [Fmt.yuan(EconomyManager.cash), Fmt.yuan(EconomyManager.bank)], 15, UIKit.YELLOW))
	for id in DataDB.ids("vehicles"):
		var m: Dictionary = DataDB.vehicles[id]
		var card := UIKit.card(UIKit.CYAN)
		box.add_child(card)
		var v := UIKit.vbox(2)
		card.add_child(v)
		var h := UIKit.hbox(8)
		v.add_child(h)
		h.add_child(UIKit.label(String(m["name"]), 18, UIKit.TEXT))
		h.add_child(UIKit.spacer())
		h.add_child(UIKit.label(Fmt.yuan(int(m["price"])), 17, UIKit.YELLOW))
		v.add_child(UIKit.label("最高 %d km/h · 体面度 %+d · 月费 %s · 油费 %s/公里" % [int(float(m["top_speed"]) * 3.6), int(m["prestige"]), Fmt.yuan(int(m["monthly"])), "¥%.1f" % float(m["fuel_per_km"])], 14, UIKit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
		v.add_child(UIKit.label(String(m.get("desc", "")), 14, UIKit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
		var row := UIKit.hbox(6)
		v.add_child(row)
		var paints: Array = m.get("paints", [])
		for i in paints.size():
			var b := UIKit.small_button("■ 购买", func():
				Events.say(VehicleManager.buy(id, i), "info")
				refresh.call())
			b.add_theme_color_override("font_color", Mats.hex(String(paints[i]), Color.WHITE))
			b.add_theme_color_override("font_hover_color", Mats.hex(String(paints[i]), Color.WHITE))
			b.disabled = not EconomyManager.can_afford(int(m["price"]))
			b.tooltip_text = "购买这个颜色的%s" % String(m["name"])
			row.add_child(b)
		if not EconomyManager.can_afford(int(m["price"])):
			row.add_child(UIKit.label("还差 %s" % Fmt.yuan(int(m["price"]) - EconomyManager.liquid()), 14, UIKit.BAD))
	box.add_child(UIKit.label("操作：走近车按 E 上车 · W/S 油门、刹车 / 倒车 · A/D 转向 · 空格 手刹 · E 下车。手机：左下摇杆上推加速、下拉刹车、左右转向。", 13, UIKit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
