class_name SuitcaseProp
extends Interactable
## 开场的行李箱放在地上时的样子。按 F 再拿起来；租到房、住进旅馆或第一天结束后会自动收进屋里。

const GROUP := "suitcase_prop"


func _ready() -> void:
	add_to_group(GROUP)
	display_name = "行李箱"
	name = "SuitcaseProp"
	set_sphere_shape(1.0, Vector3(0, 0.4, 0))
	max_distance = 2.2
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.42, 0.62, 0.24)
	mi.mesh = bm
	mi.position = Vector3(0, 0.31, 0)
	mi.material_override = Mats.color(Color(0.15, 0.4, 0.55), 0.4)
	add_child(mi)


func get_actions(player: Node) -> Array:
	if String(player.get("carrying")) != "":
		return [Interactable.action("pickup", "手里拿着东西，拿不了行李箱", false)]
	return [Interactable.action("pickup", "拿起行李箱")]


func perform(_action_key: String, player: Node) -> void:
	if String(player.get("carrying")) != "":
		return
	player.call("set_carry", "suitcase")
	AudioManager.play_sfx("pickup")
	queue_free()
