class_name Melee
extends Node
## 玩家近战（路线图 2.4；GDD.md 第六节；TECH.md 4.3）：拔剑 / 收剑、轻击（两段连击）、重击（按住 0.35 秒蓄力）、体力。
## 输入只有 press() / release() / toggle_draw() 三个入口：鼠标左键、触屏「攻」按钮、测试都调用它们。
## 命中判定：挥砍的「命中帧」做一次形状查询（相机前方 0.4–2.0 米的盒子，物理层 4「可受击」），再用一条射线确认中间没有墙。
## 命中停顿只冻结自己的挥砍动画和被打的目标（局部），不改全局 Engine.time_scale。
## 3.6：敌人的「踢」（kind = kick）挡不住，举着格挡也会被踢破防。
## 2.5：格挡（右键 / Q / 触屏「挡」按住）、完美格挡（敌人命中前 0.2 秒内按下：不耗体力、对方失衡 0.8 秒）、失衡、生命。
## 格挡住普通攻击时伤害变成体力消耗（重击 1.5 倍）；体力不够挡：格挡被打破，自己失衡 0.8 秒并吃一半伤害。失衡期间受到的伤害加倍、不能出招。
## 属性与技能在 2.7（现在用 GameState 里的默认力量与剑术）。
## 3.3 徒手格斗：没装备武器、或者打架时不许动刀（fists_only），手里就是拳头（FISTS）：出招时机和剑一样，够得着的距离短一些、体力省一些，
## 用格斗技能算伤害、涨格斗；格斗专长：连拳（轻拳三连）、重拳（重拳打中让对方失衡）、硬骨头（空手格挡体力减半）。
## 不致命的打斗（对方攻击带 nonlethal）：生命被打到 KO_FLOOR 就算被打倒（knocked_out），不会倒下死去。

signal swung(kind: String)
signal hit(target: Node, info: Dictionary)
signal drawn_changed(drawn: bool)
signal guarded(result: String, info: Dictionary)      # perfect / block / guard_break
signal damaged(amount: int, info: Dictionary)
signal defeated
signal knocked_out(info: Dictionary)   # 不致命的打斗里被打倒（3.3）：生命停在 KO_FLOOR，不算倒下

enum State { SHEATHED, DRAWING, IDLE, CHARGE, WINDUP, STRIKE, RECOVER, SHEATHING, BLOCK }

const WEAPON_SKILL := {"sword": "blade", "club": "blunt", "fists": "brawl"}     # 武器外观 → 用的技能（2.7；拳头 3.3）
const FISTS := {"name": "拳头", "model": "fists", "base": 5}       # 空手（3.3）：当成一件基础伤害 5 的「武器」
const FIST_REACH := 1.5           # 拳头够得着的距离（剑 2.0）
const FIST_COST := 0.7            # 出拳的体力消耗是挥剑的七成
const KO_FLOOR := 25              # 不致命的打斗：生命被打到这里就算被打倒（3.3）
const HEAVY_HOLD := 0.35          # 按住超过这个时间松开 = 重击（GDD.md 第三节）
const DRAW_TIME := 0.35
const SHEATHE_TIME := 0.3
## 每种攻击：起手、挥砍、收招的时长（秒）；命中帧在挥砍段的 hit_at 处
const TIMING := {
	"light": {"wind": 0.10, "strike": 0.12, "recover": 0.30, "hit_at": 0.5, "cost": 12.0, "stop": 0.05, "kick": 0.6},
	"heavy": {"wind": 0.0, "strike": 0.15, "recover": 0.45, "hit_at": 0.55, "cost": 25.0, "stop": 0.09, "kick": 1.4},
}
const COMBO_MAX := 2              # 轻击连击段数（剑术 25 专长「连环」后 3 段，见 combo_max()）
const STAMINA_MAX := 100.0        # 体魄 5 时的体力上限；实际上限看 GameState.stamina_max()
const SPRINT_COST := 12.0         # 每秒
const REGEN := 28.0               # 每秒
const REGEN_DELAY := 0.7          # 最后一次消耗后多久开始恢复
const RECOVER_AT := 25.0          # 体力耗尽后恢复到这么多才算缓过气
const TIRED_SPEED := 0.65         # 体力不足时出招变慢
const REACH_NEAR := 0.4
const REACH_FAR := 2.0
const HIT_BOX := Vector3(1.4, 1.2, REACH_FAR - REACH_NEAR)     # 拳头时深度按 FIST_REACH 缩短（reach_far()）
const HEALTH_MAX := 100           # 体魄 5 时的生命上限；实际上限看 GameState.health_max()
const PERFECT_WINDOW := 0.2       # 完美格挡：在对方命中前这么久之内按下（剑术 75 专长「定心」放宽到 0.3）
const PERFECT_WINDOW_WIDE := 0.3
## 用什么涨什么（2.7）：命中一次、挡住一次、完美格挡一次各涨多少进度；打木桩只算一半
const TRAIN_HIT := 1.0
const TRAIN_BLOCK := 0.5
const TRAIN_PERFECT := 2.0
const GUARD_COST := 1.0           # 挡住时每点伤害换成多少体力（重击再 × 1.5）
const GUARD_ANGLE := 70.0         # 正面这么大角度内的攻击才挡得住
const STAGGER_TIME := 0.8
const BOUNCE_TIME := 0.18         # 被对方挡住时剑弹回来的停顿
const DAMAGE_LAYER := 8           # 物理层 4「可受击」
const WORLD_LAYER := 1

var player: FpController
var view: WeaponView
var state := State.SHEATHED
var stamina := STAMINA_MAX
var exhausted := false
var since_use := 10.0
var kind := "light"
var combo := 0
var queued := false
var pressed := false
var held := 0.0
var t := 0.0                      # 当前阶段已经过的时间
var dur := 0.0
var speed := 1.0
var hit_done := false
var from_pose: Array = []
var stop_left := 0.0              # 命中停顿剩余时间
var cam_kick := 0.0
var last_hit := {}
var health := HEALTH_MAX
var block_held := false
var block_since := 0.0            # 进入格挡的时刻（clock，秒）
var clock := 0.0                  # 自己的时钟：暂停时不走
var stagger_left := 0.0
var down := false                 # 生命归零
var counter_ready := false        # 剑术 50「反击」：完美格挡后下一击必定是重击
var fists_only := false           # 打架时不许动刀，只用拳头（3.3，Brawl 设）


func _ready() -> void:
	view = WeaponView.new()
	view.name = "Weapon"
	player.camera.add_child(view)
	view.set_model(str(arms().get("model", "sword")))
	GameState.inventory_changed.connect(_on_inventory_changed)
	health = health_max()
	stamina = stamina_max()


## 装备中的武器（data/items.json 里的一条；没装备武器时是空字典）
func weapon() -> Dictionary:
	return GameState.item(GameState.weapon_id())


## 现在手里打出去的是什么：装备的武器；没装备武器、或者打架不许动刀时是拳头（3.3）
func arms() -> Dictionary:
	return FISTS if unarmed() else weapon()


func unarmed() -> bool:
	return fists_only or weapon().is_empty()


## 打架开始 / 结束（3.3）：只许用拳头；正拿着剑就先收起来
func set_fists_only(on: bool) -> void:
	fists_only = on
	_refresh_model()


func _on_inventory_changed() -> void:
	_refresh_model()


## 手里的东西换了（换武器、卸下武器、开始 / 结束打架）：换外观。武器换武器直接换到手里；
## 武器和拳头之间换（武器没了、开始 / 结束打架）正拿着就先收起来，再按一次拔剑 / 举拳
func _refresh_model() -> void:
	var m := str(arms().get("model", "sword"))
	if m == view.model:
		return
	if state != State.SHEATHED and (m == "fists" or view.model == "fists"):
		cancel_press()
		view.visible = false
		_enter(State.SHEATHED, 1.0)
		drawn_changed.emit(false)
	view.set_model(m)


func drawn() -> bool:
	return state != State.SHEATHED and state != State.SHEATHING and state != State.DRAWING


func busy() -> bool:
	return state in [State.CHARGE, State.WINDUP, State.STRIKE, State.RECOVER, State.BLOCK]


func blocking() -> bool:
	return state == State.BLOCK


func staggered() -> bool:
	return stagger_left > 0.0


## 格挡键按下 / 松开（右键、Q、触屏「挡」）。收着剑时先拔剑，拔出来还按着就举剑格挡。
func block_press() -> void:
	block_held = true
	if down or staggered():
		return
	if state == State.SHEATHED:
		_draw_weapon()
	elif state in [State.IDLE, State.RECOVER]:
		_enter_block()


func block_release() -> void:
	block_held = false
	if state == State.BLOCK:
		from_pose = view.current()
		_enter(State.RECOVER, 0.15)
		kind = "light"
		combo = 99


func _enter_block() -> void:
	pressed = false
	queued = false
	from_pose = view.current()
	block_since = clock
	_enter(State.BLOCK, 0.12)


## 敌人命中帧调用：info = {damage, kind, attacker, stop}；返回 perfect / block / guard_break / hit / none
func receive_hit(info: Dictionary) -> String:
	if down:
		return "none"
	var dmg := int(info.get("damage", 0))
	var attacker: Node3D = info.get("attacker")
	var front := true
	if attacker:
		var to := attacker.global_position - player.global_position
		to.y = 0.0
		var fwd := -player.global_transform.basis.z
		fwd.y = 0.0
		front = to.length() < 0.01 or rad_to_deg(fwd.angle_to(to.normalized())) <= GUARD_ANGLE
	if state == State.BLOCK and front and info.get("kind") == "kick":
		# 踢（3.6，头目「灰手」奥弗）：格挡挡不住，直接破防；看到「踢！」就该往后退
		_spend(minf(stamina, dmg * GUARD_COST))
		_stagger_self()
		guarded.emit("guard_break", info)
		_take(dmg, info)
		return "guard_break"
	if state == State.BLOCK and front:
		if clock - block_since <= perfect_window() and info.get("kind") != "arrow":      # 箭（B.4）没有完美格挡：射手站在远处，失衡不了
			view.kick = Vector3(0, 0, 0.05)
			GameState.train(weapon_skill(), TRAIN_PERFECT)
			if GameState.has_perk("blade", "counter"):
				counter_ready = true
			guarded.emit("perfect", info)
			return "perfect"
		var cost := guard_cost(info)
		if stamina >= cost:
			_spend(cost)
			GameState.train(weapon_skill(), TRAIN_BLOCK)
			view.kick = Vector3(0, 0, 0.04)
			guarded.emit("block", info)
			return "block"
		# 体力不够挡：格挡被打破
		_spend(stamina)
		_stagger_self()
		guarded.emit("guard_break", info)
		_take(int(ceil(dmg * 0.5)), info)
		return "guard_break"
	if staggered():
		dmg *= 2
	_take(dmg, info)
	return "hit"


## 挡住这一下要花多少体力：每点伤害 GUARD_COST，重击 1.5 倍；格斗 75「硬骨头」空手格挡减半（3.3）
func guard_cost(info: Dictionary) -> float:
	var cost := int(info.get("damage", 0)) * GUARD_COST * (1.5 if info.get("kind") == "heavy" else 1.0)
	if unarmed() and GameState.has_perk("brawl", "guard_cheap"):
		cost *= 0.5
	return cost


func _take(dmg: int, info: Dictionary) -> void:
	# 不致命的打斗（3.3）：打到 KO_FLOOR 就停，算被打倒；本来就在这条线以下的，挨一下就倒
	if bool(info.get("nonlethal", false)) and health - dmg <= KO_FLOOR:
		health = mini(health, KO_FLOOR) if health > 0 else 1
		damaged.emit(dmg, info)
		cancel_press()
		block_held = false
		_stagger_self()
		knocked_out.emit(info)
		return
	health = maxi(health - dmg, 0)
	if not Settings.reduced_motion:
		cam_kick = 2.0
	damaged.emit(dmg, info)
	if health <= 0 and not down:
		down = true
		cancel_press()
		block_held = false
		defeated.emit()


func _stagger_self() -> void:
	stagger_left = STAGGER_TIME
	pressed = false
	queued = false
	if state in [State.BLOCK, State.CHARGE, State.WINDUP, State.STRIKE]:
		from_pose = view.current()
		_enter(State.RECOVER, STAGGER_TIME)
		kind = "light"
		combo = 99


## 自己的轻击被对方挡住：剑弹回来，停顿一下（2.5）
func on_blocked() -> void:
	stop_left = BOUNCE_TIME
	view.kick = Vector3(0, 0, 0.06)


func can_sprint() -> bool:
	return not exhausted and stamina > 0.0


## 拔剑 / 收剑（R 键）；空手时是举起 / 放下拳头
func toggle_draw() -> void:
	if state == State.SHEATHED:
		_draw_weapon()
	elif state == State.IDLE:
		_enter(State.SHEATHING, SHEATHE_TIME)
		from_pose = view.current()


func _draw_weapon() -> void:
	_refresh_model()
	view.visible = true
	view.set_pose(view.pose("lowered"))
	from_pose = view.current()
	_enter(State.DRAWING, DRAW_TIME)


## 攻击键按下：收着剑时先拔剑；空闲时开始蓄力（松开得快就是轻击）；出招中按下记为连击
func press() -> void:
	pressed = true
	if down or staggered() or state == State.BLOCK:
		return
	match state:
		State.SHEATHED:
			_draw_weapon()
		State.IDLE:
			held = 0.0
			from_pose = view.current()
			_enter(State.CHARGE, HEAVY_HOLD)
		State.DRAWING:
			queued = true            # 拔剑途中点了一下：拔出来就出一记轻击（帧率低时不丢输入）
		State.STRIKE, State.RECOVER, State.WINDUP:
			if kind == "light":
				queued = true


func release() -> void:
	if not pressed:
		return
	pressed = false
	if state == State.CHARGE:
		_start_attack("heavy" if held >= HEAVY_HOLD else "light")


## 打开对话、菜单时：放弃正在攒的蓄力，回到持剑姿势
func cancel_press() -> void:
	pressed = false
	queued = false
	if block_held or state == State.BLOCK:
		block_release()
	if state == State.CHARGE:
		from_pose = view.current()
		_enter(State.RECOVER, 0.2)
		kind = "light"


func _enter(s: State, d: float) -> void:
	state = s
	t = 0.0
	dur = maxf(d, 0.0001)


## 现在这把武器用的技能（剑 → 剑术，木棍 → 钝器，拳头 → 格斗）
func weapon_skill() -> String:
	return str(WEAPON_SKILL.get(str(arms().get("model", "sword")), "blade"))


## 轻击连几段：这件武器的技能有「三连」专长（剑术 25「连环」、格斗 25「连拳」）就是 3 段
func combo_max() -> int:
	return 3 if GameState.has_perk(weapon_skill(), "combo3") else COMBO_MAX


## 够得着多远（米，从眼睛算）：剑 2.0，拳头 1.5
func reach_far() -> float:
	return FIST_REACH if unarmed() else REACH_FAR


func perfect_window() -> float:
	return PERFECT_WINDOW_WIDE if GameState.has_perk("blade", "parry_window") else PERFECT_WINDOW


func health_max() -> int:
	return GameState.health_max()


func stamina_max() -> float:
	return GameState.stamina_max()


func _start_attack(k: String) -> void:
	if counter_ready:
		k = "heavy"               # 反击
		counter_ready = false
	kind = k
	if k == "heavy":
		combo = 0
	var tm: Dictionary = TIMING[k]
	var cost: float = tm.cost * (FIST_COST if unarmed() else 1.0)
	speed = 1.0
	if stamina < cost or exhausted:
		speed = TIRED_SPEED
	_spend(cost)
	hit_done = false
	queued = false
	from_pose = view.current()
	if k == "heavy":
		_enter(State.STRIKE, tm.strike / speed)
	else:
		_enter(State.WINDUP, tm.wind / speed)
	swung.emit(k)


func _spend(amount: float) -> void:
	stamina = maxf(stamina - amount, 0.0)
	since_use = 0.0
	if stamina <= 0.0:
		exhausted = true


func _poses() -> Array:
	if kind == "heavy":
		return [view.pose("h_wind"), view.pose("h_end")]
	if combo % 2 == 0:
		return [view.pose("l1_wind"), view.pose("l1_end")]
	return [view.pose("l2_wind"), view.pose("l2_end")]


func _process(delta: float) -> void:
	clock += delta
	if stagger_left > 0.0:
		stagger_left = maxf(stagger_left - delta, 0.0)
	_update_stamina(delta)
	_update_kick(delta)
	view.off_raise = move_toward(view.off_raise, 1.0 if state == State.BLOCK else 0.0, delta * 8.0)     # 空手时左拳跟着举起来
	if stop_left > 0.0:
		stop_left -= delta
		return
	t += delta
	var k := clampf(t / dur, 0.0, 1.0)
	var e := k * k * (3.0 - 2.0 * k)
	match state:
		State.DRAWING:
			view.blend(from_pose, view.pose("rest"), e)
			if k >= 1.0:
				_enter(State.IDLE, 1.0)
				drawn_changed.emit(true)
				if block_held:
					_enter_block()
				elif pressed:
					queued = false
					press()          # 一直按着：拔出来接着蓄力
				elif queued:
					queued = false
					_start_attack("light")
		State.SHEATHING:
			view.blend(from_pose, view.pose("lowered"), e)
			if k >= 1.0:
				view.visible = false
				_enter(State.SHEATHED, 1.0)
				drawn_changed.emit(false)
		State.IDLE:
			view.set_pose(view.pose("rest"))
			if block_held and not staggered():
				_enter_block()
		State.BLOCK:
			view.blend(from_pose, view.pose("block"), e)
		State.CHARGE:
			held += delta
			view.blend(from_pose, view.pose("h_wind"), clampf(held / HEAVY_HOLD, 0.0, 1.0))
		State.WINDUP:
			view.blend(from_pose, _poses()[0], e)
			if k >= 1.0:
				from_pose = view.current()
				_enter(State.STRIKE, TIMING[kind].strike / speed)
		State.STRIKE:
			var p := _poses()
			view.blend(p[0] if kind == "light" else from_pose, p[1], k)
			if not hit_done and k >= float(TIMING[kind].hit_at):
				hit_done = true
				_resolve_hit()
			if k >= 1.0:
				from_pose = view.current()
				_enter(State.RECOVER, TIMING[kind].recover / speed)
		State.RECOVER:
			view.blend(from_pose, view.pose("rest"), e)
			# 轻击收招的前半段再按一次：接下一段（不用等完全收回）
			if queued and kind == "light" and combo + 1 < combo_max() and k >= 0.15:
				combo += 1
				_start_attack("light")
			elif k >= 1.0:
				combo = 0
				_enter(State.IDLE, 1.0)
				if queued:
					queued = false
				if block_held and not staggered():
					_enter_block()
				elif pressed:
					press()


func _update_stamina(delta: float) -> void:
	since_use += delta
	if player.running:
		_spend(SPRINT_COST * delta)
	elif since_use >= REGEN_DELAY and not busy():
		stamina = minf(stamina + REGEN * GameState.stamina_regen_mult() * delta, stamina_max())
	if exhausted and stamina >= RECOVER_AT:
		exhausted = false


func _update_kick(delta: float) -> void:
	view.kick = view.kick.move_toward(Vector3.ZERO, 0.6 * delta)
	if cam_kick != 0.0:
		cam_kick = move_toward(cam_kick, 0.0, 10.0 * delta)
		player.camera.rotation.x = deg_to_rad(cam_kick)


## 命中帧：前方盒子里离得最近、中间没有墙挡着的一个目标
func _resolve_hit() -> Dictionary:
	var target := find_target()
	if target == null:
		last_hit = {}
		return {}
	var tm: Dictionary = TIMING[kind]
	var w := arms()
	var sk := weapon_skill()
	var armor := float(target.get("armor")) if "armor" in target else 0.0
	if sk == "blunt" and GameState.has_perk("blunt", "armor_pierce"):
		armor = 0.0                                   # 钝器 50「破甲」
	var dmg := DamageCalc.compute(float(w.get("base", 1)), GameState.strength, int(GameState.skills.get(sk, 0)), kind,
		bool(target.get("staggered")) if "staggered" in target else false, armor)
	var dir := player.aim_forward()
	var info := {"damage": dmg, "kind": kind, "dir": dir, "stop": tm.stop, "weapon": str(w.get("name", ""))}
	stop_left = tm.stop
	view.kick = Vector3(0, 0, 0.04)
	if not Settings.reduced_motion:
		cam_kick = -float(tm.kick)
	target.take_hit(info)
	# 钝器 25「震骨」、格斗 50「重拳」：重击打中让对方失衡
	var stagger_perk := (sk == "blunt" and GameState.has_perk("blunt", "blunt_stagger")) or (sk == "brawl" and GameState.has_perk("brawl", "fist_stagger"))
	if kind == "heavy" and stagger_perk and target.has_method("stagger"):
		target.stagger()
	GameState.train(sk, TRAIN_HIT * (0.5 if target is TrainingDummy else 1.0))
	last_hit = info.merged({"target": target})
	hit.emit(target, info)
	return info


func find_target() -> Node3D:
	var cam := player.camera
	var eye := player.aim_origin()               # 第三人称时相机在身后：剑程从眼睛算（2.9）
	var basis := cam.global_transform.basis.orthonormalized()
	var depth := reach_far() - REACH_NEAR
	var center := eye - basis.z * (REACH_NEAR + depth * 0.5)
	var box := BoxShape3D.new()
	box.size = Vector3(HIT_BOX.x, HIT_BOX.y, depth)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.transform = Transform3D(basis, center)
	q.collision_mask = DAMAGE_LAYER
	q.exclude = [player.get_rid()]
	var space := player.get_world_3d().direct_space_state
	var best: Node3D = null
	var best_d := INF
	for r in space.intersect_shape(q, 8):
		var c: Object = r.collider
		if not (c is Node3D) or not c.has_method("take_hit"):
			continue
		var n := c as Node3D
		var aim := n.global_position + Vector3(0, clampf(eye.y - n.global_position.y, 0.3, 1.6), 0)
		var d := eye.distance_to(aim)
		if d >= best_d:
			continue
		var ray := PhysicsRayQueryParameters3D.create(eye, aim, WORLD_LAYER, [player.get_rid(), n.get_rid()])
		if not space.intersect_ray(ray).is_empty():
			continue
		best = n
		best_d = d
	return best
