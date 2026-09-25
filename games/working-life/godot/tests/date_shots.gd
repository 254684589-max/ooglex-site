extends "res://tests/site_shots.gd"
## 约会截图（开发用）：约会 APP、选地点、山坡夜景聊天、结算表白、在家约会。
##   xvfb-run godot --path . --rendering-driver opengl3 --resolution 1280x720 res://tests/date_shots.tscn -- <outdir>


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else "user://date"
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
	EconomyManager.earn(200000, "其他", "测试", true)
	for id in ["suqing", "xiaomei", "xuys", "chenmo"]:
		NPCManager.change_relation(id, 45)
	set_scene(20.5, "sunny")
	Events.panel_requested.emit("phone", {"app": "romance"})
	await _wait(20)
	await _shot("phone_romance", 1280)
	main.ui.close_all()
	Events.panel_requested.emit("date", {"npc": "suqing"})
	await _wait(10)
	await _shot("date_plan", 1280)
	var w: DateWindow = main.ui.windows.back()
	w._go("night_view")
	await _wait(40)
	await _shot("date_talk", 1280)
	# 窗口外的画面：暂时隐藏界面拍两人
	main.ui.visible = false
	await _wait(5)
	await _shot("date_scene", 1280)
	main.ui.visible = true
	RomanceManager.affection["suqing"] = 60
	for i in 3:
		w._answer(0)
		await _wait(2)
		w._round()
		await _wait(2)
	await _wait(10)
	await _shot("date_finish", 1280)
	get_tree().quit()
