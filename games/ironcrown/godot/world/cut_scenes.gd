class_name CutScenes
extends RefCounted
## 各处的过场镜头脚本（路线图 C.5；播放器在 core/cutscene.gd）。每个过场一个静态函数：按场景里的东西现算机位，返回镜头列表。
## 没有配音：每段过场开头换一首配乐（data/music.json），字幕写谁说的、说什么；旁白（谁 = ""）居中。
##   prologue       开场（新游戏、选完出身以后）：从夜空摇下来，掠过霜渡镇的屋顶和街灯，停在领主宅邸门口的你身上——
##                  旁白交代这个世界：老王暴毙、铁冠失踪、冬天不走、五个家族争摄政、烽燧熄灭。之后接原来的钟声和管家喊人。
##   norbert_vial   第五章北上，第十九烽塔顶：诺伯特把三十五年前那只空誓瓶交给你（第一次和他说话时演，台词同 winter.json norbert5，
##                  演完给誓瓶、主线到 well，再从对话的 come 那一句接着说）。

const IDS := ["prologue", "norbert_vial"]


## 这段对话开始前要不要先演一段过场：{cut, after: Callable（演完做的事）, node: 演完从对话哪一句接着说}；不用就 {}
static func before_dialogue(dialogue_id: String) -> Dictionary:
	if dialogue_id == "norbert5" and GameState.quest_stage("ch5_main") == "vial" and not GameState.has_item("oath_vial") and not GameState.has_flag("ch5_cut_vial"):
		return {"cut": "norbert_vial", "node": "come", "after": func():
			GameState.set_flag("ch5_cut_vial")
			GameState.add_item("oath_vial")
			GameState.set_flag("ch5_vial", "norbert")
			Winter5.got_vial()}
	return {}


## 这个过场现在能不能播（场景里该有的东西都在）
static func available(main: Node, id: String) -> bool:
	match id:
		"prologue":
			return main.world != null and main.area == "frostford"
		"norbert_vial":
			return main.world != null and main.world.find_child("Npc_norbert5", true, false) != null
	return false


static func shots(main: Node, id: String) -> Array:
	match id:
		"prologue":
			return prologue(main)
		"norbert_vial":
			return norbert_vial(main)
	return []


## 开场：夜空 → 屋顶 → 街灯 → 宅邸门口的你。霜渡镇的主街南北走向（南门 z ≈ 11，宅邸在北头 z ≈ -46），你站在宅邸门口（0, -44.3）面朝南
static func prologue(main: Node) -> Array:
	var p: FpController = main.player
	return [
		{"from": [Vector3(0, 46, 34), Vector3(0, 30, -30)], "to": [Vector3(0, 30, 26), Vector3(0, 6, -18)], "dur": 7.0, "fov": 55.0, "music": "night",
			"lines": [[0.8, "", "冠历六四三年秋，老王奥雷利安三世在冠城暴毙。"], [4.0, "", "守灵夜里，铁冠不见了。"]],
			"on_start": func(): p.set_third_person(true)},
		{"from": [Vector3(7.5, 9.5, 9.0), Vector3(0, 2.5, -18)], "to": [Vector3(6.0, 7.5, -14.0), Vector3(-1.0, 2.0, -36)], "dur": 7.0, "fov": 50.0,
			"lines": [[0.6, "", "三年过去，王位空着。"], [3.4, "", "没有加冕的冬天，一年比一年长。"]]},
		{"from": [Vector3(-3.2, 1.5, -6.0), Vector3(0.5, 1.6, -30)], "to": [Vector3(-2.4, 1.7, -22.0), Vector3(0.5, 2.0, -42)], "dur": 6.5, "fov": 46.0,
			"lines": [[0.5, "", "五个家族在冠城争摄政；"], [3.0, "", "北方烽燧线上的火，一座接一座熄灭。"]]},
		{"from": [Vector3(3.8, 2.6, -33.0), Vector3(0, 2.0, -46)], "to": [Vector3(1.4, 1.9, -39.0), Vector3(0, 1.6, -44.3)], "dur": 6.5, "fov": 44.0,
			"lines": [[0.5, "", "霜渡镇，灰鲸河上的一个渡口。"], [3.2, "", "今夜，镇上的钟要响了。"]]},
	]


## 塔顶交瓶：远景推近塔顶的火 → 越过你的肩膀看他 → 他的近景（火光在脸上） → 瓶子的特写 → 拉远升高、两个人和整座塔、淡出
static func norbert_vial(main: Node) -> Array:
	var nb := main.world.find_child("Npc_norbert5", true, false) as Npc
	var tp := HighlandBeacon.tower_place()
	var th := HighlandLayout.TOWER_H
	var L := func(x: float, y: float, z: float) -> Vector3: return tp * Vector3(x, th + y, z)      # 塔顶本地坐标 → 世界
	var head: Vector3 = nb.global_position + Vector3(0, 1.55, 0)
	# 你站在他对面（火盆的另一侧偏一点），面朝他
	var you: Vector3 = L.call(0.9, 0.0, 0.9)
	var p: FpController = main.player
	var vial := _vial()
	return [
		{"from": [L.call(20.0, -1.0, 18.0), L.call(0.0, 1.0, 0.0)], "to": [L.call(12.0, 2.5, 11.0), L.call(0.0, 1.2, -0.3)], "dur": 5.0, "fov": 42.0, "music": "well",
			"lines": [[0.8, "", "第十九烽 · 塔顶"]],
			"on_start": func():
				p.global_position = you
				var to := nb.global_position - you
				p.rotation.y = atan2(-to.x, -to.z)
				p.set_third_person(true)},
		{"from": [you + (you - nb.global_position).normalized() * 1.4 + Vector3(0, 1.95, 0) + tp.basis.z * 0.95, head], "to": [you + (you - nb.global_position).normalized() * 1.1 + Vector3(0, 1.9, 0) + tp.basis.z * 0.85, head], "dur": 5.0, "fov": 46.0, "cut": true, "exposure": 0.75,
			"talk": nb, "lines": [[0.3, "诺伯特", "……你回来了。我数着日子，等了三天。"], [2.8, "诺伯特", "冠城那边的钟，是不是敲过了？"]]},
		{"from": [L.call(-1.25 + 1.35, 1.5, -0.5 + 0.75), head + Vector3(0, 0.02, 0)], "to": [L.call(-1.25 + 1.05, 1.58, -0.5 + 0.35), head], "dur": 6.5, "fov": 36.0, "fov_to": 32.0, "cut": true, "exposure": 0.55,
			"talk": nb, "lines": [[0.3, "诺伯特", "三十五年前我捧着它走出去，走到山脊上，"], [3.2, "诺伯特", "回头看了一眼，没往井边去。"]]},
		{"from": [L.call(-1.0, 1.4, 0.2), L.call(-0.62, 1.15, -0.45)], "to": [L.call(-0.85, 1.32, 0.0), L.call(-0.62, 1.15, -0.45)], "dur": 4.5, "fov": 30.0, "cut": true, "exposure": 0.6,
			"lines": [[0.4, "诺伯特", "它一直是空的。（他把瓶子放在你手心里）拿去。"]],
			"on_start": func():
				if vial.get_parent() == null:
					main.world.add_child(vial)
				vial.global_position = L.call(-0.62, 1.1, -0.45)},
		{"from": [L.call(-0.5, 2.6, 4.2), L.call(-0.5, 1.3, -0.4)], "to": [L.call(-3.0, 7.5, 10.5), L.call(-0.4, 1.0, -0.4)], "dur": 6.5, "fov": 44.0, "cut": true,
			"talk": nb, "lines": [[0.4, "诺伯特", "这一回，别让它空着回来。"]]},
	]


## 誓瓶（灰白的陶、瓶口一圈老蜡）：过场里那一下特写用
static func _vial() -> Node3D:
	var root := Node3D.new()
	root.name = "CutVial"
	var clay := StandardMaterial3D.new()
	clay.albedo_color = Color("c8c2b6")
	clay.roughness = 0.75
	var wax := StandardMaterial3D.new()
	wax.albedo_color = Color("7a2a20")
	wax.roughness = 0.5
	var parts := [[0.034, 0.03, 0.075, 0.0, clay], [0.016, 0.02, 0.03, 0.05, clay], [0.022, 0.022, 0.014, 0.07, wax]]
	for pt: Array in parts:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = float(pt[1])
		cm.bottom_radius = float(pt[0])
		cm.height = float(pt[2])
		cm.radial_segments = 16
		mi.mesh = cm
		mi.material_override = pt[4]
		mi.position.y = float(pt[3])
		root.add_child(mi)
	return root
