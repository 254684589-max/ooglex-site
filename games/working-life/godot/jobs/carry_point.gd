class_name CarryPoint
extends Interactable
## 建筑搬运小游戏的取料点 / 卸货区（按 F）。

var job: CarryJob
var is_pile := true


func setup(p_job: CarryJob, pile: bool) -> void:
	job = p_job
	is_pile = pile
	display_name = "材料堆" if pile else "卸货区"
	set_sphere_shape(2.4 if pile else 3.0, Vector3(0, 1.0, 0))
	max_distance = 3.2 if pile else 3.8
	focus_priority = 2


func get_actions(player: Node) -> Array:
	var carrying := String(player.get("carrying"))
	if is_pile:
		if carrying == "":
			return [Interactable.action("pickup", "扛起一捆材料")]
		return [Interactable.action("pickup", "手上已经有材料了——送去卸货区", false)]
	if carrying != "":
		return [Interactable.action("pickup", "放下材料（%d / %d）" % [job.delivered + 1, job.target])]
	return []


func perform(_key: String, player: Node) -> void:
	if is_pile:
		job.pick(player)
	else:
		job.drop(player)
