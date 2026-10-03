class_name WeaponView
extends Node3D
## 第一人称手中的武器（路线图 2.4；GDD.md 第四节「只显示武器」）。挂在相机下，坐标是相机空间：x 右、y 上、-z 前。
## 占位短剑：剑身、护手、握柄、剑首四块，用 MeshKit 合成一个网格（正式模型在阶段 A）。剑身沿本地 +y，剑脊薄的方向是本地 z。
## 姿势 = [位置, 剑尖方向, 剑面法线]；挥动就是在两个姿势之间插值（Melee 驱动），不用骨骼动画。
## 3.3 拳头（fists）：两只占位的拳头 + 袖子。右拳按姿势表出拳（方向 = 小臂指向拳面，法线 = 手背朝向）；
## 左拳平时护在胸前，格挡时跟着举到面前（off_raise，Melee 驱动）。拳头时本节点不动，姿势直接摆在两只拳头上。

## 姿势表（相机空间）
const POSES := {
	"rest": [Vector3(0.24, -0.30, -0.52), Vector3(-0.22, 0.62, -0.75), Vector3(1, 0, 0.3)],
	"lowered": [Vector3(0.30, -0.90, -0.35), Vector3(0.0, 0.7, -0.7), Vector3(1, 0, 0)],
	"l1_wind": [Vector3(0.48, -0.12, -0.40), Vector3(0.80, 0.50, 0.30), Vector3(0, 1, 0.2)],
	"l1_end": [Vector3(-0.30, -0.26, -0.52), Vector3(-0.85, 0.05, -0.50), Vector3(0, 1, -0.1)],
	"l2_wind": [Vector3(-0.34, -0.10, -0.42), Vector3(-0.80, 0.50, 0.30), Vector3(0, 1, 0.2)],
	"l2_end": [Vector3(0.34, -0.28, -0.52), Vector3(0.85, 0.0, -0.50), Vector3(0, 1, -0.1)],
	"h_wind": [Vector3(0.22, 0.06, -0.28), Vector3(0.10, 0.70, 0.70), Vector3(1, 0, 0)],
	"h_end": [Vector3(0.04, -0.46, -0.58), Vector3(0.0, -0.35, -0.94), Vector3(1, 0, 0)],
	"block": [Vector3(0.20, -0.26, -0.68), Vector3(-0.68, 0.66, -0.30), Vector3(0, 0.3, 1)],     # 剑斜架在面前（不糊满画面）
}
## 拳头的姿势表（同样的键，Melee 不用分武器）：轻拳一刺拳、二直拳，重拳是从右边抡过来的摆拳；格挡时右拳竖在面前
const FIST_POSES := {
	"rest": [Vector3(0.17, -0.20, -0.46), Vector3(-0.25, 0.70, -0.65), Vector3(1, 0, 0.3)],
	"lowered": [Vector3(0.26, -0.80, -0.30), Vector3(0.0, 0.6, -0.8), Vector3(1, 0, 0)],
	"l1_wind": [Vector3(0.20, -0.22, -0.32), Vector3(-0.10, 0.20, -0.97), Vector3(1, 0.3, 0)],
	"l1_end": [Vector3(0.06, -0.13, -0.80), Vector3(-0.12, 0.06, -0.99), Vector3(0.3, 1, 0)],
	"l2_wind": [Vector3(0.26, -0.27, -0.30), Vector3(-0.20, 0.25, -0.95), Vector3(1, 0, 0)],
	"l2_end": [Vector3(-0.02, -0.12, -0.76), Vector3(-0.35, 0.06, -0.94), Vector3(0.2, 1, 0)],
	"h_wind": [Vector3(0.42, -0.18, -0.34), Vector3(-0.55, 0.15, -0.82), Vector3(0, 1, 0)],
	"h_end": [Vector3(-0.10, -0.14, -0.62), Vector3(-0.95, 0.05, -0.30), Vector3(0, 1, 0)],
	"block": [Vector3(0.09, -0.12, -0.42), Vector3(-0.10, 1.0, 0.10), Vector3(0, 0, -1)],
}
## 左拳：护在胸前 / 格挡时举到面前
const OFF_GUARD := [Vector3(-0.19, -0.22, -0.46), Vector3(0.25, 0.70, -0.65), Vector3(-1, 0, 0.3)]
const OFF_BLOCK := [Vector3(-0.11, -0.12, -0.42), Vector3(0.10, 1.0, 0.10), Vector3(0, 0, -1)]
const BLADE_LEN := 0.62

var pose_pos := Vector3.ZERO
var pose_dir := Vector3.UP
var pose_face := Vector3.RIGHT
var kick := Vector3.ZERO          # 命中时的小回弹（位置偏移，逐帧衰减）
var model := ""
var model_hidden := false
var mesh_node: MeshInstance3D
var off_node: MeshInstance3D      # 拳头时的左拳
var off_raise := 0.0              # 左拳举起的程度：0 = 护在胸前，1 = 举到面前（格挡）


func _ready() -> void:
	if model == "":
		set_model("sword")
	set_pose(POSES.lowered)
	visible = false


## 换外观：sword（剑身、护手、握柄、剑首）/ club（裹铁皮的木棍）（2.6）/ fists（两只拳头，3.3）
func set_model(m: String) -> void:
	if m == model and mesh_node:
		return
	model = m
	for n in [mesh_node, off_node]:
		if n:
			remove_child(n)
			n.queue_free()
	off_node = null
	var kit := MeshKit.new()
	if m == "fists":
		kit.box("sleeve", Vector3(0, -0.2, 0), Vector3(0.07, 0.24, 0.07))           # 袖子（小臂）
		kit.box("skin", Vector3(0, -0.06, 0), Vector3(0.05, 0.04, 0.046))           # 手腕
		kit.box("skin", Vector3(0, 0.0, 0), Vector3(0.074, 0.08, 0.072))            # 拳头
		kit.box("knuckle", Vector3(0, 0.043, -0.004), Vector3(0.07, 0.01, 0.06))    # 指节
		kit.box("skin", Vector3(0.04, 0.008, -0.018), Vector3(0.018, 0.045, 0.026)) # 拇指
	elif m == "club":
		kit.cylinder("leather", Vector3(0, -0.12, 0), Vector3(0, 0.08, 0), 0.022, 0.022, 6)
		kit.cylinder("wood", Vector3(0, 0.08, 0), Vector3(0, 0.62, 0), 0.026, 0.045, 6)
		kit.cylinder("iron", Vector3(0, 0.48, 0), Vector3(0, 0.62, 0), 0.05, 0.05, 6)
	else:
		kit.box("steel", Vector3(0, 0.09 + BLADE_LEN * 0.5, 0), Vector3(0.045, BLADE_LEN, 0.008))
		kit.box("steel", Vector3(0, 0.09 + BLADE_LEN + 0.025, 0), Vector3(0.02, 0.05, 0.006))      # 剑尖收窄
		kit.box("iron", Vector3(0, 0.08, 0), Vector3(0.20, 0.025, 0.03))                          # 护手
		kit.box("leather", Vector3(0, -0.02, 0), Vector3(0.032, 0.18, 0.032))                     # 握柄
		kit.box("iron", Vector3(0, -0.125, 0), Vector3(0.05, 0.04, 0.05))                         # 剑首
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color("b4bcc6")
	steel.metallic = 0.35
	steel.roughness = 0.4
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color("4a4d52")
	iron.metallic = 0.3
	iron.roughness = 0.5
	var leather := StandardMaterial3D.new()
	leather.albedo_color = Color("3a2a1e")
	leather.roughness = 0.9
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("6a4a30")
	wood.roughness = 0.85
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color("b08a76")
	skin.roughness = 0.8
	var knuckle := StandardMaterial3D.new()
	knuckle.albedo_color = Color("9a7462")
	knuckle.roughness = 0.8
	var sleeve := StandardMaterial3D.new()
	sleeve.albedo_color = Color("4a3a2c")
	sleeve.roughness = 0.95
	for mat in [steel, iron, leather, wood, skin, knuckle, sleeve]:
		mat.vertex_color_use_as_albedo = true
		# 一点点自发光：背光站着时（训练场火把在敌人身后）剑也不会变成一根黑棍（2.5 截图）
		mat.emission_enabled = true
		mat.emission = mat.albedo_color
		mat.emission_energy_multiplier = 0.12
	mesh_node = kit.build({"steel": steel, "iron": iron, "leather": leather, "wood": wood, "skin": skin, "knuckle": knuckle, "sleeve": sleeve})
	mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_node.name = "Model"
	add_child(mesh_node)
	mesh_node.visible = not model_hidden
	if m == "fists":
		off_node = MeshInstance3D.new()
		off_node.name = "OffHand"
		off_node.mesh = mesh_node.mesh                  # 左拳用同一个网格（拇指在内侧，左右看不出差别）
		off_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(off_node)
		off_node.visible = not model_hidden
	_apply()


## 姿势表里的一个姿势（按现在的外观：剑 / 木棍用 POSES，拳头用 FIST_POSES）
func pose(key: String) -> Array:
	return FIST_POSES[key] if model == "fists" else POSES[key]


## 第三人称时藏起第一人称的武器（剑由 PlayerAvatar 拿着）
func hide_model(on: bool) -> void:
	model_hidden = on
	for n in [mesh_node, off_node]:
		if n:
			n.visible = not on


## 直接摆到某个姿势
func set_pose(p: Array) -> void:
	pose_pos = p[0]
	pose_dir = (p[1] as Vector3).normalized()
	pose_face = (p[2] as Vector3).normalized()
	_apply()


## a → b 插值，t 0..1
func blend(a: Array, b: Array, t: float) -> void:
	pose_pos = (a[0] as Vector3).lerp(b[0], t)
	pose_dir = (a[1] as Vector3).normalized().slerp((b[1] as Vector3).normalized(), t)
	pose_face = (a[2] as Vector3).normalized().lerp((b[2] as Vector3).normalized(), t)
	_apply()


## 当前姿势（作为下一段插值的起点）
func current() -> Array:
	return [pose_pos, pose_dir, pose_face]


func _apply() -> void:
	var t := _xform(pose_pos, pose_dir, pose_face)
	t.origin += kick
	if model == "fists" and mesh_node and off_node:
		# 拳头：本节点不动，两只拳头各摆各的（左拳的网格左右镜像，基向量里补一个 -X）
		transform = Transform3D.IDENTITY
		mesh_node.transform = t
		var k := clampf(off_raise, 0.0, 1.0)
		var o := _xform((OFF_GUARD[0] as Vector3).lerp(OFF_BLOCK[0], k), (OFF_GUARD[1] as Vector3).lerp(OFF_BLOCK[1], k),
			(OFF_GUARD[2] as Vector3).lerp(OFF_BLOCK[2], k))
		off_node.transform = Transform3D(o.basis * Basis.from_scale(Vector3(-1, 1, 1)), o.origin)
		return
	if mesh_node:
		mesh_node.transform = Transform3D.IDENTITY
	transform = t


## 姿势 → 相机空间的变换：y 轴沿方向，z 轴沿法线（去掉和方向平行的部分）
func _xform(pos: Vector3, dir: Vector3, face: Vector3) -> Transform3D:
	var y := dir.normalized()
	var z := face - y * face.dot(y)
	if z.length() < 0.01:
		z = Vector3.BACK - y * y.z
	z = z.normalized()
	var x := y.cross(z)
	var p := pos
	p.x *= narrow_factor()
	return Transform3D(Basis(x, y, z), p)


## 竖屏手机的水平视野窄（相机按高度保持视野），姿势的左右偏移按宽高比收拢，剑才不会跑出画面（2.4 截图）
func narrow_factor() -> float:
	if not is_inside_tree():
		return 1.0
	var r := get_viewport().get_visible_rect().size
	if r.y <= 0.0:
		return 1.0
	return clampf((r.x / r.y) / (16.0 / 9.0), 0.45, 1.0)
