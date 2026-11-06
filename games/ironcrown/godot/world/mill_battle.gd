class_name MillBattle
extends Node3D
## 磨坊之战（路线图 6.7b；STORY.md 6.6「磨坊之战」；用 B.1–B.5 的军阵）：抉择（6.6，ch3_side）以后，天黑在金穗平原的水磨坊打。
## 三种站法：
##   守磨坊（lomond）：你 + 跟着你的 6 个护院；护院头目带 5 个人守东门（第一拨从这儿进）、2 个人守北墙缺口（第二拨一分钟以后才到；一共 14 个）。
##   开仓以后守（tenants）：同上，再加 10 个拿棍棒的佃农守着粮仓（老贝恩带头）；没说动护院头目、护院撤走了的（ch3_guards_left）：
##     只有佃农——6 个跟着你，缺口、东门各 2 个，老贝恩和 1 个人守粮仓（12 个）。
##   攻方：塞弗林家的征粮兵。第一波 20 人（多是矿上拉来的民兵）在东门外的麦茬地上列好，开打就往东门压；第二波 19 人 + 队长奥迪隆 WAVE2_AT 秒后从北墙缺口进来。
##   守住（held）：攻方倒下 / 溃逃过半（B.3）；打倒奥迪隆全队士气大掉（ch3_odilon_down，6.8 他身上那封信）。
##   失守（lost）：你这边溃逃过半，或者攻方有 BREACH_LIMIT 个人摸到过粮仓门口（据点规则，granary_doors / DOOR_R）。
##   站塞弗林家（severin）：你 + 第一波 20 人（6 个跟着你）在东门外；守方：护院头目和 11 个护院（缺口、东门、粮仓），
##     WAVE_TEN_AT 秒后老贝恩带 8 个佃农从南门进来护自己的口粮。抢到了（seized）：守方溃逃过半，或者你这边 BREACH_LIMIT 个人摸到过粮仓门口；
##     打退了（repelled）：你这边溃逃过半。
## 开打：天黑以后到了这儿，站好几秒（main._mill_tick，先自动存档）。你自己倒下：读档。结束写 ch3_mill（main._on_battle_ended → finish）。
## 磨坊院子有墙、门、缺口：开打时只烘焙磨坊那一片的导航（NAV_BOUNDS，同鹭沼营地 4.7c），兵绕着墙走。
## 6.7c 再加：水渠绕后（「去那儿」命令）、远处几百人的背景大军、佃农挡路时冲过去还是让开。

const DEF := "lomond"
const ATK := "severin"
const DEF_COAT := "2e4a32"
const DEF_BAND := "c8a440"
const TEN_COAT := "5a5046"
const ATK_COAT := "4a4a4e"
const ATK_BAND := "8e1f1c"
const GRANARY_ZONE := Rect2(29.0, -28.0, 13.5, 19.0)     # 三座粮仓那片院子（守粮仓的人站在这儿）
const DOOR_R := 3.0                                      # 粮仓门口这么近：攻方 BREACH_LIMIT 个人摸到过仓门就算抢到了（整片院子当据点时，第一波一路打一路就「冲进去了」，6.7b 实测十几秒失守）
const BREACH_LIMIT := 6
const NAV_BOUNDS := AABB(Vector3(4.0, -3.0, -58.0), Vector3(64.0, 12.0, 62.0))
const START_AFTER := 4.0                                 # 到了以后几秒开打
const WAVE1B_AT := 15.0
const WAVE2_AT := 60.0
const WAVE_TEN_AT := 30.0
const ROW_GAP := 1.5
const COLS := 4
## 守方的点：[位置, 朝哪边]
const BREACH_POST := [Vector2(27.5, -35.0), Vector2(0, -1)]
const EAST_POST := [Vector2(41.0, -33.6), Vector2(1, 0)]
const GRANARY_POST := [Vector2(35.0, -17.0), Vector2(1, 0)]
const SOUTH_POST := [Vector2(16.5, -4.5), Vector2(0, 1)]
const WAVE1_AT := Vector2(60.0, -30.0)                  # 第一波在东门外的麦茬地上
const WAVE2_FROM := Vector2(27.5, -50.0)                 # 第二波从北边过来，进缺口
const TEN_FROM := Vector2(14.0, 4.0)                     # 站塞弗林家时：老贝恩的佃农从南门外的路上来
const WAVE1 := ["levy", "soldier", "levy", "spear", "levy", "levy", "soldier", "levy", "shield", "levy",
	"levy", "soldier", "levy", "spear", "levy", "levy", "soldier", "levy", "levy", "archer"]      # 第一拨多是从砧山矿上拉来的民兵（征粮兵）；老兵在第二拨
const WAVE2 := ["shield", "spear", "soldier", "shield", "spear", "soldier", "soldier", "spear", "shield", "soldier",
	"spear", "soldier", "shield", "soldier", "spear", "soldier", "archer", "archer", "soldier"]

var battle: Battle
var ready_t := 0.0


## 现在该摆这场仗吗：抉择定了（主线到 to_mill_*）、夜里、还没打过
static func due() -> bool:
	return pending() and GameState.daypart == "night"


static func pending() -> bool:
	return GameState.chapter == 3 and side() != "" and GameState.quest_stage("ch3_main") in ["to_mill_lomond", "to_mill_tenants", "to_mill_severin"] \
		and not GameState.has_flag("ch3_mill")


static func side() -> String:
	var s := str(GameState.get_flag("ch3_side", ""))
	return s if s in ["lomond", "tenants", "severin"] else ""


static func raiding() -> bool:
	return side() == "severin"


## 天黑以前走到哪儿就入夜开打：守磨坊的到了磨坊院子（外扩 6 米），跟塞弗林家的到了营地口
static func at_muster(p: Vector2) -> bool:
	if raiding():
		var c: Vector2 = (PlainLayout.SPAWN_XZ.camp as Array)[0]
		return p.distance_to(c) < 14.0
	return PlainMill.RECT.grow(6.0).has_point(p)


## 入夜以后站哪儿：[出生点, 到了以后说的话]
static func night_arrival() -> Array:
	match side():
		"severin":
			return ["mill_raid", "天黑透了。奥迪隆的第一拨二十个人跟着你下了坡，伏在磨坊东门外的麦茬地里。院墙上的火把一个一个亮起来。"]
		"tenants":
			if GameState.has_flag("ch3_guards_left"):
				return ["mill_night", "天黑透了。护院都撤回了庄园，磨坊院子里只有麦渡的人——拿着棍棒、撬棍，围着那三座仓。东边麦茬地里亮起一串火把。"]
			return ["mill_night", "天黑透了。护院和佃农挤在一个院子里，谁也不看谁。东边麦茬地里亮起一串火把——塞弗林家的兵来了。"]
	return ["mill_night", "天黑透了。护院头目把火把分下去，北墙缺口放了四个人。东边麦茬地里亮起一串火把——塞弗林家的兵来了。"]


static func p3(p: Vector2) -> Vector3:
	return Vector3(p.x, PlainLayout.height(p.x, p.y) + 0.05, p.y)


static func _yaw(dir: Vector2) -> float:
	return atan2(-dir.x, -dir.y)


static func _soldier(kind: String, id: String, side_id: String, at: Vector2, face: Vector2, coat: String, band: String, label: String) -> Soldier:
	var s := Soldier.create(kind, id, side_id, Color(coat), Color(band))
	s.position = p3(at)
	s.rotation.y = _yaw(face)
	s.display_override = label
	return s


## 一队人排成几排：从 at 往 back 方向一排排往后
static func _block(kinds: Array, tag: String, side_id: String, at: Vector2, face: Vector2, coat: String, band: String, label_of: Callable) -> Array:
	var out := []
	var side_v := Vector2(-face.y, face.x)
	for i in kinds.size():
		var row := i / COLS
		var col := i % COLS
		var p := at - face * (row * ROW_GAP) + side_v * ((col - (COLS - 1) * 0.5) * 1.3)
		out.append(_soldier(kinds[i], "%s_%d" % [tag, i], side_id, p, face, coat, band, label_of.call(kinds[i], i)))
	return out


static func _guard(list: Array, post: Array, r: float) -> void:
	var c: Vector2 = post[0]
	var f: Vector2 = post[1]
	for i in list.size():
		var s: Soldier = list[i]
		var off := Vector2(-f.y, f.x) * ((i % 4 - 1.5) * 1.2) - f * (i / 4) * 1.2
		s.position = p3(c + off)
		s.rotation.y = _yaw(f)
		s.guard_post = s.position
		s.guard_r = r
		s.guard_face = Vector3(f.x, 0, f.y)


## 三座粮仓的门口（门外 1 米）
static func granary_doors() -> Array:
	var out := []
	for i in PlainMill.GRANARIES.size():
		var p := PlainMill.granary_pos(i)
		var yaw := deg_to_rad(float((PlainMill.GRANARIES[i] as Array)[1]))
		out.append(Vector2(p.x, p.z) + Vector2(sin(yaw), cos(yaw)) * 1.0)
	return out


static func at_granary_door(p: Vector3) -> bool:
	var q := Vector2(p.x, p.z)
	for d: Vector2 in granary_doors():
		if q.distance_to(d) < DOOR_R:
			return true
	return false


static func kind_name(k: String) -> String:
	return str(Enemy.types().get(k, {}).get("name", k))


## 摆好这场仗（main 在区域搭好以后调）；不该打返回 null
static func setup(world: Node3D) -> Battle:
	if not due():
		return null
	for n in ["Npc_captain", "Npc_mill_guard1", "Npc_mill_guard2"]:   # 白天站在磨坊的护院：这会儿都在军阵里
		var npc := world.find_child(n, true, false)
		if npc:
			npc.get_parent().remove_child(npc)              # 马上拿掉：同一帧还要烘焙导航，站着的 NPC 是静态碰撞体
			npc.queue_free()
	var director := CombatDirector.new()
	director.name = "CombatDirector"
	world.add_child(director)
	var b := Battle.new()
	b.name = "Battle"
	var raid := raiding()
	b.player_side = ATK if raid else DEF
	b.add_side(DEF, "洛蒙德家" if side() != "tenants" else "守磨坊的人")
	b.add_side(ATK, "塞弗林家的兵")
	b.breach_side = ATK
	b.breach_limit = BREACH_LIMIT
	b.breach_test = func(s: Soldier) -> bool: return at_granary_door(s.global_position)
	world.add_child(b)
	var guard_label := func(_k: String, _i: int) -> String: return "洛蒙德家 · 护院"
	var ten_label := func(_k: String, _i: int) -> String: return "麦渡的佃农"
	var sev_label := func(k: String, _i: int) -> String: return "塞弗林家 · %s" % kind_name(k)
	var west := Vector2(-1, 0)
	if raid:
		var van := _block(WAVE1, "raid", ATK, WAVE1_AT + Vector2(-2.0, 0), west, ATK_COAT, ATK_BAND, sev_label)
		for i in van.size():
			var s: Soldier = van[i]
			if i < 6:
				s.display_override = "塞弗林家 · 跟着你的兵"
				b.add_to_squad(s)
			b.enlist(s, world)
		b.order("follow")
		var cap := _soldier("captain", "mill_captain", DEF, (BREACH_POST[0] as Vector2), (BREACH_POST[1] as Vector2), DEF_COAT, DEF_BAND, "护院头目")
		var g1 := [cap] + _block(["shield", "spear", "soldier"], "g_breach", DEF, Vector2.ZERO, Vector2.UP, DEF_COAT, DEF_BAND, guard_label)
		var g2 := _block(["shield", "spear", "soldier", "spear"], "g_east", DEF, Vector2.ZERO, Vector2.UP, DEF_COAT, DEF_BAND, guard_label)
		var g3 := _block(["soldier", "shield", "spear", "soldier"], "g_gran", DEF, Vector2.ZERO, Vector2.UP, DEF_COAT, DEF_BAND, guard_label)
		_guard(g1, BREACH_POST, 7.0)
		_guard(g2, EAST_POST, 7.0)
		_guard(g3, GRANARY_POST, 9.0)
		for s: Soldier in g1 + g2 + g3:
			b.enlist(s, world)
		var ten := _block(["captain", "levy", "levy", "levy", "levy", "levy", "levy", "levy"], "tenant", DEF, TEN_FROM, Vector2(0, -1), TEN_COAT, DEF_BAND, ten_label)
		(ten[0] as Soldier).display_override = "老贝恩"
		b.add_wave(DEF, ten, world, WAVE_TEN_AT, "◆ 南门外一阵喊——老贝恩带着麦渡的人拿着棍棒冲进来了，护着自己的口粮！")
	else:
		var left := side() == "tenants" and GameState.has_flag("ch3_guards_left")
		var with_tenants := side() == "tenants"
		var squad_kinds := ["levy", "levy", "levy", "levy", "levy", "levy"] if left else ["shield", "spear", "soldier", "shield", "spear", "soldier"]
		var spawn: Array = PlainLayout.SPAWN_XZ.mill_night
		var sq := _block(squad_kinds, "squad", DEF, (spawn[0] as Vector2) + Vector2(-1.5, 0), Vector2(1, 0), TEN_COAT if left else DEF_COAT, DEF_BAND, ten_label if left else guard_label)
		for s: Soldier in sq:
			b.add_to_squad(s)
			b.enlist(s, world)
		b.order("follow")
		var cap := _soldier("captain" if not left else "levy", "mill_captain", DEF, Vector2.ZERO, Vector2.UP, TEN_COAT if left else DEF_COAT, DEF_BAND, "麦渡的佃农" if left else "护院头目")
		var g1 := _block(["levy", "levy"] if left else ["shield", "spear"], "g_breach", DEF, Vector2.ZERO, Vector2.UP, TEN_COAT if left else DEF_COAT, DEF_BAND, ten_label if left else guard_label)    # 缺口：第二拨一分钟以后才来，先放两个
		var g2 := [cap] + _block(["levy"] if left else ["shield", "spear", "soldier", "shield", "spear"], "g_east", DEF, Vector2.ZERO, Vector2.UP, TEN_COAT if left else DEF_COAT, DEF_BAND, ten_label if left else guard_label)    # 东门：第一拨从这儿进
		_guard(g1, BREACH_POST, 7.0)
		_guard(g2, EAST_POST, 7.0)
		for s: Soldier in g1 + g2:
			b.enlist(s, world)
		if with_tenants:
			var tk := ["captain", "levy"] if left else ["captain", "levy", "levy", "levy", "levy", "levy", "levy", "levy", "levy", "levy"]
			var ten := _block(tk, "tenant", DEF, Vector2.ZERO, Vector2.UP, TEN_COAT, DEF_BAND, ten_label)
			(ten[0] as Soldier).display_override = "老贝恩"
			_guard(ten, GRANARY_POST, 9.0)
			for s: Soldier in ten:
				b.enlist(s, world)
		var van := _block(WAVE1, "van", ATK, WAVE1_AT, west, ATK_COAT, ATK_BAND, sev_label)
		for i in van.size():                            # 第一拨分两股：前 10 个先压东门，后 10 个 WAVE1B_AT 秒后跟上（一下子 20 个挤进东门，几个人守门几秒就垮，6.7b 实测）
			if i < 10:
				b.enlist(van[i], world)
		b.add_wave(ATK, van.slice(10), world, WAVE1B_AT, "◆ 东边麦茬地里又上来一股——第一拨的后半截！")
	var second := _block(WAVE2, "wave2", ATK, WAVE2_FROM, Vector2(0, 1), ATK_COAT, ATK_BAND, sev_label)
	var odilon := _soldier("captain", "odilon", ATK, WAVE2_FROM + Vector2(0, -2.5), Vector2(0, 1), ATK_COAT, ATK_BAND, "奥迪隆")
	second.push_front(odilon)
	b.add_wave(ATK, second, world, WAVE2_AT, "◆ 北墙那道缺口外头一片火把——奥迪隆带着第二拨上来了！")
	b.captain_down.connect(func(s: String):
		if s == ATK:
			GameState.set_flag("ch3_odilon_down"))
	var mb := MillBattle.new()
	mb.name = "MillBattle"
	mb.battle = b
	world.add_child(mb)
	print("IC_MILL setup side=%s def=%d atk=%d waves=%d guards_left=%s" % [side(), b.side_total(DEF), b.side_total(ATK), b.waves.size(), GameState.has_flag("ch3_guards_left")])
	return b


func _process(delta: float) -> void:
	if battle and not battle.started:
		ready_t += delta


## 到了几秒了，可以开打（main._mill_tick）
func ready_to_start() -> bool:
	return battle != null and not battle.started and ready_t >= START_AFTER


## 打完了：写 ch3_mill、声望、推进主线；返回给玩家看的一句话
static func finish(winner: String) -> String:
	var raid := raiding()
	var res := ("seized" if winner == ATK else "repelled") if raid else ("held" if winner == DEF else "lost")
	GameState.set_flag("ch3_mill", res)
	match res:
		"held":
			GameState.change_rep("lomond", 10)
			GameState.change_rep("severin", -10)
		"lost":
			GameState.change_rep("lomond", -10)
			GameState.change_rep("severin", 5)
		"seized":
			GameState.change_rep("lomond", -25)
			GameState.change_rep("severin", 10)
		"repelled":
			GameState.change_rep("severin", -5)
	if GameState.quest_active("ch3_main"):
		GameState.set_stage("ch3_main", "after_mill")
	match res:
		"held":
			return "✓ 守住了！塞弗林家的兵退回了麦茬地，三座仓的门都还锁着。" + ("奥迪隆倒在缺口里。" if GameState.has_flag("ch3_odilon_down") else "")
		"lost":
			return "× 磨坊失守了。粮仓的门被砸开，一袋一袋麦子扛上了车，往砧山那边去了……"
		"seized":
			return "✓ 抢到了！护院散了，粮仓的门砸开了。塞弗林家的兵一袋一袋往车上扛。佃农远远站着，看着你。"
	return "× 打不进去。塞弗林家的兵退回了麦茬地，奥迪隆骂了一声，叫人把伤兵抬上车。"


## 打完以后天亮：[出生点, 到了以后说的话]
static func dawn_arrival(res: String) -> Array:
	match res:
		"held":
			return ["mill", "天亮了。雪地上横七竖八躺着人，北墙缺口里堆着塞弗林家的盾。护院头目坐在仓门口，一夜没合眼。"]
		"lost":
			return ["mill", "天亮了。三座仓空了一座，门板倒在雪里，车辙一路往东北去了。麦渡那边没有冒烟。"]
		"seized":
			return ["mill", "天亮了。最后一辆粮车出了东门。奥迪隆拍拍你的肩：「砧山记着你。」坡上的庄园，窗户都黑着。"]
	return ["mill", "天亮了。磨坊院墙外的麦茬地被踩成了泥。护院在墙头上数着倒下的人，指着你说了句什么。"]
