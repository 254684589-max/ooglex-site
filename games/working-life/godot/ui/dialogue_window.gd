class_name DialogueWindow
extends UIWindow
## 与 NPC 对话：问候（按关系分档）、每日闲聊（选项影响关系）、接任务、交付任务物品、送礼、NPC 提供的帮助与服务。

var npc_id := ""
var npc: Dictionary = {}
var _node: NPC


func _init(id: String) -> void:
	npc_id = id
	npc = DataDB.npc(id)
	super(String(npc.get("name", id)), Vector2(720, 560))
	window_id = "dialogue"


func _ready() -> void:
	super()
	_node = GameManager.lookup("npc:" + npc_id) as NPC
	if _node != null:
		_node.begin_talk()
	closed.connect(func():
		if is_instance_valid(_node):
			_node.end_talk())
	NPCManager.met[npc_id] = true
	Events.notify("talk", {"npc": npc_id})
	show_main(NPCManager.greeting(npc_id))


func _header() -> void:
	clear_body()
	var h := UIKit.hbox(10)
	body.add_child(h)
	h.add_child(UIKit.label(String(npc.get("role", "")), 15, UIKit.DIM))
	h.add_child(UIKit.spacer())
	var rel := NPCManager.relation(npc_id)
	h.add_child(UIKit.label("关系：%s（%d）" % [NPCManager.tier_name(npc_id), rel], 15, UIKit.GOOD if rel >= 20 else UIKit.TEXT))


func _line(text: String) -> void:
	var card := UIKit.card(UIKit.MAGENTA)
	body.add_child(card)
	card.add_child(UIKit.label("「%s」" % text, 19, UIKit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true))


func _opt(text: String, cb: Callable, enabled := true) -> void:
	var b := UIKit.button(text, cb)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.disabled = not enabled
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(b)


func show_main(line: String) -> void:
	_header()
	_line(line)
	# 任务进展提示（刚刚因为交谈而推进的目标）
	for qid in QuestManager.active_ids():
		var idx := QuestManager.current_objective_index(qid)
		if idx < 0:
			continue
		var o: Dictionary = QuestManager.objectives(qid)[idx]
		if String(o.get("type", "")) in ["talk", "deliver"] and String(o.get("npc", "")) == npc_id:
			body.add_child(UIKit.label("◆ 任务「%s」：%s" % [String(QuestManager.data(qid).get("title", "")), String(o.get("text", ""))], 15, UIKit.YELLOW, HORIZONTAL_ALIGNMENT_LEFT, true))
	for d in QuestManager.deliverables_for(npc_id):
		_opt("【交付】把%s交给%s" % [DataDB.item_name(String(d["item"])), String(npc.get("name", ""))], _deliver.bind(String(d["item"])))
	for qid2 in QuestManager.available_from(npc_id):
		var q := QuestManager.data(qid2)
		_opt("【新任务】%s" % String(q.get("title", "")), _offer.bind(qid2))
	var topic := NPCManager.topic_for(npc_id)
	if not topic.is_empty():
		_opt("闲聊" if NPCManager.can_chat(npc_id) else "闲聊（今天已经聊过了）", _chat, NPCManager.can_chat(npc_id))
	var gifts: Array = []
	for id in PlayerManager.backpack:
		if String(DataDB.item(String(id)).get("use", "")) == "gift" or String(id) in ["coffee", "cake", "synth_bar"]:
			gifts.append(String(id))
	if not gifts.is_empty():
		_opt("送礼物" if NPCManager.can_gift(npc_id) else "送礼物（今天已经送过了）", _gift_menu.bind(gifts), NPCManager.can_gift(npc_id))
	var hire := NPCManager.direct_hire_job(npc_id)
	if hire != "" and not (JobManager.has_job() and JobManager.job_id() == hire):
		_opt("【关系】请%s直接录用我：%s（%s）" % [String(npc.get("name", "")), String(DataDB.job(hire).get("name", "")), JobManager.pay_text(hire, 0)], _direct_hire.bind(hire))
	_services()
	_opt("再见", close)


func _services() -> void:
	match npc_id:
		"laoli":
			_opt("我想租房子", func(): _open_panel("phone", {"app": "housing"}))
		"wangjl":
			_opt("看看最近的招聘信息", func(): _open_panel("phone", {"app": "jobs"}))
		"liulaoshi":
			_opt("我想报名课程", func(): _open_panel("courses", {}))
		"zhaojl":
			_opt("办理银行业务", func(): _open_panel("phone", {"app": "bank"}))
		"zhoulb":
			_opt("聊聊创业", func(): _open_panel("phone", {"app": "business"}))
		"laok":
			_opt("问问最近的行情", _market_tip)
		"xuys":
			_opt("请您帮我看看（挂号 %s）" % Fmt.yuan(ServiceRouter.treatment_fee()), func():
				force_close()
				ServiceRouter._treatment())
		"chenshu", "fangjie":
			_opt("买点东西", func(): 
				force_close()
				Events.shop_requested.emit("convenience" if npc_id == "chenshu" else "restaurant"))


func _open_panel(id: String, args: Dictionary) -> void:
	force_close()
	Events.panel_requested.emit(id, args)


func _market_tip() -> void:
	var line := ""
	if NPCManager.has_perk("market_tip"):
		line = "跟你说实话：现在是%s期，还剩大概 %d 天。%s" % [InvestmentManager.cycle_name(), InvestmentManager.cycle_days_left, "繁荣期拿指数和科技，衰退期多配黄金债券。"]
	else:
		line = "行情嘛……涨涨跌跌。等咱俩再熟一点（关系 30），我再跟你说点真心话。"
	show_main(line)


func _deliver(item: String) -> void:
	QuestManager.deliver(npc_id, item)
	show_main("太谢谢你了！")


func _offer(qid: String) -> void:
	var q := QuestManager.data(qid)
	_header()
	_line(String(q.get("desc", "")))
	var rw := Effects.describe(q.get("reward", {}))
	if rw != "":
		body.add_child(UIKit.label("报酬：" + rw, 15, UIKit.YELLOW, HORIZONTAL_ALIGNMENT_LEFT, true))
	_opt("好，交给我吧", func():
		QuestManager.start(qid)
		Events.notify("talk", {"npc": npc_id})
		show_main("那就拜托你了！"))
	_opt("现在没空", func(): show_main("好吧，有空再说。"))


func _chat() -> void:
	var topic := NPCManager.topic_for(npc_id)
	_header()
	_line(String(topic.get("q", "")))
	for o in topic.get("options", []):
		_opt(String(o.get("text", "")), _answer.bind(o))


func _answer(o: Dictionary) -> void:
	NPCManager.mark_chatted(npc_id)
	var rel := int(o.get("rel", 0))
	NPCManager.change_relation(npc_id, rel)
	if rel > 0:
		SkillManager.add_xp("communication", 6 + rel, "聊天")
		PlayerManager.change("mood", 2)
	show_main(String(o.get("reply", "")) + ("　（关系 %+d）" % rel))


func _gift_menu(gifts: Array) -> void:
	_header()
	_line("送点什么给%s？" % String(npc.get("name", "")))
	for g in gifts:
		_opt("%s（背包 %d）" % [DataDB.item_name(g), PlayerManager.item_count(g)], func(): show_main(NPCManager.give_gift(npc_id, g)))
	_opt("算了", func(): show_main("嗯？"))


func _direct_hire(job_id: String) -> void:
	if JobManager.has_job():
		JobManager.quit_job()
	JobManager.hire(job_id, 0)
	Events.notify("interview_pass", {"job": job_id})
	show_main("没问题！明天按时来上班，别迟到。")
