extends Node
## 截图工具（开发用）：xvfb-run godot --path . res://tests/shots.tscn -- <输出目录>
## 依次拍：主菜单、火车站门口（夜）、白天街道、室内、雨夜、手机界面、地图。

var main: Node
var out := "user://shots"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await _wait(20)
	await _shot("01_menu")
	SaveManager.current_slot = 3
	main._reset_all()
	main.ui.hide_menu()
	GameManager.set_playing(true)
	main._skip_intro = true
	main._begin_play()
	QuestManager.start("m1_first_day")
	var p: Player = GameManager.player
	var shots := [
		["02_station_night", 21.5, "cloudy", "train_station", 0.0, 0.0],
		["03_street_day", 10.5, "sunny", "store", 0.0, 0.3],
		["04_cbd_dusk", 18.4, "cloudy", "office_tower", 0.0, 0.0],
		["05_rain_night", 23.0, "rain", "restaurant", 0.0, 0.0],
		["06_park_day", 15.0, "sunny", "park", 0.0, 0.0],
		["07_site", 9.0, "cloudy", "construction_site", 0.0, 0.0],
	]
	for s in shots:
		TimeManager.set_time(1, float(s[1]) * 60.0)
		WeatherManager.set_weather(String(s[2]))
		var ln := GameManager.lookup("loc:" + String(s[3])) as LocationNode
		var yaw := ln.front_yaw()
		var out_dir := Vector3(sin(yaw), 0, cos(yaw))
		var pos := ln.front_position() + out_dir * 5.0
		p.teleport(pos, yaw)
		p.camera_rig.yaw = yaw + float(s[5])
		p.camera_rig.pitch = -0.05
		p.camera_rig.distance = 7.0
		await _wait(30)
		await _shot(String(s[0]))
	# 观景台俯瞰
	TimeManager.set_time(1, 20.5 * 60.0)
	WeatherManager.set_weather("cloudy")
	var rp := GameManager.lookup("point:park:rooftop") as Node3D
	p.teleport(rp.global_position + Vector3(0, 0.2, 0), 0.0)
	p.camera_rig.yaw = 0.0
	p.camera_rig.pitch = -0.1
	await _wait(30)
	await _shot("12_viewpoint")
	# 室内
	TimeManager.set_time(1, 20.0 * 60.0)
	var sp := GameManager.lookup("point:store:shop") as Node3D
	p.teleport(sp.global_position + Vector3(0, 0.1, 4.0), 0.0)
	p.camera_rig.yaw = 0.0
	p.camera_rig.distance = 3.5
	await _wait(20)
	await _shot("08_store_inside")
	Events.panel_requested.emit("phone", {"app": ""})
	await _wait(10)
	await _shot("09_phone")
	main.ui.close_all()
	Events.panel_requested.emit("map", {})
	await _wait(10)
	await _shot("10_map")
	main.ui.close_all()
	Events.panel_requested.emit("phone", {"app": "jobs"})
	await _wait(10)
	await _shot("11_jobs")
	main.ui.close_all()
	# 家里
	HousingManager.book_hotel(1)
	var bed := GameManager.lookup("point:hotel:bed") as Node3D
	(GameManager.lookup("door:hotel") as Door).set_open(true)
	p.teleport(bed.global_position + bed.global_transform.basis.z * 3.0 + Vector3(0, 0.1, 0), 0.0)
	p.camera_rig.yaw = bed.global_transform.basis.get_euler().y
	p.camera_rig.distance = 3.0
	await _wait(20)
	await _shot("13_hotel_room")
	# 工作小游戏
	var g := CodeGame.new(0)
	main.ui.open(MinigameWindow.new(g))
	await _wait(10)
	await _shot("14_minigame_code")
	main.ui.close_all()
	var g2 := AnalysisGame.new(0)
	main.ui.open(MinigameWindow.new(g2))
	await _wait(10)
	await _shot("15_minigame_analysis")
	main.ui.close_all()
	SkillManager.set_level("finance", 3)
	Events.panel_requested.emit("phone", {"app": "invest"})
	await _wait(10)
	await _shot("16_invest")
	main.ui.close_all()
	main.ui.show_ending("freedom")
	await _wait(200)
	await _shot("17_ending")
	get_tree().quit()


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out.path_join(name + ".png"))
	print("shot ", name)
