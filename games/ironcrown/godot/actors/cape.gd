class_name Cape
extends MeshInstance3D
## 披风（路线图 A.2b）：素材包里没有披风，用代码搭一块布。一张 COLS × ROWS 的点阵（Verlet 布料）：
## 最上面一排钉在两肩（每帧跟着骨架走），其余的点受重力、互相用「绳子」拉着；不许穿进后背和腿（后背一个平面、腿上几个球把点推出去）。
## 人跑起来披风往后飘、停下来摆两下垂回去、转身时甩开。点不多（42 个），每帧在 CPU 上重算网格，网页版也跑得动。
## 节点是 top_level：网格顶点直接用世界坐标；跟着父节点（PlayerAvatar）一起显示 / 隐藏。

const COLS := 6
const ROWS := 7
const LENGTH := 1.0               # 肩到下摆（米）
const WIDTH_TOP := 0.34           # 肩上的宽度
const WIDTH_BOTTOM := 0.66        # 下摆的宽度
const BACK_GAP := 0.16            # 肩上离后背（脊椎）多远
const DAMPING := 0.985            # 每一步留下多少速度：也就是空气阻力（跑速 5.5 米 / 秒时披风往后飘二三十度；0.95 时飘到快六十度，从身后看缩成一团）
const SIDE_SLACK := 0.12          # 下摆最多甩到身体侧面多远（超过半幅之外的距离）
const FLARE := 0.11               # 自然垂下的方向随身体速度往后倾：每米 / 秒倾多少（跑速 5.5 米 / 秒约 30°）
const SHAPE_PULL := 0.06          # 每一步往「自然垂在背后」的样子拉回多少：没有它布太软，跑起来飘成水平、一停就甩到身侧（网页实拍）
const ITERATIONS := 4
const STEP := 1.0 / 60.0
const MAX_STEPS := 3
const RESET_JUMP := 1.0           # 肩膀一帧挪了这么远（传送、读档）：重新垂下来，不拉成长条
const LEG_RADIUS := {"thigh_l": 0.11, "thigh_r": 0.11, "calf_l": 0.09, "calf_r": 0.09}

var character: CharacterModel
var color := Color("5e2420")
var pos := PackedVector3Array()
var prev := PackedVector3Array()
var _acc := 0.0
var _ready_sim := false
var _last_anchor := Vector3.ZERO
var _vel := Vector3.ZERO          # 肩膀的水平速度（平滑过的）
var _mat: StandardMaterial3D
var _arr_mesh := ArrayMesh.new()


static func make(c: CharacterModel, col: Color) -> Cape:
	var cape := Cape.new()
	cape.name = "Cape"
	cape.character = c
	cape.color = col
	return cape


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	mesh = _arr_mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = color
	_mat.vertex_color_use_as_albedo = true
	_mat.roughness = 0.95
	_mat.cull_mode = BaseMaterial3D.CULL_BACK          # 正反两面各一份三角形（_rebuild），只画朝着镜头的那一面，两面不打架
	_mat.emission_enabled = true                 # 和人物一样一点点自发光：背光时不变成一块黑
	_mat.emission = color
	_mat.emission_energy_multiplier = CharacterModel.GLOW
	pos.resize(COLS * ROWS)
	prev.resize(COLS * ROWS)
	extra_cull_margin = 2.0


func _process(delta: float) -> void:
	if character == null or not character.loaded or not is_visible_in_tree():
		_ready_sim = false
		return
	var top := _anchors()
	if not _ready_sim or top[0].distance_to(_last_anchor) > RESET_JUMP:
		_reset(top)
		_vel = Vector3.ZERO
	elif delta > 0.0:
		var v := (top[0] - _last_anchor) / delta
		v.y = 0.0
		_vel = _vel.lerp(v, clampf(delta * 6.0, 0.0, 1.0))
	_last_anchor = top[0]
	_acc = minf(_acc + delta, STEP * MAX_STEPS)
	while _acc >= STEP:
		_acc -= STEP
		_step(top)
	_rebuild()


## 身体的方向：right = 从左肩指向右肩，up = 从腰到脖子，back = 往背后
func _frame() -> Dictionary:
	var sk := character.skeleton
	var g := sk.global_transform
	var l := g * sk.get_bone_global_pose(sk.find_bone("upperarm_l")).origin
	var r := g * sk.get_bone_global_pose(sk.find_bone("upperarm_r")).origin
	var neck := g * sk.get_bone_global_pose(sk.find_bone("neck_01")).origin
	var spine := g * sk.get_bone_global_pose(sk.find_bone("spine_01")).origin
	var right := (r - l).normalized()
	var up := (neck - spine).normalized()
	var back := right.cross(up).normalized()
	return {"l": l, "r": r, "neck": neck, "spine": spine, "right": right, "up": up, "back": back}


## 最上面一排钉在哪：两肩之间、往背后挪一点、往上一点，中间往外鼓一点（贴着后背的弧度）
func _anchors() -> PackedVector3Array:
	var f := _frame()
	var mid: Vector3 = (f.l + f.r) * 0.5 + f.back * BACK_GAP + f.up * 0.03
	var out := PackedVector3Array()
	for c in COLS:
		var t := float(c) / float(COLS - 1)
		out.append(mid + f.right * (t - 0.5) * WIDTH_TOP + f.back * 0.04 * sin(PI * t))
	return out


func _reset(top: PackedVector3Array) -> void:
	var f := _frame()
	for r in ROWS:
		for c in COLS:
			var p := _rest(top, f, r, c)
			pos[r * COLS + c] = p
			prev[r * COLS + c] = p
	_ready_sim = true


func _width(r: int) -> float:
	return lerpf(WIDTH_TOP, WIDTH_BOTTOM, float(r) / float(ROWS - 1))


func _step(top: PackedVector3Array) -> void:
	var g := Vector3(0, -9.8, 0) * STEP * STEP
	for c in COLS:
		pos[c] = top[c]
		prev[c] = top[c]
	for i in range(COLS, pos.size()):
		var p := pos[i]
		var v := (p - prev[i]) * DAMPING
		prev[i] = p
		pos[i] = p + v + g
	var seg := LENGTH / float(ROWS - 1)
	var f := _frame()
	var legs := _legs()
	for r in range(1, ROWS):
		for c in COLS:
			var i := r * COLS + c
			pos[i] = pos[i].lerp(_rest(top, f, r, c), SHAPE_PULL)
	for _it in ITERATIONS:
		for r in range(1, ROWS):
			var hseg := _width(r) / float(COLS - 1)
			for c in COLS:
				var i := r * COLS + c
				_link(i - COLS, i, seg, r == 1)
				if c > 0:
					_link(i - 1, i, hseg, false)
		_collide(f, legs)


## 两个点之间的「绳子」：拉回到 rest 长；上一个点是钉住的（第一排）只动下面那个
func _link(a: int, b: int, rest: float, a_pinned: bool) -> void:
	var d := pos[b] - pos[a]
	var len := d.length()
	if len < 0.0001:
		return
	var diff := (len - rest) / len
	if a_pinned:
		pos[b] -= d * diff
	else:
		pos[a] += d * diff * 0.5
		pos[b] -= d * diff * 0.5


## 腿：大腿、小腿中段各一个球（跑起来往后蹬的腿不戳穿披风）
func _legs() -> Array:
	var sk := character.skeleton
	var g := sk.global_transform
	var out := []
	for pair in [["thigh_l", "calf_l"], ["thigh_r", "calf_r"], ["calf_l", "foot_l"], ["calf_r", "foot_r"]]:
		var a := g * sk.get_bone_global_pose(sk.find_bone(pair[0])).origin
		var b := g * sk.get_bone_global_pose(sk.find_bone(pair[1])).origin
		out.append([(a + b) * 0.5, float(LEG_RADIUS[pair[0]])])
	return out


## 自然垂下的样子：从肩上那一排往正下方垂（世界的「下」），离后背稍远一点，下摆张开
func _rest(top: PackedVector3Array, f: Dictionary, r: int, c: int) -> Vector3:
	var seg := LENGTH / float(ROWS - 1)
	var t := float(c) / float(COLS - 1)
	var spread: Vector3 = f.right * (t - 0.5) * (WIDTH_BOTTOM - WIDTH_TOP) * float(r) / float(ROWS - 1)
	var flat_back: Vector3 = Vector3(f.back.x, 0.0, f.back.z).normalized()
	var hang := (Vector3.DOWN - _vel * FLARE).normalized()        # 走得越快越往后倾
	return top[c] + hang * seg * r + flat_back * 0.03 * r + spread


## 不许穿进身体：后背平面（脊椎往后 BACK_GAP 一点）以前的点推到平面后面；腿上的球把点推出去
func _collide(f: Dictionary, legs: Array) -> void:
	var plane_pt: Vector3 = f.spine
	var back: Vector3 = f.back
	var right: Vector3 = f.right
	for i in range(COLS, pos.size()):
		var d := (pos[i] - plane_pt).dot(back)
		var margin := BACK_GAP * 0.9
		if d < margin:
			pos[i] += back * (margin - d)
			prev[i] = prev[i].lerp(pos[i], 0.5)          # 贴着后背蹭过去：有摩擦，不会顺着背滑到身体侧面去
		var side := (pos[i] - plane_pt).dot(right)
		var lim := _width(i / COLS) * 0.5 + SIDE_SLACK
		if absf(side) > lim:
			pos[i] -= right * (side - signf(side) * lim)
		for s in legs:
			var to: Vector3 = pos[i] - s[0]
			var r: float = s[1]
			var l := to.length()
			if l < r and l > 0.0001:
				pos[i] = s[0] + to / l * r


## 重算网格：两面都画（正反面法线各一份），下摆一条深色的边
func _rebuild() -> void:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var n := COLS * ROWS
	var normals := PackedVector3Array()
	normals.resize(n)
	for r in ROWS:
		for c in COLS:
			var i := r * COLS + c
			var dx := pos[r * COLS + mini(c + 1, COLS - 1)] - pos[r * COLS + maxi(c - 1, 0)]
			var dy := pos[mini(r + 1, ROWS - 1) * COLS + c] - pos[maxi(r - 1, 0) * COLS + c]
			normals[i] = dy.cross(dx).normalized()
	for side in 2:
		for i in n:
			verts.append(pos[i])
			norms.append(normals[i] * (1.0 if side == 0 else -1.0))
			var hem := 0.7 if i >= (ROWS - 1) * COLS else 1.0
			cols.append(Color(hem, hem, hem))
		for r in ROWS - 1:
			for c in COLS - 1:
				var a := side * n + r * COLS + c
				var b := a + 1
				var d := a + COLS
				var e := d + 1
				if side == 0:
					idx.append_array([a, d, b, b, d, e])
				else:
					idx.append_array([a, b, d, b, e, d])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	_arr_mesh.clear_surfaces()
	_arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_arr_mesh.surface_set_material(0, _mat)
