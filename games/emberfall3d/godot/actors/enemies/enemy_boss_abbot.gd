class_name EnemyBossAbbot
extends EnemyBase
## 首领「堕落院长 · 摩登」（P9，移植 V0.1 bossAI 的摩登分支）：第 6 层封印大厅。
##   邪术弹：一次 3 发扇形（二阶段 5 发），间隔 2.3 秒（二阶段 1.6 秒）；
##   烈焰新星：每 10 秒（二阶段 6 秒）从脚下扩散一圈火环，伤害 = 伤害上限 × 1.2；
##   召唤：每 13 秒在身边召唤 2 只骸骨战士（二阶段火坑小鬼），场上仆从最多 8 只；
##   被贴近（3.6 米内）瞬移走，只在首领房里落脚；离主角 9 米以上或没有视线就追，5.25 米以内往后退。
##   生命低于一半进入二阶段：改名「灰烬之王的容器 · 摩登」，体型变大、移动速度 × 1.2，并爆出一圈火环。
## 占位造型：高瘦的院长长袍、高冠与法杖，胸口一枚发光的「余烬之心」（二阶段变亮变大）。

signal shouted(text: String)
signal phase_changed(phase: int)

var phase := 1
var arena := Rect2()             # 首领房（世界坐标 x / z）：瞬移只在房里落脚（V0.1 inRoom）
var minions: Array = []
var _shouted := false
var _heart: MeshInstance3D


func _ready() -> void:
	super._ready()
	cooldowns["shot"] = float(def.shot.first_s)
	cooldowns["nova"] = float(def.nova.first_s)
	cooldowns["summon"] = float(def.summon.first_s)


func _build_visual() -> void:
	var robe := Color(0.36, 0.08, 0.08)
	var gold := Color(0.7, 0.55, 0.25)
	part(cyl(0.22, 0.55, 1.9), Vector3(0, 0.95, 0), robe)                                 # 长袍
	part(cyl(0.3, 0.3, 0.12), Vector3(0, 1.9, 0), gold)                                   # 金色披肩
	part(sphere(0.22), Vector3(0, 2.12, 0.02), Color(0.62, 0.55, 0.5))                   # 枯瘦的脸
	part(cyl(0.08, 0.2, 0.5), Vector3(0, 2.5, -0.02), Color(0.9, 0.86, 0.78))           # 高冠
	part(box(Vector3(0.05, 0.3, 0.05)), Vector3(0, 2.45, 0.17), gold, 1.0)
	part(cyl(0.03, 0.03, 2.3), Vector3(0.5, 1.15, 0.2), Color(0.3, 0.22, 0.14))          # 法杖
	part(LowPoly.torus(0.12, 0.16), Vector3(0.5, 2.35, 0.2), gold, 0.0, Vector3(90, 0, 0))
	_heart = part(sphere(0.13), Vector3(0, 1.55, 0.28), Color(1.0, 0.5, 0.15), 3.0)       # 胸口的余烬之心
	# 最后一个部件放发光的杖头：施法时变亮
	part(sphere(0.1), Vector3(0.5, 2.35, 0.2), Color(1.0, 0.45, 0.2), 2.0)


func _ai(delta: float) -> void:
	if leash_check():
		return
	if notice_check():
		return
	if not _shouted:
		_shouted = true
		shouted.emit(def.shout)
	var P2: Dictionary = def.phase2
	if phase == 1 and hp < max_hp * float(P2.hp_frac):
		_enter_phase2()
	var ph := phase - 1
	var spd: float = float(def.speed) * (float(P2.speed_mul) if phase == 2 else 1.0)
	var d := dist_to_player()
	var los := has_los()
	minions = minions.filter(func(m): return is_instance_valid(m) and not m.dead)
	face(player.global_position)
	# 邪术弹扇形
	if cooldowns.get("shot", 0.0) <= 0.0 and los:
		var n: int = int(def.shot.count[ph])
		for i in n:
			_shoot((i - (n - 1) / 2.0) * float(def.shot.spread_rad))
		cooldowns["shot"] = float(def.shot.cooldown_s[ph])
	# 烈焰新星
	if cooldowns.get("nova", 0.0) <= 0.0:
		_ring(float(def.nova.radius), float(def.nova.speed), float(def.nova.dmg_mul))
		cooldowns["nova"] = float(def.nova.cooldown_s[ph])
	# 召唤仆从
	if cooldowns.get("summon", 0.0) <= 0.0:
		if _adds_alive() < int(def.summon.cap):
			_summon(def.summon.minion[ph])
		cooldowns["summon"] = float(def.summon.cooldown_s)
	# 被贴近：瞬移走
	if d < float(def.blink.trigger_dist) and cooldowns.get("blink", 0.0) <= 0.0:
		cooldowns["blink"] = float(def.blink.cooldown_s)
		if _blink_away():
			return
	if d > float(def.chase_beyond) or not los:
		go_towards(player.global_position, spd, delta)
	elif d < float(def.back_within):
		var away := global_position - player.global_position
		away.y = 0.0
		move_dir = away.normalized()
		move_speed = spd * float(def.back_speed_mul)


func _enter_phase2() -> void:
	var P2: Dictionary = def.phase2
	phase = 2
	def.name = P2.name
	visual.scale = Vector3.ONE * float(P2.scale)
	_heart.scale = Vector3.ONE * 1.8
	(_heart.material_override as StandardMaterial3D).emission_energy_multiplier = 6.0
	update_label()
	_ring(float(P2.ring_radius), float(P2.ring_speed), float(P2.ring_dmg_mul))
	if player.get("camera"):
		player.camera.add_trauma(0.8)
	phase_changed.emit(2)


func _adds_alive() -> int:
	var n := 0
	for e in enemies_this_frame():
		if is_instance_valid(e) and not e.dead and e != self and e.def.has("aggro"):
			n += 1
	return n


func _shoot(ang: float) -> void:
	var s: Dictionary = def.shot
	var p := Projectile.new()
	p.attacker = attacker_stats(s.dmg)
	p.source = self
	p.kind = "bolt"
	p.tint = Color(1.0, 0.45, 0.12)
	p.speed = float(s.speed)
	p.max_range = float(s.range)
	var dir := player.global_position - global_position
	dir.y = 0.0
	p.dir = dir.normalized().rotated(Vector3.UP, ang)
	get_parent().add_child(p)
	p.global_position = global_position + Vector3(0, 1.4, 0) + p.dir * 0.8


func _ring(radius: float, speed: float, mul: float) -> void:
	var r := NovaRing.new()
	var hi: int = roundi(float(def.shot.dmg[1]) * mul)
	r.attacker = attacker_stats([hi, hi])
	r.player = player
	r.max_radius = radius
	r.speed = speed
	get_parent().add_child(r)
	r.global_position = Vector3(global_position.x, 0, global_position.z)


func _summon(key: String) -> void:
	var map := get_world_3d().navigation_map
	for i in int(def.summon.count):
		var p := global_position + Vector3(rng.randf_range(-3.0, 3.0), 0, rng.randf_range(-3.0, 3.0))
		p = NavigationServer3D.map_get_closest_point(map, p)
		var m := Monsters.spawn(key, get_parent(), Vector3(p.x, 0, p.z), player, def.get("floor", 1))
		m.set_state("chase")
		minions.append(m)
		_puff(m.global_position)


## 瞬移（V0.1 blinkAway）：4.5–9 米外随机一处能站、且在首领房里的位置
func _blink_away() -> bool:
	var b: Dictionary = def.blink
	var map := get_world_3d().navigation_map
	for k in 20:
		var a := rng.randf() * TAU
		var cand := global_position + Vector3(cos(a), 0, sin(a)) * rng.randf_range(float(b.min_m), float(b.max_m))
		if arena.has_area() and not arena.grow(-0.6).has_point(Vector2(cand.x, cand.z)):
			continue
		var on_nav := NavigationServer3D.map_get_closest_point(map, cand)
		if Vector2(on_nav.x - cand.x, on_nav.z - cand.z).length() < 0.3:
			_puff(global_position)
			global_position = Vector3(cand.x, 0, cand.z)
			_puff(global_position)
			return true
	return false


func _puff(at: Vector3) -> void:
	var s := MeshInstance3D.new()
	s.mesh = LowPoly.sphere(0.7)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.55, 0.3, 1.0, 0.6)
	s.material_override = m
	get_parent().add_child(s)
	s.global_position = at + Vector3(0, 1.0, 0)
	var tw := s.create_tween()
	tw.set_parallel(true)
	tw.tween_property(s, "scale", Vector3.ONE * 1.8, 0.3)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.3)
	tw.chain().tween_callback(s.queue_free)
