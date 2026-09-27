class_name EnemyMelee
extends EnemyBase
## 近战追击型（「腐尸」等）：发现玩家后追上去，进入攻击距离后前摇 → 挥击 → 收招。

func _build_visual() -> void:
	## 造型按 look 区分（P5：V0.1 的腐尸、骸骨战士、火坑小鬼、食尸鬼、熔渊猎犬、堕落骑士）；全部是骨骼角色（熔渊猎犬用四足骨架）
	match def.get("look", "zombie"):
		"skel":
			use_rig("skeleton")      # 2.6 之三：代码搭的骸骨战士（锈剑、破圆盾、锈肩甲）
		"imp":
			use_rig("imp", "claw")        # 2.6 之三：大脑袋、肚子里烧着余烬的小鬼
		"ghoul":
			use_rig("ghoul", "claw")      # 2.6 之三：佝偻、长爪、背上骨刺
		"hound":
			use_rig("hound", "bite")      # 2.6 之三：四足骨架，小跑、扑咬
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
