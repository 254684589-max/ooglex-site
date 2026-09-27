extends Node3D
## 程序化角色预览（2.6 之三，开发用，不在 run_tests.sh 里）：
##   xvfb-run -a godot --path games/emberfall3d/godot --rendering-driver opengl3 --resolution 1280x720 res://tests/rig_shots.tscn -- <输出目录> [只拍第几组]
## 每三个角色一组排成一排，依次拍各种姿势（待机、走路、挥砍、施法、双手施法、抓挠、冲锋、拉弓、倒下），再拍一张游戏镜头角度的近景。

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://rig_shots"
	Look.photo_enabled = false         # 软件渲染下压缩贴图很慢，预览用程序化地面
	DirAccess.make_dir_recursive_absolute(out)
	var env := WorldEnvironment.new()
	env.environment = Look.crypt_environment()
	env.environment.ambient_light_energy = 0.8
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_energy = 1.1
	sun.light_color = Color(1.0, 0.85, 0.7)
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 20)
	ground.mesh = pm
	ground.material_override = Look.floor_material()
	add_child(ground)
	var cam := Camera3D.new()
	add_child(cam)
	var all_ids := CharModels.ids()
	if args.size() > 1 and args[1] == "props":
		await _props(cam, out)
		get_tree().quit()
		return
	if args.size() > 1 and args[1] == "props2":
		await _props2(cam, out)
		get_tree().quit()
		return
	if args.size() > 1 and args[1] == "props3":
		await _props3(cam, out)
		get_tree().quit()
		return
	var only := int(args[1]) if args.size() > 1 else -1       # 第二个参数：只拍第几组（0 起）；"props"：拍道具与房屋（2.6 之五）；"props2"：树、地面装饰、训练木桩（2.6 之六）；"props3"：火把、楼梯、篝火火苗（2.6 之七）
	for g in ceili(all_ids.size() / 3.0):
		if only < 0 or only == g:
			await _group(cam, all_ids.slice(g * 3, g * 3 + 3), out, g)
	get_tree().quit()


func _group(cam: Camera3D, ids: Array, out: String, g: int) -> void:
	var rigs: Array = []
	for i in ids.size():
		var r := CharRig.create(ids[i])
		r.position = Vector3((i - 1) * 1.4, 0, 0)
		add_child(r)
		rigs.append(r)
		print("RIG ", ids[i], " tris=", r.tris, " build_ms=", CharModels.get_model(ids[i]).build_ms)
	var poses := [["idle", "", "", 0.0, 0.0], ["walk", "", "", 0.0, 4.0], ["windup", "attack", "windup", 1.0, 0.0], ["strike", "attack", "strike", 1.0, 0.0],
		["cast", "cast", "strike", 0.6, 0.0], ["cast2", "cast2", "windup", 1.0, 0.0], ["claw", "claw", "windup", 1.0, 0.0], ["charge", "charge", "windup", 1.0, 0.0],
		["shoot", "shoot", "windup", 1.0, 0.0], ["bite", "bite", "strike", 0.6, 0.0], ["dead", "", "", 0.0, 0.0]]
	cam.fov = 75
	for fr in [["front", Vector3(0, 1.3, 4.6), Vector3(0, 1.0, 0)], ["side", Vector3(4.6, 1.3, 0.3), Vector3(0, 1.0, 0)]]:
		cam.position = fr[1]
		cam.look_at(fr[2])
		for p in poses:
			for r in rigs:
				r.reset_pose()
				r.dead = p[0] == "dead"
			for i in 40:
				for r in rigs:
					if p[1] != "":
						r.act(p[1], p[2], p[3])
					r.tick(0.05 if p[0] != "walk" else 0.013, p[4])
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var path: String = out.path_join("rig%d-%s-%s.png" % [g, fr[0], p[0]])
			get_viewport().get_texture().get_image().save_png(path)
			print("SHOT ", path)
	# 游戏镜头（55° 俯角、约 15 米）
	cam.position = Vector3(0, 12.3, 8.6)
	cam.look_at(Vector3(0, 0.8, 0))
	cam.fov = 40
	for r in rigs:
		r.reset_pose()
		for i in 30:
			r.tick(0.02, 4.0)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join("rig%d-game.png" % g))
	print("SHOT game")
	for r in rigs:
		r.queue_free()


func _props(cam: Camera3D, out: String) -> void:
	## 道具一排（木桶、宝箱开盖与合盖、神殿、水井、铁砧、传送石、篝火）+ 后面一栋房子（灰泥墙 + 石板瓦 + 木构架）
	var row := [["barrel", -4.2], ["chest", -3.0], ["shrine", -1.6], ["well", 0.3], ["anvil", 2.1], ["waystone", 3.3], ["campfire", 4.6]]
	for it in row:
		var mi := PropModels.instance(it[0])
		mi.position = Vector3(it[1], 0, 1.5)
		add_child(mi)
		if it[0] == "chest":
			var lid := PropModels.instance("chest_lid")
			lid.position = Vector3(it[1], 0.5, 1.5 - 0.275)
			lid.rotation_degrees.x = -70
			add_child(lid)
		if it[0] == "shrine":
			var cr := MeshInstance3D.new()
			cr.mesh = PropModels.get_model("shrine_crystal").mesh
			var gm := StandardMaterial3D.new()
			gm.emission_enabled = true
			gm.emission = Color(0.45, 0.8, 1.0)
			gm.emission_energy_multiplier = 3.0
			cr.material_override = gm
			cr.position = Vector3(it[1], 1.5, 1.5)
			add_child(cr)
	var r := Rect2i(-2, -4, 4, 3)
	var walls := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(r.size.x * 2.0, DungeonBuilder.WALL_H, r.size.y * 2.0)
	walls.mesh = bm
	walls.material_override = Look.surface_material("wall_house")
	walls.position = Vector3((r.position.x + r.size.x / 2.0) * 2.0, DungeonBuilder.WALL_H / 2.0, (r.position.y + r.size.y / 2.0) * 2.0)
	add_child(walls)
	var roof := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(r.size.x * 2.0 + 0.8, 2.2, r.size.y * 2.0 + 0.8)
	roof.mesh = pm
	roof.material_override = Look.surface_material("roof")
	roof.position = walls.position + Vector3(0, DungeonBuilder.WALL_H / 2.0 + 1.1, 0)
	add_child(roof)
	add_child(PropModels.house(r, Vector2i(0, 1), 1))
	var i := 0
	for view in [[Vector3(0, 3.2, 9.5), Vector3(0, 1.2, 0)], [Vector3(-5.5, 3.5, 7.5), Vector3(-2, 0.8, 1.5)], [Vector3(5.0, 3.2, 7.0), Vector3(2.5, 0.8, 1.5)], [Vector3(0, 12.3, 8.6 + 1.5), Vector3(0, 0.8, 0)]]:
		cam.position = view[0]
		cam.look_at(view[1])
		cam.fov = 60 if i < 3 else 40
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out.path_join("props-%d.png" % i))
		print("SHOT props-%d" % i)
		i += 1


func _props2(cam: Camera3D, out: String) -> void:
	## 2.6 之六：后排三种树（针叶、阔叶、枯树各两棵），前面训练木桩，地上散着腿骨、头骨、碎石和熔岩裂缝
	var trees := [["tree_pine", -5.0, -3.0, 1.0], ["tree_broad", -2.2, -4.0, 1.1], ["tree_dead", 0.6, -3.2, 1.0], ["tree_pine", 3.2, -4.2, 1.25], ["tree_broad", 5.8, -3.0, 0.9], ["tree_dead", -7.4, -4.5, 1.2]]
	for t in trees:
		var mi := PropModels.instance(t[0])
		mi.position = Vector3(t[1], 0, t[2])
		mi.scale = Vector3.ONE * float(t[3])
		mi.rotation.y = t[1]
		add_child(mi)
	var dummy := PropModels.instance("dummy")
	dummy.position = Vector3(-2.2, 0, 1.2)
	add_child(dummy)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var scatter := [["bone", 5], ["skull", 3], ["rock", 9], ["lava_crack", 3]]
	for sc in scatter:
		for k in int(sc[1]):
			var mi := PropModels.instance(sc[0])
			mi.position = Vector3(rng.randf_range(0.2, 4.2), 0.04 if sc[0] == "bone" else 0.02, rng.randf_range(0.2, 3.0))
			mi.rotation.y = rng.randf() * TAU
			if sc[0] == "skull" and k == 1:
				mi.rotation.z = -1.2
				mi.position.y = 0.06
			add_child(mi)
	var i := 0
	for view in [[Vector3(0, 3.0, 10.0), Vector3(0, 2.0, -2.0)], [Vector3(2.2, 2.2, 5.6), Vector3(2.2, 0.0, 1.6)], [Vector3(-2.2, 1.6, 4.4), Vector3(-2.2, 1.2, 1.2)], [Vector3(0, 12.3, 10.1), Vector3(0, 0.8, 0)]]:
		cam.position = view[0]
		cam.look_at(view[1])
		cam.fov = 60 if i < 3 else 40
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out.path_join("props2-%d.png" % i))
		print("SHOT props2-%d" % i)
		i += 1


func _props3(cam: Camera3D, out: String) -> void:
	## 2.6 之七：后面一堵墙挂两支火把，前面下楼梯、上楼梯，右边篝火（只有火苗的 Torch）
	var wall := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(12, DungeonBuilder.WALL_H, 0.6)
	wall.mesh = bm
	wall.material_override = Look.wall_material()
	wall.position = Vector3(0, DungeonBuilder.WALL_H / 2.0, -3.3)
	add_child(wall)
	for x in [-2.5, 2.5]:
		var t := Torch.new()
		add_child(t)
		t.position = Vector3(x, 1.8, -3.0 + 0.12)
	var down := Stairs.make("down", "↓ 下一层")
	add_child(down)
	down.position = Vector3(-2.0, 0, 0.0)
	var up := Stairs.make("up", "↑ 上一层")
	add_child(up)
	up.position = Vector3(1.4, 0, -0.6)
	var cf := PropModels.instance("campfire")
	cf.position = Vector3(4.4, 0, 1.2)
	add_child(cf)
	var fire := Torch.new()
	fire.mounted = false
	add_child(fire)
	fire.position = Vector3(4.4, 0.55, 1.2)
	fire.scale = Vector3.ONE * 2.2
	await get_tree().create_timer(0.3).timeout
	var i := 0
	for view in [[Vector3(0, 3.4, 7.5), Vector3(0, 1.0, -1.0)], [Vector3(-1.6, 2.2, -1.2), Vector3(-2.5, 1.6, -3.0)], [Vector3(-2.0, 3.2, 3.0), Vector3(-2.0, 0.0, 0.0)], [Vector3(0, 12.3, 10.1), Vector3(0, 0.8, 0)]]:
		cam.position = view[0]
		cam.look_at(view[1])
		cam.fov = 60 if i < 3 else 40
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out.path_join("props3-%d.png" % i))
		print("SHOT props3-%d" % i)
		i += 1
