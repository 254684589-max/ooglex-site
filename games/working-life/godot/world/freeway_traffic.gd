class_name FreewayTraffic
extends Node3D
## 高架快速路上的车流（纯视觉）：两条快速路 × 双向 × 3 车道，每条车道若干辆车匀速行驶、首尾循环。
## 车身与车灯分成两个 MultiMesh：车身按实例上色，车灯（前白后红）不受车漆影响，夜里远远看是两条光带。

var body := MultiMeshInstance3D.new()
var lights := MultiMeshInstance3D.new()
var cars: Array = []


func setup() -> void:
	var mb := MeshBatcher.new()
	mb.chunked = false
	BuildingKit.car_geometry_lod(mb, Color(1, 1, 1))
	var full := mb.to_mesh()
	var body_mesh := ArrayMesh.new()
	var light_mesh := ArrayMesh.new()
	for i in full.get_surface_count():
		var target := light_mesh if full.surface_get_material(i) == Mats.batch("neon") else body_mesh
		target.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, full.surface_get_arrays(i))
		target.surface_set_material(target.get_surface_count() - 1, full.surface_get_material(i))
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var paints := [Color(0.9, 0.9, 0.9), Color(0.1, 0.1, 0.11), Color(0.45, 0.47, 0.5), Color(0.55, 0.08, 0.08), Color(0.12, 0.2, 0.42), Color(0.75, 0.75, 0.72)]
	var per_lane: int = [4, 7, 10][clampi(int(SettingsManager.get_v("quality", 1)), 0, 2)]
	for ew in [true, false]:
		var line: float = Outskirts.FW_Z if ew else Outskirts.FW_X
		var y: float = (Outskirts.FW_Y_EW if ew else Outskirts.FW_Y_NS) + 0.6
		var half: float = sqrt(Outskirts.R_MAX * Outskirts.R_MAX - line * line) - 10.0
		for dir in [1.0, -1.0]:
			for lane in 3:
				var off: float = (2.0 + lane * 3.7) * dir * (1.0 if ew else -1.0)
				for i in per_lane:
					cars.append({"ew": ew, "line": line + off, "y": y, "dir": dir, "half": half, "t": rng.randf_range(-half, half),
						"speed": rng.randf_range(24.0, 34.0), "col": paints[rng.randi() % paints.size()]})
	for pair in [[body, body_mesh, true], [lights, light_mesh, false]]:
		var mmi: MultiMeshInstance3D = pair[0]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = pair[2]
		mm.mesh = pair[1]
		mm.instance_count = cars.size()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
	for i in cars.size():
		body.multimesh.set_instance_color(i, cars[i]["col"])
	_update(0.0)


func _process(delta: float) -> void:
	_update(delta)


func _update(delta: float) -> void:
	var bm := body.multimesh
	var lm := lights.multimesh
	for i in cars.size():
		var c: Dictionary = cars[i]
		var half: float = c["half"]
		var dir: float = c["dir"]
		var t: float = c["t"] + dir * float(c["speed"]) * delta
		if absf(t) > half:
			t = -signf(t) * half
		c["t"] = t
		var pos: Vector3
		var yaw: float
		if bool(c["ew"]):
			pos = Vector3(t, c["y"], c["line"])
			yaw = -PI * 0.5 * dir
		else:
			pos = Vector3(c["line"], c["y"], t)
			yaw = 0.0 if dir < 0 else PI
		var xf := Transform3D(Basis(Vector3.UP, yaw), pos)
		bm.set_instance_transform(i, xf)
		lm.set_instance_transform(i, xf)
