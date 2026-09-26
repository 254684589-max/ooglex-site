class_name EnemySummoner
extends EnemyBase
## 召唤型（「灰誓祭司」）：保持距离；每隔 cooldown_s 秒吟唱 1 秒（地面出现两个红圈），
## 在红圈处召唤「腐尸」。同时存活的仆从有上限。近身时用法杖打一下然后后退。

var minions: Array = []
var summon_spots: Array[Vector3] = []


func _build_visual() -> void:
	part(cyl(0.12, 0.5, 1.6), Vector3(0, 0.8, 0), Color(0.27, 0.24, 0.24))            # 灰袍
	part(cyl(0.2, 0.26, 0.4), Vector3(0, 1.75, 0), Color(0.2, 0.18, 0.18))           # 兜帽
	part(box(Vector3(0.06, 1.9, 0.06)), Vector3(0.42, 0.95, 0.1), Color(0.35, 0.25, 0.15))  # 法杖
	part(sphere(0.12), Vector3(0.42, 1.95, 0.1), Color(0.69, 0.42, 1.0), 3.0)          # 虚之光


func _ai(delta: float) -> void:
	if leash_check() or notice_check():
		return
	var sm: Dictionary = def.summon
	var a: Dictionary = def.attack
	var d := dist_to_player()
	minions = minions.filter(func(m): return is_instance_valid(m) and not m.dead)
	match state:
		"chase":
			if d <= a.range:
				face(player.global_position)
				mode = 0
				set_state("windup")
			elif cooldowns.get("summon", 0.0) <= 0.0 and minions.size() < sm.cap and has_los():
				mode = 1
				summon_spots = _pick_spots(sm.count)
				for i in summon_spots.size():
					show_warning("circle", Vector2(0.8, 0), summon_spots[i], 0.0, i > 0)
				set_state("windup")
			elif d < def.keep_min:
				var away := global_position - player.global_position
				away.y = 0.0
				move_dir = away.normalized()
				move_speed = def.speed
			elif d > def.keep_max or not has_los():
				go_towards(player.global_position, def.speed, delta)
			else:
				face(player.global_position)
		"windup":
			if mode == 1:
				_update_warning(state_t / sm.windup_s)
				if state_t >= sm.windup_s:
					clear_warning()
					_summon()
					cooldowns["summon"] = sm.cooldown_s
					set_state("recover")
			elif state_t >= a.windup_s:
				melee_hit(a.dmg, a.range, a.arc_deg)
				set_state("recover")
		"recover":
			if state_t >= a.recover_s:
				set_state("chase")


func _pick_spots(n: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var map := get_world_3d().navigation_map
	var toward := (player.global_position - global_position).normalized()
	for i in n:
		var side := Vector3(-toward.z, 0, toward.x) * (1.6 if i % 2 == 0 else -1.6)
		var p := global_position + toward * 1.8 + side
		out.append(NavigationServer3D.map_get_closest_point(map, p))
	return out


func _summon() -> void:
	for p in summon_spots:
		var m := Monsters.spawn(def.summon.minion, get_parent(), p, player)
		m.set_state("chase")
		minions.append(m)
