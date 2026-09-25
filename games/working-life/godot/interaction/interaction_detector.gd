class_name InteractionDetector
extends Area3D
## 挂在玩家身上，给每个按键分别找出最合适的交互对象：
##   E（interact）可能是「与陈叔交谈」，同时 F（pickup）是「使用 ATM」——
## 两个提示一起显示，互不遮挡。

signal focus_changed(target: Interactable)

const ACTION_ORDER := ["interact", "pickup"]

var player: Node3D
## 综合得分最高的交互对象（用于引导、测试）
var focus: Interactable = null
var _candidates: Array = []
## 当前显示的动作：[{action, label, enabled, target}]
var _actions: Array = []


func _ready() -> void:
	collision_layer = 0
	collision_mask = Interactable.LAYER
	monitoring = true
	monitorable = false
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)


func _on_area_entered(area: Area3D) -> void:
	if area is Interactable and not _candidates.has(area):
		_candidates.append(area)


func _on_area_exited(area: Area3D) -> void:
	_candidates.erase(area)


func refresh() -> void:
	if player == null:
		return
	var fwd: Vector3 = -player.global_transform.basis.z
	if player.has_method("facing_direction"):
		fwd = player.facing_direction()
	var best_by_key: Dictionary = {}
	var best_any: Interactable = null
	var best_any_score := -INF
	for c in _candidates.duplicate():
		if not is_instance_valid(c) or not c.is_inside_tree():
			_candidates.erase(c)
			continue
		var it: Interactable = c
		# 开车时只能和自己的车交互（下车），不能开着车进门、买东西
		var veh = player.get("vehicle")
		if veh != null and not (it is PlayerCar.CarDoor and (it as PlayerCar.CarDoor).car == veh):
			continue
		if not it.visible:
			continue
		var dist := it.distance_to_player(player)
		if dist > it.max_distance:
			continue
		var acts: Array = it.get_actions(player)
		if acts.is_empty():
			continue
		var to := it.focus_point() - player.global_position
		to.y = 0.0
		var facing := 1.0
		if to.length() > 0.05:
			facing = fwd.dot(to.normalized())
		var score := float(it.focus_priority) * 10.0 - dist - (1.0 - facing) * 0.9
		if score > best_any_score:
			best_any_score = score
			best_any = it
		for a in acts:
			var key := String(a.get("action", ""))
			# 可用的动作优先于只是提示的动作
			var s := score + (100.0 if bool(a.get("enabled", true)) else 0.0) + float(a.get("boost", 0.0))
			if not best_by_key.has(key) or s > float(best_by_key[key]["score"]):
				var entry: Dictionary = a.duplicate()
				entry["target"] = it
				entry["score"] = s
				best_by_key[key] = entry
	_actions = []
	for key in ACTION_ORDER:
		if best_by_key.has(key):
			_actions.append(best_by_key[key])
	if best_any != focus:
		focus = best_any
		focus_changed.emit(focus)


func current_actions() -> Array:
	return _actions


## 当前某个按键对应的交互对象
func target_for(action_key: String) -> Interactable:
	for a in _actions:
		if String(a.get("action", "")) == action_key:
			var t = a.get("target")
			if t != null and is_instance_valid(t):
				return t
	return null


## 执行动作，找到对应动作返回 true
func perform(action_key: String) -> bool:
	for a in _actions:
		if String(a.get("action", "")) != action_key:
			continue
		var target = a.get("target")
		if target == null or not is_instance_valid(target):
			return false
		if not bool(a.get("enabled", true)):
			Events.say(String(a.get("label", "")), "warn")
			return true
		(target as Interactable).perform(action_key, player)
		refresh()
		return true
	return false


func has_action(action_key: String) -> bool:
	return target_for(action_key) != null
