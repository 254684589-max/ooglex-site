class_name HarborRooms
extends RefCounted
## 双钥港的室内（路线图 7.3，D12；STORY.md 7.2「钥楼的大厅（高柜台、账房先生、算筹和天平）与地下金库（铁门、一格一格的抵押匣）；
## 渡工行会会馆；码头边的酒馆；债牢」）。五个区域共用一个搭屋子的办法（_room：四面墙按门窗切开、地板、顶、横梁、碰撞），各自摆陈设。
## 坐标：原点在屋里地面中心，北 = -Z。出口门在南墙（z = +D/2），出去站在双钥港那扇门外（harbor 的出生点 *_door）；
## 金库在钥楼大厅底下：北墙一道石阶上大厅（门锁着，莫德管着钥匙，7.5），东墙一道铁栅水门通北潮沟（金库之夜，7.5）。
## 室内的光不跟时段走；窗玻璃按时段换颜色（Inn.glass）。先回答「这里住着谁、缺什么、刚发生过什么」（ART.md 第十节），写在每个房间的注释里。

const AREAS := ["key_hall", "key_vault", "guild_hall", "dock_tavern", "debt_prison"]
const CROWN_AREAS := ["council_hall", "matilda_inn", "church_archive"]          # 冠城的几间（7.6、8.1，陈设在 world/crown_rooms.gd；出去回 crown_city）
const WELL_AREAS := ["well_bottom"]                          # 冬井底（8.3，陈设和人在 world/well_rooms.gd；出去回 highland）
const NAMES := {"key_hall": "钥楼 · 大厅", "key_vault": "钥楼 · 金库", "guild_hall": "渡工行会会馆", "dock_tavern": "「咸潮」酒馆", "debt_prison": "债牢",
	"council_hall": "冠城 · 议事厅", "matilda_inn": "玛蒂尔达的小酒馆", "church_archive": "钟楼底下 · 教会档案馆", "well_bottom": "冬井底"}
## 每个房间：宽、进深、高，墙用哪种材质，出口门（南墙上的 x、宽），出去站在双钥港哪个出生点
const SPEC := {
	"key_hall": {"w": 14.0, "d": 7.0, "h": 4.4, "wall": "castle", "floor": "street", "door_x": 0.0, "door_w": 1.6, "exit": "keyhouse_door", "exit_name": "回到钥楼街"},
	"key_vault": {"w": 11.0, "d": 7.0, "h": 3.0, "wall": "castle", "floor": "street", "door_x": 99.0, "door_w": 0.0, "exit": "", "exit_name": ""},
	"guild_hall": {"w": 13.0, "d": 8.0, "h": 4.0, "wall": "plaster", "floor": "timber", "door_x": 0.0, "door_w": 1.4, "exit": "guild_door", "exit_name": "回到鱼市"},
	"dock_tavern": {"w": 9.0, "d": 7.2, "h": 3.4, "wall": "plaster", "floor": "timber", "door_x": 2.6, "door_w": 1.2, "exit": "tavern_door", "exit_name": "回到码头街"},
	"debt_prison": {"w": 11.0, "d": 8.0, "h": 3.6, "wall": "castle", "floor": "street", "door_x": 0.0, "door_w": 1.2, "exit": "prison_door", "exit_name": "回到街上"},
	"council_hall": {"w": 16.0, "d": 10.0, "h": 7.0, "wall": "castle", "floor": "street", "door_x": 0.0, "door_w": 2.0, "exit": "council_door", "exit_name": "回到议事厅广场", "out": "crown_city"},
	"matilda_inn": {"w": 7.0, "d": 6.0, "h": 3.0, "wall": "plaster", "floor": "timber", "door_x": 0.0, "door_w": 1.0, "exit": "matilda_door", "exit_name": "回到斜街", "out": "crown_city"},
	"well_bottom": {"w": 14.0, "d": 12.0, "h": 6.0, "wall": "stone", "floor": "street", "door_x": 3.6, "door_w": 1.4, "exit": "well", "exit_name": "顺着石阶回井口", "out": "highland"},
	"church_archive": {"w": 10.0, "d": 12.0, "h": 3.6, "wall": "castle", "floor": "street", "door_x": 0.0, "door_w": 1.2, "exit": "bell_door", "exit_name": "上石阶回钟楼脚下", "out": "crown_city"},
}
const VAULT_STAIR := Vector3(-1.2, 0, -3.0)                 # 金库北墙那道上大厅的石阶的脚（石阶贴着北墙往西上，钻进顶上一个黑洞——上面是大厅西北角那扇铁门）
const VAULT_GATE := Vector3(5.5, 0, 0.6)                  # 金库东墙的水门（铁栅，外面是北潮沟）
const CROWN_BOX := Vector3(0.0, 0, -2.6)                  # 那只铁匣：北墙正中一座石台上，罩着一道铁笼
const HALL_VAULT_DOOR := Vector3(-5.6, 0, -3.5)          # 大厅西北角下金库的门
const VAULT_DOOR_TEXT := "门是一整块铁，上了三道锁。门房说钥匙在金库管事莫德身上，「她连睡觉都揣着」。（金库之夜，路线图 7.5）"
const GATE_TEXT := "一道铁栅门，外面就是北潮沟。退潮的时候，栅门底下露出一截黑泥。铁栅上挂着一把大锁，锁上结着盐霜。"
const CROWN_TEXT := "一只铁匣，比架子上别的匣子都旧，四角包着星铁。封蜡上压着一枚星铁冠印——和序章那张借据背面的一模一样。锁孔是两把钥匙交叉的形状。铁笼锁着，你够不着它。"
const SHELF_TEXT := "一格一格的抵押匣，每只匣子上贴着签：「洛蒙德·十二座磨坊」「塞弗林·砧山北坑十年」「厄尔德·羊脊村以北牧场」「瓦伦·霜渡镇渡口税权」……有一格空着，签上写着「埃德里克·瓦伦（未赎）」。"
const SCALES_TEXT := "柜台上一架黄铜天平，一头压着一摞银币，另一头是一块写着字的铅牌：「抵押：麦渡以东十二座磨坊。」铅牌那头沉下去了。"
const BOARD_TEXT := "墙上一块黑板，粉笔写着「冬至清账」，底下一排家名：塞弗林、洛蒙德、瓦伦、厄尔德。每一家后面一个数，瓦伦家那一栏擦过又写过，最后一个数比前面的都大。黑板最底下有人添了一行小字：「王室——未结。」"
const TIDE_TEXT := "墙上钉着一张潮汐表，行会的人一天改一回：「冬至前三日：午时涨满，子时退到底，寅时回涨。」底下一行炭笔字：「退潮别走北潮沟，沟底的泥能吞人。」"
const SCHEDULE_TEXT := "船期板：「往冠城（逆流）：每日卯时，行会的船，一人三枚银币。冬至前三日加一班。」最下头一格空着，写着「运粮船——搁浅，待修」。"
const COUNTER_TEXT := "柜台上刻着一行字，刀口都磨圆了：「灰鲸河的水往南流，账往北走。」"
const DEBT_TEXT := "看门的桌上摊着一本账，一行一个人、一个数：「约斯特，船钱四十二枚，担保：王室（老王殁，担保作废，债归本人）。」「寡妇露西，房钱十一枚。」「无名，渔网钱三枚。」最后一行是新写的：「冬至以前不赎，转卖钥楼。」"

## 进门站在哪：front = 门里头
static func spawns(area: String) -> Dictionary:
	var s: Dictionary = SPEC[area]
	if area == "key_vault":
		return {"front": [Vector3(-1.8, 0, -1.4), -120.0], "stair": [Vector3(-1.8, 0, -1.4), -120.0], "gate": [VAULT_GATE + Vector3(-1.0, 0, 0.0), 90.0]}
	var out := {"front": [Vector3(float(s.door_x), 0, float(s.d) * 0.5 - 0.9), 0.0]}
	if area == "key_hall":
		out["vault_stair"] = [HALL_VAULT_DOOR + Vector3(0.0, 0, 1.2), 180.0]
	return out


const VIEW_SPECS := {
	"key_hall": [[Vector3(0.0, 0, 2.6), 0.0, -6.0], [Vector3(4.5, 0, 1.6), 60.0, -8.0], [Vector3(-4.2, 0, 1.8), -40.0, -6.0]],
	"key_vault": [[Vector3(-1.8, 0, -1.4), -120.0, -8.0], [Vector3(1.6, 0, -1.4), 20.0, -12.0], [Vector3(2.0, 0, 0.7), -90.0, -6.0]],
	"guild_hall": [[Vector3(0.0, 0, 3.1), 0.0, -6.0], [Vector3(-4.6, 0, 1.6), -50.0, -6.0], [Vector3(4.6, 0, 2.2), 50.0, -6.0]],
	"dock_tavern": [[Vector3(2.6, 0, 2.7), 20.0, -6.0], [Vector3(-2.5, 0, 1.8), -60.0, -8.0], [Vector3(1.4, 0, -1.2), 160.0, -6.0]],
	"debt_prison": [[Vector3(0.0, 0, 3.1), 0.0, -6.0], [Vector3(3.6, 0, 1.0), 40.0, -6.0], [Vector3(-3.6, 0, 1.4), -30.0, -6.0]],
	"council_hall": [[Vector3(0.0, 0, 4.1), 0.0, 4.0], [Vector3(-5.6, 0, 1.2), -60.0, 0.0], [Vector3(5.8, 0, 3.6), 30.0, 6.0]],
	"well_bottom": [[Vector3(-3.0, 0, 4.4), -20.0, 2.0], [Vector3(4.6, 0, 1.6), 50.0, 4.0], [Vector3(-5.0, 0, -4.6), -120.0, 0.0]],
	"church_archive": [[Vector3(0.0, 0, 5.0), 0.0, -4.0], [Vector3(-3.2, 0, 2.0), -30.0, -8.0], [Vector3(2.6, 0, -2.6), 160.0, -6.0]],
	"matilda_inn": [[Vector3(0.0, 0, 2.2), 0.0, -6.0], [Vector3(-2.6, 0, 2.2), -40.0, -6.0], [Vector3(2.4, 0, -0.4), 140.0, -6.0]],
}
const VIEW_NAMES := {"key_hall": ["进门看大厅", "柜台和天平", "黑板和下金库的门"], "key_vault": ["石阶下看金库", "铁匣和铁笼", "水门"],
	"guild_hall": ["进门看会馆", "潮汐表", "船期板和炉子"], "dock_tavern": ["进门看酒馆", "炉边", "柜台"], "debt_prison": ["进门看债牢", "牢房", "看门的桌子"],
	"council_hall": ["进门看议事厅", "栏杆边看椅子", "东南角看王座"], "matilda_inn": ["进门看酒馆", "桌边看柜台", "火塘边"], "church_archive": ["下了石阶看档案馆", "卷宗架之间", "铁箱和铁栅门"], "well_bottom": ["石阶下看井底", "石台和星铁", "冰壁"]}


static func views(area: String) -> Array:
	return VIEW_SPECS.get(area, [])


static func display_name(area: String) -> String:
	return str(NAMES.get(area, area))


# ---------------- 共用：一间屋子 ----------------

## 四面墙（南墙按门切开，openings 里另有窗：[墙 "n"/"s"/"e"/"w", 中心（沿墙）, 宽, 下沿, 上沿]），地板、顶、横梁
static func _room(kit: MeshKit, area: String, openings: Array) -> void:
	var s: Dictionary = SPEC[area]
	var w := float(s.w)
	var d := float(s.d)
	var h := float(s.h)
	var wall := str(s.wall)
	kit.box("floor", Vector3(0, -0.05, 0), Vector3(w, 0.1, d), Basis.IDENTITY, 0.75, 0.75)
	kit.box("timber", Vector3(0, h + 0.05, 0), Vector3(w, 0.1, d), Basis.IDENTITY, 0.35, 0.35, true)
	var nb := int(w / 2.6)
	for i in nb:
		var x := -w * 0.5 + (i + 0.5) * w / nb
		kit.box("timber", Vector3(x, h - 0.16, 0), Vector3(0.26, 0.32, d), Basis.IDENTITY, 0.5, 0.4)
	var ops := openings.duplicate()
	if float(s.door_w) > 0.0:
		ops.append(["s", float(s.door_x), float(s.door_w), 0.0, 2.3])
	for side in ["n", "s", "e", "w"]:
		var along := w if side in ["n", "s"] else d
		var cuts := []
		for o: Array in ops:
			if str(o[0]) == side:
				cuts.append(o)
		cuts.sort_custom(func(a, b): return float(a[1]) < float(b[1]))
		var x0 := -along * 0.5
		for o: Array in cuts:
			var a := float(o[1]) - float(o[2]) * 0.5
			var b := float(o[1]) + float(o[2]) * 0.5
			if a > x0:
				_wall_piece(kit, wall, side, w, d, x0, a, 0.0, h)
			_wall_piece(kit, wall, side, w, d, a, b, 0.0, float(o[3]))
			_wall_piece(kit, wall, side, w, d, a, b, float(o[4]), h)
			if float(o[3]) > 0.0:                                         # 窗：玻璃、窗台
				var c := _wall_point(side, w, d, (a + b) * 0.5, 0.0)
				var n := _inward(side)
				var bas := Basis(Vector3.UP, atan2(n.x, n.z))
				kit.box("glass", c + Vector3(0, (float(o[3]) + float(o[4])) * 0.5, 0) - n * 0.12, Vector3(b - a, float(o[4]) - float(o[3]), 0.04), bas)
				kit.box(wall, c + Vector3(0, float(o[3]) - 0.05, 0) + n * 0.05, Vector3(b - a + 0.2, 0.1, 0.3), bas)
			else:
				kit.box("timber", _wall_point(side, w, d, (a + b) * 0.5, 0.0) + Vector3(0, float(o[4]) + 0.08, 0) + _inward(side) * 0.12, Vector3(b - a + 0.4, 0.16, 0.16), Basis(Vector3.UP, atan2(_inward(side).x, _inward(side).z)))
			x0 = b
		if x0 < along * 0.5:
			_wall_piece(kit, wall, side, w, d, x0, along * 0.5, 0.0, h)


static func _inward(side: String) -> Vector3:
	return {"n": Vector3(0, 0, 1), "s": Vector3(0, 0, -1), "e": Vector3(-1, 0, 0), "w": Vector3(1, 0, 0)}[side]


## 墙上沿墙 t 处（从西 / 北往东 / 南量，中心 0）、墙中心线上的点
static func _wall_point(side: String, w: float, d: float, t: float, y: float) -> Vector3:
	var wt := 0.4
	match side:
		"n":
			return Vector3(t, y, -d * 0.5 - wt * 0.5)
		"s":
			return Vector3(t, y, d * 0.5 + wt * 0.5)
		"e":
			return Vector3(w * 0.5 + wt * 0.5, y, t)
	return Vector3(-w * 0.5 - wt * 0.5, y, t)


static func _wall_piece(kit: MeshKit, key: String, side: String, w: float, d: float, a: float, b: float, y0: float, y1: float) -> void:
	if b - a < 0.01 or y1 - y0 < 0.01:
		return
	if side in ["n", "s"]:                                             # 南北两面墙两头各伸出一个墙厚，把四个角包住
		if a <= -w * 0.5 + 0.01:
			a -= 0.4
		if b >= w * 0.5 - 0.01:
			b += 0.4
	var c := _wall_point(side, w, d, (a + b) * 0.5, (y0 + y1) * 0.5)
	var size := Vector3(b - a, y1 - y0, 0.4) if side in ["n", "s"] else Vector3(0.4, y1 - y0, b - a)
	kit.box(key, c, size, Basis.IDENTITY, 0.75 if y1 > 2.0 else 0.6, 0.5)


## 碰撞：地板、顶、四面墙（南墙留门洞）
static func _colliders(parent: Node3D, area: String) -> void:
	var s: Dictionary = SPEC[area]
	var w := float(s.w)
	var d := float(s.d)
	var h := float(s.h)
	var t := 0.4
	Inn._solid(parent, Vector3(0, -0.1, 0), Vector3(w + 1, 0.2, d + 1))
	Inn._solid(parent, Vector3(0, h + 0.1, 0), Vector3(w + 1, 0.2, d + 1))
	Inn._solid(parent, Vector3(0, h * 0.5, -d * 0.5 - t * 0.5), Vector3(w + 1, h, t))
	Inn._solid(parent, Vector3(w * 0.5 + t * 0.5, h * 0.5, 0), Vector3(t, h, d + 1))
	Inn._solid(parent, Vector3(-w * 0.5 - t * 0.5, h * 0.5, 0), Vector3(t, h, d + 1))
	var zs := d * 0.5 + t * 0.5
	var dw := float(s.door_w)
	if dw <= 0.0:
		Inn._solid(parent, Vector3(0, h * 0.5, zs), Vector3(w + 1, h, t))
		return
	var dl := float(s.door_x) - dw * 0.5
	var dr := float(s.door_x) + dw * 0.5
	Inn._solid(parent, Vector3((-w * 0.5 + dl) * 0.5, h * 0.5, zs), Vector3(dl + w * 0.5, h, t))
	Inn._solid(parent, Vector3((dr + w * 0.5) * 0.5, h * 0.5, zs), Vector3(w * 0.5 - dr, h, t))
	Inn._solid(parent, Vector3(float(s.door_x), h * 0.5, zs + 0.15), Vector3(dw, h, 0.1))


static func _exit(parent: Node3D, area: String) -> void:
	var s: Dictionary = SPEC[area]
	if str(s.exit) == "":
		return
	var exit := Door.make(str(s.exit_name), float(s.door_w), 2.3, false)
	exit.verb = "离开"
	exit.to_area = str(s.get("out", "harbor"))
	exit.to_spawn = str(s.exit)
	exit.name = "Exit"
	exit.position = Vector3(float(s.door_x) - float(s.door_w) * 0.5, 0, float(s.d) * 0.5 - 0.02)
	parent.add_child(exit)


static func _examine(parent: Node3D, label: String, verb: String, text: String, at: Vector3, size: Vector3, node_name: String, flag := "") -> void:
	var e := Examine.make(label, verb, func(_who: FpController) -> Dictionary:
		if flag != "":
			GameState.set_flag(flag)
		return {"toast": text}, size)
	e.name = node_name
	e.position = at
	parent.add_child(e)


static func _lamp(parent: Node3D, pos: Vector3, energy: float, rng: float, color: Color, flicker: bool, node_name: String) -> void:
	var l := Tavern.FireLight.new()
	l.name = node_name
	l.light_color = color
	l.base = energy
	l.omni_range = rng
	l.position = pos
	l.flicker = flicker
	l.add_to_group("light_source")
	l.set_meta("radius", rng * 0.6)
	parent.add_child(l)


static func _fill(parent: Node3D, pos: Vector3, energy: float, rng: float) -> void:
	var f := OmniLight3D.new()
	f.light_color = Color("9aa4b4")
	f.light_energy = energy
	f.omni_range = rng
	f.position = pos
	parent.add_child(f)


static func _mats() -> Dictionary:
	return {"castle": Look.mat("castle"), "stone": Look.mat("stone"), "plaster": Look.mat("plaster"), "timber": Look.mat("timber"), "floor": Look.mat("timber"),
		"street": Look.mat("street"), "glass": Inn.glass(GameState.daypart), "iron": Inn._iron_mat(), "cloth": Inn._cloth_mat(), "ink": Inn._unshaded(Color("2a1e14")),
		"brass": _brass(), "chalk": Inn._unshaded(Color("d8d4c8")), "slate": _flat(Color("23272a")), "straw": _flat(Color("9a8a5a")), "bone": _flat(Color("cfc6b2"), 0.8), "water": _flat(Color("16201f"), 0.2)}


static func _brass() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("a8843a")
	m.metallic = 0.7
	m.roughness = 0.35
	m.vertex_color_use_as_albedo = true
	return m


static func _flat(c: Color, rough := 0.95) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.vertex_color_use_as_albedo = true
	return m


static func _finish(parent: Node3D, kit: MeshKit, area: String) -> void:
	var m := _mats()
	m["floor"] = Look.mat(str(SPEC[area].floor))
	var mi := kit.build(m)
	mi.name = "Room_" + area
	parent.add_child(mi)


## 金库之夜：从水门进来了、冠还没拿到、事还没定（7.5）
static func vault_night() -> bool:
	return GameState.has_flag("ch4_vault_entered") and GameState.quest_stage("ch4_main") in ["way", "to_city"] and str(GameState.get_flag("ch4_crown_way", "")) in ["", "stolen"]


## 那只铁匣：白天只能看；金库之夜拿到了莫德的钥匙（她睡着了顺手拿的、打完了她扔下的）就打开铁笼拿走
static func crown_box() -> Dictionary:
	GameState.set_flag("ch4_crown_seen")
	if GameState.has_item("iron_crown"):
		return {"toast": "铁笼开着，石台上空了。"}
	if not vault_night():
		return {"toast": CROWN_TEXT}
	if not GameState.has_flag("ch4_maud_keys"):
		return {"toast": "铁笼锁着。钥匙在莫德腰上那一大串里。"}
	GameState.add_item("iron_crown")
	GameState.set_flag("ch4_crown_way", "stolen")
	if str(GameState.get_flag("ch4_vault", "")) == "":
		GameState.set_flag("ch4_vault", "unseen")
	GameState.set_stage("ch4_main", "to_city")
	return {"toast": "最小的那把钥匙打开了铁笼。铁匣不沉，比你想的轻。你把它揣进怀里——一圈暗色的铁，冠底下那块星铁冰得扎手。（得到：铁冠）"}


## 约斯特那间牢门（7.7）：夜里看门的打盹，撬锁（潜行 14，一次定）；白天、或者人已经出来了，只是看看
static func cell_lock() -> Dictionary:
	if str(GameState.get_flag("ch4_debtor", "")) != "":
		return {"toast": "牢门开着，草铺上没有人。"}
	if not GameState.quest_active("ch4_debtor"):
		return {"toast": "一把生锈的挂锁，锁着当中那间牢门。"}
	if GameState.daypart != "night":
		return {"toast": "看门的就坐在桌子后面，眼睛一直没离开过你。（夜里他会打盹）"}
	if GameState.checks.has("ch4_jost_pick") and not bool(GameState.checks["ch4_jost_pick"]):
		return {"toast": "锁眼被你上回别弯了，再也捅不进去。"}
	if not GameState.check("ch4_jost_pick", "stealth", 14):
		return {"toast": "锁太紧。看门的翻了个身，你只好住手——锁眼被你别弯了。（潜行 14 没过）"}
	GameState.set_flag("ch4_debtor", "broken")
	GameState.complete_quest("ch4_debtor")
	GameState.change_rep("caswell", -5)
	return {"kind": "travel", "area": "debt_prison", "spawn": "front", "name": "债牢", "toast": "锁「咔」的一声开了。约斯特从草铺上爬起来，跟着你贴着墙溜出去，在门口回头看了一眼：「冬至那天，我去议事厅。」（卡斯韦尔家 −5）"}


## 搭这一间：区域入口（main 调）
static func build(area: String, parent: Node3D, reduced_motion := false) -> Transform3D:
	match area:
		"key_hall":
			_key_hall(parent, reduced_motion)
		"key_vault":
			_key_vault(parent, reduced_motion)
		"guild_hall":
			_guild_hall(parent, reduced_motion)
		"dock_tavern":
			_dock_tavern(parent, reduced_motion)
		"debt_prison":
			_debt_prison(parent, reduced_motion)
		"council_hall":
			CrownRooms.council_hall(parent, reduced_motion)              # 冠城（7.6）
		"matilda_inn":
			CrownRooms.matilda_inn(parent, reduced_motion)
		"church_archive":
			CrownRooms.church_archive(parent, reduced_motion)          # 第五章（8.1）
		"well_bottom":
			WellRooms.build(parent, reduced_motion)                     # 第五章（8.3）
	_colliders(parent, area)
	_exit(parent, area)
	if area in WELL_AREAS:
		WellRooms.build_people(parent)
	elif area in CROWN_AREAS:
		CrownPeople.build_room(area, parent)
	else:
		HarborPeople.build_room(area, parent)        # 屋里的人（7.4）
	var s: Array = spawns(area).front
	return Transform3D(Basis(Vector3.UP, deg_to_rad(float(s[1]))), s[0])


# ---------------- 钥楼 · 大厅 ----------------
## 住着谁：卡斯韦尔家的账房先生、门房；缺什么：什么都不缺——炉火旺、灯多，可没有一把给来人坐的好椅子（等着的人坐长凳）；
## 刚发生过什么：黑板上刚写了「冬至清账」，瓦伦家那一栏擦过又写过。
## 一道齐胸高的长柜台横在屋子当中，台上一道铁栅、三个小窗口；柜台后面三张斜面账桌、算筹、天平、一墙账册；前面一排长凳；
## 西北角一扇铁门下金库（锁着）；北墙两面双钥交叉的旗、一块黑板。
static func _key_hall(parent: Node3D, reduced_motion: bool) -> void:
	var kit := MeshKit.new()
	_room(kit, "key_hall", [["s", -4.6, 1.0, 1.4, 2.6], ["s", 4.6, 1.0, 1.4, 2.6], ["n", 2.5, 0.9, 1.8, 3.4]])
	var cz := -0.4                                                       # 柜台
	kit.box("timber", Vector3(0.8, 0.55, cz), Vector3(10.0, 1.1, 0.7), Basis.IDENTITY, 1.0, 0.6)
	kit.box("timber", Vector3(0.8, 1.13, cz), Vector3(10.2, 0.06, 0.8), Basis.IDENTITY, 1.0, 1.0)
	for i in 21:                                                         # 柜台上的铁栅，三个窗口留空
		var x := -4.2 + i * 0.5
		if absf(x + 1.7) < 0.5 or absf(x - 0.8) < 0.5 or absf(x - 3.3) < 0.5:
			continue
		kit.box("iron", Vector3(x, 1.75, cz), Vector3(0.04, 1.2, 0.04))
	kit.box("iron", Vector3(0.8, 2.36, cz), Vector3(10.0, 0.05, 0.06))
	for dx: float in [-1.7, 0.8, 3.3]:                                    # 柜台后面三张斜面账桌、高凳
		var c := Vector3(dx, 0, -1.8)
		kit.box("timber", c + Vector3(0, 0.95, 0), Vector3(1.2, 0.06, 0.7), Basis(Vector3.RIGHT, -0.25), 1.0, 0.8)
		for lx: float in [-0.5, 0.5]:
			kit.box("timber", c + Vector3(lx, 0.47, 0.05), Vector3(0.07, 0.94, 0.55), Basis.IDENTITY, 0.8, 0.5)
		kit.box("cloth", c + Vector3(0, 1.0, 0.02), Vector3(0.6, 0.02, 0.42), Basis(Vector3.RIGHT, -0.25))
		kit.box("timber", c + Vector3(0, 0.36, 0.6), Vector3(0.36, 0.72, 0.36), Basis.IDENTITY, 0.8, 0.6)
	for k in 5:                                                          # 北墙一整面账册架
		for r in 4:
			kit.box("timber", Vector3(-1.6 + k * 1.3, 0.4 + r * 0.75, -3.3), Vector3(1.2, 0.05, 0.4), Basis.IDENTITY, 0.8, 0.6)
	kit.box("timber", Vector3(1.0, 1.5, -3.48), Vector3(6.6, 3.0, 0.05), Basis.IDENTITY, 0.6, 0.5)
	var sc := Vector3(0.8, 1.16, cz)                                     # 柜台上的黄铜天平
	kit.cylinder("brass", sc, sc + Vector3(0, 0.5, 0), 0.03, 0.03, 6)
	kit.box("brass", sc + Vector3(0, 0.5, 0), Vector3(0.6, 0.03, 0.03), Basis(Vector3.BACK, 0.12))
	for s: float in [-1.0, 1.0]:
		kit.cylinder("brass", sc + Vector3(s * 0.28, 0.5 - s * 0.035 - 0.25, 0), sc + Vector3(s * 0.28, 0.5 - s * 0.035 - 0.23, 0), 0.12, 0.12, 8)
	for k in 6:                                                          # 算筹盘
		kit.box("ink", Vector3(-1.7 - 0.25 + k * 0.1, 1.17, cz), Vector3(0.02, 0.01, 0.3))
	kit.box("slate", Vector3(-3.2, 1.9, -3.45), Vector3(2.0, 1.3, 0.05))  # 黑板
	for r in 6:
		kit.box("chalk", Vector3(-3.5 + (0.15 if r > 0 else 0.0), 2.35 - r * 0.17, -3.42), Vector3(0.9 if r > 0 else 1.2, 0.03, 0.005))
		if r > 0:
			kit.box("chalk", Vector3(-2.6, 2.35 - r * 0.17, -3.42), Vector3(0.3 + (0.15 if r == 3 else 0.0), 0.03, 0.005))
	for k in 2:                                                          # 前面两排长凳（等着的人坐这儿）
		kit.box("timber", Vector3(-2.0 + k * 4.6, 0.45, 2.0), Vector3(2.6, 0.08, 0.4), Basis.IDENTITY, 1.0, 0.8)
		for lx: float in [-1.1, 1.1]:
			kit.box("timber", Vector3(-2.0 + k * 4.6 + lx, 0.22, 2.0), Vector3(0.08, 0.44, 0.34), Basis.IDENTITY, 0.8, 0.6)
	var vd := HALL_VAULT_DOOR                                            # 下金库的铁门（锁着）
	kit.box("iron", vd + Vector3(0, 1.1, 0.02), Vector3(1.1, 2.2, 0.08))
	for k in 3:
		kit.box("iron", vd + Vector3(0.38, 0.6 + k * 0.5, 0.08), Vector3(0.12, 0.1, 0.06))
	kit.box("castle", vd + Vector3(0, 2.35, 0.1), Vector3(1.5, 0.3, 0.3))
	_finish(parent, kit, "key_hall")
	var dec := Decor.new()
	for s: float in [-1.0, 1.0]:
		dec.banner(Vector3(1.0 + s * 3.8, 3.9, -3.44), Vector3(0, 0, 1), 1.1, 2.2, Color("26407a"), Color("d8c890"), "keys")
		dec.sconce(Vector3(-6.98, 2.4, s * 1.8), Vector3(1, 0, 0), s > 0.0)
	dec.candles(Vector3(-1.7, 1.05, -1.6), 2)
	dec.candles(Vector3(3.3, 1.05, -1.6), 2)
	dec.chest(Vector3(5.8, 0, -2.6), PI * 0.5)
	dec.chest(Vector3(5.8, 0, -1.5), PI * 0.5, Vector3(0.8, 0.45, 0.5))
	dec.books(Vector3(-1.9, 0.43, -3.25), Vector3(1, 0, 0), 6.2, 71)
	dec.books(Vector3(-1.9, 1.18, -3.25), Vector3(1, 0, 0), 6.2, 72)
	dec.books(Vector3(-1.9, 1.93, -3.25), Vector3(1, 0, 0), 6.2, 73)
	dec.rug(Rect2(-2.6, 0.6, 5.2, 2.6), 0.005, Color("2a3450"), Color("8a7440"))
	dec.build(parent, "Decor", not reduced_motion)
	Inn._solid(parent, Vector3(0.8, 1.2, cz), Vector3(10.2, 2.4, 0.8))
	Inn._solid(parent, Vector3(1.0, 1.5, -3.25), Vector3(6.8, 3.0, 0.5))
	for k in 2:
		Inn._solid(parent, Vector3(-2.0 + k * 4.6, 0.25, 2.0), Vector3(2.6, 0.5, 0.4))
	var vdoor := Door.make("下金库的铁门", 1.1, 2.2, true)
	vdoor.locked_text = VAULT_DOOR_TEXT
	vdoor.name = "VaultDoor"
	vdoor.position = vd + Vector3(-0.55, 0, 0.12)
	parent.add_child(vdoor)
	_examine(parent, "黄铜天平", "看看", SCALES_TEXT, Vector3(0.8, 1.0, 0.2), Vector3(0.9, 0.6, 0.6), "Scales")
	_examine(parent, "清账的黑板", "看黑板", BOARD_TEXT, Vector3(-3.2, 1.2, -3.0), Vector3(2.0, 1.4, 0.6), "ClearingBoard", "ch4_board_read")
	_lamp(parent, Vector3(-2.5, 3.4, 0.8), 3.0, 11.0, Look.LAMP_COLOR, not reduced_motion, "HallLamp")      # 截图：第一版一盏灯 2.2，柜台前一片黑
	_lamp(parent, Vector3(3.8, 3.4, 0.8), 2.6, 10.0, Look.LAMP_COLOR, not reduced_motion, "HallLamp2")
	_lamp(parent, Vector3(0.8, 1.7, -1.4), 1.6, 5.0, Color("ffb060"), not reduced_motion, "DeskLamp")
	_fill(parent, Vector3(0.0, 2.6, 2.6), 2.0, 12.0)
	_fill(parent, Vector3(0.8, 2.8, -2.4), 1.2, 8.0)


# ---------------- 钥楼 · 金库 ----------------
## 住着谁：没人，只有莫德每天下来点一遍匣子；缺什么：光——一盏油灯；刚发生过什么：有一格空着，签上写着「埃德里克·瓦伦（未赎）」。
## 拱顶、三排铁架，架上一格一格的抵押匣；北墙正中一座石台，罩着铁笼，台上那只星铁包角的铁匣；西北角石阶上大厅；东墙一道铁栅水门通北潮沟。
static func _key_vault(parent: Node3D, reduced_motion: bool) -> void:
	var kit := MeshKit.new()
	_room(kit, "key_vault", [])
	for x: float in [-3.6, -1.2, 1.2, 3.6]:                               # 拱：几道石肋
		kit.box("castle", Vector3(x, 2.75, 0), Vector3(0.4, 0.5, 7.0), Basis.IDENTITY, 0.7, 0.5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7301
	for row: float in [-0.4, 1.8]:                                       # 两排铁架、一格一格的匣子
		for side: float in [-1.0, 1.0]:
			var x0 := side * 2.2
			for lv in 4:
				kit.box("iron", Vector3(x0, 0.35 + lv * 0.55, row), Vector3(2.6, 0.04, 0.7))
				for k in 5:
					if rng.randf() < 0.85:
						var bx := x0 - 1.0 + k * 0.5
						kit.box("timber" if rng.randf() < 0.6 else "iron", Vector3(bx, 0.35 + lv * 0.55 + 0.17, row + rng.randf_range(-0.05, 0.05)), Vector3(0.38, 0.3, 0.45), Basis.IDENTITY, 1.0, 0.7)
						kit.box("cloth", Vector3(bx, 0.35 + lv * 0.55 + 0.2, row + 0.235), Vector3(0.2, 0.08, 0.005))
			for px: float in [x0 - 1.3, x0 + 1.3]:
				kit.box("iron", Vector3(px, 1.15, row), Vector3(0.05, 2.3, 0.7))
	var cb := CROWN_BOX                                                  # 石台、铁笼、铁匣
	kit.box("castle", cb + Vector3(0, 0.45, 0), Vector3(1.4, 0.9, 1.0), Basis.IDENTITY, 0.9, 0.6)
	kit.box("iron", cb + Vector3(0, 1.08, 0), Vector3(0.6, 0.36, 0.4), Basis.IDENTITY, 1.0, 0.7)
	for s: float in [-1.0, 1.0]:
		kit.box("brass", cb + Vector3(s * 0.3, 1.08, 0.2), Vector3(0.06, 0.38, 0.06))
		kit.box("brass", cb + Vector3(s * 0.3, 1.08, -0.2), Vector3(0.06, 0.38, 0.06))
	for k in 9:
		var x := -0.85 + k * 0.212
		kit.box("iron", cb + Vector3(x, 1.2, 0.62), Vector3(0.04, 2.4, 0.04))
		kit.box("iron", cb + Vector3(x, 1.2, -0.62), Vector3(0.04, 2.4, 0.04))
	for k in 6:
		var z := -0.55 + k * 0.22
		for s: float in [-1.0, 1.0]:
			kit.box("iron", cb + Vector3(s * 0.85, 1.2, z), Vector3(0.04, 2.4, 0.04))
	kit.box("iron", cb + Vector3(0, 2.42, 0), Vector3(1.75, 0.05, 1.3))
	var st := VAULT_STAIR                                                # 石阶：贴着北墙一级一级往西上，钻进顶上的黑洞
	for k in 8:
		var top := 0.33 * (k + 1)
		kit.box("castle", st + Vector3(-k * 0.42, top * 0.5, 0), Vector3(0.42, top, 1.0), Basis.IDENTITY, 0.9, 0.5)
	kit.box("ink", st + Vector3(-2.7, 2.99, 0), Vector3(1.6, 0.04, 1.0))
	var g := VAULT_GATE                                                  # 东墙的水门：墙上开一个洞、一道铁栅，外面是黑水
	kit.box("water", Vector3(g.x + 0.6, 0.02, g.z), Vector3(0.8, 0.04, 2.2))
	for k in 9:
		kit.box("iron", Vector3(g.x - 0.05, 1.0, g.z - 1.0 + k * 0.25), Vector3(0.05, 2.0, 0.05))
	kit.box("iron", Vector3(g.x - 0.05, 2.0, g.z), Vector3(0.06, 0.06, 2.2))
	kit.box("iron", Vector3(g.x - 0.05, 0.6, g.z), Vector3(0.06, 0.06, 2.2))
	_finish(parent, kit, "key_vault")
	var dec := Decor.new()
	dec.candles(cb + Vector3(0.9, 0.0, 0.8), 1, false)
	dec.chest(Vector3(-4.6, 0, 2.6), 0.2)
	dec.build(parent, "Decor", not reduced_motion)
	for row: float in [-0.4, 1.8]:
		for side: float in [-1.0, 1.0]:
			Inn._solid(parent, Vector3(side * 2.2, 1.2, row), Vector3(2.7, 2.4, 0.75))
	Inn._solid(parent, cb + Vector3(0, 1.2, 0), Vector3(1.8, 2.4, 1.3))
	Inn._solid(parent, st + Vector3(-1.47, 1.5, 0), Vector3(3.4, 3.0, 1.0))      # 整道石阶一个盒子（不让人爬进顶上的洞里）
	var up := Door.make("上大厅的石阶", 1.0, 2.0, false)            # 石阶脚下：上去是大厅（门闩在金库这一面：从下面推得开）
	up.verb = "上去"
	up.to_area = "key_hall"
	up.to_spawn = "vault_stair"
	up.panel = false
	up.name = "StairUp"
	up.transform = Transform3D(Basis(Vector3.UP, PI * 0.5), st + Vector3(0.3, 0, 0.5))
	parent.add_child(up)
	var night := vault_night()
	var gate := Door.make("铁栅水门", 2.2, 2.0, not night)
	gate.locked_text = GATE_TEXT
	gate.name = "WaterGate"
	if night:                                                          # 金库之夜（7.5）：从水门进来的，也从水门出去（顺着北潮沟摸回西边那座桥）
		gate.to_area = "harbor"
		gate.to_spawn = "keyhouse_gate"
		gate.verb = "从水门出去"
	gate.transform = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(g.x - 0.1, 0, g.z + 1.1))
	parent.add_child(gate)
	var box := Examine.make("星铁包角的铁匣", "看看", func(_who: FpController) -> Dictionary: return crown_box(), Vector3(1.6, 1.6, 0.4))
	box.name = "CrownBox"
	box.position = cb + Vector3(0, 0, 0.8)
	box.verb_fn = func() -> String: return "打开铁笼" if vault_night() and GameState.has_flag("ch4_maud_keys") and not GameState.has_item("iron_crown") else "看看"
	parent.add_child(box)
	_examine(parent, "抵押匣", "看签", SHELF_TEXT, Vector3(-2.2, 0, 0.3), Vector3(2.4, 1.8, 0.4), "PledgeShelf")
	_lamp(parent, cb + Vector3(0.9, 0.5, 0.8), 1.8, 7.0, Color("ffb060"), not reduced_motion, "VaultCandle")
	_lamp(parent, Vector3(-4.0, 2.2, 2.4), 1.4, 7.0, Look.LAMP_COLOR, not reduced_motion, "VaultLantern")
	_fill(parent, Vector3(0.0, 2.4, 1.0), 1.3, 9.0)


# ---------------- 渡工行会会馆 ----------------
## 住着谁：行会的港口头领科妮莉亚、记账的、等活的船工；缺什么：活——船期板上空了几格；刚发生过什么：运粮船搁浅了，墙上「待修」。
## 一张长桌（摊着河道图、潮汐表压着石头）、墙上挂着桨和成卷的缆绳、一个大铁炉、船期板、潮汐表、角落里一摞空酒桶；东墙两面行会的旗。
static func _guild_hall(parent: Node3D, reduced_motion: bool) -> void:
	var kit := MeshKit.new()
	_room(kit, "guild_hall", [["s", -4.2, 1.2, 1.2, 2.4], ["s", 4.2, 1.2, 1.2, 2.4], ["w", 0.0, 1.0, 1.4, 2.6]])
	kit.box("timber", Vector3(0, 0.82, -0.6), Vector3(6.0, 0.08, 1.4), Basis.IDENTITY, 1.0, 0.8)    # 长桌
	for lx: float in [-2.7, 2.7]:
		for lz: float in [-1.1, -0.1]:
			kit.box("timber", Vector3(lx, 0.4, lz), Vector3(0.12, 0.8, 0.12), Basis.IDENTITY, 0.8, 0.6)
	kit.box("cloth", Vector3(-1.0, 0.87, -0.6), Vector3(2.0, 0.01, 1.0))                             # 河道图
	for r in 7:
		kit.box("ink", Vector3(-1.6 + r * 0.2, 0.876, -0.6 + sin(r * 1.3) * 0.25), Vector3(0.22, 0.003, 0.02), Basis(Vector3.UP, r * 0.4))
	for k in 2:
		kit.box("timber", Vector3(0, 0.45, -0.6 + (k * 2 - 1) * 1.1), Vector3(5.6, 0.07, 0.35), Basis.IDENTITY, 1.0, 0.8)
	for k in 4:                                                          # 北墙上挂着的桨
		var x := -4.8 + k * 0.7
		kit.box("timber", Vector3(x, 2.2, -3.9), Vector3(0.06, 2.6, 0.06), Basis(Vector3.BACK, 0.06), 0.9, 0.7)
		kit.box("timber", Vector3(x - 0.08, 1.0, -3.9), Vector3(0.22, 0.7, 0.03), Basis(Vector3.BACK, 0.06), 0.9, 0.7)
	for k in 3:                                                          # 成卷的缆绳
		kit.cylinder("straw", Vector3(-5.6, 0.05 + k * 0.2, 2.8 - k * 0.1), Vector3(-5.6, 0.22 + k * 0.2, 2.8 - k * 0.1), 0.45, 0.45, 10)
	var stove := Vector3(4.8, 0, -3.0)                                   # 大铁炉、烟囱
	kit.box("iron", stove + Vector3(0, 0.5, 0), Vector3(1.0, 1.0, 0.8), Basis.IDENTITY, 1.0, 0.7)
	kit.cylinder("iron", stove + Vector3(0, 1.0, -0.1), stove + Vector3(0, 4.0, -0.1), 0.14, 0.14, 8)
	kit.box("slate", Vector3(6.46, 1.8, -0.5), Vector3(0.05, 1.4, 2.2))  # 船期板（东墙）
	for r in 6:
		kit.box("chalk", Vector3(6.43, 2.3 - r * 0.18, -0.6), Vector3(0.005, 0.03, 1.6 if r != 4 else 0.6))
	kit.box("cloth", Vector3(-1.5, 1.8, -3.95), Vector3(1.4, 1.0, 0.02))                              # 潮汐表（北墙）
	for r in 8:
		kit.box("ink", Vector3(-1.5, 2.2 - r * 0.1, -3.94), Vector3(1.1, 0.012, 0.005))
	_finish(parent, kit, "guild_hall")
	var dec := Decor.new()
	for s: float in [-1.0, 1.0]:
		dec.banner(Vector3(6.44, 3.5, s * 2.4), Vector3(-1, 0, 0), 1.0, 1.9, Color("5a5e62"), Color("d8d2c0"), "oar", Color("8a6a3a"))
	for k in 4:
		dec.barrel(Vector3(-5.6 + (k % 2) * 0.7, 0, -2.8 + (k / 2) * 0.7))
	dec.crate(Vector3(5.2, 0, 2.8), 0.3)
	dec.candles(Vector3(1.6, 0.86, -0.6), 3)
	dec.build(parent, "Decor", not reduced_motion)
	Inn._solid(parent, Vector3(0, 0.45, -0.6), Vector3(6.0, 0.9, 1.4))
	Inn._solid(parent, stove + Vector3(0, 0.5, 0), Vector3(1.0, 1.0, 0.8))
	Inn._solid(parent, Vector3(-5.6, 0.35, 2.75), Vector3(1.0, 0.7, 1.0))
	_examine(parent, "潮汐表", "看看", TIDE_TEXT, Vector3(-1.5, 1.0, -3.6), Vector3(1.6, 1.4, 0.6), "TideChart", "ch4_tide_read")
	_examine(parent, "船期板", "看看", SCHEDULE_TEXT, Vector3(6.1, 1.0, -0.5), Vector3(0.6, 1.4, 2.2), "BoatSchedule")
	var fire := Tavern.FireLight.new()
	fire.name = "StoveFire"
	fire.light_color = Color("ff8a3a")
	fire.base = 1.4
	fire.omni_range = 6.0
	fire.position = stove + Vector3(0, 0.6, 0.6)
	fire.flicker = not reduced_motion
	fire.add_to_group("light_source")
	fire.set_meta("radius", 3.0)
	parent.add_child(fire)
	_lamp(parent, Vector3(0, 3.2, -0.6), 3.0, 11.0, Look.LAMP_COLOR, not reduced_motion, "HangLamp")
	_fill(parent, Vector3(-4.0, 2.4, 2.6), 1.8, 10.0)
	_fill(parent, Vector3(3.0, 2.4, 2.0), 1.2, 8.0)


# ---------------- 「咸潮」酒馆 ----------------
## 住着谁：码头上卸货的、等船的、被钥楼赶出来的；缺什么：酒——柜台后面的桶一半是空的，敲着是空响；
## 刚发生过什么：有人在墙上用刀刻了一道「冬至」，下面一排划痕在倒数。
## 屋子矮、梁低；柜台在北墙，后面一排酒桶；东边一个砖砌的大火塘；三张粗木桌、长凳；墙上挂着渔网和一只干了的鲨鱼头（不，一副鲸的下颌骨——灰鲸河的名字从这儿来）。
static func _dock_tavern(parent: Node3D, reduced_motion: bool) -> void:
	var kit := MeshKit.new()
	_room(kit, "dock_tavern", [["s", -2.0, 1.0, 1.1, 2.1], ["w", 0.6, 0.9, 1.2, 2.2]])
	kit.box("timber", Vector3(-0.8, 0.55, -2.4), Vector3(5.0, 1.1, 0.6), Basis.IDENTITY, 1.0, 0.6)    # 柜台
	kit.box("timber", Vector3(-0.8, 1.13, -2.4), Vector3(5.2, 0.06, 0.7), Basis.IDENTITY, 1.0, 1.0)
	for k in 6:                                                          # 柜台后面一排酒桶（侧躺着）
		var c := Vector3(-3.2 + k * 0.9, 0.45, -3.25)
		kit.cylinder("timber", c - Vector3(0, 0, 0.3), c + Vector3(0, 0, 0.3), 0.36, 0.36, 10)
		kit.cylinder("iron", c - Vector3(0, 0, 0.18), c - Vector3(0, 0, 0.14), 0.37, 0.37, 10)
		kit.cylinder("iron", c + Vector3(0, 0, 0.14), c + Vector3(0, 0, 0.18), 0.37, 0.37, 10)
	var fp := Vector3(3.9, 0, -1.6)                                      # 火塘
	kit.box("stone", fp + Vector3(0, 0.9, 0), Vector3(1.0, 1.8, 1.8), Basis.IDENTITY, 0.9, 0.6)
	kit.box("stone", fp + Vector3(0, 2.6, 0), Vector3(0.8, 1.6, 1.2), Basis.IDENTITY, 0.8, 0.8)
	kit.box("ink", fp + Vector3(-0.42, 0.5, 0), Vector3(0.2, 0.7, 1.1))
	for t: Vector3 in [Vector3(-2.4, 0, 0.6), Vector3(0.4, 0, 1.0), Vector3(-1.2, 0, 2.4)]:   # 三张粗木桌、长凳
		kit.box("timber", t + Vector3(0, 0.78, 0), Vector3(1.8, 0.08, 0.9), Basis.IDENTITY, 1.0, 0.8)
		for lx: float in [-0.75, 0.75]:
			kit.box("timber", t + Vector3(lx, 0.38, 0), Vector3(0.1, 0.76, 0.7), Basis.IDENTITY, 0.8, 0.6)
		for s: float in [-1.0, 1.0]:
			kit.box("timber", t + Vector3(0, 0.44, s * 0.7), Vector3(1.7, 0.06, 0.3), Basis.IDENTITY, 1.0, 0.8)
	for k in 3:                                                          # 墙上的渔网（几道斜线）
		kit.box("straw", Vector3(-4.48, 2.0, -1.8 + k * 0.4), Vector3(0.02, 1.0, 0.03), Basis(Vector3.RIGHT, 0.5), 1.0, 1.0)
		kit.box("straw", Vector3(-4.48, 2.0, -1.8 + k * 0.4), Vector3(0.02, 1.0, 0.03), Basis(Vector3.RIGHT, -0.5), 1.0, 1.0)
	for s: float in [-1.0, 1.0]:                                         # 柜台上方一副鲸的下颌骨
		kit.box("bone", Vector3(-0.8 + s * 0.9, 2.7, -3.52), Vector3(1.9, 0.14, 0.12), Basis(Vector3.BACK, s * 0.22), 1.0, 0.8)      # 骨头受光（第一版用了不受光的粉笔色，像一道发光的白线，截图）
	for k in 9:                                                          # 门边墙上刻的倒数划痕
		kit.box("ink", Vector3(4.48, 1.4, 1.4 + k * 0.07), Vector3(0.01, 0.3, 0.012))
	_finish(parent, kit, "dock_tavern")
	var dec := Decor.new()
	dec.candles(Vector3(-2.4, 0.82, 0.6), 2)
	dec.candles(Vector3(0.4, 0.82, 1.0), 1)
	dec.barrel(Vector3(3.4, 0, 2.6))
	dec.crate(Vector3(-3.9, 0, 2.8), 0.5)
	dec.build(parent, "Decor", not reduced_motion)
	Inn._solid(parent, Vector3(-0.8, 0.6, -2.4), Vector3(5.2, 1.2, 0.7))
	Inn._solid(parent, Vector3(-0.8, 0.5, -3.25), Vector3(5.8, 1.0, 0.8))
	Inn._solid(parent, fp + Vector3(0, 1.0, 0), Vector3(1.0, 2.0, 1.8))
	for t: Vector3 in [Vector3(-2.4, 0, 0.6), Vector3(0.4, 0, 1.0), Vector3(-1.2, 0, 2.4)]:
		Inn._solid(parent, t + Vector3(0, 0.4, 0), Vector3(1.8, 0.8, 0.9))
	_examine(parent, "柜台", "看看", COUNTER_TEXT, Vector3(-0.8, 0.6, -2.0), Vector3(2.0, 1.0, 0.5), "TavernCounter")
	var fire := Tavern.FireLight.new()
	fire.name = "Hearth"
	fire.light_color = Color("ff8a3a")
	fire.base = 1.8
	fire.omni_range = 7.0
	fire.position = fp + Vector3(-0.8, 0.6, 0)
	fire.flicker = not reduced_motion
	fire.add_to_group("light_source")
	fire.set_meta("radius", 3.5)
	parent.add_child(fire)
	_lamp(parent, Vector3(-0.8, 2.6, 0.6), 2.4, 8.0, Look.LAMP_COLOR, not reduced_motion, "HangLamp")
	_fill(parent, Vector3(-3.0, 2.0, 2.2), 1.5, 8.0)


# ---------------- 债牢 ----------------
## 住着谁：欠债的人、看门的；缺什么：炭——屋子当中一个炭盆，冷的；刚发生过什么：看门的账上新写了一行「冬至以前不赎，转卖钥楼」。
## 北墙一排三间牢房（铁栅门、草铺），看门的桌子、一本账、一串钥匙；墙上的铁链；一扇很高很小的窗。
static func _debt_prison(parent: Node3D, reduced_motion: bool) -> void:
	var kit := MeshKit.new()
	_room(kit, "debt_prison", [["e", -1.0, 0.6, 2.6, 3.2]])
	for k in 3:                                                          # 三间牢房：隔墙、铁栅门、草铺
		var cx := -3.6 + k * 3.6
		for s: float in [-1.0, 1.0]:
			kit.box("castle", Vector3(cx + s * 1.8, 1.8, -2.9), Vector3(0.3, 3.6, 2.2), Basis.IDENTITY, 0.8, 0.5)
		for i in 13:
			kit.box("iron", Vector3(cx - 1.55 + i * 0.26, 1.2, -1.8), Vector3(0.05, 2.4, 0.05))
		kit.box("iron", Vector3(cx, 2.42, -1.8), Vector3(3.3, 0.06, 0.06))
		kit.box("iron", Vector3(cx, 1.2, -1.8), Vector3(3.3, 0.05, 0.05))
		kit.box("straw", Vector3(cx - 0.7, 0.08, -3.3), Vector3(1.6, 0.16, 0.9), Basis(Vector3.UP, 0.1 * k), 1.0, 0.8)
	var t := Vector3(3.6, 0, 1.6)                                        # 看门的桌子
	kit.box("timber", t + Vector3(0, 0.78, 0), Vector3(1.6, 0.08, 0.8), Basis.IDENTITY, 1.0, 0.8)
	for lx: float in [-0.7, 0.7]:
		kit.box("timber", t + Vector3(lx, 0.38, 0), Vector3(0.1, 0.76, 0.6), Basis.IDENTITY, 0.8, 0.6)
	kit.box("cloth", t + Vector3(0, 0.83, 0), Vector3(0.6, 0.02, 0.42))
	for r in 6:
		kit.box("ink", t + Vector3(0, 0.842, -0.15 + r * 0.06), Vector3(0.45, 0.003, 0.01))
	kit.box("iron", t + Vector3(0.6, 0.85, -0.2), Vector3(0.2, 0.04, 0.14))
	var br := Vector3(0, 0, 1.2)                                         # 冷了的炭盆
	kit.cylinder("iron", br, br + Vector3(0, 0.6, 0), 0.08, 0.08, 6)
	kit.cylinder("iron", br + Vector3(0, 0.6, 0), br + Vector3(0, 0.8, 0), 0.25, 0.45, 8)
	kit.cylinder("ink", br + Vector3(0, 0.76, 0), br + Vector3(0, 0.78, 0), 0.4, 0.4, 8)
	for k in 3:                                                          # 西墙上的铁链
		kit.box("iron", Vector3(-5.46, 1.6 - k * 0.3, 1.8 + k * 0.1), Vector3(0.04, 0.4, 0.06), Basis(Vector3.RIGHT, 0.4 * (k % 2 * 2 - 1)))
	_finish(parent, kit, "debt_prison")
	var dec := Decor.new()
	dec.candles(t + Vector3(-0.5, 0.82, 0.1), 1)
	dec.sconce(Vector3(-5.48, 2.2, -0.6), Vector3(1, 0, 0), true)
	dec.build(parent, "Decor", not reduced_motion)
	for k in 3:
		var cx := -3.6 + k * 3.6
		Inn._solid(parent, Vector3(cx, 1.2, -1.8), Vector3(3.4, 2.4, 0.15))
		for s: float in [-1.0, 1.0]:
			Inn._solid(parent, Vector3(cx + s * 1.8, 1.8, -2.9), Vector3(0.3, 3.6, 2.2))
	Inn._solid(parent, t + Vector3(0, 0.4, 0), Vector3(1.6, 0.8, 0.8))
	Inn._solid(parent, br + Vector3(0, 0.4, 0), Vector3(0.8, 0.8, 0.8))
	_examine(parent, "看门的账", "看看", DEBT_TEXT, t + Vector3(0, 0.6, 0), Vector3(1.4, 0.6, 0.8), "DebtBook", "ch4_debts_read")
	var lock := Examine.make("牢门的锁", "看看", func(_who: FpController) -> Dictionary: return cell_lock(), Vector3(1.0, 1.2, 0.5))   # 债牢里的人（7.7）：夜里撬开约斯特那间
	lock.name = "CellLock"
	lock.position = Vector3(0.0, 0.6, -1.55)
	lock.verb_fn = func() -> String: return "撬锁" if GameState.quest_active("ch4_debtor") and GameState.daypart == "night" else "看看"
	parent.add_child(lock)
	_lamp(parent, Vector3(3.6, 1.6, 1.6), 1.6, 7.0, Color("ffb060"), not reduced_motion, "TableCandle")
	_fill(parent, Vector3(-1.0, 2.6, 1.6), 1.6, 10.0)
	_fill(parent, Vector3(0.0, 2.6, -1.0), 1.0, 7.0)


## 地图册「本地」页
static func map_spec(area: String) -> Dictionary:
	var s: Dictionary = SPEC[area]
	var w := float(s.w)
	var d := float(s.d)
	var shapes := []
	var exits := []
	match area:
		"key_hall":
			shapes = [{"k": "furniture", "rect": Rect2(-4.2, -0.75, 10.0, 0.7), "label": "柜台"}, {"k": "furniture", "rect": Rect2(-2.3, -3.5, 6.6, 0.5), "label": "账册"},
				{"k": "furniture", "rect": Rect2(-3.3, 1.8, 2.6, 0.4)}, {"k": "furniture", "rect": Rect2(1.3, 1.8, 2.6, 0.4)}]
			exits.append({"at": Vector2(HALL_VAULT_DOOR.x, -d * 0.5), "dir": Vector2(0, -1), "to": "key_vault", "spawn": "stair", "name": "下金库的铁门"})
		"key_vault":
			shapes = [{"k": "furniture", "rect": Rect2(-3.5, -0.75, 7.0, 0.7), "label": "抵押匣"}, {"k": "furniture", "rect": Rect2(-3.5, 1.45, 7.0, 0.7)},
				{"k": "furniture", "rect": Rect2(-0.9, -3.25, 1.8, 1.3), "label": "铁匣"}]
			shapes.append({"k": "furniture", "rect": Rect2(VAULT_STAIR.x - 3.15, VAULT_STAIR.z - 0.5, 3.4, 1.0), "label": "石阶"})
			exits.append({"at": Vector2(VAULT_STAIR.x - 2.0, -d * 0.5), "dir": Vector2(0, -1), "to": "key_hall", "spawn": "vault_stair", "name": "上大厅的石阶"})
		"guild_hall":
			shapes = [{"k": "furniture", "rect": Rect2(-3.0, -1.3, 6.0, 1.4), "label": "长桌"}, {"k": "furniture", "rect": Rect2(4.3, -3.4, 1.0, 0.8), "label": "炉子"}]
		"dock_tavern":
			shapes = [{"k": "furniture", "rect": Rect2(-3.3, -2.7, 5.0, 0.6), "label": "柜台"}, {"k": "furniture", "rect": Rect2(3.4, -2.5, 1.0, 1.8), "label": "火塘"},
				{"k": "furniture", "rect": Rect2(-3.3, 0.15, 1.8, 0.9)}, {"k": "furniture", "rect": Rect2(-0.5, 0.55, 1.8, 0.9)}, {"k": "furniture", "rect": Rect2(-2.1, 1.95, 1.8, 0.9)}]
		"debt_prison":
			shapes = [{"k": "furniture", "rect": Rect2(-5.4, -4.0, 10.8, 2.2), "label": "牢房"}, {"k": "furniture", "rect": Rect2(2.8, 1.2, 1.6, 0.8), "label": "看门的桌子"}]
		"well_bottom":
			shapes = WellRooms.map_shapes()
		"council_hall", "matilda_inn", "church_archive":
			shapes = CrownRooms.map_shapes(area)
	if str(s.exit) != "":
		exits.append({"at": Vector2(float(s.door_x), d * 0.5), "dir": Vector2(0, 1), "to": str(s.get("out", "harbor")), "spawn": str(s.exit), "name": str(s.exit_name)})
	return {"bounds": Rect2(-w * 0.5, -d * 0.5, w, d), "shapes": shapes, "exits": exits}
