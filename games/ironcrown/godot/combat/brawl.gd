class_name Brawl
extends Node
## 徒手打一架（路线图 3.3；GDD 6.2「醉汉：徒手，动作慢，打倒后认输（不死）」；STORY.md 第三节「跟醉汉打一架（教学：徒手战斗）」）。
## 对话效果 {"brawl": 敌人种类, "win": 旗标, "lose": 旗标} 开打（DialogueRunner 记在 GameState.pending_brawl，对话关上后 main.start_brawl）：
## 说话的 NPC 先藏起来，原地换成一个同名的敌人（enemies.json 里 nonlethal 的种类），玩家只许用拳头（Melee.fists_only）。
## 对方认输 = 赢（跪一会儿再变回 NPC，站在原地）；自己被打倒（Melee.knocked_out）= 输（对方回到原处接着喝）。两种结局都不死人，
## 设对应旗标，对话按旗标接着走。打的时候算「战斗中」（main.in_combat）：不能存档、不能走出去、不能和别人搭话。

signal ended(won: bool)

const END_DELAY := 1.2            # 对方认输后跪这么久再变回 NPC

var npc: Npc
var enemy: Enemy
var player: FpController
var kind := ""
var win_flag := ""
var lose_flag := ""
var done := false
var won := false
var npc_home := Transform3D.IDENTITY
var npc_layer := 0


## 开打：NPC 换成敌人，玩家收剑、只许用拳头
func begin(world: Node3D, p: FpController, n: Npc, enemy_kind: String, win: String, lose: String) -> void:
	player = p
	npc = n
	kind = enemy_kind
	win_flag = win
	lose_flag = lose
	npc_home = n.global_transform
	npc_layer = n.collision_layer
	if world.get_tree().get_first_node_in_group("combat_director") == null:
		var director := CombatDirector.new()
		director.name = "CombatDirector"
		world.add_child(director)
	enemy = Enemy.make(enemy_kind, "brawl:" + n.dialogue_id)
	enemy.display_override = n.display_name
	world.add_child(enemy)
	var to := p.global_position - n.global_position
	enemy.global_position = n.global_position
	enemy.rotation.y = atan2(-to.x, -to.z)
	_hide_npc(true)
	enemy.state_changed.connect(_on_enemy_state)
	player.melee.set_fists_only(true)
	player.melee.knocked_out.connect(_on_knocked_out)
	enemy.engage()


func active() -> bool:
	return not done


func _hide_npc(on: bool) -> void:
	npc.visible = not on
	npc.collision_layer = 0 if on else npc_layer


func _on_enemy_state(_e: Enemy, state: String) -> void:
	if state == "yield" and not done:
		_finish(true)


func _on_knocked_out(_info: Dictionary) -> void:
	if not done:
		_finish(false)


## 一开打就知道你在哪：躲到暗处也不会让它忘了这一架（不然它会回去巡逻，架就打不完了）
func _physics_process(_delta: float) -> void:
	if done or enemy == null or not is_instance_valid(enemy):
		return
	if enemy.state in [Enemy.State.PATROL, Enemy.State.SUSPICIOUS, Enemy.State.ALERT]:
		enemy.engage()


func _finish(w: bool) -> void:
	done = true
	won = w
	player.melee.set_fists_only(false)
	if player.melee.knocked_out.is_connected(_on_knocked_out):
		player.melee.knocked_out.disconnect(_on_knocked_out)
	enemy.remove_from_group("enemy")          # 马上不算「战斗中」
	enemy.remove_from_group("damageable")
	enemy.collision_layer = 0
	var flag := win_flag if w else lose_flag
	if flag != "":
		GameState.set_flag(flag)
	print("IC_BRAWL end won=%s kind=%s" % [w, kind])
	ended.emit(w)
	if w:
		# 认输：跪一会儿，再变回站在原地的 NPC（面朝你）
		await get_tree().create_timer(END_DELAY, false).timeout
	_restore(w)


## 敌人撤掉，NPC 回来：赢了站在它认输的地方，输了回到原处
func _restore(w: bool) -> void:
	if is_instance_valid(enemy):
		var at := enemy.global_position
		enemy.queue_free()
		if w:
			npc.global_position = Vector3(at.x, npc_home.origin.y, at.z)
			var to := player.global_position - npc.global_position
			npc.rotation.y = atan2(-to.x, -to.z)
		else:
			npc.global_transform = npc_home
	enemy = null
	_hide_npc(false)
	queue_free()
