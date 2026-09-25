class_name RomanceApp
extends RefCounted
## 约会 APP：可以约会的人（在哪儿、关系、好感、阶段），一键约 TA 出去。


static func build(box: VBoxContainer, close_phone: Callable) -> void:
	if RomanceManager.partner != "":
		var pid := RomanceManager.partner
		box.add_child(UIKit.label("%s：%s（好感 %d）" % [RomanceManager.stage_text(pid), DataDB.npc_name(pid), RomanceManager.affection_of(pid)], 18, UIKit.MAGENTA))
		var gap := TimeManager.day - int(RomanceManager.last_date.get(pid, RomanceManager.partner_since))
		box.add_child(UIKit.label("上次约会是 %d 天前。太久不约会好感会下降。" % gap, 14, UIKit.DIM))
		box.add_child(UIKit.sep())
	box.add_child(UIKit.label("关系到了就可以约 TA 出去：咖啡馆、吃饭、看电影、公园、夜景、高级餐厅，或者来你家。聊天回答得好、选 TA 喜欢的地方，好感涨得快；好感 65 以上可以表白。", 14, UIKit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
	var shown := 0
	for id in RomanceManager.candidates():
		if not NPCManager.met.has(id) and NPCManager.relation(id) == 0:
			continue
		shown += 1
		var card := UIKit.card(UIKit.MAGENTA)
		box.add_child(card)
		var v := UIKit.vbox(2)
		card.add_child(v)
		var h := UIKit.hbox(8)
		v.add_child(h)
		h.add_child(UIKit.label(DataDB.npc_name(id), 18, UIKit.TEXT))
		h.add_child(UIKit.label(String(DataDB.npc(id).get("role", "")), 14, UIKit.DIM))
		h.add_child(UIKit.spacer())
		h.add_child(UIKit.label(RomanceManager.stage_text(id), 15, UIKit.MAGENTA))
		v.add_child(UIKit.label("关系 %d · 好感 %d / 100 · 现在在%s" % [NPCManager.relation(id), RomanceManager.affection_of(id), NPCManager.where_text(id)], 14, UIKit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
		var why := RomanceManager.date_block(id)
		var b := UIKit.small_button("约 TA 出去" if why == "" else why, func():
			close_phone.call()
			Events.panel_requested.emit("date", {"npc": id}))
		b.disabled = why != ""
		v.add_child(b)
	if shown == 0:
		box.add_child(UIKit.label("你在新澜市还没认识可以约会的人。多去咖啡馆、医院、芳姐小馆、星河科技附近走走，先交个朋友吧。", 15, UIKit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true))
