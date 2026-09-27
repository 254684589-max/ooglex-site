class_name HumanoidRig
extends CharRig
## 程序化人形角色（2.6 之三，方案 1；公共部分见 CharRig）：动作全部由代码算出骨骼姿势，不用动作文件：
##   走 / 跑（按实际移动速度推进步伐相位）、待机呼吸、挥砍、施法、双手施法、旋转斩、拉弓、受击后仰、倒下。
## 骨骼名沿用 Godot 的人形骨骼规范（SkeletonProfileHumanoid 的子集），以后换成正式模型时动作接口不用改。
## 用法见 CharRig。

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
	"claw": {
		"raised": {"RightUpperArm": Vector3(-150, 0, -25), "LeftUpperArm": Vector3(-150, 0, 25), "RightLowerArm": Vector3(-45, 0, 0), "LeftLowerArm": Vector3(-45, 0, 0), "Spine": Vector3(-8, 0, 0), "Head": Vector3(-10, 0, 0)},
		"follow": {"RightUpperArm": Vector3(-40, 0, 12), "LeftUpperArm": Vector3(-40, 0, -12), "RightLowerArm": Vector3(-8, 0, 0), "LeftLowerArm": Vector3(-8, 0, 0), "Spine": Vector3(22, 0, 0), "Chest": Vector3(12, 0, 0)},
	},
	"charge": {
		"raised": {"Spine": Vector3(28, 0, 0), "Chest": Vector3(12, 0, 0), "Neck": Vector3(-10, 0, 0), "Head": Vector3(-18, 0, 0), "RightUpperArm": Vector3(40, 0, -22), "LeftUpperArm": Vector3(40, 0, 22), "RightLowerArm": Vector3(-50, 0, 0), "LeftLowerArm": Vector3(-50, 0, 0)},
		"follow": {"Spine": Vector3(28, 0, 0), "Chest": Vector3(12, 0, 0), "Neck": Vector3(-10, 0, 0), "Head": Vector3(-18, 0, 0), "RightUpperArm": Vector3(40, 0, -22), "LeftUpperArm": Vector3(40, 0, 22), "RightLowerArm": Vector3(-50, 0, 0), "LeftLowerArm": Vector3(-50, 0, 0)},
	},
	"shoot": {
		"raised": {"LeftUpperArm": Vector3(-88, 0, 8), "LeftLowerArm": Vector3(-4, 0, 0), "RightUpperArm": Vector3(-88, 0, -30), "RightLowerArm": Vector3(-135, 0, 0), "Chest": Vector3(0, 22, 0), "Head": Vector3(0, -18, 0)},
		"follow": {"LeftUpperArm": Vector3(-86, 0, 8), "LeftLowerArm": Vector3(-4, 0, 0), "RightUpperArm": Vector3(-70, 0, -55), "RightLowerArm": Vector3(-95, 0, 0), "Chest": Vector3(0, 18, 0), "Head": Vector3(0, -15, 0)},
	},
}

func bones() -> Array:
	return BONES


func actions() -> Dictionary:
	return ACTIONS


func _hurt_pose() -> Dictionary:
	## 受击：上身后仰
	return {"Chest": Vector3(-16, 0, 0), "Spine": Vector3(-8, 0, 0), "Head": Vector3(-12, 0, 0)}


func _dead_pose() -> Dictionary:
	## 倒下：手脚发软张开、膝盖弯、头后仰（整个身体向后倒由持有者的补间负责）
	return {"LeftUpperArm": Vector3(-30, 0, 55), "RightUpperArm": Vector3(-30, 0, -55), "LeftLowerArm": Vector3(-25, 0, 0), "RightLowerArm": Vector3(-25, 0, 0),
		"LeftUpperLeg": Vector3(-25, 0, 8), "RightUpperLeg": Vector3(-10, 0, -6), "LeftLowerLeg": Vector3(40, 0, 0), "RightLowerLeg": Vector3(20, 0, 0),
		"Head": Vector3(-25, 15, 0), "Spine": Vector3(-8, 0, 0), "Chest": Vector3(0, 0, 0)}


func _base_pose() -> Dictionary:
	## 走路 / 待机：w 是「走路程度」（0 = 站着，1 = 按参考速度跑）
	var w := clampf(_spd / float(style.get("walk_ref", 4.0)), 0.0, 1.25)
	var idle := clampf(1.0 - w * 2.0, 0.0, 1.0)
	var s := sin(_phase)
	var c := cos(_phase)
	var leg_amp: float = style.get("leg_amp", 1.0)       # 长袍角色步子小（腿不从袍子里戳出来）
	var leg := 34.0 * w * leg_amp
	var knee := 55.0 * w * leg_amp
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
	p.Head = Vector3(-4.0 * w, -2.0 * w * s, float(style.get("head_tilt", 0.0)))
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
