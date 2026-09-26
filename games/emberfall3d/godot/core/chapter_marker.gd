extends Node3D
## 章节包测试内容的脚本。约定（TECH.md 第 5.3 节）：章节包只放场景与资源，脚本一律留在主包，
## 否则章节包里脚本的 UID 不在主包的 UID 表里，加载时会报警告。
## 场景 res://packs/ch_test/marker.tscn 只存在于 ch_test.pck；能看到这根发光的柱子，就说明章节包下载并挂载成功。

func _ready() -> void:
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.35
	cyl.bottom_radius = 0.5
	cyl.height = 2.6
	mesh.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.8, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.4, 0.75, 1.0)
	mat.emission_energy_multiplier = 1.6
	mesh.material_override = mat
	mesh.position.y = 1.3
	add_child(mesh)
	var light := OmniLight3D.new()
	light.light_color = Color(0.5, 0.8, 1.0)
	light.omni_range = 5.0
	light.light_energy = 1.4
	light.position.y = 2.0
	add_child(light)
