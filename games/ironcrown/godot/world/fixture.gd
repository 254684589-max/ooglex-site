class_name Fixture
extends Interactable
## 能对着说话的「东西」（路线图 4.7a）：不是人，但按交互键打开一段对话（data/dialogue/<dialogue_area>.json），例如账房侧墙上那扇能撬的小窗。
## 只在「可交互」层，不挡路；外观由区域自己画（这里只放一个看不见的碰撞盒）。

var dialogue_area := ""
var dialogue_id := ""
var size := Vector3(0.8, 0.8, 0.3)


static func make(name_text: String, verb_text: String, area: String, id: String, box: Vector3) -> Fixture:
	var f := Fixture.new()
	f.display_name = name_text
	f.verb = verb_text
	f.dialogue_area = area
	f.dialogue_id = id
	f.size = box
	return f


func _ready() -> void:
	collision_layer = LAYER_INTERACT          # 只让射线找到，不挡路
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	add_child(cs)


func interact(_who: FpController) -> Dictionary:
	return {"kind": "dialogue", "name": display_name, "area": dialogue_area, "id": dialogue_id}
