class_name ConvoyEscort
extends Node3D
## 第二夜 · 护粮（路线图 5.7b；STORY.md 5.6 表「护粮」）。安塞尔姆答应分三车粮（主线「护车」，`ch2_aid` = granted）以后天黑透：
## 三辆粮车在盘山路伏击段的下头排成一列（同一段路：HighlandLayout.AMBUSH_LEG，ConvoyAmbush.leg_point），一辆接一辆往山脊上推。
## 每辆车：一个车夫在前头拉车把；两个烽誓团的兵举着火把走在车两边（BEARER_OFF）——火让长眠者绕开，给车开出一条道；
## 洛蒙德家的八个押车兵跟在车后（不打人：没人来抢，敌人是潮水和山路）。
## 车头走到 TIDE_START_T 米，第二次潮水从北边山脊上下来、横穿山路（同劫粮：ConvoyAmbush.TIDE_T；第十八烽点着了少一些）。
## 风会吹灭兵手里的火把（BLOW）：灭了的自己过 RELIGHT_SELF 秒从车上的油罐续上；你举着点着的火把对着他按 E 马上点着。
## 车上有油罐：对着车按 E 续火把（手里没有就拿一支点着的）。
## 一辆车两边的火都灭了、长眠者又在 PANIC_R 以内，车夫就慌（panic 涨，PANIC_TIME 秒涨满）；慌了一半对着车按 E「稳住车夫」；涨满了他扔下车往山下跑（这辆车丢了）。
## 前面有长眠者挡路（车头前 BLOCK_AHEAD 米、BLOCK_R 以内），车停下等。
## 结果（ch2_convoy）：过了潮水、到伏击段上头（END_T）的车 ≥ 2 = delivered，1 = partial，0 = lost。你倒下：读档（动身前的自动存档）。

signal begun
signal ended(result: String)
signal note(text: String)

const CARTS := 3
const CART_START := [26.0, 17.0, 8.0]          # 动身时三辆车在伏击段上的米数（第一辆在前）
const END_T := 86.0                            # 过了这里算送上山了
const SPEED := 1.05
const GAP_MIN := 6.5                           # 跟前车至少隔这么远
const SPAWN_T := 2.0                           # 你站在车队后头
const START_DELAY := 4.0                       # 到了以后几秒动身（先自动存档）
const TIDE_START_T := 30.0                     # 头车走到这里，潮水下来（从岩坎上头 TIDE_FROM 米下来：头车到横穿的地方时正好撞上）
const TIDE_FROM := 22.0
const BEARER_OFF := 1.6                        # 举火把的兵走在车两边多远
const BLOW := 1.0 / 18.0                       # 风里每个兵手里的火把每秒被吹灭的机会（没人帮着挡风，比你举着的容易灭得多：没人管的话一辆车常有两边都灭的时候）
const RELIGHT_SELF := 30.0                     # 灭了以后自己去车上续油点着要多久
const PANIC_R := 4.5
const SAFE_R := 3.4                            # 这么近有亮着的火，车夫就不慌
const PANIC_TIME := 8.0
const CALM_DECAY := 1.0 / 14.0
const BLOCK_AHEAD := 2.6
const BLOCK_R := 1.6
const LOST_OFF := 2.6                          # 扔下的车歪到路肩上
const GONE_DIST := 12.0
const GONE_SEC := 20.0
const CART_R := 1.4                            # 长眠者绕开车（障碍半径）
const GUARDS := [3, 3, 2]                      # 每辆车后头跟几个押车兵（共 8 个）
const NEAR_CAP := 2
const TIME_MAX := 420.0
const PANIC_NOTE := "第%s辆车的车夫在发抖，攥着车把直往后看——两边的火都灭了。"
const FLEE_NOTE := "第%s辆车的车夫扔下车把往山下跑了！那车粮丢在路上了。"
const NUM := ["一", "二", "三"]

enum {WAIT, GO, DONE}

var state := WAIT
var player: FpController
var wait_left := START_DELAY
var clock := 0.0
var carts: Array = []            # 每辆车：{node, t, panic, said, state: "go" / "wait" / "through" / "lost", carter, bearers: [..], guards: [..], flee_t}
var bearers: Array = []          # 每个举火把的兵：{node, cart, side, lit, out_t, model, prop, use}
var crowd: SleeperCrowd
var tide_started := false
var light: OmniLight3D
var rng := RandomNumberGenerator.new()
var windy := true
var result := ""


## 现在该护车吗：主线「护车」、还没走过
static func due() -> bool:
	return GameState.chapter == 2 and GameState.quest_stage("ch2_main") == "escort_ready" and not GameState.has_flag("ch2_convoy")


static func spawn() -> Array:
	return [ConvoyAmbush.leg_point(SPAWN_T, 0.0) + Vector3(0, 0.05, 0), rad_to_deg(ConvoyAmbush._yaw(ConvoyAmbush.ahead()))]


## 摆好（main 在高地搭好以后调）；不该护车返回 null
static func setup(world: Node3D) -> ConvoyEscort:
	if not due():
		return null
	var ce := ConvoyEscort.new()
	ce.name = "ConvoyEscort"
	world.add_child(ce)
	return ce


func _ready() -> void:
	rng.randomize()
	for i in CARTS:
		var node := Node3D.new()
		node.name = "EscortCart%d" % i
		add_child(node)
		var d := Decor.new()
		d.cart(Vector3.ZERO, 0.0, "sacks")
		d.build(node, "Cart", false)
		var c := {"node": node, "t": float(CART_START[i]), "panic": 0.0, "said": false, "state": "wait", "flee_t": 0.0}
		var use := Examine.make("粮车", "续火把", _use_cart.bind(i), Vector3(1.3, 1.3, 1.8))
		use.verb_fn = func(): return "稳住车夫" if float(carts[i].panic) > 0.3 and carts[i].state != "lost" else "续火把"
		node.add_child(use)
		c["use"] = use
		c["carter"] = _person("车夫", "Carter%d" % i, node, Vector3(0, 0, -1.7), "walk")
		var gs := []
		for g in GUARDS[i]:
			gs.append(_person("押车兵", "Guard%d_%d" % [i, g], node, Vector3((g - (GUARDS[i] - 1) * 0.5) * 1.1, 0, 2.6 + (g % 2) * 0.6), "walk"))
		c["guards"] = gs
		carts.append(c)
		for s: float in [-1.0, 1.0]:
			bearers.append(_bearer(i, s))
	for i in CARTS:
		_place(i)
	for b in bearers:
		_place_bearer(b)
	light = OmniLight3D.new()
	light.light_color = Color("ff9a4a")
	light.light_energy = 1.4
	light.omni_range = 8.0
	light.omni_attenuation = 1.3
	light.light_cull_mask = TorchHand.LIGHT_MASK
	light.visible = PlantedTorch.max_lights > 0
	add_child(light)
	print("IC_ESCORT setup carts=%d bearers=%d guards=%d" % [CARTS, bearers.size(), GUARDS.reduce(func(a, b): return a + b, 0)])


## 车上走的人（车夫、押车兵）：车的子节点，跟着车走
func _person(look_name: String, node_name: String, parent: Node3D, at: Vector3, anim: String) -> CharacterModel:
	var m := Looks.make(look_name)
	if m == null:
		return null
	m.name = node_name
	m.position = at
	m.rotation.y = PI
	parent.add_child(m)
	if m.loaded:
		Looks.finish(m)
		m.play_loop("idle" if anim == "walk" else anim, randf_range(0.9, 1.1))
		m.set_anim_every(2)
	return m


## 举火把的兵：一个节点（亮着时进 light_source 组，长眠者绕开）+ 真人模型左手举火把 + 能对着按 E 点着
func _bearer(cart: int, side: float) -> Dictionary:
	var root := Node3D.new()
	root.name = "Bearer%d%s" % [cart, "L" if side < 0.0 else "R"]
	root.set_meta("radius", TorchHand.RADIUS)
	root.set_meta("no_warm", true)
	add_child(root)
	var b := {"node": root, "cart": cart, "side": side, "lit": true, "out_t": 0.0, "model": null, "prop": null}
	var m := Looks.make("营房门口的兵")
	if m:
		m.name = "Look"
		m.rotation.y = PI
		root.add_child(m)
		if m.loaded:
			Looks.finish(m)
			var prop := TorchHand.make_visual(1)             # 同你手里的火把（火苗、光晕；灭了只剩一根黑棍），举过头顶、在外侧（走路的动作手是垂着的，挂在手上看不见火）
			prop.position = Vector3(float(side) * 0.32, 1.62, -0.12)
			prop.rotation.z = -float(side) * 0.12
			prop.scale = Vector3.ONE * 1.25
			root.add_child(prop)
			b.prop = prop
			m.play_loop("torch", randf_range(0.9, 1.1))
			m.set_anim_every(2)
		b.model = m
	var use := Examine.make("烽誓团的兵", "点着火把", _use_bearer.bind(bearers.size()), Vector3(0.8, 1.8, 0.8))
	use.verb_fn = func(): return "点着火把" if not bool(b.lit) else "火把亮着"
	root.add_child(use)
	b["use"] = use
	_set_lit(b, true)
	return b


func _set_lit(b: Dictionary, on: bool) -> void:
	b.lit = on
	var root: Node3D = b.node
	if on:
		root.add_to_group("light_source")
	elif root.is_in_group("light_source"):
		root.remove_from_group("light_source")
	if b.prop:
		TorchHand.set_lit(b.prop as Node3D, on)
	if not on:
		b.out_t = clock


func _place(i: int) -> void:
	var c: Dictionary = carts[i]
	var t := float(c.t)
	var node: Node3D = c.node
	var off := float(c.get("off", 0.4))
	var p := ConvoyAmbush.leg_point(t, off)
	var hf := ConvoyAmbush.leg_point(t + 0.9, off).y
	var hb := ConvoyAmbush.leg_point(t - 0.9, off).y
	node.global_position = p
	node.rotation = Vector3(atan2(hf - hb, 1.8), ConvoyAmbush._yaw(ConvoyAmbush.ahead()), 0.0)


func _place_bearer(b: Dictionary) -> void:
	var c: Dictionary = carts[int(b.cart)]
	var p := ConvoyAmbush.leg_point(float(c.t) - 0.3, 0.4 + float(b.side) * BEARER_OFF)
	var root: Node3D = b.node
	root.global_position = p
	root.rotation.y = ConvoyAmbush._yaw(ConvoyAmbush.ahead())


## 车的位置（地面上的平面坐标）
func cart_xz(i: int) -> Vector2:
	var p := ConvoyAmbush.leg_point(float(carts[i].t), float(carts[i].get("off", 0.4)))
	return Vector2(p.x, p.z)


func lit_bearers() -> int:
	return bearers.filter(func(b): return b.lit).size()


func through() -> int:
	return carts.filter(func(c): return c.state == "through").size()


func lost() -> int:
	return carts.filter(func(c): return c.state == "lost").size()


## 动身（main 先自动存档再调）
func begin() -> void:
	if state != WAIT:
		return
	state = GO
	for c in carts:
		c.state = "go"
	_anim_all("walk")
	begun.emit()
	note.emit("◆ 车队动身了。火把别让风吹灭——灭了的兵按 E 帮他点着；车上有油罐，对着车按 E 续火把。")
	print("IC_ESCORT begin")


func _anim_all(r: String) -> void:
	for c in carts:
		_anim_cart(c, r)


func _anim_cart(c: Dictionary, r: String) -> void:
	var ms: Array = [c.carter] + c.guards
	for m in ms:
		if m and (m as CharacterModel).loaded and c.state != "lost":
			(m as CharacterModel).play_loop(r if r == "walk" else "idle", 0.62 if r == "walk" else 1.0)
	for b in bearers:
		if int(b.cart) == carts.find(c) and b.model and (b.model as CharacterModel).loaded:
			(b.model as CharacterModel).play_loop("walk" if r == "walk" else "torch", 0.62 if r == "walk" else 1.0)


func _physics_process(delta: float) -> void:
	clock += delta
	match state:
		WAIT:
			wait_left -= delta
		GO:
			_tick(delta)
		DONE:
			for i in CARTS:
				if carts[i].state == "through":
					_gone(i)


func _tick(delta: float) -> void:
	_wind(delta)
	var lead_t := 0.0
	var fires := SleeperCrowd.fires(get_tree())
	for i in CARTS:
		var c: Dictionary = carts[i]
		if c.state == "lost":
			_flee(c, delta)
			continue
		if c.state == "through":
			_gone(i)
			continue
		var was: String = c.state
		var go := not _blocked(i)
		for j in range(i - 1, -1, -1):                   # 跟前面还在路上的车（扔在路肩上的、过去了的不算）隔开
			var ahead_c: Dictionary = carts[j]
			if ahead_c.state == "go" or ahead_c.state == "wait":
				if float(ahead_c.t) - float(c.t) < GAP_MIN:
					go = false
				break
		if go:
			c.t = float(c.t) + SPEED * delta
			c.state = "go"
		else:
			c.state = "wait"
		if c.state != was:
			_anim_cart(c, "walk" if c.state == "go" else "idle")
		_panic(i, delta, fires)
		if c.state != "lost" and float(c.t) >= END_T:
			c.state = "through"
			c.through_at = clock
			_anim_cart(c, "idle")
			print("IC_ESCORT through i=%d" % i)
		_place(i)
		lead_t = maxf(lead_t, float(c.t))
	for b in bearers:
		if carts[int(b.cart)].state != "lost":
			_place_bearer(b)
	if not tide_started and lead_t >= TIDE_START_T:
		_start_tide()
	if crowd:
		var obs := []
		for i in CARTS:
			obs.append([cart_xz(i), CART_R])
		crowd.obstacles = obs
	_light()
	if carts.all(func(c): return c.state in ["through", "lost"]) or clock >= TIME_MAX:
		finish_run()


## 过去了的车接着往烽燧去：你离它 GONE_DIST 米以外、或者过去 GONE_SEC 秒以后，车和跟车的人都不画了（翻过了山脊；不然一群人挤在路头，绘制调用超预算：中档实测 427）
func _gone(i: int) -> void:
	var c: Dictionary = carts[i]
	var node: Node3D = c.node
	if not node.visible:
		return
	var far := player == null or cart_xz(i).distance_to(Vector2(player.global_position.x, player.global_position.z)) >= GONE_DIST
	if far or clock - float(c.get("through_at", clock)) >= GONE_SEC:
		node.visible = false
		(c.use as Examine).collision_layer = 0
		for b in bearers:
			if int(b.cart) == i:
				_set_lit(b, false)
				(b.node as Node3D).visible = false
				(b.use as Examine).collision_layer = 0


## 风把兵手里的火把吹灭；灭了的过一会儿自己续上
func _wind(delta: float) -> void:
	for b in bearers:
		if carts[int(b.cart)].state == "lost" or not (b.node as Node3D).visible:
			continue
		if b.lit:
			if windy and rng.randf() < BLOW * delta:
				_set_lit(b, false)
				print("IC_ESCORT blow cart=%d" % int(b.cart))
		elif clock - float(b.out_t) >= RELIGHT_SELF:
			_set_lit(b, true)


func _blocked(i: int) -> bool:
	if crowd == null:
		return false
	var a := ConvoyAmbush.leg_point(float(carts[i].t) + BLOCK_AHEAD, 0.4)
	var front := Vector2(a.x, a.z)
	for ag in crowd.agents:
		if not ag.done and (ag.p as Vector2).distance_to(front) < BLOCK_R:
			return true
	return false


## 车夫慌不慌：两边的火都灭了（或者近处没有别的火）、长眠者又在跟前
func _panic(i: int, delta: float, fires: Array) -> void:
	var c: Dictionary = carts[i]
	var xz := cart_xz(i)
	var near := false
	if crowd:
		for ag in crowd.agents:
			if not ag.done and (ag.p as Vector2).distance_to(xz) < PANIC_R:
				near = true
				break
	var safe := false
	for f in fires:
		if (f[0] as Vector2).distance_to(xz) < SAFE_R:
			safe = true
			break
	if near and not safe:
		c.panic = minf(float(c.panic) + delta / PANIC_TIME, 1.0)
	else:
		c.panic = maxf(float(c.panic) - delta * CALM_DECAY, 0.0)
	if float(c.panic) >= 0.5 and not bool(c.said):
		c.said = true
		note.emit(PANIC_NOTE % NUM[i])
	if float(c.panic) < 0.2:
		c.said = false
	if float(c.panic) >= 1.0:
		_abandon(i)


func _abandon(i: int) -> void:
	var c: Dictionary = carts[i]
	c.state = "lost"
	c.flee_t = 0.0
	c.off = LOST_OFF                                   # 没人拉，车歪到下坡一侧的路肩上（后面的车过得去）
	_place(i)
	for b in bearers:
		if int(b.cart) == i:
			_set_lit(b, false)
			if b.model:
				(b.model as Node3D).visible = false          # 车丢了：两个兵跟着往回撤（不画了）
	for m in c.guards:
		if m:
			(m as CharacterModel).play_loop("idle")
	var carter: CharacterModel = c.carter
	if carter:
		var gp := carter.global_position
		carter.reparent(self)
		carter.global_position = gp
		carter.rotation.y = ConvoyAmbush._yaw(-ConvoyAmbush.ahead()) + PI
		if carter.loaded:
			carter.play_loop("run")
	note.emit(FLEE_NOTE % NUM[i])
	print("IC_ESCORT lost i=%d" % i)


## 扔下车的车夫往山下跑，跑远了不见
func _flee(c: Dictionary, delta: float) -> void:
	var carter: CharacterModel = c.carter
	if carter == null or not carter.visible:
		return
	c.flee_t = float(c.flee_t) + delta
	var t := ConvoyAmbush.t_of(carter.global_position) - 3.2 * delta
	carter.global_position = ConvoyAmbush.leg_point(t, 1.6)
	if float(c.flee_t) > 9.0:
		carter.visible = false


## 第二次潮水：同劫粮那一夜，从北边山脊上横穿山路
func _start_tide() -> void:
	tide_started = true
	var n := ConvoyAmbush.TIDE_COUNT_LIT18 if Beacon18.lit() else ConvoyAmbush.TIDE_COUNT
	var side := ConvoyAmbush.ahead().cross(Vector3.UP).normalized() * ConvoyAmbush._downhill()
	var mid := ConvoyAmbush.leg_point(ConvoyAmbush.TIDE_T, 0.0)
	var route := []
	for k: float in [-TIDE_FROM, -10.0, 0.0, 16.0, 46.0]:
		var p := mid + side * k
		route.append(Vector2(p.x, p.z))
	crowd = SleeperCrowd.make(route, n, 7.0)
	crowd.height_fn = Highland.height_at
	crowd.player = player
	crowd.speed_base = 0.95
	crowd.near_cap = NEAR_CAP
	add_child(crowd)
	note.emit("◆ 北边山脊上下来一串白影子——潮水横穿山路！火把护着车，一辆一辆过。")
	print("IC_ESCORT tide count=%d" % n)


## 一盏实时光源（中、高画质）：跟着离你最近、火还亮着的那辆车
func _light() -> void:
	if not light.visible or player == null:
		return
	var best := -1
	var bd := INF
	for i in CARTS:
		if carts[i].state == "lost":
			continue
		var d := cart_xz(i).distance_to(Vector2(player.global_position.x, player.global_position.z))
		if d < bd and bearers.any(func(b): return int(b.cart) == i and b.lit):
			bd = d
			best = i
	if best < 0:
		light.light_energy = 0.0
		return
	var p := ConvoyAmbush.leg_point(float(carts[best].t), 0.4)
	light.global_position = p + Vector3(0, 2.2, 0)
	var t := clock
	light.light_energy = 1.4 * (1.0 + (0.0 if Settings.reduced_motion else sin(t * 8.3) * 0.06 + sin(t * 17.9) * 0.04))


## 对着车按 E：车夫慌了就稳住他；不然从油罐续火把（手里没有就拿一支点着的）
func _use_cart(who: FpController, i: int) -> Dictionary:
	var c: Dictionary = carts[i]
	if c.state == "lost":
		return {"kind": "escort", "toast": "车夫跑了，这车粮推不动了。"}
	if float(c.panic) > 0.3:
		c.panic = 0.0
		c.said = false
		return {"kind": "escort", "name": "粮车", "speech": "你按住车夫的肩膀：「看着火，别看它们。跟着火走。」他咬着牙点了点头。"}
	var hand: TorchHand = who.torch if who else null
	if hand == null:
		return {}
	if hand.lit() and hand.fuel > TorchHand.FUEL * 0.8:
		return {"kind": "escort", "toast": "火把还旺着。"}
	hand.take_from_ground(TorchHand.FUEL)
	return {"kind": "escort", "name": "粮车", "toast": "从车上的油罐里蘸了油，火把点着了。"}


## 对着举火把的兵按 E：你手里的火把亮着就帮他点上
func _use_bearer(who: FpController, k: int) -> Dictionary:
	var b: Dictionary = bearers[k]
	if b.lit:
		return {"kind": "escort", "toast": "他的火把亮着。"}
	var hand: TorchHand = who.torch if who else null
	if hand == null or not hand.lit():
		return {"kind": "escort", "toast": "得拿着点着的火把才能帮他点——车上有油罐。"}
	_set_lit(b, true)
	return {"kind": "escort", "name": "烽誓团的兵", "toast": "火把点着了。"}


## 走完了：送上山的车数 → 结果
func finish_run() -> void:
	if state == DONE:
		return
	state = DONE
	var n := through()
	result = "delivered" if n >= 2 else ("partial" if n == 1 else "lost")
	print("IC_ESCORT end through=%d lost=%d result=%s" % [n, lost(), result])
	ended.emit(result)


## 写旗标、声望、推进主线；返回给玩家看的一句话
static func finish(res: String, carts_through := -1) -> String:
	GameState.set_flag("ch2_convoy", res)
	var req := GameState.has_flag("ch2_requisition")
	match res:
		"delivered", "partial":
			GameState.change_rep("lomond", 5)
			GameState.change_rep("beacon_oath", 10)
			if req and res == "delivered":
				GameState.change_rep("eld", 5)
		_:
			GameState.change_rep("lomond", -5)
			if req:
				GameState.change_rep("eld", -5)
	Chapter2.dawn()                                           # 火亮不亮（ch2_fire）、主线「天亮以后」（5.8）
	match res:
		"delivered":
			return "✓ %s车粮翻过了山脊。安塞尔姆在后头数车，没说话，冲你点了一下头。天快亮了。" % (NUM[carts_through - 1] if carts_through >= 1 and carts_through <= 3 else "两")
		"partial":
			return "✓ 只有一车粮翻过了山脊。另外的扔在半路上，雪已经盖了一层。天快亮了。"
	return "× 一车也没上来。车夫都跑了，粮车扔在潮水走过的路上。天快亮了。"
