class_name Interactor
extends Node
## 交互射线（TECH.md 4.2）：每个物理帧从相机中心往前发 REACH 米的射线（世界层 + 可交互层），
## 第一个碰到的是可交互物体才算目标——隔着墙看不到的东西不能交互。

signal target_changed(target: Interactable)
signal interacted(result: Dictionary)

const REACH := 2.5

var player: FpController
var target: Interactable


func _physics_process(_delta: float) -> void:
	refresh()


func refresh() -> void:
	var found: Interactable = null
	if player and player.is_inside_tree():
		var cam := player.camera
		var from := cam.global_position
		var q := PhysicsRayQueryParameters3D.create(from, from - cam.global_transform.basis.z * REACH,
			Interactable.LAYER_WORLD | Interactable.LAYER_INTERACT, [player.get_rid()])
		var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty() and hit.collider is Interactable and hit.collider.can_interact():
			found = hit.collider
	if found != target:
		target = found
		target_changed.emit(target)


func use() -> Dictionary:
	if target == null or not is_instance_valid(target):
		return {}
	var result := target.interact(player)
	interacted.emit(result)
	refresh()
	return result
