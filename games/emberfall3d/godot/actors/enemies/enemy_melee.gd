class_name EnemyMelee
extends EnemyBase
## 近战追击型（「腐尸」等）：发现玩家后追上去，进入攻击距离后前摇 → 挥击 → 收招。

func _build_visual() -> void:
	var c := Color(0.22, 0.2, 0.17)
	part(cyl(0.28, 0.34, 1.3), Vector3(0, 0.75, 0.08), c, 0.0, Vector3(18, 0, 0))   # 佝偻的身体
	part(sphere(0.22), Vector3(0, 1.45, 0.32), Color(0.28, 0.25, 0.2))
	part(sphere(0.05), Vector3(-0.08, 1.48, 0.52), Color(1.0, 0.5, 0.15), 3.0)        # 余烬眼
	part(sphere(0.05), Vector3(0.08, 1.48, 0.52), Color(1.0, 0.5, 0.15), 3.0)
	part(box(Vector3(0.12, 0.7, 0.12)), Vector3(-0.35, 1.0, 0.35), c, 0.0, Vector3(70, 0, 0))
	part(box(Vector3(0.12, 0.7, 0.12)), Vector3(0.35, 1.0, 0.35), c, 0.0, Vector3(70, 0, 0))


func _ai(delta: float) -> void:
	if leash_check() or notice_check():
		return
	var a: Dictionary = def.attack
	match state:
		"chase":
			if dist_to_player() <= a.range:
				face(player.global_position)
				set_state("windup")
			else:
				go_towards(player.global_position, def.speed, delta)
		"windup":
			if state_t >= a.windup_s:
				melee_hit(a.dmg, a.range, a.arc_deg)
				set_state("recover")
		"recover":
			if state_t >= a.recover_s:
				set_state("chase")
