class_name Npc
extends Node3D
## 烬原镇的人物（P7）：老祭司伊莲、铁匠格伦、药剂师玛拉（V0.1 genTown 的 npcs）。
## P8 加上学徒托比（交了「铁匠的学徒」后回到镇上）。
## 点他们走过去对话（Player.talk_target）；头顶显示名字与任务提示（「!」有新任务、「?」可以交任务，Quests.mark）。
## 外观（2.6 之三）：代码搭的骨骼角色（CharModels.npc_*），站着呼吸、慢慢左右张望。

const TALK_RANGE := 2.4
const RIG_BY_LOOK := {"priest": "npc_elin", "smith": "npc_gren", "alch": "npc_mara", "boy": "npc_toby"}

var npc_id := ""
var npc_name := ""
var glyph := ""
var look := ""
var label: Label3D
var mark: Label3D
var _t := 0.0
var _body: Node3D
var rig: CharRig


static func make(d: Dictionary) -> Npc:
	var n := Npc.new()
	n.npc_id = d.id
	n.npc_name = d.name
	n.glyph = d.glyph
	n.look = d.get("look", "")
	n.name = "Npc_" + String(d.id)
	return n


func _ready() -> void:
	add_to_group("npc")
	_t = randf() * 5.0
	_body = Node3D.new()
	add_child(_body)
	rig = CharRig.create(RIG_BY_LOOK.get(look, "npc_elin"))
	rig._t = _t                  # 各自错开，不会一起左右张望
	_body.add_child(rig)
	add_child(Look.blob_shadow(0.4))
	label = Label3D.new()
	label.text = npc_name
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0011
	label.font_size = 20
	label.outline_size = 8
	label.modulate = Color(1.0, 0.85, 0.5)
	label.position.y = 2.15
	add_child(label)
	mark = Label3D.new()
	mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	mark.no_depth_test = true
	mark.fixed_size = true
	mark.pixel_size = 0.0016
	mark.font_size = 36
	mark.outline_size = 8
	mark.modulate = Color(1.0, 0.85, 0.2)
	mark.position.y = 2.8
	add_child(mark)


## 头顶任务提示（「!」「?」或空）
func set_mark(m: String) -> void:
	mark.text = m
	mark.modulate = Color(1.0, 0.85, 0.2) if m == "!" else Color(0.75, 0.9, 1.0)


## V0.1 的朝向是平面角（格子坐标 x 向右、y 向下）
func face_v01(a: float) -> void:
	rotation.y = atan2(cos(a), sin(a))


func _process(delta: float) -> void:
	_t += delta
	if rig != null and is_visible_in_tree():
		rig.tick(delta, 0.0)
