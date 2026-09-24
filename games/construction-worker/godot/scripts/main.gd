extends Node3D
## 主场景：生成地图、玩家、NPC，串起「标题 → 开场 → 干活 → 吃饭 → 睡觉 → 第二天」的游戏流程。

const INTRO_LINES := [
	"一辆破旧的大巴，摇摇晃晃开进了这座城市。",
	"你的全部家当：300 元、一部旧手机、一个行李包。",
	"老乡说，城南滨江中心的工地正在招人。",
]
const AUTOSAVE_INTERVAL := 90.0

@onready var world: SiteBuilder = $World
@onready var day_night: DayNight = $DayNight
@onready var title_camera: Camera3D = $TitleCamera
@onready var ui: UIRoot = $UI
@onready var player: Player = $Player

var info: Dictionary = {}
var zones: Array = []
var marker: ObjectiveMarker
var _dropped_root: Node3D
var _title_angle := 0.6
var _autosave_timer := AUTOSAVE_INTERVAL
var _bus_tween: Tween


func _ready() -> void:
	GameState.world = self
	info = world.build()
	GameState.player = player
	player.set_spawn(info["spawn"], info["spawn_yaw"])
	player.teleport(info["spawn"], info["spawn_yaw"])
	player.dropped_on_ground.connect(spawn_dropped)
	_dropped_root = Node3D.new()
	_dropped_root.name = "Dropped"
	add_child(_dropped_root)
	for d in info["npcs"]:
		_spawn_npc(d)
	for id in ["brick_zone", "cement_zone", "rebar_zone"]:
		var z := GameState.lookup(id)
		if z != null:
			zones.append(z)
	day_night.setup(info["night_lights"], info.get("crane_pivot"))
	marker = ObjectiveMarker.new()
	marker.name = "ObjectiveMarker"
	add_child(marker)
	SaveSystem.world_provider = _world_state
	SaveSystem.world_applier = _apply_world_state
	TaskSystem.task_completed.connect(_on_task_completed)
	PlayerStats.skill_level_up.connect(_on_level_up)
	TimeSystem.pass_out.connect(_on_pass_out)
	ui.setup(self)
	add_child(DevTools.new())
	apply_quality()
	_update_wall()
	show_title()


func _spawn_npc(d: Dictionary) -> void:
	var n := NPC.new()
	n.name = "NPC_" + String(d["id"])
	n.npc_id = String(d["id"])
	n.display_name = String(d["name"])
	n.role = String(d.get("role", ""))
	n.look = d.get("look", {})
	n.talkable = bool(d.get("talkable", true))
	n.patrol = d.get("patrol", PackedVector3Array())
	n.carry_item = String(d.get("carry", ""))
	n.walk_speed = float(d.get("speed", 1.7))
	n.idle_yaw = float(d.get("yaw", 0.0))
	n.barks = PackedStringArray(d.get("barks", []))
	n.position = d["pos"]
	add_child(n)
	GameState.register("npc_" + n.npc_id, n)


func apply_quality() -> void:
	day_night.apply_quality()


# ================================================================ 流程
func show_title() -> void:
	GameState.playing = false
	TimeSystem.running = false
	title_camera.current = true
	ui.show_title()


func go_to_title() -> void:
	show_title()


func _reset_all() -> void:
	for c in _dropped_root.get_children():
		c.queue_free()
	for z in zones:
		z.clear_stack()
	EconomySystem.reset()
	TimeSystem.reset()
	PlayerStats.reset()
	TaskSystem.reset()
	GameState.reset_for_new_game()
	player.inventory.clear()
	player.touch_move = Vector2.ZERO
	var door := GameState.lookup("door_dorm")
	if door != null:
		door.set_open(false, false)


func start_new_game() -> void:
	SaveSystem.delete_save()
	_reset_all()
	_update_wall()
	player.teleport(info["spawn"], info["spawn_yaw"])
	_reset_bus()
	ui.hide_title()
	player.camera_rig.camera.current = true
	ui.story.play_lines(PackedStringArray(INTRO_LINES), _after_intro)


func _after_intro() -> void:
	_enter_play()
	_drive_bus_away()
	GameState.set_flag("intro_done")
	Events.banner.emit("你刚来到这座城市，身上只剩下 300 元。", "任务：去项目部找工头老王")
	if GameState.touch_mode:
		Events.say("操作：左下摇杆移动 · 右半屏拖动转视角 · 右下角「交互」「拿/放」", "info")
	else:
		Events.say("操作：WASD 移动 · 鼠标转视角 · E 交互 · F 拿放 · Tab 任务 · M 地图", "info")
	SaveSystem.save_game()


func continue_game() -> void:
	var data := SaveSystem.read_save()
	if data.is_empty():
		Events.say("没有可以读取的存档", "warn")
		return
	_reset_all()
	SaveSystem.apply_save(data)
	_update_wall()
	_hide_bus()
	ui.close_all_modals()
	_enter_play()
	Events.say("读取存档：%s" % SaveSystem.describe_save(), "info")


func _enter_play() -> void:
	GameState.playing = true
	TimeSystem.running = true
	player.camera_rig.camera.current = true
	player.camera_rig.snap()
	_autosave_timer = AUTOSAVE_INTERVAL
	ui.enter_play()
	Events.game_started.emit(false)
	Events.objective_changed.emit()


func _notification(what: int) -> void:
	# 切到别的标签页 / 关闭窗口前自动存档（网页版存到浏览器 IndexedDB）
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_CLOSE_REQUEST:
		if GameState.playing:
			SaveSystem.save_game()


func _process(delta: float) -> void:
	if not GameState.playing:
		_title_angle += delta * 0.05
		var center := Vector3(0, 6, -8)
		title_camera.global_position = center + Vector3(sin(_title_angle) * 78.0, 30.0, cos(_title_angle) * 78.0)
		title_camera.look_at(center + Vector3(0, 4, 0), Vector3.UP)
		return
	_autosave_timer -= delta
	if _autosave_timer <= 0.0 and not GameState.is_modal():
		_autosave_timer = AUTOSAVE_INTERVAL
		SaveSystem.save_game()


# ================================================================ 睡觉
## mode = "night" 睡到第二天早上；"nap" 小睡一小时
func sleep(mode: String) -> void:
	if mode == "nap":
		ui.story.fade_out(0.5, func():
			TimeSystem.advance(60.0)
			PlayerStats.change_stamina(40.0)
			ui.story.fade_in(0.8)
			Events.say("小睡了一个钟头，体力 +40", "good"))
		return
	var summary := _day_summary()
	ui.story.fade_out(0.8, func(): _do_sleep(summary, 1.0, TimeSystem.WAKE_MINUTE))


func _day_summary(note := "") -> Dictionary:
	return {
		"day": TimeSystem.day,
		"income": EconomySystem.today_income,
		"expense": EconomySystem.today_expense,
		"tasks": TaskSystem.tasks_done_today(),
		"note": note,
	}


func _do_sleep(summary: Dictionary, quality: float, wake_minute: int) -> void:
	if not player.inventory.is_empty():
		summary["note"] = (String(summary.get("note", "")) + "\n手上的%s被工友收回了材料区。" % ItemDB.describe(player.inventory.item_id, player.inventory.count)).strip_edges()
		player.inventory.clear()
	TimeSystem.sleep_until_morning(wake_minute)
	PlayerStats.restore_after_sleep(quality)
	EconomySystem.new_day()
	TaskSystem.new_day()
	for z in zones:
		z.clear_stack()
	_update_wall()
	player.teleport(info["wake_pos"], info["wake_yaw"])
	var door := GameState.lookup("door_dorm")
	if door != null:
		door.set_open(false, false)
	SaveSystem.save_game()
	ui.show_summary(summary)


## 结算面板点「起床干活」
func wake_up() -> void:
	ui.story.fade_in(1.0)
	var sub := "新的一天，找老王接活去！"
	if GameState.building_progress > 0:
		sub = "你砌的墙又长高了一截。新的一天，找老王接活去！"
	Events.banner.emit("第 %d 天 · 早上 %s" % [TimeSystem.day, TimeSystem.clock_text()], sub)
	Events.morning_started.emit(TimeSystem.day)
	ui.capture_mouse()


func _on_pass_out() -> void:
	if not GameState.playing:
		return
	ui.close_all_modals()
	var summary := _day_summary("你熬到了后半夜，累得直接倒头睡着……第二天 8 点才醒，体力只恢复了七成。")
	ui.story.fade_out(1.0, func(): _do_sleep(summary, 0.7, 8 * 60))


# ================================================================ 事件
func _on_task_completed(t: TaskDefinition) -> void:
	Events.banner.emit("任务完成：%s" % t.title, "老王转账 ¥%d —— %s" % [t.reward, t.complete_line])
	Events.say("【手机】微信到账 ¥%d，余额 ¥%d" % [t.reward, EconomySystem.cash], "good")
	if TaskSystem.completed_total.get(t.id, 0) == 1 and t.id == "haul_bricks":
		Events.say("第一天的工钱到手了！饿了就去东南角的食堂，饭票能换一份盒饭", "info")
	SaveSystem.save_game()


func _on_level_up(skill: String, level: int) -> void:
	if skill == "carry":
		Events.banner.emit("搬运熟练度提升到 Lv%d" % level, "现在一次能搬：红砖 %d 块 · 水泥 %d 袋 · 钢筋 %d 捆" % [PlayerStats.carry_capacity("brick"), PlayerStats.carry_capacity("cement"), PlayerStats.carry_capacity("rebar")])


# ================================================================ 世界状态
func spawn_dropped(item_id: String, count: int, at: Vector3) -> DroppedStack:
	var s := DroppedStack.new()
	s.setup(item_id, count)
	s.position = at
	_dropped_root.add_child(s)
	return s


func _update_wall() -> void:
	var wall: MeshInstance3D = info.get("growing_wall")
	if wall == null:
		return
	var h := clampf(0.8 + GameState.building_progress * 0.3, 0.8, 3.2)
	var bm := wall.mesh as BoxMesh
	bm.size = Vector3(6.0, h, 0.24)
	wall.position.y = 0.05 + h * 0.5
	var body := wall.get_child(0) as StaticBody3D
	if body != null:
		var cs := body.get_child(0) as CollisionShape3D
		(cs.shape as BoxShape3D).size = Vector3(6.0, h, 0.24)


func _world_state() -> Dictionary:
	var dropped: Array = []
	for c in _dropped_root.get_children():
		if c is DroppedStack and not c.is_queued_for_deletion() and c.count > 0:
			dropped.append(c.to_dict())
	var stacks := {}
	for z in zones:
		stacks[z.zone_id] = z.stacked
	var door := GameState.lookup("door_dorm")
	return {"dropped": dropped, "stacks": stacks, "dorm_door_open": door.is_open if door != null else false}


func _apply_world_state(d: Dictionary) -> void:
	for c in _dropped_root.get_children():
		c.queue_free()
	for e in d.get("dropped", []):
		var pos: Array = e.get("pos", [0, 0, 0])
		spawn_dropped(String(e.get("item", "brick")), int(e.get("count", 1)), Vector3(float(pos[0]), float(pos[1]), float(pos[2])))
	var stacks: Dictionary = d.get("stacks", {})
	for z in zones:
		z.clear_stack()
		var n := int(stacks.get(z.zone_id, 0))
		if n > 0:
			z.add_stacked(n)
	var door := GameState.lookup("door_dorm")
	if door != null:
		door.set_open(bool(d.get("dorm_door_open", false)), false)


# ================================================================ 开场大巴
func _reset_bus() -> void:
	var bus: Node3D = info.get("bus")
	if bus == null:
		return
	if _bus_tween != null and _bus_tween.is_valid():
		_bus_tween.kill()
	bus.visible = true
	bus.position = Vector3(-18.0, 0, 62.8)


func _drive_bus_away() -> void:
	var bus: Node3D = info.get("bus")
	if bus == null:
		return
	_bus_tween = create_tween()
	_bus_tween.tween_interval(1.2)
	_bus_tween.tween_property(bus, "position:x", 220.0, 14.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_bus_tween.tween_callback(func(): bus.visible = false)


func _hide_bus() -> void:
	var bus: Node3D = info.get("bus")
	if bus != null:
		if _bus_tween != null and _bus_tween.is_valid():
			_bus_tween.kill()
		bus.visible = false
