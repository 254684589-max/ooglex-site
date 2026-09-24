class_name JobsApp
extends RefCounted
## 招聘 APP：公司、职位、工资、上班时间、技能要求、工作地点、职位等级；点「申请」投简历。


static func build(box: VBoxContainer, refresh: Callable) -> void:
	if not JobManager.invites.is_empty():
		box.add_child(UIKit.label("面试邀请", 18, UIKit.MAGENTA))
		for inv in JobManager.invites:
			var j := DataDB.job(String(inv["job"]))
			box.add_child(UIKit.label("● %s · %s —— 请在第 %d 天结束前到「%s」参加面试" % [String(j.get("company", "")), String(JobManager.ladder(String(inv["job"]))[int(inv["level"])]["title"]), int(inv["expires_day"]), DataDB.location_name(String(j.get("venue", "")))], 15, UIKit.YELLOW, HORIZONTAL_ALIGNMENT_LEFT, true))
		box.add_child(UIKit.sep())
	box.add_child(UIKit.label("在招职位（写字楼岗位投简历后需要简历筛选；体力岗位简历必过）", 15, UIKit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
	for p in JobManager.postings():
		var eligible := bool(p["eligible"])
		var card := UIKit.card(UIKit.GOOD if eligible else Color(0.5, 0.5, 0.55))
		box.add_child(card)
		var v := UIKit.vbox(2)
		card.add_child(v)
		var h := UIKit.hbox(8)
		v.add_child(h)
		h.add_child(UIKit.label("%s · %s" % [String(p["company"]), String(p["title"])], 18, UIKit.TEXT))
		h.add_child(UIKit.spacer())
		h.add_child(UIKit.label(String(p["pay"]), 17, UIKit.YELLOW))
		v.add_child(UIKit.label("%s · 职位等级 %d · %s · 地点：%s · 面试：%s" % [String(p["name"]), int(p["grade"]), String(p["hours"]), DataDB.location_name(String(p["location"])), DataDB.location_name(String(p["venue"]))], 14, UIKit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
		var req: Dictionary = p["req"]
		var rtxt: Array = []
		for s in req:
			rtxt.append("%s Lv.%d" % [DataDB.skill_name(String(s)), int(req[s])])
		var rep_need := int(DataDB.job(String(p["job"])).get("rep", 0))
		if rep_need > 0:
			rtxt.append("声望 %d" % rep_need)
		v.add_child(UIKit.label("要求：" + ("、".join(rtxt) if not rtxt.is_empty() else "无"), 14, UIKit.TEXT))
		v.add_child(UIKit.label(String(p["desc"]), 13, UIKit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
		var row := UIKit.hbox(8)
		v.add_child(row)
		if String(p["status"]) != "":
			row.add_child(UIKit.label(String(p["status"]), 15, UIKit.CYAN))
		elif not eligible:
			row.add_child(UIKit.label("还差：" + "、".join(p["missing"]), 14, UIKit.WARN, HORIZONTAL_ALIGNMENT_LEFT, true))
		else:
			row.add_child(UIKit.small_button("申请", func():
				var r := JobManager.apply(String(p["job"]))
				Events.say(String(r["text"]), "good" if bool(r["ok"]) else "warn")
				refresh.call()))
