class_name Melee
extends Node
## 玩家近战（路线图 2.4；GDD.md 第六节；TECH.md 4.3）：拔剑 / 收剑、轻击（两段连击）、重击（按住 0.35 秒蓄力）、体力。
## 输入只有 press() / release() / toggle_draw() 三个入口：鼠标左键、触屏「攻」按钮、测试都调用它们。
## 命中判定：挥砍的「命中帧」做一次形状查询（相机前方 0.4–2.0 米的盒子，物理层 4「可受击」），再用一条射线确认中间没有墙。
## 命中停顿只冻结自己的挥砍动画和被打的目标（局部），不改全局 Engine.time_scale。
## 格挡、完美格挡、失衡与敌人在 2.5；属性与技能在 2.7（现在用 GameState 里的默认力量与剑术）。

signal swung(kind: String)
signal hit(target: Node, info: Dictionary)
signal drawn_changed(drawn: bool)

enum State { SHEATHED, DRAWING, IDLE, CHARGE, WINDUP, STRIKE, RECOVER, SHEATHING }

const WEAPON := {"name": "短剑", "base": 10.0}     # 背包与装备在 2.6，到时从装备里读
const HEAVY_HOLD := 0.35          # 按住超过这个时间松开 = 重击（GDD.md 第三节）
const DRAW_TIME := 0.35
const SHEATHE_TIME := 0.3
## 每种攻击：起手、挥砍、收招的时长（秒）；命中帧在挥砍段的 hit_at 处
const TIMING := {
	"light": {"wind": 0.10, "strike": 0.12, "recover": 0.30, "hit_at": 0.5, "cost": 12.0, "stop": 0.05, "kick": 0.6},
	"heavy": {"wind": 0.0, "strike": 0.15, "recover": 0.45, "hit_at": 0.55, "cost": 25.0, "stop": 0.09, "kick": 1.4},
}
const COMBO_MAX := 2              # 轻击连击段数（剑术 25 后 3 段，2.7）
const STAMINA_MAX := 100.0
const SPRINT_COST := 12.0         # 每秒
const REGEN := 28.0               # 每秒
const REGEN_DELAY := 0.7          # 最后一次消耗后多久开始恢复
const RECOVER_AT := 25.0          # 体力耗尽后恢复到这么多才算缓过气
const TIRED_SPEED := 0.65         # 体力不足时出招变慢
const REACH_NEAR := 0.4
const REACH_FAR := 2.0
const HIT_BOX := Vector3(1.4, 1.2, REACH_FAR - REACH_NEAR)
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


func _ready() -> void:
	view = WeaponView.new()
	view.name = "Weapon"
	player.camera.add_child(view)


func drawn() -> bool:
	return state != State.SHEATHED and state != State.SHEATHING and state != State.DRAWING


func busy() -> bool:
	return state in [State.CHARGE, State.WINDUP, State.STRIKE, State.RECOVER]


func can_sprint() -> bool:
	return not exhausted and stamina > 0.0


## 拔剑 / 收剑（R 键）
func toggle_draw() -> void:
	if state == State.SHEATHED:
		_draw_weapon()
	elif state == State.IDLE:
		_enter(State.SHEATHING, SHEATHE_TIME)
		from_pose = view.current()


func _draw_weapon() -> void:
	view.visible = true
	view.set_pose(WeaponView.POSES.lowered)
	from_pose = view.current()
	_enter(State.DRAWING, DRAW_TIME)


## 攻击键按下：收着剑时先拔剑；空闲时开始蓄力（松开得快就是轻击）；出招中按下记为连击
func press() -> void:
	pressed = true
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
	if state == State.CHARGE:
		from_pose = view.current()
		_enter(State.RECOVER, 0.2)
		kind = "light"


func _enter(s: State, d: float) -> void:
	state = s
	t = 0.0
	dur = maxf(d, 0.0001)


func _start_attack(k: String) -> void:
	kind = k
	if k == "heavy":
		combo = 0
	var tm: Dictionary = TIMING[k]
	var cost: float = tm.cost
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
		return [WeaponView.POSES.h_wind, WeaponView.POSES.h_end]
	if combo % 2 == 0:
		return [WeaponView.POSES.l1_wind, WeaponView.POSES.l1_end]
	return [WeaponView.POSES.l2_wind, WeaponView.POSES.l2_end]


func _process(delta: float) -> void:
	_update_stamina(delta)
	_update_kick(delta)
	if stop_left > 0.0:
		stop_left -= delta
		return
	t += delta
	var k := clampf(t / dur, 0.0, 1.0)
	var e := k * k * (3.0 - 2.0 * k)
	match state:
		State.DRAWING:
			view.blend(from_pose, WeaponView.POSES.rest, e)
			if k >= 1.0:
				_enter(State.IDLE, 1.0)
				drawn_changed.emit(true)
				if pressed:
					queued = false
					press()          # 一直按着：拔出来接着蓄力
				elif queued:
					queued = false
					_start_attack("light")
		State.SHEATHING:
			view.blend(from_pose, WeaponView.POSES.lowered, e)
			if k >= 1.0:
				view.visible = false
				_enter(State.SHEATHED, 1.0)
				drawn_changed.emit(false)
		State.IDLE:
			view.set_pose(WeaponView.POSES.rest)
		State.CHARGE:
			held += delta
			view.blend(from_pose, WeaponView.POSES.h_wind, clampf(held / HEAVY_HOLD, 0.0, 1.0))
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
			view.blend(from_pose, WeaponView.POSES.rest, e)
			# 轻击收招的前半段再按一次：接下一段（不用等完全收回）
			if queued and kind == "light" and combo + 1 < COMBO_MAX and k >= 0.15:
				combo += 1
				_start_attack("light")
			elif k >= 1.0:
				combo = 0
				_enter(State.IDLE, 1.0)
				if queued:
					queued = false
				if pressed:
					press()


func _update_stamina(delta: float) -> void:
	since_use += delta
	if player.running:
		_spend(SPRINT_COST * delta)
	elif since_use >= REGEN_DELAY and not busy():
		stamina = minf(stamina + REGEN * delta, STAMINA_MAX)
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
	var dmg := DamageCalc.compute(WEAPON.base, GameState.strength, int(GameState.skills.get("blade", 0)), kind,
		bool(target.get("staggered")) if "staggered" in target else false, float(target.get("armor")) if "armor" in target else 0.0)
	var dir := -player.camera.global_transform.basis.z
	var info := {"damage": dmg, "kind": kind, "dir": dir, "stop": tm.stop, "weapon": WEAPON.name}
	stop_left = tm.stop
	view.kick = Vector3(0, 0, 0.04)
	if not Settings.reduced_motion:
		cam_kick = -float(tm.kick)
	target.take_hit(info)
	last_hit = info.merged({"target": target})
	hit.emit(target, info)
	return info


func find_target() -> Node3D:
	var cam := player.camera
	var basis := cam.global_transform.basis.orthonormalized()
	var center := cam.global_position - basis.z * (REACH_NEAR + HIT_BOX.z * 0.5)
	var box := BoxShape3D.new()
	box.size = HIT_BOX
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
		var aim := n.global_position + Vector3(0, clampf(cam.global_position.y - n.global_position.y, 0.3, 1.6), 0)
		var d := cam.global_position.distance_to(aim)
		if d >= best_d:
			continue
		var ray := PhysicsRayQueryParameters3D.create(cam.global_position, aim, WORLD_LAYER, [player.get_rid(), n.get_rid()])
		if not space.intersect_ray(ray).is_empty():
			continue
		best = n
		best_d = d
	return best
