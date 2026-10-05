class_name Enemy
extends CharacterBody3D
## 敌人（路线图 2.5；GDD.md 6.1、6.2；TECH.md 4.3、4.4）。数值在 data/enemies.json（棍手、剑手）。
## 状态：巡逻 → 起疑（头顶「？ 起疑」）→ 警觉（「！ 警觉」，喊附近同伙）→ 战斗 → 受重伤时逃跑或求饶；另有失衡、后退、倒下。
## 感知：前方 110° 视野锥 + 视线射线，距离看光照（玩家站在灯火旁 20 米，暗处 8 米，蹲着再打六折）；听觉看玩家动静（跑 10 米、走 4 米、蹲 1.5 米、挥剑 8 米）。
## 战斗：向 CombatDirector 要攻击令牌，拿到才上前出招（起手 → 命中帧 → 收招），没拿到就在 3.5 米外绕圈。
## 剑手会格挡轻击；重击破防让它失衡。完美格挡它的攻击也会让它失衡 0.8 秒，失衡期间受到的伤害加倍（DamageCalc）。
## 寻路（3.4）：区域烘焙了导航网格（main 按 Areas.nav_bounds 烘焙）就用 NavigationAgent3D 沿路径走——追你时绕开房子和桌子、
## 起疑时去你最后出现的地方找、巡逻点之间沿路走、逃跑时往远处能走到的地方跑；没有导航网格的区域（或刚载入、导航还没同步）照旧直线走加碰撞滑动。
## 离你很近、看得见你的时候直接朝你走（贴身时不绕路）。
## 外观是占位胶囊人（正式人物在阶段 A）。
## 3.5：求饶（或逃跑后认输）的敌人跪在原地，能搜身（和倒下的一样留一个搜刮点，东西是同一份）；跪下的位置记进存档（GameState.yielded），读档后还跪着。
## 打架时（nonlethal）的认输不算：那是 Brawl 管的，打完就变回 NPC。
## 3.6：头目（outlaw_boss，「灰手」奥弗）会踢——kick_chance 的概率出一记踢，起手时头上冒「踢！」，踢中时格挡挡不住（破防，Melee.receive_hit）；
## flank_call 的种类第一次掉到半血时喊「包抄他！」，附近的同伙立刻冲上来、往你两侧绕。逃跑一开始就记进 GameState.yielded（读档后按认输算，不会再站起来）。
## 3.3：nonlethal 的种类（酒馆醉汉）用拳头、打不死：生命最少留 1，到 flee_below 就认输；它打玩家也不致命（Melee.KO_FLOOR）。
## 打架时由 Brawl 现场生成（engage() 直接进入战斗；display_override 用 NPC 的名字）。
## B.1（军阵战斗）：「对手」抽成 foe()——基类永远是玩家（序章的行为不变），Soldier 改成军阵里挑中的敌方（可能是另一个兵）。
## 出招命中走 _strike_target()：对手是玩家调 Melee.receive_hit()，是兵就调它的 take_hit()；take_hit() 按攻击者的位置判断正面能不能挡；
## 只有玩家打倒的才扣声望；transient（军阵的普通兵）倒下、求饶不写进存档，drops_loot = false 的不留搜刮点。
## B.4 兵种：兵器多了 spear（长枪：够得远，出招是往前刺）与 bow（弓：远射，行为在 Soldier）；数据可选 "shield": true（左手一面盾：
## 正面的轻击多半挡住、正面射来的箭全挡，重击照旧破防）。箭（combat/arrow.gd）打中时 kind = "arrow"：有盾、正对着就挡，不然不能挡。

signal state_changed(enemy: Enemy, state: String)
signal died(enemy: Enemy)

enum State { PATROL, SUSPICIOUS, ALERT, COMBAT, RETREAT, STAGGER, FLEE, YIELD, DEAD }
const STATE_NAMES := ["patrol", "suspicious", "alert", "combat", "retreat", "stagger", "flee", "yield", "dead"]
const STATE_LABELS := ["", "？ 起疑", "！ 警觉", "！", "后退", "失衡", "逃跑", "求饶", ""]

const DATA_PATH := "res://data/enemies.json"
const DATA_KEYS := ["name", "coat", "weapon", "hp", "armor", "weapon_base", "strength", "skill", "walk", "run", "reach",
	"windup", "heavy_windup", "strike", "recover", "heavy_chance", "block_chance", "stamina", "attack_cost", "stamina_regen",
	"retreat_below", "circle_side", "flee_below", "yield_chance", "loot", "silver", "faction", "nonlethal", "kick_chance", "flank_call"]
const OPTIONAL_KEYS := ["shield"]  # 可以不写的字段（B.4）
const WEAPONS := ["sword", "club", "fists", "spear", "bow"]
const ARM_POS := Vector3(0.34, 1.3, -0.05)
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
const REPATH_MOVE := 0.5          # 目标挪动超过这么多米才重新寻路
const REPATH_AGE := 0.5           # 或者路径用了这么久（秒）
const DIRECT_NEAR := 2.5          # 看得见你、又在这个距离以内：直接朝你走

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
var shield: MeshInstance3D        # 左手的盾（B.4，数据 "shield": true）
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var agent: NavigationAgent3D
var nav_target := Vector3.INF
var nav_age := 0.0
var move_dir := Vector3.ZERO      # 这一帧沿路径要走的方向（水平；没在走时是零）
var loot_node: LootContainer      # 倒下或求饶后留下的搜刮点（只放一个）
var flank_called := false         # 半血时已经喊过「包抄他！」（3.6）
var sees_foe := false             # 看得见对手（B.1；基类 = sees_player，士兵在军阵里总当作看得见）
var transient := false            # 军阵战斗的普通兵（B.1）：倒下、求饶、逃跑不写进存档
var drops_loot := true            # 倒下或求饶后留不留搜刮点（军阵的普通兵不留，GDD 6.4）
var last_attacker: Node3D         # 最后一次打中自己的（null = 玩家）：只有玩家打倒才扣声望（B.1）
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
			if not key in DATA_KEYS and not key in OPTIONAL_KEYS:
				errs.append("%s 有不认识的字段 %s" % [k, key])
		if not GameState.progression().get("factions", {}).has(str(t.get("faction", ""))):
			errs.append("%s 的势力 %s 不在 progression.json 里" % [k, t.get("faction", "")])
		for it in t.get("loot", []):
			if GameState.item(str(it)).is_empty():
				errs.append("%s 的掉落 %s 不在 items.json 里" % [k, it])
		if float(t.get("hp", 0)) <= 0 or float(t.get("reach", 0)) <= 0:
			errs.append("%s 的生命或攻击距离不对" % k)
		for key in ["heavy_chance", "block_chance", "flee_below", "yield_chance", "kick_chance"]:
			if float(t.get(key, 0)) < 0.0 or float(t.get(key, 0)) > 1.0:
				errs.append("%s 的 %s 应在 0..1" % [k, key])
		if not str(t.get("weapon", "")) in WEAPONS:
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
	agent = NavigationAgent3D.new()
	agent.name = "Agent"
	agent.radius = 0.35
	agent.height = 1.75
	agent.path_desired_distance = 0.6
	agent.target_desired_distance = 0.5
	agent.avoidance_enabled = false
	add_child(agent)
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
	elif GameState.yielded.has(enemy_id):         # 读档：求饶的，还跪在那里（3.5）
		var p: Array = GameState.yielded[enemy_id]
		global_position = Vector3(p[0], p[1], p[2])
		_kneel.call_deferred(true)


func _build_arm() -> void:
	arm = Node3D.new()
	arm.name = "Arm"
	arm.position = ARM_POS
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
	elif data.weapon == "spear":                                          # 长枪（B.4）：2.4 米的杆子 + 枪头
		kit.cylinder("wood", Vector3(0, -0.7, 0), Vector3(0, 1.6, 0), 0.025, 0.025, 6)
		kit.box("steel", Vector3(0, 1.72, 0), Vector3(0.05, 0.24, 0.02))
		var tip := StandardMaterial3D.new()
		tip.albedo_color = Color("aab2bc")
		tip.vertex_color_use_as_albedo = true
		mats = {"wood": Look.mat("timber"), "steel": tip}
	elif data.weapon == "bow":                                            # 弓（B.4）：竖着的弓身 + 一根弦
		kit.box("wood", Vector3(0, 0.0, 0.06), Vector3(0.03, 1.1, 0.03))
		kit.box("string", Vector3(0, 0.0, -0.03), Vector3(0.008, 1.05, 0.008))
		var cord := StandardMaterial3D.new()
		cord.albedo_color = Color("d8d0bc")
		cord.vertex_color_use_as_albedo = true
		mats = {"wood": Look.mat("timber"), "string": cord}
	else:
		kit.cylinder("wood", Vector3(0, -0.05, 0), Vector3(0, 0.75, 0), 0.03, 0.055, 6)
		mats = {"wood": Look.mat("timber")}
	var mi := kit.build(mats)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	arm.add_child(mi)
	arm.rotation_degrees = _rest_pose()
	if bool(data.get("shield", false)):
		_build_shield()


## 手臂平时的姿势：剑和棍斜举（-40°），长枪端平往前（-80°），弓竖着（-10°）
func _rest_pose() -> Vector3:
	match str(data.weapon):
		"spear":
			return Vector3(-80, 0, 0)
		"bow":
			return Vector3(-10, 0, 0)
	return Vector3(-40, 0, 0)


## 左手的盾（B.4）：一块木盾挡在身前左侧；Soldier 会把它涂成阵营布带的颜色
func _build_shield() -> void:
	shield = MeshInstance3D.new()
	shield.name = "Shield"
	var bm := BoxMesh.new()
	bm.size = Vector3(0.5, 0.62, 0.05)
	bm.material = Look.mat("timber")
	shield.mesh = bm
	shield.position = Vector3(-0.3, 1.0, -0.3)
	shield.rotation_degrees = Vector3(0, 20, 0)
	body.add_child(shield)


func state_name() -> String:
	return STATE_NAMES[state]


func alive() -> bool:
	return state != State.DEAD


## 现在的对手（B.1）：基类敌人永远是玩家；Soldier 覆盖成军阵里挑中的目标（可能是另一个兵，也可能是空）
func foe() -> Node3D:
	return player


## 声望按哪个势力算（玩家打倒时扣）；Soldier 按军阵的设定覆盖
func rep_faction() -> String:
	return str(data.get("faction", ""))


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
	if s == State.YIELD:
		_kneel(false)
	elif s == State.FLEE and not bool(data.get("nonlethal", false)) and not transient:
		GameState.yielded[enemy_id] = [global_position.x, global_position.y, global_position.z]     # 逃了：读档后按认输算（3.6）
	state_changed.emit(self, state_name())


## 求饶：跪下，留一个能搜身的搜刮点，位置记进存档（打架的醉汉不算，3.3）
func _kneel(restoring: bool) -> void:
	if bool(data.get("nonlethal", false)):
		return
	if restoring:
		state = State.YIELD
		body.position.y = -0.45
		_update_status()
	elif not transient:
		GameState.yielded[enemy_id] = [global_position.x, global_position.y, global_position.z]
	name_label.text = display_name + "（求饶）"
	_drop_loot()


## 倒下或求饶的地方留一个搜刮点（2.6）：带着他的兵器和随身的东西；同一个人只留一个
func _drop_loot() -> void:
	if not drops_loot or (loot_node != null and is_instance_valid(loot_node)):
		return
	loot_node = LootContainer.make("loot:" + enemy_id, display_name, Array(data.get("loot", [])), int(data.get("silver", 0)), true)
	loot_node.position = global_position
	get_parent().add_child(loot_node)


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
	nav_age += delta
	move_dir = Vector3.ZERO
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
			move = _steer(last_known, float(data.walk), 1.2)          # 去你最后出现的地方找
			_face(global_position + move_dir if move_dir != Vector3.ZERO else last_known, delta)
		State.ALERT:
			if player:
				_face(player.global_position, delta)
			if state_t >= ALERT_TIME:
				_enter(State.COMBAT)
		State.COMBAT:
			move = _combat(delta)
		State.RETREAT:
			var f := foe()
			if f:
				_face(f.global_position, delta)
				var away := _flat(global_position - f.global_position).normalized()
				move = away * float(data.walk) if _flat(global_position - f.global_position).length() < 5.0 else Vector3.ZERO
			if state_t >= 2.0:
				_enter(State.COMBAT)
		State.STAGGER:
			if state_t >= STAGGER_TIME:
				_enter(State.COMBAT)
		State.FLEE:
			var f := foe()
			if f:
				var away := _flat(global_position - f.global_position).normalized()
				move = _steer(global_position + away * 8.0, float(data.run), 0.5)     # 往远处能走到的地方跑，不撞墙
				_face(global_position + (move_dir if move_dir != Vector3.ZERO else away), delta)
			if state_t >= 4.0:
				_enter(State.YIELD)
		State.YIELD:
			var f := foe()
			if f:
				_face(f.global_position, delta)
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


## 这个区域有没有能用的导航网格（导航服务器同步过、地图上有区域）
func nav_ready() -> bool:
	if agent == null or not agent.is_inside_tree():
		return false
	var map := agent.get_navigation_map()
	return map.is_valid() and NavigationServer3D.map_get_iteration_id(map) > 0 and not NavigationServer3D.map_get_regions(map).is_empty()


## 朝 p 走：有导航网格就沿路径走（目标挪远了或路径旧了才重新寻路），没有就直线走；到 stop 以内停下。返回水平速度，方向记在 move_dir
func _steer(p: Vector3, speed: float, stop := 0.3) -> Vector3:
	var d := _flat(p - global_position)
	if d.length() <= stop:
		return Vector3.ZERO
	var dir := d.normalized()
	if nav_ready():
		if nav_target == Vector3.INF or _flat(nav_target - p).length() > REPATH_MOVE or nav_age >= REPATH_AGE:
			agent.target_position = p
			nav_target = p
			nav_age = 0.0
		var step := _flat(agent.get_next_path_position() - global_position)
		if step.length() > 0.05:
			dir = step.normalized()
	move_dir = dir
	return dir * speed


func _patrol(delta: float) -> Vector3:
	var p: Vector3 = waypoints[wp_index % waypoints.size()]
	# 到了：离巡逻点 0.4 米以内；巡逻点贴着墙、导航网格够不到时，走到路径的终点也算到了
	var at_end := nav_ready() and nav_target == p and _flat(agent.get_final_position() - global_position).length() <= 0.45
	if _flat(p - global_position).length() <= 0.4 or at_end:
		wp_wait += delta
		if wp_wait >= 1.5:
			wp_wait = 0.0
			wp_index += 1
		return Vector3.ZERO
	var v := _steer(p, float(data.walk) * 0.7, 0.3)                   # 巡逻点之间沿路走（3.4）
	_face(global_position + move_dir if move_dir != Vector3.ZERO else p, delta)
	return v


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
	sees_foe = sees_player
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
	var f := foe()
	if f == null:
		return Vector3.ZERO
	var to := _flat(f.global_position - global_position)
	var d := to.length()
	var reach := float(data.reach)
	# 看得见你或离得近：正对着你；隔着房子绕路时：脸朝走的方向（3.4）
	var direct := sees_foe and d <= DIRECT_NEAR
	if action in ["windup", "strike", "recover", "block"] or sees_foe or d <= CIRCLE_DIST:
		_face(f.global_position, delta)
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
				_strike_target()
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
		has_token = director.request(self, f)
	if has_token:
		if d <= reach * 0.9:
			_start_attack()
			return Vector3.ZERO
		var v := to.normalized() * float(data.run) if direct else _steer(f.global_position, float(data.run), reach * 0.85)
		if not sees_foe and move_dir != Vector3.ZERO and d > CIRCLE_DIST:
			_face(global_position + move_dir, delta)
		return v
	# 看不见你（隔着房子）：先沿路走过来，到绕圈的距离再说
	if not sees_foe and d > CIRCLE_DIST + 0.5:
		action = "approach"
		var v := _steer(f.global_position, float(data.walk) * 1.4, CIRCLE_DIST)
		if move_dir != Vector3.ZERO:
			_face(global_position + move_dir, delta)
		return v
	# 没拿到令牌：在 CIRCLE_DIST 外绕圈（剑手绕得更多，往你侧面去）
	action = "circle"
	var radial := to.normalized() * clampf(d - CIRCLE_DIST, -1.0, 1.0) * float(data.walk)
	var side := Vector3(-to.z, 0, to.x).normalized() * circle_dir * float(data.walk) * float(data.circle_side)
	return radial + side


func _start_attack() -> void:
	attack_kind = "heavy" if rng.randf() < float(data.heavy_chance) else "light"
	if rng.randf() < float(data.get("kick_chance", 0.0)):
		attack_kind = "kick"                     # 踢（3.6）：格挡挡不住，看到「踢！」就往后退
		FloatText.spawn(self, "踢！", Vector3(0, 1.9, 0), Color("ff8a6a"), 30)
	stamina = maxf(stamina - float(data.attack_cost), 0.0)
	action = "windup"
	action_t = 0.0


## 命中帧：对手在剑程内、在正面 60° 内、中间没有墙，才算打到。对手是玩家走 Melee.receive_hit()，是兵（B.1）走它的 take_hit()
func _strike_target() -> void:
	var f := foe()
	if f == null:
		return
	var to := f.global_position - global_position
	var d := _flat(to).length()
	if d > float(data.reach) + 0.35:
		return
	if rad_to_deg(forward().angle_to(_flat(to).normalized())) > 60.0:
		return
	var at_player := f == player
	var aim := player.aim_origin() if at_player else f.global_position + Vector3(0, 1.3, 0)
	var skip := [get_rid()] if at_player else [get_rid(), (f as CollisionObject3D).get_rid()]
	var ray := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 1.3, 0), aim, 1, skip)
	if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
		return
	var base := float(data.weapon_base) * (0.6 if attack_kind == "kick" else 1.0)
	if not at_player:
		var e := f as Enemy
		var hit := DamageCalc.compute(base, int(data.strength), int(data.skill), attack_kind, e.staggered, e.armor)
		if e.take_hit({"damage": hit, "kind": attack_kind, "attacker": self, "stop": 0.06}) == "block":
			action = "recover"
			action_t = float(data.recover) * 0.3        # 被挡住弹开，收招稍快
		return
	var dmg := DamageCalc.compute(base, int(data.strength), int(data.skill), attack_kind, player.melee.staggered(), GameState.armor_total())
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
		if _near_player(12.0):
			FloatText.spawn(self, "失衡", Vector3(0, 1.7, 0), Color("ffcf6a"), 28)


## Melee 命中时调用（与木桩同一个接口）；军阵里别的兵打中自己也走这里（info.attacker = 那个兵，B.1）。
## 返回 "block" / "hit" / "dead" / "none"（兵打兵时出招的一方据此收招）
func take_hit(info: Dictionary) -> String:
	if not alive():
		return "none"
	stop_left = float(info.get("stop", 0.0))
	var k := str(info.get("kind", "light"))
	var by: Variant = info.get("attacker")
	var attacker: Node3D = by if by is Node3D and is_instance_valid(by) else player      # 没写攻击者 = 玩家（Melee 不写）
	var from_player := attacker == player
	last_attacker = null if from_player else attacker
	var fx := from_player or _near_player(12.0)      # 军阵里远处兵打兵不冒字（Label3D 多了费绘制调用）
	# 剑手：正面、没在出招、没失衡时可能挡住轻击；重击破防
	var facing := forward().dot(_flat(attacker.global_position - global_position).normalized()) > 0.4 if attacker else false
	var can_block := state == State.COMBAT and action not in ["windup", "strike"] and facing
	if k == "arrow":                     # 箭（B.4）：有盾、正对着就挡住；没盾挡不了
		if shield != null and facing and alive() and state != State.YIELD:
			if fx:
				FloatText.spawn(self, "挡箭", Vector3(0, 1.6, 0), Color("c8d8e8"), 26)
			return "block"
		can_block = false
	if can_block and rng.randf() < float(data.block_chance):
		if k == "light":
			action = "block"
			action_t = 0.0
			if fx:
				FloatText.spawn(self, "格挡", Vector3(0, 1.6, 0), Color("c8d8e8"), 28)
			if from_player and player:
				player.melee.on_blocked()
			return "block"
		stagger()              # 想挡重击：被破防
	var dmg := int(info.get("damage", 0))
	hp = maxi(hp - dmg, 1 if bool(data.get("nonlethal", false)) else 0)     # 打不死的（醉汉）最少留 1，到 flee_below 认输
	flash = 1.0
	if fx:
		FloatText.spawn(self, ("重击 −%d" if k == "heavy" else "−%d") % dmg, Vector3(randf_range(-0.2, 0.2), 1.45, 0),
			Color("ffcf6a") if k == "heavy" else Color("f2e6c8"), 36 if k == "heavy" else 30)
	if hp <= 0:
		_die()
		return "dead"
	if state in [State.PATROL, State.SUSPICIOUS]:
		alert()
	if state == State.ALERT:
		_enter(State.COMBAT)
	if bool(data.get("flank_call", false)) and not flank_called and hp <= int(hp_max * 0.5) and state not in [State.YIELD, State.FLEE]:
		_call_flank()
	if state != State.YIELD and state != State.FLEE and hp <= int(ceil(hp_max * float(data.flee_below))):
		_enter(State.YIELD if rng.randf() < float(data.yield_chance) else State.FLEE)
		if fx:
			FloatText.spawn(self, "别打了，我认输！" if state == State.YIELD else "快跑！", Vector3(0, 1.9, 0), Color("ffcf6a"), 26)
	_update_status()
	return "hit"


## 离玩家多近（水平距离）；没有玩家时当作很远
func _near_player(r: float) -> bool:
	return player != null and is_instance_valid(player) and _flat(player.global_position - global_position).length() <= r


## 半血喊包抄（3.6，GDD 6.2「灰手奥弗：半血时喊手下包抄」）：附近还能打的同伙立刻冲上来，一左一右往你两侧绕
func _call_flank() -> void:
	flank_called = true
	FloatText.spawn(self, "包抄他！", Vector3(0, 2.0, 0), Color("ff8a6a"), 30)
	var side := 1.0
	for e in get_tree().get_nodes_in_group("enemy"):
		if e == self or not e.alive() or e.state in [State.YIELD, State.FLEE] or e.global_position.distance_to(global_position) > 15.0:
			continue
		e.data = e.data.duplicate()
		e.data.circle_side = 1.6                 # 绕得更开：往你侧面去
		e.circle_dir = side
		e.token_cd = 0.0
		side = -side
		e.engage()


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
		if not transient:
			GameState.dead[enemy_id] = [global_position.x, global_position.y, global_position.z]
	if not transient:
		GameState.yielded.erase(enemy_id)            # 求饶以后又被杀了：按倒下算
	_drop_loot()
	if restoring:
		return
	if last_attacker == null:
		GameState.change_rep(rep_faction(), -5)     # 杀了他们的人，这个势力更恨你（2.7）；兵打倒兵不算（B.1）
	died.emit(self)


## 手臂动作：持械、起手举高（重击举得更高更久）、劈下、格挡横架；求饶时跪下
func _animate(delta: float) -> void:
	if data.weapon in ["spear", "bow"]:
		_animate_reach(delta)
		return
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


## 长枪：起手往回收、出招往前捅（手臂整个前后移，不是挥）；弓：拉弓时举平往前、放箭后回到竖着（B.4）
func _animate_reach(delta: float) -> void:
	var rot := _rest_pose()
	var z := ARM_POS.z
	var k := clampf(delta * 12.0, 0.0, 1.0)
	if data.weapon == "spear":
		match action:
			"windup":
				var wt := float(data.heavy_windup if attack_kind == "heavy" else data.windup)
				z = ARM_POS.z + 0.3 * clampf(action_t / wt, 0.0, 1.0)
				k = 1.0
			"strike":
				z = ARM_POS.z - 0.45
				rot = Vector3(-88, 0, 0)
				k = clampf(delta * 30.0, 0.0, 1.0)
			"block":
				rot = Vector3(-30, 0, 60)
	elif action in ["draw", "loose"]:
		rot = Vector3(-90, 0, 0)
		z = ARM_POS.z - (0.25 if action == "draw" else 0.35)
	if state == State.YIELD:
		rot = Vector3(-10, 0, 0)
		body.position.y = move_toward(body.position.y, -0.45, delta * 1.5)
	arm.rotation_degrees = arm.rotation_degrees.lerp(rot, k)
	arm.position.z = lerpf(arm.position.z, z, k)
