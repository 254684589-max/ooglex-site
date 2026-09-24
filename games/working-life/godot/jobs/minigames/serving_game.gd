class_name ServingGame
extends MinigameBase
## 餐厅服务：先点出餐口的菜（选中），再点点了这道菜的桌子送过去；客人走后要清桌。
## 客人等太久会生气离开。

const DISHES := ["红烧肉", "番茄炒蛋", "牛肉面", "麻婆豆腐", "炒饭", "酸辣汤"]
var tables: Array = []   # [{order, patience, state: empty/waiting/dirty}]
var ready_dishes: Array = []
var selected := -1
var served := 0
var angry := 0
var _table_btns: Array = []
var _dish_box: HBoxContainer
var _spawn_t := 0.0
var _cook_t := 0.0


func _configure() -> void:
	title = "晚市 · 芳姐小馆"
	instructions = "出餐口的菜先点一下（选中），再点等这道菜的桌子。客人吃完会留下脏桌，点一下清理。别让客人等太久！"
	duration = 70.0


func _setup() -> void:
	content.add_child(UIKit.label("出餐口（点选菜品）：", 16, UIKit.DIM))
	_dish_box = UIKit.hbox(8)
	content.add_child(_dish_box)
	content.add_child(UIKit.label("餐桌：", 16, UIKit.DIM))
	var g := grid(4)
	content.add_child(g)
	for i in 4:
		tables.append({"order": "", "patience": 0.0, "state": "empty", "eat": 0.0})
		var b := big_button("", _click_table.bind(i))
		b.custom_minimum_size = Vector2(120, 90)
		g.add_child(b)
		_table_btns.append(b)
	_seat(0)
	_refresh()


func _seat(i: int) -> void:
	tables[i] = {"order": DISHES[rng.randi() % DISHES.size()], "patience": 22.0 - difficulty * 2.0, "state": "waiting", "eat": 0.0}


func _tick(delta: float) -> void:
	_spawn_t -= delta
	if _spawn_t <= 0.0:
		_spawn_t = rng.randf_range(3.0, 5.5) - difficulty * 0.3
		var empty: Array = []
		for i in tables.size():
			if String(tables[i]["state"]) == "empty":
				empty.append(i)
		if not empty.is_empty():
			_seat(empty[rng.randi() % empty.size()])
	_cook_t -= delta
	if _cook_t <= 0.0 and ready_dishes.size() < 3:
		_cook_t = rng.randf_range(2.0, 3.5)
		# 优先做客人点了的菜
		var wanted: Array = []
		for t in tables:
			if String(t["state"]) == "waiting" and not ready_dishes.has(t["order"]):
				wanted.append(t["order"])
		ready_dishes.append(wanted[rng.randi() % wanted.size()] if not wanted.is_empty() else DISHES[rng.randi() % DISHES.size()])
		_refresh_dishes()
	for i in tables.size():
		var t: Dictionary = tables[i]
		if String(t["state"]) == "waiting":
			t["patience"] = float(t["patience"]) - delta
			if float(t["patience"]) <= 0.0:
				angry += 1
				t["state"] = "empty"
				say("%d 号桌的客人等不及走了" % (i + 1), false)
		elif String(t["state"]) == "eating":
			t["eat"] = float(t["eat"]) - delta
			if float(t["eat"]) <= 0.0:
				t["state"] = "dirty"
	_refresh_tables()


func _refresh() -> void:
	_refresh_dishes()
	_refresh_tables()


func _refresh_dishes() -> void:
	for c in _dish_box.get_children():
		c.queue_free()
	for i in ready_dishes.size():
		var b := big_button(("▶ " if i == selected else "") + String(ready_dishes[i]), _select.bind(i), UIKit.YELLOW if i == selected else UIKit.CYAN)
		b.custom_minimum_size = Vector2(110, 48)
		_dish_box.add_child(b)
	if ready_dishes.is_empty():
		_dish_box.add_child(UIKit.label("（厨房正在做……）", 16, UIKit.DIM))


func _refresh_tables() -> void:
	for i in tables.size():
		var t: Dictionary = tables[i]
		var b: Button = _table_btns[i]
		match String(t["state"]):
			"waiting":
				b.text = "%d 号桌\n点了：%s\n耐心 %d" % [i + 1, t["order"], int(ceil(float(t["patience"])))]
			"eating":
				b.text = "%d 号桌\n用餐中……" % (i + 1)
			"dirty":
				b.text = "%d 号桌\n脏桌，点击清理" % (i + 1)
			_:
				b.text = "%d 号桌\n空" % (i + 1)
	update_score()


func _select(i: int) -> void:
	selected = i if selected != i else -1
	_refresh()


func _number_key(i: int) -> void:
	if i < 4:
		_click_table(i)


func _click_table(i: int) -> void:
	if done:
		return
	var t: Dictionary = tables[i]
	match String(t["state"]):
		"dirty":
			t["state"] = "empty"
			say("清好了 %d 号桌" % (i + 1))
		"waiting":
			if selected < 0 or selected >= ready_dishes.size():
				say("先在出餐口选一道菜", false)
			elif String(ready_dishes[selected]) == String(t["order"]):
				ready_dishes.remove_at(selected)
				selected = -1
				served += 1
				t["state"] = "eating"
				t["eat"] = rng.randf_range(4.0, 7.0)
				say("上菜！%d 号桌开吃了" % (i + 1))
			else:
				say("送错菜了！%d 号桌点的是%s" % [i + 1, t["order"]], false)
	_refresh()


func score_text() -> String:
	return "上菜 %d · 气走 %d" % [served, angry]


func final_score() -> float:
	var target := 10.0 + difficulty * 1.5
	return served / target * 100.0 - angry * 8.0
