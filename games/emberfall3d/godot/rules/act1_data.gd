class_name Act1Data
extends RefCounted
## 第一幕（移植自 V0.1）的数据：res://data/act1_items.json、act1_monsters.json、act1_rules.json、act1_dialogs.json（只读、缓存）。
## 三个文件由 tools/port_v01.js 从 V0.1 转换而来（阶段 P1），之后以这三个文件为准。

static var _cache: Dictionary = {}


static func _load(name: String) -> Dictionary:
	if not _cache.has(name):
		var f := FileAccess.open("res://data/act1_%s.json" % name, FileAccess.READ)
		_cache[name] = JSON.parse_string(f.get_as_text()) if f != null else {}
	return _cache[name]


static func items() -> Dictionary:
	return _load("items")


static func monsters() -> Dictionary:
	return _load("monsters")


static func dialogs() -> Dictionary:
	return _load("dialogs")


static func rules() -> Dictionary:
	return _load("rules")


static func base(id: String) -> Dictionary:
	return items().bases[id]


static func affix(id: String) -> Dictionary:
	return items().affixes[id]


static func monster(id: String) -> Dictionary:
	return monsters().monsters[id]
