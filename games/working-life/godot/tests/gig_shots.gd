extends "res://tests/site_shots.gd"
## 零工截图（开发用）：手机主屏、零工 APP、送外卖途中（状态行 + 箭头）、网约车接乘客。
##   xvfb-run godot --path . --rendering-driver opengl3 --resolution 1280x720 res://tests/gig_shots.tscn -- <outdir>


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else "user://gig"
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
	set_scene(18.5, "sunny")
	Events.panel_requested.emit("phone", {})
	await _wait(10)
	await _shot("phone_home", 1280)
	main.ui.close_all()
	Events.panel_requested.emit("phone", {"app": "gig"})
	await _wait(10)
	await _shot("phone_gig", 1280)
	main.ui.close_all()
	GigManager.accept("delivery")
	var t := GigManager.target()
	var dir: Vector3 = (t["pos"] - p.global_position)
	dir.y = 0.0
	p.teleport(t["pos"] - dir.normalized() * 30.0 + Vector3(0, 0.1, 0), atan2(-dir.x, -dir.z))
	await _wait(40)
	await _shot("delivery", 1280)
	GigManager.cancel()
	EconomyManager.earn(200000, "其他", "测试", true)
	VehicleManager.buy("sedan")
	var car := VehicleManager.node("car1")
	car.enter(p)
	GigManager.accept("ride")
	t = GigManager.target()
	var pos: Vector3 = t["pos"]
	car.place(pos + Vector3(14, 0, 6), 0.0)
	var to: Vector3 = pos - car.global_position
	car.place(car.global_position, atan2(-to.x, -to.z))
	p.camera_rig.yaw = car.rotation.y
	await _wait(40)
	await _shot("ride_pickup", 1280)
	get_tree().quit()
