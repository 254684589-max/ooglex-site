class_name PlainPeople
extends RefCounted
## 金穗平原主线第 3–4 步的人（路线图 6.3d；STORY.md 6.5 第 4 步「麦渡与塞弗林营地（顺序随意）」）：
##   麦渡村西头那栋空屋旁边，佃农头老贝恩守着一座小坟（伊达的男人，去年腊月饿死的：雪里一个小土包、插着一块劈开的木板，板上刻着名字）；
##   塞弗林营地：征粮官奥迪隆在指挥帐里的桌边倒酒（第一章那个进了黑鹭堡的信使，同一身打扮），营地口木桩那儿两个哨兵，熔炉车旁跟车的铁匠。
## 6.4：渡口的船夫（boatman）、夜里坟边的伊达（白天她在坠星院门口排队，PlainAbbey.people）、抄经室门缝（贴着门听，ch3_ignaz_heard）。
## 对话在 data/dialogue/plain.json（bain、odilon、boatman、ida）；路人只说一句。庄园大厅里的伊莎贝拉、塞缪尔在 ManorHall.people。

const GRAVE := Vector2(-83.4, 16.2)          # 麦渡村西头空屋（PlainVillage.LONGHOUSES 的 empty）的东北角外，离墙角两米多
const BAIN := [Vector2(-81.9, 17.3), -119.0]  # 坟边，面朝村子
const BOATMAN := [Vector2(-19.6, 49.2), 37.0]  # 渡口栈桥岸上那头，面朝上岸的地方（出生点 dock）
const IDA_NIGHT := [Vector2(-82.6, 18.0), 150.0]  # 夜里伊达不在坠星院门口排队：在麦渡那座小坟边
const LISTEN_AT := Vector2(61.15, 96.2)        # 抄经室门（PlainAbbey.SCRIPTORIUM 正面朝西）旁边的门缝
const CAPTAIN := [Vector2(16.8, -4.4), 180.0]    # 磨坊南门里、门洞东边，面朝南门（6.6）
const MILL_GUARDS := [[Vector2(25.8, -35.4), 0.0], [Vector2(29.2, -35.2), 10.0]]   # 北墙缺口里两个护院，面朝缺口
const MILL_GUARD_LINES := ["北墙这道口子，去年冬天就塌了。没人修，说是开春再说。", "女家主说塞弗林家的兵今晚要来。（他往手心哈了口气）来就来吧。"]
const PRY_AT := Vector2(33.0, -12.7)           # 第一座粮仓（PlainMill.GRANARIES[0]，门朝北）门边：开仓那一下（6.6）
const SENTRY_LINES := ["征粮官不见闲人。要见，自己往里走——手别往剑上放。", "砧山的冬天比这儿冷十倍。（他跺了跺脚）这儿的人还嫌冷。", "仓满着，人饿着。南边的规矩真怪。"]
const SMITH_LINES := ["枪头，马掌，钉子。征粮的营地，打的全是这些。", "（他把铁条塞回炭里）学徒跑哪儿去了……炉子一离人就凉。"]


## 主线第 4 步（顺序随意）：老贝恩的坟、奥迪隆的征粮令都看过了 → 「天黑以前决定站哪边」（main 每段对话结束时调）
static func sides_heard() -> bool:
	if GameState.quest_stage("ch3_main") == "sides" and GameState.has_flag("ch3_bain_grave") and GameState.has_flag("ch3_odilon_order"):
		GameState.set_stage("ch3_main", "choose")
		return true
	return false


static func ground(p: Vector2) -> float:
	return PlainLayout.height(p.x, p.y)


## 奥迪隆站在指挥帐里桌子朝门那一边（桌子让开中柱、他让开门口那条道），面朝门帘
static func odilon_at() -> Array:
	var pc := PlainCamp.at(PlainCamp.PAVILION[0], PlainCamp.PAVILION[1])
	var p := pc + PlainCamp.SIDE * 0.4 - PlainCamp.ALONG * 1.25
	return [p, PlainCamp.YAW_ALONG - 90.0]


static func build(parent: Node3D) -> void:
	var list := [
		["bain", "老贝恩", BAIN[0], float(BAIN[1]), "6a6052", "bain", []],
		["odilon", "奥迪隆", odilon_at()[0], float(odilon_at()[1]), "8a3a34", "odilon", []],
		["sentry1", "塞弗林家的哨兵", PlainCamp.at(PlainCamp.STAKES_U + 1.5, -3.2), PlainCamp.YAW_ALONG + 180.0, "6a2a26", "", SENTRY_LINES],
		["sentry2", "塞弗林家的哨兵", PlainCamp.at(PlainCamp.STAKES_U + 1.5, 3.2), PlainCamp.YAW_ALONG + 180.0 + 12.0, "6a2a26", "", SENTRY_LINES.slice(1)],
		["captain", "护院头目", CAPTAIN[0], float(CAPTAIN[1]), "2e4a32", "captain", []],
		["mill_guard1", "磨坊的护院", (MILL_GUARDS[0] as Array)[0], float((MILL_GUARDS[0] as Array)[1]), "2e4a32", "", MILL_GUARD_LINES],
		["mill_guard2", "磨坊的护院", (MILL_GUARDS[1] as Array)[0], float((MILL_GUARDS[1] as Array)[1]), "2e4a32", "", MILL_GUARD_LINES.slice(1)],
		["boatman", "渡口的船夫", BOATMAN[0], float(BOATMAN[1]), "4a4a44", "boatman", []],
		["camp_smith", "跟车的铁匠", PlainCamp.at(PlainCamp.FORGE[0], PlainCamp.FORGE[1] + 2.2), PlainCamp.YAW_ALONG + 90.0, "3a2e24", "", SMITH_LINES],
	]
	if str(GameState.get_flag("ch3_apprentice", "")) == "":                                  # 支线「熔炉车上的学徒」（6.5）：放走了、交出去了就不在了
		list.append(["apprentice", "熔炉车上的学徒", PlainCamp.at(PlainCamp.FORGE[0] + 2.6, PlainCamp.FORGE[1] - 1.5), PlainCamp.YAW_ALONG - 90.0, "3a3430", "apprentice", []])
	if GameState.daypart == "night":
		list.append(["ida", "伊达", IDA_NIGHT[0], float(IDA_NIGHT[1]), "5e5248", "ida", []])
	for it: Array in list:
		var at: Vector2 = it[2]
		var n := Npc.make(str(it[1]), it[6], Color(str(it[4])))
		n.name = "Npc_" + str(it[0])
		if str(it[5]) != "":
			n.dialogue_area = "plain"
			n.dialogue_id = str(it[5])
		n.position = Vector3(at.x, ground(at), at.y)
		n.rotation.y = deg_to_rad(float(it[3]))
		n.far_end = Plain.NPC_FAR
		n.label_far = Plain.LABEL_FAR
		if str(it[0]) == "apprentice":
			n.scale = Vector3.ONE * 0.88                    # 十四五岁
		parent.add_child(n)
	_grave(parent)
	_listen_door(parent)
	_pry(parent)


## 开仓（6.6，先开仓那条路）：主线在 open_granary 时，佃农的撬棍插进第一座粮仓的门缝——洛蒙德家 −20；
## 没说动护院头目（ch3_captain_aside）就撬的，护院撤回庄园（ch3_guards_left）。别的时候只是一扇锁着的仓门
static func pry_granary() -> Dictionary:
	if GameState.quest_stage("ch3_main") != "open_granary" or GameState.has_flag("ch3_granary_opened"):
		return {"toast": PlainMill.GRANARY_DOOR_TEXT}
	GameState.set_flag("ch3_granary_opened")
	GameState.change_rep("lomond", -20)
	var left := not GameState.has_flag("ch3_captain_aside")
	if left:
		GameState.set_flag("ch3_guards_left")
	GameState.set_stage("ch3_main", "to_mill_tenants")
	return {"toast": "老贝恩的撬棍插进门缝，三个人一起往下压——锁鼻子崩开了，麦子从门缝里淌出来，淌了一地。佃农们跪下去用手捧。" + ("\n护院头目看了一眼，带着他的人往庄园那边走了。今夜磨坊只有你们。" if left else "")}


static func _pry(parent: Node3D) -> void:
	var e := Examine.make("粮仓的门", "看看", func(_who: FpController) -> Dictionary: return pry_granary(), Vector3(1.2, 2.0, 0.8))
	e.name = "GranaryPry"
	e.position = Vector3(PRY_AT.x, ground(PRY_AT), PRY_AT.y)
	e.verb_fn = func() -> String: return "撬开粮仓" if GameState.quest_stage("ch3_main") == "open_granary" else "看看"
	parent.add_child(e)


## 抄经室锁着的门旁边：贴着门缝听（6.4）——里头那个人念的话按北边留下的事不一样：
## 名册上认下补守的（ch2_roll = served）听见「第二十一烽」；北边的火亮着（ch2_fire = lit）他问火还亮不亮；烽誓团逃兵听见「护送誓瓶北上的……」；不然只有一个「冠」字
static func listen_text() -> String:
	var heard := "门缝里透出一股冷气。里头有人在念，声音很低："
	if str(GameState.get_flag("ch2_roll", "")) == "served":
		heard += "「……第二十一烽……三年……逃……补……」念到这儿停了，像在听门外的脚步。"
	elif str(GameState.get_flag("ch2_fire", "")) == "lit":
		heard += "「……北边的火……还亮着吗……」——像是在问门外的人。"
	elif str(GameState.get_flag("origin", "")) == "deserter":
		heard += "「……护送誓瓶北上的……是烽誓团的人……蜡封……」后面听不清了。"
	else:
		heard += "「……冠……」然后是很久的静，然后是哭。"
	return heard


static func _listen_door(parent: Node3D) -> void:
	var e := Examine.make("抄经室的门缝", "贴着门听", func(_who: FpController) -> Dictionary:
		GameState.set_flag("ch3_ignaz_heard")
		return {"toast": listen_text()}, Vector3(0.5, 1.8, 0.5))
	e.name = "ScriptoriumListen"
	e.position = Vector3(LISTEN_AT.x, ground(LISTEN_AT), LISTEN_AT.y)
	parent.add_child(e)


## 伊达男人的坟：雪里一个小土包、一块劈开的木板（板上刻着名字），能看
static func _grave(parent: Node3D) -> void:
	var kit := MeshKit.new()
	var g := Vector3(GRAVE.x, ground(GRAVE), GRAVE.y)
	var b := Basis(Vector3.UP, deg_to_rad(45.0))
	for k in 3:                                                                                          # 土包：三层一层比一层小（方块一层像块石板，截图）
		var sz := Vector3(0.95 - k * 0.2, 0.12, 1.95 - k * 0.3)
		kit.box("mud", g + Vector3(0, 0.02 + k * 0.1 + 0.06, 0), sz, b * Basis(Vector3.UP, 0.04 * (k - 1)), 0.9, 0.55)
	kit.box("snow", g + b * Vector3(0.08, 0.33, 0.25), Vector3(0.38, 0.03, 0.9), b * Basis(Vector3.UP, 0.15), 1.0, 1.0)   # 背阴那半边留着一点雪
	var head := g + b * Vector3(0, 0, -1.05)
	var tilt := b * Basis(Vector3.FORWARD, 0.08) * Basis(Vector3.RIGHT, -0.06)
	kit.box("plank", head + Vector3(0, 0.5, 0), Vector3(0.26, 1.05, 0.05), tilt, 1.0, 0.7)           # 劈开的木板（新劈的，比房子的木头浅）
	kit.box("dark", head + tilt * Vector3(0, 0.22, 0.027), Vector3(0.16, 0.34, 0.004), tilt)             # 刀刻的名字（一道暗痕）
	var plank := StandardMaterial3D.new()
	plank.albedo_color = Color("9a8466")
	plank.roughness = 0.95
	plank.vertex_color_use_as_albedo = true
	var mi := kit.build({"mud": Look.mat("mud"), "snow": Look.mat("snow"), "plank": plank, "dark": PlainVillage.dark()})
	mi.name = "IdaGrave"
	parent.add_child(mi)
	var e := Examine.make("一座小坟", "看看", func(_who: FpController) -> Dictionary:
		return {"toast": "雪里一个小土包，插着一块劈开的木板。板上用刀刻着一个名字，刻得很深。" + ("老贝恩说，是伊达的男人，去年腊月饿死的。" if GameState.has_flag("ch3_bain_grave") else "")}, Vector3(1.2, 1.0, 2.0))
	e.name = "IdaGraveLook"
	e.position = g
	e.rotation.y = deg_to_rad(45.0)
	parent.add_child(e)
