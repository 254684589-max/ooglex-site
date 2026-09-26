class_name EnemyRanged
extends EnemyBase
## 远程型（「骸骨弓手」）：和玩家保持 keep_min–keep_max 米；有视线时拉弓（0.5 秒前摇、弓上发光），
## 射出可以躲开的箭；玩家贴太近就后退。

func _build_visual() -> void:
	var bone := Color(0.78, 0.74, 0.64)
	part(cyl(0.12, 0.16, 1.1), Vector3(0, 0.95, 0), bone)
	part(sphere(0.2), Vector3(0, 1.65, 0), Color(0.85, 0.82, 0.72))
	part(box(Vector3(0.5, 0.08, 0.08)), Vector3(0, 1.3, 0), bone)
	part(box(Vector3(0.08, 0.6, 0.08)), Vector3(-0.1, 0.3, 0), bone)
	part(box(Vector3(0.08, 0.6, 0.08)), Vector3(0.1, 0.3, 0), bone)
	var bow := LowPoly.torus(0.42, 0.47)
	part(bow, Vector3(0.3, 1.25, 0.3), Color(0.45, 0.3, 0.16), 0.0, Vector3(0, 0, 90))


func _ai(delta: float) -> void:
	if leash_check() or notice_check():
		return
	var s: Dictionary = def.shot
	var d := dist_to_player()
	match state:
		"chase":
			var los := has_los()
			if d < def.keep_min:
				# 太近了：背对玩家后退
				var away := global_position - player.global_position
				away.y = 0.0
				move_dir = away.normalized()
				move_speed = def.speed
			elif d > def.keep_max or not los:
				go_towards(player.global_position, def.speed, delta)
			elif cooldowns.get("shot", 0.0) <= 0.0:
				face(player.global_position)
				set_state("windup")
		"windup":
			face(player.global_position)
			_mats[_mats.size() - 1].emission_enabled = true
			_mats[_mats.size() - 1].emission = Color(1.0, 0.3, 0.2)
			_mats[_mats.size() - 1].emission_energy_multiplier = 2.0 * state_t / s.windup_s
			if state_t >= s.windup_s:
				_mats[_mats.size() - 1].emission_enabled = false
				_shoot()
				cooldowns["shot"] = s.cooldown_s
				set_state("recover")
		"recover":
			if state_t >= s.recover_s:
				set_state("chase")


func _shoot() -> void:
	var s: Dictionary = def.shot
	var p := Projectile.new()
	p.attacker = attacker_stats(s.dmg)
	p.speed = s.speed
	p.max_range = s.range
	p.dir = (player.global_position - global_position).normalized()
	p.dir.y = 0.0
	p.dir = p.dir.normalized()
	get_parent().add_child(p)
	p.global_position = global_position + Vector3(0, 1.2, 0) + p.dir * 0.6
