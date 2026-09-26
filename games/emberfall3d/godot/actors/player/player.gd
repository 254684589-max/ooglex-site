class_name Player
extends CharacterBody3D
## 玩家（TECH.md 第 4.1、4.2 节，GDD.md 第三、四、五节）
## 移动：
## - 电脑：左键点地面移动，按住持续移动（每 0.15 秒刷新目标）；可选 WASD。
## - 手机：虚拟摇杆（TouchControls）直接按方向移动；点摇杆区域以外的地面也能移动。
## - 点击移动走导航网格（NavigationAgent3D）；摇杆 / 键盘不走寻路，靠碰撞体贴墙滑动。
## 战斗（阶段 1.4 打击手感；P4 起为 V0.1 的「流浪者」，D10）：
## - 左键点敌人：走到攻击距离后挥砍（断誓斩）；按住持续攻击。手机用「攻击」按钮自动锁定最近的敌人。
## - 四个技能消耗法力、有冷却、按等级解锁（V0.1）：火球术（1 级，右键 / 1）、烬环斩（3 级，2）、
##   寂霜环（6 级，3）、暗影闪现（10 级，4）。电脑朝鼠标所指的地面释放；手机按钮自动瞄准最近的可见敌人。
## - 命中停顿只冻结命中双方（hitstop_t），不改全局时间。
## 占位外观：胶囊 + 方块武器（阶段 2 换成正式模型）。

signal arrived
signal hit_landed(skill_id: String, hits: int)
signal hurt(amount: int)
signal died
signal respawned
signal message(text: String, color: Color)     # 屏幕左侧的消息（拾取、背包已满等）
signal talk_requested(npc: Node3D)             # 走到 NPC（P7）或传送石 / 传送门 / 水井（P8，InteractSpot）身边

const LAYER_WORLD := Layers.WORLD
const LAYER_GROUND := Layers.GROUND
const LAYER_PLAYER := Layers.PLAYER
const HOLD_REFRESH := 0.15
const ARRIVE_DIST := 0.15
const AUTO_TARGET_RANGE := 7.0
const SKILL_KEYS := {KEY_1: "fireball", KEY_2: "whirl", KEY_3: "nova", KEY_4: "blink"}
const SKILL_AIM_RANGE := 12.0            # 自动瞄准的最远距离（V0.1 autoAim 8 格）

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
var skill_cd := {}                    # 技能冷却剩余秒数（P4）
var aim_point := Vector3.ZERO           # 本次施法瞄准的地面点
var last_skill_fail := ""               # 最近一次放不出技能的原因（界面提示用）
var progress := HeroProgress.new()     # P3：等级、属性点、装备与计算后的属性（V0.1 规则）
var stats: Dictionary = progress.combat_stats()
var mp := 0.0
var max_mp := 1.0
var last_gold_lost := 0
var pickup_target: GroundItem = null
var talk_target: Node3D = null     # 要走过去对话 / 使用的 NPC 或 InteractSpot
var in_town := false                   # 镇上不能施法（V0.1 castSkill）
var rng := RandomNumberGenerator.new()
var attack_target: Node3D
var attack_hold := false         # 按住鼠标 / 攻击按钮：打完一下继续打
var action := ""                 # 正在进行的动作：""、"oath_cleave"、"fireball"、"whirl"、"nova"、"blink"
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
	# P5：不再和敌人碰撞（怪物会被推开让路，见 EnemyBase._separation），否则点地移动会被挡路的怪顶住
	collision_mask = LAYER_WORLD
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
	_apply_progress()
	hp = max_hp
	mp = max_mp
	respawn_point = global_position
	_build_placeholder()
	_apply_progress()      # 身上的光建好后再算一次照明范围


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
	light.name = "HeroLight"
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
			cast_skill("fireball", pick_ground(event.position))
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
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode in SKILL_KEYS:
		cast_skill(SKILL_KEYS[event.physical_keycode], pick_ground(get_viewport().get_mouse_position()))


func _over_ui(p: Vector2) -> bool:
	for c in ui_blockers:
		if is_instance_valid(c) and c.is_visible_in_tree() and c.get_global_rect().has_point(p):
			return true
	return false


func click_at(screen_pos: Vector2) -> void:
	if dead:
		return
	pickup_target = null
	talk_target = null
	# 点选优先级同 V0.1 pickAt：地上物品的名字 > 怪物 > 人物与可以用的东西（传送石、木桶、宝箱……）
	var gi := pick_item(screen_pos)
	if gi != null:
		# 点地上的东西：走过去拾取（V0.1 pickUp）
		attack_target = null
		pickup_target = gi
		move_to(gi.global_position)
		return
	var enemy = pick_enemy(screen_pos)
	if enemy:
		attack_target = enemy
		moving_to = false
		return
	attack_target = null
	var npc := pick_npc(screen_pos)
	if npc != null:
		# 点 NPC：走过去对话（V0.1 talk）
		talk_target = npc
		move_to(npc.global_position)
		return
	var p = pick_ground(screen_pos)
	if p != null:
		move_to(p)
		_show_marker(last_target)


## 屏幕上离点击位置最近的 NPC 或可使用的东西（传送石、传送门、水井；身体或名字在 50 像素以内）
func pick_npc(screen_pos: Vector2) -> Node3D:
	if camera == null:
		return null
	var best: Node3D = null
	var bd := 50.0 * get_window().content_scale_factor
	for n in get_tree().get_nodes_in_group("npc") + get_tree().get_nodes_in_group("interact"):
		if camera.is_position_behind(n.global_position):
			continue
		for h in ([0.8, 1.5, 2.15] if n is Npc else n.pick_heights):
			var d := camera.unproject_position(n.global_position + Vector3(0, h, 0)).distance_to(screen_pos)
			if d < bd:
				bd = d
				best = n
	return best


## 屏幕上离点击位置最近的地上物品（名字标签或物品本身在 40 像素以内）
func pick_item(screen_pos: Vector2) -> GroundItem:
	if camera == null:
		return null
	var best: GroundItem = null
	var bd := 40.0 * get_window().content_scale_factor
	for g in get_tree().get_nodes_in_group("ground_item"):
		if not is_instance_valid(g) or not g.visible or camera.is_position_behind(g.global_position):
			continue
		for h in [0.3, 0.8]:
			var sp := camera.unproject_position(g.global_position + Vector3(0, h, 0))
			var d := sp.distance_to(screen_pos)
			if d < bd:
				bd = d
				best = g
	return best


## 拾取（V0.1 pickUp）：金币、药水直接收下；装备进背包（上限 40 件，满了留在地上）
func pick_up(g: GroundItem) -> bool:
	if not is_instance_valid(g):
		return false
	var sh: Dictionary = progress.sheet
	var msg := ""
	if g.data.has("gold"):
		sh.gold += int(g.data.gold)
		msg = "拾取 %d 金币" % int(g.data.gold)
	elif g.data.has("pot"):
		sh.pots[g.data.pot] = int(sh.pots.get(g.data.pot, 0)) + 1
		msg = "拾取 " + g.title()
	else:
		if sh.inv.size() >= int(Act1Data.rules().hero.inventory_cap):
			message.emit("背包已满", Color(0.88, 0.38, 0.29))
			return false
		sh.inv.append(g.data.item)
		msg = "拾取 " + g.title()
	message.emit(msg, g.color())
	print("EF_PICKUP ", g.title())
	g.queue_free()
	progress.changed.emit()
	return true


func pick_enemy(screen_pos: Vector2):
	if camera == null:
		return null
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 200.0, Layers.ENEMY)
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	# 战争迷雾里看不见的怪物（P10，visible = false）点不中
	if not r.is_empty() and r.collider.is_in_group("enemy") and r.collider.visible:
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

# ---------------- 成长（P3） ----------------

func _apply_progress() -> void:
	## 属性变了（升级、加点、换装备）：刷新战斗数值、生命法力上限与移动速度；当前生命法力不超过上限
	stats = progress.combat_stats()
	max_hp = progress.S.maxHp
	max_mp = progress.S.maxMp
	hp = minf(hp, max_hp)
	mp = minf(mp, max_mp)
	speed = progress.move_speed()
	# 照明范围（P10，V0.1 S.light：基础 6 格，「明亮的」词缀与守夜人之冠会加）：每多 1 格，身上的光多照 1.2 米
	var hl := get_node_or_null("HeroLight") as OmniLight3D
	if hl:
		hl.omni_range = 7.0 + (float(progress.S.light) - float(Act1Data.rules().hero.stats.base_light)) * 1.2


func on_enemy_killed(e: Node) -> void:
	var d: Dictionary = e.def
	var ups := progress.add_kill(int(d.get("xp", 0)), int(d.get("level", 1)))
	if ups > 0:
		_apply_progress()
		hp = max_hp
		mp = max_mp
		print("EF_LEVEL lvl=%d pts=%d" % [progress.sheet.lvl, progress.sheet.pts])
		_level_fx()


## 任务奖励的经验（P8）：升级时同击杀升级一样回满并放光环
func gain_xp(v: int) -> void:
	if progress.gain_xp(v) > 0:
		_apply_progress()
		hp = max_hp
		mp = max_mp
		_level_fx()


## 换装备后调用（P6）：重算属性并刷新战斗数值、生命法力上限、移动速度
func stats_changed() -> void:
	progress.recalc()
	_apply_progress()


func allocate(stat: String) -> bool:
	if not progress.allocate(stat):
		return false
	_apply_progress()
	return true


## 喝药（V0.1 drinkPotion）：满了不喝，没有了不喝；返回回复量（0 = 没喝）
func drink_potion(kind: String) -> int:
	if dead or progress.sheet.pots.get(kind, 0) <= 0:
		return 0
	if (kind == "hp" and hp >= max_hp) or (kind == "mp" and mp >= max_mp):
		return 0
	progress.sheet.pots[kind] -= 1
	var v := HeroStats.potion_amount(kind, progress.S)
	if kind == "hp":
		hp = minf(max_hp, hp + v)
	else:
		mp = minf(max_mp, mp + v)
	if HitFeedback.numbers_enabled:
		HitFeedback.spawn_number(self, {"amount": v, "crit": false, "type": "heal" if kind == "hp" else "mana"})
	progress.changed.emit()
	return v


func _level_fx() -> void:
	## 升级：脚下金色光环向外扩散（占位特效）
	var ring := MeshInstance3D.new()
	ring.mesh = LowPoly.torus(0.9, 1.0)
	var m := _mat(Color(1.0, 0.85, 0.35))
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = m
	get_parent().add_child(ring)
	ring.global_position = global_position + Vector3(0, 0.15, 0)
	var tw := ring.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(2.4, 1, 2.4), 0.6).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.7)
	tw.chain().tween_callback(ring.queue_free)


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
	# V0.1 die()：掉落 10% 金币
	last_gold_lost = HeroStats.death_gold_loss(progress.sheet.gold)
	progress.sheet.gold -= last_gold_lost
	progress.sheet.deaths += 1
	died.emit()
	print("EF_PLAYER_DEAD")
	var tw := create_tween()
	tw.tween_property(_visual, "rotation_degrees:x", -80.0, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func respawn() -> void:
	dead = false
	hp = max_hp
	mp = max_mp
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
		if e.get("dead") or not e.visible:
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


## 技能定义：法力、冷却、解锁等级来自 act1_rules.json（V0.1 SK），动作节奏与距离来自 balance.json
static func skill_rule(id: String) -> Dictionary:
	for s in Act1Data.rules().skills:
		if s.id == id:
			return s
	return {}


## 能不能放：返回空字符串表示可以，否则是原因（V0.1 的提示语）
func skill_block_reason(id: String) -> String:
	var r := skill_rule(id)
	if r.is_empty():
		return "没有这个技能"
	if dead:
		return "倒下了"
	if in_town:
		return "镇上不能施法"
	if progress.sheet.lvl < int(r.lvl):
		return "%s 需要 %d 级" % [r.name, int(r.lvl)]
	if skill_cd.get(id, 0.0) > 0.0:
		return "冷却中"
	if action != "":
		return "正在出手"
	if mp < float(r.mp):
		return "法力不足"
	return ""


## 放技能。target 为地面上的瞄准点；不给（手机按钮、键盘没有指向地面）就自动瞄准最近的可见敌人（V0.1 autoAim）
func cast_skill(id: String, target = null) -> bool:
	last_skill_fail = skill_block_reason(id)
	if last_skill_fail != "":
		return false
	var p: Vector3 = target if target is Vector3 else _auto_aim(id)
	if id == "blink":
		var dest = _blink_destination(p)
		if dest == null:
			last_skill_fail = "无法闪现到那里"
			return false
		p = dest
	var r := skill_rule(id)
	mp -= float(r.mp)
	skill_cd[id] = float(r.cd)
	moving_to = false
	attack_target = null
	aim_point = p
	face_point(p)
	_start_action(id)
	return true


func _auto_aim(id: String) -> Vector3:
	var e := nearest_enemy(SKILL_AIM_RANGE if id != "blink" else 7.5)
	if e != null:
		return e.global_position
	return global_position + facing() * (6.0 if id != "blink" else Balance.skill("blink").range)


## 闪现落点：最远 10.5 米、需要视线、落在导航网格上；落不下就沿原路往回退（V0.1：退 10 次）
func _blink_destination(p: Vector3):
	var d := p - global_position
	d.y = 0.0
	var rng_m: float = Balance.skill("blink").range
	if d.length() > rng_m:
		d = d.normalized() * rng_m
	if d.length() < 0.5:
		return null
	var space := get_world_3d().direct_space_state
	var map := get_world_3d().navigation_map
	var from := global_position + Vector3(0, 1.0, 0)
	for k in 10:
		# 退到原地附近（不足 0.5 米）就算失败，不白扣法力（V0.1 会原地「闪现」）
		if d.length() * (1.0 - k * 0.1) < 0.5:
			break
		var cand := global_position + d * (1.0 - k * 0.1)
		var q := PhysicsRayQueryParameters3D.create(from, cand + Vector3(0, 1.0, 0), LAYER_WORLD)
		if space.intersect_ray(q).is_empty():
			var on_nav := NavigationServer3D.map_get_closest_point(map, cand)
			if Vector2(on_nav.x - cand.x, on_nav.z - cand.z).length() < 0.3:
				return Vector3(cand.x, 0.0, cand.z)
	return null


func _start_action(id: String) -> void:
	action = id
	action_t = 0.0
	action_hit_done = false


func _enemies_within(radius: float, need_los := false) -> Array:
	var out := []
	var space := get_world_3d().direct_space_state
	for e in get_tree().get_nodes_in_group("enemy"):
		if e.get("dead"):
			continue
		var d: Vector3 = e.global_position - global_position
		d.y = 0.0
		if d.length() > radius + float(e.def.get("radius", 0.45)):
			continue
		if need_los:
			var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 1, 0), e.global_position + Vector3(0, 1, 0), LAYER_WORLD)
			if not space.intersect_ray(q).is_empty():
				continue
		out.append(e)
	return out


func _resolve_action() -> void:
	var s := Balance.skill(action)
	var hits := 0
	var sf: Dictionary = Act1Data.rules().skill_formulas
	var lvl: int = progress.sheet.lvl
	match action:
		"oath_cleave", "whirl":
			# 普攻：正前方扇形；烬环斩：周围一圈、130% 武器伤害（V0.1 whirl）
			var coef := 1.0 if action == "oath_cleave" else float(sf.whirl.weapon_mul)
			var knock: float = Balance.fb().knockback_m[s.knockback]
			var targets := []
			if action == "whirl":
				targets = _enemies_within(s.radius)
			else:
				for e in get_tree().get_nodes_in_group("enemy"):
					if e.get("dead"):
						continue
					var d: Vector3 = e.global_position - global_position
					d.y = 0.0
					var ang := rad_to_deg(facing().angle_to(d.normalized())) if d.length() > 0.01 else 0.0
					if d.length() <= s.range + 0.45 and ang <= s.arc_deg * 0.5:
						targets.append(e)
			for e in targets:
				var d: Vector3 = e.global_position - global_position
				d.y = 0.0
				var r := DamageCalc.roll(stats, coef, "physical", e.combat_target(), rng)
				e.take_hit(r, d, knock, 0.0)
				HitFeedback.apply(self, e, r, camera, false)
				if progress.S.ls > 0:
					hp = minf(max_hp, hp + r.amount * progress.S.ls / 100.0)
				hits += 1
			if action == "whirl":
				_ring_fx(Color(1.0, 0.62, 0.3), s.radius, 0.3)
		"fireball":
			var fb := Fireball.new()
			var dir := aim_point - global_position
			dir.y = 0.0
			fb.dir = dir.normalized() if dir.length() > 0.01 else facing()
			fb.speed = s.speed
			fb.life = float(sf.fireball.life_s)
			fb.hit_radius = s.hit_radius
			fb.splash_radius = s.splash_radius
			fb.damage = (float(sf.fireball.base) + lvl * float(sf.fireball.per_lvl)) * progress.S.spell
			fb.owner_player = self
			get_parent().add_child(fb)
			fb.global_position = global_position + Vector3(0, 1.1, 0) + fb.dir * 0.6
			last_fireball = fb
			hit_landed.emit(action, 0)
			return
		"nova":
			# 寂霜环：周围 6 米内看得见的敌人受冰霜伤害并减速 3 秒
			var j: Array = sf.nova.jitter
			for e in _enemies_within(s.radius, true):
				var amount: float = (float(sf.nova.base) + lvl * float(sf.nova.per_lvl)) * progress.S.spell * rng.randf_range(j[0], j[1])
				var r := {"amount": maxi(1, roundi(amount)), "crit": false, "type": "cold"}
				e.take_hit(r, Vector3.ZERO, 0.0, 0.0)
				e.apply_slow(float(sf.nova.slow_s))
				HitFeedback.apply(self, e, r, camera, false)
				hits += 1
			_ring_fx(Color(0.6, 0.85, 1.0), s.radius, 0.45)
		"blink":
			_ring_fx(Color(0.7, 0.5, 1.0), 1.2, 0.3)
			global_position = aim_point
			stop()
			_ring_fx(Color(0.7, 0.5, 1.0), 1.2, 0.3)
			if camera:
				camera.snap()
	hit_landed.emit(action, hits)
	if hits > 0:
		print("EF_HIT skill=%s hits=%d" % [action, hits])


var last_fireball: Fireball


func _ring_fx(c: Color, radius: float, dur: float) -> void:
	## 技能的占位特效：从脚下扩散的一圈光环
	var ring := MeshInstance3D.new()
	ring.mesh = LowPoly.torus(0.88, 1.0)
	var m := _mat(c)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = m
	get_parent().add_child(ring)
	ring.global_position = Vector3(global_position.x, 0.12, global_position.z)
	ring.scale = Vector3(0.3, 1, 0.3)
	var tw := ring.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(radius, 1, radius), dur).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, dur + 0.05).set_delay(dur * 0.3)
	tw.chain().tween_callback(ring.queue_free)


func _update_action(delta: float) -> void:
	var s := Balance.skill(action)
	# 普攻节奏随攻速变化（V0.1：攻击间隔 = 1 / 攻速）；技能不受影响
	action_t += delta * (progress.attack_speed_scale() if action == "oath_cleave" else 1.0)
	var total: float = s.windup_s + s.recover_s
	if action == "oath_cleave":
		# 前摇举刀 → 判定瞬间挥下 → 后摇收刀
		if action_t < s.windup_s:
			_set_swing(0.0)
		else:
			_set_swing(clampf((action_t - s.windup_s) / 0.08, 0.0, 1.0))
	elif action == "whirl":
		# 烬环斩：整个人转一圈
		_visual.rotation.y = clampf(action_t / total, 0.0, 1.0) * TAU
	else:
		_blade_pivot.position.y = 1.25 + (0.4 if action_t < s.windup_s else 0.0)
	if not action_hit_done and action_t >= s.windup_s:
		action_hit_done = true
		_resolve_action()
	if action_t >= total:
		action = ""
		_set_swing(0.0)
		_visual.rotation.y = 0.0
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
	for k in skill_cd.keys():
		skill_cd[k] = maxf(0.0, skill_cd[k] - delta)
	_update_marker(delta)
	if _hurt_t > 0.0:
		_hurt_t -= delta
	_body_mat.albedo_color = Color(1.0, 0.35, 0.3) if _hurt_t > 0.0 else Color(0.55, 0.47, 0.38)
	if dead:
		_respawn_t -= delta
		if _respawn_t <= 0.0:
			respawn()
		return
	if talk_target != null:
		if not is_instance_valid(talk_target):
			talk_target = null
		elif Vector2(talk_target.global_position.x - global_position.x, talk_target.global_position.z - global_position.z).length() <= (Npc.TALK_RANGE if talk_target is Npc else talk_target.use_range):
			var npc := talk_target
			talk_target = null
			stop()
			face_point(npc.global_position)
			talk_requested.emit(npc)
	if pickup_target != null:
		if not is_instance_valid(pickup_target):
			pickup_target = null
		elif Vector2(pickup_target.global_position.x - global_position.x, pickup_target.global_position.z - global_position.z).length() <= GroundItem.PICK_RANGE:
			var gi := pickup_target
			pickup_target = null
			stop()
			pick_up(gi)
	# 每秒回复（V0.1：生命 0.4 + 0.05×等级 + 装备；法力 1.2 + 0.06×魔力）
	hp = minf(max_hp, hp + progress.S.regen * delta)
	mp = minf(max_mp, mp + progress.S.mregen * delta)
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
