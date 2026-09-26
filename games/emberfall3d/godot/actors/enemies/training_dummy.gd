class_name TrainingDummy
extends EnemyBase
## 训练木桩（占位敌人，用来调战斗手感）：不攻击；被击退后底座弹簧把它拉回原位；
## 倒下后数秒原地复活。受击、闪白、眩晕等通用逻辑在 EnemyBase。

var stats: Dictionary
var respawn_t := 0.0


func _ready() -> void:
	stats = Balance.data().training_dummy
	def = stats.duplicate()
	def["always_label"] = true
	max_hp = stats.max_hp
	hp = max_hp
	super._ready()


func _build_visual() -> void:
	part(cyl(0.32, 0.32, 1.7), Vector3(0, 0.85, 0), Color(0.45, 0.32, 0.2))
	part(cyl(0.5, 0.5, 0.12), Vector3(0, 0.06, 0), Color(0.3, 0.22, 0.15))
	part(box(Vector3(1.3, 0.14, 0.14)), Vector3(0, 1.3, 0), Color(0.4, 0.28, 0.18))
	part(sphere(0.24), Vector3(0, 1.85, 0), Color(0.62, 0.5, 0.34))


func _ai(_delta: float) -> void:
	# 木桩底座有弹簧：慢慢回到原位
	var back := home - global_position
	back.y = 0.0
	if back.length() > 0.02:
		move_dir = back.normalized()
		move_speed = back.length() * 3.0
	state = "idle"


func _separation() -> Vector3:
	return Vector3.ZERO


func _on_dead() -> void:
	respawn_t = stats.respawn_s
	var tw := create_tween()
	tw.tween_property(visual, "rotation_degrees:x", -80.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _physics_process(delta: float) -> void:
	if dead:
		respawn_t -= delta
		if respawn_t <= 0.0:
			_respawn()
		return
	super._physics_process(delta)


func _respawn() -> void:
	dead = false
	hp = max_hp
	collision_layer = Layers.ENEMY
	global_position = home
	visual.rotation_degrees = Vector3.ZERO
	stun_t = 0.0
	set_state("idle")
	update_label()
