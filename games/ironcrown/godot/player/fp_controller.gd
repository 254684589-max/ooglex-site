class_name FpController
extends CharacterBody3D
## 第一人称控制器（GDD.md 第三、四节；TECH.md 4.1）。
## 身体原点在脚底；水平转身转整个身体，俯仰只转头部节点。
## 输入来源：键盘动作（move_* / sprint / crouch / jump）、鼠标（look()）、触屏（touch_move、look_touch()）。

const WALK_SPEED := 3.0
const RUN_SPEED := 5.5
const CROUCH_SPEED := 1.6
const EYE_STAND := 1.65
const EYE_CROUCH := 1.0
const HEIGHT_STAND := 1.8
const HEIGHT_CROUCH := 1.15
const RADIUS := 0.35
const GROUND_ACCEL := 30.0      # 米每二次方秒：约 0.1 秒达到步行速度
const AIR_ACCEL := 6.0
const JUMP_VELOCITY := 4.2      # 起跳约 0.9 米高
const STEP_HEIGHT := 0.3        # 能直接跨上的台阶高度
const PITCH_LIMIT := 85.0
const TOUCH_RUN_THRESHOLD := 0.95   # 摇杆推到边缘 = 跑
const BOB_AMPLITUDE := 0.035
const GUARD_SPEED := 1.7          # 举剑格挡、失衡时只能慢慢挪（2.5）
## 第三人称越肩镜头（2.9，D6）：相机在头部后方 TP_DIST 米、偏右 TP_SIDE 米、高 TP_UP 米；身后有墙就往前收
const TP_DIST := 2.6
const TP_SIDE := 0.55
const TP_UP := 0.25
const TP_MARGIN := 0.25

var head: Node3D
var interactor: Interactor
var melee: Melee
var avatar: PlayerAvatar
var third_person := false
var dialogue_view := false    # 对话时临时用第一人称的镜头（不改设置）
var camera: Camera3D
var shape: CollisionShape3D
var capsule: CapsuleShape3D
var crouching := false
var crouch_wanted := false
var touch_move := Vector2.ZERO      # 触屏摇杆，-1..1，y 负 = 向前
var jump_requested := false
var pitch := 0.0                    # 度，正 = 抬头
var running := false                # 这一帧在跑（消耗体力，2.4）
var bob_time := 0.0
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)


func _init() -> void:
	floor_max_angle = deg_to_rad(46.0)
	floor_snap_length = STEP_HEIGHT + 0.05
	collision_layer = 2
	collision_mask = 1
	capsule = CapsuleShape3D.new()
	capsule.radius = RADIUS
	capsule.height = HEIGHT_STAND
	shape = CollisionShape3D.new()
	shape.shape = capsule
	shape.position.y = HEIGHT_STAND * 0.5
	add_child(shape)
	head = Node3D.new()
	head.name = "Head"
	head.position.y = EYE_STAND
	add_child(head)
	camera = Camera3D.new()
	camera.near = 0.05
	camera.fov = 75.0
	head.add_child(camera)
	interactor = Interactor.new()
	interactor.name = "Interactor"
	interactor.player = self
	add_child(interactor)
	melee = Melee.new()
	melee.name = "Melee"
	melee.player = self
	add_child(melee)
	avatar = PlayerAvatar.new()
	avatar.name = "Avatar"
	avatar.player = self
	add_child(avatar)


func _ready() -> void:
	add_to_group("player")
	_apply_settings()
	Settings.changed.connect(_apply_settings)


func _apply_settings() -> void:
	camera.fov = Settings.fov
	if Settings.third_person != third_person:
		set_third_person(Settings.third_person)


## 切换第一 / 第三人称（2.9）：第三人称显示人物模型（A.1）、藏起第一人称的武器；身体跟着镜头的水平朝向转（越肩视角）
func set_third_person(on: bool) -> void:
	third_person = on
	avatar.visible = on and not dialogue_view
	if melee and melee.view:
		melee.view.hide_model(on)
	if not on:
		camera.position = Vector3.ZERO


## 对话时临时换成第一人称的镜头、藏起人物（2026-10-04 手机实测：竖屏第三人称时主角正好挡在说话人前面）；
## 只改镜头，不改「第三人称」设置，对话结束后相机再慢慢退回肩后
func set_dialogue_view(on: bool) -> void:
	dialogue_view = on
	if not third_person:
		return
	avatar.visible = not on
	if on:
		camera.position = Vector3.ZERO


## 瞄准 / 交互 / 命中判定的起点：总是眼睛的位置（第三人称时相机在身后，不能从相机算）
func aim_origin() -> Vector3:
	return head.global_position


func aim_forward() -> Vector3:
	return -camera.global_transform.basis.z


## 鼠标转视角：relative 是鼠标移动的像素
func look(relative: Vector2) -> void:
	_turn(relative * Settings.MOUSE_DEG_PER_PX * Settings.sensitivity)


## 触屏转视角：relative 是手指拖动的像素
func look_touch(relative: Vector2) -> void:
	_turn(relative * Settings.TOUCH_DEG_PER_PX * Settings.sensitivity)


func _turn(deg: Vector2) -> void:
	rotation.y -= deg_to_rad(deg.x)
	pitch += deg.y if Settings.invert_y else -deg.y
	pitch = clampf(pitch, -PITCH_LIMIT, PITCH_LIMIT)
	head.rotation.x = deg_to_rad(pitch)


func yaw_deg() -> float:
	return rad_to_deg(rotation.y)


func toggle_crouch() -> void:
	crouch_wanted = not crouch_wanted


func request_jump() -> void:
	jump_requested = true


func move_input() -> Vector2:
	var v := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	return touch_move if touch_move.length() > v.length() else v


func current_speed(input: Vector2) -> float:
	if crouching:
		return CROUCH_SPEED
	if melee and (melee.blocking() or melee.staggered()):
		return GUARD_SPEED
	return RUN_SPEED if wants_run() else WALK_SPEED


## 想跑并且体力够（体力耗尽后要缓过气才能再跑，2.4）
func wants_run() -> bool:
	var run := Input.is_action_pressed("sprint") or touch_move.length() >= TOUCH_RUN_THRESHOLD
	return run and not GameState.over_encumbered() and (melee == null or (melee.can_sprint() and not melee.blocking() and not melee.staggered()))


func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("crouch"):
		toggle_crouch()
	_update_crouch()
	var input := move_input()
	var dir := global_transform.basis * Vector3(input.x, 0.0, input.y)
	dir.y = 0.0
	dir = dir.normalized() * minf(input.length(), 1.0)
	var target := dir * current_speed(input)
	running = not crouching and is_on_floor() and input.length() > 0.1 and wants_run()
	var accel := GROUND_ACCEL if is_on_floor() else AIR_ACCEL
	var h := Vector2(velocity.x, velocity.z).move_toward(Vector2(target.x, target.z), accel * delta)
	velocity.x = h.x
	velocity.z = h.y
	if is_on_floor():
		if (jump_requested or Input.is_action_just_pressed("jump")) and not crouching:
			velocity.y = JUMP_VELOCITY
	else:
		velocity.y -= gravity * delta
	jump_requested = false
	_try_step(delta)
	move_and_slide()
	_update_head(delta)


## 台阶：水平方向被挡住时，试着抬高 STEP_HEIGHT 再往前；前方落脚点是平地就把身体抬上去。
## Godot 4 的 CharacterBody3D 没有内置跨台阶（TECH.md 4.1）；陡坡（法线太斜）不算台阶。
func _try_step(delta: float) -> void:
	if not is_on_floor() or velocity.y > 0.0:
		return
	var motion := Vector3(velocity.x, 0.0, velocity.z) * delta
	if motion.length() < 0.0005:
		return
	motion = motion.normalized() * maxf(motion.length(), RADIUS * 0.5)   # 看远一点，慢走时也能探到
	var from := global_transform
	if not test_move(from, motion):
		return
	var up := Vector3(0.0, STEP_HEIGHT, 0.0)
	if test_move(from, up):
		return
	var raised := from.translated(up)
	if test_move(raised, motion):
		return
	var hit := KinematicCollision3D.new()
	if not test_move(raised.translated(motion), -up, hit):
		return
	if hit.get_normal().y < cos(floor_max_angle):
		return
	var rise := STEP_HEIGHT - hit.get_travel().length()
	if rise > 0.01:
		global_position.y += rise + 0.01


func _update_crouch() -> void:
	if crouch_wanted and not crouching:
		_set_crouch(true)
	elif not crouch_wanted and crouching and can_stand():
		_set_crouch(false)


func _set_crouch(on: bool) -> void:
	crouching = on
	capsule.height = HEIGHT_CROUCH if on else HEIGHT_STAND
	shape.position.y = capsule.height * 0.5


## 头顶有没有空间站起来（矮洞里松开蹲下不会卡进天花板）
func can_stand() -> bool:
	var probe := CapsuleShape3D.new()
	probe.radius = RADIUS - 0.03
	probe.height = HEIGHT_STAND - 0.1
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = probe
	q.collision_mask = collision_mask
	q.transform = Transform3D(Basis.IDENTITY, global_position + Vector3(0.0, HEIGHT_STAND * 0.5 + 0.05, 0.0))
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


func _update_head(delta: float) -> void:
	var eye := EYE_CROUCH if crouching else EYE_STAND
	head.position.y = move_toward(head.position.y, eye, 4.0 * delta)
	if third_person and not dialogue_view:
		_update_third_person(delta)
		return
	var speed := Vector2(velocity.x, velocity.z).length()
	if Settings.head_bob and is_on_floor() and speed > 0.5:
		bob_time += delta * speed * 2.2
		camera.position = Vector3(cos(bob_time) * BOB_AMPLITUDE * 0.6, absf(sin(bob_time)) * BOB_AMPLITUDE, 0.0)
	else:
		camera.position = camera.position.move_toward(Vector3.ZERO, 0.2 * delta)
		if not Settings.head_bob:
			camera.position = Vector3.ZERO


## 越肩镜头：从眼睛往身后右上方打一条射线（只看世界层），撞到墙就把相机收到墙前面，避免穿墙
func _update_third_person(delta: float) -> void:
	# 竖屏手机水平视野窄（相机按高度保持视野）：右肩偏移按宽高比收拢，人不会被挤到屏幕左边去压住摇杆
	var r := get_viewport().get_visible_rect().size
	var narrow := clampf((r.x / maxf(r.y, 1.0)) / (16.0 / 9.0), 0.3, 1.0)
	var want_local := Vector3(TP_SIDE * narrow, TP_UP, TP_DIST)
	var from := head.global_position
	var to := head.global_transform * want_local
	var q := PhysicsRayQueryParameters3D.create(from, to, 1, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var local := want_local
	if not hit.is_empty():
		var d := maxf(from.distance_to(hit.position) - TP_MARGIN, 0.2)
		local = want_local.normalized() * d
	# 往前收要快（不然会先穿墙一下），往后退慢一点
	var speed := 30.0 if local.length() < camera.position.length() else 6.0
	camera.position = camera.position.lerp(local, clampf(delta * speed, 0.0, 1.0))
