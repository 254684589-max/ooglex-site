class_name PlayerCar
extends CharacterBody3D
## 玩家的私家车：走近按 E 上车，开车时 W/S 油门 · 刹车 / 倒车，A/D 转向，空格手刹，E 下车。
## 手机上左下摇杆：上推油门、下拉刹车倒车、左右转向。
## 街机式操控（自行车模型）：车速 → 按前轮转角算出转弯角速度；车身碰撞体抬高到路沿以上，
## 高度与俯仰由前后两条向下的射线贴地，所以能开上人行道但会被楼、灯杆、树挡住。
## 路上的车流是纯视觉的，这里按距离做简单的碰撞：撞上就减速弹开。

const GRAVITY := 18.0

var uid := ""
var model_id := ""
var spec: Dictionary = {}
var dims: Dictionary = {}
var driver: Player = null
## 车速（米/秒，向前为正）
var speed := 0.0
var steer := 0.0
var throttle := 0.0
var braking := false
var handbrake := false
var _vy := 0.0
var _wheels: Array = []
var _wheel_spin := 0.0
var _brake_mat: StandardMaterial3D
var _lights: Array = []
var _door: CarDoor
var _engine: AudioStreamPlayer3D
var _bump_cd := 0.0
var _body_pitch := 0.0
var _body: Node3D


## 车门交互：走近时「上车」，开车时「下车」
class CarDoor:
	extends Interactable
	var car: PlayerCar

	func get_actions(p: Node) -> Array:
		if car.driver != null:
			return [Interactable.action("interact", "下车")]
		if not car.can_enter():
			var why := "先把手里的建材放下" if (p as Player).carrying == "box" else "现在不能开车"
			return [Interactable.action("interact", why, false)]
		return [Interactable.action("interact", "开车（%s）" % String(car.spec.get("name", "")))]

	func perform(action: String, p: Node) -> void:
		if action != "interact":
			return
		if car.driver != null:
			car.exit()
		elif car.can_enter():
			car.enter(p as Player)

	func distance_to_player(player: Node3D) -> float:
		if car.driver != null:
			return 0.0
		# 到车身边缘的距离（车身是长方形）
		var local: Vector3 = car.global_transform.affine_inverse() * player.global_position
		var dx := maxf(absf(local.x) - float(car.dims.get("half_w", 0.9)), 0.0)
		var dz := maxf(absf(local.z) - 2.2, 0.0)
		return Vector2(dx, dz).length()


func setup(c: Dictionary) -> void:
	uid = String(c["uid"])
	model_id = String(c["model"])
	spec = VehicleManager.model(model_id)
	name = "Car_" + uid
	collision_layer = 1
	collision_mask = 1 | 4 | 32
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	add_to_group("player_car")
	_body = Node3D.new()
	add_child(_body)
	var mb := MeshBatcher.new()
	mb.chunked = false
	dims = BuildingKit.car_body(mb, String(spec.get("shape", "sedan")), Mats.hex(String(c.get("paint", "#cccccc")), Color(0.8, 0.8, 0.8)))
	var mi := MeshInstance3D.new()
	mi.mesh = mb.to_mesh()
	_body.add_child(mi)
	# 车轮
	var wb := MeshBatcher.new()
	wb.chunked = false
	BuildingKit.car_wheel(wb, float(dims["wheel_r"]), float(dims["wheel_w"]))
	var wmesh := wb.to_mesh()
	for wp in dims["wheels"]:
		var pivot := Node3D.new()
		pivot.position = wp
		_body.add_child(pivot)
		var w := MeshInstance3D.new()
		w.mesh = wmesh
		pivot.add_child(w)
		_wheels.append(pivot)
	# 刹车灯（踩刹车时变亮）
	var half: float = dims["half_w"]
	_brake_mat = StandardMaterial3D.new()
	_brake_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_brake_mat.albedo_color = Color(0.35, 0.02, 0.03)
	for sx in [-1.0, 1.0]:
		var bl := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(half * 0.36, 0.09, 0.02)
		bl.mesh = bm
		bl.material_override = _brake_mat
		bl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bl.position = Vector3(sx * half * 0.68, float(dims["tail_y"]), float(dims["rear"]) + 0.005)
		_body.add_child(bl)
	# 车身碰撞体：抬高到路沿以上
	var length: float = float(dims["rear"]) - float(dims["front"])
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var h: float = float(dims["height"]) - 0.35
	box.size = Vector3(half * 2.0, h, length)
	cs.shape = box
	cs.position = Vector3(0, 0.35 + h * 0.5, (float(dims["rear"]) + float(dims["front"])) * 0.5)
	add_child(cs)
	_door = CarDoor.new()
	_door.car = self
	_door.display_name = String(spec.get("name", "车"))
	_door.max_distance = 2.2
	_door.focus_priority = 2
	_door.set_box_shape(Vector3(half * 2.0 + 3.0, 2.0, length + 2.0), Vector3(0, 1.0, 0))
	add_child(_door)


func _ready() -> void:
	# 车灯：夜里亮（画质「中」以上才有真实光源）
	if int(SettingsManager.get_v("quality", 1)) >= 1:
		for sx in [-0.6, 0.6]:
			var l := SpotLight3D.new()
			l.position = Vector3(sx, float(dims["light_y"]), float(dims["front"]) - 0.1)
			l.rotation = Vector3(-0.12, 0, 0)
			l.spot_range = 28.0
			l.spot_angle = 32.0
			l.light_energy = 3.0
			l.light_color = Color(1.0, 0.95, 0.85)
			l.shadow_enabled = false
			l.visible = false
			_body.add_child(l)
			_lights.append(l)
	var st: AudioStream = AudioManager._stream("sfx_engine")
	if st != null:
		_engine = AudioStreamPlayer3D.new()
		_engine.stream = st
		_engine.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
		_engine.unit_size = 8.0
		_engine.volume_db = -8.0
		add_child(_engine)


func place(pos: Vector3, yaw: float) -> void:
	global_position = pos
	rotation = Vector3(0, yaw, 0)
	speed = 0.0
	_vy = 0.0
	velocity = Vector3.ZERO
	_snap_ground(1.0)


func can_enter() -> bool:
	# 行李箱可以放进车里；工地搬运的建材不行
	return GameManager.can_act() and not VehicleManager.is_driving() and GameManager.player != null and (GameManager.player as Player).carrying != "box"


func enter(p: Player) -> void:
	if p == null or driver != null:
		return
	driver = p
	p.enter_vehicle(self)
	VehicleManager.on_enter(uid)
	AudioManager.play_sfx("door")
	if _engine != null:
		_engine.play()


## 下车：从驾驶座一侧（车左边）下；被挡住就换右边、车后
func exit() -> void:
	if driver == null:
		return
	var p := driver
	var spot := _exit_spot()
	driver = null
	throttle = 0.0
	braking = false
	handbrake = false
	p.exit_vehicle(self, spot)
	VehicleManager.on_exit(uid)
	AudioManager.play_sfx("door")
	if _engine != null:
		_engine.stop()
	_update_lights()


func _exit_spot() -> Vector3:
	var half: float = dims["half_w"]
	var cands := [Vector3(-half - 0.8, 0, -0.3), Vector3(half + 0.8, 0, -0.3), Vector3(0, 0, float(dims["rear"]) + 1.2), Vector3(0, 0, float(dims["front"]) - 1.2)]
	var space := get_world_3d().direct_space_state
	for c in cands:
		var wp: Vector3 = global_transform * c
		var q := PhysicsShapeQueryParameters3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.35
		cap.height = 1.7
		q.shape = cap
		q.transform = Transform3D(Basis(), wp + Vector3(0, 1.0, 0))
		q.collision_mask = 1 | 4 | 32
		q.exclude = [get_rid()]
		if space.intersect_shape(q, 1).is_empty():
			return wp + Vector3(0, 0.1, 0)
	return global_position + Vector3(0, 2.0, 0)


## 读取驾驶输入：键盘或触屏摇杆
func _read_input() -> void:
	throttle = 0.0
	var s := 0.0
	handbrake = false
	if driver == null or not GameManager.can_act():
		return
	var tv: Vector2 = driver.touch_move
	if tv.length() > 0.1:
		throttle = clampf(-tv.y * 1.3, -1.0, 1.0)
		s = clampf(-tv.x * 1.2, -1.0, 1.0)
	else:
		throttle = Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
		s = Input.get_action_strength("move_left") - Input.get_action_strength("move_right")
	handbrake = Input.is_action_pressed("jump")
	var max_steer: float = float(spec.get("steer", 0.55)) / (1.0 + absf(speed) * 0.045)
	steer = move_toward(steer, s * max_steer, get_physics_process_delta_time() * 2.6)


func _physics_process(delta: float) -> void:
	_read_input()
	var top: float = spec.get("top_speed", 25.0)
	var acc: float = spec.get("accel", 6.0)
	braking = false
	if driver != null and throttle > 0.05:
		if speed < -0.5:
			speed = move_toward(speed, 0.0, 12.0 * throttle * delta)
			braking = true
		else:
			speed += acc * throttle * (1.0 - clampf(speed / top, 0.0, 1.0)) * delta
	elif driver != null and throttle < -0.05:
		if speed > 0.5:
			speed = move_toward(speed, 0.0, 14.0 * -throttle * delta)
			braking = true
		else:
			speed = maxf(speed - acc * 0.6 * -throttle * delta, -top * 0.25)
	else:
		speed = move_toward(speed, 0.0, (2.0 + absf(speed) * 0.04) * delta)
	if handbrake:
		speed = move_toward(speed, 0.0, 9.0 * delta)
		braking = true
	if WeatherManager.is_raining():
		speed = minf(speed, top * 0.85)
	# 转弯：角速度 = 车速 / 轴距 × tan(前轮转角)；手刹时甩尾更猛
	var wz: Array = BuildingKit.CAR_SHAPES.get(String(spec.get("shape", "sedan")), {}).get("wheel_z", [-1.4, 1.4])
	var wheelbase: float = absf(float(wz[1]) - float(wz[0]))
	var yaw_rate := speed / wheelbase * tan(steer) * (1.5 if handbrake and absf(speed) > 4.0 else 1.0)
	rotation.y += yaw_rate * delta
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	velocity = fwd * speed
	var before := global_position
	move_and_slide()
	# 撞到楼 / 灯杆 / 树：减速
	if get_slide_collision_count() > 0:
		var n := get_slide_collision(0).get_normal()
		var hit := absf(fwd.dot(Vector3(n.x, 0, n.z).normalized()))
		speed *= 1.0 - 0.8 * hit
		if hit > 0.5 and absf(speed) > 1.0:
			speed = -speed * 0.2
		_bump(hit * absf(speed))
	_traffic_collide(delta)
	_snap_ground(delta)
	var moved := Vector2(global_position.x - before.x, global_position.z - before.z).length()
	if driver != null:
		VehicleManager.add_distance(moved)
		driver.follow_vehicle(self)
	# 车轮：滚动 + 前轮转向
	_wheel_spin += speed * delta / float(dims["wheel_r"])
	for i in _wheels.size():
		var w: Node3D = _wheels[i]
		w.rotation = Vector3(-_wheel_spin, steer if i < 2 else 0.0, 0)
	# 车身：加减速时前后点头
	var pitch_target := clampf(-throttle * 0.02 + (0.035 if braking and absf(speed) > 1.0 else 0.0), -0.04, 0.05)
	_body_pitch = lerpf(_body_pitch, pitch_target if driver != null else 0.0, clampf(delta * 5.0, 0.0, 1.0))
	_body.rotation.x = _body_pitch
	_brake_mat.albedo_color = Color(1.0, 0.08, 0.1) if braking else Color(0.35, 0.02, 0.03)
	_update_lights()
	if _engine != null and _engine.playing:
		_engine.pitch_scale = 0.7 + absf(speed) / top * 1.3 + maxf(throttle, 0.0) * 0.15
	_bump_cd = maxf(_bump_cd - delta, 0.0)


## 前后两条射线贴地（能开上路沿、坡道）
func _snap_ground(delta: float) -> void:
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space == null:
		return
	var fz: float = float(dims.get("front", -2.0)) + 0.6
	var rz: float = float(dims.get("rear", 2.0)) - 0.6
	var ys: Array = []
	for z in [fz, rz]:
		var from: Vector3 = global_transform * Vector3(0, 1.2, z)
		var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -4.0, 0), 1)
		q.exclude = [get_rid()]
		var r := space.intersect_ray(q)
		ys.append(r["position"].y if not r.is_empty() else null)
	if ys[0] == null and ys[1] == null:
		_vy -= GRAVITY * delta
		global_position.y += _vy * delta
		return
	var yf: float = ys[0] if ys[0] != null else ys[1]
	var yr: float = ys[1] if ys[1] != null else ys[0]
	var target := (yf + yr) * 0.5
	if global_position.y > target + 0.05:
		_vy -= GRAVITY * delta
		global_position.y = maxf(global_position.y + _vy * delta, target)
	else:
		_vy = 0.0
		global_position.y = lerpf(global_position.y, target, clampf(delta * 14.0, 0.0, 1.0))
	var pitch := atan2(yf - yr, rz - fz)
	rotation.x = lerpf(rotation.x, pitch, clampf(delta * 8.0, 0.0, 1.0))


## 与路上车流（纯视觉的车）的简单碰撞
func _traffic_collide(_delta: float) -> void:
	var st := _street_traffic()
	if st == null:
		return
	for d in st.cars:
		var n: Node3D = d["node"]
		if not n.visible:
			continue
		var off := global_position - n.global_position
		off.y = 0.0
		if off.length() > 6.0:
			continue
		# 两个车身都当作沿车长方向的两个圆
		var mine := [global_position + (-global_transform.basis.z) * 1.1, global_position + global_transform.basis.z * 1.1]
		var theirs := [n.global_position + (-n.global_transform.basis.z) * 1.1, n.global_position + n.global_transform.basis.z * 1.1]
		for a in mine:
			for b in theirs:
				var v: Vector3 = a - b
				v.y = 0.0
				var dist := v.length()
				if dist < 2.0 and dist > 0.001:
					global_position += v / dist * (2.0 - dist) * 0.9
					var hit := absf(speed)
					speed *= 0.35
					_bump(hit)
					return


func _street_traffic() -> StreetTraffic:
	if GameManager.main == null:
		return null
	var st = GameManager.main.get("street_traffic")
	return st if st is StreetTraffic else null


func _bump(strength: float) -> void:
	if strength < 3.0 or _bump_cd > 0.0:
		return
	_bump_cd = 0.6
	AudioManager.play_sfx("place", -2.0, 0.6)
	if driver != null:
		GigManager.on_bump()
	if driver != null and strength > 8.0:
		PlayerManager.change("mood", -2.0)
		Events.say("小心开车！", "warn")


func _update_lights() -> void:
	var night := TimeManager.daylight() < 0.35
	var on := night and (driver != null or absf(speed) > 0.5)
	for l in _lights:
		(l as SpotLight3D).visible = on
