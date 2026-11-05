class_name Scriptorium
extends RefCounted
## 坠星院的抄经室（路线图 6.2b；STORY.md 6.2、6.5 第 2 步「抄经室里关着一个灰袍修士，夜里一个人对着墙说话」）：原创布局。
## 东边一排石屋里的一间，10 × 5.5 米外面、屋里 9 × 4.8 米、3.4 米高：粗石墙、石板地、木梁顶。
##   北墙一扇高窄的窗（冬天的冷光，屋里最亮的就是它），四张斜面的抄经桌、高凳，桌上摊着抄了一半的书、墨水壶、羽毛笔；
##   西墙（门边）一排书架，书和卷轴；东头是伊格纳兹修士的角落：一张草铺、一条毯子、一只空碗，墙上从地面到齐肩高刻满了一道道划痕
##   和几行歪歪扭扭的字——三十五年，他夜里对着墙说话（6.8 他开口时要念的那些）。人（伊格纳兹）6.4 放：跪在东墙下（IGNAZ），6.8 才开口。
## 室内的光不跟时段走；窗玻璃按时段换颜色（同驿站，Inn.glass）。门从外面锁着（PlainAbbey.SCRIPTORIUM_DOOR_TEXT），6.8 院长放人以后才进得来；?area=scriptorium 和测试直接进。
## 坐标：原点在屋里地面中心，北 = -Z；出口门在南墙（z = +2.4），出去站在回廊上（plain 的出生点 scriptorium_door）。

const W := 9.0
const D := 4.8
const H := 3.4
const WALL_T := 0.35
const DOOR_X := -1.2
const DOOR_W := 1.1
const EXIT_NAME := "回到回廊"
const WIN_X := 0.6
const WIN_W := 0.6
const WIN_Y := 2.0
const WIN_H := 1.5
const DESKS := [Vector3(-2.4, 0, -0.9), Vector3(-0.6, 0, -0.9), Vector3(1.2, 0, -0.9), Vector3(-1.5, 0, 0.8)]
const SHELF := Rect2(-4.45, -2.2, 0.4, 3.0)
const PALLET := Rect2(3.0, -1.9, 1.4, 2.2)            # 伊格纳兹的草铺（东头靠北）
const TALLY_WALL_X := 4.48                            # 刻满划痕的那面墙（东墙）
const IGNAZ := [Vector3(3.85, 0, 0.7), -90.0]         # 跪在东墙下、草铺旁边，面朝刻满划痕的墙
const IGNAZ_LINES := ["（他背对着你，跪在东墙下，手指一道一道摸着墙上的划痕）……三十四……三十五……", "（他没回头）门开着，冷。……关上吧。"]
const SPAWNS := {
	"front": [Vector3(DOOR_X, 0, 1.8), 0.0],
}
const VIEW_NAMES := ["进门看抄经室", "东墙上的划痕", "窗下的抄经桌"]
const VIEWS := [
	[Vector3(DOOR_X, 0, 1.8), 10.0, -8.0],
	[Vector3(1.6, 0, 0.6), -72.0, -2.0],
	[Vector3(-0.2, 0, 1.4), -5.0, -12.0],
]


static func build(parent: Node3D, reduced_motion := false) -> Transform3D:
	var kit := MeshKit.new()
	_room(kit)
	_furniture(kit)
	_corner(kit)
	var mi := kit.build({"stone": Look.mat("stone"), "floor": Look.mat("street"), "timber": Look.mat("timber"), "glass": Inn.glass(GameState.daypart),
		"cloth": Inn._cloth_mat(), "ink": Inn._unshaded(Color("2a1e14")), "iron": Inn._iron_mat(), "straw": _straw(), "scratch": _scratch(), "wool": _wool()})
	mi.name = "Scriptorium"
	parent.add_child(mi)
	_decor(parent, reduced_motion)
	_colliders(parent)
	_lights(parent, reduced_motion)
	var ig := Npc.make("灰袍修士", IGNAZ_LINES, Color("6a6a74"))           # 伊格纳兹（6.4 放进来；6.8 院长放人以后才开口，对话那时候加）
	ig.name = "Npc_ignaz"
	ig.position = IGNAZ[0]
	ig.rotation.y = deg_to_rad(float(IGNAZ[1]))
	parent.add_child(ig)
	var exit := Door.make(EXIT_NAME, DOOR_W, 2.1, false)
	exit.verb = "离开"
	exit.to_area = "plain"
	exit.to_spawn = "scriptorium_door"
	exit.position = Vector3(DOOR_X - DOOR_W * 0.5, 0, D * 0.5 - 0.02)
	parent.add_child(exit)
	var s: Array = SPAWNS.front
	return Transform3D(Basis(Vector3.UP, deg_to_rad(float(s[1]))), s[0])


static func map_spec() -> Dictionary:
	var shapes := [
		{"k": "furniture", "rect": SHELF, "label": "书架"},
		{"k": "furniture", "rect": PALLET, "label": "草铺"},
	]
	for d: Vector3 in DESKS:
		shapes.append({"k": "furniture", "rect": Rect2(d.x - 0.55, d.z - 0.35, 1.1, 0.7)})
	return {
		"bounds": Rect2(-W * 0.5, -D * 0.5, W, D),
		"shapes": shapes,
		"exits": [{"at": Vector2(DOOR_X, D * 0.5), "dir": Vector2(0, 1), "to": "plain", "spawn": "scriptorium_door", "name": EXIT_NAME}],
	}


## 石板地、四面粗石墙（北墙一扇高窄的窗、南墙一扇门）、木板顶和三根横梁
static func _room(kit: MeshKit) -> void:
	var hw := W * 0.5
	var hd := D * 0.5
	kit.box("floor", Vector3(0, -0.05, 0), Vector3(W, 0.1, D), Basis.IDENTITY, 0.75, 0.75)
	kit.box("timber", Vector3(0, H + 0.05, 0), Vector3(W, 0.1, D), Basis.IDENTITY, 0.35, 0.35, true)
	for x in [-2.8, 0.0, 2.8]:
		kit.box("timber", Vector3(x, H - 0.15, 0), Vector3(0.26, 0.3, D), Basis.IDENTITY, 0.5, 0.4)
	kit.box("stone", Vector3(hw + WALL_T * 0.5, H * 0.5, 0), Vector3(WALL_T, H, D), Basis.IDENTITY, 0.75, 0.5)
	kit.box("stone", Vector3(-hw - WALL_T * 0.5, H * 0.5, 0), Vector3(WALL_T, H, D), Basis.IDENTITY, 0.75, 0.5)
	var zn := -hd - WALL_T * 0.5                                         # 北墙：中间一扇高窄的窗
	var wl := WIN_X - WIN_W * 0.5
	var wr := WIN_X + WIN_W * 0.5
	kit.box("stone", Vector3((-hw - WALL_T + wl) * 0.5, H * 0.5, zn), Vector3(wl + hw + WALL_T, H, WALL_T), Basis.IDENTITY, 0.75, 0.5)
	kit.box("stone", Vector3((wr + hw + WALL_T) * 0.5, H * 0.5, zn), Vector3(hw + WALL_T - wr, H, WALL_T), Basis.IDENTITY, 0.75, 0.5)
	var sill := WIN_Y - WIN_H * 0.5
	var head := WIN_Y + WIN_H * 0.5
	kit.box("stone", Vector3(WIN_X, sill * 0.5, zn), Vector3(WIN_W, sill, WALL_T), Basis.IDENTITY, 0.7, 0.5)
	kit.box("stone", Vector3(WIN_X, (head + H) * 0.5, zn), Vector3(WIN_W, H - head, WALL_T), Basis.IDENTITY, 0.75, 0.6)
	kit.box("glass", Vector3(WIN_X, WIN_Y, zn - 0.08), Vector3(WIN_W, WIN_H, 0.04))
	kit.box("iron", Vector3(WIN_X, WIN_Y, zn + 0.02), Vector3(0.03, WIN_H, 0.03))
	kit.box("iron", Vector3(WIN_X, WIN_Y, zn + 0.02), Vector3(WIN_W, 0.03, 0.03))
	kit.box("stone", Vector3(WIN_X, sill - 0.05, zn + 0.12), Vector3(WIN_W + 0.2, 0.1, 0.3))
	var zs := hd + WALL_T * 0.5                                          # 南墙：门
	var dl := DOOR_X - DOOR_W * 0.5
	var dr := DOOR_X + DOOR_W * 0.5
	kit.box("stone", Vector3((-hw - WALL_T + dl) * 0.5, H * 0.5, zs), Vector3(dl + hw + WALL_T, H, WALL_T), Basis.IDENTITY, 0.75, 0.5)
	kit.box("stone", Vector3((dr + hw + WALL_T) * 0.5, H * 0.5, zs), Vector3(hw + WALL_T - dr, H, WALL_T), Basis.IDENTITY, 0.75, 0.5)
	kit.box("stone", Vector3(DOOR_X, (2.1 + H) * 0.5, zs), Vector3(DOOR_W, H - 2.1, WALL_T), Basis.IDENTITY, 0.75, 0.6)
	kit.box("timber", Vector3(DOOR_X, 2.17, zs - 0.12), Vector3(DOOR_W + 0.4, 0.16, 0.16))


## 四张斜面的抄经桌（桌上抄了一半的书、墨水壶、羽毛笔）、高凳；西墙的书架
static func _furniture(kit: MeshKit) -> void:
	for i in DESKS.size():
		var c: Vector3 = DESKS[i]
		var tilt := Basis(Vector3.RIGHT, -0.32)
		kit.box("timber", c + Vector3(0, 1.0, 0), Vector3(1.1, 0.06, 0.7), tilt, 1.0, 0.8)
		for lx in [-0.48, 0.48]:
			kit.box("timber", c + Vector3(lx, 0.48, 0.05), Vector3(0.07, 0.96, 0.55), Basis.IDENTITY, 0.8, 0.5)
		kit.box("timber", c + Vector3(0, 0.25, 0.05), Vector3(0.96, 0.05, 0.5), Basis.IDENTITY, 0.7, 0.5)
		if i != 3:
			kit.box("cloth", c + Vector3(-0.05, 1.045, 0.02), Vector3(0.62, 0.02, 0.42), tilt * Basis(Vector3.UP, 0.04 * i))     # 摊开的书
			kit.box("ink", c + Vector3(-0.05, 1.05, 0.02), Vector3(0.012, 0.025, 0.42), tilt)
			for r in 5:                                                                                                       # 抄了一半：左页满、右页几行
				var ww := 0.24 if r < 3 else 0.12
				kit.box("ink", c + Vector3(-0.2, 1.057, -0.12 + r * 0.06), Vector3(0.24, 0.003, 0.012), tilt)
				kit.box("ink", c + Vector3(0.1 + (0.24 - ww) * 0.5, 1.057, -0.12 + r * 0.06), Vector3(ww, 0.003, 0.012), tilt)
		kit.cylinder("ink", c + Vector3(0.45, 1.13, -0.28), c + Vector3(0.45, 1.2, -0.28), 0.035, 0.03, 6, 0.6)
		kit.cylinder("cloth", c + Vector3(0.45, 1.18, -0.28), c + Vector3(0.5, 1.42, -0.22), 0.008, 0.002, 3)                     # 羽毛笔
		kit.cylinder("timber", c + Vector3(0, 0, 0.75), c + Vector3(0, 0.72, 0.75), 0.18, 0.16, 7, 0.7)                          # 高凳
	var sx := SHELF.get_center().x
	for y in [0.4, 1.0, 1.6, 2.2]:
		kit.box("timber", Vector3(sx, y, SHELF.get_center().y), Vector3(SHELF.size.x, 0.05, SHELF.size.y), Basis.IDENTITY, 0.85, 0.65)
	for z in [SHELF.position.y + 0.03, SHELF.end.y - 0.03]:
		kit.box("timber", Vector3(sx, 1.25, z), Vector3(SHELF.size.x, 2.5, 0.07), Basis.IDENTITY, 0.8, 0.5)


## 伊格纳兹的角落：草铺、毯子、一只空碗；东墙从地面到齐肩高刻满了一道道划痕（五道一捆），中间几行歪歪扭扭的字
static func _corner(kit: MeshKit) -> void:
	var p := PALLET
	kit.box("straw", Vector3(p.get_center().x, 0.1, p.get_center().y), Vector3(p.size.x, 0.2, p.size.y), Basis(Vector3.UP, 0.05), 1.0, 0.7)
	kit.box("wool", Vector3(p.get_center().x + 0.1, 0.23, p.get_center().y + 0.3), Vector3(p.size.x * 0.8, 0.06, p.size.y * 0.55), Basis(Vector3.UP, -0.12), 0.9, 0.7)
	kit.cylinder("timber", Vector3(p.position.x - 0.3, 0, p.end.y + 0.25), Vector3(p.position.x - 0.3, 0.07, p.end.y + 0.25), 0.1, 0.08, 7, 0.8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 6205
	var x := TALLY_WALL_X
	var z := -2.15
	var row_y := 0.25
	while row_y < 1.5:                                                    # 划痕：一捆一捆（四竖一斜）
		z = -2.15
		while z < 2.0:
			if z > -0.5 and z < 0.7 and row_y > 0.75 and row_y < 1.3:
				z += 0.2
				continue                                                  # 中间留给字
			for k in 4:
				kit.box("scratch", Vector3(x, row_y, z + k * 0.035), Vector3(0.01, 0.13, 0.012))
			kit.box("scratch", Vector3(x, row_y, z + 0.05), Vector3(0.01, 0.16, 0.012), Basis(Vector3.RIGHT, 0.9))
			z += 0.2 + rng.randf_range(-0.02, 0.03)
		row_y += 0.2
	for line in 3:                                                         # 几行字（刻得歪歪扭扭）
		var ly := 1.18 - line * 0.17
		var lz := -0.4
		while lz < 0.6 - line * 0.15:
			kit.box("scratch", Vector3(x, ly + rng.randf_range(-0.02, 0.02), lz), Vector3(0.01, 0.07, 0.05), Basis(Vector3.RIGHT, rng.randf_range(-0.5, 0.5)))
			lz += 0.08


static func _decor(parent: Node3D, reduced_motion := false) -> void:
	var d := Decor.new()
	d.books(Vector3(SHELF.get_center().x + 0.05, 0.43, SHELF.position.y + 0.15), Vector3(0, 0, 1), SHELF.size.y - 0.3, 61)
	d.books(Vector3(SHELF.get_center().x + 0.05, 1.03, SHELF.position.y + 0.15), Vector3(0, 0, 1), SHELF.size.y - 0.3, 62)
	d.books(Vector3(SHELF.get_center().x + 0.05, 1.63, SHELF.position.y + 0.15), Vector3(0, 0, 1), SHELF.size.y - 0.5, 63)
	d.candles((DESKS[1] as Vector3) + Vector3(0.42, 1.15, -0.05), 1)
	d.candles(Vector3(PALLET.position.x - 0.6, 0.0, PALLET.get_center().y - 0.6), 1, true)        # 地上一截蜡烛（他夜里点的）
	d.chest(Vector3(3.6, 0, 1.6), PI * 0.5)
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
	for c: Vector3 in DESKS:
		Inn._solid(parent, c + Vector3(0, 0.55, 0.05), Vector3(1.15, 1.1, 0.75))
	Inn._solid(parent, Vector3(SHELF.get_center().x, 1.25, SHELF.get_center().y), Vector3(SHELF.size.x, 2.5, SHELF.size.y))
	Inn._solid(parent, Vector3(3.6, 0.3, 1.6), Vector3(0.6, 0.6, 0.95))


## 光：北窗的冷光（一盏偏蓝的面光朝屋里打）、桌上一支蜡烛的暖光
static func _lights(parent: Node3D, reduced_motion: bool) -> void:
	var win := SpotLight3D.new()
	win.name = "WindowLight"
	win.light_color = Color("c4d2e6")
	win.light_energy = 3.6
	win.spot_range = 8.0
	win.spot_angle = 50.0
	win.position = Vector3(WIN_X, WIN_Y + 0.3, -D * 0.5 + 0.2)
	win.rotation_degrees = Vector3(-38, 0, 0)
	parent.add_child(win)
	var candle := Tavern.FireLight.new()
	candle.name = "Candle"
	candle.light_color = Color("ffb060")
	candle.base = 1.4
	candle.omni_range = 5.0
	candle.position = (DESKS[1] as Vector3) + Vector3(0.42, 1.45, -0.05)
	candle.flicker = not reduced_motion
	candle.add_to_group("light_source")
	candle.set_meta("radius", 3.0)
	parent.add_child(candle)
	var fill := OmniLight3D.new()
	fill.name = "Fill"
	fill.light_color = Color("8a96a8")
	fill.light_energy = 1.3                          # 截图：屋里一片黑、东墙的划痕像浮在半空——补一盏偏冷的散光
	fill.omni_range = 10.0
	fill.position = Vector3(0, 2.6, 0)
	parent.add_child(fill)
	var floor_candle := Tavern.FireLight.new()        # 草铺边地上那截蜡烛：照着刻满划痕的东墙
	floor_candle.name = "FloorCandle"
	floor_candle.light_color = Color("ff9a48")
	floor_candle.base = 1.1
	floor_candle.omni_range = 3.6
	floor_candle.position = Vector3(PALLET.position.x - 0.6, 0.35, PALLET.get_center().y - 0.6)
	floor_candle.flicker = not reduced_motion
	parent.add_child(floor_candle)


static func _straw() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("8a7a52")
	m.roughness = 1.0
	m.vertex_color_use_as_albedo = true
	return m


static func _wool() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("5a5248")
	m.roughness = 1.0
	m.vertex_color_use_as_albedo = true
	return m


static func _scratch() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("b8b0a2")                 # 刻出来的新鲜石面，比墙亮
	m.roughness = 1.0
	return m
