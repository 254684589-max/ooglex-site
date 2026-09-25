class_name DateWindow
extends UIWindow
## 约会：选地点 → 两人一起到那里 → 聊三轮 → 结算（结束时可以表白 / 求婚）。
## 中途关掉窗口也会按已经聊过的部分结算。

var npc_id := ""
var _name := ""


func _init(id: String) -> void:
	npc_id = id
	_name = DataDB.npc_name(id)
	super("约会 · " + DataDB.npc_name(id), Vector2(720, 600))
	window_id = "date"


func _ready() -> void:
	super()
	closed.connect(func():
		if not RomanceManager.current.is_empty():
			Events.say(RomanceManager.finish_date(), "good"))
	_plan()


func _status_line() -> void:
	var h := UIKit.hbox(10)
	body.add_child(h)
	h.add_child(UIKit.label(String(DataDB.npc(npc_id).get("role", "")), 15, UIKit.DIM))
	h.add_child(UIKit.spacer())
	h.add_child(UIKit.label("%s · 好感 %d · 关系 %d" % [RomanceManager.stage_text(npc_id), RomanceManager.affection_of(npc_id), NPCManager.relation(npc_id)], 15, UIKit.MAGENTA))


func _line(text: String) -> void:
	var card := UIKit.card(UIKit.MAGENTA)
	body.add_child(card)
	card.add_child(UIKit.label(text, 19, UIKit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true))


func _opt(text: String, cb: Callable, enabled := true) -> Button:
	var b := UIKit.button(text, cb)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.disabled = not enabled
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(b)
	return b


## 第一步：选地点
func _plan() -> void:
	clear_body()
	_status_line()
	var why := RomanceManager.date_block(npc_id)
	if why != "":
		_line(why)
		_opt("好吧", close)
		return
	var d := RomanceManager.data(npc_id)
	if RomanceManager.affection_of(npc_id) >= 10:
		body.add_child(UIKit.label("你已经有点了解 TA 了：" + String(d.get("hint", "")), 14, UIKit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
	body.add_child(UIKit.label("约%s去哪儿？（可用资金 %s）" % [_name, Fmt.yuan(EconomyManager.liquid())], 17, UIKit.TEXT))
	for v in RomanceManager.venues():
		var vb := RomanceManager.venue_block(v)
		var cost := int(v.get("cost", 0))
		var text := "%s · %s · %d 分钟%s\n%s" % [String(v["name"]), "免费" if cost == 0 else Fmt.yuan(cost), int(v["minutes"]), ("（%s）" % vb) if vb != "" else "", String(v.get("desc", ""))]
		_opt(text, _go.bind(String(v["id"])), vb == "")
	_opt("改天吧", close)


func _go(vid: String) -> void:
	var r := RomanceManager.start_date(npc_id, vid)
	if not bool(r["ok"]):
		Events.say(String(r["text"]), "warn")
		_plan()
		return
	set_title("约会 · %s · %s" % [_name, String(RomanceManager.venue(vid).get("name", ""))])
	_round(String(r["text"]))


## 聊天：一轮一题
func _round(intro := "") -> void:
	clear_body()
	_status_line()
	if intro != "":
		body.add_child(UIKit.label(intro, 15, UIKit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
	var t := RomanceManager.current_topic()
	if t.is_empty():
		_finish()
		return
	_line("%s：「%s」" % [_name, String(t["q"])])
	var opts: Array = t["options"]
	for i in opts.size():
		_opt(String(opts[i]["text"]), _answer.bind(i))


func _answer(i: int) -> void:
	var r := RomanceManager.answer(i)
	clear_body()
	_status_line()
	_line("%s：「%s」" % [_name, String(r[0])])
	var a := int(r[1])
	body.add_child(UIKit.label("好感 %+d" % a, 17, UIKit.GOOD if a > 0 else (UIKit.BAD if a < 0 else UIKit.DIM)))
	_opt("继续", func(): _round())


## 结算：可以表白 / 求婚
func _finish() -> void:
	clear_body()
	var summary := RomanceManager.finish_date()
	_status_line()
	_line(summary)
	var cw := RomanceManager.can_confess(npc_id)
	if cw == "":
		_opt("鼓起勇气表白", _confess)
	elif RomanceManager.status_of(npc_id) == "none" and RomanceManager.affection_of(npc_id) >= 30:
		body.add_child(UIKit.label("表白：%s" % cw, 14, UIKit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
	if RomanceManager.status_of(npc_id) == "dating":
		var pw := RomanceManager.can_propose(npc_id)
		if pw == "":
			_opt("单膝跪下，求婚（钻戒 %s）" % Fmt.yuan(RomanceManager.RING_PRICE), _propose)
		else:
			body.add_child(UIKit.label("求婚：%s" % pw, 14, UIKit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
	_opt("送 TA 回去，结束约会", close)


func _confess() -> void:
	var r := RomanceManager.confess(npc_id)
	clear_body()
	_status_line()
	_line("%s：「%s」" % [_name, String(r[1])])
	body.add_child(UIKit.label("你们在一起了！以后每天心情 +3。" if bool(r[0]) else "好感 -8，过几天再说吧。", 17, UIKit.GOOD if bool(r[0]) else UIKit.BAD))
	_opt("结束约会", close)


func _propose() -> void:
	var r := RomanceManager.propose(npc_id)
	clear_body()
	_status_line()
	_line("%s：「%s」" % [_name, String(r[1])])
	if bool(r[0]):
		body.add_child(UIKit.label("你们结婚了！以后每天心情 +5、压力 -3。", 17, UIKit.GOOD))
	_opt("结束约会", close)
