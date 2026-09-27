class_name TestRange
extends RefCounted
## 灰盒测试场（路线图 1.2）：验证第一人称控制器的台阶、斜坡、陡坡、窄门、矮洞。
## 网页用 ?test=1 打开；自动化测试把玩家放到各项前方 2 米处往前走（-Z 方向）。
## 所有项目的起始线都在 z = START_Z，玩家出生在 z = 4 面朝 -Z。

const SPAWN := Vector3(0, 0, 4)
const START_Z := -4.0
const STAIRS_X := 0.0
const STEP_RISE := 0.2
const STEP_DEPTH := 0.5
const STEPS := 4
const RAMP_X := -6.0
const RAMP_DEG := 20.0
const RAMP_LEN := 6.0             # 水平长度
const STEEP_X := -12.0
const STEEP_DEG := 55.0
const DOOR_X := 6.0
const DOOR_W := 0.9
const DOOR_Z := -6.0
const TUNNEL_X := 12.0
const TUNNEL_CLEAR := 1.4         # 矮洞净高：站着（1.8 米）进不去，蹲着（1.15 米）可以
const TUNNEL_LEN := 4.0


static func build(parent: Node3D) -> Transform3D:
	var floor_mat := Blocks.mat(Color("3a4048"))
	var block := Blocks.mat(Color("6a6f78"))
	var accent := Blocks.mat(Color("8a7a5a"))
	Blocks.box(parent, Vector3(44, 0.2, 44), Vector3(0, -0.1, -8), floor_mat)
	for w in [[Vector3(44, 4, 0.4), Vector3(0, 2, 14)], [Vector3(44, 4, 0.4), Vector3(0, 2, -30)],
			[Vector3(0.4, 4, 44), Vector3(22, 2, -8)], [Vector3(0.4, 4, 44), Vector3(-22, 2, -8)]]:
		Blocks.box(parent, w[0], w[1], block)
	# 起始线
	Blocks.box(parent, Vector3(30, 0.01, 0.1), Vector3(0, 0.006, START_Z + 0.05), accent, false)
	# 台阶：4 级，每级 0.2 米高、0.5 米深，上面接一个平台
	for i in STEPS:
		var h := STEP_RISE * (i + 1)
		Blocks.box(parent, Vector3(3, h, STEP_DEPTH), Vector3(STAIRS_X, h * 0.5, START_Z - STEP_DEPTH * (i + 0.5)), block)
	var top := STEP_RISE * STEPS
	Blocks.box(parent, Vector3(3, top, 3), Vector3(STAIRS_X, top * 0.5, START_Z - STEP_DEPTH * STEPS - 1.5), block)
	Blocks.label(parent, "台阶 0.2 米 ×4", Vector3(STAIRS_X, 2.6, START_Z))
	# 20° 斜坡：能走上去
	var rise := RAMP_LEN * tan(deg_to_rad(RAMP_DEG))
	var slab := RAMP_LEN / cos(deg_to_rad(RAMP_DEG))
	Blocks.box(parent, Vector3(3, 0.2, slab), Vector3(RAMP_X, rise * 0.5 - 0.1, START_Z - RAMP_LEN * 0.5), block, true, Vector3(RAMP_DEG, 0, 0))
	Blocks.box(parent, Vector3(3, rise, 3), Vector3(RAMP_X, rise * 0.5, START_Z - RAMP_LEN - 1.5), block)
	Blocks.label(parent, "斜坡 20°", Vector3(RAMP_X, 2.6, START_Z))
	# 55° 陡坡：上不去（可行走的最大坡度 46°）
	var steep_len := 3.0
	var steep_rise := steep_len * tan(deg_to_rad(STEEP_DEG))
	var steep_slab := steep_len / cos(deg_to_rad(STEEP_DEG))
	Blocks.box(parent, Vector3(3, 0.2, steep_slab), Vector3(STEEP_X, steep_rise * 0.5 - 0.1, START_Z - steep_len * 0.5), accent, true, Vector3(STEEP_DEG, 0, 0))
	Blocks.label(parent, "陡坡 55°（上不去）", Vector3(STEEP_X, 2.6, START_Z))
	# 窄门：墙上一个 0.9 米宽、2.1 米高的门洞
	var side := (6.0 - DOOR_W) * 0.5
	Blocks.box(parent, Vector3(side, 3, 0.3), Vector3(DOOR_X - DOOR_W * 0.5 - side * 0.5, 1.5, DOOR_Z), block)
	Blocks.box(parent, Vector3(side, 3, 0.3), Vector3(DOOR_X + DOOR_W * 0.5 + side * 0.5, 1.5, DOOR_Z), block)
	Blocks.box(parent, Vector3(DOOR_W, 0.9, 0.3), Vector3(DOOR_X, 2.55, DOOR_Z), block)
	Blocks.label(parent, "窄门 0.9 米", Vector3(DOOR_X, 3.4, DOOR_Z + 0.6))
	# 矮洞：净高 1.4 米，要蹲下才能进
	var zc := START_Z - TUNNEL_LEN * 0.5
	Blocks.box(parent, Vector3(0.3, TUNNEL_CLEAR, TUNNEL_LEN), Vector3(TUNNEL_X - 0.85, TUNNEL_CLEAR * 0.5, zc), block)
	Blocks.box(parent, Vector3(0.3, TUNNEL_CLEAR, TUNNEL_LEN), Vector3(TUNNEL_X + 0.85, TUNNEL_CLEAR * 0.5, zc), block)
	Blocks.box(parent, Vector3(2.0, 0.3, TUNNEL_LEN), Vector3(TUNNEL_X, TUNNEL_CLEAR + 0.15, zc), accent)
	Blocks.label(parent, "矮洞 1.4 米（蹲下 C）", Vector3(TUNNEL_X, 2.6, START_Z))
	# 两盏灯：测试场用中性的冷暖光，看得清几何体
	for x in [-6.0, 8.0]:
		var l := OmniLight3D.new()
		l.light_color = Color("ffd9a0")
		l.light_energy = 1.6
		l.omni_range = 16.0
		l.position = Vector3(x, 5.0, -6.0)
		parent.add_child(l)
	return Transform3D(Basis.IDENTITY, SPAWN)
