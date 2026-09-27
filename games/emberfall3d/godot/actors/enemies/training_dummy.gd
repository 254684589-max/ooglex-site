class_name TrainingDummy
extends EnemyBase
## 训练木桩（用来调战斗手感）：不攻击；被击退后底座弹簧把它拉回原位；
## 倒下后数秒原地复活。受击、闪白、眩晕等通用逻辑在 EnemyBase。
## 外观：代码搭的木桩模型（PropModels「dummy」，2.6 之六：圆木底座、麻袋塞草的身子、横杆手臂、缝着脸的麻袋头）。

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
	use_prop("dummy")


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
