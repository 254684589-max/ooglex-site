class_name WellRooms
extends RefCounted
## 冬井底（路线图 8.3；STORY.md 8.2「冬井的石盖底下一道冻住的铁链、一道凿在井壁上的石阶；井底是一间冰做的圆厅：当中一块半埋在冰里的星铁（王国的那颗星），
## 四周冰壁里一排一排刻着名字——历代封誓的人，最后一个名字刻在约四百年前；星铁前一张石台、一个嵌誓瓶的凹槽、一个冠形的凹槽」）。
## 搭屋子、碰撞、出口用双钥港室内那一套（HarborRooms._room / _colliders / _exit，房间登记在 HarborRooms.SPEC，出去回 highland 的 well 出生点）。
## 住着谁：没有人——井口上那一圈人的脸都朝着这儿；缺什么：火——四角四个铁火盆是冷的，四百年没人点过；刚发生过什么：冰壁上最后一个名字的后面，是一大片空着的冰。
## 圆厅：方的屋子四面贴着冰壁（冰是半透明的淡蓝色，里面刻着字）；南边一道石阶从顶上的井口下来；当中星铁、石台；四角火盆（8.4 封誓时点）。

const STAR := Vector3(0.0, 0, -3.0)                     # 星铁：北半边当中，半埋在冰里
const ALTAR := Vector3(0.0, 0, -0.8)                    # 石台：星铁前面
const BRAZIERS := [Vector3(-4.6, 0, -4.6), Vector3(4.6, 0, -4.6), Vector3(-4.6, 0, 3.4), Vector3(4.6, 0, 3.4)]
const NAMES_TEXT := "冰壁里一排一排刻着名字，刀口里结着霜。最上头一行认得出：「哈尔文」。往下是一个接一个的名字，有的是王，有的不是——「守塔人伯恩」「渡工之女玛丽」「无名」。最后一个名字刻在约四百年前：「奥斯温，冠历三百九十七年」。再往下，是一大片空着的冰。"
const STAR_TEXT := "一块黑得发亮的铁，比一个人还高，一半埋在冰里。手放上去，冷得像握住了一整个冬天。这就是王国的那颗星。"
const ALTAR_TEXT := "星铁前一张矮石台，台面上两个凹槽：一个冠形的，和议事厅王座椅背上那个一模一样；一个誓瓶大小的，底下一道细细的槽，一直通到星铁脚下。"
const BRAZIER_TEXT := "一个铁火盆，盆里是四百年前的冷灰。"


static func _ice() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.62, 0.76, 0.86, 0.78)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.12
	m.metallic = 0.1
	m.emission_enabled = true
	m.emission = Color("3a5a78")
	m.emission_energy_multiplier = 0.35
	m.vertex_color_use_as_albedo = true
	return m


static func _star() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("16181c")
	m.metallic = 0.9
	m.roughness = 0.25
	m.vertex_color_use_as_albedo = true
	return m


static func build(parent: Node3D, reduced_motion: bool) -> void:
	var kit := MeshKit.new()
	HarborRooms._room(kit, "well_bottom", [])
	var s: Dictionary = HarborRooms.SPEC["well_bottom"]
	var w := float(s.w)
	var d := float(s.d)
	var h := float(s.h)
	var rng := RandomNumberGenerator.new()
	rng.seed = 8301
	for side: float in [-1.0, 1.0]:                                      # 冰壁：东西两面、北面贴一层冰，冰里一行一行的名字
		kit.box("ice", Vector3(side * (w * 0.5 - 0.15), h * 0.5, -0.5), Vector3(0.3, h, d - 1.0), Basis.IDENTITY, 1.0, 0.8)
	kit.box("ice", Vector3(0, h * 0.5, -d * 0.5 + 0.15), Vector3(w, h, 0.3), Basis.IDENTITY, 1.0, 0.8)
	kit.box("ice", Vector3(0, 0.03, -0.5), Vector3(w - 0.6, 0.06, d - 1.6), Basis.IDENTITY, 1.0, 1.0)          # 冰面
	for wall in 3:
		var rows := 7
		for r in rows:
			var y := 0.8 + r * 0.62
			var n := 9 if wall == 1 else 7
			for k in n:
				if wall == 0 and r < 2 and k > 2:                         # 最后几行：名字刻到一半就停了（约四百年前），往下是空的冰
					continue
				var len := rng.randf_range(0.35, 0.8)
				var t := -0.5 * (d - 2.0) + (k + 0.5) * (d - 2.0) / n if wall != 1 else -0.5 * (w - 2.0) + (k + 0.5) * (w - 2.0) / n
				match wall:
					0:
						kit.box("ink", Vector3(-w * 0.5 + 0.33, y, t - 0.5), Vector3(0.02, 0.06, len))
					1:
						kit.box("ink", Vector3(t, y, -d * 0.5 + 0.33), Vector3(len, 0.06, 0.02))
					2:
						kit.box("ink", Vector3(w * 0.5 - 0.33, y, t - 0.5), Vector3(0.02, 0.06, len))
	# 南边：从顶上井口下来的石阶（贴着南墙往东走上去）、垂下来的铁链
	for k in 10:
		kit.box("stone", Vector3(-3.6 + k * 0.62, 0.17 + k * 0.34, d * 0.5 - 0.7), Vector3(0.62, 0.34, 1.0), Basis.IDENTITY, 0.8, 0.6)
	kit.box("ink", Vector3(2.8, h - 0.02, d * 0.5 - 0.9), Vector3(1.8, 0.04, 1.6))
	for k in 12:
		kit.cylinder("iron", Vector3(2.8, h - k * 0.4, d * 0.5 - 1.2), Vector3(2.8, h - (k + 1) * 0.4, d * 0.5 - 1.2), 0.03, 0.03, 5)
	# 星铁：几块黑亮的铁斜着戳出冰面
	for k in 5:
		var off := Vector3(rng.randf_range(-0.8, 0.8), 0, rng.randf_range(-0.5, 0.5))
		var hh := rng.randf_range(1.0, 2.4)
		kit.box("star", STAR + off + Vector3(0, hh * 0.45, 0), Vector3(rng.randf_range(0.7, 1.3), hh, rng.randf_range(0.6, 1.1)), Basis(Vector3.UP, rng.randf() * PI) * Basis(Vector3.RIGHT, rng.randf_range(-0.3, 0.3)), 1.0, 0.6)
	kit.box("ice", STAR + Vector3(0, 0.25, 0), Vector3(3.2, 0.5, 2.4), Basis.IDENTITY, 1.0, 0.9)
	# 石台：一个冠形的凹槽、一个誓瓶大小的凹槽，一道细槽通到星铁脚下
	kit.box("castle", ALTAR + Vector3(0, 0.45, 0), Vector3(1.8, 0.9, 0.9), Basis.IDENTITY, 0.85, 0.6)
	kit.box("ink", ALTAR + Vector3(-0.4, 0.91, 0), Vector3(0.55, 0.02, 0.4))
	kit.cylinder("ink", ALTAR + Vector3(0.45, 0.9, 0), ALTAR + Vector3(0.45, 0.92, 0), 0.12, 0.12, 8)
	kit.box("ink", ALTAR + Vector3(0.45, 0.91, -0.7), Vector3(0.04, 0.02, 1.0))
	for b: Vector3 in BRAZIERS:                                          # 四角四个铁火盆（冷的）
		kit.cylinder("iron", b, b + Vector3(0, 0.75, 0), 0.08, 0.08, 6)
		kit.cylinder("iron", b + Vector3(0, 0.75, 0), b + Vector3(0, 1.0, 0), 0.3, 0.5, 10)
		kit.cylinder("ink", b + Vector3(0, 0.96, 0), b + Vector3(0, 0.98, 0), 0.45, 0.45, 10)
	var m := HarborRooms._mats()
	m["floor"] = Look.mat("stone")
	m["ice"] = _ice()
	m["star"] = _star()
	var mi := kit.build(m)
	mi.name = "Room_well_bottom"
	parent.add_child(mi)
	for k in 10:
		Inn._solid(parent, Vector3(-3.6 + k * 0.62, 0.17 + k * 0.34, d * 0.5 - 0.7), Vector3(0.62, 0.34, 1.0))
	Inn._solid(parent, STAR + Vector3(0, 1.2, 0), Vector3(2.8, 2.4, 2.0))
	Inn._solid(parent, ALTAR + Vector3(0, 0.45, 0), Vector3(1.8, 0.9, 0.9))
	for b: Vector3 in BRAZIERS:
		Inn._solid(parent, b + Vector3(0, 0.5, 0), Vector3(0.9, 1.0, 0.9))
	HarborRooms._examine(parent, "冰壁里的名字", "看看", NAMES_TEXT, Vector3(-w * 0.5 + 0.8, 1.4, -1.0), Vector3(0.8, 2.0, 4.0), "IceNames", "ch5_names_read")
	HarborRooms._examine(parent, "星铁", "看看", STAR_TEXT, STAR + Vector3(0, 1.2, 1.3), Vector3(2.6, 2.0, 0.8), "StarIron")
	for k in BRAZIERS.size():                                            # 铁火盆（8.4）：封誓的时候点着、添柴
		var kk := k
		var b := Examine.make("铁火盆", "看看", func(_who: FpController) -> Dictionary: return brazier(parent, kk), Vector3(1.0, 1.0, 1.0))
		b.name = "Brazier%d" % k
		b.position = BRAZIERS[k] + Vector3(0, 0.8, 0)
		b.verb_fn = func() -> String:
			var r := parent.get_node_or_null("OathRitual") as OathRitual
			if r == null or r.done != "":
				return "看看"
			return "添柴" if r.lit(kk) else "点着火盆"
		parent.add_child(b)
	var al := Examine.make("石台", "看看", func(_who: FpController) -> Dictionary: return altar(), Vector3(1.8, 1.0, 0.6))   # 石台（8.4）：封誓从这儿开始
	al.name = "Altar"
	al.position = ALTAR + Vector3(0, 0.7, 0.6)
	al.verb_fn = func() -> String: return "封誓" if GameState.quest_stage("ch5_main") == "oath" and not GameState.has_flag("ch5_ritual") else "看看"
	parent.add_child(al)
	for p: Vector3 in [Vector3(-3.0, 4.0, -2.0), Vector3(3.0, 4.0, -2.0), Vector3(0, 3.6, 3.0)]:
		var f := OmniLight3D.new()
		f.light_color = Color("7a9ec0")
		f.light_energy = 1.3
		f.omni_range = 9.0
		f.position = p
		parent.add_child(f)
	var glow := OmniLight3D.new()                                        # 星铁底下透上来的一点光
	glow.light_color = Color("a8c8e8")
	glow.light_energy = 0.9
	glow.omni_range = 4.0
	glow.position = STAR + Vector3(0, 0.3, 1.4)
	parent.add_child(glow)


## 石台（8.4）：主线到了「封誓」、还没开始，就打开石台前的对话（winter.json oath：谁来留名）
static func altar() -> Dictionary:
	GameState.set_flag("ch5_altar_seen")
	if GameState.quest_stage("ch5_main") == "oath" and not GameState.has_flag("ch5_ritual"):
		return {"kind": "dialogue", "area": "winter", "id": "oath", "name": "石台"}
	return {"toast": ALTAR_TEXT}


## 火盆（8.4）：封誓的时候点着、添柴；平时只是冷灰
static func brazier(parent: Node3D, k: int) -> Dictionary:
	var r := parent.get_node_or_null("OathRitual") as OathRitual
	if r == null:
		return {"toast": BRAZIER_TEXT}
	return r.feed(k)


## 井底的人（8.3）：同行的人捧着冠站在石台边；随她去了的妮尔站在西面冰壁前，睁着眼
static func people() -> Array:
	var out := []
	var c := Winter5.companion()
	if not c.is_empty():
		out.append(["companion_well", str(c[1]), Vector3(1.9, 0, 0.4), -150.0, ["（捧着那只铁匣，看着石台上那个冠形的凹槽）", "……和议事厅王座上那个一模一样。"]])
	if str(GameState.get_flag("ch2_nell", "")) == "left":
		out.append(["nell_well", "妮尔", Vector3(-5.6, 0, -1.4), 90.0, [], "nell5"])
	return out


static func build_people(parent: Node3D) -> void:
	if GameState.quest_stage("ch5_main") == "descend":
		GameState.set_stage("ch5_main", "oath")                          # 下到了井底（8.3）：主线到「封誓」
	for it: Array in people():
		var n := Npc.make(str(it[1]), it[4], Color("5a5650"))
		n.name = "Npc_" + str(it[0])
		if it.size() > 5:
			n.dialogue_area = "winter"
			n.dialogue_id = str(it[5])
		n.position = it[2]
		n.rotation.y = deg_to_rad(float(it[3]))
		parent.add_child(n)


static func map_shapes() -> Array:
	return [{"k": "furniture", "rect": Rect2(STAR.x - 1.4, STAR.z - 1.0, 2.8, 2.0), "label": "星铁"}, {"k": "furniture", "rect": Rect2(ALTAR.x - 0.9, ALTAR.z - 0.45, 1.8, 0.9), "label": "石台"},
		{"k": "furniture", "rect": Rect2(-3.9, 4.5, 6.2, 1.0), "label": "石阶"}]
