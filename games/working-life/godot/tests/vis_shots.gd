extends "res://tests/site_shots.gd"
## 画质对比用的快速截图：只拍城市场景（不开面板、不跑小游戏）。
##   xvfb-run godot --path . --rendering-driver opengl3 --resolution 1280x720 res://tests/vis_shots.tscn -- <outdir>


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
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
	var p: Player = GameManager.player
	SettingsManager.values["show_marker"] = false
	main.ui.visible = false
	var cam := Camera3D.new()
	cam.far = 1600.0
	cam.fov = 60.0
	main.add_child(cam)
	for spec in [[18.5, "sunny", "drone_sunset", Vector3(185, 75, 120), Vector3(-80, 30, -60)], [11.0, "sunny", "drone_noon", Vector3(120, 50, 190), Vector3(0, 25, -40)], [21.5, "cloudy", "drone_night", Vector3(-180, 55, 150), Vector3(0, 20, -40)]]:
		set_scene(spec[0], spec[1])
		cam.look_at_from_position(spec[3], spec[4])
		cam.make_current()
		await _wait(30)
		await _shot(spec[2], 1280)
	cam.clear_current()
	p.camera_rig.camera.make_current()
	var rp := GameManager.lookup("point:park:rooftop") as Node3D
	for spec in [[18.4, "sunny", "sunset"], [10.5, "sunny", "noon"], [21.5, "cloudy", "night"]]:
		set_scene(spec[0], spec[1])
		p.teleport(rp.global_position + Vector3(0, 0.2, 1.0), 0.0)
		p.camera_rig.yaw = 0.25
		p.camera_rig.pitch = -0.06
		p.camera_rig.distance = 6.0
		await _wait(40)
		await _shot("roof_" + spec[2], 1280)
	set_scene(17.8, "sunny")
	_look_at_loc(p, "office_tower", 10.0, 0.3, 0.1, 7.0)
	await _wait(40)
	await _shot("street_eve", 1280)
	set_scene(22.3, "rain")
	_look_at_loc(p, "cafe", 9.0, 0.35, -0.04, 7.5)
	await _wait(40)
	await _shot("street_rain", 1280)
	get_tree().quit()
