class_name AnimationController
extends RefCounted
## 动画控制器：状态 Idle / Walk / Run / Interact / Carry / Sit / Work。
## 程序化步态：按移动距离推进步伐相位，算出髋、膝、踝、肩、肘、脊柱每根骨头的角度——
## 摆动腿屈膝抬脚、支撑腿脚跟着地到脚尖蹬地、骨盆左右转动与侧移、胸腔反向扭转、手臂与对侧腿同步摆动、
## 奔跑时前倾屈肘、转弯时身体向内侧倾斜；骨盆高度按两只脚里更低的那只贴地来算，走路自然起伏。
## 待机有呼吸、重心左右换脚和偶尔转头。各种姿势（坐、干活、搬箱子、拖行李箱、交互、腾空）按权重平滑混合。
## 如果模型里有 AnimationPlayer（换成外部美术资源后），就改为按状态名播放对应动画。

enum State { IDLE, WALK, RUN, INTERACT, CARRY, SIT, WORK }
const NAMES := ["Idle", "Walk", "Run", "Interact", "Carry", "Sit", "Work"]

var model: CharacterModel
var anim_player: AnimationPlayer
var state: int = State.IDLE
## 叠加状态：搬东西 / 拖行李箱时手臂姿势
var carrying := ""
var _phase := 0.0
var _amount := 0.0
var _run := 0.0
var _oneshot := 0.0
var _oneshot_len := 0.6
var _oneshot_state: int = State.INTERACT
var _t := 0.0
var _seed := 0.0
var _last_yaw := 0.0
var _has_yaw := false
var _turn := 0.0
var _speed := 0.0
var _accel := 0.0
var _air := 0.0
## 各姿势的混合权重（平滑过渡）
var _w := {"sit": 0.0, "work": 0.0, "box": 0.0, "suitcase": 0.0}
var _hips_y := 0.0
## 骨头角度（欧拉角）
var _rot: Array = []


func _init(m: CharacterModel) -> void:
	model = m
	_rot.resize(CharacterModel.BONE_NAMES.size())
	_rot.fill(Vector3.ZERO)
	if m != null:
		anim_player = m.find_child("AnimationPlayer", true, false) as AnimationPlayer
		_seed = float(m.get_instance_id() % 1000) * 0.37


func state_name() -> String:
	return NAMES[state]


## 一次性动作（交互、弯腰）
func play_once(s: int, duration := 0.6) -> void:
	_oneshot_state = s
	_oneshot = duration
	_oneshot_len = duration


func set_sitting(on: bool) -> void:
	state = State.SIT if on else State.IDLE


## 一个完整步态周期（左右各迈一步）前进的距离：走得越快步子越大
static func stride_length(speed: float) -> float:
	return clampf(0.9 + speed * 0.42, 1.2, 3.4)


func cycle_time(speed: float) -> float:
	return stride_length(speed) / maxf(speed, 0.01)


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
	_procedural(delta, speed, on_floor, running)


func _procedural(delta: float, speed: float, on_floor: bool, running: bool) -> void:
	var dt := clampf(delta, 0.0, 0.1)
	_t += dt
	var k := 1.0 - exp(-dt * 10.0)
	# 加速度（前倾 / 后仰）与转向角速度（向内倾斜）
	_accel = lerpf(_accel, (speed - _speed) / maxf(dt, 0.001), 1.0 - exp(-dt * 4.0))
	_speed = speed
	var yaw := model.global_rotation.y if model.is_inside_tree() else 0.0
	if _has_yaw and dt > 0.0:
		_turn = lerpf(_turn, clampf(wrapf(yaw - _last_yaw, -PI, PI) / dt, -8.0, 8.0), 1.0 - exp(-dt * 8.0))
	_last_yaw = yaw
	_has_yaw = true
	# 步态参数
	var target_amt := clampf(speed / 1.2, 0.0, 1.0)
	_amount = lerpf(_amount, target_amt, 1.0 - exp(-dt * 9.0))
	var run_target := 1.0 if running and speed > 2.0 else clampf((speed - 3.2) / 3.0, 0.0, 0.55)
	_run = lerpf(_run, run_target, 1.0 - exp(-dt * 5.0))
	if speed > 0.05:
		_phase = fmod(_phase + TAU * speed / stride_length(speed) * dt, TAU)
	elif _amount < 0.05:
		# 停下时把相位慢慢带回两腿并拢的位置
		_phase = lerp_angle(_phase, 0.0 if cos(_phase) > 0.0 else PI, k * 0.5)
	_air = lerpf(_air, 0.0 if on_floor else 1.0, 1.0 - exp(-dt * 12.0))
	_w["sit"] = lerpf(_w["sit"], 1.0 if state == State.SIT else 0.0, k)
	_w["work"] = lerpf(_w["work"], 1.0 if state == State.WORK else 0.0, k)
	_w["box"] = lerpf(_w["box"], 1.0 if carrying == "box" and state != State.SIT else 0.0, k)
	_w["suitcase"] = lerpf(_w["suitcase"], 1.0 if carrying == "suitcase" and state != State.SIT else 0.0, k)

	var amt := _amount
	var run := _run
	var D := stride_length(maxf(speed, 0.5))
	var hip_amp := clampf(asin(clampf(D / 3.4, 0.0, 0.9)) * 0.95, 0.2, 0.72) * amt
	var r := _rot
	for i in r.size():
		r[i] = Vector3.ZERO
	var pl := _phase
	var pr := _phase + PI
	# ---- 腿 ----
	var legs := [[CharacterModel.UPPERLEG_L, pl, -1.0], [CharacterModel.UPPERLEG_R, pr, 1.0]]
	var foot_low := 10.0
	for L in legs:
		var ub: int = L[0]
		var p: float = L[1]
		var hip := sin(p) * hip_amp + run * 0.22 * amt
		# 摆动期（cos p > 0，腿向前摆）屈膝最大；支撑期脚跟着地后有一点缓冲屈膝
		var swing_bell := pow(maxf(0.0, cos(wrapf(p - lerpf(0.3, 0.05, run), -PI, PI) * 1.15)), 2.0)
		var load_bell := pow(maxf(0.0, cos(wrapf(p - PI * 0.5 - 0.55, -PI, PI) * 1.6)), 2.0)
		var knee_amp := lerpf(clampf(0.55 + speed * 0.12, 0.7, 1.05), 1.8, run)
		var knee := -(0.06 + swing_bell * knee_amp + load_bell * lerpf(0.18, 0.5, run)) * amt
		# 脚掌角度：着地时脚尖微翘，蹬地时脚跟抬起，摆动时基本放平
		var strike := pow(maxf(0.0, cos(wrapf(p - PI * 0.5, -PI, PI) * 1.3)), 3.0)
		var push := pow(maxf(0.0, cos(wrapf(p + PI * 0.5 - 0.25, -PI, PI) * 1.5)), 2.0)
		var foot_world := (strike * lerpf(0.25, 0.08, run) - push * lerpf(0.5, 0.7, run)) * amt
		var ankle := foot_world - hip - knee
		r[ub] = Vector3(hip, 0, 0)
		r[ub + 1] = Vector3(knee, 0, 0)
		r[ub + 2] = Vector3(ankle, 0, 0)
		# 侧面平面里的正向运动学：算脚跟 / 脚尖离髋关节的竖直距离
		var knee_pos := Vector2(sin(hip), -cos(hip)) * CharacterModel.THIGH
		var shin_a := hip + knee
		var ankle_pos := knee_pos + Vector2(sin(shin_a), -cos(shin_a)) * CharacterModel.SHIN
		var fa := foot_world
		var heel := ankle_pos + Vector2(0.06 * -cos(fa), 0.0) + Vector2(0, -CharacterModel.ANKLE_H).rotated(fa)
		var toe := ankle_pos + Vector2(0.19 * cos(fa), 0.19 * sin(fa)) + Vector2(0, -CharacterModel.ANKLE_H + 0.02).rotated(fa)
		foot_low = minf(foot_low, minf(heel.y, toe.y))
	# 骨盆高度：让更低的那只脚刚好着地；奔跑有腾空期，另加上下弹跳
	var rest_drop := -(CharacterModel.BONE_REST[CharacterModel.HIPS].y + CharacterModel.BONE_REST[CharacterModel.UPPERLEG_L].y)
	var fit := foot_low - rest_drop
	var bounce := run * amt * 0.035 * cos(2.0 * _phase)
	var hy := -fit * (1.0 - run * 0.5) + bounce
	_hips_y = hy if amt > 0.02 else lerpf(_hips_y, hy, k)
	# ---- 骨盆与躯干 ----
	var pelvis_yaw := -sin(pl) * 0.16 * amt * (1.0 - run * 0.3)
	var pelvis_roll := cos(2.0 * _phase) * 0.035 * amt * (1.0 - run)
	var sway := cos(pl) * 0.028 * amt * (1.0 - run)
	var lean_fwd := -(run * 0.2 + clampf(_accel * 0.03, -0.12, 0.15)) * amt
	var turn_lean := clampf(_turn * speed * 0.035, -0.3, 0.3)
	r[CharacterModel.HIPS] = Vector3(lean_fwd * 0.5, pelvis_yaw, pelvis_roll + turn_lean)
	r[CharacterModel.SPINE] = Vector3(lean_fwd * 0.3 + 0.03 * amt, -pelvis_yaw * 0.9, -pelvis_roll * 0.6)
	r[CharacterModel.CHEST] = Vector3(lean_fwd * 0.2, -pelvis_yaw * 1.1, -pelvis_roll * 0.4 - turn_lean * 0.3)
	# 头：抵消躯干的扭转，朝着转弯的方向看
	r[CharacterModel.NECK] = Vector3(-lean_fwd * 0.5, pelvis_yaw * 0.6, 0)
	r[CharacterModel.HEAD] = Vector3(-lean_fwd * 0.4, clampf(_turn * 0.12, -0.35, 0.35), -turn_lean * 0.4)
	# ---- 手臂：与对侧腿同步 ----
	var arm_amp := lerpf(0.36, 0.75, run) * amt
	for A in [[CharacterModel.UPPERARM_L, pl, -1.0], [CharacterModel.UPPERARM_R, pr, 1.0]]:
		var ab: int = A[0]
		var p: float = A[1]
		var side: float = A[2]
		var sw := -sin(p) * arm_amp
		var elbow := lerpf(0.18, 1.45, run) + maxf(0.0, sw) * lerpf(0.5, 0.3, run) + 0.08 * (1.0 - amt)
		r[ab] = Vector3(sw + 0.02, 0, side * lerpf(0.09, 0.14, run))
		r[ab + 1] = Vector3(elbow, side * -0.1 * run, 0)
		r[ab + 2] = Vector3(-0.1 * run, 0, side * 0.08)
	# ---- 待机：呼吸、重心换脚、偶尔转头 ----
	var idle := 1.0 - amt
	if idle > 0.01:
		var t := _t + _seed
		var breath := sin(t * 1.7)
		var shift := sin(t * 0.37) * 0.5 + sin(t * 0.13) * 0.5
		r[CharacterModel.HIPS] += Vector3(0, 0, shift * 0.035) * idle
		r[CharacterModel.SPINE] += Vector3(breath * 0.012, 0, -shift * 0.03) * idle
		r[CharacterModel.CHEST] += Vector3(-breath * 0.02, 0, 0) * idle
		r[CharacterModel.HEAD] += Vector3(sin(t * 0.23) * 0.05, (sin(t * 0.31) + sin(t * 0.17 + 1.3)) * 0.22, 0) * idle
		for side in [-1.0, 1.0]:
			var ab := CharacterModel.UPPERARM_L if side < 0 else CharacterModel.UPPERARM_R
			r[ab] += Vector3(0.02, 0, side * (0.06 + breath * 0.008)) * idle
			r[ab + 1] += Vector3(0.1, 0, 0) * idle
			# 重心在哪条腿上，另一条腿稍微弯一点
			var ub := CharacterModel.UPPERLEG_L if side < 0 else CharacterModel.UPPERLEG_R
			var relax := clampf(shift * side * -1.0, 0.0, 1.0)
			r[ub] += Vector3(0.1 * relax, 0, -side * 0.03) * idle
			r[ub + 1] += Vector3(-0.2 * relax, 0, 0) * idle
			r[ub + 2] += Vector3(0.1 * relax, 0, 0) * idle
	# ---- 叠加姿势 ----
	var wb: float = _w["box"]
	if wb > 0.01:
		for side in [-1.0, 1.0]:
			var ab := CharacterModel.UPPERARM_L if side < 0 else CharacterModel.UPPERARM_R
			r[ab] = r[ab].lerp(Vector3(0.75, 0, -side * 0.12), wb)
			r[ab + 1] = r[ab + 1].lerp(Vector3(1.05, 0, 0), wb)
			r[ab + 2] = r[ab + 2].lerp(Vector3(0, 0, -side * 0.35), wb)
		r[CharacterModel.SPINE] += Vector3(0.08, 0, 0) * wb
	var ws: float = _w["suitcase"]
	if ws > 0.01:
		r[CharacterModel.UPPERARM_R] = r[CharacterModel.UPPERARM_R].lerp(Vector3(-0.32, 0, 0.1), ws)
		r[CharacterModel.LOWERARM_R] = r[CharacterModel.LOWERARM_R].lerp(Vector3(0.08, 0, 0), ws)
		r[CharacterModel.HAND_R] = r[CharacterModel.HAND_R].lerp(Vector3(0, 0, 0.1), ws)
	var wk: float = _w["work"]
	if wk > 0.01:
		var t2 := _t * 9.0
		for side in [-1.0, 1.0]:
			var ab := CharacterModel.UPPERARM_L if side < 0 else CharacterModel.UPPERARM_R
			var wig := sin(t2 + (0.0 if side < 0 else 1.7)) * 0.1
			r[ab] = r[ab].lerp(Vector3(0.6 + wig, 0, -side * 0.15), wk)
			r[ab + 1] = r[ab + 1].lerp(Vector3(1.0 - wig, 0, 0), wk)
		r[CharacterModel.SPINE] += Vector3(-0.1, 0, 0) * wk
		r[CharacterModel.HEAD] = r[CharacterModel.HEAD].lerp(Vector3(-0.25, 0, 0), wk)
	var wsit: float = _w["sit"]
	if wsit > 0.01:
		for side in [-1.0, 1.0]:
			var ub := CharacterModel.UPPERLEG_L if side < 0 else CharacterModel.UPPERLEG_R
			var ab := CharacterModel.UPPERARM_L if side < 0 else CharacterModel.UPPERARM_R
			r[ub] = r[ub].lerp(Vector3(1.5, 0, side * 0.06), wsit)
			r[ub + 1] = r[ub + 1].lerp(Vector3(-1.45, 0, 0), wsit)
			r[ub + 2] = r[ub + 2].lerp(Vector3(-0.05, 0, 0), wsit)
			r[ab] = r[ab].lerp(Vector3(0.35, 0, -side * 0.05), wsit)
			r[ab + 1] = r[ab + 1].lerp(Vector3(0.75, 0, 0), wsit)
		r[CharacterModel.HIPS] = r[CharacterModel.HIPS].lerp(Vector3(-0.08, 0, 0), wsit)
		r[CharacterModel.SPINE] = r[CharacterModel.SPINE].lerp(Vector3(0.05, 0, 0), wsit)
	if _air > 0.01:
		for side in [-1.0, 1.0]:
			var ub := CharacterModel.UPPERLEG_L if side < 0 else CharacterModel.UPPERLEG_R
			var ab := CharacterModel.UPPERARM_L if side < 0 else CharacterModel.UPPERARM_R
			r[ub] = r[ub].lerp(Vector3(0.55 if side < 0 else 0.2, 0, 0), _air)
			r[ub + 1] = r[ub + 1].lerp(Vector3(-1.0 if side < 0 else -0.5, 0, 0), _air)
			r[ub + 2] = r[ub + 2].lerp(Vector3(-0.2, 0, 0), _air)
			if _w["box"] < 0.5:
				r[ab] = r[ab].lerp(Vector3(0.3, 0, side * 0.35), _air)
				r[ab + 1] = r[ab + 1].lerp(Vector3(0.6, 0, 0), _air)
	# 一次性动作：伸手按东西 / 弯腰拿东西
	if _oneshot > 0.0:
		var g := sin(clampf(_oneshot / _oneshot_len, 0.0, 1.0) * PI)
		match _oneshot_state:
			State.INTERACT:
				r[CharacterModel.UPPERARM_R] = r[CharacterModel.UPPERARM_R].lerp(Vector3(1.25, 0, -0.05), g)
				r[CharacterModel.LOWERARM_R] = r[CharacterModel.LOWERARM_R].lerp(Vector3(0.35, 0, 0), g)
				r[CharacterModel.HEAD] = r[CharacterModel.HEAD].lerp(Vector3(-0.15, 0, 0), g)
			State.CARRY:
				r[CharacterModel.SPINE] += Vector3(-0.45, 0, 0) * g
				r[CharacterModel.CHEST] += Vector3(-0.2, 0, 0) * g
				for ub in [CharacterModel.UPPERLEG_L, CharacterModel.UPPERLEG_R]:
					r[ub] += Vector3(0.35, 0, 0) * g
					r[ub + 1] += Vector3(-0.6, 0, 0) * g
					r[ub + 2] += Vector3(0.25, 0, 0) * g
	# 骨盆高度：坐下时降到椅面
	var hips_off := Vector3(sway * (1.0 - wsit), _hips_y, 0)
	hips_off = hips_off.lerp(Vector3(0, -0.47, 0.05), wsit)
	if _oneshot > 0.0 and _oneshot_state == State.CARRY:
		hips_off.y -= 0.12 * sin(clampf(_oneshot / _oneshot_len, 0.0, 1.0) * PI)
	if _air > 0.01:
		hips_off.y = lerpf(hips_off.y, 0.0, _air)
	model.pose_hips(hips_off)
	for i in r.size():
		model.pose(i, r[i])
