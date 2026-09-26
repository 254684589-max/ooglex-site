class_name TrainingDummy
extends CharacterBody3D
## 训练木桩（占位敌人，用来调战斗手感）。受击时闪白、被击退后慢慢回到原位、可被眩晕；
## 生命归零时倒下，数秒后原地复活。外观是占位几何体。

signal died

var stats: Dictionary
var hp := 1.0
var max_hp := 1.0
var home := Vector3.ZERO
var hitstop_t := 0.0
var flash_t := 0.0
var stun_t := 0.0
var knock_vel := Vector3.ZERO
var knock_t := 0.0
var dead := false
var respawn_t := 0.0
var _mats: Array[StandardMaterial3D] = []
var _base_colors: Array[Color] = []
var _visual: Node3D
var _hp_label: Label3D
var _stun_mark: Label3D


func _ready() -> void:
	add_to_group("enemy")
	stats = Balance.data().training_dummy
	max_hp = stats.max_hp
	hp = max_hp
	home = global_position
	collision_layer = Layers.ENEMY
	collision_mask = Layers.WORLD
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.45
	cyl.height = 1.9
	shape.shape = cyl
	shape.position.y = 0.95
	add_child(shape)
	_visual = Node3D.new()
	add_child(_visual)
	_part(_cyl_mesh(0.32, 1.7), Vector3(0, 0.85, 0), Color(0.45, 0.32, 0.2))
	_part(_cyl_mesh(0.5, 0.12), Vector3(0, 0.06, 0), Color(0.3, 0.22, 0.15))
	var arm := BoxMesh.new()
	arm.size = Vector3(1.3, 0.14, 0.14)
	_part(arm, Vector3(0, 1.3, 0), Color(0.4, 0.28, 0.18))
	var head := SphereMesh.new()
	head.radius = 0.24
	head.height = 0.48
	_part(head, Vector3(0, 1.85, 0), Color(0.62, 0.5, 0.34))
	_hp_label = Label3D.new()
	_hp_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hp_label.no_depth_test = true
	_hp_label.fixed_size = true
	_hp_label.pixel_size = 0.0011
	_hp_label.font_size = 18
	_hp_label.outline_size = 8
	_hp_label.position = Vector3(0, 2.45, 0)
	add_child(_hp_label)
	_stun_mark = Label3D.new()
	_stun_mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_stun_mark.no_depth_test = true
	_stun_mark.fixed_size = true
	_stun_mark.pixel_size = 0.0011
	_stun_mark.font_size = 30
	_stun_mark.outline_size = 8
	_stun_mark.modulate = Color(1.0, 0.85, 0.3)
	_stun_mark.text = "眩晕"
	_stun_mark.position = Vector3(0, 2.8, 0)
	_stun_mark.visible = false
	add_child(_stun_mark)
	_update_label()


static func _cyl_mesh(r: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = h
	return m


func _part(mesh: Mesh, pos: Vector3, c: Color) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mat.roughness = 1.0
	mi.material_override = mat
	mi.position = pos
	_visual.add_child(mi)
	_mats.append(mat)
	_base_colors.append(c)


func combat_target() -> Dictionary:
	return {"armor": stats.armor, "resist": stats.resist}


func take_hit(result: Dictionary, from_dir: Vector3, knock_m: float, stun_s: float = 0.0) -> void:
	if dead:
		return
	hp = maxf(0.0, hp - result.amount)
	flash_t = Balance.fb().flash_s
	if knock_m > 0.0:
		var d := from_dir
		d.y = 0.0
		if d.length() > 0.001:
			# 在 0.15 秒内滑出 knock_m 米
			knock_t = 0.15
			knock_vel = d.normalized() * (knock_m / knock_t)
	if stun_s > 0.0:
		stun_t = maxf(stun_t, stun_s)
	_update_label()
	if hp <= 0.0:
		_die()


func _die() -> void:
	dead = true
	respawn_t = stats.respawn_s
	collision_layer = 0
	died.emit()
	var tw := create_tween()
	tw.tween_property(_visual, "rotation_degrees:x", -80.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _respawn() -> void:
	dead = false
	hp = max_hp
	collision_layer = Layers.ENEMY
	global_position = home
	_visual.rotation_degrees = Vector3.ZERO
	stun_t = 0.0
	_update_label()


func _update_label() -> void:
	_hp_label.text = "%s  %d / %d" % [stats.name, ceili(hp), int(max_hp)]
	_hp_label.modulate = Color(0.95, 0.85, 0.7) if hp > max_hp * 0.3 else Color(1.0, 0.45, 0.35)


func _physics_process(delta: float) -> void:
	if dead:
		respawn_t -= delta
		if respawn_t <= 0.0:
			_respawn()
		return
	# 闪白：受击后 flash_s 秒内所有部件变成近白色
	if flash_t > 0.0:
		flash_t -= delta
	var white := flash_t > 0.0
	for i in _mats.size():
		_mats[i].albedo_color = Color(1, 0.97, 0.92) if white else _base_colors[i]
	_stun_mark.visible = stun_t > 0.0
	if stun_t > 0.0:
		stun_t -= delta
	if hitstop_t > 0.0:
		hitstop_t -= delta
		return
	if knock_t > 0.0:
		knock_t -= delta
		velocity = knock_vel
	else:
		# 木桩底座有弹簧：慢慢回到原位
		var back := home - global_position
		back.y = 0.0
		velocity = back * 3.0 if back.length() > 0.02 else Vector3.ZERO
	move_and_slide()
	global_position.y = 0.0
