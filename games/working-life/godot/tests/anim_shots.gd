extends Node3D
## 人物动作逐帧图（开发用）：侧面拍待机 / 慢走 / 快走 / 奔跑 / 转身 / 搬箱子 / 坐下各几帧，拼成一张大图。
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1600x900 res://tests/anim_shots.tscn -- <outdir>

const CELL := 240
var out := ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else "user://anim"
	DirAccess.make_dir_recursive_absolute(out)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.6, 0.66)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.62, 0.68)
	env.environment.ambient_light_energy = 0.7
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 0.6, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.42, 0.42, 0.4)
	ground.material_override = gm
	add_child(ground)
	var holder := Node3D.new()
	add_child(holder)
	var m := CharacterModel.new()
	m.skin_color = Color(0.78, 0.58, 0.44)
	m.shirt_color = Color(0.09, 0.09, 0.1)
	m.pants_color = Color(0.1, 0.1, 0.11)
	m.shoe_color = Color(0.08, 0.08, 0.09)
	m.hair_color = Color(0.24, 0.23, 0.22)
	m.hat = "snapback"
	m.jacket = true
	m.earring = true
	m.accent_strip = false
	holder.add_child(m)
	var m2 := CharacterModel.new()
	m2.shirt_color = Color(0.5, 0.1, 0.25)
	m2.pants_color = Color(0.12, 0.12, 0.15)
	m2.hat = "none"
	m2.position = Vector3(0, 0, 0)
	m2.visible = false
	holder.add_child(m2)
	var cam := Camera3D.new()
	cam.fov = 30.0
	add_child(cam)
	cam.make_current()
	await _frames(3)
	var rows := [
		["idle", 0.0, 6, 0.35, "", false],
		["walk_npc", 1.5, 8, 0.0, "", false],
		["walk", 4.4, 8, 0.0, "", false],
		["run", 7.6, 8, 0.0, "", true],
		["carry", 3.4, 6, 0.0, "box", false],
		["suitcase", 3.0, 6, 0.0, "suitcase", false],
	]
	var sheet := Image.create(CELL * 8, CELL * (rows.size() + 2), false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.1, 0.1, 0.1))
	var r := 0
	for row in rows:
		var anim := AnimationController.new(m)
		anim.carrying = String(row[4])
		var speed: float = row[1]
		# 先预热一秒，让幅度稳定
		for i in 60:
			anim.update(1.0 / 60.0, speed, true, bool(row[5]))
		var frames: int = row[2]
		var cycle := _cycle_time(speed)
		var step := cycle / frames if speed > 0.1 else 0.4
		for f in frames:
			var t := 0.0
			while t < step:
				var dt := minf(1.0 / 60.0, step - t)
				anim.update(dt, speed, true, bool(row[5]))
				t += dt
			cam.look_at_from_position(Vector3(4.4, 1.0, 0.4), Vector3(0, 0.9, 0))
			await _frames(2)
			_paste(sheet, f, r)
		r += 1
	# 转身：原地快速左右转
	var anim2 := AnimationController.new(m)
	for f in 8:
		for i in 6:
			holder.rotation.y += 0.09 if f < 4 else -0.09
			anim2.update(1.0 / 60.0, 3.0, true, false)
		cam.look_at_from_position(Vector3(0.3, 1.2, -4.4), Vector3(0, 0.9, 0))
		await _frames(2)
		_paste(sheet, f, r)
	r += 1
	holder.rotation.y = 0.0
	# 坐 / 工作 / 交互 / 跳起
	var anim3 := AnimationController.new(m)
	var poses := ["sit", "work", "interact", "air", "front", "back", "npc", "npc_walk"]
	for f in poses.size():
		var name: String = poses[f]
		anim3 = AnimationController.new(m if not name.begins_with("npc") else m2)
		m.visible = not name.begins_with("npc")
		m2.visible = name.begins_with("npc")
		match name:
			"sit":
				anim3.set_sitting(true)
			"work":
				anim3.state = AnimationController.State.WORK
			"interact":
				anim3.play_once(AnimationController.State.INTERACT)
		for i in (18 if name == "interact" else 60):
			anim3.update(1.0 / 60.0, 1.5 if name == "npc_walk" else 0.0, name != "air", false)
		match name:
			"front":
				cam.look_at_from_position(Vector3(0.0, 1.1, -4.6), Vector3(0, 0.9, 0))
			"back":
				cam.look_at_from_position(Vector3(0.6, 1.2, 4.6), Vector3(0, 0.9, 0))
			_:
				cam.look_at_from_position(Vector3(3.2, 1.1, -3.2), Vector3(0, 0.85, 0))
		await _frames(2)
		_paste(sheet, f, r)
	sheet.save_jpg(out.path_join("anim_sheet.jpg"), 0.88)
	print("wrote ", out.path_join("anim_sheet.jpg"))
	get_tree().quit()


func _cycle_time(speed: float) -> float:
	if speed < 0.1:
		return 2.4
	var probe := AnimationController.new(null)
	if probe.has_method("cycle_time"):
		return probe.call("cycle_time", speed)
	return TAU / (4.0 + speed * 1.6)


func _paste(sheet: Image, col: int, row: int) -> void:
	var img := get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	# 取画面中间的正方形，缩成一格
	var s := mini(img.get_width(), img.get_height())
	var sq := img.get_region(Rect2i((img.get_width() - s) / 2, (img.get_height() - s) / 2, s, s))
	sq.resize(CELL, CELL, Image.INTERPOLATE_BILINEAR)
	sheet.blit_rect(sq, Rect2i(0, 0, CELL, CELL), Vector2i(col * CELL, row * CELL))


func _frames(n: int) -> void:
	for i in n:
		await RenderingServer.frame_post_draw
