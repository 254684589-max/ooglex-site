class_name QuestPickup
extends Interactable
## 任务物品（钱包、包裹、猫……），按 F 拿起。会上下浮动并带一圈光环，方便发现。

var item_id := ""
var quest_id := ""
var _visual: Node3D
var _t := 0.0


func setup(p_item: String, p_quest: String) -> void:
	item_id = p_item
	quest_id = p_quest
	display_name = DataDB.item_name(p_item)
	name = "Pickup_" + p_item
	set_sphere_shape(1.2, Vector3(0, 0.5, 0))
	max_distance = 2.4
	_visual = Node3D.new()
	add_child(_visual)
	var mi := MeshInstance3D.new()
	var mesh: Mesh
	match p_item:
		"lost_cat":
			var sm := SphereMesh.new()
			sm.radius = 0.28
			sm.height = 0.45
			mesh = sm
			mi.material_override = Mats.color(Color(0.95, 0.6, 0.2))
		"parcel":
			var bm := BoxMesh.new()
			bm.size = Vector3(0.6, 0.45, 0.45)
			mesh = bm
			mi.material_override = Mats.color(Color(0.7, 0.55, 0.35))
		_:
			var bm2 := BoxMesh.new()
			bm2.size = Vector3(0.3, 0.06, 0.22)
			mesh = bm2
			mi.material_override = Mats.color(Color(0.4, 0.25, 0.15))
	mi.mesh = mesh
	mi.position = Vector3(0, 0.35, 0)
	_visual.add_child(mi)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.55
	tm.outer_radius = 0.62
	ring.mesh = tm
	ring.material_override = Mats.glow(Color(1.0, 0.85, 0.2))
	ring.position = Vector3(0, 0.05, 0)
	_visual.add_child(ring)


func _process(delta: float) -> void:
	_t += delta
	if _visual != null:
		_visual.position.y = sin(_t * 2.4) * 0.08
		_visual.rotation.y += delta * 0.8


func get_actions(_player: Node) -> Array:
	return [Interactable.action("pickup", "拿起%s" % display_name)]


func perform(_action_key: String, _player: Node) -> void:
	if PlayerManager.add_item(item_id, 1):
		Events.say("拿到了：%s" % display_name, "good")
		AudioManager.play_sfx("pickup")
		Events.notify("pickup", {"item": item_id})
		queue_free()
