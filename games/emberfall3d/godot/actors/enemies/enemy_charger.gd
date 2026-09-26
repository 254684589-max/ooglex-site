class_name EnemyCharger
extends EnemyBase
## 冲锋型（「焦骨蛮兵」）：中距离时低头蓄力，地面出现红色长条预警，然后沿直线冲锋；
## 撞到玩家造成重击并击退，撞到墙会把自己撞晕（给玩家的反击窗口）。近身时普通挥击。

var charge_dir := Vector3.ZERO
var charge_from := Vector3.ZERO
var charge_hit := false


func _build_visual() -> void:
	var c := Color(0.18, 0.15, 0.13)
	part(box(Vector3(0.95, 1.0, 0.7)), Vector3(0, 1.0, 0), c)                          # 宽厚的躯干
	part(box(Vector3(1.0, 0.08, 0.72)), Vector3(0, 1.15, 0), Color(1.0, 0.45, 0.12), 2.5)  # 裂缝里的余烬光
	part(box(Vector3(0.9, 0.08, 0.72)), Vector3(0, 0.8, 0), Color(1.0, 0.45, 0.12), 2.0)
	part(sphere(0.26), Vector3(0, 1.7, 0.18), Color(0.24, 0.2, 0.17))
	part(box(Vector3(0.2, 0.2, 0.5)), Vector3(-0.2, 1.8, 0.38), Color(0.5, 0.45, 0.4), 0.0, Vector3(-20, 0, 0))  # 角
	part(box(Vector3(0.2, 0.2, 0.5)), Vector3(0.2, 1.8, 0.38), Color(0.5, 0.45, 0.4), 0.0, Vector3(-20, 0, 0))
	part(box(Vector3(0.3, 0.5, 0.3)), Vector3(-0.28, 0.25, 0), c)
	part(box(Vector3(0.3, 0.5, 0.3)), Vector3(0.28, 0.25, 0), c)


func _ai(delta: float) -> void:
	if leash_check() or notice_check():
		return
	var a: Dictionary = def.attack
	var ch: Dictionary = def.charge
	var d := dist_to_player()
	match state:
		"chase":
			if d <= a.range:
				face(player.global_position)
				mode = 0
				set_state("windup")
			elif d >= ch.min_dist and d <= ch.max_dist and cooldowns.get("charge", 0.0) <= 0.0 and has_los():
				face(player.global_position)
				charge_dir = forward()
				mode = 1
				show_warning("line", Vector2(1.2, ch.distance), global_position, rotation.y)
				set_state("windup")
			else:
				go_towards(player.global_position, def.speed, delta)
		"windup":
			if mode == 1:
				_update_warning(state_t / ch.windup_s)
				if state_t >= ch.windup_s:
					clear_warning()
					charge_from = global_position
					charge_hit = false
					cooldowns["charge"] = ch.cooldown_s
					set_state("act")
			elif state_t >= a.windup_s:
				melee_hit(a.dmg, a.range, a.arc_deg)
				set_state("recover")
		"act":
			# 冲锋中：沿锁定方向直线冲刺
			move_dir = charge_dir
			move_speed = ch.speed
			if not charge_hit and player_alive():
				var pd := player.global_position - global_position
				pd.y = 0.0
				if pd.length() < 1.1:
					charge_hit = true
					var r := DamageCalc.roll(attacker_stats(ch.dmg), 1.0, "physical", player.combat_target(), rng)
					player.take_hit(r, charge_dir, ch.knockback_m)
			var travelled := Vector2(global_position.x - charge_from.x, global_position.z - charge_from.z).length()
			if travelled >= ch.distance or state_t > ch.distance / ch.speed + 0.3:
				set_state("recover")
			elif _hit_wall():
				stun_t = ch.wall_stun_s     # 撞墙：自己被撞晕
				set_state("recover")
		"recover":
			var need: float = a.recover_s if mode == 0 else ch.recover_s
			if state_t >= need:
				set_state("chase")


func _hit_wall() -> bool:
	for i in get_slide_collision_count():
		var col := get_slide_collision(i).get_collider()
		if col is StaticBody3D and (col.collision_layer & Layers.WORLD) != 0 and state_t > 0.08:
			return true
	return false
