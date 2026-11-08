extends MeshInstance3D
## 跟着镜头走的一大块平面（鹭沼荒野的水面，2026-11-08）：按 SNAP 米跳，高度不变
const SNAP := 50.0


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return
	position.x = snappedf(cam.global_position.x, SNAP)
	position.z = snappedf(cam.global_position.z, SNAP)
