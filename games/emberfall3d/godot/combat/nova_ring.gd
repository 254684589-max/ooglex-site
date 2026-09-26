class_name NovaRing
extends Node3D
## 向外扩散的火环（P9，V0.1 fx type 'ring'：摩登的烈焰新星、二阶段变身时的爆发）：
## 从中心以 speed 米 / 秒扩到 max_radius；环扫过主角时（环前沿与主角距离 < 0.8 米）造成一次火焰伤害。
## 看得见、躲得开：往外跑到环外或等它扫过去之前穿过去都行。

var max_radius := 10.0
var speed := 6.0
var attacker: Dictionary
var player: Node3D
var color := Color(1.0, 0.48, 0.16)
var radius := 0.2
var hit := false
var _mi: MeshInstance3D
var _mat: StandardMaterial3D
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	_mi = MeshInstance3D.new()
	# 环会扩到 10 米：分段要多，否则一段段直边看起来像断开的短棍
	var tm := TorusMesh.new()
	tm.inner_radius = 0.93
	tm.outer_radius = 1.0
	tm.rings = 48
	tm.ring_segments = 4
	_mi.mesh = tm
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.albedo_color = Color(color, 0.85)
	_mi.material_override = _mat
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mi.position.y = 0.3
	add_child(_mi)
	rng.randomize()
	_apply()


func _physics_process(delta: float) -> void:
	radius += speed * delta
	_apply()
	if not hit and is_instance_valid(player) and not player.get("dead"):
		var d := Vector2(player.global_position.x - global_position.x, player.global_position.z - global_position.z).length()
		if absf(d - radius) < 0.8:
			hit = true
			var r := DamageCalc.roll(attacker, 1.0, "fire", player.combat_target(), rng)
			r.type = "fire"
			player.take_hit(r, player.global_position - global_position, 0.4)
	if radius >= max_radius:
		queue_free()


func _apply() -> void:
	if _mi:
		# 竖向也放大一点：环是一条有高度的光带，不会被凹凸的地砖挡成一段一段
		_mi.scale = Vector3(radius, 5.0, radius)
		_mat.albedo_color.a = 0.85 * clampf(1.0 - radius / max_radius, 0.15, 1.0)
