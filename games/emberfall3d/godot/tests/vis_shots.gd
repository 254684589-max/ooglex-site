extends Node
## 固定机位截图（画质步骤前后对比用，开发用，不在 run_tests.sh 里）：
##   xvfb-run -a godot --path games/emberfall3d/godot --rendering-driver opengl3 --resolution 1280x720 res://tests/vis_shots.tscn -- <输出目录> [画质档：low/medium/high]
## 机位：room（房间，火把与木桩）、hall（大厅战斗，怪物围上来）；floor1 / 3 / 5 / 8（P2 随机地下城四种主题）。

# 截图期间每帧回满血（不改最大生命，界面上显示的仍是正常数值）
var hero: Player


func _process(_delta: float) -> void:
	if hero != null and not hero.dead:
		hero.hp = hero.max_hp


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://shots"
	var tier := args[1] if args.size() > 1 else ""
	DirAccess.make_dir_recursive_absolute(out)
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.use_test_area = true      # 第 0 层用灰盒测试区（P7 起默认是烬原镇）
	main.auto_pack_test = false
	main.run_nav_bench = false
	add_child(main)
	if tier != "" and main.has_method("apply_quality"):
		main.apply_quality(tier)
	hero = main.hero
	await _wait(20)
	for shot in [["room", Vector3(-1.0, 0, -1.5), 0.5], ["hall", Vector3(0, 0, 13), 3.5]]:
		hero.global_position = shot[1]
		main.camera.snap()
		await get_tree().create_timer(shot[2]).timeout
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var path: String = out.path_join("%s%s.png" % [shot[0], ("-" + tier) if tier != "" else ""])
		img.save_png(path)
		print("SHOT ", path)
	# P2：随机地下城（地窖、墓穴首领层、熔渊、深渊），固定种子，主角站在入口旁
	main.run_seed = 1
	for f in [1, 3, 5, 8]:
		main.go_floor(f)
		await get_tree().create_timer(3.8).timeout   # 等楼层名横幅淡出
		await RenderingServer.frame_post_draw
		var img2 := get_viewport().get_texture().get_image()
		var p2: String = out.path_join("floor%d%s.png" % [f, ("-" + tier) if tier != "" else ""])
		img2.save_png(p2)
		print("SHOT ", p2, " draw_calls=", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), " primitives=", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	# P5：地下城里的怪物群与掉落（找一群精英，没有就找第一群；站到旁边，打倒一只看掉落）
	for f in [2, 5]:
		main.go_floor(f)
		await get_tree().create_timer(0.3).timeout
		var sps: Array = main.dungeon.spawns
		if sps.is_empty():
			continue
		var pick: Dictionary = sps[0]
		for sp in sps:
			if sp.champ != "":
				pick = sp
				break
		var c: Vector2i = pick.cell
		hero.global_position = DungeonBuilder.cell_center(DungeonGen.near_free(main.dungeon, c + Vector2i(-2, 1)))
		main.camera.snap()
		await get_tree().create_timer(1.2).timeout
		var nearest: EnemyBase = null
		for e in main.monsters:
			if is_instance_valid(e) and not e.dead and (nearest == null or e.global_position.distance_to(hero.global_position) < nearest.global_position.distance_to(hero.global_position)):
				nearest = e
		if nearest:
			nearest.die()
		await get_tree().create_timer(0.8).timeout
		await RenderingServer.frame_post_draw
		var img3 := get_viewport().get_texture().get_image()
		var p3: String = out.path_join("fight%d%s.png" % [f, ("-" + tier) if tier != "" else ""])
		img3.save_png(p3)
		print("SHOT ", p3, " draw_calls=", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), " primitives=", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), " monsters=", main.monsters.size())
	# P6：背包面板（放几件随机装备，选中一件看说明与比较）
	var irng := RandomNumberGenerator.new()
	irng.seed = 26
	for i in 14:
		hero.progress.sheet.inv.append(ItemGen.generate(irng, 8, {"mul": 4.0}))
	hero.progress.sheet.inv.append(ItemGen.generate(irng, 8, {"rarity": 2, "base": "lsword"}))
	main.inv_panel.open()
	main.inv_panel._select({"where": "inv", "idx": 14})
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img4 := get_viewport().get_texture().get_image()
	var p4: String = out.path_join("inv%s.png" % (("-" + tier) if tier != "" else ""))
	img4.save_png(p4)
	print("SHOT ", p4)
	main.inv_panel.close()
	# P7：烬原镇（开局位置、修道院入口、和伊莲对话、格伦的货架）
	main.use_test_area = false
	main.go_floor(0, "start")
	await get_tree().create_timer(1.0).timeout
	await _shot(out, "town", tier)
	hero.global_position = DungeonBuilder.cell_center(Vector2i(17, 10))
	main.camera.snap()
	await get_tree().create_timer(0.8).timeout
	await _shot(out, "town-gate", tier)
	main._talk(main.npc("elin"))
	await _shot(out, "town-dialog", tier)
	main.dialog_panel.close()
	main.open_shop("smith")
	main.shop_panel.sel = {"kind": "item", "item": main.shop_stock.smith[0]}
	main.shop_panel.refresh()
	await _shot(out, "town-shop", tier)
	main.shop_panel.close()
	# P8：任务标记与小地图、任务日志、地下的回城传送门、自动地图
	hero.global_position = TownGen.to_world(19.5, 21.5)
	main.camera.snap()
	await get_tree().create_timer(0.5).timeout
	await _shot(out, "quest-town", tier)
	main._talk(main.npc("elin"))
	main.dialog_panel.opts.get_child(0).pressed.emit()
	main._talk(main.npc("gren"))
	main.dialog_panel.opts.get_child(0).pressed.emit()
	main._toggle_panel(main.quest_panel)
	await _shot(out, "quest-log", tier)
	main.quest_panel.close()
	main.go_floor(2)
	await get_tree().create_timer(0.5).timeout
	hero.progress.sheet.pots.tp = 1
	main.cast_town_portal()
	await get_tree().create_timer(0.8).timeout
	await _shot(out, "portal", tier)
	main.toggle_map()
	await get_tree().create_timer(0.3).timeout
	await _shot(out, "automap", tier)
	main.toggle_map()
	# 阶段 2.5：特效（火球爆炸与焦痕、寂霜环、怪物烧尽消散）——第 4 层最大的房间中央（没有传送门挡着），主角 12 级
	main.go_floor(4)
	await get_tree().create_timer(0.3).timeout
	for e in main.monsters:
		if is_instance_valid(e):
			e.queue_free()
	var big: Dictionary = main.dungeon.rooms[0]
	for r in main.dungeon.rooms:
		if r.w * r.h > big.w * big.h:
			big = r
	hero.global_position = Vector3((big.cx + 0.5) * DungeonBuilder.TILE, 0, (big.cy + 0.5) * DungeonBuilder.TILE)
	hero.stop()
	main.info.visible = false
	hero.progress.sheet.lvl = 12
	hero.stats_changed()
	main.camera.snap()
	await get_tree().create_timer(0.5).timeout
	Sfx.counts.clear()
	var z1 := Monsters.spawn("zombie", main.stage, hero.global_position + Vector3(-3.0, 0, -3.0), hero, 2)
	var z2 := Monsters.spawn("skel", main.stage, hero.global_position + Vector3(-1.5, 0, 1.0), hero, 2)
	z1.stun_t = 30.0
	z2.stun_t = 30.0
	main.camera.snap()
	await get_tree().create_timer(0.4).timeout
	hero.mp = hero.max_mp
	hero.cast_skill("fireball", z1.global_position)
	for i in 120:
		await get_tree().process_frame
		if Sfx.counts.get("boom", 0) > 0 and not is_instance_valid(hero.last_fireball):
			break
	await _shot(out, "fx-fireball", tier)
	await get_tree().create_timer(0.6).timeout
	hero.mp = hero.max_mp
	hero.skill_cd["nova"] = 0.0
	z2.hp = 5000.0                    # 别让寂霜环直接打死，溶解要从下面那一击开始计时
	hero.cast_skill("nova")
	await get_tree().create_timer(0.25).timeout
	await _shot(out, "fx-nova", tier)
	z2.take_hit({"amount": 99999, "crit": false, "type": "physical"}, Vector3.ZERO, 0.0)
	await get_tree().create_timer(1.35).timeout
	await _shot(out, "fx-dissolve", tier)
	main.info.visible = true
	# P10：木桶、宝箱、神殿与战争迷雾（找一层有神殿和宝箱的，站在神殿旁）
	for f in range(2, 12):
		main.go_floor(f)
		await get_tree().create_timer(0.2).timeout
		var shr: Array = main.stage.get_children().filter(func(n): return n is InteractSpot and n.kind == "shrine")
		var chs: Array = main.stage.get_children().filter(func(n): return n is InteractSpot and n.kind == "chest")
		if not shr.is_empty() and not chs.is_empty():
			for e in main.monsters:
				if is_instance_valid(e):
					e.queue_free()
			hero.global_position = shr[0].global_position + Vector3(2.0, 0, 2.0)
			main.camera.snap()
			await get_tree().create_timer(0.8).timeout
			await _shot(out, "props", tier)
			hero.global_position = chs[0].global_position + Vector3(1.8, 0, 1.8)
			main.camera.snap()
			await get_tree().create_timer(0.3).timeout
			main._use_spot(chs[0])
			await get_tree().create_timer(0.8).timeout
			await _shot(out, "chest-open", tier)
			break
	# P9：两个首领（清掉护卫，站在首领房里；摩登打到二阶段）。之后不再恢复说明文字，首领截图放在最后
	for f in [3, 6]:
		main.go_floor(f)
		await get_tree().create_timer(0.3).timeout
		var b: EnemyBase = main.boss
		for e in main.monsters:
			if is_instance_valid(e) and e != b:
				e.queue_free()
		hero.global_position = b.global_position + Vector3(2.6, 0, 2.6)
		main.camera.snap()
		b.set_physics_process(false)     # 定住首领拍照（不然它马上贴脸）
		main.info.visible = false        # 说明文字挡住画面上方，首领截图时先藏起来
		await get_tree().create_timer(0.5).timeout
		await _shot(out, "boss%d" % f, tier)
		if f == 6:
			b.hp = b.max_hp * 0.45
			b.set_physics_process(true)
			await get_tree().create_timer(0.25).timeout
			b.set_physics_process(false)
			await get_tree().create_timer(0.6).timeout
			await _shot(out, "boss6-phase2", tier)
	get_tree().quit()


func _shot(out: String, name: String, tier: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var p: String = out.path_join("%s%s.png" % [name, ("-" + tier) if tier != "" else ""])
	img.save_png(p)
	print("SHOT ", p, " draw_calls=", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), " primitives=", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame
