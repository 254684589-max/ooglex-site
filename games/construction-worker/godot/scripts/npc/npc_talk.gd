class_name NpcTalk
extends Interactable
## NPC 身上的对话范围：靠近按 E 交谈。

var npc: NPC


func _init() -> void:
	super._init()
	focus_priority = 4
	max_distance = 2.6


func focus_point() -> Vector3:
	return npc.global_position if npc != null else global_position


func get_actions(_player: Node) -> Array:
	if npc == null or npc.talking:
		return []
	return [Interactable.action("interact", npc.talk_prompt())]


func perform(action_key: String, player: Node) -> void:
	if action_key == "interact" and npc != null:
		npc.on_talk(player)
