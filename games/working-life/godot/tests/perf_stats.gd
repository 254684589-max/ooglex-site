extends Node
## 场景规模统计（开发用）：xvfb-run godot --path . res://tests/perf_stats.tscn
## 输出几个典型视角的绘制调用数、图元数、节点数与灯光数。

func _ready() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.auto_skip_intro = true
	add_child(main)
	await _wait(10)
	main.start_new_game(3)
	for i in 200:
		await _wait(1)
		if GameManager.playing and not main.ui.story.playing:
			break
	var p: Player = GameManager.player
	var meshes := 0
	var verts := 0
	for n in main.city.find_children("*", "MeshInstance3D", true, false):
		meshes += 1
		var m: Mesh = (n as MeshInstance3D).mesh
		if m != null:
			for s in m.get_surface_count():
				verts += (m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	print("城市网格节点 %d 个，顶点 %d 个；灯光 %d 个；碰撞形状 %d 个；Label3D %d 个" % [meshes, verts, main.city.kit.lights.size(), main.city.body.get_child_count(), main.city.find_children("*", "Label3D", true, false).size()])
	print("场景节点总数 %d" % get_tree().get_node_count())
	for view in [["火车站", "train_station", 21.0], ["商务区", "office_tower", 20.0], ["美食街", "restaurant", 22.0], ["公园", "park", 12.0]]:
		TimeManager.set_time(1, float(view[2]) * 60.0)
		var ln := GameManager.lookup("loc:" + String(view[1])) as LocationNode
		p.teleport(ln.front_position() + Vector3(0, 0, 0), ln.front_yaw() + PI)
		await _wait(30)
		var dc := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		var prim := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
		var obj := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
		print("%s：绘制调用 %d，图元 %d，可见物体 %d，FPS %d（软件渲染，仅供参考）" % [view[0], dc, prim, obj, Engine.get_frames_per_second()])
	get_tree().quit()


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame
