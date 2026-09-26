class_name IsoCamera
extends Camera3D
## 斜俯视相机（TECH.md 第 3 节 camera/、GDD.md 第三节）：
## - 固定俯角 55°、偏航 45°，只跟随位置，不随角色转向；
## - 平滑跟随（指数衰减，与帧率无关）；
## - 小范围缩放（鼠标滚轮 / 触控板捏合）；
## - 横屏按垂直视角、竖屏按水平视角，保证手机竖屏也能看到足够宽的范围；
## - 挡住主角的墙体 / 柱子自动半透明（碰撞层 OCCLUDER_LAYER 上的物体）；
## - 屏幕震动（add_trauma），可整体关闭（无障碍设置）。

const OCCLUDER_LAYER := 2          # 碰撞层第 2 层（位值 2）：会遮挡视线、需要半透明的物体
const FADE_ALPHA := 0.28
const FADE_SPEED := 8.0

@export var target: Node3D
@export var pitch_deg := 55.0
@export var yaw_deg := 45.0
@export var distance := 15.0
@export var min_distance := 11.0
@export var max_distance := 19.0
@export var follow_speed := 6.0     # 越大跟得越紧
@export var landscape_fov := 40.0   # 横屏：垂直视角
@export var portrait_fov := 44.0    # 竖屏：水平视角
@export var look_height := 0.9      # 看向主角胸口高度

var shake_enabled := true
var trauma := 0.0
var focus := Vector3.ZERO           # 当前平滑后的跟随点
var fade := {}                      # MeshInstance3D -> 当前透明度
var _noise_t := 0.0


func _ready() -> void:
	current = true
	if target:
		focus = target.global_position
	get_viewport().size_changed.connect(apply_aspect)
	apply_aspect()
	_place()


func _process(delta: float) -> void:
	if target:
		var k := 1.0 - exp(-follow_speed * delta)
		focus = focus.lerp(target.global_position, k)
	_place()
	if shake_enabled and trauma > 0.0:
		_noise_t += delta * 40.0
		var s := trauma * trauma * 0.35
		h_offset = sin(_noise_t * 1.3) * s
		v_offset = cos(_noise_t * 1.7) * s
		trauma = maxf(0.0, trauma - delta * 1.8)
	else:
		h_offset = 0.0
		v_offset = 0.0
	_update_occluders(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_by(-1.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_by(1.0)
	elif event is InputEventMagnifyGesture:
		zoom_by((1.0 - event.factor) * 8.0)


func zoom_by(step: float) -> void:
	distance = clampf(distance + step, min_distance, max_distance)


func snap() -> void:
	## 立即对准目标（切换区域、传送后调用）
	if target:
		focus = target.global_position
	_place()


func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)


static func offset_for(pitch: float, yaw: float, dist: float) -> Vector3:
	var p := deg_to_rad(pitch)
	var y := deg_to_rad(yaw)
	return Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p)) * dist


static func is_portrait(size: Vector2) -> bool:
	return size.y > size.x


func apply_aspect() -> void:
	var size := Vector2(get_viewport().get_visible_rect().size)
	if is_portrait(size):
		keep_aspect = Camera3D.KEEP_WIDTH
		fov = portrait_fov
	else:
		keep_aspect = Camera3D.KEEP_HEIGHT
		fov = landscape_fov


func visible_width_at_focus(size: Vector2) -> float:
	## 在跟随点处能看到的水平宽度（米），用于测试手机竖屏下视野是否够宽
	var half_h: float
	if is_portrait(size):
		half_h = deg_to_rad(portrait_fov) * 0.5
	else:
		half_h = atan(tan(deg_to_rad(landscape_fov) * 0.5) * size.x / size.y)
	return 2.0 * distance * tan(half_h)


func _place() -> void:
	var look := focus + Vector3(0, look_height, 0)
	global_position = look + offset_for(pitch_deg, yaw_deg, distance)
	look_at(look, Vector3.UP)


func _update_occluders(delta: float) -> void:
	var hit := {}
	if target and is_inside_tree():
		var space := get_world_3d().direct_space_state
		var from := global_position
		for h in [0.3, 1.0, 1.7]:
			var to: Vector3 = target.global_position + Vector3(0, h, 0)
			var exclude: Array[RID] = []
			for i in 4:
				var q := PhysicsRayQueryParameters3D.create(from, to, OCCLUDER_LAYER, exclude)
				var r := space.intersect_ray(q)
				if r.is_empty():
					break
				var col: Object = r.collider
				exclude.append(r.rid)
				if col.has_meta("fade_meshes"):
					for m in col.get_meta("fade_meshes"):
						hit[m] = true
	for m in hit:
		if not fade.has(m):
			fade[m] = 1.0
	for m in fade.keys():
		if not is_instance_valid(m):
			fade.erase(m)
			continue
		var want := FADE_ALPHA if hit.has(m) else 1.0
		var a: float = move_toward(fade[m], want, FADE_SPEED * delta)
		fade[m] = a
		_set_alpha(m, a)
		if a >= 1.0 and not hit.has(m):
			fade.erase(m)


static func _set_alpha(m: MeshInstance3D, a: float) -> void:
	var mat := m.material_override as StandardMaterial3D
	if mat == null:
		return
	if a < 0.999:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	else:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	var c := mat.albedo_color
	c.a = a
	mat.albedo_color = c
