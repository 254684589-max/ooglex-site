class_name CausewayBattle
extends RefCounted
## 堤道夜战（路线图 4.9a；STORY.md 4.6；用 B.1–B.5 的军阵）：入夜备战说定以后（主线「上堤道」、夜里、还没打过），鹭沼地图上摆好一场仗。
## 守方（瓦伦家，白布带）：你、你的小队（赫尔曼给的六个人，分了两个守水门的只剩四个；跟着你出堡门，默认「跟随我」），
## 石拱上赫尔曼带着他的六个人守着（不归你指挥：只打石拱附近的敌人，赫尔曼是队长）。
## 攻方（另一位继承人的人，黑布带）：先头 8 人（民兵、剑兵）在堤道村子那头列好；主力 14 人（剑盾、长枪、剑兵、2 名弓手）开打后 WAVE2_AT 秒到；
## 第三波「芦刀」加斯帕（队长）和 6 名精兵 WAVE3_AT 秒到。同屏最多约 40 人。
## 开打：你沿堤道走到和赫尔曼定下的守点（断口或石拱，ch1_hold）附近（main 每帧看，先自动存档）。
## 守住：攻方倒下 / 溃逃过半（B.3 的规则；打倒加斯帕全队士气大掉）。失守：你这边溃逃过半，或者攻方有 BREACH_LIMIT 个人冲过石拱（据点规则，Battle.breach_*）。
## 你自己倒下：读档（开打前的自动存档）。结束写 ch1_causeway = held / lost（main._on_battle_ended → finish）。
## 留到 4.9b：奥弗从芦苇里杀出、水门绕后、泥炭垛点火、芦苇挡视线、泥里变慢、远处的火把线、窄路两列的队形。

const DEF := "valen"
const ATK := "rebels"
const DEF_COAT := "3e4652"
const DEF_BAND := "ece6d8"
const ATK_COAT := "6a3a2e"
const ATK_BAND := "161616"
const HOLD_T := {"gap": 45.5, "arch": 75.0}       # 守点：断口靠堡这头、石拱靠堡这头（沿堤道的米数）
const START_R := 6.0                              # 走到守点这么近就开打
const SQUAD_KINDS := ["shield", "spear", "soldier", "shield", "spear", "soldier"]      # 分人守水门时后两个不来
const ARCH_KINDS := ["shield", "spear", "soldier", "shield", "spear", "archer"]
const ARCH_T := 77.0                              # 赫尔曼的人站在石拱靠堡这头
const ARCH_GUARD_R := 7.0
const BREACH_T := MarshLayout.ARCH_T + 7.0        # 攻方过了这里（石拱和赫尔曼的人都在身后）就算冲过去了
const BREACH_LIMIT := 6
const WAVE1 := ["levy", "soldier", "levy", "soldier", "levy", "soldier", "levy", "soldier"]
const WAVE2 := ["shield", "spear", "shield", "spear", "soldier", "shield", "spear", "soldier", "shield", "spear", "soldier", "soldier", "archer", "archer"]
const WAVE3 := ["shield", "soldier", "shield", "soldier", "spear", "spear"]
const WAVE1_T := 10.0                             # 先头在堤道村子那头列队（沿堤道的米数，往村子方向一排排往后）
const WAVE_T := 4.0                               # 援军从堤道头上来
const WAVE2_AT := 35.0
const WAVE3_AT := 70.0
const ROW_GAP := 1.6
const LANE_HALF := 1.0                            # 兵离堤道中线超过这么远就往回走（路面半宽 2 米，断口上的木板半宽 1.2 米）
const COLS := 2                                   # 堤道 4 米宽：两人一排


## 现在该摆这场仗吗：主线「上堤道」、夜里、还没打过
static func due() -> bool:
	return GameState.quest_stage("ch1_main") == "to_causeway" and GameState.daypart == "night" and not GameState.has_flag("ch1_causeway")


## 攻方是谁的人（另一位继承人）
static func foe_name() -> String:
	return "伊薇特的人" if str(GameState.get_flag("valen_heir", "")) == "alric" else "阿尔里克的人"


static func hold() -> String:
	var h := str(GameState.get_flag("ch1_hold", "arch"))
	return h if HOLD_T.has(h) else "arch"


static func hold_point() -> Vector3:
	return MarshLayout.cw3(float(HOLD_T[hold()]))


## 沿堤道的米数（0 = 村子那头的堤道头）
static func t_of(p: Vector3) -> float:
	return (Vector2(p.x, p.z) - MarshLayout.CW_START).dot(MarshLayout.CW_DIR)


## 朝村子（攻方来的方向）
static func toward_village() -> Vector3:
	return Vector3(-MarshLayout.CW_DIR.x, 0, -MarshLayout.CW_DIR.y)


static func _yaw(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)


## 摆一个兵：沿堤道 t 米、两列里的第 col 列
static func _soldier(kind: String, id: String, side: String, t: float, col: int) -> Soldier:
	var def := side == DEF
	var s := Soldier.create(kind, id, side, Color(DEF_COAT if def else ATK_COAT), Color(DEF_BAND if def else ATK_BAND))
	s.position = MarshLayout.cw3(t, (col - (COLS - 1) * 0.5) * 1.3)
	s.rotation.y = _yaw(toward_village() if def else -toward_village())
	s.extra_mask = FpController.LAYER_BOUNDARY
	s.lane_a = MarshLayout.cw3(0.0)
	s.lane_dir = Vector3(MarshLayout.CW_DIR.x, 0, MarshLayout.CW_DIR.y)
	s.lane_half = LANE_HALF
	return s


## 摆好这场仗（main 在区域搭好以后、接军阵的 HUD 以前调）；不该打返回 null
static func setup(world: Node3D) -> Battle:
	if not due():
		return null
	var director := CombatDirector.new()
	director.name = "CombatDirector"
	world.add_child(director)
	var b := Battle.new()
	b.name = "Battle"
	b.player_side = DEF
	b.add_side(DEF, "守军")
	b.add_side(ATK, foe_name())
	b.breach_side = ATK
	b.breach_limit = BREACH_LIMIT
	b.breach_test = func(s: Soldier) -> bool: return t_of(s.global_position) > BREACH_T
	world.add_child(b)
	var gate_t := t_of(MarshLayout.SPAWNS.castle_gate[0])
	var n := 4 if GameState.has_flag("ch1_gate_guard") else SQUAD_KINDS.size()
	for i in n:                                                  # 你的小队：堡门里出来，站在你身后
		var s := _soldier(SQUAD_KINDS[i], "squad_%d" % i, DEF, gate_t + 1.6 + (i / COLS) * ROW_GAP, i % COLS)
		s.display_override = "守军 · 卫兵"
		b.add_to_squad(s)
		b.enlist(s, world)
	b.order("follow")
	var herman := _soldier("captain", "herman", DEF, ARCH_T + 1.2, 0)
	herman.display_override = "赫尔曼"
	var arch := [herman]
	for i in ARCH_KINDS.size():
		arch.append(_soldier(ARCH_KINDS[i], "arch_%d" % i, DEF, ARCH_T + (i / COLS) * ROW_GAP, i % COLS))
	for s: Soldier in arch:
		s.guard_post = s.position
		s.guard_r = ARCH_GUARD_R
		s.guard_face = toward_village()
		if s != herman:
			s.display_override = "守军 · 赫尔曼的人"
		b.enlist(s, world)
	for i in WAVE1.size():                                      # 先头：村子那头列好，开打就往堡这边压
		var s := _soldier(WAVE1[i], "van_%d" % i, ATK, WAVE1_T - (i / COLS) * ROW_GAP, i % COLS)
		s.display_override = "%s · %s" % [foe_name(), Enemy.types()[WAVE1[i]].name]
		b.enlist(s, world)
	b.add_wave(ATK, _wave("main", WAVE2), world, WAVE2_AT)
	var third := _wave("elite", WAVE3)
	var gaspar := _soldier("captain", "gaspar", ATK, WAVE_T + ROW_GAP, 0)
	gaspar.display_override = "「芦刀」加斯帕"
	third.push_front(gaspar)
	b.add_wave(ATK, third, world, WAVE3_AT)
	print("IC_CAUSEWAY setup hold=%s squad=%d foe=%s" % [hold(), n, foe_name()])
	return b


static func _wave(tag: String, kinds: Array) -> Array:
	var out := []
	for i in kinds.size():
		var s := _soldier(kinds[i], "%s_%d" % [tag, i], ATK, WAVE_T - (i / COLS) * ROW_GAP, i % COLS)
		s.display_override = "%s · %s" % [foe_name(), Enemy.types()[kinds[i]].name]
		out.append(s)
	return out


## 你走到守点附近了吗（main 每帧看，到了就开打）
static func at_post(p: Vector3) -> bool:
	return t_of(p) <= float(HOLD_T[hold()]) + START_R


## 打完了：写旗标、推进主线；返回给玩家看的一句话
static func finish(held: bool) -> String:
	GameState.set_flag("ch1_causeway", "held" if held else "lost")
	if GameState.quest_active("ch1_main"):
		GameState.set_stage("ch1_main", "after_causeway")
	if held:
		return "✓ 守住了！%s退回了沼地。天快亮了……" % foe_name()
	return "× 堤道失守了。你被挤下堤道，跌进泥里……"
