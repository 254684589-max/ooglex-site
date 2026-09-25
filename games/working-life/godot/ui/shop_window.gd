class_name ShopWindow
extends UIWindow
## 商店：商品列表（名称、效果、价格），购买进背包；餐厅 / 便利店 / 咖啡馆可以「买了就吃」。
## 所有付款都走 EconomyManager（现金优先，不够自动刷银行卡）。

var shop_id := ""
var shop: Dictionary = {}
var _cash_label: Label


func _init(id: String) -> void:
	shop_id = id
	shop = DataDB.shops.get(id, {})
	super(String(shop.get("name", "商店")), Vector2(780, 580))
	window_id = "shop"


func _ready() -> void:
	super()
	_build()


func price_of(item_id: String) -> int:
	var it := DataDB.item(item_id)
	var p := float(it.get("price", 0)) * float(shop.get("discount", 1.0)) * float(shop.get("markup", 1.0))
	if shop_id == "restaurant":
		p *= 1.0 - NPCManager.perk_value("meal_discount")
	return maxi(1, int(round(p)))


func _build() -> void:
	clear_body()
	_cash_label = UIKit.label("现金 %s · 银行卡 %s · 背包 %d/%d 格" % [Fmt.yuan(EconomyManager.cash), Fmt.yuan(EconomyManager.bank), PlayerManager.used_slots(), PlayerManager.BACKPACK_SLOTS], 16, UIKit.YELLOW)
	body.add_child(_cash_label)
	for item_id in shop.get("items", []):
		var it := DataDB.item(String(item_id))
		if it.is_empty():
			continue
		var card := UIKit.card(UIKit.CYAN)
		body.add_child(card)
		var h := UIKit.hbox(10)
		card.add_child(h)
		var info := UIKit.vbox(2)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(info)
		var owned := ""
		var use := String(it.get("use", ""))
		if use in ["durable", "outfit"] and PlayerManager.owned.has(String(item_id)):
			owned = "（已拥有）"
		elif PlayerManager.item_count(String(item_id)) > 0:
			owned = "（背包里有 %d）" % PlayerManager.item_count(String(item_id))
		info.add_child(UIKit.label(String(it.get("name", "")) + owned, 18, UIKit.TEXT))
		var fx := _effects_text(it)
		info.add_child(UIKit.label(fx, 14, UIKit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
		h.add_child(UIKit.label(Fmt.yuan(price_of(String(item_id))), 18, UIKit.YELLOW))
		var buy := UIKit.small_button("购买", _buy.bind(String(item_id), false))
		buy.disabled = owned.begins_with("（已拥有")
		h.add_child(buy)
		if bool(shop.get("eat_in", false)) and use == "consume":
			h.add_child(UIKit.small_button("买了就吃", _buy.bind(String(item_id), true)))


func _effects_text(it: Dictionary) -> String:
	var parts: Array = []
	var fx: Dictionary = it.get("effects", {})
	for k in fx:
		parts.append("%s %+d" % [PlayerManager.STAT_NAMES.get(k, k), int(fx[k])])
	var sx: Dictionary = it.get("skill_xp", {})
	for s in sx:
		parts.append("%s经验 +%d" % [DataDB.skill_name(String(s)), int(sx[s])])
	if it.has("interview"):
		parts.append("面试加分 +%d" % int(it["interview"]))
	var d := String(it.get("desc", ""))
	return (" · ".join(parts) + "  " if not parts.is_empty() else "") + d


func _buy(item_id: String, eat_now: bool) -> void:
	var it := DataDB.item(item_id)
	var price := price_of(item_id)
	var use := String(it.get("use", ""))
	if not eat_now and use in ["consume", "read", "tool", "gift"] and not PlayerManager.can_add(item_id, 1):
		Events.say("背包满了", "warn")
		return
	var cat: String = {"food": "食品", "drink": "食品", "medicine": "医疗", "book": "学习", "clothes": "购物", "electronics": "购物", "membership": "娱乐"}.get(String(it.get("category", "")), "购物")
	if not EconomyManager.spend(price, cat, "购买 %s" % String(it.get("name", ""))):
		Events.say("钱不够（需要 %s）" % Fmt.yuan(price), "warn")
		AudioManager.play_sfx("error")
		return
	AudioManager.play_sfx("coin", -4.0)
	Events.notify("buy", {"item": item_id, "category": String(it.get("category", ""))})
	if eat_now:
		PlayerManager.apply_consumable(it)
		Events.notify("eat_at", {"location": String(shop.get("location", ""))})
		Events.say("吃掉了%s" % String(it.get("name", "")), "good")
	else:
		PlayerManager.add_item(item_id, 1)
		Events.say("买了%s（%s）" % [String(it.get("name", "")), Fmt.yuan(price)], "good")
	_build()
