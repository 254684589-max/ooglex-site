class_name EnemyMelee
extends EnemyBase
## 近战追击型（「腐尸」等）：发现玩家后追上去，进入攻击距离后前摇 → 挥击 → 收招。

func _build_visual() -> void:
	## 占位造型按 look 区分（P5：V0.1 的腐尸、骸骨战士、火坑小鬼、食尸鬼、熔渊猎犬、堕落骑士）
	match def.get("look", "zombie"):
		"skel":
			var bone := Color(0.8, 0.76, 0.66)
			part(cyl(0.13, 0.17, 1.05), Vector3(0, 0.95, 0), bone)
			part(sphere(0.21), Vector3(0, 1.66, 0), Color(0.86, 0.83, 0.74))
			part(sphere(0.045), Vector3(-0.07, 1.68, 0.18), Color(0.4, 0.8, 1.0), 3.0)
			part(sphere(0.045), Vector3(0.07, 1.68, 0.18), Color(0.4, 0.8, 1.0), 3.0)
			part(box(Vector3(0.08, 0.62, 0.08)), Vector3(-0.1, 0.3, 0), bone)
			part(box(Vector3(0.08, 0.62, 0.08)), Vector3(0.1, 0.3, 0), bone)
			part(box(Vector3(0.06, 0.8, 0.12)), Vector3(0.32, 1.1, 0.3), Color(0.6, 0.6, 0.62), 0.0, Vector3(60, 0, 0))   # 锈剑
		"imp":
			var red := Color(0.62, 0.16, 0.08)
			part(sphere(0.3), Vector3(0, 0.55, 0), red, 0.4)
			part(sphere(0.2), Vector3(0, 0.95, 0.08), Color(0.7, 0.2, 0.1), 0.4)
			part(cyl(0.0, 0.06, 0.25), Vector3(-0.12, 1.15, 0.05), Color(0.2, 0.1, 0.08), 0.0, Vector3(0, 0, 20))
			part(cyl(0.0, 0.06, 0.25), Vector3(0.12, 1.15, 0.05), Color(0.2, 0.1, 0.08), 0.0, Vector3(0, 0, -20))
			part(sphere(0.05), Vector3(-0.07, 1.0, 0.25), Color(1.0, 0.8, 0.2), 4.0)
			part(sphere(0.05), Vector3(0.07, 1.0, 0.25), Color(1.0, 0.8, 0.2), 4.0)
		"ghoul":
			var g := Color(0.3, 0.34, 0.28)
			part(cyl(0.34, 0.4, 1.35), Vector3(0, 0.8, 0.12), g, 0.0, Vector3(28, 0, 0))
			part(sphere(0.25), Vector3(0, 1.4, 0.48), Color(0.36, 0.4, 0.32))
			part(box(Vector3(0.14, 0.9, 0.14)), Vector3(-0.42, 0.8, 0.4), g, 0.0, Vector3(40, 0, 0))
			part(box(Vector3(0.14, 0.9, 0.14)), Vector3(0.42, 0.8, 0.4), g, 0.0, Vector3(40, 0, 0))
			part(sphere(0.05), Vector3(-0.09, 1.44, 0.7), Color(0.7, 1.0, 0.3), 3.0)
			part(sphere(0.05), Vector3(0.09, 1.44, 0.7), Color(0.7, 1.0, 0.3), 3.0)
		"hound":
			var h := Color(0.28, 0.12, 0.08)
			part(box(Vector3(0.45, 0.4, 1.1)), Vector3(0, 0.6, 0), h)
			part(box(Vector3(0.34, 0.32, 0.4)), Vector3(0, 0.78, 0.66), Color(0.34, 0.14, 0.09))
			for x in [-0.16, 0.16]:
				for z in [-0.38, 0.38]:
					part(box(Vector3(0.1, 0.42, 0.1)), Vector3(x, 0.21, z), h)
			part(box(Vector3(0.12, 0.08, 0.55)), Vector3(0, 0.72, 0), Color(1.0, 0.45, 0.1), 2.5)    # 背上的熔火裂纹
			part(sphere(0.045), Vector3(-0.08, 0.84, 0.86), Color(1.0, 0.7, 0.2), 4.0)
			part(sphere(0.045), Vector3(0.08, 0.84, 0.86), Color(1.0, 0.7, 0.2), 4.0)
		"knight":
			var steel := Color(0.3, 0.3, 0.34)
			part(cyl(0.3, 0.36, 1.3), Vector3(0, 0.85, 0), steel)
			part(box(Vector3(0.78, 0.22, 0.4)), Vector3(0, 1.45, 0), Color(0.35, 0.33, 0.38))       # 肩甲
			part(cyl(0.2, 0.22, 0.34), Vector3(0, 1.78, 0), Color(0.26, 0.26, 0.3))                 # 头盔
			part(box(Vector3(0.24, 0.05, 0.05)), Vector3(0, 1.8, 0.2), Color(1.0, 0.3, 0.15), 3.0)  # 盔缝里的红光
			part(box(Vector3(0.1, 1.3, 0.2)), Vector3(0.45, 1.1, 0.35), Color(0.45, 0.42, 0.46), 0.0, Vector3(55, 0, 0))
		_:
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
