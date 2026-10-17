class_name Props
extends RefCounted
## 人物手里拿的东西（路线图 A.2b 人物动作）：代码搭的小道具，挂在 CharacterModel 的右手（grip，和主角拿剑一样）。
## 灯、火把只有自发光，不带真的光源（网页上每多一盏灯都要算一遍；夜里远处看得见那点亮就够了）。
## 坐标按剑的握法：握把在原点，剑身朝 +Y。

const KINDS := ["lantern", "torch", "axe", "cup", "sword"]
const UPRIGHT := ["lantern", "torch", "cup"]
const LEFT_HAND := ["torch", "cup"]      # UAL 的举火把、喝东西动作是左手


static func make(kind: String) -> Node3D:
	var kit := MeshKit.new()
	match kind:
		"lantern":       # 提灯：提环在手里，灯笼吊在下面
			kit.cylinder("iron", Vector3(0, 0.02, 0), Vector3(0, -0.12, 0), 0.008, 0.008, 4, 0.6)
			kit.box("iron", Vector3(0, -0.13, 0), Vector3(0.14, 0.02, 0.14))
			kit.box("glow", Vector3(0, -0.22, 0), Vector3(0.1, 0.15, 0.1))
			kit.box("iron", Vector3(0, -0.31, 0), Vector3(0.15, 0.02, 0.15))
		"torch":         # 火把：木棍朝上，头上一团火
			kit.cylinder("wood", Vector3(0, -0.12, 0), Vector3(0, 0.42, 0), 0.025, 0.02, 6, 0.8)
			kit.box("flame", Vector3(0, 0.5, 0), Vector3(0.09, 0.16, 0.09))
		"axe":           # 斧头（砍柴、切泥炭）
			kit.cylinder("wood", Vector3(0, -0.15, 0), Vector3(0, 0.6, 0), 0.02, 0.02, 6, 0.8)
			kit.box("iron", Vector3(0.07, 0.55, 0), Vector3(0.14, 0.12, 0.025))
		"cup":           # 木杯
			kit.cylinder("wood", Vector3(0, -0.03, 0.06), Vector3(0, 0.1, 0.06), 0.045, 0.05, 8, 0.8)
		"sword":         # 卫兵手里的剑（同主角的剑）
			kit.box("iron", Vector3(0, 0.42, 0), Vector3(0.045, 0.62, 0.01))
			kit.box("wood", Vector3(0, 0.08, 0), Vector3(0.18, 0.025, 0.03))
			kit.box("wood", Vector3(0, -0.01, 0), Vector3(0.032, 0.16, 0.032))
		_:
			return null
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color("6a6a70")
	iron.metallic = 0.4
	iron.roughness = 0.5
	iron.vertex_color_use_as_albedo = true
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("6a4a30")
	wood.vertex_color_use_as_albedo = true
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color("ffd890")
	glow.emission_enabled = true
	glow.emission = Color("ffb850")
	glow.emission_energy_multiplier = 2.5
	var flame := glow.duplicate() as StandardMaterial3D
	flame.emission = Color("ff8a30")
	flame.emission_energy_multiplier = 3.5
	var node := kit.build({"iron": iron, "wood": wood, "glow": glow, "flame": flame})
	node.name = "Prop_" + kind
	if kind in UPRIGHT:                  # 灯往下吊、火把朝上、杯口朝上：不跟着手腕转
		var up := Upright.new()
		up.name = "Prop_" + kind
		node.name = "Mesh"
		up.add_child(node)
		return up
	return node
