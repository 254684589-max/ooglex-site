class_name CausewayBattle
extends Node3D
## 堤道夜战（路线图 4.9a；STORY.md 4.6；用 B.1–B.5 的军阵）：入夜备战说定以后（主线「上堤道」、夜里、还没打过），鹭沼地图上摆好一场仗。
## 守方（瓦伦家，白布带）：你、你的小队（赫尔曼给的六个人，分了两个守水门的只剩四个；跟着你出堡门，默认「跟随我」），
## 石拱上赫尔曼带着他的六个人守着（不归你指挥：只打石拱附近的敌人，赫尔曼是队长）。
## 攻方（另一位继承人的人，黑布带）：先头 8 人（民兵、剑兵）在堤道村子那头列好；主力 14 人（剑盾、长枪、剑兵、2 名弓手）开打后 WAVE2_AT 秒到；
## 第三波「芦刀」加斯帕（队长）和 6 名精兵 WAVE3_AT 秒到。同屏最多约 40 人。
## 开打：你沿堤道走到和赫尔曼定下的守点（断口或石拱，ch1_hold）附近（main 每帧看，先自动存档）。
## 守住：攻方倒下 / 溃逃过半（B.3 的规则；打倒加斯帕全队士气大掉）。失守：你这边溃逃过半，或者攻方有 BREACH_LIMIT 个人冲过石拱（据点规则，Battle.breach_*）。
## 你自己倒下：读档（开打前的自动存档）。结束写 ch1_causeway = held / lost（main._on_battle_ended → finish）。
## 4.9b 变数与地形（STORY 4.6）：
##   奥弗（ch1_outlaws = ally）：主力到时他带 4 个人从堤道边的芦苇里杀出来（站在守方，不归你指挥；奥弗死在渡口的，是无旗者的头目带人来）；
##   水门：埃德里克没交出钥匙（kept），又没人提醒你、或者提醒了却没分人去守（warned + ch1_gate_guard），主力到时有 4 个人从水门摸到堡门背后（不算「冲过石拱」）；
##     分了人守的，两个人把他们挡回去（只有一句提示）；
##   泥炭垛：这一仗里断口靠村子这头路边码着两垛泥炭（挡人，路窄成 2 米多）；选了伊薇特、托宾的泥炭工站在她这边、守的又是断口的，
##     先头冲到断口前时泥炭工点着它，火墙拦住堤道 PEAT_BURN 秒，火边的攻方士气大掉；
##   芦苇挡视线：站在堤道外面（路边泥里、芦苇丛里）的人，离得比 REED_SEE 远就看不见（Battle.see_test）；泥里走得慢（Soldier.slow_below）；
##   远处的火把：攻方的火把在村子那头的沼地上连成一条线，开打后慢慢压到堤道头，主力上来以后就是他们（只是背景，不受雾挡）；
##   窄路两列：小队的坚守、跟随队形两人一排，坚守时顺着堤道朝村子排（Battle.line_cols / rank_cols / hold_facing）。

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
const REED_OFF := 3.0                             # 离堤道中线这么远就在堤道外面（芦苇、泥里）
const REED_SEE := 6.0                             # 芦苇里的人：离得比这远看不见
const OUTLAW_KINDS := ["soldier", "levy", "soldier", "levy", "soldier"]     # 第一个是奥弗（或头目）
const OUTLAW_T := 26.0                            # 奥弗的人藏在堤道东北边的芦苇里（沿堤道 26–29 米、离中线 5 米）
const OUTLAW_OFF := 5.0
const OUTLAW_COAT := "4a4434"
const GATE_KINDS := ["soldier", "shield", "soldier", "levy"]
const GATE_T := 91.0                              # 水门摸进来的人出现在堡门前的石台上
const PEAT_T := 35.2                              # 断口靠村子这头路边的两垛泥炭
const PEAT_OFF := 1.75
const PEAT_SIZE := Vector3(0.7, 0.9, 1.3)         # 横（离中线方向）、高、顺着路
const PEAT_TRIGGER_T := 30.0                      # 攻方有人走到这里就点火
const PEAT_BURN := 15.0
const PEAT_SCARE := 15.0                          # 火边 8 米内的攻方士气 −15
const TORCHES := 14
const TORCH_FROM := -26.0                         # 火把线：开打时在村子那头（沿堤道的米数，负的是堤道头往东南）
const TORCH_TO := -3.0
const TORCH_SPAN := 24.0                          # 火把线的宽度

var battle: Battle
var torches: Array = []           # [火苗, 横着的偏移, 晃动相位]
var peat_fire := false            # 这一仗会点泥炭垛吗
var peat_lit := false
var burn_left := 0.0
var barrier: StaticBody3D
var flames: Array = []


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
	s.slow_below = MarshLayout.CAUSE_Y - 0.3
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
	b.breach_test = func(s: Soldier) -> bool: return not s.has_meta("flank") and t_of(s.global_position) > BREACH_T
	b.line_cols = COLS
	b.rank_cols = COLS
	b.hold_facing = toward_village()
	b.see_test = func(_s: Soldier, o: Node3D) -> bool: return off_of(o.global_position) <= REED_OFF or _s.global_position.distance_to(o.global_position) <= REED_SEE
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
	if str(GameState.get_flag("ch1_outlaws", "")) == "ally":    # 奥弗：主力到时从芦苇里杀出来
		var lead := "无旗者的头目" if GameState.dead.has("ferry_offer") else "「灰手」奥弗"
		var outlaws := []
		for i in OUTLAW_KINDS.size():
			var s := Soldier.create(OUTLAW_KINDS[i], "outlaw_%d" % i, DEF, Color(OUTLAW_COAT), Color(DEF_BAND))
			s.position = MarshLayout.cw3(OUTLAW_T + i * 0.8, OUTLAW_OFF + (i % 2) * 1.2, MarshLayout.MUD_Y)
			s.rotation.y = _yaw(-toward_village())
			s.extra_mask = FpController.LAYER_BOUNDARY
			s.slow_below = MarshLayout.CAUSE_Y - 0.3
			s.display_override = lead if i == 0 else "无旗者"
			outlaws.append(s)
		b.add_wave(DEF, outlaws, world, WAVE2_AT + 4.0, "◆ %s带着人从芦苇里杀出来了，打在他们背后！" % lead)
	match gate_state():
		"breach":
			var g := []
			for i in GATE_KINDS.size():
				var s := _soldier(GATE_KINDS[i], "gate_%d" % i, ATK, GATE_T + (i / COLS) * ROW_GAP, i % COLS)
				s.set_meta("flank", true)
				s.display_override = "%s · 从水门摸进来的" % foe_name()
				g.append(s)
			b.add_wave(ATK, g, world, WAVE2_AT, "◆ 水门那边摸进来 4 个人——堡门背后有敌人！")
		"guarded":
			b.add_wave(ATK, [], world, WAVE2_AT, "◆ 水门那边有动静——守水门的两个人把摸进来的人挡回去了。")
	var cw := CausewayBattle.new()
	cw.name = "Causeway"
	cw.battle = b
	cw.peat_fire = will_burn_peat()
	world.add_child(cw)
	cw._build_peat()
	cw._build_torches()
	print("IC_CAUSEWAY setup hold=%s squad=%d foe=%s outlaws=%s gate=%s peat=%s" % [hold(), n, foe_name(), GameState.get_flag("ch1_outlaws", ""), gate_state(), cw.peat_fire])
	return b


## 离堤道中线多远（米）
static func off_of(p: Vector3) -> float:
	return absf((Vector2(p.x, p.z) - MarshLayout.CW_START).dot(MarshLayout.CW_SIDE))


## 水门：breach 有人摸进来 / guarded 分了人守、挡回去了 / shut 埃德里克交出了钥匙，门没开
static func gate_state() -> String:
	var wg := str(GameState.get_flag("ch1_water_gate", "unknown"))
	if wg == "kept":
		return "shut"
	if wg == "warned" and GameState.has_flag("ch1_gate_guard"):
		return "guarded"
	return "breach"


## 泥炭垛会点着吗：泥炭工站在伊薇特这边、印戒给了伊薇特、守的是断口
static func will_burn_peat() -> bool:
	return str(GameState.get_flag("ch1_peat", "")) == "ivette" and str(GameState.get_flag("valen_heir", "")) == "ivette" and hold() == "gap"


## 断口靠村子这头路边的两垛泥炭（挡人，路窄成 2 米多）
func _build_peat() -> void:
	var kit := MeshKit.new()
	var right := Vector3(MarshLayout.CW_SIDE.x, 0, MarshLayout.CW_SIDE.y)
	var along := Vector3(MarshLayout.CW_DIR.x, 0, MarshLayout.CW_DIR.y)
	var b := Basis(right, Vector3.UP, along)
	for sgn: float in [-1.0, 1.0]:
		var c := MarshLayout.cw3(PEAT_T, sgn * PEAT_OFF)
		for layer in 3:
			var h := PEAT_SIZE.y / 3.0
			kit.box("peat", c + Vector3(0, h * (layer + 0.5), 0), PEAT_SIZE - Vector3(layer * 0.12, h * 2.0 + 0.02, layer * 0.15), b * Basis(Vector3.UP, (layer - 1) * 0.06), 0.95 - layer * 0.05, 0.6)
		Castle._solid(self, c + Vector3(0, PEAT_SIZE.y * 0.5, 0), (b * PEAT_SIZE).abs())
	var mi := kit.build({"peat": Look.mat("peat")})
	mi.name = "PeatStacks"
	add_child(mi)


## 远处的火把线：一排火苗（不受雾挡，远远就看得见）
func _build_torches() -> void:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.disable_fog = true
	m.albedo_color = Color(1.0, 0.6, 0.25, 0.9)
	var q := QuadMesh.new()
	q.size = Vector2(0.9, 1.2)
	q.material = m
	var rng := RandomNumberGenerator.new()
	rng.seed = 4901
	for i in TORCHES:
		var f := MeshInstance3D.new()
		f.name = "Torch%d" % i
		f.mesh = q
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var off := (float(i) / (TORCHES - 1) - 0.5) * TORCH_SPAN + rng.randf_range(-0.8, 0.8)
		torches.append([f, off, rng.randf() * TAU])
		add_child(f)
	_place_torches(0.0)


## 火把线压过来：开打以后 WAVE2_AT 秒里从 TORCH_FROM 走到 TORCH_TO，主力上来以后熄掉（他们就是主力）
func _place_torches(t: float) -> void:
	var k := clampf(t / WAVE2_AT, 0.0, 1.0)
	var along := lerpf(TORCH_FROM, TORCH_TO, k)
	for e in torches:
		var f: MeshInstance3D = e[0]
		f.visible = t < WAVE2_AT + 2.0
		f.position = MarshLayout.cw3(along + sin(float(e[2]) + t * 0.7) * 0.6, float(e[1]), 1.9 + sin(float(e[2]) * 3.0 + t * 2.3) * 0.08)


func _process(delta: float) -> void:
	if battle == null or not is_instance_valid(battle):
		return
	if not torches.is_empty():
		_place_torches(battle.elapsed)
	if peat_fire and not peat_lit and battle.active() and _vanguard_at_gap():
		_ignite()
	if burn_left > 0.0:
		burn_left -= delta
		if burn_left <= 0.0:
			_burn_out()


func _vanguard_at_gap() -> bool:
	for s in battle.roster:
		if is_instance_valid(s) and s.side == ATK and s.fighting() and t_of(s.global_position) >= PEAT_TRIGGER_T:
			return true
	return false


## 泥炭工点着了泥炭垛：两垛冒火、横着拦一道火墙（挡人：兵和你都过不去），火边的攻方慌
func _ignite() -> void:
	peat_lit = true
	burn_left = PEAT_BURN
	barrier = StaticBody3D.new()
	barrier.name = "PeatFire"
	barrier.collision_layer = FpController.LAYER_BOUNDARY
	barrier.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(MarshLayout.CW_W + 1.0, 2.4, 0.8)
	shape.shape = box
	barrier.add_child(shape)
	barrier.position = MarshLayout.cw3(PEAT_T, 0.0, MarshLayout.CAUSE_Y + 1.2)
	barrier.rotation.y = _yaw(-toward_village())
	add_child(barrier)
	for sgn: float in [-1.0, 0.0, 1.0]:
		var at := MarshLayout.cw3(PEAT_T, sgn * PEAT_OFF, MarshLayout.CAUSE_Y + (PEAT_SIZE.y if sgn != 0.0 else 0.1))
		flames.append(_flame(self, at, 1.0 if sgn != 0.0 else 0.6))
	var light := Tavern.FireLight.new()
	light.name = "PeatLight"
	light.light_color = Color("ff7a2a")
	light.base = 3.0
	light.omni_range = 12.0
	light.position = MarshLayout.cw3(PEAT_T, 0.0, MarshLayout.CAUSE_Y + 1.6)
	add_child(light)
	flames.append(light)
	for s in battle.roster:
		if is_instance_valid(s) and s.side == ATK and s.fighting() and s.global_position.distance_to(barrier.global_position) <= 8.0:
			s.shake(-PEAT_SCARE)
	battle.wave_note.emit("◆ 托宾的人点着了断口边上的泥炭垛——一道火墙拦住了堤道！")
	print("IC_CAUSEWAY peat_lit t=%.0f" % battle.elapsed)


## 火小了：火墙撤掉，只剩一点余烬
func _burn_out() -> void:
	if is_instance_valid(barrier):
		barrier.queue_free()
	for f in flames:
		if f is CPUParticles3D:
			(f as CPUParticles3D).amount = 6
		elif f is Tavern.FireLight:
			(f as Tavern.FireLight).base = 0.8
	print("IC_CAUSEWAY peat_out t=%.0f" % battle.elapsed)


## 一团火：往上窜、由黄变红变透明的粒子（CPU 粒子，网页兼容渲染器上 GPU 粒子不稳）
static func _flame(parent: Node3D, at: Vector3, size: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Flame"
	p.position = at
	p.amount = 18
	p.lifetime = 0.9
	p.preprocess = 0.9
	var q := QuadMesh.new()
	q.size = Vector2(0.7, 0.7) * size
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = Atmos._soft_dot()
	q.material = m
	p.mesh = q
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.5, 0.1, 0.5) * size
	p.direction = Vector3.UP
	p.spread = 15.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 2.0
	p.gravity = Vector3(0, 0.5, 0)
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.3
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.85, 0.4, 0.9))
	ramp.add_point(0.5, Color(1.0, 0.45, 0.12, 0.7))
	ramp.set_color(ramp.get_point_count() - 1, Color(0.4, 0.1, 0.05, 0.0))
	p.color_ramp = ramp
	parent.add_child(p)
	return p


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
