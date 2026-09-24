class_name FilingGame
extends MinigameBase
## 办公室文件：把文件归到正确的文件夹（合同 / 发票 / 报告 / 简历），盖了「加急」章的直接放加急篮；
## 电话响了要在 4 秒内接起来。

const FOLDERS := ["合同", "发票", "报告", "简历", "加急篮"]
var filed := 0
var wrong := 0
var calls_ok := 0
var calls_missed := 0
var _doc := {}
var _doc_label: Label
var _phone_btn: Button
var _ring_t := 0.0
var _ring_left := 0.0


func _configure() -> void:
	title = "行政事务 · 云途集团"
	instructions = "按文件类型归档（键盘 1~5）；有「加急」章的一律放加急篮。电话响了点「接电话」（空格也行）。"
	duration = 60.0


func _setup() -> void:
	var card := UIKit.card(UIKit.CYAN)
	card.custom_minimum_size = Vector2(0, 110)
	content.add_child(card)
	_doc_label = UIKit.label("", 22, UIKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	card.add_child(_doc_label)
	var g := grid(5)
	content.add_child(g)
	for i in FOLDERS.size():
		g.add_child(big_button("%d\n%s" % [i + 1, FOLDERS[i]], _file.bind(i), UIKit.MAGENTA if i == 4 else UIKit.CYAN))
	_phone_btn = big_button("☎ 电话响了！接电话", _answer_phone, UIKit.YELLOW)
	_phone_btn.visible = false
	content.add_child(_phone_btn)
	_ring_t = rng.randf_range(6.0, 10.0)
	_next_doc()


func _next_doc() -> void:
	var t := rng.randi() % 4
	var urgent := rng.randf() < 0.2
	var titles := [["房屋租赁合同", "采购合同", "劳动合同", "保密协议"], ["增值税发票", "差旅报销单", "餐饮发票", "设备采购发票"], ["季度销售报告", "市场调研报告", "项目周报", "审计报告"], ["应聘简历·张伟", "应聘简历·李娜", "应聘简历·王强", "应聘简历·赵敏"]]
	var name: String = titles[t][rng.randi() % 4]
	_doc = {"folder": 4 if urgent else t}
	_doc_label.text = "%s%s" % [name, "\n【加急】" if urgent else ""]


func _tick(delta: float) -> void:
	if _ring_left > 0.0:
		_ring_left -= delta
		_phone_btn.text = "☎ 电话响了！接电话（%.1f 秒）" % maxf(_ring_left, 0.0)
		if _ring_left <= 0.0:
			calls_missed += 1
			_phone_btn.visible = false
			say("漏接了一个电话", false)
			update_score()
	else:
		_ring_t -= delta
		if _ring_t <= 0.0:
			_ring_t = rng.randf_range(7.0, 12.0) - difficulty
			_ring_left = 4.0
			_phone_btn.visible = true
			AudioManager.play_sfx("phone", -4.0)


func _answer_phone() -> void:
	if _ring_left <= 0.0 or done:
		return
	_ring_left = 0.0
	_phone_btn.visible = false
	calls_ok += 1
	say("「您好，云途集团。」——电话处理完毕")
	update_score()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_SPACE:
		_answer_phone()
		get_viewport().set_input_as_handled()
		return
	super(event)


func _number_key(i: int) -> void:
	if i < FOLDERS.size():
		_file(i)


func _file(i: int) -> void:
	if done:
		return
	if i == int(_doc["folder"]):
		filed += 1
		say("✓ 归档正确")
	else:
		wrong += 1
		say("× 放错了：应放「%s」" % FOLDERS[int(_doc["folder"])], false)
	update_score()
	_next_doc()


func score_text() -> String:
	return "归档 %d · 错 %d · 电话 %d/%d" % [filed, wrong, calls_ok, calls_ok + calls_missed]


func final_score() -> float:
	var target := 20.0 + difficulty * 2.0
	return filed / target * 85.0 + calls_ok * 5.0 - wrong * 5.0 - calls_missed * 8.0
