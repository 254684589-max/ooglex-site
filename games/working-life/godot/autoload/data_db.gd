extends Node
## 数据仓库（自动加载名：DataDB）。
## 启动时读取 res://data/*.json：职业、商品、NPC、任务、事件、住房、地点、课程、投资品、
## 创业、面试题、结局。游戏里所有「内容」都来自这些文件，代码里只写规则。

const FILES := ["jobs", "items", "npcs", "quests", "events", "housing", "locations", "courses",
	"assets", "business", "interview", "endings", "shops", "skills", "transport", "vehicles", "furniture"]

var jobs: Dictionary = {}
var items: Dictionary = {}
var npcs: Dictionary = {}
var quests: Dictionary = {}
var events: Dictionary = {}
var housing: Dictionary = {}
var locations: Dictionary = {}
var courses: Dictionary = {}
var assets: Dictionary = {}
var business: Dictionary = {}
var interview: Dictionary = {}
var endings: Dictionary = {}
var shops: Dictionary = {}
var skills: Dictionary = {}
var transport: Dictionary = {}
var vehicles: Dictionary = {}
var furniture: Dictionary = {}

## 按文件原始顺序保存的 id 列表（字典遍历顺序即插入顺序，这里再存一份方便排序显示）
var order: Dictionary = {}
var load_errors: Array = []


func _init() -> void:
	load_all()


func load_all() -> void:
	load_errors.clear()
	for f in FILES:
		var raw = _read_json("res://data/%s.json" % f)
		var dict := {}
		var ids: Array = []
		if typeof(raw) == TYPE_DICTIONARY and raw.has("list"):
			for entry in raw["list"]:
				if typeof(entry) == TYPE_DICTIONARY and entry.has("id"):
					dict[String(entry["id"])] = entry
					ids.append(String(entry["id"]))
			# 除 list 之外的顶层字段作为元数据保存在 "_meta"
			var meta := {}
			for k in raw:
				if k != "list":
					meta[k] = raw[k]
			dict["_meta"] = meta
		elif typeof(raw) == TYPE_DICTIONARY:
			dict = raw
		else:
			load_errors.append("%s.json 读取失败" % f)
		set(f, dict)
		order[f] = ids


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_error("DataDB: 缺少数据文件 %s" % path)
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var text := f.get_as_text()
	f.close()
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		push_error("DataDB: %s 第 %d 行解析错误：%s" % [path, json.get_error_line(), json.get_error_message()])
		load_errors.append(path)
		return null
	return json.data


func ids(table: String) -> Array:
	return order.get(table, [])


func meta(table: String) -> Dictionary:
	var d: Dictionary = get(table)
	return d.get("_meta", {})


func job(id: String) -> Dictionary:
	return jobs.get(id, {})


func item(id: String) -> Dictionary:
	return items.get(id, {})


func npc(id: String) -> Dictionary:
	return npcs.get(id, {})


func quest(id: String) -> Dictionary:
	return quests.get(id, {})


func location(id: String) -> Dictionary:
	return locations.get(id, {})


func item_name(id: String) -> String:
	return String(item(id).get("name", id))


func npc_name(id: String) -> String:
	return String(npc(id).get("name", id))


func location_name(id: String) -> String:
	return String(location(id).get("name", id))


func skill_name(id: String) -> String:
	return String(skills.get(id, {}).get("name", id))
