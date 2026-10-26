class_name BeaconTower
extends RefCounted
## 第十九烽塔里（路线图 5.3b；STORY.md 5.2「烽燧塔里面（螺旋石梯、存柴的底层、诺伯特住的顶层小屋）」）：原创布局。
## 塔外面 6.4 米见方（HighlandLayout.TOWER_W），墙 0.8 米厚，里面 4.8 米见方：
##   底层（存柴）：石板地，东墙下一小垛柴（缺柴：柴架大半是空的），东北角两桶烧火盆用的油，东南角一捆备用的火把；顶上吊着一盏风灯（底层唯一的光）。
##   石梯：贴着西墙往北爬、到西北角拐弯贴着北墙往东，一级级从墙里挑出来的石阶，上到 4.2 米的楼板；楼板上石梯那一圈有木栏杆。
##   顶层（诺伯特的小屋）：木板地，东墙下一张窄床（毛皮褥子）、床头一只箱子，西边一张小桌一只凳子（桌上一支蜡烛），一只小铁炉里几块炭（缺柴，只够暖手）；
##   北墙上挂着一只断了的号角（断角烽）；东南角一架木梯通到塔顶的天窗（「爬上塔顶」→ 余火高地 beacon_top）。
## 坐标：原点在底层地面中心，北 = -Z；出口门在南墙（z = +2.4），和外面塔门同一面（HighlandBeacon：门朝塔的本地 +Z）。
## 室内的光不跟时段走；箭窗按时段换颜色（Inn.glass）。

const TORCH_PICKUP := "beacon19_torches"
const IN := 4.8
const UPPER := 4.2                   # 顶层楼板的高度
const UPPER_H := 3.2                 # 顶层小屋的高
const FLOOR_T := 0.2
const WALL_T := 0.8
const DOOR_W := 1.1
const EXIT_NAME := "回到营地"
const LADDER_NAME := "木梯（爬上塔顶）"
const RISE := 0.25
const RUN1 := 12                     # 贴西墙那一段：12 级到拐角的平台（3.0 米）
const RUN1_Z0 := 2.15                # 第一级在哪（往北爬）
const RUN1_Z1 := -1.5
const STAIR_W := 0.9
const RUN2 := 4                      # 贴北墙那一段：4 级到 4.0 米，再一步上楼板
const TREAD2 := 0.32
const LADDER_X := 1.1                # 木梯（东南角，靠南墙）
const HORN_POS := Vector3(0.7, UPPER + 1.7, -IN * 0.5 + 0.05)
## 命名出生点：front = 刚进门、面朝北；top = 从天窗下来，站在木梯脚下
const SPAWNS := {
	"front": [Vector3(0.0, 0, 1.7), 0.0],
	"top": [Vector3(1.0, UPPER, 1.2), 30.0],
}
const VIEW_NAMES := ["进门看底层", "石梯", "诺伯特的小屋", "门内对着出口", "木梯和天窗"]
const VIEWS := [
	[Vector3(0.3, 0, 1.9), 8.0, -4.0],
	[Vector3(0.6, 0, 1.3), 62.0, 18.0],
	[Vector3(-0.8, UPPER, 1.8), -42.0, -10.0],
	[Vector3(0.0, 0, 0.2), 180.0, -8.0],
	[Vector3(0.2, UPPER, -0.6), -155.0, 22.0],
]


static func build(parent: Node3D, reduced_motion := false) -> Transform3D:
	var kit := MeshKit.new()
	_room(kit)
	_stairs(kit)
	_furniture(kit)
	var mi := kit.build({"stone": Look.mat("stone"), "floor": Look.mat("street"), "timber": Look.mat("timber"), "glass": Inn.glass(GameState.daypart),
		"iron": Inn._iron_mat(), "cloth": Inn._cloth_mat(), "fur": _fur_mat(), "horn": _horn_mat(), "ember": Inn._unshaded(Color("ff6a24")),
		"oil": _oil_mat(), "dark_hatch": Inn._unshaded(Color("1a1410"))})
	mi.name = "BeaconTowerInside"
	parent.add_child(mi)
	_decor(parent, reduced_motion)
	_colliders(parent)
	_lights(parent, reduced_motion)
	var exit := Door.make(EXIT_NAME, DOOR_W, 2.1, false)
	exit.verb = "离开"
	exit.to_area = "highland"
	exit.to_spawn = "beacon_door"
	exit.position = Vector3(-DOOR_W * 0.5, 0, IN * 0.5 - 0.02)
	parent.add_child(exit)
	var ladder := Door.make(LADDER_NAME, 0.8, 2.2, false)
	ladder.name = "Ladder"
	ladder.verb = "爬上去"
	ladder.panel = false
	ladder.to_area = "highland"
	ladder.to_spawn = "beacon_top"
	ladder.position = Vector3(LADDER_X, UPPER, IN * 0.5 - 0.3)
	parent.add_child(ladder)
	var s: Array = SPAWNS.front
	return Transform3D(Basis(Vector3.UP, deg_to_rad(float(s[1]))), s[0])


static func map_spec() -> Dictionary:
	var h := IN * 0.5
	var shapes := [
		{"k": "furniture", "rect": Rect2(-h, RUN1_Z1, STAIR_W, RUN1_Z0 - RUN1_Z1), "label": "石梯"},
		{"k": "furniture", "rect": Rect2(-h, -h, STAIR_W + RUN2 * TREAD2, STAIR_W)},
		{"k": "furniture", "rect": Rect2(1.6, -1.6, 0.8, 1.8), "label": "柴"},
		{"k": "furniture", "rect": Rect2(1.0, -h, 1.4, 0.8), "label": "油桶"},
		{"k": "mark", "at": Vector2(LADDER_X + 0.4, h - 0.4), "label": "木梯（楼上）"},
	]
	return {
		"bounds": Rect2(-h, -h, IN, IN),
		"shapes": shapes,
		"exits": [{"at": Vector2(0, h), "dir": Vector2(0, 1), "to": "highland", "spawn": "beacon_door", "name": EXIT_NAME}],
	}


## 顶层楼板：三块（中间留出石梯上来的口子）——[x0, z0, x1, z1]
static func upper_floor() -> Array:
	var h := IN * 0.5
	var x2 := -h + STAIR_W + RUN2 * TREAD2          # 北墙那段石梯的东头
	return [
		[x2, -h, h, h],                             # 东半边
		[-h + STAIR_W, -h + STAIR_W, x2, h],        # 中间（石梯北头和拐角那段的南边）
		[-h, 0.4, -h + STAIR_W, h],                 # 西南角（石梯低的那头上面）
	]


## 石阶：[[顶面中心, 尺寸]]——贴西墙那段从地上垒起来（实心），拐角的平台和贴北墙那段从墙里挑出来（一块块石板）
static func steps() -> Array:
	var h := IN * 0.5
	var out := []
	var tread := (RUN1_Z0 - RUN1_Z1) / RUN1
	for k in RUN1:
		var top := RISE * (k + 1)
		var z := RUN1_Z0 - tread * (k + 0.5)
		out.append([Vector3(-h + STAIR_W * 0.5, top, z), Vector3(STAIR_W, top, tread + 0.02), true])
	var land := RISE * RUN1
	out.append([Vector3(-h + STAIR_W * 0.5, land, -h + STAIR_W * 0.5), Vector3(STAIR_W, 0.3, STAIR_W), false])
	for k in RUN2:
		var top := land + RISE * (k + 1)
		out.append([Vector3(-h + STAIR_W + TREAD2 * (k + 0.5), top, -h + STAIR_W * 0.5), Vector3(TREAD2 + 0.02, 0.3, STAIR_W), false])
	return out


## 四面墙（南墙留门、两道箭窗）、底层石板地、顶层木板地（留石梯口）、顶上的木板顶（留天窗）、横梁
static func _room(kit: MeshKit) -> void:
	var h := IN * 0.5
	var top := UPPER + UPPER_H
	kit.box("floor", Vector3(0, -0.05, 0), Vector3(IN, 0.1, IN), Basis.IDENTITY, 0.75, 0.75)
	for f in upper_floor():
		var c := Vector3((f[0] + f[2]) * 0.5, UPPER - FLOOR_T * 0.5, (f[1] + f[3]) * 0.5)
		kit.box("timber", c, Vector3(f[2] - f[0], FLOOR_T, f[3] - f[1]), Basis.IDENTITY, 0.9, 0.5, true)
	for x in [-1.0, 0.6, 1.8]:                                       # 底层顶上的横梁（楼板下面）
		kit.box("timber", Vector3(x, UPPER - FLOOR_T - 0.12, 0.3), Vector3(0.22, 0.24, IN - 0.6), Basis.IDENTITY, 0.6, 0.45)
	kit.box("timber", Vector3(0, top + 0.05, 0), Vector3(IN, 0.1, IN), Basis.IDENTITY, 0.45, 0.45, true)   # 顶
	for z in [-1.2, 0.2]:
		kit.box("timber", Vector3(0, top - 0.12, z), Vector3(IN, 0.24, 0.22), Basis.IDENTITY, 0.55, 0.45)
	kit.box("dark_hatch", Vector3(LADDER_X + 0.4, top - 0.01, h - 0.55), Vector3(0.9, 0.02, 0.8))      # 天窗（从下面看是一块深色的木板，边上漏进来一点光）
	for side in 4:
		var b := Basis(Vector3.UP, side * PI * 0.5)
		if side == 0:                                                 # 南墙：门
			var seg := (IN - DOOR_W) * 0.5
			for s in [-1.0, 1.0]:
				kit.box("stone", b * Vector3(s * (DOOR_W * 0.5 + seg * 0.5), top * 0.5, h + 0.15), Vector3(seg, top, 0.3), b, 0.8, 0.5)
			kit.box("stone", b * Vector3(0, (2.2 + top) * 0.5, h + 0.15), Vector3(DOOR_W, top - 2.2, 0.3), b, 0.8, 0.6)
			kit.box("timber", b * Vector3(0, 2.26, h + 0.05), Vector3(DOOR_W + 0.3, 0.14, 0.12), b, 0.8, 0.6)
		else:
			kit.box("stone", b * Vector3(0, top * 0.5, h + 0.15), Vector3(IN + 0.6, top, 0.3), b, 0.8, 0.5)
	for slit in HighlandBeacon.SLITS:                                  # 箭窗（同外面那几道，透进来一点天光）
		var b := Basis(Vector3.UP, int(slit[0]) * PI * 0.5)
		kit.box("glass", b * Vector3(float(slit[1]), float(slit[2]), h - 0.012), Vector3(0.16, 0.9, 0.02), b)   # 贴在墙里面（放进墙的盒子里会和墙面抢深度，看着是一根根白刺）


## 石梯：石阶 + 楼板口上的木栏杆
static func _stairs(kit: MeshKit) -> void:
	for st in steps():
		var c: Vector3 = st[0]
		var s: Vector3 = st[1]
		kit.box("stone", c - Vector3(0, s.y * 0.5, 0), s, Basis.IDENTITY, 0.95, 0.55, not bool(st[2]))
	var h := IN * 0.5
	var x2 := -h + STAIR_W + RUN2 * TREAD2
	for rail in [[Vector3(-h + STAIR_W, 0, -h + STAIR_W), Vector3(-h + STAIR_W, 0, 0.4)], [Vector3(-h + STAIR_W, 0, -h + STAIR_W), Vector3(x2, 0, -h + STAIR_W)],
			[Vector3(-h, 0, 0.4), Vector3(-h + STAIR_W, 0, 0.4)]]:
		var a: Vector3 = rail[0] + Vector3(0, UPPER, 0)
		var b: Vector3 = rail[1] + Vector3(0, UPPER, 0)
		kit.cylinder("timber", a + Vector3(0, 0.95, 0), b + Vector3(0, 0.95, 0), 0.04, 0.04, 5, 0.8)
		var n := maxi(2, int(a.distance_to(b) / 0.6) + 1)
		for k in n:
			var p := a.lerp(b, float(k) / (n - 1))
			kit.cylinder("timber", p, p + Vector3(0, 0.95, 0), 0.035, 0.035, 5, 0.75)


## 底层的柴架（大半空着）、油桶；顶层的床、箱子、小桌和凳子、小铁炉、断了的号角、木梯
static func _furniture(kit: MeshKit) -> void:
	var h := IN * 0.5
	for z in [-1.6, 0.2]:                                               # 东墙下的柴架：两根立柱、两道横档
		kit.box("timber", Vector3(h - 0.3, 0.9, z), Vector3(0.1, 1.8, 0.1), Basis.IDENTITY, 0.8, 0.5)
	for y in [0.6, 1.4]:
		kit.box("timber", Vector3(h - 0.55, y, -0.7), Vector3(0.06, 0.06, 1.9), Basis.IDENTITY, 0.8, 0.6)
	for p in [Vector3(1.85, 0, -2.0), Vector3(1.25, 0, -2.05)]:          # 两桶油（烧火盆用的），桶口一圈黑油渍
		kit.cylinder("timber", p, p + Vector3(0, 0.45, 0), 0.27, 0.3, 10, 0.75)
		kit.cylinder("timber", p + Vector3(0, 0.45, 0), p + Vector3(0, 0.9, 0), 0.3, 0.27, 10, 0.85)
		kit.cylinder("oil", p + Vector3(0, 0.9, 0), p + Vector3(0, 0.92, 0), 0.25, 0.25, 10)
	var u := UPPER
	var bed := Vector3(1.85, u, -0.5)                                     # 床：木框、毛皮褥子、卷起来的枕头
	kit.box("timber", bed + Vector3(0, 0.25, 0), Vector3(0.85, 0.12, 2.0), Basis.IDENTITY, 0.85, 0.6)
	for dz in [-0.95, 0.95]:
		for dx in [-0.38, 0.38]:
			kit.box("timber", bed + Vector3(dx, 0.1, dz), Vector3(0.08, 0.2, 0.08), Basis.IDENTITY, 0.7, 0.5)
	kit.box("fur", bed + Vector3(0, 0.36, 0.1), Vector3(0.8, 0.12, 1.7), Basis(Vector3.UP, 0.03), 1.0, 0.7)
	kit.box("cloth", bed + Vector3(0, 0.4, -0.85), Vector3(0.6, 0.14, 0.25), Basis.IDENTITY, 0.9, 0.7)
	var tbl := Vector3(-0.9, u, 1.6)                                      # 小桌、凳子
	kit.box("timber", tbl + Vector3(0, 0.72, 0), Vector3(0.9, 0.06, 0.6), Basis.IDENTITY, 1.0, 0.8)
	for dx in [-0.38, 0.38]:
		for dz in [-0.24, 0.24]:
			kit.box("timber", tbl + Vector3(dx, 0.35, dz), Vector3(0.06, 0.7, 0.06), Basis.IDENTITY, 0.8, 0.5)
	kit.box("timber", tbl + Vector3(0.1, 0.42, -0.6), Vector3(0.38, 0.06, 0.38), Basis.IDENTITY, 0.9, 0.7)
	for dx in [-0.14, 0.14]:
		for dz in [-0.14, 0.14]:
			kit.box("timber", tbl + Vector3(0.1 + dx, 0.2, -0.6 + dz), Vector3(0.05, 0.4, 0.05), Basis.IDENTITY, 0.8, 0.5)
	kit.box("cloth", tbl + Vector3(-0.15, 0.76, 0.05), Vector3(0.3, 0.01, 0.22), Basis(Vector3.UP, 0.2))   # 一张旧纸
	var stove := Vector3(-0.6, u, -0.3)                                    # 小铁炉：几块炭，只够暖手
	kit.cylinder("iron", stove, stove + Vector3(0, 0.5, 0), 0.26, 0.24, 8, 0.8)
	kit.box("ember", stove + Vector3(0, 0.51, 0), Vector3(0.24, 0.03, 0.24))
	kit.cylinder("iron", stove + Vector3(0, 0.5, 0), stove + Vector3(0, UPPER_H, 0), 0.06, 0.06, 6, 0.7)   # 烟筒通到顶
	# 北墙上挂着一只断了的号角：牛角，尖那头断了，系着一根皮绳
	kit.cylinder("horn", HORN_POS + Vector3(-0.32, 0.0, 0.06), HORN_POS + Vector3(0.2, -0.1, 0.06), 0.08, 0.045, 8)
	kit.cylinder("horn", HORN_POS + Vector3(-0.32, 0.0, 0.06), HORN_POS + Vector3(-0.42, 0.04, 0.06), 0.09, 0.1, 8)
	kit.cylinder("cloth", HORN_POS + Vector3(-0.3, 0.06, 0.03), HORN_POS + Vector3(0.0, 0.25, 0.01), 0.01, 0.01, 4)
	kit.cylinder("cloth", HORN_POS + Vector3(0.0, 0.25, 0.01), HORN_POS + Vector3(0.15, -0.05, 0.03), 0.01, 0.01, 4)
	kit.box("iron", HORN_POS + Vector3(0.0, 0.27, 0.0), Vector3(0.04, 0.04, 0.06))
	# 木梯：东南角靠南墙，两根立柱、九根横档，通到顶上的天窗
	var lz := h - 0.25
	for x in [LADDER_X + 0.08, LADDER_X + 0.72]:
		kit.cylinder("timber", Vector3(x, u, lz - 0.15), Vector3(x, u + UPPER_H, lz), 0.04, 0.04, 5, 0.85)
	for k in 9:
		var y := u + 0.3 + k * 0.32
		var z := lz - 0.15 + 0.15 * (y - u) / UPPER_H
		kit.cylinder("timber", Vector3(LADDER_X + 0.08, y, z), Vector3(LADDER_X + 0.72, y, z), 0.028, 0.028, 5, 0.85)


static func _decor(parent: Node3D, reduced_motion := false) -> void:
	var d := Decor.new()
	d.woodpile(Vector3(IN * 0.5 - 0.6, 0, -0.9), Vector3(0, 0, 1), 1.2, 0.45, false)       # 柴架下面一小垛
	d.chest(Vector3(1.85, UPPER, 0.95), 0.0, Vector3(0.75, 0.45, 0.5))                        # 床头的箱子
	d.candles(Vector3(-0.75, UPPER + 0.75, 1.5), 1)
	d.build(parent, "Decor", not reduced_motion)
	_torch_bundle(parent)


## 东南角：一捆备用的火把（5.4b 起能拿：拾取得 3 支；拿走以后这捆就没了）
static func _torch_bundle(parent: Node3D) -> void:
	if GameState.picked.has(TORCH_PICKUP):
		return
	var p := Pickup.make("torch", "一捆备用的火把", Color.WHITE, Vector3(0.45, 1.1, 0.45))
	p.pickup_id = TORCH_PICKUP
	p.count = 3
	p.show_box = false
	p.position = Vector3(1.9, 0, 1.6)
	parent.add_child(p)
	var kit := MeshKit.new()
	for k in 5:
		var a := k * 0.5
		var base := Vector3(-0.05 + cos(a) * 0.08, 0, sin(a) * 0.08)
		kit.cylinder("timber", base, base + Vector3(0.18, 1.0, -0.05 + k * 0.02), 0.03, 0.025, 5, 0.8)
		kit.cylinder("cloth", base + Vector3(0.15, 0.85, -0.04 + k * 0.02), base + Vector3(0.19, 1.08, -0.05 + k * 0.02), 0.05, 0.045, 6, 0.6)
	var mi := kit.build({"timber": Look.mat("timber"), "cloth": Inn._cloth_mat()})
	mi.name = "TorchBundle"
	p.add_child(mi)


static func _colliders(parent: Node3D) -> void:
	var h := IN * 0.5
	var top := UPPER + UPPER_H
	Inn._solid(parent, Vector3(0, -0.1, 0), Vector3(IN + 1, 0.2, IN + 1))
	Inn._solid(parent, Vector3(0, top + 0.1, 0), Vector3(IN + 1, 0.2, IN + 1))
	for f in upper_floor():
		Inn._solid(parent, Vector3((f[0] + f[2]) * 0.5, UPPER - FLOOR_T * 0.5, (f[1] + f[3]) * 0.5), Vector3(f[2] - f[0], FLOOR_T, f[3] - f[1]))
	for side in [1, 2, 3]:
		var b := Basis(Vector3.UP, side * PI * 0.5)
		var c := b * Vector3(0, top * 0.5, h + 0.15)
		var size := (b * Vector3(IN + 0.6, top, 0.3)).abs()
		Inn._solid(parent, c, size)
	var seg := (IN - DOOR_W) * 0.5
	for s in [-1.0, 1.0]:
		Inn._solid(parent, Vector3(s * (DOOR_W * 0.5 + seg * 0.5), top * 0.5, h + 0.15), Vector3(seg, top, 0.3))
	Inn._solid(parent, Vector3(0, top * 0.5, h + 0.35), Vector3(DOOR_W, top, 0.1))
	Inn._solid(parent, Vector3(0, (2.2 + top) * 0.5, h + 0.15), Vector3(DOOR_W, top - 2.2, 0.3))
	for st in steps():                                                                         # 石阶：贴西墙那段实心，其余一块块石板
		var c: Vector3 = st[0]
		var s: Vector3 = st[1]
		Inn._solid(parent, c - Vector3(0, s.y * 0.5, 0), s)
	var x2 := -h + STAIR_W + RUN2 * TREAD2
	for rail in [[Vector3(-h + STAIR_W, 0, (-h + STAIR_W + 0.4) * 0.5), Vector3(0.1, 1.0, 0.4 - (-h + STAIR_W))],
			[Vector3((-h + STAIR_W + x2) * 0.5, 0, -h + STAIR_W), Vector3(x2 - (-h + STAIR_W), 1.0, 0.1)],
			[Vector3(-h + STAIR_W * 0.5, 0, 0.4), Vector3(STAIR_W, 1.0, 0.1)]]:
		Inn._solid(parent, (rail[0] as Vector3) + Vector3(0, UPPER + 0.5, 0), rail[1])
	Inn._solid(parent, Vector3(1.85, 0.45, -2.0), Vector3(1.4, 0.9, 0.7))                        # 油桶
	Inn._solid(parent, Vector3(1.85, UPPER + 0.25, -0.5), Vector3(0.9, 0.5, 2.0))                 # 床
	Inn._solid(parent, Vector3(-0.9, UPPER + 0.4, 1.6), Vector3(0.9, 0.8, 0.6))                   # 小桌
	Inn._solid(parent, Vector3(-0.6, UPPER + 0.3, -0.3), Vector3(0.55, 0.6, 0.55))                # 小铁炉


## 光：底层吊着的风灯（暗）；顶层的蜡烛和小铁炉（炉子算火边，暖手用）
static func _lights(parent: Node3D, reduced_motion: bool) -> void:
	var lamp := Tavern.FireLight.new()
	lamp.name = "Lantern"
	lamp.light_color = Look.LAMP_COLOR
	lamp.base = 2.4
	lamp.omni_range = 8.0
	lamp.flicker = not reduced_motion
	lamp.position = Vector3(0.2, 2.9, 0.0)
	parent.add_child(lamp)
	var kit := MeshKit.new()                                                                   # 风灯：吊在横梁上
	kit.cylinder("iron", Vector3(0.2, UPPER - 0.36, 0.0), Vector3(0.2, 3.25, 0.0), 0.01, 0.01, 4)
	kit.box("iron", Vector3(0.2, 3.22, 0.0), Vector3(0.2, 0.04, 0.2))
	kit.box("flame", Vector3(0.2, 3.02, 0.0), Vector3(0.12, 0.3, 0.12))
	kit.box("iron", Vector3(0.2, 2.86, 0.0), Vector3(0.2, 0.04, 0.2))
	var mi := kit.build({"iron": Inn._iron_mat(), "flame": Inn._unshaded(Color("ffc070"))})
	mi.name = "LanternMesh"
	parent.add_child(mi)
	var stove := Tavern.FireLight.new()
	stove.name = "Stove"
	stove.light_color = Color("ff7a32")
	stove.base = 1.6
	stove.omni_range = 5.0
	stove.flicker = not reduced_motion
	stove.position = Vector3(-0.6, UPPER + 0.8, -0.3)
	stove.add_to_group("light_source")
	stove.set_meta("radius", 1.2)
	parent.add_child(stove)
	var candle := Tavern.FireLight.new()                                                       # 桌上的蜡烛
	candle.name = "Candle"
	candle.light_color = Color("ffb060")
	candle.base = 1.0
	candle.omni_range = 4.0
	candle.flicker = not reduced_motion
	candle.position = Vector3(-0.75, UPPER + 1.0, 1.5)
	parent.add_child(candle)
	var stair := OmniLight3D.new()                                                             # 石梯拐角：从楼上漏下来的一点光（不然石梯那一角全黑）
	stair.name = "StairFill"
	stair.light_color = Color("c8a070")
	stair.light_energy = 0.7
	stair.omni_range = 4.5
	stair.position = Vector3(-1.6, 3.6, -1.6)
	parent.add_child(stair)


static func _fur_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("5a4634")
	m.roughness = 1.0
	m.vertex_color_use_as_albedo = true
	return m


static func _horn_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("c9b48a")
	m.roughness = 0.55
	m.vertex_color_use_as_albedo = true
	return m


static func _oil_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("141010")
	m.roughness = 0.2
	return m
