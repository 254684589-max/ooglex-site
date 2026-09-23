class_name Inventory
extends Node
## 玩家手上搬着的材料。一次只能搬一种材料，数量受「搬运」等级限制。
## （食物、饮料买了当场吃掉，不进背包；装备记录在 PlayerStats.equipment）

signal changed(item_id: String, count: int)

var item_id := ""
var count := 0


func is_empty() -> bool:
	return count <= 0 or item_id == ""


func capacity_for(id: String) -> int:
	return PlayerStats.carry_capacity(id)


## 还能再拿多少个 id
func room_for(id: String) -> int:
	if not is_empty() and item_id != id:
		return 0
	return maxi(0, capacity_for(id) - count)


## 拿起 n 个，返回实际拿起的数量
func add(id: String, n := 1) -> int:
	var take := mini(n, room_for(id))
	if take <= 0:
		return 0
	item_id = id
	count += take
	changed.emit(item_id, count)
	return take


## 放下 n 个（默认全部），返回实际放下的数量
func remove(n := -1) -> int:
	if is_empty():
		return 0
	var put := count if n < 0 else mini(n, count)
	count -= put
	if count <= 0:
		count = 0
		item_id = ""
	changed.emit(item_id, count)
	return put


func clear() -> void:
	item_id = ""
	count = 0
	changed.emit(item_id, count)


func weight() -> float:
	if is_empty():
		return 0.0
	return ItemDB.weight(item_id) * count


func to_dict() -> Dictionary:
	return {"item": item_id, "count": count}


func from_dict(d: Dictionary) -> void:
	item_id = String(d.get("item", ""))
	count = int(d.get("count", 0))
	if not ItemDB.has(item_id) or count <= 0:
		item_id = ""
		count = 0
	changed.emit(item_id, count)
