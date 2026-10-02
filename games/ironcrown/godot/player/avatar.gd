class_name PlayerAvatar
extends Node3D
## 第三人称时看到的主角（路线图 2.9；决定 D6）：占位胶囊人 + 一只拿武器的手臂（和敌人同一套占位做法）。
## 第一人称时隐藏（第一人称只显示手里的武器）。正式的人物模型与动作跟着 D4 人物方案做（阶段 A）。
## 手臂姿势跟着 Melee 的状态走：收剑垂手、持剑、蓄力举高、劈下、格挡横架。

var player: FpController
var body: Node3D
var arm: Node3D
var weapon_mesh: MeshInstance3D
var model := ""


func _ready() -> void:
	body = Npc.build_body(self, Color("6a5a48"))
	# 一点自发光：镜头在背后、灯在前面时，人形不至于是一团黑影（2.9 截图）
	for c in body.get_children():
		if c is MeshInstance3D and c.mesh.material is StandardMaterial3D:
			var mat := (c.mesh.material as StandardMaterial3D).duplicate() as StandardMaterial3D
			mat.emission_enabled = true
			mat.emission = mat.albedo_color
			mat.emission_energy_multiplier = 0.18
			c.mesh = c.mesh.duplicate()
			c.mesh.material = mat
	arm = Node3D.new()
	arm.name = "Arm"
	arm.position = Vector3(0.34, 1.3, -0.05)
	body.add_child(arm)
	visible = false


func _set_model(m: String) -> void:
	if m == model:
		return
	model = m
	if weapon_mesh:
		arm.remove_child(weapon_mesh)
		weapon_mesh.queue_free()
	var kit := MeshKit.new()
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color("b4bcc6")
	steel.metallic = 0.35
	steel.roughness = 0.4
	steel.vertex_color_use_as_albedo = true
	if m == "club":
		kit.cylinder("wood", Vector3(0, -0.05, 0), Vector3(0, 0.62, 0), 0.026, 0.045, 6)
	else:
		kit.box("steel", Vector3(0, 0.42, 0), Vector3(0.045, 0.62, 0.01))
		kit.box("wood", Vector3(0, 0.08, 0), Vector3(0.18, 0.025, 0.03))
		kit.box("wood", Vector3(0, -0.01, 0), Vector3(0.032, 0.16, 0.032))
	weapon_mesh = kit.build({"steel": steel, "wood": Look.mat("timber")})
	arm.add_child(weapon_mesh)


func _process(delta: float) -> void:
	if not visible or player == null:
		return
	var m := player.melee
	_set_model(str(m.weapon().get("model", "sword")))
	weapon_mesh.visible = m.state != Melee.State.SHEATHED and not m.weapon().is_empty()
	var target := Vector3(-40, 0, 0)
	var k := clampf(m.t / maxf(m.dur, 0.0001), 0.0, 1.0)
	match m.state:
		Melee.State.SHEATHED, Melee.State.SHEATHING:
			target = Vector3(10, 0, 0)
		Melee.State.CHARGE:
			target = Vector3(-40, 0, 0).lerp(Vector3(55, 0, 0), clampf(m.held / Melee.HEAVY_HOLD, 0.0, 1.0))
		Melee.State.WINDUP:
			target = Vector3(35, 0, 0)
		Melee.State.STRIKE:
			target = Vector3(35 if m.kind == "light" else 55, 0, 0).lerp(Vector3(-115, 0, 0), k)
		Melee.State.BLOCK:
			target = Vector3(-30, 0, 75)
	var speed := 40.0 if m.state == Melee.State.STRIKE else 12.0
	arm.rotation_degrees = arm.rotation_degrees.lerp(target, clampf(delta * speed, 0.0, 1.0))
	# 蹲下：身子矮一截
	var sy := 0.68 if player.crouching else 1.0
	body.scale.y = move_toward(body.scale.y, sy, delta * 4.0)
