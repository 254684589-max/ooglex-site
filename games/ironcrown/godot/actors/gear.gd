class_name Gear
extends Node3D
## 主角身上的硬件（路线图 A.2b）：背上斜挎的剑鞘（剑柄从右肩后露出来）、胸前斜挎的皮带。素材包里没有，用 MeshKit 搭。
## 在骨架空间（模型面朝 +Z、上 +Y、人的右手在 -X）按 T 姿势设计好，挂到 spine_03 骨头上，跟着上身动。
## 剑拔出来时背上只剩空鞘（hilt 藏起来），收剑时剑柄回到肩后。

const BONE := "spine_03"
## 剑鞘：从左腰斜到右肩后
const SHEATH_TOP := Vector3(-0.21, 1.56, -0.145)
const SHEATH_DIR := Vector3(-0.42, 1.0, -0.03)
const SHEATH_LEN := 0.82
## 胸前交叉的两条皮带（X 形）：右肩 → 胸口 → 左腰、左肩 → 胸口 → 右腰（两段，贴着胸口的弧度）；背后一条扣着剑鞘
const STRAPS := [
	[Vector3(-0.16, 1.53, 0.04), Vector3(0.0, 1.30, 0.165), Vector3(0.18, 1.02, 0.135)],
	[Vector3(0.16, 1.53, 0.04), Vector3(0.0, 1.26, 0.168), Vector3(-0.18, 1.02, 0.135)],
	[Vector3(-0.16, 1.53, -0.06), Vector3(0.0, 1.28, -0.165), Vector3(0.18, 1.02, -0.13)],
]

var hilt: Node3D


static func attach(c: CharacterModel) -> Gear:
	if not c.loaded:
		return null
	var sk := c.skeleton
	var idx := sk.find_bone(BONE)
	var ba := BoneAttachment3D.new()
	ba.name = "GearBone"
	ba.bone_name = BONE
	sk.add_child(ba)
	var g := Gear.new()
	g.name = "Gear"
	ba.add_child(g)
	g.transform = sk.get_bone_global_rest(idx).affine_inverse()      # 子节点按骨架空间摆
	g._build()
	return g


func _build() -> void:
	var leather := _mat(Color("2e241e"), 0.85)
	var iron := _mat(Color("5a5c60"), 0.45, 0.4)
	var grip := _mat(Color("3a2a20"), 0.9)
	var kit := MeshKit.new()
	# 剑鞘：一根扁长的皮鞘，口和尖包铁
	var d := SHEATH_DIR.normalized()
	var bottom := SHEATH_TOP - d * SHEATH_LEN
	_bar(kit, "leather", bottom, SHEATH_TOP, 0.07, 0.03)
	_bar(kit, "iron", SHEATH_TOP - d * 0.07, SHEATH_TOP, 0.085, 0.04)
	_bar(kit, "iron", bottom, bottom + d * 0.06, 0.06, 0.035)
	# 皮带：胸前交叉两条、背后一条扣着剑鞘，每条两段
	for pts in STRAPS:
		for i in 2:
			_bar(kit, "leather", pts[i], pts[i + 1], 0.05, 0.012)
	var body := kit.build({"leather": leather, "iron": iron})
	body.name = "Sheath"
	add_child(body)
	# 剑柄（收剑时露在右肩后）：护手、握柄、剑首
	var hk := MeshKit.new()
	var side := d.cross(Vector3(0, 0, 1)).normalized()
	_bar(hk, "iron", SHEATH_TOP - side * 0.11, SHEATH_TOP + side * 0.11, 0.03, 0.03)
	_bar(hk, "grip", SHEATH_TOP, SHEATH_TOP + d * 0.19, 0.032, 0.032)
	_bar(hk, "iron", SHEATH_TOP + d * 0.19, SHEATH_TOP + d * 0.24, 0.05, 0.05)
	hilt = hk.build({"iron": iron, "grip": grip})
	hilt.name = "Hilt"
	add_child(hilt)
	for mi: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


## 剑在鞘里时肩后露出剑柄；剑在手里、空手、换了别的武器时背上只剩空鞘
func show_hilt(on: bool) -> void:
	if hilt:
		hilt.visible = on


## 从 a 到 b 的一根方条（宽 w、厚 t；厚的方向尽量朝着身体前后）
func _bar(kit: MeshKit, mat: String, a: Vector3, b: Vector3, w: float, t: float) -> void:
	var y := b - a
	var len := y.length()
	var up := y / len
	var z := Vector3(0, 0, 1) - up * up.z
	if z.length() < 0.01:
		z = Vector3(1, 0, 0) - up * up.x
	z = z.normalized()
	var x := up.cross(z)
	kit.box(mat, (a + b) * 0.5, Vector3(w, len, t), Basis(x, up, z))


func _mat(c: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	m.vertex_color_use_as_albedo = true
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = CharacterModel.GLOW
	return m
