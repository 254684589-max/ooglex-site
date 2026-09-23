class_name ShopPanel
extends Control
## 商店界面（食堂、小卖部）：商品列表、价格、购买 / 饭票兑换。

signal closed()

var shop_id := ""
var _open := false
var _panel: PanelContainer
var _title: Label
var _greeting: Label
var _cash: Label
var _list: VBoxContainer
var _msg: Label
var _close_btn: Button


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIKit.full_rect(self)
	visible = false
	var center := CenterContainer.new()
	UIKit.full_rect(center)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_panel = UIKit.panel(Color(0.06, 0.065, 0.08, 0.95), 14, 20)
	_panel.custom_minimum_size = Vector2(560, 0)
	center.add_child(_panel)
	var v := UIKit.vbox(10)
	_panel.add_child(v)
	var head := UIKit.hbox(10)
	v.add_child(head)
	_title = UIKit.label("", 26, UIKit.YELLOW)
	head.add_child(_title)
	head.add_child(UIKit.spacer())
	_cash = UIKit.label("", 20, UIKit.YELLOW)
	head.add_child(_cash)
	_greeting = UIKit.label("", 17, UIKit.DIM)
	_greeting.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_greeting)
	v.add_child(HSeparator.new())
	_list = UIKit.vbox(8)
	v.add_child(_list)
	_msg = UIKit.label("", 17, UIKit.GOOD)
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_msg)
	_close_btn = UIKit.button("离开（Esc）", close, 160)
	_close_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	v.add_child(_close_btn)


func is_open() -> bool:
	return _open


func open(id: String) -> void:
	var shop := ShopDB.get_shop(id)
	if shop.is_empty():
		return
	shop_id = id
	_open = true
	visible = true
	_panel.custom_minimum_size.x = clampf(get_viewport_rect().size.x - 40.0, 320.0, 560.0)
	_title.text = String(shop.get("name", ""))
	_greeting.text = "%s：%s" % [String(shop.get("owner", "")), String(shop.get("greeting", ""))]
	_msg.text = ""
	_rebuild()
	_close_btn.grab_focus()


func _rebuild() -> void:
	var shop := ShopDB.get_shop(shop_id)
	_cash.text = "现金 ¥%d" % EconomySystem.cash + ("　饭票 ×%d" % EconomySystem.meal_tickets if EconomySystem.meal_tickets > 0 else "")
	for c in _list.get_children():
		c.queue_free()
	var items: Array = shop.get("items", [])
	for i in items.size():
		var item: Dictionary = items[i]
		var row := UIKit.hbox(10)
		_list.add_child(row)
		var info := UIKit.vbox(0)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		info.add_child(UIKit.label("%d. %s" % [i + 1, String(item.get("name", ""))], 19, UIKit.TEXT))
		info.add_child(UIKit.label(String(item.get("desc", "")), 14, UIKit.DIM))
		var price := int(item.get("price", 0))
		var buy := UIKit.button("¥%d 购买" % price, _buy.bind(i, false), 118)
		buy.disabled = not EconomySystem.can_afford(price)
		row.add_child(buy)
		if bool(item.get("ticket", false)) and EconomySystem.meal_tickets > 0:
			row.add_child(UIKit.button("用饭票", _buy.bind(i, true), 92))


func _buy(index: int, use_ticket: bool) -> void:
	var items: Array = ShopDB.get_shop(shop_id).get("items", [])
	if index < 0 or index >= items.size():
		return
	var result := ShopDB.buy(shop_id, items[index], use_ticket)
	_msg.text = String(result.get("msg", ""))
	_msg.add_theme_color_override("font_color", UIKit.GOOD if bool(result.get("ok", false)) else UIKit.WARN)
	if bool(result.get("ok", false)):
		Events.say(String(result.get("msg", "")), "good")
	_rebuild()


## 测试 / 快捷键用：按商品 id 购买
func buy_item(item_id: String, use_ticket := false) -> Dictionary:
	var items: Array = ShopDB.get_shop(shop_id).get("items", [])
	for i in items.size():
		if String(items[i].get("id", "")) == item_id:
			var result := ShopDB.buy(shop_id, items[i], use_ticket)
			_rebuild()
			return result
	return {"ok": false, "msg": "没有这个商品"}


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.physical_keycode
		if k >= KEY_1 and k <= KEY_9:
			_buy(k - KEY_1, false)
			get_viewport().set_input_as_handled()
		elif event.is_action("pause") or event.is_action("interact"):
			close()
			get_viewport().set_input_as_handled()
