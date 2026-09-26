class_name LowPoly
extends RefCounted
## 灰盒占位用的低面数基本体。Godot 自带的球 / 胶囊 / 圆柱 / 圆环默认分段很高（一个球约 2000 个三角形），
## 1.5 性能基准实测大厅一个镜头就有 25 万个图元；占位模型用不着这么圆，统一降到这里的分段数。

static func sphere(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 12
	m.rings = 6
	return m


static func capsule(r: float, h: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = 12
	m.rings = 3
	return m


static func cylinder(r_top: float, r_bot: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bot
	m.height = h
	m.radial_segments = 16
	m.rings = 1
	return m


static func torus(inner: float, outer: float) -> TorusMesh:
	var m := TorusMesh.new()
	m.inner_radius = inner
	m.outer_radius = outer
	m.rings = 24
	m.ring_segments = 6
	return m
