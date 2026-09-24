extends "res://tests/site_shots.gd"
## 触屏布局截图（开发用）：强制触屏模式，按命令行给的分辨率拍游戏画面，检查 HUD 与触屏按钮不重叠。
##   xvfb-run godot --path . --rendering-driver opengl3 --resolution 540x1080 res://tests/touch_shots.tscn -- <outdir> <name>


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else "user://touch"
	var name := args[1] if args.size() > 1 else "touch"
	DirAccess.make_dir_recursive_absolute(out)
	GameManager.touch_mode = true
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.auto_skip_intro = true
	add_child(main)
	await _wait(20)
	main.start_new_game(3)
	for i in 200:
		await _wait(1)
		if GameManager.playing and not main.ui.story.playing:
			break
	await _wait(240)
	set_scene(17.7, "sunny")
	await _wait(30)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_jpg(out.path_join(name + ".jpg"), 0.86)
	print("shot ", name)
	get_tree().quit()
