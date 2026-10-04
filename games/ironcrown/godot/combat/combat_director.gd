class_name CombatDirector
extends Node
## 攻击令牌（GDD.md 6.2；TECH.md 4.3）：同时最多 MAX_ATTACKERS 个敌人可以上前出招，其余绕圈等待。
## 敌人出完一招、失衡、逃跑、倒下时交回令牌；交回后要等一会儿才能再要（让别人有机会）。
## B.1（军阵战斗，GDD 6.4）：令牌按目标分配——每个目标（玩家或某个兵）同时最多 MAX_ATTACKERS 个攻击者。
## 不写目标、或目标是玩家时走原来那一份（holders），序章的敌人不用改。

const MAX_ATTACKERS := 2

var holders: Array = []          # 正在打玩家的
var by_target := {}              # 目标（兵）的 instance id → 正在打它的攻击者
var aimed := {}                  # 攻击者的 instance id → 它拿着谁的令牌（交回时找得到）


func _ready() -> void:
	add_to_group("combat_director")


func request(who: Node, target: Node = null) -> bool:
	if target == null or target.is_in_group("player"):
		holders = holders.filter(func(h): return is_instance_valid(h))
		if who in holders:
			return true
		if holders.size() < MAX_ATTACKERS:
			holders.append(who)
			return true
		return false
	var k := target.get_instance_id()
	var list: Array = by_target.get(k, []).filter(func(h): return is_instance_valid(h))
	by_target[k] = list
	if who in list:
		return true
	if list.size() >= MAX_ATTACKERS:
		return false
	release(who)                  # 换了目标：先把原来那一份交回
	list.append(who)
	aimed[who.get_instance_id()] = k
	return true


func release(who: Node) -> void:
	holders.erase(who)
	var id := who.get_instance_id()
	if aimed.has(id):
		var list: Array = by_target.get(aimed[id], [])
		list.erase(who)
		if list.is_empty():
			by_target.erase(aimed[id])
		aimed.erase(id)


## 正在打玩家的有几个
func count() -> int:
	holders = holders.filter(func(h): return is_instance_valid(h))
	return holders.size()


## 正在打某个目标的有几个（目标是玩家时同 count()）
func count_for(target: Node) -> int:
	if target == null or target.is_in_group("player"):
		return count()
	return by_target.get(target.get_instance_id(), []).filter(func(h): return is_instance_valid(h)).size()
