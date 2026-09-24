class_name EndingSystem
extends RefCounted
## 结局判定：五种人生结局的条件写在 data/endings.json。


static func achieved() -> Array:
	var out: Array = []
	for id in DataDB.ids("endings"):
		if Conditions.check(DataDB.endings[id].get("conditions", {})):
			out.append(id)
	return out


## 达成的结局里优先级最高的
static func best() -> String:
	var best_id := ""
	var best_p := -1
	for id in achieved():
		var p := int(DataDB.endings[id].get("priority", 0))
		if p > best_p:
			best_p = p
			best_id = id
	return best_id


static func data(id: String) -> Dictionary:
	return DataDB.endings.get(id, {})
