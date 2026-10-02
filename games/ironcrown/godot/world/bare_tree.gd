class_name BareTree
extends RefCounted
## 枯树（ART.md 第六节）：树干 + 三级分叉的枝条，代码搭的多棱柱 + 树皮贴图，整棵一个网格。占位水平，正式的树在阶段 A。

static func build(parent: Node3D, pos: Vector3, seed_value: int, height := 5.5) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var kit := MeshKit.new()
	var base := Vector3.ZERO
	var top := Vector3(rng.randf_range(-0.3, 0.3), height * 0.55, rng.randf_range(-0.3, 0.3))
	kit.cylinder("bark", base + Vector3(0, -0.2, 0), top, 0.32, 0.2, 7, 0.8)
	_branch(kit, rng, top, Vector3.UP, height * 0.5, 0.2, 0)
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = rng.randf() * TAU
	parent.add_child(root)
	var mi := kit.build({"bark": Look.mat("bark")})
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(mi)
	var body := StaticBody3D.new()
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.32
	cyl.height = height * 0.55
	cs.shape = cyl
	cs.position.y = height * 0.275
	body.add_child(cs)
	root.add_child(body)
	return root


static func _branch(kit: MeshKit, rng: RandomNumberGenerator, from: Vector3, dir: Vector3, length: float, radius: float, depth: int) -> void:
	var count := 3 if depth < 2 else 2
	for i in count:
		var spread := deg_to_rad(rng.randf_range(25.0, 50.0))
		var turn := TAU * (float(i) / count) + rng.randf_range(-0.5, 0.5)
		var side := dir.cross(Vector3.RIGHT if absf(dir.x) < 0.9 else Vector3.FORWARD).normalized().rotated(dir, turn)
		var nd := (dir * cos(spread) + side * sin(spread)).normalized()
		nd.y += 0.15
		nd = nd.normalized()
		var l := length * rng.randf_range(0.55, 0.8)
		var to := from + nd * l
		kit.cylinder("bark", from, to, radius, radius * 0.55, 5 if depth < 2 else 4, 0.85)
		if depth < 3:
			_branch(kit, rng, to, nd, l, radius * 0.55, depth + 1)
