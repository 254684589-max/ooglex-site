class_name MaterialPile
extends Interactable
## 材料堆（砖块堆放区、水泥库、钢筋堆场）。靠近按 F 拿一个，再按 F 再拿一个，
## 直到达到「搬运」等级允许的上限；按 E 把手上的同种材料放回去。

@export var item_id := "brick"
@export var area_size := Vector3(10, 3, 8)


func _ready() -> void:
	focus_priority = 2
	max_distance = 1.6
	set_box_shape(area_size, Vector3(0, area_size.y * 0.5, 0))


## 到范围边缘的水平距离：站在堆放区里面就是 0
func distance_to_player(player: Node3D) -> float:
	var local := to_local(player.global_position)
	var dx := maxf(absf(local.x) - area_size.x * 0.5, 0.0)
	var dz := maxf(absf(local.z) - area_size.z * 0.5, 0.0)
	return Vector2(dx, dz).length()


func focus_point() -> Vector3:
	return global_position


func get_actions(player: Node) -> Array:
	var inv: Inventory = player.inventory
	var item_name := ItemDB.item_name(item_id)
	if not inv.is_empty() and inv.item_id != item_id:
		return [Interactable.action("pickup", "手上拿着%s，先放下再拿%s" % [ItemDB.item_name(inv.item_id), item_name], false)]
	var cap := inv.capacity_for(item_id)
	var acts: Array = []
	if PlayerStats.stamina <= 0.0:
		acts.append(Interactable.action("pickup", "体力耗尽，拿不动了", false))
	elif inv.count < cap:
		acts.append(Interactable.action("pickup", "拿起%s（%d/%d）" % [item_name, inv.count + 1, cap]))
	else:
		acts.append(Interactable.action("pickup", "%s拿满了（%d/%d），搬运熟练后能拿更多" % [item_name, inv.count, cap], false))
	if inv.item_id == item_id:
		acts.append(Interactable.action("interact", "把%s放回去" % item_name))
	return acts


func perform(action_key: String, player: Node) -> void:
	var inv: Inventory = player.inventory
	match action_key:
		"pickup":
			if inv.add(item_id, 1) > 0:
				Sfx.play("pickup")
				PlayerStats.change_stamina(-float(ItemDB.get_item(item_id).get("lift_cost", 0.5)))
				if not GameState.has_flag("tip_pickup"):
					GameState.set_flag("tip_pickup")
					Events.say("搬得越多走得越慢。拿好了就去亮着黄框的卸货区", "info")
		"interact":
			var n := inv.remove()
			if n > 0:
				Events.say("放回了%s" % ItemDB.describe(item_id, n), "info")
