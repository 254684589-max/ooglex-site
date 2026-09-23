class_name ItemDB
extends RefCounted
## 物品数据表：工地上能搬运的材料。
## 新增材料只需要在 ITEMS 里加一条，然后在地图上放一个 MaterialPile 和 DeliveryZone。

## capacity：按「搬运」技能等级（1~4）一次最多能拿的数量。
## visual："stack" 抱在胸前一摞；"shoulder" 扛在肩上；"bundle" 长条一捆扛肩上。
## stack_grid：在卸货区码放时每层的列数 × 行数。
const ITEMS := {
	"brick": {
		"name": "红砖",
		"unit": "块",
		"weight": 2.5,
		"capacity": [1, 2, 4, 6],
		"size": Vector3(0.26, 0.075, 0.13),
		"color": Color(0.64, 0.24, 0.16),
		"visual": "stack",
		"lift_cost": 0.3,
		"stack_grid": Vector2i(3, 2),
	},
	"cement": {
		"name": "水泥",
		"unit": "袋",
		"weight": 25.0,
		"capacity": [1, 1, 2, 2],
		"size": Vector3(0.52, 0.14, 0.36),
		"color": Color(0.78, 0.76, 0.7),
		"visual": "shoulder",
		"lift_cost": 2.5,
		"stack_grid": Vector2i(2, 2),
	},
	"rebar": {
		"name": "钢筋",
		"unit": "捆",
		"weight": 12.0,
		"capacity": [1, 2, 2, 3],
		"size": Vector3(0.12, 0.12, 2.4),
		"color": Color(0.33, 0.27, 0.24),
		"visual": "bundle",
		"lift_cost": 1.2,
		"stack_grid": Vector2i(5, 1),
	},
}


static func has(item_id: String) -> bool:
	return ITEMS.has(item_id)


static func get_item(item_id: String) -> Dictionary:
	return ITEMS.get(item_id, {})


static func item_name(item_id: String) -> String:
	return String(get_item(item_id).get("name", item_id))


static func unit(item_id: String) -> String:
	return String(get_item(item_id).get("unit", "个"))


static func weight(item_id: String) -> float:
	return float(get_item(item_id).get("weight", 1.0))


static func capacity(item_id: String, level: int) -> int:
	var caps: Array = get_item(item_id).get("capacity", [1])
	if caps.is_empty():
		return 1
	var idx := clampi(level - 1, 0, caps.size() - 1)
	return int(caps[idx])


static func describe(item_id: String, count: int) -> String:
	return "%s ×%d%s" % [item_name(item_id), count, unit(item_id)]
