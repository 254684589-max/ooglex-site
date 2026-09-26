class_name EnemyRanged
extends EnemyBase
## 远程型（「骸骨弓手」）：和玩家保持 keep_min–keep_max 米；有视线时拉弓（0.5 秒前摇、弓上发光），
## 射出可以躲开的箭；玩家贴太近就后退。

func _build_visual() -> void:
	if def.get("look", "archer") == "cultist":
		# 邪教术士（V0.1）：灰紫长袍、兜帽，法杖顶端发光（最后一个部件 = 发光件，前摇时变亮）
		var robe := Color(0.24, 0.18, 0.3)
		part(cyl(0.18, 0.42, 1.5), Vector3(0, 0.75, 0), robe)
		part(sphere(0.22), Vector3(0, 1.62, 0), Color(0.2, 0.15, 0.26))
		part(sphere(0.04), Vector3(-0.06, 1.62, 0.19), Color(0.8, 0.5, 1.0), 3.0)
		part(sphere(0.04), Vector3(0.06, 1.62, 0.19), Color(0.8, 0.5, 1.0), 3.0)
		part(cyl(0.03, 0.03, 1.7), Vector3(0.36, 0.9, 0.2), Color(0.35, 0.25, 0.15))
		part(sphere(0.12), Vector3(0.36, 1.8, 0.2), Color(0.55, 0.3, 0.8))
		return
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
			if def.has("blink") and d < float(def.blink.trigger_dist) and cooldowns.get("blink", 0.0) <= 0.0 and _blink_away():
				cooldowns["blink"] = float(def.blink.cooldown_s)
				return
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
	Sfx.play("arrow" if s.get("kind", "arrow") == "arrow" else "bolt")
	var p := Projectile.new()
	p.attacker = attacker_stats(s.dmg)
	p.source = self
	p.kind = s.get("kind", "arrow")
	p.speed = s.speed
	p.max_range = s.range
	p.dir = (player.global_position - global_position).normalized()
	p.dir.y = 0.0
	p.dir = p.dir.normalized()
	get_parent().add_child(p)
	p.global_position = global_position + Vector3(0, 1.2, 0) + p.dir * 0.6


## 邪教术士（V0.1 blinkAway）：玩家贴太近时瞬移到 4.5–9 米外随机一个能站的位置
func _blink_away() -> bool:
	var b: Dictionary = def.blink
	var map := get_world_3d().navigation_map
	for k in 20:
		var a := rng.randf() * TAU
		var r := rng.randf_range(float(b.min_m), float(b.max_m))
		var cand := global_position + Vector3(cos(a), 0, sin(a)) * r
		var on_nav := NavigationServer3D.map_get_closest_point(map, cand)
		if Vector2(on_nav.x - cand.x, on_nav.z - cand.z).length() < 0.3:
			_puff()
			global_position = Vector3(cand.x, 0, cand.z)
			_puff()
			return true
	return false


func _puff() -> void:
	var s := MeshInstance3D.new()
	s.mesh = LowPoly.sphere(0.6)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.55, 0.3, 1.0, 0.6)
	s.material_override = m
	get_parent().add_child(s)
	s.global_position = global_position + Vector3(0, 1.0, 0)
	var tw := s.create_tween()
	tw.set_parallel(true)
	tw.tween_property(s, "scale", Vector3.ONE * 1.8, 0.3)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.3)
	tw.chain().tween_callback(s.queue_free)
