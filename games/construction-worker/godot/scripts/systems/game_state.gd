extends Node
## 全局游戏状态（自动加载名：GameState）。
## 负责：剧情标记、场景对象登记、界面「模态」计数、玩家设置、当前引导目标。

const SETTINGS_PATH := "user://settings.cfg"

## 剧情 / 教学标记，例如 met_wang、intro_done
var flags: Dictionary = {}
## 是否处于游玩状态（标题画面时为 false）
var playing := false
## 玩家节点（Player），由 main.gd 设置
var player: Node3D = null
## 主场景（Main），用于生成地上的散落物等
var world: Node = null
## 场景里需要被引导、地图、存档引用的对象：id -> Node3D
var registry: Dictionary = {}
## 小地图要画的建筑与区域：[{name, rect: Rect2(XZ), color, kind}]
var map_features: Array = []
## 施工楼一层砌筑墙的进度（每完成一次搬砖任务 +1，睡觉后体现在墙体高度上）
var building_progress := 0
## 触屏模式（手机 / 平板）
var touch_mode := false
## 玩家设置
var settings := {
	"mouse_sensitivity": 1.0,
	"invert_y": false,
	"shadows": true,
	"guide": true,
	"msaa": true,
}

var _modal_count := 0


func _enter_tree() -> void:
	InputSetup.register()
	touch_mode = DisplayServer.is_touchscreen_available()
	# 触屏设备默认关掉阴影与抗锯齿，保证手机帧率
	if touch_mode:
		settings["shadows"] = false
		settings["msaa"] = false
	load_settings()


# ---------------------------------------------------------------- 模态界面
## 对话、商店、暂停菜单等打开时调用：玩家停止操作、时间暂停、鼠标释放。
func push_modal() -> void:
	_modal_count += 1


func pop_modal() -> void:
	_modal_count = maxi(0, _modal_count - 1)


func is_modal() -> bool:
	return _modal_count > 0


func clear_modal() -> void:
	_modal_count = 0


# ---------------------------------------------------------------- 标记
func has_flag(flag: String) -> bool:
	return bool(flags.get(flag, false))


func set_flag(flag: String, value := true) -> void:
	flags[flag] = value
	Events.objective_changed.emit()


# ---------------------------------------------------------------- 登记
func register(id: String, node: Node3D) -> void:
	registry[id] = node


func lookup(id: String) -> Node3D:
	var n = registry.get(id)
	if n != null and is_instance_valid(n):
		return n
	return null


func add_map_feature(feature_name: String, rect: Rect2, color: Color, kind := "building") -> void:
	map_features.append({"name": feature_name, "rect": rect, "color": color, "kind": kind})


# ---------------------------------------------------------------- 新游戏
func reset_for_new_game() -> void:
	flags = {}
	building_progress = 0
	clear_modal()


func to_dict() -> Dictionary:
	return {"flags": flags.duplicate(), "building_progress": building_progress}


func from_dict(d: Dictionary) -> void:
	flags = (d.get("flags", {}) as Dictionary).duplicate()
	building_progress = int(d.get("building_progress", 0))


# ---------------------------------------------------------------- 引导目标
## 返回 {"text": 目标描述, "target": 登记 id 或 ""}
func current_objective() -> Dictionary:
	if not has_flag("met_wang"):
		return {"text": "去项目部找工头老王", "target": "npc_wang"}
	var carried_item := ""
	if player != null and player.has_method("carried_item"):
		carried_item = player.carried_item()
	var task: TaskDefinition = TaskSystem.get_active()
	if task != null:
		var obj := TaskSystem.next_open_objective()
		if obj.is_empty():
			return {"text": "回去找老王", "target": "npc_wang"}
		var item := String(obj.get("item", ""))
		var zone := String(obj.get("zone", ""))
		if carried_item == item:
			return {"text": "把%s送到%s" % [ItemDB.item_name(item), zone_name(zone)], "target": zone}
		if carried_item != "":
			return {"text": "先放下手里的%s（按 F）" % ItemDB.item_name(carried_item), "target": ""}
		if PlayerStats.stamina < 8.0:
			return {"text": "体力耗尽了，先歇一会儿或者去吃点东西", "target": ""}
		return {"text": "去%s拿%s" % [pile_name(item), ItemDB.item_name(item)], "target": "pile_" + item}
	if carried_item != "":
		return {"text": "手上的%s用不上，按 F 放下" % ItemDB.item_name(carried_item), "target": ""}
	var hour := TimeSystem.hour()
	if PlayerStats.hunger < 35.0:
		return {"text": "肚子饿了：去食堂吃饭", "target": "shop_canteen"}
	if PlayerStats.thirst < 30.0:
		return {"text": "口渴了：去凉茶桶或小卖部喝水", "target": "water_station"}
	if EconomySystem.meal_tickets > 0 and hour >= 11:
		return {"text": "拿饭票去食堂换一份盒饭", "target": "shop_canteen"}
	if TimeSystem.is_work_hours() and not TaskSystem.available_tasks().is_empty():
		return {"text": "找老王接活", "target": "npc_wang"}
	if TimeSystem.can_sleep():
		return {"text": "天黑了：回宿舍睡觉", "target": "bed_player"}
	return {"text": "今天的活干完了：吃饭、休息，天黑后回宿舍睡觉", "target": "bed_player"}


func zone_name(zone_id: String) -> String:
	var n := lookup(zone_id)
	if n != null and "display_name" in n:
		return String(n.display_name)
	return zone_id


func pile_name(item_id: String) -> String:
	var n := lookup("pile_" + item_id)
	if n != null and "display_name" in n:
		return String(n.display_name)
	return ItemDB.item_name(item_id) + "堆"


# ---------------------------------------------------------------- 设置
func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	for k in settings.keys():
		settings[k] = cfg.get_value("settings", k, settings[k])


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for k in settings.keys():
		cfg.set_value("settings", k, settings[k])
	cfg.save(SETTINGS_PATH)


# ---------------------------------------------------------------- 网页
func is_web() -> bool:
	return OS.has_feature("web")
