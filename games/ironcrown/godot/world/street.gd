class_name Street
extends RefCounted
## 灰盒雾夜街道（阶段 1.1 的场景，1.2 起加上碰撞可以走进去；正式的霜渡镇主街在 1.4）。

const WINDOW_COLOR := Color("ffc873")
const LAMP_COLOR := Color("ff9a3c")
const SPAWN := Vector3(0, 0, 4)


## 搭在 parent 下，返回出生点
static func build(parent: Node3D) -> Transform3D:
	var stone := Blocks.mat(Color("5e6670"))
	stone.roughness = 0.45                      # 湿石板：稍亮的高光
	Blocks.box(parent, Vector3(12, 0.2, 80), Vector3(0, -0.1, -30), stone, false)    # 街道（看得见的一层）
	Blocks.box(parent, Vector3(80, 0.2, 80), Vector3(0, -0.12, -30), Blocks.mat(Color("2a3036")))   # 地面（带碰撞）
	# 四面看不见的围墙：走不出灰盒区域
	var none := Blocks.mat(Color(0, 0, 0, 0))
	for w in [[Vector3(80, 6, 0.4), Vector3(0, 3, 10)], [Vector3(80, 6, 0.4), Vector3(0, 3, -70)],
			[Vector3(0.4, 6, 80), Vector3(40, 3, -30)], [Vector3(0.4, 6, 80), Vector3(-40, 3, -30)]]:
		var b := Blocks.box(parent, w[0], w[1], none)
		b.get_child(1).visible = false
	var wall := Blocks.mat(Color("4a4c50"))
	var timber := Blocks.mat(Color("3a2a20"))
	var glow := Blocks.mat(WINDOW_COLOR, WINDOW_COLOR)
	# 两排灰盒房子：石砌底层 + 木构上层 + 一扇亮窗（ART.md 第六节的比例，占位）
	for i in 5:
		for side in [-1, 1]:
			var z := -6.0 - i * 11.0
			var x: float = side * 10.0
			Blocks.box(parent, Vector3(7, 3, 8), Vector3(x, 1.5, z), wall)
			Blocks.box(parent, Vector3(7.4, 2.6, 8.4), Vector3(x, 4.3, z), timber)
			Blocks.box(parent, Vector3(0.1, 1.0, 1.2), Vector3(x - side * 3.52, 1.8, z), glow, false)
	# 两盏街灯：真实点光源（TECH.md 4.6：视野内 ≤ 4 盏）
	for z in [-8.0, -26.0]:
		Blocks.box(parent, Vector3(0.15, 3.2, 0.15), Vector3(4.5, 1.6, z), timber)
		Blocks.box(parent, Vector3(0.35, 0.35, 0.35), Vector3(4.5, 3.3, z), Blocks.mat(LAMP_COLOR, LAMP_COLOR), false)
		var lamp := OmniLight3D.new()
		lamp.light_color = LAMP_COLOR
		lamp.light_energy = 2.0
		lamp.omni_range = 9.0
		lamp.position = Vector3(4.5, 3.0, z)
		parent.add_child(lamp)
	return Transform3D(Basis.IDENTITY, SPAWN)
