class_name Encounter
extends Node
## 对峙转战斗（路线图 3.6）：区域里先站着一组 NPC（组 "encounter:<编号>"，每个带元数据 enemy_kind / enemy_id），对话说崩了就动手。
## 对话效果 {"fight": 编号, "win": 旗标}：对话关上后 main.start_encounter()——这组 NPC 原地换成同名的敌人（Enemy.display_override），直接进入战斗；
## 每个敌人倒下、求饶或逃跑就算解决，全部解决 = 打赢（设 win 旗标、自动存档）。和打架（Brawl）不同，这是真打：会死人，声望照常变。
## 对话效果 {"leave": 编号}：这组人走了（NPC 直接撤掉；有没有走记在对话另设的旗标里，区域搭场景时据此决定还放不放他们）。
## 打的时候 main.in_combat() 为真（不能存档、不能走出去、不能和别人搭话）。

signal ended(won: bool)

var id := ""
var win_flag := ""
var enemies: Array = []
var done := false


static func group_name(encounter_id: String) -> String:
	return "encounter:" + encounter_id


## 开打：组里的 NPC 换成敌人
func begin(world: Node3D, encounter_id: String, win: String) -> void:
	id = encounter_id
	win_flag = win
	if world.get_tree().get_first_node_in_group("combat_director") == null:
		var director := CombatDirector.new()
		director.name = "CombatDirector"
		world.add_child(director)
	for n in world.get_tree().get_nodes_in_group(group_name(id)):
		var npc := n as Node3D
		var e := Enemy.make(str(npc.get_meta("enemy_kind")), str(npc.get_meta("enemy_id")))
		e.display_override = str(npc.get("display_name"))
		e.transform = npc.global_transform              # 区域的节点都挂在 world 下，world 本身不动
		world.add_child(e)
		npc.remove_from_group(group_name(id))
		npc.queue_free()
		e.state_changed.connect(_on_enemy_state)
		enemies.append(e)
	for e in enemies:
		e.engage()


func active() -> bool:
	return not done


## 这组人走了：NPC 撤掉
static func leave(world: Node3D, encounter_id: String) -> int:
	var n := 0
	for npc in world.get_tree().get_nodes_in_group(group_name(encounter_id)):
		npc.remove_from_group(group_name(encounter_id))
		npc.queue_free()
		n += 1
	return n


func _on_enemy_state(_e: Enemy, _state: String) -> void:
	if done:
		return
	for e in enemies:
		if is_instance_valid(e) and e.state not in [Enemy.State.DEAD, Enemy.State.YIELD, Enemy.State.FLEE]:
			return
	done = true
	if win_flag != "":
		GameState.set_flag(win_flag)
	print("IC_ENCOUNTER end id=%s" % id)
	ended.emit(true)
