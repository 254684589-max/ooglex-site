extends Node
## 自动化验收测试：无界面运行，完整走一遍 V0.1 的游戏闭环。
##
##   进入游戏 → 找老王 → 接任务 → 去砖堆 → 拿砖 → 搬砖 → 完成任务 → 获得工资
##   → 去食堂买饭 → 回宿舍 → 睡觉 → 第二天开始 → 存档 / 读档
##
## 运行：
##   godot --headless --path games/construction-worker/godot res://tests/test_game_loop.tscn
## 全部通过时退出码为 0，否则为 1。

var main: Node
var player: Player
var ui: UIRoot
var failures: Array = []
var checks := 0


func _ready() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	main = scene.instantiate()
	add_child(main)
	await _frames(3)
	player = GameState.player
	ui = main.ui
	await _run()
	print("")
	if failures.is_empty():
		print("ALL %d CHECKS PASSED" % checks)
		get_tree().quit(0)
	else:
		print("%d / %d CHECKS FAILED:" % [failures.size(), checks])
		for f in failures:
			print("  - " + f)
		get_tree().quit(1)


func check(cond: bool, what: String) -> void:
	checks += 1
	if cond:
		print("  ok   " + what)
	else:
		print("  FAIL " + what)
		failures.append(what)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
		await get_tree().process_frame


func _press(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	await _frames(1)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
	await _frames(1)


func _goto(pos: Vector3, yaw := 0.0) -> void:
	player.teleport(pos, yaw)
	await _frames(4)


func _run() -> void:
	print("== 标题画面")
	check(not GameState.playing, "启动后停在标题画面")
	check(ui.title.visible, "标题界面可见")

	print("== 新游戏与开场")
	main.start_new_game()
	await _frames(2)
	check(ui.story.is_playing(), "开场剧情字幕在播放")
	ui.story.skip()
	await _frames(3)
	check(GameState.playing, "开场结束后进入游玩状态")
	check(EconomySystem.cash == 300, "初始现金 ¥300（实际 ¥%d）" % EconomySystem.cash)
	check(TimeSystem.day == 1, "第 1 天")
	check(String(GameState.current_objective().get("target", "")) == "npc_wang", "第一个目标是找工头老王")
	check(not GameState.is_modal(), "没有打开的窗口")

	print("== 移动与物理")
	var start := player.global_position
	Input.action_press("move_forward")
	await _frames(40)
	Input.action_release("move_forward")
	await _frames(10)
	var moved := start.distance_to(player.global_position)
	check(moved > 1.5, "按 W 能走动（移动了 %.1f 米）" % moved)
	check(player.is_on_floor(), "站在地面上（重力与碰撞）")
	check(player.global_position.y > -0.2 and player.global_position.y < 0.5, "没有穿过地面（y=%.2f）" % player.global_position.y)

	print("== 找老王接活")
	var wang := GameState.lookup("npc_wang")
	check(wang != null, "老王在场景里")
	await _goto(wang.global_position + Vector3(1.4, 0.1, 0), -PI * 0.5)
	check(player.detector.focus is NpcTalk, "靠近老王时交互焦点是老王")
	await _press("interact")
	check(ui.dialogue.is_open(), "按 E 打开与老王的对话")
	check(GameState.is_modal(), "对话时游戏进入模态（暂停时间与操作）")
	ui.dialogue.choose(0)
	await _frames(1)
	check(String(ui.dialogue.current_node().get("text", "")).contains("一天 280，管一顿饭，干不干"), "老王：一天 280，管一顿饭，干不干？")
	ui.dialogue.choose(0)
	await _frames(1)
	check(TaskSystem.active_id == "haul_bricks", "选「干！」后接到搬砖任务")
	check(PlayerStats.has_equipment("hardhat"), "拿到安全帽")
	check(EconomySystem.meal_tickets == 1, "拿到一张饭票")
	ui.dialogue.choose(0)
	await _frames(2)
	check(not ui.dialogue.is_open() and not GameState.is_modal(), "对话结束，恢复操作")
	check(String(GameState.current_objective().get("target", "")) == "pile_brick", "目标变成去砖堆")

	print("== 搬砖 20 块")
	var zone: DeliveryZone = GameState.lookup("brick_zone")
	var trips := 0
	var levels_seen := {}
	while TaskSystem.active_id == "haul_bricks" and trips < 40:
		trips += 1
		await _goto(Vector3(-10.5, 0.1, -9.7), PI)
		var cap := PlayerStats.carry_capacity("brick")
		levels_seen[cap] = true
		for i in cap:
			await _press("pickup")
		if trips == 1:
			check(player.inventory.item_id == "brick" and player.inventory.count == 1, "在砖堆按 F 拿起 1 块砖（Lv1 上限 1）")
			check(player.carry_root.get_child_count() > 0, "砖块显示在玩家手中")
			# 在卸货区外按 F：砖会放在地上，不算进度
			await _goto(Vector3(-8.0, 0.1, -19.0), PI)
			await _press("pickup")
			check(player.inventory.is_empty() and TaskSystem.done_count() == 0, "卸货区外放下不计入进度")
			check(get_tree().get_nodes_in_group("dropped_stack").size() == 1, "砖块放在了地上")
			await _press("pickup")
			check(player.inventory.count == 1, "可以把地上的砖捡回来")
		await _goto(Vector3(-8.0, 0.15, -26.5), PI)
		await _press("work")
		if trips == 1:
			check(TaskSystem.done_count() == 1, "进入砌筑作业面按鼠标左键放下，进度 1 / 20")
			check(zone.stacked == 1, "放下的砖码放在卸货区里")
	check(TaskSystem.active_id == "", "搬砖任务完成（共 %d 趟）" % trips)
	check(levels_seen.has(2) and levels_seen.has(4), "搬运熟练度逐步提升：一次能拿 1 → 2 → 4 块")
	check(EconomySystem.cash == 580, "获得工资 ¥280，现金 ¥%d" % EconomySystem.cash)
	check(int(TaskSystem.completed_today.get("haul_bricks", 0)) == 1, "今天完成了 1 次搬砖")
	check(GameState.building_progress == 1, "工程进度 +1")

	print("== 体力系统")
	var st_before := PlayerStats.stamina
	await _goto(Vector3(0, 0.1, 10), PI)
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await _frames(60)
	Input.action_release("sprint")
	Input.action_release("move_forward")
	await _frames(2)
	check(PlayerStats.stamina < st_before - 3.0, "奔跑消耗体力（%.0f → %.0f）" % [st_before, PlayerStats.stamina])
	PlayerStats.change_stamina(-200.0)
	check(not PlayerStats.can_sprint(), "体力耗尽后不能奔跑")
	check(PlayerStats.stamina_speed_factor() < 1.0, "体力过低移动变慢")
	PlayerStats.change_stamina(100.0)

	print("== 去食堂买饭")
	var hunger_before := PlayerStats.hunger
	await _goto(Vector3(43.5, 0.1, 38.4), PI)
	check(player.detector.focus != null and player.detector.focus.display_name == "食堂打饭窗口", "靠近打饭窗口有交互提示")
	await _press("interact")
	check(ui.shop.is_open(), "按 E 打开食堂菜单")
	PlayerStats.change_hunger(-40.0)
	hunger_before = PlayerStats.hunger
	var r1: Dictionary = ui.shop.buy_item("box_meal", true)
	check(bool(r1.get("ok", false)), "用饭票换红烧肉盒饭（%s）" % String(r1.get("msg", "")))
	check(EconomySystem.meal_tickets == 0, "饭票用掉了")
	check(PlayerStats.hunger > hunger_before + 30.0, "饥饿值恢复（%.0f → %.0f）" % [hunger_before, PlayerStats.hunger])
	PlayerStats.change_thirst(-40.0)
	var r2: Dictionary = ui.shop.buy_item("water", false)
	check(bool(r2.get("ok", false)) and EconomySystem.cash == 578, "花 ¥2 买矿泉水，现金 ¥%d" % EconomySystem.cash)
	ui.shop.close()
	await _frames(2)
	check(not GameState.is_modal(), "关闭商店")

	print("== 小卖部买手套")
	await _goto(Vector3(21.0, 0.1, 32.6), PI)
	await _press("interact")
	check(ui.shop.is_open() and ui.shop.shop_id == "store", "打开小卖部")
	var r3: Dictionary = ui.shop.buy_item("gloves")
	check(bool(r3.get("ok", false)) and PlayerStats.has_equipment("gloves"), "买到劳保手套")
	check(PlayerStats.carry_drain_factor() < 1.0, "戴上手套后搬运体力消耗降低")
	ui.shop.close()
	await _frames(2)

	print("== 回宿舍睡觉")
	await _goto(Vector3(-41.0, 0.1, 31.3), PI)
	var door: Door = GameState.lookup("door_dorm")
	check(player.detector.focus == door, "宿舍门口的交互焦点是门")
	await _press("interact")
	check(door.is_open, "按 E 开门")
	await _goto(Vector3(-41.8, 0.1, 37.2), PI)
	await _press("interact")
	check(ui.menus.is_open() and ui.menus.current == "bed", "按 E 打开床铺菜单")
	var money_before_sleep := EconomySystem.cash
	ui._on_menu_action("sleep_night")
	await get_tree().create_timer(1.5).timeout
	check(TimeSystem.day == 2, "睡觉后进入第 2 天")
	check(TimeSystem.clock_text() == "06:00", "早上 06:00 起床（实际 %s）" % TimeSystem.clock_text())
	check(is_equal_approx(PlayerStats.stamina, 100.0), "睡觉恢复体力")
	check(ui.menus.current == "summary", "显示当日结算")
	check(EconomySystem.cash == money_before_sleep, "睡觉不花钱")
	ui._on_menu_action("wake")
	await _frames(3)
	check(not GameState.is_modal() and GameState.playing, "第二天开始，继续游玩")
	check(TaskSystem.completed_today.is_empty(), "新的一天任务记录已重置")
	check(zone.stacked == 0, "卸货区的砖第二天被用掉了")

	print("== 第二天的活")
	var ids := []
	for t in TaskSystem.available_tasks():
		ids.append(t.id)
	check(ids.has("haul_bricks") and ids.has("haul_cement") and ids.has("haul_rebar"), "第二天可以接：搬砖 / 搬水泥 / 搬钢筋（%s）" % str(ids))
	check(TaskSystem.accept("haul_cement"), "接搬水泥任务（通用任务系统）")
	await _goto(Vector3(22.0, 0.1, -2.3), 0.0)
	await _press("pickup")
	check(player.inventory.item_id == "cement", "在水泥库拿起水泥")
	await _goto(Vector3(26.2, 0.1, -7.6), 0.0)
	await _press("pickup")
	check(TaskSystem.done_count() == 1, "送到搅拌站上料点，水泥进度 1 / 8")

	print("== 存档与读档")
	check(SaveSystem.save_game(), "保存游戏")
	var saved := SaveSystem.read_save()
	check(int(saved["time"]["day"]) == 2, "存档里是第 2 天")
	check(int(saved["economy"]["cash"]) == EconomySystem.cash, "存档里的现金正确")
	check(String(saved["tasks"]["active_id"]) == "haul_cement", "存档里有进行中的任务")
	check(saved.has("player") and (saved["player"]["pos"] as Array).size() == 3, "存档里有玩家位置")
	var saved_pos := player.global_position
	EconomySystem.earn(9999, "测试")
	TaskSystem.abandon()
	await _goto(Vector3(0, 0.1, 40), 0.0)
	main.continue_game()
	await _frames(3)
	check(EconomySystem.cash == int(saved["economy"]["cash"]), "读档后现金恢复（¥%d）" % EconomySystem.cash)
	check(TaskSystem.active_id == "haul_cement" and TaskSystem.done_count() == 1, "读档后任务进度恢复")
	check(player.global_position.distance_to(saved_pos) < 0.5, "读档后玩家位置恢复")
	check((GameState.lookup("cement_zone") as DeliveryZone).stacked == 1, "读档后卸货区码放恢复")

	print("== 熬夜")
	TimeSystem.advance(TimeSystem.PASS_OUT_MINUTE - TimeSystem.minutes)
	await get_tree().create_timer(1.6).timeout
	check(TimeSystem.day == 3, "熬到凌晨 2 点会累倒，直接进入第 3 天")
	check(TimeSystem.clock_text() == "08:00", "累倒后 8 点才醒")
	ui._on_menu_action("wake")
	await _frames(2)

	print("== 回到标题")
	main.go_to_title()
	await _frames(2)
	check(ui.title.visible and not GameState.playing, "可以回到标题画面")
	check(SaveSystem.has_save(), "标题画面能看到存档")
