class_name StreetTrigger
extends Area3D
## 走进这一片就开一段对话（路线图 7.6：冠城斜街上堵你的人）：只开一次；正在对话、正在打、倒下了的时候不开（等下一回走进来）。
## main 有 open_dialogue / encounter_active（scenes/main.gd）；找不到 main（测试场里）就什么都不做。

var dialogue_area := ""
var dialogue_id := ""
var npc: Node3D
var fired := false


static func make(size: Vector3, area: String, id: String, who: Node3D) -> StreetTrigger:
	var t := StreetTrigger.new()
	t.dialogue_area = area
	t.dialogue_id = id
	t.npc = who
	t.collision_layer = 0
	t.collision_mask = 2                       # 玩家（FpController 在层 2）
	t.monitorable = false
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = Vector3(0, size.y * 0.5, 0)
	t.add_child(cs)
	return t


func _ready() -> void:
	body_entered.connect(_on_body)


func _on_body(body: Node3D) -> void:
	if fired or not body is FpController:
		return
	var m: Node = get_parent()
	while m != null and not m.has_method("open_dialogue"):              # main（网页上是当前场景；测试里挂在测试场景底下）
		m = m.get_parent()
	if m == null:
		return
	if m.has_method("encounter_active") and m.encounter_active():
		return
	var dlg: Variant = m.get("dialogue")
	if dlg is Control and (dlg as Control).visible:
		return
	if npc != null and not is_instance_valid(npc):
		return
	fired = true
	print("IC_STREET_TRIGGER id=%s" % dialogue_id)
	m.open_dialogue(dialogue_area, dialogue_id, npc)
