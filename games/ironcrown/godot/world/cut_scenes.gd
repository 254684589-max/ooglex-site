class_name CutScenes
extends RefCounted
## 各处的过场镜头脚本（路线图 C.5；播放器在 core/cutscene.gd）。每个过场一个静态函数：按场景里的东西现算机位，返回镜头列表。
## 没有配音：每段过场开头换一首配乐（data/music.json），字幕写谁说的、说什么；旁白（谁 = ""）居中。
##   prologue       开场（新游戏、选完出身以后）：从夜空摇下来，掠过霜渡镇的屋顶和街灯，停在领主宅邸门口的你身上——
##                  旁白交代这个世界：老王暴毙、铁冠失踪、冬天不走、五个家族争摄政、烽燧熄灭。之后接原来的钟声和管家喊人。
##   norbert_vial   第五章北上，第十九烽塔顶：诺伯特把三十五年前那只空誓瓶交给你（第一次和他说话时演，台词同 winter.json norbert5，
##                  演完给誓瓶、主线到 well，再从对话的 come 那一句接着说）。

##   ferry_standoff 序章到渡口（第一次走下来、还没和奥弗搭上话）：雾里的河 → 码头尽头埃德里克和塞拉斯在交易 → 芦苇里走出一伙人，
##                  领头的摘下灰皮手套 → 回到你走下坡的视角；演完你自己走过去，奥弗那句「又来一个」照旧在对话里说。

##   osric_dawn     第一章天亮、家主临终（和他说最后一番话之前）：熄了一半的炭盆和窗缝里的灰光 → 守了一夜的人（床尾的继承人或者玛尔塔）
##                  → 床上他的脸，慢慢推近；之后他在对话里说「铁冠没有被偷，是老王自己交出去的」（过场里不抢这句）。

##   well_ring      第二章章末，你和诺伯特走到冬井边（WinterWell.reached）：冰原上一口石井、长眠者站成一圈 → 圈里贴着它们的脸 →
##                  你和诺伯特的背影（他那句「三十五年，我头一回走到这口井边」） → 镜头升高拉远，淡出接章末画面。

##   wake_memory    第三章，伊格纳兹说完守灵夜那一夜（对话关上、晨钟响以前）：跪在墙下的他 → 回忆（褪色）：烛光里的铁冠、
##                  老王亲手把它交出去、第二天说是被偷了 → 回到现在，窗外天快亮了；演完接晨钟和章末。

##   council_open   第四章冬议开始以前（第一次和议事厅里的人说话时）：门口看进去，五把椅子围着空王座 → 王座椅背上积灰的冠形凹槽 →
##                  一张一张扫过五家的人；之后冬议的对话照原样（谁念借据按序章的旗标）。

##   oath_sealed    第五章封誓封上了（OathRitual.finished → sealed）：石台上誓瓶里最后一滴血 → 西边冰壁那一大片空着的冰里慢慢浮出一个名字
##                  （留名的人：继承人 / 大主祭卢西安 / 诺伯特 / 你——你没有名字，浮出来的是「誓剑」） → 星铁暗下去 → 抬头看井口，长眠者转身往南；之后结局。
##   oath_failed    封誓断了：火盆一个接一个暗下去 → 长眠的人围住石台；之后结局（长冬）。

##   causeway_open  第一章堤道夜战开打以前（你走到守点、main.start_battle）：高处看堤道和村子那头连成一线的火把 → 你身后的人；演完开打
##                  （攻方的兵开打以后才摆上去，所以不拍他们的脸）。

##   tide_rising    第二章第一夜潮水上来（FirstTide.tide_started）：营地这边往南看，坡上的人影一个接一个走上来 → 迎着它们，光着脚、闭着眼 →
##                  火把那一排背后，它们碰到火就拐开；演的时候潮水照样在走。

const IDS := ["prologue", "norbert_vial", "ferry_standoff", "osric_dawn", "well_ring", "wake_memory", "council_open", "oath_sealed", "oath_failed", "causeway_open", "tide_rising", "mill_open", "vault_crown", "well_descend", "ending_film", "royal_seal", "castle_first", "first_sleeper", "beacon_line", "ambush_open"]


## 这场仗开打以前演哪一段（每段只演一次）；没有就 ""
static func before_battle(main: Node) -> String:
	if str(main.area) == "marsh" and CausewayBattle.due() and not GameState.has_flag("cut_causeway_open"):
		return "causeway_open"
	if str(main.area) == "highland" and main.world != null and main.world.get_node_or_null("ConvoyAmbush") != null and not GameState.has_flag("cut_ambush_open"):
		return "ambush_open"
	if str(main.area) == "plain" and main.world != null and main.world.get_node_or_null("MillBattle") != null and not GameState.has_flag("cut_mill_open"):
		return "mill_open"
	return ""


## 进一个区域时要不要先演一段（main 进场时调，每段只演一次：播的时候记旗标 cut_<编号>）
static func on_enter(main: Variant) -> String:
	var a := str(main.area)
	if a == "ferry" and GameState.chapter == 0 and not GameState.has_flag("offer_parley") and not GameState.has_flag("offer_left") \
			and not GameState.has_flag("prologue_edric") and not GameState.has_flag("cut_ferry_standoff"):
		return "ferry_standoff"
	if GameState.has_flag("ch5_film") and not GameState.has_flag("ch5_done") and not GameState.has_flag("cut_ending_film") and a == str(ending_stage()[0]):
		return "ending_film"
	if a == "castle" and GameState.chapter == 1 and not GameState.has_flag("cut_castle_first") and not GameState.has_flag("ch1_hold"):
		return "castle_first"
	if a == "highland" and GameState.chapter == 2 and not GameState.has_flag("cut_beacon_line") and GameState.quest_stage("ch2_main") in ["", "ask_yangji"]:
		return "beacon_line"
	if a == "well_bottom" and GameState.chapter == 5 and not GameState.has_flag("ch5_ritual") and not GameState.has_flag("cut_well_descend"):
		return "well_descend"
	return ""


## 这段对话开始前要不要先演一段过场：{cut, after: Callable（演完做的事）, node: 演完从对话哪一句接着说}；不用就 {}
static func before_dialogue(dialogue_id: String) -> Dictionary:
	if dialogue_id == "council" and CrownPeople.council_due() and not GameState.has_flag("cut_council_open"):
		return {"cut": "council_open", "node": "", "after": func(): pass}
	if dialogue_id == "osric" and GameState.quest_stage("ch1_main") in ["dawn_held", "dawn_lost"] and not GameState.has_flag("ch1_osric_farewell") and not GameState.has_flag("cut_osric_dawn"):
		return {"cut": "osric_dawn", "node": "", "after": func(): pass}
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
		"ferry_standoff":
			return main.world != null and main.area == "ferry"
		"osric_dawn":
			return main.world != null and main.world.find_child("Npc_osric", true, false) != null
		"well_ring":
			return main.world != null and main.area == "highland" and main.world.find_child("WinterWell", true, false) != null
		"wake_memory":
			return main.world != null and main.area == "scriptorium"
		"council_open":
			return main.world != null and main.area == "council_hall"
		"oath_sealed", "oath_failed":
			return main.world != null and main.area == "well_bottom"
		"causeway_open":
			return main.world != null and main.area == "marsh"
		"tide_rising":
			return main.world != null and main.area == "highland"
		"mill_open":
			return main.world != null and main.area == "plain" and main.world.get_node_or_null("MillBattle") != null
		"vault_crown":
			return main.world != null and main.area == "key_vault"
		"well_descend":
			return main.world != null and main.area == "well_bottom"
		"ending_film":
			return main.world != null and main.area == str(ending_stage()[0])
		"royal_seal":
			return main.world != null
		"castle_first":
			return main.world != null and main.area == "castle"
		"first_sleeper":
			return main.world != null and main.area == "marsh" and main.sleeper != null and is_instance_valid(main.sleeper)
		"beacon_line":
			return main.world != null and main.area == "highland"
		"ambush_open":
			return main.world != null and main.area == "highland" and main.world.get_node_or_null("ConvoyAmbush") != null
	return false


static func shots(main: Node, id: String) -> Array:
	match id:
		"prologue":
			return prologue(main)
		"norbert_vial":
			return norbert_vial(main)
		"ferry_standoff":
			return ferry_standoff(main)
		"osric_dawn":
			return osric_dawn(main)
		"well_ring":
			return well_ring(main)
		"wake_memory":
			return wake_memory(main)
		"council_open":
			return council_open(main)
		"oath_sealed":
			return oath_sealed(main)
		"oath_failed":
			return oath_failed(main)
		"causeway_open":
			return causeway_open(main)
		"tide_rising":
			return tide_rising(main)
		"mill_open":
			return mill_open(main)
		"vault_crown":
			return vault_crown(main)
		"well_descend":
			return well_descend(main)
		"ending_film":
			return ending_film(main)
		"royal_seal":
			return royal_seal(main)
		"castle_first":
			return castle_first(main)
		"first_sleeper":
			return first_sleeper(main)
		"beacon_line":
			return beacon_line(main)
		"ambush_open":
			return ambush_open(main)
	return []


## 第一夜潮水（2-3）：长眠者从南边山坡（FirstTide.ROUTE_CAMP 第一个点）往北朝营地走，营地前一排插火把的木桩（SPOT_CENTER 两边）
## 磨坊之战开场（3-2）：院子 PlainMill.RECT（x 12–44、z -38 到 -2），东门外麦茬地是第一拨（MillBattle.WAVE1_AT），北边远处是背景大军（FAR_BLOCKS）
static func mill_open(main: Node) -> Array:
	var p: FpController = main.player
	var g := func(v: Vector2, up: float) -> Vector3: return MillBattle.p3(v) + Vector3(0, up, 0)
	var far: Vector2 = (MillBattle.FAR_BLOCKS[1] as Array)[0]
	var east: Vector2 = MillBattle.WAVE1_AT
	var breach: Vector2 = PlainMill.BREACH
	var raid := MillBattle.raiding()
	var shots := [
		{"from": [g.call(Vector2(6.0, 8.0), 16.0), g.call(Vector2(30.0, -24.0), 0.0)], "to": [g.call(Vector2(10.0, 2.0), 13.0), g.call(Vector2(34.0, -40.0), 2.0)], "dur": 7.0, "fov": 50.0, "music": "battle", "exposure": 1.5,
			"lines": [[0.6, "", "入夜。麦渡的水磨坊，院墙上一支一支点起火把。"], [3.8, "", "三座粮仓里的麦子，够一个村子吃过这个冬天。"]],
			"on_start": func(): p.set_third_person(true)},
		{"from": [g.call(breach + Vector2(-1.5, 3.0), 2.2), g.call(far, 6.0)], "to": [g.call(breach + Vector2(-0.5, 1.0), 2.0), g.call(far, 4.0)], "dur": 6.0, "fov": 44.0, "cut": true, "exposure": 1.6,
			"lines": [[0.5, "", "北边的麦茬地上，塞弗林家的大营亮成一片。"], [3.2, "", "几百支火把，一动不动，像在等什么。"]]},
	]
	if raid:
		shots.append({"from": [g.call(east + Vector2(6.0, 2.5), 2.6), g.call(PlainMill.EAST_GATE, 2.0)], "to": [g.call(east + Vector2(3.5, 1.5), 2.3), g.call(PlainMill.EAST_GATE, 2.0)], "dur": 5.0, "fov": 46.0, "cut": true, "exposure": 1.6,
			"lines": [[0.5, "", "你伏在东门外的麦茬里，身边是奥迪隆的第一拨。"], [2.8, "", "院墙后面，有人在往门上顶木头。"]]})
	else:
		shots.append({"from": [g.call(PlainMill.EAST_GATE + Vector2(2.5, 1.2), 2.4), g.call(east, 1.0)], "to": [g.call(PlainMill.EAST_GATE + Vector2(6.0, 0.8), 1.9), g.call(east, 1.0)], "dur": 5.0, "fov": 46.0, "cut": true, "exposure": 1.6,
			"lines": [[0.5, "", "东门外，第一拨人伏在麦茬里，刀背映着火光。"], [2.8, "", "今夜，粮仓不能丢。"]]})
	return shots


## 金库之夜（4-2）：铁冠第一次露面。金库 11 × 7 米，铁匣在北墙正中的石台上（HarborRooms.CROWN_BOX），罩着铁笼（前面一排铁条在 z = 台 + 0.62）
## 拿到冠的那一下演（HarborRooms.crown_box 返回 cutscene）；冠和星铁那点冷光放在 CutVaultProps 底下（cut_prop 组：演完 main 拿掉）
static func vault_crown(main: Node) -> Array:
	var p: FpController = main.player
	var cb: Vector3 = HarborRooms.CROWN_BOX
	var lid := cb + Vector3(0, 1.27, 0)
	var props := Node3D.new()
	props.name = "CutVaultProps"
	props.add_to_group("cut_prop")
	var crown := _crown()
	props.add_child(crown)
	crown.position = lid
	crown.visible = false
	var glow := OmniLight3D.new()
	glow.name = "CutStarGlow"
	glow.light_color = Color(0.6, 0.78, 1.0)
	glow.light_energy = 0.0
	glow.omni_range = 1.2
	glow.position = lid + Vector3(0, 0.12, 0.25)
	props.add_child(glow)
	var maud := main.world.find_child("Npc_maud_vault", true, false) as Node3D
	var wide_at: Vector3 = maud.global_position + Vector3(0, 1.3, 0) if maud else cb + Vector3(0, 1.2, 0)
	return [
		{"from": [cb + Vector3(0.6, 1.55, 1.6), cb + Vector3(0, 1.1, 0.0)], "to": [cb + Vector3(0.3, 1.4, 1.05), cb + Vector3(0, 1.1, 0.0)], "dur": 5.0, "fov": 40.0, "music": "harbor", "exposure": 1.2,
			"lines": [[0.5, "", "最小的那把钥匙，在锁眼里转了半圈。铁笼的门往外荡开。"]],
			"on_start": func():
				p.set_third_person(false)
				if props.get_parent() == null:
					main.world.add_child(props)},
		{"from": [lid + Vector3(0.0, 0.42, 0.55), lid + Vector3(0, 0.03, 0)], "to": [lid + Vector3(0.0, 0.3, 0.36), lid + Vector3(0, 0.03, 0)], "dur": 6.5, "fov": 34.0, "cut": true, "exposure": 1.25,
			"lines": [[0.4, "", "匣盖掀开。一圈暗色的铁，没有宝石，也没有金子。"], [3.6, "", "冠底下嵌着一块星铁，冷得像冬井里的水。"]],
			"on_start": func():
				crown.visible = true
				var tw := glow.create_tween()
				tw.tween_property(glow, "light_energy", 0.9, 2.5)},
		{"from": [Vector3(0.0, 1.9, 3.0), wide_at], "to": [Vector3(0.0, 1.75, 2.2), cb + Vector3(0, 1.1, 0)], "dur": 5.5, "fov": 50.0, "cut": true, "exposure": 1.45,
			"lines": [[0.5, "", "王国为它争了三十五年。"], [2.8, "", "它就躺在一只铁匣里，在一间放借据的屋子底下。"]]},
	]


## 下到井底（5-3）：第一次下来就演。井底 14 × 12 × 6 米：石阶贴着南墙从西往东上到顶上的井口，冰壁在东西北三面（刻着名字），星铁在北半边（WellRooms.STAR），石台在它前面
static func well_descend(main: Node) -> Array:
	var p: FpController = main.player
	var st: Vector3 = WellRooms.STAR
	var al: Vector3 = WellRooms.ALTAR
	var wx := -6.67
	var rim := OmniLight3D.new()                                          # 星铁那个镜头的一道冷光（cut_prop：演完拿掉）
	rim.name = "CutStarRim"
	rim.add_to_group("cut_prop")
	rim.light_color = Color(0.7, 0.85, 1.0)
	rim.light_energy = 0.0
	rim.omni_range = 7.0
	return [
		{"from": [Vector3(2.0, 4.9, 5.3), Vector3(-3.6, 0.6, 4.9)], "to": [Vector3(-0.4, 3.2, 5.2), Vector3(-3.9, 0.3, 3.6)], "dur": 4.5, "fov": 54.0, "music": "well", "exposure": 1.2,
			"lines": [[0.5, "", "石阶贴着井壁往下，一级一级，结着冰。"]],
			"on_start": func(): p.set_third_person(false)},
		{"from": [Vector3(-1.6, 2.6, 4.6), Vector3(-0.5, 0.8, -2.0)], "to": [Vector3(-2.6, 2.0, 4.4), Vector3(0.0, 1.0, -2.5)], "dur": 4.5, "fov": 52.0, "cut": true, "exposure": 1.2,
			"lines": [[0.4, "", "底下有光——不是火光。"]]},
		{"from": [Vector3(wx + 2.2, 1.9, 1.6), Vector3(wx, 2.4, 0.6)], "to": [Vector3(wx + 2.0, 1.5, -0.6), Vector3(wx, 1.2, -2.2)], "dur": 7.0, "fov": 44.0, "cut": true, "exposure": 1.2,
			"lines": [[0.5, "", "冰壁里刻满了名字。有的是王，有的不是。"], [3.8, "", "最后一个，刻在四百年前。再往下，是一大片空着的冰。"]]},
		{"from": [al + Vector3(1.6, 1.9, 2.0), st + Vector3(0, 1.2, 0)], "to": [al + Vector3(0.9, 1.65, 1.1), st + Vector3(0, 1.3, 0)], "dur": 6.0, "fov": 46.0, "cut": true, "exposure": 1.25,
			"lines": [[0.5, "", "星铁。半埋在冰里，比一个人还高。"], [3.2, "", "王国的那颗星，一直在这儿。"]],
			"on_start": func():
				if rim.get_parent() == null:
					main.world.add_child(rim)
				rim.global_position = al + Vector3(0.6, 2.8, 1.4)            # 差不多在镜头上方：黑亮的星铁朝着镜头那几面才反得出光
				rim.create_tween().tween_property(rim, "light_energy", 3.0, 2.0)},
	]


## 结局影片（5-5）：封誓演完以后，按结局去一个地方演（main._finale 先 travel 过去，到了 on_enter 演，演完出结局画面）
## new_king：冠城议事厅，王座椅背的凹槽里放着铁冠；crownless_spring：金穗平原的白天；long_winter：冬井边的夜里
static func ending_kind() -> String:
	var e := str(GameState.get_flag("ending", ""))
	return e if e in ["new_king", "crownless_spring", "long_winter"] else "long_winter"


## [区域, 出生点, 时段]
static func ending_stage() -> Array:
	match ending_kind():
		"new_king":
			return ["council_hall", "front", "dawn"]
		"crownless_spring":
			return ["plain", "mill", "day"]
	return ["highland", "well", "night"]


static func ending_film(main: Node) -> Array:
	var p: FpController = main.player
	var hide_me := func(): p.set_third_person(false)
	match ending_kind():
		"new_king":
			var t := CrownRooms.THRONE
			var notch := t + Vector3(0, 3.45, -0.49)
			var crown := _crown()
			crown.add_to_group("cut_prop")
			var sun := OmniLight3D.new()
			sun.add_to_group("cut_prop")
			sun.light_color = Color("ffd9a0")
			sun.light_energy = 1.4
			sun.omni_range = 6.0
			return [
				{"from": [t + Vector3(0, 3.4, 8.6), t + Vector3(0, 1.2, 0.5)], "to": [t + Vector3(0, 2.8, 6.6), t + Vector3(0, 1.2, 0.3)], "dur": 6.0, "fov": 50.0, "music": "keep", "exposure": 1.3,
					"lines": [[0.6, "", "冬至过后的第一个早晨，冠城的钟响了。"]],
					"on_start": func():
						hide_me.call()
						if crown.get_parent() == null:
							main.world.add_child(crown)
							main.world.add_child(sun)
						crown.global_position = notch + Vector3(0, -0.02, 0)
						crown.scale = Vector3.ONE * 1.6
						sun.global_position = notch + Vector3(0.8, 1.0, 1.6)},
				{"from": [notch + Vector3(0.7, -0.25, 1.0), notch + Vector3(0, 0.03, 0)], "to": [notch + Vector3(0.35, -0.12, 0.6), notch + Vector3(0, 0.03, 0)], "dur": 5.5, "fov": 34.0, "cut": true, "exposure": 1.3,
					"lines": [[0.5, "", "椅背顶上那个冠形的凹槽，这一回没有空着。"]]},
				{"from": [t + Vector3(-2.5, 2.0, 4.0), t + Vector3(0, 2.2, 0)], "to": [t + Vector3(-3.5, 4.5, 7.5), t + Vector3(0, 1.8, 0)], "dur": 7.0, "fov": 48.0, "cut": true, "exposure": 1.3,
					"lines": [[0.5, "", "%s戴上了铁冠。" % Chapter5.heir_name()], [3.4, "", "北边烽燧线上的火，一座接一座，又点起来了。"]]},
			]
		"crownless_spring":
			var g := func(v: Vector2, up: float) -> Vector3: return MillBattle.p3(v) + Vector3(0, up, 0)
			return [
				{"from": [g.call(Vector2(-12.0, 34.0), 22.0), g.call(Vector2(28.0, -24.0), 0.0)], "to": [g.call(Vector2(-6.0, 24.0), 17.0), g.call(Vector2(32.0, -34.0), 2.0)], "dur": 7.0, "fov": 52.0, "music": "plain", "exposure": 1.0,
					"lines": [[0.6, "", "那个冬天，终于过去了。"], [3.6, "", "冠城的王座还空着。"]],
					"on_start": hide_me},
				{"from": [g.call(Vector2(-26.0, 46.0), 15.0), g.call(Vector2(-54.0, 16.0), 0.0)], "to": [g.call(Vector2(-29.0, 42.0), 12.0), g.call(Vector2(-55.0, 14.0), 0.0)], "dur": 5.5, "fov": 46.0, "cut": true, "exposure": 1.0,
					"lines": [[0.5, "", "麦渡的人照样下地。没有王，地也照样要种。"]]},
				{"from": [g.call(Vector2(40.0, -42.0), 1.8), g.call(Vector2(46.0, -150.0), 6.0)], "to": [g.call(Vector2(41.0, -50.0), 3.5), g.call(Vector2(46.0, -150.0), 12.0)], "dur": 7.0, "fov": 50.0, "cut": true, "exposure": 1.0,
					"lines": [[0.5, "", "北边冰壁上多了一个名字。"], [3.4, "", "铁冠，从此只是一圈铁。"]]},
			]
	var w: Vector2 = HighlandLayout.WELL
	var gw := func(v: Vector2, up: float) -> Vector3: return WinterWell.ground(v) + Vector3(0, up, 0)
	var vil := Vector2(6.0, 112.0)
	return [
		{"from": [gw.call(w + Vector2(12.0, 20.0), 14.0), gw.call(w, 0.0)], "to": [gw.call(w + Vector2(8.0, 14.0), 10.0), gw.call(w, 0.5)], "dur": 7.0, "fov": 50.0, "music": "well", "exposure": 1.5,
			"lines": [[0.6, "", "火盆一个接一个暗下去。"], [3.4, "", "冬天没有走。"]],
			"on_start": hide_me},
		{"from": [gw.call(w + Vector2(2.6, 2.4), 1.5), gw.call(w, 0.3)], "to": [gw.call(w + Vector2(1.8, 1.7), 1.3), gw.call(w, 0.2)], "dur": 6.0, "fov": 42.0, "cut": true, "exposure": 1.5,
			"lines": [[0.5, "", "井底那面冰壁上，还是一大片空着的冰。"]]},
		{"from": [gw.call(vil + Vector2(0, 26.0), 9.0), gw.call(vil + Vector2(0, -6.0), 2.0)], "to": [gw.call(vil + Vector2(0, 20.0), 7.0), gw.call(vil + Vector2(0, -10.0), 2.0)], "dur": 7.0, "fov": 50.0, "cut": true, "exposure": 1.5,
			"lines": [[0.5, "", "开春以前，羊脊村的人往南搬了。"], [3.4, "", "王国一年比一年冷，等着下一个走到井边的人。"]]},
	]


## 王室印鉴（0-3）：序章尾声、出结局画面以前。在哪儿结束都一样（教堂 / 渡口）：在场景上空搭一张「特写台」——黑布、借据正面和背面、一支蜡烛（cut_prop，演完拿掉）
const SEAL_STAGE := Vector3(0.0, 300.0, 0.0)


static func _seal_stage() -> Node3D:
	var root := Node3D.new()
	root.name = "CutSealStage"
	root.add_to_group("cut_prop")
	var mat := func(c: String, rough := 0.9, metal := 0.0) -> StandardMaterial3D:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(c)
		m.roughness = rough
		m.metallic = metal
		return m
	var box := func(size: Vector3, at: Vector3, m: Material) -> void:
		var mi := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = size
		mi.mesh = b
		mi.material_override = m
		mi.position = at
		root.add_child(mi)
	var disc := func(r: float, at: Vector3, m: Material) -> void:
		var mi := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = r
		c.bottom_radius = r * 1.08
		c.height = 0.008
		c.radial_segments = 20
		mi.mesh = c
		mi.material_override = m
		mi.position = at
		root.add_child(mi)
	box.call(Vector3(3.0, 0.02, 2.0), Vector3(0.5, -0.01, 0), mat.call("141012"))           # 黑布
	box.call(Vector3(6.0, 4.0, 0.1), Vector3(0.5, 1.0, -1.2), mat.call("050506"))           # 背后一片黑，看不见天
	var paper: StandardMaterial3D = mat.call("a8966e")
	var ink: StandardMaterial3D = mat.call("4a3a2c")
	for k in 2:                                                       # 0：正面（两家的印）；1：背面（星铁冠印）
		var c := Vector3(k * 1.0, 0, 0)
		box.call(Vector3(0.32, 0.004, 0.23), c + Vector3(0, 0.002, 0), paper)
		if k == 0:
			for r in 11:
				box.call(Vector3(0.25 - (0.08 if r == 10 else 0.0), 0.001, 0.0025), c + Vector3(-0.005 - (0.04 if r == 10 else 0.0), 0.0045, -0.09 + r * 0.0135), ink)
			disc.call(0.022, c + Vector3(-0.07, 0.008, 0.075), mat.call("7a2a20", 0.5))         # 瓦伦家：红蜡
			disc.call(0.022, c + Vector3(0.07, 0.008, 0.075), mat.call("2f4a3a", 0.5))          # 卡斯韦尔家：绿蜡
		else:
			disc.call(0.04, c + Vector3(0, 0.008, 0.0), mat.call("23252a", 0.3, 0.8))         # 星铁冠印：一块黑亮的蜡
			var cr := _crown()
			cr.scale = Vector3.ONE * 0.26
			cr.position = c + Vector3(0, 0.013, 0.0)
			root.add_child(cr)
	var candle := OmniLight3D.new()
	candle.light_color = Color("ffb060")
	candle.light_energy = 0.9
	candle.omni_range = 2.5
	candle.position = Vector3(0.5, 0.45, 0.35)
	root.add_child(candle)
	return root


static func royal_seal(main: Node) -> Array:
	var p: FpController = main.player
	var st := _seal_stage()
	var o := SEAL_STAGE
	return [
		{"from": [o + Vector3(-0.12, 0.3, 0.26), o + Vector3(-0.02, 0.0, 0.0)], "to": [o + Vector3(0.1, 0.24, 0.2), o + Vector3(0.03, 0.0, 0.02)], "dur": 6.0, "fov": 40.0, "music": "night", "exposure": 0.9,
			"lines": [[0.5, "", "借据底下压着两家的印：瓦伦家的红蜡，卡斯韦尔家的绿蜡。"]],
			"on_start": func():
				p.set_third_person(false)
				if st.get_parent() == null:
					main.world.add_child(st)
				st.global_position = o},
		{"from": [o + Vector3(1.0, 0.24, 0.2), o + Vector3(1.0, 0.0, 0.0)], "to": [o + Vector3(1.0, 0.13, 0.1), o + Vector3(1.0, 0.0, 0.0)], "dur": 6.5, "fov": 34.0, "cut": true, "exposure": 0.9,
			"lines": [[0.5, "", "翻过来，背面还压着一枚印——一顶星铁冠。"], [3.4, "", "王室的印鉴。老王生前，亲手担保过这笔债。"]]},
	]


## 初见黑鹭堡（1-1）：第一章第一次进堡门。庭院 36 × 40 米、墙高 8 米，主楼在北（Castle.KEEP），堡门在南（z = 20）
static func castle_first(main: Node) -> Array:
	var p: FpController = main.player
	var keep: Vector3 = Castle.KEEP[0]
	return [
		{"from": [Vector3(-7.0, 11.0, 24.0), keep + Vector3(0, 4.0, 0)], "to": [Vector3(-3.5, 8.5, 17.0), keep + Vector3(0, 3.0, 0)], "dur": 7.0, "fov": 50.0, "music": "keep",
			"lines": [[0.6, "", "黑鹭堡。鹭沼北岸的一圈石墙，瓦伦家世世代代守在这里。"], [3.8, "", "墙里头，家主病着，两位继承人都在等他开口。"]],
			"on_start": func(): p.set_third_person(true)},
		{"from": [Vector3(-1.6, 1.7, -2.5), Vector3(0, 1.6, -9.4)], "to": [Vector3(-0.9, 1.65, -4.2), Vector3(0, 1.5, -9.4)], "dur": 5.0, "fov": 46.0, "cut": true,
			"lines": [[0.5, "", "火盆守着大厅的门。家主躺在东边的塔楼里，一天比一天轻了。"]]},
		{"from": [Vector3(5.5, 1.7, 15.5), Vector3(0, 1.4, 17.5)], "to": [Vector3(4.5, 1.6, 13.5), Vector3(0, 1.5, 17.5)], "dur": 5.0, "fov": 46.0, "cut": true,
			"lines": [[0.5, "", "堡门里头，每一双眼睛都在看你这个外人。"]]},
	]


## 第一个长眠者（1-4）：第一章天亮回到芦栈村，撞见那个说过话的村民闭着眼往北走（Sleeper：顺着栈道往西，拐上去泥炭场的木板路往北，走进芦苇里）
## 演的时候他照样在走，机位按他现在的位置和速度往前算
static func first_sleeper(main: Node) -> Array:
	var p: FpController = main.player
	var n: Npc = main.sleeper.npc
	var at := n.global_position
	var head := Vector3(0, 1.55, 0)
	var west := Vector3(-1, 0, 0)
	var turn: Vector3 = Sleeper.PATH[0]
	var nm := str(Sleeper.who()[1])
	return [
		{"from": [at + west * 2.2 + Vector3(0, 1.6, 0.25), at + head], "to": [at + west * 5.0 + Vector3(0, 1.6, 0.25), at + west * 3.6 + head], "dur": 4.5, "fov": 38.0, "music": "marsh",
			"lines": [[0.5, nm, "……"], [2.2, "", "眼睛闭着。光着脚，踩在结霜的栈道上。"]],
			"on_start": func(): p.set_third_person(true)},
		{"from": [at + Vector3(3.5, 2.4, 0.0), turn + Vector3(0, 1.0, 0)], "to": [at + Vector3(-1.5, 2.2, 0.0), turn + Vector3(0, 1.0, -1.0)], "dur": 5.5, "fov": 50.0, "cut": true,
			"lines": [[0.5, "", "叫不醒，拦不住。你挡在前面，他就绕过去。"]]},
		{"from": [turn + Vector3(1.6, 2.4, 3.0), turn + Vector3(0, 1.0, -30.0)], "to": [turn + Vector3(1.2, 3.4, 1.0), turn + Vector3(0, 1.5, -40.0)], "dur": 6.0, "fov": 50.0, "cut": true,
			"lines": [[0.5, "", "他拐上去泥炭场的木板路，一直往北，"], [3.0, "", "走进北边的芦苇里。"]]},
	]


## 烽燧线全景（2-1）：第二章第一次到余火高地。羊脊村在南（HighlandLayout.VILLAGE），盘山路往北上到第十九烽（BEACON19），山脊往西是第十八烽（BEACON18），再往北是白寂边缘
static func beacon_line(main: Node) -> Array:
	var p: FpController = main.player
	var g := func(v: Vector2, up: float) -> Vector3: return WinterWell.ground(v) + Vector3(0, up, 0)
	var vil: Vector2 = HighlandLayout.VILLAGE
	var b19: Vector2 = HighlandLayout.BEACON19
	var b18: Vector2 = HighlandLayout.BEACON18
	return [
		{"from": [g.call(vil + Vector2(-6.0, 40.0), 26.0), g.call(vil, 0.0)], "to": [g.call(vil + Vector2(-2.0, 24.0), 20.0), g.call(b19, 8.0)], "dur": 7.5, "fov": 52.0, "music": "night",
			"lines": [[0.6, "", "北境，余火高地。羊脊村的炊烟，是这条路上最后的人烟。"], [4.0, "", "盘山路往北，一直通到山脊上。"]],
			"on_start": func(): p.set_third_person(true)},
		{"from": [g.call(Vector2(-40.0, -20.0), 30.0), g.call(b18, 8.0)], "to": [g.call(Vector2(-20.0, -24.0), 30.0), g.call(b19, 8.0)], "dur": 7.5, "fov": 50.0, "cut": true,
			"lines": [[0.5, "", "山脊上，一座烽燧接着一座，从前夜夜点着火。"], [3.8, "", "现在大半都黑着。"]]},
		{"from": [g.call(b19 + Vector2(-14.0, 22.0), 6.0), g.call(b19, 9.0)], "to": [g.call(b19 + Vector2(-10.0, 16.0), 5.0), g.call(b19, 11.0)], "dur": 6.0, "fov": 46.0, "cut": true,
			"lines": [[0.5, "", "最近的那一座，叫断角烽。"], [3.0, "", "再往北，就是白寂。"]]},
	]


## 劫粮伏击开场（2-2）：第二夜，粮车沿盘山路的伏击段上来（ConvoyAmbush.leg_point(t, 偏)：t 大的那头往山脊，偏 > 0 是下坡一侧），你伏在车头前的枯松后（head）或车尾后的弯道上（tail）
static func ambush_open(main: Node) -> Array:
	var p: FpController = main.player
	var L := func(t: float, off: float, up: float) -> Vector3: return ConvoyAmbush.leg_point(t, off) + Vector3(0, up, 0)
	var head := ConvoyAmbush.ambush() == "head"
	var mid: float = ConvoyAmbush.CART_T[2]
	var post: float = ConvoyAmbush.POST_T[ConvoyAmbush.ambush()]
	var toward := mid - post
	return [
		{"from": [L.call(mid + 22.0, -14.0, 12.0), L.call(mid, 0.0, 0.0)], "to": [L.call(mid + 14.0, -11.0, 9.0), L.call(mid - 4.0, 0.0, 0.0)], "dur": 7.0, "fov": 50.0, "music": "battle", "exposure": 1.5,
			"lines": [[0.6, "", "天黑透了。粮车点着火把，一辆接一辆爬上盘山路。"], [3.8, "", "车上的粮要运出北境。烽燧上的人，等不起了。"]],
			"on_start": func(): p.set_third_person(true)},
		{"from": [L.call(post - signf(toward) * 3.0, -2.5, 1.3), L.call(mid, 0.0, 1.0)], "to": [L.call(post - signf(toward) * 1.5, -2.0, 1.1), L.call(mid, 0.0, 1.0)], "dur": 5.5, "fov": 44.0, "cut": true, "exposure": 1.5,
			"lines": [[0.5, "", "锯倒的枯松横在路上。马蒂亚斯的人伏在石头后面，一声不出。" if head else "你们伏在车尾后面的弯道上。马蒂亚斯的人一声不出。"]]},
		{"from": [L.call(mid + 1.5, 3.5, 1.7), L.call(mid, 0.0, 1.2)], "to": [L.call(mid + 0.5, 2.8, 1.6), L.call(mid - 1.5, 0.0, 1.2)], "dur": 5.0, "fov": 44.0, "cut": true, "exposure": 1.5,
			"lines": [[0.5, "", "押车的是洛蒙德家的兵，十几个人，有两个背着弓。"]]},
	]


static func tide_rising(main: Node) -> Array:
	var p: FpController = main.player
	var g := func(v: Vector2, up: float) -> Vector3: return WinterWell.ground(v) + Vector3(0, up, 0)
	var src: Vector2 = FirstTide.ROUTE_CAMP[0]
	var mid: Vector2 = (src + FirstTide.SPOT_CENTER) * 0.5
	var spot: Vector2 = FirstTide.SPOT_CENTER
	return [
		{"from": [g.call(spot + Vector2(3.0, -6.0), 5.5), g.call(src, 1.0)], "to": [g.call(spot + Vector2(1.5, -3.0), 4.0), g.call(src + (spot - src) * 0.2, 1.0)], "dur": 6.0, "fov": 46.0, "music": "battle", "exposure": 1.3,
			"lines": [[0.6, "", "第一夜。南边的山坡上，有人影一个接一个走上来。"]],
			"on_start": func(): p.set_third_person(true)},
		{"from": [g.call(mid + Vector2(1.2, 0.0), 1.3), g.call(src + (spot - src) * 0.25, 1.5)], "to": [g.call(mid + Vector2(1.0, -1.5), 1.35), g.call(src + (spot - src) * 0.3, 1.5)], "dur": 5.0, "fov": 40.0, "cut": true, "exposure": 1.3,
			"lines": [[0.5, "", "光着脚，闭着眼睛，不出一点声音。"]]},
		{"from": [g.call(spot + Vector2(-1.0, -3.0), 1.7), g.call(spot + (src - spot) * 0.4, 1.0)], "to": [g.call(spot + Vector2(-0.6, -2.2), 1.6), g.call(spot + (src - spot) * 0.4, 1.0)], "dur": 5.0, "fov": 48.0, "cut": true, "exposure": 1.3,
			"lines": [[0.5, "", "碰到火，它们就拐开。火要是灭了——"]]},
	]


## 堤道夜战开场（1-2）：堤道沿 MarshLayout.cw3(t) 走，t 小的那头是村子（攻方列在 WAVE1_T），守点在 HOLD_T（断口 45.5 / 石拱 75）
static func causeway_open(main: Node) -> Array:
	var p: FpController = main.player
	var ht := float(CausewayBattle.HOLD_T[CausewayBattle.hold()])
	var y := MarshLayout.CAUSE_Y
	return [
		{"from": [MarshLayout.cw3(ht + 14.0, 7.0, y + 8.0), MarshLayout.cw3(6.0, 0.0, y + 1.0)], "to": [MarshLayout.cw3(ht + 8.0, 5.0, y + 6.0), MarshLayout.cw3(8.0, 0.0, y + 1.0)], "dur": 7.0, "fov": 48.0, "music": "battle", "exposure": 1.6,
			"lines": [[0.6, "", "入夜。堤道那头的沼地上，火把连成了一条线。"], [3.8, "", "举着那些火把的，是另一位继承人的人。"]],
			"on_start": func(): p.set_third_person(true)},
		{"from": [MarshLayout.cw3(ht + 4.5, 1.2, y + 2.0), MarshLayout.cw3(ht - 14.0, 0.0, y + 1.2)], "to": [MarshLayout.cw3(ht + 3.2, 0.9, y + 1.9), MarshLayout.cw3(ht - 14.0, 0.0, y + 1.2)], "dur": 5.0, "fov": 46.0, "cut": true,
			"lines": [[0.5, "", "你的人在你身后。今夜，这条堤道要守住。"]]},
	]


## 留名的人在冰壁上的名字
static func oath_name() -> String:
	match str(GameState.get_flag("oath_taker", "")):
		"heir":
			return Chapter5.heir_name()
		"lucien":
			return "卢西安"
		"norbert":
			return "诺伯特"
	return "誓剑"


## 封上了（5-4）：冬井底 14 × 12 米，星铁在北半边（WellRooms.STAR），石台在它前面（ALTAR），刻名字的冰壁在西墙（x = -7）
static func oath_sealed(main: Node) -> Array:
	var p: FpController = main.player
	var a: Vector3 = WellRooms.ALTAR
	var st: Vector3 = WellRooms.STAR
	var name_at := Vector3(-6.85, 1.15, -1.6)
	var label := Label3D.new()
	label.name = "CutOathName"
	label.text = oath_name()
	label.font_size = 96
	label.pixel_size = 0.004
	label.modulate = Color(0.75, 0.88, 1.0, 0.0)
	label.outline_size = 0
	label.rotation_degrees.y = 90.0                                   # 刻在西墙上、朝着屋里
	var show_name := func():
		if label.get_parent() == null:
			main.world.add_child(label)
		label.global_position = name_at
		var tw := label.create_tween()
		tw.tween_property(label, "modulate:a", 0.95, 3.5)
	return [
		{"from": [a + Vector3(0.9, 1.35, 1.1), a + Vector3(0, 0.75, 0)], "to": [a + Vector3(0.55, 1.15, 0.7), a + Vector3(0, 0.75, 0)], "dur": 5.0, "fov": 34.0, "music": "well",
			"lines": [[0.5, "", "最后一滴血落进誓瓶。"]],
			"on_start": func(): p.set_third_person(true)},
		{"from": [name_at + Vector3(3.6, 0.3, 1.6), name_at], "to": [name_at + Vector3(2.4, 0.15, 0.9), name_at], "dur": 6.5, "fov": 38.0, "cut": true,
			"lines": [[0.6, "", "冰壁上那一大片空着的冰里，慢慢浮出一个名字。"]],
			"on_start": show_name},
		{"from": [st + Vector3(-1.8, 1.4, 3.2), st + Vector3(0, 1.6, 0)], "to": [st + Vector3(-1.2, 1.2, 2.4), st + Vector3(0, 1.4, 0)], "dur": 5.0, "fov": 44.0, "cut": true, "exposure": 1.1,
			"lines": [[0.5, "", "星铁上的光一点一点暗了下去。"]]},
		{"from": [Vector3(4.8, 3.4, 5.0), Vector3(-1.6, 1.0, -1.6)], "to": [Vector3(5.4, 4.6, 5.4), Vector3(-1.8, 1.0, -1.8)], "dur": 6.0, "fov": 52.0, "cut": true,      # 石阶口看整个井底（往上看井口是黑的）
			"lines": [[0.5, "", "井口上那一圈人站住了——一个，接一个，转过身，往南走。"]]},
	]


## 封誓断了：火盆一个接一个暗下去，长眠的人围住石台
static func oath_failed(main: Node) -> Array:
	var a: Vector3 = WellRooms.ALTAR
	var b0: Vector3 = WellRooms.BRAZIERS[0]
	return [
		{"from": [b0 + Vector3(2.0, 1.8, 2.4), b0 + Vector3(0, 0.9, 0)], "to": [b0 + Vector3(1.4, 1.5, 1.6), b0 + Vector3(0, 0.9, 0)], "dur": 5.0, "fov": 40.0, "music": "well", "exposure": 0.8,
			"lines": [[0.5, "", "火盆一个接一个暗了下去。"]]},
		{"from": [a + Vector3(0, 5.5, 4.5), a + Vector3(0, 0.5, 0)], "to": [a + Vector3(0, 7.5, 6.5), a + Vector3(0, 0.4, 0)], "dur": 6.5, "fov": 46.0, "cut": true, "exposure": 0.8,
			"lines": [[0.5, "", "长眠的人走下石阶，围住了石台。誓瓶还是空的。"]]},
	]


## 冬议开场（4-3）：王座在北头（CrownRooms.THRONE），五把椅子在它前面一段弧上（半径 CHAIR_R），人站在椅子前面；门在南边
static func council_open(main: Node) -> Array:
	var p: FpController = main.player
	var t := CrownRooms.THRONE
	var heads: Array = []
	for c: Array in CrownRooms.CHAIRS:
		var n := main.world.find_child("Npc_council_" + str(c[0]), true, false) as Node3D
		if n:
			heads.append(n.global_position + Vector3(0, 1.6, 0))
	if heads.is_empty():
		heads = [t + Vector3(-3, 1.6, 2), t + Vector3(3, 1.6, 2)]
	var mid := t + Vector3(0, 1.55, 3.4)
	return [
		{"from": [t + Vector3(0, 3.4, 8.6), t + Vector3(0, 1.2, 0.5)], "to": [t + Vector3(0, 2.8, 6.6), t + Vector3(0, 1.2, 0.3)], "dur": 6.0, "fov": 50.0, "music": "keep",
			"lines": [[0.6, "", "冬至。冠城的议事厅里，五把椅子围着一张空着的王座。"]],
			"on_start": func(): p.set_third_person(false)},
		{"from": [t + Vector3(0.7, 3.2, 1.3), t + Vector3(0, 3.45, -0.49)], "to": [t + Vector3(0.4, 3.35, 0.75), t + Vector3(0, 3.45, -0.49)], "dur": 5.0, "fov": 34.0, "cut": true,      # 凹槽在椅背顶上（CrownRooms：台阶 0.6 米 + 2.85）
			"lines": [[0.5, "", "椅背顶上那个冠形的凹槽，三年没擦过，落着一层薄灰。"]]},
		{"from": [mid, heads[0]], "to": [mid, heads[-1]], "dur": 7.5, "fov": 42.0, "cut": true,
			"lines": [[0.5, "", "五家的人都到了。"], [3.4, "", "今天要清的，是这个王国欠下的账。"]]},
	]


## 守灵夜的回忆（3-3）：抄经室 9 × 4.8 米，伊格纳兹跪在东墙（刻满划痕）下；回忆的几个镜头在窗下那张抄经桌上——一块黑布、一支蜡烛、一顶铁冠
static func wake_memory(main: Node) -> Array:
	var p: FpController = main.player
	var ig: Vector3 = Scriptorium.IGNAZ[0]
	var desk: Vector3 = Scriptorium.DESKS[1]
	var top := desk + Vector3(0, 0.8, 0)
	var crown := _crown()
	var candle := OmniLight3D.new()
	candle.name = "CutCandle"
	candle.light_color = Color("ffb060")
	candle.light_energy = 1.6
	candle.omni_range = 2.2
	var cloth := MeshInstance3D.new()
	cloth.name = "CutCloth"
	var cm := BoxMesh.new()
	cm.size = Vector3(0.9, 0.01, 0.6)
	cloth.mesh = cm
	var clm := StandardMaterial3D.new()
	clm.albedo_color = Color("1a1416")
	clm.roughness = 0.95
	cloth.material_override = clm
	var stage := func():
		for n in [crown, candle, cloth]:
			if (n as Node).get_parent() == null:
				main.world.add_child(n)
		cloth.global_position = top + Vector3(0, 0.005, 0)
		crown.global_position = top + Vector3(0, 0.02, 0)
		candle.global_position = top + Vector3(0.35, 0.35, 0.25)
	return [
		{"from": [ig + Vector3(-2.2, 1.7, 1.4), ig + Vector3(0.4, 1.0, 0.0)], "to": [ig + Vector3(-1.6, 1.55, 1.0), ig + Vector3(0.5, 1.0, 0.0)], "dur": 5.0, "fov": 46.0, "music": "night",
			"lines": [[0.5, "", "他说完了。手还按在墙上那一道一道的划痕上。"]],
			"on_start": func():
				p.set_third_person(false)
				stage.call()},
		{"from": [top + Vector3(0.0, 0.55, 0.95), top + Vector3(0, 0.08, 0)], "to": [top + Vector3(0.0, 0.42, 0.62), top + Vector3(0, 0.08, 0)], "dur": 6.0, "fov": 38.0, "memory": true,
			"lines": [[0.5, "", "三十五年前，冠城。老王在半夜睁开眼，叫所有人出去。"]]},
		{"from": [top + Vector3(-0.55, 0.3, 0.35), top + Vector3(0, 0.1, 0)], "to": [top + Vector3(0.5, 0.32, 0.4), top + Vector3(0, 0.1, 0)], "dur": 6.5, "fov": 34.0, "cut": true, "memory": true,
			"lines": [[0.4, "", "他从枕边拿起铁冠，亲手放进一个从双钥港来的人手里。"], [3.6, "", "那人手上戴着一枚戒指：两把钥匙，交叉着。"]]},
		{"from": [Vector3(Scriptorium.TALLY_WALL_X - 0.9, 1.3, 0.4), Vector3(Scriptorium.TALLY_WALL_X, 1.25, 0.4)], "to": [Vector3(Scriptorium.TALLY_WALL_X - 0.6, 1.25, 0.2), Vector3(Scriptorium.TALLY_WALL_X, 1.2, 0.3)], "dur": 5.0, "fov": 40.0, "cut": true, "memory": true,
			"lines": [[0.4, "", "第二天，王城里的人说冠被偷了。他什么都没说。"]]},
		{"from": [Vector3(-2.0, 1.5, 1.6), Vector3(Scriptorium.WIN_X, Scriptorium.WIN_Y + 0.6, -2.4)], "to": [Vector3(-1.6, 1.4, 1.2), Vector3(Scriptorium.WIN_X, Scriptorium.WIN_Y + 0.7, -2.4)], "dur": 5.0, "fov": 44.0, "cut": true,
			"lines": [[0.5, "", "高窗外，天快亮了。"]],
			"on_start": func():
				for n in [crown, candle, cloth]:
					if is_instance_valid(n):
						(n as Node).queue_free()},
	]


## 铁冠（过场的道具）：一圈黑铁，十个齿，铆钉；只有回忆和金库里用
static func _crown() -> Node3D:
	var root := Node3D.new()
	root.name = "CutCrown"
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color("3a3634")
	iron.metallic = 0.6
	iron.roughness = 0.45
	var n := 20
	var r := 0.1
	for i in n:
		var a := TAU * i / n
		var seg := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(TAU * r / n * 1.05, 0.045, 0.012)
		seg.mesh = b
		seg.material_override = iron
		seg.position = Vector3(cos(a) * r, 0.022, sin(a) * r)
		seg.rotation.y = -a + PI * 0.5
		root.add_child(seg)
		if i % 2 == 0:
			var spike := MeshInstance3D.new()
			var pm := PrismMesh.new()
			pm.size = Vector3(0.03, 0.05, 0.01)
			spike.mesh = pm
			spike.material_override = iron
			spike.position = Vector3(cos(a) * r, 0.07, sin(a) * r)
			spike.rotation.y = -a + PI * 0.5
			root.add_child(spike)
	return root


## 冬井那一圈（2-4）：井在 HighlandLayout.WELL，长眠者站成半径 WinterWell.RING_R 的一圈；诺伯特停在井外 STOP_R 米
static func well_ring(main: Node) -> Array:
	var p: FpController = main.player
	var w2: Vector2 = HighlandLayout.WELL
	var w := WinterWell.ground(w2)
	var nb := main.world.find_child("Npc_norbert_well", true, false) as Node3D
	var nbp: Vector3 = nb.global_position if nb else WinterWell.ground(w2 + Vector2(0, WinterWell.STOP_R))
	var away := Vector3(nbp.x - w.x, 0, nbp.z - w.z).normalized()          # 从井指向诺伯特（你们站的那一边）
	var side := Vector3(-away.z, 0, away.x)
	var face_at := w + Vector3(cos(0.6), 0, sin(0.6)) * WinterWell.RING_R + Vector3(0, 1.55, 0)      # 圈上一张脸
	return [
		{"from": [w + away * 22.0 + side * 10.0 + Vector3(0, 13.0, 0), w + Vector3(0, 1.0, 0)], "to": [w + away * 15.0 - side * 6.0 + Vector3(0, 9.0, 0), w + Vector3(0, 1.0, 0)], "dur": 6.5, "fov": 48.0, "music": "well",
			"lines": [[0.7, "", "冰原上一口石井。长眠的人围着它站成一圈，一动不动。"]],
			"on_start": func(): p.set_third_person(true)},
		{"from": [w + Vector3(0, 1.45, 0) + (face_at - w).normalized() * 1.2 * Vector3(1, 0, 1), face_at], "to": [w + Vector3(0, 1.5, 0) + (face_at - w).normalized() * 2.4 * Vector3(1, 0, 1), face_at], "dur": 5.0, "fov": 40.0, "cut": true,
			"lines": [[0.5, "", "它们闭着眼睛，脸都朝着井。"]]},
		{"from": [nbp + away * 3.2 + side * 1.4 + Vector3(0, 1.8, 0), w + Vector3(0, 1.0, 0)], "to": [nbp + away * 2.6 + side * 1.0 + Vector3(0, 1.75, 0), w + Vector3(0, 1.0, 0)], "dur": 6.5, "fov": 44.0, "cut": true,
			"talk": nb, "lines": [[0.4, "诺伯特", "……三十五年，我头一回走到这口井边。"], [3.4, "诺伯特", "它们没往北走。它们在这儿站着——像在等一样东西。"]]},
		{"from": [w + away * 10.0 + Vector3(0, 5.0, 0), w + Vector3(0, 0.5, 0)], "to": [w + away * 26.0 + side * 4.0 + Vector3(0, 20.0, 0), w], "dur": 6.0, "fov": 46.0, "cut": true},
	]


## 家主临终（1-3）：病房 5.6 × 5 米，床靠北墙（床头朝北），东墙窄窗、西南角炭盆；守夜的人：床尾的继承人（守住了）或者床边的玛尔塔
static func osric_dawn(main: Node) -> Array:
	var p: FpController = main.player
	var watcher: Node3D = null
	for n in main.world.find_children("Npc_*", "Npc", true, false):
		if str(n.name) in ["Npc_alric", "Npc_ivette", "Npc_heir"] or (n as Npc).display_name in ["阿尔里克", "伊薇特"]:
			watcher = n
	if watcher == null:
		watcher = main.world.find_child("Npc_marta", true, false) as Node3D
	var wh: Vector3 = (watcher.global_position if watcher else Vector3(1.0, 0, -1.2)) + Vector3(0, 1.55, 0)
	var wf: Vector3 = Vector3(0.0, 1.6, 1.2) if watcher == null else watcher.global_position + (Vector3(0.2, 1.6, 1.4) - Vector3(0, 0, 0))
	var face := Vector3(-0.5, Sickroom.BED_TOP + 0.3, -2.3)          # 头朝北墙（躺着的人本地 +Z 是头，转了 180°）
	return [
		{"from": [Vector3(2.2, 2.6, 2.0), Vector3(-0.6, 0.6, -1.3)], "to": [Vector3(1.9, 2.35, 1.5), Vector3(-0.6, 0.6, -1.4)], "dur": 5.5, "fov": 52.0, "music": "night", "exposure": 1.15,
			"lines": [[0.6, "", "天亮了。窗缝里透进来一点灰光，炭盆快灭了。"]],
			"on_start": func(): p.set_third_person(false)},
		{"from": [wf, wh], "to": [wf.lerp(wh, 0.18), wh], "dur": 5.0, "fov": 40.0, "cut": true, "exposure": 1.1,
			"lines": [[0.5, "", "守了一夜的人都没出声。"]]},
		{"from": [Vector3(0.5, 0.98, -1.55), face - Vector3(0, 0.12, 0)], "to": [Vector3(0.25, 0.9, -1.85), face - Vector3(0, 0.12, 0)], "dur": 6.0, "fov": 36.0, "fov_to": 32.0, "cut": true, "exposure": 1.1,
			"lines": [[0.8, "", "他睁开眼睛，找的是你。"]]},
	]


## 渡口对峙（0-2）：码头沿南北向伸进河里（Ferry.PIER_X0..X1，尽头 z = 14），奥弗站在码头根上（2.1, 2.4）面朝岸上，两个手下在岸上左右；
## 你从北头的坡上下来（z ≈ -26.5）
static func ferry_standoff(main: Node) -> Array:
	var p: FpController = main.player
	var d := Ferry.DECK_Y
	return [
		{"from": [Vector3(12.5, 3.4, -11.0), Vector3(2.5, 0.6, 9.0)], "to": [Vector3(10.0, 2.7, -5.5), Vector3(2.5, 0.8, 10.0)], "dur": 5.5, "fov": 50.0, "music": "battle",
			"lines": [[0.6, "", "渡口。灰鲸河上起了雾，渡船拴在码头尽头。"]],
			"on_start": func(): p.set_third_person(true)},
		{"from": [Vector3(5.6, d + 1.7, 7.4), Vector3(2.3, d + 1.45, 11.0)], "to": [Vector3(4.6, d + 1.65, 8.3), Vector3(2.3, d + 1.5, 11.0)], "dur": 6.0, "fov": 42.0, "cut": true, "exposure": 0.9,
			"lines": [[0.4, "塞拉斯", "东西都带来了？天一亮就开船。"], [3.2, "埃德里克", "……就这一张。别让我父亲知道。"]]},
		{"from": [Vector3(2.6, d + 1.0, 5.2), Vector3(2.1, d + 1.6, 2.4)], "to": [Vector3(2.4, d + 1.4, 4.0), Vector3(2.1, d + 1.62, 2.4)], "dur": 5.0, "fov": 38.0, "cut": true,
			"lines": [[0.5, "", "芦苇里走出来一伙人。领头的高个子，左手戴着一只磨亮了的灰皮手套。"]]},
		{"from": [Vector3(0.8, 2.2, -13.5), Vector3(2.0, 1.1, 1.5)], "to": [Vector3(1.0, 2.0, -8.5), Vector3(2.0, 1.2, 1.5)], "dur": 4.5, "fov": 46.0, "cut": true,
			"lines": [[0.3, "", "他们也看见你了。"]]},
	]


## 开场：夜空 → 屋顶 → 街灯 → 宅邸门口的你。霜渡镇的主街南北走向（南门 z ≈ 11，宅邸在北头 z ≈ -46），你站在宅邸门口（0, -44.3）面朝南
static func prologue(main: Node) -> Array:
	var p: FpController = main.player
	return [
		{"from": [Vector3(0, 19, 21), Vector3(0, 6, -6)], "to": [Vector3(0, 14, 11), Vector3(0, 1.5, -20)], "dur": 7.0, "fov": 55.0, "music": "night",      # 雾大：机位不能太高太远，不然只看得见雾
			"lines": [[0.8, "", "冠历六四三年秋，老王奥雷利安三世在冠城暴毙。"], [4.0, "", "守灵夜里，铁冠不见了。"]],
			"on_start": func():
				if p.global_position.distance_to(Vector3(0, 0, -44.3)) > 3.0:     # 预览 / 录视频时人不在宅邸门口：站过去（正常开场本来就在那儿）
					p.global_position = Vector3(0, 0.05, -44.3)
					p.rotation.y = PI
				p.set_third_person(true)},
		{"from": [Vector3(0.6, 13.0, 4.0), Vector3(0, 2.0, -24)], "to": [Vector3(0.6, 10.0, -14.0), Vector3(0, 1.5, -40)], "dur": 7.0, "fov": 50.0,
			"lines": [[0.6, "", "三年过去，王位空着。"], [3.4, "", "没有加冕的冬天，一年比一年长。"]]},
		{"from": [Vector3(-1.1, 1.6, -4.0), Vector3(0.5, 1.6, -30)], "to": [Vector3(-0.9, 1.7, -22.0), Vector3(0.4, 2.0, -42)], "dur": 6.5, "fov": 46.0,
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
