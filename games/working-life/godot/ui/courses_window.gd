class_name CoursesWindow
extends UIWindow
## 职业培训学校：18 门课程（六项技能 × 基础 / 进阶 / 高级），每天最多上一门。


func _init() -> void:
	super("职业培训学校 · 课程表", Vector2(780, 600))
	window_id = "courses"


func _ready() -> void:
	super()
	_build()


func price(c: Dictionary) -> int:
	var p := float(c.get("price", 0))
	p *= 1.0 - NPCManager.perk_value("course_discount")
	if int(GameManager.get_value("course_sale_until", -1)) >= TimeManager.day:
		p *= 0.7
	return int(round(p))


func _build() -> void:
	clear_body()
	var taken_today := int(GameManager.get_value("course_day", -1)) == TimeManager.day
	add_text("每天最多上一门课，上课会占用几个小时。刘老师：「学到的东西，谁也拿不走。」", 15, UIKit.DIM)
	if taken_today:
		add_text("今天已经上过课了，明天再来。", 16, UIKit.WARN)
	if int(GameManager.get_value("course_sale_until", -1)) >= TimeManager.day:
		add_text("限时 7 折进行中！", 16, UIKit.MAGENTA)
	for id in DataDB.ids("courses"):
		var c: Dictionary = DataDB.courses[id]
		var skill := String(c["skill"])
		var lvl := SkillManager.level(skill)
		var ok_level := lvl >= int(c["min_level"]) and lvl < int(c["max_level"])
		var card := UIKit.card(Mats.hex(String(DataDB.skills[skill].get("color", "#22e4ff"))))
		body.add_child(card)
		var h := UIKit.hbox(8)
		card.add_child(h)
		var v := UIKit.vbox(2)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(v)
		v.add_child(UIKit.label("%s · %s" % [String(c["name"]), DataDB.skill_name(skill)], 17, UIKit.TEXT))
		v.add_child(UIKit.label("%s经验 +%d · %s · 适合 Lv.%d~%d（你 Lv.%d）" % [DataDB.skill_name(skill), int(c["xp"]), Fmt.hours_text(float(c["minutes"])), int(c["min_level"]), int(c["max_level"]) - 1, lvl], 14, UIKit.DIM if ok_level else UIKit.WARN))
		h.add_child(UIKit.label(Fmt.yuan(price(c)), 17, UIKit.YELLOW))
		var b := UIKit.small_button("报名上课", _take.bind(id))
		b.disabled = taken_today or not ok_level
		h.add_child(b)


func _take(id: String) -> void:
	var c: Dictionary = DataDB.courses[id]
	if int(GameManager.get_value("course_day", -1)) == TimeManager.day:
		Events.say("今天已经上过课了，明天再来", "warn")
		return
	if PlayerManager.energy < 15.0:
		Events.say("太累了，上课会睡着的（体力低于 15）", "warn")
		return
	var p := price(c)
	if not EconomyManager.spend(p, "学习", String(c["name"])):
		Events.say("学费不够（%s）" % Fmt.yuan(p), "warn")
		return
	GameManager.set_value("course_day", TimeManager.day)
	TimeManager.advance(float(c["minutes"]), "study")
	var xp := float(c["xp"]) * PlayerManager.efficiency()
	SkillManager.add_xp(String(c["skill"]), xp, "培训")
	PlayerManager.change("stress", 3)
	NPCManager.change_relation("liulaoshi", 2)
	Events.notify("course", {"course": id})
	Events.say("上完了「%s」（%s经验 +%d）" % [String(c["name"]), DataDB.skill_name(String(c["skill"])), int(xp)], "good")
	_build()
