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
		var pos := GameManager.location_front(String(s[3]))
		var ln := GameManager.lookup("loc:" + String(s[3])) as LocationNode
		p.teleport(pos, ln.front_yaw() + PI)
		p.camera_rig.yaw = ln.front_yaw() + PI + float(s[5])
		p.camera_rig.pitch = -0.12
		p.camera_rig.distance = 6.5
		await _wait(30)
		await _shot(String(s[0]))
	# 室内
	TimeManager.set_time(1, 20.0 * 60.0)
	var sp := GameManager.lookup("point:store:shop") as Node3D
	p.teleport(sp.global_position + Vector3(0, 0, 2.5), 0.0)
	p.camera_rig.yaw = 0.0
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
	get_tree().quit()


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out.path_join(name + ".png"))
	print("shot ", name)
