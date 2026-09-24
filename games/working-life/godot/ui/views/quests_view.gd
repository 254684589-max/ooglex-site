class_name QuestsView
extends RefCounted
## 任务列表（J 键 / 手机「任务」APP）：进行中的任务与目标进度，可以切换 HUD 追踪的任务；已完成任务列表。


static func build(box: VBoxContainer, refresh: Callable) -> void:
	var act := QuestManager.active_ids()
	box.add_child(UIKit.label("进行中（%d）" % act.size(), 18, UIKit.CYAN))
	if act.is_empty():
		box.add_child(UIKit.label("没有进行中的任务。和城市里的人聊聊，他们可能需要帮忙。", 15, UIKit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
	var tracked := QuestManager.tracked_id()
	for id in act:
		var q := QuestManager.data(id)
		var main := String(q.get("type", "")) == "main"
		var card := UIKit.card(UIKit.MAGENTA if main else UIKit.CYAN)
		box.add_child(card)
		var v := UIKit.vbox(3)
		card.add_child(v)
		var h := UIKit.hbox(8)
		v.add_child(h)
		var tag: String = "主线 · 第%d章" % int(q.get("chapter", 1)) if main else {"side": "支线", "job": "职业任务", "npc": "NPC 任务"}.get(String(q.get("type", "")), "支线")
		h.add_child(UIKit.label("[%s] %s" % [tag, String(q.get("title", ""))], 18, UIKit.TEXT))
		h.add_child(UIKit.spacer())
		if id == tracked:
			h.add_child(UIKit.label("◆ 追踪中", 14, UIKit.YELLOW))
		else:
			h.add_child(UIKit.small_button("追踪", func():
				QuestManager.tracked = id
				refresh.call()))
		if q.has("giver"):
			v.add_child(UIKit.label("委托人：%s" % DataDB.npc_name(String(q["giver"])), 14, UIKit.DIM))
		v.add_child(UIKit.label(String(q.get("desc", "")), 15, UIKit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
		var objs := QuestManager.objectives(id)
		var open := QuestManager.open_indices(id)
		for i in objs.size():
			var done := QuestManager.objective_done(id, i)
			var mark := "✓" if done else ("▶" if open.has(i) else "·")
			v.add_child(UIKit.label("%s %s" % [mark, QuestManager.objective_text(id, i)], 15, UIKit.GOOD if done else (UIKit.CYAN if open.has(i) else UIKit.DIM), HORIZONTAL_ALIGNMENT_LEFT, true))
		var rw := Effects.describe(q.get("reward", {}))
		if rw != "":
			v.add_child(UIKit.label("奖励：" + rw, 14, UIKit.YELLOW, HORIZONTAL_ALIGNMENT_LEFT, true))
	var done_ids: Array = []
	for id in DataDB.ids("quests"):
		if QuestManager.is_done(id):
			done_ids.append(id)
	box.add_child(UIKit.sep())
	box.add_child(UIKit.label("已完成（%d / %d）" % [done_ids.size(), DataDB.ids("quests").size()], 18, UIKit.CYAN))
	var names: Array = []
	for id in done_ids:
		names.append(String(QuestManager.data(id).get("title", "")))
	if not names.is_empty():
		box.add_child(UIKit.label("、".join(names), 14, UIKit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
