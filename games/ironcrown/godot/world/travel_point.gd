class_name TravelPoint
extends Interactable
## 出发的地方（路线图 4.2）：对着它按交互打开旅行地图，能从这里出发（main.open_travel_map(true)）。
## 现在只有第一章霜渡镇宅邸门口的路牌（world/road_sign.gd 在自己身上加一个）；组 travel_point：站在它旁边按 M 打开地图也能出发。

var size := Vector3(1.6, 2.0, 0.4)


static func make(label: String, box := Vector3(1.6, 2.0, 0.4)) -> TravelPoint:
	var t := TravelPoint.new()
	t.display_name = label
	t.verb = "查看地图"
	t.size = box
	return t


func _ready() -> void:
	add_to_group("travel_point")
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = Vector3(0, size.y * 0.5, 0)
	add_child(cs)


func interact(_who: FpController) -> Dictionary:
	return {"kind": "map", "name": display_name}
