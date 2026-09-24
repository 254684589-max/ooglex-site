class_name CharacterModel
extends Node3D
## 程序生成的人物（玩家与 NPC 共用）：一副 17 根骨头的骨架（Skeleton3D）+ 一张蒙皮网格。
## 躯干、四肢、鞋子用截面放样（loft）生成连续的身体，膝、肘、肩、腰处按骨头平滑分配权重，弯曲时不会断开；
## 头部五官、帽子、领子等小零件直接绑在对应骨头上。整个人 1 次绘制调用（有发光零件时再加 1 次）。
## 模型正面朝 -Z，身高约 1.8 米（body_scale = 1）。动画由 AnimationController 逐帧设置骨头姿势。

enum { HIPS, SPINE, CHEST, NECK, HEAD, UPPERARM_L, LOWERARM_L, HAND_L, UPPERARM_R, LOWERARM_R, HAND_R, UPPERLEG_L, LOWERLEG_L, FOOT_L, UPPERLEG_R, LOWERLEG_R, FOOT_R }
const BONE_NAMES := ["Hips", "Spine", "Chest", "Neck", "Head", "UpperArm.L", "LowerArm.L", "Hand.L", "UpperArm.R", "LowerArm.R", "Hand.R", "UpperLeg.L", "LowerLeg.L", "Foot.L", "UpperLeg.R", "LowerLeg.R", "Foot.R"]
const BONE_PARENT := [-1, 0, 1, 2, 3, 2, 5, 6, 2, 8, 9, 0, 11, 12, 0, 14, 15]
## 每根骨头相对父骨头的静止位置（米）；左侧在 -X
const BONE_REST := [
	Vector3(0, 0.98, 0), Vector3(0, 0.1, 0), Vector3(0, 0.2, 0), Vector3(0, 0.19, 0), Vector3(0, 0.08, 0),
	Vector3(-0.18, 0.148, 0.01), Vector3(0, -0.29, 0), Vector3(0, -0.25, 0),
	Vector3(0.18, 0.148, 0.01), Vector3(0, -0.29, 0), Vector3(0, -0.25, 0),
	Vector3(-0.095, -0.05, 0), Vector3(0, -0.43, 0), Vector3(0, -0.42, 0),
	Vector3(0.095, -0.05, 0), Vector3(0, -0.43, 0), Vector3(0, -0.42, 0),
]
const HIPS_Y := 0.98
## 大腿、小腿长度（动画里做脚底贴地计算用）
const THIGH := 0.43
const SHIN := 0.42
const ANKLE_H := 0.08
## 顶点颜色标签：换衣服时按标签改色
## T_NONE 为固定颜色（眼睛、鞋底、拉链等），其余按当前外观换算
enum { T_NONE, T_SHIRT, T_PANTS, T_SHIRT_DARK, T_SHIRT_LIGHT, T_SKIN, T_SKIN_D5, T_SKIN_D8, T_HAIR, T_HAIR_L3, T_SHOE, T_BEARD, T_ACCENT, T_SHIRT_D25, T_SHIRT_D12, T_SKIN_D3, T_SKIN_D25, T_LIP }
## 旧版头部零件坐标 → 新头部（缩小成真人比例的头，约 7.5 头身）
const HEAD_XF := Transform3D(Basis(Vector3(0.77, 0, 0), Vector3(0, 0.87, 0), Vector3(0, 0, 0.84)), Vector3(0, -0.044, 0))

@export var skin_color := Color(0.87, 0.68, 0.52)
@export var shirt_color := Color(0.2, 0.36, 0.6)
@export var pants_color := Color(0.18, 0.2, 0.26)
@export var shoe_color := Color(0.1, 0.1, 0.12)
@export var hair_color := Color(0.08, 0.07, 0.07)
@export var accent_color := Color(0.13, 0.9, 1.0)
@export var hat := "none"
@export var body_scale := 1.0
## 体型：肩宽 / 胖瘦（1 = 标准）
@export var build_width := 1.0
## 形象细节：胡子（none / goatee）、胡子颜色、外套（夹克 + 连帽衫的帽子与拉链）、金链、耳钉、胸前灯带
@export var beard := "none"
@export var beard_color := Color(0.33, 0.31, 0.3)
@export var jacket := false
@export var chain := false
@export var earring := false
@export var accent_strip := true
## 袖子：auto（穿外套为长袖，否则短袖）/ long / short
@export var sleeves := "auto"
## 远处不渲染（米，0 = 不限制）；NPC 与路人关闭阴影以减少绘制调用
@export var draw_distance := 0.0
@export var casts_shadow := true

var skeleton: Skeleton3D
var _mi: MeshInstance3D
var _glow_mi: MeshInstance3D
var _skin: Skin
var _built := false
## 网格数据（换衣服时只改颜色，不重新生成）
var _buf: Buf
var _glow: Buf

static var _wind := 0.0
## 几何数据缓存：外形参数 → [网格数据, 发光零件数据]
static var _cache := {}


## 一份可蒙皮的网格数据
class Buf:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var tags := PackedByteArray()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var idx := PackedInt32Array()

	func add(p: Vector3, n: Vector3, c: Color, tag: int, b0: int, b1: int, w1: float) -> void:
		verts.append(p)
		norms.append(n)
		cols.append(c)
		tags.append(tag)
		bones.append_array([b0, b1, 0, 0])
		weights.append_array([1.0 - w1, w1, 0.0, 0.0])

	func copy() -> Buf:
		var b := Buf.new()
		b.verts = verts
		b.norms = norms
		b.cols = cols.duplicate()
		b.tags = tags
		b.bones = bones
		b.weights = weights
		b.idx = idx
		return b

	func arrays() -> Array:
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = verts
		a[Mesh.ARRAY_NORMAL] = norms
		a[Mesh.ARRAY_COLOR] = cols
		a[Mesh.ARRAY_BONES] = bones
		a[Mesh.ARRAY_WEIGHTS] = weights
		a[Mesh.ARRAY_INDEX] = idx
		return a


func _ready() -> void:
	build()


func build() -> void:
	if _built:
		return
	_built = true
	scale = Vector3.ONE * body_scale
	skeleton = Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	_skin = Skin.new()
	for i in BONE_NAMES.size():
		skeleton.add_bone(BONE_NAMES[i])
		if BONE_PARENT[i] >= 0:
			skeleton.set_bone_parent(i, BONE_PARENT[i])
		skeleton.set_bone_rest(i, Transform3D(Basis(), BONE_REST[i]))
		skeleton.set_bone_pose_position(i, BONE_REST[i])
		_skin.add_bind(i, Transform3D(Basis(), -bone_global(i)))
	add_child(skeleton)
	_mi = MeshInstance3D.new()
	_mi.name = "Body"
	_mi.skin = _skin
	_mi.skeleton = NodePath("..")
	if draw_distance > 0.0:
		_mi.visibility_range_end = draw_distance
	if not casts_shadow:
		_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	skeleton.add_child(_mi)
	_generate()


## 骨头在静止姿势下的模型空间位置
static func bone_global(i: int) -> Vector3:
	var p := Vector3.ZERO
	var b := i
	while b >= 0:
		p += BONE_REST[b]
		b = BONE_PARENT[b]
	return p


## 设置骨头旋转（欧拉角，弧度，YXZ 顺序）；x 为正：腿 / 胳膊向前抬，小臂向前弯，脚尖上翘，躯干向后仰
func pose(bone: int, euler: Vector3) -> void:
	skeleton.set_bone_pose_rotation(bone, Quaternion.from_euler(euler))


## 骨盆位置（相对静止位置的偏移）
func pose_hips(offset: Vector3) -> void:
	skeleton.set_bone_pose_position(HIPS, BONE_REST[HIPS] + offset)


# ---------- 网格生成 ----------

func _generate() -> void:
	# 同样体型、同样款式的人共用一份几何数据，只按各自的颜色重新上色
	var key := _shape_key()
	if _cache.has(key):
		var c: Array = _cache[key]
		_buf = (c[0] as Buf).copy()
		_glow = (c[1] as Buf).copy()
		_recolor(_buf)
		_recolor(_glow)
		_commit()
		return
	_buf = Buf.new()
	_glow = Buf.new()
	var w := build_width
	var long_sleeve := sleeves == "long" or (sleeves == "auto" and jacket)
	_torso(w)
	for side in [-1.0, 1.0]:
		_leg(side)
		_shoe(side)
		_arm(side, w, long_sleeve)
		_hand(side, w)
	_clothes_details(w)
	_head()
	_hat_parts()
	_cache[key] = [_buf.copy(), _glow.copy()]
	_commit()


func _shape_key() -> String:
	var long_sleeve := sleeves == "long" or (sleeves == "auto" and jacket)
	return "%.2f|%s|%s|%s|%s|%s|%s|%s" % [build_width, jacket, long_sleeve, beard, earring, chain, accent_strip, hat]


## 按标签换算颜色（固定颜色的顶点不动）
func _role_color(tag: int) -> Color:
	match tag:
		T_SHIRT:
			return shirt_color
		T_PANTS:
			return pants_color
		T_SHIRT_DARK:
			return shirt_color.darkened(0.3)
		T_SHIRT_LIGHT:
			return shirt_color.lightened(0.04)
		T_SHIRT_D25:
			return shirt_color.darkened(0.25)
		T_SHIRT_D12:
			return shirt_color.darkened(0.12)
		T_SKIN:
			return skin_color
		T_SKIN_D5:
			return skin_color.darkened(0.05)
		T_SKIN_D8:
			return skin_color.darkened(0.08)
		T_SKIN_D3:
			return skin_color.darkened(0.03)
		T_SKIN_D25:
			return skin_color.darkened(0.25)
		T_LIP:
			return skin_color.lerp(Color(0.62, 0.3, 0.3), 0.45)
		T_HAIR:
			return hair_color
		T_HAIR_L3:
			return hair_color.lightened(0.3)
		T_SHOE:
			return shoe_color
		T_BEARD:
			return beard_color
		T_ACCENT:
			return accent_color
	return Color.WHITE


func _recolor(buf: Buf) -> void:
	var cols := buf.cols
	for i in cols.size():
		var t := buf.tags[i]
		if t != T_NONE:
			cols[i] = _role_color(t)
	buf.cols = cols


func _commit() -> void:
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _buf.arrays())
	am.surface_set_material(0, Mats.batch("skin"))
	am.custom_aabb = AABB(Vector3(-1.2, -0.3, -1.2), Vector3(2.4, 2.6, 2.4))
	_mi.mesh = am
	if _glow.verts.is_empty():
		if _glow_mi != null:
			_glow_mi.queue_free()
			_glow_mi = null
		return
	var gm := ArrayMesh.new()
	gm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _glow.arrays())
	gm.surface_set_material(0, Mats.batch("neon"))
	gm.custom_aabb = am.custom_aabb
	if _glow_mi == null:
		_glow_mi = MeshInstance3D.new()
		_glow_mi.name = "Glow"
		_glow_mi.skin = _skin
		_glow_mi.skeleton = NodePath("..")
		_glow_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if draw_distance > 0.0:
			_glow_mi.visibility_range_end = draw_distance
		skeleton.add_child(_glow_mi)
	_glow_mi.mesh = gm


## 按骨头链上的位置给权重：在 [a - blend, a + blend] 之间从 b0 平滑过渡到 b1
static func _blend(y: float, a: float, blend: float) -> float:
	return smoothstep(a - blend, a + blend, y)


## 躯干：从裆部到脖子一条连续的放样，截面为圆角方形（胸、肩更方正）
func _torso(w: float) -> void:
	# [y, 半宽, 半厚, 中心 z 偏移, 方正程度]
	var spec := [
		[0.84, 0.1, 0.085, 0.0, 2.0],
		[0.88, 0.152, 0.112, 0.0, 2.3],
		[0.95, 0.172, 0.123, 0.012, 2.5],
		[1.02, 0.163, 0.114, 0.006, 2.4],
		[1.08, 0.148, 0.104, 0.0, 2.3],
		[1.18, 0.158, 0.11, -0.004, 2.4],
		[1.28, 0.17, 0.118, -0.012, 2.7],
		[1.36, 0.18, 0.114, -0.01, 3.0],
		[1.415, 0.178, 0.104, -0.004, 3.2],
		[1.455, 0.15, 0.088, 0.0, 2.8],
		[1.482, 0.1, 0.072, 0.004, 2.3],
		[1.5, 0.062, 0.06, 0.004, 2.0],
		[1.535, 0.055, 0.057, 0.0, 2.0],
		[1.58, 0.05, 0.052, 0.006, 2.0],
	]
	var rings: Array = []
	for s in spec:
		var y: float = s[0]
		var wide := w if y > 1.1 else lerpf(1.0, w, 0.6)
		var r := {"c": Vector3(0, y, float(s[3])), "u": Vector3(float(s[1]) * wide, 0, 0), "v": Vector3(0, 0, float(s[2]) * lerpf(1.0, wide, 0.5)), "sq": float(s[4])}
		# 权重：髋 → 腰椎 → 胸 → 脖子 → 头
		if y < 1.1:
			r["b"] = [HIPS, SPINE, _blend(y, 1.04, 0.05)]
		elif y < 1.36:
			r["b"] = [SPINE, CHEST, _blend(y, 1.2, 0.07)]
		elif y < 1.52:
			r["b"] = [CHEST, NECK, _blend(y, 1.48, 0.02)]
		else:
			r["b"] = [NECK, HEAD, _blend(y, 1.565, 0.02)]
		rings.append(r)
	_loft(_buf, rings, 22, true, true, _paint_torso)


func _paint_torso(p: Vector3) -> Array:
	var y := p.y
	if y > 1.5 or (y > 1.485 and not jacket):
		return [skin_color, T_SKIN]
	if jacket:
		if y < 0.985:
			return [pants_color, T_PANTS]
		if y < 1.035:
			return [shirt_color.darkened(0.3), T_SHIRT_DARK]
		return [shirt_color, T_SHIRT]
	if y < 1.0:
		return [pants_color, T_PANTS]
	if y < 1.035:
		return [Color(0.08, 0.07, 0.07), T_NONE]
	return [shirt_color, T_SHIRT]


func _leg(side: float) -> void:
	var hip := bone_global(UPPERLEG_L if side < 0 else UPPERLEG_R)
	var knee_y := hip.y - THIGH
	# [y, 半宽, 半厚, x 向内收, z 偏移]
	var spec := [
		[0.99, 0.095, 0.104, 0.0, 0.004],
		[0.93, 0.102, 0.108, 0.0, 0.0],
		[0.8, 0.094, 0.1, 0.004, -0.004],
		[0.66, 0.08, 0.086, 0.008, 0.0],
		[0.55, 0.068, 0.072, 0.01, 0.002],
		[0.5, 0.066, 0.07, 0.01, 0.004],
		[0.43, 0.066, 0.073, 0.01, 0.012],
		[0.3, 0.058, 0.062, 0.008, 0.008],
		[0.18, 0.052, 0.055, 0.006, 0.002],
		[0.1, 0.05, 0.053, 0.006, 0.0],
	]
	var rings: Array = []
	for s in spec:
		var y: float = s[0]
		var r := {"c": Vector3(hip.x - side * float(s[3]), y, float(s[4])), "u": Vector3(float(s[1]), 0, 0), "v": Vector3(0, 0, float(s[2])), "sq": 2.0}
		var ul := UPPERLEG_L if side < 0 else UPPERLEG_R
		if y > hip.y:
			r["b"] = [HIPS, ul, 0.45]
		elif y > knee_y - 0.1:
			r["b"] = [ul, ul + 1, _blend(y, knee_y, 0.04) * -1.0 + 1.0]
		else:
			r["b"] = [ul + 1, ul + 2, 1.0 - _blend(y, 0.09, 0.03)]
		rings.append(r)
	_loft(_buf, rings, 14, false, true, func(_p: Vector3) -> Array: return [pants_color, T_PANTS])


func _shoe(side: float) -> void:
	var ankle := bone_global(FOOT_L if side < 0 else FOOT_R)
	var foot := FOOT_L if side < 0 else FOOT_R
	# [z, 半宽, 中心高, 半高]
	var spec := [
		[0.062, 0.03, 0.045, 0.035],
		[0.045, 0.043, 0.055, 0.055],
		[0.0, 0.047, 0.06, 0.06],
		[-0.06, 0.05, 0.043, 0.043],
		[-0.12, 0.048, 0.034, 0.034],
		[-0.17, 0.04, 0.029, 0.029],
		[-0.198, 0.02, 0.026, 0.02],
	]
	var rings: Array = []
	for s in spec:
		rings.append({"c": Vector3(ankle.x - side * 0.004, float(s[2]), float(s[0])), "u": Vector3(float(s[1]), 0, 0), "v": Vector3(0, float(s[3]), 0), "sq": 2.6, "b": [foot, foot, 0.0]})
	var sole := Color(0.86, 0.86, 0.83)
	_loft(_buf, rings, 14, true, true, func(p: Vector3) -> Array: return [sole, T_NONE] if p.y < 0.018 else [shoe_color, T_SHOE])


func _arm(side: float, w: float, long_sleeve: bool) -> void:
	var ua := UPPERARM_L if side < 0 else UPPERARM_R
	var sh := bone_global(ua)
	sh.x *= lerpf(1.0, w, 0.9)
	# [沿手臂向下的距离, 半宽, 半厚]
	var spec := [
		[-0.05, 0.028, 0.03],
		[-0.025, 0.05, 0.054],
		[0.03, 0.057, 0.06],
		[0.12, 0.049, 0.053],
		[0.23, 0.042, 0.045],
		[0.29, 0.038, 0.04],
		[0.35, 0.042, 0.043],
		[0.44, 0.036, 0.036],
		[0.525, 0.027, 0.031],
		[0.56, 0.025, 0.029],
	]
	var rings: Array = []
	for s in spec:
		var d: float = s[0]
		var bulk := 1.08 if long_sleeve and jacket else 1.0
		var r := {"c": sh + Vector3(side * d * 0.03, -d, 0), "u": Vector3(float(s[1]) * bulk * lerpf(1.0, w, 0.7), 0, 0), "v": Vector3(0, 0, float(s[2]) * bulk), "sq": 2.0}
		if d < 0.0:
			r["b"] = [CHEST, ua, lerpf(0.55, 1.0, (d + 0.05) / 0.05)]
		elif d < 0.4:
			r["b"] = [ua, ua + 1, _blend(d, 0.29, 0.035)]
		else:
			r["b"] = [ua + 1, ua + 2, _blend(d, 0.54, 0.02)]
		rings.append(r)
	var cuff := 0.5 if long_sleeve else 0.13
	_loft(_buf, rings, 12, true, false, func(p: Vector3) -> Array:
		var dd := sh.y - p.y
		if dd < cuff:
			return [shirt_color, T_SHIRT]
		if long_sleeve and dd < cuff + 0.035:
			return [shirt_color.darkened(0.3), T_SHIRT_DARK]
		return [skin_color, T_SKIN])


func _hand(side: float, w: float) -> void:
	var hb := HAND_L if side < 0 else HAND_R
	var wrist := bone_global(hb)
	wrist.x *= lerpf(1.0, w, 0.9)
	wrist.x += side * 0.016
	# 手掌朝向大腿：厚度在 X 方向，宽度在 Z 方向
	var spec := [
		[-0.02, 0.017, 0.025, 0.0],
		[0.03, 0.02, 0.037, 0.0],
		[0.08, 0.017, 0.035, 0.004],
		[0.12, 0.014, 0.028, 0.012],
		[0.15, 0.009, 0.016, 0.022],
	]
	# 手指自然向掌心（大腿一侧）微曲
	var rings: Array = []
	for s in spec:
		rings.append({"c": wrist + Vector3(-side * float(s[3]), -float(s[0]), -0.004), "u": Vector3(float(s[1]), 0, 0), "v": Vector3(0, 0, float(s[2])), "sq": 2.2, "b": [hb, hb, 0.0]})
	_loft(_buf, rings, 10, true, true, func(_p: Vector3) -> Array: return [skin_color, T_SKIN])
	# 大拇指
	_prim(_buf, "capsule", Vector3(0.022, 0.07, 0.022), wrist + Vector3(-side * 0.004, -0.05, -0.04), skin_color, Vector3(-0.5, 0, side * 0.2), hb, T_SKIN)


## 外套、腰带、灯带等附加零件
func _clothes_details(w: float) -> void:
	if accent_strip:
		_prim(_glow, "box", Vector3(0.026, 0.22, 0.012), Vector3(0.075 * w, 1.31, -0.132), accent_color, Vector3(0.06, 0, 0), CHEST, T_ACCENT)
	if jacket:
		# 立领、银色拉链、背后垂着的卫衣帽子
		var collar: Array = []
		for s in [[1.465, 0.085, 0.078], [1.505, 0.074, 0.07], [1.53, 0.068, 0.066]]:
			collar.append({"c": Vector3(0, float(s[0]), 0.004), "u": Vector3(float(s[1]), 0, 0), "v": Vector3(0, 0, float(s[2])), "sq": 2.0, "b": [CHEST, NECK, 0.3]})
		_loft(_buf, collar, 16, false, false, func(_p: Vector3) -> Array: return [shirt_color.lightened(0.04), T_SHIRT_LIGHT], true)
		var zy := [1.035, 1.08, 1.18, 1.28, 1.36, 1.415, 1.46]
		var zz := [-0.108, -0.104, -0.114, -0.13, -0.124, -0.108, -0.086]
		for i in zy.size() - 1:
			var a := Vector3(0, zy[i], zz[i] - 0.003)
			var b := Vector3(0, zy[i + 1], zz[i + 1] - 0.003)
			var mid := (a + b) * 0.5
			var ang := atan2(b.z - a.z, b.y - a.y)
			_prim(_buf, "box", Vector3(0.012, a.distance_to(b) + 0.004, 0.006), mid, Color(0.72, 0.73, 0.75), Vector3(ang, 0, 0), SPINE if mid.y < 1.2 else CHEST)
		_prim(_buf, "capsule", Vector3(0.24, 0.18, 0.1), Vector3(0, 1.45, 0.115), shirt_color.darkened(0.25), Vector3(0.45, 0, 0), CHEST, T_SHIRT_D25)
	else:
		# 普通上衣：圆领口
		_prim(_buf, "cylinder", Vector3(0.132, 0.02, 0.132), Vector3(0, 1.49, 0.004), shirt_color.darkened(0.12), Vector3(0.12, 0, 0), CHEST, T_SHIRT_D12)
	if chain:
		var gold := Color(0.86, 0.66, 0.26)
		for sx in [-1.0, 1.0]:
			for i in 9:
				var t := float(i) / 8.0
				_prim(_buf, "sphere", Vector3(0.014, 0.014, 0.014), Vector3(sx * lerpf(0.07, 0.0, t), lerpf(1.49, 1.33, t), lerpf(-0.07, -0.132, t)), gold, Vector3.ZERO, CHEST)


## 头部：放样出下巴、下颌、颧骨、额头、后脑的连续轮廓，发际线直接画在头皮上，另加头顶发量；
## 五官（眼白 + 瞳孔、眉毛、鼻梁 + 鼻头、嘴唇、耳朵）为小零件。坐标以 Head 骨头为原点，前方为 -Z。
func _head() -> void:
	var hb := bone_global(HEAD)
	# [y, 半宽, 半厚, 中心 z, 方正程度]
	var spec := [
		[0.0, 0.018, 0.02, -0.058, 2.0],
		[0.014, 0.034, 0.04, -0.048, 2.2],
		[0.04, 0.056, 0.07, -0.022, 2.4],
		[0.07, 0.067, 0.088, -0.006, 2.4],
		[0.1, 0.073, 0.096, 0.0, 2.3],
		[0.13, 0.077, 0.1, 0.004, 2.2],
		[0.16, 0.079, 0.102, 0.008, 2.2],
		[0.19, 0.077, 0.1, 0.012, 2.1],
		[0.215, 0.069, 0.09, 0.014, 2.0],
		[0.236, 0.05, 0.066, 0.014, 2.0],
		[0.25, 0.018, 0.026, 0.012, 2.0],
	]
	var rings: Array = []
	for sp in spec:
		rings.append({"c": hb + Vector3(0, float(sp[0]), float(sp[3])), "u": Vector3(float(sp[1]), 0, 0), "v": Vector3(0, 0, float(sp[2])), "sq": float(sp[4]), "b": [HEAD, HEAD, 0.0]})
	_loft(_buf, rings, 18, true, true, func(p: Vector3) -> Array:
		var l := p - hb
		var hair := l.y > 0.196 or (l.z > 0.03 and l.y > 0.05) or (absf(l.x) > 0.06 and l.z > -0.025 and l.y > 0.118)
		return [hair_color, T_HAIR] if hair else [skin_color, T_SKIN])
	# 头顶发量（比头皮大一圈，偏后）
	var cap: Array = []
	for sp in [[0.17, 0.078, 0.098, 0.03], [0.2, 0.084, 0.106, 0.018], [0.228, 0.076, 0.098, 0.016], [0.252, 0.05, 0.068, 0.014], [0.266, 0.016, 0.024, 0.012]]:
		cap.append({"c": hb + Vector3(0, float(sp[0]), float(sp[3])), "u": Vector3(float(sp[1]), 0, 0), "v": Vector3(0, 0, float(sp[2])), "sq": 2.1, "b": [HEAD, HEAD, 0.0]})
	_loft(_buf, cap, 18, false, true, func(_p: Vector3) -> Array: return [hair_color, T_HAIR])
	var eye_white := Color(0.9, 0.89, 0.86)
	var iris := Color(0.07, 0.05, 0.04)
	for sx in [-1.0, 1.0]:
		_prim(_buf, "sphere", Vector3(0.026, 0.014, 0.01), hb + Vector3(sx * 0.032, 0.13, -0.087), eye_white, Vector3.ZERO, HEAD)
		_prim(_buf, "sphere", Vector3(0.012, 0.012, 0.006), hb + Vector3(sx * 0.031, 0.13, -0.0915), iris, Vector3.ZERO, HEAD)
		# 上眼睑的阴影与眉毛
		_prim(_buf, "box", Vector3(0.028, 0.004, 0.006), hb + Vector3(sx * 0.032, 0.138, -0.09), skin_color.darkened(0.25), Vector3(0, 0, 0), HEAD, T_SKIN_D25)
		_prim(_buf, "box", Vector3(0.032, 0.007, 0.009), hb + Vector3(sx * 0.034, 0.153, -0.094), hair_color, Vector3(0, 0, -sx * 0.12), HEAD, T_HAIR)
		# 耳朵
		_prim(_buf, "sphere", Vector3(0.016, 0.052, 0.032), hb + Vector3(sx * 0.078, 0.122, 0.012), skin_color.darkened(0.08), Vector3(0, -sx * 0.25, 0), HEAD, T_SKIN_D8)
	# 鼻梁 + 鼻头
	_prim(_buf, "box", Vector3(0.016, 0.046, 0.018), hb + Vector3(0, 0.118, -0.1), skin_color.darkened(0.03), Vector3(-0.32, 0, 0), HEAD, T_SKIN_D3)
	_prim(_buf, "sphere", Vector3(0.03, 0.018, 0.022), hb + Vector3(0, 0.097, -0.106), skin_color.darkened(0.05), Vector3.ZERO, HEAD, T_SKIN_D5)
	# 嘴唇
	var lip := skin_color.lerp(Color(0.62, 0.3, 0.3), 0.45)
	_prim(_buf, "capsule", Vector3(0.012, 0.036, 0.008), hb + Vector3(0, 0.074, -0.093), lip, Vector3(0, 0, PI * 0.5), HEAD, T_LIP)
	_prim(_buf, "capsule", Vector3(0.01, 0.03, 0.007), hb + Vector3(0, 0.066, -0.09), lip.darkened(0.1), Vector3(0, 0, PI * 0.5), HEAD, T_LIP)
	if beard == "goatee":
		_hp("box", Vector3(0.062, 0.01, 0.01), Vector3(0, 0.154, -0.121), beard_color, Vector3.ZERO, false, T_BEARD)
		for sx in [-1.0, 1.0]:
			_hp("box", Vector3(0.008, 0.026, 0.01), Vector3(sx * 0.03, 0.142, -0.118), beard_color, Vector3.ZERO, false, T_BEARD)
		_hp("box", Vector3(0.036, 0.034, 0.012), Vector3(0, 0.097, -0.103), beard_color, Vector3(0.35, 0, 0), false, T_BEARD)
	if earring:
		_prim(_buf, "sphere", Vector3(0.012, 0.012, 0.012), hb + Vector3(-0.082, 0.098, 0.012), Color(0.8, 0.8, 0.82), Vector3.ZERO, HEAD)


func _hat_parts() -> void:
	var o := Vector3(0, 0.32, 0)
	match hat:
		"yellow":
			_hp("dome", Vector3(0.33, 0.165, 0.33), o + Vector3(0, -0.04, 0), Color(0.98, 0.78, 0.1))
		"visor":
			_hp("box", Vector3(0.28, 0.06, 0.05), o + Vector3(0, -0.1, -0.13), accent_color, Vector3.ZERO, true, T_ACCENT)
		"snapback":
			# 黑色平檐棒球帽：帽顶、平帽檐（檐下绿色）、帽顶纽扣、正面红色刺绣徽标（通用翅膀图案，不用真实品牌）
			var black := Color(0.06, 0.06, 0.07)
			_hp("dome", Vector3(0.29, 0.15, 0.29), o + Vector3(0, -0.06, 0.005), black)
			_hp("box", Vector3(0.22, 0.014, 0.16), o + Vector3(0, -0.05, -0.2), black, Vector3(0.06, 0, 0))
			_hp("box", Vector3(0.215, 0.008, 0.155), o + Vector3(0, -0.059, -0.198), Color(0.08, 0.3, 0.17), Vector3(0.06, 0, 0))
			_hp("sphere", Vector3(0.025, 0.012, 0.025), o + Vector3(0, 0.09, 0.005), black)
			var red := Color(0.86, 0.1, 0.12)
			_hp("box", Vector3(0.075, 0.016, 0.006), o + Vector3(0.015, 0.03, -0.128), red, Vector3(-0.45, 0, 0.3))
			_hp("box", Vector3(0.04, 0.012, 0.006), o + Vector3(-0.022, 0.022, -0.13), red, Vector3(-0.45, 0, -0.25))
			_hp("box", Vector3(0.11, 0.02, 0.006), o + Vector3(0, -0.005, -0.14), red, Vector3(-0.3, 0, 0))


## 头部零件：坐标用旧版头部系（头中心 y = 0.2），经 HEAD_XF 换算后绑到 Head 骨头
func _hp(kind: String, size: Vector3, pos: Vector3, col: Color, rot := Vector3.ZERO, glow := false, tag := T_NONE) -> void:
	var xf := Transform3D(Basis.from_euler(rot), pos)
	var head := Transform3D(Basis(), bone_global(HEAD)) * HEAD_XF * xf
	_prim_xf(_glow if glow else _buf, kind, size, head, col, HEAD, tag)


func _prim(buf: Buf, kind: String, size: Vector3, pos: Vector3, col: Color, rot: Vector3, bone: int, tag := T_NONE) -> void:
	_prim_xf(buf, kind, size, Transform3D(Basis.from_euler(rot), pos), col, bone, tag)


## 基础几何体零件（整块绑在一根骨头上）
func _prim_xf(buf: Buf, kind: String, size: Vector3, xf: Transform3D, col: Color, bone: int, tag: int) -> void:
	var mesh: PrimitiveMesh
	var sc := Vector3.ONE
	match kind:
		"box":
			var bm := BoxMesh.new()
			bm.size = size
			mesh = bm
		"sphere":
			var sm := SphereMesh.new()
			sm.radius = size.x * 0.5
			sm.height = size.y
			sm.radial_segments = 14
			sm.rings = 8
			mesh = sm
			sc = Vector3(1, 1, size.z / maxf(size.x, 0.001))
		"capsule":
			var cm := CapsuleMesh.new()
			cm.radius = size.x * 0.5
			cm.height = maxf(size.y, cm.radius * 2.0)
			cm.radial_segments = 10
			cm.rings = 3
			mesh = cm
			sc = Vector3(1, 1, size.z / maxf(size.x, 0.001))
		"dome":
			var hm := SphereMesh.new()
			hm.radius = size.x * 0.5
			hm.height = size.y
			hm.is_hemisphere = true
			hm.radial_segments = 16
			hm.rings = 6
			mesh = hm
		_:
			var cy := CylinderMesh.new()
			cy.top_radius = size.x * 0.5
			cy.bottom_radius = size.z * 0.5
			cy.height = size.y
			cy.radial_segments = 16
			cy.cap_top = false
			cy.cap_bottom = false
			mesh = cy
	var full := xf * Transform3D(Basis.from_scale(sc), Vector3.ZERO)
	var nb := full.basis.inverse().transposed()
	var arr: Array = mesh.get_mesh_arrays()
	var base := buf.verts.size()
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	for i in vs.size():
		buf.add(full * vs[i], (nb * ns[i]).normalized(), col, tag, bone, bone, 0.0)
	for i in arr[Mesh.ARRAY_INDEX] as PackedInt32Array:
		buf.idx.append(base + i)


## 截面放样：rings 为 {c 中心, u / v 两个半轴, sq 方正程度（2 = 椭圆）, b [骨头0, 骨头1, 骨头1的权重]}
## paint(顶点位置) 返回 [颜色, 标签]
func _loft(buf: Buf, rings: Array, seg: int, cap_start: bool, cap_end: bool, paint: Callable, double_sided := false) -> void:
	if _wind == 0.0:
		_wind = _detect_winding()
	var base := buf.verts.size()
	var n := rings.size()
	var pts := PackedVector3Array()
	var nor := PackedVector3Array()
	for r in rings:
		var e := 2.0 / float(r["sq"])
		for k in seg:
			var a := TAU * float(k) / seg
			var ca := cos(a)
			var sa := sin(a)
			var cx := signf(ca) * pow(absf(ca), e)
			var sx := signf(sa) * pow(absf(sa), e)
			pts.append((r["c"] as Vector3) + (r["u"] as Vector3) * cx + (r["v"] as Vector3) * sx)
			nor.append(Vector3.ZERO)
	var tris := PackedInt32Array()
	# 同一条放样的绕序一致：用第一个四边形判断一次
	var flip := _oriented(pts, 0, seg, 1, rings[0]["c"], rings[1]["c"])[1] != seg
	for i in n - 1:
		for k in seg:
			var k2 := (k + 1) % seg
			var a := i * seg + k
			var b := i * seg + k2
			var c := (i + 1) * seg + k
			var d := (i + 1) * seg + k2
			if flip:
				tris.append_array([a, b, c, b, d, c])
			else:
				tris.append_array([a, c, b, b, c, d])
	# 两端封口（扇形）
	var caps := []
	if cap_start:
		caps.append(0)
	if cap_end:
		caps.append(n - 1)
	var cap_centers := {}
	for ci in caps:
		var r: Dictionary = rings[ci]
		var neighbor: Vector3 = rings[1 if ci == 0 else n - 2]["c"]
		var tip: Vector3 = r["c"] + ((r["c"] as Vector3) - neighbor).normalized() * minf((r["u"] as Vector3).length(), (r["v"] as Vector3).length()) * 0.6
		var ti := pts.size()
		pts.append(tip)
		nor.append(Vector3.ZERO)
		cap_centers[ti] = ci
		var cap_flip: bool = _oriented(pts, ci * seg, ci * seg + 1, ti, neighbor, neighbor)[1] != ci * seg + 1
		for k in seg:
			var a: int = ci * seg + k
			var b: int = ci * seg + (k + 1) % seg
			if cap_flip:
				tris.append_array([a, ti, b])
			else:
				tris.append_array([a, b, ti])
	# 平滑法线：面法线累加
	for t in range(0, tris.size(), 3):
		var fn := (pts[tris[t + 1]] - pts[tris[t]]).cross(pts[tris[t + 2]] - pts[tris[t]]) * _wind
		for j in 3:
			nor[tris[t + j]] += fn
	for i in pts.size():
		var ri: int = cap_centers.get(i, mini(i / seg, n - 1))
		var r: Dictionary = rings[ri]
		var bb: Array = r["b"]
		var pc: Array = paint.call(pts[i])
		var nn := nor[i].normalized() if nor[i].length_squared() > 1e-12 else Vector3.UP
		buf.add(pts[i], nn, pc[0], pc[1], int(bb[0]), int(bb[1]), float(bb[2]))
	for t in tris:
		buf.idx.append(base + t)
	if double_sided:
		var base2 := buf.verts.size()
		for i in pts.size():
			buf.verts.append(buf.verts[base + i])
			buf.norms.append(-buf.norms[base + i])
			buf.cols.append(buf.cols[base + i])
			buf.tags.append(buf.tags[base + i])
			buf.bones.append_array(buf.bones.slice((base + i) * 4, (base + i) * 4 + 4))
			buf.weights.append_array(buf.weights.slice((base + i) * 4, (base + i) * 4 + 4))
		for t in range(0, tris.size(), 3):
			buf.idx.append_array([base2 + tris[t], base2 + tris[t + 2], base2 + tris[t + 1]])


## 让三角形朝外（按引擎的正面绕序）
func _oriented(pts: PackedVector3Array, a: int, b: int, c: int, c0: Vector3, c1: Vector3) -> PackedInt32Array:
	var fn := (pts[b] - pts[a]).cross(pts[c] - pts[a])
	var mid := (pts[a] + pts[b] + pts[c]) / 3.0
	# 离轴线最近的点作为参考中心
	var axis := c1 - c0
	var ref := c0
	if axis.length_squared() > 1e-8:
		ref = c0 + axis * clampf((mid - c0).dot(axis) / axis.length_squared(), 0.0, 1.0)
	var out := mid - ref
	if fn.dot(out) * _wind < 0.0:
		return PackedInt32Array([a, c, b])
	return PackedInt32Array([a, b, c])


## 从引擎自带的球体网格推断正面绕序（叉积与法线同向为 1，否则为 -1）
static func _detect_winding() -> float:
	var sm := SphereMesh.new()
	var arr := sm.get_mesh_arrays()
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var nn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var sum := 0.0
	for t in range(0, mini(ix.size(), 300), 3):
		var fn := (v[ix[t + 1]] - v[ix[t]]).cross(v[ix[t + 2]] - v[ix[t]])
		sum += fn.dot(nn[ix[t]] + nn[ix[t + 1]] + nn[ix[t + 2]])
	return 1.0 if sum >= 0.0 else -1.0


# ---------- 外观 ----------

## 外观数据：{"skin": "#..", "shirt": "#..", "pants": "#..", "hair": "#..", "hat": "yellow"}
func apply_look(look: Dictionary) -> void:
	skin_color = Mats.hex(String(look.get("skin", "")), skin_color)
	shirt_color = Mats.hex(String(look.get("shirt", "")), shirt_color)
	pants_color = Mats.hex(String(look.get("pants", "")), pants_color)
	hair_color = Mats.hex(String(look.get("hair", "")), hair_color)
	hat = String(look.get("hat", hat))


## 换衣服：只改上衣和裤子颜色（不重新生成网格）
func set_clothes(shirt: Color, pants: Color) -> void:
	shirt_color = shirt
	pants_color = pants
	if not _built:
		return
	_recolor(_buf)
	_commit()


func set_hat(kind: String) -> void:
	hat = kind
	if _built:
		_generate()
