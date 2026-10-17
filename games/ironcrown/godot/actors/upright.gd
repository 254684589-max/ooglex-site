class_name Upright
extends Node3D
## 拿在手里、但不跟着手腕转的东西（A.2b）：提灯总是往下吊着、火把总是朝上、杯子不歪。挂在手上跟着走，每帧把朝向摆正（只转身子朝向）。

func _process(_delta: float) -> void:
	var yaw := get_parent_node_3d().global_basis.get_euler().y if get_parent_node_3d() else 0.0
	global_basis = Basis(Vector3.UP, yaw)
