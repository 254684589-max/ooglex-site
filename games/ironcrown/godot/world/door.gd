class_name Door
extends Interactable
## 门（路线图 1.3）：节点原点就是门轴，门板沿本地 +X 伸出 width 米。
## 打开时总是朝远离玩家的一侧转 90°（不会拍到人）；locked = true 时只提示「门锁着」。

const OPEN_DEG := 90.0
const SWING_SEC := 0.35

var width := 1.0
var height := 2.1
var locked := false
var locked_text := "门锁着。"
var is_open := false
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
	verb = "打开"
	closed_rot = rotation.y
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(width, height, 0.08)
	cs.shape = bs
	cs.position = Vector3(width * 0.5, height * 0.5, 0)
	add_child(cs)
	var wood := Blocks.mat(Color("5a3e2a") if not locked else Color("4a3428"))
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = bs.size
	bm.material = wood
	mi.mesh = bm
	mi.position = cs.position
	add_child(mi)
	# 门把手：在门轴对面的一侧，两面都有
	var knob := MeshInstance3D.new()
	var km := BoxMesh.new()
	km.size = Vector3(0.06, 0.06, 0.2)
	km.material = Blocks.mat(Color("b8964e"))
	knob.mesh = km
	knob.position = Vector3(width - 0.12, 1.0, 0)
	add_child(knob)


func verb_now() -> String:
	return "关上" if is_open else "打开"


func interact(who: FpController) -> Dictionary:
	if locked:
		return {"kind": "door", "name": display_name, "locked": true, "toast": locked_text}
	if is_open:
		target_deg = 0.0
	else:
		# 玩家在门的本地 +Z 一侧就往 -Z 方向转（绕 Y 轴 +90°），反之亦然
		var local := to_local(who.global_position)
		target_deg = OPEN_DEG if local.z > 0.0 else -OPEN_DEG
	is_open = not is_open
	var tw := create_tween()
	tw.tween_property(self, "rotation:y", closed_rot + deg_to_rad(target_deg), SWING_SEC).set_trans(Tween.TRANS_SINE)
	return {"kind": "door", "name": display_name, "open": is_open}
