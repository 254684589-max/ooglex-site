class_name ConvoyAmbush
extends Node3D
## 第二夜 · 劫粮（路线图 5.7a；STORY.md 5.6 表「劫粮」；用 B.1–B.5 的军阵）。
## 主线「设伏」（beacon_grain = rob）以后天黑透：南边的山口被雪封了，洛蒙德家的粮车只能走盘山路翻山脊绕下去——
## 在伏击段（HighlandLayout.AMBUSH_LEG：上坡一侧是岩坎）上，五辆车停成一列（车头朝山脊）。
## 你这边（烽誓团，灰布带）：马蒂亚斯给的十个人（小队，跟着你；卡斯滕留下来的再多一个）。
## 对面（洛蒙德家，赭红布带）：押车队长、14 个押车兵（剑盾、长枪、剑兵、两个弓手）；安塞尔姆在车尾（按征来的兵算：拿着短矛、打得最弱）；车夫一开打就扔下鞭子跑了。
## 伏击位置（ch2_ambush，5.6 定的）：
##   head 先断车头——车头前那棵枯松已经锯倒、横在路上；你们在树后，押车兵从车队后头压上来；
##   tail 先断车尾——你们从车尾后面摸上去，安塞尔姆就在跟前；车头的押车兵得回头救。
## 开打：走到伏击点 START_R 以内（先自动存档）。TIDE_AT 秒后第二次潮水从北边山脊上横穿山路（第十八烽点着了的少一些）：
## 挡路的人（两边都算）被推倒、踩过（Soldier.trampled：失衡、掉血不致死、士气掉）——举着火把、插火把能让它们从你这边拐开，往押车兵那边去。
## 粮车：插着的火把离车太近、或者你举着火把被推倒在车边，车上的麻袋会着（burned）。
## 结果（ch2_convoy）：赢了（对面倒下 / 溃逃）车没烧 = taken；赢了但烧了车 = burned；你这边溃逃 = repelled。你自己倒下：读档（开打前的自动存档）。

const OURS := "beacon_oath"
const FOE := "lomond"
const OUR_COAT := "4a4842"
const OUR_BAND := "9a9a9a"
const FOE_COAT := "5a3a2e"
const FOE_BAND := "b0522e"
const CART_T := [62.0, 57.0, 52.0, 47.0, 42.0]          # 五辆车沿伏击段的米数（第一辆是车头）
const TREE_T := 68.0                                    # 锯倒的枯松
const POST_T := {"head": 72.0, "tail": 32.0}            # 伏击点：车头前（树后）/ 车尾后
const SPAWN_T := {"head": 84.0, "tail": 20.0}           # 天黑透以后你站在这里（走到伏击点开打）
const START_R := 7.0
const SQUAD_KINDS := ["shield", "spear", "soldier", "shield", "spear", "soldier", "levy", "soldier", "spear", "soldier"]
const GUARD_KINDS := ["shield", "spear", "soldier", "shield", "spear", "soldier", "shield", "spear", "soldier", "soldier", "shield", "spear", "archer", "archer"]
const COLS := 3
const ROW_GAP := 1.5
const LANE_HALF := 2.2
const TIDE_AT := 35.0
const TIDE_COUNT := 30
const TIDE_COUNT_LIT18 := 20                            # 第十八烽点着了：第二夜的潮水小一些
const TIDE_T := 50.0                                    # 潮水在这里横穿山路
const CART_BURN_R := 1.7
const NEAR_CAP := 2                                     # 潮水里近处的真人模型：二十多个兵已经在画（中档实测 5 个时 423 → 2 个 400 以内）

var battle: Battle
var crowd: SleeperCrowd
var player: FpController
var carts_burning := {}          # 第几辆 → 火
var tide_started := false
var start_seen := false


## 现在该摆这场仗吗：主线「设伏」、还没打过
static func due() -> bool:
	return GameState.chapter == 2 and GameState.quest_stage("ch2_main") == "rob_ready" and not GameState.has_flag("ch2_convoy")


static func ambush() -> String:
	var a := str(GameState.get_flag("ch2_ambush", "head"))
	return a if POST_T.has(a) else "head"


## 伏击段上沿路 t 米、往一侧偏 off 米（正 = 下坡一侧）的点
static func leg_point(t: float, off := 0.0) -> Vector3:
	var a: Vector2 = HighlandLayout.ROAD[HighlandLayout.AMBUSH_LEG]
	var b: Vector2 = HighlandLayout.ROAD[HighlandLayout.AMBUSH_LEG + 1]
	var d := (b - a).normalized()
	var side := Vector2(-d.y, d.x) * _downhill()
	var p := a + d * t + side * off
	return Vector3(p.x, Highland.height_at(p.x, p.y), p.y)


## 路往山脊去的方向（车头朝的方向）
static func ahead() -> Vector3:
	var a: Vector2 = HighlandLayout.ROAD[HighlandLayout.AMBUSH_LEG]
	var b: Vector2 = HighlandLayout.ROAD[HighlandLayout.AMBUSH_LEG + 1]
	var d := (b - a).normalized()
	return Vector3(d.x, 0, d.y)


## 下坡一侧在路的左边还是右边（+1 / −1）：看哪边地势低
static func _downhill() -> float:
	var a: Vector2 = HighlandLayout.ROAD[HighlandLayout.AMBUSH_LEG]
	var b: Vector2 = HighlandLayout.ROAD[HighlandLayout.AMBUSH_LEG + 1]
	var d := (b - a).normalized()
	var m := (a + b) * 0.5
	var left := Vector2(-d.y, d.x)
	return 1.0 if HighlandLayout.height((m + left * 8.0).x, (m + left * 8.0).y) < HighlandLayout.height((m - left * 8.0).x, (m - left * 8.0).y) else -1.0


static func t_of(p: Vector3) -> float:
	var a: Vector2 = HighlandLayout.ROAD[HighlandLayout.AMBUSH_LEG]
	var b: Vector2 = HighlandLayout.ROAD[HighlandLayout.AMBUSH_LEG + 1]
	return (Vector2(p.x, p.z) - a).dot((b - a).normalized())


static func _yaw(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)


static func spawn() -> Array:
	var face := -ahead() if ambush() == "head" else ahead()
	return [leg_point(SPAWN_T[ambush()], 0.0) + Vector3(0, 0.05, 0), rad_to_deg(_yaw(face))]


static func _soldier(kind: String, id: String, side: String, t: float, col: int, face: Vector3) -> Soldier:
	var ours := side == OURS
	var s := Soldier.create(kind, id, side, Color(OUR_COAT if ours else FOE_COAT), Color(OUR_BAND if ours else FOE_BAND))
	s.position = leg_point(t, (col - (COLS - 1) * 0.5) * 1.3)
	s.rotation.y = _yaw(face)
	s.lane_a = leg_point(0.0)
	s.lane_dir = ahead()
	s.lane_half = LANE_HALF
	return s


## 摆好这场仗（main 在区域搭好以后调）；不该打返回 null
static func setup(world: Node3D) -> Battle:
	if not due():
		return null
	var director := CombatDirector.new()
	director.name = "CombatDirector"
	world.add_child(director)
	var b := Battle.new()
	b.name = "Battle"
	b.player_side = OURS
	b.add_side(OURS, "烽誓团")
	b.add_side(FOE, "洛蒙德家")
	b.line_cols = COLS
	b.rank_cols = COLS
	world.add_child(b)
	var head := ambush() == "head"
	var post: float = POST_T[ambush()]
	var face_foe := -ahead() if head else ahead()           # 我们朝车队那边
	var kinds := SQUAD_KINDS.duplicate()
	if str(GameState.get_flag("ch2_carsten", "")) == "stayed":
		kinds.append("soldier")
	for i in kinds.size():
		var t: float = post + (1.0 if head else -1.0) * (2.0 + (i / COLS) * ROW_GAP)
		var s := _soldier(kinds[i], "oath_%d" % i, OURS, t, i % COLS, face_foe)
		s.display_override = "卡斯滕" if i == SQUAD_KINDS.size() else "烽誓团 · %s" % Enemy.types()[kinds[i]].name
		b.add_to_squad(s)
		b.enlist(s, world)
	b.order("follow")
	var face_us := -face_foe
	var cap_t: float = CART_T[2]
	var captain := _soldier("captain", "convoy_captain", FOE, cap_t, 1, face_us)
	captain.display_override = "洛蒙德家 · 押车队长"
	b.enlist(captain, world)
	for i in GUARD_KINDS.size():
		var t: float                                            # 先断车头：押车兵在车队后半截，压上来；先断车尾：在车头那半截，回头救
		if head:
			t = CART_T[4] + 2.0 + (i / COLS) * ROW_GAP * 1.4
		else:
			t = CART_T[0] - 2.0 - (i / COLS) * ROW_GAP * 1.4
		var s := _soldier(GUARD_KINDS[i], "guard_%d" % i, FOE, t, i % COLS, face_us)
		s.display_override = "洛蒙德家 · %s" % Enemy.types()[GUARD_KINDS[i]].name
		b.enlist(s, world)
	var anselm := _soldier("levy", "anselm", FOE, CART_T[4] - 3.5, 1, face_us)
	anselm.display_override = "安塞尔姆"
	anselm.set_meta("anselm", true)
	b.enlist(anselm, world)
	var ca := ConvoyAmbush.new()
	ca.name = "ConvoyAmbush"
	ca.battle = b
	world.add_child(ca)
	ca._build_carts()
	if head:
		ca._build_tree()
	print("IC_AMBUSH setup ambush=%s ours=%d foe=%d" % [ambush(), kinds.size(), GUARD_KINDS.size() + 2])
	return b


## 五辆满载的粮车（一份 Decor，有碰撞）
func _build_carts() -> void:
	var d := Decor.new()
	for i in CART_T.size():
		var p := leg_point(CART_T[i], 0.4)
		d.cart(p, _yaw(-ahead()) + PI, "sacks")
	d.build(self, "AmbushCarts", true)


## 车头前锯倒的枯松：横在路上（挡人）
func _build_tree() -> void:
	var kit := MeshKit.new()
	var c := leg_point(TREE_T, 0.0)
	var side := ahead().cross(Vector3.UP).normalized()
	var a := c - side * 4.2 + Vector3(0, 0.35, 0)
	var e := c + side * 4.2 + Vector3(0, 0.3, 0)
	kit.cylinder("bark", a, e, 0.34, 0.24, 9, 0.8)
	for k in 5:
		var at := a.lerp(e, 0.25 + k * 0.15)
		kit.cylinder("bark", at, at + Vector3(0.1 * (k % 2 * 2 - 1), 0.6, 0.3 * (k % 2 * 2 - 1)), 0.05, 0.02, 5, 0.7)
	var mi := kit.build({"bark": Look.mat("bark")})
	mi.name = "FelledPine"
	add_child(mi)
	Castle._solid(self, c + Vector3(0, 0.4, 0), (Basis.looking_at(side, Vector3.UP) * Vector3(0.6, 0.8, 8.4)).abs())


## 你走到伏击点附近了吗（main 每帧看，到了就开打）
static func at_post(p: Vector3) -> bool:
	return absf(t_of(p) - float(POST_T[ambush()])) <= START_R


func _on_start() -> void:
	battle.wave_note.emit("◆ 车夫扔下鞭子往回跑了！押车兵围上来——" + ("他们从车队后头压上来了。" if ambush() == "head" else "车头那边的人回头来救。"))


func _physics_process(_delta: float) -> void:
	if battle == null or not is_instance_valid(battle) or not battle.active():
		return
	if not start_seen:
		start_seen = true
		_on_start()
	if not tide_started and battle.elapsed >= TIDE_AT:
		_start_tide()
	if crowd:
		crowd.victims = battle.roster
	_check_carts()


## 第二次潮水：从北边山脊上下来，横穿山路，往南去
func _start_tide() -> void:
	tide_started = true
	var n := TIDE_COUNT_LIT18 if Beacon18.lit() else TIDE_COUNT
	var side := ahead().cross(Vector3.UP).normalized() * _downhill()     # 下坡一侧
	var mid := leg_point(TIDE_T, 0.0)
	var route := []
	for k: float in [-40.0, -14.0, 0.0, 16.0, 46.0]:
		var p := mid + side * k
		route.append(Vector2(p.x, p.z))
	crowd = SleeperCrowd.make(route, n, 7.0)
	crowd.height_fn = Highland.height_at
	crowd.player = player
	crowd.speed_base = 0.95
	crowd.near_cap = NEAR_CAP
	add_child(crowd)
	battle.wave_note.emit("◆ 北边山脊上下来一串白影子——潮水横穿山路！拿火把把它们往押车兵那边引。")
	print("IC_AMBUSH tide count=%d" % n)


## 车着火：插着的、亮着的火把离车太近；或者你举着火把被推倒在车边
func _check_carts() -> void:
	var torches := get_tree().get_nodes_in_group("planted_torch")
	for i in CART_T.size():
		if carts_burning.has(i):
			continue
		var c := leg_point(CART_T[i], 0.4)
		var lit := false
		for t in torches:
			var pt := t as PlantedTorch
			if pt and pt.lit and pt.global_position.distance_to(c) <= CART_BURN_R:
				lit = true
		if player and player.knocked() and player.torch and player.torch.state == TorchHand.OUT and player.global_position.distance_to(c) <= CART_BURN_R + 0.6 and player.torch.dropped_lit:
			lit = true
		if lit:
			burn_cart(i)


func burn_cart(i: int) -> void:
	if carts_burning.has(i):
		return
	var c := leg_point(CART_T[i], 0.4)
	carts_burning[i] = CausewayBattle._flame(self, c + Vector3(0, 0.9, 0), 1.3)
	var light := Tavern.FireLight.new()
	light.light_color = Color("ff7a2a")
	light.base = 2.6
	light.omni_range = 10.0
	light.position = c + Vector3(0, 1.6, 0)
	add_child(light)
	if battle:
		battle.wave_note.emit("◆ 车上的麻袋着了！")
	print("IC_AMBUSH cart_burn i=%d" % i)


## 结果：赢了车没烧 taken、赢了烧了车 burned、输了 repelled
func result(winner: String) -> String:
	if winner != OURS:
		return "repelled"
	return "burned" if not carts_burning.is_empty() else "taken"


## 打完了：写旗标、声望、推进主线；返回给玩家看的一句话
static func finish(res: String) -> String:
	GameState.set_flag("ch2_convoy", res)
	GameState.change_rep("lomond", -20)
	if res != "repelled":
		GameState.change_rep("beacon_oath", 10)
	Chapter2.dawn()                                           # 火亮不亮（ch2_fire）、主线「天亮以后」（5.8）
	match res:
		"taken":
			return "✓ 押车兵散了。五车粮是你们的了——马蒂亚斯的人连夜把车往山上推。天快亮了。"
		"burned":
			return "✓ 押车兵散了。可着了火的车救不回来——剩下的粮推上山，烧掉的只剩一地焦黑的麦子。天快亮了。"
	return "× 你们被打散了。押车兵护着车翻过了山脊。马蒂亚斯的人扶着伤兵往回走。天快亮了。"
