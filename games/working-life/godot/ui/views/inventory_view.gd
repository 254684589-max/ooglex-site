class_name InventoryView
extends RefCounted
## 背包（I 键）：消耗品与书可以直接使用；在家时可以把东西放进 / 取出储物柜。耐用品与服装单独列出。


static func build(box: VBoxContainer, refresh: Callable, at_home := false) -> void:
	box.add_child(UIKit.label("背包 %d / %d 格" % [PlayerManager.used_slots(), PlayerManager.BACKPACK_SLOTS], 18, UIKit.CYAN))
	if PlayerManager.backpack.is_empty():
		box.add_child(UIKit.label("空空如也。便利店、超市可以买吃的。", 15, UIKit.DIM))
	for id in PlayerManager.backpack.keys():
		var it := DataDB.item(String(id))
		var card := UIKit.card(UIKit.CYAN)
		box.add_child(card)
		var h := UIKit.hbox(8)
		card.add_child(h)
		var v := UIKit.vbox(1)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(v)
		v.add_child(UIKit.label("%s × %d" % [String(it.get("name", id)), PlayerManager.item_count(String(id))], 17, UIKit.TEXT))
		v.add_child(UIKit.label(String(it.get("desc", "")), 13, UIKit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
		var use := String(it.get("use", ""))
		if use in ["consume", "read"]:
			h.add_child(UIKit.small_button("使用" if use == "consume" else "阅读", func():
				var msg := PlayerManager.use_item(String(id))
				if msg != "":
					Events.say(msg, "good" if msg.begins_with("使用") or msg.begins_with("读完") else "warn")
				refresh.call()))
		if at_home:
			h.add_child(UIKit.small_button("放进储物柜", func():
				PlayerManager.store_item(String(id), 1)
				refresh.call()))
	if at_home:
		box.add_child(UIKit.sep())
		box.add_child(UIKit.label("家中储物柜 %d / %d" % [PlayerManager.storage_used(), HousingManager.storage_capacity()], 18, UIKit.CYAN))
		for id in PlayerManager.storage.keys():
			var h2 := UIKit.hbox(8)
			box.add_child(h2)
			var l := UIKit.label("%s × %d" % [DataDB.item_name(String(id)), int(PlayerManager.storage[id])], 16, UIKit.TEXT)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h2.add_child(l)
			h2.add_child(UIKit.small_button("取出", func():
				PlayerManager.take_item(String(id), 1)
				refresh.call()))
	box.add_child(UIKit.sep())
	var owned: Array = []
	for id in PlayerManager.owned:
		owned.append(DataDB.item_name(String(id)) + ("（穿着）" if String(id) == PlayerManager.outfit else ""))
	if PlayerManager.gym_member():
		owned.append("健身月卡（到第 %d 天）" % PlayerManager.gym_until_day)
	box.add_child(UIKit.label("拥有：" + ("、".join(owned) if not owned.is_empty() else "只有一个行李箱和一部旧手机"), 15, UIKit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
