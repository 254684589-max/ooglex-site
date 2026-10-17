class_name Npc
extends Interactable
## 灰盒 NPC（路线图 1.3）：说话时转身面向玩家。
## 有 dialogue_id（2.1 起）：按交互键打开对话树（data/dialogue/<dialogue_area>.json）；没有：轮流说 lines 里的一句话，显示在底部字幕。
## 外观是占位的胶囊 + 头（正式人物在阶段 A）。

var lines: Array = []
var line_index := 0
var coat := Color("4a5a6a")
var dialogue_area := ""
var dialogue_id := ""
var look_model: CharacterModel   # A.2：配了打扮的人（data/looks.json）是真人模型，没配的是占位胶囊
var _lod_left := 0.0
var pose := "idle"                 # A.2b：平时的动作（data/looks.json 的 pose）
var talking := false
const LYING_OFFSET := Vector3(0, 0.08, 0.75)   # LayToIdle 第一帧：脚在本地 z -0.62、头在 +0.9；往床头挪、背贴在褥子上
var lying := false          # 躺着（4.5c 病床上昏睡的家主）：身子放平、脸朝上，说话时不转身；头朝本地 +Z


static func make(name_text: String, speech: Array, c := Color("4a5a6a")) -> Npc:
	var n := Npc.new()
	n.display_name = name_text
	n.lines = speech
	n.coat = c
	return n


func _ready() -> void:
	verb = "看看" if lying else "交谈"
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.75
	cs.shape = cap
	cs.position.y = 0.875
	add_child(cs)
	var body := Npc.build_body(self, coat)
	if Looks.has(display_name, name) and not get_groups().any(func(g): return str(g).begins_with("encounter:")):
		_dress(body)                       # 要和你打起来的人（对峙那一组）照旧是胶囊：开打时换成敌人，敌人换装在 A.2b
	if lying:
		cs.rotation.x = PI / 2
		cs.position = Vector3(0, 0.3, 0.875)
		body.rotation.x = PI / 2           # 头（本地 +Y 1.6）转到 +Z，鼻子朝上
		body.position.y = 0.3
		Blocks.label(self, display_name, Vector3(0, 0.95, 0.9), 32, 0.0035)
	else:
		Blocks.label(self, display_name, Vector3(0, 1.98, 0), 32, 0.0035)


## 换上真人模型（A.2）：近处画模型、远处画胶囊（visibility range），远了动作也停下
func _dress(body: Node3D) -> void:
	var m := Looks.make(display_name, name)
	m.rotation.y = PI                       # 模型面朝 +Z，人的脸朝本地 -Z
	if lying:
		m.position = LYING_OFFSET          # 躺着的动作（LayToIdle 第一帧）：人平躺、脚朝前，挪到床褥上
	add_child(m)
	if not m.loaded:
		m.queue_free()
		return
	Looks.finish(m)
	pose = Looks.pose(display_name, name)
	m.hold_prop(Props.make(Looks.prop(display_name, name)), Looks.prop(display_name, name) in Props.LEFT_HAND)
	if lying:
		m.hold("lying", 0.0)
	else:
		m.play_loop(pose, randf_range(0.88, 1.12))          # 每个人快慢不一样
		m.anim.seek(randf() * m.clip_length(pose), true)  # 起点错开：不要一屋子人同时晃
		m.set_anim_every(2)
	look_model = m
	for mi: MeshInstance3D in body.find_children("*", "MeshInstance3D", true, false):
		mi.visibility_range_begin = Looks.LOD_FAR


## 对话开始 / 结束（main.open_dialogue / _on_dialogue_closed）：说话的人比划着说（坐着的坐着说）；提灯、举火把的不换（手里有东西）。
## 对话时游戏暂停，只让说话的人的模型照样动
func begin_talk() -> void:
	if look_model == null or talking or lying:
		return
	talking = true
	look_model.process_mode = Node.PROCESS_MODE_ALWAYS
	look_model.set_process(true)
	if Looks.prop(display_name, name) in ["lantern", "torch"]:
		return
	look_model.play_loop("sit_talk" if pose in ["sit", "sit_talk"] else "talk", 1.0, 0.35)


func end_talk() -> void:
	if look_model == null or not talking:
		return
	talking = false
	look_model.process_mode = Node.PROCESS_MODE_INHERIT
	look_model.play_loop(pose, 1.0, 0.45)


func _process(delta: float) -> void:
	if look_model == null or talking:
		return
	_lod_left -= delta
	if _lod_left > 0.0:
		return
	_lod_left = 0.5
	var cam := get_viewport().get_camera_3d()
	var near := cam == null or cam.global_position.distance_to(global_position) < Looks.LOD_FAR
	if look_model.is_processing() != near:
		look_model.set_process(near)            # 远处（画的是胶囊）不推进动作（动作每两帧手动推进一次，CharacterModel.set_anim_every）


## 占位人形（胶囊身子 + 头 + 看得出朝向的小鼻子）；敌人（2.5）也用它。脸朝本地 -Z。
static func build_body(parent: Node3D, coat_color: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "Body"
	parent.add_child(root)
	var body := MeshInstance3D.new()
	body.name = "Coat"
	var cm := CapsuleMesh.new()
	cm.radius = 0.3
	cm.height = 1.45
	cm.radial_segments = 12
	cm.rings = 4
	cm.material = Blocks.mat(coat_color)
	body.mesh = cm
	body.position.y = 0.725
	root.add_child(body)
	var head := MeshInstance3D.new()
	head.name = "Head"
	var sm := SphereMesh.new()
	sm.radius = 0.14
	sm.height = 0.28
	sm.radial_segments = 12
	sm.rings = 6
	sm.material = Blocks.mat(Color("c8a88a"))
	head.mesh = sm
	head.position = Vector3(0, 1.6, 0)
	root.add_child(head)
	var nose := MeshInstance3D.new()    # 看得出朝向的小鼻子（占位）
	nose.name = "Nose"
	var nm := BoxMesh.new()
	nm.size = Vector3(0.05, 0.05, 0.08)
	nm.material = sm.material
	nose.mesh = nm
	nose.position = Vector3(0, 1.6, -0.15)
	root.add_child(nose)
	return root


func interact(who: FpController) -> Dictionary:
	var to := who.global_position - global_position
	if not lying and Vector2(to.x, to.z).length() > 0.01:
		rotation.y = atan2(-to.x, -to.z)     # 本地 -Z 是脸的朝向
	if dialogue_id != "":
		return {"kind": "dialogue", "name": display_name, "area": dialogue_area, "id": dialogue_id, "npc": self}
	var text := "……"
	if not lines.is_empty():
		text = str(lines[line_index % lines.size()])
		line_index += 1
	return {"kind": "npc", "name": display_name, "speech": "%s：%s" % [display_name, text]}
