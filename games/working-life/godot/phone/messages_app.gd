class_name MessagesApp
extends RefCounted
## 消息：房东、公司、银行、NPC 发来的短信（最近 40 条）。


static func build(box: VBoxContainer) -> void:
	var msgs: Array = GameManager.get_value("messages", [])
	if msgs.is_empty():
		box.add_child(UIKit.label("还没有消息。", 16, UIKit.DIM))
		return
	for i in range(msgs.size() - 1, -1, -1):
		var m: Dictionary = msgs[i]
		var card := UIKit.card(UIKit.MAGENTA)
		box.add_child(card)
		var v := UIKit.vbox(2)
		card.add_child(v)
		v.add_child(UIKit.label("%s · 第 %d 天 %s" % [String(m.get("from", "")), int(m.get("day", 1)), String(m.get("time", ""))], 14, UIKit.CYAN))
		v.add_child(UIKit.label(String(m.get("text", "")), 16, UIKit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true))
