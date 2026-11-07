class_name Winter5
extends Node3D
## 第五章的余火高地（路线图 8.2；STORY.md 8.5 第 4–5 步「三天后的黄昏到羊脊村……第十九烽：火亮着的，诺伯特在塔顶等你，把那只三十五年前的空誓瓶交给你；
## 火灭了的，他已经一个人去了井边，瓶在塔顶小屋的炉灰里」「入夜，山脊背后的井边，长眠者站成了更大的一圈」）。同一张地图（Highland），第五章叠一层：
##   诺伯特：火亮着（ch2_fire = lit）在塔顶火盆边（对话 winter.json norbert5，给誓瓶）；灭了在井边（norbert5_well），誓瓶在塔里小屋的炉灰里（BeaconTower 那一间，Examine）；
##   井边：第二章那一圈（WinterWell）外面再站一圈（OUTER_N 个，OUTER_R 米）；同行的人（按 crown_holder）先到了井边；
##   井口的石盖：主线到了 well、誓瓶在手、冠在（你手里或者同行的人手里）就能掀开（8.3 下到井底）。
## 第二章的诺伯特（塔顶、小屋、山脊背后）在第五章不放（HighlandBeacon / BeaconTower / WinterWell 看 active()）。

const OUTER_N := 24
const OUTER_R := 8.6
const NORBERT_WELL := Vector2(-26.0, -104.0)       # 火灭了：诺伯特一个人先到了井边（井的东南，背对着来路）
const COMPANION_AT := Vector2(-13.6, -105.8)        # 同行的人：井的东边，离圈两三米
const LID_TEXT_DARK := "裂成两半的石盖底下是黑的，一股冷气从井里冒上来。铁链冻在井栏上，往下垂进黑里。"
const STAGES := ["north", "vial", "well", "descend", "oath"]

var ww: WinterWell


## 第五章、主线「冬井」在北上以后
static func active() -> bool:
	return GameState.chapter >= 5 and str(GameState.quest_stage("ch5_main")) in STAGES


## 同行的人：[编号, 名字, 看 looks.json 的名字]；没有人跟你（冠在你手里、或者回了钥楼）返回 []
static func companion() -> Array:
	match str(GameState.get_flag("crown_holder", "")):
		"severin":
			return ["young_bertrand", "小贝尔特兰", "小贝尔特兰"]
		"lomond":
			return ["isabella", "伊莎贝拉·洛蒙德", "伊莎贝拉·洛蒙德"]
		"valen":
			return ["ivette", "伊薇特", "伊薇特"] if str(GameState.get_flag("valen_heir", "")) == "ivette" else ["alric", "阿尔里克", "阿尔里克"]
		"church":
			return ["lucien", "大主祭卢西安", "大主祭卢西安"]
	return []


## 冠在不在北边：你手里，或者同行的人带着
static func crown_here() -> bool:
	return GameState.has_item("iron_crown") or not companion().is_empty()


static func fire_lit() -> bool:
	return str(GameState.get_flag("ch2_fire", "")) == "lit"


## 到了高地（main 进区域时调）：主线 north → vial；记下同行的人；冠回了钥楼的，科尔温的人在码头上把冠借给你
static func arrived() -> String:
	if GameState.chapter < 5 or GameState.quest_stage("ch5_main") != "north":
		return ""
	var c := companion()
	GameState.set_flag("ch5_companion", str(c[0]) if not c.is_empty() else "none")
	var note := ""
	if str(GameState.get_flag("crown_holder", "")) == "caswell" and not GameState.has_item("iron_crown"):
		GameState.add_item("iron_crown")
		note = "临上船，科尔温的人在码头上把那只星铁包角的铁匣塞给你：「借你一冬。利息另算。」"
	GameState.set_stage("ch5_main", "vial")
	return note


## 拿到了诺伯特的誓瓶：主线 vial → well
static func got_vial() -> void:
	if GameState.quest_stage("ch5_main") == "vial":
		GameState.set_stage("ch5_main", "well")


## 塔里小屋的炉灰（火灭了的那条线）：誓瓶在里面
static func hearth_vial() -> Dictionary:
	if GameState.has_item("oath_vial"):
		return {"toast": "炉子冷透了。灰里还留着一个瓶底大小的印子。"}
	if GameState.chapter < 5 or not active() or fire_lit():
		return {"toast": "小铁炉里的灰是冷的。"}
	GameState.add_item("oath_vial")
	GameState.set_flag("ch5_vial", "ashes")
	got_vial()
	return {"toast": "你在冷透了的炉灰里摸到一只小瓶：灰白的陶，瓶口封着一圈老蜡，蜡上压着一道冠形的印——是空的。诺伯特把它留在这儿，自己去了井边。（得到：空誓瓶）"}


## 井口的石盖：主线到了 well、誓瓶在手、冠在北边，就掀开（8.3：下到井底）
static func lid() -> Dictionary:
	if not active():
		return {"toast": LID_TEXT_DARK}
	if GameState.quest_stage("ch5_main") in ["vial", "north"]:
		return {"toast": LID_TEXT_DARK + "（先去第十九烽找诺伯特——那只空誓瓶在他手里）"}
	if not GameState.has_item("oath_vial"):
		return {"toast": LID_TEXT_DARK + "（誓瓶不在你手里）"}
	if not crown_here():
		return {"toast": LID_TEXT_DARK + "（冠不在北边：没有钥匙）"}
	GameState.set_flag("ch5_lid_open")
	if GameState.quest_stage("ch5_main") == "well":
		GameState.set_stage("ch5_main", "descend")
	if Areas.known("well_bottom"):
		return {"kind": "travel", "area": "well_bottom", "spawn": "front", "name": "冬井", "toast": ("你和%s一起把那半块石盖推开。" % str(companion()[1]) if not companion().is_empty() else "你一个人把那半块石盖推开。") + "井壁上凿着一道石阶，往下，再往下。"}
	return {"toast": "你把那半块石盖推开了。井壁上凿着一道石阶，往下是黑的。（第五章还在制作中：井底是下一步）"}


static func setup(world: Node3D) -> Winter5:
	if not active():
		return null
	var w := Winter5.new()
	w.name = "Winter5"
	world.add_child(w)
	return w


func _ready() -> void:
	ww = get_parent().get_node_or_null("WinterWell") as WinterWell
	if ww:
		ww._build_ring()
		_outer_ring()
	_people()
	var l := Examine.make("井口的石盖", "掀开石盖", func(_who: FpController) -> Dictionary: return lid(), Vector3(2.6, 1.4, 2.6))
	l.name = "WellLid"
	l.position = WinterWell.ground(HighlandLayout.WELL)
	l.verb_fn = func() -> String: return "掀开石盖" if active() and GameState.quest_stage("ch5_main") in ["well", "descend", "oath"] else "看看"
	add_child(l)


## 第二章那一圈外面再站一圈：三天里又有人走过来了（生人，麻衣光脚）
func _outer_ring() -> void:
	var ring := Node3D.new()
	ring.name = "WellRingOuter"
	add_child(ring)
	for k in OUTER_N:
		var spec := Looks.spec_of({"preset": "woman" if k % 3 == 2 else "commoner", "hair": [["Hair_Long"], ["Hair_Buzzed", "Hair_Beard"], ["Hair_SimpleParted"], ["Hair_Buzzed"]][k % 4],
			"hair_color": ["#2a2018", "#9a948a", "#3a2a1a", "#c8c4bc", "#6a5a4a"][k % 5]})
		if spec.is_empty():
			continue
		SleeperCrowd.chill(spec)
		var a := TAU * k / OUTER_N + 0.31
		var p := HighlandLayout.WELL + Vector2(cos(a), sin(a)) * (OUTER_R + 0.4 * sin(k * 1.7))
		if p.distance_to(COMPANION_AT) < 2.0 or p.distance_to(NORBERT_WELL) < 2.0:
			continue
		var m := CharacterModel.new()
		m.name = "WellOuter%d" % k
		m.parts = spec.parts
		m.look = spec.look
		ring.add_child(m)
		m.global_position = WinterWell.ground(p)
		var to := HighlandLayout.WELL - p
		m.rotation.y = atan2(to.x, to.y) + 0.05 * sin(k * 1.9)
		if m.loaded:
			Looks.hide_parts(m)
			m.hold("idle", 0.15 + 0.05 * (k % 6))
			for mi: MeshInstance3D in m.scene_root.find_children("*", "MeshInstance3D", true, false):
				mi.visibility_range_end = Looks.LOD_FAR
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _people() -> void:
	if fire_lit():                                                       # 火亮着：诺伯特在塔顶火盆边等你
		var tp := HighlandBeacon.tower_place()
		var at := tp * Vector3(-1.25, HighlandLayout.TOWER_H, -0.5)
		_npc("norbert5", "诺伯特", at, deg_to_rad(float(HighlandLayout.TOWER[1])) - PI * 0.5, "norbert5", [])
	else:                                                                # 火灭了：他一个人先去了井边
		var np := NORBERT_WELL
		_npc("norbert5", "诺伯特", WinterWell.ground(np), _face(np), "norbert5_well", [])
	if Origins.current() == "deserter" or str(GameState.get_flag("ch2_roll", "")) == "served":     # 支线「第二十一烽的人」（8.4）：马蒂亚斯举着火把在井边
		var mp := Vector2(-25.0, -118.0)
		_npc("matthias5", "马蒂亚斯", WinterWell.ground(mp), _face(mp), "matthias5", [])
	var c := companion()
	if not c.is_empty():
		var lines := {"young_bertrand": ["（他把那只铁匣抱在怀里，抱得太紧了）……祖父说，戴上它就行了。", "（他看着那一圈人，往你身后退了一步）"],
			"isabella": ["（她把斗篷裹紧）洛蒙德家替王国还的账，原来是还到这儿来了。", "（她看着井，很久没说话）"],
			"ivette": ["（她站在井边，像站在黑鹭堡的堡门口）北境的人，总是自己往北走。", "（她把冠抱在胸前）"],
			"alric": ["（他看着那一圈人，脸色发白）……我不想来。可我更不想让别人来。", "（他没有走近那一圈）"],
			"lucien": ["（他捧着铁匣，嘴唇在动，像在念什么）四百年了。", "（他看着石盖上那几道磨平的线）这是教会的字。"]}
		_npc("companion", str(c[1]), WinterWell.ground(COMPANION_AT), _face(COMPANION_AT), "", lines.get(str(c[0]), []))


func _npc(id: String, nm: String, at: Vector3, yaw: float, dlg: String, lines: Array) -> void:
	var n := Npc.make(nm, lines, Color("5a5650"))
	n.name = "Npc_" + id
	if dlg != "":
		n.dialogue_area = "winter"
		n.dialogue_id = dlg
	n.position = at
	n.rotation.y = yaw
	n.far_end = 90.0
	add_child(n)


static func _face(p: Vector2) -> float:
	var to := HighlandLayout.WELL - p
	return atan2(-to.x, -to.y)
