class_name CrownPeople
extends RefCounted
## 冠城一角的人（路线图 7.6；STORY.md 7.2「贫民区的一条斜街（挤、窄、晾着衣服、排队买面包）」、7.5 第 6 步、7.6「冠城斜街」）。
## 有对话的（data/dialogue/crown.json）：玛蒂尔达（她新盘下的小酒馆里）、议事厅的差役（议事厅里）、斜街上堵你的人（冠在你手里时）。
## 只说一句的：桥门的守卫、面包坊门口排队的人、洗衣妇、从北边逃荒下来的、行会的船工、广场上等着看冬议的人；酒馆里喝酒的。
## 说的都是这几天城里的事：冬议、面包的价钱、北边的饥荒、王座空着；前三章留下的事（罪证念给了佃农的：队伍里有人骂洛蒙德家；无旗者收编过的：斜街上有人认得你）。

const GUARD_LINES := ["冬议前三天，桥门天一黑就落闸。", "北边来的？（他看了一眼你的靴子）往上走，别在桥门这儿站着。"]
const QUEUE_LINES := ["从天亮排到现在。一人一个，冬至以前都是这个价——冬至以后谁知道。", "（她把孩子往怀里搂了搂）前面还有十一个。", "议事厅里五把椅子，面包坊里一个炉子。你说哪个要紧？", "北边的人还往城里来。来了也是排队。", "（他跺着脚取暖，没理你）", "听说钥楼里押着一顶冠。冠能吃吗？"]
const QUEUE_SOUTH := "洛蒙德家的粮仓是满的——南边麦渡的人当着全村念过账本。满的！我们在这儿排队。"
const WASHER_LINES := ["（她把冻硬的床单往绳子上甩）晾一天，冻一天。冬至那天总该出太阳。", "河水比冰还冷。王宫里的衣服，是用热水洗的。"]
const REFUGEE_LINES := ["（一个瘦得脱了形的男人，坐在门槛上）羊脊村……再往北。今年冬天，烽燧线那边一车粮都没到。", "（他伸出手，又缩了回去）"]
const BOATMAN_LINES := ["回双钥港？顺流半天。船在这儿等到午后。", "行会的船，冬议那天不开。老爷们要的是热闹，不是船。"]
const CROWD_LINES := ["辰时开门。我们这种人，站在栏杆外头听个响。", "王座空了三年，今天总该有个说法。", "（他朝议事厅门上那根空旗杆努了努嘴）王室那面旗，没人敢挂。"]
const DRINKER_LINES := ["（他捧着杯子）霜渡镇来的老板娘，酒淡，嘴紧。", "（他朝门口看了一眼）这条街上，晚上别一个人走。"]
const OUTLAW_LINES := ["（他把帽檐往下一压）鹭沼那一回，你没把我们卖了。斜街上这几天有生面孔，盯着从桥门进来的人。", "（他靠着墙，像在晒太阳）我在这儿。你走你的。"]
const MILO_LINES := ["（他捧着一碗热汤，吹了半天也不喝）", "（他小声说）我再也不去上城送面包了。"]
const AMBUSH_AT := Vector2(-9.6, -6.2)               # 斜街上堵你的人：第二条小巷的巷口（往北那条）
const AMBUSH_FACE := Vector2(-12.0, 0.4)


static func ground(p: Vector2) -> float:
	return CrownCity.height_at(p.x, p.y)


static func yaw_to(from: Vector2, to: Vector2) -> float:
	return HarborPeople.yaw_to(from, to)


## 冠在你手里（换、偷）进冠城：斜街上有人堵你（还没了结过的）
static func ambush_due() -> bool:
	return GameState.has_item("iron_crown") and not GameState.has_flag("ch4_ambush")


static func ambush_count() -> int:
	return 2 if str(GameState.get_flag("ch1_outlaws", "")) == "ally" else 3       # 无旗者收编过的：巷子里有人拽回去一个


## 进了冠城：主线到 in_city（main 进区域时调；只从 to_city 往前推）
static func arrived() -> bool:
	if GameState.quest_stage("ch4_main") == "to_city" and str(GameState.get_flag("ch4_lighthouse", "")) != "lit":
		GameState.set_flag("ch4_lighthouse", "dark")                    # 灯塔的火（7.7）：上冠城时还没亮
	if GameState.quest_stage("ch4_main") == "to_city":
		GameState.set_stage("ch4_main", "in_city")
		return true
	return false


## 玛蒂尔达说完了冬议上的椅子和昨夜的酒：主线到 council（main 每段对话结束时调）
static func matilda_heard() -> bool:
	if GameState.quest_stage("ch4_main") in ["to_city", "in_city"] and GameState.has_flag("ch4_seats_heard") and GameState.has_flag("ch4_drinks_heard"):
		GameState.set_stage("ch4_main", "council")
		return true
	return false


## 城里只说一句的人：[编号, 名字, 位置, 朝向, 台词]
static func crowd() -> Array:
	var out := []
	for s: float in [-1.0, 1.0]:
		var p := Vector2(-36.6, s * 3.4)
		out.append(["gate_guard%d" % int(s + 1.0), "桥门的守卫", p, yaw_to(p, p + Vector2(0.4, -s)), GUARD_LINES if s < 0.0 else GUARD_LINES.slice(1) + GUARD_LINES.slice(0, 1)])
	var bk := CrownTown.bakery()
	var front: Vector2 = bk.front
	var face: Vector2 = bk.face
	var along := Vector2(-face.y, face.x)                                # 顺着街往西排
	if along.x > 0.0:
		along = -along
	var south := str(GameState.get_flag("ch3_evidence_to", "")) == "tenants"
	for k in 7:
		var p := front + face * (1.0 + 0.1 * (k % 2)) + along * (1.0 + k * 0.85)
		var lines: Array = QUEUE_LINES.slice(k % QUEUE_LINES.size()) + QUEUE_LINES.slice(0, k % QUEUE_LINES.size())
		if south and k == 2:
			lines = [QUEUE_SOUTH] + lines
		out.append(["queue%d" % k, "排队买面包的", p, yaw_to(p, p - along), lines])
	for it: Array in [["washer1", Vector2(-24.4, 16.0), Vector2(-27.0, 16.0)], ["washer2", Vector2(19.6, 12.0), Vector2(16.0, 12.0)]]:
		out.append([it[0], "洗衣妇", it[1], yaw_to(it[1], it[2]), WASHER_LINES if it[0] == "washer1" else WASHER_LINES.slice(1) + WASHER_LINES.slice(0, 1)])
	var rp := Vector2(-18.3, 4.9)
	out.append(["refugee", "北边来的人", rp, yaw_to(rp, Vector2(-19.0, 3.4)), REFUGEE_LINES])
	for it: Array in [["boatman1", Vector2(-68.0, 7.0), Vector2(-62.0, 9.0)], ["boatman2", Vector2(-71.0, 1.0), Vector2(-60.0, 0.0)]]:
		out.append([it[0], "行会的船工", it[1], yaw_to(it[1], it[2]), BOATMAN_LINES if it[0] == "boatman1" else BOATMAN_LINES.slice(1) + BOATMAN_LINES.slice(0, 1)])
	var door := CrownTown.council_front()
	for k in 4:
		var p := door + Vector2(-6.0 + k * 3.6, 7.0 + (k % 2) * 1.6)
		out.append(["square%d" % k, "等着看冬议的人", p, yaw_to(p, door), CROWD_LINES.slice(k % 3) + CROWD_LINES.slice(0, k % 3)])
	if str(GameState.get_flag("ch1_outlaws", "")) == "ally":
		var op := Vector2(-26.0, 9.6)
		out.append(["outlaw", "认得你的人", op, yaw_to(op, Vector2(-24.0, 4.0)), OUTLAW_LINES])
	return out


## 冠城（室外）：城里的人（同步放；远了不画）
static func build(parent: Node3D) -> void:
	if ambush_due():
		var leader: Npc = null
		var spots := [[AMBUSH_AT, 0.0], [AMBUSH_AT + Vector2(-1.4, -1.2), 0.0], [AMBUSH_AT + Vector2(1.3, -1.4), 0.0]]
		for k in ambush_count():
			var at: Vector2 = (spots[k] as Array)[0]
			var t := Npc.make("蒙着脸的人", [] if k == 0 else ["（他不说话，手按在腰上）"], Color("2a2a2c"))
			t.name = "Npc_ambusher%d" % k
			if k == 0:
				t.dialogue_area = "crown"
				t.dialogue_id = "ambush"
				leader = t
			t.position = Vector3(at.x, ground(at), at.y)
			t.rotation.y = deg_to_rad(yaw_to(at, AMBUSH_FACE))
			t.add_to_group(Encounter.group_name("crown_ambush"))
			t.set_meta("enemy_kind", "swordsman" if k == 0 else "clubber")
			t.set_meta("enemy_id", "ambusher%d" % k)
			parent.add_child(t)
		var tr := StreetTrigger.make(Vector3(7.0, 3.0, 7.0), "crown", "ambush", leader)       # 走到巷口前面那段斜街上，他们就出来堵你
		tr.name = "AmbushTrigger"
		tr.position = Vector3(-11.0, ground(Vector2(-11.0, 0.0)), 0.0)
		parent.add_child(tr)
	for it: Array in talkers():                                         # 有对话的（7.7）：面包师、巷子里的米洛
		var at: Vector2 = it[2]
		var t := Npc.make(str(it[1]), [], Color("5a5248"))
		t.name = "Npc_" + str(it[0])
		t.dialogue_area = "crown"
		t.dialogue_id = str(it[4])
		t.position = Vector3(at.x, ground(at), at.y)
		t.rotation.y = deg_to_rad(float(it[3]))
		t.far_end = Plain.NPC_FAR
		t.label_far = Plain.LABEL_FAR
		parent.add_child(t)
	for it: Array in crowd():
		var at: Vector2 = it[2]
		var n := Npc.make(str(it[1]), it[4], Color("5a5248"))
		n.name = "Npc_" + str(it[0])
		n.position = Vector3(at.x, _floor_y(at), at.y)
		n.rotation.y = deg_to_rad(float(it[3]))
		n.far_end = Plain.NPC_FAR
		n.label_far = Plain.LABEL_FAR
		parent.add_child(n)


## 有对话的（7.7）：[编号, 名字, 位置, 朝向, 对话编号]。米洛只在玛蒂尔达托你找他、还没找到的时候缩在巷子里
const MILO_AT := Vector2(24.8, 33.3)


static func talkers() -> Array:
	var bk := CrownTown.bakery()
	var face: Vector2 = bk.face
	var along := Vector2(-face.y, face.x)
	if along.x > 0.0:
		along = -along
	var bp: Vector2 = (bk.front as Vector2) + face * 0.8 - along * 1.3   # 门的另一边（队排在西边）
	var out := [["baker", "面包师", bp, yaw_to(bp, bp + face), "baker"]]
	if str(GameState.quest_stage("ch4_matilda")) in ["bakery", "lane"]:
		out.append(["milo", "米洛", MILO_AT, yaw_to(MILO_AT, Vector2(20.0, 22.0)), "milo"])
	return out


static func _floor_y(at: Vector2) -> float:
	var ja: Vector2 = CrownTown.JETTY[0]
	var jb: Vector2 = CrownTown.JETTY[1]
	if at.x > ja.x and at.x < jb.x and absf(at.y - ja.y) < CrownTown.JETTY_W * 0.5:
		return ground(ja) + 0.08
	return ground(at)


## 屋里的人：[编号, 名字, 位置, 朝向, 对话编号（"" = 只说一句）, 台词]
static func room_people(area: String) -> Array:
	match area:
		"matilda_inn":
			return [["matilda", "玛蒂尔达", Vector3(1.1, 0, -2.0), 180.0, "matilda", []],
				["inn_drinker1", "喝酒的脚夫", Vector3(2.2, 0, 1.4), 0.0, "", DRINKER_LINES],
				["inn_drinker2", "喝酒的脚夫", Vector3(-2.0, 0, 1.5), 10.0, "", DRINKER_LINES.slice(1) + DRINKER_LINES.slice(0, 1)]] + (
				[["milo_inn", "米洛", Vector3(0.6, 0, 1.6), -20.0, "", MILO_LINES]] if str(GameState.quest_stage("ch4_matilda")) == "back" or str(GameState.get_flag("ch4_matilda", "")) == "found" else [])
		"council_hall":
			return [["council_steward", "议事厅的差役", Vector3(5.6, 0, -0.9), 120.0, "council_steward", []]]
	return []


static func build_room(area: String, parent: Node3D) -> void:
	for it: Array in room_people(area):
		var n := Npc.make(str(it[1]), it[5], Color("5a5248"))
		n.name = "Npc_" + str(it[0])
		if str(it[4]) != "":
			n.dialogue_area = "crown"
			n.dialogue_id = str(it[4])
		n.position = it[2]
		n.rotation.y = deg_to_rad(float(it[3]))
		parent.add_child(n)
