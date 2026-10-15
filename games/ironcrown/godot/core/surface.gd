class_name Surface
extends RefCounted
## 脚下的地面（路线图 4.4；STORY.md 第四节「泥潭（走进去变慢、不能冲刺）」）。
## 地面种类写在碰撞体的元数据 "surface" 上（鹭沼的泥滩：world/marsh.gd），不按坐标查表：栈道铺在泥滩上面，
## 站在栈道上踩的是栈道的碰撞体，自然不算泥。主角每 0.1 秒看一次脚下（FpController），以后敌人、士兵也用它（4.9）。
## 不只靠颜色：在泥里时 HUD 写一行字（label），第一次踩进去弹教学提示 mud。

const KINDS := {
	"mud": {"mult": 0.55, "run": false, "label": "泥潭：走得慢，不能跑"},
}


## 速度乘多少（不认识的 = 1）
static func mult(id: String) -> float:
	return float(KINDS.get(id, {}).get("mult", 1.0))


static func can_run(id: String) -> bool:
	return bool(KINDS.get(id, {}).get("run", true))


## HUD 上那一行（"" = 普通地面，不显示）
static func label(id: String) -> String:
	return str(KINDS.get(id, {}).get("label", ""))


## 角色脚下是什么：从脚底往上 0.3 米处往下打短射线（只看物理层 1「世界」），读打到的碰撞体的元数据；
## 悬空（跳起、掉下去）返回 null，调用的人保留上一次的。不用滑动碰撞：平地上走路时引擎靠吸附贴地，滑动碰撞里常常没有地面那一条。
## 中间一条打到泥时，再在身子边上（radius 米）打四条：只要有一条踩着别的（栈道边上半个身子在木板上），就不算泥（审查）
static func under(body: Node3D, radius := 0.3) -> Variant:
	var mid: Variant = _ray(body, Vector3.ZERO)
	if mid == null or str(mid) == "":
		return mid
	for off in [Vector3(radius, 0, 0), Vector3(-radius, 0, 0), Vector3(0, 0, radius), Vector3(0, 0, -radius)]:
		var s: Variant = _ray(body, off)
		if s != null and str(s) != str(mid):
			return s
	return mid


static func _ray(body: Node3D, off: Vector3) -> Variant:
	var space := body.get_world_3d().direct_space_state
	var from := body.global_position + off + Vector3(0, 0.3, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -0.7, 0), 1)
	if body is CollisionObject3D:
		q.exclude = [(body as CollisionObject3D).get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return null
	var o: Object = hit.collider
	return str(o.get_meta("surface", "")) if o != null else ""
