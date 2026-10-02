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


static func make(name_text: String, speech: Array, c := Color("4a5a6a")) -> Npc:
	var n := Npc.new()
	n.display_name = name_text
	n.lines = speech
	n.coat = c
	return n


func _ready() -> void:
	verb = "交谈"
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.75
	cs.shape = cap
	cs.position.y = 0.875
	add_child(cs)
	Npc.build_body(self, coat)
	Blocks.label(self, display_name, Vector3(0, 1.98, 0), 32, 0.0035)


## 占位人形（胶囊身子 + 头 + 看得出朝向的小鼻子）；敌人（2.5）也用它。脸朝本地 -Z。
static func build_body(parent: Node3D, coat_color: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "Body"
	parent.add_child(root)
	var body := MeshInstance3D.new()
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
	var nm := BoxMesh.new()
	nm.size = Vector3(0.05, 0.05, 0.08)
	nm.material = sm.material
	nose.mesh = nm
	nose.position = Vector3(0, 1.6, -0.15)
	root.add_child(nose)
	return root


func interact(who: FpController) -> Dictionary:
	var to := who.global_position - global_position
	if Vector2(to.x, to.z).length() > 0.01:
		rotation.y = atan2(-to.x, -to.z)     # 本地 -Z 是脸的朝向
	if dialogue_id != "":
		return {"kind": "dialogue", "name": display_name, "area": dialogue_area, "id": dialogue_id, "npc": self}
	var text := "……"
	if not lines.is_empty():
		text = str(lines[line_index % lines.size()])
		line_index += 1
	return {"kind": "npc", "name": display_name, "speech": "%s：%s" % [display_name, text]}
