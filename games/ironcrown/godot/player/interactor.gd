class_name Interactor
extends Node
## 交互射线（TECH.md 4.2）：每个物理帧从相机中心往前发 REACH 米的射线（世界层 + 可交互层），
## 第一个碰到的是可交互物体才算目标——隔着墙看不到的东西不能交互。
## 第三人称（2.9）：相机在身后，射线照样从相机穿过屏幕中心（准星对准什么就是什么），但只认离眼睛 REACH 米以内的东西。

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
		var eye := player.aim_origin()
		var length := REACH + from.distance_to(eye)
		var q := PhysicsRayQueryParameters3D.create(from, from - cam.global_transform.basis.z * length,
			Interactable.LAYER_WORLD | Interactable.LAYER_INTERACT, [player.get_rid()])
		var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty() and hit.collider is Interactable and hit.collider.can_interact() and (hit.position as Vector3).distance_to(eye) <= REACH + 0.3:
			found = hit.collider
		elif player.third_person:
			# 越肩视差：近处的东西在准星左边一点，屏幕中心的射线擦过去了；再从眼睛往前看一眼
			var q2 := PhysicsRayQueryParameters3D.create(eye, eye + player.aim_forward() * REACH,
				Interactable.LAYER_WORLD | Interactable.LAYER_INTERACT, [player.get_rid()])
			var hit2 := player.get_world_3d().direct_space_state.intersect_ray(q2)
			if not hit2.is_empty() and hit2.collider is Interactable and hit2.collider.can_interact():
				found = hit2.collider
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
