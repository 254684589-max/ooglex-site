extends Node3D
## 程序化角色预览（2.6 之三，开发用，不在 run_tests.sh 里）：
##   xvfb-run -a godot --path games/emberfall3d/godot --rendering-driver opengl3 --resolution 1280x720 res://tests/rig_shots.tscn -- <输出目录>
## 三个角色一排，依次拍：待机、走路、蓄力、出手、受击、倒下；再拍一张游戏镜头角度的近景。

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://rig_shots"
	DirAccess.make_dir_recursive_absolute(out)
	var env := WorldEnvironment.new()
	env.environment = Look.crypt_environment()
	env.environment.ambient_light_energy = 0.8
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_energy = 1.1
	sun.light_color = Color(1.0, 0.85, 0.7)
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 20)
	ground.mesh = pm
	ground.material_override = Look.floor_material()
	add_child(ground)
	var cam := Camera3D.new()
	add_child(cam)
	var rigs: Array = []
	var ids := CharModels.ids()
	for i in ids.size():
		var r := HumanoidRig.create(ids[i])
		r.position = Vector3((i - 1) * 1.3, 0, 0)
		add_child(r)
		rigs.append(r)
		print("RIG ", ids[i], " tris=", r.tris, " build_ms=", CharModels.get_model(ids[i]).build_ms)
	var poses := [["idle", "", "", 0.0, 0.0], ["walk", "", "", 0.0, 4.0], ["windup", "attack", "windup", 1.0, 0.0], ["strike", "attack", "strike", 1.0, 0.0],
		["cast", "cast", "strike", 0.6, 0.0], ["shoot", "shoot", "windup", 1.0, 0.0], ["dead", "", "", 0.0, 0.0]]
	for fr in [["front", Vector3(0, 1.3, 4.2), Vector3(0, 1.0, 0)], ["side", Vector3(4.2, 1.3, 0.3), Vector3(0, 1.0, 0)]]:
		cam.position = fr[1]
		cam.look_at(fr[2])
		for p in poses:
			for r in rigs:
				r.reset_pose()
				r.dead = p[0] == "dead"
			for i in 40:
				for r in rigs:
					if p[1] != "":
						r.act(p[1], p[2], p[3])
					r.tick(0.05 if p[0] != "walk" else 0.013, p[4])
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var path: String = out.path_join("rig-%s-%s.png" % [fr[0], p[0]])
			get_viewport().get_texture().get_image().save_png(path)
			print("SHOT ", path)
	# 游戏镜头（55° 俯角、约 15 米）
	cam.position = Vector3(0, 12.3, 8.6)
	cam.look_at(Vector3(0, 0.8, 0))
	cam.fov = 40
	for r in rigs:
		r.reset_pose()
		for i in 30:
			r.tick(0.02, 4.0)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join("rig-game.png"))
	print("SHOT game")
	get_tree().quit()
