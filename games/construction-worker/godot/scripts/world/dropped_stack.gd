class_name DroppedStack
extends Interactable
## 放在地上的材料（不在卸货区）。可以再用 F 拿起来。

var item_id := ""
var count := 0
var _visual: Node3D


func setup(item: String, n: int) -> void:
	item_id = item
	count = n
	display_name = "地上的" + ItemDB.item_name(item)


func _ready() -> void:
	add_to_group("dropped_stack")
	focus_priority = 3
	max_distance = 2.0
	set_sphere_shape(1.2, Vector3(0, 0.5, 0))
	_visual = Node3D.new()
	add_child(_visual)
	_rebuild()


func get_actions(player: Node) -> Array:
	var inv: Inventory = player.inventory
	var item_name := ItemDB.item_name(item_id)
	if not inv.is_empty() and inv.item_id != item_id:
		return [Interactable.action("pickup", "地上有%s（手上满了）" % item_name, false)]
	var room := inv.room_for(item_id)
	if room <= 0:
		return [Interactable.action("pickup", "地上还有%s ×%d，拿不下了" % [item_name, count], false)]
	return [Interactable.action("pickup", "捡起地上的%s（剩 %d）" % [item_name, count])]


func perform(action_key: String, player: Node) -> void:
	if action_key != "pickup":
		return
	var inv: Inventory = player.inventory
	var took := inv.add(item_id, mini(count, inv.room_for(item_id)))
	if took > 0:
		Sfx.play("pickup")
	count -= took
	if count <= 0:
		queue_free()
	else:
		_rebuild()


func _rebuild() -> void:
	for c in _visual.get_children():
		c.queue_free()
	var info := ItemDB.get_item(item_id)
	var size: Vector3 = info.get("size", Vector3(0.3, 0.1, 0.2))
	var mat := Mats.color(info.get("color", Color.GRAY))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(global_position if is_inside_tree() else Vector3.ZERO))
	for i in count:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		mi.material_override = mat
		var layer := int(i / 4.0)
		var k := i % 4
		mi.position = Vector3((k % 2) * size.x * 1.1 - size.x * 0.5, size.y * 0.5 + layer * size.y, int(k / 2.0) * size.z * 1.1 - size.z * 0.5)
		mi.rotation.y = rng.randf_range(-0.25, 0.25)
		_visual.add_child(mi)


func to_dict() -> Dictionary:
	var p := global_position
	return {"item": item_id, "count": count, "pos": [p.x, p.y, p.z]}
