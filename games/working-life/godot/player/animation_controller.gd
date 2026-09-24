class_name AnimationController
extends RefCounted
## 动画控制器：状态 Idle / Walk / Run / Interact / Carry / Sit / Work。
## 占位人物没有骨骼动画，这里用程序化方式摆动 CharacterModel 的关节；
## 如果模型里有 AnimationPlayer（换成正式美术后），就改为按状态名播放对应动画。

enum State { IDLE, WALK, RUN, INTERACT, CARRY, SIT, WORK }
const NAMES := ["Idle", "Walk", "Run", "Interact", "Carry", "Sit", "Work"]

var model: CharacterModel
var anim_player: AnimationPlayer
var state: int = State.IDLE
## 叠加状态：搬东西 / 拖行李箱时手臂姿势
var carrying := ""
var _phase := 0.0
var _amount := 0.0
var _oneshot := 0.0
var _oneshot_state: int = State.INTERACT


func _init(m: CharacterModel) -> void:
	model = m
	if m != null:
		anim_player = m.find_child("AnimationPlayer", true, false) as AnimationPlayer


func state_name() -> String:
	return NAMES[state]


## 一次性动作（交互、弯腰）
func play_once(s: int, duration := 0.6) -> void:
	_oneshot_state = s
	_oneshot = duration


func set_sitting(on: bool) -> void:
	state = State.SIT if on else State.IDLE


func update(delta: float, speed: float, on_floor := true, running := false) -> void:
	if model == null or not model._built:
		return
	if state != State.SIT and state != State.WORK:
		if speed < 0.3:
			state = State.IDLE
		elif running:
			state = State.RUN
		else:
			state = State.WALK
		if carrying != "" and speed >= 0.3:
			state = State.CARRY
	if _oneshot > 0.0:
		_oneshot -= delta
	if anim_player != null:
		var n: String = NAMES[_oneshot_state if _oneshot > 0.0 else state]
		if anim_player.has_animation(n) and anim_player.current_animation != n:
			anim_player.play(n)
		return
	_procedural(delta, speed, on_floor)


func _procedural(delta: float, speed: float, on_floor: bool) -> void:
	var m := model
	var target := clampf(speed / 4.0, 0.0, 1.4)
	_amount = lerpf(_amount, target, clampf(delta * 8.0, 0.0, 1.0))
	_phase += delta * (4.0 + speed * 1.6) * (1.0 if _amount > 0.05 else 0.0)
	var swing := sin(_phase) * 0.62 * minf(_amount, 1.0)
	if not on_floor:
		swing = 0.35
	var t := Time.get_ticks_msec() / 1000.0
	if state == State.SIT:
		m.leg_l.rotation.x = lerpf(m.leg_l.rotation.x, 1.45, delta * 8.0)
		m.leg_r.rotation.x = lerpf(m.leg_r.rotation.x, 1.45, delta * 8.0)
		m.hips.position.y = lerpf(m.hips.position.y, 0.5, delta * 8.0)
		m.arm_l.rotation = Vector3(0.4, 0, 0.1)
		m.arm_r.rotation = Vector3(0.4, 0, -0.1)
		return
	m.leg_l.rotation.x = swing
	m.leg_r.rotation.x = -swing if on_floor else -0.2
	var bob := absf(sin(_phase)) * 0.045 * minf(_amount, 1.0)
	m.hips.position.y = 0.95 + bob + sin(t * 1.4) * 0.008
	m.torso.rotation.x = lerpf(m.torso.rotation.x, 0.12 if state == State.RUN else 0.0, delta * 6.0)
	match carrying:
		"box":
			m.arm_l.rotation = Vector3(1.25, 0, 0.18)
			m.arm_r.rotation = Vector3(1.25, 0, -0.18)
		"suitcase":
			m.arm_l.rotation = Vector3(-swing * 0.8, 0, 0.08)
			m.arm_r.rotation = Vector3(-0.35, 0, -0.12)
		_:
			m.arm_l.rotation = Vector3(-swing * 0.8, 0, 0.08)
			m.arm_r.rotation = Vector3(swing * 0.8, 0, -0.08)
	if state == State.WORK:
		m.arm_l.rotation = Vector3(0.9 + sin(t * 9.0) * 0.1, 0, 0.2)
		m.arm_r.rotation = Vector3(0.9 + cos(t * 9.0) * 0.1, 0, -0.2)
	if _oneshot > 0.0:
		var g := sin(clampf(_oneshot / 0.6, 0.0, 1.0) * PI)
		match _oneshot_state:
			State.INTERACT:
				m.arm_r.rotation = Vector3(1.2 * g + 0.2, 0, -0.1)
				m.head_pivot.rotation.x = -g * 0.15
			State.CARRY:
				m.hips.rotation.x = -g * 0.5
	else:
		m.hips.rotation.x = lerpf(m.hips.rotation.x, 0.0, clampf(delta * 10.0, 0.0, 1.0))
		m.head_pivot.rotation.x = lerpf(m.head_pivot.rotation.x, 0.0, clampf(delta * 10.0, 0.0, 1.0))
