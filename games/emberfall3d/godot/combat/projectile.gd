class_name Projectile
extends Node3D
## 敌方投射物（箭）：匀速直线飞行，每个物理帧用射线检测这一段路径；
## 打到玩家造成伤害，打到墙就消失。飞得不快，玩家看得见、躲得开（GDD.md 第 7.3 节）。

var dir := Vector3.FORWARD
var speed := 11.0
var max_range := 13.0
var attacker: Dictionary
var source: Node                   # 发射者（嗜血精英打中后回血）
var kind := "arrow"                # arrow 箭 / bolt 邪术弹（P5）
var rng := RandomNumberGenerator.new()
var travelled := 0.0


func _ready() -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(0.06, 0.06, 0.7)
	mi.mesh = b
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.45, 0.3) if kind == "arrow" else Color(0.7, 0.35, 1.0)
	if kind == "bolt":
		b.size = Vector3(0.22, 0.22, 0.22)
		m.emission_enabled = true
		m.emission = Color(0.6, 0.3, 1.0)
		m.emission_energy_multiplier = 3.0
	mi.material_override = m
	add_child(mi)
	look_at(global_position + dir, Vector3.UP)


func _physics_process(delta: float) -> void:
	var step := dir * speed * delta
	var from := global_position
	var q := PhysicsRayQueryParameters3D.create(from, from + step, Layers.WORLD | Layers.PLAYER)
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	if not r.is_empty():
		var col: Object = r.collider
		if col.has_method("take_hit") and col is Player:
			var res := DamageCalc.roll(attacker, 1.0, "physical", col.combat_target(), rng)
			col.take_hit(res, dir, 0.15)
			if is_instance_valid(source) and source.has_method("on_damage_dealt"):
				source.on_damage_dealt(res.amount)
		queue_free()
		return
	global_position += step
	travelled += step.length()
	if travelled >= max_range:
		queue_free()
