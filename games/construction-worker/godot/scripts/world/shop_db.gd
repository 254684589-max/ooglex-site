class_name ShopDB
extends RefCounted
## 商店与商品。effects 里的字段：hunger / thirst / stamina（恢复量）、equip（装备 id）。
## ticket = true 的商品可以用饭票兑换。

const SHOPS := {
	"canteen": {
		"name": "职工食堂",
		"owner": "老陈",
		"greeting": "今天有红烧肉盒饭，管饱！",
		"items": [
			{"id": "box_meal", "name": "红烧肉盒饭", "price": 15, "ticket": true, "desc": "饥饿 +50 · 体力 +12", "effects": {"hunger": 50, "stamina": 12}},
			{"id": "buns", "name": "馒头两个 + 咸菜", "price": 3, "desc": "饥饿 +18", "effects": {"hunger": 18}},
			{"id": "mung_soup", "name": "绿豆汤", "price": 3, "desc": "水分 +25 · 体力 +5", "effects": {"thirst": 25, "stamina": 5}},
			{"id": "water", "name": "矿泉水", "price": 2, "desc": "水分 +35", "effects": {"thirst": 35}},
		],
	},
	"store": {
		"name": "工地小卖部",
		"owner": "扫码自助",
		"greeting": "扫码付款，自觉拿取。",
		"items": [
			{"id": "water", "name": "矿泉水", "price": 2, "desc": "水分 +35", "effects": {"thirst": 35}},
			{"id": "ice_tea", "name": "冰红茶", "price": 4, "desc": "水分 +30 · 体力 +8", "effects": {"thirst": 30, "stamina": 8}},
			{"id": "bread", "name": "面包", "price": 6, "desc": "饥饿 +22", "effects": {"hunger": 22}},
			{"id": "sausage", "name": "火腿肠", "price": 3, "desc": "饥饿 +10", "effects": {"hunger": 10}},
			{"id": "gloves", "name": "劳保手套", "price": 25, "desc": "装备：搬运时体力消耗 -25%（按 2 切换）", "effects": {"equip": "gloves"}},
		],
	},
}


static func get_shop(shop_id: String) -> Dictionary:
	return SHOPS.get(shop_id, {})


## 购买。返回 {"ok": bool, "msg": String}
static func buy(shop_id: String, item: Dictionary, use_ticket := false) -> Dictionary:
	var effects: Dictionary = item.get("effects", {})
	var price := int(item.get("price", 0))
	var item_name := String(item.get("name", ""))
	if effects.has("equip"):
		var eq := String(effects["equip"])
		if PlayerStats.has_equipment(eq):
			return {"ok": false, "msg": "已经有%s了" % item_name}
	elif effects.has("hunger") and not effects.has("thirst") and PlayerStats.hunger >= 96.0:
		return {"ok": false, "msg": "吃不下了，肚子饱饱的"}
	elif effects.has("thirst") and not effects.has("hunger") and PlayerStats.thirst >= 96.0:
		return {"ok": false, "msg": "不渴，喝不下了"}
	if use_ticket:
		if not bool(item.get("ticket", false)) or not EconomySystem.use_meal_ticket():
			return {"ok": false, "msg": "饭票不能换这个"}
	elif not EconomySystem.spend(price, "%s · %s" % [String(get_shop(shop_id).get("name", "")), item_name]):
		return {"ok": false, "msg": "钱不够，还差 ¥%d" % (price - EconomySystem.cash)}
	if effects.has("hunger"):
		PlayerStats.change_hunger(float(effects["hunger"]))
	if effects.has("thirst"):
		PlayerStats.change_thirst(float(effects["thirst"]))
	if effects.has("stamina"):
		PlayerStats.change_stamina(float(effects["stamina"]))
	if effects.has("equip"):
		PlayerStats.equip(String(effects["equip"]))
		PlayerStats.select_tool(1)
	Events.objective_changed.emit()
	var how := "饭票兑换" if use_ticket else "¥%d" % price
	return {"ok": true, "msg": "%s（%s）：%s" % [item_name, how, String(item.get("desc", ""))]}
