class_name HarborPeople
extends RefCounted
## 双钥港的人（路线图 7.4；STORY.md 7.3「新人物」、7.5 第 1–3 步；7.2 挪过来的「城市人群」）。
## 有对话的（data/dialogue/harbor.json）：
##   钥楼大厅——科尔温·卡斯韦尔（柜台后面最里头那张账桌）、塞拉斯（柜台东头）、金库管事莫德（下金库的铁门前）、北境的使者（长凳上：
##   阿尔里克当家的是军士赫尔曼，伊薇特当家的是厄尔德家的罗薇娜）；
##   渡工行会会馆——港口头领科妮莉亚、洛蒙德家的管家塞缪尔、埃德里克（只有序章放走他的：他在行会记账）；
##   「咸潮」酒馆——塞弗林家的奥迪隆（火塘边喝酒）。
## 只说一句的：码头上的搬运工、等船的人、行会的船工，鱼市卖鱼的女人，钥楼街的账房先生、收债的打手，屋里的门房、喝酒的船工、看门的、牢里的约斯特。
## 说的都是这几天城里的事：冬至清账、灯塔没油、粮船搁浅、钥楼。远了不画（同平原，Plain.NPC_FAR / LABEL_FAR）。

const PORTER_LINES := ["粮船搁浅了，搬什么？搬盐。盐又不能吃。", "冬至那天冠城清账——清的是老爷们的账。我们的账，月底照清。", "钥楼的人昨天来码头上点过船，一条一条地点。"]
const FISHWIFE_LINES := ["鱼？今天没有鱼。灯塔不亮，船不敢夜里出去。", "老蒂博那盆炭，烧了三个月了。钥楼一滴油都不给。", "咸鱼，三个铜子两条。要不要？不要就让开，后面还有人。"]
const WAITER_LINES := ["卯时那班船，我等了两天了。说是冠城的老爷们先上。", "冠城？去冠城做什么——去看他们清账？（他往地上吐了口唾沫）"]
const BOATMAN_LINES := ["退潮的时候别下北潮沟。上个月有个外乡人陷进去，涨潮才捞上来。", "行会的船，每条都登在科妮莉亚的账上。少一根桨她都知道。"]
const CLERK_LINES := ["钥楼街上的每一扇门，都欠钥楼一点什么。", "（他夹着一摞账册匆匆走过）冬至、冬至……今年的冬至比哪年都长。"]
const COLLECTOR_LINES := ["收账的，别挡道。", "（他掂了掂腰上的短棍）有人说，老王欠的账不该我们来收。说这话的人，现在在债牢里。"]
const PORTER_IN_LINES := ["家主在后面。不坐的话，就站着等。", "长凳上那位坐了三天了。（他压低声音）别学他。"]
const HALL_CLERK_LINES := ["（他头也不抬，算筹拨得飞快）利滚利，三年，正好是一顶冠的价。", "（他在账上画了一道）又一家来求宽限的。"]
const GUILD_LINES := ["冬至前三日加一班船。加的那班，钥楼包了。", "（他把一卷缆绳扛上肩）粮船那九个人，有两个是我舅家的。"]
const DRINKER_LINES := ["（他举着杯子）敬冬至——敬钥楼——敬还不起的账。", "那个灰斗篷的砧山人，天天坐在火塘边。他请的酒，没人喝。"]
const KEEPER_LINES := ["酒还剩半桶。半桶喝完，酒馆就改成等船的地方。", "柜台上那行字？我爹刻的。他欠了钥楼一辈子。"]
const JAILER_LINES := ["来赎人的？先去钥楼把账算清楚。", "冬至以前不赎，就转卖钥楼。钥楼买人，比买船便宜。"]
const JOST_LINES := ["（他隔着铁栅抬起头）……船钱四十二枚。担保人是老王。老王死了，账就落到我头上了。", "（他缩在草铺上，没说话）"]


static func ground(p: Vector2) -> float:
	return Harbor.height_at(p.x, p.y)


## 朝着某一点的朝向（人的正面是 -Z，同镜头）
static func yaw_to(from: Vector2, to: Vector2) -> float:
	var d := to - from
	return rad_to_deg(atan2(-d.x, -d.y))


## 三家的使者都开过价：主线到 way（main 每段对话结束时调）
static func envoys_heard() -> bool:
	if GameState.quest_stage("ch4_main") == "envoys" and GameState.has_flag("ch4_envoy_lomond") and GameState.has_flag("ch4_envoy_severin") and GameState.has_flag("ch4_envoy_north"):
		GameState.set_stage("ch4_main", "way")
		return true
	return false


## 北境派谁来：伊薇特当家的是厄尔德家的罗薇娜，不然（阿尔里克当家、或者没有这一章以前的存档）是军士赫尔曼
static func north_envoy() -> Array:
	if str(GameState.get_flag("valen_heir", "")) == "ivette":
		return ["north_envoy", "罗薇娜", "rowena"]
	return ["north_envoy", "赫尔曼", "herman"]          # 节点不叫 Npc_herman：作息表（data/schedules.json）按这个编号把第一章黑鹭堡以外的赫尔曼删掉


## 城里只说一句的人：[编号, 名字, 位置, 朝向, 台词]
static func crowd() -> Array:
	var out := []
	var piers: Array = HarborTown.piers()
	for k in piers.size():
		var a: Vector2 = (piers[k] as Array)[0]
		var p := a + Vector2(3.0, 0.6 if k % 2 == 0 else -0.6)              # 站在栈桥面上（岸上那头往里 3 米：再往岸上是石岸的陡坡）
		if k % 2 == 0:
			out.append(["porter%d" % k, "码头的搬运工", p, yaw_to(p, p + Vector2(-1, 0.3)), PORTER_LINES.slice(k % 3) + PORTER_LINES.slice(0, k % 3)])
		else:
			out.append(["boatman%d" % k, "行会的船工", p, yaw_to(p, p + Vector2(1, 0)), BOATMAN_LINES.slice(k % 2) + BOATMAN_LINES.slice(0, k % 2)])
	for it: Array in [["waiter1", Vector2(13.6, -34.0), Vector2(30.0, -34.0)], ["waiter2", Vector2(12.6, 0.0), Vector2(0.0, -2.0)]]:
		out.append([it[0], "等船的人", it[1], yaw_to(it[1], it[2]), WAITER_LINES if it[0] == "waiter1" else WAITER_LINES.slice(1) + WAITER_LINES.slice(0, 1)])
	for k in 3:
		var p := Vector2(-52.0 + k * 9.0, 36.2)
		out.append(["fishwife%d" % k, "卖鱼的女人", p, yaw_to(p, p + Vector2(0.2, -1.0)), FISHWIFE_LINES.slice(k) + FISHWIFE_LINES.slice(0, k)])
	for it: Array in [["clerk1", Vector2(-58.0, -61.6), Vector2(-40.0, -62.0)], ["clerk2", Vector2(-12.0, -59.2), Vector2(-30.0, -62.0)]]:
		out.append([it[0], "账房先生", it[1], yaw_to(it[1], it[2]), CLERK_LINES if it[0] == "clerk1" else CLERK_LINES.slice(1) + CLERK_LINES.slice(0, 1)])
	for it: Array in [["collector1", Vector2(-27.6, -61.2), Vector2(-34.0, -62.0)], ["collector2", Vector2(-40.4, -61.4), Vector2(-34.0, -62.0)]]:
		out.append([it[0], "收债的打手", it[1], yaw_to(it[1], it[2]), COLLECTOR_LINES if it[0] == "collector1" else COLLECTOR_LINES.slice(1) + COLLECTOR_LINES.slice(0, 1)])
	return out


## 脚下的高度：栈桥上的是桥面，别处是地面
static func _floor_y(at: Vector2) -> float:
	for p: Array in HarborTown.piers():
		var a: Vector2 = p[0]
		var b: Vector2 = p[1]
		if at.x > a.x and at.x < b.x and absf(at.y - a.y) < HarborTown.PIER_W * 0.5:
			return HarborTown.pier_y(p)
	return ground(at)


## 序章勒索过塞拉斯的：见过科尔温以后，塞拉斯的三个人在码头街上堵你（7.5；付钱、说走、或者打——组 encounter:silas_men）
static func silas_men_due() -> bool:
	return str(GameState.get_flag("prologue_edric", "")) == "extort" and GameState.quest_stage("ch4_main") in ["envoys", "way"] and not GameState.has_flag("ch4_thugs")


const SILAS_MEN := [[Vector2(13.4, -44.0), 0.0], [Vector2(14.8, -45.6), -20.0], [Vector2(12.0, -45.8), 20.0]]


## 双钥港（室外）：城里的人（同步放：块没搭好时也说得上话；远了不画）
static func build(parent: Node3D) -> void:
	if silas_men_due():
		for k in SILAS_MEN.size():
			var at: Vector2 = (SILAS_MEN[k] as Array)[0]
			var t := Npc.make("收债的打手", [] if k == 0 else ["（他掂着短棍，看着领头的）"], Color("2a2420"))
			t.name = "Npc_silas_man%d" % k
			if k == 0:
				t.dialogue_area = "harbor"
				t.dialogue_id = "silas_man"
			t.position = Vector3(at.x, ground(at), at.y)
			t.rotation.y = deg_to_rad(float((SILAS_MEN[k] as Array)[1]))
			t.add_to_group(Encounter.group_name("silas_men"))
			t.set_meta("enemy_kind", "clubber")
			t.set_meta("enemy_id", "silas_man%d" % k)
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


## 屋里的人：[编号, 名字, 位置, 朝向, 对话编号（"" = 只说一句）, 台词]
static func room_people(area: String) -> Array:
	match area:
		"key_hall":
			var ne := north_envoy()
			return [["colwin", "科尔温·卡斯韦尔", Vector3(3.3, 0, -2.55), 180.0, "colwin", []],
				["silas", "塞拉斯", Vector3(6.4, 0, 0.1), 105.0, "silas", []],
				["maud", "金库管事莫德", Vector3(-4.7, 0, -2.7), 150.0, "maud", []],
				[ne[0], ne[1], Vector3(-2.0, 0, 2.8), 10.0, ne[2], []],
				["hall_clerk1", "账房先生", Vector3(-1.7, 0, -2.55), 180.0, "", HALL_CLERK_LINES],
				["hall_clerk2", "账房先生", Vector3(0.8, 0, -2.55), 180.0, "", HALL_CLERK_LINES.slice(1) + HALL_CLERK_LINES.slice(0, 1)],
				["hall_porter", "钥楼的门房", Vector3(2.4, 0, 3.0), -120.0, "", PORTER_IN_LINES]]
		"guild_hall":
			var out := [["cornelia", "科妮莉亚", Vector3(-1.0, 0, -1.7), 180.0, "cornelia", []],
				["samuel", "管家塞缪尔", Vector3(4.6, 0, 1.0), -95.0, "samuel", []],
				["guild_boatman1", "行会的船工", Vector3(4.0, 0, -1.9), 40.0, "", GUILD_LINES],
				["guild_boatman2", "行会的船工", Vector3(-4.6, 0, 1.6), -60.0, "", GUILD_LINES.slice(1) + GUILD_LINES.slice(0, 1)]]
			if str(GameState.get_flag("prologue_edric", "")) == "release":
				out.append(["edric", "埃德里克", Vector3(1.6, 0, 0.95), 0.0, "edric", []])
			return out
		"dock_tavern":
			return [["odilon", "奥迪隆", Vector3(2.4, 0, -0.5), 148.0, "odilon", []],
				["drinker1", "喝酒的船工", Vector3(-2.4, 0, 1.55), 0.0, "", DRINKER_LINES],
				["drinker2", "喝酒的船工", Vector3(0.4, 0, 0.05), 180.0, "", DRINKER_LINES.slice(1) + DRINKER_LINES.slice(0, 1)],
				["keeper", "酒馆的老板娘", Vector3(-3.7, 0, -1.6), -120.0, "", KEEPER_LINES]]
		"key_vault":
			if not HarborRooms.vault_night() or GameState.has_item("iron_crown"):
				return []
			var guard_lines := ["（他靠着石阶睡着了，头一点一点）"] if GameState.has_flag("ch4_vault_sneaky") else ["（他按着剑柄，盯着水门那边）"]
			return [["maud_vault", "金库管事莫德", Vector3(1.5, 0, -1.6), 160.0, "maud_vault", []],
				["vault_guard0", "卡斯韦尔家的雇佣兵", Vector3(-3.4, 0, -1.9), 160.0, "", guard_lines],
				["vault_guard1", "卡斯韦尔家的雇佣兵", Vector3(-2.3, 0, -2.0), 190.0, "", guard_lines],
				["vault_guard2", "卡斯韦尔家的雇佣兵", Vector3(-4.4, 0, 2.6), 120.0, "", guard_lines]]
		"debt_prison":
			return [["jailer", "看门的", Vector3(3.6, 0, 2.45), 0.0, "", JAILER_LINES],
				["jost", "约斯特", Vector3(0.6, 0, -2.6), 180.0, "", JOST_LINES]]
	return []


static func build_room(area: String, parent: Node3D) -> void:
	for it: Array in room_people(area):
		var n := Npc.make(str(it[1]), it[5], Color("5a5248"))
		n.name = "Npc_" + str(it[0])
		if str(it[4]) != "":
			n.dialogue_area = "harbor"
			n.dialogue_id = str(it[4])
		n.position = it[2]
		n.rotation.y = deg_to_rad(float(it[3]))
		if str(it[0]).begins_with("vault_guard"):                       # 金库之夜：莫德醒着、你拔了剑，这三个人就动手（组 encounter:vault_guards）
			n.add_to_group(Encounter.group_name("vault_guards"))
			n.set_meta("enemy_kind", "swordsman")
			n.set_meta("enemy_id", str(it[0]))
		parent.add_child(n)
