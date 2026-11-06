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
## 6.7c：
##   水渠绕后——第二拨来以前 HINT_BEFORE 秒提示一句；小队用「去那儿」（Battle 命令 goto，按 4）顺着西边的水渠绕到北墙外的 FLANK 附近，
##     第二拨到了以后 FLANK_WINDOW 秒以内小队还有 FLANK_MIN 个人在那儿：第二拨全体士气 −FLANK_HIT（从背后打进去），记 ch3_flanked；
##   远处的背景大军（STORY 1.1、D11）——北边麦茬地上三大块塞弗林家的兵（FAR_BLOCKS，一共 240 个），每两个人一支火把、几面红旗，开打以后慢慢往前压一段；
##     只是背景：不进士兵 AI、一个多实例节点画人、一个画火把（不受雾挡，同堤道夜战的火把线）、一个网格画旗。
##   「佃农挡路时冲过去还是让开」没做（要给佃农加「不打你」的状态和判断，挪到 6.8）。

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

const FLANK := Vector2(19.0, -45.0)                     # 北墙缺口外西北角：顺着水渠从院子西边绕出来的地方
const FLANK_R := 8.0
const FLANK_MIN := 3
const FLANK_WINDOW := 25.0
const FLANK_HIT := 25.0
const HINT_BEFORE := 15.0
const FAR_BLOCKS := [[Vector2(42.0, -108.0), 0.0], [Vector2(72.0, -112.0), -0.3], [Vector2(100.0, -120.0), -0.5]]   # [中心, 朝向（弧度，0 = 朝南对着磨坊）]
const FAR_ROWS := 8
const FAR_COLS := 10
const FAR_ADVANCE := 14.0                               # 开打以后慢慢往前压多远（米）
const FAR_ADVANCE_T := 90.0

var battle: Battle
var ready_t := 0.0
var hinted := false
var flank_done := false
var far_men: MultiMeshInstance3D
var far_fire: MultiMeshInstance3D
var far_base: Array = []                                 # 每个人原来的位置
var far_t := 0.0
var wave2: Array = []                                    # 奥迪隆和第二拨（水渠绕后打的是他们）


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
	mb.wave2 = second
	world.add_child(mb)
	mb.build_far_host()
	print("IC_MILL setup side=%s def=%d atk=%d waves=%d guards_left=%s" % [side(), b.side_total(DEF), b.side_total(ATK), b.waves.size(), GameState.has_flag("ch3_guards_left")])
	return b


func _process(delta: float) -> void:
	if battle and not battle.started:
		ready_t += delta
	if battle == null or not battle.started or battle.finished:
		return
	_far_tick(delta)
	if not hinted and battle.elapsed >= WAVE2_AT - HINT_BEFORE:
		hinted = true
		battle.wave_note.emit("◆ 北边缺口外的麦茬地里火把越聚越多。" + ("顺着西边的水渠能绕到他们背后——按 4 让小队去（准星指着那儿）。" if not raiding() else "第二拨要从缺口进去了。"))
	if not flank_done and not raiding() and battle.elapsed >= WAVE2_AT and battle.elapsed <= WAVE2_AT + FLANK_WINDOW \
			and not wave2.is_empty() and is_instance_valid(wave2[0]) and (wave2[0] as Node).is_inside_tree() and flank_ready():
		flank_done = true
		GameState.set_flag("ch3_flanked")
		for s in wave2:
			if is_instance_valid(s) and (s as Node).is_inside_tree():
				s.morale -= FLANK_HIT
		battle.wave_note.emit("◆ 你的小队从水渠那边绕到了缺口外头，打在第二拨背后！他们乱了。")


## 小队有 FLANK_MIN 个人站在缺口外西北角（水渠绕出来的地方）吗
func flank_ready() -> bool:
	var n := 0
	for s in battle.squad:
		if is_instance_valid(s) and s.fighting() and Vector2(s.global_position.x, s.global_position.z).distance_to(FLANK) <= FLANK_R:
			n += 1
	return n >= FLANK_MIN


# ---------------- 远处的背景大军（6.7c）----------------

## 一个远处的兵：身子、头、肩上一根长枪（一个网格，颜色写进顶点色）；三大块 240 个一个多实例节点画
static func _far_man_mesh() -> Mesh:
	var kit := MeshKit.new()
	kit.box("a", Vector3(0, 0.75, 0), Vector3(0.5, 1.1, 0.32), Basis.IDENTITY, 0.9, 0.6)
	kit.box("a", Vector3(0, 1.45, 0), Vector3(0.26, 0.28, 0.26), Basis.IDENTITY, 1.0, 1.0)
	kit.box("a", Vector3(0.18, 0.15, 0), Vector3(0.14, 0.3, 0.14))
	kit.box("a", Vector3(-0.18, 0.15, 0), Vector3(0.14, 0.3, 0.14))
	kit.cylinder("a", Vector3(0.3, 0.2, 0), Vector3(0.36, 2.8, 0), 0.025, 0.02, 4)
	var m := MeshKit.flat_mat(0.9)
	m.albedo_color = Color(0.16, 0.15, 0.16)
	var mi := kit.build({"a": m})
	return mi.mesh


static func _far_fire_mesh() -> Mesh:
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.4)                             # 远处几个像素：做大一点才看得出一串火（截图）
	var m := Look.halo(Color(1.0, 0.6, 0.25), 0.95).duplicate() as StandardMaterial3D     # 软的一团光（加法混合、不受雾挡）；纯色方片远看是一排橙色小方块（截图）
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_DISABLED    # 光晕原来 30 米外淡没；这串火就是给远处看的
	q.material = m
	return q


func build_far_host() -> void:
	far_men = MultiMeshInstance3D.new()
	far_men.name = "FarHost"
	far_men.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _far_man_mesh()
	mm.instance_count = FAR_BLOCKS.size() * FAR_ROWS * FAR_COLS
	far_men.multimesh = mm
	far_fire = MultiMeshInstance3D.new()
	far_fire.name = "FarTorches"
	far_fire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var fm := MultiMesh.new()
	fm.transform_format = MultiMesh.TRANSFORM_3D
	fm.mesh = _far_fire_mesh()
	fm.instance_count = mm.instance_count / 2
	far_fire.multimesh = fm
	var rng := RandomNumberGenerator.new()
	rng.seed = 6703
	far_base.clear()
	var flags := MeshKit.new()
	var red := MeshKit.flat_mat(0.9)
	red.albedo_color = Color("6a1a18")
	var pole := MeshKit.flat_mat(0.9)
	pole.albedo_color = Color("2a2420")
	var i := 0
	for blk: Array in FAR_BLOCKS:
		var c: Vector2 = blk[0]
		var yaw := float(blk[1])
		var b := Basis(Vector3.UP, yaw)
		for r in FAR_ROWS:
			for k in FAR_COLS:
				var local := Vector3((k - (FAR_COLS - 1) * 0.5) * 1.4 + rng.randf_range(-0.3, 0.3), 0, (r - FAR_ROWS * 0.5) * 1.6 + rng.randf_range(-0.3, 0.3))
				var w := Vector3(c.x, 0, c.y) + b * local
				w.y = PlainLayout.height(w.x, w.z)
				far_base.append([w, yaw + rng.randf_range(-0.15, 0.15), rng.randf() * TAU])
				mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, yaw + PI), w))
				i += 1
		for f in 3:                                                         # 每块三面红旗
			var fp := Vector3(c.x, 0, c.y) + b * Vector3((f - 1) * 5.0, 0, -FAR_ROWS * 0.8 - 1.0)
			fp.y = PlainLayout.height(fp.x, fp.z)
			flags.cylinder("p", fp, fp + Vector3(0, 5.0, 0), 0.05, 0.04, 4)
			flags.box("r", fp + Vector3(0.45, 4.3, 0), Vector3(0.9, 1.2, 0.03), b, 1.0, 0.8)
	var fl := flags.build({"p": pole, "r": red})
	fl.name = "FarBanners"
	fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(far_men)
	add_child(far_fire)
	add_child(fl)
	_far_place(0.0)


## 摆到第 t 秒的位置：往前（朝南、朝磨坊）压 FAR_ADVANCE 米，人轻轻晃，火把跟着人
func _far_place(t: float) -> void:
	var adv := FAR_ADVANCE * clampf(t / FAR_ADVANCE_T, 0.0, 1.0)
	var mm := far_men.multimesh
	var fm := far_fire.multimesh
	for i in far_base.size():
		var e: Array = far_base[i]
		var w: Vector3 = e[0]
		var yaw := float(e[1])
		var fwd := Vector3(-sin(yaw + PI), 0, -cos(yaw + PI))
		var p := w + fwd * adv
		p.y = PlainLayout.height(p.x, p.z) + sin(t * 2.0 + float(e[2])) * 0.04
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, yaw + PI), p))
		if i % 2 == 0 and i / 2 < fm.instance_count:
			fm.set_instance_transform(i / 2, Transform3D(Basis.IDENTITY, p + Vector3(0.35, 2.6 + sin(t * 7.0 + float(e[2])) * 0.06, 0)))


func _far_tick(delta: float) -> void:
	if far_men == null:
		return
	far_t += delta
	if int(far_t * 5.0) != int((far_t - delta) * 5.0):      # 一秒挪五次就够了（几百个人，远处看不出跳）
		_far_place(far_t)


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
