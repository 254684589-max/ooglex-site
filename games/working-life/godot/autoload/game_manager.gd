extends Node
## 游戏总状态（自动加载名：GameManager）。
## 负责：是否在游玩、模态窗口计数（打开手机/对话/菜单时暂停时间与操作）、剧情标记、
## 章节、通用键值、世界节点登记表、结局记录、调试模式开关。

signal playing_changed(playing: bool)

var playing := false
var modal_count := 0
## 小游戏进行中（上班）：时间暂停，但 3D 搬运小游戏仍然允许走动
var in_minigame := false
var touch_mode := false
var debug_enabled := false
var player: Node3D = null
var main: Node = null

var chapter := 1
var flags: Dictionary = {}
var values: Dictionary = {}
var endings_seen: Array = []
var infinite_mode := false
## 世界里可被引用的节点：地点触发器、交互点、NPC 等
var registry: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	touch_mode = DisplayServer.is_touchscreen_available() and (OS.has_feature("web_android") or OS.has_feature("web_ios") or OS.has_feature("android") or OS.has_feature("ios"))
	debug_enabled = OS.is_debug_build()
	if OS.has_feature("web"):
		var q = JavaScriptBridge.eval("window.location.search", true)
		if typeof(q) == TYPE_STRING:
			if String(q).contains("dev=1"):
				debug_enabled = true
			if String(q).contains("touch=1"):
				touch_mode = true
			if String(q).contains("touch=0"):
				touch_mode = false


func reset() -> void:
	chapter = 1
	flags.clear()
	values.clear()
	endings_seen.clear()
	infinite_mode = false
	in_minigame = false
	modal_count = 0


func set_playing(p: bool) -> void:
	playing = p
	playing_changed.emit(p)


func is_modal() -> bool:
	return modal_count > 0


func push_modal() -> void:
	modal_count += 1


func pop_modal() -> void:
	modal_count = maxi(0, modal_count - 1)


func clear_modal() -> void:
	modal_count = 0


## 玩家能否自由行动（移动、交互）
func can_act() -> bool:
	return playing and not is_modal()


func set_flag(f: String, on := true) -> void:
	if on:
		flags[f] = true
	else:
		flags.erase(f)
	Events.stats_changed.emit()


func has_flag(f: String) -> bool:
	return flags.has(f)


func set_value(k: String, v: Variant) -> void:
	values[k] = v


func get_value(k: String, default: Variant = null) -> Variant:
	return values.get(k, default)


func set_chapter(c: int) -> void:
	if c == chapter:
		return
	chapter = c
	Events.chapter_changed.emit(c)


func register(id: String, node: Node) -> void:
	registry[id] = node


func unregister(id: String) -> void:
	registry.erase(id)


func lookup(id: String) -> Node:
	var n = registry.get(id)
	if n != null and is_instance_valid(n):
		return n
	return null


## 某地点的世界坐标（门口），找不到返回 Vector3.INF
func location_front(loc_id: String) -> Vector3:
	var n := lookup("loc:" + loc_id)
	if n != null and n.has_method("front_position"):
		return n.front_position()
	return Vector3.INF


func to_dict() -> Dictionary:
	return {"chapter": chapter, "flags": flags.keys(), "values": values, "endings_seen": endings_seen, "infinite": infinite_mode}


func from_dict(d: Dictionary) -> void:
	chapter = int(d.get("chapter", 1))
	flags.clear()
	for f in d.get("flags", []):
		flags[String(f)] = true
	values = d.get("values", {}).duplicate(true)
	endings_seen = Array(d.get("endings_seen", [])).duplicate()
	infinite_mode = bool(d.get("infinite", false))
