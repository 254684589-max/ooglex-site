class_name EnemyBase
extends CharacterBody3D
## 敌人基类（TECH.md 第 4.3 节）：受击（闪白 / 击退 / 眩晕 / 命中停顿）、死亡、状态机骨架、
## 寻路与视线、地面预警、群体推开、思考频率分级。具体行为由子类的 _ai() 实现：
##   EnemyMelee（近战追击）· EnemyCharger（蓄力冲锋）· EnemyRanged（保持距离放箭）· EnemySummoner（召唤仆从）
##   TrainingDummy（训练木桩：不攻击，被打后弹回原位，倒下后复活）
## 数值来自 data/monsters.json（木桩来自 data/balance.json）。外观都是占位几何体。

signal died(enemy: EnemyBase)

const FAR_THINK := 25.0          # 超过这个距离，每 0.5 秒才思考一次
const LEASH := 24.0              # 玩家离出生点超过这个距离（或玩家死亡）就回家并回满血

var def: Dictionary = {}
var player: Node3D
var hp := 1.0
var max_hp := 1.0
var home := Vector3.ZERO
var state := "idle"              # idle / chase / windup / act / recover / return / dead
var state_t := 0.0
var hitstop_t := 0.0
var flash_t := 0.0
var stun_t := 0.0
var knock_vel := Vector3.ZERO
var knock_t := 0.0
var dead := false
var cooldowns := {}
var mode := 0                    # 子类用：当前蓄力的是哪种招式（不要放进 cooldowns，那里的值每帧都会递减）
var rng := RandomNumberGenerator.new()
var agent: NavigationAgent3D
var move_dir := Vector3.ZERO     # 本帧想走的方向（_ai 设置）
var move_speed := 0.0
var slow_t := 0.0                 # 寂霜环减速剩余秒数（P4，V0.1：减速 3 秒、移动速度减半）
var _repath_t := 0.0
var _los_t := 0.0
var _los_cached := false
static var prof_us := 0          # 性能统计：所有敌人物理更新（AI + 移动 + 碰撞）累计耗时（微秒），测试用
static var _enemy_cache: Array = []
static var _enemy_cache_frame := -1
var _think_acc := 0.0
var _warnings: Array[MeshInstance3D] = []
var _mats: Array[StandardMaterial3D] = []
var _base_colors: Array[Color] = []
var visual: Node3D
var hp_label: Label3D
var stun_mark: Label3D


func _ready() -> void:
	add_to_group("enemy")
	if home == Vector3.ZERO:
		home = global_position
	collision_layer = Layers.ENEMY
	collision_mask = Layers.WORLD
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = def.get("radius", 0.45)
	cyl.height = 1.9
	shape.shape = cyl
	shape.position.y = 0.95
	add_child(shape)
	rng.randomize()
	_repath_t = rng.randf_range(0.0, 0.4)    # 错开寻路刷新，避免所有敌人在同一帧重算路径
	agent = NavigationAgent3D.new()
	agent.radius = 0.45
	agent.path_desired_distance = 0.4
	add_child(agent)
	visual = Node3D.new()
	add_child(visual)
	_build_visual()
	if def.get("champ", "") != "":
		_champion_look()
	add_child(Look.blob_shadow(def.get("radius", 0.45)))
	hp_label = _label(18, Vector3(0, def.get("label_h", 2.45), 0))
	stun_mark = _label(22, Vector3(0, def.get("label_h", 2.45) + 0.35, 0))
	stun_mark.modulate = Color(1.0, 0.85, 0.3)
	stun_mark.text = "眩晕"
	stun_mark.visible = false
	update_label()


func setup(definition: Dictionary, target: Node3D) -> void:
	def = definition
	player = target
	max_hp = def.get("hp", 100)
	hp = max_hp


# ---------------- 子类覆盖 ----------------

func _build_visual() -> void:
	pass


func _ai(_delta: float) -> void:
	pass


func _on_dead() -> void:
	## 倒地 → 停一下 → 从身上烧穿出洞、边缘发余烬光，整个消散（阶段 2.5 溶解着色器；之前是沉进地里）
	var tw := create_tween()
	tw.tween_property(visual, "rotation_degrees:x", -85.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_interval(0.6)
	tw.tween_callback(func():
		var mats := Fx.dissolve_materials(visual)
		Fx.burst(get_parent(), global_position + Vector3(0, 0.4, 0), Color(1.0, 0.5, 0.15), 16, {"speed": 1.2, "life": 1.0, "size": 0.1, "gravity": -1.5, "sphere": 0.6, "explosive": 0.3})
		var t2 := create_tween()
		t2.tween_method(func(v: float):
			for m in mats:
				m.set_shader_parameter("progress", v), 0.0, 1.0, 1.1)
		t2.tween_callback(queue_free))


# ---------------- 外观工具 ----------------

func part(mesh: Mesh, pos: Vector3, c: Color, emissive: float = 0.0, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mat.roughness = 1.0
	if emissive > 0.0:
		mat.emission_enabled = true
		mat.emission = c
		mat.emission_energy_multiplier = emissive
	Look.rim(mat, 0.25)       # 轮廓光：暗处也能看清剪影
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot
	visual.add_child(mi)
	_mats.append(mat)
	_base_colors.append(c)
	return mi


static func box(s: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = s
	return m


static func cyl(r_top: float, r_bot: float, h: float) -> CylinderMesh:
	return LowPoly.cylinder(r_top, r_bot, h)


static func sphere(r: float) -> SphereMesh:
	return LowPoly.sphere(r)


func _label(size: int, pos: Vector3) -> Label3D:
	var l := Label3D.new()
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = true
	l.pixel_size = 0.0011
	l.font_size = size
	l.outline_size = 8
	l.position = pos
	add_child(l)
	return l


func update_label() -> void:
	if hp_label == null:
		return
	hp_label.text = "%s  %d / %d" % [def.get("name", "?"), ceili(hp), int(max_hp)]
	var champ: bool = def.get("champ", "") != ""
	# V0.1：精英蓝名
	hp_label.modulate = (Color(0.55, 0.62, 1.0) if champ else Color(0.95, 0.85, 0.7)) if hp > max_hp * 0.3 else Color(1.0, 0.45, 0.35)
	# 满血且没被惊动时不显示，减少画面上的字
	hp_label.visible = hp < max_hp or state != "idle" or def.get("always_label", false)


# ---------------- 受击与死亡 ----------------

func combat_target() -> Dictionary:
	return {"armor": def.get("armor", 0), "resist": def.get("resist", {})}


func attacker_stats(dmg: Array) -> Dictionary:
	# V0.1 的怪物不会暴击
	return {"level": def.get("level", 1), "main_stat": 0, "weapon_min": dmg[0], "weapon_max": dmg[1], "damage_bonus": 0.0, "crit_chance": 0.0}


func take_hit(result: Dictionary, from_dir: Vector3, knock_m: float, stun_s: float = 0.0) -> void:
	if dead:
		return
	if def.get("champ", "") == "stone":
		# 石肤精英：受到的伤害 ×0.6（V0.1 hurtMon）
		result = result.duplicate()
		result.amount = maxi(1, roundi(result.amount * Act1Data.rules().monsters.champion.stone_taken_mul))
	hp = maxf(0.0, hp - result.amount)
	flash_t = Balance.fb().flash_s
	if knock_m > 0.0 and not def.get("no_knockback", false):
		var d := from_dir
		d.y = 0.0
		if d.length() > 0.001:
			knock_t = 0.15
			knock_vel = d.normalized() * (knock_m / knock_t)
	if stun_s > 0.0:
		stun_t = maxf(stun_t, stun_s)
		clear_warning()
		if state in ["windup", "act"]:
			set_state("recover")
	if state == "idle":
		set_state("chase")
	update_label()
	if hp <= 0.0:
		die()


func die() -> void:
	dead = true
	set_state("dead")
	collision_layer = 0
	clear_warning()
	hp_label.visible = false
	stun_mark.visible = false
	died.emit(self)
	# 击杀经验（P3）：木桩没有 xp 字段，不给经验
	if def.get("xp", 0) > 0 and is_instance_valid(player) and player.has_method("on_enemy_killed"):
		player.on_enemy_killed(self)
	# 掉落（P5）：由场景里登记为 loot_host 的节点（scenes/main.gd）负责生成地上的金币、药水与装备
	if def.get("xp", 0) > 0 and is_inside_tree():
		get_tree().call_group("loot_host", "on_enemy_died", self)
	if def.get("champ", "") == "fire":
		_fire_ring()
	_on_dead()


func set_state(s: String) -> void:
	state = s
	state_t = 0.0
	update_label()


# ---------------- 感知、移动与预警 ----------------

func dist_to_player() -> float:
	if player == null:
		return INF
	var d := player.global_position - global_position
	return Vector2(d.x, d.z).length()


func player_alive() -> bool:
	return player != null and not player.get("dead")


const CHAMP_COLORS := {"fast": Color(0.4, 0.9, 1.0), "stone": Color(0.7, 0.7, 0.72), "fury": Color(1.0, 0.3, 0.2), "vamp": Color(0.75, 0.1, 0.25), "fire": Color(1.0, 0.55, 0.15)}


func _champion_look() -> void:
	## 精英（P5）：体型大一点，脚下一圈对应特性颜色的光环
	visual.scale = Vector3.ONE * 1.15
	var ring := MeshInstance3D.new()
	ring.mesh = LowPoly.torus(0.85, 1.0)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = CHAMP_COLORS.get(def.champ, Color.WHITE)
	m.emission_enabled = true
	m.emission = m.albedo_color
	m.emission_energy_multiplier = 1.5
	ring.material_override = m
	ring.scale = Vector3.ONE * (float(def.get("radius", 0.45)) + 0.25)
	ring.position.y = 0.06
	ring.name = "ChampionRing"
	add_child(ring)


func _fire_ring() -> void:
	## 焚烧精英死亡时爆出火环（V0.1 killMon：半径 2.2 格 ≈ 3.3 米，伤害 = 该怪伤害上限）
	var radius: float = float(Act1Data.rules().monsters.champion.fire_death_ring.radius) * 1.5
	var parent := get_parent()
	var pos := global_position
	var ring := MeshInstance3D.new()
	ring.mesh = LowPoly.torus(0.85, 1.0)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1.0, 0.48, 0.16, 0.9)
	ring.material_override = m
	parent.add_child(ring)
	ring.global_position = pos + Vector3(0, 0.15, 0)
	ring.scale = Vector3(0.3, 1, 0.3)
	var tw := ring.create_tween()
	tw.tween_property(ring, "scale", Vector3(radius, 1, radius), 0.36)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.2)
	tw.tween_callback(ring.queue_free)
	var pl := player
	var dmg: Array = def.attack.dmg if def.has("attack") else def.shot.dmg
	var lvl: int = def.get("level", 1)
	var tree := get_tree()
	tree.create_timer(0.3).timeout.connect(func():
		if is_instance_valid(pl) and not pl.get("dead") and Vector2(pl.global_position.x - pos.x, pl.global_position.z - pos.z).length() <= radius:
			var r := DamageCalc.roll({"level": lvl, "main_stat": 0, "weapon_min": dmg[1], "weapon_max": dmg[1], "damage_bonus": 0.0, "crit_chance": 0.0}, 1.0, "fire", pl.combat_target(), RandomNumberGenerator.new())
			r.type = "fire"
			pl.take_hit(r, pl.global_position - pos, 0.3))


func apply_slow(seconds: float) -> void:
	slow_t = maxf(slow_t, seconds)


func has_los(fresh := false) -> bool:
	## 视线检测：结果缓存 0.2 秒（60 只怪物每帧各打一条射线太浪费）；fresh = true 时强制重测
	if player == null:
		return false
	if not fresh and _los_t > 0.0:
		return _los_cached
	_los_t = 0.2
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 1.2, 0), player.global_position + Vector3(0, 1.2, 0), Layers.WORLD)
	_los_cached = get_world_3d().direct_space_state.intersect_ray(q).is_empty()
	return _los_cached


func face(p: Vector3) -> void:
	var d := p - global_position
	if Vector2(d.x, d.z).length() > 0.01:
		rotation.y = atan2(d.x, d.z)


func forward() -> Vector3:
	return Vector3(sin(rotation.y), 0, cos(rotation.y))


func go_towards(p: Vector3, speed: float, delta: float) -> void:
	## 有视线且距离近就直走，否则按导航网格寻路（每 0.4 秒刷新一次路径）
	var d := p - global_position
	d.y = 0.0
	if d.length() < 6.0 and has_los():
		move_dir = d.normalized()
	else:
		_repath_t -= delta
		if _repath_t <= 0.0:
			_repath_t = 0.4
			agent.target_position = p
		var nxt := agent.get_next_path_position() - global_position
		nxt.y = 0.0
		move_dir = nxt.normalized() if nxt.length() > 0.05 else Vector3.ZERO
	move_speed = speed
	if move_dir.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(move_dir.x, move_dir.z), 0.25)


func show_warning(kind: String, size: Vector2, at: Vector3, yaw: float = 0.0, keep_existing := false) -> void:
	## 地面预警（GDD.md 第 7.3 节：只看画面就能躲）：circle = 圆形，size.x 为半径；line = 长条，size = (宽, 长)
	## keep_existing = true 时保留已有预警（一次出现多个红圈）
	if not keep_existing:
		clear_warning()
	var _warning := MeshInstance3D.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1.0, 0.23, 0.18, 0.18)
	m.no_depth_test = false
	if kind == "circle":
		_warning.mesh = cyl(size.x, size.x, 0.02)
	else:
		var b := BoxMesh.new()
		b.size = Vector3(size.x, 0.02, size.y)
		_warning.mesh = b
	_warning.material_override = m
	_warning.top_level = true
	add_child(_warning)
	if kind == "line":
		var dir := Vector3(sin(yaw), 0, cos(yaw))
		_warning.global_position = at + dir * size.y * 0.5 + Vector3(0, 0.03, 0)
		_warning.global_rotation = Vector3(0, yaw, 0)
	else:
		_warning.global_position = at + Vector3(0, 0.03, 0)
	_warnings.append(_warning)


func clear_warning() -> void:
	for w in _warnings:
		if is_instance_valid(w):
			w.queue_free()
	_warnings.clear()


func has_warning() -> bool:
	return not _warnings.is_empty()


func _update_warning(progress: float) -> void:
	for w in _warnings:
		var m := w.material_override as StandardMaterial3D
		m.albedo_color.a = lerpf(0.15, 0.55, clampf(progress, 0.0, 1.0))


# ---------------- 主循环 ----------------

func _physics_process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_tick(delta)
	prof_us += Time.get_ticks_usec() - t0


func _tick(delta: float) -> void:
	if dead:
		return
	if flash_t > 0.0:
		flash_t -= delta
	var white := flash_t > 0.0
	if slow_t > 0.0:
		slow_t -= delta
	for i in _mats.size():
		_mats[i].albedo_color = Color(1, 0.97, 0.92) if white else (_base_colors[i].lerp(Color(0.55, 0.8, 1.0), 0.55) if slow_t > 0.0 else _base_colors[i])
	stun_mark.visible = stun_t > 0.0
	for k in cooldowns.keys():
		cooldowns[k] = maxf(0.0, cooldowns[k] - delta)
	if stun_t > 0.0:
		stun_t -= delta
	if hitstop_t > 0.0:
		hitstop_t -= delta
		return
	state_t += delta
	_los_t -= delta
	if knock_t > 0.0:
		knock_t -= delta
		velocity = knock_vel
	elif stun_t > 0.0:
		velocity = Vector3.ZERO
	else:
		# 思考频率分级：离玩家远的敌人每 0.5 秒才思考一次；两次思考之间沿用上次决定的移动方向。
		var far := player != null and dist_to_player() > FAR_THINK
		_think_acc += delta
		if not far or _think_acc >= 0.5:
			move_dir = Vector3.ZERO
			_ai(_think_acc if far else delta)
			_think_acc = 0.0
		velocity = move_dir * move_speed * (Act1Data.rules().skill_formulas.nova.slow_mul if slow_t > 0.0 else 1.0)
		velocity += _separation() * 2.0
	move_and_slide()
	global_position.y = 0.0


func _separation() -> Vector3:
	## 群体推开：离其他敌人太近时互相推开一点（TECH.md 第 4.3 节的退化做法）
	var push := Vector3.ZERO
	for e in enemies_this_frame():
		if e == self or not is_instance_valid(e) or e.dead:
			continue
		var d: Vector3 = global_position - e.global_position
		d.y = 0.0
		var l := d.length()
		if l < 0.95 and l > 0.001:
			push += d / l * (0.95 - l)
	# P5：主角不再被怪物挡住（主角碰撞不含敌人层），改由怪物让开：和主角重叠时往外推（V0.1 separate）
	if is_instance_valid(player) and not player.get("dead"):
		var dp: Vector3 = global_position - player.global_position
		dp.y = 0.0
		var need: float = float(def.get("radius", 0.45)) + 0.35
		var lp := dp.length()
		if lp < need:
			push += (dp / lp if lp > 0.001 else Vector3(1, 0, 0)) * (need - lp) * 2.5
	return push


func enemies_this_frame() -> Array:
	## 敌人列表每个物理帧只取一次，所有敌人共用（避免 N 只敌人各自遍历一次分组）
	var f := Engine.get_physics_frames()
	if f != _enemy_cache_frame:
		_enemy_cache_frame = f
		_enemy_cache = get_tree().get_nodes_in_group("enemy")
	return _enemy_cache


# ---------------- 通用行为片段 ----------------

func leash_check() -> bool:
	## 玩家死了或跑远了：回家并回满血。返回 true 表示本帧在执行回家
	if state == "return":
		var d := home - global_position
		d.y = 0.0
		if d.length() < 0.5:
			hp = max_hp
			set_state("idle")
		else:
			go_towards(home, def.get("speed", 3.0) * 1.3, get_physics_process_delta_time())
		return true
	if state != "idle" and (not player_alive() or (player.global_position - home).length() > LEASH):
		clear_warning()
		set_state("return")
		return true
	return false


func notice_check() -> bool:
	## 待机时发现玩家（距离 + 视线）就开始追。返回 true 表示仍在待机
	if state != "idle":
		return false
	if player_alive() and dist_to_player() <= def.get("aggro", 10.0) and has_los():
		set_state("chase")
		_alert_pack()
		return false
	return true


func _alert_pack() -> void:
	## 一只发现玩家，附近 6 米内待机的同伴一起被惊动
	for e in enemies_this_frame():
		if e != self and is_instance_valid(e) and not e.dead and e.state == "idle" and e.global_position.distance_to(global_position) < 6.0 and e.has_method("set_state") and e.def.has("aggro"):
			e.set_state("chase")


func melee_hit(dmg: Array, reach: float, arc_deg: float) -> bool:
	## 近战判定：玩家在正前方扇形范围内就命中
	if not player_alive():
		return false
	var d := player.global_position - global_position
	d.y = 0.0
	if d.length() > reach + 0.35:
		return false
	if d.length() > 0.01 and rad_to_deg(forward().angle_to(d.normalized())) > arc_deg * 0.5:
		return false
	var dm := dmg
	if def.get("champ", "") == "fire":
		var fm: float = Act1Data.rules().monsters.champion.fire_dmg_mul
		dm = [roundi(dmg[0] * fm), roundi(dmg[1] * fm)]
	var r := DamageCalc.roll(attacker_stats(dm), 1.0, "physical", player.combat_target(), rng)
	player.take_hit(r, d, 0.25)
	on_damage_dealt(r.amount)
	return true


## 嗜血精英：打中玩家时按伤害回血（V0.1 hurtHero）
func on_damage_dealt(amount: float) -> void:
	if def.get("champ", "") == "vamp" and not dead:
		hp = minf(max_hp, hp + amount)
		update_label()
