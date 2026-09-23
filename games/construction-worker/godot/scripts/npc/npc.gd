class_name NPC
extends CharacterBody3D
## NPC：外观、头顶名字、简单巡逻（在几个点之间走动，可以边走边搬东西）、
## 被搭话时停下来面向玩家。对话内容在 dialogue_db.gd。

@export var npc_id := ""
@export var display_name := ""
@export var role := ""
@export var talkable := true
## 巡逻点（世界坐标）。为空时站在原地
@export var patrol: PackedVector3Array = PackedVector3Array()
@export var patrol_wait := 2.5
@export var walk_speed := 1.7
## 从第 0 个点走向第 1 个点的路上搬着的材料（纯装饰）
@export var carry_item := ""
## 站着时朝向（弧度）
@export var idle_yaw := 0.0
## 外观
@export var look: Dictionary = {}
## 不能对话的 NPC 被搭话时随机说一句
@export var barks: PackedStringArray = PackedStringArray()

var model: CharacterModel
var name_tag: Label3D
var talk_area: NpcTalk
var talking := false

var _target_index := 0
var _wait := 0.0
var _carry_node: Node3D
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _face_yaw := 0.0


func _ready() -> void:
	add_to_group("npc")
	collision_layer = 4
	collision_mask = 1
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.34
	cap.height = 1.76
	cs.shape = cap
	cs.position = Vector3(0, 0.88, 0)
	add_child(cs)
	model = CharacterModel.new()
	model.skin_color = look.get("skin", Color(0.84, 0.64, 0.48))
	model.shirt_color = look.get("shirt", Color(0.4, 0.4, 0.42))
	model.pants_color = look.get("pants", Color(0.2, 0.2, 0.24))
	model.vest_color = look.get("vest", Color(0, 0, 0, 0))
	model.hat = String(look.get("hat", "yellow"))
	model.belly = bool(look.get("belly", false))
	model.body_scale = float(look.get("scale", 1.0))
	add_child(model)
	name_tag = Label3D.new()
	name_tag.text = display_name if role == "" else "%s · %s" % [role, display_name]
	name_tag.font_size = 32
	name_tag.pixel_size = 0.004
	name_tag.outline_size = 10
	name_tag.modulate = Color(1, 1, 1, 0.95)
	name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_tag.no_depth_test = false
	name_tag.position = Vector3(0, 2.2, 0)
	name_tag.visibility_range_end = 22.0
	add_child(name_tag)
	talk_area = NpcTalk.new()
	talk_area.npc = self
	talk_area.display_name = display_name
	talk_area.set_sphere_shape(1.7, Vector3(0, 1.0, 0))
	add_child(talk_area)
	_carry_node = Node3D.new()
	add_child(_carry_node)
	rotation.y = idle_yaw
	_face_yaw = idle_yaw
	Events.dialogue_closed.connect(_on_dialogue_closed)


func talk_prompt() -> String:
	return "与%s交谈" % display_name


func on_talk(player: Node3D) -> void:
	talking = true
	_face_toward(player.global_position)
	model.gesture("nod")
	if talkable and DialogueDB.has_dialogue(npc_id):
		Events.dialogue_requested.emit(npc_id)
	else:
		talking = false
		var line := "……"
		if not barks.is_empty():
			line = barks[randi() % barks.size()]
		Events.say("%s：%s" % [display_name, line], "info")


func _on_dialogue_closed(id: String) -> void:
	if id == npc_id:
		talking = false


func _face_toward(pos: Vector3) -> void:
	var d := pos - global_position
	d.y = 0.0
	if d.length() > 0.05:
		_face_yaw = atan2(-d.x, -d.z)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = -0.1
	var hv := Vector3.ZERO
	if not talking and patrol.size() > 0 and not GameState.is_modal():
		hv = _patrol_velocity(delta)
	elif not talking and patrol.is_empty():
		_face_yaw = idle_yaw
	velocity.x = hv.x
	velocity.z = hv.z
	move_and_slide()
	rotation.y = lerp_angle(rotation.y, _face_yaw, clampf(delta * 6.0, 0.0, 1.0))
	model.animate(delta, hv.length(), true)


func _patrol_velocity(delta: float) -> Vector3:
	if _wait > 0.0:
		_wait -= delta
		return Vector3.ZERO
	var goal: Vector3 = patrol[_target_index]
	var d := goal - global_position
	d.y = 0.0
	if d.length() < 0.35:
		_wait = patrol_wait
		_target_index = (_target_index + 1) % patrol.size()
		_update_carry()
		return Vector3.ZERO
	# 玩家挡在正前方就等一下
	var p := GameState.player
	if p != null:
		var to_p := p.global_position - global_position
		to_p.y = 0.0
		if to_p.length() < 1.3 and to_p.normalized().dot(d.normalized()) > 0.5:
			return Vector3.ZERO
	_face_toward(goal)
	return d.normalized() * walk_speed


func _update_carry() -> void:
	for c in _carry_node.get_children():
		c.queue_free()
	if carry_item == "" or _target_index != 1:
		model.set_carry_pose("")
		return
	var info := ItemDB.get_item(carry_item)
	var visual := String(info.get("visual", "stack"))
	model.set_carry_pose(visual)
	var size: Vector3 = info.get("size", Vector3(0.3, 0.1, 0.2))
	var n := 4 if visual == "stack" else 1
	for i in n:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		mi.material_override = Mats.color(info.get("color", Color.GRAY))
		if visual == "stack":
			mi.position = Vector3(0, 1.08 + i * (size.y + 0.006), -0.42)
		else:
			mi.position = Vector3(0.24, 1.72, 0.05)
		_carry_node.add_child(mi)
