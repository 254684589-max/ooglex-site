class_name CrownRooms
extends RefCounted
## 冠城的室内（路线图 7.6，D12；STORY.md 7.2「议事厅（摄政会议：五家各一张高背椅、王座空着）；玛蒂尔达在斜街上新盘下的小酒馆」）。
## 搭屋子、碰撞、出口门用双钥港室内那一套（HarborRooms._room / _colliders / _exit，房间登记在 HarborRooms.SPEC，出去回 crown_city）。
## 先回答「这里住着谁、缺什么、刚发生过什么」（ART.md 第十节），写在每个房间的注释里。

const THRONE := Vector3(0.0, 0, -3.7)
## 五张高背椅：[家, 绕王座的角度（度，0 = 正南；正 = 往东）, 旗的颜色, 图案颜色, 图案, 镶边]
const CHAIRS := [["severin", 30.0, Color("7a2420"), Color("2a2a2e"), "anvil", Color("c8a040")], ["lomond", 60.0, Color("3c5a2c"), Color("d8b850"), "wheat", Color("b89a4a")],
	["valen", 90.0, Color("1e2228"), Color("cfcac0"), "heron", Color("8a8a8a")], ["caswell", -30.0, Color("26407a"), Color("d8c890"), "keys", Color("b89a4a")],
	["erde", -90.0, Color("4a3424"), Color("e08a3a"), "beacon", Color("8a6a3a")]]
const BANNER_X := {"severin": 3.2, "lomond": 5.0, "valen": 6.8, "caswell": -3.2, "erde": -6.8}
const CHAIR_R := 4.2
const THRONE_TEXT := "王座是一整块灰石凿出来的，扶手上包着星铁，磨得发亮。椅背顶上一个空着的凹槽，形状像一顶冠。三年了，凹槽里落着一层薄灰——差役擦椅子，从来不擦这儿。"
const CHAIRS_TEXT := "五张高背椅，椅背上各刻着一家的纹：铁砧托冠、金麦束、黑鹭、烽燧、双钥交叉。椅子的腿都钉在地上，挪不动。塞弗林家那张离王座最近，近得扶手快要碰到王座的台阶。"
const SIGN_TEXT := "柜台后面的墙上钉着一块旧木牌：一条鱼，鱼嘴里一枚倒钩——霜渡镇「倒钩鱼」门口那块。漆掉了一半，钉子是新的。"
const SLATE_TEXT := "柜台边一块小石板，粉笔写着：「酒：两个铜子。面包：没有。赊账：冬至以后再说。」底下一行字被擦过，还看得出是「霜渡镇」。"


static func chair_pos(deg: float) -> Vector3:
	var a := deg_to_rad(deg)
	return THRONE + Vector3(sin(a), 0, cos(a)) * CHAIR_R


# ---------------- 议事厅 ----------------
## 住着谁：没有人住——差役、守门的；冬议那天五家和大主祭（7.8）。缺什么：王座上那顶冠；生火的人——屋子太高，两只铁吊灯照不到顶，冷得哈气。
## 刚发生过什么：差役昨夜把五张椅子擦了一遍，五家的旗挂上了；王座后面那面王室的旗没挂（旗杆空着）。
## 北头三级石台上一张空王座，五张高背椅绕着王座摆成半圈，南边一道齐腰的木栏杆（旁听的站在外头）；东西两面墙上各三扇高窗。
static func council_hall(parent: Node3D, reduced_motion: bool) -> void:
	var kit := MeshKit.new()
	var openings := []
	for side in ["e", "w"]:
		for z: float in [-2.6, 0.4, 3.2]:
			openings.append([side, z, 1.1, 2.4, 5.6])
	HarborRooms._room(kit, "council_hall", openings)
	var t := THRONE
	for k in 3:                                                          # 三级石台
		kit.box("castle", t + Vector3(0, 0.1 * (k + 1), 0.4 - k * 0.4), Vector3(4.4 - k * 0.8, 0.2 * (k + 1), 2.6 - k * 0.6), Basis.IDENTITY, 0.8, 0.6)
	var ty := 0.6
	kit.box("castle", t + Vector3(0, ty + 0.25, -0.2), Vector3(1.4, 0.5, 1.0), Basis.IDENTITY, 0.85, 0.6)        # 王座：一整块灰石
	kit.box("castle", t + Vector3(0, ty + 1.7, -0.62), Vector3(1.4, 2.6, 0.24), Basis.IDENTITY, 0.9, 0.7)
	for s: float in [-1.0, 1.0]:
		kit.box("iron", t + Vector3(s * 0.66, ty + 0.75, -0.2), Vector3(0.14, 0.5, 0.9), Basis.IDENTITY)
	kit.box("ink", t + Vector3(0, ty + 2.85, -0.49), Vector3(0.5, 0.26, 0.02))                                  # 椅背顶上那个空凹槽
	for c: Array in CHAIRS:                                              # 五张高背椅，脸朝屋子当中
		var p := chair_pos(float(c[1]))
		var face := (Vector3(0, 0, -0.2) - p).normalized()
		var b := Basis(Vector3.UP, atan2(-face.x, -face.z) + PI)
		kit.box("timber", p + Vector3(0, 0.45, 0), Vector3(0.7, 0.1, 0.65), b, 1.0, 0.8)
		kit.box("timber", p + b * Vector3(0, 1.25, 0.3), Vector3(0.7, 1.6, 0.08), b, 1.0, 0.7)
		kit.box("cloth", p + b * Vector3(0, 1.55, 0.25), Vector3(0.42, 0.42, 0.01), b)
		for lx: float in [-0.3, 0.3]:
			for lz: float in [-0.26, 0.26]:
				kit.box("timber", p + b * Vector3(lx, 0.2, lz), Vector3(0.07, 0.4, 0.07), b, 0.8, 0.6)
	for x0: float in [-7.0, 1.1]:                                        # 南边齐腰的栏杆（当中留道口子）
		kit.box("timber", Vector3(x0 + 2.95, 1.0, 2.4), Vector3(5.9, 0.1, 0.12), Basis.IDENTITY, 1.0, 0.8)
		for k in 7:
			kit.box("timber", Vector3(x0 + 0.1 + k * 0.95, 0.5, 2.4), Vector3(0.08, 1.0, 0.08), Basis.IDENTITY, 0.8, 0.6)
	kit.box("cloth", Vector3(0, 0.005, -0.4), Vector3(2.2, 0.01, 6.0))                                          # 当中一条长毯，一直铺到石台下
	kit.box("iron", Vector3(0, 4.6, -3.95), Vector3(0.06, 2.6, 0.06))                                              # 王座后面那根空旗杆
	_finish(parent, kit, "council_hall")
	var dec := Decor.new()
	for c: Array in CHAIRS:
		dec.banner(Vector3(float(BANNER_X[c[0]]), 5.6, -4.92), Vector3(0, 0, 1), 1.1, 2.6, c[2], c[3], str(c[4]), c[5])
	for s: float in [-1.0, 1.0]:
		dec.candle_stand(Vector3(s * 1.9, 0.6, -3.0), 1.5)
		dec.sconce(Vector3(s * 7.95, 2.6, -1.1), Vector3(-s, 0, 0), true)
	dec.build(parent, "Decor", not reduced_motion)
	Inn._solid(parent, t + Vector3(0, 0.3, 0), Vector3(4.4, 0.6, 2.6))
	Inn._solid(parent, t + Vector3(0, 1.8, -0.4), Vector3(1.5, 3.0, 1.3))
	for c: Array in CHAIRS:
		Inn._solid(parent, chair_pos(float(c[1])) + Vector3(0, 0.8, 0), Vector3(0.8, 1.6, 0.8))
	for x0: float in [-7.0, 1.1]:
		Inn._solid(parent, Vector3(x0 + 2.95, 0.55, 2.4), Vector3(5.9, 1.1, 0.2))
	HarborRooms._examine(parent, "空王座", "看看", THRONE_TEXT, t + Vector3(0, 1.0, 0.6), Vector3(1.8, 2.0, 1.0), "Throne", "ch4_throne_seen")
	HarborRooms._examine(parent, "五张高背椅", "看看", CHAIRS_TEXT, chair_pos(30.0) + Vector3(0, 0.6, 0.6), Vector3(1.2, 1.4, 1.2), "Chairs")
	for s: float in [-1.0, 1.0]:
		HarborRooms._lamp(parent, Vector3(s * 3.4, 5.2, -1.0), 3.2, 12.0, Look.LAMP_COLOR, not reduced_motion, "Chandelier%d" % int(s + 1.0))
	HarborRooms._lamp(parent, t + Vector3(0, 2.2, 1.6), 1.6, 6.0, Color("ffb060"), not reduced_motion, "ThroneCandles")
	HarborRooms._fill(parent, Vector3(0, 4.0, 2.0), 2.0, 14.0)
	HarborRooms._fill(parent, Vector3(0, 3.0, -2.0), 1.2, 10.0)


# ---------------- 玛蒂尔达的小酒馆 ----------------
## 住着谁：玛蒂尔达——霜渡镇「倒钩鱼」的老板娘，渡口的税权押给钥楼以后，她把酒馆盘了出去，下河上了冠城；来喝酒的是斜街上的脚夫、船工。
## 缺什么：酒（只有一种，兑了水）、面包（石板上写着「没有」）；刚发生过什么：她三天前才盘下这间铺子，霜渡镇那块旧招牌刚钉到墙上，钉子还是新的。
## 一间窄长的屋子：北边一道柜台、后面一排酒桶和一架杯子，东边一个小火塘，两张桌子；墙上那块「倒钩鱼」的旧木牌。
static func matilda_inn(parent: Node3D, reduced_motion: bool) -> void:
	var kit := MeshKit.new()
	HarborRooms._room(kit, "matilda_inn", [["s", -2.3, 0.9, 1.1, 2.0], ["w", 0.0, 0.8, 1.2, 2.1]])
	kit.box("timber", Vector3(-0.5, 0.55, -1.3), Vector3(3.6, 1.1, 0.6), Basis.IDENTITY, 1.0, 0.6)          # 柜台
	kit.box("timber", Vector3(-0.5, 1.13, -1.3), Vector3(3.8, 0.06, 0.7), Basis.IDENTITY, 1.0, 1.0)
	for k in 4:                                                          # 柜台后面一排酒桶（侧躺）
		var c := Vector3(-2.4 + k * 0.85, 0.42, -2.6)
		kit.cylinder("timber", c - Vector3(0, 0, 0.28), c + Vector3(0, 0, 0.28), 0.34, 0.34, 10)
		kit.cylinder("iron", c - Vector3(0, 0, 0.17), c - Vector3(0, 0, 0.13), 0.35, 0.35, 10)
		kit.cylinder("iron", c + Vector3(0, 0, 0.13), c + Vector3(0, 0, 0.17), 0.35, 0.35, 10)
	kit.box("timber", Vector3(1.6, 1.5, -2.85), Vector3(1.6, 0.06, 0.26), Basis.IDENTITY, 1.0, 0.8)          # 一架杯子
	for k in 6:
		kit.cylinder("brass", Vector3(1.0 + k * 0.24, 1.53, -2.85), Vector3(1.0 + k * 0.24, 1.66, -2.85), 0.05, 0.06, 6)
	kit.box("timber", Vector3(-0.5, 1.9, -2.96), Vector3(1.1, 0.5, 0.05), Basis.IDENTITY, 1.0, 0.7)            # 倒钩鱼的旧招牌
	kit.box("ink", Vector3(-0.5, 1.92, -2.93), Vector3(0.7, 0.14, 0.01))
	kit.box("iron", Vector3(-0.2, 1.86, -2.92), Vector3(0.02, 0.14, 0.01))
	kit.box("slate", Vector3(1.4, 1.3, -1.0), Vector3(0.5, 0.4, 0.04), Basis(Vector3.RIGHT, -0.25))          # 小石板
	var fp := Vector3(3.1, 0, -1.4)                                      # 小火塘
	kit.box("stone", fp + Vector3(0, 0.75, 0), Vector3(0.8, 1.5, 1.4), Basis.IDENTITY, 0.9, 0.6)
	kit.box("stone", fp + Vector3(0, 2.25, 0), Vector3(0.6, 1.5, 0.9), Basis.IDENTITY, 0.8, 0.8)
	kit.box("ink", fp + Vector3(-0.34, 0.45, 0), Vector3(0.16, 0.6, 0.8))
	for tb: Vector3 in [Vector3(2.2, 0, 0.6), Vector3(-2.0, 0, 0.7)]:      # 两张桌子、长凳
		kit.box("timber", tb + Vector3(0, 0.76, 0), Vector3(1.4, 0.08, 0.8), Basis.IDENTITY, 1.0, 0.8)
		for lx: float in [-0.55, 0.55]:
			kit.box("timber", tb + Vector3(lx, 0.37, 0), Vector3(0.1, 0.74, 0.6), Basis.IDENTITY, 0.8, 0.6)
		kit.box("timber", tb + Vector3(0, 0.43, -0.65), Vector3(1.3, 0.06, 0.3), Basis.IDENTITY, 1.0, 0.8)
	_finish(parent, kit, "matilda_inn")
	var dec := Decor.new()
	dec.candles(Vector3(2.2, 0.8, 0.6), 1)
	dec.candles(Vector3(-2.0, 0.8, 0.7), 2)
	dec.barrel(Vector3(3.0, 0, 2.2))
	dec.sack(Vector3(-3.0, 0, 2.3), 0.6)
	dec.build(parent, "Decor", not reduced_motion)
	Inn._solid(parent, Vector3(-0.5, 0.6, -1.3), Vector3(3.8, 1.2, 0.7))
	Inn._solid(parent, Vector3(-1.1, 0.45, -2.6), Vector3(3.6, 0.9, 0.7))
	Inn._solid(parent, fp + Vector3(0, 1.0, 0), Vector3(0.8, 2.0, 1.4))
	for tb: Vector3 in [Vector3(2.2, 0, 0.6), Vector3(-2.0, 0, 0.7)]:
		Inn._solid(parent, tb + Vector3(0, 0.4, 0), Vector3(1.4, 0.8, 0.8))
	HarborRooms._examine(parent, "倒钩鱼的旧招牌", "看看", SIGN_TEXT, Vector3(-0.5, 1.4, -2.4), Vector3(1.2, 1.0, 0.6), "OldSign", "ch4_old_sign")
	HarborRooms._examine(parent, "小石板", "看看", SLATE_TEXT, Vector3(1.4, 1.0, -0.9), Vector3(0.6, 0.6, 0.5), "Slate")
	var fire := Tavern.FireLight.new()
	fire.name = "Hearth"
	fire.light_color = Color("ff8a3a")
	fire.base = 1.6
	fire.omni_range = 6.0
	fire.position = fp + Vector3(-0.7, 0.5, 0)
	fire.flicker = not reduced_motion
	fire.add_to_group("light_source")
	fire.set_meta("radius", 3.0)
	parent.add_child(fire)
	HarborRooms._lamp(parent, Vector3(-0.5, 2.5, 0.0), 2.2, 7.0, Look.LAMP_COLOR, not reduced_motion, "HangLamp")
	HarborRooms._fill(parent, Vector3(-2.0, 2.0, 1.8), 1.4, 7.0)


# ---------------- 钟楼底下 · 教会档案馆（第五章，8.1） ----------------
## 住着谁：守卷的修士西缪和两个年轻修士；缺什么：光——只点得起抄经桌上的两根蜡烛，卷宗架之间是黑的；
## 刚发生过什么：约四百年前改加冕礼的时候，教会在这儿烧掉了一箱东西，那只烧黑的铁箱一直没人挪过；斜街上蒙着脸堵你的三个人，是从这儿出去的。
## 拱顶的地下室：南墙一道石阶上钟楼；两排卷宗架；当中一张抄经桌；东北角那只烧黑的铁箱；北墙一道铁栅门，门后是冠城地下的旧井道（不往下走）。
const ARCHIVE_CHEST := Vector3(3.0, 0, -4.6)
const ARCHIVE_GRATE := Vector3(-2.4, 0, -6.0)
const GRATE_TEXT := "一道锈死的铁栅门，门后是往下去的旧井道，一股冷风从底下吹上来，带着雪的味道。门上的锁没有锁孔——只有一个冠形的凹槽。"
const SHELF_TEXT := "一格一格的卷宗：加冕礼的记录、历代大主祭的手札、各家的婚约和借据的抄本。约四百年那一年的格子是空的，格子边上有一圈烧焦的印子。"
const SCROLL_TEXT := "残卷只剩下半张，边上烧焦了：「……其七，封誓。持冠者以血封瓶，瓶置冬井，留名于冰。留名者，每冬还井，守井一夜，冬乃退。」底下一行小字，是后来添的：「无人肯还。此页毁之，改为游行。」"


static func church_archive(parent: Node3D, reduced_motion: bool) -> void:
	var kit := MeshKit.new()
	HarborRooms._room(kit, "church_archive", [])
	for k in 4:                                                          # 拱顶的肋：四道横着的石拱
		var z := -4.5 + k * 3.0
		kit.box("castle", Vector3(0, 3.35, z), Vector3(10.0, 0.5, 0.5), Basis.IDENTITY, 0.8, 0.6)
		for s: float in [-1.0, 1.0]:
			kit.box("castle", Vector3(s * 4.75, 1.7, z), Vector3(0.5, 3.4, 0.5), Basis.IDENTITY, 0.8, 0.5)
	for s: float in [-1.0, 1.0]:                                         # 两排卷宗架（中间留一条道）
		for k in 3:
			var c := Vector3(s * 3.0, 0, -3.4 + k * 2.6)
			kit.box("timber", c + Vector3(0, 1.2, 0), Vector3(2.2, 2.4, 0.5), Basis.IDENTITY, 0.8, 0.6)
			for r in 4:
				kit.box("cloth", c + Vector3(0, 0.35 + r * 0.55, 0.26), Vector3(2.0, 0.32, 0.02), Basis.IDENTITY, 0.9, 0.9)
	kit.box("timber", Vector3(0, 0.8, 1.8), Vector3(1.6, 0.08, 0.9), Basis.IDENTITY, 1.0, 0.8)        # 抄经桌
	for lx: float in [-0.7, 0.7]:
		kit.box("timber", Vector3(lx, 0.39, 1.8), Vector3(0.1, 0.78, 0.7), Basis.IDENTITY, 0.8, 0.6)
	kit.box("cloth", Vector3(-0.2, 0.85, 1.8), Vector3(0.7, 0.01, 0.5))
	var ch := ARCHIVE_CHEST                                              # 烧黑的铁箱
	kit.box("iron", ch + Vector3(0, 0.35, 0), Vector3(1.2, 0.7, 0.7), Basis(Vector3.UP, 0.2))
	kit.box("ink", ch + Vector3(0, 0.72, 0), Vector3(1.22, 0.04, 0.72), Basis(Vector3.UP, 0.2))
	var g := ARCHIVE_GRATE                                               # 北墙的铁栅门
	kit.box("ink", g + Vector3(0, 1.2, 0.02), Vector3(1.6, 2.4, 0.05))
	for k in 7:
		kit.box("iron", g + Vector3(-0.72 + k * 0.24, 1.2, 0.1), Vector3(0.05, 2.4, 0.05))
	kit.box("iron", g + Vector3(0, 2.4, 0.1), Vector3(1.7, 0.08, 0.08))
	kit.box("brass", g + Vector3(0.0, 1.2, 0.14), Vector3(0.24, 0.16, 0.02))
	_finish(parent, kit, "church_archive")
	var dec := Decor.new()
	dec.candles(Vector3(0.5, 0.84, 1.8), 2)
	dec.books(Vector3(-0.7, 0.84, 1.6), Vector3(1, 0, 0), 0.5, 7)
	dec.sconce(Vector3(-4.95, 2.0, 4.0), Vector3(1, 0, 0), true)
	dec.build(parent, "Decor", not reduced_motion)
	for s: float in [-1.0, 1.0]:
		for k in 3:
			Inn._solid(parent, Vector3(s * 3.0, 1.2, -3.4 + k * 2.6), Vector3(2.2, 2.4, 0.5))
		for k in 4:
			Inn._solid(parent, Vector3(s * 4.75, 1.7, -4.5 + k * 3.0), Vector3(0.5, 3.4, 0.5))
	Inn._solid(parent, Vector3(0, 0.4, 1.8), Vector3(1.6, 0.8, 0.9))
	Inn._solid(parent, ch + Vector3(0, 0.4, 0), Vector3(1.3, 0.8, 0.9))
	var chest := Examine.make("烧黑的铁箱", "看看", func(_who: FpController) -> Dictionary:
		if GameState.has_flag("ch5_archive"):
			return {"toast": SCROLL_TEXT}
		return {"toast": "一只烧黑的铁箱，锁扣是新的。钥匙在大主祭身上。"}, Vector3(1.4, 1.0, 1.0))
	chest.name = "ScrollChest"
	chest.position = ch + Vector3(0, 0.4, 0)
	parent.add_child(chest)
	HarborRooms._examine(parent, "铁栅门", "看看", GRATE_TEXT, g + Vector3(0, 1.0, 0.5), Vector3(1.8, 2.0, 0.6), "UnderGrate", "ch5_grate_seen")
	HarborRooms._examine(parent, "卷宗架", "看看", SHELF_TEXT, Vector3(-3.0, 1.0, 0.0), Vector3(2.2, 2.0, 1.0), "Shelves")
	HarborRooms._lamp(parent, Vector3(0.3, 1.4, 1.8), 1.6, 7.0, Color("ffb060"), not reduced_motion, "DeskCandles")
	HarborRooms._lamp(parent, Vector3(-4.6, 2.2, 4.0), 1.8, 7.0, Look.LAMP_COLOR, not reduced_motion, "StairSconce")
	HarborRooms._fill(parent, Vector3(0, 2.6, -2.0), 1.0, 9.0)
	HarborRooms._fill(parent, Vector3(0, 2.6, 3.0), 0.8, 8.0)


static func _finish(parent: Node3D, kit: MeshKit, area: String) -> void:
	HarborRooms._finish(parent, kit, area)


static func map_shapes(area: String) -> Array:
	match area:
		"council_hall":
			var out := [{"k": "furniture", "rect": Rect2(THRONE.x - 2.2, THRONE.z - 0.9, 4.4, 2.6), "label": "王座"},
				{"k": "furniture", "rect": Rect2(-7.0, 2.3, 5.9, 0.2), "label": "栏杆"}, {"k": "furniture", "rect": Rect2(1.1, 2.3, 5.9, 0.2)}]
			for c: Array in CHAIRS:
				var p := chair_pos(float(c[1]))
				out.append({"k": "furniture", "rect": Rect2(p.x - 0.4, p.z - 0.4, 0.8, 0.8)})
			return out
		"church_archive":
			return [{"k": "furniture", "rect": Rect2(-4.1, -3.65, 2.2, 5.7), "label": "卷宗架"}, {"k": "furniture", "rect": Rect2(1.9, -3.65, 2.2, 5.7), "label": "卷宗架"},
				{"k": "furniture", "rect": Rect2(-0.8, 1.35, 1.6, 0.9), "label": "抄经桌"}, {"k": "furniture", "rect": Rect2(ARCHIVE_CHEST.x - 0.6, ARCHIVE_CHEST.z - 0.35, 1.2, 0.7), "label": "铁箱"},
				{"k": "furniture", "rect": Rect2(ARCHIVE_GRATE.x - 0.8, ARCHIVE_GRATE.z, 1.6, 0.2), "label": "铁栅门"}]
		"matilda_inn":
			return [{"k": "furniture", "rect": Rect2(-2.4, -1.65, 3.8, 0.7), "label": "柜台"}, {"k": "furniture", "rect": Rect2(2.7, -2.1, 0.8, 1.4), "label": "火塘"},
				{"k": "furniture", "rect": Rect2(1.5, 0.2, 1.4, 0.8)}, {"k": "furniture", "rect": Rect2(-2.7, 0.3, 1.4, 0.8)}]
	return []
