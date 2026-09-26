class_name Fireball
extends Node3D
## 主角的火球（P4，移植 V0.1 castSkill / updProj 的 fireball）：直线飞行，碰到敌人、撞墙或飞满时间就爆炸；
## 爆炸范围内所有敌人受火焰伤害：被直接打中的 100%，其余 50%，各自再浮动 ±15%。
## 伤害 = (4 + 1.6 × 等级) × 法术伤害倍率（act1_rules.json skill_formulas.fireball）。外观是占位的发光球。

var dir := Vector3.FORWARD
var speed := 13.5
var life := 1.2
var hit_radius := 0.45
var splash_radius := 2.0
var damage := 1.0
var owner_player: Player
var rng := RandomNumberGenerator.new()
var _exploded := false


func _ready() -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = LowPoly.sphere(0.22)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.6, 0.2)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.5, 0.15)
	m.emission_energy_multiplier = 4.0
	mi.material_override = m
	add_child(mi)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.2)
	light.light_energy = 1.4
	light.omni_range = 4.0
	add_child(light)


func _physics_process(delta: float) -> void:
	if _exploded:
		return
	life -= delta
	var step := dir * speed * delta
	var from := global_position
	var q := PhysicsRayQueryParameters3D.create(from, from + step, Layers.WORLD)
	var wall := get_world_3d().direct_space_state.intersect_ray(q)
	if not wall.is_empty():
		global_position = wall.position - dir * 0.1
		explode(null)
		return
	global_position += step
	for e in get_tree().get_nodes_in_group("enemy"):
		if e.get("dead"):
			continue
		var d := Vector2(e.global_position.x - global_position.x, e.global_position.z - global_position.z).length()
		if d < float(e.def.get("radius", 0.45)) + hit_radius:
			explode(e)
			return
	if life <= 0.0:
		explode(null)


func explode(direct: Node3D) -> void:
	if _exploded:
		return
	_exploded = true
	var j: Array = Act1Data.rules().skill_formulas.fireball.jitter
	var hits := 0
	for e in get_tree().get_nodes_in_group("enemy"):
		if e.get("dead"):
			continue
		var er := float(e.def.get("radius", 0.45))
		var d := Vector2(e.global_position.x - global_position.x, e.global_position.z - global_position.z).length()
		if d >= splash_radius + er:
			continue
		var full: bool = e == direct or d < er + hit_radius + 0.15
		var amount: float = damage * (1.0 if full else Act1Data.rules().skill_formulas.fireball.splash_mul) * rng.randf_range(j[0], j[1])
		var r := {"amount": maxi(1, roundi(amount)), "crit": false, "type": "fire"}
		var push: Vector3 = e.global_position - global_position
		push.y = 0.0
		e.take_hit(r, push, Balance.fb().knockback_m.light, 0.0)
		if is_instance_valid(owner_player):
			HitFeedback.apply(self, e, r, owner_player.camera, false)   # 攻击方记为火球本身：远处爆炸不让主角停顿
		hits += 1
	if is_instance_valid(owner_player):
		owner_player.hit_landed.emit("fireball", hits)
		if hits > 0:
			print("EF_HIT skill=fireball hits=%d" % hits)
	_boom_fx()
	queue_free()


func _boom_fx() -> void:
	var ring := MeshInstance3D.new()
	ring.mesh = LowPoly.sphere(1.0)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1.0, 0.55, 0.2, 0.55)
	ring.material_override = m
	get_parent().add_child(ring)
	ring.global_position = global_position
	ring.scale = Vector3.ONE * 0.3
	var tw := ring.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector3.ONE * splash_radius, 0.25).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.3)
	tw.chain().tween_callback(ring.queue_free)
