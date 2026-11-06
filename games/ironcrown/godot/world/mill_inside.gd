class_name MillInside
extends RefCounted
## 磨坊里面（路线图 6.3b；STORY.md 6.2「磨坊里面（磨盘、粮袋、账房小间）」；6.5 第 7 步「塞缪尔的粮仓账本」）：原创布局。
## 屋里 9.4 × 7.4 米、4.2 米高：石砌底层、木梁、一道木梯上阁楼（只做样子）。
##   西墙那头是两副磨盘（下扇不动、上扇压着，上面一个木斗往里漏麦子），旁边一个立着的大木齿轮——轴从墙外的水轮穿进来，慢慢转；
##   满屋子码着面粉袋、麦子袋（一直码到梁下），东北角用木板隔出一个账房小间：一张斜面桌、一盏油灯、一摞账本——
##   塞缪尔的账（6.8 的罪证）；墙上钉着一张写满名字和数字的单子。
## 室内的光不跟时段走；窗玻璃按时段换颜色（Inn.glass）。坐标：原点在屋里地面中心，北 = -Z；出口门在南墙（z = +3.7），出去站在磨坊门外（plain 的出生点 mill_door）。

const W := 9.4
const D := 7.4
const H := 4.2
const WALL_T := 0.4
const DOOR_X := 1.5
const DOOR_W := 1.3
const EXIT_NAME := "回到院子里"
const WINDOWS := [-2.6]
const WIN_W := 0.7
const WIN_Y := 2.0
const WIN_H := 0.8
const STONES := [Vector3(-3.0, 0, -1.6), Vector3(-3.0, 0, 1.4)]
const GEAR := Vector3(-4.2, 2.0, 0.0)
const OFFICE := Rect2(2.2, -3.7, 2.5, 2.6)               # 东北角的账房小间
const LEDGER_DESK := Vector3(3.5, 0, -3.0)
const LEDGER_CHEST := Vector3(4.25, 0, -1.75)             # 账房里东南角那口铁皮箱（6.5）：往年的账锁在里头——谁交了、谁欠着、谁死了
const LEDGER_TEXT := "（往年的账，一年一本，最上头那本是去年的。翻到腊月——）\n「腊月十九，麦渡东头，老科尔，欠租一袋。殁。」\n「腊月廿三，麦渡西头，鲁本，欠租两袋半。殁。账转其妻伊达，开春补。」\n「正月初四，麦渡西头，孩子一个（未记名），殁。」\n最后一页：「仓存，上等麦一千四百一十袋。」——字迹是同一个人的，一笔不乱。"
const SPAWNS := {
	"front": [Vector3(DOOR_X, 0, 2.9), 0.0],
}
const VIEW_NAMES := ["进门看磨坊", "磨盘和木齿轮", "账房小间"]
const VIEWS := [
	[Vector3(DOOR_X, 0, 2.9), 25.0, -6.0],
	[Vector3(-0.6, 0, 0.6), 90.0, -8.0],
	[Vector3(1.6, 0, 0.6), -35.0, -10.0],
]


static func build(parent: Node3D, reduced_motion := false) -> Transform3D:
	var kit := MeshKit.new()
	_room(kit)
	_stones(kit)
	_sacks(kit)
	_office(kit)
	var mi := kit.build({"stone": Look.mat("stone"), "floor": Look.mat("timber"), "timber": Look.mat("timber"), "glass": Inn.glass(GameState.daypart),
		"millstone": _millstone(), "flour": _sack("d8d0c0"), "grain": _sack("9a8a62"), "dust": _sack("e8e2d4"), "cloth": Inn._cloth_mat(), "ink": Inn._unshaded(Color("2a1e14")), "iron": Inn._iron_mat()})
	mi.name = "MillInside"
	parent.add_child(mi)
	var gear := _gear(reduced_motion)
	parent.add_child(gear)
	_decor(parent, reduced_motion)
	_colliders(parent)
	_lights(parent, reduced_motion)
	_ledger_chest(parent)
	var exit := Door.make(EXIT_NAME, DOOR_W, 2.2, false)
	exit.verb = "离开"
	exit.to_area = "plain"
	exit.to_spawn = "mill_door"
	exit.position = Vector3(DOOR_X - DOOR_W * 0.5, 0, D * 0.5 - 0.02)
	parent.add_child(exit)
	var s: Array = SPAWNS.front
	return Transform3D(Basis(Vector3.UP, deg_to_rad(float(s[1]))), s[0])


static func map_spec() -> Dictionary:
	var shapes := [
		{"k": "furniture", "rect": OFFICE, "label": "账房"},
		{"k": "furniture", "rect": Rect2(-4.0, -2.6, 2.0, 5.2), "label": "磨盘"},
		{"k": "furniture", "rect": Rect2(-1.0, -3.6, 2.8, 1.0), "label": "粮袋"},
		{"k": "furniture", "rect": Rect2(3.2, 0.6, 1.4, 2.6), "label": "粮袋"},
	]
	return {
		"bounds": Rect2(-W * 0.5, -D * 0.5, W, D),
		"shapes": shapes,
		"exits": [{"at": Vector2(DOOR_X, D * 0.5), "dir": Vector2(0, 1), "to": "plain", "spawn": "mill_door", "name": EXIT_NAME}],
	}


static func _room(kit: MeshKit) -> void:
	var hw := W * 0.5
	var hd := D * 0.5
	kit.box("floor", Vector3(0, -0.05, 0), Vector3(W, 0.1, D), Basis.IDENTITY, 0.7, 0.7)
	kit.box("timber", Vector3(0, H + 0.05, 0), Vector3(W, 0.1, D), Basis.IDENTITY, 0.35, 0.35, true)
	for x in [-3.0, -1.0, 1.0, 3.0]:
		kit.box("timber", Vector3(x, H - 0.18, 0), Vector3(0.3, 0.36, D), Basis.IDENTITY, 0.5, 0.4)
	kit.box("stone", Vector3(0, H * 0.5, -hd - WALL_T * 0.5), Vector3(W + WALL_T * 2, H, WALL_T), Basis.IDENTITY, 0.75, 0.5)
	kit.box("stone", Vector3(hw + WALL_T * 0.5, H * 0.5, 0), Vector3(WALL_T, H, D), Basis.IDENTITY, 0.75, 0.5)
	kit.box("stone", Vector3(-hw - WALL_T * 0.5, H * 0.5, 0), Vector3(WALL_T, H, D), Basis.IDENTITY, 0.75, 0.5)
	var zs := hd + WALL_T * 0.5
	var cuts := [[DOOR_X - DOOR_W * 0.5, DOOR_X + DOOR_W * 0.5]]
	for wx: float in WINDOWS:
		cuts.append([wx - WIN_W * 0.5, wx + WIN_W * 0.5])
	cuts.sort_custom(func(a, b): return a[0] < b[0])
	var x0 := -hw - WALL_T
	for c in cuts:
		var a: float = c[0]
		if a > x0:
			kit.box("stone", Vector3((x0 + a) * 0.5, H * 0.5, zs), Vector3(a - x0, H, WALL_T), Basis.IDENTITY, 0.75, 0.5)
		x0 = c[1]
	kit.box("stone", Vector3((x0 + hw + WALL_T) * 0.5, H * 0.5, zs), Vector3(hw + WALL_T - x0, H, WALL_T), Basis.IDENTITY, 0.75, 0.5)
	for wx: float in WINDOWS:
		var sill := WIN_Y - WIN_H * 0.5
		var head := WIN_Y + WIN_H * 0.5
		kit.box("stone", Vector3(wx, sill * 0.5, zs), Vector3(WIN_W, sill, WALL_T), Basis.IDENTITY, 0.7, 0.5)
		kit.box("stone", Vector3(wx, (head + H) * 0.5, zs), Vector3(WIN_W, H - head, WALL_T), Basis.IDENTITY, 0.75, 0.6)
		kit.box("glass", Vector3(wx, WIN_Y, zs + 0.06), Vector3(WIN_W, WIN_H, 0.04))
	kit.box("stone", Vector3(DOOR_X, (2.2 + H) * 0.5, zs), Vector3(DOOR_W, H - 2.2, WALL_T), Basis.IDENTITY, 0.75, 0.6)
	kit.box("timber", Vector3(DOOR_X, 2.28, zs - 0.12), Vector3(DOOR_W + 0.4, 0.16, 0.16))
	for k in 9:                                                       # 木梯上阁楼（只做样子）
		var t := float(k) / 8.0
		kit.box("timber", Vector3(hw - 0.6, 0.25 + t * (H - 0.6), 2.6 - t * 2.4), Vector3(0.9, 0.06, 0.28), Basis.IDENTITY, 0.85, 0.6)
	for s in [-0.47, 0.47]:
		kit.box("timber", Vector3(hw - 0.6 + s, H * 0.5, 1.4), Vector3(0.07, 0.07, 3.6), Basis(Vector3.RIGHT, -atan2(H - 0.6, 2.4) + PI * 0.5) * Basis.IDENTITY, 0.8, 0.6)


## 两副磨盘（石墩上：下扇、上扇，上扇上方一个木斗）
static func _stones(kit: MeshKit) -> void:
	for c: Vector3 in STONES:
		kit.box("timber", c + Vector3(0, 0.35, 0), Vector3(1.6, 0.7, 1.6), Basis.IDENTITY, 0.7, 0.5)
		kit.cylinder("millstone", c + Vector3(0, 0.7, 0), c + Vector3(0, 0.92, 0), 0.68, 0.68, 14)
		kit.cylinder("millstone", c + Vector3(0, 0.94, 0), c + Vector3(0, 1.16, 0), 0.66, 0.66, 14)
		kit.cylinder("dust", c + Vector3(0, 0.71, 0), c + Vector3(0, 0.715, 0), 0.8, 0.8, 14)                    # 撒了一圈面粉
		kit.cylinder("timber", c + Vector3(0, 1.5, 0), c + Vector3(0, 1.95, 0), 0.12, 0.45, 4)                   # 木斗
		kit.box("timber", c + Vector3(0, 1.75, 0), Vector3(0.08, 0.6, 0.08), Basis.IDENTITY, 0.8, 0.6)
		kit.cylinder("timber", c + Vector3(0, 1.16, 0), c + Vector3(0, H - 0.35, 0), 0.08, 0.08, 6)             # 立轴


## 码到梁下的面粉袋、麦子袋
static func _sacks(kit: MeshKit) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 6303
	for area: Array in [[Rect2(-1.0, -3.6, 2.8, 1.0), 6], [Rect2(3.2, 0.6, 1.4, 2.6), 5], [Rect2(-1.4, 2.4, 1.6, 1.0), 3]]:
		var r: Rect2 = area[0]
		var layers := int(area[1])
		for ly in layers:
			var x := r.position.x + 0.3
			while x < r.end.x - 0.2:
				var z := r.position.y + 0.25
				while z < r.end.y - 0.1:
					var key := "flour" if rng.randf() < 0.55 else "grain"
					kit.box(key, Vector3(x + rng.randf_range(-0.05, 0.05), 0.17 + ly * 0.32, z), Vector3(0.55, 0.32, 0.4), Basis(Vector3.UP, rng.randf_range(-0.2, 0.2)), 1.0, 0.7)
					z += 0.45
				x += 0.6


## 账箱（支线「账本上的名字」，6.5）：钥匙在塞缪尔那儿（说动他，ch3_ledger_key），没钥匙就撬（潜行 13，一次定）；
## 打开了翻到鲁本那一行（ch3_ledger_read、线索 ledger_reuben），支线到「回去告诉伊达」
static func _ledger_chest(parent: Node3D) -> void:
	var kit := MeshKit.new()
	var c := LEDGER_CHEST
	kit.box("timber", c + Vector3(0, 0.28, 0), Vector3(0.8, 0.56, 0.5), Basis(Vector3.UP, 0.1), 0.95, 0.6)
	for y in [0.08, 0.5]:
		kit.box("iron", c + Vector3(0, y, 0), Vector3(0.82, 0.05, 0.52), Basis(Vector3.UP, 0.1))
	kit.box("iron", c + Vector3(-0.02, 0.42, 0.26), Vector3(0.1, 0.12, 0.03), Basis(Vector3.UP, 0.1))     # 锁
	var mi := kit.build({"timber": Look.mat("timber"), "iron": Inn._iron_mat()})
	mi.name = "LedgerChest"
	parent.add_child(mi)
	Inn._solid(parent, c + Vector3(0, 0.28, 0), Vector3(0.8, 0.56, 0.5))
	var e := Examine.make("铁皮账箱", "打开", func(_who: FpController) -> Dictionary: return open_ledger(), Vector3(0.9, 0.8, 0.7))
	e.name = "LedgerChestOpen"
	e.position = c
	e.verb_fn = func() -> String: return ("拿走账本" if ledger_takeable() and not GameState.has_item("granary_ledger") else "看看") if str(GameState.get_flag("ch3_mill", "")) != "" else ("翻账" if GameState.has_flag("ch3_ledger_open") else ("开锁" if GameState.has_flag("ch3_ledger_key") else "撬锁"))
	parent.add_child(e)


## 打完以后（6.8a）：守住了、抢到了、或者开过仓的，账本能拿走（罪证）；失守了的，账箱被砸开、空了
static func ledger_takeable() -> bool:
	var m := str(GameState.get_flag("ch3_mill", ""))
	return m in ["held", "seized"] or (m != "" and GameState.has_flag("ch3_granary_opened"))


static func open_ledger() -> Dictionary:
	var m := str(GameState.get_flag("ch3_mill", ""))
	if m != "":
		if GameState.has_item("granary_ledger") or GameState.has_flag("ch3_ledger_taken"):
			return {"toast": "账箱空了。"}
		if not ledger_takeable():
			return {"toast": "账箱被砸开了，锁扣歪在一边——里头空了。塞弗林家的人连账一起扛走了。"}
		GameState.add_item("granary_ledger")
		GameState.set_flag("ch3_ledger_taken")
		GameState.set_flag("ch3_ledger_read")
		return {"toast": "夜里没人顾得上这间屋子。你把最上头那本账抽出来，揣进怀里——塞缪尔的账，一年一本，去年那本记到腊月。（得到：洛蒙德家的粮仓账本）"}
	if not GameState.has_flag("ch3_ledger_open"):
		if GameState.has_flag("ch3_ledger_key"):
			GameState.set_flag("ch3_ledger_open")
		elif GameState.check("ch3_ledger_pick", "stealth", 13):
			GameState.set_flag("ch3_ledger_open")
			GameState.set_flag("ch3_ledger_picked")
		else:
			return {"toast": "锁簧咬得死死的，撬了几下纹丝不动。（潜行 13 没过）钥匙在塞缪尔那儿。"}
	GameState.set_flag("ch3_ledger_read")
	if GameState.quest_stage("ch3_ida") == "find":
		GameState.add_clue("ledger_reuben")
		GameState.set_stage("ch3_ida", "tell")
	return {"toast": LEDGER_TEXT}


## 东北角的账房小间：木板隔墙、斜面桌上摊着账本、一摞账本、墨水壶；墙上钉着一张单子
static func _office(kit: MeshKit) -> void:
	var o := OFFICE
	kit.box("timber", Vector3(o.position.x, 0.75, o.get_center().y + 0.3), Vector3(0.08, 1.5, o.size.y - 0.6), Basis.IDENTITY, 1.0, 0.7)     # 西边隔板（齐胸高，留门；2.2 米高时像两块黑板，截图）
	kit.box("timber", Vector3(o.get_center().x + 0.5, 0.75, o.end.y), Vector3(o.size.x - 1.0, 1.5, 0.08), Basis.IDENTITY, 1.0, 0.7)          # 南边隔板（西头留门）
	var d := LEDGER_DESK
	kit.box("timber", d + Vector3(0, 0.95, 0), Vector3(1.2, 0.06, 0.7), Basis(Vector3.RIGHT, -0.2), 1.0, 0.8)
	for lx in [-0.5, 0.5]:
		kit.box("timber", d + Vector3(lx, 0.47, 0.05), Vector3(0.07, 0.94, 0.55), Basis.IDENTITY, 0.8, 0.5)
	kit.box("cloth", d + Vector3(0, 1.0, 0.02), Vector3(0.6, 0.02, 0.42), Basis(Vector3.RIGHT, -0.2))                                         # 摊开的账
	for r in 6:
		kit.box("ink", d + Vector3(-0.12, 1.012, -0.14 + r * 0.055), Vector3(0.24, 0.003, 0.01), Basis(Vector3.RIGHT, -0.2))
		kit.box("ink", d + Vector3(0.17, 1.012, -0.14 + r * 0.055), Vector3(0.12, 0.003, 0.01), Basis(Vector3.RIGHT, -0.2))
	for k in 5:                                                                                                                                 # 一摞账本
		kit.box("timber", d + Vector3(0.75, 0.5 + k * 0.07, -0.1), Vector3(0.32, 0.06, 0.42), Basis(Vector3.UP, 0.05 * k), 0.6, 0.6)
	kit.box("timber", d + Vector3(0.75, 0.24, -0.1), Vector3(0.4, 0.48, 0.5), Basis.IDENTITY, 0.7, 0.5)
	kit.cylinder("ink", d + Vector3(-0.45, 1.0, -0.25), d + Vector3(-0.45, 1.07, -0.25), 0.035, 0.03, 6)
	kit.box("cloth", Vector3(o.end.x - 0.02, 1.6, o.get_center().y - 0.3), Vector3(0.02, 0.7, 0.5))                                         # 墙上的单子：名字和数字
	for r in 8:
		kit.box("ink", Vector3(o.end.x - 0.035, 1.88 - r * 0.075, o.get_center().y - 0.3), Vector3(0.005, 0.012, 0.36))


## 立着的大木齿轮：轴从西墙外的水轮穿进来，慢慢转
static func _gear(reduced_motion: bool) -> Node3D:
	var k := MeshKit.new()
	var r := 1.6
	for i in 20:
		var t0 := TAU * i / 20.0
		var t1 := TAU * (i + 1) / 20.0
		k.cylinder("timber", Vector3(0, sin(t0) * r, cos(t0) * r), Vector3(0, sin(t1) * r, cos(t1) * r), 0.09, 0.09, 4)
		k.box("timber", Vector3(0.12, sin(t0) * (r + 0.12), cos(t0) * (r + 0.12)), Vector3(0.14, 0.12, 0.12), Basis(Vector3.RIGHT, t0), 0.8, 0.6)
	for i in 6:
		var t := TAU * i / 6.0
		k.cylinder("timber", Vector3.ZERO, Vector3(0, sin(t) * r, cos(t) * r), 0.08, 0.07, 4)
	k.cylinder("timber", Vector3(-0.6, 0, 0), Vector3(0.3, 0, 0), 0.22, 0.22, 8)
	var mi := k.build({"timber": Look.mat("timber")})
	var spin := PlainMill.MillWheel.new()
	spin.name = "Gear"
	spin.position = GEAR
	spin.speed = 0.0 if reduced_motion else 0.12
	spin.add_child(mi)
	return spin


static func _decor(parent: Node3D, reduced_motion := false) -> void:
	var d := Decor.new()
	d.sconce(Vector3(-W * 0.5 + 0.02, 2.2, 2.4), Vector3.RIGHT, false)
	d.candles(LEDGER_DESK + Vector3(-0.4, 1.02, 0.18), 1)
	d.barrel(Vector3(0.4, 0, 3.0))
	d.crate(Vector3(-0.2, 0, 1.4), 0.3)
	d.build(parent, "Decor", not reduced_motion)


static func _colliders(parent: Node3D) -> void:
	var hw := W * 0.5
	var hd := D * 0.5
	Inn._solid(parent, Vector3(0, -0.1, 0), Vector3(W + 1, 0.2, D + 1))
	Inn._solid(parent, Vector3(0, H + 0.1, 0), Vector3(W + 1, 0.2, D + 1))
	Inn._solid(parent, Vector3(0, H * 0.5, -hd - WALL_T * 0.5), Vector3(W + 1, H, WALL_T))
	Inn._solid(parent, Vector3(hw + WALL_T * 0.5, H * 0.5, 0), Vector3(WALL_T, H, D + 1))
	Inn._solid(parent, Vector3(-hw - WALL_T * 0.5, H * 0.5, 0), Vector3(WALL_T, H, D + 1))
	var zs := hd + WALL_T * 0.5
	var dl := DOOR_X - DOOR_W * 0.5
	var dr := DOOR_X + DOOR_W * 0.5
	Inn._solid(parent, Vector3((-hw + dl) * 0.5, H * 0.5, zs), Vector3(dl + hw, H, WALL_T))
	Inn._solid(parent, Vector3((dr + hw) * 0.5, H * 0.5, zs), Vector3(hw - dr, H, WALL_T))
	Inn._solid(parent, Vector3(DOOR_X, H * 0.5, zs + 0.15), Vector3(DOOR_W, H, 0.1))
	for c: Vector3 in STONES:
		Inn._solid(parent, c + Vector3(0, 0.8, 0), Vector3(1.7, 1.6, 1.7))
	Inn._solid(parent, GEAR, Vector3(1.0, 3.6, 3.6))
	for r: Rect2 in [Rect2(-1.0, -3.6, 2.8, 1.0), Rect2(3.2, 0.6, 1.4, 2.6), Rect2(-1.4, 2.4, 1.6, 1.0)]:
		Inn._solid(parent, Vector3(r.get_center().x, 1.0, r.get_center().y), Vector3(r.size.x, 2.0, r.size.y))
	Inn._solid(parent, Vector3(OFFICE.position.x, 0.75, OFFICE.get_center().y + 0.3), Vector3(0.1, 1.5, OFFICE.size.y - 0.6))
	Inn._solid(parent, Vector3(OFFICE.get_center().x + 0.5, 0.75, OFFICE.end.y), Vector3(OFFICE.size.x - 1.0, 1.5, 0.1))
	Inn._solid(parent, LEDGER_DESK + Vector3(0.2, 0.5, 0), Vector3(1.6, 1.0, 0.75))
	Inn._solid(parent, Vector3(W * 0.5 - 0.6, 1.2, 1.4), Vector3(1.0, 2.4, 3.0))


## 光：账房桌上一盏油灯（暖）、屋里一盏挂灯、窗外的天光
static func _lights(parent: Node3D, reduced_motion: bool) -> void:
	var lamp := Tavern.FireLight.new()
	lamp.name = "LedgerLamp"
	lamp.light_color = Color("ffb060")
	lamp.base = 1.3
	lamp.omni_range = 4.5
	lamp.position = LEDGER_DESK + Vector3(-0.4, 1.4, 0.18)
	lamp.flicker = not reduced_motion
	lamp.add_to_group("light_source")
	lamp.set_meta("radius", 3.0)
	parent.add_child(lamp)
	var hang := OmniLight3D.new()
	hang.name = "HangLamp"
	hang.light_color = Look.LAMP_COLOR
	hang.light_energy = 2.6                           # 截图：屋里太暗
	hang.omni_range = 10.0
	hang.position = Vector3(-0.8, 3.2, 0.0)
	parent.add_child(hang)
	var fill := OmniLight3D.new()
	fill.light_color = Color("9aa4b4")
	fill.light_energy = 1.3
	fill.omni_range = 10.0
	fill.position = Vector3(-2.6, 2.6, 2.6)
	parent.add_child(fill)


static func _sack(hex: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(hex)
	m.roughness = 1.0
	m.vertex_color_use_as_albedo = true
	return m


static func _millstone() -> StandardMaterial3D:
	var m := Look.mat("stone").duplicate() as StandardMaterial3D
	m.albedo_color = Color(0.82, 0.8, 0.76)
	return m
