extends Node
## 固定机位截图（画质步骤前后对比用，开发用，不在 run_tests.sh 里）：
##   xvfb-run -a godot --path games/emberfall3d/godot --rendering-driver opengl3 --resolution 1280x720 res://tests/vis_shots.tscn -- <输出目录> [画质档：low/medium/high]
## 机位：room（房间，火把与木桩）、hall（大厅战斗，怪物围上来）。

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://shots"
	var tier := args[1] if args.size() > 1 else ""
	DirAccess.make_dir_recursive_absolute(out)
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.auto_pack_test = false
	main.run_nav_bench = false
	add_child(main)
	if tier != "" and main.has_method("apply_quality"):
		main.apply_quality(tier)
	var hero: Player = main.hero
	hero.max_hp = 1e9
	hero.hp = hero.max_hp
	await _wait(20)
	for shot in [["room", Vector3(-1.0, 0, -1.5), 0.5], ["hall", Vector3(0, 0, 13), 3.5]]:
		hero.global_position = shot[1]
		main.camera.snap()
		await get_tree().create_timer(shot[2]).timeout
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var path: String = out.path_join("%s%s.png" % [shot[0], ("-" + tier) if tier != "" else ""])
		img.save_png(path)
		print("SHOT ", path)
	get_tree().quit()


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame
