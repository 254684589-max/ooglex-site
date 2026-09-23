class_name Player
extends CharacterBody3D
## 玩家控制：移动（走 / 跑 / 跳 / 重力 / 碰撞）、体力消耗、交互按键、搬运显示。

signal dropped_on_ground(item_id: String, count: int, at: Vector3)

@export var walk_speed := 4.3
@export var run_speed := 7.2
@export var ground_accel := 32.0
@export var air_accel := 6.0
@export var jump_velocity := 4.8

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var input_enabled := true
## 触屏摇杆输入（-1..1），由 TouchControls 写入
var touch_move := Vector2.ZERO
var touch_sprint := false
var sprinting := false

@onready var model: CharacterModel = $Model
@onready var camera_rig: PlayerCamera = $CameraRig
@onready var detector: InteractionDetector = $InteractionDetector
@onready var inventory: Inventory = $Inventory
@onready var carry_root: Node3D = $CarryRoot

var _spawn_point := Vector3.ZERO
var _spawn_yaw := 0.0
var _warned_empty := false


func _ready() -> void:
	add_to_group("player")
	collision_layer = 2
	collision_mask = 1 | 4
	floor_snap_length = 0.3
	floor_max_angle = deg_to_rad(50)
	detector.player = self
	camera_rig.set_target(self)
	inventory.changed.connect(_on_inventory_changed)
	PlayerStats.equipment_changed.connect(_refresh_equipment)
	_refresh_equipment()


func set_spawn(pos: Vector3, yaw: float) -> void:
	_spawn_point = pos
	_spawn_yaw = yaw


func teleport(pos: Vector3, yaw: float) -> void:
	global_position = pos
	rotation.y = yaw
	velocity = Vector3.ZERO
	camera_rig.yaw = yaw
	camera_rig.pitch = -0.28
	camera_rig.snap()


func facing_direction() -> Vector3:
	return Vector3(-sin(rotation.y), 0, -cos(rotation.y))


func carried_item() -> String:
	return inventory.item_id if not inventory.is_empty() else ""


func controllable() -> bool:
	return input_enabled and GameState.playing and not GameState.is_modal()


# ---------------------------------------------------------------- 物理
func _physics_process(delta: float) -> void:
	var on_floor := is_on_floor()
	if not on_floor:
		velocity.y -= gravity * delta
	var can_move := controllable()
	var input_vec := Vector2.ZERO
	if can_move:
		input_vec = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		if touch_move.length() > 0.08:
			input_vec = touch_move.limit_length(1.0)
	var dir := camera_rig.right_flat() * input_vec.x + camera_rig.forward_flat() * (-input_vec.y)
	if dir.length() > 1.0:
		dir = dir.normalized()
	var moving := dir.length() > 0.05
	var load_kg := inventory.weight()
	var load_factor := clampf(1.0 - load_kg * 0.012, 0.45, 1.0)
	var want_sprint := can_move and moving and (Input.is_action_pressed("sprint") or touch_sprint)
	sprinting = want_sprint and PlayerStats.can_sprint() and load_kg <= 26.0
	var speed := (run_speed if sprinting else walk_speed) * load_factor * PlayerStats.stamina_speed_factor()
	if PlayerStats.starving():
		speed *= 0.85
	var target := dir * speed
	var accel := ground_accel if on_floor else air_accel
	var hv := Vector3(velocity.x, 0, velocity.z).move_toward(target, accel * delta)
	velocity.x = hv.x
	velocity.z = hv.z
	if can_move and on_floor and Input.is_action_just_pressed("jump"):
		_try_jump(load_kg)
	move_and_slide()
	if moving:
		var want_yaw := atan2(-dir.x, -dir.z)
		rotation.y = lerp_angle(rotation.y, want_yaw, clampf(delta * 12.0, 0.0, 1.0))
	var hspeed := Vector2(velocity.x, velocity.z).length()
	_update_stamina(delta, moving and hspeed > 0.4, load_kg)
	model.animate(delta, hspeed, is_on_floor())
	camera_rig.sway = PlayerStats.fatigue_level()
	detector.refresh()
	if global_position.y < -25.0:
		teleport(_spawn_point, _spawn_yaw)
		Events.say("你摔出了地图，已经把你送回工地门口", "warn")


func _try_jump(load_kg: float) -> void:
	if load_kg > 20.0:
		Events.say("扛着这么重的东西跳不起来", "warn")
		return
	if PlayerStats.stamina < 3.0:
		return
	velocity.y = jump_velocity
	PlayerStats.change_stamina(-3.0)


func _update_stamina(delta: float, moving: bool, load_kg: float) -> void:
	if not GameState.playing or GameState.is_modal():
		return
	var d := 0.0
	var exertion := 0.0
	if moving:
		d -= 0.08
		exertion = 0.25
		if sprinting:
			d -= 6.0
			exertion = 1.0
		if load_kg > 0.0:
			d -= load_kg * 0.045 * PlayerStats.carry_drain_factor()
			exertion = maxf(exertion, clampf(load_kg / 25.0, 0.3, 1.0))
	elif load_kg > 0.0:
		d -= load_kg * 0.01
		exertion = 0.2
	elif PlayerStats.needs_ok():
		d += 3.0
	else:
		d += 0.6
	if PlayerStats.starving():
		d -= 0.35
	if absf(d) > 0.0001:
		PlayerStats.change_stamina(d * delta)
	if TimeSystem.running:
		var game_minutes := delta * TimeSystem.minutes_per_second() * TimeSystem.speed_multiplier
		PlayerStats.tick_needs(game_minutes, exertion)
	if PlayerStats.stamina <= 0.0 and not _warned_empty:
		_warned_empty = true
		Events.say("体力耗尽！先停下来歇一歇，或者去吃点东西", "bad")
	elif PlayerStats.stamina > 20.0:
		_warned_empty = false


# ---------------------------------------------------------------- 输入
func _unhandled_input(event: InputEvent) -> void:
	if not controllable():
		return
	# 触屏模拟出来的鼠标事件不当作鼠标操作
	if event is InputEventMouseButton and event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			camera_rig.handle_mouse_motion(event.relative)
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera_rig.zoom(-0.4)
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera_rig.zoom(0.4)
			return
		# 鼠标还没锁定：这次点击只用来锁定鼠标
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not GameState.touch_mode:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("interact"):
		_do_action("interact")
	elif event.is_action_pressed("pickup"):
		_do_action("pickup")
	elif event.is_action_pressed("work"):
		_do_action("work")
	elif event.is_action_pressed("aim"):
		camera_rig.aiming = true
	elif event.is_action_released("aim"):
		camera_rig.aiming = false
	else:
		for i in 5:
			if event.is_action_pressed("tool_%d" % (i + 1)):
				var msg := PlayerStats.select_tool(i)
				if msg != "":
					Events.say(msg, "warn")
				else:
					Events.say("切换工具：%s" % PlayerStats.current_tool()["name"], "info")
				break


func _do_action(action_key: String) -> void:
	get_viewport().set_input_as_handled()
	if action_key == "work":
		# 鼠标左键：在卸货区放下 / 在材料堆拿起，等同于 F，但不会把东西丢在地上
		if detector.perform("pickup"):
			model.gesture("pickup")
		return
	if detector.perform(action_key):
		if action_key == "pickup":
			model.gesture("pickup")
		return
	if action_key == "pickup" and not inventory.is_empty():
		drop_on_ground()


## 把手上的东西放在脚边（不计入任务）
func drop_on_ground() -> void:
	if inventory.is_empty():
		return
	var item := inventory.item_id
	var n := inventory.remove()
	var at := global_position + facing_direction() * 0.9
	at.y = global_position.y
	model.gesture("pickup")
	Sfx.play("place", -3.0)
	dropped_on_ground.emit(item, n, at)
	Events.say("把%s放在了地上（不在卸货区，不算进度）" % ItemDB.describe(item, n), "warn")


# ---------------------------------------------------------------- 搬运显示
func _on_inventory_changed(item_id: String, count: int) -> void:
	for c in carry_root.get_children():
		c.queue_free()
	if item_id == "" or count <= 0:
		model.set_carry_pose("")
		return
	var info := ItemDB.get_item(item_id)
	var size: Vector3 = info.get("size", Vector3(0.3, 0.1, 0.2))
	var col: Color = info.get("color", Color.GRAY)
	var visual := String(info.get("visual", "stack"))
	model.set_carry_pose(visual)
	var mat := Mats.color(col)
	for i in count:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		mi.material_override = mat
		match visual:
			"stack":
				mi.position = Vector3(0, 1.08 + i * (size.y + 0.006), -0.42)
			"shoulder":
				mi.position = Vector3(0.24, 1.72 + i * (size.y + 0.01), 0.02)
			_:
				mi.position = Vector3(0.24 + (i % 2) * 0.1, 1.7 + int(i / 2.0) * 0.1, 0.1)
		carry_root.add_child(mi)


func _refresh_equipment() -> void:
	if model == null:
		return
	model.set_hat("yellow" if PlayerStats.has_equipment("hardhat") else "none")


# ---------------------------------------------------------------- 存档
func to_save_dict() -> Dictionary:
	var p := global_position
	return {
		"pos": [p.x, p.y, p.z],
		"yaw": rotation.y,
		"cam_yaw": camera_rig.yaw,
		"inventory": inventory.to_dict(),
	}


func apply_save_dict(d: Dictionary) -> void:
	var pos: Array = d.get("pos", [])
	if pos.size() == 3:
		teleport(Vector3(float(pos[0]), float(pos[1]) + 0.05, float(pos[2])), float(d.get("yaw", 0.0)))
		camera_rig.yaw = float(d.get("cam_yaw", rotation.y))
		camera_rig.snap()
	inventory.from_dict(d.get("inventory", {}))
