class_name EnemyBossMog
extends EnemyBase
## 首领「腐肉监工 · 莫格」（P9，移植 V0.1 bossAI 的 mog 分支）：第 3 层首领房。
##   近战重击；每 6 秒一次冲锋（3.75–12 米、有视线时）：V0.1 是立刻冲，3D 版先亮 0.35 秒红色长条预警再冲，
##   冲锋速度 = 移动速度 × 3.2、持续 0.6 秒，撞到主角造成 伤害上限 × 1.4；
##   生命低于一半时暴怒：移动速度 × 1.35、攻击间隔 × 0.7。
## 外观（2.6 之三）：代码搭的骨骼角色（CharModels.mog）：佝偻的巨汉，铁栅面罩，背上铁笼里关着托比，腰间拖铁链，右手铁链连枷；
## 冲锋时低头弓背，暴怒时全身涨红、眼睛更亮。

signal shouted(text: String)
signal enraged_now

var enraged := false
var rush_dir := Vector3.ZERO
var rush_hit := false
var _shouted := false


func _ready() -> void:
	super._ready()
	cooldowns["rush"] = float(def.rush.first_s)


func _build_visual() -> void:
	use_rig("mog")


func _rig_pose() -> void:
	## 冲锋（mode 1）：预警时低头弓背、双臂后摆，冲刺中保持，收招时直起身；近身重击走通用的挥砍姿势（抡连枷）
	if mode != 1 or stun_t > 0.0:
		super()
		return
	match state:
		"windup":
			rig.act("charge", "windup", state_t / maxf(float(def.rush.windup_s), 0.01))
		"act":
			rig.act("charge", "windup", 1.0)
		"recover":
			rig.act("charge", "recover", state_t / 0.4)

func _ai(delta: float) -> void:
	if leash_check():
		return
	if notice_check():
		return
	if not _shouted:
		_shouted = true
		shouted.emit(def.shout)
	var a: Dictionary = def.attack
	var R: Dictionary = def.rush
	var E: Dictionary = def.enrage
	if not enraged and hp < max_hp * float(E.hp_frac):
		enraged = true
		enraged_now.emit()
		rig.base_tint = Color(1.35, 0.72, 0.66)      # 暴怒：身体涨红、眼睛更亮
		rig.set_tint(false, false)
		_rig_tint = -1
		if rig.glow_material:
			rig.glow_material.emission_energy_multiplier = 7.0
	var spd: float = float(def.speed) * (float(E.speed_mul) if enraged else 1.0)
	var cdm: float = float(E.cd_mul) if enraged else 1.0
	var d := dist_to_player()
	match state:
		"chase":
			if d >= float(R.min_dist) and d <= float(R.max_dist) and cooldowns.get("rush", 0.0) <= 0.0 and has_los(true):
				face(player.global_position)
				rush_dir = forward()
				mode = 1
				show_warning("line", Vector2(float(R.width), spd * float(R.speed_mul) * float(R.duration_s)), global_position, rotation.y)
				set_state("windup")
			elif d <= float(a.range):
				face(player.global_position)
				mode = 0
				set_state("windup")
			else:
				go_towards(player.global_position, spd, delta)
		"windup":
			if mode == 1:
				_update_warning(state_t / float(R.windup_s))
				if state_t >= float(R.windup_s):
					clear_warning()
					rush_hit = false
					cooldowns["rush"] = float(R.cooldown_s)
					set_state("act")
			elif state_t >= float(a.windup_s):
				melee_hit(a.dmg, a.range, a.arc_deg)
				set_state("recover")
		"act":
			# 冲锋：沿锁定方向直冲（V0.1 charge），撞到主角一次重击
			move_dir = rush_dir
			move_speed = spd * float(R.speed_mul)
			if not rush_hit and player_alive():
				var pd := player.global_position - global_position
				pd.y = 0.0
				if pd.length() < float(def.radius) + 0.6:
					rush_hit = true
					var hi: int = roundi(float(def.attack.dmg[1]) * float(R.dmg_mul))
					var r := DamageCalc.roll(attacker_stats([hi, hi]), 1.0, "physical", player.combat_target(), rng)
					player.take_hit(r, rush_dir, 1.2)
					if player.get("camera"):
						player.camera.add_trauma(0.6)
			if state_t >= float(R.duration_s):
				mode = 1
				set_state("recover")
		"recover":
			var need: float = (float(a.recover_s) if mode == 0 else 0.4) * cdm
			if state_t >= need:
				set_state("chase")
