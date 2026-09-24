class_name InterviewWindow
extends UIWindow
## 面试：三道题（对话选择），根据回答、技能、着装、住房体面度、声望、心情与人脉计算录用概率。

var job_id := ""
var questions: Array = []
var qi := 0
var total := 0.0


func _init(id: String) -> void:
	job_id = id
	super("面试 · %s" % String(DataDB.job(id).get("company", "")), Vector2(720, 540))
	window_id = "interview"


func _ready() -> void:
	super()
	questions = JobManager.interview_questions(job_id, 3)
	var inv := JobManager.get_invite(job_id)
	clear_body()
	var lvl := int(inv.get("level", 0))
	add_text("应聘职位：%s · %s（%s）" % [String(DataDB.job(job_id).get("name", "")), String(JobManager.ladder(job_id)[lvl]["title"]), JobManager.pay_text(job_id, lvl)], 18, UIKit.YELLOW)
	add_text("面试官请你坐下。深呼吸，回答要真诚、有条理。", 16, UIKit.DIM)
	if PlayerManager.outfit != "":
		add_text("你穿着%s。" % DataDB.item_name(PlayerManager.outfit), 15, UIKit.DIM)
	add_button("开始面试", _show_q)
	set_closable(false)


func _show_q() -> void:
	clear_body()
	if qi >= questions.size():
		_finish()
		return
	var q: Dictionary = questions[qi]
	add_text("第 %d / %d 题" % [qi + 1, questions.size()], 15, UIKit.DIM)
	var card := UIKit.card(UIKit.MAGENTA)
	body.add_child(card)
	card.add_child(UIKit.label("面试官：「%s」" % String(q.get("q", "")), 19, UIKit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true))
	var opts: Array = q.get("options", []).duplicate()
	opts.shuffle()
	for o in opts:
		var b := UIKit.button(String(o.get("text", "")), _answer.bind(q, o))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(b)


func _answer(q: Dictionary, o: Dictionary) -> void:
	var s := float(o.get("score", 5))
	if q.has("skill"):
		# 回答得好不好，也看你真实的本事
		s += clampf((SkillManager.level(String(q["skill"])) - 2) * 0.6, -1.5, 2.0)
	total += clampf(s, 0.0, 10.0)
	qi += 1
	_show_q()


func _finish() -> void:
	var avg := total / maxf(1.0, questions.size())
	var r := JobManager.finish_interview(job_id, avg)
	clear_body()
	add_text("面试表现：%.1f / 10" % avg, 18, UIKit.CYAN)
	add_text("综合录用概率约 %d%%" % int(float(r["chance"]) * 100), 15, UIKit.DIM)
	add_text(String(r["text"]), 20, UIKit.GOOD if bool(r["ok"]) else UIKit.BAD)
	if bool(r["ok"]):
		AudioManager.play_sfx("levelup")
		add_text("上班时间：%s（%s）。地点：%s。手机「人物」页可以随时查看。" % [JobManager.hours_text(job_id), JobManager.workdays_text(job_id), DataDB.location_name(String(DataDB.job(job_id).get("workplace", "")))], 16, UIKit.TEXT)
	set_closable(true)
	add_button("好的", force_close)
