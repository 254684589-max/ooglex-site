class_name PlainAbbey
extends RefCounted
## 坠星院（路线图 6.2b，D12；STORY.md 6.2「南边矮丘上的星铁教会修道院：钟楼、回廊、菜园（冻死了一半）、施粥的门房——粥一天比一天稀」）。
## 先回答「这里住着谁、缺什么、刚发生过什么」（ART.md 第十节）：住着院长格雷戈尔和十几个修士；修道院吃的是洛蒙德家的粮——石砌、石板瓦顶，和对岸茅草塌了的长屋是两个世界；
## 缺的是给穷人的那一份：门房外头一口大锅，粥稀得照得见天；菜园冻死了一半；东边抄经室的门从外面锁着（里面关着伊格纳兹修士，6.8）。
##   围墙（石砌、北面门房）、门房（中间一条门洞，东边一个施粥的窗口，墙外披棚下一口熬粥的大锅）、教堂（石墙、石板瓦顶、高窄的窗）、
##   西头的钟楼（15 米、顶上一圈钟窗、钟挂在里面、四角攒尖顶）、回廊（院子四面一圈带顶的走廊，中间一块雪地和一口小井）、
##   西边宿舍（两层石楼，House）、东边抄经室（House，门锁着；屋里是另一个区域 scriptorium）、西南角的菜园（八畦，一半冻死的茎秆、一半盖着雪）、门口的路牌。
## 同麦渡：碰撞、门、路牌同步建；画面每样一件活，交给所在那一块分帧搭。坐标就是平原的世界坐标。

const WALL_RECT := Rect2(26.0, 77.0, 42.0, 30.0)      # 围墙：西北角 (26, 77)，东西 42 米、南北 30 米
const WALL_H := 2.6
const WALL_T := 0.7
const GATE_X := 40.0                                   # 门洞在北墙上的位置
const GATE_W := 3.4
const GATEHOUSE := Rect2(36.0, 77.0, 8.0, 5.0)
const GATEHOUSE_H := 4.2
const TOWER := Rect2(47.0, 81.0, 4.4, 4.4)
const TOWER_H := 15.0
const NAVE := Rect2(51.4, 79.5, 12.6, 8.0)
const NAVE_H := 6.2
const CLOISTER := Rect2(47.0, 90.0, 14.0, 14.0)
const WALK := 2.4                                      # 回廊走道宽
const GARDEN := Rect2(28.0, 85.0, 8.4, 19.0)
const DORM := [Vector3(45.5, 0, 97.0), 90.0, 14.0, 7.0]           # 宿舍：正面墙脚中点、朝向（度）、宽、进深
const SCRIPTORIUM := [Vector3(61.5, 0, 95.0), -90.0, 10.0, 5.5]   # 抄经室：正面朝西对着回廊
const CAULDRON := Vector2(46.0, 75.4)
const SIGN_AT := Vector2(35.5, 74.0)
const SIGN_TEXT := "往麦渡 · 磨坊"
const SCRIPTORIUM_DOOR_TEXT := "门从外面上了锁。门缝里有人在低声说话，一句一句，像在对着墙念什么。"
const DORM_DOOR_TEXT := "修士的宿舍。门闩着。"
## 门口的人（6.2c）：[编号, 名字, 位置, 朝向（弧度，0 = 面朝北）, 衣服颜色, 对话编号（plain.json；空 = 只说一句）]
const GREGOR := ["gregor", "格雷戈尔院长", Vector2(41.05, 80.4), 0.0, "6a6660", "gregor"]        # 站在门洞里靠东那边，面朝外（门洞 3.4 米，西边留 2.4 米走得过去）
const PORTER := ["porter", "门房的修士", Vector2(47.45, 75.2), PI * 0.5, "7a756c", "porter"]      # 锅东边，面朝西对着排队的人（锅和围墙之间只有 0.6 米，站不下）
## 排队领粥的佃农：从锅前往西北排开（STORY.md 6.5 第 1 步「一路上看见麦茬地上排队领粥的佃农」）；夜里散了
const IDA_IN_QUEUE := 3
const QUEUE := [Vector2(45.6, 74.0), Vector2(44.9, 73.0), Vector2(44.3, 72.0), Vector2(43.9, 70.9), Vector2(43.6, 69.7), Vector2(43.1, 68.6), Vector2(42.4, 67.6), Vector2(41.6, 66.8)]
const QUEUE_LINES := [
	["一人一勺。昨天还能看见米粒。"], ["（她把碗揣在怀里捂着）……排到我就好了。"], ["洛蒙德家的仓是满的。修道院的锅是空的。"],
	["别挤。前头那个天不亮就站在这儿了。"], ["（孩子盯着锅里冒出来的热气，一声不吭）"], ["从麦渡走过来两里地，走回去又是两里地。"],
	["院长说主会看顾。主看顾的是坡上那座庄园。"], ["（他没抬头）你不是来收租的吧。"],
]

static var _y := NAN


static func clear_cache() -> void:
	_y = NAN


## 丘顶压平的那一块的高度（PlainLayout.pads 里有坠星院）
static func base_y() -> float:
	if is_nan(_y):
		_y = PlainLayout.height(PlainLayout.ABBEY_SITE.x, PlainLayout.ABBEY_SITE.y)
	return _y


static func ground(p: Vector2) -> float:
	return PlainLayout.height(p.x, p.y)


static func dorm_spec() -> Dictionary:
	return {"w": float(DORM[2]), "d": float(DORM[3]), "floors": 2, "stone_upper": true, "roof": "eaves", "seed": 62, "lit": 0.5, "door_x": 2.5, "chimney": true,
		"solid": false, "door": {"name": "宿舍的门", "text": DORM_DOOR_TEXT}}


static func scriptorium_spec() -> Dictionary:
	return {"w": float(SCRIPTORIUM[2]), "d": float(SCRIPTORIUM[3]), "floors": 1, "stone_upper": true, "roof": "eaves", "seed": 63, "lit": 1.0, "door_x": 0.0, "chimney": false,
		"solid": false, "door": {"name": "抄经室的门", "text": SCRIPTORIUM_DOOR_TEXT}}


static func house_pos(h: Array) -> Vector3:
	var p: Vector3 = h[0]
	return Vector3(p.x, base_y(), p.z)


## 出了抄经室站在哪：门外回廊上、背对着门（面朝西）
static func scriptorium_exit() -> Array:
	var p: Vector3 = SCRIPTORIUM[0]
	return [Vector2(p.x - 1.6, p.z), 90.0]


# ---------------- 碰撞 ----------------

static func solids() -> Array:
	var out := []
	var y := base_y()
	for seg: Array in wall_segments():
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		var m := (a + b) * 0.5
		var len := a.distance_to(b)
		var basis := Basis(Vector3.UP, -atan2(b.y - a.y, b.x - a.x))
		out.append([Transform3D(basis, Vector3(m.x, ground(m) + WALL_H * 0.5 - 0.3, m.y)), Vector3(len + WALL_T, WALL_H + 0.6, WALL_T)])
	var gh := GATEHOUSE
	for half in [Rect2(gh.position.x, gh.position.y, GATE_X - GATE_W * 0.5 - gh.position.x, gh.size.y), Rect2(GATE_X + GATE_W * 0.5, gh.position.y, gh.end.x - GATE_X - GATE_W * 0.5, gh.size.y)]:
		out.append([Transform3D(Basis.IDENTITY, Vector3(half.get_center().x, y + GATEHOUSE_H * 0.5, half.get_center().y)), Vector3(half.size.x, GATEHOUSE_H, half.size.y)])
	out.append([Transform3D(Basis.IDENTITY, Vector3(TOWER.get_center().x, y + TOWER_H * 0.5, TOWER.get_center().y)), Vector3(TOWER.size.x, TOWER_H, TOWER.size.y)])
	out.append([Transform3D(Basis.IDENTITY, Vector3(NAVE.get_center().x, y + NAVE_H * 0.5, NAVE.get_center().y)), Vector3(NAVE.size.x, NAVE_H, NAVE.size.y)])
	out.append_array(House.solids(house_pos(DORM), float(DORM[1]), dorm_spec()))
	out.append_array(House.solids(house_pos(SCRIPTORIUM), float(SCRIPTORIUM[1]), scriptorium_spec()))
	out.append([Transform3D(Basis.IDENTITY, Vector3(CAULDRON.x, ground(CAULDRON) + 0.5, CAULDRON.y)), Vector3(1.3, 1.0, 1.3)])
	var gc := CLOISTER.get_center()
	out.append([Transform3D(Basis.IDENTITY, Vector3(gc.x, y + 0.45, gc.y)), Vector3(1.4, 0.9, 1.4)])          # 院子中间的小井
	return out


## 围墙一段段：[起点, 终点]；北墙在门洞处断开（门房那段由门房自己挡）
static func wall_segments() -> Array:
	var r := WALL_RECT
	var nw := r.position
	var ne := Vector2(r.end.x, r.position.y)
	var se := r.end
	var sw := Vector2(r.position.x, r.end.y)
	return [[nw, Vector2(GATEHOUSE.position.x, nw.y)], [Vector2(GATEHOUSE.end.x, ne.y), ne], [ne, se], [se, sw], [sw, nw]]


static func interactables(parent: Node3D) -> void:
	for h: Array in [[DORM, dorm_spec(), "AbbeyDormDoor"], [SCRIPTORIUM, scriptorium_spec(), "ScriptoriumDoor"]]:
		var spec: Dictionary = h[1]
		var d := House.door_node(spec.door)
		d.name = str(h[2])
		d.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(float((h[0] as Array)[1]))), house_pos(h[0])) * Transform3D(Basis.IDENTITY, Vector3(float(spec.door_x) - 0.55, 0, 0.05))
		parent.add_child(d)
	var rs := RoadSign.new()
	rs.text = SIGN_TEXT
	rs.position = Vector3(SIGN_AT.x, ground(SIGN_AT), SIGN_AT.y)
	rs.rotation_degrees.y = 160.0
	parent.add_child(rs)


## 门口的人（6.2c）：院长、门房的修士（对话，plain.json）、排队领粥的佃农（只说一句；夜里散了）。同步放（块没搭好时也得找得到、说得上话）
static func people(parent: Node3D) -> void:
	for p: Array in [GREGOR, PORTER]:
		var pos: Vector2 = p[2]
		var n := Npc.make(str(p[1]), [], Color(str(p[4])))
		n.name = "Npc_" + str(p[0])
		n.dialogue_area = "plain"
		n.dialogue_id = str(p[5])
		n.position = Vector3(pos.x, ground(pos), pos.y)
		n.rotation.y = float(p[3])
		n.far_end = Plain.NPC_FAR
		n.label_far = Plain.LABEL_FAR
		parent.add_child(n)
	if GameState.daypart == "night":
		return
	for i in QUEUE.size():
		var q: Vector2 = QUEUE[i]
		var ahead: Vector2 = CAULDRON if i == 0 else QUEUE[i - 1]
		var child := i == 4
		var ida := i == IDA_IN_QUEUE                                          # 6.4：队里第四个是麦渡的寡妇伊达（对话 plain.json ida；夜里在麦渡坟边，PlainPeople）
		var n := Npc.make("伊达" if ida else ("佃农的孩子" if child else "排队领粥的佃农"), [] if ida else QUEUE_LINES[i], Color(["5a5046", "6a5a48", "4e4a44", "5e5248"][i % 4]))
		n.name = "Npc_ida" if ida else "Npc_queue%d" % i
		if ida:
			n.dialogue_area = "plain"
			n.dialogue_id = "ida"
		n.position = Vector3(q.x, ground(q), q.y)
		n.rotation.y = atan2(-(ahead.x - q.x), -(ahead.y - q.y))
		n.far_end = Plain.NPC_FAR
		n.label_far = Plain.LABEL_FAR
		if child:
			n.scale = Vector3.ONE * 0.72
		parent.add_child(n)


# ---------------- 画面（分帧的活） ----------------

static func jobs_for(rect: Rect2, reduced_motion: bool) -> Array:
	var out := []
	var c := WALL_RECT.get_center()
	if rect.has_point(c):
		out.append(func(root: Node3D): walls(root))
		out.append(func(root: Node3D): gatehouse(root, reduced_motion))
		out.append(func(root: Node3D): church(root))
		out.append(func(root: Node3D): cloister(root))
		out.append(func(root: Node3D): garden(root))
		out.append(func(root: Node3D): House.build(root, house_pos(DORM), float(DORM[1]), dorm_spec()))
		out.append(func(root: Node3D): House.build(root, house_pos(SCRIPTORIUM), float(SCRIPTORIUM[1]), scriptorium_spec()))
	return out


static func _mats() -> Dictionary:
	return {"stone": Look.mat("stone"), "roof": Look.mat("roof"), "timber": Look.mat("timber"), "snow": Look.mat("snow"), "bark": Look.mat("bark"),
		"dark": PlainVillage.dark(), "iron": Inn._iron_mat(), "ember": Inn._unshaded(Color("ff7a28")), "glass_lit": Look.glass_lit(), "glass_dark": Look.glass_dark(),
		"halo": Look.halo(Look.WINDOW_COLOR, 0.32), "bronze": _bronze(), "soil": _soil(), "stalk": _stalk()}


static func _bronze() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("6d5a3a")
	m.metallic = 0.7
	m.roughness = 0.5
	return m


static func _soil() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("4a3c30")
	m.roughness = 1.0
	m.vertex_color_use_as_albedo = true
	return m


static func _stalk() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("6e5a3c")
	m.roughness = 1.0
	m.vertex_color_use_as_albedo = true
	return m


static func _finish(parent: Node3D, kit: MeshKit, name: String) -> MeshInstance3D:
	var mi := kit.build(_mats())
	mi.name = name
	parent.add_child(mi)
	return mi


## 围墙：粗石墙，墙脚埋进土里一截（丘顶外缘是坡），墙头一溜石板压顶、积雪
static func walls(parent: Node3D) -> void:
	var kit := MeshKit.new()
	for seg: Array in wall_segments():
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		var len := a.distance_to(b)
		var n := maxi(int(len / 6.0), 1)
		var basis := Basis(Vector3.UP, -atan2(b.y - a.y, b.x - a.x))
		for k in n:
			var p0 := a.lerp(b, float(k) / n)
			var p1 := a.lerp(b, float(k + 1) / n)
			var m := (p0 + p1) * 0.5
			var g := minf(ground(p0), ground(p1))
			var top := maxf(ground(p0), ground(p1)) + WALL_H
			var h := top - g + 0.8
			kit.box("stone", Vector3(m.x, g - 0.8 + h * 0.5, m.y), Vector3(len / n + 0.05, h, WALL_T), basis, 0.85, 0.5)
			kit.box("stone", Vector3(m.x, top + 0.08, m.y), Vector3(len / n + 0.1, 0.16, WALL_T + 0.2), basis, 0.95, 0.8)
			kit.box("snow", Vector3(m.x, top + 0.2, m.y), Vector3(len / n + 0.1, 0.1, WALL_T + 0.1), basis, 1.0, 0.95)
	_finish(parent, kit, "AbbeyWalls")


## 门房：两块石屋夹一条门洞，上面连着、两坡石板瓦顶；东边朝外一个施粥的窗口（木板窗往上撑开、窗台当柜台）；
## 墙外披棚下一口熬粥的大锅（三根铁腿、炭火、冒着热气）、一条长凳
static func gatehouse(parent: Node3D, reduced_motion := false) -> void:
	var kit := MeshKit.new()
	var y := base_y()
	var gh := GATEHOUSE
	var l := GATE_X - GATE_W * 0.5
	var r := GATE_X + GATE_W * 0.5
	var zc := gh.get_center().y
	for half in [[gh.position.x, l], [r, gh.end.x]]:
		var x0: float = half[0]
		var x1: float = half[1]
		kit.box("stone", Vector3((x0 + x1) * 0.5, y + GATEHOUSE_H * 0.5 - 0.6, zc), Vector3(x1 - x0, GATEHOUSE_H + 1.2, gh.size.y), Basis.IDENTITY, 0.85, 0.5)
	kit.box("stone", Vector3(GATE_X, y + GATEHOUSE_H - 0.6, zc), Vector3(GATE_W + 0.1, 1.2, gh.size.y), Basis.IDENTITY, 0.8, 0.7)            # 门洞上面
	kit.box("dark", Vector3(GATE_X, y + 0.02, zc), Vector3(GATE_W, 0.04, gh.size.y))
	for s in [-1.0, 1.0]:                                                                                                                       # 两扇门往里敞着
		var hx: float = GATE_X + s * GATE_W * 0.5
		kit.box("timber", Vector3(hx - s * 0.12, y + 1.6, gh.position.y + 1.6), Vector3(0.12, 3.2, 1.5), Basis.IDENTITY, 0.8, 0.6)
	_gable(kit, Rect2(gh.position.x - 0.3, gh.position.y - 0.3, gh.size.x + 0.6, gh.size.y + 0.6), y + GATEHOUSE_H, 40.0, true)
	# 施粥的窗口：门洞东边那块的北面
	var wx := r + 1.9
	var wz := gh.position.y - 0.02
	kit.box("dark", Vector3(wx, y + 1.35, wz), Vector3(1.3, 0.8, 0.04))
	kit.box("timber", Vector3(wx, y + 0.95, wz - 0.25), Vector3(1.6, 0.08, 0.55), Basis.IDENTITY, 0.9, 0.7)                                  # 窗台当柜台
	kit.box("timber", Vector3(wx, y + 2.05, wz - 0.4), Vector3(1.4, 0.06, 0.8), Basis(Vector3.RIGHT, -0.6), 0.9, 0.6)                      # 往上撑开的窗板
	kit.cylinder("timber", Vector3(wx + 0.6, y + 1.0, wz - 0.5), Vector3(wx + 0.6, y + 1.9, wz - 0.7), 0.025, 0.025, 4)
	for i in 3:                                                                                                                                 # 柜台上几只木碗（空的）
		kit.cylinder("timber", Vector3(wx - 0.45 + i * 0.4, y + 1.0, wz - 0.3), Vector3(wx - 0.45 + i * 0.4, y + 1.07, wz - 0.3), 0.08, 0.06, 7, 0.85)
	# 墙外的大锅、披棚
	var cg := ground(CAULDRON)
	var cp := Vector3(CAULDRON.x, cg, CAULDRON.y)
	for k in 3:
		var a := TAU * k / 3.0
		kit.cylinder("iron", cp + Vector3(cos(a) * 0.55, 0, sin(a) * 0.55), cp + Vector3(cos(a) * 0.3, 0.7, sin(a) * 0.3), 0.025, 0.025, 4)
	kit.cylinder("iron", cp + Vector3(0, 0.55, 0), cp + Vector3(0, 1.05, 0), 0.42, 0.5, 10, 0.7)
	kit.cylinder("dark", cp + Vector3(0, 1.03, 0), cp + Vector3(0, 1.04, 0), 0.47, 0.47, 10)
	kit.box("ember", cp + Vector3(0, 0.12, 0), Vector3(0.6, 0.12, 0.6))
	for k in 4:
		var a := TAU * k / 4.0 + 0.4
		kit.cylinder("timber", cp + Vector3(cos(a) * 0.35, 0.1, sin(a) * 0.35), cp + Vector3(-cos(a) * 0.25, 0.22, -sin(a) * 0.25), 0.05, 0.05, 5, 0.5)
	for px in [-1.4, 1.4]:                                                                                                                      # 披棚：两根柱子 + 一面斜着的木板顶（靠在墙上）
		kit.box("timber", cp + Vector3(px, 1.1, -0.9), Vector3(0.14, 2.2, 0.14), Basis.IDENTITY, 0.8, 0.6)
	kit.box("timber", Vector3(CAULDRON.x, cg + 2.5, (CAULDRON.y - 0.9 + gh.position.y) * 0.5), Vector3(3.2, 0.08, gh.position.y - CAULDRON.y + 1.2), Basis(Vector3.RIGHT, 0.32), 0.8, 0.6)
	kit.box("snow", Vector3(CAULDRON.x, cg + 2.58, (CAULDRON.y - 0.9 + gh.position.y) * 0.5), Vector3(3.2, 0.05, gh.position.y - CAULDRON.y + 1.1), Basis(Vector3.RIGHT, 0.32), 1.0, 1.0)
	kit.box("timber", cp + Vector3(-2.3, 0.42, 0.3), Vector3(1.8, 0.07, 0.35), Basis(Vector3.UP, 0.2), 0.9, 0.7)                             # 长凳
	_finish(parent, kit, "Gatehouse")
	var steam := Atmos.smoke(parent, cp + Vector3(0, 1.2, 0))
	if steam != null:
		steam.scale_amount_min *= 0.5
		steam.scale_amount_max *= 0.5


## 两坡顶：rect 是屋顶外沿，屋脊沿长边；snow = 屋脊和坡上积雪
static func _gable(kit: MeshKit, rect: Rect2, eave_y: float, pitch: float, snow: bool) -> void:
	var along_x := rect.size.x >= rect.size.y
	var half := (rect.size.y if along_x else rect.size.x) * 0.5
	var rise := half * tan(deg_to_rad(pitch))
	var c := rect.get_center()
	var x0 := rect.position.x
	var x1 := rect.end.x
	var z0 := rect.position.y
	var z1 := rect.end.y
	if along_x:
		var ridge := [Vector3(x0, eave_y + rise, c.y), Vector3(x1, eave_y + rise, c.y)]
		kit.quad("roof", [Vector3(x0, eave_y, z0), Vector3(x1, eave_y, z0), ridge[1], ridge[0]], Vector3(0, 1, 0).lerp(Vector3(0, 0, -1), 0.5).normalized())
		kit.quad("roof", [Vector3(x1, eave_y, z1), Vector3(x0, eave_y, z1), ridge[0], ridge[1]], Vector3(0, 1, 0).lerp(Vector3(0, 0, 1), 0.5).normalized())
		kit.tri("stone", Vector3(x0 + 0.3, eave_y, z0 + 0.3), Vector3(x0 + 0.3, eave_y, z1 - 0.3), Vector3(x0 + 0.3, eave_y + rise - 0.2, c.y), Vector3(-1, 0, 0))
		kit.tri("stone", Vector3(x1 - 0.3, eave_y, z1 - 0.3), Vector3(x1 - 0.3, eave_y, z0 + 0.3), Vector3(x1 - 0.3, eave_y + rise - 0.2, c.y), Vector3(1, 0, 0))
		if snow:
			kit.box("snow", Vector3(c.x, eave_y + rise + 0.05, c.y), Vector3(rect.size.x, 0.14, 0.5), Basis.IDENTITY, 1.0, 0.9)
			for s in [-1.0, 1.0]:
				var mid := Vector3(c.x, eave_y + rise * 0.62, c.y + s * half * 0.38)
				kit.box("snow", mid, Vector3(rect.size.x - 0.2, 0.06, half * 0.75 / cos(deg_to_rad(pitch))), Basis(Vector3.RIGHT, s * deg_to_rad(pitch)), 1.0, 0.95)
	else:
		var ridge := [Vector3(c.x, eave_y + rise, z0), Vector3(c.x, eave_y + rise, z1)]
		kit.quad("roof", [Vector3(x0, eave_y, z1), Vector3(x0, eave_y, z0), ridge[0], ridge[1]], Vector3(-1, 1, 0).normalized())
		kit.quad("roof", [Vector3(x1, eave_y, z0), Vector3(x1, eave_y, z1), ridge[1], ridge[0]], Vector3(1, 1, 0).normalized())
		if snow:
			kit.box("snow", Vector3(c.x, eave_y + rise + 0.05, c.y), Vector3(0.5, 0.14, rect.size.y), Basis.IDENTITY, 1.0, 0.9)


## 教堂和钟楼：石墙、扶壁、高窄的尖窗（黑着，教堂里白天不点灯）、石板瓦顶；钟楼四面钟窗、一口青铜钟、四角攒尖顶
static func church(parent: Node3D) -> void:
	var kit := MeshKit.new()
	var y := base_y()
	var n := NAVE
	kit.box("stone", Vector3(n.get_center().x, y + NAVE_H * 0.5 - 0.8, n.get_center().y), Vector3(n.size.x, NAVE_H + 1.6, n.size.y), Basis.IDENTITY, 0.9, 0.5)
	for k in 5:                                                                                                                                 # 扶壁、窗
		var x := lerpf(n.position.x + 1.2, n.end.x - 1.2, k / 4.0)
		for s in [-1.0, 1.0]:
			var z: float = n.get_center().y + s * (n.size.y * 0.5)
			kit.box("stone", Vector3(x, y + 1.8, z + s * 0.35), Vector3(0.7, 3.6, 0.7), Basis.IDENTITY, 0.85, 0.5)
			kit.box("stone", Vector3(x, y + 3.9, z + s * 0.2), Vector3(0.6, 0.6, 0.4), Basis(Vector3.RIGHT, s * 0.6), 0.9, 0.7)
			if k < 4:
				var wx := x + (n.size.x - 2.4) / 8.0
				kit.box("glass_dark", Vector3(wx, y + 3.6, z + s * 0.02), Vector3(0.7, 2.6, 0.04))
				kit.box("stone", Vector3(wx, y + 5.0, z + s * 0.05), Vector3(0.5, 0.4, 0.06), Basis(Vector3.BACK, PI * 0.25))
	kit.box("glass_dark", Vector3(n.end.x + 0.02, y + 3.8, n.get_center().y), Vector3(0.04, 3.2, 1.6))                                       # 东头的大窗
	_gable(kit, Rect2(n.position.x - 0.2, n.position.y - 0.4, n.size.x + 0.4, n.size.y + 0.8), y + NAVE_H, 52.0, true)
	var t := TOWER
	var tc := t.get_center()
	kit.box("stone", Vector3(tc.x, y + TOWER_H * 0.5 - 0.8, tc.y), Vector3(t.size.x, TOWER_H + 1.6, t.size.y), Basis.IDENTITY, 0.95, 0.5)
	for s in [-1.0, 1.0]:                                                                                                                       # 钟楼四角加厚
		for s2 in [-1.0, 1.0]:
			kit.box("stone", Vector3(tc.x + s * t.size.x * 0.5, y + TOWER_H * 0.45, tc.y + s2 * t.size.y * 0.5), Vector3(0.6, TOWER_H * 0.9, 0.6), Basis.IDENTITY, 0.9, 0.5)
	for f in 4:                                                                                                                                 # 钟窗：四面各两个黑洞
		var dir := Vector3(sin(f * PI * 0.5), 0, cos(f * PI * 0.5))
		var side := Vector3(dir.z, 0, -dir.x)
		for k in [-0.6, 0.6]:
			kit.box("dark", Vector3(tc.x, y + TOWER_H - 2.2, tc.y) + dir * (t.size.x * 0.5 + 0.02) + side * k, Vector3(0.7, 1.8, 0.7) if f % 2 == 1 else Vector3(0.7, 1.8, 0.7), Basis(Vector3.UP, f * PI * 0.5))
		kit.box("glass_dark", Vector3(tc.x, y + 6.0, tc.y) + dir * (t.size.x * 0.5 + 0.02), Vector3(0.4, 1.4, 0.04), Basis(Vector3.UP, f * PI * 0.5))
	kit.box("stone", Vector3(tc.x, y + TOWER_H + 0.15, tc.y), Vector3(t.size.x + 0.5, 0.3, t.size.y + 0.5), Basis.IDENTITY, 0.95, 0.8)
	var apex := Vector3(tc.x, y + TOWER_H + 4.2, tc.y)                                                                                          # 四角攒尖顶
	var corners := [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(1, 0, 1), Vector3(-1, 0, 1)]
	for k in 4:
		var a: Vector3 = Vector3(tc.x, y + TOWER_H + 0.3, tc.y) + (corners[k] as Vector3) * (t.size.x * 0.5 + 0.3)
		var b: Vector3 = Vector3(tc.x, y + TOWER_H + 0.3, tc.y) + (corners[(k + 1) % 4] as Vector3) * (t.size.x * 0.5 + 0.3)
		var nn := (b - a).cross(apex - a).normalized()
		if nn.y < 0:
			nn = -nn
		kit.tri("roof", a, b, apex, nn)
		kit.tri("roof", b, a, apex, nn)
	kit.cylinder("iron", apex, apex + Vector3(0, 1.3, 0), 0.04, 0.03, 5)                                                                     # 尖上一根铁杆、一颗星（星铁教会）
	for k in 4:
		var a := TAU * k / 4.0 + PI * 0.25
		kit.cylinder("iron", apex + Vector3(0, 1.1, 0), apex + Vector3(cos(a) * 0.35, 1.1, sin(a) * 0.35), 0.025, 0.02, 4)
	kit.cylinder("bronze", Vector3(tc.x, y + TOWER_H - 1.5, tc.y), Vector3(tc.x, y + TOWER_H - 2.4, tc.y), 0.25, 0.55, 12, 0.9)                 # 钟
	kit.cylinder("timber", Vector3(tc.x - 1.6, y + TOWER_H - 1.35, tc.y), Vector3(tc.x + 1.6, y + TOWER_H - 1.35, tc.y), 0.1, 0.1, 6)
	# 钟楼下的门（朝北）
	kit.box("timber", Vector3(tc.x, y + 1.25, t.position.y - 0.03), Vector3(1.3, 2.5, 0.08), Basis.IDENTITY, 0.8, 0.6)
	kit.box("stone", Vector3(tc.x, y + 2.75, t.position.y - 0.08), Vector3(1.9, 0.5, 0.2), Basis.IDENTITY, 0.9, 0.7)
	_finish(parent, kit, "Church")


## 回廊：院子四面一圈带顶的走道（外侧靠房子 / 墙，内侧一排木柱、单坡石板瓦顶），中间雪地上一口小井、一棵光秃的小果树
static func cloister(parent: Node3D) -> void:
	var kit := MeshKit.new()
	var y := base_y()
	var c := CLOISTER
	var inner := c.grow(-WALK)
	kit.box("stone", Vector3(c.get_center().x, y + 0.03, c.get_center().y), Vector3(c.size.x, 0.06, c.size.y), Basis.IDENTITY, 0.6, 0.6)       # 走道的石板地
	kit.box("snow", Vector3(inner.get_center().x, y + 0.08, inner.get_center().y), Vector3(inner.size.x, 0.06, inner.size.y), Basis.IDENTITY, 1.0, 1.0)
	var sides := [[Vector2(c.position.x, c.position.y), Vector2(c.end.x, c.position.y), Vector2(0, 1)], [Vector2(c.end.x, c.position.y), Vector2(c.end.x, c.end.y), Vector2(-1, 0)],
		[Vector2(c.end.x, c.end.y), Vector2(c.position.x, c.end.y), Vector2(0, -1)], [Vector2(c.position.x, c.end.y), Vector2(c.position.x, c.position.y), Vector2(1, 0)]]
	for sd: Array in sides:
		var a: Vector2 = sd[0]
		var b: Vector2 = sd[1]
		var inw: Vector2 = sd[2]
		var len := a.distance_to(b)
		var dir := (b - a).normalized()
		var posts := int(len / 2.2)
		for k in posts + 1:
			var p := a + dir * (k * len / posts) + inw * WALK
			kit.box("timber", Vector3(p.x, y + 1.25, p.y), Vector3(0.22, 2.5, 0.22), Basis.IDENTITY, 0.8, 0.6)
		var outer_y := y + 3.4
		var inner_y := y + 2.55
		var o0 := Vector3(a.x, outer_y, a.y)
		var o1 := Vector3(b.x, outer_y, b.y)
		var i0 := Vector3(a.x + inw.x * (WALK + 0.4), inner_y, a.y + inw.y * (WALK + 0.4))
		var i1 := Vector3(b.x + inw.x * (WALK + 0.4), inner_y, b.y + inw.y * (WALK + 0.4))
		var nrm := Vector3(inw.x, 1.0, inw.y).normalized()
		kit.quad("roof", [o0, o1, i1, i0], nrm)
		kit.quad("roof", [i0, i1, o1, o0], -nrm)
		kit.quad("snow", [o0 + nrm * 0.06, o1 + nrm * 0.06, i1 + nrm * 0.06, i0 + nrm * 0.06], nrm, [1.0, 1.0, 0.9, 0.9])
		kit.box("timber", (Vector3(a.x, inner_y - 0.1, a.y) + Vector3(b.x, inner_y - 0.1, b.y)) * 0.5 + Vector3(inw.x, 0, inw.y) * WALK, Vector3(absf(dir.x) * len + 0.2, 0.18, absf(dir.y) * len + 0.2), Basis.IDENTITY, 0.8, 0.6)
	var gc := inner.get_center()                                                                                                               # 小井
	for k in 8:
		var a := TAU * k / 8.0
		kit.box("stone", Vector3(gc.x + cos(a) * 0.55, y + 0.4, gc.y + sin(a) * 0.55), Vector3(0.42, 0.8, 0.26), Basis(Vector3.UP, -a + PI * 0.5), 0.9, 0.6)
	kit.box("snow", Vector3(gc.x, y + 0.82, gc.y), Vector3(1.3, 0.05, 1.3), Basis.IDENTITY, 1.0, 1.0)
	kit.box("dark", Vector3(gc.x, y + 0.84, gc.y), Vector3(0.8, 0.02, 0.8))
	var tp := Vector3(gc.x + 2.6, y, gc.y - 2.2)                                                                                              # 院子里一棵光秃的小果树
	kit.cylinder("bark", tp, tp + Vector3(0.1, 1.6, 0), 0.12, 0.09, 6)
	for k in 5:
		var a := TAU * k / 5.0
		kit.cylinder("bark", tp + Vector3(0.1, 1.5, 0), tp + Vector3(cos(a) * 1.1, 2.6 + 0.3 * sin(a * 2.0), sin(a) * 1.1), 0.06, 0.02, 4)
	_finish(parent, kit, "Cloister")


## 菜园：八畦（土垄），一半冻死了（垄上一丛丛枯黄的茎秆歪着），一半盖着雪；四周一圈编篱
static func garden(parent: Node3D) -> void:
	var kit := MeshKit.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 6204
	var g := GARDEN
	var beds := 8
	var w := g.size.x / beds
	for k in beds:
		var x := g.position.x + (k + 0.5) * w
		var dead := k % 2 == 0 or k == 3
		var z0 := g.position.y + 0.8
		var z1 := g.end.y - 0.8
		var len := z1 - z0
		var mid := Vector2(x, (z0 + z1) * 0.5)
		var gy := ground(mid)
		kit.box("soil" if dead else "snow", Vector3(x, gy + 0.12, mid.y), Vector3(w * 0.62, 0.3, len), Basis.IDENTITY, 1.0, 0.7)
		if dead:
			var s := z0 + 0.3
			while s < z1 - 0.2:
				var p := Vector3(x + rng.randf_range(-0.2, 0.2), ground(Vector2(x, s)) + 0.27, s)
				for j in 3:                                                                                                                 # 一丛冻死的茎秆，往一边歪
					var top := p + Vector3(rng.randf_range(-0.25, 0.25), rng.randf_range(0.35, 0.75), rng.randf_range(-0.15, 0.15))
					kit.cylinder("stalk", p, top, 0.02, 0.008, 3, rng.randf_range(0.7, 1.0))
				s += rng.randf_range(0.45, 0.7)
			kit.box("snow", Vector3(x, gy + 0.3, mid.y), Vector3(w * 0.15, 0.04, len * 0.9), Basis.IDENTITY, 1.0, 1.0)
	var r := g.grow(0.3)                                                                                                                       # 编篱：一片片矮的木板（像编起来的枝条）
	var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	for k in 4:
		var a: Vector2 = corners[k]
		var b: Vector2 = corners[(k + 1) % 4]
		var n := int(a.distance_to(b) / 1.8)
		for j in n:
			if k == 1 and j == n / 2:
				continue                                                                                                                   # 东边留个口
			var p0 := a.lerp(b, float(j) / n)
			var p1 := a.lerp(b, float(j + 1) / n)
			var m := (p0 + p1) * 0.5
			kit.box("bark", Vector3(m.x, ground(m) + 0.45, m.y), Vector3(p0.distance_to(p1) - 0.05, 0.9, 0.09), Basis(Vector3.UP, -atan2(p1.y - p0.y, p1.x - p0.x)), 0.9, 0.6)
			kit.box("timber", Vector3(p0.x, ground(p0) + 0.55, p0.y), Vector3(0.1, 1.1, 0.1), Basis.IDENTITY, 0.8, 0.6)
	_finish(parent, kit, "Garden")


## 地图上的房子（本地地图）
static func map_shapes() -> Array:
	var out := []
	out.append({"k": "house", "pts": _rect_pts(GATEHOUSE), "label": "门房"})
	out.append({"k": "house", "pts": _rect_pts(NAVE), "label": "教堂"})
	out.append({"k": "house", "pts": _rect_pts(TOWER), "label": "钟楼"})
	out.append({"k": "house", "pts": House.footprint(house_pos(DORM), float(DORM[1]), float(DORM[2]), float(DORM[3])), "label": "宿舍"})
	out.append({"k": "house", "pts": House.footprint(house_pos(SCRIPTORIUM), float(SCRIPTORIUM[1]), float(SCRIPTORIUM[2]), float(SCRIPTORIUM[3])), "label": "抄经室"})
	return out


static func _rect_pts(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
