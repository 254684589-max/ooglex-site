class_name Areas
extends RefCounted
## 区域登记（路线图 3.1）：名字、室内还是室外、命名出生点、固定机位。
## main 按区域名搭场景（main.area / scene_name()）；区域之间用 Door.to_area 连起来。
## 换区域 = 记下去哪、站在哪个出生点 → 重新载入主场景（和读档同一条路，GameState 是自动加载的，不受影响）。
## 存档里的 "scene" 字段就是区域名（core/saves.gd 用 NAMES 校验）。

const NAMES := {"frostford": "霜渡镇", "tavern": "「倒钩鱼」酒馆", "churchyard": "星铁小教堂墓园", "chapel": "星铁小教堂",
	"birch": "镇外桦林", "ferry": "渡口", "test_range": "灰盒测试场", "arena": "训练场"}
const INDOOR := ["tavern", "chapel"]
## 要烘焙导航网格的区域（3.4）：敌人会出现的地方。范围 = 能走的那片地（地面碰撞盒比它大）；墓园、小教堂、测试场没有敌人，不烘焙（敌人在那里直线走）
const NAV_BOUNDS := {
	"frostford": AABB(Vector3(-15.5, -0.5, -59.0), Vector3(31.0, 4.0, 70.5)),
	"tavern": AABB(Vector3(-4.0, -0.5, -3.5), Vector3(8.0, 3.0, 7.0)),
	"arena": AABB(Vector3(-16.0, -0.5, -17.0), Vector3(32.0, 4.0, 32.0)),
	"birch": AABB(Vector3(-18.0, -0.5, -36.0), Vector3(36.0, 4.0, 72.0)),
	"ferry": AABB(Vector3(-16.0, -0.5, -30.0), Vector3(32.0, 4.0, 44.5)),
}


static func known(area: String) -> bool:
	return NAMES.has(area)


static func display_name(area: String) -> String:
	return str(NAMES.get(area, area))


static func is_indoor(area: String) -> bool:
	return area in INDOOR


## 区域里的命名出生点（各区域脚本的 SPAWNS：名字 → [位置, 水平朝向（度，0 = 面朝 -Z，正 = 向左转）]）
static func spawns(area: String) -> Dictionary:
	match area:
		"frostford":
			return Frostford.SPAWNS
		"tavern":
			return Tavern.SPAWNS
		"churchyard":
			return Churchyard.SPAWNS
		"chapel":
			return Chapel.SPAWNS
		"birch":
			return Birch.SPAWNS
		"ferry":
			return Ferry.SPAWNS
	return {}


## 出生点的位置与朝向；没有这个名字返回 null（main 就用区域默认的出生点）
static func spawn(area: String, id: String) -> Variant:
	var table := spawns(area)
	if not table.has(id):
		return null
	var s: Array = table[id]
	return Transform3D(Basis(Vector3.UP, deg_to_rad(float(s[1]))), s[0])


## 导航网格的烘焙范围；不烘焙的区域返回空的 AABB
static func nav_bounds(area: String) -> AABB:
	return NAV_BOUNDS.get(area, AABB())


## 网页 ?view=N 的固定机位（截图、冒烟测试用）：[位置, 水平朝向（度）, 俯仰（度）]
static func views(area: String) -> Array:
	match area:
		"frostford":
			return Frostford.VIEWS
		"tavern":
			return Tavern.VIEWS
		"churchyard":
			return Churchyard.VIEWS
		"chapel":
			return Chapel.VIEWS
		"birch":
			return Birch.VIEWS
		"ferry":
			return Ferry.VIEWS
	return []
