class_name SkillsApp
extends RefCounted
## 技能 APP：六项技能的等级、经验进度，以及提升途径。


static func build(box: VBoxContainer) -> void:
	for id in SkillManager.ids():
		var d: Dictionary = DataDB.skills[id]
		var card := UIKit.card(Mats.hex(String(d.get("color", "#22e4ff"))))
		box.add_child(card)
		var v := UIKit.vbox(3)
		card.add_child(v)
		var h := UIKit.hbox(8)
		v.add_child(h)
		var lvl := SkillManager.level(id)
		h.add_child(UIKit.label("%s %s" % [String(d["name"]), String(d.get("en", ""))], 18, UIKit.TEXT))
		h.add_child(UIKit.spacer())
		h.add_child(UIKit.label("Lv.%d / %d" % [lvl, SkillManager.max_level()], 18, UIKit.YELLOW))
		var b := UIKit.bar(Mats.hex(String(d.get("color", "#22e4ff"))), 300, 10)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.value = SkillManager.progress(id) * 100.0
		v.add_child(b)
		var next := "已满级" if lvl >= SkillManager.max_level() else "距离下一级还需 %d 经验" % int(SkillManager.total_for(lvl + 1) - float(SkillManager.xp[id]))
		v.add_child(UIKit.label("%s · %s" % [String(d.get("desc", "")), next], 14, UIKit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
	box.add_child(UIKit.label("提升途径：职业培训学校上课（每天一门）· 读书 · 上班实践 · 在家用电脑练习 · 健身房锻炼 · 与人聊天 · 完成任务", 14, UIKit.CYAN, HORIZONTAL_ALIGNMENT_LEFT, true))
