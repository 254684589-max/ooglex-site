class_name HousingApp
extends RefCounted
## 住房 APP：五个等级的房源、租金、押金、睡眠 / 心情 / 体面度 / 储物；签约与退租。


static func build(box: VBoxContainer, refresh: Callable) -> void:
	box.add_child(UIKit.label("当前住处：%s" % HousingManager.home_name(), 18, UIKit.CYAN))
	if HousingManager.is_monthly() and not HousingManager.is_owned(HousingManager.current):
		box.add_child(UIKit.label("月租 %s（每月 1 日自动扣款）· 押金 %s%s" % [Fmt.yuan(HousingManager.rent_of(HousingManager.current)), Fmt.yuan(HousingManager.deposit), ("· 欠租 %s！" % Fmt.yuan(HousingManager.arrears)) if HousingManager.arrears > 0 else ""], 15, UIKit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true))
		box.add_child(UIKit.small_button("退租（押金退回）", func():
			Events.say(HousingManager.move_out(), "info")
			refresh.call()))
	elif HousingManager.has_hotel_room():
		box.add_child(UIKit.label("旅馆房间有效到第 %d 天中午 12:00。" % (int(HousingManager.hotel_until / 1440.0) + 1), 15, UIKit.TEXT))
	box.add_child(UIKit.sep())
	for id in DataDB.ids("housing"):
		var d: Dictionary = DataDB.housing[id]
		var card := UIKit.card(UIKit.CYAN if id != HousingManager.current else UIKit.GOOD)
		box.add_child(card)
		var v := UIKit.vbox(2)
		card.add_child(v)
		var h := UIKit.hbox(8)
		v.add_child(h)
		h.add_child(UIKit.label("Lv.%d %s · %s" % [int(d["level"]), String(d["name"]), DataDB.location_name(String(d["location"]))], 18, UIKit.TEXT))
		h.add_child(UIKit.spacer())
		var per := "/ 晚" if String(d["period"]) == "night" else "/ 月"
		h.add_child(UIKit.label("%s %s" % [Fmt.yuan(HousingManager.rent_of(id)), per], 17, UIKit.YELLOW))
		v.add_child(UIKit.label("睡眠恢复 %d%% · 心情 %+d/天 · 体面度 %+d · 储物 %d 格" % [int(float(d["sleep"]) * 100), int(d["mood"]), int(d["prestige"]), int(d["storage"])], 14, UIKit.DIM))
		v.add_child(UIKit.label(String(d.get("desc", "")), 14, UIKit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
		if String(d["period"]) == "night":
			v.add_child(UIKit.label("到安心旅馆前台办理入住（车站东北）。", 14, UIKit.TEXT))
		elif id == HousingManager.current:
			v.add_child(UIKit.label("✓ 你住在这里%s" % ("（自己的房子）" if HousingManager.is_owned(id) else ""), 15, UIKit.GOOD))
		elif HousingManager.is_owned(id):
			v.add_child(UIKit.label("这是你自己的房子，到「房产」APP 搬进去住", 14, UIKit.GOOD))
		else:
			v.add_child(UIKit.small_button("签约（押金 + 首月 %s）" % Fmt.yuan(HousingManager.rent_of(id) * 2), func():
				Events.say(HousingManager.move_in(id), "info")
				refresh.call()))
