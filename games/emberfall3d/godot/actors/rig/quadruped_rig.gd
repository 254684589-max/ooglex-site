class_name QuadrupedRig
extends CharRig
## 程序化四足角色（2.6 之三；公共部分见 CharRig）：熔渊猎犬等。动作全部由代码算：
##   小跑（对角的两条腿同时迈：左前 + 右后、右前 + 左后）、待机呼吸与摇尾巴、扑咬（后坐、仰头张嘴 → 整个身子前窜约 0.3 米、合嘴）、
##   受击缩头、倒下（侧翻、腿软）。
## 静止姿势面朝 +Z、四条腿竖直向下；腿向前摆 x 为负，关节向后弯 x 为正；张嘴是下颌 x 为正。

const BONES := [
	["Hips", ""], ["Spine", "Hips"], ["Chest", "Spine"], ["Neck", "Chest"], ["Head", "Neck"], ["Jaw", "Head"],
	["Tail", "Hips"], ["TailTip", "Tail"],
	["FrontLeftUpper", "Chest"], ["FrontLeftLower", "FrontLeftUpper"], ["FrontLeftPaw", "FrontLeftLower"],
	["FrontRightUpper", "Chest"], ["FrontRightLower", "FrontRightUpper"], ["FrontRightPaw", "FrontRightLower"],
	["HindLeftUpper", "Hips"], ["HindLeftLower", "HindLeftUpper"], ["HindLeftPaw", "HindLeftLower"],
	["HindRightUpper", "Hips"], ["HindRightLower", "HindRightUpper"], ["HindRightPaw", "HindRightLower"],
]

const ACTIONS := {
	"bite": {
		"raised": {"_lunge": Vector3(0, -0.03, -0.08), "Neck": Vector3(-28, 0, 0), "Head": Vector3(-12, 0, 0), "Jaw": Vector3(38, 0, 0), "Chest": Vector3(-6, 0, 0),
			"FrontLeftUpper": Vector3(10, 0, 0), "FrontRightUpper": Vector3(10, 0, 0), "HindLeftUpper": Vector3(-14, 0, 0), "HindRightUpper": Vector3(-14, 0, 0),
			"HindLeftLower": Vector3(-20, 0, 0), "HindRightLower": Vector3(-20, 0, 0)},
		"follow": {"_lunge": Vector3(0, -0.04, 0.3), "Neck": Vector3(28, 0, 0), "Head": Vector3(14, 0, 0), "Jaw": Vector3(0, 0, 0), "Chest": Vector3(10, 0, 0), "Spine": Vector3(6, 0, 0),
			"FrontLeftUpper": Vector3(-35, 0, 0), "FrontRightUpper": Vector3(-30, 0, 0), "FrontLeftLower": Vector3(25, 0, 0), "FrontRightLower": Vector3(20, 0, 0),
			"HindLeftUpper": Vector3(22, 0, 0), "HindRightUpper": Vector3(18, 0, 0)},
	},
}


func _init() -> void:
	fall_sideways = true


func bones() -> Array:
	return BONES


func actions() -> Dictionary:
	return ACTIONS


func _base_pose() -> Dictionary:
	var w := clampf(_spd / float(style.get("walk_ref", 4.0)), 0.0, 1.3)
	var idle := clampf(1.0 - w * 2.0, 0.0, 1.0)
	var s := sin(_phase)
	var c := cos(_phase)
	var leg := 30.0 * w
	var knee := 45.0 * w
	var breath := sin(_t * 2.6)
	var p := {}
	for b in BONES:
		p[b[0]] = Vector3.ZERO
	p._lunge = Vector3.ZERO
	p._bob = -0.035 * w * absf(sin(_phase * 2.0)) * 0.5 + 0.005 * breath * idle
	# 对角步态：左前与右后同相，右前与左后同相
	var pairs := {"FrontLeft": s, "HindRight": s, "FrontRight": -s, "HindLeft": -s}
	var lift := {"FrontLeft": c, "HindRight": c, "FrontRight": -c, "HindLeft": -c}
	for leg_name in pairs:
		var ph: float = pairs[leg_name]
		var up: float = maxf(0.0, lift[leg_name])
		p[leg_name + "Upper"] = Vector3(-leg * ph, 0, 0)
		# 前腿的腕关节向后弯；后腿的跗关节在静止时已经向后，迈步时再收一点
		p[leg_name + "Lower"] = Vector3(knee * pow(up, 1.3) * (1.0 if leg_name.begins_with("Front") else -0.6), 0, 0)
		p[leg_name + "Paw"] = Vector3(-(p[leg_name + "Upper"] as Vector3).x * 0.4, 0, 0)
	p.Spine = Vector3(1.5 * breath * idle, 4.0 * w * s, 0)
	p.Chest = Vector3(0, -4.0 * w * s, 0)
	p.Neck = Vector3(6.0 * w + 2.0 * sin(_t * 1.3) * idle, 3.0 * sin(_t * 0.7) * idle, 0)
	p.Head = Vector3(-5.0 * w, 0, 0)
	p.Jaw = Vector3(4.0 + 3.0 * maxf(0.0, breath) * idle + 8.0 * w, 0, 0)       # 喘气：嘴微张，跑起来张得更大
	p.Tail = Vector3(-10.0 + 12.0 * w, 22.0 * sin(_t * (7.0 if idle > 0.5 else 3.0)) * (0.35 + idle * 0.65), 0)
	p.TailTip = Vector3(-8.0, 14.0 * sin(_t * 7.0 - 0.8) * idle, 0)
	return p


func _hurt_pose() -> Dictionary:
	## 受击：缩头、弓背
	return {"Neck": Vector3(-20, 0, 0), "Head": Vector3(-10, 0, 0), "Spine": Vector3(-8, 0, 0), "Jaw": Vector3(20, 0, 0)}


func _dead_pose() -> Dictionary:
	## 倒下：侧翻由持有者的补间负责；这里让腿发软收起、头垂下、嘴张开、尾巴垂落
	var d := {"Neck": Vector3(22, 0, 0), "Head": Vector3(12, 0, 0), "Jaw": Vector3(30, 0, 0), "Tail": Vector3(20, 0, 0), "TailTip": Vector3(10, 0, 0)}
	for leg_name in ["FrontLeft", "FrontRight", "HindLeft", "HindRight"]:
		d[leg_name + "Upper"] = Vector3(-25 if leg_name.begins_with("Front") else 25, 0, 0)
		d[leg_name + "Lower"] = Vector3(35 if leg_name.begins_with("Front") else -35, 0, 0)
	return d
