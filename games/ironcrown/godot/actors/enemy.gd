class_name Enemy
extends CharacterBody3D
## 敌人（路线图 2.5；GDD.md 6.1、6.2；TECH.md 4.3、4.4）。数值在 data/enemies.json（棍手、剑手）。
## 状态：巡逻 → 起疑（头顶「？ 起疑」）→ 警觉（「！ 警觉」，喊附近同伙）→ 战斗 → 受重伤时逃跑或求饶；另有失衡、后退、倒下。
## 感知：前方 110° 视野锥 + 视线射线，距离看光照（玩家站在灯火旁 20 米，暗处 8 米，蹲着再打六折）；听觉看玩家动静（跑 10 米、走 4 米、蹲 1.5 米、挥剑 8 米）。
## 战斗：向 CombatDirector 要攻击令牌，拿到才上前出招（起手 → 命中帧 → 收招），没拿到就在 3.5 米外绕圈。
## 剑手会格挡轻击；重击破防让它失衡。完美格挡它的攻击也会让它失衡 0.8 秒，失衡期间受到的伤害加倍（DamageCalc）。
## 寻路：现在只在平坦的训练场里直线走（加碰撞滑动）；进街巷时再用导航网格（TECH.md 4.4）。
## 外观是占位胶囊人（正式人物在阶段 A）。
## 3.3：nonlethal 的种类（酒馆醉汉）用拳头、打不死：生命最少留 1，到 flee_below 就认输；它打玩家也不致命（Melee.KO_FLOOR）。
## 打架时由 Brawl 现场生成（engage() 直接进入战斗；display_override 用 NPC 的名字）。

signal state_changed(enemy: Enemy, state: String)
signal died(enemy: Enemy)

enum State { PATROL, SUSPICIOUS, ALERT, COMBAT, RETREAT, STAGGER, FLEE, YIELD, DEAD }
const STATE_NAMES := ["patrol", "suspicious", "alert", "combat", "retreat", "stagger", "flee", "yield", "dead"]
const STATE_LABELS := ["", "？ 起疑", "！ 警觉", "！", "后退", "失衡", "逃跑", "求饶", ""]

const DATA_PATH := "res://data/enemies.json"
const DATA_KEYS := ["name", "coat", "weapon", "hp", "armor", "weapon_base", "strength", "skill", "walk", "run", "reach",
	"windup", "heavy_windup", "strike", "recover", "heavy_chance", "block_chance", "stamina", "attack_cost", "stamina_regen",
	"retreat_below", "circle_side", "flee_below", "yield_chance", "loot", "silver", "faction", "nonlethal"]
const FOV_HALF := 55.0            # 视野锥 110°
const SIGHT_LIT := 20.0
const SIGHT_DARK := 8.0
const CROUCH_SIGHT := 0.6
const NOISE := {"run": 10.0, "walk": 4.0, "crouch": 1.5, "fight": 8.0}
const SUSPECT_AT := 0.35          # 怀疑值到这里进入「起疑」
const ALERT_TIME := 0.6           # 「在那儿！」喊话的时间
const CALL_RADIUS := 12.0         # 警觉时叫上这个范围内的同伙
const LOSE_TIME := 6.0            # 战斗中看不到玩家这么久，回到起疑去找
const CIRCLE_DIST := 3.5
const STAGGER_TIME := 0.8
const TURN_SPEED := 7.0
const EYE := 1.6
const THINK_STEP := 0.1           # 感知每 0.1 秒算一次（射线不必每帧打）

var kind := "clubber"
var enemy_id := ""
var display_override := ""       # 打架时用说话那个 NPC 的名字（3.3）
var data: Dictionary = {}
var display_name := ""
var hp := 1
var hp_max := 1
var armor := 0.0
var stamina := 100.0
var state := State.PATROL
var action := ""                  # 战斗中的动作：approach / circle / windup / strike / recover / block
var action_t := 0.0
var attack_kind := "light"
var hit_done := false
var has_token := false
var token_cd := 0.0
var circle_dir := 1.0
var waypoints: Array = []
var wp_index := 0
var wp_wait := 0.0
var suspicion := 0.0
var last_known := Vector3.ZERO
var since_seen := 0.0
var state_t := 0.0
var think_t := 0.0
var sees_player := false
var stop_left := 0.0
var flash := 0.0
var rng := RandomNumberGenerator.new()
var player: FpController
var director: CombatDirector
var body: Node3D
var arm: Node3D
var name_label: Label3D
var status_label: Label3D
var coat_mat: StandardMaterial3D
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var staggered: bool:
	get:
		return state == State.STAGGER


static func types() -> Dictionary:
	if not Engine.has_meta("ic_enemies"):
		var f := FileAccess.open(DATA_PATH, FileAccess.READ)
		Engine.set_meta("ic_enemies", JSON.parse_string(f.get_as_text()) if f else {})
	return Engine.get_meta("ic_enemies")


## 数据校验：每种敌人的字段齐全、数值合理；返回错误列表（自动化测试用）
static func validate_types(d: Dictionary) -> Array:
	var errs := []
	for k in d:
		if str(k).begins_with("_"):
			continue
		var t: Dictionary = d[k]
		for key in DATA_KEYS:
			if not t.has(key):
				errs.append("%s 缺少 %s" % [k, key])
		for key in t:
			if not key in DATA_KEYS:
				errs.append("%s 有不认识的字段 %s" % [k, key])
		if not GameState.progression().get("factions", {}).has(str(t.get("faction", ""))):
			errs.append("%s 的势力 %s 不在 progression.json 里" % [k, t.get("faction", "")])
		for it in t.get("loot", []):
			if GameState.item(str(it)).is_empty():
				errs.append("%s 的掉落 %s 不在 items.json 里" % [k, it])
		if float(t.get("hp", 0)) <= 0 or float(t.get("reach", 0)) <= 0:
			errs.append("%s 的生命或攻击距离不对" % k)
		for key in ["heavy_chance", "block_chance", "flee_below", "yield_chance"]:
			if float(t.get(key, 0)) < 0.0 or float(t.get(key, 0)) > 1.0:
				errs.append("%s 的 %s 应在 0..1" % [k, key])
		if not str(t.get("weapon", "")) in ["sword", "club", "fists"]:
			errs.append("%s 的兵器 %s 不认识" % [k, t.get("weapon", "")])
		if bool(t.get("nonlethal", false)) and (float(t.get("flee_below", 0)) <= 0.0 or float(t.get("yield_chance", 0)) < 1.0):
			errs.append("%s 打不死，打到 flee_below 必须认输（yield_chance = 1）" % k)
	return errs


static func make(kind_id: String, id: String, route: Array = []) -> Enemy:
	var e := Enemy.new()
	e.kind = kind_id
	e.enemy_id = id
	e.waypoints = route
	return e


func _ready() -> void:
	add_to_group("enemy")
	add_to_group("damageable")
	data = types()[kind]
	display_name = display_override if display_override != "" else str(data.name)
	hp_max = int(data.hp)
	hp = hp_max
	armor = float(data.armor)
	stamina = float(data.stamina)
	rng.seed = hash("%d:enemy:%s" % [GameState.seed_value, enemy_id])
	circle_dir = 1.0 if rng.randf() < 0.5 else -1.0
	collision_layer = 1 | 8
	collision_mask = 1 | 2
	floor_max_angle = deg_to_rad(46.0)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.75
	cs.shape = cap
	cs.position.y = 0.875
	add_child(cs)
	body = Npc.build_body(self, Color(str(data.coat)))
	coat_mat = (body.get_child(0) as MeshInstance3D).mesh.material
	coat_mat.emission_enabled = true
	coat_mat.emission = Color("ff5a3a")
	coat_mat.emission_energy_multiplier = 0.0
	_build_arm()
	# 头顶的字在屏幕上大小固定：贴身打斗时不糊满画面，远处也看得清（2.5 截图）
	name_label = Blocks.label(self, display_name, Vector3(0, 2.0, 0), 28, 0.0009)
	status_label = Blocks.label(self, "", Vector3(0, 2.12, 0), 30, 0.001)
	status_label.modulate = Color("ffcf6a")
	for l in [name_label, status_label]:
		l.fixed_size = true
	if waypoints.is_empty():
		waypoints = [global_position]
	last_known = global_position
	if GameState.dead.has(enemy_id):              # 读档：已经倒下的，直接摆成倒下的样子（2.8）
		var p: Array = GameState.dead[enemy_id]
		global_position = Vector3(p[0], p[1], p[2])
		_die.call_deferred(true)


func _build_arm() -> void:
	arm = Node3D.new()
	arm.name = "Arm"
	arm.position = Vector3(0.34, 1.3, -0.05)
	body.add_child(arm)
	var kit := MeshKit.new()
	var mats := {}
	if data.weapon == "fists":
		kit.box("coat", Vector3(0, -0.2, 0), Vector3(0.1, 0.32, 0.1))       # 小臂
		kit.box("skin", Vector3(0, 0.02, 0), Vector3(0.11, 0.12, 0.11))     # 拳头
		var coat := StandardMaterial3D.new()
		coat.albedo_color = Color(str(data.coat)).darkened(0.15)
		coat.vertex_color_use_as_albedo = true
		var skin := StandardMaterial3D.new()
		skin.albedo_color = Color("c8a88a")
		skin.vertex_color_use_as_albedo = true
		mats = {"coat": coat, "skin": skin}
	elif data.weapon == "sword":
		kit.box("steel", Vector3(0, 0.45, 0), Vector3(0.05, 0.7, 0.012))
		kit.box("wood", Vector3(0, 0.08, 0), Vector3(0.18, 0.03, 0.03))
		kit.box("wood", Vector3(0, 0.0, 0), Vector3(0.035, 0.16, 0.035))
		var steel := StandardMaterial3D.new()
		steel.albedo_color = Color("aab2bc")
		steel.metallic = 0.35
		steel.roughness = 0.4
		steel.vertex_color_use_as_albedo = true
		mats = {"steel": steel, "wood": Look.mat("timber")}
	else:
		kit.cylinder("wood", Vector3(0, -0.05, 0), Vector3(0, 0.75, 0), 0.03, 0.055, 6)
		mats = {"wood": Look.mat("timber")}
	var mi := kit.build(mats)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	arm.add_child(mi)
	arm.rotation_degrees = Vector3(-40, 0, 0)


func state_name() -> String:
	return STATE_NAMES[state]


func alive() -> bool:
	return state != State.DEAD


func _enter(s: State) -> void:
	if s == state:
		return
	if s in [State.STAGGER, State.FLEE, State.YIELD, State.DEAD, State.RETREAT, State.PATROL, State.SUSPICIOUS]:
		_release_token()
	state = s
	state_t = 0.0
	action = ""
	action_t = 0.0
	_update_status()
	state_changed.emit(self, state_name())


func _update_status() -> void:
	var t: String = STATE_LABELS[state]
	if state in [State.COMBAT, State.STAGGER, State.RETREAT] or (hp < hp_max and alive() and state != State.YIELD):
		t = ("%s  " % t if t != "" else "") + "生命 %d / %d" % [hp, hp_max]
	status_label.text = t
	status_label.modulate = Color("ff8a6a") if state in [State.ALERT, State.COMBAT] else Color("ffcf6a")


func _find_refs() -> void:
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as FpController
	if director == null or not is_instance_valid(director):
		director = get_tree().get_first_node_in_group("combat_director") as CombatDirector


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	_find_refs()
	if flash > 0.0:
		flash = maxf(flash - delta * 6.0, 0.0)
		coat_mat.emission_energy_multiplier = flash * 0.8
	if stop_left > 0.0:          # 命中停顿：只冻结自己
		stop_left -= delta
		return
	state_t += delta
	token_cd = maxf(token_cd - delta, 0.0)
	stamina = minf(stamina + float(data.stamina_regen) * delta * (0.4 if action in ["windup", "strike"] else 1.0), float(data.stamina))
	think_t -= delta
	if think_t <= 0.0 and player:
		think_t = THINK_STEP
		_perceive(THINK_STEP)
	var move := Vector3.ZERO
	match state:
		State.PATROL:
			move = _patrol(delta)
		State.SUSPICIOUS:
			move = _go_to(last_known, float(data.walk), 1.2)
			_face(last_known, delta)
		State.ALERT:
			if player:
				_face(player.global_position, delta)
			if state_t >= ALERT_TIME:
				_enter(State.COMBAT)
		State.COMBAT:
			move = _combat(delta)
		State.RETREAT:
			if player:
				_face(player.global_position, delta)
				var away := _flat(global_position - player.global_position).normalized()
				move = away * float(data.walk) if _flat(global_position - player.global_position).length() < 5.0 else Vector3.ZERO
			if state_t >= 2.0:
				_enter(State.COMBAT)
		State.STAGGER:
			if state_t >= STAGGER_TIME:
				_enter(State.COMBAT)
		State.FLEE:
			if player:
				var away := _flat(global_position - player.global_position).normalized()
				move = away * float(data.run)
				_face(global_position + away, delta)
			if state_t >= 4.0:
				_enter(State.YIELD)
		State.YIELD:
			if player:
				_face(player.global_position, delta)
	_animate(delta)
	velocity.x = move.x
	velocity.z = move.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - gravity * delta
	move_and_slide()


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _face(p: Vector3, delta: float) -> void:
	var d := _flat(p - global_position)
	if d.length() < 0.01:
		return
	var target := atan2(-d.x, -d.z)
	rotation.y += clampf(angle_difference(rotation.y, target), -TURN_SPEED * delta, TURN_SPEED * delta)


func _go_to(p: Vector3, speed: float, stop := 0.3) -> Vector3:
	var d := _flat(p - global_position)
	if d.length() <= stop:
		return Vector3.ZERO
	return d.normalized() * speed


func _patrol(delta: float) -> Vector3:
	var p: Vector3 = waypoints[wp_index % waypoints.size()]
	if _flat(p - global_position).length() <= 0.4:
		wp_wait += delta
		if wp_wait >= 1.5:
			wp_wait = 0.0
			wp_index += 1
		return Vector3.ZERO
	_face(p, delta)
	return _go_to(p, float(data.walk) * 0.7)


# ---- 感知 ----

func forward() -> Vector3:
	return -global_transform.basis.z


func sight_range() -> float:
	var r := SIGHT_LIT if player_lit() else SIGHT_DARK
	return r * (CROUCH_SIGHT if player.crouching else 1.0)


## 玩家是不是站在灯火旁（街灯、火把：组 light_source，元数据 radius）
func player_lit() -> bool:
	for l in get_tree().get_nodes_in_group("light_source"):
		var r := float(l.get_meta("radius", 6.0))
		if _flat(l.global_position - player.global_position).length() <= r:
			return true
	return false


func can_see_player() -> bool:
	var to := player.global_position - global_position
	var d := _flat(to).length()
	if d > sight_range():
		return false
	# 战斗中不用视野锥（已经知道你在哪），只要视线不被挡
	if state not in [State.COMBAT, State.ALERT, State.RETREAT] and d > 1.0:
		if rad_to_deg(forward().angle_to(_flat(to).normalized())) > FOV_HALF:
			return false
	var from := global_position + Vector3(0, EYE, 0)
	var ray := PhysicsRayQueryParameters3D.create(from, player.aim_origin(), 1, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()


## 玩家的动静能传多远
func player_noise() -> float:
	if player.melee and player.melee.busy() and player.melee.state != Melee.State.BLOCK:
		return NOISE.fight
	if Vector2(player.velocity.x, player.velocity.z).length() < 0.5:
		return 0.0
	if player.crouching:
		return NOISE.crouch
	return (NOISE.run if player.running else NOISE.walk) + GameState.armor_noise()     # 穿锁甲走路更吵（2.6）


func _perceive(dt: float) -> void:
	if state in [State.DEAD, State.YIELD, State.FLEE]:
		return
	sees_player = can_see_player()
	var d := _flat(player.global_position - global_position).length()
	var heard := d <= player_noise()
	if sees_player or heard:
		last_known = player.global_position
		since_seen = 0.0
	else:
		since_seen += dt
	match state:
		State.PATROL, State.SUSPICIOUS:
			if sees_player:
				var rate := 0.8 * clampf(1.3 - d / sight_range(), 0.25, 1.3)
				if GameState.has_perk("stealth", "stealth_slow"):
					rate *= 0.7               # 潜行 25「轻步」（2.7）
				if state == State.SUSPICIOUS:
					rate *= 3.0          # 起疑后再看到你就很快发现（GDD 6.2）
				suspicion += rate * dt
			elif heard:
				suspicion = maxf(suspicion, SUSPECT_AT)
			else:
				suspicion -= 0.25 * dt
			suspicion = clampf(suspicion, 0.0, 1.0)
			if suspicion >= 1.0:
				alert()
			elif state == State.PATROL and suspicion >= SUSPECT_AT:
				_enter(State.SUSPICIOUS)
			elif state == State.SUSPICIOUS and suspicion <= 0.0:
				_enter(State.PATROL)
		State.COMBAT:
			if since_seen >= LOSE_TIME:
				suspicion = 0.9
				_enter(State.SUSPICIOUS)


## 发现玩家：喊一声，叫上附近还没发现的同伙
func alert(call_others := true) -> void:
	if state in [State.DEAD, State.YIELD, State.FLEE, State.COMBAT, State.ALERT, State.STAGGER, State.RETREAT]:
		return
	suspicion = 1.0
	if player:
		last_known = player.global_position
	_enter(State.ALERT)
	FloatText.spawn(self, "在那儿！", Vector3(0, 1.9, 0), Color("ffcf6a"), 28)
	if call_others:
		for e in get_tree().get_nodes_in_group("enemy"):
			if e != self and e.alive() and e.global_position.distance_to(global_position) <= CALL_RADIUS:
				e.alert(false)


# ---- 战斗 ----

## 直接进入战斗（3.3 打架：一开打就知道你在哪，不用先起疑、喊话）
func engage() -> void:
	if not alive() or state == State.YIELD:
		return
	suspicion = 1.0
	_find_refs()
	if player:
		last_known = player.global_position
	_enter(State.COMBAT)


func _release_token() -> void:
	if has_token and director:
		director.release(self)
	has_token = false


func _combat(delta: float) -> Vector3:
	if player == null:
		return Vector3.ZERO
	var to := _flat(player.global_position - global_position)
	var d := to.length()
	_face(player.global_position, delta)
	var reach := float(data.reach)
	action_t += delta
	match action:
		"windup":
			var wt := float(data.heavy_windup if attack_kind == "heavy" else data.windup)
			if action_t >= wt:
				action = "strike"
				action_t = 0.0
				hit_done = false
			return Vector3.ZERO
		"strike":
			if not hit_done and action_t >= float(data.strike) * 0.5:
				hit_done = true
				_strike_player()
			if action_t >= float(data.strike):
				action = "recover"
				action_t = 0.0
			return Vector3.ZERO
		"recover", "block":
			if action_t >= (float(data.recover) if action == "recover" else 0.35):
				if action == "recover":
					_release_token()
					token_cd = rng.randf_range(0.6, 1.4)
				action = ""
			return Vector3.ZERO
	# 体力见底的棍手先退开喘口气（GDD 6.2）
	if float(data.retreat_below) > 0.0 and stamina < float(data.retreat_below):
		_enter(State.RETREAT)
		return Vector3.ZERO
	if not has_token and token_cd <= 0.0 and director:
		has_token = director.request(self)
	if has_token:
		if d <= reach * 0.9:
			_start_attack()
			return Vector3.ZERO
		return to.normalized() * float(data.run)
	# 没拿到令牌：在 CIRCLE_DIST 外绕圈（剑手绕得更多，往你侧面去）
	action = "circle"
	var radial := to.normalized() * clampf(d - CIRCLE_DIST, -1.0, 1.0) * float(data.walk)
	var side := Vector3(-to.z, 0, to.x).normalized() * circle_dir * float(data.walk) * float(data.circle_side)
	return radial + side


func _start_attack() -> void:
	attack_kind = "heavy" if rng.randf() < float(data.heavy_chance) else "light"
	stamina = maxf(stamina - float(data.attack_cost), 0.0)
	action = "windup"
	action_t = 0.0


## 命中帧：玩家在剑程内、在正面 60° 内、中间没有墙，才算打到
func _strike_player() -> void:
	var to := player.global_position - global_position
	var d := _flat(to).length()
	if d > float(data.reach) + 0.35:
		return
	if rad_to_deg(forward().angle_to(_flat(to).normalized())) > 60.0:
		return
	var ray := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 1.3, 0), player.aim_origin(), 1, [get_rid()])
	if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
		return
	var dmg := DamageCalc.compute(float(data.weapon_base), int(data.strength), int(data.skill), attack_kind, player.melee.staggered(), GameState.armor_total())
	var result := player.melee.receive_hit({"damage": dmg, "kind": attack_kind, "attacker": self, "stop": 0.06,
		"nonlethal": bool(data.get("nonlethal", false))})
	if result == "perfect":
		stagger()
	elif result == "block":
		action = "recover"
		action_t = float(data.recover) * 0.3        # 被挡住弹开，收招稍快


func stagger() -> void:
	if alive() and state != State.YIELD:
		_enter(State.STAGGER)
		FloatText.spawn(self, "失衡", Vector3(0, 1.7, 0), Color("ffcf6a"), 28)


## Melee 命中时调用（与木桩同一个接口）
func take_hit(info: Dictionary) -> void:
	if not alive():
		return
	stop_left = float(info.get("stop", 0.0))
	var k := str(info.get("kind", "light"))
	# 剑手：正面、没在出招、没失衡时可能挡住轻击；重击破防
	var facing := forward().dot(_flat(player.global_position - global_position).normalized()) > 0.4 if player else false
	var can_block := state == State.COMBAT and action not in ["windup", "strike"] and facing
	if can_block and rng.randf() < float(data.block_chance):
		if k == "light":
			action = "block"
			action_t = 0.0
			FloatText.spawn(self, "格挡", Vector3(0, 1.6, 0), Color("c8d8e8"), 28)
			if player:
				player.melee.on_blocked()
			return
		stagger()              # 想挡重击：被破防
	var dmg := int(info.get("damage", 0))
	hp = maxi(hp - dmg, 1 if bool(data.get("nonlethal", false)) else 0)     # 打不死的（醉汉）最少留 1，到 flee_below 认输
	flash = 1.0
	FloatText.spawn(self, ("重击 −%d" if k == "heavy" else "−%d") % dmg, Vector3(randf_range(-0.2, 0.2), 1.45, 0),
		Color("ffcf6a") if k == "heavy" else Color("f2e6c8"), 36 if k == "heavy" else 30)
	if hp <= 0:
		_die()
		return
	if state in [State.PATROL, State.SUSPICIOUS]:
		alert()
	if state == State.ALERT:
		_enter(State.COMBAT)
	if state != State.YIELD and state != State.FLEE and hp <= int(ceil(hp_max * float(data.flee_below))):
		_enter(State.YIELD if rng.randf() < float(data.yield_chance) else State.FLEE)
		FloatText.spawn(self, "别打了，我认输！" if state == State.YIELD else "快跑！", Vector3(0, 1.9, 0), Color("ffcf6a"), 26)
	_update_status()


## restoring = 读档恢复：不再改声望、不发信号、直接倒在地上
func _die(restoring := false) -> void:
	_enter(State.DEAD)
	collision_layer = 0
	collision_mask = 1
	name_label.text = display_name + "（倒下）"
	if restoring:
		body.rotation.x = deg_to_rad(-88.0)
		body.position.y = 0.3
	else:
		var tw := create_tween()
		tw.tween_property(body, "rotation:x", deg_to_rad(-88.0), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(body, "position:y", 0.3, 0.45)
		GameState.dead[enemy_id] = [global_position.x, global_position.y, global_position.z]
	# 倒下的地方留一个可搜刮的「尸体」（2.6）：带着他的兵器和随身的东西
	var loot := LootContainer.make("loot:" + enemy_id, display_name, Array(data.get("loot", [])), int(data.get("silver", 0)), true)
	loot.position = global_position
	get_parent().add_child(loot)
	if restoring:
		return
	GameState.change_rep(str(data.get("faction", "")), -5)     # 杀了他们的人，这个势力更恨你（2.7）
	died.emit(self)


## 手臂动作：持械、起手举高（重击举得更高更久）、劈下、格挡横架；求饶时跪下
func _animate(delta: float) -> void:
	var target := Vector3(-40, 0, 0)
	match action:
		"windup":
			var wt := float(data.heavy_windup if attack_kind == "heavy" else data.windup)
			var k := clampf(action_t / wt, 0.0, 1.0)
			target = Vector3(-40, 0, 0).lerp(Vector3(55 if attack_kind == "heavy" else 35, 0, 0), k)
			arm.rotation_degrees = target
			return
		"strike":
			target = Vector3(-115, 0, 0)
			arm.rotation_degrees = arm.rotation_degrees.lerp(target, clampf(delta * 30.0, 0.0, 1.0))
			return
		"block":
			target = Vector3(-30, 0, 75)
	if state == State.YIELD:
		target = Vector3(-10, 0, 0)
		body.position.y = move_toward(body.position.y, -0.45, delta * 1.5)
	arm.rotation_degrees = arm.rotation_degrees.lerp(target, clampf(delta * 10.0, 0.0, 1.0))
