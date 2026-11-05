class_name PlainPeople
extends RefCounted
## 金穗平原主线第 3–4 步的人（路线图 6.3d；STORY.md 6.5 第 4 步「麦渡与塞弗林营地（顺序随意）」）：
##   麦渡村西头那栋空屋旁边，佃农头老贝恩守着一座小坟（伊达的男人，去年腊月饿死的：雪里一个小土包、插着一块劈开的木板，板上刻着名字）；
##   塞弗林营地：征粮官奥迪隆在指挥帐里的桌边倒酒（第一章那个进了黑鹭堡的信使，同一身打扮），营地口木桩那儿两个哨兵，熔炉车旁跟车的铁匠。
## 对话在 data/dialogue/plain.json（bain、odilon）；路人只说一句。庄园大厅里的伊莎贝拉、塞缪尔在 ManorHall.people。

const GRAVE := Vector2(-83.4, 16.2)          # 麦渡村西头空屋（PlainVillage.LONGHOUSES 的 empty）的东北角外，离墙角两米多
const BAIN := [Vector2(-81.9, 17.3), -119.0]  # 坟边，面朝村子
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
		["camp_smith", "跟车的铁匠", PlainCamp.at(PlainCamp.FORGE[0], PlainCamp.FORGE[1] + 2.2), PlainCamp.YAW_ALONG + 90.0, "3a2e24", "", SMITH_LINES],
	]
	for it: Array in list:
		var at: Vector2 = it[2]
		var n := Npc.make(str(it[1]), it[6], Color(str(it[4])))
		n.name = "Npc_" + str(it[0])
		if str(it[5]) != "":
			n.dialogue_area = "plain"
			n.dialogue_id = str(it[5])
		n.position = Vector3(at.x, ground(at), at.y)
		n.rotation.y = deg_to_rad(float(it[3]))
		parent.add_child(n)
	_grave(parent)


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
