class_name SortingGame
extends MinigameBase
## 仓库分拣：包裹上写着目的地区域（A/B/C/D），把它放进对应的货区；「易碎」件必须放进「易碎专区」。

const ZONES := ["A 区 · 城北", "B 区 · 城南", "C 区 · 城东", "D 区 · 城西", "易碎专区"]
var sorted := 0
var wrong := 0
var _current := {}
var _card: PanelContainer
var _card_label: Label


func _configure() -> void:
	title = "分拣线 · 速达物流园"
	instructions = "看包裹标签，把它送到对应货区（键盘 1~5）。标着「易碎」的一律放进易碎专区。"
	duration = 60.0


func _setup() -> void:
	_card = UIKit.card(UIKit.YELLOW)
	_card.custom_minimum_size = Vector2(0, 110)
	content.add_child(_card)
	_card_label = UIKit.label("", 26, UIKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_card.add_child(_card_label)
	var g := grid(5)
	content.add_child(g)
	for i in ZONES.size():
		g.add_child(big_button("%d\n%s" % [i + 1, ZONES[i]], _put.bind(i), UIKit.YELLOW if i == 4 else UIKit.CYAN))
	_next()


func _next() -> void:
	var zone := rng.randi() % 4
	var fragile := rng.randf() < 0.18 + difficulty * 0.03
	var code := "%s-%03d" % ["ABCD"[zone], rng.randi_range(1, 999)]
	_current = {"zone": 4 if fragile else zone, "code": code}
	_card_label.text = "%s%s\n收件：%s" % [code, "  ⚠ 易碎" if fragile else "", ["北区仓", "南区仓", "东区仓", "西区仓"][zone]]


func _number_key(i: int) -> void:
	if i < ZONES.size():
		_put(i)


func _put(i: int) -> void:
	if done:
		return
	if i == int(_current["zone"]):
		sorted += 1
		say("✓ 分拣正确")
		AudioManager.play_sfx("beep", -10.0)
	else:
		wrong += 1
		say("× 放错了：应该放 %s" % ZONES[int(_current["zone"])], false)
	update_score()
	_next()


func score_text() -> String:
	return "分拣 %d · 错误 %d" % [sorted, wrong]


func final_score() -> float:
	var target := 26.0 + difficulty * 3.0
	return sorted / target * 100.0 - wrong * 5.0
