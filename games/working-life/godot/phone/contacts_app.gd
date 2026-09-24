class_name ContactsApp
extends RefCounted
## 联系人：认识的 NPC、关系、身份、此刻大概在哪、已经解锁的帮助。


static func build(box: VBoxContainer) -> void:
	box.add_child(UIKit.label("关系达到 20 成为熟人、50 成为朋友。聊天、帮忙、送礼都能增进关系。", 14, UIKit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
	for id in DataDB.ids("npcs"):
		var d := DataDB.npc(id)
		var known := NPCManager.met.has(id)
		var card := UIKit.card(UIKit.GOOD if NPCManager.relation(id) >= 50 else UIKit.CYAN)
		box.add_child(card)
		var v := UIKit.vbox(2)
		card.add_child(v)
		var h := UIKit.hbox(8)
		v.add_child(h)
		h.add_child(UIKit.label(String(d.get("name", id)) if known else "？？？（还没见过）", 17, UIKit.TEXT))
		h.add_child(UIKit.spacer())
		h.add_child(UIKit.label("%s %d" % [NPCManager.tier_name(id), NPCManager.relation(id)], 16, UIKit.YELLOW))
		v.add_child(UIKit.label("%s · 现在：%s" % [String(d.get("role", "")), NPCManager.where_text(id)], 14, UIKit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
		for p in d.get("perks", []):
			var ok := NPCManager.relation(id) >= int(p.get("min_rel", 999))
			v.add_child(UIKit.label("%s 关系 %d：%s" % ["✓" if ok else "○", int(p.get("min_rel", 0)), String(p.get("text", ""))], 13, UIKit.GOOD if ok else UIKit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
