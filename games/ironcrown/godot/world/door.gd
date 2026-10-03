class_name Door
extends Interactable
## 门（路线图 1.3）：节点原点就是门轴，门板沿本地 +X 伸出 width 米。
## 打开时总是朝远离玩家的一侧转 90°（不会拍到人）；locked = true 时只提示「门锁着」。
## 3.1 起：to_area 不为空的门通往另一个区域（酒馆、教堂……），交互结果 kind = "travel"，由 main 淡出、换区域、放到 to_spawn 出生点。
## 3.2 起：key_item 不为空的锁着的门，身上有那把钥匙就能打开（瓦伦家墓室的铁门要墓园钥匙）。

const OPEN_DEG := 90.0
const SWING_SEC := 0.35

var width := 1.0
var height := 2.1
var locked := false
var locked_text := "门锁着。"
var is_open := false
var to_area := ""                 # 通往的区域（world/areas.gd）；空 = 普通的门
var to_spawn := ""                # 到了那边站在哪个出生点
var key_item := ""                # 能开这把锁的钥匙（data/items.json）；空 = 打不开
var target_deg := 0.0
var closed_rot := 0.0


static func make(name_text: String, w := 1.0, h := 2.1, lock := false) -> Door:
	var d := Door.new()
	d.display_name = name_text
	d.width = w
	d.height = h
	d.locked = lock
	return d


func _ready() -> void:
	if to_area == "":
		verb = "打开"
	closed_rot = rotation.y
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(width, height, 0.08)
	cs.shape = bs
	cs.position = Vector3(width * 0.5, height * 0.5, 0)
	add_child(cs)
	# 门板与把手用 MeshKit 搭（贴图按米计算 UV，比例和墙上的木梁一致）
	var kit := MeshKit.new()
	kit.box("timber", cs.position, bs.size, Basis.IDENTITY, 0.85, 0.6, true)
	for z in [-0.06, 0.06]:   # 门把手：在门轴对面的一侧，两面都有
		kit.box("iron", Vector3(width - 0.12, 1.0, z), Vector3(0.06, 0.06, 0.06))
	kit.box("timber", Vector3(width * 0.5, height * 0.25, 0.045), Vector3(width - 0.1, 0.1, 0.02), Basis.IDENTITY, 0.7, 0.7)
	kit.box("timber", Vector3(width * 0.5, height * 0.75, 0.045), Vector3(width - 0.1, 0.1, 0.02), Basis.IDENTITY, 0.7, 0.7)
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color("2a2a2e")
	iron.metallic = 0.6
	iron.roughness = 0.5
	add_child(kit.build({"timber": Look.mat("timber"), "iron": iron}))


func verb_now() -> String:
	if to_area != "" and not locked:
		return verb
	return "关上" if is_open else "打开"


func interact(who: FpController) -> Dictionary:
	var unlocked_now := false
	if locked:
		if key_item == "" or not GameState.has_item(key_item):
			return {"kind": "door", "name": display_name, "locked": true, "toast": locked_text}
		locked = false
		unlocked_now = true
	if to_area != "":
		return {"kind": "travel", "name": display_name, "area": to_area, "spawn": to_spawn}
	if is_open:
		target_deg = 0.0
	else:
		# 玩家在门的本地 +Z 一侧就往 -Z 方向转（绕 Y 轴 +90°），反之亦然
		var local := to_local(who.global_position)
		target_deg = OPEN_DEG if local.z > 0.0 else -OPEN_DEG
	is_open = not is_open
	var tw := create_tween()
	tw.tween_property(self, "rotation:y", closed_rot + deg_to_rad(target_deg), SWING_SEC).set_trans(Tween.TRANS_SINE)
	var r := {"kind": "door", "name": display_name, "open": is_open}
	if unlocked_now:
		r["toast"] = "用%s打开了%s。" % [GameState.item_name(key_item), display_name]
		r["unlocked"] = true
	return r
