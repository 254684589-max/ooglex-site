class_name NpcTalk
extends Interactable
## NPC 的交谈范围：靠近按 E 打开对话。

var npc: NPC


func setup_shape() -> void:
	set_sphere_shape(1.6, Vector3(0, 1.0, 0))
	max_distance = 2.8
	focus_priority = 1


func get_actions(_player: Node) -> Array:
	if npc == null or npc.at_home:
		return []
	return [Interactable.action("interact", "与%s交谈" % String(npc.data.get("name", "")))]


func perform(_action_key: String, _player: Node) -> void:
	Events.dialogue_requested.emit(npc.npc_id)
