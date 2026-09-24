class_name Door
extends Interactable
## 可以开关的门：按 E 开门 / 关门。关着的时候挡路。
## 门板绕左侧门轴旋转；局部坐标下门洞沿 X 方向，门板宽 width。

@export var width := 1.0
@export var height := 2.1
@export var door_color := Color(0.55, 0.6, 0.66)
@export var open_angle := 1.7
@export var start_open := false

var is_open := false
var _hinge: Node3D
var _shape: CollisionShape3D
var _tween: Tween


func _ready() -> void:
	focus_priority = 1
	max_distance = 2.2
	set_box_shape(Vector3(width + 1.2, 2.0, 2.4), Vector3(0, 1.0, 0))
	_hinge = Node3D.new()
	_hinge.position = Vector3(-width * 0.5, 0, 0)
	add_child(_hinge)
	var panel := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(width, height, 0.06)
	panel.mesh = bm
	panel.material_override = Mats.color(door_color, 0.6)
	panel.position = Vector3(width * 0.5, height * 0.5, 0)
	_hinge.add_child(panel)
	var knob := MeshInstance3D.new()
	var km := SphereMesh.new()
	km.radius = 0.04
	km.height = 0.08
	knob.mesh = km
	knob.material_override = Mats.color(Color(0.85, 0.8, 0.6), 0.3)
	knob.position = Vector3(width * 0.85, 1.0, -0.06)
	_hinge.add_child(knob)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(width, height, 0.12)
	_shape.shape = box
	_shape.position = Vector3(0, height * 0.5, 0)
	body.add_child(_shape)
	add_child(body)
	set_open(start_open, false)


func get_actions(_player: Node) -> Array:
	return [Interactable.action("interact", "关门" if is_open else "开门")]


func perform(action_key: String, _player: Node) -> void:
	if action_key == "interact":
		set_open(not is_open, true)
		Sfx.play("door", -4.0)


func set_open(value: bool, animate := true) -> void:
	is_open = value
	_shape.set_deferred("disabled", value)
	var goal := -open_angle if value else 0.0
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if animate and is_inside_tree():
		_tween = create_tween()
		_tween.tween_property(_hinge, "rotation:y", goal, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	else:
		_hinge.rotation.y = goal
