class_name Door
extends Interactable
## 住房的房门：只有租下（或在旅馆开了房）才能进。门板是带碰撞的静态体，打开时旋转 90° 并关闭碰撞。

var loc_id := ""
var is_open := false
var _hinge: Node3D
var _panel_body: StaticBody3D
var _shape: CollisionShape3D
var _target_angle := 0.0


func setup(p_loc: String, width := 1.6, height := 2.5) -> void:
	loc_id = p_loc
	display_name = "房门"
	name = "Door_" + p_loc
	set_box_shape(Vector3(width + 1.6, 2.4, 2.6), Vector3(0, 1.2, 0))
	max_distance = 2.6
	_hinge = Node3D.new()
	_hinge.position = Vector3(-width * 0.5, 0, 0)
	add_child(_hinge)
	_panel_body = StaticBody3D.new()
	_panel_body.collision_layer = 1
	_hinge.add_child(_panel_body)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(width, height, 0.08)
	mi.mesh = bm
	mi.material_override = Mats.color(Color(0.22, 0.24, 0.3), 0.5)
	mi.position = Vector3(width * 0.5, height * 0.5, 0)
	_panel_body.add_child(mi)
	var strip := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.05, height * 0.8, 0.1)
	strip.mesh = sm
	strip.material_override = Mats.glow(Color(0.2, 0.9, 1.0))
	strip.position = Vector3(width - 0.15, height * 0.5, 0)
	_panel_body.add_child(strip)
	_shape = CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(width, height, 0.12)
	_shape.shape = bs
	_shape.position = Vector3(width * 0.5, height * 0.5, 0)
	_panel_body.add_child(_shape)
	Events.housing_changed.connect(_refresh)


func can_enter() -> bool:
	return HousingManager.can_enter(loc_id)


func get_actions(_player: Node) -> Array:
	if is_open:
		return [Interactable.action("interact", "关门")]
	if can_enter():
		return [Interactable.action("interact", "开门（你的房间）")]
	return [Interactable.action("interact", "房门锁着——这不是你的房间", false)]


func perform(_action_key: String, _player: Node) -> void:
	if is_open:
		set_open(false)
	elif can_enter():
		set_open(true)


func set_open(o: bool) -> void:
	is_open = o
	_target_angle = -PI * 0.5 if o else 0.0
	_shape.set_deferred("disabled", o)
	AudioManager.play_sfx("door")


func _refresh() -> void:
	if is_open and not can_enter():
		set_open(false)


func _process(delta: float) -> void:
	if _hinge != null:
		_hinge.rotation.y = lerp_angle(_hinge.rotation.y, _target_angle, clampf(delta * 6.0, 0.0, 1.0))
