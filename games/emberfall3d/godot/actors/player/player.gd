class_name Player
extends CharacterBody3D
## 玩家（TECH.md 第 4.1、4.2 节，GDD.md 第三、四、五节）
## 移动：
## - 电脑：左键点地面移动，按住持续移动（每 0.15 秒刷新目标）；可选 WASD。
## - 手机：虚拟摇杆（TouchControls）直接按方向移动；点摇杆区域以外的地面也能移动。
## - 点击移动走导航网格（NavigationAgent3D）；摇杆 / 键盘不走寻路，靠碰撞体贴墙滑动。
## 战斗（阶段 1.4，职业：烬卫）：
## - 左键点敌人：走到攻击距离后「断誓斩」；按住持续攻击。手机用「攻击」按钮自动锁定最近的敌人。
## - 右键 / 数字键 1 / 手机「践踏」按钮：「焚地践踏」（消耗誓火，范围伤害 + 眩晕 + 燃烧地面）。
## - 命中停顿只冻结命中双方（hitstop_t），不改全局时间。
## 占位外观：胶囊 + 方块武器（阶段 2 换成正式模型）。

signal arrived
signal hit_landed(skill_id: String, hits: int)
signal hurt(amount: int)
signal died
signal respawned

const LAYER_WORLD := Layers.WORLD
const LAYER_GROUND := Layers.GROUND
const LAYER_PLAYER := Layers.PLAYER
const HOLD_REFRESH := 0.15
const ARRIVE_DIST := 0.15
const AUTO_TARGET_RANGE := 7.0

@export var speed := 5.0
var camera: IsoCamera
var stick := Vector2.ZERO        # 虚拟摇杆输入（-1..1，y 向下为正，与 Input.get_vector 一致）
var agent: NavigationAgent3D
var moving_to := false
var hold_active := false
var hold_screen := Vector2.ZERO
var hold_timer := 0.0
var touch_index := -1
var last_target := Vector3.ZERO
var marker: MeshInstance3D
var ui_blockers: Array[Control] = []   # 这些控件（手机按钮）范围内的触点不当成点地面

# 战斗
var kit := EmberguardKit.new()
var stats: Dictionary = Balance.data().placeholder_hero
var rng := RandomNumberGenerator.new()
var attack_target: Node3D
var attack_hold := false         # 按住鼠标 / 攻击按钮：打完一下继续打
var action := ""                 # 正在进行的动作：""、"oath_cleave"、"scorch_stomp"
var action_t := 0.0
var action_hit_done := false
var hitstop_t := 0.0
var hp := 1.0
var max_hp := 1.0
var dead := false
var respawn_point := Vector3.ZERO
var _respawn_t := 0.0
var _knock_vel := Vector3.ZERO
var _knock_t := 0.0
var _hurt_t := 0.0
var _body_mat: StandardMaterial3D
var _visual: Node3D
var _blade_pivot: Node3D
var _repath_t := 0.0


func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	collision_layer = LAYER_PLAYER
	collision_mask = LAYER_WORLD | Layers.ENEMY
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	shape.shape = cap
	shape.position.y = 0.9
	add_child(shape)
	agent = NavigationAgent3D.new()
	agent.radius = 0.4
	agent.height = 1.8
	agent.path_desired_distance = 0.35
	agent.target_desired_distance = 0.25
	add_child(agent)
	max_hp = stats.get("max_hp", 200)
	hp = max_hp
	respawn_point = global_position
	_build_placeholder()


func _build_placeholder() -> void:
	_visual = Node3D.new()
	add_child(_visual)
	add_child(Look.blob_shadow(0.45))   # 圆形假阴影（不跟着倒地动画转）
	var body := MeshInstance3D.new()
	body.mesh = LowPoly.capsule(0.35, 1.8)
	_body_mat = Look.rim(_mat(Color(0.55, 0.47, 0.38)))
	body.material_override = _body_mat
	body.position.y = 0.9
	_visual.add_child(body)
	# 武器挂在肩部支点上，挥砍时绕支点转动
	_blade_pivot = Node3D.new()
	_blade_pivot.position = Vector3(0.3, 1.25, 0)
	_visual.add_child(_blade_pivot)
	var blade := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.1, 0.1, 1.3)
	blade.mesh = bm
	blade.material_override = _mat(Color(0.8, 0.82, 0.86))
	blade.position = Vector3(0, 0, 0.7)
	_blade_pivot.add_child(blade)
	_set_swing(0.0)
	# 「鼻子」：让朝向看得出来
	var nose := MeshInstance3D.new()
	var nm := BoxMesh.new()
	nm.size = Vector3(0.18, 0.12, 0.2)
	nose.mesh = nm
	nose.material_override = _mat(Color(0.91, 0.52, 0.23))
	nose.position = Vector3(0, 1.45, 0.34)
	_visual.add_child(nose)
	var light := OmniLight3D.new()
	# 跟随主角的暖光（TECH.md 第 4.6 节：主角一盏 + 附近火把），照亮脚下一圈
	light.light_color = Color(1.0, 0.72, 0.45)
	light.light_energy = 0.9
	light.omni_range = 7.0
	light.position = Vector3(0, 2.4, 0)
	add_child(light)
	# 点击目标标记（占位：一个会淡出的圆环）
	marker = MeshInstance3D.new()
	marker.mesh = LowPoly.torus(0.28, 0.38)
	var mm := _mat(Color(0.91, 0.64, 0.35))
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker.material_override = mm
	marker.top_level = true
	marker.visible = false
	add_child(marker)


static func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	return m


func _set_swing(k: float) -> void:
	## k：0 = 举刀（右后上方），1 = 挥到左前方。占位动画，正式动作在阶段 2.4。
	_blade_pivot.rotation = Vector3(deg_to_rad(lerpf(-60.0, 10.0, k)), deg_to_rad(lerpf(70.0, -80.0, k)), 0)


# ---------------- 输入 ----------------

func _unhandled_input(event: InputEvent) -> void:
	# 触屏会同时产生「模拟鼠标」事件（device = DEVICE_ID_EMULATION），这里只认真正的鼠标，
	# 触屏由下面的 ScreenTouch / ScreenDrag 处理，避免摇杆的触点被当成点地面。
	if event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
		if event.button_index == MOUSE_BUTTON_LEFT:
			hold_active = event.pressed
			hold_screen = event.position
			attack_hold = event.pressed and attack_target != null
			if event.pressed:
				click_at(event.position)
				attack_hold = attack_target != null
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			cast_skill("scorch_stomp")
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION:
		if hold_active:
			hold_screen = event.position
	elif event is InputEventScreenTouch:
		if event.pressed and touch_index == -1 and not _over_ui(event.position):
			touch_index = event.index
			hold_active = true
			hold_screen = event.position
			click_at(event.position)
			attack_hold = attack_target != null
		elif not event.pressed and event.index == touch_index:
			touch_index = -1
			hold_active = false
			attack_hold = false
	elif event is InputEventScreenDrag and event.index == touch_index:
		hold_screen = event.position
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_1:
		cast_skill("scorch_stomp")


func _over_ui(p: Vector2) -> bool:
	for c in ui_blockers:
		if is_instance_valid(c) and c.is_visible_in_tree() and c.get_global_rect().has_point(p):
			return true
	return false


func click_at(screen_pos: Vector2) -> void:
	if dead:
		return
	var enemy = pick_enemy(screen_pos)
	if enemy:
		attack_target = enemy
		moving_to = false
		return
	attack_target = null
	var p = pick_ground(screen_pos)
	if p != null:
		move_to(p)
		_show_marker(last_target)


func pick_enemy(screen_pos: Vector2):
	if camera == null:
		return null
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 200.0, Layers.ENEMY)
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	if not r.is_empty() and r.collider.is_in_group("enemy"):
		return r.collider
	return null


func pick_ground(screen_pos: Vector2):
	## 屏幕坐标 → 地面上的点：先对地面碰撞层做射线检测，没打中就与 y = 0 平面求交。
	if camera == null:
		return null
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 200.0, LAYER_GROUND)
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	if not r.is_empty():
		return r.position
	var hit = Plane(Vector3.UP, 0.0).intersects_ray(from, dir)
	return hit


func move_to(p: Vector3) -> void:
	var map := get_world_3d().navigation_map
	last_target = NavigationServer3D.map_get_closest_point(map, p)
	agent.target_position = last_target
	moving_to = true


func stop() -> void:
	moving_to = false
	hold_active = false
	agent.target_position = global_position


func _show_marker(p: Vector3) -> void:
	marker.global_position = p + Vector3(0, 0.03, 0)
	marker.visible = true
	marker.scale = Vector3.ONE
	var mat := marker.material_override as StandardMaterial3D
	mat.albedo_color.a = 0.9


# ---------------- 受击与死亡 ----------------

func combat_target() -> Dictionary:
	return {"armor": stats.get("armor", 0), "resist": {}}


func take_hit(result: Dictionary, from_dir: Vector3, knock_m: float, _stun_s: float = 0.0) -> void:
	if dead:
		return
	hp = maxf(0.0, hp - result.amount)
	_hurt_t = 0.12
	hurt.emit(result.amount)
	if knock_m > 0.0:
		var d := from_dir
		d.y = 0.0
		if d.length() > 0.001:
			_knock_t = 0.15
			_knock_vel = d.normalized() * (knock_m / _knock_t)
	if camera:
		camera.add_trauma(0.18)
	if HitFeedback.numbers_enabled:
		var r := result.duplicate()
		r["type"] = "incoming"
		r["crit"] = false
		HitFeedback.spawn_number(self, r)
	if hp <= 0.0:
		_die()


func _die() -> void:
	dead = true
	action = ""
	attack_target = null
	moving_to = false
	hold_active = false
	_respawn_t = stats.get("respawn_s", 3.0)
	died.emit()
	print("EF_PLAYER_DEAD")
	var tw := create_tween()
	tw.tween_property(_visual, "rotation_degrees:x", -80.0, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func respawn() -> void:
	dead = false
	hp = max_hp
	global_position = respawn_point
	_visual.rotation_degrees = Vector3.ZERO
	if camera:
		camera.snap()
	respawned.emit()


# ---------------- 战斗 ----------------

func nearest_enemy(max_dist: float = AUTO_TARGET_RANGE) -> Node3D:
	var best: Node3D = null
	var bd := max_dist
	for e in get_tree().get_nodes_in_group("enemy"):
		if e.get("dead"):
			continue
		var d: float = global_position.distance_to(e.global_position)
		if d < bd:
			bd = d
			best = e
	return best


func attack_nearest(hold: bool) -> void:
	## 手机「攻击」按钮：锁定最近的敌人，按住持续攻击
	attack_hold = hold
	if hold:
		attack_target = nearest_enemy()


func facing() -> Vector3:
	return Vector3(sin(rotation.y), 0, cos(rotation.y))


func face_point(p: Vector3) -> void:
	var d := p - global_position
	if Vector2(d.x, d.z).length() > 0.01:
		rotation.y = atan2(d.x, d.z)


func cast_skill(id: String) -> bool:
	if dead or action != "" or not kit.can_cast(id):
		return false
	kit.on_cast(id)
	moving_to = false
	_start_action(id)
	return true


func _start_action(id: String) -> void:
	action = id
	action_t = 0.0
	action_hit_done = false


func _resolve_action() -> void:
	var s := Balance.skill(action)
	var hits := 0
	var knock: float = Balance.fb().knockback_m[s.knockback]
	var heavy: bool = s.knockback == "heavy"
	for e in get_tree().get_nodes_in_group("enemy"):
		if e.get("dead"):
			continue
		var d: Vector3 = e.global_position - global_position
		d.y = 0.0
		var dist := d.length()
		var in_range := false
		if action == "oath_cleave":
			# 扇形：距离 ≤ 攻击距离 + 目标半径，且在正前方 arc_deg 度以内
			var ang := rad_to_deg(facing().angle_to(d.normalized())) if dist > 0.01 else 0.0
			in_range = dist <= s.range + 0.45 and ang <= s.arc_deg * 0.5
		else:
			in_range = dist <= s.radius + 0.45
		if not in_range:
			continue
		var r := DamageCalc.roll(stats, s.coef, s.type, e.combat_target(), rng)
		e.take_hit(r, d, knock, s.get("stun_s", 0.0))
		HitFeedback.apply(self, e, r, camera, heavy)
		hits += 1
	if action == "scorch_stomp":
		_spawn_stomp_fx(s)
		if camera:
			camera.add_trauma(Balance.fb().shake.heavy)
	kit.on_hit(action, hits)
	hit_landed.emit(action, hits)
	if hits > 0:
		print("EF_HIT skill=%s hits=%d" % [action, hits])


func _spawn_stomp_fx(s: Dictionary) -> void:
	var zone := BurnZone.new()
	zone.radius = s.radius
	zone.duration = s.burn.duration_s
	zone.tick = s.burn.tick_s
	zone.coef = s.burn.coef_per_tick
	zone.attacker = stats
	get_parent().add_child(zone)
	zone.global_position = Vector3(global_position.x, 0, global_position.z)
	# 冲击环（占位）：从脚下扩散到技能半径
	var ring := MeshInstance3D.new()
	ring.mesh = LowPoly.torus(0.85, 1.0)
	var m := _mat(Color(1.0, 0.7, 0.3))
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = m
	get_parent().add_child(ring)
	ring.global_position = zone.global_position + Vector3(0, 0.1, 0)
	ring.scale = Vector3(0.3, 1, 0.3)
	var tw := ring.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(s.radius, 1, s.radius), 0.25).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.3).set_delay(0.1)
	tw.chain().tween_callback(ring.queue_free)


func _update_action(delta: float) -> void:
	var s := Balance.skill(action)
	action_t += delta
	var total: float = s.windup_s + s.recover_s
	if action == "oath_cleave":
		# 前摇举刀 → 判定瞬间挥下 → 后摇收刀
		if action_t < s.windup_s:
			_set_swing(0.0)
		else:
			_set_swing(clampf((action_t - s.windup_s) / 0.08, 0.0, 1.0))
	else:
		_blade_pivot.position.y = 1.25 + (0.4 if action_t < s.windup_s else 0.0)
	if not action_hit_done and action_t >= s.windup_s:
		action_hit_done = true
		_resolve_action()
	if action_t >= total:
		action = ""
		_set_swing(0.0)
		_blade_pivot.position.y = 1.25
		if not attack_hold and attack_target != null:
			attack_target = null


func _update_attack_target() -> bool:
	## 有攻击目标时：进入攻击距离就开打，否则寻路靠近。返回 true 表示本帧由攻击逻辑接管移动。
	if attack_target == null:
		return false
	if not is_instance_valid(attack_target) or attack_target.get("dead"):
		attack_target = null
		return false
	var d := attack_target.global_position - global_position
	d.y = 0.0
	var reach: float = Balance.skill("oath_cleave").range + 0.2
	if d.length() <= reach:
		moving_to = false
		face_point(attack_target.global_position)
		_start_action("oath_cleave")
		return true
	_repath_t -= get_physics_process_delta_time()
	if _repath_t <= 0.0 or not moving_to:
		_repath_t = 0.2
		move_to(attack_target.global_position)
	return false


# ---------------- 移动 ----------------

func camera_relative(v: Vector2) -> Vector3:
	## 屏幕方向 → 世界方向：v.y < 0 是「屏幕上方」（远离相机），v.x > 0 是屏幕右方。
	var yaw := deg_to_rad(camera.yaw_deg if camera else 45.0)
	var forward := Vector3(-sin(yaw), 0, -cos(yaw))
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	return right * v.x + forward * (-v.y)


func _physics_process(delta: float) -> void:
	kit.tick(delta)
	_update_marker(delta)
	if _hurt_t > 0.0:
		_hurt_t -= delta
	_body_mat.albedo_color = Color(1.0, 0.35, 0.3) if _hurt_t > 0.0 else Color(0.55, 0.47, 0.38)
	if dead:
		_respawn_t -= delta
		if _respawn_t <= 0.0:
			respawn()
		return
	if _knock_t > 0.0:
		_knock_t -= delta
		velocity = _knock_vel
		move_and_slide()
		global_position.y = 0.0
		return
	if hitstop_t > 0.0:
		# 命中停顿：动作与移动都冻结
		hitstop_t -= delta
		velocity = Vector3.ZERO
		return
	if action != "":
		velocity = Vector3.ZERO
		_update_action(delta)
		return
	var dir := Vector3.ZERO
	var kb := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var s := stick if stick.length() > 0.15 else kb
	if s.length() > 0.15:
		moving_to = false
		hold_active = false
		attack_target = null
		dir = camera_relative(s.limit_length(1.0))
	elif _update_attack_target():
		return
	else:
		if hold_active and attack_target == null:
			hold_timer -= delta
			if hold_timer <= 0.0:
				hold_timer = HOLD_REFRESH
				var p = pick_ground(hold_screen)
				if p != null:
					move_to(p)
		if moving_to:
			# 到达判定按水平距离自己算：导航网格表面按格子高度量化，比地面略高，
			# NavigationAgent3D 的三维距离可能永远达不到阈值（1.3 实测 is_navigation_finished 不会变 true）。
			var flat := Vector2(global_position.x - last_target.x, global_position.z - last_target.z)
			if flat.length() < ARRIVE_DIST:
				moving_to = false
				if not hold_active and attack_target == null:
					arrived.emit()
					print("EF_ARRIVED x=%.2f z=%.2f" % [global_position.x, global_position.z])
			else:
				var nxt := agent.get_next_path_position()
				var to := nxt - global_position
				to.y = 0.0
				if to.length() > 0.01:
					dir = to.normalized()
	velocity = dir * speed
	move_and_slide()
	global_position.y = 0.0
	if dir.length() > 0.05:
		rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), 1.0 - exp(-14.0 * delta))


func _update_marker(delta: float) -> void:
	if marker.visible:
		var mat := marker.material_override as StandardMaterial3D
		mat.albedo_color.a -= delta * 1.6
		marker.scale *= 1.0 + delta * 0.8
		if mat.albedo_color.a <= 0.0:
			marker.visible = false
