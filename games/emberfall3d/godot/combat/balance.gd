class_name Balance
extends RefCounted
## 读取 res://data/balance.json（只读、缓存）。所有战斗系数都从这里取，不在代码里写死。

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open("res://data/balance.json", FileAccess.READ)
		_data = JSON.parse_string(f.get_as_text())
	return _data


static func skill(id: String) -> Dictionary:
	return data().skills[id]


static func fb() -> Dictionary:
	return data().feedback
