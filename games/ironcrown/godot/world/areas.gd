class_name Areas
extends RefCounted
## 区域登记（路线图 3.1）：名字、室内还是室外、命名出生点、固定机位。
## main 按区域名搭场景（main.area / scene_name()）；区域之间用 Door.to_area 连起来。
## 换区域 = 记下去哪、站在哪个出生点 → 重新载入主场景（和读档同一条路，GameState 是自动加载的，不受影响）。
## 存档里的 "scene" 字段就是区域名（core/saves.gd 用 NAMES 校验）。

const NAMES := {"frostford": "霜渡镇", "tavern": "「倒钩鱼」酒馆", "test_range": "灰盒测试场", "arena": "训练场"}
const INDOOR := ["tavern"]


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
	return {}


## 出生点的位置与朝向；没有这个名字返回 null（main 就用区域默认的出生点）
static func spawn(area: String, id: String) -> Variant:
	var table := spawns(area)
	if not table.has(id):
		return null
	var s: Array = table[id]
	return Transform3D(Basis(Vector3.UP, deg_to_rad(float(s[1]))), s[0])


## 网页 ?view=N 的固定机位（截图、冒烟测试用）：[位置, 水平朝向（度）, 俯仰（度）]
static func views(area: String) -> Array:
	match area:
		"frostford":
			return Frostford.VIEWS
		"tavern":
			return Tavern.VIEWS
	return []
