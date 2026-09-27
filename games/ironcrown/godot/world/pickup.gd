class_name Pickup
extends Interactable
## 可拾取物（路线图 1.3）：捡起后放进背包、从场景里消失。
## 只在「可交互」层，不挡路。外观是占位的小方块（正式物品模型在阶段 A）。背包界面在 2.4。

var item_id := ""
var color := Color("c8a060")
var size := Vector3(0.25, 0.12, 0.18)


static func make(id: String, name_text: String, c: Color, s := Vector3(0.25, 0.12, 0.18)) -> Pickup:
	var p := Pickup.new()
	p.item_id = id
	p.display_name = name_text
	p.color = c
	p.size = s
	return p


func _ready() -> void:
	verb = "拾取"
	collision_layer = LAYER_INTERACT          # 只让射线找到，不挡路
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size + Vector3(0.1, 0.1, 0.1)   # 碰撞比外观大一点，好瞄
	cs.shape = bs
	cs.position.y = size.y * 0.5
	add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = Blocks.mat(color)
	mi.mesh = bm
	mi.position.y = size.y * 0.5
	add_child(mi)


func interact(_who: FpController) -> Dictionary:
	collision_layer = 0
	queue_free()
	return {"kind": "pickup", "item": item_id, "name": display_name, "toast": "拾取：%s" % display_name}
