class_name LootPanel
extends Control
## 搜刮面板（路线图 2.6）：打开箱子或搜刮倒下的敌人时出现，游戏暂停。
## 一行一件（银币单独一行），点一下拿走；「全部拿走」一次拿完；下方写当前负重（拿了会超重时照样能拿，只是不能跑）。

signal closed
signal took(names: Array)

var f: Dictionary
var box: VBoxContainer
var container: LootContainer
var take_all_btn: Button


func _ready() -> void:
	f = UiKit.frame(self, "搜刮")
	box = f.box
	(f.close as Button).pressed.connect(close)
	get_tree().root.size_changed.connect(_fit)
	hide()


func open(c: LootContainer) -> void:
	container = c
	(f.title as Label).text = ("搜刮：" if c.corpse else "") + c.display_name
	show()
	refresh()
	if take_all_btn and not take_all_btn.disabled:
		take_all_btn.grab_focus()
	else:
		(f.close as Button).grab_focus()
	print("IC_LOOT open id=%s items=%d" % [c.loot_id, (c.contents().items as Array).size()])


func close() -> void:
	if not visible:
		return
	hide()
	print("IC_LOOT closed")
	closed.emit()


func refresh() -> void:
	UiKit.clear(box)
	var c := container.contents()
	if int(c.silver) > 0:
		UiKit.button(box, "银币 ×%d" % int(c.silver), func(): _take(-1))
	var items: Array = c.items
	for i in items.size():
		var it := GameState.item(str(items[i]))
		var idx := i
		UiKit.button(box, "%s（%s · %.1f 斤）" % [GameState.item_name(str(items[i])), GameState.KIND_NAMES.get(str(it.get("kind", "")), ""), float(it.get("weight", 0))], func(): _take(idx))
	if container.is_empty():
		UiKit.label(box, "什么都没有了。", true)
	box.add_child(HSeparator.new())
	var foot := "负重 %.1f / %.0f 斤 · 银币 %d" % [GameState.carry_weight(), GameState.carry_limit(), GameState.silver]
	if GameState.over_encumbered():
		foot += " · 超重：不能跑"
	UiKit.label(box, foot, true, 15)
	take_all_btn = Button.new()
	take_all_btn.text = "全部拿走"
	take_all_btn.custom_minimum_size = Vector2(120, 40)
	take_all_btn.disabled = container.is_empty()
	take_all_btn.pressed.connect(take_everything)
	box.add_child(take_all_btn)
	_fit()


func _take(i: int) -> void:
	var name_got := container.take(i)
	if name_got != "":
		print("IC_LOOT took %s" % name_got)
		took.emit([name_got])
	refresh()
	if container.is_empty():
		(f.close as Button).grab_focus()


func take_everything() -> void:
	var got := container.take_all()
	if not got.is_empty():
		print("IC_LOOT took %s" % "、".join(got))
		took.emit(got)
	refresh()
	(f.close as Button).grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("pause") or event.is_action_pressed("inventory") or event.is_action_pressed("interact")):
		get_viewport().set_input_as_handled()
		close()


func _fit() -> void:
	if not is_inside_tree():
		return
	# 自动换行的 Label 在第一次排版前按 0 宽度算高度（一个字一行），面板会被撑满整屏：
	# 先定宽度，排版一帧后再按真实高度定一次（2.6 截图）
	var w := UiKit.content_width(self, 480.0)
	for c in box.get_children():
		if c is Label:
			c.custom_minimum_size.x = w - 12.0
	UiKit.fit(self, f, 480.0)
	_refit.call_deferred()


func _refit() -> void:
	if is_inside_tree() and visible:
		UiKit.fit(self, f, 480.0)
