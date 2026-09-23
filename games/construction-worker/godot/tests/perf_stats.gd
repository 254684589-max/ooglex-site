extends Node
## 统计场景规模（网格数、顶点数、灯光、文字标签），用来控制网页 / 手机上的渲染负担。
## godot --headless --path games/construction-worker/godot res://tests/perf_stats.tscn

func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var meshes := 0
	var verts := 0
	var labels := 0
	var lights := 0
	var mm := 0
	var shapes := 0
	var stack: Array = [main]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is MeshInstance3D and n.mesh != null:
			meshes += 1
			for s in n.mesh.get_surface_count():
				var arr = n.mesh.surface_get_arrays(s)
				verts += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		elif n is MultiMeshInstance3D:
			mm += 1
		elif n is Label3D:
			labels += 1
		elif n is Light3D:
			lights += 1
		elif n is CollisionShape3D:
			shapes += 1
	print("MeshInstance3D: %d  顶点: %d  MultiMesh: %d  Label3D: %d  灯光: %d  碰撞形状: %d" % [meshes, verts, mm, labels, lights, shapes])
	get_tree().quit(0)
