class_name LocationNode
extends Node3D
## 城市里的一个地点（火车站、便利店、写字楼……）。
## 负责：营业时间判断、门口位置（导航与传送用）、进入范围时通知任务系统「到达某地」、
## 切换室内 / 室外环境声。

var loc_id := ""
var data: Dictionary = {}
var frame: Dictionary = {}
var _area: Area3D


func setup(id: String, d: Dictionary, f: Dictionary) -> void:
	loc_id = id
	data = d
	frame = f
	name = "Loc_" + id
	GameManager.register("loc:" + id, self)
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = 2
	_area.monitorable = false
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	var w: float = f["w"]
	var dd: float = f["d"]
	sh.size = Vector3(w + 6.0, 8.0, dd + 6.0)
	cs.shape = sh
	cs.position = Vector3(0, 4, 0)
	_area.add_child(cs)
	add_child(_area)
	global_transform = Transform3D(f["basis"], f["c"])
	_area.body_entered.connect(_on_enter)
	_area.body_exited.connect(_on_exit)


## 门口外 3 米的位置（世界坐标）
func front_position() -> Vector3:
	var dd: float = frame["d"]
	return BuildingKit.xf(frame, 0, 0.1, dd * 0.5 + 3.0)


func front_yaw() -> float:
	# 站在门口面朝建筑
	return float(frame["yaw"])


func spot_position(spot: String) -> Vector3:
	var s: Dictionary = data.get("spots", {})
	if spot == "front" or not s.has(spot):
		return front_position()
	var p: Array = s[spot]
	return BuildingKit.xf(frame, float(p[0]), 0.05, float(p[1]))


## 营业时间：[开, 关]，关门时间可以超过 24（跨午夜）
static func hours_open(hours: Variant, h: float) -> bool:
	if typeof(hours) != TYPE_ARRAY or (hours as Array).size() < 2:
		return true
	var o := float(hours[0])
	var c := float(hours[1])
	if c > 24.0:
		return h >= o or h < c - 24.0
	return h >= o and h < c


func is_open() -> bool:
	return hours_open(data.get("hours", null), TimeManager.hour_f())


func hours_text() -> String:
	var hrs = data.get("hours", null)
	if typeof(hrs) != TYPE_ARRAY:
		return "24 小时营业"
	return "营业 %02d:00-%02d:00" % [int(hrs[0]), int(hrs[1]) % 24]


func _on_enter(b: Node) -> void:
	if not b.is_in_group("player"):
		return
	GameManager.set_value("current_location", loc_id)
	Events.location_entered.emit(loc_id)
	Events.notify("visit", {"location": loc_id})


func _on_exit(b: Node) -> void:
	if not b.is_in_group("player"):
		return
	if String(GameManager.get_value("current_location", "")) == loc_id:
		GameManager.set_value("current_location", "")
		Events.location_entered.emit("")
