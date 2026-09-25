class_name GigApp
extends RefCounted
## 零工 APP：外卖骑手、网约车司机、主播。上班之外的时间也能接单，多挣一份钱。


static func build(box: VBoxContainer, refresh: Callable, close_phone: Callable) -> void:
	box.add_child(UIKit.label("下班以后、没找到工作的时候，都可以接零工。同一时间只能接一单；地图箭头会带你去取餐点 / 上车点 / 目的地。", 14, UIKit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
	if GigManager.has_order():
		var card := UIKit.card(UIKit.YELLOW)
		box.add_child(card)
		var v := UIKit.vbox(2)
		card.add_child(v)
		v.add_child(UIKit.label("进行中：" + GigManager.status_text(), 16, UIKit.YELLOW, HORIZONTAL_ALIGNMENT_LEFT, true))
		v.add_child(UIKit.small_button("取消订单（差评）", func():
			Events.say(GigManager.cancel(), "warn")
			refresh.call()))
	_card(box, "delivery", "闪送外卖 · 骑手", "到餐馆取餐，限时送到住处或写字楼；越早送到评分越高，下雨天多 ¥4 补贴。每单体力 -4。", refresh, close_phone)
	_card(box, "ride", "新澜出行 · 网约车司机", "开自己的车到上车点接乘客，送到目的地；开得稳（别撞）、到得快，评分高。每单体力 -3。", refresh, close_phone)
	# 直播
	var card2 := UIKit.card(UIKit.MAGENTA)
	box.add_child(card2)
	var v2 := UIKit.vbox(2)
	card2.add_child(v2)
	var h2 := UIKit.hbox(8)
	v2.add_child(h2)
	h2.add_child(UIKit.label("霓虹直播 · 主播", 18, UIKit.TEXT))
	h2.add_child(UIKit.spacer())
	h2.add_child(UIKit.label("粉丝 %d" % GigManager.followers, 16, UIKit.MAGENTA))
	v2.add_child(UIKit.label("在家开播 2 小时：涨粉看口才、心情和家里的装修，收入看粉丝数。已播 %d 场，累计收入 %s。" % [GigManager.done_count("stream"), Fmt.yuan(int(GigManager.stats["stream"]["earned"]))], 14, UIKit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	v2.add_child(row)
	for s in GigManager.STREAMS:
		var cid := String(s[0])
		var why := GigManager.stream_block(cid)
		var b := UIKit.small_button("开播：%s" % String(s[1]) if why == "" else "%s（%s）" % [String(s[1]), why], func():
			Events.say(GigManager.stream(cid), "good")
			refresh.call())
		b.disabled = why != ""
		row.add_child(b)


static func _card(box: VBoxContainer, gig: String, title: String, desc: String, refresh: Callable, close_phone: Callable) -> void:
	var card := UIKit.card(UIKit.CYAN)
	box.add_child(card)
	var v := UIKit.vbox(2)
	card.add_child(v)
	var h := UIKit.hbox(8)
	v.add_child(h)
	h.add_child(UIKit.label(title, 18, UIKit.TEXT))
	h.add_child(UIKit.spacer())
	h.add_child(UIKit.label("%s · ★%.1f" % [GigManager.level_name(gig), GigManager.rating(gig)], 15, UIKit.YELLOW))
	v.add_child(UIKit.label(desc, 14, UIKit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
	var lv := GigManager.level(gig)
	var nxt := ""
	if lv + 1 < GigManager.LEVELS.size():
		var L: Array = GigManager.LEVELS[lv + 1]
		nxt = " · 升「%s」需 %d 单、平均 %.1f 星（收入 ×%.1f）" % [String(L[3]), int(L[0]), float(L[1]), float(L[2])]
	v.add_child(UIKit.label("已完成 %d 单，累计收入 %s%s" % [GigManager.done_count(gig), Fmt.yuan(int(GigManager.stats[gig]["earned"])), nxt], 14, UIKit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
	var why := GigManager.accept_block(gig)
	var b := UIKit.small_button("接单" if why == "" else why, func():
		var msg := GigManager.accept(gig)
		Events.say(msg, "info")
		if GigManager.has_order():
			close_phone.call()
		else:
			refresh.call())
	b.disabled = why != ""
	v.add_child(b)
