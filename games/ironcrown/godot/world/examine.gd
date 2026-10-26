class_name Examine
extends Interactable
## 能看 / 能用的一处东西（5.5a）：石圈上的刻字、第十八烽的火盆、塔边的梯子。
## 用的时候调 on_use(who) -> Dictionary（同 Interactable.interact 的结果：toast / speech / kind…）；verb_fn 不为空时按它换动作字。
## size 是射线能找到的那块（只在「可交互」层，不挡路）。

var on_use: Callable
var verb_fn: Callable
var size := Vector3(0.8, 1.2, 0.8)


static func make(name_text: String, verb_text: String, use: Callable, s := Vector3(0.8, 1.2, 0.8)) -> Examine:
	var e := Examine.new()
	e.display_name = name_text
	e.verb = verb_text
	e.on_use = use
	e.size = s
	return e


func _ready() -> void:
	collision_layer = LAYER_INTERACT
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position.y = size.y * 0.5
	add_child(cs)


func verb_now() -> String:
	return str(verb_fn.call()) if verb_fn.is_valid() else verb


func interact(who: FpController) -> Dictionary:
	return on_use.call(who) if on_use.is_valid() else {}
