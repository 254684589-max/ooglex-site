extends "res://tests/site_shots.gd"
## 主角形象特写（开发用）：正面、四分之三侧面、全身、背面。
##   xvfb-run godot --path . --rendering-driver opengl3 --resolution 900x900 res://tests/char_shots.tscn -- <outdir>


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else "user://char"
	DirAccess.make_dir_recursive_absolute(out)
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
	main.ui.visible = false
	set_scene(16.3, "sunny")
	var p: Player = GameManager.player
	p.teleport(Vector3(-28, 0.1, -10), 0.0)
	await _wait(10)
	var cam := Camera3D.new()
	cam.fov = 35.0
	main.add_child(cam)
	cam.make_current()
	var head := p.global_position + Vector3(0, 1.62, 0)
	# 模型正面朝 -Z
	for spec in [["face", Vector3(0, 0.02, -1.2)], ["face34", Vector3(-0.8, 0.05, -0.9)], ["body", Vector3(0.9, -0.5, -3.2)], ["back", Vector3(0.3, 0.1, 1.4)]]:
		var off: Vector3 = spec[1]
		var target := head if spec[0] != "body" else p.global_position + Vector3(0, 0.95, 0)
		cam.look_at_from_position(target + off, target)
		await _wait(8)
		await _shot(spec[0], 900)
	get_tree().quit()


func _shot(name: String, width: int) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_jpg(out.path_join(name + ".jpg"), 0.9)
	print("shot ", name)
