class_name DeliveryZone
extends Interactable
## 任务卸货区。只有玩家真正走进这个区域、并且当前任务需要这种材料时，
## 按 F / 鼠标左键才能放下，放下的数量才计入任务进度。
## 放下的材料会整齐码放在区域中间，第二天早上被工人用掉（清空）。

@export var zone_id := ""
@export var item_id := "brick"
@export var zone_size := Vector3(5, 2.5, 4)

## 已码放的数量（显示用，睡觉后清空）
var stacked := 0

var _stack_mm: MultiMeshInstance3D
var _ghost: MeshInstance3D
var _sign: Label3D
var _count_label: Label3D
var _floor: MeshInstance3D
var _pulse := 0.0
var _active_target := false


func _ready() -> void:
	focus_priority = 5
	max_distance = 0.5
	set_box_shape(zone_size, Vector3(0, zone_size.y * 0.5, 0))
	_build_visuals()
	TaskSystem.tasks_changed.connect(_refresh_labels)
	Events.objective_changed.connect(_refresh_labels)
	_refresh_labels()


func contains(pos: Vector3) -> bool:
	var local := to_local(pos)
	return absf(local.x) <= zone_size.x * 0.5 and absf(local.z) <= zone_size.z * 0.5 and local.y > -1.0 and local.y < 3.0


func distance_to_player(player: Node3D) -> float:
	var local := to_local(player.global_position)
	var dx := maxf(absf(local.x) - zone_size.x * 0.5, 0.0)
	var dz := maxf(absf(local.z) - zone_size.z * 0.5, 0.0)
	return Vector2(dx, dz).length()


func get_actions(player: Node) -> Array:
	var inv: Inventory = player.inventory
	if inv.is_empty() or not contains(player.global_position):
		return []
	var item_name := ItemDB.item_name(item_id)
	if inv.item_id != item_id:
		return [Interactable.action("pickup", "%s只收%s" % [display_name, item_name], false)]
	var want := TaskSystem.wants("deliver", {"item": item_id, "zone": zone_id})
	if want <= 0:
		return [Interactable.action("pickup", "现在这里不需要%s（先找老王接活）" % item_name, false)]
	var n := mini(inv.count, want)
	return [Interactable.action("pickup", "放下%s ×%d" % [item_name, n])]


func perform(action_key: String, player: Node) -> void:
	if action_key != "pickup":
		return
	var inv: Inventory = player.inventory
	if inv.is_empty() or inv.item_id != item_id or not contains(player.global_position):
		return
	var want := TaskSystem.wants("deliver", {"item": item_id, "zone": zone_id})
	var n := mini(inv.count, want)
	if n <= 0:
		return
	var task := TaskSystem.get_active()
	var total := task.total_target() if task != null else 0
	inv.remove(n)
	add_stacked(n)
	Sfx.play("place")
	PlayerStats.add_skill_xp("carry", n)
	var used := TaskSystem.notify("deliver", {"item": item_id, "zone": zone_id, "count": n})
	if task != null and used > 0:
		var done := total - want + used
		Events.say("%s进度：%d / %d" % [task.title, done, total], "good")


func add_stacked(n: int) -> void:
	stacked += n
	_update_stack()


func clear_stack() -> void:
	stacked = 0
	_update_stack()


# ---------------------------------------------------------------- 视觉
func _build_visuals() -> void:
	# 地面黄色标线区域
	_floor = MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(zone_size.x, 0.02, zone_size.z)
	_floor.mesh = fm
	_floor.material_override = Mats.marker(Color(1.0, 0.82, 0.1, 0.28))
	_floor.position = Vector3(0, 0.07, 0)
	_floor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_floor)
	# 四条边框（黄黑）
	var border := Mats.marker(Color(1.0, 0.78, 0.0, 0.95))
	for side in [-1, 1]:
		_add_bar(Vector3(0, 0.09, side * zone_size.z * 0.5), Vector3(zone_size.x, 0.03, 0.12), border)
		_add_bar(Vector3(side * zone_size.x * 0.5, 0.09, 0), Vector3(0.12, 0.03, zone_size.z), border)
	# 标牌
	_sign = Label3D.new()
	_sign.text = display_name
	_sign.font_size = 48
	_sign.pixel_size = 0.004
	_sign.outline_size = 10
	_sign.modulate = Color(1, 0.9, 0.35)
	_sign.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_sign.position = Vector3(0, 2.9, -zone_size.z * 0.5)
	add_child(_sign)
	_count_label = Label3D.new()
	_count_label.font_size = 44
	_count_label.pixel_size = 0.004
	_count_label.outline_size = 10
	_count_label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_count_label.position = Vector3(0, 2.62, -zone_size.z * 0.5)
	add_child(_count_label)
	# 码放的材料（MultiMesh）
	var info := ItemDB.get_item(item_id)
	var bm := BoxMesh.new()
	bm.size = info.get("size", Vector3(0.3, 0.1, 0.2))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = bm
	mm.instance_count = 0
	_stack_mm = MultiMeshInstance3D.new()
	_stack_mm.multimesh = mm
	_stack_mm.material_override = Mats.color(info.get("color", Color.GRAY))
	add_child(_stack_mm)
	# 放置预览
	_ghost = MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = bm.size * 1.04
	_ghost.mesh = gm
	_ghost.material_override = Mats.marker(Color(0.4, 1.0, 0.5, 0.45))
	_ghost.visible = false
	add_child(_ghost)
	# 托盘
	var pallet := MeshInstance3D.new()
	var pm := BoxMesh.new()
	var grid: Vector2i = info.get("stack_grid", Vector2i(3, 2))
	var sz: Vector3 = bm.size
	pm.size = Vector3(grid.x * (sz.x + 0.02) + 0.2, 0.12, grid.y * (sz.z + 0.02) + 0.2)
	pallet.mesh = pm
	pallet.material_override = Mats.color(Color(0.55, 0.4, 0.24))
	pallet.position = Vector3(0, 0.06, 0)
	add_child(pallet)


func _add_bar(pos: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _slot_transform(index: int) -> Transform3D:
	var info := ItemDB.get_item(item_id)
	var grid: Vector2i = info.get("stack_grid", Vector2i(3, 2))
	var sz: Vector3 = info.get("size", Vector3(0.3, 0.1, 0.2))
	var per_layer := maxi(grid.x * grid.y, 1)
	var layer := int(index / float(per_layer))
	var in_layer := index % per_layer
	var col := in_layer % grid.x
	var row := int(in_layer / float(grid.x))
	var gap := 0.02
	var x := (col - (grid.x - 1) * 0.5) * (sz.x + gap)
	var z := (row - (grid.y - 1) * 0.5) * (sz.z + gap)
	var y := 0.12 + sz.y * 0.5 + layer * (sz.y + 0.005)
	var basis := Basis.IDENTITY
	# 砖块逐层交错码放
	if item_id == "brick" and layer % 2 == 1:
		basis = Basis(Vector3.UP, 0.04)
	return Transform3D(basis, Vector3(x, y, z))


func _update_stack() -> void:
	var mm := _stack_mm.multimesh
	mm.instance_count = stacked
	for i in stacked:
		mm.set_instance_transform(i, _slot_transform(i))
	_refresh_labels()


func _refresh_labels() -> void:
	if _count_label == null:
		return
	var task := TaskSystem.get_active()
	var text := ""
	_active_target = false
	if task != null:
		for i in task.objectives.size():
			var o: Dictionary = task.objectives[i]
			if String(o.get("zone", "")) == zone_id:
				text = "进度 %d / %d" % [int(TaskSystem.progress[i]), int(o.get("count", 0))]
				_active_target = true
	_count_label.text = text
	_count_label.visible = text != ""


func _process(delta: float) -> void:
	_pulse += delta
	if _floor != null:
		var a := 0.22 + (0.16 * (0.5 + 0.5 * sin(_pulse * 3.0)) if _active_target else 0.0)
		_floor.material_override = Mats.marker(Color(1.0, 0.82, 0.1, snappedf(a, 0.02)))
	# 放置预览
	var p := GameState.player
	var show := false
	if p != null and _active_target and p.has_method("carried_item") and p.carried_item() == item_id and contains(p.global_position):
		show = true
		_ghost.transform = _slot_transform(stacked)
	_ghost.visible = show
