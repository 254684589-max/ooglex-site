class_name NavBuilder
extends RefCounted
## 导航网格（路线图 3.4；TECH.md 4.4）：区域搭好以后运行时烘焙（网页导出没有线程，同步烘焙）。
## 思路复制自 games/emberfall3d/godot/world/nav_builder.gd（参数对齐体素、同步烘焙）；这里改成烘焙区域里的静态碰撞体：
## 源几何 = root 下所有物理层 1「世界」的静态碰撞体（房子、墙、桌子、井、站着的 NPC、关着的门……），地面是有厚度的盒子（《余烬陷落》P2 的坑）。
## 范围用 Areas.nav_bounds() 限住：地面碰撞盒比能走的范围大得多，不限的话会烘焙一大片走不到的雪地。
## 门开着、NPC 走开都不会重新烘焙（门按关着算，敌人不穿门）。

const PARSE_MASK := 1             # 物理层 1「世界」
const CELL := 0.25
const CELL_H := 0.05              # 高度方向细一点：网格面贴着地面（0.25 时比地面高 0.5 米，导航代理按三维距离判断到没到路径点）
const AGENT_RADIUS := 0.5         # 敌人碰撞半径 0.32，按格子向上取整（半径必须是 cell_size 的整数倍，不然引擎取整并报警告）
const AGENT_HEIGHT := 1.75        # 高度、攀爬是 cell_height 的整数倍
const AGENT_CLIMB := 0.25


static func make_navmesh(bounds: AABB) -> NavigationMesh:
	var nm := NavigationMesh.new()
	nm.cell_size = CELL
	nm.cell_height = CELL_H
	nm.agent_radius = AGENT_RADIUS
	nm.agent_height = AGENT_HEIGHT
	nm.agent_max_climb = AGENT_CLIMB
	nm.agent_max_slope = 46.0
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = PARSE_MASK
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	nm.filter_baking_aabb = bounds
	return nm


## 烘焙 root 下的静态碰撞体，挂一个 NavigationRegion3D 到 root 下；返回 {region, ms, polygons}
static func bake(root: Node3D, bounds: AABB) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var nm := make_navmesh(bounds)
	var geo := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nm, geo, root)
	NavigationServer3D.bake_from_source_geometry_data(nm, geo)
	var region := NavigationRegion3D.new()
	region.name = "Navigation"
	region.navigation_mesh = nm
	root.add_child(region)
	var map := root.get_world_3d().navigation_map           # 地图的格子大小和网格对齐，不然合并多边形边时会报警告
	NavigationServer3D.map_set_cell_size(map, CELL)
	NavigationServer3D.map_set_cell_height(map, CELL_H)
	return {"region": region, "ms": (Time.get_ticks_usec() - t0) / 1000.0, "polygons": nm.get_polygon_count()}


## 路径长度（水平距离之和）
static func path_length(path: PackedVector3Array) -> float:
	var total := 0.0
	for i in range(1, path.size()):
		total += Vector2(path[i].x - path[i - 1].x, path[i].z - path[i - 1].z).length()
	return total
