class_name Player
extends CharacterBody3D
## 玩家控制：WASD 移动、Shift 奔跑、空格跳跃、鼠标镜头、E 交互、F 使用 / 拿起 / 放下、鼠标左键执行动作。
## 平滑加减速、重力、碰撞、斜坡 / 台阶（台阶用斜坡碰撞体）、体力影响速度、奔跑耗体力、脚步声。

@export var walk_speed := 4.4
@export var run_speed := 7.6
@export var ground_accel := 30.0
@export var air_accel := 6.0
@export var jump_velocity := 4.8

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var input_enabled := true
## 触屏摇杆（-1..1），由 TouchControls 写入
var touch_move := Vector2.ZERO
var touch_sprint := false
var sprinting := false
## 手上搬着的东西（建筑搬运小游戏）
var carrying := ""
var anim: AnimationController
## 正在驾驶的车（null：步行）
var vehicle: PlayerCar = null

@onready var model: CharacterModel = $Model
@onready var camera_rig: PlayerCamera = $CameraRig
@onready var detector: InteractionDetector = $InteractionDetector
@onready var carry_root: Node3D = $CarryRoot

var _spawn_point := Vector3.ZERO
var _spawn_yaw := 0.0
var _step_dist := 0.0
var _warned_tired := false


func _ready() -> void:
	add_to_group("player")
	collision_layer = 2
	collision_mask = 1 | 4 | 32
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(50)
	detector.player = self
	camera_rig.set_target(self)
	anim = AnimationController.new(model)
	PlayerManager.stats_changed_outfit_hook = refresh_outfit
	refresh_outfit()


func set_spawn(pos: Vector3, yaw: float) -> void:
	_spawn_point = pos
	_spawn_yaw = yaw


func teleport(pos: Vector3, yaw: float) -> void:
	# 打车 / 晕倒送医等传送：人先下车，车留在原地
	if vehicle != null:
		vehicle.exit()
	global_position = pos
	rotation.y = yaw
	velocity = Vector3.ZERO
	camera_rig.yaw = yaw
	camera_rig.pitch = -0.25
	camera_rig.snap()


func facing_direction() -> Vector3:
	return Vector3(-sin(rotation.y), 0, -cos(rotation.y))


func controllable() -> bool:
	return input_enabled and GameManager.can_act()


func _physics_process(delta: float) -> void:
	if vehicle != null:
		detector.refresh()
		return
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
	var want_sprint := can_move and moving and (Input.is_action_pressed("sprint") or touch_sprint)
	sprinting = want_sprint and PlayerManager.can_sprint() and carrying == ""
	var speed := (run_speed if sprinting else walk_speed) * PlayerManager.speed_factor()
	if carrying != "":
		speed *= 0.78
		if WeatherManager.is_raining():
			speed *= 0.88
	var target := dir * speed
	var accel := ground_accel if on_floor else air_accel
	var hv := Vector3(velocity.x, 0, velocity.z).move_toward(target, accel * delta)
	velocity.x = hv.x
	velocity.z = hv.z
	if can_move and on_floor and Input.is_action_just_pressed("jump") and carrying == "":
		if PlayerManager.energy > 3.0:
			velocity.y = jump_velocity
			PlayerManager.change("energy", -1.0)
	move_and_slide()
	if moving:
		var want_yaw := atan2(-dir.x, -dir.z)
		rotation.y = lerp_angle(rotation.y, want_yaw, clampf(delta * 12.0, 0.0, 1.0))
	var hspeed := Vector2(velocity.x, velocity.z).length()
	anim.carrying = carrying
	anim.update(delta, hspeed, is_on_floor(), sprinting)
	camera_rig.sway = clampf((25.0 - PlayerManager.energy) / 25.0, 0.0, 1.0)
	detector.refresh()
	# 奔跑耗体力（电动滑板不耗）
	if sprinting and hspeed > 1.0 and GameManager.can_act() and not PlayerManager.owned.has("skateboard"):
		PlayerManager.change("energy", -1.1 * delta)
	if PlayerManager.energy < 10.0 and not _warned_tired:
		_warned_tired = true
		Events.say("体力快耗尽了！找地方休息、吃点东西，或者喝杯咖啡", "bad")
	elif PlayerManager.energy > 25.0:
		_warned_tired = false
	# 脚步声
	if is_on_floor() and hspeed > 0.8:
		_step_dist += hspeed * delta
		if _step_dist > (1.6 if sprinting else 1.25):
			_step_dist = 0.0
			AudioManager.footstep(sprinting)
	if global_position.y < -25.0:
		teleport(_spawn_point, _spawn_yaw)


func _unhandled_input(event: InputEvent) -> void:
	if not controllable():
		return
	if event is InputEventMouseButton and event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			# 刚锁定鼠标时浏览器可能送来一次很大的位移，限制单次幅度避免镜头猛甩
			camera_rig.handle_mouse_motion((event.relative as Vector2).limit_length(80.0))
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera_rig.zoom(-0.4)
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera_rig.zoom(0.4)
			return
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not GameManager.touch_mode:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("interact"):
		_do("interact")
	elif event.is_action_pressed("use"):
		_do("pickup")
	elif event.is_action_pressed("action"):
		# 鼠标左键：执行当前动作（优先 F 类动作，其次 E 类）
		if not _do("pickup", false):
			_do("interact", false)


## 上车：隐藏人物、关闭碰撞，镜头改为跟车
func enter_vehicle(car: PlayerCar) -> void:
	vehicle = car
	velocity = Vector3.ZERO
	sprinting = false
	model.visible = false
	carry_root.visible = false
	collision_layer = 0
	collision_mask = 0
	camera_rig.follow_vehicle(car)
	follow_vehicle(car)


## 开车时人物跟着车走（地点触发、任务距离、NPC 与车流的避让都照常按玩家位置计算）
func follow_vehicle(car: PlayerCar) -> void:
	global_position = car.global_position + Vector3(0, 0.2, 0)
	rotation.y = car.rotation.y


func exit_vehicle(car: PlayerCar, spot: Vector3) -> void:
	vehicle = null
	collision_layer = 2
	collision_mask = 1 | 4 | 32
	model.visible = true
	carry_root.visible = true
	global_position = spot
	rotation.y = car.rotation.y
	velocity = Vector3.ZERO
	camera_rig.follow_vehicle(null)
	camera_rig.set_target(self)


func _do(key: String, warn := true) -> bool:
	get_viewport().set_input_as_handled()
	if detector.perform(key):
		anim.play_once(AnimationController.State.INTERACT)
		return true
	if warn and key == "pickup" and carrying != "":
		Events.say("这里不能放下——把材料送到卸货区", "warn")
	return false


## 搬运显示（建筑搬运小游戏、开场的行李箱）
func set_carry(kind: String) -> void:
	carrying = kind
	for c in carry_root.get_children():
		c.queue_free()
	if kind == "":
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	match kind:
		"box":
			bm.size = Vector3(0.6, 0.45, 0.45)
			mi.position = Vector3(0, 1.15, -0.45)
			mi.material_override = Mats.color(Color(0.7, 0.3, 0.2))
		"suitcase":
			bm.size = Vector3(0.42, 0.62, 0.24)
			mi.position = Vector3(0.38, 0.36, 0.35)
			mi.rotation.x = 0.35
			mi.material_override = Mats.color(Color(0.15, 0.4, 0.55), 0.4)
	mi.mesh = bm
	carry_root.add_child(mi)


func refresh_outfit() -> void:
	if model == null:
		return
	var id := PlayerManager.outfit
	if id == "":
		# 默认造型：黑色飞行员夹克 + 黑色连帽衫、黑裤
		model.set_clothes(Color(0.09, 0.09, 0.1), Color(0.1, 0.1, 0.11))
		return
	var cols: Dictionary = DataDB.item(id).get("colors", {})
	model.set_clothes(Mats.hex(String(cols.get("shirt", "")), Color(0.3, 0.3, 0.4)), Mats.hex(String(cols.get("pants", "")), Color(0.15, 0.15, 0.2)))


func to_save_dict() -> Dictionary:
	if vehicle != null:
		# 开车时存档：记录车旁边的位置，读档后由 VehicleManager 放回车里
		var p2 := vehicle.global_position + vehicle.global_transform.basis.x * -2.0
		return {"pos": [p2.x, p2.y + 0.1, p2.z], "yaw": rotation.y, "cam_yaw": camera_rig.yaw}
	var p := global_position
	return {"pos": [p.x, p.y, p.z], "yaw": rotation.y, "cam_yaw": camera_rig.yaw}


func apply_save_dict(d: Dictionary) -> void:
	if vehicle != null:
		vehicle.exit()
	var pos: Array = d.get("pos", [])
	if pos.size() == 3:
		teleport(Vector3(float(pos[0]), float(pos[1]) + 0.1, float(pos[2])), float(d.get("yaw", 0.0)))
		camera_rig.yaw = float(d.get("cam_yaw", rotation.y))
		camera_rig.snap()
	set_carry("")
	refresh_outfit()
