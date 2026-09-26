class_name BurnZone
extends Node3D
## 燃烧地面（焚地践踏留下的火海，GDD.md 第 5.1 节）：持续 duration 秒，每 tick 秒对范围内的敌人造成火焰伤害。
## 外观是占位的发光圆盘。

var radius := 3.0
var duration := 3.0
var tick := 0.5
var attacker: Dictionary
var coef := 0.15
var rng := RandomNumberGenerator.new()
var _left := 0.0
var _next := 0.0
var _mat: StandardMaterial3D
var ticks_done := 0


func _ready() -> void:
	attacker = attacker.duplicate()
	attacker["crit_chance"] = 0.0     # 持续伤害不暴击
	_left = duration
	_next = tick
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 0.02
	mi.mesh = cyl
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.albedo_color = Color(1.0, 0.42, 0.12, 0.35)
	mi.material_override = _mat
	mi.position.y = 0.02
	add_child(mi)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.5, 0.2)
	light.light_energy = 1.2
	light.omni_range = radius + 1.5
	light.position.y = 0.8
	add_child(light)


func _physics_process(delta: float) -> void:
	_left -= delta
	_next -= delta
	_mat.albedo_color.a = 0.35 * clampf(_left / 0.6, 0.0, 1.0) + 0.05 * sin(_left * 20.0)
	if _next <= 0.0 and _left > 0.0:
		_next += tick
		ticks_done += 1
		for e in get_tree().get_nodes_in_group("enemy"):
			if e.get("dead"):
				continue
			var d: Vector3 = e.global_position - global_position
			if Vector2(d.x, d.z).length() <= radius:
				var r := DamageCalc.roll(attacker, coef, "fire", e.combat_target(), rng)
				e.take_hit(r, Vector3.ZERO, 0.0)
				if HitFeedback.numbers_enabled:
					HitFeedback.spawn_number(e, r)
	if _left <= 0.0:
		queue_free()
