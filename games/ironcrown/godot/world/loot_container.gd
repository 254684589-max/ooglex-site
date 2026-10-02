class_name LootContainer
extends Interactable
## 可搜刮的容器（路线图 2.6）：木箱 / 箱子，或者倒下的敌人身上（corpse = true，没有外观，只有一块让交互射线找到的碰撞）。
## 按交互键打开搜刮面板（ui/loot_panel.gd）：一件件拿或者全部拿走。剩下什么记在 GameState.looted[编号]（2.8 一起存档）。
## 物品归属与偷窃（「这是别人的东西」）在之后的步骤；现在放的都是无主的东西。

var loot_id := ""
var start_items: Array = []
var start_silver := 0
var corpse := false
var size := Vector3(0.9, 0.55, 0.55)


static func make(id: String, name_text: String, items: Array, silver := 0, is_corpse := false) -> LootContainer:
	var c := LootContainer.new()
	c.loot_id = id
	c.display_name = name_text
	c.start_items = items.duplicate()
	c.start_silver = silver
	c.corpse = is_corpse
	return c


func _ready() -> void:
	add_to_group("loot")
	verb = "搜刮" if corpse else "打开"
	var cs := CollisionShape3D.new()
	if corpse:
		collision_layer = LAYER_INTERACT                 # 尸体不挡路
		var sp := SphereShape3D.new()
		sp.radius = 0.55
		cs.shape = sp
		cs.position = Vector3(0, 0.35, 0)
	else:
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		cs.position.y = size.y * 0.5
		var kit := MeshKit.new()
		kit.box("timber", Vector3(0, size.y * 0.45, 0), Vector3(size.x, size.y * 0.9, size.z), Basis.IDENTITY, 1.0, 0.6)
		kit.box("iron", Vector3(0, size.y * 0.92, 0), Vector3(size.x + 0.02, size.y * 0.16, size.z + 0.02))
		var iron := StandardMaterial3D.new()
		iron.albedo_color = Color("3a3c40")
		iron.vertex_color_use_as_albedo = true
		add_child(kit.build({"timber": Look.mat("timber"), "iron": iron}))
	add_child(cs)


## 现在剩下的东西：{items: [...], silver: n}（第一次打开前就是初始内容）
func contents() -> Dictionary:
	if GameState.looted.has(loot_id):
		return GameState.looted[loot_id]
	return {"items": start_items.duplicate(), "silver": start_silver}


func is_empty() -> bool:
	var c := contents()
	return (c.items as Array).is_empty() and int(c.silver) <= 0


func prompt() -> String:
	return super.prompt() + ("（空）" if is_empty() else "")


func interact(_who: FpController) -> Dictionary:
	return {"kind": "loot", "name": display_name, "container": self}


func _save(c: Dictionary) -> void:
	GameState.looted[loot_id] = c


## 拿第 i 件；i = -1 拿银币。返回拿到的东西的名字（空 = 没拿到）
func take(i: int) -> String:
	var c := contents()
	if i == -1:
		var n := int(c.silver)
		if n <= 0:
			return ""
		c.silver = 0
		_save(c)
		if GameState.has_perk("survival", "loot_bonus"):
			n += 2                                  # 生存 50「搜刮老手」
		GameState.add_silver(n)
		GameState.train("survival", 0.5)
		return "%d 枚银币" % n
	if i < 0 or i >= (c.items as Array).size():
		return ""
	var id := str(c.items[i])
	c.items.remove_at(i)
	_save(c)
	GameState.add_item(id)
	GameState.train("survival", 0.5)            # 用什么涨什么：搜刮（2.7）
	return GameState.item_name(id)


## 全部拿走；返回拿到的名字列表
func take_all() -> Array:
	var got := []
	var s := take(-1)
	if s != "":
		got.append(s)
	while not (contents().items as Array).is_empty():
		got.append(take(0))
	return got
