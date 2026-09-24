class_name Interactable
extends Area3D
## 可交互物体的基类。玩家身上的 InteractionDetector 会在附近的 Interactable 里
## 挑一个「焦点」，把它的动作显示成屏幕中央的按键提示：
##
##   [E] 与工头老王交谈        -> action = "interact"
##   [F] 拿起红砖 (1/2)        -> action = "pickup"
##
## 子类覆盖 get_actions() 与 perform()。
## 动作字典：{"action": "interact"|"pickup", "label": "提示文字", "enabled": true}
## enabled = false 时只显示提示（例如「先放下手里的水泥」），按键无效。

const LAYER := 8

@export var display_name := ""
@export var focus_priority := 0
## 距离超过这个值就不当作焦点（米）
@export var max_distance := 3.2


func _init() -> void:
	collision_layer = LAYER
	collision_mask = 0
	monitoring = false
	monitorable = true


## 以一个盒子作为交互范围
func set_box_shape(size: Vector3, offset := Vector3.ZERO) -> void:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = offset
	add_child(cs)


func set_sphere_shape(radius: float, offset := Vector3.ZERO) -> void:
	var cs := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = radius
	cs.shape = shape
	cs.position = offset
	add_child(cs)


func get_actions(_player: Node) -> Array:
	return []


func perform(_action: String, _player: Node) -> void:
	pass


## 用于判断距离与朝向的参考点
func focus_point() -> Vector3:
	return global_position


## 玩家与交互物之间的距离（子类可以改成「到范围边缘」的距离）
func distance_to_player(player: Node3D) -> float:
	var a := focus_point()
	var b := player.global_position
	return Vector2(a.x - b.x, a.z - b.z).length()


static func action(key: String, label: String, enabled := true) -> Dictionary:
	return {"action": key, "label": label, "enabled": enabled}
