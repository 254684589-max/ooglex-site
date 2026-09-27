extends Node
## 固定机位截图（画质步骤前后对比用，开发用，不在 run_tests.sh 里）：
##   xvfb-run -a godot --path games/emberfall3d/godot --rendering-driver opengl3 --resolution 1280x720 res://tests/vis_shots.tscn -- <输出目录> [画质档：low/medium/high] [proc：用程序化贴图]
## 机位：room（房间，火把与木桩）、hall（大厅战斗，怪物围上来）；floor1 / 3 / 5 / 8（P2 随机地下城四种主题）。
## 第四个参数 six：只拍 2.6 之六的三张近景（dummy 训练木桩、town-trees 镇外树林、deco 熔渊地面装饰）；
## seven：只拍 2.6 之七的四张近景（stairs-down / stairs-up 第 2 层的上下楼梯、torch 墙上的火把、town-fire 镇上的篝火）。

# 截图期间每帧回满血（不改最大生命，界面上显示的仍是正常数值）
var hero: Player


func _process(_delta: float) -> void:
	if hero != null and not hero.dead:
		hero.hp = hero.max_hp


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://shots"
	var tier := args[1] if args.size() > 1 else ""
	if args.size() > 2 and args[2] == "proc":
		Look.photo_enabled = false
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
	if args.size() > 3 and args[3] == "six":
		await _shots_six(main, out, tier)
		get_tree().quit()
		return
	if args.size() > 3 and args[3] == "seven":
		await _shots_seven(main, out, tier)
		get_tree().quit()
		return
	for shot in [["room", Vector3(-1.0, 0, -1.5), 0.5], ["hall", Vector3(0, 0, 13), 3.5]]:
		hero.global_position = shot[1]
		main.camera.snap()
		await get_tree().create_timer(shot[2]).timeout
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var path: String = out.path_join("%s%s.png" % [shot[0], ("-" + tier) if tier != "" else ""])
		img.save_png(path)
		print("SHOT ", path)
	# 2.6 之三：骨骼角色近景（测试区房间：主角举剑，两只骸骨战士与一只骸骨弓手围上来）
	# 先清掉测试区原有的怪（大厅那一拍惊动的怪会一路追回房间，挤在主角身边挡镜头）
	for m0 in main.monsters:
		if is_instance_valid(m0):
			m0.queue_free()
	main.monsters.clear()
	var skels: Array = []
	for sp in [["skel", Vector3(0.6, 0, 1.6)], ["skel", Vector3(-1.4, 0, 1.2)], ["archer", Vector3(1.8, 0, 3.4)]]:
		var e := Monsters.spawn(sp[0], main.stage, (sp[1] as Vector3) + Vector3(-1.0, 0, -1.5), hero)
		e.set_physics_process(false)
		e.face(hero.global_position)
		skels.append(e)
	hero.global_position = Vector3(-1.0, 0, -1.5)
	hero.face_point(skels[0].global_position)
	var dist0: float = main.camera.distance
	main.camera.distance = main.camera.min_distance      # 镜头拉到最近
	main.camera.snap()
	hero._start_action("oath_cleave")
	skels[0].set_state("windup")
	skels[2].set_state("windup")
	for i in 12:
		await get_tree().process_frame
	await _shot(out, "rig-fight", tier)
	for e in skels:
		e.queue_free()
	# 第二批：腐尸、食尸鬼、堕落骑士、邪教术士、灰誓祭司、焦骨蛮兵围着主角
	var b2: Array = []
	# 围成一圈（半径 2.8 米）：镜头在 +X +Z 方向，大个子（蛮兵、骑士）站在远处，矮的腐尸站在镜头这边，都不挡主角
	var ring := [["zombie", 45.0], ["knight", 150.0], ["cultist", -30.0], ["ghoul", 100.0], ["ash_priest", 0.0], ["ash_brute", 280.0]]
	for sp in ring:
		var a := deg_to_rad(sp[1])
		var e2 := Monsters.spawn(sp[0], main.stage, hero.global_position + Vector3(cos(a), 0, sin(a)) * 2.8, hero)
		e2.set_physics_process(false)
		e2.face(hero.global_position)
		b2.append(e2)
	await get_tree().create_timer(0.3).timeout
	b2[0].set_state("windup")
	b2[1].set_state("windup")
	b2[2].set_state("windup")
	b2[4].mode = 1
	b2[4].set_state("windup")
	for i in 14:
		await get_tree().process_frame
	await _shot(out, "rig-fight2", tier)
	for e in b2:
		e.queue_free()
	# 第三批：火坑小鬼与熔渊猎犬（四足）
	var b3: Array = []
	for sp in [["imp", 30.0], ["imp", 75.0], ["imp", -20.0], ["hound", 150.0], ["hound", 250.0]]:
		var a3 := deg_to_rad(sp[1])
		var e3 := Monsters.spawn(sp[0], main.stage, hero.global_position + Vector3(cos(a3), 0, sin(a3)) * 2.6, hero)
		e3.set_physics_process(false)
		e3.face(hero.global_position)
		b3.append(e3)
	await get_tree().create_timer(0.3).timeout
	b3[0].set_state("windup")
	b3[3].set_state("windup")
	for i in 14:
		await get_tree().process_frame
	await _shot(out, "rig-fight3", tier)
	for e in b3:
		e.queue_free()
	main.camera.distance = dist0
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
	# 2.6 之四 / 之五：铁匠铺（灰泥石墙、石板瓦房顶、木构架、门、亮灯的窗、烟囱）——主角站在门前，镜头拉近
	var smith: Dictionary = main.town.houses.filter(func(hs): return hs.id == "smith")[0] if "town" in main and main.town else {}
	var sr: Rect2i = smith.rect if not smith.is_empty() else Rect2i(6, 12, 4, 3)
	var dd := TownBuilder.door_dir(sr, TownGen.generate().paths)
	var door_cell := sr.position + sr.size / 2 + Vector2i(dd.x * (sr.size.x / 2 + 2), dd.y * (sr.size.y / 2 + 2))
	hero.global_position = DungeonBuilder.cell_center(door_cell) + Vector3(1.2, 0, 0.6)
	var d0: float = main.camera.distance
	main.camera.distance = main.camera.min_distance
	main.camera.snap()
	await get_tree().create_timer(0.8).timeout
	await _shot(out, "town-house", tier)
	main.camera.distance = d0
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
	# 2.6 画质样板间：第 4 层，站在一面有火把的北墙前，镜头拉到最近，看墙脚石基、压檐、壁柱、石块法线与墙脚遮蔽
	main.go_floor(4)
	await get_tree().create_timer(0.3).timeout
	for e in main.monsters:
		if is_instance_valid(e):
			e.queue_free()
	for tc in main.dungeon.torches:
		var c: Vector2i = tc.cell
		if tc.face == Vector2i(0, 1) and DungeonGen.walkable(DungeonGen.tile(main.dungeon, c.x, c.y + 3)) and DungeonGen.walkable(DungeonGen.tile(main.dungeon, c.x + 1, c.y + 2)):
			hero.global_position = DungeonBuilder.cell_center(c) + Vector3(1.2, 0, 4.6)
			break
	hero.stop()
	main.info_row.visible = false
	main.camera.distance = main.camera.min_distance
	main.camera.snap()
	await get_tree().create_timer(0.6).timeout
	await _shot(out, "kit-room", tier)
	main.camera.distance = 15.0
	main.info_row.visible = true
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
	main.info_row.visible = false
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
	main.info_row.visible = true
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
		main.info_row.visible = false        # 说明那一行挡住画面左上角，首领截图时先藏起来
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


func _shots_six(main: Node, out: String, tier: String) -> void:
	## 2.6 之六：训练木桩、镇外树林、熔渊地面装饰（白骨、头骨、碎石、熔岩裂缝）近景
	for e in main.monsters:
		if is_instance_valid(e):
			e.queue_free()
	main.monsters.clear()
	var d0: float = main.camera.distance
	var dm: TrainingDummy = main.dummies[0]
	hero.global_position = dm.global_position + Vector3(-1.6, 0, -1.2)
	hero.face_point(dm.global_position)
	main.camera.distance = main.camera.min_distance
	main.camera.snap()
	await get_tree().create_timer(0.3).timeout
	await _shot(out, "dummy", tier)
	# 镇外树林：找一格可走的地面，画面上方（西北方）是一片树
	main.use_test_area = false
	main.go_floor(0, "start")
	await get_tree().create_timer(0.5).timeout
	var tm: Dictionary = main.town
	var trees := {}
	for c in tm.trees:
		trees[c] = true
	var best := Vector2i(-1, -1)
	var best_n := -1
	for y in range(3, tm.h - 3):
		for x in range(3, tm.w - 3):
			if not DungeonGen.walkable(DungeonGen.tile(tm, x, y)):
				continue
			# 镜头从东南往西北看：紧挨着的西北方是一片树（画面上方、在主角的光照范围里），主角所在与镜头那一侧没有树
			var n := 0
			for dy in range(-4, 0):
				for dx in range(-4, 0):
					if trees.has(Vector2i(x + dx, y + dy)):
						n += 1
			for dy in range(0, 4):
				for dx in range(0, 4):
					if trees.has(Vector2i(x + dx, y + dy)):
						n -= 20
			if n > best_n:
				best_n = n
				best = Vector2i(x, y)
	hero.global_position = DungeonBuilder.cell_center(best) + Vector3(0.6, 0, 0.6)
	main.camera.distance = d0
	main.camera.snap()
	await get_tree().create_timer(0.8).timeout
	await _shot(out, "town-trees", tier)
	# 熔渊（第 5 层）：找周围 5 × 5 格里熔岩、白骨、碎石都有的一格
	main.go_floor(5)
	await get_tree().create_timer(0.3).timeout
	for e in main.monsters:
		if is_instance_valid(e):
			e.queue_free()
	main.monsters.clear()
	var dg: Dictionary = main.dungeon
	var bestd := Vector2i(-1, -1)
	var bestk := -1
	for y in range(2, dg.h - 2):
		for x in range(2, dg.w - 2):
			if dg.deco[y * dg.w + x] != DungeonGen.DECO_LAVA:
				continue
			var kinds := {}
			var cnt := 0
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					var dv: int = dg.deco[(y + dy) * dg.w + x + dx]
					if dv != 0:
						kinds[dv] = true
						cnt += 1
			var k := kinds.size() * 10 + cnt
			if k > bestk:
				bestk = k
				bestd = Vector2i(x, y)
	hero.global_position = DungeonBuilder.cell_center(bestd) + Vector3(-1.0, 0, 1.0)
	main.camera.distance = main.camera.min_distance
	main.camera.snap()
	await get_tree().create_timer(0.8).timeout
	await _shot(out, "deco", tier)
	main.camera.distance = d0


func _shots_seven(main: Node, out: String, tier: String) -> void:
	## 2.6 之七：楼梯、火把、篝火近景（说明文字先藏起来，免得挡住画面）
	main.info_row.visible = false
	var d0: float = main.camera.distance
	main.go_floor(2)
	await get_tree().create_timer(0.3).timeout
	for e in main.monsters:
		if is_instance_valid(e):
			e.queue_free()
	main.monsters.clear()
	main.camera.distance = main.camera.min_distance
	for k in ["down", "up"]:
		var st: Stairs = main.stairs[k]
		# 主角站在楼梯东北侧（触发范围外），楼梯出现在主角左边、不被下方的技能栏挡住；那里是墙就换个方向
		# （上楼梯：主角站在石阶东南侧，整段石阶和拱门在主角左上方）
		var offs: Array = [Vector3(1.4, 0, -1.2), Vector3(1.3, 0, 1.3), Vector3(-1.3, 0, -1.3), Vector3(-1.4, 0, 1.2)]
		if k == "up":
			offs.push_front(Vector3(1.7, 0, 0.9))
		var spot: Vector3 = st.global_position + offs[0]
		for off in offs:
			var pp: Vector3 = st.global_position + off
			if DungeonGen.walkable(DungeonGen.tile(main.dungeon, floori(pp.x / DungeonBuilder.TILE), floori(pp.z / DungeonBuilder.TILE))):
				spot = pp
				break
		hero.global_position = spot
		hero.face_point(st.global_position)
		hero.stop()
		main.camera.snap()
		main.banner_t = 0.0          # 楼层名横幅先收起来，免得和楼梯上方的字叠在一起
		await get_tree().create_timer(0.6).timeout
		await _shot(out, "stairs-" + k, tier)
	for tc in main.dungeon.torches:
		var c: Vector2i = tc.cell
		if tc.face == Vector2i(0, 1) and DungeonGen.walkable(DungeonGen.tile(main.dungeon, c.x, c.y + 2)) and DungeonGen.walkable(DungeonGen.tile(main.dungeon, c.x + 1, c.y + 2)):
			hero.global_position = DungeonBuilder.cell_center(c) + Vector3(1.0, 0, 2.5)
			break
	hero.stop()
	main.camera.snap()
	await get_tree().create_timer(0.6).timeout
	await _shot(out, "torch", tier)
	main.use_test_area = false
	main.go_floor(0, "start")
	await get_tree().create_timer(0.5).timeout
	var fire: Dictionary = main.town.props.filter(func(p): return p.type == "fire")[0]
	hero.global_position = TownGen.to_world(fire.x, fire.y) + Vector3(-1.6, 0, 1.6)
	hero.stop()
	main.camera.snap()
	await get_tree().create_timer(0.6).timeout
	await _shot(out, "town-fire", tier)
	main.camera.distance = d0
	main.info_row.visible = true


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame
