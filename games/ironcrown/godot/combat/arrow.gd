class_name Arrow
extends Node3D
## 箭（路线图 B.4，军阵的弓手；GDD 6.4）：从弓手手里沿直线飞出去（不算下坠：网页上省事，十几米内看不出来），
## 每一帧用射线查飞过的这一段撞到了什么：
##   自己人（和射手同一阵营的兵）→ 穿过去；玩家 → 玩家和射手是敌对的才算，走 Melee.receive_hit()（正面举剑能挡，耗体力）；
##   别的兵 → take_hit(kind = "arrow")（有盾、正对着就挡住）；墙、地面 → 箭没了。飞了 LIFE 秒还没撞到也没了。
## 准头在弓手那边（Soldier._loose：越远越散），这里只管飞。

const SPEED := 28.0               # 米 / 秒
const LIFE := 1.6                 # 秒（约 45 米）
const MASK := 1 | 2               # 世界 + 兵（第 1 层）、玩家（第 2 层）

var shooter: Soldier
var dir := Vector3.FORWARD
var base := 8.0                   # 兵器基础伤害（按射手的力量、技能、对方的护甲算，DamageCalc）
var left := LIFE


static func shoot(parent: Node3D, from: Vector3, to: Vector3, by: Soldier, base_damage: float) -> Arrow:
	var a := Arrow.new()
	a.shooter = by
	a.base = base_damage
	a.dir = (to - from).normalized()
	parent.add_child(a)
	a.global_position = from
	if absf(a.dir.dot(Vector3.UP)) < 0.99:
		a.look_at(from + a.dir, Vector3.UP)
	return a


func _ready() -> void:
	add_to_group("arrow")
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.02, 0.02, 0.7)
	bm.material = Blocks.mat(Color("6a5a48"))
	mi.mesh = bm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _physics_process(delta: float) -> void:
	left -= delta
	if left <= 0.0:
		queue_free()
		return
	var from := global_position
	var to := from + dir * SPEED * delta
	var space := get_world_3d().direct_space_state
	var skip: Array = [shooter.get_rid()] if is_instance_valid(shooter) else []
	for i in 6:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, MASK, skip))
		if hit.is_empty():
			break
		var c: Object = hit.collider
		if c is Soldier and is_instance_valid(shooter) and (c as Soldier).side == shooter.side:
			skip.append((c as CollisionObject3D).get_rid())      # 自己人：穿过去
			continue
		if c is FpController:
			if not _hostile_to_player():
				skip.append((c as CollisionObject3D).get_rid())
				continue
			_hit_player(c as FpController)
		elif c is Enemy:
			var e := c as Enemy
			e.take_hit({"damage": _damage(e.staggered, e.armor), "kind": "arrow", "attacker": shooter, "stop": 0.0})
		queue_free()                                             # 打中人，或者撞上墙、地面
		return
	global_position = to


func _hostile_to_player() -> bool:
	if not is_instance_valid(shooter) or shooter.battle == null:
		return false
	return shooter.battle.player_side != "" and shooter.side != shooter.battle.player_side


func _hit_player(p: FpController) -> void:
	if p.melee == null or p.melee.down:
		return
	p.melee.receive_hit({"damage": _damage(p.melee.staggered(), GameState.armor_total()), "kind": "arrow",
		"attacker": shooter if is_instance_valid(shooter) else null, "stop": 0.0})


func _damage(staggered: bool, armor: float) -> int:
	var st := int(shooter.data.strength) if is_instance_valid(shooter) else 3
	var sk := int(shooter.data.skill) if is_instance_valid(shooter) else 10
	return DamageCalc.compute(base, st, sk, "light", staggered, armor)
