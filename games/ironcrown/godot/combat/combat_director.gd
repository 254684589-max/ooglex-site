class_name CombatDirector
extends Node
## 攻击令牌（GDD.md 6.2；TECH.md 4.3）：同时最多 MAX_ATTACKERS 个敌人可以上前出招，其余绕圈等待。
## 敌人出完一招、失衡、逃跑、倒下时交回令牌；交回后要等一会儿才能再要（让别人有机会）。

const MAX_ATTACKERS := 2

var holders: Array = []


func _ready() -> void:
	add_to_group("combat_director")


func request(who: Node) -> bool:
	holders = holders.filter(func(h): return is_instance_valid(h))
	if who in holders:
		return true
	if holders.size() < MAX_ATTACKERS:
		holders.append(who)
		return true
	return false


func release(who: Node) -> void:
	holders.erase(who)


func count() -> int:
	holders = holders.filter(func(h): return is_instance_valid(h))
	return holders.size()
