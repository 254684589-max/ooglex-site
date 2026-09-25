class_name ServicePoint
extends Interactable
## 数据驱动的交互点：商店柜台、工位、面试间、银行柜台、床、衣柜、电脑、公交站……
## kind 决定做什么（由 ServiceRouter 执行），label 是屏幕中央的提示文字。

var kind := ""
var loc_id := ""
var args: Dictionary = {}
var key := "interact"
var label_text := ""


func setup(p_kind: String, p_label: String, p_loc: String, p_args := {}, p_key := "interact") -> void:
	kind = p_kind
	label_text = p_label
	loc_id = p_loc
	args = p_args
	key = p_key
	display_name = p_label
	name = "SP_%s_%s" % [p_loc, p_kind]
	set_sphere_shape(1.6, Vector3(0, 1.0, 0))
	max_distance = float(args.get("reach", 2.6))
	# 与 NPC 同级：站在柜台 / 器械前时按 E 是用它，面向旁边的 NPC 时才是聊天
	focus_priority = 1


func get_actions(_player: Node) -> Array:
	return ServiceRouter.actions_for(self)


func perform(action_key: String, _player: Node) -> void:
	ServiceRouter.run(self, action_key)


func location() -> LocationNode:
	return GameManager.lookup("loc:" + loc_id) as LocationNode
