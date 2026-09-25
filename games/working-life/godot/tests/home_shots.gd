extends "res://tests/site_shots.gd"
## 装修截图（开发用）：普通公寓全套高档家具 / 全套入门家具、房产 APP、装修页。
##   xvfb-run godot --path . --rendering-driver opengl3 --resolution 1280x720 res://tests/home_shots.tscn -- <outdir>


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else "user://home"
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
	await _wait(60)
	var p: Player = GameManager.player
	p.set_carry("")
	EconomyManager.earn(9000000, "其他", "测试", true)
	HousingManager.buy_home("apartment", false)
	HousingManager.move_into_owned("apartment")
	for tier in [3, 1]:
		for slot in ["tv", "sofa", "rug", "lamp", "art", "bookshelf", "plant", "treadmill", "bedding"]:
			HousingManager.buy_furniture("apartment", "%s_%d" % [slot, tier])
		main.home_decor.refresh()
		set_scene(12.5, "sunny")
		var door := GameManager.lookup("door:apartment") as Node3D
		var xf := door.global_transform
		p.teleport(xf * Vector3(4.0, 0.1, -6.5), 0.0)
		main.ui.visible = false
		var cam := Camera3D.new()
		cam.fov = 62.0
		main.add_child(cam)
		cam.make_current()
		await _wait(20)
		cam.look_at_from_position(xf * Vector3(0.6, 2.5, -0.5), xf * Vector3(-3.4, 0.5, -6.5))
		await _wait(20)
		await _shot("room_t%d_a" % tier, 1280)
		cam.look_at_from_position(xf * Vector3(-1.5, 1.9, -2.2), xf * Vector3(6.0, 0.8, -2.5))
		await _wait(20)
		await _shot("room_t%d_b" % tier, 1280)
		cam.clear_current()
		cam.queue_free()
		p.camera_rig.camera.make_current()
		main.ui.visible = true
	PropertyApp.decor_home = ""
	Events.panel_requested.emit("phone", {"app": "property"})
	await _wait(20)
	await _shot("phone_property", 1280)
	main.ui.close_all()
	PropertyApp.decor_home = "apartment"
	Events.panel_requested.emit("phone", {"app": "property"})
	await _wait(20)
	await _shot("phone_decor", 1280)
	get_tree().quit()
