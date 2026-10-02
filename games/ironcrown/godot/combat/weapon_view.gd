class_name WeaponView
extends Node3D
## 第一人称手中的武器（路线图 2.4；GDD.md 第四节「只显示武器」）。挂在相机下，坐标是相机空间：x 右、y 上、-z 前。
## 占位短剑：剑身、护手、握柄、剑首四块，用 MeshKit 合成一个网格（正式模型在阶段 A）。剑身沿本地 +y，剑脊薄的方向是本地 z。
## 姿势 = [位置, 剑尖方向, 剑面法线]；挥动就是在两个姿势之间插值（Melee 驱动），不用骨骼动画。

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
const BLADE_LEN := 0.62

var pose_pos := Vector3.ZERO
var pose_dir := Vector3.UP
var pose_face := Vector3.RIGHT
var kick := Vector3.ZERO          # 命中时的小回弹（位置偏移，逐帧衰减）
var model := ""
var mesh_node: MeshInstance3D


func _ready() -> void:
	if model == "":
		set_model("sword")
	set_pose(POSES.lowered)
	visible = false


## 换外观：sword（剑身、护手、握柄、剑首）/ club（裹铁皮的木棍）（2.6）
func set_model(m: String) -> void:
	if m == model and mesh_node:
		return
	model = m
	if mesh_node:
		remove_child(mesh_node)
		mesh_node.queue_free()
	var kit := MeshKit.new()
	if m == "club":
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
	for mat in [steel, iron, leather, wood]:
		mat.vertex_color_use_as_albedo = true
		# 一点点自发光：背光站着时（训练场火把在敌人身后）剑也不会变成一根黑棍（2.5 截图）
		mat.emission_enabled = true
		mat.emission = mat.albedo_color
		mat.emission_energy_multiplier = 0.12
	mesh_node = kit.build({"steel": steel, "iron": iron, "leather": leather, "wood": wood})
	mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_node.name = "Model"
	add_child(mesh_node)


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
	var y := pose_dir.normalized()
	var z := pose_face - y * pose_face.dot(y)
	if z.length() < 0.01:
		z = Vector3.BACK - y * y.z
	z = z.normalized()
	var x := y.cross(z)
	var p := pose_pos
	p.x *= narrow_factor()
	transform = Transform3D(Basis(x, y, z), p + kick)


## 竖屏手机的水平视野窄（相机按高度保持视野），姿势的左右偏移按宽高比收拢，剑才不会跑出画面（2.4 截图）
func narrow_factor() -> float:
	if not is_inside_tree():
		return 1.0
	var r := get_viewport().get_visible_rect().size
	if r.y <= 0.0:
		return 1.0
	return clampf((r.x / r.y) / (16.0 / 9.0), 0.45, 1.0)
