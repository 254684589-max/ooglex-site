class_name CashierGame
extends MinigameBase
## 便利店收银：给顾客的每件商品扫码，然后在三个选项里选出正确的找零。

const GOODS := [["矿泉水", 3], ["泡面", 6], ["面包", 8], ["蛋白棒", 10], ["咖啡", 15], ["盒饭", 18], ["能量饮料", 12], ["纸巾", 5], ["口香糖", 7], ["冰淇淋", 9], ["电池", 22], ["雨伞", 35]]

var customers := 0
var correct := 0
var mistakes := 0
var _basket: Array = []
var _scanned := 0
var _paid := 0
var _stage := 0


func _configure() -> void:
	title = "收银台 · 24h 便利店"
	instructions = "点击商品逐个扫码 → 顾客付款后选择正确的找零（键盘 1~3 也可以）。尽量又快又准。"
	duration = 70.0


func _setup() -> void:
	_next_customer()


func score_text() -> String:
	return "已服务 %d 位 · 正确 %d" % [customers, correct]


func final_score() -> float:
	var target := 6.0 + difficulty
	return minf(100.0, correct / target * 100.0) - mistakes * 5.0


func _next_customer() -> void:
	clear_content()
	_basket.clear()
	_scanned = 0
	_stage = 0
	var n := rng.randi_range(2, 3 + mini(difficulty, 2))
	for i in n:
		_basket.append(GOODS[rng.randi() % GOODS.size()])
	content.add_child(UIKit.label("第 %d 位顾客把东西放上了柜台：" % (customers + 1), 17, UIKit.TEXT))
	var g := grid(4)
	content.add_child(g)
	for i in _basket.size():
		var it: Array = _basket[i]
		var b := big_button("%s\n¥%d" % [it[0], it[1]], Callable())
		b.pressed.connect(_scan.bind(b))
		g.add_child(b)


func _scan(b: Button) -> void:
	if done or _stage != 0 or b.disabled:
		return
	b.disabled = true
	b.text += " ✓"
	_scanned += 1
	AudioManager.play_sfx("beep", -8.0)
	if _scanned >= _basket.size():
		_ask_change()


func _total() -> int:
	var t := 0
	for it in _basket:
		t += int(it[1])
	return t


func _ask_change() -> void:
	_stage = 1
	var total := _total()
	_paid = 50 if total <= 50 else 100
	if total > 100:
		_paid = 200
	var change := _paid - total
	var opts := [change, change + rng.randi_range(1, 5) * (1 if rng.randf() < 0.5 else -1), change + 10 * (1 if rng.randf() < 0.5 else -1)]
	for i in opts.size():
		opts[i] = maxi(0, int(opts[i]))
	if opts[1] == opts[0]:
		opts[1] = opts[0] + 2
	if opts[2] == opts[0] or opts[2] == opts[1]:
		opts[2] = opts[0] + 7
	opts.shuffle()
	content.add_child(UIKit.label("合计 ¥%d，顾客付了 ¥%d。应该找零多少？" % [total, _paid], 19, UIKit.YELLOW))
	var h := UIKit.hbox(10)
	content.add_child(h)
	for i in opts.size():
		var v: int = opts[i]
		h.add_child(big_button("%d. 找 ¥%d" % [i + 1, v], _answer.bind(v)))


func _number_key(i: int) -> void:
	if _stage == 1:
		var btns: Array = content.find_children("*", "Button", true, false)
		var opts: Array = btns.filter(func(x): return not x.disabled)
		if i < opts.size():
			(opts[i] as Button).pressed.emit()


func _answer(v: int) -> void:
	if done or _stage != 1:
		return
	customers += 1
	if v == _paid - _total():
		correct += 1
		say("找零正确，顾客满意地离开了")
	else:
		mistakes += 1
		say("找错钱了！正确是 ¥%d" % (_paid - _total()), false)
	update_score()
	_next_customer()
