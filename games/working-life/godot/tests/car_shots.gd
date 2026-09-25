extends "res://tests/site_shots.gd"
## 私家车截图（开发用）：四款车并排、开车追尾视角（白天 / 夜里）、手机汽车 APP、手机横屏开车界面。
##   xvfb-run godot --path . --rendering-driver opengl3 --resolution 1280x720 res://tests/car_shots.tscn -- <outdir>


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else "user://cars"
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
	await _wait(120)
	var p: Player = GameManager.player
	EconomyManager.earn(3000000, "其他", "测试", true)
	# 四款车停在同一条路边
	set_scene(16.5, "sunny")
	var ids := ["hatch", "suv", "sports"]
	for i in ids.size():
		VehicleManager.buy(ids[i], i % 2)
	var cars := VehicleManager.nodes()
	for i in cars.size():
		(cars[i] as PlayerCar).place(Vector3(-2.6, 0.02, -60.0 + i * 6.5), PI * 0.5)
	p.teleport(Vector3(-9, 0.1, -40), 0.0)
	main.ui.visible = false
	var cam := Camera3D.new()
	cam.fov = 45.0
	main.add_child(cam)
	cam.make_current()
	cam.look_at_from_position(Vector3(-12.0, 3.2, -34.0), Vector3(-2.6, 0.6, -50.0))
	await _wait(30)
	await _shot("cars_lineup", 1280)
	cam.look_at_from_position(Vector3(-7.0, 1.4, -44.5), Vector3(-2.6, 0.7, -40.5))
	await _wait(10)
	await _shot("cars_sports", 1280)
	cam.clear_current()
	cam.queue_free()
	p.camera_rig.camera.make_current()
	main.ui.visible = true
	# 开车：追尾视角（边开边拍）
	var car: PlayerCar = cars[2]
	for c in cars:
		if c != car:
			(c as PlayerCar).place(Vector3(-150.0, 0.02, 150.0 + cars.find(c) * 8.0), 0.0)
	car.place(Vector3(81.8, 0.02, 60.0), 0.0)
	car.enter(p)
	Input.action_press("move_forward")
	await _wait(100)
	await _shot("drive_day", 1280)
	Input.action_press("move_left")
	await _wait(25)
	await _shot("drive_turn", 1280)
	Input.action_release("move_left")
	Input.action_release("move_forward")
	set_scene(21.5, "sunny")
	car.place(Vector3(78.2, 0.02, -60.0), PI)
	Input.action_press("move_forward")
	await _wait(90)
	await _shot("drive_night", 1280)
	Input.action_release("move_forward")
	await _wait(60)
	car.exit()
	await _wait(10)
	Events.panel_requested.emit("phone", {"app": "cars"})
	await _wait(20)
	await _shot("phone_cars", 1280)
	main.ui.close_all()
	Events.panel_requested.emit("map", {})
	await _wait(20)
	await _shot("map_car", 1280)
	main.ui.close_all()
	# 手机触屏：开车时的按钮
	GameManager.touch_mode = true
	car.enter(p)
	await _wait(20)
	await _shot("drive_touch", 1280)
	get_tree().quit()
