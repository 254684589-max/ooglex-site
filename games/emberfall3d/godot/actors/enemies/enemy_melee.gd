class_name EnemyMelee
extends EnemyBase
## 近战追击型（「腐尸」等）：发现玩家后追上去，进入攻击距离后前摇 → 挥击 → 收招。

func _build_visual() -> void:
	## 造型按 look 区分（P5：V0.1 的腐尸、骸骨战士、火坑小鬼、食尸鬼、熔渊猎犬、堕落骑士）；人形的都是骨骼角色，火坑小鬼、熔渊猎犬仍是占位几何体
	match def.get("look", "zombie"):
		"skel":
			use_rig("skeleton")      # 2.6 之三：代码搭的骸骨战士（锈剑、破圆盾、锈肩甲）
		"imp":
			var red := Color(0.62, 0.16, 0.08)
			part(sphere(0.3), Vector3(0, 0.55, 0), red, 0.4)
			part(sphere(0.2), Vector3(0, 0.95, 0.08), Color(0.7, 0.2, 0.1), 0.4)
			part(cyl(0.0, 0.06, 0.25), Vector3(-0.12, 1.15, 0.05), Color(0.2, 0.1, 0.08), 0.0, Vector3(0, 0, 20))
			part(cyl(0.0, 0.06, 0.25), Vector3(0.12, 1.15, 0.05), Color(0.2, 0.1, 0.08), 0.0, Vector3(0, 0, -20))
			part(sphere(0.05), Vector3(-0.07, 1.0, 0.25), Color(1.0, 0.8, 0.2), 4.0)
			part(sphere(0.05), Vector3(0.07, 1.0, 0.25), Color(1.0, 0.8, 0.2), 4.0)
		"ghoul":
			use_rig("ghoul", "claw")      # 2.6 之三：佝偻、长爪、背上骨刺
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
			use_rig("knight")             # 2.6 之三：板甲、红光眼缝、双手大剑
		_:
			use_rig("zombie", "claw")     # 2.6 之三：焦黑干裂的腐尸，双臂前伸，抓挠


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
