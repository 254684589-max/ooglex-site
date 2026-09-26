class_name EnemyBossMog
extends EnemyBase
## 首领「腐肉监工 · 莫格」（P9，移植 V0.1 bossAI 的 mog 分支）：第 3 层首领房。
##   近战重击；每 6 秒一次冲锋（3.75–12 米、有视线时）：V0.1 是立刻冲，3D 版先亮 0.35 秒红色长条预警再冲，
##   冲锋速度 = 移动速度 × 3.2、持续 0.6 秒，撞到主角造成 伤害上限 × 1.4；
##   生命低于一半时暴怒：移动速度 × 1.35、攻击间隔 × 0.7。
## 占位造型：佝偻的巨汉，背上一只铁笼（托比被关在里面）、腰间拖着铁链。

signal shouted(text: String)
signal enraged_now

var enraged := false
var rush_dir := Vector3.ZERO
var rush_hit := false
var _cage_boy: Node3D
var _shouted := false


func _ready() -> void:
	super._ready()
	cooldowns["rush"] = float(def.rush.first_s)


func _build_visual() -> void:
	var flesh := Color(0.42, 0.3, 0.26)
	var leather := Color(0.24, 0.16, 0.1)
	var iron := Color(0.3, 0.29, 0.3)
	part(cyl(0.55, 0.62, 1.5), Vector3(0, 1.05, 0.05), flesh, 0.0, Vector3(14, 0, 0))     # 臃肿的身体
	part(cyl(0.64, 0.64, 0.35), Vector3(0, 0.62, 0.02), leather)                           # 皮围腰
	part(sphere(0.3), Vector3(0, 2.0, 0.42), Color(0.46, 0.33, 0.28))                      # 往前探的头
	part(box(Vector3(0.44, 0.2, 0.3)), Vector3(0, 2.02, 0.58), iron)                       # 铁面罩
	part(sphere(0.05), Vector3(-0.1, 2.06, 0.74), Color(1.0, 0.4, 0.15), 4.0)
	part(sphere(0.05), Vector3(0.1, 2.06, 0.74), Color(1.0, 0.4, 0.15), 4.0)
	part(box(Vector3(0.26, 1.1, 0.26)), Vector3(-0.7, 1.15, 0.35), flesh, 0.0, Vector3(35, 0, 10))   # 两条粗胳膊
	part(box(Vector3(0.26, 1.1, 0.26)), Vector3(0.7, 1.15, 0.35), flesh, 0.0, Vector3(35, 0, -10))
	part(box(Vector3(0.5, 0.5, 0.18)), Vector3(0.8, 0.6, 0.85), iron, 0.0, Vector3(20, 0, 0))        # 右手的屠刀
	part(box(Vector3(0.34, 0.7, 0.34)), Vector3(-0.3, 0.3, 0), leather)
	part(box(Vector3(0.34, 0.7, 0.34)), Vector3(0.3, 0.3, 0), leather)
	# 背上的铁笼：四根立柱 + 顶底框，笼里缩着一个小人（托比）
	var cage := Vector3(0, 1.95, -0.55)
	for x in [-0.32, 0.32]:
		for z in [-0.28, 0.28]:
			part(box(Vector3(0.05, 0.8, 0.05)), cage + Vector3(x, 0, z), iron)
	part(box(Vector3(0.72, 0.06, 0.64)), cage + Vector3(0, 0.4, 0), iron)
	part(box(Vector3(0.72, 0.06, 0.64)), cage + Vector3(0, -0.4, 0), iron)
	_cage_boy = part(sphere(0.16), cage + Vector3(0, -0.12, 0), Color(0.78, 0.62, 0.5))
	# 腰间拖地的铁链
	for i in 5:
		part(LowPoly.torus(0.07, 0.1), Vector3(0.45 + i * 0.05, 0.6 - i * 0.13, -0.2 - i * 0.12), iron, 0.0, Vector3(90 * (i % 2), 0, 0))


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
		_base_colors[0] = Color(0.62, 0.2, 0.14)     # 暴怒：身体涨红
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
