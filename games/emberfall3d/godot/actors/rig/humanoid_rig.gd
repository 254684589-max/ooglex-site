class_name HumanoidRig
extends Node3D
## 程序化人形角色（2.6 之三，方案 1）：Skeleton3D + 一个蒙皮网格（CharModels 按配方用 RigBuilder 生成，同种角色共用网格），
## 动作全部由代码算出骨骼姿势，不用动作文件：
##   走 / 跑（按实际移动速度推进步伐相位）、待机呼吸、挥砍、施法、双手施法、旋转斩、拉弓、受击后仰、倒下。
## 骨骼名沿用 Godot 的人形骨骼规范（SkeletonProfileHumanoid 的子集），以后换成正式模型时动作接口不用改。
## 用法：做动作期间持续调用 act(种类, 阶段, 进度)（物理帧或画面帧都行），每个画面帧调用 tick(delta, 水平速度)；
## 停止调用 act 后动作层 0.12 秒内淡出。
##   阶段："windup" 蓄力（进度 0→1 举起）、"strike" 出手（0→1 挥过去）、"recover" 收招（0→1 回到站姿）

const BONES := [
	["Hips", ""], ["Spine", "Hips"], ["Chest", "Spine"], ["Neck", "Chest"], ["Head", "Neck"],
	["LeftUpperArm", "Chest"], ["LeftLowerArm", "LeftUpperArm"], ["LeftHand", "LeftLowerArm"],
	["RightUpperArm", "Chest"], ["RightLowerArm", "RightUpperArm"], ["RightHand", "RightLowerArm"],
	["LeftUpperLeg", "Hips"], ["LeftLowerLeg", "LeftUpperLeg"], ["LeftFoot", "LeftLowerLeg"],
	["RightUpperLeg", "Hips"], ["RightLowerLeg", "RightUpperLeg"], ["RightFoot", "RightLowerLeg"],
]

## 动作关键姿势（角度，度；x 前后摆、y 扭转、z 侧抬）。没写的骨骼沿用走路 / 待机的姿势。
## 右臂向前抬是 x 为负；左臂向外抬 z 为正、右臂向外抬 z 为负；上身前倾 x 为正；上身向左扭 y 为正。
const ACTIONS := {
	"attack": {
		"raised": {"RightUpperArm": Vector3(-150, 0, -25), "RightLowerArm": Vector3(-60, 0, 0), "Chest": Vector3(0, -28, 0), "Spine": Vector3(-6, 0, 0), "LeftUpperArm": Vector3(-25, 0, 18)},
		"follow": {"RightUpperArm": Vector3(-38, 0, 28), "RightLowerArm": Vector3(-12, 0, 0), "Chest": Vector3(8, 32, 0), "Spine": Vector3(12, 0, 0), "LeftUpperArm": Vector3(22, 0, 22)},
	},
	"cast": {
		"raised": {"RightUpperArm": Vector3(-110, 0, -25), "RightLowerArm": Vector3(-85, 0, 0), "Chest": Vector3(0, -22, 0), "LeftUpperArm": Vector3(-20, 0, 15)},
		"follow": {"RightUpperArm": Vector3(-88, 0, 6), "RightLowerArm": Vector3(-6, 0, 0), "Chest": Vector3(6, 18, 0), "Spine": Vector3(6, 0, 0), "LeftUpperArm": Vector3(-35, 0, 12)},
	},
	"cast2": {
		"raised": {"RightUpperArm": Vector3(-155, 0, -30), "LeftUpperArm": Vector3(-155, 0, 30), "RightLowerArm": Vector3(-30, 0, 0), "LeftLowerArm": Vector3(-30, 0, 0), "Spine": Vector3(-10, 0, 0), "Head": Vector3(-15, 0, 0)},
		"follow": {"RightUpperArm": Vector3(-25, 0, -70), "LeftUpperArm": Vector3(-25, 0, 70), "RightLowerArm": Vector3(-10, 0, 0), "LeftLowerArm": Vector3(-10, 0, 0), "Spine": Vector3(18, 0, 0), "Head": Vector3(10, 0, 0)},
	},
	"spin": {
		"raised": {"RightUpperArm": Vector3(-70, 0, -75), "LeftUpperArm": Vector3(-40, 0, 75), "RightLowerArm": Vector3(-10, 0, 0), "LeftLowerArm": Vector3(-15, 0, 0), "Spine": Vector3(8, 0, 0)},
		"follow": {"RightUpperArm": Vector3(-70, 0, -75), "LeftUpperArm": Vector3(-40, 0, 75), "RightLowerArm": Vector3(-10, 0, 0), "LeftLowerArm": Vector3(-15, 0, 0), "Spine": Vector3(8, 0, 0)},
	},
	"shoot": {
		"raised": {"LeftUpperArm": Vector3(-88, 0, 8), "LeftLowerArm": Vector3(-4, 0, 0), "RightUpperArm": Vector3(-88, 0, -30), "RightLowerArm": Vector3(-135, 0, 0), "Chest": Vector3(0, 22, 0), "Head": Vector3(0, -18, 0)},
		"follow": {"LeftUpperArm": Vector3(-86, 0, 8), "LeftLowerArm": Vector3(-4, 0, 0), "RightUpperArm": Vector3(-70, 0, -55), "RightLowerArm": Vector3(-95, 0, 0), "Chest": Vector3(0, 18, 0), "Head": Vector3(0, -15, 0)},
	},
}

var model_id := ""
var style: Dictionary = {}
var skeleton: Skeleton3D
var mesh_instance: MeshInstance3D
var materials: Array[StandardMaterial3D] = []     # 身体 / 金属两种（受击发白、减速发蓝），发光件单独
var glow_material: StandardMaterial3D
var dead := false
var tris := 0

var _bi := {}                    # 骨骼名 → 下标
var _rest := {}                  # 骨骼名 → 静止姿势的局部位置
var _t := 0.0
var _phase := 0.0
var _spd := 0.0
var _act := ""
var _act_stage := ""
var _act_k := 0.0
var _act_w := 0.0
var _act_time := -1.0            # 最近一次 act() 的时间：物理帧与画面帧不同步时，0.05 秒内都算「还在做这个动作」
var _hurt := 0.0
var _dead_k := 0.0
var _flash := 0.0


static func create(id: String) -> HumanoidRig:
	var r := HumanoidRig.new()
	r.model_id = id
	r.name = "Rig"
	var m: Dictionary = CharModels.get_model(id)
	r.style = m.style
	r.tris = m.tris
	r.scale = Vector3.ONE * float(m.style.get("scale", 1.0))
	r._build(m)
	return r


func _build(m: Dictionary) -> void:
	skeleton = Skeleton3D.new()
	skeleton.name = "Skeleton"
	add_child(skeleton)
	var joints: Dictionary = m.joints
	for b in BONES:
		skeleton.add_bone(b[0])
		var idx := skeleton.find_bone(b[0])
		_bi[b[0]] = idx
		var local: Vector3 = joints[b[0]] - (joints[b[1]] if b[1] != "" else Vector3.ZERO)
		if b[1] != "":
			skeleton.set_bone_parent(idx, _bi[b[1]])
		skeleton.set_bone_rest(idx, Transform3D(Basis.IDENTITY, local))
		_rest[b[0]] = local
	skeleton.reset_bone_poses()
	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "Body"
	mesh_instance.mesh = m.mesh
	mesh_instance.skeleton = NodePath("..")  # 绑到上面的骨架（默认是空路径，不设就不会跟着骨骼动）
	skeleton.add_child(mesh_instance)
	var surfaces: Array = m.surfaces
	for s in surfaces.size():
		var mat := StandardMaterial3D.new()
		match surfaces[s]:
			RigBuilder.GLOW:
				mat.albedo_color = Color(0.05, 0.05, 0.05)
				mat.emission_enabled = true
				mat.emission = m.glow
				mat.emission_energy_multiplier = 3.0
				glow_material = mat
			_:
				mat.vertex_color_use_as_albedo = true
				mat.roughness = 0.88
				if surfaces[s] == RigBuilder.METAL:
					mat.metallic = 0.55
					mat.roughness = 0.42
				# 常开发光、平时是黑的：受击闪白只改颜色，不切换着色器（避免卡顿）
				mat.emission_enabled = true
				mat.emission = Color(0, 0, 0)
				Look.rim(mat, 0.3)
				materials.append(mat)
		mesh_instance.set_surface_override_material(s, mat)


func bone_index(bone_name: String) -> int:
	return _bi.get(bone_name, -1)


# ---------------- 控制 ----------------

func act(kind: String, stage: String, k: float) -> void:
	_act = kind
	_act_stage = stage
	_act_k = clampf(k, 0.0, 1.0)
	_act_time = _t


func hurt() -> void:
	_hurt = 1.0
	_flash = 1.0


func set_tint(flash: bool, slow: bool, flash_color := Color(0.85, 0.8, 0.75)) -> void:
	## 受击闪白（发光；主角用红色）与寂霜环减速（偏冰蓝）
	var e := flash_color if flash else Color(0, 0, 0)
	var a := Color(0.62, 0.82, 1.0) if slow else Color(1, 1, 1)
	for m in materials:
		m.emission = e
		m.albedo_color = a


func reset_pose() -> void:
	dead = false
	_dead_k = 0.0
	_act_w = 0.0
	_act_time = -1.0
	_hurt = 0.0


# ---------------- 每帧 ----------------

func tick(delta: float, speed: float) -> void:
	_t += delta
	_spd = lerpf(_spd, speed, 1.0 - exp(-12.0 * delta))
	_phase = fmod(_phase + _spd * delta / float(style.get("stride", 1.5)) * TAU, TAU)
	_act_w = move_toward(_act_w, 1.0 if _t - _act_time <= 0.05 + delta else 0.0, delta / 0.12)
	_hurt = maxf(0.0, _hurt - delta / 0.3)
	if dead:
		_dead_k = minf(1.0, _dead_k + delta / 0.4)
	var pose := _base_pose()
	if _act_w > 0.0 and ACTIONS.has(_act):
		_blend_action(pose)
	if _hurt > 0.0:
		var h := _hurt * _hurt
		pose.Chest += Vector3(-16, 0, 0) * h
		pose.Spine += Vector3(-8, 0, 0) * h
		pose.Head += Vector3(-12, 0, 0) * h
	if _dead_k > 0.0:
		_blend_dead(pose)
	for b in pose:
		if b == "_bob":
			continue
		var v: Vector3 = pose[b] * (PI / 180.0)
		skeleton.set_bone_pose_rotation(_bi[b], Quaternion.from_euler(v))
	skeleton.set_bone_pose_position(_bi.Hips, _rest.Hips + Vector3(0, pose._bob, 0))


func _base_pose() -> Dictionary:
	## 走路 / 待机：w 是「走路程度」（0 = 站着，1 = 按参考速度跑）
	var w := clampf(_spd / float(style.get("walk_ref", 4.0)), 0.0, 1.25)
	var idle := clampf(1.0 - w * 2.0, 0.0, 1.0)
	var s := sin(_phase)
	var c := cos(_phase)
	var leg := 34.0 * w
	var knee := 55.0 * w
	var arm: float = float(style.get("arm_swing", 28.0)) * w
	var hunch: float = style.get("hunch", 0.0)
	var breath := sin(_t * 2.1)
	var p := {}
	for b in BONES:
		p[b[0]] = Vector3.ZERO
	p._bob = -0.045 * w * absf(s) + 0.006 * breath * idle
	p.Hips = Vector3(0, 9.0 * w * s, 0)
	p.Spine = Vector3(7.0 * w + hunch, 0, 0)
	p.Chest = Vector3(1.5 * breath * idle + hunch * 0.4, -11.0 * w * s, 0)
	p.Neck = Vector3(-hunch * 0.8, 0, 0)
	p.Head = Vector3(-4.0 * w, -2.0 * w * s, 0)
	p.LeftUpperLeg = Vector3(-leg * s - 3.0 * idle, 0, 0)
	p.RightUpperLeg = Vector3(leg * s - 3.0 * idle, 0, 0)
	p.LeftLowerLeg = Vector3(knee * pow(maxf(0.0, c), 1.3) + 6.0 * idle, 0, 0)
	p.RightLowerLeg = Vector3(knee * pow(maxf(0.0, -c), 1.3) + 6.0 * idle, 0, 0)
	p.LeftFoot = Vector3(-p.LeftUpperLeg.x * 0.3 - p.LeftLowerLeg.x * 0.5, 0, 0)
	p.RightFoot = Vector3(-p.RightUpperLeg.x * 0.3 - p.RightLowerLeg.x * 0.5, 0, 0)
	var ia: float = style.get("idle_arms", 8.0)
	p.LeftUpperArm = Vector3(arm * s, 0, ia + 2.0 * breath * idle)
	p.RightUpperArm = Vector3(-arm * s, 0, -ia - 2.0 * breath * idle)
	p.LeftLowerArm = Vector3(-12.0 - 18.0 * w, 0, 0)
	p.RightLowerArm = Vector3(-12.0 - 18.0 * w, 0, 0)
	# 持武器的手：右手（剑）、左手（弓）端在身前
	var carry: Dictionary = style.get("carry", {})
	for b in carry:
		p[b] += carry[b] as Vector3
	return p


func _key(kind: String, key: String, base: Dictionary) -> Dictionary:
	var out := {}
	var k: Dictionary = ACTIONS[kind].get(key, {})
	for b in base:
		out[b] = k.get(b, base[b])
	return out


func _blend_action(p: Dictionary) -> void:
	var a: Dictionary
	var b: Dictionary
	var e := 0.0
	match _act_stage:
		"windup":
			a = p
			b = _key(_act, "raised", p)
			e = 1.0 - pow(1.0 - _act_k, 2.0)
		"strike":
			a = _key(_act, "raised", p)
			b = _key(_act, "follow", p)
			e = sqrt(_act_k)
		_:
			a = _key(_act, "follow", p)
			b = p
			e = _act_k * _act_k * (3.0 - 2.0 * _act_k)
	for bone in p:
		if bone == "_bob":
			continue
		var target: Vector3 = (a[bone] as Vector3).lerp(b[bone], e)
		p[bone] = (p[bone] as Vector3).lerp(target, _act_w)


func _blend_dead(p: Dictionary) -> void:
	## 倒下：手脚发软张开、膝盖弯、头后仰（整个身体向后倒由持有者的补间负责）
	var d := _dead_k
	var limp := {"LeftUpperArm": Vector3(-30, 0, 55), "RightUpperArm": Vector3(-30, 0, -55), "LeftLowerArm": Vector3(-25, 0, 0), "RightLowerArm": Vector3(-25, 0, 0),
		"LeftUpperLeg": Vector3(-25, 0, 8), "RightUpperLeg": Vector3(-10, 0, -6), "LeftLowerLeg": Vector3(40, 0, 0), "RightLowerLeg": Vector3(20, 0, 0),
		"Head": Vector3(-25, 15, 0), "Spine": Vector3(-8, 0, 0), "Chest": Vector3(0, 0, 0)}
	for b in limp:
		p[b] = (p[b] as Vector3).lerp(limp[b], d)
	p._bob = lerpf(p._bob, 0.0, d)
