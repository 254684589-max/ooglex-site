extends Node
## 生成网站介绍页用的实机截图（JPG）：
##   xvfb-run godot --path . --rendering-driver opengl3 --resolution 1280x720 res://tests/site_shots.tscn -- ../img

var main: Node
var out := "user://site"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.auto_skip_intro = true
	add_child(main)
	await _wait(30)
	await _shot("menu", 960)
	main.start_new_game(3)
	for i in 200:
		await _wait(1)
		if GameManager.playing and not main.ui.story.playing:
			break
	await _wait(260)   # 等开场横幅消失
	var p: Player = GameManager.player
	SettingsManager.values["show_marker"] = false
	# 1. 主图：雨夜的美食街
	set_scene(22.3, "rain")
	_look_at_loc(p, "cafe", 9.0, 0.35, -0.04, 7.5)
	await _wait(60)
	await _shot("hero", 1280)
	# 2. 观景台：黄昏俯瞰
	set_scene(18.7, "cloudy")
	var rp := GameManager.lookup("point:park:rooftop") as Node3D
	p.teleport(rp.global_position + Vector3(0, 0.2, 1.0), 0.0)
	p.camera_rig.yaw = 0.25
	p.camera_rig.pitch = -0.02
	p.camera_rig.distance = 6.0
	await _wait(60)
	await _shot("viewpoint", 960)
	# 2b. 航拍天际线：黄昏与夜景（隐藏界面）
	main.ui.visible = false
	var cam := Camera3D.new()
	cam.far = 1600.0
	cam.fov = 60.0
	main.add_child(cam)
	set_scene(18.5, "sunny")
	cam.look_at_from_position(Vector3(185, 75, 120), Vector3(-80, 30, -60))
	cam.make_current()
	await _wait(40)
	await _shot("skyline", 1280)
	set_scene(21.5, "cloudy")
	cam.look_at_from_position(Vector3(-180, 55, 150), Vector3(0, 20, -40))
	await _wait(40)
	await _shot("skyline_night", 960)
	cam.clear_current()
	cam.queue_free()
	p.camera_rig.camera.make_current()
	main.ui.visible = true
	# 3. 白天的写字楼
	set_scene(10.5, "sunny")
	_look_at_loc(p, "office_tower", 12.0, 0.3, 0.12, 9.0)
	await _wait(60)
	await _shot("day", 960)
	# 4. 手机招聘
	set_scene(19.5, "cloudy")
	_look_at_loc(p, "talent_market", 6.0, 0.2, -0.05, 6.0)
	await _wait(30)
	Events.panel_requested.emit("phone", {"app": "jobs"})
	await _wait(20)
	await _shot("phone", 960)
	main.ui.close_all()
	# 5. 上班小游戏
	var g := CodeGame.new(0)
	main.ui.open(MinigameWindow.new(g))
	await _wait(20)
	await _shot("work", 960)
	main.ui.close_all()
	# 6. 与 NPC 对话（便利店陈叔）
	set_scene(20.0, "cloudy")
	NPCManager.refresh_schedules(true)
	await _wait(5)
	var chen := GameManager.lookup("npc:chenshu") as NPC
	p.teleport(chen.global_position + Vector3(0, 0.1, 2.2), 0.0)
	p.camera_rig.yaw = 0.35
	p.camera_rig.distance = 3.6
	await _wait(20)
	Events.dialogue_requested.emit("chenshu")
	await _wait(20)
	await _shot("talk", 960)
	main.ui.close_all()
	# 7. 地图
	Events.panel_requested.emit("map", {})
	await _wait(20)
	await _shot("map", 960)
	main.ui.close_all()
	get_tree().quit()


func set_scene(hour: float, weather: String) -> void:
	TimeManager.set_time(TimeManager.day, hour * 60.0)
	WeatherManager.set_weather(weather)


func _look_at_loc(p: Player, id: String, back: float, yaw_off: float, pitch: float, dist: float) -> void:
	var ln := GameManager.lookup("loc:" + id) as LocationNode
	var yaw := ln.front_yaw()
	var out_dir := Vector3(sin(yaw), 0, cos(yaw))
	p.teleport(ln.front_position() + out_dir * back, yaw)
	p.camera_rig.yaw = yaw + yaw_off
	p.camera_rig.pitch = pitch
	p.camera_rig.distance = dist


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String, width: int) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if width != img.get_width():
		img.resize(width, int(width * 9.0 / 16.0), Image.INTERPOLATE_LANCZOS)
	img.save_jpg(out.path_join(name + ".jpg"), 0.86)
	print("shot ", name)
